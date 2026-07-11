import Foundation

/// File I/O for local recovery backups. SwiftData access intentionally stays in the
/// MainActor-isolated coordinator; this actor receives only a completed JSON value.
actor DailyBackupStore {
    static let defaultRetentionCount = 7

    private let directory: URL
    private let retentionCount: Int

    init(directory: URL, retentionCount: Int = defaultRetentionCount) throws {
        guard directory.isFileURL, retentionCount > 0 else {
            throw DurabilityError.unsafeBackupLocation(directory.absoluteString)
        }
        self.directory = directory.standardizedFileURL
        self.retentionCount = retentionCount
    }

    static func applicationSupport(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "app.whatfun",
        retentionCount: Int = defaultRetentionCount
    ) throws -> DailyBackupStore {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DurabilityError.unsafeBackupLocation("Application Support is unavailable")
        }
        let safeComponent = bundleIdentifier.replacingOccurrences(of: "/", with: "_")
        let directory = root
            .appending(path: safeComponent, directoryHint: .isDirectory)
            .appending(path: "Daily Backups", directoryHint: .isDirectory)
        return try DailyBackupStore(directory: directory, retentionCount: retentionCount)
    }

    @discardableResult
    func writeValidatedBackup(
        _ data: Data,
        for date: Date = .now,
        calendar: Calendar = .current
    ) throws -> URL {
        // Never rotate known-good files for data that cannot be restored.
        _ = try FullFidelityArchiveCodec.decode(data)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appending(path: filename(for: date, calendar: calendar))
        try data.write(to: destination, options: .atomic)

        // Validate the bytes that actually reached disk before pruning an older slot.
        let writtenData = try Data(contentsOf: destination)
        _ = try FullFidelityArchiveCodec.decode(writtenData)
        try pruneExcessBackups()
        return destination
    }

    func latestValidBackup() throws -> Data {
        for url in try backupURLsNewestFirst() {
            guard let data = try? Data(contentsOf: url),
                  (try? FullFidelityArchiveCodec.decode(data)) != nil
            else { continue }
            return data
        }
        throw DurabilityError.noValidBackup
    }

    func backupURLsNewestFirst() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("whatfun-") && name.hasSuffix(".full.json")
        }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func pruneExcessBackups() throws {
        let backups = try backupURLsNewestFirst()
        for url in backups.dropFirst(retentionCount) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func filename(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "whatfun-%04d-%02d-%02d.full.json", year, month, day)
    }
}
