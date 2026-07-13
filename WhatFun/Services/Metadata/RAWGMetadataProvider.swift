import Foundation

nonisolated struct RAWGMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.rawg
    let supportedMediaTypes: Set<MetadataMediaType> = [.game]
    let attribution: MetadataAttribution? = MetadataAttribution(
        label: "Data by RAWG",
        notice: nil,
        url: URL(string: "https://rawg.io")!
    )

    private let httpClient: any HTTPClient
    private let credential: MetadataCredentialSource

    var availability: MetadataProviderAvailability {
        let apiKey = credential.currentToken()
        if apiKey.metadataNilIfBlank == nil || apiKey.hasPrefix("YOUR_") {
            return .credentialRequired(
                instructions: "Add a RAWG API key in Settings → Metadata.",
                setupURL: URL(string: "https://rawg.io/apidocs")
            )
        } else {
            return .available
        }
    }

    init(httpClient: any HTTPClient, credential: MetadataCredentialSource) {
        self.httpClient = httpClient
        self.credential = credential
    }

    init(httpClient: any HTTPClient, apiKey: String) {
        self.init(httpClient: httpClient, credential: .constant(apiKey))
    }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        try validate(request)
        let response = try await httpClient.send(
            makeRequest(
                path: "/api/games",
                queryItems: [
                    URLQueryItem(name: "key", value: credential.currentToken()),
                    URLQueryItem(name: "search", value: request.trimmedQuery),
                    URLQueryItem(name: "search_precise", value: "true"),
                    URLQueryItem(name: "page", value: String(request.page)),
                    URLQueryItem(name: "page_size", value: String(request.limit)),
                ]
            )
        )
        let payload = try decode(RAWGSearchResponse.self, from: response.data)
        let totalPages = max(1, Int(ceil(Double(payload.count) / Double(request.limit))))
        return MetadataSearchPage(
            results: payload.results.map(makeResult),
            page: request.page,
            totalPages: totalPages,
            totalResults: payload.count
        )
    }

    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        try validateOwnership(of: result)
        let response = try await httpClient.send(
            makeRequest(
                path: "/api/games/\(result.id.externalID)",
                queryItems: [URLQueryItem(name: "key", value: credential.currentToken())]
            )
        )
        let payload = try decode(RAWGDetailsResponse.self, from: response.data)
        let platforms = (payload.platforms ?? []).compactMap(\.platform?.name).metadataDeduplicated
        let genres = (payload.genres ?? []).compactMap(\.name).metadataDeduplicated
        let creators = (payload.developers ?? []).compactMap(\.name).metadataDeduplicated
        let enrichedResult = MetadataSearchResult(
            id: result.id,
            mediaType: .game,
            title: payload.name?.metadataNilIfBlank ?? result.title,
            subtitle: result.subtitle,
            creators: creators.isEmpty ? result.creators : creators,
            overview: payload.descriptionRaw?.metadataNilIfBlank ?? result.overview,
            releaseYear: metadataYear(from: payload.released) ?? result.releaseYear,
            coverImageURL: metadataURL(payload.backgroundImage) ?? result.coverImageURL,
            thumbnailImageURL: metadataURL(payload.backgroundImage) ?? result.thumbnailImageURL,
            sourceURL: result.sourceURL,
            feedURL: nil,
            genres: genres.isEmpty ? result.genres : genres,
            pageCount: nil,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: platforms.isEmpty ? result.platformNames : platforms
        )

        var facts = [MetadataFact]()
        if let playtime = payload.playtime, playtime > 0 {
            facts.append(MetadataFact(label: "Typical playtime", value: "\(playtime) hr"))
        }
        if let esrb = payload.esrbRating?.name?.metadataNilIfBlank {
            facts.append(MetadataFact(label: "Age rating", value: esrb))
        }
        if !enrichedResult.platformNames.isEmpty {
            facts.append(
                MetadataFact(label: "Platforms", value: enrichedResult.platformNames.joined(separator: ", "))
            )
        }

        return MetadataItemDetails(
            result: enrichedResult,
            websiteURL: metadataURL(payload.website),
            facts: facts,
            artworkURLs: [enrichedResult.coverImageURL].compactMap(\.self)
        )
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.rawg.io"
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

    private func makeResult(_ item: RAWGSearchItem) -> MetadataSearchResult {
        let platforms = (item.platforms ?? []).compactMap(\.platform?.name).metadataDeduplicated
        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: String(item.id)),
            mediaType: .game,
            title: item.name?.metadataNilIfBlank ?? "Untitled",
            subtitle: nil,
            creators: [],
            overview: nil,
            releaseYear: metadataYear(from: item.released),
            coverImageURL: metadataURL(item.backgroundImage),
            thumbnailImageURL: metadataURL(item.backgroundImage),
            sourceURL: URL(string: "https://rawg.io/games/\(item.slug ?? String(item.id))"),
            feedURL: nil,
            genres: (item.genres ?? []).compactMap(\.name).metadataDeduplicated,
            pageCount: nil,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: platforms
        )
    }
}

private nonisolated struct RAWGSearchResponse: Decodable, Sendable {
    let count: Int
    let results: [RAWGSearchItem]
}

private nonisolated struct RAWGSearchItem: Decodable, Sendable {
    let id: Int
    let slug: String?
    let name: String?
    let released: String?
    let backgroundImage: String?
    let genres: [RAWGNamedValue]?
    let platforms: [RAWGPlatformContainer]?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, released, genres, platforms
        case backgroundImage = "background_image"
    }
}

private nonisolated struct RAWGDetailsResponse: Decodable, Sendable {
    let name: String?
    let descriptionRaw: String?
    let released: String?
    let backgroundImage: String?
    let website: String?
    let metacriticURL: String?
    let playtime: Int?
    let genres: [RAWGNamedValue]?
    let platforms: [RAWGPlatformContainer]?
    let developers: [RAWGNamedValue]?
    let esrbRating: RAWGNamedValue?

    enum CodingKeys: String, CodingKey {
        case name, released, website, playtime, genres, platforms, developers
        case descriptionRaw = "description_raw"
        case backgroundImage = "background_image"
        case metacriticURL = "metacritic_url"
        case esrbRating = "esrb_rating"
    }
}

private nonisolated struct RAWGNamedValue: Decodable, Sendable {
    let name: String?
}

private nonisolated struct RAWGPlatformContainer: Decodable, Sendable {
    let platform: RAWGNamedValue?
}
