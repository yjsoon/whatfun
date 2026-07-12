import SwiftData
import SwiftUI

enum BuiltInListKind: String, CaseIterable, Identifiable, Sendable {
    case planned
    case inProgress
    case paused
    case completed
    case dropped
    case favorites

    nonisolated var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .planned: "Planned"
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .dropped: "Dropped"
        case .favorites: "Favorites"
        }
    }

    var symbolName: String {
        switch self {
        case .favorites: "heart.fill"
        case .planned: ConsumptionStatus.planned.symbolName
        case .inProgress: ConsumptionStatus.inProgress.symbolName
        case .paused: ConsumptionStatus.paused.symbolName
        case .completed: ConsumptionStatus.completed.symbolName
        case .dropped: ConsumptionStatus.dropped.symbolName
        }
    }

    var color: Color {
        switch self {
        case .favorites: WhatFunTheme.coral
        case .planned: ConsumptionStatus.planned.color
        case .inProgress: ConsumptionStatus.inProgress.color
        case .paused: ConsumptionStatus.paused.color
        case .completed: ConsumptionStatus.completed.color
        case .dropped: ConsumptionStatus.dropped.color
        }
    }

    func includes(_ item: LibraryItem) -> Bool {
        switch self {
        case .favorites: item.isFavorite
        case .planned: item.status == .planned
        case .inProgress: item.status == .inProgress
        case .paused: item.status == .paused
        case .completed: item.status == .completed
        case .dropped: item.status == .dropped
        }
    }
}

struct ListsView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.sortTitle)]
    ) private var items: [LibraryItem]
    @Query(sort: \UserList.sortOrder) private var allLists: [UserList]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @State private var presentsCreator = false
    @State private var editingList: UserList?
    @State private var pendingDeletion: UserList?
    @State private var errorMessage: String?

    private var activeItems: [LibraryItem] {
        items.filter { $0.archivedAt == nil }
    }

    private var lists: [UserList] {
        allLists
            .filter { $0.trashedAt == nil }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.sortOrder < rhs.sortOrder
            }
    }

    private var activeLists: [UserList] {
        lists.filter { $0.archivedAt == nil }
    }

    private var archivedLists: [UserList] {
        lists.filter { $0.archivedAt != nil }
    }

    var body: some View {
        List {
            Section("Quick Views") {
                ForEach(BuiltInListKind.allCases) { kind in
                    NavigationLink {
                        ListDetailView(source: .builtIn(kind))
                    } label: {
                        BuiltInListRow(
                            kind: kind,
                            count: activeItems.lazy.filter(kind.includes).count
                        )
                    }
                    .listRowBackground(WhatFunTheme.raisedBackground)
                }
            }

            Section {
                if activeLists.isEmpty {
                    ContentUnavailableView {
                        Label("No custom lists", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Make a manual list or let rules keep a smart list up to date.")
                    } actions: {
                        Button("Create List", systemImage: "plus") {
                            presentsCreator = true
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(activeLists) { list in
                        listLink(list)
                    }
                }
            } header: {
                Text("Your Lists")
            }

            if !archivedLists.isEmpty {
                Section("Archived Lists") {
                    ForEach(archivedLists) { list in
                        listLink(list)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Lists")
        .archiveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create List", systemImage: "plus") {
                    presentsCreator = true
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    navigation.showSettings()
                }
            }
        }
        .sheet(isPresented: $presentsCreator) {
            ListEditorView()
        }
        .sheet(item: $editingList) { list in
            ListEditorView(list: list)
        }
        .confirmationDialog(
            "Move this list to Recently Deleted?",
            isPresented: confirmsDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { list in
            Button("Move to Recently Deleted", role: .destructive) {
                moveToTrash(list)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its items and entertainment history will stay untouched.")
        }
        .alert("Couldn’t Update List", isPresented: errorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func listLink(_ list: UserList) -> some View {
        NavigationLink {
            ListDetailView(source: .user(list))
        } label: {
            UserListRow(
                list: list,
                count: itemCount(for: list)
            )
        }
        .listRowBackground(WhatFunTheme.raisedBackground)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingDeletion = list
            }
            Button("Edit", systemImage: "pencil") {
                editingList = list
            }
            .tint(WhatFunTheme.sky)
        }
        .swipeActions(edge: .leading) {
            Button(
                list.archivedAt == nil ? "Archive" : "Restore",
                systemImage: list.archivedAt == nil ? "archivebox" : "arrow.uturn.backward"
            ) {
                toggleArchive(list)
            }
            .tint(WhatFunTheme.sage)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingList = list }
            Button(
                list.archivedAt == nil ? "Archive" : "Restore",
                systemImage: list.archivedAt == nil ? "archivebox" : "arrow.uturn.backward"
            ) { toggleArchive(list) }
            Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) {
                pendingDeletion = list
            }
        }
    }

    private func itemCount(for list: UserList) -> Int {
        if list.kind == .manual {
            let activeIDs = Set(activeItems.map(\.id))
            let memberIDs = Set((list.memberships ?? []).map(\.itemID))
            return activeIDs.intersection(memberIDs).count
        }
        return SmartListEvaluator.items(
            matching: list,
            from: activeItems,
            allLists: lists
        ).count
    }

    private var confirmsDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func toggleArchive(_ list: UserList) {
        list.archivedAt = list.archivedAt == nil ? .now : nil
        list.updatedAt = .now
        save()
    }

    private func moveToTrash(_ list: UserList) {
        let date = Date.now
        list.trashedAt = date
        list.purgeAfter = Calendar.current.date(byAdding: .day, value: 30, to: date)
        list.updatedAt = date
        pendingDeletion = nil
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

private struct BuiltInListRow: View {
    let kind: BuiltInListKind
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text(kind.title)
                Spacer()
                Text(count, format: .number)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UserListRow: View {
    let list: UserList
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: list.kind == .smart ? "wand.and.stars" : "rectangle.stack")
                .font(.title3)
                .foregroundStyle(list.kind == .smart ? WhatFunTheme.sky : WhatFunTheme.coral)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.headline)
                    if list.archivedAt != nil {
                        Image(systemName: "archivebox")
                            .font(.caption)
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                }
                Text(list.kind == .smart ? "Smart List" : "Manual List")
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }

            Spacer()

            Text(count, format: .number)
                .foregroundStyle(WhatFunTheme.secondaryInk)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(list.name), \(list.kind == .smart ? "smart" : "manual") list, \(count) items")
    }
}
