import Testing
@testable import WhatFun

@Suite("Maintenance scheduling and restore gating")
@MainActor
struct MaintenanceSchedulerTests {
    @MainActor
    final class OrderRecorder {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    @Test("Rapid foreground bounces coalesce into a single maintenance run")
    func rapidRequestsCoalesce() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        let first = scheduler.scheduleMaintenance {
            await Task.yield()
            recorder.record("run")
        }
        let second = scheduler.scheduleMaintenance { recorder.record("run") }
        await scheduler.waitForIdle()

        #expect(first)
        #expect(!second)
        #expect(recorder.events == ["run"])
    }

    @Test("Maintenance requested during a restore is replayed exactly once after the gate closes")
    func maintenanceReplayedAfterRestore() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate {
            let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            let secondAccepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            #expect(!accepted)
            #expect(!secondAccepted)
            recorder.record("restore")
        }
        await scheduler.waitForIdle()

        #expect(recorder.events == ["restore", "maintenance"])
    }

    @Test("A restore drains in-flight maintenance before mutating")
    func restoreWaitsForInFlightMaintenance() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        scheduler.scheduleMaintenance {
            recorder.record("maintenance-start")
            await Task.yield()
            recorder.record("maintenance-end")
        }
        await scheduler.withRestoreGate {
            recorder.record("restore")
        }

        #expect(recorder.events == ["maintenance-start", "maintenance-end", "restore"])
    }

    @Test("Overlapping restores keep the gate closed until both complete")
    func overlappingRestoresKeepGateClosed() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate {
            recorder.record("outer-start")
            await scheduler.withRestoreGate {
                recorder.record("inner")
            }
            // The inner gate has released, but the outer one is still active:
            // a maintenance request must be deferred, not started.
            let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            #expect(!accepted)
            await Task.yield()
            #expect(!recorder.events.contains("maintenance"))
            recorder.record("outer-end")
        }
        await scheduler.waitForIdle()

        #expect(recorder.events == ["outer-start", "inner", "outer-end", "maintenance"])
    }

    @Test("Concurrent restores replay deferred maintenance only after the last one finishes")
    func concurrentRestoresReplayAfterLastRelease() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        async let first: Void = scheduler.withRestoreGate {
            recorder.record("restore1-start")
            scheduler.scheduleMaintenance { recorder.record("maintenance") }
            for _ in 0 ..< 3 { await Task.yield() }
            recorder.record("restore1-end")
        }
        async let second: Void = scheduler.withRestoreGate {
            recorder.record("restore2-start")
            for _ in 0 ..< 8 { await Task.yield() }
            recorder.record("restore2-end")
        }
        _ = await (first, second)
        await scheduler.waitForIdle()

        let maintenanceRuns = recorder.events.filter { $0 == "maintenance" }
        #expect(maintenanceRuns.count == 1)
        let maintenanceIndex = recorder.events.firstIndex(of: "maintenance")
        let firstEnd = recorder.events.firstIndex(of: "restore1-end")
        let secondEnd = recorder.events.firstIndex(of: "restore2-end")
        #expect(maintenanceIndex != nil && firstEnd != nil && secondEnd != nil)
        if let maintenanceIndex, let firstEnd, let secondEnd {
            #expect(maintenanceIndex > firstEnd)
            #expect(maintenanceIndex > secondEnd)
        }
    }

    @Test("Maintenance runs again once the restore gate is released")
    func maintenanceResumesAfterRestore() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate { recorder.record("restore") }
        let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
        await scheduler.waitForIdle()

        #expect(accepted)
        #expect(recorder.events == ["restore", "maintenance"])
    }
}
