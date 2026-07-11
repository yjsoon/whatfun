import Foundation

enum SmartListField: String, CaseIterable, Identifiable, Sendable {
    case mediaKind
    case status
    case effectiveRating
    case genre
    case platform
    case tag
    case listMembership
    case progress
    case startDate
    case completionDate
    case lastSessionDate
    case favorite
    case repeatCount

    nonisolated var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .mediaKind: "Media Type"
        case .status: "Status"
        case .effectiveRating: "Rating"
        case .genre: "Genre"
        case .platform: "Platform"
        case .tag: "Tag"
        case .listMembership: "List Membership"
        case .progress: "Progress"
        case .startDate: "Start Date"
        case .completionDate: "Completion Date"
        case .lastSessionDate: "Last Session Date"
        case .favorite: "Favorite"
        case .repeatCount: "Repeat Count"
        }
    }

    var valueKind: SmartRuleValueKind {
        switch self {
        case .mediaKind, .status: .selection
        case .genre, .platform, .tag, .listMembership: .referenceSelection
        case .effectiveRating, .progress, .repeatCount: .number
        case .startDate, .completionDate, .lastSessionDate: .date
        case .favorite: .boolean
        }
    }

    var allowedOperators: [SmartRuleOperator] {
        switch valueKind {
        case .selection, .referenceSelection:
            [.equals, .notEquals, .containsAny, .containsNone]
        case .number:
            [.equals, .notEquals, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .isSet, .isNotSet]
        case .date:
            [.before, .after, .onOrBefore, .onOrAfter, .isSet, .isNotSet]
        case .boolean:
            [.equals, .notEquals]
        }
    }
}

enum SmartRuleValueKind: Sendable {
    case selection
    case referenceSelection
    case number
    case date
    case boolean
}

enum SmartRuleOperator: String, CaseIterable, Identifiable, Sendable {
    case equals
    case notEquals
    case containsAny
    case containsNone
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case before
    case after
    case onOrBefore
    case onOrAfter
    case isSet
    case isNotSet

    nonisolated var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .equals: "Is"
        case .notEquals: "Is Not"
        case .containsAny: "Contains Any"
        case .containsNone: "Contains None"
        case .greaterThan: "Is Greater Than"
        case .greaterThanOrEqual: "Is At Least"
        case .lessThan: "Is Less Than"
        case .lessThanOrEqual: "Is At Most"
        case .before: "Is Before"
        case .after: "Is After"
        case .onOrBefore: "Is On or Before"
        case .onOrAfter: "Is On or After"
        case .isSet: "Has a Value"
        case .isNotSet: "Has No Value"
        }
    }
}

@MainActor
enum SmartListEvaluator {
    static func matches(
        _ item: LibraryItem,
        list: UserList,
        allLists: [UserList] = []
    ) -> Bool {
        guard list.kind == .smart else {
            return (list.memberships ?? []).contains { $0.itemID == item.id }
        }

        let evaluations = (list.smartRules ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { evaluate($0, item: item, allLists: allLists) }

        // Unknown fields/operators are ignored when known rules remain. An entirely
        // unsupported or empty smart list matches nothing rather than everything.
        guard !evaluations.isEmpty else { return false }
        switch list.matchMode {
        case .all:
            return evaluations.allSatisfy(\.self)
        case .any:
            return evaluations.contains(true)
        case .unknown:
            return false
        }
    }

    static func items(
        matching list: UserList,
        from items: [LibraryItem],
        allLists: [UserList] = []
    ) -> [LibraryItem] {
        items.filter { item in
            item.trashedAt == nil && matches(item, list: list, allLists: allLists)
        }
    }

    private static func evaluate(
        _ rule: SmartRule,
        item: LibraryItem,
        allLists: [UserList]
    ) -> Bool? {
        guard let field = SmartListField(rawValue: rule.fieldRaw),
              let operation = SmartRuleOperator(rawValue: rule.operatorRaw),
              field.allowedOperators.contains(operation) else {
            return nil
        }

        let values = (rule.values ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let result: Bool

        switch field {
        case .mediaKind:
            result = compareStrings(
                candidate: item.mediaKindRaw,
                accepted: values.compactMap(\.stringValue),
                operation: operation
            )
        case .status:
            result = compareStrings(
                candidate: item.statusProjectionRaw,
                accepted: values.compactMap(\.stringValue),
                operation: operation
            )
        case .effectiveRating:
            result = compareNumber(
                candidate: item.effectiveRatingHalfSteps.map { Double($0) / 2 },
                values: values.compactMap(\.numberValue),
                operation: operation
            )
        case .progress:
            result = compareNumber(
                candidate: item.progressFraction.map { $0 * 100 },
                values: values.compactMap(\.numberValue),
                operation: operation
            )
        case .repeatCount:
            result = compareNumber(
                candidate: Double(item.repeatCount),
                values: values.compactMap(\.numberValue),
                operation: operation
            )
        case .startDate:
            result = compareDate(
                candidate: item.firstStartedAt,
                values: values.compactMap(\.dateValue),
                operation: operation
            )
        case .completionDate:
            result = compareDate(
                candidate: item.lastCompletedAt,
                values: values.compactMap(\.dateValue),
                operation: operation
            )
        case .lastSessionDate:
            result = compareDate(
                candidate: item.lastSessionAt,
                values: values.compactMap(\.dateValue),
                operation: operation
            )
        case .favorite:
            result = compareBoolean(
                candidate: item.isFavorite,
                values: values.compactMap(\.boolValue),
                operation: operation
            )
        case .genre:
            result = compareFacets(
                item: item,
                kind: .genre,
                values: values,
                operation: operation
            )
        case .platform:
            result = compareFacets(
                item: item,
                kind: .platform,
                values: values,
                operation: operation
            )
        case .tag:
            result = compareFacets(
                item: item,
                kind: .tag,
                values: values,
                operation: operation
            )
        case .listMembership:
            let memberships = Set((item.listMemberships ?? []).map(\.listID))
            let listIDs = Set(values.compactMap(\.referenceID))
            let fallbackIDs = Set(values.compactMap(\.stringValue).compactMap(UUID.init(uuidString:)))
            let accepted = listIDs.union(fallbackIDs)
            // If a list catalogue is available, stale references match nothing.
            // With no catalogue (for example during an incremental import), stable
            // identifiers still evaluate without requiring relationship hydration.
            let knownIDs = Set(allLists.map(\.id))
            let resolved = knownIDs.isEmpty ? accepted : accepted.intersection(knownIDs)
            result = compareSets(
                candidate: memberships,
                accepted: resolved,
                operation: operation
            )
        }

        return rule.isNegated ? !result : result
    }

    private static func compareStrings(
        candidate: String,
        accepted: [String],
        operation: SmartRuleOperator
    ) -> Bool {
        guard !accepted.isEmpty else { return false }
        let matches = accepted.contains(candidate)
        return switch operation {
        case .equals, .containsAny: matches
        case .notEquals, .containsNone: !matches
        default: false
        }
    }

    private static func compareNumber(
        candidate: Double?,
        values: [Double],
        operation: SmartRuleOperator
    ) -> Bool {
        if operation == .isSet { return candidate != nil }
        if operation == .isNotSet { return candidate == nil }
        guard let candidate, let value = values.first else { return false }

        return switch operation {
        case .equals: abs(candidate - value) < 0.000_001
        case .notEquals: abs(candidate - value) >= 0.000_001
        case .greaterThan: candidate > value
        case .greaterThanOrEqual: candidate >= value
        case .lessThan: candidate < value
        case .lessThanOrEqual: candidate <= value
        default: false
        }
    }

    private static func compareDate(
        candidate: Date?,
        values: [Date],
        operation: SmartRuleOperator
    ) -> Bool {
        if operation == .isSet { return candidate != nil }
        if operation == .isNotSet { return candidate == nil }
        guard let candidate, let value = values.first else { return false }

        return switch operation {
        case .before: candidate < value
        case .after: candidate > value
        case .onOrBefore: candidate <= value
        case .onOrAfter: candidate >= value
        default: false
        }
    }

    private static func compareBoolean(
        candidate: Bool,
        values: [Bool],
        operation: SmartRuleOperator
    ) -> Bool {
        guard let value = values.first else { return false }
        return switch operation {
        case .equals: candidate == value
        case .notEquals: candidate != value
        default: false
        }
    }

    private static func compareFacets(
        item: LibraryItem,
        kind: FacetKind,
        values: [SmartRuleValue],
        operation: SmartRuleOperator
    ) -> Bool {
        guard !values.isEmpty else { return false }
        let facets = (item.facetMemberships ?? [])
            .compactMap(\.facet)
            .filter { $0.kind == kind }
        let candidateIDs = Set(facets.map(\.id))
        let candidateNames = Set(facets.map(\.normalizedName))
        let acceptedIDs = Set(values.compactMap(\.referenceID))
        let acceptedNames = Set(values.compactMap(\.stringValue).map(LibraryItem.normalize))
        let overlaps = !candidateIDs.isDisjoint(with: acceptedIDs) ||
            !candidateNames.isDisjoint(with: acceptedNames)

        return switch operation {
        case .equals, .containsAny: overlaps
        case .notEquals, .containsNone: !overlaps
        default: false
        }
    }

    private static func compareSets<T: Hashable>(
        candidate: Set<T>,
        accepted: Set<T>,
        operation: SmartRuleOperator
    ) -> Bool {
        guard !accepted.isEmpty else { return false }
        let overlaps = !candidate.isDisjoint(with: accepted)
        return switch operation {
        case .equals, .containsAny: overlaps
        case .notEquals, .containsNone: !overlaps
        default: false
        }
    }
}
