import Foundation
import Testing
@testable import WhatFun

@Suite("Podcast RSS")
struct PodcastFeedTests {
    @Test("RSS parser maps episode progress metadata")
    func parseRSS() throws {
        let data = try podcastFixture(named: "podcast-feed", extension: "xml")
        let feed = try PodcastFeedParser().parse(data)

        #expect(feed.title == "The Example Show")
        #expect(feed.author == "Example Studio")
        #expect(feed.languageCode == "en-SG")
        #expect(feed.episodes.count == 1)

        let episode = try #require(feed.episodes.first)
        #expect(episode.id == "episode-42")
        #expect(episode.title == "Small Histories")
        #expect(episode.summary == "Notes from the week.")
        #expect(episode.durationSeconds == 3723)
        #expect(episode.seasonNumber == 3)
        #expect(episode.episodeNumber == 42)
        #expect(episode.isExplicit == false)
    }

    @Test("RSS refresh sends conditional headers and handles not modified")
    func conditionalRefresh() async throws {
        let client = FeedFixtureHTTPClient(
            response: HTTPResponse(
                data: Data(),
                statusCode: 304,
                headers: ["ETag": "new-tag"]
            )
        )
        let feedClient = RSSPodcastFeedClient(httpClient: client)
        let result = try await feedClient.refresh(
            PodcastFeedRefreshRequest(
                feedURL: URL(string: "https://private.example.com/feed/token")!,
                eTag: "old-tag",
                lastModified: "Sat, 20 Jun 2026 09:00:00 GMT"
            )
        )

        guard case let .notModified(eTag, lastModified) = result else {
            Issue.record("Expected an unchanged feed")
            return
        }
        #expect(eTag == "new-tag")
        #expect(lastModified == "Sat, 20 Jun 2026 09:00:00 GMT")

        let request = try #require(await client.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "old-tag")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Sat, 20 Jun 2026 09:00:00 GMT")
    }
}

private actor FeedFixtureHTTPClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse {
        lastRequest = request
        return try response.validated(using: statusPolicy)
    }
}

private func podcastFixture(named name: String, extension fileExtension: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures", directoryHint: .isDirectory)
    return try Data(contentsOf: directory.appendingPathComponent(name).appendingPathExtension(fileExtension))
}
