import Foundation

/// Serialises automatic maintenance against restore operations on the shared
/// MainActor model context.
///
/// Two hazards make this necessary:
/// - Every return to the foreground requests maintenance; rapid inactive/active
///   bounces must coalesce into a single run, or two purge passes can interleave
///   across suspension points and touch models the other already deleted.
/// - A Replace-Everything restore suspends mid-mutation (credential I/O) and
///   relies on rollback for atomicity; a purge that saves the context mid-restore
///   would commit a half-restored graph. Maintenance is therefore deferred while
///   any restore holds the gate, and a restore first drains any in-flight
///   maintenance.
///
/// Restores are counted rather than flagged so overlapping `withRestoreGate`
/// calls keep the gate closed until every one of them has finished. A request
/// that arrives while the gate is held is remembered and replayed once after
/// the last restore releases it, so a foreground that lands mid-restore still
/// gets that day's snapshot and purge.
@MainActor
final class MaintenanceScheduler {
    private var activeRestoreCount = 0
    private var maintenanceTask: Task<Void, Never>?
    private var pendingMaintenance: (@MainActor () async -> Void)?

    nonisolated init() {}

    /// Starts maintenance unless a run is already in flight or a restore holds
    /// the gate. Returns whether the work started immediately. A request gated
    /// by a restore is stored and replayed once the gate releases; one that
    /// coalesces into an in-flight run is simply dropped, because that run is
    /// already doing today's work.
    @discardableResult
    func scheduleMaintenance(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard activeRestoreCount == 0 else {
            pendingMaintenance = work
            return false
        }
        guard maintenanceTask == nil else { return false }
        maintenanceTask = Task { @MainActor [weak self] in
            await work()
            self?.maintenanceTask = nil
        }
        return true
    }

    /// Runs a restore or import mutation exclusively of maintenance: waits for
    /// any in-flight maintenance to finish, then blocks new maintenance until
    /// every overlapping gated operation has completed.
    func withRestoreGate<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await waitForIdle()
        activeRestoreCount += 1
        defer {
            activeRestoreCount -= 1
            if activeRestoreCount == 0, let pending = pendingMaintenance {
                pendingMaintenance = nil
                scheduleMaintenance(pending)
            }
        }
        return try await operation()
    }

    /// Resumes once no maintenance is in flight.
    func waitForIdle() async {
        while let task = maintenanceTask {
            await task.value
        }
    }
}
