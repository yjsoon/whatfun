import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack(path: $navigation.homePath) {
                    HomeView()
                    .navigationDestination(for: AppRoute.self, destination: RoutePlaceholder.init)
                }
            }

            Tab("Library", systemImage: "books.vertical", value: .library) {
                NavigationStack(path: $navigation.libraryPath) {
                    LibraryView()
                    .navigationDestination(for: AppRoute.self, destination: RoutePlaceholder.init)
                }
            }

            Tab("Lists", systemImage: "rectangle.stack", value: .lists) {
                NavigationStack(path: $navigation.listsPath) {
                    PlaceholderContent(
                        title: "Lists",
                        message: "Manual and smart lists will organize what comes next.",
                        symbol: "rectangle.stack"
                    )
                    .navigationDestination(for: AppRoute.self, destination: RoutePlaceholder.init)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack(path: $navigation.searchPath) {
                    PlaceholderContent(
                        title: "Search",
                        message: "Find your library or add metadata from supported providers.",
                        symbol: "magnifyingglass"
                    )
                    .navigationDestination(for: AppRoute.self, destination: RoutePlaceholder.init)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .archiveBackground()
        .environment(navigation)
    }
}

private struct PlaceholderContent: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .navigationTitle(title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .archiveBackground()
    }
}

private struct RoutePlaceholder: View {
    let route: AppRoute

    var body: some View {
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
