import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.sortTitle)]
    ) private var items: [LibraryItem]

    @Environment(AppNavigation.self) private var navigation
    @State private var mediaFilter = MediaFilter.all
    @AppStorage("library.grid-style") private var gridStyleRaw = LibraryGridStyle.flow.rawValue

    private var gridStyle: LibraryGridStyle {
        get { LibraryGridStyle(rawValue: gridStyleRaw) ?? .flow }
        nonmutating set { gridStyleRaw = newValue.rawValue }
    }

    private var visibleItems: [LibraryItem] {
        items.filter { $0.archivedAt == nil && mediaFilter.includes($0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                MediaFilterBar(selection: $mediaFilter)

                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "books.vertical")
                    } description: {
                        Text("Add something manually or find it with metadata search.")
                    } actions: {
                        Button("Add Item", systemImage: "plus") {
                            navigation.presentedSheet = .quickAdd()
                        }
                        .buttonStyle(.glassProminent)

                        Button("Find with Search", systemImage: "magnifyingglass") {
                            navigation.selectedTab = .search
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(minHeight: 430)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeading(
                            title: "Your Archive",
                            subtitle: "\(visibleItems.count) items"
                        )
                        Spacer()
                    }

                    if gridStyle == .flow {
                        FlowCoverGrid(items: visibleItems, openItem: open)
                    } else {
                        DenseCoverGrid(items: visibleItems, openItem: open)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .navigationTitle("Library")
        .archiveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Grid Style", selection: $gridStyleRaw) {
                        ForEach(LibraryGridStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.symbolName)
                                .tag(style.rawValue)
                        }
                    }
                } label: {
                    Label("Grid Style", systemImage: gridStyle.symbolName)
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Item", systemImage: "plus") {
                    navigation.presentedSheet = .quickAdd()
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    navigation.showSettings()
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch mediaFilter {
        case .all: "Your library is ready"
        case let .kind(kind): "No \(kind.displayName) yet"
        }
    }

    private func open(_ item: LibraryItem) {
        navigation.showItem(item.id, from: .library)
    }
}
