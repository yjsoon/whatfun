import Foundation
import SwiftData

struct SessionProgress: Sendable, Equatable {
    var currentPage: Int?
    var totalPages: Int?
    var chapter: String?
    var elapsedSeconds: Int?
    var mediaDurationSeconds: Int?
    var gamePlaytimeDeltaSeconds: Int?
    var gamePlaytimeTotalSeconds: Int?
    var completionPercent: Double?

    init(
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        chapter: String? = nil,
        elapsedSeconds: Int? = nil,
        mediaDurationSeconds: Int? = nil,
        gamePlaytimeDeltaSeconds: Int? = nil,
        gamePlaytimeTotalSeconds: Int? = nil,
        completionPercent: Double? = nil
    ) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.chapter = chapter
        self.elapsedSeconds = elapsedSeconds
        self.mediaDurationSeconds = mediaDurationSeconds
        self.gamePlaytimeDeltaSeconds = gamePlaytimeDeltaSeconds
        self.gamePlaytimeTotalSeconds = gamePlaytimeTotalSeconds
        self.completionPercent = completionPercent
    }
}

enum ActivityServiceError: Error, LocalizedError, Equatable {
    case itemIsTrashed
    case targetBelongsToAnotherItem
    case cycleBelongsToAnotherItem
    case completedCycleRequiresChoice

    var errorDescription: String? {
        switch self {
        case .itemIsTrashed:
            "Restore this item before logging activity."
        case .targetBelongsToAnotherItem:
            "The selected installment belongs to another item."
        case .cycleBelongsToAnotherItem:
            "The selected consumption cycle belongs to another item."
        case .completedCycleRequiresChoice:
            "Choose whether to add to the previous cycle or start a repeat."
        }
    }
}

@MainActor
final class ActivityService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func register(_ item: LibraryItem, at date: Date = .now) throws -> ActivityEvent {
        context.insert(item)
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .created,
            toStatus: .planned,
            effectiveAt: date
        )
        insert(event, into: item)
        ActivityProjection.rebuild(item)
        try context.save()
        return event
    }

    @discardableResult
    func startCycle(
        for item: LibraryItem,
        targetUnit: ContentUnit? = nil,
        kind: ConsumptionCycleKind = .initial,
        at date: Date = .now,
        source: RecordSource = .manual
    ) throws -> ConsumptionCycle {
        try validate(item: item, targetUnit: targetUnit)
        let cycle = makeCycle(
            for: item,
            targetUnit: targetUnit,
            kind: kind,
            at: date,
            source: source
        )
        ActivityProjection.rebuild(item)
        try context.save()
        return cycle
    }

    @discardableResult
    func startRepeat(
        for item: LibraryItem,
        targetUnit: ContentUnit? = nil,
        at date: Date = .now
    ) throws -> ConsumptionCycle {
        try startCycle(
            for: item,
            targetUnit: targetUnit,
            kind: .repeatConsumption,
            at: date
        )
    }

    @discardableResult
    func startNextInstallment(
        for item: LibraryItem,
        targetUnit: ContentUnit,
        at date: Date = .now
    ) throws -> ConsumptionCycle {
        try startCycle(
            for: item,
            targetUnit: targetUnit,
            kind: .installmentContinuation,
            at: date
        )
    }

    @discardableResult
    func logSession(
        for item: LibraryItem,
        targetUnit: ContentUnit? = nil,
        in explicitCycle: ConsumptionCycle? = nil,
        at date: Date = .now,
        durationSeconds: Int? = nil,
        note: String? = nil,
        progress: SessionProgress = SessionProgress(),
        source: RecordSource = .manual,
        timeZone: TimeZone = .current
    ) throws -> ConsumptionSession {
        try validate(item: item, targetUnit: targetUnit)
        guard explicitCycle?.rootItemID == item.id || explicitCycle == nil else {
            throw ActivityServiceError.cycleBelongsToAnotherItem
        }

        let cycle: ConsumptionCycle
        if let explicitCycle {
            cycle = explicitCycle
        } else if let active = activeCycle(for: item, targetUnit: targetUnit) {
            cycle = active
        } else {
            let matching = matchingCycles(for: item, targetUnit: targetUnit)
            if matching.contains(where: { $0.status == .completed }) {
                throw ActivityServiceError.completedCycleRequiresChoice
            }
            cycle = makeCycle(
                for: item,
                targetUnit: targetUnit,
                kind: .initial,
                at: date,
                source: source
            )
        }

        if cycle.status == .paused || cycle.status == .dropped ||
            item.status == .paused || item.status == .dropped {
            let previousStatus = cycle.status == .paused || cycle.status == .dropped
                ? cycle.status
                : item.status
            let resume = ActivityEvent(
                item: item,
                cycle: cycle,
                targetUnit: targetUnit ?? cycle.targetUnit,
                scope: (targetUnit ?? cycle.targetUnit) == nil ? .item : .unit,
                kind: .reopened,
                fromStatus: previousStatus,
                toStatus: .inProgress,
                effectiveAt: date,
                timeZoneIdentifier: timeZone.identifier,
                source: source
            )
            insert(resume, into: item, cycle: cycle)
        }

        let session = ConsumptionSession(
            cycle: cycle,
            targetUnit: targetUnit,
            occurredAt: date,
            timeZoneIdentifier: timeZone.identifier,
            durationSeconds: durationSeconds,
            note: note,
            source: source
        )
        session.currentPage = progress.currentPage
        session.totalPagesSnapshot = progress.totalPages
        session.chapter = progress.chapter
        session.elapsedSeconds = progress.elapsedSeconds
        session.mediaDurationSecondsSnapshot = progress.mediaDurationSeconds
        session.gamePlaytimeDeltaSeconds = progress.gamePlaytimeDeltaSeconds
        session.gamePlaytimeTotalSnapshotSeconds = progress.gamePlaytimeTotalSeconds
        session.completionPercent = progress.completionPercent.map { min(max($0, 0), 100) }
        context.insert(session)
        attach(session, to: cycle)

        ActivityProjection.rebuild(item)
        try context.save()
        return session
    }

    @discardableResult
    func markDone(
        item: LibraryItem,
        cycle: ConsumptionCycle,
        targetUnit: ContentUnit? = nil,
        at date: Date = .now,
        ratingHalfSteps: Int? = nil,
        note: String? = nil,
        source: RecordSource = .manual,
        timeZone: TimeZone = .current
    ) throws -> ActivityEvent {
        try validate(item: item, targetUnit: targetUnit ?? cycle.targetUnit)
        guard cycle.rootItemID == item.id else {
            throw ActivityServiceError.cycleBelongsToAnotherItem
        }

        let target = targetUnit ?? cycle.targetUnit
        let event = ActivityEvent(
            item: item,
            cycle: cycle,
            targetUnit: target,
            scope: target == nil ? .item : .unit,
            kind: .completed,
            fromStatus: cycle.status,
            toStatus: .completed,
            effectiveAt: date,
            timeZoneIdentifier: timeZone.identifier,
            note: note,
            source: source
        )
        insert(event, into: item, cycle: cycle)

        if let ratingHalfSteps {
            if let target {
                target.setRating(halfSteps: ratingHalfSteps)
            } else {
                item.setRating(halfSteps: ratingHalfSteps)
            }
        }

        ActivityProjection.rebuild(item)

        // Series completion is also recorded at item scope. A newly discovered
        // season or volume can then raise hasNewInstallment without erasing the
        // earlier completion from history.
        if target != nil,
           (item.mediaKind == .tvShow || item.mediaKind == .comic),
           item.status == .completed {
            let aggregateCompletion = ActivityEvent(
                item: item,
                scope: .item,
                kind: .completed,
                fromStatus: .inProgress,
                toStatus: .completed,
                effectiveAt: date,
                timeZoneIdentifier: timeZone.identifier,
                note: note,
                source: source
            )
            insert(aggregateCompletion, into: item)
            ActivityProjection.rebuild(item)
        }
        try context.save()
        return event
    }

    @discardableResult
    func setStatus(
        _ status: ConsumptionStatus,
        for item: LibraryItem,
        cycle: ConsumptionCycle? = nil,
        targetUnit: ContentUnit? = nil,
        at date: Date = .now,
        note: String? = nil
    ) throws -> ActivityEvent {
        try validate(item: item, targetUnit: targetUnit)
        let scope: ActivityScope = targetUnit == nil ? .item : .unit
        let oldStatus = cycle?.status ?? targetUnit?.status ?? item.status
        let kind: ActivityEventKind = status == .completed ? .completed : .statusSet
        let event = ActivityEvent(
            item: item,
            cycle: cycle,
            targetUnit: targetUnit,
            scope: scope,
            kind: kind,
            fromStatus: oldStatus,
            toStatus: status,
            effectiveAt: date,
            note: note
        )
        insert(event, into: item, cycle: cycle)
        ActivityProjection.rebuild(item)
        try context.save()
        return event
    }

    func archive(_ item: LibraryItem, at date: Date = .now) throws {
        item.archivedAt = date
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .archived,
            effectiveAt: date
        )
        insert(event, into: item)
        try context.save()
    }

    func restoreFromArchive(_ item: LibraryItem, at date: Date = .now) throws {
        item.archivedAt = nil
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .restored,
            effectiveAt: date
        )
        insert(event, into: item)
        try context.save()
    }

    func moveToTrash(
        _ item: LibraryItem,
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws {
        item.trashedAt = date
        item.purgeAfter = calendar.date(byAdding: .day, value: 30, to: date)
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .trashed,
            effectiveAt: date
        )
        insert(event, into: item)
        try context.save()
    }

    func recoverFromTrash(_ item: LibraryItem, at date: Date = .now) throws {
        item.trashedAt = nil
        item.purgeAfter = nil
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .recovered,
            effectiveAt: date
        )
        insert(event, into: item)
        try context.save()
    }

    private func makeCycle(
        for item: LibraryItem,
        targetUnit: ContentUnit?,
        kind: ConsumptionCycleKind,
        at date: Date,
        source: RecordSource
    ) -> ConsumptionCycle {
        let existing = matchingCycles(for: item, targetUnit: targetUnit)
        let previous = existing.max { $0.ordinal < $1.ordinal }
        let cycle = ConsumptionCycle(
            item: item,
            targetUnit: targetUnit,
            kind: kind,
            ordinal: (existing.map(\.ordinal).max() ?? -1) + 1,
            repeatOfCycleID: kind == .repeatConsumption ? previous?.id : nil,
            createdAt: date
        )
        context.insert(cycle)
        attach(cycle, to: item)

        let event = ActivityEvent(
            item: item,
            cycle: cycle,
            targetUnit: targetUnit,
            scope: targetUnit == nil ? .item : .unit,
            kind: .started,
            fromStatus: .planned,
            toStatus: .inProgress,
            effectiveAt: date,
            source: source
        )
        insert(event, into: item, cycle: cycle)
        return cycle
    }

    private func validate(item: LibraryItem, targetUnit: ContentUnit?) throws {
        guard item.trashedAt == nil else {
            throw ActivityServiceError.itemIsTrashed
        }
        guard targetUnit?.rootItemID == item.id || targetUnit == nil else {
            throw ActivityServiceError.targetBelongsToAnotherItem
        }
    }

    private func matchingCycles(
        for item: LibraryItem,
        targetUnit: ContentUnit?
    ) -> [ConsumptionCycle] {
        (item.cycles ?? []).filter {
            $0.deletedAt == nil && $0.targetUnitID == targetUnit?.id
        }
    }

    private func activeCycle(
        for item: LibraryItem,
        targetUnit: ContentUnit?
    ) -> ConsumptionCycle? {
        matchingCycles(for: item, targetUnit: targetUnit)
            .filter { $0.status == .inProgress || $0.status == .paused }
            .max { $0.ordinal < $1.ordinal }
    }

    private func insert(
        _ event: ActivityEvent,
        into item: LibraryItem,
        cycle: ConsumptionCycle? = nil
    ) {
        context.insert(event)
        if !(item.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            item.activityEvents = (item.activityEvents ?? []) + [event]
        }
        if let cycle,
           !(cycle.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            cycle.activityEvents = (cycle.activityEvents ?? []) + [event]
        }
    }

    private func attach(_ cycle: ConsumptionCycle, to item: LibraryItem) {
        if !(item.cycles ?? []).contains(where: { $0.id == cycle.id }) {
            item.cycles = (item.cycles ?? []) + [cycle]
        }
    }

    private func attach(_ session: ConsumptionSession, to cycle: ConsumptionCycle) {
        if !(cycle.sessions ?? []).contains(where: { $0.id == session.id }) {
            cycle.sessions = (cycle.sessions ?? []) + [session]
        }
    }
}
