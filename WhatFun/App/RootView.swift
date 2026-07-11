import SwiftUI

struct RootView: View {
    private enum AppTab: Hashable {
        case home
        case library
        case lists
        case search
    }

    @State private var selection = AppTab.home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                PlaceholderScreen(
                    title: "WhatFun",
                    message: "Your current and recent entertainment will live here.",
                    symbol: "sparkles"
                )
            }

            Tab("Library", systemImage: "books.vertical", value: .library) {
                PlaceholderScreen(
                    title: "Library",
                    message: "A cover-first archive across all six media types.",
                    symbol: "books.vertical"
                )
            }

            Tab("Lists", systemImage: "rectangle.stack", value: .lists) {
                PlaceholderScreen(
                    title: "Lists",
                    message: "Manual and smart lists will organize what comes next.",
                    symbol: "rectangle.stack"
                )
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                PlaceholderScreen(
                    title: "Search",
                    message: "Find your library or add metadata from supported providers.",
                    symbol: "magnifyingglass"
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.accentColor)
    }
}

private struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}

