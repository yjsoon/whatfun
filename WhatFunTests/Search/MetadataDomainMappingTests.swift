import Foundation
import Testing
@testable import WhatFun

@Suite("Metadata domain mapping")
struct MetadataDomainMappingTests {
    @Test("Every searchable metadata type maps to its canonical media kind")
    func mapsMediaKinds() {
        let pairs: [(MetadataMediaType, MediaKind)] = [
            (.book, .book),
            (.comic, .comic),
            (.movie, .movie),
            (.tvShow, .tvShow),
            (.game, .game),
            (.podcast, .podcast),
        ]

        for (metadataType, mediaKind) in pairs {
            #expect(MetadataDomainMapper.mediaKind(for: metadataType) == mediaKind)
            #expect(MetadataDomainMapper.metadataType(for: mediaKind) == metadataType)
        }
        #expect(MetadataDomainMapper.metadataType(for: .unknown) == nil)
    }

    @Test("Details enrich matching search identity and facets are stable and deduplicated")
    func mapsEnrichedDetails() throws {
        let search = makeResult(
            provider: .rawg,
            externalID: "3498",
            mediaType: .game,
            title: "GTA V",
            creators: [],
            genres: ["Action"],
            platforms: ["PC"]
        )
        let enriched = makeResult(
            provider: .rawg,
            externalID: "3498",
            mediaType: .game,
            title: "Grand Theft Auto V",
            creators: ["Rockstar North", "rockstar north"],
            genres: ["Action", "action", "Adventure"],
            platforms: ["PC", "PlayStation 5", "pc"],
            durationMinutes: 90
        )
        let details = MetadataItemDetails(
            result: enriched,
            websiteURL: nil,
            facts: [],
            artworkURLs: []
        )

        let draft = MetadataDomainMapper.makeDraft(result: search, details: details)

        #expect(draft.title == "Grand Theft Auto V")
        #expect(draft.creators == ["Rockstar North"])
        #expect(draft.runtimeSeconds == 5400)
        #expect(
            draft.facets == [
                MetadataFacetDraft(kind: .genre, name: "Action"),
                MetadataFacetDraft(kind: .genre, name: "Adventure"),
                MetadataFacetDraft(kind: .platform, name: "PC"),
                MetadataFacetDraft(kind: .platform, name: "PlayStation 5"),
            ]
        )
    }

    @Test("A detail payload with another identity cannot replace the selected result")
    func ignoresMismatchedDetails() {
        let selected = makeResult(
            provider: .tmdb,
            externalID: "1",
            mediaType: .movie,
            title: "Selected"
        )
        let other = makeResult(
            provider: .tmdb,
            externalID: "2",
            mediaType: .movie,
            title: "Other"
        )
        let details = MetadataItemDetails(
            result: other,
            websiteURL: nil,
            facts: [],
            artworkURLs: []
        )

        let draft = MetadataDomainMapper.makeDraft(result: selected, details: details)
        #expect(draft.title == "Selected")
        #expect(draft.externalID == "1")
    }

    @Test("Provider duplicate identity matching is case and whitespace tolerant")
    func matchesDuplicateIdentity() {
        let key = MetadataDuplicateKey(
            provider: .openLibrary,
            mediaType: .comic,
            externalID: " OL45883W "
        )

        #expect(key.providerRaw == "openLibrary")
        #expect(key.recordKindRaw == "comic")
        #expect(key.externalID == "OL45883W")
        #expect(
            key.matches(
                providerRaw: " OPENLIBRARY ",
                recordKindRaw: "COMIC",
                externalID: "ol45883w"
            )
        )
        #expect(
            !key.matches(providerRaw: "tmdb", recordKindRaw: "comic", externalID: "OL45883W")
        )
        #expect(
            !key.matches(providerRaw: "openLibrary", recordKindRaw: "book", externalID: "OL45883W")
        )
        #expect(
            !key.matches(providerRaw: "openLibrary", recordKindRaw: "comic", externalID: "OL999W")
        )
    }

    @Test("Only non-secret Apple directory feeds are persisted as public URLs")
    func classifiesPodcastFeeds() throws {
        let publicURL = try #require(URL(string: "https://feeds.example.com/show.xml"))
        let tokenURL = try #require(URL(string: "https://feeds.example.com/show.xml?token=secret"))
        let privateURL = try #require(URL(string: "https://premium.example.com/member/abc123.xml"))

        #expect(PodcastFeedPrivacy.classify(publicURL, discoveredBy: .applePodcasts) == .publicDirectoryFeed)
        #expect(PodcastFeedPrivacy.classify(tokenURL, discoveredBy: .applePodcasts) == .privateCredential)
        #expect(PodcastFeedPrivacy.classify(privateURL, discoveredBy: .rss) == .privateCredential)

        let result = makeResult(
            provider: .applePodcasts,
            externalID: "42",
            mediaType: .podcast,
            title: "A Show",
            feedURL: tokenURL
        )
        let draft = MetadataDomainMapper.makeDraft(result: result)
        #expect(draft.podcastFeed?.privacy == .privateCredential)
        #expect(draft.podcastFeed?.opaqueID.contains("secret") == false)
    }
}

private func makeResult(
    provider: MetadataProviderID,
    externalID: String,
    mediaType: MetadataMediaType,
    title: String,
    creators: [String] = [],
    genres: [String] = [],
    platforms: [String] = [],
    durationMinutes: Int? = nil,
    feedURL: URL? = nil
) -> MetadataSearchResult {
    MetadataSearchResult(
        id: MetadataResultID(provider: provider, externalID: externalID),
        mediaType: mediaType,
        title: title,
        subtitle: nil,
        creators: creators,
        overview: nil,
        releaseYear: nil,
        coverImageURL: nil,
        thumbnailImageURL: nil,
        sourceURL: nil,
        feedURL: feedURL,
        genres: genres,
        pageCount: nil,
        durationMinutes: durationMinutes,
        seasonCount: nil,
        episodeCount: nil,
        platformNames: platforms
    )
}
