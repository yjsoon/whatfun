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

    @Test("Maintenance requested during an active restore is dropped")
    func maintenanceDroppedDuringRestore() async {
        let scheduler = MaintenanceScheduler()
        let recorder = OrderRecorder()

        await scheduler.withRestoreGate {
            let accepted = scheduler.scheduleMaintenance { recorder.record("maintenance") }
            #expect(!accepted)
        }
        await scheduler.waitForIdle()

        #expect(recorder.events.isEmpty)
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
