import SwiftData
import SwiftUI

struct ArchivedItemsView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.title)]
    ) private var items: [LibraryItem]
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    private var archivedItems: [LibraryItem] {
        items.filter { $0.archivedAt != nil }
    }

    var body: some View {
        List {
            if archivedItems.isEmpty {
                ContentUnavailableView(
                    "No Archived Items",
                    systemImage: "archivebox",
                    description: Text("Archiving hides an item while preserving all of its history.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(archivedItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.mediaKind.symbolName)
                            .foregroundStyle(item.mediaKind.accentColor)
                        VStack(alignment: .leading) {
                            Text(item.title).font(.headline)
                            Text(item.mediaKind.displayName)
                                .font(.caption)
                                .foregroundStyle(WhatFunTheme.secondaryInk)
                        }
                        Spacer()
                        Button("Restore") { restore(item) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    .listRowBackground(WhatFunTheme.raisedBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Archived Items")
        .archiveBackground()
        .alert("Couldn’t Restore", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func restore(_ item: LibraryItem) {
        do {
            try ActivityService(context: modelContext).restoreFromArchive(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RecentlyDeletedView: View {
    @Query(sort: \LibraryItem.trashedAt, order: .reverse) private var items: [LibraryItem]
    @Query(sort: \UserList.trashedAt, order: .reverse) private var lists: [UserList]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @State private var pendingPermanentDeletion: DeletedRecord?
    @State private var errorMessage: String?

    private var deletedItems: [LibraryItem] { items.filter { $0.trashedAt != nil } }
    private var deletedLists: [UserList] { lists.filter { $0.trashedAt != nil } }

    var body: some View {
        List {
            if deletedItems.isEmpty, deletedLists.isEmpty {
                ContentUnavailableView(
                    "Recently Deleted is Empty",
                    systemImage: "trash",
                    description: Text("Removed items remain recoverable here for 30 days.")
                )
                .listRowBackground(Color.clear)
            }

            if !deletedItems.isEmpty {
                Section("Items") {
                    ForEach(deletedItems) { item in
                        deletedRow(
                            title: item.title,
                            subtitle: remainingText(item.purgeAfter),
                            symbol: item.mediaKind.symbolName,
                            restore: { restore(item) },
                            delete: { pendingPermanentDeletion = .item(item) }
                        )
                    }
                }
            }

            if !deletedLists.isEmpty {
                Section("Lists") {
                    ForEach(deletedLists) { list in
                        deletedRow(
                            title: list.name,
                            subtitle: remainingText(list.purgeAfter),
                            symbol: "rectangle.stack",
                            restore: { restore(list) },
                            delete: { pendingPermanentDeletion = .list(list) }
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Recently Deleted")
        .archiveBackground()
        .task { await purgeExpired() }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: confirmsPermanentDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task { await deletePermanently() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone and removes the associated history.")
        }
        .alert("Couldn’t Update Recently Deleted", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func deletedRow(
        title: String,
        subtitle: String,
        symbol: String,
        restore: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(WhatFunTheme.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
            Spacer()
            Menu {
                Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                Button("Delete Permanently", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Actions for \(title)")
            }
        }
        .listRowBackground(WhatFunTheme.raisedBackground)
    }

    private var confirmsPermanentDeletion: Binding<Bool> {
        Binding(
            get: { pendingPermanentDeletion != nil },
            set: { if !$0 { pendingPermanentDeletion = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func remainingText(_ purgeAfter: Date?) -> String {
        guard let purgeAfter else { return "Scheduled for automatic removal" }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: purgeAfter).day ?? 0)
        return days == 1 ? "1 day remaining" : "\(days) days remaining"
    }

    private func restore(_ item: LibraryItem) {
        do {
            try ActivityService(context: modelContext).recoverFromTrash(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ list: UserList) {
        list.trashedAt = nil
        list.purgeAfter = nil
        list.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purgeExpired() async {
        do {
            _ = try await service.purgeExpired()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePermanently() async {
        guard let record = pendingPermanentDeletion else { return }
        pendingPermanentDeletion = nil
        do {
            switch record {
            case let .item(item): try await service.permanentlyDelete(item)
            case let .list(list): service.permanentlyDelete(list)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var service: TrashPurgeService {
        TrashPurgeService(
            context: modelContext,
            credentials: services.credentials,
            reminders: services.reminders
        )
    }
}

private enum DeletedRecord {
    case item(LibraryItem)
    case list(UserList)
}

