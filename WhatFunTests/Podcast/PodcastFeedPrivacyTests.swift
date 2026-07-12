import Foundation
import Testing
@testable import WhatFun

@Suite("Podcast feed privacy classification")
struct PodcastFeedPrivacyTests {
    @Test("Untrusted feeds are public only when no credential is embedded", arguments: [
        // rawURL, expected private
        ("https://feeds.megaphone.fm/show", false),
        ("https://public.example.com/feed.xml", false),
        ("http://plain.example.com/rss", false),
        ("https://anchor.fm/s/12ab34/podcast/rss", false),
        ("https://user:pass@example.com/feed.xml", true),
        ("https://example.com/feed.xml?token=secret", true),
        ("https://example.com/feed.xml?apikey=abc", true),
        ("https://example-premium.com/premium/tok_abc123/feed.rss", true),
        ("https://premium.example.com/secret-9f8e7d6c5b/feed", true),
        ("https://members.example.com/rss/a1B2c3D4e5F6g7H8i9J0/feed.xml", true),
    ])
    func classifiesUntrustedFeeds(rawURL: String, expectedPrivate: Bool) throws {
        let url = try #require(URL(string: rawURL))
        #expect(PodcastFeedPrivacy.classify(untrustedFeed: url).isPrivate == expectedPrivate)
    }

    @Test("Trusted classification trusts only Apple directory HTTPS feeds", arguments: [
        // rawURL, provider, expected privacy
        ("https://feeds.example.com/show.xml", MetadataProviderID.applePodcasts, PodcastFeedPrivacy.publicDirectoryFeed),
        ("http://feeds.example.com/show.xml", .applePodcasts, .privateCredential),
        ("https://feeds.example.com/show.xml?token=x", .applePodcasts, .privateCredential),
        ("https://feeds.example.com/show.xml", .rss, .privateCredential),
        ("https://feeds.example.com/show.xml", .tmdb, .privateCredential),
    ])
    func classifiesTrustedFeeds(
        rawURL: String,
        provider: MetadataProviderID,
        expected: PodcastFeedPrivacy
    ) throws {
        let url = try #require(URL(string: rawURL))
        #expect(PodcastFeedPrivacy.classify(url, discoveredBy: provider) == expected)
    }

    @Test("Path segments are judged as credentials only when high-entropy or labelled", arguments: [
        // segment, expected credential-like
        ("show", false),
        ("feed.xml", false),
        ("episode-42", false),
        ("the-daily-show", false),
        ("12ab34cd", false),
        ("tok_abc123", true),
        ("secret-abcd", true),
        ("apikey_abcdef", true),
        ("a1B2c3D4e5F6g7H8i9J0", true),
        ("deadbeef0123456789abcdef", true),
        ("this-is-a-long-slug-name", false),
    ])
    func detectsCredentialSegments(segment: String, expected: Bool) {
        #expect(PodcastFeedPrivacy.isCredentialLikePathSegment(segment) == expected)
    }

    @Test("A validated feed URL requires an http(s) scheme and a host")
    func validatesFeedURLs() {
        #expect(PodcastFeedPrivacy.validatedFeedURL(from: "https://example.com/f") != nil)
        #expect(PodcastFeedPrivacy.validatedFeedURL(from: "http://example.com/f") != nil)
        #expect(PodcastFeedPrivacy.validatedFeedURL(from: "ftp://example.com/f") == nil)
        #expect(PodcastFeedPrivacy.validatedFeedURL(from: "not a url") == nil)
        #expect(PodcastFeedPrivacy.validatedFeedURL(from: "https:///nohost") == nil)
    }
}
