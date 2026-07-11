import Foundation
import SwiftData

@Model
final class Facet {
    #Index<Facet>([\.kindRaw, \.normalizedName])

    var id: UUID = UUID()
    var kindRaw: String = FacetKind.tag.rawValue
    var name: String = ""
    var normalizedName: String = ""
    var colorToken: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ItemFacetMembership.facet)
    var memberships: [ItemFacetMembership]?

    init(
        id: UUID = UUID(),
        kind: FacetKind,
        name: String,
        colorToken: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.name = name
        self.normalizedName = LibraryItem.normalize(name)
        self.colorToken = colorToken
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var kind: FacetKind {
        get { FacetKind.value(for: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class ItemFacetMembership {
    #Index<ItemFacetMembership>([\.itemID], [\.facetID])

    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var facetID: UUID = UUID()
    var sourceRaw: String = RecordSource.manual.rawValue
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    var item: LibraryItem?
    var facet: Facet?

    init(
        id: UUID = UUID(),
        item: LibraryItem,
        facet: Facet,
        source: RecordSource = .manual,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemID = item.id
        self.facetID = facet.id
        self.sourceRaw = source.rawValue
        self.sortOrder = sortOrder
        self.item = item
        self.facet = facet
        self.createdAt = createdAt
    }
}

@Model
final class UserList {
    #Index<UserList>([\.sortOrder], [\.trashedAt])

    var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    var iconName: String?
    var colorToken: String?
    var sortOrder: Int = 0
    var kindRaw: String = ListKind.manual.rawValue
    var matchModeRaw: String = SmartListMatchMode.all.rawValue
    var archivedAt: Date?
    var trashedAt: Date?
    var purgeAfter: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ListMembership.list)
    var memberships: [ListMembership]?

    @Relationship(deleteRule: .cascade, inverse: \SmartRule.list)
    var smartRules: [SmartRule]?

    init(
        id: UUID = UUID(),
        name: String,
        kind: ListKind = .manual,
        matchMode: SmartListMatchMode = .all,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.matchModeRaw = matchMode.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var kind: ListKind {
        get { ListKind.value(for: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    var matchMode: SmartListMatchMode {
        get { SmartListMatchMode.value(for: matchModeRaw) }
        set { matchModeRaw = newValue.rawValue }
    }
}

@Model
final class ListMembership {
    #Index<ListMembership>([\.listID, \.positionRank], [\.itemID])

    var id: UUID = UUID()
    var listID: UUID = UUID()
    var itemID: UUID = UUID()
    var positionRank: String = ""
    var addedAt: Date = Date.now

    var list: UserList?
    var item: LibraryItem?

    init(
        id: UUID = UUID(),
        list: UserList,
        item: LibraryItem,
        positionRank: String,
        addedAt: Date = .now
    ) {
        self.id = id
        self.listID = list.id
        self.itemID = item.id
        self.positionRank = positionRank
        self.list = list
        self.item = item
        self.addedAt = addedAt
    }
}

@Model
final class SmartRule {
    #Index<SmartRule>([\.listID, \.sortOrder], [\.fieldRaw])

    var id: UUID = UUID()
    var listID: UUID = UUID()
    var fieldRaw: String = "mediaKind"
    var operatorRaw: String = "equals"
    var isNegated: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var list: UserList?

    @Relationship(deleteRule: .cascade, inverse: \SmartRuleValue.rule)
    var values: [SmartRuleValue]?

    init(
        id: UUID = UUID(),
        list: UserList,
        fieldRaw: String,
        operatorRaw: String,
        isNegated: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.listID = list.id
        self.fieldRaw = fieldRaw
        self.operatorRaw = operatorRaw
        self.isNegated = isNegated
        self.sortOrder = sortOrder
        self.list = list
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class SmartRuleValue {
    #Index<SmartRuleValue>([\.ruleID], [\.referenceID])

    var id: UUID = UUID()
    var ruleID: UUID = UUID()
    var valueTypeRaw: String = "string"
    var stringValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
    var referenceID: UUID?
    var sortOrder: Int = 0

    var rule: SmartRule?

    init(
        id: UUID = UUID(),
        rule: SmartRule,
        valueTypeRaw: String,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil,
        referenceID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.ruleID = rule.id
        self.valueTypeRaw = valueTypeRaw
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
        self.referenceID = referenceID
        self.sortOrder = sortOrder
        self.rule = rule
    }
}

@Model
final class StartReminder {
    #Index<StartReminder>([\.stateRaw, \.fireAt], [\.itemID])

    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var fireAt: Date = Date.now
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var notificationIdentifier: String = UUID().uuidString
    var stateRaw: String = ReminderState.pending.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var item: LibraryItem?

    init(
        id: UUID = UUID(),
        item: LibraryItem,
        fireAt: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        notificationIdentifier: String = UUID().uuidString,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemID = item.id
        self.fireAt = fireAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.notificationIdentifier = notificationIdentifier
        self.item = item
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var state: ReminderState {
        get { ReminderState.value(for: stateRaw) }
        set { stateRaw = newValue.rawValue }
    }
}

