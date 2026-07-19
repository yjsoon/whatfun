import SwiftData
import SwiftUI

enum ListDetailSource {
    case builtIn(BuiltInListKind)
    case user(UserList)
}

struct ListDetailView: View {
    let source: ListDetailSource

    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.sortTitle)]
    ) private var items: [LibraryItem]
    @Query(sort: \UserList.sortOrder) private var allLists: [UserList]

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @State private var presentsEditor = false
    @State private var managesMemberships = false
    @State private var errorMessage: String?

    private var userList: UserList? {
        guard case let .user(list) = source else { return nil }
        return list
    }

    private var isManualList: Bool {
        userList?.kind == .manual
    }

    private var lists: [UserList] {
        allLists.filter { $0.trashedAt == nil }
    }

    private var displayedItems: [LibraryItem] {
        let available = items.filter { $0.archivedAt == nil }
        switch source {
        case let .builtIn(kind):
            return available.filter(kind.includes)
        case let .user(list) where list.kind == .manual:
            let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
            var seen = Set<UUID>()
            return (list.memberships ?? [])
                .sorted { lhs, rhs in
                    if lhs.positionRank == rhs.positionRank {
                        return lhs.addedAt < rhs.addedAt
                    }
                    return lhs.positionRank < rhs.positionRank
                }
                .compactMap { membership in
                    guard seen.insert(membership.itemID).inserted else { return nil }
                    return byID[membership.itemID]
                }
        case let .user(list):
            return SmartListEvaluator.items(
                matching: list,
                from: available,
                allLists: lists
            )
        }
    }

    var body: some View {
        mainList
            .sheet(isPresented: $presentsEditor) {
                if let userList {
                    ListEditorView(list: userList)
                }
            }
            .sheet(isPresented: $managesMemberships) {
                if let userList {
                    ManualMembershipEditor(list: userList)
                }
            }
            .alert("Couldn’t Update List", isPresented: errorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
    }

    private var mainList: some View {
        List {
            listSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(title)
        .archiveBackground()
        .toolbar {
            if let userList, userList.kind == .manual {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Item", systemImage: "plus") {
                        navigation.presentedSheet = .quickAdd(destinationListID: userList.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listSections: some View {
        if let list = userList {
            Section("List Actions") {
                if list.kind == .manual {
                    Button("Manage Items", systemImage: "checklist") {
                        managesMemberships = true
                    }

                    HStack {
                        Label("Reorder Items", systemImage: "arrow.up.arrow.down")
                        Spacer()
                        EditButton()
                    }
                }

                Button("Edit List", systemImage: "pencil") {
                    presentsEditor = true
                }
            }
            .listRowBackground(WhatFunTheme.raisedBackground)
        }

        if let descriptionText {
            Section {
                Text(descriptionText)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
            .listRowBackground(WhatFunTheme.raisedBackground)
        }

        Section {
            itemSectionContent
        } header: {
            Text("\(displayedItems.count) Items")
        }
    }

    @ViewBuilder
    private var itemSectionContent: some View {
        if displayedItems.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyMessage)
            } actions: {
                if isManualList {
                    Button("Add Item", systemImage: "plus") {
                        if let userList {
                            navigation.presentedSheet = .quickAdd(destinationListID: userList.id)
                        }
                    }

                    Button("Choose from Library", systemImage: "checklist") {
                        managesMemberships = true
                    }
                }
            }
            .listRowBackground(Color.clear)
        } else if isManualList {
            ForEach(displayedItems) { item in
                itemRow(item)
            }
            .onMove(perform: moveItems)
        } else {
            ForEach(displayedItems) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: LibraryItem) -> some View {
        Button {
            navigation.showItem(item.id, from: .lists)
        } label: {
            HStack(spacing: 12) {
                CoverArtworkView(item: item)
                    .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                    .frame(width: 46, height: 62)
                    .clipShape(CoverShape(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(WhatFunTheme.ink)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Label(item.mediaKind.displayName, systemImage: item.mediaKind.symbolName)
                        Text("·")
                        Text(item.status.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .lineLimit(1)
                }

                Spacer()

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(WhatFunTheme.coral)
                        .accessibilityLabel("Favorite")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(WhatFunTheme.raisedBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isManualList {
                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                    remove(item)
                }
            }
        }
        .accessibilityHint("Opens item details and history")
    }

    private var title: String {
        switch source {
        case let .builtIn(kind): String(localized: kind.title)
        case let .user(list): list.name
        }
    }

    private var descriptionText: String? {
        switch source {
        case let .builtIn(kind):
            switch kind {
            case .favorites: "Items you have marked as favorites."
            default: "A live view of items whose status is \(String(localized: kind.title).lowercased())."
            }
        case let .user(list):
            list.notes
        }
    }

    private var emptyTitle: String {
        isManualList ? "This list is empty" : "Nothing matches yet"
    }

    private var emptyMessage: String {
        if isManualList {
            "Choose existing library items. Their metadata and history stay canonical."
        } else {
            "This view updates automatically as your archive changes."
        }
    }

    private var emptySymbol: String {
        isManualList ? "rectangle.stack.badge.plus" : "line.3.horizontal.decrease.circle"
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        guard let list = userList else { return }
        var reordered = displayedItems
        reordered.move(fromOffsets: source, toOffset: destination)
        let memberships = list.memberships ?? []
        for (index, item) in reordered.enumerated() {
            memberships.first(where: { $0.itemID == item.id })?.positionRank =
                String(format: "%08d", index)
        }
        list.updatedAt = .now
        save()
    }

    private func remove(_ item: LibraryItem) {
        guard let list = userList,
              let membership = (list.memberships ?? []).first(where: { $0.itemID == item.id }) else {
            return
        }
        list.memberships = (list.memberships ?? []).filter { $0.id != membership.id }
        item.listMemberships = (item.listMemberships ?? []).filter { $0.id != membership.id }
        modelContext.delete(membership)
        list.updatedAt = .now
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ManualMembershipEditor: View {
    let list: UserList

    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.sortTitle)]
    ) private var items: [LibraryItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var visibleItems: [LibraryItem] {
        let available = items.filter { $0.archivedAt == nil }
        guard !searchText.isEmpty else { return available }
        return available.filter {
            $0.title.localizedStandardContains(searchText) ||
                ($0.creatorLine?.localizedStandardContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleItems) { item in
                Toggle(isOn: membershipBinding(for: item)) {
                    HStack(spacing: 12) {
                        Image(systemName: item.mediaKind.symbolName)
                            .foregroundStyle(item.mediaKind.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                            if let creator = item.creatorLine {
                                Text(creator)
                                    .font(.caption)
                                    .foregroundStyle(WhatFunTheme.secondaryInk)
                            }
                        }
                    }
                }
                .listRowBackground(WhatFunTheme.raisedBackground)
                .accessibilityHint("Adds or removes this item without duplicating its history")
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search your library")
            .navigationTitle("Manage Items")
            .navigationBarTitleDisplayMode(.inline)
            .archiveBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .alert("Couldn’t Update List", isPresented: errorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func membershipBinding(for item: LibraryItem) -> Binding<Bool> {
        Binding(
            get: { membership(for: item) != nil },
            set: { isIncluded in
                if isIncluded {
                    add(item)
                } else {
                    remove(item)
                }
            }
        )
    }

    private func membership(for item: LibraryItem) -> ListMembership? {
        (list.memberships ?? []).first { $0.itemID == item.id }
    }

    private func add(_ item: LibraryItem) {
        guard membership(for: item) == nil else { return }
        let nextPosition = (list.memberships ?? []).count
        let membership = ListMembership(
            list: list,
            item: item,
            positionRank: String(format: "%08d", nextPosition)
        )
        modelContext.insert(membership)
        list.memberships = (list.memberships ?? []) + [membership]
        if !(item.listMemberships ?? []).contains(where: { $0.id == membership.id }) {
            item.listMemberships = (item.listMemberships ?? []) + [membership]
        }
        list.updatedAt = .now
        save()
    }

    private func remove(_ item: LibraryItem) {
        guard let membership = membership(for: item) else { return }
        list.memberships = (list.memberships ?? []).filter { $0.id != membership.id }
        item.listMemberships = (item.listMemberships ?? []).filter { $0.id != membership.id }
        modelContext.delete(membership)
        list.updatedAt = .now
        save()
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
