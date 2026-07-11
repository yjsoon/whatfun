import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()

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
    }
}

private struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case let .item(id):
            ItemDetailView(itemID: id)
        case .list:
            destinationPlaceholder
        case .settings, .importExport, .recentlyDeleted:
            destinationPlaceholder
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
        case .recentlyDeleted: "Recently Deleted"
        }
    }

    private var symbol: String {
        switch route {
        case .item: "rectangle.portrait"
        case .list: "rectangle.stack"
        case .settings: "gearshape"
        case .importExport: "arrow.up.arrow.down"
        case .recentlyDeleted: "trash"
        }
    }
}

#Preview {
    RootView()
}
