import Foundation
import Testing
@testable import WhatFun

@Suite("Reminder scheduler")
struct ReminderSchedulerTests {
    @Test("A reminder can be replaced and cancelled")
    func reminderLifecycle() async {
        let scheduler = InMemoryReminderScheduler()
        let fireAt = Date(timeIntervalSince1970: 1_800_000_000)
        let request = ReminderRequest(
            identifier: "start-item",
            title: "Start The Book",
            body: "You planned to start this today.",
            fireAt: fireAt,
            timeZoneIdentifier: "Asia/Singapore"
        )

        await scheduler.schedule(request)
        #expect(await scheduler.request(identifier: request.identifier) == request)

        await scheduler.cancel(identifier: request.identifier)
        #expect(await scheduler.request(identifier: request.identifier) == nil)
    }
}
