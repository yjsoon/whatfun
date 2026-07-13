import Foundation
import Security
import Testing
@testable import WhatFun

@Suite("Metadata credentials")
struct MetadataCredentialsTests {
    @Test("A saved key wins over the Config fallback")
    func storedKeyWins() {
        let resolved = MetadataCredentialResolver.resolve(
            stored: "user-key",
            config: "config-key"
        )
        #expect(resolved == "user-key")
    }

    @Test("A missing saved key falls back to Config")
    func missingKeyFallsBack() {
        let resolved = MetadataCredentialResolver.resolve(
            stored: nil,
            config: "config-key"
        )
        #expect(resolved == "config-key")
    }

    @Test("A blank saved key falls back to Config")
    func blankKeyFallsBack() {
        let resolved = MetadataCredentialResolver.resolve(
            stored: "   \n",
            config: "config-key"
        )
        #expect(resolved == "config-key")
    }

    @Test("The credential source resolves through its reader at request time")
    func sourceResolvesThroughReader() {
        let reader = StubCredentialReader(values: [.tmdbReadAccessToken: "stored-token"])
        let source = MetadataCredentialSource(
            reader: reader,
            key: .tmdbReadAccessToken,
            configValue: "YOUR_TMDB_READ_ACCESS_TOKEN"
        )
        #expect(source.currentToken() == .token("stored-token"))

        let emptySource = MetadataCredentialSource(
            reader: reader,
            key: .rawgAPIKey,
            configValue: "config-rawg-key"
        )
        #expect(emptySource.currentToken() == .token("config-rawg-key"))
    }

    @Test("A failing Keychain never falls back to the developer's Config key")
    func keychainFailureDoesNotFallBackToConfig() {
        let source = MetadataCredentialSource(
            reader: FailingCredentialReader(status: errSecInteractionNotAllowed),
            key: .rawgAPIKey,
            configValue: "developer-config-key"
        )
        #expect(source.currentToken() == .keychainUnavailable(errSecInteractionNotAllowed))
        #expect(source.currentToken().token == nil)
    }

    @Test("A failing Keychain reports a distinct error, not a missing key")
    func keychainFailureIsNotReportedAsMissingKey() {
        let provider = RAWGMetadataProvider(
            httpClient: NoopHTTPClient(),
            credential: MetadataCredentialSource(
                reader: FailingCredentialReader(status: errSecInteractionNotAllowed),
                key: .rawgAPIKey,
                configValue: "developer-config-key"
            )
        )
        guard case let .credentialRequired(instructions, _) = provider.availability else {
            Issue.record("Expected credentialRequired availability")
            return
        }
        #expect(instructions.contains("Keychain"))
        #expect(!instructions.contains("Add a RAWG API key"))
    }

    @Test("A saved key makes a placeholder-config provider available")
    func savedKeyEnablesProvider() {
        let reader = StubCredentialReader(values: [.tmdbReadAccessToken: "stored-token"])
        let provider = TMDBMetadataProvider(
            httpClient: NoopHTTPClient(),
            credential: MetadataCredentialSource(
                reader: reader,
                key: .tmdbReadAccessToken,
                configValue: "YOUR_TMDB_READ_ACCESS_TOKEN"
            )
        )
        #expect(provider.availability == .available)
    }

    @Test("Missing key everywhere points at Settings, not source files")
    func missingKeyMentionsSettings() {
        let provider = RAWGMetadataProvider(
            httpClient: NoopHTTPClient(),
            credential: MetadataCredentialSource(
                reader: StubCredentialReader(values: [:]),
                key: .rawgAPIKey,
                configValue: "YOUR_RAWG_API_KEY"
            )
        )
        guard case let .credentialRequired(instructions, setupURL) = provider.availability else {
            Issue.record("Expected credentialRequired availability")
            return
        }
        #expect(instructions.contains("Settings"))
        #expect(!instructions.contains("Config.swift"))
        #expect(setupURL == URL(string: "https://rawg.io/apidocs"))
    }

    @Test("Masked display reveals only the final characters and hides short keys")
    func maskedDisplay() {
        #expect(maskedCredential("abcdef123456") == "••••3456")
        #expect(maskedCredential("  padded-key-value  ") == "••••alue")
        // Short keys are masked entirely: revealing 4 of 6 would give the key away.
        #expect(maskedCredential("abc") == "•••")
        #expect(maskedCredential("abcdefg") == "•••••••")
        #expect(maskedCredential("abcdefgh") == "••••efgh")
        #expect(maskedCredential("") == "")
    }

    @Test("A key written through the Keychain store is read back by the synchronous reader")
    func keychainRoundTrip() async throws {
        let service = "com.yjsoon.whatfun.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service)
        let reader = KeychainSynchronousReader(service: service)
        let key = MetadataCredentialKey.rawgAPIKey
        let source = MetadataCredentialSource(
            reader: reader,
            key: key,
            configValue: "YOUR_RAWG_API_KEY"
        )

        #expect(try reader.value(for: key) == nil)

        try await store.set("round-trip-key", for: key.account)
        #expect(try reader.value(for: key) == "round-trip-key")
        // The live resolution path must see the saved key, not the Config fallback.
        #expect(source.currentToken() == .token("round-trip-key"))

        try await store.set("replacement-key", for: key.account)
        #expect(try reader.value(for: key) == "replacement-key")

        try await store.removeValue(for: key.account)
        #expect(try reader.value(for: key) == nil)
        #expect(source.currentToken() == .token("YOUR_RAWG_API_KEY"))
    }

    @Test("Settings shows a saved key as masked, never as plaintext")
    func settingsStatusForSavedKey() {
        let status = metadataKeyStatus(
            stored: .success("abcdef123456"),
            hasConfigFallback: false
        )
        #expect(status == .saved(masked: "••••3456"))
        #expect(status.maskedKey == "••••3456")
        #expect(status.isUsable)
    }

    @Test("Settings distinguishes no saved key from a Config fallback")
    func settingsStatusWithoutSavedKey() {
        #expect(
            metadataKeyStatus(stored: .success(nil), hasConfigFallback: true) == .developerFallback
        )
        #expect(
            metadataKeyStatus(stored: .success(nil), hasConfigFallback: false) == .missing
        )
        // A blank stored value is not a saved key.
        #expect(
            metadataKeyStatus(stored: .success("  "), hasConfigFallback: false) == .missing
        )
    }

    @Test("Settings reports an unreadable Keychain instead of claiming no key is saved")
    func settingsStatusWhenKeychainFails() {
        let failure = Result<String?, any Error>.failure(
            CredentialStoreError.unexpectedStatus(errSecInteractionNotAllowed)
        )
        // Crucially, this must not report .developerFallback or .missing: those
        // would tell the user nothing is stored while search fails on the key
        // that in fact is stored but cannot be read.
        #expect(metadataKeyStatus(stored: failure, hasConfigFallback: true) == .unreadable)
        #expect(metadataKeyStatus(stored: failure, hasConfigFallback: false) == .unreadable)
        #expect(metadataKeyStatus(stored: failure, hasConfigFallback: true).isUsable == false)
        #expect(metadataKeyStatus(stored: failure, hasConfigFallback: true).maskedKey == nil)

        let decodeFailure = Result<String?, any Error>.failure(CredentialStoreError.invalidEncoding)
        #expect(metadataKeyStatus(stored: decodeFailure, hasConfigFallback: true) == .unreadable)
    }

    @Test("Credential-bearing requests use a session that cannot cache to disk")
    func metadataSessionHasNoDiskCache() {
        #expect(URLSessionHTTPClient.secretless().persistsResponsesToDisk == false)
        // The default shared session is exactly what must not be used for these.
        #expect(URLSessionHTTPClient().persistsResponsesToDisk == true)
    }
}

private nonisolated struct StubCredentialReader: SynchronousCredentialReading {
    let values: [MetadataCredentialKey: String]

    func value(for key: MetadataCredentialKey) -> String? {
        values[key]
    }
}

private nonisolated struct FailingCredentialReader: SynchronousCredentialReading {
    let status: OSStatus

    func value(for key: MetadataCredentialKey) throws -> String? {
        throw CredentialStoreError.unexpectedStatus(status)
    }
}

private nonisolated struct NoopHTTPClient: HTTPClient {
    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}
