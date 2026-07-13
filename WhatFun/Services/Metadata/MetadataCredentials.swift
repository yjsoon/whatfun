import Foundation
import Security

/// Identifies a metadata provider credential the user can manage in Settings.
/// The `account` is the Keychain item name; the `setupURL` is the provider's key page.
nonisolated enum MetadataCredentialKey: String, CaseIterable, Sendable {
    case tmdbReadAccessToken = "metadata.tmdb.read-access-token"
    case rawgAPIKey = "metadata.rawg.api-key"

    var account: String { rawValue }

    var displayName: String {
        switch self {
        case .tmdbReadAccessToken: "TMDB"
        case .rawgAPIKey: "RAWG"
        }
    }

    var setupURL: URL {
        switch self {
        case .tmdbReadAccessToken: URL(string: "https://www.themoviedb.org/settings/api")!
        case .rawgAPIKey: URL(string: "https://rawg.io/apidocs")!
        }
    }
}

/// Pure resolution of a provider credential: a Keychain value the user saved
/// wins; otherwise the developer fallback in `Config.swift` is used, so the
/// owner's checkout keeps working without any in-app setup.
nonisolated enum MetadataCredentialResolver {
    static func resolve(stored: String?, config: String) -> String {
        if let stored = stored?.metadataNilIfBlank {
            return stored
        }
        return config
    }
}

/// Synchronous, read-only Keychain access used at request time so a saved key
/// takes effect without restarting the app. Writes still go through the async
/// `KeychainCredentialStore`; both share the same Keychain service.
nonisolated protocol SynchronousCredentialReading: Sendable {
    func value(for account: String) -> String?
}

nonisolated struct KeychainSynchronousReader: SynchronousCredentialReading {
    private let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }
}

/// Resolves a single provider credential on demand: reads the user's saved
/// Keychain value if present, otherwise falls back to `Config.swift`.
nonisolated struct MetadataCredentialSource: Sendable {
    private let reader: any SynchronousCredentialReading
    private let account: String
    private let configValue: String

    init(reader: any SynchronousCredentialReading, key: MetadataCredentialKey, configValue: String) {
        self.reader = reader
        self.account = key.account
        self.configValue = configValue
    }

    func currentToken() -> String {
        MetadataCredentialResolver.resolve(stored: reader.value(for: account), config: configValue)
    }

    /// A fixed token with no Keychain lookup, used for tests and previews.
    static func constant(_ value: String) -> MetadataCredentialSource {
        MetadataCredentialSource(reader: EmptyCredentialReader(), key: .tmdbReadAccessToken, configValue: value)
    }
}

private nonisolated struct EmptyCredentialReader: SynchronousCredentialReading {
    func value(for account: String) -> String? { nil }
}

/// Masks a stored credential for display, revealing only the final characters
/// so the user can confirm which key is in place without exposing the secret.
nonisolated func maskedCredential(_ value: String, visibleSuffix: Int = 4) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    guard trimmed.count > visibleSuffix else {
        return String(repeating: "•", count: max(trimmed.count, 1))
    }
    return "••••" + trimmed.suffix(visibleSuffix)
}
