import Foundation
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
        let reader = StubCredentialReader(values: [
            MetadataCredentialKey.tmdbReadAccessToken.account: "stored-token"
        ])
        let source = MetadataCredentialSource(
            reader: reader,
            key: .tmdbReadAccessToken,
            configValue: "YOUR_TMDB_READ_ACCESS_TOKEN"
        )
        #expect(source.currentToken() == "stored-token")

        let emptySource = MetadataCredentialSource(
            reader: reader,
            key: .rawgAPIKey,
            configValue: "config-rawg-key"
        )
        #expect(emptySource.currentToken() == "config-rawg-key")
    }

    @Test("A saved key makes a placeholder-config provider available")
    func savedKeyEnablesProvider() {
        let reader = StubCredentialReader(values: [
            MetadataCredentialKey.tmdbReadAccessToken.account: "stored-token"
        ])
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

    @Test("Masked display reveals only the final characters")
    func maskedDisplay() {
        #expect(maskedCredential("abcdef123456") == "••••3456")
        #expect(maskedCredential("abc") == "•••")
        #expect(maskedCredential("  padded-key-value  ") == "••••alue")
        #expect(maskedCredential("") == "")
    }
}

private nonisolated struct StubCredentialReader: SynchronousCredentialReading {
    let values: [String: String]

    func value(for account: String) -> String? {
        values[account]
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
