import Foundation

nonisolated struct OpenLibraryMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.openLibrary
    let supportedMediaTypes: Set<MetadataMediaType> = [.book, .comic]
    let attribution: MetadataAttribution? = MetadataAttribution(
        label: "Data from Open Library",
        notice: nil,
        url: URL(string: "https://openlibrary.org")!
    )
    let availability = MetadataProviderAvailability.available

    private let httpClient: any HTTPClient
    private let applicationName: String
    private let contactEmail: String?

    init(
        httpClient: any HTTPClient,
        applicationName: String,
        contactEmail: String?
    ) {
        self.httpClient = httpClient
        self.applicationName = applicationName.metadataNilIfBlank ?? "WhatFun"
        if let contactEmail = contactEmail?.metadataNilIfBlank,
           !contactEmail.hasPrefix("YOUR_")
        {
            self.contactEmail = contactEmail
        } else {
            self.contactEmail = nil
        }
    }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        try validate(request)
        var queryItems = [
            URLQueryItem(name: "q", value: request.trimmedQuery),
            URLQueryItem(name: "page", value: String(request.page)),
            URLQueryItem(name: "limit", value: String(request.limit)),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,subject"
            ),
        ]
        if request.mediaType == .comic {
            // Open Library is intentionally shared by books and comics. This
            // favors series and collected editions rather than issue-level data.
            queryItems.append(URLQueryItem(name: "subject", value: "comics"))
        }

        let response = try await httpClient.send(
            makeRequest(path: "/search.json", queryItems: queryItems)
        )
        let payload = try decode(OpenLibrarySearchResponse.self, from: response.data)
        let totalPages = max(1, Int(ceil(Double(payload.numFound) / Double(request.limit))))
        return MetadataSearchPage(
            results: payload.docs.compactMap { makeResult(from: $0, mediaType: request.mediaType) },
            page: request.page,
            totalPages: totalPages,
            totalResults: payload.numFound
        )
    }

    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        try validateOwnership(of: result)
        let workID = result.id.externalID
            .replacingOccurrences(of: "/works/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let response = try await httpClient.send(
            makeRequest(path: "/works/\(workID).json", queryItems: [])
        )
        let payload = try decode(OpenLibraryWorkResponse.self, from: response.data)
        let coverID = payload.covers?.first
        let allGenres = payload.subjects ?? result.genres
        let genres = Array(allGenres[0 ..< min(20, allGenres.count)]).metadataDeduplicated
        let enrichedResult = MetadataSearchResult(
            id: result.id,
            mediaType: result.mediaType,
            title: payload.title?.metadataNilIfBlank ?? result.title,
            subtitle: result.subtitle,
            creators: result.creators,
            overview: payload.description?.value.metadataNilIfBlank ?? result.overview,
            releaseYear: result.releaseYear,
            coverImageURL: coverID.flatMap { coverURL(id: $0, size: "L") } ?? result.coverImageURL,
            thumbnailImageURL: coverID.flatMap { coverURL(id: $0, size: "M") } ?? result.thumbnailImageURL,
            sourceURL: URL(string: "https://openlibrary.org/works/\(workID)"),
            feedURL: nil,
            genres: genres,
            pageCount: result.pageCount,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )

        var facts = [MetadataFact]()
        if let pages = result.pageCount {
            facts.append(MetadataFact(label: "Pages", value: String(pages)))
        }

        return MetadataItemDetails(
            result: enrichedResult,
            websiteURL: enrichedResult.sourceURL,
            facts: facts,
            artworkURLs: [enrichedResult.coverImageURL].compactMap(\.self)
        )
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openlibrary.org"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let identity = contactEmail.map { "\(applicationName)/1.0 (mailto:\($0))" }
            ?? "\(applicationName)/1.0"
        request.setValue(identity, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeResult(
        from document: OpenLibrarySearchDocument,
        mediaType: MetadataMediaType
    ) -> MetadataSearchResult? {
        guard let key = document.key?.metadataNilIfBlank,
              let title = document.title?.metadataNilIfBlank
        else { return nil }
        let workID = key.replacingOccurrences(of: "/works/", with: "")
        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: workID),
            mediaType: mediaType,
            title: title,
            subtitle: nil,
            creators: (document.authorName ?? []).metadataDeduplicated,
            overview: nil,
            releaseYear: document.firstPublishYear,
            coverImageURL: document.coverID.flatMap { coverURL(id: $0, size: "L") },
            thumbnailImageURL: document.coverID.flatMap { coverURL(id: $0, size: "M") },
            sourceURL: URL(string: "https://openlibrary.org/works/\(workID)"),
            feedURL: nil,
            genres: limitedSubjects(document.subjects ?? []),
            pageCount: document.pageCount,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )
    }

    private func coverURL(id: Int, size: String) -> URL? {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-\(size).jpg")
    }

    private func limitedSubjects(_ subjects: [String]) -> [String] {
        Array(subjects[0 ..< min(20, subjects.count)]).metadataDeduplicated
    }
}

private nonisolated struct OpenLibrarySearchResponse: Decodable, Sendable {
    let numFound: Int
    let docs: [OpenLibrarySearchDocument]

    enum CodingKeys: String, CodingKey {
        case numFound
        case docs
    }
}

private nonisolated struct OpenLibrarySearchDocument: Decodable, Sendable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverID: Int?
    let pageCount: Int?
    let subjects: [String]?

    enum CodingKeys: String, CodingKey {
        case key, title, subject
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverID = "cover_i"
        case pageCount = "number_of_pages_median"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        authorName = try container.decodeIfPresent([String].self, forKey: .authorName)
        firstPublishYear = try container.decodeIfPresent(Int.self, forKey: .firstPublishYear)
        coverID = try container.decodeIfPresent(Int.self, forKey: .coverID)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        subjects = try container.decodeIfPresent([String].self, forKey: .subject)
    }
}

private nonisolated struct OpenLibraryWorkResponse: Decodable, Sendable {
    let title: String?
    let description: OpenLibraryDescription?
    let subjects: [String]?
    let covers: [Int]?
}

private nonisolated struct OpenLibraryDescription: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            value = string
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }
}
