import SwiftData
import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @AppStorage("backup.last-success") private var lastBackupTimestamp = 0.0
    @AppStorage("backup.last-error") private var lastBackupError = ""

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack(path: $navigation.homePath) {
                    HomeView()
                        .navigationDestination(for: AppRoute.self, destination: RouteDestination.init)
                }
            }

            Tab("Library", systemImage: "books.vertical", value: .library) {
                NavigationStack(path: $navigation.libraryPath) {
                    LibraryView()
                        .navigationDestination(for: AppRoute.self, destination: RouteDestination.init)
                }
            }

            Tab("Lists", systemImage: "rectangle.stack", value: .lists) {
                NavigationStack(path: $navigation.listsPath) {
                    ListsView()
                        .navigationDestination(for: AppRoute.self, destination: RouteDestination.init)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack(path: $navigation.searchPath) {
                    SearchView(
                        onOpenItem: { navigation.showItem($0, from: .search) },
                        onRequestManualAdd: { kind, query in
                            navigation.presentedSheet = .addItemFor(kind, query)
                        }
                    )
                    .navigationDestination(for: AppRoute.self, destination: RouteDestination.init)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .archiveBackground()
        .environment(navigation)
        .sheet(item: $navigation.presentedSheet) { sheet in
            switch sheet {
            case .addItem:
                ItemEditorView()
            case let .addItemFor(kind, query):
                ItemEditorView(initialKind: kind, initialTitle: query)
            case let .logSession(id):
                SessionEditorView(itemID: id)
            case let .editItem(id):
                ItemEditorView(itemID: id)
            case .createList:
                ListEditorView()
            }
        }
        .task {
            _ = try? await TrashPurgeService(
                context: modelContext,
                credentials: services.credentials,
                reminders: services.reminders
            ).purgeExpired()
            await writeDailyBackupIfNeeded()
        }
    }

    private func writeDailyBackupIfNeeded() async {
        guard services.allowsAutomaticBackups else { return }
        if lastBackupTimestamp > 0,
           Calendar.autoupdatingCurrent.isDateInToday(
               Date(timeIntervalSince1970: lastBackupTimestamp)
           ) {
            return
        }

        do {
            let bridge = SwiftDataArchiveBridge(
                context: modelContext,
                credentials: services.credentials
            )
            let snapshot = try await bridge.snapshot(includePrivateFeedSecrets: false)
            let envelope = FullFidelityArchiveEnvelope(
                exportedAt: .now,
                generator: "WhatFun 0.1 automatic recovery",
                payload: snapshot.payload
            )
            let data = try FullFidelityArchiveCodec.encode(envelope)
            _ = try await DailyBackupStore.applicationSupport().writeValidatedBackup(data)
            lastBackupTimestamp = Date.now.timeIntervalSince1970
            lastBackupError = ""
        } catch {
            lastBackupError = error.localizedDescription
        }
    }
}

private struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case let .item(id):
            ItemDetailView(itemID: id)
        case let .list(id):
            ListRouteDestination(listID: id)
        case .settings:
            SettingsView()
        case .archived:
            ArchivedItemsView()
        case .recentlyDeleted:
            RecentlyDeletedView()
        case .importExport:
            ImportExportView()
        }
    }

    private var destinationPlaceholder: some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text("This destination is being connected to the local archive.")
        )
        .navigationTitle(title)
        .archiveBackground()
    }

    private var title: LocalizedStringKey {
        switch route {
        case .item: "Item"
        case .list: "List"
        case .settings: "Settings"
        case .importExport: "Import & Export"
        case .archived: "Archived Items"
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    private var symbol: String {
        switch route {
        case .item: "rectangle.portrait"
        case .list: "rectangle.stack"
        case .settings: "gearshape"
        case .importExport: "arrow.up.arrow.down"
        case .archived: "archivebox"
        case .recentlyDeleted: "trash"
        }
    }
}

private struct ListRouteDestination: View {
    @Query private var lists: [UserList]

    init(listID: UUID) {
        let listID = listID
        _lists = Query(filter: #Predicate<UserList> { list in
            list.id == listID
        })
    }

    var body: some View {
        if let list = lists.first, list.trashedAt == nil {
            ListDetailView(source: .user(list))
        } else {
            ContentUnavailableView(
                "List Not Found",
                systemImage: "rectangle.stack.badge.questionmark",
                description: Text("This list may have been moved to Recently Deleted.")
            )
            .navigationTitle("List")
            .archiveBackground()
        }
    }
}

#Preview("Empty Archive") {
    let container = try! AppModelContainer.make(isStoredInMemoryOnly: true)

    RootView()
        .modelContainer(container)
        .environment(AppServices.preview)
}
