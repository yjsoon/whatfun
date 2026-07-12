import Foundation

enum ActivityProjection {
    static func latestStatus(
        events: [ActivityEvent],
        hasSessions: Bool,
        fallback: ConsumptionStatus = .planned
    ) -> ConsumptionStatus {
        if let status = sorted(events).last(where: { $0.toStatus != nil })?.toStatus {
            return status
        }
        return hasSessions ? .inProgress : fallback
    }

    static func latestProgress(in sessions: [ConsumptionSession]) -> Double? {
        sessions
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.occurredAt < rhs.occurredAt
            }
            .last?
            .progressFraction
    }

    static func derivedRating(
        overrideHalfSteps: Int?,
        seasonHalfSteps: [Int]
    ) -> Int? {
        if let overrideHalfSteps {
            return min(max(overrideHalfSteps, 1), 10)
        }

        let valid = seasonHalfSteps.filter { (1...10).contains($0) }
        guard !valid.isEmpty else { return nil }
        let average = Double(valid.reduce(0, +)) / Double(valid.count)
        return min(max(Int(average.rounded()), 1), 10)
    }

    static func repeatCount(in cycles: [ConsumptionCycle]) -> Int {
        cycles.lazy.filter {
            $0.deletedAt == nil && $0.cycleKind == .repeatConsumption
        }.count
    }

    // `touchUpdatedAt` lets history-preserving callers (backup restore) re-derive
    // projections without overwriting the archived `updatedAt`, which Home orders by.
    static func rebuild(_ item: LibraryItem, now: Date = .now, touchUpdatedAt: Bool = true) {
        let units = (item.units ?? []).filter { $0.deletedAt == nil }
        let cycles = (item.cycles ?? []).filter { $0.deletedAt == nil }
        let events = item.activityEvents ?? []

        for cycle in cycles {
            rebuild(cycle, events: events, touchUpdatedAt: touchUpdatedAt)
        }

        // Direct episode/issue state first, then aggregate seasons/volumes.
        for unit in units {
            rebuild(unit, events: events, touchUpdatedAt: touchUpdatedAt)
        }
        for unit in units where !(unit.children ?? []).isEmpty {
            aggregateChildren(into: unit, now: now)
        }

        let sessions = cycles.flatMap { $0.sessions ?? [] }
            .filter { $0.deletedAt == nil }
        let sortedSessions = sessions.sorted { $0.occurredAt < $1.occurredAt }

        item.cycleCount = cycles.count
        item.repeatCount = repeatCount(in: cycles)
        item.sessionCount = sessions.count
        let firstStartedEvent = events
            .filter { $0.kind == .started || $0.toStatus == .inProgress }
            .map(\.effectiveAt)
            .min()
        item.firstStartedAt = [sortedSessions.first?.occurredAt, firstStartedEvent]
            .compactMap { $0 }
            .min()
        item.lastSessionAt = sortedSessions.last?.occurredAt
        item.progressFraction = latestProgress(in: sessions)

        let completionEvents = events.filter {
            $0.kind == .completed || $0.toStatus == .completed
        }
        item.lastCompletedAt = completionEvents.map(\.effectiveAt).max()

        let topLevelTrackableUnits = units.filter { unit in
            unit.parentUnitID == nil &&
                (unit.unitKind == .tvSeason || unit.unitKind == .comicVolume)
        }
        let releasedTopLevelUnits = topLevelTrackableUnits.filter {
            ($0.releaseDate ?? .distantPast) <= now
        }
        let allReleasedUnitsComplete = !releasedTopLevelUnits.isEmpty &&
            releasedTopLevelUnits.allSatisfy { $0.status == .completed }

        let meaningfulEvents = events.filter { event in
            guard event.toStatus != nil else { return false }
            if event.toStatus == .completed, event.targetUnitID != nil {
                return false
            }
            return true
        }

        var itemStatus = latestStatus(
            events: meaningfulEvents,
            hasSessions: !sessions.isEmpty,
            fallback: .planned
        )

        let latestMeaningfulDate = sorted(meaningfulEvents).last?.effectiveAt ?? .distantPast
        let latestUnitCompletionDate = sorted(completionEvents.filter { $0.targetUnitID != nil })
            .last?.effectiveAt ?? .distantPast

        if item.mediaKind == .tvShow || item.mediaKind == .comic {
            // An explicit item completion written at the same instant wins. This
            // preserves a show's completed history when metadata later adds a season.
            if latestUnitCompletionDate > latestMeaningfulDate {
                itemStatus = allReleasedUnitsComplete ? .completed : .inProgress
            }
        }

        item.status = itemStatus
        item.hasNewInstallment = itemStatus == .completed &&
            topLevelTrackableUnits.contains { unit in
                (unit.releaseDate ?? .distantPast) <= now && unit.status != .completed
            }

        if item.mediaKind == .tvShow {
            let seasonRatings = units
                .filter { $0.unitKind == .tvSeason }
                .compactMap(\.ratingHalfSteps)
            item.derivedRatingHalfSteps = derivedRating(
                overrideHalfSteps: nil,
                seasonHalfSteps: seasonRatings
            )
        } else {
            item.derivedRatingHalfSteps = nil
        }
        item.effectiveRatingHalfSteps = derivedRating(
            overrideHalfSteps: item.ratingOverrideHalfSteps,
            seasonHalfSteps: item.mediaKind == .tvShow
                ? units.filter { $0.unitKind == .tvSeason }.compactMap(\.ratingHalfSteps)
                : []
        )
        if touchUpdatedAt {
            item.updatedAt = .now
        }
    }

    static func rebuild(_ cycle: ConsumptionCycle, events: [ActivityEvent], touchUpdatedAt: Bool = true) {
        let sessions = (cycle.sessions ?? []).filter { $0.deletedAt == nil }
        let cycleEvents = events.filter { $0.cycleID == cycle.id }
        cycle.sessionCount = sessions.count
        cycle.startedAt = sessions.map(\.occurredAt).min()
            ?? cycleEvents.filter { $0.kind == .started }.map(\.effectiveAt).min()
        cycle.lastSessionAt = sessions.map(\.occurredAt).max()
        cycle.completedAt = cycleEvents
            .filter { $0.kind == .completed || $0.toStatus == .completed }
            .map(\.effectiveAt)
            .max()
        cycle.progressFraction = latestProgress(in: sessions)
        cycle.status = latestStatus(
            events: cycleEvents,
            hasSessions: !sessions.isEmpty,
            fallback: .planned
        )
        if touchUpdatedAt {
            cycle.updatedAt = .now
        }
    }

    static func rebuild(_ unit: ContentUnit, events: [ActivityEvent], touchUpdatedAt: Bool = true) {
        let sessions = (unit.sessions ?? []).filter { $0.deletedAt == nil }
        let unitEvents = events.filter { $0.targetUnitID == unit.id }
        unit.sessionCount = sessions.count
        unit.firstStartedAt = sessions.map(\.occurredAt).min()
            ?? unitEvents.filter { $0.kind == .started }.map(\.effectiveAt).min()
        unit.lastSessionAt = sessions.map(\.occurredAt).max()
        unit.lastCompletedAt = unitEvents
            .filter { $0.kind == .completed || $0.toStatus == .completed }
            .map(\.effectiveAt)
            .max()
        unit.progressFraction = latestProgress(in: sessions)
        unit.status = latestStatus(
            events: unitEvents,
            hasSessions: !sessions.isEmpty,
            fallback: .planned
        )
        if touchUpdatedAt {
            unit.updatedAt = .now
        }
    }

    private static func aggregateChildren(into unit: ContentUnit, now: Date) {
        let releasedChildren = (unit.children ?? []).filter { child in
            child.deletedAt == nil && (child.releaseDate ?? .distantPast) <= now
        }
        guard !releasedChildren.isEmpty else { return }

        let childSessions = releasedChildren.compactMap(\.lastSessionAt)
        unit.sessionCount = releasedChildren.reduce(0) { $0 + $1.sessionCount }
        unit.firstStartedAt = releasedChildren.compactMap(\.firstStartedAt).min()
        unit.lastSessionAt = childSessions.max()

        if releasedChildren.allSatisfy({ $0.status == .completed }) {
            unit.status = .completed
            unit.lastCompletedAt = releasedChildren.compactMap(\.lastCompletedAt).max()
            unit.progressFraction = 1
        } else if releasedChildren.contains(where: { $0.status == .inProgress }) {
            unit.status = .inProgress
        }
    }

    private static func sorted(_ events: [ActivityEvent]) -> [ActivityEvent] {
        events.sorted { lhs, rhs in
            if lhs.effectiveAt == rhs.effectiveAt {
                return lhs.recordedAt < rhs.recordedAt
            }
            return lhs.effectiveAt < rhs.effectiveAt
        }
    }
}
