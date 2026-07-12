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
            writeRecoverySnapshot: { recorder.record("snapshot") },
            purgeExpiredTrash: { recorder.record("purge") }
        )
        #expect(recorder.events == ["snapshot", "purge"])
    }
}
