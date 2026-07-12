import Observation
import SwiftUI

enum AppTab: Hashable, Sendable {
    case home
    case library
    case lists
    case search
}

enum AppRoute: Hashable, Sendable {
    case item(UUID)
    case list(UUID)
    case settings
    case importExport
    case archived
    case recentlyDeleted
}

enum AppSheet: Identifiable, Hashable, Sendable {
    case addItem
    case addItemFor(MediaKind, String)
    case logSession(UUID)
    case editItem(UUID)
    case createList

    var id: String {
        switch self {
        case .addItem:
            "add-item"
        case let .addItemFor(kind, query):
            "add-item-\(kind.rawValue)-\(query)"
        case let .logSession(id):
            "log-session-\(id.uuidString)"
        case let .editItem(id):
            "edit-item-\(id.uuidString)"
        case .createList:
            "create-list"
        }
    }
}

@Observable
final class AppNavigation {
    var selectedTab = AppTab.home
    var homePath: [AppRoute] = []
    var libraryPath: [AppRoute] = []
    var listsPath: [AppRoute] = []
    var searchPath: [AppRoute] = []
    var presentedSheet: AppSheet?

    func showItem(_ id: UUID, from tab: AppTab? = nil) {
        let sourceTab = tab ?? selectedTab
        switch sourceTab {
        case .home:
            homePath.append(.item(id))
        case .library:
            libraryPath.append(.item(id))
        case .lists:
            listsPath.append(.item(id))
        case .search:
            searchPath.append(.item(id))
        }
    }

    func showSettings() {
        switch selectedTab {
        case .home:
            homePath.append(.settings)
        case .library:
            libraryPath.append(.settings)
        case .lists:
            listsPath.append(.settings)
        case .search:
            searchPath.append(.settings)
        }
    }

    func showImportExport() {
        switch selectedTab {
        case .home:
            homePath.append(.importExport)
        case .library:
            libraryPath.append(.importExport)
        case .lists:
            listsPath.append(.importExport)
        case .search:
            searchPath.append(.importExport)
        }
    }

    func popCurrent() {
        switch selectedTab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .library:
            if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .lists:
            if !listsPath.isEmpty { listsPath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        }
    }
}
