import Foundation
import Testing
@testable import WhatFun

@Suite("Podcast feed privacy classification")
struct PodcastFeedPrivacyTests {
    @Test("Untrusted feeds are public only when no credential is embedded", arguments: [
        // rawURL, expected private
        // Ordinary public shapes stay public.
        ("https://feeds.megaphone.fm/show", false),
        ("https://public.example.com/feed.xml", false),
        ("http://plain.example.com/rss", false),
        ("https://anchor.fm/s/12ab34/podcast/rss", false),
        ("https://feeds.transistor.fm/the-daily-tech-show", false),
        ("https://feeds.buzzsprout.com/123456.rss", false),
        ("https://feeds.libsyn.com/123456789012/rss", false),
        // Public-directory shapes whose opaque IDs are show IDs, not secrets.
        ("https://feeds.acast.com/public/shows/5f6a7b8c9d0e1f2a3b4c5d6e", false),
        // Long human slugs, even with a year in them, are not tokens.
        ("https://example.com/best-of-2024-holiday-special/feed.rss", false),
        // Short human values under a weak credential name are not secrets.
        ("https://example.com/feed.rss?code=latest", false),
        // Explicit credentials.
        ("https://user:pass@example.com/feed.xml", true),
        ("https://example.com/feed.xml?token=secret", true),
        ("https://example.com/feed.xml?apikey=abc", true),
        // Innocently named query parameters carrying token-shaped values.
        ("https://example.com/feed.rss?psk=deadbeefdeadbeef", true),
        ("https://example.com/feed.rss?member=a1B2c3D4e5F6g7H8i9J0aa", true),
        ("https://example.com/feed.rss?u=deadbeef00112233&t=cafebabe44556677", true),
        // Labelled path tokens.
        ("https://example-premium.com/premium/tok_abc123/feed.rss", true),
        ("https://premium.example.com/secret-9f8e7d6c5b/feed", true),
        // High-entropy path tokens: mixed, hex (including 19 chars), all-digit,
        // all-letter, and base64 with padding.
        ("https://members.example.com/rss/a1B2c3D4e5F6g7H8i9J0/feed.xml", true),
        ("https://example.com/abcdef0123456789abc/feed.rss", true),
        ("https://example.com/12345678901234567890/feed.rss", true),
        ("https://example.com/abcdefghijklmnopqrstuvwx/feed.rss", true),
        ("https://example.com/QWxhZGRpbjpvcGVuc2VzYW1l+x==/feed.rss", true),
        // Premium membership hosts are per-subscriber by construction.
        ("https://www.patreon.com/rss/myshow", true),
        ("https://myshow.supportingcast.fm/feed.rss", true),
        ("https://members.memberful.com/rss", true),
        ("https://myshow.supercast.com/feed", true),
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
        // Directory-vouched feeds skip the path heuristic so common public feeds
        // with opaque path IDs keep their metadata.
        ("https://feeds.example.com/5f6a7b8c9d0e1f2a3b4c5d6e/show.xml", .applePodcasts, .publicDirectoryFeed),
    ])
    func classifiesTrustedFeeds(
        rawURL: String,
        provider: MetadataProviderID,
        expected: PodcastFeedPrivacy
    ) throws {
        let url = try #require(URL(string: rawURL))
        #expect(PodcastFeedPrivacy.classify(url, discoveredBy: provider) == expected)
    }

    @Test("Explicit-credential detection ignores path shapes", arguments: [
        // rawURL, expected sensitive
        ("https://example.com/5f6a7b8c9d0e1f2a3b4c5d6e/episode-1", false),
        ("https://example.com/episodes/12345678901234567890", false),
        ("https://example.com/e?id=42", false),
        ("https://example.com/e?code=latest", false),
        ("https://user:pass@example.com/e", true),
        ("https://example.com/e?token=abc", true),
        ("https://example.com/e?code=abcd1234efgh", true),
    ])
    func detectsExplicitCredentials(rawURL: String, expected: Bool) throws {
        let url = try #require(URL(string: rawURL))
        #expect(PodcastFeedPrivacy.containsExplicitCredential(in: url) == expected)
    }

    @Test("Path segments are judged as credentials only when labelled or token-shaped", arguments: [
        // segment, expected credential-like
        ("show", false),
        ("feed.xml", false),
        ("episode-42", false),
        ("the-daily-show", false),
        ("this-is-a-long-slug-name", false),
        ("best-of-2024-holiday-special", false),
        ("12ab34cd", false),
        ("123456789012345", false),
        ("tok_abc123", true),
        ("secret-abcd", true),
        ("apikey_abcdef", true),
        ("a1B2c3D4e5F6g7H8i9J0", true),
        ("deadbeef0123456789abcdef", true),
        ("abcdef0123456789abc", true),
        ("12345678901234567890", true),
        ("abcdefghijklmnopqrstuvwx", true),
        ("QWxhZGRpbjpvcGVuc2VzYW1l+x==", true),
    ])
    func detectsCredentialSegments(segment: String, expected: Bool) {
        #expect(PodcastFeedPrivacy.isCredentialLikePathSegment(segment) == expected)
    }

    @Test("Token shapes cover hex, digit, letter, and base64 runs", arguments: [
        // value, expected token-like
        ("", false),
        ("latest", false),
        ("abc123", false),
        ("deadbeefcafe123", false),
        ("deadbeefcafe1234", true),
        ("abcdef0123456789abc", true),
        ("12345678901234567890", true),
        ("abcdefghijklmnopqrstuvwx", true),
        ("QWxhZGRpbjpvcGVuc2VzYW1l+x==", true),
        ("has spaces so not a token blob", false),
    ])
    func detectsTokenShapes(value: String, expected: Bool) {
        #expect(PodcastFeedPrivacy.isCredentialLikeToken(value) == expected)
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
