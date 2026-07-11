import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("History-first activity service", .serialized)
@MainActor
struct ActivityServiceTests {
    @Test("First session starts an item and completion stays separate")
    func initialSessionAndCompletion() throws {
        let container = try makeContainer()
        let service = ActivityService(context: container.mainContext)
        let item = LibraryItem(mediaKind: .movie, title: "Perfect Days")
        try service.register(item)

        let session = try service.logSession(
            for: item,
            progress: SessionProgress(elapsedSeconds: 3_600, mediaDurationSeconds: 7_440)
        )

        #expect(item.status == .inProgress)
        #expect(item.sessionCount == 1)
        #expect(item.progressFraction == session.progressFraction)
        #expect(item.lastCompletedAt == nil)

        let cycle = try #require(item.cycles?.first)
        try service.markDone(item: item, cycle: cycle, ratingHalfSteps: 9)

        #expect(item.status == .completed)
        #expect(item.lastCompletedAt != nil)
        #expect(item.ratingOverrideHalfSteps == 9)
        #expect(item.sessionCount == 1)
    }

    @Test("A completed item requires an explicit replay decision")
    func explicitReplayChoice() throws {
        let container = try makeContainer()
        let service = ActivityService(context: container.mainContext)
        let item = LibraryItem(mediaKind: .book, title: "Piranesi")
        try service.register(item)
        _ = try service.logSession(for: item)
        let firstCycle = try #require(item.cycles?.first)
        try service.markDone(item: item, cycle: firstCycle)

        #expect(throws: ActivityServiceError.completedCycleRequiresChoice) {
            try service.logSession(for: item)
        }

        let repeatCycle = try service.startRepeat(for: item)
        _ = try service.logSession(for: item, in: repeatCycle)

        #expect(item.status == .inProgress)
        #expect(item.repeatCount == 1)
        #expect(item.cycleCount == 2)
        #expect(firstCycle.completedAt != nil)
    }

    @Test("TV completes only after all released seasons complete")
    func tvSeasonAggregation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = ActivityService(context: context)
        let show = LibraryItem(mediaKind: .tvShow, title: "Somebody Somewhere")
        try service.register(show)

        let seasonOne = ContentUnit(
            item: show,
            kind: .tvSeason,
            title: "Season 1",
            sortOrder: 1
        )
        seasonOne.releaseDate = .distantPast
        let seasonTwo = ContentUnit(
            item: show,
            kind: .tvSeason,
            title: "Season 2",
            sortOrder: 2
        )
        seasonTwo.releaseDate = .distantPast
        context.insert(seasonOne)
        context.insert(seasonTwo)
        show.units = [seasonOne, seasonTwo]

        let first = try service.startNextInstallment(for: show, targetUnit: seasonOne)
        _ = try service.logSession(for: show, targetUnit: seasonOne, in: first)
        try service.markDone(item: show, cycle: first, targetUnit: seasonOne, ratingHalfSteps: 8)
        #expect(show.status == .inProgress)

        let second = try service.startNextInstallment(for: show, targetUnit: seasonTwo)
        _ = try service.logSession(for: show, targetUnit: seasonTwo, in: second)
        try service.markDone(item: show, cycle: second, targetUnit: seasonTwo, ratingHalfSteps: 9)

        #expect(show.status == .completed)
        #expect(show.derivedRatingHalfSteps == 9)
        #expect(show.effectiveRatingHalfSteps == 9)

        let seasonThree = ContentUnit(
            item: show,
            kind: .tvSeason,
            title: "Season 3",
            sortOrder: 3
        )
        seasonThree.releaseDate = .distantPast
        context.insert(seasonThree)
        show.units = (show.units ?? []) + [seasonThree]
        ActivityProjection.rebuild(show)

        #expect(show.status == .completed)
        #expect(show.hasNewInstallment)

        _ = try service.startNextInstallment(for: show, targetUnit: seasonThree)
        #expect(show.status == .inProgress)
        #expect(!show.hasNewInstallment)
    }

    @Test("Trash uses a recoverable thirty day window")
    func recentlyDeletedWindow() throws {
        let container = try makeContainer()
        let service = ActivityService(context: container.mainContext)
        let item = LibraryItem(mediaKind: .game, title: "Pentiment")
        try service.register(item)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try service.moveToTrash(item, at: date, calendar: calendar)

        #expect(item.trashedAt == date)
        #expect(item.purgeAfter == calendar.date(byAdding: .day, value: 30, to: date))

        try service.recoverFromTrash(item)
        #expect(item.trashedAt == nil)
        #expect(item.purgeAfter == nil)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: WhatFunSchemaV1.self)
        let configuration = ModelConfiguration(
            "WhatFunTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WhatFunMigrationPlan.self,
            configurations: configuration
        )
    }
}
