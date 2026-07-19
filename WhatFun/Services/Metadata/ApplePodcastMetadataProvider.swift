import Foundation

nonisolated struct ApplePodcastMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.applePodcasts
    let supportedMediaTypes: Set<MetadataMediaType> = [.podcast]
    let attribution: MetadataAttribution? = MetadataAttribution(
        label: "Podcast discovery by Apple",
        notice: nil,
        url: URL(string: "https://podcasts.apple.com")!
    )
    let availability = MetadataProviderAvailability.available

    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func featured(_ request: MetadataDiscoveryRequest) async throws -> MetadataSearchPage {
        try validate(request, availability: availability)
        let storefront = request.countryCode?.metadataNilIfBlank?.lowercased() ?? "us"
        let response = try await httpClient.send(
            makeChartRequest(storefront: storefront, limit: request.limit)
        )
        let payload = try decode(ApplePodcastChartResponse.self, from: response.data)
        let results = payload.feed.results.map { item in
            MetadataSearchResult(
                id: MetadataResultID(provider: id, externalID: item.id),
                mediaType: .podcast,
                title: item.name,
                subtitle: item.artistName.metadataNilIfBlank,
                creators: [item.artistName].metadataDeduplicated,
                overview: nil,
                releaseYear: nil,
                coverImageURL: metadataURL(item.artworkURL100),
                thumbnailImageURL: metadataURL(item.artworkURL100),
                sourceURL: metadataURL(item.url),
                feedURL: nil,
                genres: item.genres.map(\.name).metadataDeduplicated,
                pageCount: nil,
                durationMinutes: nil,
                seasonCount: nil,
                episodeCount: nil,
                platformNames: []
            )
        }
        return MetadataSearchPage(
            results: results,
            page: 1,
            totalPages: 1,
            totalResults: results.count
        )
    }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        try validate(request)
        var queryItems = [
            URLQueryItem(name: "term", value: request.trimmedQuery),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(request.limit)),
        ]
        if let country = request.countryCode?.metadataNilIfBlank {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        if let language = request.languageCode?.metadataNilIfBlank {
            queryItems.append(URLQueryItem(name: "lang", value: language))
        }

        let response = try await httpClient.send(
            makeRequest(path: "/search", queryItems: queryItems)
        )
        let payload = try decode(ApplePodcastResponse.self, from: response.data)
        return MetadataSearchPage(
            results: payload.results.compactMap(makeResult),
            page: 1,
            totalPages: 1,
            totalResults: payload.resultCount
        )
    }

    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        try validateOwnership(of: result)
        let response = try await httpClient.send(
            makeRequest(
                path: "/lookup",
                queryItems: [
                    URLQueryItem(name: "id", value: result.id.externalID),
                    URLQueryItem(name: "entity", value: "podcast"),
                ]
            )
        )
        let payload = try decode(ApplePodcastResponse.self, from: response.data)
        let enriched = payload.results.compactMap(makeResult).first ?? result
        var facts = [MetadataFact]()
        if let count = enriched.episodeCount {
            facts.append(MetadataFact(label: "Episodes", value: String(count)))
        }
        return MetadataItemDetails(
            result: enriched,
            websiteURL: enriched.sourceURL,
            facts: facts,
            artworkURLs: [enriched.coverImageURL].compactMap(\.self)
        )
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeChartRequest(storefront: String, limit: Int) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "rss.marketingtools.apple.com"
        components.path = "/api/v2/\(storefront)/podcasts/top/\(limit)/podcasts.json"
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeResult(_ item: ApplePodcastResult) -> MetadataSearchResult? {
        guard let collectionID = item.collectionID,
              let title = item.collectionName?.metadataNilIfBlank
        else { return nil }

        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: String(collectionID)),
            mediaType: .podcast,
            title: title,
            subtitle: item.artistName?.metadataNilIfBlank,
            creators: [item.artistName].compactMap(\.self).metadataDeduplicated,
            overview: nil,
            releaseYear: metadataYear(from: item.releaseDate),
            coverImageURL: metadataURL(item.artworkURL600 ?? item.artworkURL100),
            thumbnailImageURL: metadataURL(item.artworkURL100 ?? item.artworkURL600),
            sourceURL: metadataURL(item.collectionViewURL),
            feedURL: metadataURL(item.feedURL),
            genres: (item.genres ?? [item.primaryGenreName].compactMap(\.self)).metadataDeduplicated,
            pageCount: nil,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: item.trackCount,
            platformNames: []
        )
    }
}

private nonisolated struct ApplePodcastChartResponse: Decodable, Sendable {
    let feed: ApplePodcastChartFeed
}

private nonisolated struct ApplePodcastChartFeed: Decodable, Sendable {
    let results: [ApplePodcastChartItem]
}

private nonisolated struct ApplePodcastChartItem: Decodable, Sendable {
    let artistName: String
    let id: String
    let name: String
    let artworkURL100: String?
    let genres: [ApplePodcastChartGenre]
    let url: String?

    enum CodingKeys: String, CodingKey {
        case artistName, id, name, genres, url
        case artworkURL100 = "artworkUrl100"
    }
}

private nonisolated struct ApplePodcastChartGenre: Decodable, Sendable {
    let name: String
}

private nonisolated struct ApplePodcastResponse: Decodable, Sendable {
    let resultCount: Int
    let results: [ApplePodcastResult]
}

private nonisolated struct ApplePodcastResult: Decodable, Sendable {
    let collectionID: Int?
    let collectionName: String?
    let artistName: String?
    let artworkURL100: String?
    let artworkURL600: String?
    let collectionViewURL: String?
    let feedURL: String?
    let primaryGenreName: String?
    let genres: [String]?
    let trackCount: Int?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case artistName, primaryGenreName, genres, trackCount, releaseDate
        case collectionID = "collectionId"
        case collectionName
        case artworkURL100 = "artworkUrl100"
        case artworkURL600 = "artworkUrl600"
        case collectionViewURL
        case feedURL = "feedUrl"
    }
}
