import CryptoKit
import Foundation
import Testing
@testable import WhatFun

@Suite("Backup passphrase encryption")
struct BackupKeyDerivationTests {
    @Test("The same passphrase and salt derive the same key")
    func deterministicKey() throws {
        let salt = Data((0 ..< 16).map(UInt8.init))
        let first = try BackupKeyDerivation.deriveKey(
            passphrase: "correct horse battery staple",
            salt: salt,
            iterations: 1_000
        )
        let second = try BackupKeyDerivation.deriveKey(
            passphrase: "correct horse battery staple",
            salt: salt,
            iterations: 1_000
        )

        #expect(first.withUnsafeBytes { Data($0) } == second.withUnsafeBytes { Data($0) })
    }

    @Test("Derived keys encrypt and decrypt the private archive payload")
    func privatePayloadRoundTrip() throws {
        let salt = Data(repeating: 7, count: 16)
        let key = try BackupKeyDerivation.deriveKey(
            passphrase: "portable secret",
            salt: salt,
            iterations: 1_000
        )
        let payload = ArchivePrivatePayload(
            privateFeedSecrets: [
                ArchivePrivateFeedSecret(
                    id: UUID(),
                    externalReferenceID: UUID(),
                    feedURL: "https://private.example/feed?token=secret"
                ),
            ]
        )

        let encrypted = try ArchivePrivateDataCipher.encrypt(
            payload,
            using: key,
            salt: salt,
            keyDerivationIterations: 1_000
        )
        let restored = try ArchivePrivateDataCipher.decryptPayload(encrypted, using: key)

        #expect(restored == payload)
    }
}
