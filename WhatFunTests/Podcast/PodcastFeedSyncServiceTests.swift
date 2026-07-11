import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("Podcast feed sync", .serialized)
@MainActor
struct PodcastFeedSyncServiceTests {
    @Test("Refreshing a feed deduplicates episodes by GUID")
    func deduplicatesEpisodes() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .podcast, title: "Example")
        try ActivityService(context: context).register(item)
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "feed",
            externalID: "example",
            canonicalURLString: "https://example.com/feed.xml"
        )
        reference.isActiveFeed = true
        context.insert(reference)
        item.externalReferences = [reference]
        try context.save()

        let refresher = StubPodcastRefresher(result: .updated(
            feed: sampleFeed,
            eTag: "v1",
            lastModified: nil
        ))
        let service = PodcastFeedSyncService(
            context: context,
            credentials: InMemoryCredentialStore(),
            refresher: refresher
        )

        let first = try await service.refresh(item)
        let second = try await service.refresh(item)

        #expect(first.addedEpisodes == 2)
        #expect(second.addedEpisodes == 0)
        #expect(second.updatedEpisodes == 2)
        #expect((item.units ?? []).filter { $0.unitKind == .podcastEpisode }.count == 2)
        #expect(reference.etag == "v1")
    }

    @Test("Private feed URLs and URL-shaped GUIDs stay out of SwiftData")
    func redactsPrivateFeedDetails() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let credentials = InMemoryCredentialStore()
        let item = LibraryItem(mediaKind: .podcast, title: "Private")
        try ActivityService(context: context).register(item)
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "feed",
            externalID: "private.example"
        )
        reference.isActiveFeed = true
        reference.isPrivateFeed = true
        reference.credentialKeychainID = "private-feed"
        context.insert(reference)
        item.externalReferences = [reference]
        await credentials.set("https://private.example/feed?token=secret", for: "private-feed")

        let privateEpisode = PodcastFeedEpisode(
            id: "https://private.example/audio?token=secret",
            title: "Private Episode",
            summary: nil,
            publishedAt: nil,
            durationSeconds: 600,
            webpageURL: URL(string: "https://private.example/episode?token=secret"),
            enclosureURL: nil,
            imageURL: URL(string: "https://private.example/art?token=secret"),
            seasonNumber: nil,
            episodeNumber: nil,
            episodeType: nil,
            isExplicit: nil
        )
        let feed = PodcastFeed(
            title: "Private",
            author: nil,
            summary: nil,
            websiteURL: nil,
            imageURL: nil,
            languageCode: nil,
            isExplicit: nil,
            lastUpdatedAt: nil,
            episodes: [privateEpisode]
        )
        let service = PodcastFeedSyncService(
            context: context,
            credentials: credentials,
            refresher: StubPodcastRefresher(result: .updated(
                feed: feed,
                eTag: nil,
                lastModified: nil
            ))
        )

        _ = try await service.refresh(item)
        let unit = try #require(item.units?.first)

        #expect(unit.episodeGUID == nil)
        #expect(unit.canonicalURLString == nil)
        #expect(unit.artworkAssets?.isEmpty != false)
        #expect(reference.canonicalURLString == nil)
    }

    private var sampleFeed: PodcastFeed {
        PodcastFeed(
            title: "Example",
            author: "Example Studio",
            summary: "A show",
            websiteURL: URL(string: "https://example.com"),
            imageURL: nil,
            languageCode: "en",
            isExplicit: false,
            lastUpdatedAt: nil,
            episodes: [
                episode(id: "episode-1", title: "One", number: 1),
                episode(id: "episode-2", title: "Two", number: 2),
            ]
        )
    }

    private func episode(id: String, title: String, number: Int) -> PodcastFeedEpisode {
        PodcastFeedEpisode(
            id: id,
            title: title,
            summary: nil,
            publishedAt: Date(timeIntervalSince1970: Double(number * 1_000)),
            durationSeconds: 1_800,
            webpageURL: URL(string: "https://example.com/\(id)"),
            enclosureURL: nil,
            imageURL: nil,
            seasonNumber: nil,
            episodeNumber: number,
            episodeType: "full",
            isExplicit: false
        )
    }
}

private nonisolated struct StubPodcastRefresher: PodcastFeedRefreshing {
    let result: PodcastFeedRefreshResult

    func refresh(_: PodcastFeedRefreshRequest) async throws -> PodcastFeedRefreshResult {
        result
    }
}

