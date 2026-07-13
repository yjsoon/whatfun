import Foundation

/// A single, conservative classifier for whether a podcast feed URL should be
/// treated as a public directory feed or as a private credential.
///
/// Feed *redaction* (Keychain storage, export scrubbing) is solid elsewhere; the
/// only way a premium feed token leaks is if the feed is misclassified as public.
/// This type is therefore the one place that decides privacy, so every code path —
/// metadata search, staged import, archive restore, and the manual item editor —
/// agrees.
///
/// Two tiers exist deliberately:
/// - `containsExplicitCredential(in:)` — userinfo or a sensitive query parameter.
///   Used wherever a URL merely accompanies a feed (episode links, GUIDs, website
///   references), matching the app's original behaviour so public-feed metadata is
///   not needlessly dropped.
/// - `containsEmbeddedCredential(in:)` — the explicit check plus premium-host
///   signals and a path-token heuristic. Used to classify the feed URL itself,
///   where a missed token means a plain-text leak in exports.
nonisolated enum PodcastFeedPrivacy: Sendable, Equatable {
    case publicDirectoryFeed
    case privateCredential

    var isPrivate: Bool { self == .privateCredential }

    /// Classify a feed discovered through a trusted metadata provider.
    ///
    /// A feed is public only when it comes verifiably from Apple's public
    /// directory over HTTPS and carries no explicit credential. The path-token
    /// heuristic deliberately does not run here: directory-listed feeds are
    /// vouched for, and running it would drop metadata for common public feeds.
    static func classify(_ url: URL, discoveredBy provider: MetadataProviderID) -> Self {
        guard provider == .applePodcasts,
              url.scheme?.lowercased() == "https",
              !containsExplicitCredential(in: url)
        else {
            // URLs outside the public Apple directory are treated as private by
            // default. This errs toward Keychain storage instead of accidentally
            // persisting a premium feed token in SwiftData or an export.
            return .privateCredential
        }
        return .publicDirectoryFeed
    }

    /// Classify a feed of unknown provenance — one pasted by hand into the editor,
    /// imported from OPML/Overcast, or arriving in a restored archive, where there
    /// is no trustworthy directory to vouch for it.
    static func classify(untrustedFeed url: URL) -> Self {
        containsEmbeddedCredential(in: url) ? .privateCredential : .publicDirectoryFeed
    }

    /// Validate and normalise a raw feed string the way every writer expects: an
    /// `http`/`https` URL with a non-empty host. Returns `nil` for anything else.
    static func validatedFeedURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host()?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    // MARK: - Explicit credentials (light tier)

    /// Whether the URL openly carries a credential: userinfo, a query parameter
    /// with a credential name, or a query value shaped like a token.
    static func containsExplicitCredential(in url: URL) -> Bool {
        if url.user != nil || url.password != nil { return true }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            // An unparseable URL is treated as sensitive rather than risk leaking it.
            return true
        }
        return (components.queryItems ?? []).contains { item in
            isSensitiveQueryItem(name: item.name, value: item.value)
        }
    }

    /// Names that mean "credential" regardless of the value.
    private static let strongQueryNames: Set<String> = [
        "access_token", "apikey", "api_key", "auth", "authorization",
        "password", "secret", "signature", "token",
    ]

    /// Names that often mean "credential" but also appear with short human values
    /// (`?code=latest`); these count only when the value is substantial.
    private static let weakQueryNames: Set<String> = ["code", "key", "sig"]

    static func isSensitiveQueryItem(name: String, value: String?) -> Bool {
        let lowered = name.lowercased()
        if strongQueryNames.contains(lowered) { return true }
        if weakQueryNames.contains(lowered) { return (value ?? "").count >= 8 }
        return false
    }

    // MARK: - Embedded credentials (full tier, feed URLs only)

    /// Whether the feed URL embeds anything credential-like: an explicit
    /// credential, a known premium/membership host, or a token baked into the
    /// path (Memberful, Supporting Cast, Patreon style) — after exempting known
    /// public-directory shapes.
    static func containsEmbeddedCredential(in url: URL) -> Bool {
        if containsExplicitCredential(in: url) { return true }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }
        // For a feed URL, an innocently-named query parameter (?psk=, ?member=,
        // ?u=&t=) still counts when its value is shaped like a token.
        if (components.queryItems ?? []).contains(where: { isCredentialLikeToken($0.value ?? "") }) {
            return true
        }
        let host = url.host()?.lowercased() ?? ""
        let path = url.path(percentEncoded: false)
        if isKnownPremiumFeed(host: host, path: path) { return true }
        if isKnownPublicDirectoryShape(host: host, path: path) { return false }
        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { isCredentialLikePathSegment(String($0)) }
    }

    /// Hosts whose feeds are per-subscriber by construction.
    private static func isKnownPremiumFeed(host: String, path: String) -> Bool {
        let premiumHostSuffixes = ["supportingcast.fm", "memberful.com", "supercast.com"]
        if premiumHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        // Patreon serves premium audio under /rss; the rest of the site is not a feed.
        if (host == "patreon.com" || host.hasSuffix(".patreon.com")) && path.hasPrefix("/rss") {
            return true
        }
        return false
    }

    /// Public-directory URL shapes whose opaque-looking IDs are show IDs, not
    /// secrets (e.g. Acast's public catalogue).
    private static func isKnownPublicDirectoryShape(host: String, path: String) -> Bool {
        host == "feeds.acast.com" && path.hasPrefix("/public/")
    }

    // MARK: - Token shapes (pure, table-testable)

    /// Heuristic for a path segment that looks like a baked-in secret. It errs
    /// toward private: a false positive merely stores a public feed in Keychain and
    /// redacts it from exports, whereas a false negative leaks a token in plain text.
    static func isCredentialLikePathSegment(_ segment: String) -> Bool {
        // Judge the stem, so "abc123def456ghi789.rss" is measured without its extension.
        let stem = strippingFeedExtension(from: segment)

        // Labelled credentials, e.g. "tok_abc123", "secret-…", "apikey_…".
        let lower = stem.lowercased()
        let credentialPrefixes = [
            "tok", "token", "sk", "pk", "key", "apikey", "api_key",
            "secret", "auth", "access", "sig", "signature", "password", "pwd",
        ]
        for prefix in credentialPrefixes where lower.hasPrefix(prefix + "_") || lower.hasPrefix(prefix + "-") {
            if lower.dropFirst(prefix.count + 1).count >= 4 { return true }
        }

        // Hyphen/underscore-separated human slugs stay public, even long ones
        // with years in them ("best-of-2024-holiday-special").
        if isHumanSlug(stem) { return false }

        return isCredentialLikeToken(stem)
    }

    /// Whether a bare string (a path stem or a query value) is shaped like an
    /// opaque token: a hex run, or a long base64/base62-style blob — including
    /// all-digit and all-letter runs, which premium platforms also issue.
    static func isCredentialLikeToken(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if value.count >= 16, value.unicodeScalars.allSatisfy({ hexDigits.contains($0) }) {
            return true
        }
        let tokenCharacters = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=+")
        return value.count >= 20 && value.unicodeScalars.allSatisfy { tokenCharacters.contains($0) }
    }

    /// A separator-delimited slug reads as human when every part is a word or a
    /// short number ("the-daily-show", "best-of-2024-holiday-special").
    private static func isHumanSlug(_ stem: String) -> Bool {
        let parts = stem.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            part.count <= 12 && (
                part.allSatisfy(\.isLetter) ||
                    (part.count <= 4 && part.allSatisfy(\.isNumber))
            )
        }
    }

    private static func strippingFeedExtension(from segment: String) -> String {
        guard let dot = segment.lastIndex(of: "."), dot != segment.startIndex else { return segment }
        let ext = segment[segment.index(after: dot)...].lowercased()
        let feedExtensions: Set<String> = ["rss", "xml", "json", "atom", "opml"]
        return feedExtensions.contains(ext) ? String(segment[..<dot]) : segment
    }
}

/// A recorded Keychain write, kept so a caller can undo it if a later step in the
/// same operation throws. Mirrors the compensation pattern used across the writers.
nonisolated struct CredentialMutation: Sendable {
    var key: String
    var previousValue: String?
}
