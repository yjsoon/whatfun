import Foundation

nonisolated struct TMDBMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.tmdb
    let supportedMediaTypes: Set<MetadataMediaType> = [.movie, .tvShow]
    let attribution: MetadataAttribution? = MetadataAttribution(
        label: "Metadata by TMDB",
        notice: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
        url: URL(string: "https://www.themoviedb.org")!
    )

    private let httpClient: any HTTPClient
    private let credential: MetadataCredentialSource

    var availability: MetadataProviderAvailability {
        availability(for: credential.currentToken())
    }

    private func availability(
        for resolution: MetadataCredentialResolution
    ) -> MetadataProviderAvailability {
        guard let readAccessToken = resolution.token else {
            return .credentialRequired(
                instructions: "WhatFun could not read your saved TMDB key from the Keychain. Unlock your device, then try again.",
                setupURL: nil
            )
        }
        if readAccessToken.metadataNilIfBlank == nil || readAccessToken.hasPrefix("YOUR_") {
            return .credentialRequired(
                instructions: "Add a TMDB read-access token in Settings → Metadata.",
                setupURL: URL(string: "https://www.themoviedb.org/settings/api")
            )
        } else {
            return .available
        }
    }

    init(httpClient: any HTTPClient, credential: MetadataCredentialSource) {
        self.httpClient = httpClient
        self.credential = credential
    }

    init(httpClient: any HTTPClient, readAccessToken: String) {
        self.init(httpClient: httpClient, credential: .constant(readAccessToken))
    }

    @concurrent
    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        let resolution = credential.currentToken()
        try validate(request, availability: availability(for: resolution))
        let readAccessToken = try requireToken(resolution)
        let path = request.mediaType == .movie ? "/3/search/movie" : "/3/search/tv"
        var queryItems = [
            URLQueryItem(name: "query", value: request.trimmedQuery),
            URLQueryItem(name: "page", value: String(request.page)),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        if let languageCode = request.languageCode?.metadataNilIfBlank {
            queryItems.append(URLQueryItem(name: "language", value: languageCode))
        }

        let response = try await httpClient.send(
            makeRequest(path: path, queryItems: queryItems, readAccessToken: readAccessToken)
        )
        let payload = try decode(TMDBSearchResponse.self, from: response.data)
        let results = payload.results.map { item in
            makeResult(from: item, mediaType: request.mediaType)
        }

        return MetadataSearchPage(
            results: results,
            page: payload.page,
            totalPages: payload.totalPages,
            totalResults: payload.totalResults
        )
    }

    @concurrent
    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        let resolution = credential.currentToken()
        try validateOwnership(of: result, availability: availability(for: resolution))
        let readAccessToken = try requireToken(resolution)
        let segment = result.mediaType == .movie ? "movie" : "tv"
        let queryItems = [URLQueryItem(name: "append_to_response", value: "credits")]
        let response = try await httpClient.send(
            makeRequest(
                path: "/3/\(segment)/\(result.id.externalID)",
                queryItems: queryItems,
                readAccessToken: readAccessToken
            )
        )
        let payload = try decode(TMDBDetailsResponse.self, from: response.data)

        let title = (payload.title ?? payload.name)?.metadataNilIfBlank ?? result.title
        let originalTitle = (payload.originalTitle ?? payload.originalName)?.metadataNilIfBlank
        let creators: [String] = if result.mediaType == .movie {
            (payload.credits?.crew ?? [])
                .filter { $0.job == "Director" }
                .compactMap(\.name)
                .metadataDeduplicated
        } else {
            (payload.createdBy ?? []).compactMap(\.name).metadataDeduplicated
        }

        let poster = tmdbImageURL(path: payload.posterPath, size: "w780") ?? result.coverImageURL
        let thumbnail = tmdbImageURL(path: payload.posterPath, size: "w342") ?? result.thumbnailImageURL
        let duration = payload.runtime ?? payload.episodeRunTime?.first ?? result.durationMinutes
        let genres = (payload.genres ?? []).compactMap(\.name).metadataDeduplicated
        let releaseDate = payload.releaseDate ?? payload.firstAirDate
        let enrichedResult = MetadataSearchResult(
            id: result.id,
            mediaType: result.mediaType,
            title: title,
            subtitle: originalTitle == title ? nil : originalTitle,
            creators: creators.isEmpty ? result.creators : creators,
            overview: payload.overview?.metadataNilIfBlank ?? result.overview,
            releaseYear: metadataYear(from: releaseDate) ?? result.releaseYear,
            coverImageURL: poster,
            thumbnailImageURL: thumbnail,
            sourceURL: result.sourceURL,
            feedURL: nil,
            genres: genres.isEmpty ? result.genres : genres,
            pageCount: nil,
            durationMinutes: duration,
            seasonCount: payload.numberOfSeasons ?? result.seasonCount,
            episodeCount: payload.numberOfEpisodes ?? result.episodeCount,
            platformNames: []
        )

        var facts = [MetadataFact]()
        if let status = payload.status?.metadataNilIfBlank {
            facts.append(MetadataFact(label: "Release status", value: status))
        }
        if let duration {
            facts.append(MetadataFact(label: "Runtime", value: "\(duration) min"))
        }
        if let seasons = payload.numberOfSeasons {
            facts.append(MetadataFact(label: "Seasons", value: String(seasons)))
        }
        if let episodes = payload.numberOfEpisodes {
            facts.append(MetadataFact(label: "Episodes", value: String(episodes)))
        }

        return MetadataItemDetails(
            result: enrichedResult,
            websiteURL: metadataURL(payload.homepage),
            facts: facts,
            artworkURLs: [poster, tmdbImageURL(path: payload.backdropPath, size: "original")].compactMap(\.self)
        )
    }

    /// The resolution is made once per operation, so a missing token here means
    /// validation already threw. Kept as a guard rather than a force-unwrap.
    private func requireToken(_ resolution: MetadataCredentialResolution) throws -> String {
        guard let token = resolution.token else {
            throw MetadataProviderError.missingCredential(
                provider: id,
                instructions: "WhatFun could not read your saved TMDB key from the Keychain."
            )
        }
        return token
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem],
        readAccessToken: String
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.themoviedb.org"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeResult(
        from item: TMDBSearchItem,
        mediaType: MetadataMediaType
    ) -> MetadataSearchResult {
        let title = (item.title ?? item.name)?.metadataNilIfBlank ?? "Untitled"
        let originalTitle = (item.originalTitle ?? item.originalName)?.metadataNilIfBlank
        let externalID = String(item.id)
        let sourceSegment = mediaType == .movie ? "movie" : "tv"
        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: externalID),
            mediaType: mediaType,
            title: title,
            subtitle: originalTitle == title ? nil : originalTitle,
            creators: [],
            overview: item.overview?.metadataNilIfBlank,
            releaseYear: metadataYear(from: item.releaseDate ?? item.firstAirDate),
            coverImageURL: tmdbImageURL(path: item.posterPath, size: "w780"),
            thumbnailImageURL: tmdbImageURL(path: item.posterPath, size: "w342"),
            sourceURL: URL(string: "https://www.themoviedb.org/\(sourceSegment)/\(externalID)"),
            feedURL: nil,
            genres: [],
            pageCount: nil,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )
    }

    private func tmdbImageURL(path: String?, size: String) -> URL? {
        guard let path = path?.metadataNilIfBlank else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

private nonisolated struct TMDBSearchResponse: Decodable, Sendable {
    let page: Int
    let results: [TMDBSearchItem]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

private nonisolated struct TMDBSearchItem: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case originalTitle = "original_title"
        case originalName = "original_name"
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

private nonisolated struct TMDBDetailsResponse: Decodable, Sendable {
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let status: String?
    let homepage: String?
    let genres: [TMDBNamedValue]?
    let createdBy: [TMDBNamedValue]?
    let credits: TMDBCredits?

    enum CodingKeys: String, CodingKey {
        case title, name, overview, runtime, status, homepage, genres, credits
        case originalTitle = "original_title"
        case originalName = "original_name"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case createdBy = "created_by"
    }
}

private nonisolated struct TMDBNamedValue: Decodable, Sendable {
    let name: String?
}

private nonisolated struct TMDBCredits: Decodable, Sendable {
    let crew: [TMDBCrewMember]?
}

private nonisolated struct TMDBCrewMember: Decodable, Sendable {
    let job: String?
    let name: String?
}
