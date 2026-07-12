import SwiftData
import SwiftUI
import UIKit

struct SearchView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var libraryItems: [LibraryItem]

    @State private var query = ""
    @State private var selectedMediaKind: MediaKind
    @State private var remoteState = RemoteSearchState.idle
    @State private var retryNonce = 0
    @State private var addingKey: MetadataDuplicateKey?
    @State private var addedKeys = Set<MetadataDuplicateKey>()
    @State private var addFailure: SearchAddFailure?
    @State private var successfulAdds = 0

    private let onOpenItem: (UUID) -> Void
    private let onRequestManualAdd: ((MediaKind, String) -> Void)?

    init(
        initialMediaKind: MediaKind = .movie,
        onOpenItem: @escaping (UUID) -> Void = { _ in },
        onRequestManualAdd: ((MediaKind, String) -> Void)? = nil
    ) {
        _selectedMediaKind = State(initialValue: initialMediaKind)
        self.onOpenItem = onOpenItem
        self.onRequestManualAdd = onRequestManualAdd
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchMediaKindPicker(selection: $selectedMediaKind)
                .padding(.vertical, 6)

            Divider()
                .overlay(WhatFunTheme.secondaryInk.opacity(0.15))

            List {
                if trimmedQuery.isEmpty {
                    initialPrompt
                } else {
                    localResultsSection
                    remoteResultsSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Titles, creators, and series")
        .searchToolbarBehavior(.minimize)
        .archiveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    navigation.showSettings()
                }
            }
        }
        .task(id: searchTaskID) {
            await searchRemoteMetadata()
        }
        .alert(item: $addFailure) { failure in
            Alert(
                title: Text("Couldn’t Add Item"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sensoryFeedback(.success, trigger: successfulAdds)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchTaskID: RemoteSearchTaskID {
        RemoteSearchTaskID(
            query: LibraryItem.normalize(trimmedQuery),
            mediaKind: selectedMediaKind,
            retryNonce: retryNonce
        )
    }

    private var matchingLibraryItems: [LibraryItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        let terms = LibraryItem.normalize(trimmedQuery)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let matches = libraryItems
            .filter { item in
                guard item.trashedAt == nil, item.mediaKind == selectedMediaKind else { return false }
                let searchable = LibraryItem.normalize(
                    [item.title, item.subtitle, item.creatorLine]
                        .compactMap(\.self)
                        .joined(separator: " ")
                )
                return terms.allSatisfy(searchable.contains)
            }
        return Array(matches[0 ..< min(20, matches.count)])
    }

    @ViewBuilder
    private var initialPrompt: some View {
        ContentUnavailableView {
            Label("Find Your Next Thing", systemImage: selectedMediaKind.symbolName)
        } description: {
            Text("Search your library and discover metadata for \(String(localized: selectedMediaKind.displayName)).")
        } actions: {
            if let onRequestManualAdd {
                Button("Add Manually") {
                    onRequestManualAdd(selectedMediaKind, "")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var localResultsSection: some View {
        if !matchingLibraryItems.isEmpty {
            Section("In Your Library") {
                ForEach(matchingLibraryItems) { item in
                    Button {
                        onOpenItem(item.id)
                    } label: {
                        LocalSearchResultRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var remoteResultsSection: some View {
        Section {
            switch remoteState {
            case .idle:
                SearchMessageRow(
                    symbol: "text.cursor",
                    title: "Keep typing",
                    message: "Enter at least two characters to search metadata."
                )
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(String(localized: selectedMediaKind.displayName))…")
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
                .listRowBackground(Color.clear)
            case let .loaded(results):
                if results.isEmpty {
                    SearchMessageRow(
                        symbol: "magnifyingglass",
                        title: "No metadata matches",
                        message: "Try another title or add this \(String(localized: selectedMediaKind.singularName)) manually."
                    )
                    manualAddRow
                } else {
                    ForEach(results) { result in
                        RemoteSearchResultRow(
                            result: result,
                            isAdding: addingKey == duplicateKey(for: result),
                            isAdded: addedKeys.contains(duplicateKey(for: result)),
                            isDisabled: addingKey != nil,
                            add: { add(result) }
                        )
                        .listRowBackground(Color.clear)
                    }
                    manualAddRow
                }
            case let .failed(failure):
                VStack(alignment: .leading, spacing: 10) {
                    Label(failure.title, systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text(failure.message)
                        .font(.subheadline)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                    if let suggestion = failure.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                    HStack(spacing: 10) {
                        Button("Try Again") {
                            retryNonce += 1
                        }
                        .buttonStyle(.glass)

                        if let onRequestManualAdd {
                            Button("Add Manually") {
                                onRequestManualAdd(selectedMediaKind, trimmedQuery)
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 14)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Discover")
        } footer: {
            MetadataAttributionFooter(attribution: selectedProvider?.attribution)
        }
    }

    @ViewBuilder
    private var manualAddRow: some View {
        if let onRequestManualAdd {
            Button {
                onRequestManualAdd(selectedMediaKind, trimmedQuery)
            } label: {
                Label("Can’t find it? Add manually", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WhatFunTheme.coral)
            .listRowBackground(Color.clear)
        }
    }

    private var selectedProvider: (any MetadataProvider)? {
        guard let type = MetadataDomainMapper.metadataType(for: selectedMediaKind) else { return nil }
        return services.metadata.catalog.primaryProvider(for: type)
    }

    private func searchRemoteMetadata() async {
        guard trimmedQuery.count >= 2,
              let metadataType = MetadataDomainMapper.metadataType(for: selectedMediaKind),
              let provider = selectedProvider
        else {
            remoteState = .idle
            return
        }

        do {
            remoteState = .loading
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            let page = try await provider.search(
                MetadataSearchRequest(
                    query: trimmedQuery,
                    mediaType: metadataType,
                    languageCode: Locale.current.language.languageCode?.identifier,
                    countryCode: Locale.current.region?.identifier
                )
            )
            try Task.checkCancellation()
            remoteState = .loaded(page.results)
        } catch is CancellationError {
            // `.task(id:)` cancels stale keystrokes and media selections.
        } catch {
            remoteState = .failed(RemoteSearchFailure(error: error))
        }
    }

    private func add(_ result: MetadataSearchResult) {
        guard addingKey == nil else { return }
        let duplicateKey = duplicateKey(for: result)
        addingKey = duplicateKey

        Task { @MainActor in
            defer { addingKey = nil }
            let provider = services.metadata.catalog.providers.first { $0.id == result.id.provider }
            let details: MetadataItemDetails?
            if let provider {
                do {
                    details = try await provider.details(for: result)
                } catch is CancellationError {
                    return
                } catch {
                    // Search metadata is enough to create a useful local record;
                    // detail enrichment can be retried during a later refresh.
                    details = nil
                }
            } else {
                details = nil
            }

            do {
                let insertion = try await MetadataLibraryInserter(
                    context: modelContext,
                    credentials: services.credentials
                ).insert(
                    result: result,
                    details: details,
                    attribution: provider?.attribution
                )
                addedKeys.insert(duplicateKey)
                successfulAdds += 1
                onOpenItem(insertion.item.id)
            } catch is CancellationError {
                // Leaving Search should stop quietly.
            } catch {
                addFailure = SearchAddFailure(message: error.localizedDescription)
            }
        }
    }

    private func duplicateKey(for result: MetadataSearchResult) -> MetadataDuplicateKey {
        MetadataDuplicateKey(
            provider: result.id.provider,
            mediaType: result.mediaType,
            externalID: result.id.externalID
        )
    }
}

private struct RemoteSearchTaskID: Hashable {
    let query: String
    let mediaKind: MediaKind
    let retryNonce: Int
}

private enum RemoteSearchState {
    case idle
    case loading
    case loaded([MetadataSearchResult])
    case failed(RemoteSearchFailure)
}

private struct RemoteSearchFailure {
    let title: String
    let message: String
    let recoverySuggestion: String?

    init(error: any Error) {
        if let providerError = error as? MetadataProviderError,
           case .missingCredential = providerError
        {
            title = "Metadata isn’t configured"
        } else {
            title = "Search is unavailable"
        }
        message = error.localizedDescription
        recoverySuggestion = (error as? any LocalizedError)?.recoverySuggestion
    }
}

private struct SearchAddFailure: Identifiable {
    let id = UUID()
    let message: String
}

private struct SearchMediaKindPicker: View {
    @Binding var selection: MediaKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MediaKind.filterCases, id: \.rawValue) { kind in
                        Button {
                            if reduceMotion {
                                selection = kind
                            } else {
                                withAnimation(.smooth(duration: 0.2)) {
                                    selection = kind
                                }
                            }
                        } label: {
                            Label(kind.displayName, systemImage: kind.symbolName)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            selection == kind
                                ? .regular.tint(kind.accentColor.opacity(0.42)).interactive()
                                : .regular.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(selection == kind ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}

private struct LocalSearchResultRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 13) {
            CoverArtworkView(item: item)
                .frame(width: 56, height: item.mediaKind == .podcast ? 56 : 82)
                .clipShape(CoverShape(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(WhatFunTheme.ink)
                    .lineLimit(2)

                if let creator = item.creatorLine {
                    Text(creator)
                        .font(.subheadline)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Label(item.status.displayName, systemImage: item.status.symbolName)
                        .foregroundStyle(item.status.color)
                    if item.isArchived {
                        Text("· Archived")
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                }
                .font(.caption.weight(.medium))
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
    }
}

private struct RemoteSearchResultRow: View {
    let result: MetadataSearchResult
    let isAdding: Bool
    let isAdded: Bool
    let isDisabled: Bool
    let add: () -> Void

    private var mediaKind: MediaKind {
        MetadataDomainMapper.mediaKind(for: result.mediaType)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            SearchMetadataArtwork(
                url: result.thumbnailImageURL ?? result.coverImageURL,
                mediaKind: mediaKind
            )
            .frame(width: 56, height: mediaKind == .podcast ? 56 : 82)
            .clipShape(CoverShape(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(WhatFunTheme.ink)
                    .lineLimit(2)

                if let subtitle = metadataSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .lineLimit(2)
                }

                if !result.genres.isEmpty {
                    Text(Array(result.genres[0 ..< min(2, result.genres.count)]).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button(action: add) {
                Group {
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else if isAdded {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.glassProminent)
            .disabled(isDisabled || isAdded)
            .accessibilityLabel(isAdded ? "Added to library" : "Add \(result.title) to library")
        }
        .padding(.vertical, 4)
    }

    private var metadataSubtitle: String? {
        let creator = result.creators.first ?? result.subtitle
        let year = result.releaseYear.map(String.init)
        return [creator, year].compactMap(\.self).joined(separator: " · ").metadataNilIfBlank
    }
}

private struct SearchMetadataArtwork: View {
    let url: URL?
    let mediaKind: MediaKind

    @Environment(AppServices.self) private var services
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [mediaKind.accentColor.opacity(0.68), WhatFunTheme.raisedBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: didFail ? "wifi.slash" : mediaKind.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WhatFunTheme.ink.opacity(0.7))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            await load()
        }
        .animation(.easeInOut(duration: 0.18), value: image != nil)
        .accessibilityHidden(true)
    }

    private func load() async {
        image = nil
        didFail = false
        guard let url else { return }
        do {
            let data = try await services.artwork.data(for: url)
            try Task.checkCancellation()
            image = await ArtworkDownsampler.image(
                from: data,
                targetSize: CGSize(width: 64, height: 90),
                displayScale: displayScale
            )
            didFail = image == nil
        } catch is CancellationError {
            // Recycled rows should stop without showing a failure state.
        } catch {
            didFail = true
        }
    }
}

private struct SearchMessageRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(WhatFunTheme.coral)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
        .padding(.vertical, 14)
        .listRowBackground(Color.clear)
    }
}

private struct MetadataAttributionFooter: View {
    let attribution: MetadataAttribution?

    var body: some View {
        if let attribution {
            VStack(alignment: .leading, spacing: 3) {
                Link(attribution.label, destination: attribution.url)
                if let notice = attribution.notice {
                    Text(notice)
                }
            }
            .font(.caption)
            .foregroundStyle(WhatFunTheme.secondaryInk)
        }
    }
}
