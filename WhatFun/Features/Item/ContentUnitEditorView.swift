import SwiftData
import SwiftUI

struct ContentUnitEditorView: View {
    private let itemID: UUID
    private let parentUnitID: UUID?

    @Query private var matchingItems: [LibraryItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var number = ""
    @State private var hasReleaseDate = false
    @State private var releaseDate = Date.now
    @State private var pageCount = ""
    @State private var durationMinutes = ""
    @State private var comment = ""
    @State private var isNotable = false
    @State private var errorMessage: String?

    init(itemID: UUID, parentUnitID: UUID? = nil) {
        self.itemID = itemID
        self.parentUnitID = parentUnitID
        _matchingItems = Query(
            filter: #Predicate<LibraryItem> { $0.id == itemID }
        )
    }

    private var item: LibraryItem? { matchingItems.first }

    private var parent: ContentUnit? {
        guard let parentUnitID else { return nil }
        return (item?.units ?? []).first { $0.id == parentUnitID }
    }

    private var kind: ContentUnitKind {
        if let parent {
            switch parent.unitKind {
            case .tvSeason: return .tvEpisode
            case .comicVolume: return .comicIssue
            default: break
            }
        }
        return switch item?.mediaKind {
        case .tvShow: .tvSeason
        case .comic: .comicVolume
        case .podcast: .podcastEpisode
        default: .unknown
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.displayName) {
                    TextField(suggestedTitle, text: $title)
                    TextField("Number (optional)", text: $number)
                        .keyboardType(.decimalPad)
                    Toggle("Known release date", isOn: $hasReleaseDate)
                    if hasReleaseDate {
                        DatePicker("Released", selection: $releaseDate, displayedComponents: .date)
                    }
                }

                if kind == .comicVolume || kind == .comicIssue {
                    Section("Reading") {
                        TextField("Page count (optional)", text: $pageCount)
                            .keyboardType(.numberPad)
                    }
                }

                if kind == .tvEpisode || kind == .podcastEpisode {
                    Section("Episode") {
                        TextField("Duration in minutes (optional)", text: $durationMinutes)
                            .keyboardType(.numberPad)
                        if kind == .podcastEpisode {
                            Toggle("Notable episode", isOn: $isNotable)
                        }
                        TextField("Comment (optional)", text: $comment, axis: .vertical)
                            .lineLimit(2 ... 6)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WhatFunTheme.background)
            .navigationTitle("Add \(kind.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(item == nil || resolvedTitle.isEmpty || kind == .unknown)
                }
            }
            .alert("Couldn’t Add Installment", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var resolvedTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? suggestedTitle : value
    }

    private var suggestedTitle: String {
        let suffix = number.unitNilIfBlank.map { " \($0)" } ?? ""
        return switch kind {
        case .tvSeason: "Season\(suffix)"
        case .tvEpisode: "Episode\(suffix)"
        case .comicVolume: "Volume\(suffix)"
        case .comicIssue: "Issue\(suffix)"
        case .podcastEpisode: "Podcast Episode\(suffix)"
        case .unknown: "Installment"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let item, kind != .unknown else { return }
        do {
            let numericValue = Double(number)
            let nextOrder = ((parent?.children ?? item.units) ?? []).map(\.sortOrder).max() ?? -1
            let unit = ContentUnit(
                item: item,
                kind: kind,
                title: resolvedTitle,
                sortOrder: numericValue.map(Int.init) ?? nextOrder + 1,
                parent: parent
            )
            unit.numberValue = numericValue
            unit.numberLabel = number.unitNilIfBlank
            unit.releaseDate = hasReleaseDate ? releaseDate : nil
            unit.pageCount = Int(pageCount)
            unit.durationSeconds = Int(durationMinutes).map { max(0, $0) * 60 }
            unit.comment = comment.unitNilIfBlank
            unit.isNotable = isNotable

            switch kind {
            case .tvSeason:
                unit.seasonNumber = numericValue.map(Int.init)
            case .tvEpisode, .podcastEpisode:
                unit.episodeNumber = numericValue.map(Int.init)
                unit.seasonNumber = parent?.seasonNumber
            default:
                break
            }

            modelContext.insert(unit)
            item.units = (item.units ?? []) + [unit]
            if let parent {
                parent.children = (parent.children ?? []) + [unit]
            }
            ActivityProjection.rebuild(item)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct QuoteEditorView: View {
    private let episodeID: UUID

    @Query private var matchingEpisodes: [ContentUnit]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @State private var timestamp = ""
    @State private var comment = ""
    @State private var errorMessage: String?

    init(episodeID: UUID) {
        self.episodeID = episodeID
        _matchingEpisodes = Query(
            filter: #Predicate<ContentUnit> { $0.id == episodeID }
        )
    }

    private var episode: ContentUnit? { matchingEpisodes.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notable Quote") {
                    TextField("Quote", text: $text, axis: .vertical)
                        .lineLimit(3 ... 10)
                    TextField("Timestamp, e.g. 12:34 (optional)", text: $timestamp)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Comment (optional)", text: $comment, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WhatFunTheme.background)
            .navigationTitle("Add Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Couldn’t Save Quote", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let episode, episode.unitKind == .podcastEpisode else { return }
        do {
            let quote = NotableQuote(
                episode: episode,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                timestampSeconds: parseTimestamp(timestamp),
                comment: comment.unitNilIfBlank,
                sortOrder: (episode.notableQuotes ?? []).count
            )
            modelContext.insert(quote)
            episode.notableQuotes = (episode.notableQuotes ?? []) + [quote]
            episode.isNotable = true
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseTimestamp(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 1: return parts.first
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3_600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}

private extension ContentUnitKind {
    var displayName: LocalizedStringResource {
        switch self {
        case .tvSeason: "Season"
        case .tvEpisode: "Episode"
        case .comicVolume: "Volume"
        case .comicIssue: "Issue"
        case .podcastEpisode: "Podcast Episode"
        case .unknown: "Installment"
        }
    }
}

private extension String {
    var unitNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
