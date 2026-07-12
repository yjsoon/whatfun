import Testing
@testable import WhatFun

@Suite("Daily maintenance ordering")
@MainActor
struct DailyMaintenanceSequencerTests {
    @MainActor
    final class OrderRecorder {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    @Test("Recovery snapshot is written before trash is purged")
    func snapshotPrecedesPurge() async {
        let recorder = OrderRecorder()
        await DailyMaintenanceSequencer.run(
            writeRecoverySnapshot: {
                recorder.record("snapshot")
                return true
            },
            purgeExpiredTrash: { recorder.record("purge") }
        )
        #expect(recorder.events == ["snapshot", "purge"])
    }

    @Test("A failed snapshot skips the destructive purge entirely")
    func failedSnapshotSkipsPurge() async {
        let recorder = OrderRecorder()
        await DailyMaintenanceSequencer.run(
            writeRecoverySnapshot: {
                recorder.record("snapshot-failed")
                return false
            },
            purgeExpiredTrash: { recorder.record("purge") }
        )
        #expect(recorder.events == ["snapshot-failed"])
    }
}
