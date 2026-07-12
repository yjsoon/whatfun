import Foundation

/// Orders the two automatic maintenance operations that run on every foreground.
///
/// The recovery snapshot must always be written before the destructive trash purge,
/// so an unattended purge can never run without today's safety net already on disk.
/// Kept as a pure ordering shell over injected effects so the sequence is testable
/// without SwiftData or the view layer.
@MainActor
enum DailyMaintenanceSequencer {
    static func run(
        writeRecoverySnapshot: () async -> Void,
        purgeExpiredTrash: () async -> Void
    ) async {
        await writeRecoverySnapshot()
        await purgeExpiredTrash()
    }
}
