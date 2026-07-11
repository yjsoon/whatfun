import Foundation
import Testing
@testable import WhatFun

@Suite("Daily full backup rotation", .serialized)
struct DailyBackupStoreTests {
    @Test("Atomic daily writes retain seven validated calendar-day slots")
    func sevenSlotRotation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyBackupStore(directory: directory)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC

        for offset in 0 ..< 8 {
            let date = try #require(calendar.date(byAdding: .day, value: offset, to: start))
            try await store.writeValidatedBackup(fullBackup(exportedAt: date), for: date, calendar: calendar)
        }

        let urls = try await store.backupURLsNewestFirst()
        #expect(urls.count == 7)
        #expect(urls.first?.lastPathComponent == "whatfun-2025-01-08.full.json")
        #expect(urls.last?.lastPathComponent == "whatfun-2025-01-02.full.json")

        let latest = try await store.latestValidBackup()
        #expect(try FullFidelityArchiveCodec.decode(latest).exportedAt ==
            calendar.date(byAdding: .day, value: 7, to: start))
    }

    @Test("Invalid input cannot rotate a valid slot and corrupt files are skipped on restore")
    func validationGuardsRotationAndRestore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DailyBackupStore(directory: directory)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let firstDate = Date(timeIntervalSince1970: 1_735_689_600)
        let secondDate = try #require(calendar.date(byAdding: .day, value: 1, to: firstDate))

        let firstURL = try await store.writeValidatedBackup(
            fullBackup(exportedAt: firstDate),
            for: firstDate,
            calendar: calendar
        )
        let secondURL = try await store.writeValidatedBackup(
            fullBackup(exportedAt: secondDate),
            for: secondDate,
            calendar: calendar
        )

        do {
            _ = try await store.writeValidatedBackup(
                Data("not a backup".utf8),
                for: secondDate.addingTimeInterval(86_400),
                calendar: calendar
            )
            Issue.record("Expected an invalid full backup to be rejected")
        } catch {
            // Expected: input is decoded before it can affect rotation.
        }
        #expect(try await store.backupURLsNewestFirst().count == 2)

        try Data("corrupt newest backup".utf8).write(to: secondURL, options: .atomic)
        let restored = try await store.latestValidBackup()
        #expect(try FullFidelityArchiveCodec.decode(restored).exportedAt == firstDate)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
    }

    private func fullBackup(exportedAt: Date) throws -> Data {
        try FullFidelityArchiveCodec.encode(FullFidelityArchiveEnvelope(
            exportedAt: exportedAt,
            generator: "WhatFunTests",
            payload: ArchivePayload()
        ))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "WhatFunDailyBackupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
