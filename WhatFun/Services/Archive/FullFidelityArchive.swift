import CryptoKit
import Foundation

nonisolated struct ArchiveEncryptedPrivateData: Codable, Equatable, Sendable {
    /// A stable algorithm identifier, for example `aes-gcm-256+pbkdf2-sha256`.
    var algorithm: String
    var keyDerivationIterations: Int?
    var salt: Data?
    var nonce: Data
    var ciphertext: Data
    var authenticationTag: Data
}

nonisolated struct ArchivePrivateFeedSecret: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var externalReferenceID: UUID
    var feedURL: String
}

nonisolated struct ArchivePrivatePayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var privateFeedSecrets: [ArchivePrivateFeedSecret] = []
}

nonisolated enum ArchivePrivatePayloadError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Private backup payload schema version \(version) is not supported."
        }
    }
}

nonisolated enum ArchivePrivatePayloadCodec {
    static func encode(_ payload: ArchivePrivatePayload) throws -> Data {
        guard payload.schemaVersion == ArchivePrivatePayload.currentSchemaVersion else {
            throw ArchivePrivatePayloadError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> ArchivePrivatePayload {
        let payload = try JSONDecoder().decode(ArchivePrivatePayload.self, from: data)
        guard payload.schemaVersion == ArchivePrivatePayload.currentSchemaVersion else {
            throw ArchivePrivatePayloadError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        return payload
    }
}

nonisolated enum ArchivePrivateDataCipherError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedAlgorithm(String)
    case invalidKeySize(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAlgorithm(algorithm):
            "The encrypted backup algorithm \(algorithm) is not supported."
        case let .invalidKeySize(bitCount):
            "Encrypted backups require a 256-bit key; received \(bitCount) bits."
        }
    }
}

/// Encrypts an already-serialized private payload. Key creation or passphrase derivation belongs
/// to the caller so this transport layer never persists a secret or passphrase.
nonisolated enum ArchivePrivateDataCipher {
    static let algorithm = "aes-gcm-256"

    static func encrypt(
        _ plaintext: Data,
        using key: SymmetricKey,
        salt: Data? = nil,
        keyDerivationIterations: Int? = nil
    ) throws -> ArchiveEncryptedPrivateData {
        guard key.bitCount == 256 else {
            throw ArchivePrivateDataCipherError.invalidKeySize(key.bitCount)
        }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        return ArchiveEncryptedPrivateData(
            algorithm: algorithm,
            keyDerivationIterations: keyDerivationIterations,
            salt: salt,
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            authenticationTag: sealed.tag,
        )
    }

    static func decrypt(_ encrypted: ArchiveEncryptedPrivateData, using key: SymmetricKey) throws -> Data {
        guard encrypted.algorithm == algorithm else {
            throw ArchivePrivateDataCipherError.unsupportedAlgorithm(encrypted.algorithm)
        }
        guard key.bitCount == 256 else {
            throw ArchivePrivateDataCipherError.invalidKeySize(key.bitCount)
        }
        let nonce = try AES.GCM.Nonce(data: encrypted.nonce)
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encrypted.ciphertext,
            tag: encrypted.authenticationTag,
        )
        return try AES.GCM.open(sealed, using: key)
    }

    static func encrypt(
        _ payload: ArchivePrivatePayload,
        using key: SymmetricKey,
        salt: Data? = nil,
        keyDerivationIterations: Int? = nil
    ) throws -> ArchiveEncryptedPrivateData {
        try encrypt(
            ArchivePrivatePayloadCodec.encode(payload),
            using: key,
            salt: salt,
            keyDerivationIterations: keyDerivationIterations,
        )
    }

    static func decryptPayload(
        _ encrypted: ArchiveEncryptedPrivateData,
        using key: SymmetricKey
    ) throws -> ArchivePrivatePayload {
        try ArchivePrivatePayloadCodec.decode(decrypt(encrypted, using: key))
    }
}

nonisolated struct FullFidelityArchiveEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let formatIdentifier = "app.whatfun.full-backup"

    var format: String = Self.formatIdentifier
    var schemaVersion: Int = Self.currentSchemaVersion
    var exportedAt: Date
    var generator: String
    var payload: ArchivePayload
    /// App-only values that are safe to back up, keyed by a documented stable name.
    var preferences: [String: String] = [:]
    /// Private feed URLs may appear only inside a separately encrypted block.
    var encryptedPrivateData: ArchiveEncryptedPrivateData?

    func validate() throws {
        guard format == Self.formatIdentifier else {
            throw FullFidelityArchiveError.unsupportedFormat(format)
        }
        guard schemaVersion > 0, schemaVersion <= Self.currentSchemaVersion else {
            throw FullFidelityArchiveError.unsupportedSchemaVersion(schemaVersion)
        }
        if let unsafeReference = payload.externalReferences.first(where: { reference in
            guard reference.isPrivateFeed else { return false }
            return Self.looksLikeNetworkURL(reference.canonicalURL) ||
                Self.looksLikeNetworkURL(reference.externalID) ||
                Self.looksLikeNetworkURL(reference.credentialKeychainID)
        }) {
            throw FullFidelityArchiveError.privateFeedSecretOutsideEncryptedBlock(unsafeReference.id)
        }
    }

    private static func looksLikeNetworkURL(_ value: String?) -> Bool {
        guard let value, let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "feed"
    }
}

nonisolated enum FullFidelityArchiveError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedFormat(String)
    case unsupportedSchemaVersion(Int)
    case privateFeedSecretOutsideEncryptedBlock(UUID)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(format):
            "This is not a WhatFun full backup (found \(format))."
        case let .unsupportedSchemaVersion(version):
            "This backup uses unsupported schema version \(version)."
        case let .privateFeedSecretOutsideEncryptedBlock(referenceID):
            "Private feed reference \(referenceID.uuidString) contains a URL outside the encrypted block."
        }
    }
}

nonisolated enum FullFidelityArchiveCodec {
    static func encode(_ envelope: FullFidelityArchiveEnvelope, prettyPrinted: Bool = true) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ArchiveDateCodec.string(from: date))
        }
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> FullFidelityArchiveEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ArchiveDateCodec.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 timestamp, found \(value).",
                )
            }
            return date
        }
        let envelope = try decoder.decode(FullFidelityArchiveEnvelope.self, from: data)
        try envelope.validate()
        return envelope
    }
}
