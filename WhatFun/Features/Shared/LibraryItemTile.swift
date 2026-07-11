import SwiftUI

enum LibraryGridStyle: String, CaseIterable, Identifiable {
    case flow
    case dense

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .flow: "Flow"
        case .dense: "Dense"
        }
    }

    var symbolName: String {
        switch self {
        case .flow: "rectangle.grid.2x2"
        case .dense: "square.grid.3x3"
        }
    }
}

struct LibraryItemTile: View {
    let item: LibraryItem
    let style: LibraryGridStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: style == .flow ? 8 : 6) {
                ZStack(alignment: .topTrailing) {
                    CoverArtworkView(
                        item: item,
                        contentMode: style == .flow ? .fill : .fit
                    )
                    .aspectRatio(
                        style == .flow ? item.coverAspectRatio : 2.0 / 3.0,
                        contentMode: .fit
                    )
                    .background(WhatFunTheme.raisedBackground)
                    .clipShape(CoverShape(cornerRadius: style == .flow ? 22 : 16))
                    .overlay {
                        CoverShape(cornerRadius: style == .flow ? 22 : 16)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                    }
                    .shadow(color: WhatFunTheme.ink.opacity(0.12), radius: 9, y: 5)

                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(WhatFunTheme.coral, in: .circle)
                            .padding(7)
                            .accessibilityHidden(true)
                    }
                }

                Text(item.title)
                    .font(style == .flow ? .headline : .subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(WhatFunTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Image(systemName: item.status.symbolName)
                    Text(item.status.displayName)
                }
                .font(.caption)
                .foregroundStyle(item.status.color)
                .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens details and history")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: Text {
        if let rating = item.displayRating {
            Text("\(item.title), \(item.status.displayName), rated \(rating, format: .number.precision(.fractionLength(1))) out of 5")
        } else {
            Text("\(item.title), \(item.status.displayName)")
        }
    }
}

struct FlowCoverGrid: View {
    let items: [LibraryItem]
    let openItem: (LibraryItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ForEach(0 ..< 2, id: \.self) { column in
                LazyVStack(spacing: 18) {
                    ForEach(columnItems(column)) { item in
                        LibraryItemTile(item: item, style: .flow) {
                            openItem(item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func columnItems(_ column: Int) -> [LibraryItem] {
        items.enumerated().compactMap { index, item in
            index % 2 == column ? item : nil
        }
    }
}

struct DenseCoverGrid: View {
    let items: [LibraryItem]
    let openItem: (LibraryItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                LibraryItemTile(item: item, style: .dense) {
                    openItem(item)
                }
            }
        }
    }
}

