import CryptoKit
import Foundation
import SwiftData

/// Applies user-confirmed staged rows to the semantic SwiftData graph.
///
/// The staging adapters deliberately do not mutate the library. This service is the single
/// boundary where reviewed rows become canonical items and historical activity.
@MainActor
final class StagedImportApplier {
    private let context: ModelContext
    private let credentials: any CredentialStoring

    init(context: ModelContext, credentials: any CredentialStoring) {
        self.context = context
        self.credentials = credentials
    }

    func apply(
        _ batch: StagedImportBatch,
        selection: ImportApplicationSelection
    ) async throws -> ImportApplicationReport {
        let selectedRows = batch.rows.filter { selection.acceptedRowIDs.contains($0.id) }
        var report = ImportApplicationReport()
        report.acceptedRows = selectedRows.count

        var itemsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<LibraryItem>()).map { ($0.id, $0) }
        )
        // This cache joins repeated source rows created during the same import. It does not
        // silently match an existing library item; existing-item joins still require an explicit
        // choice or one unambiguous candidate at or above the confidence threshold.
        var importedItemsByIdentity: [String: LibraryItem] = [:]
        var touchedItems: [UUID: LibraryItem] = [:]
        var credentialMutations: [CredentialMutation] = []

        do {
            for row in selectedRows {
                let wasApplied: Bool
                switch row.proposal {
                case let .mediaItem(proposal):
                    wasApplied = try applyMediaItem(
                        proposal,
                        row: row,
                        batch: batch,
                        selection: selection,
                        itemsByID: &itemsByID,
                        importedItemsByIdentity: &importedItemsByIdentity,
                        touchedItems: &touchedItems,
                        report: &report
                    )

                case let .podcastSubscription(proposal):
                    wasApplied = try await applyPodcastSubscription(
                        proposal,
                        row: row,
                        batch: batch,
                        selection: selection,
                        itemsByID: &itemsByID,
                        importedItemsByIdentity: &importedItemsByIdentity,
                        touchedItems: &touchedItems,
                        credentialMutations: &credentialMutations,
                        report: &report
                    )

                case let .podcastEpisode(proposal):
                    wasApplied = try await applyPodcastEpisode(
                        proposal,
                        row: row,
                        batch: batch,
                        selection: selection,
                        itemsByID: &itemsByID,
                        importedItemsByIdentity: &importedItemsByIdentity,
                        touchedItems: &touchedItems,
                        credentialMutations: &credentialMutations,
                        report: &report
                    )

                case let .unresolved(proposal):
                    report.warnings.append(ImportApplicationWarning(
                        rowID: row.id,
                        message: proposal.reason
                    ))
                    wasApplied = false
                }

                if wasApplied {
                    report.appliedRows += 1
                }
            }

            for item in touchedItems.values {
                ActivityProjection.rebuild(item)
            }
            report.skippedRows = batch.rows.count - report.appliedRows
            try context.save()
            return report
        } catch {
            context.rollback()
            await restoreCredentials(after: credentialMutations)
            throw error
        }
    }

    private func applyMediaItem(
        _ proposal: MediaItemImportProposal,
        row: StagedImportRow,
        batch: StagedImportBatch,
        selection: ImportApplicationSelection,
        itemsByID: inout [UUID: LibraryItem],
        importedItemsByIdentity: inout [String: LibraryItem],
        touchedItems: inout [UUID: LibraryItem],
        report: inout ImportApplicationReport
    ) throws -> Bool {
        guard let archiveKind = proposal.mediaKind else {
            report.warnings.append(ImportApplicationWarning(
                rowID: row.id,
                message: "Choose a media type before importing this row."
            ))
            return false
        }

        let kind = mediaKind(archiveKind)
        let source = recordSource(batch.source)
        let createdAt = proposal.addedAt ?? batch.stagedAt
        let item = resolveOrCreateItem(
            row: row,
            title: proposal.title,
            kind: kind,
            createdAt: createdAt,
            source: source,
            selection: selection,
            itemsByID: &itemsByID,
            importedItemsByIdentity: &importedItemsByIdentity,
            report: &report
        )
        touchedItems[item.id] = item

        mergeBaseMetadata(proposal, into: item)
        attachCreators(proposal.creators, to: item)
        attachExternalIdentifiers(proposal.externalIdentifiers, to: item, source: source)
        try attachTags(proposal.tags, to: item, source: source, report: &report)
        try attachLists(proposal.listNames, to: item, report: &report)

        let targetUnit = unit(
            for: proposal.history?.progress,
            in: item,
            report: &report
        )
        let preferredDate = proposal.startDate
            ?? proposal.history?.consumedAt
            ?? proposal.history?.completedAt
            ?? proposal.completionDate
            ?? createdAt
        let importedStatus = proposal.history?.status ?? proposal.status
        let isRepeat = importedStatus.map(isRepeatStatus) ?? false

        var cycle: ConsumptionCycle?
        if proposal.startDate != nil || proposal.history != nil || importedStatus.map(requiresCycle) == true {
            cycle = ensureCycle(
                for: item,
                targetUnit: targetUnit,
                at: preferredDate,
                source: source,
                preferRepeat: isRepeat,
                report: &report
            )
        }

        if let history = proposal.history, let cycle {
            let sessionDate = history.consumedAt
                ?? history.completedAt
                ?? proposal.completionDate
                ?? proposal.startDate
                ?? batch.stagedAt
            insertSession(
                for: cycle,
                targetUnit: targetUnit,
                at: sessionDate,
                note: history.note ?? proposal.note,
                progress: history.progress,
                source: source
            )
            report.createdSessions += 1
        }

        let importedRating = proposal.history?.rating ?? proposal.rating
        if let halfSteps = ratingHalfSteps(importedRating) {
            if item.mediaKind == .tvShow,
               let season = seasonRatingTarget(for: targetUnit) {
                season.setRating(halfSteps: halfSteps)
            } else if let targetUnit {
                targetUnit.setRating(halfSteps: halfSteps)
            } else {
                item.setRating(halfSteps: halfSteps)
            }
        }

        let isCompletion = proposal.history?.isCompletion == true
            || importedStatus == .completed
            || proposal.completionDate != nil
        if isCompletion {
            let completionDate = proposal.history?.completedAt
                ?? proposal.completionDate
                ?? proposal.history?.consumedAt
                ?? batch.stagedAt
            let completionCycle = cycle ?? ensureCycle(
                for: item,
                targetUnit: targetUnit,
                at: completionDate,
                source: source,
                preferRepeat: isRepeat,
                report: &report
            )
            insertEvent(
                item: item,
                cycle: completionCycle,
                targetUnit: targetUnit,
                kind: .completed,
                fromStatus: completionCycle.status,
                toStatus: .completed,
                at: completionDate,
                note: proposal.history?.note ?? proposal.note,
                source: source
            )
            report.createdEvents += 1
        } else if let importedStatus {
            applyStatus(
                importedStatus,
                to: item,
                cycle: cycle,
                targetUnit: targetUnit,
                at: proposal.history?.consumedAt ?? proposal.startDate ?? createdAt,
                note: proposal.history?.note ?? proposal.note,
                source: source,
                report: &report
            )
        }

        ActivityProjection.rebuild(item)
        return true
    }

    private func applyPodcastSubscription(
        _ proposal: PodcastSubscriptionImportProposal,
        row: StagedImportRow,
        batch: StagedImportBatch,
        selection: ImportApplicationSelection,
        itemsByID: inout [UUID: LibraryItem],
        importedItemsByIdentity: inout [String: LibraryItem],
        touchedItems: inout [UUID: LibraryItem],
        credentialMutations: inout [CredentialMutation],
        report: inout ImportApplicationReport
    ) async throws -> Bool {
        let source = recordSource(batch.source)
        let item = resolveOrCreateItem(
            row: row,
            title: proposal.title,
            kind: .podcast,
            createdAt: batch.stagedAt,
            source: source,
            selection: selection,
            itemsByID: &itemsByID,
            importedItemsByIdentity: &importedItemsByIdentity,
            report: &report
        )
        touchedItems[item.id] = item

        if item.creatorLine?.isEmpty != false { item.creatorLine = proposal.author }
        if let author = proposal.author { attachCreators([author], to: item) }
        item.podcastListeningStyle = listeningStyle(proposal.listeningStyle)
        item.podcastFollowState = podcastFollowState(proposal.status)
        item.updatedAt = .now

        if let feedURL = proposal.feedURL {
            try await attachFeed(
                feedURL,
                to: item,
                rowID: row.id,
                credentialMutations: &credentialMutations,
                report: &report
            )
        }
        if let websiteURL = proposal.websiteURL, let safeURL = safePublicURL(websiteURL) {
            attachExternalReference(
                provider: "website",
                recordKind: "podcastWebsite",
                externalID: opaqueHash(safeURL),
                canonicalURL: safeURL,
                to: item
            )
        }
        if !proposal.categoryPath.isEmpty {
            try attachLists(
                [proposal.categoryPath.joined(separator: " / ")],
                to: item,
                report: &report
            )
        }

        ActivityProjection.rebuild(item)
        return true
    }

    private func applyPodcastEpisode(
        _ proposal: PodcastEpisodeImportProposal,
        row: StagedImportRow,
        batch: StagedImportBatch,
        selection: ImportApplicationSelection,
        itemsByID: inout [UUID: LibraryItem],
        importedItemsByIdentity: inout [String: LibraryItem],
        touchedItems: inout [UUID: LibraryItem],
        credentialMutations: inout [CredentialMutation],
        report: inout ImportApplicationReport
    ) async throws -> Bool {
        let podcastTitle = proposal.podcastTitle
            ?? proposal.feedURL.flatMap { URL(string: $0)?.host() }
            ?? "Imported Podcast"
        let source = recordSource(batch.source)
        let item = resolveOrCreateItem(
            row: row,
            title: podcastTitle,
            kind: .podcast,
            createdAt: batch.stagedAt,
            source: source,
            selection: selection,
            itemsByID: &itemsByID,
            importedItemsByIdentity: &importedItemsByIdentity,
            report: &report
        )
        touchedItems[item.id] = item
        item.podcastFollowState = item.podcastFollowState ?? .following

        var feedIsPrivate = (item.externalReferences ?? []).contains {
            $0.providerRaw == "rss" && $0.isActiveFeed && $0.isPrivateFeed
        }
        if let feedURL = proposal.feedURL {
            feedIsPrivate = try await attachFeed(
                feedURL,
                to: item,
                rowID: row.id,
                credentialMutations: &credentialMutations,
                report: &report
            )
        }

        let sourceIdentifier = proposal.enclosureURL
            ?? proposal.episodeURL
            ?? "\(proposal.episodeTitle)|\(proposal.publishedAt?.timeIntervalSince1970 ?? 0)"
        let guidHash = opaqueHash(sourceIdentifier)
        let existing = (item.units ?? []).first {
            $0.unitKind == .podcastEpisode && $0.episodeGUIDHash == guidHash
        }
        let episode: ContentUnit
        if let existing {
            episode = existing
        } else {
            episode = ContentUnit(
                item: item,
                kind: .podcastEpisode,
                title: proposal.episodeTitle,
                sortOrder: item.units?.count ?? 0,
                createdAt: batch.stagedAt
            )
            context.insert(episode)
            attach(episode, to: item)
            report.createdUnits += 1
        }

        let identifierIsSensitive = URL(string: sourceIdentifier)
            .map { PodcastFeedPrivacy.containsEmbeddedCredential(in: $0) } ?? false
        episode.episodeGUIDHash = guidHash
        episode.episodeGUID = feedIsPrivate || identifierIsSensitive ? nil : sourceIdentifier
        episode.title = proposal.episodeTitle
        episode.publishedAt = proposal.publishedAt
        episode.releaseDate = proposal.publishedAt
        episode.durationSeconds = seconds(fromMinutes: proposal.durationMinutes)
        episode.isNotable = episode.isNotable || proposal.isNotable
        episode.comment = mergedText(episode.comment, proposal.note)
        episode.canonicalURLString = feedIsPrivate ? nil : proposal.episodeURL.flatMap(safePublicURL)
        episode.updatedAt = .now

        if !feedIsPrivate {
            for (kind, rawURL) in [
                ("episodeWebpage", proposal.episodeURL),
                ("enclosure", proposal.enclosureURL),
            ] {
                guard let rawURL, let safeURL = safePublicURL(rawURL) else { continue }
                attachExternalReference(
                    provider: "overcast",
                    recordKind: kind,
                    externalID: opaqueHash(safeURL),
                    canonicalURL: safeURL,
                    to: item,
                    unit: episode
                )
            }
        }

        let hasPlayback = proposal.elapsedMinutes != nil
            || proposal.completionPercentage != nil
            || proposal.isCompleted
        if hasPlayback {
            let occurredAt = importedPlaybackDate(from: row.rawFields) ?? batch.stagedAt
            if importedPlaybackDate(from: row.rawFields) == nil {
                report.warnings.append(ImportApplicationWarning(
                    rowID: row.id,
                    message: "The episode had no playback date, so its import date was used."
                ))
            }
            let cycle = ensureCycle(
                for: item,
                targetUnit: episode,
                at: occurredAt,
                source: source,
                preferRepeat: false,
                report: &report
            )
            let session = ConsumptionSession(
                cycle: cycle,
                targetUnit: episode,
                occurredAt: occurredAt,
                note: proposal.note,
                source: source
            )
            session.elapsedSeconds = seconds(fromMinutes: proposal.elapsedMinutes)
            session.mediaDurationSecondsSnapshot = seconds(fromMinutes: proposal.durationMinutes)
            session.completionPercent = proposal.isCompleted
                ? 100
                : proposal.completionPercentage.map(clampedPercentage)
            context.insert(session)
            attach(session, to: cycle, targetUnit: episode)
            report.createdSessions += 1

            if proposal.isCompleted {
                insertEvent(
                    item: item,
                    cycle: cycle,
                    targetUnit: episode,
                    kind: .completed,
                    fromStatus: cycle.status,
                    toStatus: .completed,
                    at: occurredAt,
                    note: proposal.note,
                    source: source
                )
                report.createdEvents += 1
            }
        }

        ActivityProjection.rebuild(item)
        return true
    }

    // MARK: - Canonical resolution

    private func resolveOrCreateItem(
        row: StagedImportRow,
        title: String,
        kind: MediaKind,
        createdAt: Date,
        source: RecordSource,
        selection: ImportApplicationSelection,
        itemsByID: inout [UUID: LibraryItem],
        importedItemsByIdentity: inout [String: LibraryItem],
        report: inout ImportApplicationReport
    ) -> LibraryItem {
        let identity = identityKey(title: title, kind: kind)
        var resolved: LibraryItem?

        if let explicitID = selection.targetItemIDsByRowID[row.id] {
            resolved = itemsByID[explicitID]
            if resolved == nil {
                report.warnings.append(ImportApplicationWarning(
                    rowID: row.id,
                    message: "The selected library item no longer exists; a new item was created."
                ))
            }
        } else {
            let candidates = row.matchCandidates.sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.confidence > rhs.confidence
            }
            if let top = candidates.first,
               top.confidence >= 0.95,
               candidates.filter({ $0.confidence >= 0.95 }).count == 1,
               candidates.dropFirst().first.map({ top.confidence - $0.confidence >= 0.05 }) ?? true {
                resolved = itemsByID[top.id]
            }
        }

        if resolved == nil {
            resolved = importedItemsByIdentity[identity]
        }
        if let resolved {
            if resolved.mediaKind != kind {
                report.warnings.append(ImportApplicationWarning(
                    rowID: row.id,
                    message: "The imported media type differs from the selected canonical item."
                ))
            }
            importedItemsByIdentity[identity] = resolved
            report.mergedItems += 1
            return resolved
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LibraryItem(
            mediaKind: kind,
            title: cleanTitle.isEmpty ? "Untitled" : cleanTitle,
            createdAt: createdAt
        )
        context.insert(item)
        itemsByID[item.id] = item
        importedItemsByIdentity[identity] = item
        report.createdItems += 1

        insertEvent(
            item: item,
            cycle: nil,
            targetUnit: nil,
            kind: .created,
            fromStatus: nil,
            toStatus: .planned,
            at: createdAt,
            note: nil,
            source: source
        )
        report.createdEvents += 1
        return item
    }

    // MARK: - History

    private func ensureCycle(
        for item: LibraryItem,
        targetUnit: ContentUnit?,
        at date: Date,
        source: RecordSource,
        preferRepeat: Bool,
        report: inout ImportApplicationReport
    ) -> ConsumptionCycle {
        let matching = (item.cycles ?? []).filter {
            $0.deletedAt == nil && $0.targetUnitID == targetUnit?.id
        }
        if let active = matching
            .filter({ $0.status == .inProgress || $0.status == .paused || $0.status == .planned })
            .max(by: { $0.ordinal < $1.ordinal }) {
            return active
        }

        let previous = matching.max { $0.ordinal < $1.ordinal }
        let kind: ConsumptionCycleKind = preferRepeat || previous?.status == .completed
            ? .repeatConsumption
            : .initial
        let cycle = ConsumptionCycle(
            item: item,
            targetUnit: targetUnit,
            kind: kind,
            ordinal: (matching.map(\.ordinal).max() ?? -1) + 1,
            repeatOfCycleID: kind == .repeatConsumption ? previous?.id : nil,
            createdAt: date
        )
        context.insert(cycle)
        attach(cycle, to: item)
        insertEvent(
            item: item,
            cycle: cycle,
            targetUnit: targetUnit,
            kind: .started,
            fromStatus: .planned,
            toStatus: .inProgress,
            at: date,
            note: nil,
            source: source
        )
        report.createdEvents += 1
        cycle.status = .inProgress
        return cycle
    }

    private func insertSession(
        for cycle: ConsumptionCycle,
        targetUnit: ContentUnit?,
        at date: Date,
        note: String?,
        progress: ImportProgressProposal?,
        source: RecordSource
    ) {
        let session = ConsumptionSession(
            cycle: cycle,
            targetUnit: targetUnit,
            occurredAt: date,
            note: note,
            source: source
        )
        session.currentPage = progress?.currentPage
        session.totalPagesSnapshot = progress?.totalPages
        session.chapter = progress?.chapter
        session.elapsedSeconds = seconds(fromMinutes: progress?.elapsedMinutes)
        session.mediaDurationSecondsSnapshot = seconds(fromMinutes: progress?.totalRuntimeMinutes)
        session.gamePlaytimeTotalSnapshotSeconds = seconds(fromMinutes: progress?.playtimeMinutes)
        session.completionPercent = progress?.completionPercentage.map(clampedPercentage)
        context.insert(session)
        attach(session, to: cycle, targetUnit: targetUnit)
    }

    private func applyStatus(
        _ archiveStatus: ArchiveLifecycleStatus,
        to item: LibraryItem,
        cycle: ConsumptionCycle?,
        targetUnit: ContentUnit?,
        at date: Date,
        note: String?,
        source: RecordSource,
        report: inout ImportApplicationReport
    ) {
        if archiveStatus == .archived {
            item.archivedAt = date
            insertEvent(
                item: item,
                cycle: cycle,
                targetUnit: targetUnit,
                kind: .archived,
                fromStatus: nil,
                toStatus: nil,
                at: date,
                note: note,
                source: source
            )
            report.createdEvents += 1
            return
        }

        let status = consumptionStatus(archiveStatus)
        guard status != .planned && status != .inProgress else { return }
        insertEvent(
            item: item,
            cycle: cycle,
            targetUnit: targetUnit,
            kind: .statusSet,
            fromStatus: cycle?.status ?? targetUnit?.status ?? item.status,
            toStatus: status,
            at: date,
            note: note,
            source: source
        )
        report.createdEvents += 1
    }

    private func insertEvent(
        item: LibraryItem,
        cycle: ConsumptionCycle?,
        targetUnit: ContentUnit?,
        kind: ActivityEventKind,
        fromStatus: ConsumptionStatus?,
        toStatus: ConsumptionStatus?,
        at date: Date,
        note: String?,
        source: RecordSource
    ) {
        let event = ActivityEvent(
            item: item,
            cycle: cycle,
            targetUnit: targetUnit,
            scope: targetUnit == nil ? .item : .unit,
            kind: kind,
            fromStatus: fromStatus,
            toStatus: toStatus,
            effectiveAt: date,
            note: note,
            source: source
        )
        context.insert(event)
        if !(item.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            item.activityEvents = (item.activityEvents ?? []) + [event]
        }
        if let cycle, !(cycle.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            cycle.activityEvents = (cycle.activityEvents ?? []) + [event]
        }
        if let targetUnit,
           !(targetUnit.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            targetUnit.activityEvents = (targetUnit.activityEvents ?? []) + [event]
        }
    }

    // MARK: - Units and metadata

    private func unit(
        for progress: ImportProgressProposal?,
        in item: LibraryItem,
        report: inout ImportApplicationReport
    ) -> ContentUnit? {
        guard let progress else { return nil }
        switch item.mediaKind {
        case .tvShow:
            var season: ContentUnit?
            if let number = progress.seasonNumber {
                season = findOrCreateUnit(
                    in: item,
                    parent: nil,
                    kind: .tvSeason,
                    numberValue: Double(number),
                    numberLabel: String(number),
                    title: "Season \(number)",
                    report: &report
                )
                season?.seasonNumber = number
            }
            if let number = progress.episodeNumber {
                let episode = findOrCreateUnit(
                    in: item,
                    parent: season,
                    kind: .tvEpisode,
                    numberValue: Double(number),
                    numberLabel: String(number),
                    title: "Episode \(number)",
                    report: &report
                )
                episode.episodeNumber = number
                episode.seasonNumber = progress.seasonNumber
                episode.durationSeconds = seconds(fromMinutes: progress.totalRuntimeMinutes)
                return episode
            }
            return season

        case .comic:
            var volume: ContentUnit?
            if let number = progress.volumeNumber {
                volume = findOrCreateUnit(
                    in: item,
                    parent: nil,
                    kind: .comicVolume,
                    numberValue: Double(number),
                    numberLabel: String(number),
                    title: "Volume \(number)",
                    report: &report
                )
            }
            if let number = progress.issueNumber {
                let issue = findOrCreateUnit(
                    in: item,
                    parent: volume,
                    kind: .comicIssue,
                    numberValue: Double(number),
                    numberLabel: number,
                    title: "Issue \(number)",
                    report: &report
                )
                issue.pageCount = progress.totalPages
                return issue
            }
            return volume

        case .book:
            if item.pageCount == nil { item.pageCount = progress.totalPages }
            return nil

        case .movie:
            if item.runtimeSeconds == nil {
                item.runtimeSeconds = seconds(fromMinutes: progress.totalRuntimeMinutes)
            }
            return nil

        case .game, .podcast, .unknown:
            return nil
        }
    }

    private func findOrCreateUnit(
        in item: LibraryItem,
        parent: ContentUnit?,
        kind: ContentUnitKind,
        numberValue: Double?,
        numberLabel: String?,
        title: String,
        report: inout ImportApplicationReport
    ) -> ContentUnit {
        if let existing = (item.units ?? []).first(where: {
            $0.deletedAt == nil
                && $0.unitKind == kind
                && $0.parentUnitID == parent?.id
                && ($0.numberLabel == numberLabel || $0.numberValue == numberValue)
        }) {
            return existing
        }
        let unit = ContentUnit(
            item: item,
            kind: kind,
            title: title,
            sortOrder: item.units?.count ?? 0,
            parent: parent
        )
        unit.numberValue = numberValue
        unit.numberLabel = numberLabel
        context.insert(unit)
        attach(unit, to: item, parent: parent)
        report.createdUnits += 1
        return unit
    }

    private func mergeBaseMetadata(_ proposal: MediaItemImportProposal, into item: LibraryItem) {
        if item.subtitle?.isEmpty != false { item.subtitle = proposal.subtitle }
        if item.creatorLine?.isEmpty != false, !proposal.creators.isEmpty {
            item.creatorLine = proposal.creators.joined(separator: ", ")
        }
        if item.releaseDate == nil { item.releaseDate = proposal.releaseDate }
        if item.releaseYear == nil, let date = proposal.releaseDate {
            item.releaseYear = Calendar(identifier: .gregorian).component(.year, from: date)
        }
        item.isFavorite = item.isFavorite || proposal.isFavorite
        item.comment = mergedText(item.comment, proposal.note)
        item.updatedAt = .now
    }

    private func attachCreators(_ creators: [String], to item: LibraryItem) {
        var credits = item.credits ?? []
        let existing = Set(credits.map(\.normalizedName))
        for creator in creators {
            let normalized = LibraryItem.normalize(creator)
            guard !normalized.isEmpty, !existing.contains(normalized),
                  !credits.contains(where: { $0.normalizedName == normalized }) else { continue }
            let credit = Credit(
                ownerItem: item,
                name: creator,
                roleRaw: "creator",
                sortOrder: credits.count
            )
            context.insert(credit)
            credits.append(credit)
        }
        item.credits = credits
    }

    private func attachExternalIdentifiers(
        _ identifiers: [String: String],
        to item: LibraryItem,
        source: RecordSource
    ) {
        for (provider, rawValue) in identifiers {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let isURL = URL(string: value)?.scheme != nil
            let safeURL = isURL ? safePublicURL(value) : nil
            let externalID = isURL ? opaqueHash(value) : value
            attachExternalReference(
                provider: provider,
                recordKind: source.rawValue,
                externalID: externalID,
                canonicalURL: safeURL,
                to: item
            )
        }
    }

    private func attachExternalReference(
        provider: String,
        recordKind: String,
        externalID: String,
        canonicalURL: String?,
        to item: LibraryItem,
        unit: ContentUnit? = nil
    ) {
        if let existing = (item.externalReferences ?? []).first(where: {
            $0.providerRaw == provider
                && $0.recordKindRaw == recordKind
                && $0.externalID == externalID
                && $0.unitID == unit?.id
        }) {
            if existing.canonicalURLString == nil { existing.canonicalURLString = canonicalURL }
            return
        }
        let reference = ExternalReference(
            ownerItem: item,
            unit: unit,
            providerRaw: provider,
            recordKindRaw: recordKind,
            externalID: externalID,
            canonicalURLString: canonicalURL
        )
        context.insert(reference)
        item.externalReferences = (item.externalReferences ?? []) + [reference]
        if let unit {
            unit.externalReferences = (unit.externalReferences ?? []) + [reference]
        }
    }

    private func attachTags(
        _ names: [String],
        to item: LibraryItem,
        source: RecordSource,
        report: inout ImportApplicationReport
    ) throws {
        guard !names.isEmpty else { return }
        var facets = try context.fetch(FetchDescriptor<Facet>())
        for name in names {
            let normalized = LibraryItem.normalize(name)
            guard !normalized.isEmpty else { continue }
            let facet: Facet
            if let existing = facets.first(where: { $0.kind == .tag && $0.normalizedName == normalized }) {
                facet = existing
            } else {
                facet = Facet(kind: .tag, name: name)
                context.insert(facet)
                facets.append(facet)
                report.createdTags += 1
            }
            guard !(item.facetMemberships ?? []).contains(where: { $0.facetID == facet.id }) else { continue }
            let membership = ItemFacetMembership(item: item, facet: facet, source: source)
            context.insert(membership)
            item.facetMemberships = (item.facetMemberships ?? []) + [membership]
            facet.memberships = (facet.memberships ?? []) + [membership]
        }
    }

    private func attachLists(
        _ names: [String],
        to item: LibraryItem,
        report: inout ImportApplicationReport
    ) throws {
        guard !names.isEmpty else { return }
        var lists = try context.fetch(FetchDescriptor<UserList>())
        for name in names {
            let normalized = LibraryItem.normalize(name)
            guard !normalized.isEmpty else { continue }
            let list: UserList
            if let existing = lists.first(where: {
                $0.kind == .manual && LibraryItem.normalize($0.name) == normalized && $0.trashedAt == nil
            }) {
                list = existing
            } else {
                list = UserList(name: name, sortOrder: lists.count)
                context.insert(list)
                lists.append(list)
                report.createdLists += 1
            }
            guard !(item.listMemberships ?? []).contains(where: { $0.listID == list.id }) else { continue }
            let membership = ListMembership(
                list: list,
                item: item,
                positionRank: String(format: "%08d", (list.memberships?.count ?? 0) * 1_000)
            )
            context.insert(membership)
            item.listMemberships = (item.listMemberships ?? []) + [membership]
            list.memberships = (list.memberships ?? []) + [membership]
        }
    }

    // MARK: - Podcast privacy

    @discardableResult
    private func attachFeed(
        _ rawValue: String,
        to item: LibraryItem,
        rowID: UUID,
        credentialMutations: inout [CredentialMutation],
        report: inout ImportApplicationReport
    ) async throws -> Bool {
        guard let url = PodcastFeedPrivacy.validatedFeedURL(from: rawValue) else {
            report.warnings.append(ImportApplicationWarning(
                rowID: rowID,
                message: "The podcast feed URL was invalid and was not saved."
            ))
            return false
        }

        let isPrivate = PodcastFeedPrivacy.classify(untrustedFeed: url).isPrivate
        let reference = (item.externalReferences ?? []).first(where: {
            $0.providerRaw == "rss" && $0.isActiveFeed
        }) ?? ExternalReference(
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "podcastFeed",
            externalID: isPrivate ? "private.\(UUID().uuidString.lowercased())" : opaqueHash(rawValue)
        )
        if reference.ownerItem == nil {
            reference.ownerItem = item
        }
        if !(item.externalReferences ?? []).contains(where: { $0.id == reference.id }) {
            context.insert(reference)
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }

        reference.isActiveFeed = true
        reference.isPrivateFeed = isPrivate
        reference.updatedAt = .now
        if isPrivate {
            let key = reference.credentialKeychainID
                ?? "podcast-feed.import.\(UUID().uuidString.lowercased())"
            let previousValue = try await credentials.value(for: key)
            try await credentials.set(rawValue, for: key)
            credentialMutations.append(CredentialMutation(key: key, previousValue: previousValue))
            reference.externalID = reference.isPrivateFeed && reference.credentialKeychainID != nil
                ? reference.externalID
                : "private.\(UUID().uuidString.lowercased())"
            reference.credentialKeychainID = key
            reference.canonicalURLString = nil
        } else {
            if let oldKey = reference.credentialKeychainID {
                let previousValue = try await credentials.value(for: oldKey)
                try await credentials.removeValue(for: oldKey)
                credentialMutations.append(CredentialMutation(key: oldKey, previousValue: previousValue))
            }
            reference.externalID = opaqueHash(rawValue)
            reference.credentialKeychainID = nil
            reference.canonicalURLString = rawValue
        }
        return isPrivate
    }

    private func restoreCredentials(after mutations: [CredentialMutation]) async {
        for mutation in mutations.reversed() {
            if let previousValue = mutation.previousValue {
                try? await credentials.set(previousValue, for: mutation.key)
            } else {
                try? await credentials.removeValue(for: mutation.key)
            }
        }
    }

    // MARK: - Relationship helpers

    private func attach(_ cycle: ConsumptionCycle, to item: LibraryItem) {
        if !(item.cycles ?? []).contains(where: { $0.id == cycle.id }) {
            item.cycles = (item.cycles ?? []) + [cycle]
        }
    }

    private func attach(
        _ session: ConsumptionSession,
        to cycle: ConsumptionCycle,
        targetUnit: ContentUnit?
    ) {
        if !(cycle.sessions ?? []).contains(where: { $0.id == session.id }) {
            cycle.sessions = (cycle.sessions ?? []) + [session]
        }
        if let targetUnit, !(targetUnit.sessions ?? []).contains(where: { $0.id == session.id }) {
            targetUnit.sessions = (targetUnit.sessions ?? []) + [session]
        }
    }

    private func attach(
        _ unit: ContentUnit,
        to item: LibraryItem,
        parent: ContentUnit? = nil
    ) {
        if !(item.units ?? []).contains(where: { $0.id == unit.id }) {
            item.units = (item.units ?? []) + [unit]
        }
        if let parent, !(parent.children ?? []).contains(where: { $0.id == unit.id }) {
            parent.children = (parent.children ?? []) + [unit]
        }
    }

    // MARK: - Value mapping

    private func mediaKind(_ value: ArchiveMediaKind) -> MediaKind {
        switch value {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .television: .tvShow
        case .game: .game
        case .podcast: .podcast
        }
    }

    private func consumptionStatus(_ value: ArchiveLifecycleStatus) -> ConsumptionStatus {
        switch value {
        case .planned, .archived: .planned
        case .paused: .paused
        case .completed: .completed
        case .dropped: .dropped
        case .inProgress, .rereading, .rewatching, .replaying, .following: .inProgress
        }
    }

    private func podcastFollowState(_ value: ArchiveLifecycleStatus) -> PodcastFollowState {
        switch value {
        case .paused: .paused
        case .completed: .completed
        case .dropped: .dropped
        default: .following
        }
    }

    private func listeningStyle(_ value: ArchivePodcastListeningStyle) -> PodcastListeningStyle {
        switch value {
        case .everyEpisode: .everyEpisode
        case .selectedEpisodes: .selectedEpisodes
        case .keepAround: .keepAround
        }
    }

    private func recordSource(_ value: ImportSourceFormat) -> RecordSource {
        switch value {
        case .opml: .opml
        case .overcastAllDataCSV: .overcast
        case .sofaCSV: .sofa
        }
    }

    private func isRepeatStatus(_ value: ArchiveLifecycleStatus) -> Bool {
        value == .rereading || value == .rewatching || value == .replaying
    }

    private func requiresCycle(_ value: ArchiveLifecycleStatus) -> Bool {
        switch value {
        case .inProgress, .paused, .completed, .dropped, .rereading, .rewatching, .replaying:
            true
        case .planned, .following, .archived:
            false
        }
    }

    private func seasonRatingTarget(for unit: ContentUnit?) -> ContentUnit? {
        guard let unit else { return nil }
        if unit.unitKind == .tvSeason { return unit }
        return unit.parent?.unitKind == .tvSeason ? unit.parent : nil
    }

    private func ratingHalfSteps(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return min(max(Int((value * 2).rounded()), 1), 10)
    }

    private func seconds(fromMinutes value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        let seconds = min(value * 60, Double(Int.max))
        return Int(seconds.rounded())
    }

    private func clampedPercentage(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private func identityKey(title: String, kind: MediaKind) -> String {
        "\(kind.rawValue)|\(LibraryItem.normalize(title))"
    }

    private func mergedText(_ current: String?, _ addition: String?) -> String? {
        guard let addition = addition?.trimmingCharacters(in: .whitespacesAndNewlines),
              !addition.isEmpty else { return current }
        guard let current = current?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty else { return addition }
        guard current != addition && !current.contains(addition) else { return current }
        return current + "\n\n" + addition
    }

    private func safePublicURL(_ rawValue: String) -> String? {
        guard let url = PodcastFeedPrivacy.validatedFeedURL(from: rawValue),
              !PodcastFeedPrivacy.containsEmbeddedCredential(in: url) else { return nil }
        return rawValue
    }

    private func opaqueHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func importedPlaybackDate(from rawFields: [String: String]) -> Date? {
        let candidateNames: Set<String> = [
            "played at", "played date", "date played", "completed at", "last played",
            "listened at", "playback date",
        ]
        guard let value = rawFields.first(where: {
            candidateNames.contains($0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        })?.value.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
