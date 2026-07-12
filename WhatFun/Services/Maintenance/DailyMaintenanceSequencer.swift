import Foundation

/// Orders the two automatic maintenance operations that run on every foreground.
///
/// The recovery snapshot must land before the destructive trash purge, so the
/// snapshot closure reports whether today's safety net is in place; on failure
/// (for example a full disk) the purge is skipped entirely and retried on a
/// later foreground — the trash grace window makes deferral harmless.
/// Kept as a pure ordering shell over injected effects so the sequence and its
/// failure gate are testable without SwiftData or the view layer.
@MainActor
enum DailyMaintenanceSequencer {
    static func run(
        writeRecoverySnapshot: () async -> Bool,
        purgeExpiredTrash: () async -> Void
    ) async {
        guard await writeRecoverySnapshot() else { return }
        await purgeExpiredTrash()
    }
}
