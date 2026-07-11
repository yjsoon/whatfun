import Foundation
import Testing
@testable import WhatFun

@Suite("Calendar history periods")
struct HistoryPeriodTests {
    private let singapore = TimeZone(identifier: "Asia/Singapore")!

    @Test("Calendar weeks respect the calendar's first weekday")
    func calendarWeekUsesLocaleRules() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_SG")
        calendar.timeZone = singapore
        calendar.firstWeekday = 2

        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12)))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 23)))
        let followingMonday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))

        #expect(HistoryPeriod.week.contains(sunday, relativeTo: wednesday, calendar: calendar))
        #expect(!HistoryPeriod.week.contains(followingMonday, relativeTo: wednesday, calendar: calendar))
    }

    @Test("Calendar months use local midnight")
    func monthUsesLocalTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = singapore

        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 9)))
        let interval = HistoryPeriod.month.interval(containing: reference, calendar: calendar)
        let start = calendar.dateComponents([.year, .month, .day, .hour], from: interval.start)
        let end = calendar.dateComponents([.year, .month, .day, .hour], from: interval.end)

        #expect(start.year == 2026)
        #expect(start.month == 8)
        #expect(start.day == 1)
        #expect(start.hour == 0)
        #expect(end.month == 9)
        #expect(end.day == 1)
    }

    @Test("Repeated sessions collapse into one count per item")
    func aggregateRepeatedSessions() {
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 2_000)
        )
        let occurrences = [
            SessionOccurrence(itemID: firstID, occurredAt: Date(timeIntervalSince1970: 1_100)),
            SessionOccurrence(itemID: secondID, occurredAt: Date(timeIntervalSince1970: 1_200)),
            SessionOccurrence(itemID: firstID, occurredAt: Date(timeIntervalSince1970: 1_500)),
            SessionOccurrence(itemID: firstID, occurredAt: Date(timeIntervalSince1970: 2_000)),
        ]

        let result = SessionAggregator.counts(for: occurrences, in: interval)

        #expect(result.count == 2)
        #expect(result.first?.itemID == firstID)
        #expect(result.first?.count == 2)
        #expect(result.last?.itemID == secondID)
        #expect(result.last?.count == 1)
    }
}
