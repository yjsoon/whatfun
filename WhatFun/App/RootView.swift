import SwiftData
import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("backup.last-success") private var lastBackupTimestamp = 0.0
    @AppStorage("backup.last-error") private var lastBackupError = ""
    @AppStorage("library.grid-style") private var gridStyleRaw = LibraryGridStyle.flow.rawValue
    @AppStorage("reminders.default-hour") private var defaultReminderHour = 9

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
        // Runs on the first active appearance and every later return to the
        // foreground, so an app resident for weeks keeps writing daily snapshots
        // rather than only on a cold launch.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await runDailyMaintenance() }
        }
    }

    private func runDailyMaintenance() async {
        // Snapshot first, purge second: the only automatic destructive operation must
        // never run before today's recovery snapshot is on disk.
        await DailyMaintenanceSequencer.run(
            writeRecoverySnapshot: { await writeDailyBackupIfNeeded() },
            purgeExpiredTrash: { await purgeExpiredTrash() }
        )
    }

    private func writeDailyBackupIfNeeded() async {
        guard services.allowsAutomaticBackups else { return }
        // Idempotent guard: maintenance now runs on every foreground, but at most one
        // snapshot is written per calendar day.
        if lastBackupTimestamp > 0,
           Calendar.autoupdatingCurrent.isDateInToday(
               Date(timeIntervalSince1970: lastBackupTimestamp)
           ) {
            return
        }

        do {
            let coordinator = DurabilityCoordinator(
                bridge: SwiftDataArchiveBridge(
                    context: modelContext,
                    credentials: services.credentials
                ),
                dailyStore: try DailyBackupStore.applicationSupport(),
                generator: DurabilityCoordinator.automaticRecoveryGenerator
            )
            _ = try await coordinator.writeDailyBackup(
                preferences: DurabilityCoordinator.backupPreferences(
                    gridStyle: gridStyleRaw,
                    defaultReminderHour: defaultReminderHour
                )
            )
            lastBackupTimestamp = Date.now.timeIntervalSince1970
            lastBackupError = ""
        } catch {
            lastBackupError = error.localizedDescription
        }
    }

    private func purgeExpiredTrash() async {
        _ = try? await TrashPurgeService(
            context: modelContext,
            credentials: services.credentials,
            reminders: services.reminders
        ).purgeExpired()
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
