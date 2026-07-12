import Foundation

/// A single, conservative classifier for whether a podcast feed URL should be
/// treated as a public directory feed or as a private credential.
///
/// Feed *redaction* (Keychain storage, export scrubbing) is solid elsewhere; the
/// only way a premium feed token leaks is if the feed is misclassified as public.
/// This type is therefore the one place that decides privacy, so every code path —
/// metadata search, staged import, and the manual item editor — agrees.
nonisolated enum PodcastFeedPrivacy: Sendable, Equatable {
    case publicDirectoryFeed
    case privateCredential

    var isPrivate: Bool { self == .privateCredential }

    /// Classify a feed discovered through a trusted metadata provider.
    ///
    /// A feed is public only when it comes verifiably from Apple's public
    /// directory over HTTPS and carries no embedded credential. Everything else —
    /// any other provider, or an Apple URL that smuggles a token — is treated as a
    /// private credential so it lands in Keychain rather than SwiftData or an export.
    static func classify(_ url: URL, discoveredBy provider: MetadataProviderID) -> Self {
        guard provider == .applePodcasts,
              url.scheme?.lowercased() == "https",
              !containsEmbeddedCredential(in: url)
        else {
            return .privateCredential
        }
        return .publicDirectoryFeed
    }

    /// Classify a feed of unknown provenance — one pasted by hand into the editor,
    /// or imported from OPML/Overcast where there is no trustworthy provider.
    ///
    /// Without a trusted directory to vouch for it, the feed is public only when it
    /// carries nothing that looks like an embedded credential; anything tokenised
    /// (userinfo, a sensitive query parameter, or a high-entropy path segment) is
    /// stored privately.
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

    // MARK: - Sensitivity core (pure, table-testable)

    private static let sensitiveQueryNames: Set<String> = [
        "access_token", "apikey", "api_key", "auth", "authorization",
        "code", "key", "password", "secret", "signature", "sig", "token",
    ]

    /// Whether the URL embeds anything credential-like: userinfo, a sensitive
    /// query parameter, or a high-entropy path segment (a Memberful / Supporting
    /// Cast / Patreon style token baked into the path rather than the query).
    static func containsEmbeddedCredential(in url: URL) -> Bool {
        if url.user != nil || url.password != nil { return true }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            // An unparseable URL is treated as sensitive rather than risk leaking it.
            return true
        }
        if (components.queryItems ?? []).contains(where: {
            sensitiveQueryNames.contains($0.name.lowercased())
        }) {
            return true
        }
        return url.path(percentEncoded: false)
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { isCredentialLikePathSegment(String($0)) }
    }

    /// Heuristic for a path segment that looks like a baked-in secret. It errs
    /// toward private: a false positive merely stores a public feed in Keychain and
    /// redacts it from exports, whereas a false negative leaks a token in plain text.
    static func isCredentialLikePathSegment(_ segment: String) -> Bool {
        // Judge the stem, so "abc123def456ghi789.rss" is measured without its extension.
        let stem: String
        if let dot = segment.lastIndex(of: "."), dot != segment.startIndex {
            let ext = segment[segment.index(after: dot)...].lowercased()
            let feedExtensions: Set<String> = ["rss", "xml", "json", "atom", "opml"]
            stem = feedExtensions.contains(ext) ? String(segment[..<dot]) : segment
        } else {
            stem = segment
        }

        // Labelled credentials, e.g. "tok_abc123", "secret-…", "apikey_…".
        let lower = stem.lowercased()
        let credentialPrefixes = [
            "tok", "token", "sk", "pk", "key", "apikey", "api_key",
            "secret", "auth", "access", "sig", "signature", "password", "pwd",
        ]
        for prefix in credentialPrefixes where lower.hasPrefix(prefix + "_") || lower.hasPrefix(prefix + "-") {
            if lower.dropFirst(prefix.count + 1).count >= 4 { return true }
        }

        // Long, opaque tokens that mix letters and digits (hex, base62, UUID-ish).
        guard stem.count >= 20 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard stem.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return stem.contains(where: \.isLetter) && stem.contains(where: \.isNumber)
    }
}

/// A recorded Keychain write, kept so a caller can undo it if a later step in the
/// same operation throws. Mirrors the compensation pattern used across the writers.
nonisolated struct CredentialMutation: Sendable {
    var key: String
    var previousValue: String?
}
