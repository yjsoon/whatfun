import CryptoKit
import Foundation

/// MainActor boundary between live SwiftData models and immutable archive values.
/// Encoding and disk I/O operate only after the semantic snapshot has completed.
@MainActor
final class DurabilityCoordinator {
    /// Generator recorded in unattended recovery snapshots. Single source for the
    /// automatic daily-backup path so the view layer never re-spells the literal.
    static let automaticRecoveryGenerator = "WhatFun 0.1 automatic recovery"

    /// App-only preferences that are safe to embed in a backup, keyed by a documented
    /// stable name. Shared so the automatic and manual paths stay in lockstep.
    static func backupPreferences(
        gridStyle: String,
        defaultReminderHour: Int
    ) -> [String: String] {
        [
            "library.grid-style": gridStyle,
            "reminders.default-hour": String(defaultReminderHour),
        ]
    }

    private let bridge: SwiftDataArchiveBridge
    private let dailyStore: DailyBackupStore?
    private let generator: String

    init(
        bridge: SwiftDataArchiveBridge,
        dailyStore: DailyBackupStore? = nil,
        generator: String = "WhatFun"
    ) {
        self.bridge = bridge
        self.dailyStore = dailyStore
        self.generator = generator
    }

    func snapshot(includePrivateFeedSecrets: Bool = true) async throws -> DurabilitySnapshot {
        try await bridge.snapshot(includePrivateFeedSecrets: includePrivateFeedSecrets)
    }

    func makePortablePackage(
        exportedAt: Date = .now,
        assets: [String: Data] = [:]
    ) async throws -> PortableArchivePackage {
        let snapshot = try await bridge.snapshot(includePrivateFeedSecrets: false)
        return try PortableArchiveBuilder.makePackage(
            payload: snapshot.payload,
            generator: generator,
            exportedAt: exportedAt,
            assets: assets
        )
    }

    func makeFullBackup(
        exportedAt: Date = .now,
        encryptionKey: SymmetricKey? = nil,
        encryptionSalt: Data? = nil,
        keyDerivationIterations: Int? = nil,
        preferences: [String: String] = [:]
    ) async throws -> Data {
        let snapshot = try await bridge.snapshot(includePrivateFeedSecrets: true)
        return try encodeFullBackup(
            snapshot,
            exportedAt: exportedAt,
            encryptionKey: encryptionKey,
            encryptionSalt: encryptionSalt,
            keyDerivationIterations: keyDerivationIterations,
            preferences: preferences
        )
    }

    private func encodeFullBackup(
        _ snapshot: DurabilitySnapshot,
        exportedAt: Date,
        encryptionKey: SymmetricKey?,
        encryptionSalt: Data?,
        keyDerivationIterations: Int?,
        preferences: [String: String]
    ) throws -> Data {
        let encryptedPrivateData: ArchiveEncryptedPrivateData?
        if let privatePayload = snapshot.privatePayload {
            guard let encryptionKey else { throw DurabilityError.missingEncryptionKey }
            encryptedPrivateData = try ArchivePrivateDataCipher.encrypt(
                privatePayload,
                using: encryptionKey,
                salt: encryptionSalt,
                keyDerivationIterations: keyDerivationIterations
            )
        } else {
            encryptedPrivateData = nil
        }

        let envelope = FullFidelityArchiveEnvelope(
            exportedAt: exportedAt,
            generator: generator,
            payload: snapshot.payload,
            preferences: preferences,
            encryptedPrivateData: encryptedPrivateData
        )
        return try FullFidelityArchiveCodec.encode(envelope)
    }

    func restorePortablePackage(
        _ package: PortableArchivePackage,
        mode: ArchiveRestoreMode
    ) async throws -> ArchiveRestoreReport {
        try PortableArchiveBuilder.validate(package)
        let payload = try PortableArchiveBuilder.decodePayload(from: package)
        return try await bridge.restore(payload: payload, mode: mode)
    }

    func restoreFullBackup(
        _ data: Data,
        encryptionKey: SymmetricKey? = nil,
        mode: ArchiveRestoreMode
    ) async throws -> ArchiveRestoreReport {
        // Decode, authenticate private bytes, and validate relationships before the
        // bridge performs any destructive replace-all mutation.
        let envelope = try FullFidelityArchiveCodec.decode(data)
        let privatePayload: ArchivePrivatePayload?
        if let encrypted = envelope.encryptedPrivateData {
            guard let encryptionKey else { throw DurabilityError.missingEncryptionKey }
            privatePayload = try ArchivePrivateDataCipher.decryptPayload(
                encrypted,
                using: encryptionKey
            )
        } else {
            privatePayload = nil
        }
        return try await bridge.restore(
            payload: envelope.payload,
            privatePayload: privatePayload,
            mode: mode
        )
    }

    @discardableResult
    func writeDailyBackup(
        for date: Date = .now,
        calendar: Calendar = .current,
        preferences: [String: String] = [:]
    ) async throws -> URL {
        guard let dailyStore else {
            throw DurabilityError.unsafeBackupLocation("No daily backup store is configured")
        }
        // Unattended backups must never depend on a remembered passphrase.
        // Private feed URLs remain in Keychain and can be manually exported in an
        // encrypted full backup when the user supplies a key.
        let snapshot = try await bridge.snapshot(includePrivateFeedSecrets: false)
        let data = try encodeFullBackup(
            snapshot,
            exportedAt: date,
            encryptionKey: nil,
            encryptionSalt: nil,
            keyDerivationIterations: nil,
            preferences: preferences
        )
        return try await dailyStore.writeValidatedBackup(data, for: date, calendar: calendar)
    }

    func dailyBackupURLs() async throws -> [URL] {
        guard let dailyStore else {
            throw DurabilityError.unsafeBackupLocation("No daily backup store is configured")
        }
        return try await dailyStore.backupURLsNewestFirst()
    }

    func restoreLatestDailyBackup(
        encryptionKey: SymmetricKey? = nil,
        mode: ArchiveRestoreMode
    ) async throws -> ArchiveRestoreReport {
        guard let dailyStore else {
            throw DurabilityError.unsafeBackupLocation("No daily backup store is configured")
        }
        let data = try await dailyStore.latestValidBackup()
        return try await restoreFullBackup(data, encryptionKey: encryptionKey, mode: mode)
    }
}
