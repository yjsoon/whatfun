import Foundation
import Testing
@testable import WhatFun

@Suite("Smart list evaluator")
@MainActor
struct SmartListEvaluatorTests {
    @Test("Match All requires every supported rule")
    func matchAll() {
        let list = UserList(name: "Watching favorites", kind: .smart, matchMode: .all)
        list.smartRules = [
            rule(list, field: .mediaKind, strings: [MediaKind.tvShow.rawValue]),
            rule(list, field: .status, strings: [ConsumptionStatus.inProgress.rawValue]),
            rule(list, field: .favorite, bools: [true]),
        ]

        let item = LibraryItem(mediaKind: .tvShow, title: "The Bear")
        item.status = .inProgress
        item.isFavorite = true
        #expect(SmartListEvaluator.matches(item, list: list))

        item.isFavorite = false
        #expect(!SmartListEvaluator.matches(item, list: list))
    }

    @Test("Match Any accepts one matching rule")
    func matchAny() {
        let list = UserList(name: "Loved or replayed", kind: .smart, matchMode: .any)
        list.smartRules = [
            rule(
                list,
                field: .effectiveRating,
                operation: .greaterThanOrEqual,
                numbers: [4.5]
            ),
            rule(
                list,
                field: .repeatCount,
                operation: .greaterThanOrEqual,
                numbers: [2]
            ),
        ]

        let item = LibraryItem(mediaKind: .game, title: "Hades")
        item.effectiveRatingHalfSteps = 8
        item.repeatCount = 3
        #expect(SmartListEvaluator.matches(item, list: list))

        item.repeatCount = 0
        #expect(!SmartListEvaluator.matches(item, list: list))
    }

    @Test("Facet and manual-list membership rules use stable identities")
    func relationships() {
        let sourceList = UserList(name: "Comfort media")
        let smartList = UserList(name: "Tagged comfort", kind: .smart, matchMode: .all)
        let tag = Facet(kind: .tag, name: "Comfort")
        let item = LibraryItem(mediaKind: .book, title: "A Psalm for the Wild-Built")

        let facetMembership = ItemFacetMembership(item: item, facet: tag)
        item.facetMemberships = [facetMembership]
        let listMembership = ListMembership(
            list: sourceList,
            item: item,
            positionRank: "000001"
        )
        item.listMemberships = [listMembership]

        smartList.smartRules = [
            rule(
                smartList,
                field: .tag,
                operation: .containsAny,
                references: [tag.id]
            ),
            rule(
                smartList,
                field: .listMembership,
                operation: .containsAny,
                references: [sourceList.id]
            ),
        ]

        #expect(SmartListEvaluator.matches(
            item,
            list: smartList,
            allLists: [sourceList, smartList]
        ))
    }

    @Test("Progress and history dates compare in user-facing units")
    func progressAndDates() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let list = UserList(name: "Recently finished halfway-plus", kind: .smart, matchMode: .all)
        list.smartRules = [
            rule(
                list,
                field: .progress,
                operation: .greaterThanOrEqual,
                numbers: [50]
            ),
            rule(
                list,
                field: .completionDate,
                operation: .onOrAfter,
                dates: [cutoff]
            ),
        ]

        let item = LibraryItem(mediaKind: .movie, title: "Past Lives")
        item.progressFraction = 0.75
        item.lastCompletedAt = cutoff.addingTimeInterval(60)
        #expect(SmartListEvaluator.matches(item, list: list))

        item.progressFraction = 0.2
        #expect(!SmartListEvaluator.matches(item, list: list))
    }

    @Test("Unknown rules are ignored safely")
    func unknownRules() {
        let list = UserList(name: "Forward compatible", kind: .smart, matchMode: .all)
        let unknown = SmartRule(
            list: list,
            fieldRaw: "futureField",
            operatorRaw: "futureOperator"
        )
        list.smartRules = [unknown]
        let item = LibraryItem(mediaKind: .podcast, title: "Decoder Ring")

        #expect(!SmartListEvaluator.matches(item, list: list))

        list.smartRules = [
            unknown,
            rule(list, field: .mediaKind, strings: [MediaKind.podcast.rawValue]),
        ]
        #expect(SmartListEvaluator.matches(item, list: list))
    }

    private func rule(
        _ list: UserList,
        field: SmartListField,
        operation: SmartRuleOperator = .equals,
        strings: [String] = [],
        numbers: [Double] = [],
        dates: [Date] = [],
        bools: [Bool] = [],
        references: [UUID] = []
    ) -> SmartRule {
        let rule = SmartRule(
            list: list,
            fieldRaw: field.rawValue,
            operatorRaw: operation.rawValue
        )
        var values: [SmartRuleValue] = []
        values += strings.enumerated().map { index, value in
            SmartRuleValue(
                rule: rule,
                valueTypeRaw: "string",
                stringValue: value,
                sortOrder: index
            )
        }
        values += numbers.enumerated().map { index, value in
            SmartRuleValue(
                rule: rule,
                valueTypeRaw: "number",
                numberValue: value,
                sortOrder: values.count + index
            )
        }
        values += dates.enumerated().map { index, value in
            SmartRuleValue(
                rule: rule,
                valueTypeRaw: "date",
                dateValue: value,
                sortOrder: values.count + index
            )
        }
        values += bools.enumerated().map { index, value in
            SmartRuleValue(
                rule: rule,
                valueTypeRaw: "bool",
                boolValue: value,
                sortOrder: values.count + index
            )
        }
        values += references.enumerated().map { index, value in
            SmartRuleValue(
                rule: rule,
                valueTypeRaw: "reference",
                referenceID: value,
                sortOrder: values.count + index
            )
        }
        rule.values = values
        return rule
    }
}

