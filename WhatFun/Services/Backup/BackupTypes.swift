import Foundation

nonisolated enum ArchiveRestoreMode: Sendable, Equatable {
    /// Deletes current semantic records after the archive has validated, then restores stable IDs.
    case replaceAll
    /// Inserts records whose stable IDs are absent and never overwrites an existing record.
    case mergeNew
}

nonisolated struct DurabilitySnapshot: Sendable, Equatable {
    var payload: ArchivePayload
    var privatePayload: ArchivePrivatePayload?
}

nonisolated struct ArchiveRestoreWarning: Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var recordID: UUID?
    var message: String
}

nonisolated struct ArchiveRestoreReport: Sendable, Equatable {
    var insertedRecords = 0
    var skippedExistingRecords = 0
    var skippedOrphanedRecords = 0
    var restoredPrivateFeeds = 0
    var warnings: [ArchiveRestoreWarning] = []
}

nonisolated enum DurabilityError: Error, Sendable, Equatable, LocalizedError {
    case missingEncryptionKey
    case invalidPrivateFeedReference(UUID)
    case invalidArchive(String)
    case unsafeBackupLocation(String)
    case noValidBackup

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            "This backup contains encrypted private feeds and requires its encryption key."
        case let .invalidPrivateFeedReference(id):
            "Private feed data references missing external reference \(id.uuidString)."
        case let .invalidArchive(message):
            "The archive is not safe to restore: \(message)"
        case let .unsafeBackupLocation(path):
            "The backup location is unsafe: \(path)."
        case .noValidBackup:
            "No valid local backup is available."
        }
    }
}

nonisolated struct ImportApplicationSelection: Sendable, Equatable {
    var acceptedRowIDs: Set<UUID>
    /// Explicit choices from the review UI for ambiguous/existing canonical matches.
    var targetItemIDsByRowID: [UUID: UUID] = [:]

    static func acceptingReadyRows(in batch: StagedImportBatch) -> ImportApplicationSelection {
        ImportApplicationSelection(
            acceptedRowIDs: Set(batch.rows.filter { $0.disposition == .ready }.map(\.id)),
        )
    }
}

nonisolated struct ImportApplicationWarning: Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var rowID: UUID?
    var message: String
}

nonisolated struct ImportApplicationReport: Sendable, Equatable {
    var acceptedRows = 0
    var appliedRows = 0
    var skippedRows = 0
    var createdItems = 0
    var mergedItems = 0
    var createdUnits = 0
    var createdSessions = 0
    var createdEvents = 0
    var createdLists = 0
    var createdTags = 0
    var warnings: [ImportApplicationWarning] = []
}
