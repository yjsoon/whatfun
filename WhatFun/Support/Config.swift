import Foundation

/// Build credentials come from the ignored `Secrets.xcconfig.local` file via
/// Info.plist substitution. A public checkout resolves missing values to empty
/// strings and can still use the Keychain-backed fields in Settings.
enum Config {
    static let tmdbReadAccessToken = bundledValue(for: "TMDBReadAccessToken")
    static let rawgAPIKey = bundledValue(for: "RAWGAPIKey")

    /// Open Library does not require a key. Identify the app in requests per its API guidance.
    static let openLibraryContactEmail = "YOUR_CONTACT_EMAIL"

    /// Apple’s iTunes Search API does not require a key for podcast discovery.
    static let applicationName = "WhatFun"

    static var hasTMDBCredentials: Bool {
        !tmdbReadAccessToken.isEmpty
    }

    static var hasRAWGCredentials: Bool {
        !rawgAPIKey.isEmpty
    }

    private static func bundledValue(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
