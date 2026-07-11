import Foundation

nonisolated enum MetadataMediaType: String, CaseIterable, Codable, Sendable {
    case book
    case comic
    case movie
    case tvShow
    case game
    case podcast
}

nonisolated enum MetadataProviderID: String, CaseIterable, Codable, Sendable {
    case tmdb
    case openLibrary
    case rawg
    case applePodcasts
    case rss

    var displayName: String {
        switch self {
        case .tmdb: "TMDB"
        case .openLibrary: "Open Library"
        case .rawg: "RAWG"
        case .applePodcasts: "Apple Podcasts"
        case .rss: "Podcast feed"
        }
    }
}

nonisolated struct MetadataResultID: Hashable, Codable, Sendable, CustomStringConvertible {
    let provider: MetadataProviderID
    let externalID: String

    var description: String {
        "\(provider.rawValue):\(externalID)"
    }
}

nonisolated struct MetadataAttribution: Hashable, Codable, Sendable {
    let label: String
    let notice: String?
    let url: URL
}

nonisolated struct MetadataSearchRequest: Hashable, Sendable {
    let query: String
    let mediaType: MetadataMediaType
    let page: Int
    let limit: Int
    let languageCode: String?
    let countryCode: String?

    init(
        query: String,
        mediaType: MetadataMediaType,
        page: Int = 1,
        limit: Int = 20,
        languageCode: String? = nil,
        countryCode: String? = nil
    ) {
        self.query = query
        self.mediaType = mediaType
        self.page = max(1, page)
        self.limit = min(max(1, limit), 50)
        self.languageCode = languageCode
        self.countryCode = countryCode
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct MetadataSearchResult: Identifiable, Hashable, Codable, Sendable {
    let id: MetadataResultID
    let mediaType: MetadataMediaType
    let title: String
    let subtitle: String?
    let creators: [String]
    let overview: String?
    let releaseYear: Int?
    let coverImageURL: URL?
    let thumbnailImageURL: URL?
    let sourceURL: URL?
    let feedURL: URL?
    let genres: [String]
    let pageCount: Int?
    let durationMinutes: Int?
    let seasonCount: Int?
    let episodeCount: Int?
    let platformNames: [String]
}

nonisolated struct MetadataSearchPage: Hashable, Codable, Sendable {
    let results: [MetadataSearchResult]
    let page: Int
    let totalPages: Int?
    let totalResults: Int?

    var hasMore: Bool {
        guard let totalPages else { return !results.isEmpty }
        return page < totalPages
    }
}

nonisolated struct MetadataFact: Hashable, Codable, Sendable {
    let label: String
    let value: String
}

nonisolated struct MetadataItemDetails: Hashable, Codable, Sendable {
    let result: MetadataSearchResult
    let websiteURL: URL?
    let facts: [MetadataFact]
    let artworkURLs: [URL]
}

nonisolated enum MetadataProviderAvailability: Hashable, Sendable {
    case available
    case credentialRequired(instructions: String, setupURL: URL?)
}

nonisolated enum MetadataProviderError: Error, Sendable, Equatable {
    case emptyQuery
    case unsupportedMediaType(provider: MetadataProviderID, mediaType: MetadataMediaType)
    case missingCredential(provider: MetadataProviderID, instructions: String)
    case invalidRequest(provider: MetadataProviderID)
    case invalidResponse(provider: MetadataProviderID, reason: String)
}

extension MetadataProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Enter a title to search for."
        case let .unsupportedMediaType(provider, mediaType):
            "\(provider.displayName) does not search \(mediaType.rawValue) metadata."
        case let .missingCredential(provider, _):
            "\(provider.displayName) needs an API credential before it can search."
        case let .invalidRequest(provider):
            "WhatFun could not create the \(provider.displayName) request."
        case let .invalidResponse(provider, _):
            "\(provider.displayName) returned metadata WhatFun could not understand."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .missingCredential(_, instructions):
            "\(instructions) You can still add the item manually."
        case .emptyQuery:
            nil
        case .unsupportedMediaType, .invalidRequest, .invalidResponse:
            "Try another search, or add the item manually."
        }
    }

    var supportsManualFallback: Bool { true }
}

nonisolated extension String {
    var metadataNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

nonisolated extension Collection<String> {
    var metadataDeduplicated: [String] {
        var seen = Set<String>()
        return compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }
}
