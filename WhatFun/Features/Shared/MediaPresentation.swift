import SwiftUI

extension MediaKind {
    var displayName: LocalizedStringResource {
        switch self {
        case .book: "Books"
        case .comic: "Comics"
        case .movie: "Movies"
        case .tvShow: "TV"
        case .game: "Games"
        case .podcast: "Podcasts"
        case .unknown: "Other"
        }
    }

    var singularName: LocalizedStringResource {
        switch self {
        case .book: "Book"
        case .comic: "Comic"
        case .movie: "Movie"
        case .tvShow: "TV Show"
        case .game: "Game"
        case .podcast: "Podcast"
        case .unknown: "Item"
        }
    }

    var symbolName: String {
        switch self {
        case .book: "book.closed"
        case .comic: "rectangle.stack"
        case .movie: "film"
        case .tvShow: "tv"
        case .game: "gamecontroller"
        case .podcast: "waveform"
        case .unknown: "sparkles.rectangle.stack"
        }
    }

    var accentColor: Color {
        switch self {
        case .book, .comic: WhatFunTheme.coral
        case .movie, .tvShow: WhatFunTheme.sky
        case .game: WhatFunTheme.sage
        case .podcast: .purple
        case .unknown: WhatFunTheme.secondaryInk
        }
    }

    nonisolated var defaultCoverAspectRatio: CGFloat {
        switch self {
        case .podcast: 1
        case .game: 0.74
        case .book, .comic, .movie, .tvShow, .unknown: 2.0 / 3.0
        }
    }

    static var filterCases: [MediaKind] {
        [.book, .comic, .movie, .tvShow, .game, .podcast]
    }
}

extension ConsumptionStatus {
    var displayName: LocalizedStringResource {
        switch self {
        case .planned: "Planned"
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .dropped: "Dropped"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .planned: "bookmark"
        case .inProgress: "play.circle"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .dropped: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .planned: WhatFunTheme.secondaryInk
        case .inProgress: WhatFunTheme.coral
        case .paused: .orange
        case .completed: WhatFunTheme.sage
        case .dropped: .secondary
        case .unknown: .secondary
        }
    }
}

extension PodcastFollowState {
    var displayName: LocalizedStringResource {
        switch self {
        case .following: "Currently Following"
        case .paused: "Paused"
        case .completed: "Completed"
        case .dropped: "Dropped"
        case .unknown: "Unknown"
        }
    }
}

extension PodcastListeningStyle {
    var displayName: LocalizedStringResource {
        switch self {
        case .everyEpisode: "Every Episode"
        case .selectedEpisodes: "Selected Episodes"
        case .keepAround: "Keep Around"
        case .unknown: "Unknown"
        }
    }
}

enum MediaFilter: Hashable, Identifiable, Sendable {
    case all
    case kind(MediaKind)

    static var allCases: [MediaFilter] {
        [.all] + MediaKind.filterCases.map(MediaFilter.kind)
    }

    var id: String {
        switch self {
        case .all: "all"
        case let .kind(kind): kind.rawValue
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .all: "All"
        case let .kind(kind): kind.displayName
        }
    }

    var symbolName: String? {
        switch self {
        case .all: nil
        case let .kind(kind): kind.symbolName
        }
    }

    func includes(_ item: LibraryItem) -> Bool {
        switch self {
        case .all: true
        case let .kind(kind): item.mediaKind == kind
        }
    }
}

struct MediaFilterBar: View {
    @Binding var selection: MediaFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MediaFilter.allCases) { filter in
                        Button {
                            if reduceMotion {
                                selection = filter
                            } else {
                                withAnimation(.smooth(duration: 0.22)) {
                                    selection = filter
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if let symbol = filter.symbolName {
                                    Image(systemName: symbol)
                                }
                                Text(filter.displayName)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            selection == filter
                                ? .regular.tint(WhatFunTheme.coral.opacity(0.42)).interactive()
                                : .regular.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}

struct RatingLabel: View {
    let halfSteps: Int?
    var showsValue = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .foregroundStyle(halfSteps == nil ? Color.secondary.opacity(0.35) : Color.yellow)
            }

            if showsValue, let halfSteps {
                Text(Double(halfSteps) / 2, format: .number.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(accessibilityValue)
    }

    private func symbol(for star: Int) -> String {
        guard let halfSteps else { return "star" }
        let wholeThreshold = star * 2
        if halfSteps >= wholeThreshold { return "star.fill" }
        if halfSteps == wholeThreshold - 1 { return "star.leadinghalf.filled" }
        return "star"
    }

    private var accessibilityValue: Text {
        if let halfSteps {
            Text("\(Double(halfSteps) / 2, format: .number.precision(.fractionLength(1))) out of 5 stars")
        } else {
            Text("Not rated")
        }
    }
}
