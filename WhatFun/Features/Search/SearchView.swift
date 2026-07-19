import SwiftData
import SwiftUI
import UIKit

enum SearchPresentation {
    case library
    case quickAdd
}

struct SearchView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
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
    @State private var isSearchPresented = false
    @AppStorage("quick-add.last-media-kind") private var storedMediaKindRaw = MediaKind.movie.rawValue

    private let presentation: SearchPresentation
    private let usesRememberedMediaKind: Bool
    private let onOpenItem: (UUID) -> Void
    private let onSelectLocalItem: ((LibraryItem) throws -> Bool)?
    private let onRequestManualAdd: ((MediaKind, String) -> Void)?
    private let onAddItem: ((LibraryItem) throws -> (() -> Void)?)?
    private let addDestinationName: String?

    init(
        initialMediaKind: MediaKind = .movie,
        presentation: SearchPresentation = .library,
        usesRememberedMediaKind: Bool = true,
        onOpenItem: @escaping (UUID) -> Void = { _ in },
        onSelectLocalItem: ((LibraryItem) throws -> Bool)? = nil,
        onRequestManualAdd: ((MediaKind, String) -> Void)? = nil,
        onAddItem: ((LibraryItem) throws -> (() -> Void)?)? = nil,
        addDestinationName: String? = nil
    ) {
        _selectedMediaKind = State(initialValue: initialMediaKind)
        self.presentation = presentation
        self.usesRememberedMediaKind = usesRememberedMediaKind
        self.onOpenItem = onOpenItem
        self.onSelectLocalItem = onSelectLocalItem
        self.onRequestManualAdd = onRequestManualAdd
        self.onAddItem = onAddItem
        self.addDestinationName = addDestinationName
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .quickAdd {
                quickAddHeader
            }

            SearchMediaKindPicker(selection: $selectedMediaKind)
                .padding(.vertical, 6)

            Divider()
                .overlay(WhatFunTheme.secondaryInk.opacity(0.15))

            List {
                if trimmedQuery.isEmpty {
                    featuredResultsSection
                } else {
                    localResultsSection
                    remoteResultsSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(presentation == .quickAdd ? "Add to WhatFun" : "Search")
        .navigationBarTitleDisplayMode(presentation == .quickAdd ? .inline : .automatic)
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            prompt: "Titles, creators, and series"
        )
        .searchToolbarBehavior(.minimize)
        .archiveBackground()
        .toolbar {
            if presentation == .library {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        navigation.showSettings()
                    }
                }
            }
        }
        .task {
            guard presentation == .quickAdd else { return }
            if usesRememberedMediaKind {
                if let storedKind = MediaKind(rawValue: storedMediaKindRaw) {
                    selectedMediaKind = storedKind
                }
                if case .credentialRequired = selectedProvider?.availability,
                   let availableKind = MediaKind.filterCases.first(where: { kind in
                       guard let type = MetadataDomainMapper.metadataType(for: kind),
                             let provider = services.metadata.catalog.primaryProvider(for: type)
                       else { return false }
                       return provider.availability == .available
                   })
                {
                    selectedMediaKind = availableKind
                }
            }
            await Task.yield()
            isSearchPresented = true
        }
        .onChange(of: selectedMediaKind) { _, kind in
            guard presentation == .quickAdd else { return }
            storedMediaKindRaw = kind.rawValue
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

    private var quickAddHeader: some View {
        HStack {
            Button("Enter Manually", systemImage: "square.and.pencil") {
                onRequestManualAdd?(selectedMediaKind, trimmedQuery)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)

            Spacer()

            Text("Add to WhatFun")
                .font(.headline)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
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

    private var featuredResultsSection: some View {
        Section {
            switch remoteState {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Finding what’s popular…")
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 26)
                .listRowBackground(Color.clear)
            case let .loaded(results):
                if results.isEmpty {
                    SearchMessageRow(
                        symbol: "sparkles",
                        title: "No popular titles right now",
                        message: "Start typing to search, or enter an item manually."
                    )
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(results) { result in
                                FeaturedMetadataCard(
                                    result: result,
                                    isAdding: addingKey == duplicateKey(for: result),
                                    isAdded: addedKeys.contains(duplicateKey(for: result)),
                                    isDisabled: addingKey != nil,
                                    addDestinationName: addDestinationName,
                                    add: { add(result) }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            case let .failed(failure):
                SearchFailureContent(
                    failure: failure,
                    retry: { retryNonce += 1 },
                    manualAdd: onRequestManualAdd.map { action in
                        { action(selectedMediaKind, trimmedQuery) }
                    }
                )
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Popular \(String(localized: selectedMediaKind.displayName))")
        } footer: {
            MetadataAttributionFooter(attribution: selectedProvider?.attribution)
        }
    }

    @ViewBuilder
    private var localResultsSection: some View {
        if !matchingLibraryItems.isEmpty {
            Section("In Your Library") {
                ForEach(matchingLibraryItems) { item in
                    Button {
                        selectLocalItem(item)
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
                            addDestinationName: addDestinationName,
                            add: { add(result) }
                        )
                        .listRowBackground(Color.clear)
                    }
                    manualAddRow
                }
            case let .failed(failure):
                SearchFailureContent(
                    failure: failure,
                    retry: { retryNonce += 1 },
                    manualAdd: onRequestManualAdd.map { action in
                        { action(selectedMediaKind, trimmedQuery) }
                    }
                )
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
        guard trimmedQuery.isEmpty || trimmedQuery.count >= 2,
              let metadataType = MetadataDomainMapper.metadataType(for: selectedMediaKind),
              let provider = selectedProvider
        else {
            remoteState = .idle
            return
        }

        do {
            remoteState = .loading
            if !trimmedQuery.isEmpty {
                try await Task.sleep(for: .milliseconds(350))
            }
            try Task.checkCancellation()
            let languageCode = Locale.current.language.languageCode?.identifier
            let countryCode = Locale.current.region?.identifier
            let page: MetadataSearchPage
            if trimmedQuery.isEmpty {
                page = try await provider.featured(
                    MetadataDiscoveryRequest(
                        mediaType: metadataType,
                        limit: 20,
                        languageCode: languageCode,
                        countryCode: countryCode
                    )
                )
            } else {
                page = try await provider.search(
                    MetadataSearchRequest(
                        query: trimmedQuery,
                        mediaType: metadataType,
                        languageCode: languageCode,
                        countryCode: countryCode
                    )
                )
            }
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
                    attribution: provider?.attribution,
                    beforeSave: onAddItem
                )
                addedKeys.insert(duplicateKey)
                successfulAdds += 1
                if presentation == .library {
                    onOpenItem(insertion.item.id)
                }
            } catch is CancellationError {
                // Leaving Search should stop quietly.
            } catch {
                addFailure = SearchAddFailure(message: error.localizedDescription)
            }
        }
    }

    private func selectLocalItem(_ item: LibraryItem) {
        guard let onSelectLocalItem else {
            onOpenItem(item.id)
            return
        }

        do {
            if try onSelectLocalItem(item) {
                successfulAdds += 1
            }
        } catch {
            addFailure = SearchAddFailure(message: error.localizedDescription)
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
    let addDestinationName: String?
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
            .accessibilityLabel(accessibilityLabel)
        }
        .padding(.vertical, 4)
    }

    private var metadataSubtitle: String? {
        let creator = result.creators.first ?? result.subtitle
        let year = result.releaseYear.map(String.init)
        return [creator, year].compactMap(\.self).joined(separator: " · ").metadataNilIfBlank
    }

    private var accessibilityLabel: String {
        let destination = addDestinationName.map { "list \($0)" } ?? "library"
        return isAdded ? "Added to \(destination)" : "Add \(result.title) to \(destination)"
    }
}

private struct FeaturedMetadataCard: View {
    let result: MetadataSearchResult
    let isAdding: Bool
    let isAdded: Bool
    let isDisabled: Bool
    let addDestinationName: String?
    let add: () -> Void

    private var mediaKind: MediaKind {
        MetadataDomainMapper.mediaKind(for: result.mediaType)
    }

    private var artworkHeight: CGFloat {
        mediaKind == .podcast ? 132 : 184
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                SearchMetadataArtwork(
                    url: result.coverImageURL ?? result.thumbnailImageURL,
                    mediaKind: mediaKind,
                    targetSize: CGSize(width: 132, height: artworkHeight)
                )
                .frame(width: 132, height: artworkHeight)
                .clipShape(CoverShape(cornerRadius: 18))

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
                    .font(.headline.weight(.bold))
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.glassProminent)
                .disabled(isDisabled || isAdded)
                .padding(8)
                .accessibilityLabel(accessibilityLabel)
            }

            Text(result.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhatFunTheme.ink)
                .lineLimit(2)

            Text(result.releaseYear.map(String.init) ?? result.creators.first ?? " ")
                .font(.caption)
                .foregroundStyle(WhatFunTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
    }

    private var accessibilityLabel: String {
        let destination = addDestinationName.map { "list \($0)" } ?? "library"
        return isAdded ? "Added to \(destination)" : "Add \(result.title) to \(destination)"
    }
}

private struct SearchMetadataArtwork: View {
    let url: URL?
    let mediaKind: MediaKind
    var targetSize = CGSize(width: 64, height: 90)

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
                targetSize: targetSize,
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

private struct SearchFailureContent: View {
    let failure: RemoteSearchFailure
    let retry: () -> Void
    let manualAdd: (() -> Void)?

    var body: some View {
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
                Button("Try Again", action: retry)
                    .buttonStyle(.glass)

                if let manualAdd {
                    Button("Enter Manually", action: manualAdd)
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 14)
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

struct QuickAddView: View {
    private let initialMediaKind: MediaKind?
    private let destinationListID: UUID?

    @Query private var destinationLists: [UserList]
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var manualAddRequest: ManualAddRequest?

    init(initialMediaKind: MediaKind? = nil, destinationListID: UUID? = nil) {
        self.initialMediaKind = initialMediaKind
        self.destinationListID = destinationListID
        let queryID = destinationListID ?? UUID()
        _destinationLists = Query(
            filter: #Predicate<UserList> { list in
                list.id == queryID
            }
        )
    }

    var body: some View {
        NavigationStack {
            SearchView(
                initialMediaKind: initialMediaKind ?? .movie,
                presentation: .quickAdd,
                usesRememberedMediaKind: initialMediaKind == nil,
                onSelectLocalItem: selectLocalItem,
                onRequestManualAdd: { kind, query in
                    manualAddRequest = ManualAddRequest(kind: kind, title: query)
                },
                onAddItem: { item in
                    prepareDestinationListMembership(item)
                },
                addDestinationName: destinationLists.first?.name
            )
        }
        .sheet(item: $manualAddRequest) { request in
            ItemEditorView(
                initialKind: request.kind,
                initialTitle: request.title,
                onPrepareSave: { item in
                    _ = prepareDestinationListMembership(item)
                }
            )
        }
    }

    private func selectLocalItem(_ item: LibraryItem) throws -> Bool {
        if destinationListID != nil {
            return try addToDestinationList(item)
        }

        dismiss()
        Task { @MainActor in
            await Task.yield()
            navigation.showItem(item.id)
        }
        return false
    }

    @discardableResult
    private func addToDestinationList(_ item: LibraryItem) throws -> Bool {
        guard let undoPreparation = prepareDestinationListMembership(item) else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            undoPreparation()
            throw error
        }
    }

    private func prepareDestinationListMembership(_ item: LibraryItem) -> (() -> Void)? {
        guard destinationListID != nil,
              let list = destinationLists.first,
              !(list.memberships ?? []).contains(where: { $0.itemID == item.id })
        else { return nil }

        let previousUpdatedAt = list.updatedAt
        let membership = ListMembership(
            list: list,
            item: item,
            positionRank: String(format: "%08d", (list.memberships ?? []).count)
        )
        modelContext.insert(membership)
        list.memberships = (list.memberships ?? []) + [membership]
        if !(item.listMemberships ?? []).contains(where: { $0.id == membership.id }) {
            item.listMemberships = (item.listMemberships ?? []) + [membership]
        }
        list.updatedAt = .now
        return {
            list.memberships?.removeAll { $0.id == membership.id }
            item.listMemberships?.removeAll { $0.id == membership.id }
            list.updatedAt = previousUpdatedAt
            modelContext.delete(membership)
        }
    }
}

private struct ManualAddRequest: Identifiable {
    let id = UUID()
    let kind: MediaKind
    let title: String
}
