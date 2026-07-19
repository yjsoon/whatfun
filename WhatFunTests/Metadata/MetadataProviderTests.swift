import Foundation
import Testing
@testable import WhatFun

@Suite("Metadata providers")
struct MetadataProviderTests {
    @Test("TMDB maps movies and sends a bearer token")
    func tmdbMovieSearch() async throws {
        let client = try FixtureHTTPClient(data: Fixture.data(named: "tmdb-search", extension: "json"))
        let provider = TMDBMetadataProvider(httpClient: client, readAccessToken: "test-token")

        let page = try await provider.search(
            MetadataSearchRequest(query: "Fight Club", mediaType: .movie)
        )

        let result = try #require(page.results.first)
        #expect(result.id == MetadataResultID(provider: .tmdb, externalID: "550"))
        #expect(result.title == "Fight Club")
        #expect(result.releaseYear == 1999)
        #expect(result.coverImageURL?.host == "image.tmdb.org")

        let request = try #require(await client.request(at: 0))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let requestURL = try #require(request.url)
        #expect(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "query", value: "Fight Club")) == true)
    }

    @Test("TMDB discovery uses the media-specific trending feed")
    func tmdbDiscovery() async throws {
        let client = try FixtureHTTPClient(data: Fixture.data(named: "tmdb-search", extension: "json"))
        let provider = TMDBMetadataProvider(httpClient: client, readAccessToken: "test-token")

        let page = try await provider.featured(
            MetadataDiscoveryRequest(
                mediaType: .tvShow,
                languageCode: "en",
                countryCode: "SG"
            )
        )

        #expect(page.results.first?.mediaType == .tvShow)
        let request = try #require(await client.request(at: 0))
        #expect(request.url?.path == "/3/trending/tv/day")
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "language", value: "en-SG")) == true)
    }

    @Test("TMDB missing credentials fails before networking and supports manual fallback")
    func tmdbMissingCredentials() async throws {
        let client = FixtureHTTPClient(data: Data())
        let provider = TMDBMetadataProvider(
            httpClient: client,
            readAccessToken: "YOUR_TMDB_READ_ACCESS_TOKEN"
        )

        do {
            _ = try await provider.search(
                MetadataSearchRequest(query: "Arrival", mediaType: .movie)
            )
            Issue.record("Expected a missing credential error")
        } catch let error as MetadataProviderError {
            guard case .missingCredential(provider: .tmdb, _) = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
            #expect(error.supportsManualFallback)
        }
        #expect(await client.requestCount == 0)
    }

    @Test("Open Library maps a collected comic and applies the comics subject")
    func openLibraryComicSearch() async throws {
        let client = try FixtureHTTPClient(
            data: Fixture.data(named: "open-library-search", extension: "json")
        )
        let provider = OpenLibraryMetadataProvider(
            httpClient: client,
            applicationName: "WhatFun",
            contactEmail: "developer@example.com"
        )

        let page = try await provider.search(
            MetadataSearchRequest(query: "Watchmen", mediaType: .comic, limit: 10)
        )
        let result = try #require(page.results.first)
        #expect(result.mediaType == .comic)
        #expect(result.creators == ["Alan Moore", "Dave Gibbons"])
        #expect(result.pageCount == 416)
        #expect(result.genres.contains("Comics"))

        let request = try #require(await client.request(at: 0))
        let requestURL = try #require(request.url)
        let components = try #require(
            URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        )
        #expect(components.queryItems?.contains(URLQueryItem(name: "subject", value: "comics")) == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("mailto:developer@example.com") == true)
    }

    @Test("Open Library discovery requests trending works")
    func openLibraryDiscovery() async throws {
        let client = try FixtureHTTPClient(
            data: Fixture.data(named: "open-library-search", extension: "json")
        )
        let provider = OpenLibraryMetadataProvider(
            httpClient: client,
            applicationName: "WhatFun",
            contactEmail: "developer@example.com"
        )

        _ = try await provider.featured(MetadataDiscoveryRequest(mediaType: .book))

        let request = try #require(await client.request(at: 0))
        let queryItems = URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(queryItems?.contains(URLQueryItem(name: "sort", value: "trending")) == true)
        #expect(queryItems?.contains(URLQueryItem(name: "q", value: "trending_z_score:{0 TO *]")) == true)
    }

    @Test("RAWG maps games, platforms, and exposes required attribution")
    func rawgGameSearch() async throws {
        let client = try FixtureHTTPClient(data: Fixture.data(named: "rawg-search", extension: "json"))
        let provider = RAWGMetadataProvider(httpClient: client, apiKey: "test-key")

        let page = try await provider.search(
            MetadataSearchRequest(query: "Grand Theft Auto", mediaType: .game)
        )
        let result = try #require(page.results.first)
        #expect(result.id.externalID == "3498")
        #expect(result.releaseYear == 2013)
        #expect(result.platformNames == ["PlayStation 5", "PC"])
        #expect(provider.attribution?.label == "Data by RAWG")

        let request = try #require(await client.request(at: 0))
        let requestURL = try #require(request.url)
        #expect(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "key", value: "test-key")) == true)
    }

    @Test("RAWG discovery requests the most-added games")
    func rawgDiscovery() async throws {
        let client = try FixtureHTTPClient(data: Fixture.data(named: "rawg-search", extension: "json"))
        let provider = RAWGMetadataProvider(httpClient: client, apiKey: "test-key")

        _ = try await provider.featured(MetadataDiscoveryRequest(mediaType: .game))

        let request = try #require(await client.request(at: 0))
        let queryItems = URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(queryItems?.contains(URLQueryItem(name: "ordering", value: "-added")) == true)
        #expect(queryItems?.contains(where: { $0.name == "search" }) == false)
    }

    @Test("Apple podcast discovery preserves the RSS feed URL")
    func applePodcastSearch() async throws {
        let client = try FixtureHTTPClient(
            data: Fixture.data(named: "apple-podcast-search", extension: "json")
        )
        let provider = ApplePodcastMetadataProvider(httpClient: client)

        let page = try await provider.search(
            MetadataSearchRequest(
                query: "Example",
                mediaType: .podcast,
                countryCode: "SG"
            )
        )
        let result = try #require(page.results.first)
        #expect(result.title == "The Example Show")
        #expect(result.creators == ["Example Studio"])
        #expect(result.feedURL == URL(string: "https://example.com/feed.xml"))
        #expect(result.episodeCount == 42)

        let request = try #require(await client.request(at: 0))
        let requestURL = try #require(request.url)
        #expect(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "country", value: "SG")) == true)
    }

    @Test("Apple podcast discovery uses the regional top-shows chart")
    func applePodcastDiscovery() async throws {
        let client = try FixtureHTTPClient(
            data: Fixture.data(named: "apple-podcast-chart", extension: "json")
        )
        let provider = ApplePodcastMetadataProvider(httpClient: client)

        let page = try await provider.featured(
            MetadataDiscoveryRequest(mediaType: .podcast, limit: 10, countryCode: "SG")
        )

        let result = try #require(page.results.first)
        #expect(result.title == "The Example Show")
        #expect(result.genres == ["Technology", "Education"])
        let request = try #require(await client.request(at: 0))
        #expect(request.url?.path == "/api/v2/sg/podcasts/top/10/podcasts.json")
    }
}

private actor FixtureHTTPClient: HTTPClient {
    private let response: HTTPResponse
    private var requests = [URLRequest]()

    init(data: Data, statusCode: Int = 200, headers: [String: String] = [:]) {
        response = HTTPResponse(data: data, statusCode: statusCode, headers: headers)
    }

    var requestCount: Int { requests.count }

    func request(at index: Int) -> URLRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }

    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse {
        requests.append(request)
        return try response.validated(using: statusPolicy)
    }
}

private enum Fixture {
    static func data(named name: String, extension fileExtension: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
        return try Data(contentsOf: directory.appendingPathComponent(name).appendingPathExtension(fileExtension))
    }
}
