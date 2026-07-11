import Foundation
import SwiftData

@Model
final class ConsumptionCycle {
    #Index<ConsumptionCycle>(
        [\.rootItemID, \.targetUnitID, \.ordinal],
        [\.lastSessionAt],
        [\.deletedAt]
    )

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var targetUnitID: UUID?
    var ordinal: Int = 0
    var cycleKindRaw: String = ConsumptionCycleKind.initial.rawValue
    var repeatOfCycleID: UUID?
    var statusProjectionRaw: String = ConsumptionStatus.planned.rawValue
    var startedAt: Date?
    var completedAt: Date?
    var lastSessionAt: Date?
    var progressFraction: Double?
    var sessionCount: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var item: LibraryItem?
    var targetUnit: ContentUnit?

    @Relationship(deleteRule: .cascade, inverse: \ConsumptionSession.cycle)
    var sessions: [ConsumptionSession]?

    @Relationship(deleteRule: .nullify, inverse: \ActivityEvent.cycle)
    var activityEvents: [ActivityEvent]?

    init(
        id: UUID = UUID(),
        item: LibraryItem,
        targetUnit: ContentUnit? = nil,
        kind: ConsumptionCycleKind,
        ordinal: Int,
        repeatOfCycleID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = item.id
        self.targetUnitID = targetUnit?.id
        self.ordinal = ordinal
        self.cycleKindRaw = kind.rawValue
        self.repeatOfCycleID = repeatOfCycleID
        self.item = item
        self.targetUnit = targetUnit
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var cycleKind: ConsumptionCycleKind {
        get { ConsumptionCycleKind.value(for: cycleKindRaw) }
        set { cycleKindRaw = newValue.rawValue }
    }

    var status: ConsumptionStatus {
        get { ConsumptionStatus.value(for: statusProjectionRaw) }
        set { statusProjectionRaw = newValue.rawValue }
    }
}

@Model
final class ConsumptionSession {
    #Index<ConsumptionSession>(
        [\.occurredAt],
        [\.rootItemID, \.occurredAt],
        [\.targetUnitID, \.occurredAt],
        [\.deletedAt]
    )

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var cycleID: UUID = UUID()
    var targetUnitID: UUID?
    var occurredAt: Date = Date.now
    var endedAt: Date?
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var durationSeconds: Int?
    var note: String?
    var sourceRaw: String = RecordSource.manual.rawValue

    // Absolute progress after this session. Keeping each snapshot preserves history.
    var currentPage: Int?
    var totalPagesSnapshot: Int?
    var chapter: String?
    var elapsedSeconds: Int?
    var mediaDurationSecondsSnapshot: Int?
    var gamePlaytimeDeltaSeconds: Int?
    var gamePlaytimeTotalSnapshotSeconds: Int?
    var completionPercent: Double?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var cycle: ConsumptionCycle?
    var targetUnit: ContentUnit?

    init(
        id: UUID = UUID(),
        cycle: ConsumptionCycle,
        targetUnit: ContentUnit? = nil,
        occurredAt: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        durationSeconds: Int? = nil,
        note: String? = nil,
        source: RecordSource = .manual
    ) {
        self.id = id
        self.rootItemID = cycle.rootItemID
        self.cycleID = cycle.id
        self.targetUnitID = targetUnit?.id ?? cycle.targetUnitID
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.durationSeconds = durationSeconds
        self.note = note
        self.sourceRaw = source.rawValue
        self.cycle = cycle
        self.targetUnit = targetUnit ?? cycle.targetUnit
        self.createdAt = .now
        self.updatedAt = .now
    }

    var source: RecordSource {
        get { RecordSource.value(for: sourceRaw) }
        set { sourceRaw = newValue.rawValue }
    }

    /// A normalized progress value when a meaningful total is available.
    var progressFraction: Double? {
        if let currentPage, let totalPagesSnapshot, totalPagesSnapshot > 0 {
            return Self.clamp(Double(currentPage) / Double(totalPagesSnapshot))
        }
        if let elapsedSeconds,
           let mediaDurationSecondsSnapshot,
           mediaDurationSecondsSnapshot > 0 {
            return Self.clamp(Double(elapsedSeconds) / Double(mediaDurationSecondsSnapshot))
        }
        if let completionPercent {
            return Self.clamp(completionPercent / 100)
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

@Model
final class ActivityEvent {
    #Index<ActivityEvent>(
        [\.rootItemID, \.effectiveAt],
        [\.cycleID, \.effectiveAt],
        [\.targetUnitID, \.effectiveAt]
    )

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var cycleID: UUID?
    var targetUnitID: UUID?
    var scopeRaw: String = ActivityScope.item.rawValue
    var eventKindRaw: String = ActivityEventKind.statusSet.rawValue
    var fromStatusRaw: String?
    var toStatusRaw: String?
    var effectiveAt: Date = Date.now
    var recordedAt: Date = Date.now
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var note: String?
    var sourceRaw: String = RecordSource.manual.rawValue

    var item: LibraryItem?
    var cycle: ConsumptionCycle?
    var targetUnit: ContentUnit?

    init(
        id: UUID = UUID(),
        item: LibraryItem,
        cycle: ConsumptionCycle? = nil,
        targetUnit: ContentUnit? = nil,
        scope: ActivityScope,
        kind: ActivityEventKind,
        fromStatus: ConsumptionStatus? = nil,
        toStatus: ConsumptionStatus? = nil,
        effectiveAt: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        note: String? = nil,
        source: RecordSource = .manual
    ) {
        self.id = id
        self.rootItemID = item.id
        self.cycleID = cycle?.id
        self.targetUnitID = targetUnit?.id
        self.scopeRaw = scope.rawValue
        self.eventKindRaw = kind.rawValue
        self.fromStatusRaw = fromStatus?.rawValue
        self.toStatusRaw = toStatus?.rawValue
        self.effectiveAt = effectiveAt
        self.recordedAt = .now
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.sourceRaw = source.rawValue
        self.item = item
        self.cycle = cycle
        self.targetUnit = targetUnit
    }

    var scope: ActivityScope {
        get { ActivityScope.value(for: scopeRaw) }
        set { scopeRaw = newValue.rawValue }
    }

    var kind: ActivityEventKind {
        get { ActivityEventKind.value(for: eventKindRaw) }
        set { eventKindRaw = newValue.rawValue }
    }

    var fromStatus: ConsumptionStatus? {
        fromStatusRaw.map(ConsumptionStatus.value(for:))
    }

    var toStatus: ConsumptionStatus? {
        toStatusRaw.map(ConsumptionStatus.value(for:))
    }

    var source: RecordSource {
        RecordSource.value(for: sourceRaw)
    }
}

@Model
final class NotableQuote {
    #Index<NotableQuote>([\.episodeUnitID, \.sortOrder], [\.deletedAt])

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var episodeUnitID: UUID = UUID()
    var sessionID: UUID?
    var text: String = ""
    var timestampSeconds: Int?
    var comment: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var episode: ContentUnit?

    init(
        id: UUID = UUID(),
        episode: ContentUnit,
        text: String,
        timestampSeconds: Int? = nil,
        comment: String? = nil,
        sortOrder: Int = 0,
        sessionID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = episode.rootItemID
        self.episodeUnitID = episode.id
        self.sessionID = sessionID
        self.text = text
        self.timestampSeconds = timestampSeconds
        self.comment = comment
        self.sortOrder = sortOrder
        self.episode = episode
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

