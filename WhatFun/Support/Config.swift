import Foundation

/// All metadata-provider credentials live here so a local checkout has one setup point.
/// Do not commit real production keys to a public repository.
enum Config {
    /// Create a TMDB API read-access token at https://www.themoviedb.org/settings/api
    static let tmdbReadAccessToken = "YOUR_TMDB_READ_ACCESS_TOKEN"

    /// Create a RAWG API key at https://rawg.io/apidocs
    static let rawgAPIKey = "YOUR_RAWG_API_KEY"

    /// Open Library does not require a key. Identify the app in requests per its API guidance.
    static let openLibraryContactEmail = "YOUR_CONTACT_EMAIL"

    /// Apple’s iTunes Search API does not require a key for podcast discovery.
    static let applicationName = "WhatFun"

    static var hasTMDBCredentials: Bool {
        !tmdbReadAccessToken.hasPrefix("YOUR_") && !tmdbReadAccessToken.isEmpty
    }

    static var hasRAWGCredentials: Bool {
        !rawgAPIKey.hasPrefix("YOUR_") && !rawgAPIKey.isEmpty
    }
}

