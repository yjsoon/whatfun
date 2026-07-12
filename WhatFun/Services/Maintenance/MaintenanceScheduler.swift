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
///   would commit a half-restored graph. Maintenance is therefore dropped while a
///   restore holds the gate, and a restore first drains any in-flight maintenance.
@MainActor
final class MaintenanceScheduler {
    private var isRestoreActive = false
    private var maintenanceTask: Task<Void, Never>?

    nonisolated init() {}

    /// Starts maintenance unless a run is already in flight or a restore holds
    /// the gate. Returns whether the work was accepted; dropped requests are
    /// harmless because maintenance re-runs on the next foreground.
    @discardableResult
    func scheduleMaintenance(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard !isRestoreActive, maintenanceTask == nil else { return false }
        maintenanceTask = Task { @MainActor [weak self] in
            await work()
            self?.maintenanceTask = nil
        }
        return true
    }

    /// Runs a restore or import mutation exclusively: waits for any in-flight
    /// maintenance to finish, then blocks new maintenance until the operation
    /// completes.
    func withRestoreGate<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await waitForIdle()
        isRestoreActive = true
        defer { isRestoreActive = false }
        return try await operation()
    }

    /// Resumes once no maintenance is in flight.
    func waitForIdle() async {
        while let task = maintenanceTask {
            await task.value
        }
    }
}
