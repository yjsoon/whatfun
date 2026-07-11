import Foundation

nonisolated struct MetadataDuplicateKey: Hashable, Sendable {
    let providerRaw: String
    let recordKindRaw: String
    let externalID: String

    init(
        provider: MetadataProviderID,
        mediaType: MetadataMediaType,
        externalID: String
    ) {
        providerRaw = provider.rawValue
        recordKindRaw = mediaType.rawValue
        self.externalID = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func matches(providerRaw: String, recordKindRaw: String, externalID: String) -> Bool {
        Self.normalize(self.providerRaw) == Self.normalize(providerRaw) &&
            Self.normalize(self.recordKindRaw) == Self.normalize(recordKindRaw) &&
            Self.normalize(self.externalID) == Self.normalize(externalID)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

nonisolated enum PodcastFeedPrivacy: Sendable, Equatable {
    case publicDirectoryFeed
    case privateCredential

    static func classify(_ url: URL, discoveredBy provider: MetadataProviderID) -> Self {
        guard provider == .applePodcasts,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              !containsSensitiveQuery(in: url)
        else {
            // URLs outside the public Apple directory are treated as private by
            // default. This errs toward Keychain storage instead of accidentally
            // persisting a premium feed token in SwiftData or an export.
            return .privateCredential
        }
        return .publicDirectoryFeed
    }

    private static func containsSensitiveQuery(in url: URL) -> Bool {
        let sensitiveNames: Set<String> = [
            "access_token", "apikey", "api_key", "auth", "authorization",
            "code", "key", "password", "secret", "signature", "sig", "token",
        ]
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }
        return (components.queryItems ?? []).contains {
            sensitiveNames.contains($0.name.lowercased())
        }
    }
}

nonisolated struct MetadataFacetDraft: Hashable, Sendable {
    let kind: FacetKind
    let name: String
}

nonisolated struct PodcastFeedDraft: Hashable, Sendable {
    let url: URL
    let privacy: PodcastFeedPrivacy
    let opaqueID: String
}

nonisolated struct MetadataItemDraft: Hashable, Sendable {
    let duplicateKey: MetadataDuplicateKey
    let provider: MetadataProviderID
    let externalID: String
    let mediaKind: MediaKind
    let title: String
    let subtitle: String?
    let summary: String?
    let creators: [String]
    let releaseYear: Int?
    let pageCount: Int?
    let runtimeSeconds: Int?
    let artworkURL: URL?
    let sourceURL: URL?
    let attribution: MetadataAttribution?
    let facets: [MetadataFacetDraft]
    let podcastFeed: PodcastFeedDraft?
}

nonisolated enum MetadataDomainMapper {
    static func makeDraft(
        result searchResult: MetadataSearchResult,
        details: MetadataItemDetails? = nil,
        attribution: MetadataAttribution? = nil
    ) -> MetadataItemDraft {
        // A provider detail payload is allowed to enrich its own search result,
        // but never to replace a different identity accidentally.
        let result = if details?.result.id == searchResult.id,
                        details?.result.mediaType == searchResult.mediaType
        {
            details?.result ?? searchResult
        } else {
            searchResult
        }
        let creators = result.creators.metadataDeduplicated
        let facets = makeFacets(genres: result.genres, platforms: result.platformNames)
        let feed = result.feedURL.map {
            PodcastFeedDraft(
                url: $0,
                privacy: PodcastFeedPrivacy.classify($0, discoveredBy: result.id.provider),
                opaqueID: ArtworkRepository.hash($0.absoluteString)
            )
        }

        return MetadataItemDraft(
            duplicateKey: MetadataDuplicateKey(
                provider: result.id.provider,
                mediaType: result.mediaType,
                externalID: result.id.externalID
            ),
            provider: result.id.provider,
            externalID: result.id.externalID.trimmingCharacters(in: .whitespacesAndNewlines),
            mediaKind: mediaKind(for: result.mediaType),
            title: result.title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: result.subtitle?.metadataNilIfBlank,
            summary: result.overview?.metadataNilIfBlank,
            creators: creators,
            releaseYear: result.releaseYear,
            pageCount: result.pageCount,
            runtimeSeconds: result.durationMinutes.flatMap { minutes in
                guard minutes > 0, minutes <= Int.max / 60 else { return nil }
                return minutes * 60
            },
            artworkURL: result.coverImageURL ?? result.thumbnailImageURL,
            sourceURL: safePublicSourceURL(result.sourceURL),
            attribution: attribution,
            facets: facets,
            podcastFeed: feed
        )
    }

    static func mediaKind(for metadataType: MetadataMediaType) -> MediaKind {
        switch metadataType {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .tvShow: .tvShow
        case .game: .game
        case .podcast: .podcast
        }
    }

    static func metadataType(for mediaKind: MediaKind) -> MetadataMediaType? {
        switch mediaKind {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .tvShow: .tvShow
        case .game: .game
        case .podcast: .podcast
        case .unknown: nil
        }
    }

    private static func makeFacets(genres: [String], platforms: [String]) -> [MetadataFacetDraft] {
        let genreFacets = genres.metadataDeduplicated.map {
            MetadataFacetDraft(kind: .genre, name: $0)
        }
        let platformFacets = platforms.metadataDeduplicated.map {
            MetadataFacetDraft(kind: .platform, name: $0)
        }
        return genreFacets + platformFacets
    }

    private static func safePublicSourceURL(_ url: URL?) -> URL? {
        guard let url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil,
              url.password == nil
        else { return nil }
        return url
    }
}
