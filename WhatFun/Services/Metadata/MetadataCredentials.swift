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

/// The outcome of resolving a credential. A Keychain that fails for any reason
/// other than "no such item" must not silently fall through to the Config
/// fallback: that would bill requests to the developer's key, and would claim a
/// key is missing while one is in fact saved.
nonisolated enum MetadataCredentialResolution: Sendable, Equatable {
    case token(String)
    case keychainUnavailable(OSStatus)

    var token: String? {
        switch self {
        case let .token(token): token
        case .keychainUnavailable: nil
        }
    }
}

/// Synchronous, read-only Keychain access used when a request is built, so a
/// saved key takes effect without restarting the app. Writes go through the async
/// `KeychainCredentialStore`; both share the same Keychain service.
///
/// Deliberately keyed by `MetadataCredentialKey` rather than a free-form string:
/// this reader structurally cannot be pointed at a private podcast feed secret.
nonisolated protocol SynchronousCredentialReading: Sendable {
    /// Returns nil when no item is stored; throws when the Keychain itself fails.
    func value(for key: MetadataCredentialKey) throws -> String?
}

nonisolated struct KeychainSynchronousReader: SynchronousCredentialReading {
    private let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func value(for key: MetadataCredentialKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }
        return value
    }
}

/// Resolves a single provider credential on demand: the user's saved Keychain
/// value if present, otherwise the `Config.swift` fallback.
nonisolated struct MetadataCredentialSource: Sendable {
    private let reader: any SynchronousCredentialReading
    private let key: MetadataCredentialKey
    private let configValue: String

    init(reader: any SynchronousCredentialReading, key: MetadataCredentialKey, configValue: String) {
        self.reader = reader
        self.key = key
        self.configValue = configValue
    }

    func currentToken() -> MetadataCredentialResolution {
        do {
            let stored = try reader.value(for: key)
            return .token(MetadataCredentialResolver.resolve(stored: stored, config: configValue))
        } catch let error as CredentialStoreError {
            return switch error {
            case let .unexpectedStatus(status): .keychainUnavailable(status)
            case .invalidEncoding: .keychainUnavailable(errSecDecode)
            }
        } catch {
            return .keychainUnavailable(errSecInternalError)
        }
    }

    /// A fixed token with no Keychain lookup, used for tests and previews.
    static func constant(_ value: String) -> MetadataCredentialSource {
        MetadataCredentialSource(
            reader: EmptyCredentialReader(),
            key: .tmdbReadAccessToken,
            configValue: value
        )
    }
}

private nonisolated struct EmptyCredentialReader: SynchronousCredentialReading {
    func value(for key: MetadataCredentialKey) -> String? { nil }
}

/// Masks a stored credential for display, revealing only the final characters so
/// the user can confirm which key is in place without exposing the secret. Short
/// keys are masked entirely: revealing 4 characters of a 6-character key would
/// give away most of it.
nonisolated func maskedCredential(_ value: String, visibleSuffix: Int = 4) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    guard trimmed.count >= visibleSuffix * 2 else {
        return String(repeating: "•", count: trimmed.count)
    }
    return "••••" + trimmed.suffix(visibleSuffix)
}

/// What Settings should show for a provider key. A Keychain read that fails is
/// its own state: reporting it as "no key saved" would tell the user nothing is
/// stored while search simultaneously fails because the saved key cannot be read.
nonisolated enum MetadataKeyStatus: Sendable, Equatable {
    /// A key is saved. The associated value is already masked.
    case saved(masked: String)
    /// No saved key, but the build carries a usable Config fallback.
    case developerFallback
    /// No key anywhere: the provider cannot search.
    case missing
    /// The Keychain itself failed (locked device, decode error). We cannot say
    /// whether a key is saved.
    case unreadable

    var maskedKey: String? {
        if case let .saved(masked) = self { return masked }
        return nil
    }

    var isUsable: Bool {
        switch self {
        case .saved, .developerFallback: true
        case .missing, .unreadable: false
        }
    }
}

/// Pure derivation of the Settings row state. `stored` mirrors `CredentialStoring`:
/// success(nil) means no such item, failure means the Keychain itself failed.
nonisolated func metadataKeyStatus(
    stored: Result<String?, any Error>,
    hasConfigFallback: Bool
) -> MetadataKeyStatus {
    switch stored {
    case .failure:
        return .unreadable
    case let .success(value):
        guard let value = value?.metadataNilIfBlank else {
            return hasConfigFallback ? .developerFallback : .missing
        }
        return .saved(masked: maskedCredential(value))
    }
}

/// Removing or replacing a key must not leave behind a cached response from a
/// request that carried it. Metadata requests now use a cacheless session, but a
/// build from before that fix may have written entries into the shared on-disk
/// cache, so clear it when a key changes.
nonisolated func purgeCredentialBearingResponseCache() {
    URLCache.shared.removeAllCachedResponses()
}
