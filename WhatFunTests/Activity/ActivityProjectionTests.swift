import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("Activity projections", .serialized)
@MainActor
struct ActivityProjectionTests {
    @Test("Half-star ratings derive from seasons until overridden")
    func ratingDerivation() {
        #expect(ActivityProjection.derivedRating(
            overrideHalfSteps: nil,
            seasonHalfSteps: [7, 8, 10]
        ) == 8)
        #expect(ActivityProjection.derivedRating(
            overrideHalfSteps: 9,
            seasonHalfSteps: [2, 4]
        ) == 9)
        #expect(ActivityProjection.derivedRating(
            overrideHalfSteps: nil,
            seasonHalfSteps: []
        ) == nil)
    }

    @Test("A session preserves and normalizes page progress")
    func pageProgress() {
        let item = LibraryItem(mediaKind: .book, title: "The Left Hand of Darkness")
        let cycle = ConsumptionCycle(item: item, kind: .initial, ordinal: 0)
        let session = ConsumptionSession(cycle: cycle)
        session.currentPage = 135
        session.totalPagesSnapshot = 300

        #expect(session.progressFraction == 0.45)
    }

    @Test("Progress is clamped for imported snapshots")
    func clampsProgress() {
        let item = LibraryItem(mediaKind: .game, title: "Game")
        let cycle = ConsumptionCycle(item: item, kind: .initial, ordinal: 0)
        let session = ConsumptionSession(cycle: cycle)
        session.completionPercent = 125

        #expect(session.progressFraction == 1)
    }

    @Test("Unknown persisted enum values remain safe")
    func unknownRawValues() {
        let item = LibraryItem(mediaKind: .book, title: "Future title")
        item.mediaKindRaw = "future-media-kind"
        item.statusProjectionRaw = "future-status"

        #expect(item.mediaKind == .unknown)
        #expect(item.status == .unknown)
    }
}

