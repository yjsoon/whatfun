import CryptoKit
import Foundation
import SwiftData

@MainActor
final class SwiftDataArchiveBridge {
    private let context: ModelContext
    private let credentials: any CredentialStoring

    init(context: ModelContext, credentials: any CredentialStoring) {
        self.context = context
        self.credentials = credentials
    }

    func snapshot(includePrivateFeedSecrets: Bool = true) async throws -> DurabilitySnapshot {
        let items = try fetchAll(LibraryItem.self)
        let units = try fetchAll(ContentUnit.self).filter { $0.deletedAt == nil }
        let cycles = try fetchAll(ConsumptionCycle.self).filter { $0.deletedAt == nil }
        let cycleIDs = Set(cycles.map(\.id))
        let unitIDs = Set(units.map(\.id))
        let sessions = try fetchAll(ConsumptionSession.self).filter {
            $0.deletedAt == nil && cycleIDs.contains($0.cycleID)
        }
        let sessionIDs = Set(sessions.map(\.id))
        let events = try fetchAll(ActivityEvent.self)
        let quotes = try fetchAll(NotableQuote.self).filter {
            $0.deletedAt == nil && unitIDs.contains($0.episodeUnitID)
        }
        let artworks = try fetchAll(ArtworkAsset.self)
        let references = try fetchAll(ExternalReference.self)
        let credits = try fetchAll(Credit.self)
        let facets = try fetchAll(Facet.self)
        let facetMemberships = try fetchAll(ItemFacetMembership.self)
        let lists = try fetchAll(UserList.self)
        let listMemberships = try fetchAll(ListMembership.self)
        let smartRules = try fetchAll(SmartRule.self)
        let smartValues = try fetchAll(SmartRuleValue.self)
        let reminders = try fetchAll(StartReminder.self)

        let facetsByID = facets.reduce(into: [UUID: Facet]()) { result, facet in
            if result[facet.id] == nil { result[facet.id] = facet }
        }
        let membershipsByItem = Dictionary(grouping: facetMemberships, by: \.itemID)
        let creditsByItem = Dictionary(grouping: credits.filter { $0.unitID == nil }, by: \.rootItemID)
        let artworksByItem = Dictionary(grouping: artworks.filter { $0.unitID == nil }, by: \.rootItemID)
        let artworksByUnit = Dictionary(grouping: artworks.compactMap { artwork in
            artwork.unitID.map { ($0, artwork) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let referencesByItem = Dictionary(grouping: references, by: \.rootItemID)
        let sessionsByCycle = Dictionary(grouping: sessions, by: \.cycleID)

        var payload = ArchivePayload()
        payload.items = items.map { item in
            let itemMemberships = membershipsByItem[item.id, default: []]
            let genres = facetNames(kind: .genre, memberships: itemMemberships, facetsByID: facetsByID)
            let platforms = facetNames(kind: .platform, memberships: itemMemberships, facetsByID: facetsByID)
            let itemCredits = creditsByItem[item.id, default: []]
                .filter { ["creator", "author", "director", "developer", "host"].contains($0.roleRaw.lowercased()) }
                .sorted { $0.sortOrder < $1.sortOrder }
            let creators = itemCredits.isEmpty
                ? item.creatorLine.map { [$0] } ?? []
                : itemCredits.map(\.name)
            let preferredArtwork = preferredArtwork(
                id: item.preferredArtworkID,
                candidates: artworksByItem[item.id, default: []],
            )
            let privateReference = referencesByItem[item.id, default: []].first {
                $0.isActiveFeed && $0.isPrivateFeed
            }
            return ArchiveItemRecord(
                id: item.id,
                mediaKind: archiveMediaKind(item.mediaKind),
                title: item.title,
                subtitle: item.subtitle,
                sortTitle: item.sortTitle,
                originalTitle: item.originalTitle,
                summary: item.summary,
                creators: creators,
                genres: genres,
                platforms: platforms,
                languageCode: item.languageCode,
                pageCount: item.pageCount,
                runtimeMinutes: item.runtimeSeconds.map { Double($0) / 60 },
                releaseDate: item.releaseDate,
                releaseYear: item.releaseYear,
                userEditedFieldMask: item.userEditedFieldMask,
                metadataLastRefreshedAt: item.metadataLastRefreshedAt,
                preferredArtworkID: item.preferredArtworkID,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                archivedAt: item.archivedAt,
                deletedAt: item.trashedAt,
                purgeAfter: item.purgeAfter,
                isFavorite: item.isFavorite,
                comment: item.comment,
                projectedStatus: archiveStatus(item),
                projectedRating: item.effectiveRatingHalfSteps.map { Double($0) / 2 },
                ratingOverride: item.ratingOverrideHalfSteps.map { Double($0) / 2 },
                projectedStartDate: item.firstStartedAt,
                projectedCompletionDate: item.lastCompletedAt,
                projectedRepeatCount: item.repeatCount,
                artworkKind: preferredArtwork.map { archiveArtworkKind($0.kind) },
                artworkURL: preferredArtwork?.remoteURLString,
                artworkArchivePath: nil,
                podcastListeningStyle: item.podcastListeningStyle.flatMap(archiveListeningStyle),
                // Keychain identifiers are installation-local implementation details.
                // Only the separately encrypted private payload carries a feed URL.
                feedCredentialIdentifier: nil,
                feedURLIsPrivate: privateReference != nil,
            )
        }

        payload.units = units.map { unit in
            let preferredArtwork = preferredArtwork(
                id: unit.preferredArtworkID,
                candidates: artworksByUnit[unit.id, default: []],
            )
            return ArchiveUnitRecord(
                id: unit.id,
                itemID: unit.rootItemID,
                parentUnitID: unit.parentUnitID,
                kind: archiveUnitKind(unit.unitKind),
                title: unit.title,
                summary: unit.summary,
                guid: unit.episodeGUID,
                canonicalURL: unit.canonicalURLString,
                sortIndex: unit.sortOrder,
                numberValue: unit.numberValue,
                numberLabel: unit.numberLabel,
                seasonNumber: unit.seasonNumber,
                episodeNumber: unit.episodeNumber,
                volumeNumber: unit.unitKind == .comicVolume ? safeInteger(unit.numberValue) : nil,
                issueNumber: unit.unitKind == .comicIssue
                    ? unit.numberLabel ?? unit.numberValue.map { String($0) }
                    : nil,
                releasedAt: unit.publishedAt ?? unit.releaseDate,
                durationMinutes: unit.durationSeconds.map { Double($0) / 60 },
                pageCount: unit.pageCount,
                status: archiveStatus(unit.status),
                rating: unit.ratingHalfSteps.map { Double($0) / 2 },
                completedAt: unit.lastCompletedAt,
                isNotable: unit.isNotable,
                comment: unit.comment,
                artworkURL: preferredArtwork?.remoteURLString,
                artworkArchivePath: nil,
                releaseDate: unit.releaseDate,
                publishedAt: unit.publishedAt,
                userEditedFieldMask: unit.userEditedFieldMask,
                preferredArtworkID: unit.preferredArtworkID,
                createdAt: unit.createdAt,
                updatedAt: unit.updatedAt,
            )
        }

        payload.cycles = cycles.map { cycle in
            let itemKind = items.first(where: { $0.id == cycle.rootItemID })?.mediaKind ?? .unknown
            let latest = sessionsByCycle[cycle.id, default: []]
                .filter { $0.deletedAt == nil }
                .max { $0.occurredAt < $1.occurredAt }
            return ArchiveCycleRecord(
                id: cycle.id,
                itemID: cycle.rootItemID,
                unitID: cycle.targetUnitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                sequence: cycle.ordinal,
                kind: archiveCycleKind(cycle.cycleKind, mediaKind: itemKind),
                repeatOfCycleID: cycle.repeatOfCycleID,
                status: archiveStatus(cycle.status),
                startedAt: cycle.startedAt,
                completedAt: cycle.completedAt,
                rating: nil,
                note: nil,
                currentPage: latest?.currentPage,
                totalPages: latest?.totalPagesSnapshot,
                elapsedMinutes: latest?.elapsedSeconds.map { Double($0) / 60 },
                playtimeMinutes: latest?.gamePlaytimeTotalSnapshotSeconds.map { Double($0) / 60 },
                completionPercentage: latest?.completionPercent,
                createdAt: cycle.createdAt,
                updatedAt: cycle.updatedAt,
            )
        }

        payload.sessions = sessions.map { session in
            ArchiveSessionRecord(
                id: session.id,
                itemID: session.rootItemID,
                cycleID: session.cycleID,
                unitID: session.targetUnitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                startedAt: session.occurredAt,
                endedAt: session.endedAt,
                loggedAt: session.createdAt,
                timeZoneIdentifier: session.timeZoneIdentifier,
                durationMinutes: session.durationSeconds.map { Double($0) / 60 },
                startPage: nil,
                endPage: session.currentPage,
                totalPages: session.totalPagesSnapshot,
                chapter: session.chapter,
                startElapsedMinutes: nil,
                endElapsedMinutes: session.elapsedSeconds.map { Double($0) / 60 },
                totalRuntimeMinutes: session.mediaDurationSecondsSnapshot.map { Double($0) / 60 },
                playtimeDeltaMinutes: session.gamePlaytimeDeltaSeconds.map { Double($0) / 60 },
                cumulativePlaytimeMinutes: session.gamePlaytimeTotalSnapshotSeconds.map { Double($0) / 60 },
                completionPercentage: session.completionPercent,
                isCompletion: false,
                rating: nil,
                note: session.note,
                source: session.sourceRaw,
                updatedAt: session.updatedAt,
            )
        }

        payload.events = events.map { event in
            ArchiveEventRecord(
                id: event.id,
                itemID: event.rootItemID,
                cycleID: event.cycleID.flatMap { cycleIDs.contains($0) ? $0 : nil },
                unitID: event.targetUnitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                sessionID: nil,
                kind: archiveEventKind(event.kind),
                occurredAt: event.effectiveAt,
                timeZoneIdentifier: event.timeZoneIdentifier,
                previousStatus: event.fromStatus.map(archiveStatus),
                newStatus: event.toStatus.map(archiveStatus),
                note: event.note,
                details: [
                    "scope": event.scope.rawValue,
                    "source": event.source.rawValue,
                    "recorded_at": ArchiveDateCodec.string(from: event.recordedAt),
                ],
            )
        }

        payload.quotes = quotes.map { quote in
            ArchiveQuoteRecord(
                id: quote.id,
                itemID: quote.rootItemID,
                unitID: quote.episodeUnitID,
                sessionID: quote.sessionID.flatMap { sessionIDs.contains($0) ? $0 : nil },
                text: quote.text,
                timestampSeconds: quote.timestampSeconds.map(Double.init),
                comment: quote.comment,
                capturedAt: quote.createdAt,
                sortIndex: quote.sortOrder,
                updatedAt: quote.updatedAt,
            )
        }

        payload.lists = lists.map { list in
            ArchiveListRecord(
                id: list.id,
                name: list.name,
                kind: list.kind == .smart ? .smart : .manual,
                matchMode: list.matchMode == .any ? .any : .all,
                comment: list.notes,
                iconName: list.iconName,
                colorHex: list.colorToken,
                sortIndex: list.sortOrder,
                createdAt: list.createdAt,
                updatedAt: list.updatedAt,
                archivedAt: list.archivedAt,
                deletedAt: list.trashedAt,
                purgeAfter: list.purgeAfter,
            )
        }
        payload.smartListRules = smartRules.map { rule in
            ArchiveSmartListRuleRecord(
                id: rule.id,
                listID: rule.listID,
                sortIndex: rule.sortOrder,
                field: rule.fieldRaw,
                comparison: rule.operatorRaw,
                isNegated: rule.isNegated,
                createdAt: rule.createdAt,
                updatedAt: rule.updatedAt,
            )
        }
        payload.smartListRuleValues = smartValues.map { value in
            ArchiveSmartListRuleValueRecord(
                id: value.id,
                ruleID: value.ruleID,
                sortIndex: value.sortOrder,
                valueType: value.valueTypeRaw,
                stringValue: value.stringValue,
                numberValue: value.numberValue,
                dateValue: value.dateValue,
                boolValue: value.boolValue,
                referenceID: value.referenceID,
            )
        }
        payload.listMemberships = listMemberships.map { membership in
            ArchiveListMembershipRecord(
                id: membership.id,
                listID: membership.listID,
                itemID: membership.itemID,
                positionRank: membership.positionRank,
                addedAt: membership.addedAt,
                note: nil,
            )
        }

        payload.tags = facets.filter { $0.kind == .tag }.map { facet in
            ArchiveTagRecord(
                id: facet.id,
                name: facet.name,
                colorHex: facet.colorToken,
                createdAt: facet.createdAt,
                updatedAt: facet.updatedAt,
            )
        }
        payload.tagMemberships = facetMemberships.compactMap { membership in
            guard facetsByID[membership.facetID]?.kind == .tag else { return nil }
            return ArchiveTagMembershipRecord(
                id: membership.id,
                tagID: membership.facetID,
                itemID: membership.itemID,
                addedAt: membership.createdAt,
                source: membership.sourceRaw,
                sortIndex: membership.sortOrder,
            )
        }

        payload.artworks = artworks.map { artwork in
            ArchiveArtworkRecord(
                id: artwork.id,
                itemID: artwork.rootItemID,
                unitID: artwork.unitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                kind: archiveArtworkKind(artwork.kind),
                remoteURL: artwork.remoteURLString,
                cacheKey: artwork.cacheKey,
                archivePath: nil,
                imageData: artwork.kind == .userImage ? artwork.imageData : nil,
                contentHash: artwork.contentHash,
                mimeType: artwork.mimeType,
                pixelWidth: artwork.pixelWidth,
                pixelHeight: artwork.pixelHeight,
                aspectRatio: artwork.aspectRatio,
                provider: artwork.providerRaw,
                attributionText: artwork.attributionText,
                attributionURL: artwork.attributionURLString,
                createdAt: artwork.createdAt,
                updatedAt: artwork.updatedAt,
            )
        }
        payload.credits = credits.map { credit in
            ArchiveCreditRecord(
                id: credit.id,
                itemID: credit.rootItemID,
                unitID: credit.unitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                name: credit.name,
                role: credit.roleRaw,
                sortIndex: credit.sortOrder,
                externalPersonID: credit.externalPersonID,
                createdAt: credit.createdAt,
                updatedAt: credit.updatedAt,
            )
        }
        payload.reminders = reminders.map { reminder in
            ArchiveReminderRecord(
                id: reminder.id,
                itemID: reminder.itemID,
                fireAt: reminder.fireAt,
                timeZoneIdentifier: reminder.timeZoneIdentifier,
                state: archiveReminderState(reminder.state),
                createdAt: reminder.createdAt,
                updatedAt: reminder.updatedAt,
            )
        }
        payload.externalReferences = references.map { reference in
            ArchiveExternalReferenceRecord(
                id: reference.id,
                itemID: reference.rootItemID,
                unitID: reference.unitID.flatMap { unitIDs.contains($0) ? $0 : nil },
                provider: reference.providerRaw,
                recordKind: reference.recordKindRaw,
                externalID: reference.isPrivateFeed
                    ? "private.\(reference.id.uuidString.lowercased())"
                    : reference.externalID,
                canonicalURL: reference.isPrivateFeed ? nil : reference.canonicalURLString,
                lastFetchedAt: reference.lastFetchedAt,
                etag: reference.etag,
                lastModified: reference.lastModified,
                payloadHash: reference.payloadHash,
                payloadVersion: reference.payloadVersion,
                attributionText: reference.attributionText,
                attributionURL: reference.attributionURLString,
                isActiveFeed: reference.isActiveFeed,
                isPrivateFeed: reference.isPrivateFeed,
                credentialKeychainID: nil,
                createdAt: reference.createdAt,
                updatedAt: reference.updatedAt,
            )
        }

        let privatePayload: ArchivePrivatePayload?
        if includePrivateFeedSecrets {
            privatePayload = try await makePrivatePayload(references: references)
        } else {
            privatePayload = nil
        }
        return DurabilitySnapshot(
            payload: payload.stablySorted(),
            privatePayload: privatePayload?.privateFeedSecrets.isEmpty == false ? privatePayload : nil,
        )
    }

    func restore(
        payload: ArchivePayload,
        privatePayload: ArchivePrivatePayload? = nil,
        mode: ArchiveRestoreMode
    ) async throws -> ArchiveRestoreReport {
        try preflight(payload: payload, privatePayload: privatePayload, mode: mode)
        var report = ArchiveRestoreReport()
        var newlyWrittenCredentialKeys: [String] = []
        let oldPrivateCredentialKeysByReferenceID: [UUID: String]
        if mode == .replaceAll {
            oldPrivateCredentialKeysByReferenceID = try fetchAll(ExternalReference.self).reduce(into: [:]) {
                result, reference in
                if reference.isPrivateFeed, let key = reference.credentialKeychainID {
                    result[reference.id] = key
                }
            }
        } else {
            oldPrivateCredentialKeysByReferenceID = [:]
        }
        let oldPrivateCredentialKeys = Array(oldPrivateCredentialKeysByReferenceID.values)
        var retainedExistingCredentialKeys: Set<String> = []

        do {
            if mode == .replaceAll {
                try deleteAllSemanticRecords()
            }

            var itemsByID = mode == .mergeNew ? indexByID(try fetchAll(LibraryItem.self)) : [:]
            var unitsByID = mode == .mergeNew ? indexByID(try fetchAll(ContentUnit.self)) : [:]
            var cyclesByID = mode == .mergeNew ? indexByID(try fetchAll(ConsumptionCycle.self)) : [:]
            var sessionsByID = mode == .mergeNew ? indexByID(try fetchAll(ConsumptionSession.self)) : [:]
            var eventsByID = mode == .mergeNew ? indexByID(try fetchAll(ActivityEvent.self)) : [:]
            var listsByID = mode == .mergeNew ? indexByID(try fetchAll(UserList.self)) : [:]
            var rulesByID = mode == .mergeNew ? indexByID(try fetchAll(SmartRule.self)) : [:]
            var tagsByID: [UUID: Facet] = mode == .mergeNew
                ? indexByID(try fetchAll(Facet.self).filter { $0.kind == .tag })
                : [:]
            var referencesByID = mode == .mergeNew ? indexByID(try fetchAll(ExternalReference.self)) : [:]

            var insertedItemIDs: Set<UUID> = []
            var insertedUnitIDs: Set<UUID> = []
            var insertedReferenceIDs: Set<UUID> = []

            for record in payload.items {
                if itemsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                let item = LibraryItem(
                    id: record.id,
                    mediaKind: mediaKind(record.mediaKind),
                    title: record.title,
                    subtitle: record.subtitle,
                    createdAt: record.createdAt,
                )
                item.sortTitle = record.sortTitle ?? record.title
                item.originalTitle = record.originalTitle
                item.summary = record.summary
                item.creatorLine = record.creators.joined(separator: ", ").nilIfEmpty
                item.releaseDate = record.releaseDate
                item.releaseYear = record.releaseYear ?? record.releaseDate.map {
                    Calendar(identifier: .gregorian).component(.year, from: $0)
                }
                item.languageCode = record.languageCode
                item.pageCount = record.pageCount
                item.runtimeSeconds = seconds(record.runtimeMinutes)
                item.comment = record.comment
                item.isFavorite = record.isFavorite
                item.ratingOverrideHalfSteps = ratingHalfSteps(record.ratingOverride)
                item.archivedAt = record.archivedAt
                item.trashedAt = record.deletedAt
                item.purgeAfter = record.purgeAfter ?? record.deletedAt.flatMap {
                    Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: $0)
                }
                item.userEditedFieldMask = record.userEditedFieldMask ?? 0
                item.metadataLastRefreshedAt = record.metadataLastRefreshedAt
                item.preferredArtworkID = record.preferredArtworkID
                item.updatedAt = record.updatedAt
                if item.mediaKind == .podcast {
                    item.podcastFollowState = podcastFollowState(record.projectedStatus)
                    item.podcastListeningStyle = record.podcastListeningStyle.map(listeningStyle)
                }
                context.insert(item)
                itemsByID[item.id] = item
                insertedItemIDs.insert(item.id)
                report.insertedRecords += 1
            }

            // Tags have stable IDs. Genre/platform facets are normalized from item arrays later.
            for record in payload.tags {
                if tagsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                let facet = Facet(
                    id: record.id,
                    kind: .tag,
                    name: record.name,
                    colorToken: record.colorHex,
                    createdAt: record.createdAt,
                )
                facet.updatedAt = record.updatedAt
                context.insert(facet)
                tagsByID[facet.id] = facet
                report.insertedRecords += 1
            }

            for record in payload.lists {
                if listsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                let list = UserList(
                    id: record.id,
                    name: record.name,
                    kind: record.kind == .smart ? .smart : .manual,
                    matchMode: record.matchMode == .any ? .any : .all,
                    sortOrder: record.sortIndex,
                    createdAt: record.createdAt,
                )
                list.notes = record.comment
                list.iconName = record.iconName
                list.colorToken = record.colorHex
                list.archivedAt = record.archivedAt
                list.trashedAt = record.deletedAt
                list.purgeAfter = record.purgeAfter
                list.updatedAt = record.updatedAt
                context.insert(list)
                listsByID[list.id] = list
                report.insertedRecords += 1
            }

            for record in payload.units {
                if unitsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a unit whose item is missing."))
                    continue
                }
                let unit = ContentUnit(
                    id: record.id,
                    item: item,
                    kind: unitKind(record.kind, ownerKind: item.mediaKind),
                    title: record.title,
                    sortOrder: record.sortIndex,
                    createdAt: record.createdAt ?? record.releasedAt ?? item.createdAt,
                )
                unit.summary = record.summary
                unit.episodeGUID = record.guid
                unit.episodeGUIDHash = record.guid.map(stableHash)
                unit.canonicalURLString = record.canonicalURL
                unit.releaseDate = record.releaseDate ?? record.releasedAt
                unit.publishedAt = record.publishedAt ?? (unit.unitKind == .podcastEpisode ? record.releasedAt : nil)
                unit.durationSeconds = seconds(record.durationMinutes)
                unit.pageCount = record.pageCount
                unit.seasonNumber = record.seasonNumber
                unit.episodeNumber = record.episodeNumber
                unit.numberValue = record.numberValue
                unit.numberLabel = record.numberLabel
                if unit.unitKind == .comicVolume, unit.numberValue == nil {
                    unit.numberValue = record.volumeNumber.map(Double.init)
                    unit.numberLabel = unit.numberLabel ?? record.volumeNumber.map(String.init)
                } else if unit.unitKind == .comicIssue, unit.numberLabel == nil {
                    unit.numberLabel = record.issueNumber
                    unit.numberValue = unit.numberValue ?? record.issueNumber.flatMap(Double.init)
                }
                unit.isNotable = record.isNotable
                unit.comment = record.comment
                unit.ratingHalfSteps = ratingHalfSteps(record.rating)
                unit.userEditedFieldMask = record.userEditedFieldMask ?? 0
                unit.preferredArtworkID = record.preferredArtworkID
                unit.updatedAt = record.updatedAt ?? unit.createdAt
                context.insert(unit)
                item.units = appending(unit, to: item.units, id: \.id)
                unitsByID[unit.id] = unit
                insertedUnitIDs.insert(unit.id)
                report.insertedRecords += 1
            }

            for record in payload.units where insertedUnitIDs.contains(record.id) {
                guard let unit = unitsByID[record.id], let parentID = record.parentUnitID else { continue }
                guard let parent = unitsByID[parentID], parent.rootItemID == unit.rootItemID else {
                    report.warnings.append(.init(recordID: record.id, message: "The unit's parent was missing; restored at top level."))
                    continue
                }
                unit.parent = parent
                unit.parentUnitID = parent.id
                parent.children = appending(unit, to: parent.children, id: \.id)
            }

            for record in payload.cycles {
                if cyclesByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a cycle whose item is missing."))
                    continue
                }
                let target = record.unitID.flatMap { unitsByID[$0] }
                let cycle = ConsumptionCycle(
                    id: record.id,
                    item: item,
                    targetUnit: target,
                    kind: cycleKind(record.kind),
                    ordinal: record.sequence,
                    repeatOfCycleID: record.repeatOfCycleID,
                    createdAt: record.createdAt ?? record.startedAt ?? item.createdAt,
                )
                context.insert(cycle)
                cycle.status = consumptionStatus(record.status)
                cycle.startedAt = record.startedAt
                cycle.completedAt = record.completedAt
                cycle.updatedAt = record.updatedAt ?? cycle.createdAt
                item.cycles = appending(cycle, to: item.cycles, id: \.id)
                target?.cycles = appending(cycle, to: target?.cycles, id: \.id)
                cyclesByID[cycle.id] = cycle
                report.insertedRecords += 1
            }

            // Older portable archives may not carry repeat ancestry; use stable order as fallback.
            for item in itemsByID.values {
                let ordered = cyclesByID.values
                    .filter { $0.rootItemID == item.id }
                    .sorted { $0.ordinal < $1.ordinal }
                for (index, cycle) in ordered.enumerated() where cycle.cycleKind == .repeatConsumption && index > 0 {
                    if cycle.repeatOfCycleID == nil {
                        cycle.repeatOfCycleID = ordered[index - 1].id
                    }
                }
            }

            for record in payload.sessions {
                if sessionsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let cycleID = record.cycleID, let cycle = cyclesByID[cycleID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a session whose cycle is missing."))
                    continue
                }
                let target = record.unitID.flatMap { unitsByID[$0] }
                let session = ConsumptionSession(
                    id: record.id,
                    cycle: cycle,
                    targetUnit: target,
                    occurredAt: record.startedAt,
                    timeZoneIdentifier: record.timeZoneIdentifier,
                    durationSeconds: seconds(record.durationMinutes),
                    note: record.note,
                    source: record.source.map(RecordSource.value(for:)) ?? .portableImport,
                )
                session.endedAt = record.endedAt
                session.currentPage = record.endPage ?? record.startPage
                session.totalPagesSnapshot = record.totalPages
                session.chapter = record.chapter
                session.elapsedSeconds = seconds(record.endElapsedMinutes ?? record.startElapsedMinutes)
                session.mediaDurationSecondsSnapshot = seconds(record.totalRuntimeMinutes)
                session.gamePlaytimeDeltaSeconds = seconds(record.playtimeDeltaMinutes)
                session.gamePlaytimeTotalSnapshotSeconds = seconds(record.cumulativePlaytimeMinutes)
                session.completionPercent = record.completionPercentage
                session.createdAt = record.loggedAt
                session.updatedAt = record.updatedAt ?? record.loggedAt
                context.insert(session)
                cycle.sessions = appending(session, to: cycle.sessions, id: \.id)
                target?.sessions = appending(session, to: target?.sessions, id: \.id)
                sessionsByID[session.id] = session
                report.insertedRecords += 1
            }

            for record in payload.events {
                if eventsByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped an event whose item is missing."))
                    continue
                }
                let cycle = record.cycleID.flatMap { cyclesByID[$0] }
                let unit = record.unitID.flatMap { unitsByID[$0] }
                let event = ActivityEvent(
                    id: record.id,
                    item: item,
                    cycle: cycle,
                    targetUnit: unit,
                    scope: ActivityScope.value(for: record.details["scope"] ?? (unit == nil ? "item" : "unit")),
                    kind: eventKind(record.kind),
                    fromStatus: record.previousStatus.map(consumptionStatus),
                    toStatus: record.newStatus.map(consumptionStatus),
                    effectiveAt: record.occurredAt,
                    timeZoneIdentifier: record.timeZoneIdentifier,
                    note: record.note,
                    source: RecordSource.value(for: record.details["source"] ?? RecordSource.portableImport.rawValue),
                )
                event.recordedAt = record.details["recorded_at"].flatMap(ArchiveDateCodec.date) ?? record.occurredAt
                context.insert(event)
                item.activityEvents = appending(event, to: item.activityEvents, id: \.id)
                cycle?.activityEvents = appending(event, to: cycle?.activityEvents, id: \.id)
                unit?.activityEvents = appending(event, to: unit?.activityEvents, id: \.id)
                eventsByID[event.id] = event
                report.insertedRecords += 1
            }

            var quoteIDs = mode == .mergeNew ? Set(try fetchAll(NotableQuote.self).map(\.id)) : []
            for (fallbackSortIndex, record) in payload.quotes.enumerated() {
                if quoteIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let unitID = record.unitID, let episode = unitsByID[unitID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a quote whose episode is missing."))
                    continue
                }
                let quote = NotableQuote(
                    id: record.id,
                    episode: episode,
                    text: record.text,
                    timestampSeconds: record.timestampSeconds.map { Int($0.rounded()) },
                    comment: record.comment,
                    sortOrder: record.sortIndex ?? fallbackSortIndex,
                    sessionID: record.sessionID.flatMap { sessionsByID[$0]?.id },
                    createdAt: record.capturedAt,
                )
                quote.updatedAt = record.updatedAt ?? record.capturedAt
                context.insert(quote)
                episode.notableQuotes = appending(quote, to: episode.notableQuotes, id: \.id)
                quoteIDs.insert(quote.id)
                report.insertedRecords += 1
            }

            for record in payload.smartListRules {
                if rulesByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let list = listsByID[record.listID], list.kind == .smart else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a smart rule whose list is missing."))
                    continue
                }
                let rule = SmartRule(
                    id: record.id,
                    list: list,
                    fieldRaw: record.field,
                    operatorRaw: record.comparison,
                    isNegated: record.isNegated,
                    sortOrder: record.sortIndex,
                    createdAt: record.createdAt,
                )
                rule.updatedAt = record.updatedAt
                context.insert(rule)
                list.smartRules = appending(rule, to: list.smartRules, id: \.id)
                rulesByID[rule.id] = rule
                report.insertedRecords += 1
            }

            var smartValueIDs = mode == .mergeNew ? Set(try fetchAll(SmartRuleValue.self).map(\.id)) : []
            for record in payload.smartListRuleValues {
                if smartValueIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let rule = rulesByID[record.ruleID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped a smart-rule value whose rule is missing."))
                    continue
                }
                let value = SmartRuleValue(
                    id: record.id,
                    rule: rule,
                    valueTypeRaw: record.valueType,
                    stringValue: record.stringValue,
                    numberValue: record.numberValue,
                    dateValue: record.dateValue,
                    boolValue: record.boolValue,
                    referenceID: record.referenceID,
                    sortOrder: record.sortIndex,
                )
                context.insert(value)
                rule.values = appending(value, to: rule.values, id: \.id)
                smartValueIDs.insert(value.id)
                report.insertedRecords += 1
            }

            var listMembershipIDs = mode == .mergeNew ? Set(try fetchAll(ListMembership.self).map(\.id)) : []
            for record in payload.listMemberships {
                if listMembershipIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let list = listsByID[record.listID], let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped an orphaned list membership."))
                    continue
                }
                let membership = ListMembership(
                    id: record.id,
                    list: list,
                    item: item,
                    positionRank: record.positionRank ?? String(record.addedAt.timeIntervalSince1970),
                    addedAt: record.addedAt,
                )
                context.insert(membership)
                list.memberships = appending(membership, to: list.memberships, id: \.id)
                item.listMemberships = appending(membership, to: item.listMemberships, id: \.id)
                listMembershipIDs.insert(membership.id)
                report.insertedRecords += 1
            }

            var tagMembershipIDs = mode == .mergeNew ? Set(try fetchAll(ItemFacetMembership.self).map(\.id)) : []
            for record in payload.tagMemberships {
                if tagMembershipIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let tag = tagsByID[record.tagID], let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped an orphaned tag membership."))
                    continue
                }
                let membership = ItemFacetMembership(
                    id: record.id,
                    item: item,
                    facet: tag,
                    source: RecordSource.value(for: record.source ?? RecordSource.portableImport.rawValue),
                    sortOrder: record.sortIndex ?? 0,
                    createdAt: record.addedAt,
                )
                context.insert(membership)
                tag.memberships = appending(membership, to: tag.memberships, id: \.id)
                item.facetMemberships = appending(membership, to: item.facetMemberships, id: \.id)
                tagMembershipIDs.insert(membership.id)
                report.insertedRecords += 1
            }

            try restoreSimpleFacets(
                payload: payload,
                itemsByID: itemsByID,
                existingFacets: try fetchAll(Facet.self),
                report: &report,
            )

            var artworkIDs = mode == .mergeNew ? Set(try fetchAll(ArtworkAsset.self).map(\.id)) : []
            for record in payload.artworks {
                if artworkIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    continue
                }
                let unit = record.unitID.flatMap { unitsByID[$0] }
                let artwork = ArtworkAsset(
                    id: record.id,
                    ownerItem: item,
                    unit: unit,
                    kind: artworkKind(record.kind),
                    remoteURLString: record.remoteURL,
                    imageData: record.kind == .remote ? nil : record.imageData,
                    createdAt: record.createdAt,
                )
                artwork.cacheKey = record.cacheKey ?? record.remoteURL.map(stableHash)
                artwork.contentHash = record.contentHash
                artwork.mimeType = record.mimeType
                artwork.pixelWidth = record.pixelWidth
                artwork.pixelHeight = record.pixelHeight
                artwork.aspectRatio = record.aspectRatio
                artwork.providerRaw = record.provider
                artwork.attributionText = record.attributionText
                artwork.attributionURLString = record.attributionURL
                artwork.updatedAt = record.updatedAt
                context.insert(artwork)
                item.artworkAssets = appending(artwork, to: item.artworkAssets, id: \.id)
                unit?.artworkAssets = appending(artwork, to: unit?.artworkAssets, id: \.id)
                artworkIDs.insert(artwork.id)
                report.insertedRecords += 1
            }

            var creditIDs = mode == .mergeNew ? Set(try fetchAll(Credit.self).map(\.id)) : []
            for record in payload.credits {
                if creditIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    continue
                }
                let unit = record.unitID.flatMap { unitsByID[$0] }
                let credit = Credit(
                    id: record.id,
                    ownerItem: item,
                    unit: unit,
                    name: record.name,
                    roleRaw: record.role,
                    sortOrder: record.sortIndex,
                    createdAt: record.createdAt,
                )
                credit.externalPersonID = record.externalPersonID
                credit.updatedAt = record.updatedAt
                context.insert(credit)
                item.credits = appending(credit, to: item.credits, id: \.id)
                unit?.credits = appending(credit, to: unit?.credits, id: \.id)
                creditIDs.insert(credit.id)
                report.insertedRecords += 1
            }

            var reminderIDs = mode == .mergeNew ? Set(try fetchAll(StartReminder.self).map(\.id)) : []
            for record in payload.reminders {
                if reminderIDs.contains(record.id) {
                    report.skippedExistingRecords += 1
                    continue
                }
                guard let item = itemsByID[record.itemID] else {
                    report.skippedOrphanedRecords += 1
                    continue
                }
                let reminder = StartReminder(
                    id: record.id,
                    item: item,
                    fireAt: record.fireAt,
                    timeZoneIdentifier: record.timeZoneIdentifier,
                    notificationIdentifier: "restored.\(UUID().uuidString.lowercased())",
                    createdAt: record.createdAt,
                )
                reminder.state = reminderState(record.state)
                reminder.updatedAt = record.updatedAt
                context.insert(reminder)
                item.reminders = appending(reminder, to: item.reminders, id: \.id)
                reminderIDs.insert(reminder.id)
                report.insertedRecords += 1
            }

            for record in payload.externalReferences {
                if referencesByID[record.id] != nil {
                    report.skippedExistingRecords += 1
                    continue
                }
                let resolvedItemID = record.itemID ?? record.unitID.flatMap { unitsByID[$0]?.rootItemID }
                guard let itemID = resolvedItemID, let item = itemsByID[itemID] else {
                    report.skippedOrphanedRecords += 1
                    report.warnings.append(.init(recordID: record.id, message: "Skipped an external reference whose item is missing."))
                    continue
                }
                let unit = record.unitID.flatMap { unitsByID[$0] }
                let reference = ExternalReference(
                    id: record.id,
                    ownerItem: item,
                    unit: unit,
                    providerRaw: record.provider,
                    recordKindRaw: record.recordKind,
                    externalID: record.externalID,
                    canonicalURLString: record.isPrivateFeed ? nil : record.canonicalURL,
                    createdAt: record.createdAt,
                )
                reference.lastFetchedAt = record.lastFetchedAt
                reference.etag = record.etag
                reference.lastModified = record.lastModified
                reference.payloadHash = record.payloadHash
                reference.payloadVersion = record.payloadVersion
                reference.attributionText = record.attributionText
                reference.attributionURLString = record.attributionURL
                reference.isActiveFeed = record.isActiveFeed
                reference.isPrivateFeed = record.isPrivateFeed
                reference.credentialKeychainID = nil
                reference.updatedAt = record.updatedAt
                context.insert(reference)
                item.externalReferences = appending(reference, to: item.externalReferences, id: \.id)
                unit?.externalReferences = appending(reference, to: unit?.externalReferences, id: \.id)
                referencesByID[reference.id] = reference
                insertedReferenceIDs.insert(reference.id)
                report.insertedRecords += 1
            }

            let incomingPrivateReferenceIDs = Set(
                privatePayload?.privateFeedSecrets.map(\.externalReferenceID) ?? []
            )
            // Daily backups intentionally exclude feed URLs. During a same-install
            // restore, reconnect a stable reference to its still-valid Keychain item.
            for referenceID in insertedReferenceIDs where !incomingPrivateReferenceIDs.contains(referenceID) {
                guard let reference = referencesByID[referenceID], reference.isPrivateFeed,
                      let oldKey = oldPrivateCredentialKeysByReferenceID[referenceID],
                      try await credentials.value(for: oldKey) != nil
                else { continue }
                reference.credentialKeychainID = oldKey
                retainedExistingCredentialKeys.insert(oldKey)
            }

            if let privatePayload {
                for secret in privatePayload.privateFeedSecrets {
                    guard let reference = referencesByID[secret.externalReferenceID], reference.isPrivateFeed else {
                        throw DurabilityError.invalidPrivateFeedReference(secret.externalReferenceID)
                    }
                    // Merge-new never mutates an existing semantic record or its
                    // installation-local Keychain association.
                    guard insertedReferenceIDs.contains(reference.id) else { continue }
                    let key = "podcast-feed.restore.\(reference.rootItemID.uuidString.lowercased()).\(UUID().uuidString.lowercased())"
                    try await credentials.set(secret.feedURL, for: key)
                    newlyWrittenCredentialKeys.append(key)
                    reference.credentialKeychainID = key
                    report.restoredPrivateFeeds += 1
                }
            }

            for record in payload.items {
                guard let item = itemsByID[record.id] else { continue }
                let candidates = (item.artworkAssets ?? []).filter { $0.unitID == nil }
                item.preferredArtworkID = record.preferredArtworkID.flatMap { preferredID in
                    candidates.first(where: { $0.id == preferredID })?.id
                } ?? candidates.first(where: {
                    $0.remoteURLString == record.artworkURL && record.artworkURL != nil
                })?.id ?? candidates.first(where: { $0.kind == .userImage })?.id ?? candidates.first?.id
            }
            for record in payload.units {
                guard let unit = unitsByID[record.id] else { continue }
                let candidates = unit.artworkAssets ?? []
                unit.preferredArtworkID = record.preferredArtworkID.flatMap { preferredID in
                    candidates.first(where: { $0.id == preferredID })?.id
                } ?? candidates.first(where: {
                    $0.remoteURLString == record.artworkURL && record.artworkURL != nil
                })?.id ?? candidates.first(where: { $0.kind == .userImage })?.id ?? candidates.first?.id
            }

            for item in itemsByID.values {
                ActivityProjection.rebuild(item)
            }

            do {
                try context.save()
            } catch {
                context.rollback()
                for key in newlyWrittenCredentialKeys {
                    try? await credentials.removeValue(for: key)
                }
                throw error
            }

            if mode == .replaceAll {
                let retained = Set(newlyWrittenCredentialKeys).union(retainedExistingCredentialKeys)
                for key in oldPrivateCredentialKeys where !retained.contains(key) {
                    try? await credentials.removeValue(for: key)
                }
            }
            return report
        } catch {
            context.rollback()
            for key in newlyWrittenCredentialKeys {
                try? await credentials.removeValue(for: key)
            }
            throw error
        }
    }

    private func makePrivatePayload(references: [ExternalReference]) async throws -> ArchivePrivatePayload {
        var secrets: [ArchivePrivateFeedSecret] = []
        for reference in references where reference.isPrivateFeed {
            guard let key = reference.credentialKeychainID,
                  let url = try await credentials.value(for: key)
            else { continue }
            secrets.append(ArchivePrivateFeedSecret(
                id: reference.id,
                externalReferenceID: reference.id,
                feedURL: url,
            ))
        }
        return ArchivePrivatePayload(privateFeedSecrets: secrets.sorted {
            $0.externalReferenceID.uuidString < $1.externalReferenceID.uuidString
        })
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func facetNames(
        kind: FacetKind,
        memberships: [ItemFacetMembership],
        facetsByID: [UUID: Facet]
    ) -> [String] {
        memberships
            .filter { facetsByID[$0.facetID]?.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { facetsByID[$0.facetID]?.name }
    }

    private func preferredArtwork(id: UUID?, candidates: [ArtworkAsset]) -> ArtworkAsset? {
        id.flatMap { preferredID in candidates.first { $0.id == preferredID } }
            ?? candidates.first(where: { $0.kind == .userImage })
            ?? candidates.first
    }

    private func safeInteger(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value.rounded() == value,
              value >= Double(Int.min), value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }
}

private extension SwiftDataArchiveBridge {
    func archiveMediaKind(_ value: MediaKind) -> ArchiveMediaKind {
        switch value {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .tvShow: .television
        case .game: .game
        case .podcast: .podcast
        case .unknown: .book
        }
    }

    func archiveStatus(_ value: ConsumptionStatus) -> ArchiveLifecycleStatus {
        switch value {
        case .planned: .planned
        case .inProgress: .inProgress
        case .paused: .paused
        case .completed: .completed
        case .dropped: .dropped
        case .unknown: .planned
        }
    }

    func archiveStatus(_ item: LibraryItem) -> ArchiveLifecycleStatus {
        if item.mediaKind == .podcast, let followState = item.podcastFollowState {
            return switch followState {
            case .following: .following
            case .paused: .paused
            case .completed: .completed
            case .dropped: .dropped
            case .unknown: archiveStatus(item.status)
            }
        }
        return archiveStatus(item.status)
    }

    func archiveListeningStyle(_ value: PodcastListeningStyle) -> ArchivePodcastListeningStyle? {
        switch value {
        case .everyEpisode: .everyEpisode
        case .selectedEpisodes: .selectedEpisodes
        case .keepAround: .keepAround
        case .unknown: nil
        }
    }

    func archiveUnitKind(_ value: ContentUnitKind) -> ArchiveUnitKind {
        switch value {
        case .tvSeason: .season
        case .tvEpisode, .podcastEpisode: .episode
        case .comicVolume: .volume
        case .comicIssue: .issue
        case .unknown: .episode
        }
    }

    func archiveCycleKind(_ value: ConsumptionCycleKind, mediaKind: MediaKind) -> ArchiveCycleKind {
        if value == .installmentContinuation { return .installmentContinuation }
        guard value == .repeatConsumption else { return .initial }
        return switch mediaKind {
        case .book, .comic: .reread
        case .movie, .tvShow: .rewatch
        case .game: .replay
        case .podcast, .unknown: .repeatConsumption
        }
    }

    func archiveEventKind(_ value: ActivityEventKind) -> ArchiveEventKind {
        switch value {
        case .created: .created
        case .started: .started
        case .statusSet: .statusChanged
        case .completed: .markedCompleted
        case .reopened: .completionReversed
        case .archived: .archived
        case .restored, .recovered: .restored
        case .trashed: .movedToTrash
        case .unknown: .statusChanged
        }
    }

    func archiveArtworkKind(_ value: ArtworkKind) -> ArchiveArtworkKind {
        switch value {
        case .providerRemote: .remote
        case .userImage: .userSelected
        case .unknown: .generated
        }
    }

    func archiveReminderState(_ value: ReminderState) -> ArchiveReminderState {
        switch value {
        case .pending: .pending
        case .delivered: .delivered
        case .cancelled, .unknown: .cancelled
        }
    }

    func mediaKind(_ value: ArchiveMediaKind) -> MediaKind {
        switch value {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .television: .tvShow
        case .game: .game
        case .podcast: .podcast
        }
    }

    func consumptionStatus(_ value: ArchiveLifecycleStatus) -> ConsumptionStatus {
        switch value {
        case .planned: .planned
        case .paused: .paused
        case .completed: .completed
        case .dropped: .dropped
        case .inProgress, .rereading, .rewatching, .replaying, .following: .inProgress
        case .archived: .planned
        }
    }

    func podcastFollowState(_ value: ArchiveLifecycleStatus) -> PodcastFollowState {
        switch value {
        case .following: .following
        case .paused: .paused
        case .completed: .completed
        case .dropped: .dropped
        default: .following
        }
    }

    func listeningStyle(_ value: ArchivePodcastListeningStyle) -> PodcastListeningStyle {
        switch value {
        case .everyEpisode: .everyEpisode
        case .selectedEpisodes: .selectedEpisodes
        case .keepAround: .keepAround
        }
    }

    func unitKind(_ value: ArchiveUnitKind, ownerKind: MediaKind) -> ContentUnitKind {
        switch value {
        case .season: .tvSeason
        case .episode: ownerKind == .podcast ? .podcastEpisode : .tvEpisode
        case .volume: .comicVolume
        case .issue: .comicIssue
        }
    }

    func cycleKind(_ value: ArchiveCycleKind) -> ConsumptionCycleKind {
        switch value {
        case .initial: .initial
        case .installmentContinuation: .installmentContinuation
        case .reread, .rewatch, .replay, .repeatConsumption: .repeatConsumption
        }
    }

    func eventKind(_ value: ArchiveEventKind) -> ActivityEventKind {
        switch value {
        case .created: .created
        case .started: .started
        case .statusChanged, .progressUpdated: .statusSet
        case .markedCompleted: .completed
        case .completionReversed: .reopened
        case .archived: .archived
        case .restored: .restored
        case .movedToTrash: .trashed
        }
    }

    func artworkKind(_ value: ArchiveArtworkKind) -> ArtworkKind {
        value == .remote ? .providerRemote : .userImage
    }

    func reminderState(_ value: ArchiveReminderState) -> ReminderState {
        switch value {
        case .pending: .pending
        case .delivered: .delivered
        case .cancelled: .cancelled
        }
    }

    func seconds(_ minutes: Double?) -> Int? {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return nil }
        let value = (minutes * 60).rounded()
        guard value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    func ratingHalfSteps(_ rating: Double?) -> Int? {
        guard let rating, rating.isFinite, (0.5 ... 5).contains(rating) else { return nil }
        return min(max(Int((rating * 2).rounded()), 1), 10)
    }

    func stableHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func indexByID<T: BackupIdentified>(_ values: [T]) -> [UUID: T] {
        values.reduce(into: [:]) { result, value in
            if result[value.id] == nil { result[value.id] = value }
        }
    }

    func appending<T>(_ value: T, to values: [T]?, id: KeyPath<T, UUID>) -> [T] {
        var copy = values ?? []
        if !copy.contains(where: { $0[keyPath: id] == value[keyPath: id] }) {
            copy.append(value)
        }
        return copy
    }

    func deleteAllSemanticRecords() throws {
        try deleteAll(SmartRuleValue.self)
        try deleteAll(SmartRule.self)
        try deleteAll(ListMembership.self)
        try deleteAll(ItemFacetMembership.self)
        try deleteAll(StartReminder.self)
        try deleteAll(NotableQuote.self)
        try deleteAll(ConsumptionSession.self)
        try deleteAll(ActivityEvent.self)
        try deleteAll(ConsumptionCycle.self)
        try deleteAll(Credit.self)
        try deleteAll(ExternalReference.self)
        try deleteAll(ArtworkAsset.self)
        try deleteAll(ContentUnit.self)
        try deleteAll(UserList.self)
        try deleteAll(Facet.self)
        try deleteAll(LibraryItem.self)
    }

    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for value in try fetchAll(type) { context.delete(value) }
    }

    func restoreSimpleFacets(
        payload: ArchivePayload,
        itemsByID: [UUID: LibraryItem],
        existingFacets: [Facet],
        report: inout ArchiveRestoreReport
    ) throws {
        var facetsByKey = existingFacets.reduce(into: [String: Facet]()) { result, facet in
            let key = "\(facet.kindRaw)|\(facet.normalizedName)"
            if result[key] == nil { result[key] = facet }
        }
        var existingPairs = Set(try fetchAll(ItemFacetMembership.self).map { "\($0.itemID)|\($0.facetID)" })

        for itemRecord in payload.items {
            guard let item = itemsByID[itemRecord.id] else { continue }
            for (kind, names) in [(FacetKind.genre, itemRecord.genres), (FacetKind.platform, itemRecord.platforms)] {
                for (sortIndex, name) in names.enumerated() where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let normalized = LibraryItem.normalize(name)
                    let key = "\(kind.rawValue)|\(normalized)"
                    let facet: Facet
                    if let existing = facetsByKey[key] {
                        facet = existing
                    } else {
                        facet = Facet(kind: kind, name: name, createdAt: item.createdAt)
                        context.insert(facet)
                        facetsByKey[key] = facet
                        report.insertedRecords += 1
                    }
                    let pair = "\(item.id)|\(facet.id)"
                    guard existingPairs.insert(pair).inserted else { continue }
                    let membership = ItemFacetMembership(
                        item: item,
                        facet: facet,
                        source: .portableImport,
                        sortOrder: sortIndex,
                        createdAt: item.createdAt,
                    )
                    context.insert(membership)
                    facet.memberships = appending(membership, to: facet.memberships, id: \.id)
                    item.facetMemberships = appending(membership, to: item.facetMemberships, id: \.id)
                    report.insertedRecords += 1
                }
            }
        }
    }

    func preflight(
        payload: ArchivePayload,
        privatePayload: ArchivePrivatePayload?,
        mode: ArchiveRestoreMode
    ) throws {
        try ensureUnique(payload.items.map(\.id), table: "items")
        try ensureUnique(payload.units.map(\.id), table: "units")
        try ensureUnique(payload.cycles.map(\.id), table: "cycles")
        try ensureUnique(payload.sessions.map(\.id), table: "sessions")
        try ensureUnique(payload.events.map(\.id), table: "events")
        try ensureUnique(payload.quotes.map(\.id), table: "quotes")
        try ensureUnique(payload.lists.map(\.id), table: "lists")
        try ensureUnique(payload.smartListRules.map(\.id), table: "smart_list_rules")
        try ensureUnique(payload.smartListRuleValues.map(\.id), table: "smart_list_rule_values")
        try ensureUnique(payload.listMemberships.map(\.id), table: "list_memberships")
        try ensureUnique(payload.tags.map(\.id), table: "tags")
        try ensureUnique(payload.tagMemberships.map(\.id), table: "tag_memberships")
        try ensureUnique(payload.artworks.map(\.id), table: "artworks")
        try ensureUnique(payload.credits.map(\.id), table: "credits")
        try ensureUnique(payload.reminders.map(\.id), table: "reminders")
        try ensureUnique(payload.externalReferences.map(\.id), table: "external_references")

        var itemIDs = Set(payload.items.map(\.id))
        var unitRoots = Dictionary(uniqueKeysWithValues: payload.units.map { ($0.id, $0.itemID) })
        var cycleRoots = Dictionary(uniqueKeysWithValues: payload.cycles.map { ($0.id, $0.itemID) })
        var listIDs = Set(payload.lists.map(\.id))
        var ruleIDs = Set(payload.smartListRules.map(\.id))
        var tagIDs = Set(payload.tags.map(\.id))

        if mode == .mergeNew {
            itemIDs.formUnion(try fetchAll(LibraryItem.self).map(\.id))
            let archivedUnits = Dictionary(uniqueKeysWithValues: payload.units.map { ($0.id, $0) })
            for unit in try fetchAll(ContentUnit.self) {
                if let archived = archivedUnits[unit.id],
                   archived.itemID != unit.rootItemID || archived.parentUnitID != unit.parentUnitID
                {
                    throw DurabilityError.invalidArchive("unit \(unit.id) conflicts with existing relationships")
                }
                unitRoots[unit.id] = unit.rootItemID
            }
            let archivedCycles = Dictionary(uniqueKeysWithValues: payload.cycles.map { ($0.id, $0) })
            for cycle in try fetchAll(ConsumptionCycle.self) {
                if let archived = archivedCycles[cycle.id],
                   archived.itemID != cycle.rootItemID || archived.unitID != cycle.targetUnitID
                {
                    throw DurabilityError.invalidArchive("cycle \(cycle.id) conflicts with existing relationships")
                }
                cycleRoots[cycle.id] = cycle.rootItemID
            }
            listIDs.formUnion(try fetchAll(UserList.self).map(\.id))
            let archivedRules = Dictionary(uniqueKeysWithValues: payload.smartListRules.map { ($0.id, $0) })
            for rule in try fetchAll(SmartRule.self) {
                if let archived = archivedRules[rule.id], archived.listID != rule.listID {
                    throw DurabilityError.invalidArchive("smart rule \(rule.id) conflicts with an existing list relationship")
                }
                ruleIDs.insert(rule.id)
            }
            let archivedTagIDs = Set(payload.tags.map(\.id))
            for facet in try fetchAll(Facet.self) {
                if archivedTagIDs.contains(facet.id), facet.kind != .tag {
                    throw DurabilityError.invalidArchive("tag \(facet.id) conflicts with an existing non-tag facet")
                }
                if facet.kind == .tag { tagIDs.insert(facet.id) }
            }
            try validateMergeCollisions(payload: payload, unitRoots: unitRoots)
        }

        for unit in payload.units {
            guard itemIDs.contains(unit.itemID) else { throw DurabilityError.invalidArchive("unit \(unit.id) has no item") }
            if let parentID = unit.parentUnitID {
                guard unitRoots[parentID] == unit.itemID else {
                    throw DurabilityError.invalidArchive("unit \(unit.id) has a cross-item or missing parent")
                }
            }
        }
        try validateParentCycles(payload.units)

        for cycle in payload.cycles {
            guard itemIDs.contains(cycle.itemID) else { throw DurabilityError.invalidArchive("cycle \(cycle.id) has no item") }
            if let unitID = cycle.unitID, unitRoots[unitID] != cycle.itemID {
                throw DurabilityError.invalidArchive("cycle \(cycle.id) targets another item's unit")
            }
            if let repeatID = cycle.repeatOfCycleID,
               repeatID == cycle.id || cycleRoots[repeatID] != cycle.itemID {
                throw DurabilityError.invalidArchive("cycle \(cycle.id) has a cross-item or missing repeat ancestor")
            }
        }
        for session in payload.sessions {
            guard itemIDs.contains(session.itemID) else { throw DurabilityError.invalidArchive("session \(session.id) has no item") }
            guard let cycleID = session.cycleID, cycleRoots[cycleID] == session.itemID else {
                throw DurabilityError.invalidArchive("session \(session.id) has no matching cycle")
            }
            if let unitID = session.unitID, unitRoots[unitID] != session.itemID {
                throw DurabilityError.invalidArchive("session \(session.id) targets another item's unit")
            }
        }
        for event in payload.events {
            guard itemIDs.contains(event.itemID) else { throw DurabilityError.invalidArchive("event \(event.id) has no item") }
            if let cycleID = event.cycleID, cycleRoots[cycleID] != event.itemID {
                throw DurabilityError.invalidArchive("event \(event.id) references another item's cycle")
            }
            if let unitID = event.unitID, unitRoots[unitID] != event.itemID {
                throw DurabilityError.invalidArchive("event \(event.id) references another item's unit")
            }
        }
        for quote in payload.quotes {
            guard let unitID = quote.unitID, unitRoots[unitID] == quote.itemID else {
                throw DurabilityError.invalidArchive("quote \(quote.id) has no matching unit")
            }
        }
        for rule in payload.smartListRules where !listIDs.contains(rule.listID) {
            throw DurabilityError.invalidArchive("smart rule \(rule.id) has no list")
        }
        for value in payload.smartListRuleValues where !ruleIDs.contains(value.ruleID) {
            throw DurabilityError.invalidArchive("smart-rule value \(value.id) has no rule")
        }
        for membership in payload.listMemberships
            where !listIDs.contains(membership.listID) || !itemIDs.contains(membership.itemID)
        {
            throw DurabilityError.invalidArchive("list membership \(membership.id) is orphaned")
        }
        for membership in payload.tagMemberships
            where !tagIDs.contains(membership.tagID) || !itemIDs.contains(membership.itemID)
        {
            throw DurabilityError.invalidArchive("tag membership \(membership.id) is orphaned")
        }
        for artwork in payload.artworks {
            guard itemIDs.contains(artwork.itemID) else { throw DurabilityError.invalidArchive("artwork \(artwork.id) has no item") }
            if let unitID = artwork.unitID, unitRoots[unitID] != artwork.itemID {
                throw DurabilityError.invalidArchive("artwork \(artwork.id) references another item's unit")
            }
        }
        for credit in payload.credits {
            guard itemIDs.contains(credit.itemID) else { throw DurabilityError.invalidArchive("credit \(credit.id) has no item") }
            if let unitID = credit.unitID, unitRoots[unitID] != credit.itemID {
                throw DurabilityError.invalidArchive("credit \(credit.id) references another item's unit")
            }
        }
        for reminder in payload.reminders where !itemIDs.contains(reminder.itemID) {
            throw DurabilityError.invalidArchive("reminder \(reminder.id) has no item")
        }
        let referenceIDs = Set(payload.externalReferences.map(\.id))
        for reference in payload.externalReferences {
            let resolvedItemID = reference.itemID ?? reference.unitID.flatMap { unitRoots[$0] }
            guard let resolvedItemID, itemIDs.contains(resolvedItemID) else {
                throw DurabilityError.invalidArchive("external reference \(reference.id) has no item")
            }
            if let unitID = reference.unitID, unitRoots[unitID] != resolvedItemID {
                throw DurabilityError.invalidArchive("external reference \(reference.id) crosses items")
            }
        }
        if let privatePayload {
            try ensureUnique(privatePayload.privateFeedSecrets.map(\.externalReferenceID), table: "private feeds")
            let privateReferenceIDs = Set(payload.externalReferences.lazy.filter(\.isPrivateFeed).map(\.id))
            for secret in privatePayload.privateFeedSecrets
                where !referenceIDs.contains(secret.externalReferenceID) ||
                    !privateReferenceIDs.contains(secret.externalReferenceID)
            {
                throw DurabilityError.invalidPrivateFeedReference(secret.externalReferenceID)
            }
        }
        try validateNumbers(payload)
    }

    func validateMergeCollisions(
        payload: ArchivePayload,
        unitRoots: [UUID: UUID]
    ) throws {
        let sessions = Dictionary(uniqueKeysWithValues: payload.sessions.map { ($0.id, $0) })
        for existing in try fetchAll(ConsumptionSession.self) {
            guard let archived = sessions[existing.id] else { continue }
            if archived.itemID != existing.rootItemID || archived.cycleID != existing.cycleID ||
                archived.unitID != existing.targetUnitID
            {
                throw DurabilityError.invalidArchive("session \(existing.id) conflicts with existing relationships")
            }
        }

        let events = Dictionary(uniqueKeysWithValues: payload.events.map { ($0.id, $0) })
        for existing in try fetchAll(ActivityEvent.self) {
            guard let archived = events[existing.id] else { continue }
            if archived.itemID != existing.rootItemID || archived.cycleID != existing.cycleID ||
                archived.unitID != existing.targetUnitID
            {
                throw DurabilityError.invalidArchive("event \(existing.id) conflicts with existing relationships")
            }
        }

        let quotes = Dictionary(uniqueKeysWithValues: payload.quotes.map { ($0.id, $0) })
        for existing in try fetchAll(NotableQuote.self) {
            guard let archived = quotes[existing.id] else { continue }
            if archived.itemID != existing.rootItemID || archived.unitID != existing.episodeUnitID {
                throw DurabilityError.invalidArchive("quote \(existing.id) conflicts with existing relationships")
            }
        }

        let values = Dictionary(uniqueKeysWithValues: payload.smartListRuleValues.map { ($0.id, $0) })
        for existing in try fetchAll(SmartRuleValue.self) where values[existing.id]?.ruleID != nil {
            if values[existing.id]?.ruleID != existing.ruleID {
                throw DurabilityError.invalidArchive("smart-rule value \(existing.id) conflicts with an existing rule")
            }
        }

        let listMemberships = Dictionary(uniqueKeysWithValues: payload.listMemberships.map { ($0.id, $0) })
        for existing in try fetchAll(ListMembership.self) {
            guard let archived = listMemberships[existing.id] else { continue }
            if archived.listID != existing.listID || archived.itemID != existing.itemID {
                throw DurabilityError.invalidArchive("list membership \(existing.id) conflicts with existing relationships")
            }
        }

        let tagMemberships = Dictionary(uniqueKeysWithValues: payload.tagMemberships.map { ($0.id, $0) })
        for existing in try fetchAll(ItemFacetMembership.self) {
            guard let archived = tagMemberships[existing.id] else { continue }
            if archived.tagID != existing.facetID || archived.itemID != existing.itemID {
                throw DurabilityError.invalidArchive("tag membership \(existing.id) conflicts with existing relationships")
            }
        }

        let artworks = Dictionary(uniqueKeysWithValues: payload.artworks.map { ($0.id, $0) })
        for existing in try fetchAll(ArtworkAsset.self) {
            guard let archived = artworks[existing.id] else { continue }
            if archived.itemID != existing.rootItemID || archived.unitID != existing.unitID {
                throw DurabilityError.invalidArchive("artwork \(existing.id) conflicts with existing relationships")
            }
        }

        let credits = Dictionary(uniqueKeysWithValues: payload.credits.map { ($0.id, $0) })
        for existing in try fetchAll(Credit.self) {
            guard let archived = credits[existing.id] else { continue }
            if archived.itemID != existing.rootItemID || archived.unitID != existing.unitID {
                throw DurabilityError.invalidArchive("credit \(existing.id) conflicts with existing relationships")
            }
        }

        let reminders = Dictionary(uniqueKeysWithValues: payload.reminders.map { ($0.id, $0) })
        for existing in try fetchAll(StartReminder.self) where reminders[existing.id] != nil {
            if reminders[existing.id]?.itemID != existing.itemID {
                throw DurabilityError.invalidArchive("reminder \(existing.id) conflicts with an existing item")
            }
        }

        let references = Dictionary(uniqueKeysWithValues: payload.externalReferences.map { ($0.id, $0) })
        for existing in try fetchAll(ExternalReference.self) {
            guard let archived = references[existing.id] else { continue }
            let archivedRoot = archived.itemID ?? archived.unitID.flatMap { unitRoots[$0] }
            if archivedRoot != existing.rootItemID || archived.unitID != existing.unitID {
                throw DurabilityError.invalidArchive("external reference \(existing.id) conflicts with existing relationships")
            }
        }
    }

    func ensureUnique(_ ids: [UUID], table: String) throws {
        guard Set(ids).count == ids.count else {
            throw DurabilityError.invalidArchive("\(table) contains duplicate stable IDs")
        }
    }

    func validateParentCycles(_ units: [ArchiveUnitRecord]) throws {
        let parents = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.parentUnitID) })
        for unit in units {
            var seen: Set<UUID> = []
            var current: UUID? = unit.id
            while let id = current {
                guard seen.insert(id).inserted else {
                    throw DurabilityError.invalidArchive("unit parent hierarchy contains a cycle")
                }
                current = parents[id] ?? nil
            }
        }
    }

    func validateNumbers(_ payload: ArchivePayload) throws {
        let ratings = payload.items.flatMap { [$0.projectedRating, $0.ratingOverride] } +
            payload.units.map(\.rating) + payload.cycles.map(\.rating) + payload.sessions.map(\.rating)
        for rating in ratings.compactMap({ $0 }) where !rating.isFinite || !(0.5 ... 5).contains(rating) {
            throw DurabilityError.invalidArchive("a rating is outside the 0.5–5 range")
        }
        let values = payload.units.map(\.durationMinutes) + payload.cycles.flatMap {
            [$0.elapsedMinutes, $0.playtimeMinutes]
        } + payload.sessions.flatMap {
            [$0.durationMinutes, $0.startElapsedMinutes, $0.endElapsedMinutes, $0.totalRuntimeMinutes,
             $0.playtimeDeltaMinutes, $0.cumulativePlaytimeMinutes]
        }
        for value in values.compactMap({ $0 }) where !value.isFinite || value < 0 {
            throw DurabilityError.invalidArchive("a duration or progress value is invalid")
        }
    }
}

@MainActor
private protocol BackupIdentified: AnyObject {
    var id: UUID { get }
}

extension LibraryItem: BackupIdentified {}
extension ContentUnit: BackupIdentified {}
extension ConsumptionCycle: BackupIdentified {}
extension ConsumptionSession: BackupIdentified {}
extension ActivityEvent: BackupIdentified {}
extension UserList: BackupIdentified {}
extension SmartRule: BackupIdentified {}
extension Facet: BackupIdentified {}
extension ExternalReference: BackupIdentified {}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
