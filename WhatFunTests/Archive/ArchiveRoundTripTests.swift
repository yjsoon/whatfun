import CryptoKit
import Foundation
import Testing
@testable import WhatFun

@Suite("WhatFun archive formats")
struct ArchiveRoundTripTests {
    @Test("ISO 8601 timestamps preserve submicrosecond semantic precision")
    func timestampPrecision() throws {
        let original = Date(timeIntervalSince1970: 1_742_000_000.1234567)
        let encoded = ArchiveDateCodec.string(from: original)
        let decoded = try #require(ArchiveDateCodec.date(from: encoded))
        #expect(abs(decoded.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.000_001)
    }

    @Test("Full backup round-trips all records and encrypted private data")
    func fullBackupRoundTrip() throws {
        let key = SymmetricKey(data: Data(repeating: 0xA5, count: 32))
        let privatePayload = ArchivePrivatePayload(privateFeedSecrets: [ArchivePrivateFeedSecret(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            externalReferenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            feedURL: "https://example.com/private",
        )])
        let encrypted = try ArchivePrivateDataCipher.encrypt(privatePayload, using: key)
        #expect(!encrypted.ciphertext.isEmpty)
        #expect(try ArchivePrivateDataCipher.decryptPayload(encrypted, using: key) == privatePayload)

        let envelope = FullFidelityArchiveEnvelope(
            exportedAt: ArchiveFixture.timestamp,
            generator: "WhatFunTests/1",
            payload: ArchiveFixture.payload,
            preferences: ["homePeriod": "month"],
            encryptedPrivateData: encrypted,
        )

        let data = try FullFidelityArchiveCodec.encode(envelope)
        #expect(try FullFidelityArchiveCodec.decode(data) == envelope)
    }

    @Test("Portable package round-trips stable joins and redacts Keychain identifiers")
    func portableRoundTrip() throws {
        let package = try PortableArchiveBuilder.makePackage(
            payload: ArchiveFixture.payload,
            generator: "WhatFunTests/1",
            exportedAt: ArchiveFixture.timestamp,
        )
        try PortableArchiveBuilder.validate(package)
        let decoded = try PortableArchiveBuilder.decodePayload(from: package)

        var expected = ArchiveFixture.payload
        expected.items[0].feedCredentialIdentifier = nil
        #expect(decoded == expected.stablySorted())
        #expect(package.manifest.files.contains { $0.path == "sessions.csv" && $0.rowCount == 1 })
        #expect(package.files[PortableArchivePackage.schemaFilename]?.isEmpty == false)
        #expect(package.files["items.csv"].map { !String(decoding: $0, as: UTF8.self).contains("private-feed-key") } == true)
    }

    @Test("Private feed URLs never appear in plain JSON or portable files")
    func privateFeedRedaction() throws {
        var payload = ArchiveFixture.payload
        payload.externalReferences[0].isPrivateFeed = true
        payload.externalReferences[0].isActiveFeed = true
        payload.externalReferences[0].externalID = "https://private.example.com/feed?token=secret"
        payload.externalReferences[0].canonicalURL = "https://private.example.com/feed?token=secret"
        payload.externalReferences[0].credentialKeychainID = "podcast-feed.fixture"

        let envelope = FullFidelityArchiveEnvelope(
            exportedAt: ArchiveFixture.timestamp,
            generator: "WhatFunTests/1",
            payload: payload,
        )
        do {
            _ = try FullFidelityArchiveCodec.encode(envelope)
            Issue.record("Expected a plain private feed URL to be rejected")
        } catch let error as FullFidelityArchiveError {
            guard case .privateFeedSecretOutsideEncryptedBlock = error else {
                Issue.record("Unexpected full backup error: \(error)")
                return
            }
        }

        let package = try PortableArchiveBuilder.makePackage(
            payload: payload,
            generator: "WhatFunTests/1",
            exportedAt: ArchiveFixture.timestamp,
        )
        let combinedText = package.files.values.compactMap { String(data: $0, encoding: .utf8) }.joined()
        #expect(!combinedText.contains("token=secret"))
        #expect(!combinedText.contains("podcast-feed.fixture"))
        let restored = try PortableArchiveBuilder.decodePayload(from: package)
        #expect(restored.externalReferences[0].canonicalURL == nil)
        #expect(restored.externalReferences[0].credentialKeychainID == nil)
        #expect(restored.externalReferences[0].externalID.hasPrefix("private."))
    }

    @Test("A changed file fails checksum validation")
    func checksumFailure() throws {
        var package = try PortableArchiveBuilder.makePackage(
            payload: ArchiveFixture.payload,
            generator: "WhatFunTests/1",
            exportedAt: ArchiveFixture.timestamp,
        )
        var items = try #require(package.files["items.csv"])
        let firstIndex = items.startIndex
        items[firstIndex] = items[firstIndex] == 0x41 ? 0x42 : 0x41
        package.files["items.csv"] = items

        do {
            try PortableArchiveBuilder.validate(package)
            Issue.record("Expected checksum validation to fail")
        } catch let error as PortableArchiveError {
            guard case .checksumMismatch(path: "items.csv", expected: _, actual: _) = error else {
                Issue.record("Unexpected portable archive error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A default current export timestamp validates after JSON canonicalization")
    func currentTimestampManifest() throws {
        let package = try PortableArchiveBuilder.makePackage(
            payload: ArchiveFixture.payload,
            generator: "WhatFunTests/1",
        )
        try PortableArchiveBuilder.validate(package)
    }

    @Test("Directory store writes and reads the complete package")
    func directoryStoreRoundTrip() async throws {
        let package = try PortableArchiveBuilder.makePackage(
            payload: ArchiveFixture.payload,
            generator: "WhatFunTests/1",
            exportedAt: ArchiveFixture.timestamp,
            assets: ["assets/cover.bin": Data([0, 1, 2, 3])],
        )
        let root = FileManager.default.temporaryDirectory
            .appending(path: "WhatFunArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = PortableArchiveStore()
        try await store.write(package, to: root)
        let restored = try await store.read(from: root)
        #expect(restored == package)
    }
}
