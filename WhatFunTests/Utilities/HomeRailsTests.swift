import Foundation
import Testing
@testable import WhatFun

@Suite("Home rail classification")
struct HomeRailsTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_000_000)
    private nonisolated static let past = Date(timeIntervalSince1970: 999_000)
    private nonisolated static let future = Date(timeIntervalSince1970: 1_001_000)

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let entries: [(name: String, snapshot: HomeRails.Snapshot)]
        let active: [String]
        let planned: [String]
        let overdue: [String]

        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "planned only",
            entries: [
                ("book", HomeRails.Snapshot(status: .planned)),
                ("film", HomeRails.Snapshot(status: .planned)),
            ],
            active: [],
            planned: ["book", "film"],
            overdue: []
        ),
        Case(
            name: "active only",
            entries: [
                ("book", HomeRails.Snapshot(status: .inProgress)),
                ("game", HomeRails.Snapshot(status: .paused)),
            ],
            active: ["book", "game"],
            planned: [],
            overdue: []
        ),
        Case(
            name: "mixed statuses keep rails ordered and exclusive",
            entries: [
                ("reading", HomeRails.Snapshot(status: .inProgress)),
                ("queued", HomeRails.Snapshot(status: .planned)),
                ("finished", HomeRails.Snapshot(status: .completed)),
                ("abandoned", HomeRails.Snapshot(status: .dropped)),
            ],
            active: ["reading"],
            planned: ["queued"],
            overdue: []
        ),
        Case(
            name: "planned followed podcast lands in exactly one rail",
            entries: [
                ("podcast", HomeRails.Snapshot(status: .planned, isFollowedPodcast: true)),
                ("book", HomeRails.Snapshot(status: .planned)),
            ],
            active: ["podcast"],
            planned: ["book"],
            overdue: []
        ),
        Case(
            name: "overdue reminders only fire for past pending dates",
            entries: [
                ("late", HomeRails.Snapshot(status: .planned, earliestPendingReminderFireDate: past)),
                ("upcoming", HomeRails.Snapshot(status: .planned, earliestPendingReminderFireDate: future)),
                ("started", HomeRails.Snapshot(status: .inProgress, earliestPendingReminderFireDate: past)),
            ],
            active: ["started"],
            planned: ["late", "upcoming"],
            overdue: ["late"]
        ),
    ]

    @Test("Partitions items into the expected rails", arguments: cases)
    func partitions(testCase: Case) {
        let snapshots = Dictionary(uniqueKeysWithValues: testCase.entries.map { ($0.name, $0.snapshot) })

        let partition = HomeRails.partition(
            testCase.entries.map(\.name),
            now: Self.now
        ) { snapshots[$0]! }

        #expect(partition.active == testCase.active)
        #expect(partition.planned == testCase.planned)
        #expect(partition.overdue == testCase.overdue)
    }

    @Test("Active and planned rails never share an item")
    func railsAreDisjoint() {
        let snapshots: [HomeRails.Snapshot] = ConsumptionStatus.allCases.flatMap { status in
            [
                HomeRails.Snapshot(status: status),
                HomeRails.Snapshot(status: status, isFollowedPodcast: true),
            ]
        }

        let partition = HomeRails.partition(snapshots.indices, now: Self.now) { snapshots[$0] }

        #expect(Set(partition.active).isDisjoint(with: partition.planned))
    }
}
