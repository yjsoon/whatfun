import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("SwiftData durability bridge", .serialized)
@MainActor
struct SwiftDataArchiveBridgeTests {
    private let timestamp = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("A semantic graph restores stable IDs, history, and encrypted private feeds")
    func semanticRoundTrip() async throws {
        let sourceContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sourceCredentials = InMemoryCredentialStore()
        let fixture = try await makeSourceGraph(
            in: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let sourceBridge = SwiftDataArchiveBridge(
            context: sourceContainer.mainContext,
            credentials: sourceCredentials
        )

        let snapshot = try await sourceBridge.snapshot()
        #expect(snapshot.payload.items.map(\.id) == [fixture.itemID])
        #expect(snapshot.payload.cycles.first?.kind == .installmentContinuation)
        #expect(snapshot.payload.externalReferences.first?.canonicalURL == nil)
        #expect(snapshot.payload.externalReferences.first?.credentialKeychainID == nil)
        #expect(snapshot.payload.externalReferences.first?.externalID.hasPrefix("private.") == true)
        #expect(snapshot.privatePayload?.privateFeedSecrets.first?.feedURL == fixture.privateFeedURL)

        let plainPayloadData = try JSONEncoder().encode(snapshot.payload)
        #expect(!String(decoding: plainPayloadData, as: UTF8.self).contains(fixture.privateFeedURL))
        #expect(!String(decoding: plainPayloadData, as: UTF8.self).contains(fixture.sourceCredentialKey))

        let destinationContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let destinationCredentials = InMemoryCredentialStore()
        let destinationBridge = SwiftDataArchiveBridge(
            context: destinationContainer.mainContext,
            credentials: destinationCredentials
        )
        let report = try await destinationBridge.restore(
            payload: snapshot.payload,
            privatePayload: snapshot.privatePayload,
            mode: .replaceAll
        )

        #expect(report.restoredPrivateFeeds == 1)
        let context = destinationContainer.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let unit = try #require(try context.fetch(FetchDescriptor<ContentUnit>()).first { $0.id == fixture.unitID })
        let cycle = try #require(try context.fetch(FetchDescriptor<ConsumptionCycle>()).first)
        let session = try #require(try context.fetch(FetchDescriptor<ConsumptionSession>()).first)
        let event = try #require(try context.fetch(FetchDescriptor<ActivityEvent>()).first)
        let quote = try #require(try context.fetch(FetchDescriptor<NotableQuote>()).first)
        let reference = try #require(try context.fetch(FetchDescriptor<ExternalReference>()).first)

        #expect(item.id == fixture.itemID)
        #expect(unit.id == fixture.unitID)
        #expect(cycle.id == fixture.cycleID)
        #expect(session.id == fixture.sessionID)
        #expect(event.id == fixture.eventID)
        #expect(quote.id == fixture.quoteID)
        #expect(cycle.cycleKind == .installmentContinuation)
        #expect(cycle.rootItemID == item.id)
        #expect(cycle.targetUnitID == unit.id)
        #expect(session.cycleID == cycle.id)
        #expect(item.status == .completed)
        #expect(item.sessionCount == 1)
        #expect(item.releaseYear == 2024)
        #expect(item.userEditedFieldMask == 17)
        #expect(item.metadataLastRefreshedAt == timestamp)
        #expect(unit.numberValue == 2)
        #expect(unit.numberLabel == "2")
        #expect(session.source == .manual)
        #expect(quote.sortOrder == 7)
        #expect(quote.updatedAt == timestamp.addingTimeInterval(10))

        let restoredCredentialKey = try #require(reference.credentialKeychainID)
        #expect(restoredCredentialKey != fixture.sourceCredentialKey)
        #expect(await destinationCredentials.value(for: restoredCredentialKey) == fixture.privateFeedURL)

        let beforeMergeKey = reference.credentialKeychainID
        let mergeReport = try await destinationBridge.restore(
            payload: snapshot.payload,
            privatePayload: snapshot.privatePayload,
            mode: .mergeNew
        )
        #expect(mergeReport.insertedRecords == 0)
        #expect(try context.fetch(FetchDescriptor<LibraryItem>()).count == 1)
        #expect(reference.credentialKeychainID == beforeMergeKey)
    }

    @Test("Restore preserves archived updatedAt on items, cycles, and units")
    func restorePreservesUpdatedAt() async throws {
        let sourceContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sourceCredentials = InMemoryCredentialStore()
        let fixture = try await makeSourceGraph(
            in: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let sourceBridge = SwiftDataArchiveBridge(
            context: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let snapshot = try await sourceBridge.snapshot()

        let archivedItem = try #require(snapshot.payload.items.first { $0.id == fixture.itemID })
        let archivedUnit = try #require(snapshot.payload.units.first { $0.id == fixture.unitID })
        let archivedEpisode = try #require(snapshot.payload.units.first { $0.id == fixture.episodeUnitID })
        let archivedCycle = try #require(snapshot.payload.cycles.first { $0.id == fixture.cycleID })
        #expect(archivedItem.updatedAt == timestamp.addingTimeInterval(1))
        #expect(archivedCycle.updatedAt == timestamp.addingTimeInterval(2))
        #expect(archivedUnit.updatedAt == timestamp.addingTimeInterval(3))
        #expect(archivedEpisode.updatedAt == timestamp.addingTimeInterval(4))

        let destinationContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let destinationBridge = SwiftDataArchiveBridge(
            context: destinationContainer.mainContext,
            credentials: InMemoryCredentialStore()
        )
        _ = try await destinationBridge.restore(
            payload: snapshot.payload,
            privatePayload: snapshot.privatePayload,
            mode: .replaceAll
        )

        let context = destinationContainer.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let units = try context.fetch(FetchDescriptor<ContentUnit>())
        let unit = try #require(units.first { $0.id == fixture.unitID })
        let episode = try #require(units.first { $0.id == fixture.episodeUnitID })
        let cycle = try #require(try context.fetch(FetchDescriptor<ConsumptionCycle>()).first)

        #expect(item.updatedAt == archivedItem.updatedAt)
        #expect(unit.updatedAt == archivedUnit.updatedAt)
        #expect(episode.updatedAt == archivedEpisode.updatedAt)
        #expect(episode.parentUnitID == fixture.unitID)
        #expect(cycle.updatedAt == archivedCycle.updatedAt)

        // Snapshot -> restore -> snapshot must reproduce the same timestamps end to end.
        let roundTrip = try await destinationBridge.snapshot()
        #expect(roundTrip.payload.items.first { $0.id == fixture.itemID }?.updatedAt == archivedItem.updatedAt)
        #expect(roundTrip.payload.units.first { $0.id == fixture.unitID }?.updatedAt == archivedUnit.updatedAt)
        #expect(roundTrip.payload.units.first { $0.id == fixture.episodeUnitID }?.updatedAt == archivedEpisode.updatedAt)
        #expect(roundTrip.payload.cycles.first { $0.id == fixture.cycleID }?.updatedAt == archivedCycle.updatedAt)
    }

    @Test("Merging an already-present archive leaves existing updatedAt untouched")
    func mergePreservesExistingUpdatedAt() async throws {
        let sourceContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sourceCredentials = InMemoryCredentialStore()
        _ = try await makeSourceGraph(
            in: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let sourceBridge = SwiftDataArchiveBridge(
            context: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let snapshot = try await sourceBridge.snapshot()

        let destinationContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let destinationBridge = SwiftDataArchiveBridge(
            context: destinationContainer.mainContext,
            credentials: InMemoryCredentialStore()
        )
        _ = try await destinationBridge.restore(
            payload: snapshot.payload,
            privatePayload: snapshot.privatePayload,
            mode: .replaceAll
        )

        let context = destinationContainer.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let unit = try #require(try context.fetch(FetchDescriptor<ContentUnit>()).first)
        let cycle = try #require(try context.fetch(FetchDescriptor<ConsumptionCycle>()).first)
        let itemUpdatedAt = item.updatedAt
        let unitUpdatedAt = unit.updatedAt
        let cycleUpdatedAt = cycle.updatedAt

        let report = try await destinationBridge.restore(
            payload: snapshot.payload,
            privatePayload: snapshot.privatePayload,
            mode: .mergeNew
        )

        #expect(report.insertedRecords == 0)
        #expect(item.updatedAt == itemUpdatedAt)
        #expect(unit.updatedAt == unitUpdatedAt)
        #expect(cycle.updatedAt == cycleUpdatedAt)
    }

    @Test("Merging new history onto an existing item re-derives projections without touching updatedAt")
    func mergeAttachesNewHistoryToExistingItem() async throws {
        let sourceContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sourceCredentials = InMemoryCredentialStore()
        let fixture = try await makeSourceGraph(
            in: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let sourceBridge = SwiftDataArchiveBridge(
            context: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let firstSnapshot = try await sourceBridge.snapshot()

        let destinationContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let destinationBridge = SwiftDataArchiveBridge(
            context: destinationContainer.mainContext,
            credentials: InMemoryCredentialStore()
        )
        _ = try await destinationBridge.restore(
            payload: firstSnapshot.payload,
            privatePayload: firstSnapshot.privatePayload,
            mode: .replaceAll
        )

        // Continue the source item's history with a repeat cycle and a session.
        let sourceContext = sourceContainer.mainContext
        let sourceItem = try #require(
            try sourceContext.fetch(FetchDescriptor<LibraryItem>()).first { $0.id == fixture.itemID }
        )
        let repeatCycle = ConsumptionCycle(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            item: sourceItem,
            kind: .repeatConsumption,
            ordinal: 2,
            repeatOfCycleID: fixture.cycleID,
            createdAt: timestamp.addingTimeInterval(7_200)
        )
        sourceContext.insert(repeatCycle)
        sourceItem.cycles = (sourceItem.cycles ?? []) + [repeatCycle]
        let startEvent = ActivityEvent(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            item: sourceItem,
            cycle: repeatCycle,
            scope: .item,
            kind: .started,
            fromStatus: .completed,
            toStatus: .inProgress,
            effectiveAt: timestamp.addingTimeInterval(7_200),
            timeZoneIdentifier: "Asia/Singapore",
            source: .manual
        )
        startEvent.recordedAt = timestamp.addingTimeInterval(7_200)
        sourceContext.insert(startEvent)
        sourceItem.activityEvents = (sourceItem.activityEvents ?? []) + [startEvent]
        repeatCycle.activityEvents = [startEvent]
        let laterSession = ConsumptionSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            cycle: repeatCycle,
            occurredAt: timestamp.addingTimeInterval(7_500),
            timeZoneIdentifier: "Asia/Singapore",
            source: .manual
        )
        laterSession.createdAt = timestamp.addingTimeInterval(7_500)
        laterSession.updatedAt = timestamp.addingTimeInterval(7_500)
        sourceContext.insert(laterSession)
        repeatCycle.sessions = [laterSession]
        ActivityProjection.rebuild(sourceItem, now: timestamp.addingTimeInterval(8_000))
        sourceItem.updatedAt = timestamp.addingTimeInterval(100)
        try sourceContext.save()
        let secondSnapshot = try await sourceBridge.snapshot()

        let report = try await destinationBridge.restore(
            payload: secondSnapshot.payload,
            privatePayload: secondSnapshot.privatePayload,
            mode: .mergeNew
        )

        let context = destinationContainer.mainContext
        let merged = try #require(
            try context.fetch(FetchDescriptor<LibraryItem>()).first { $0.id == fixture.itemID }
        )
        #expect(report.insertedRecords == 3)
        // The archived item record carries a newer updatedAt, yet merge never
        // rewrites the existing record: recency stays as the user left it.
        #expect(merged.updatedAt == timestamp.addingTimeInterval(1))
        #expect(merged.sessionCount == 2)
        #expect(merged.cycleCount == 2)
        #expect(merged.repeatCount == 1)
        #expect(merged.status == .inProgress)
        #expect(merged.lastSessionAt == timestamp.addingTimeInterval(7_500))
    }

    @Test("Full JSON authenticates private data before replace-all mutates SwiftData")
    func fullBackupCoordinator() async throws {
        let sourceContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sourceCredentials = InMemoryCredentialStore()
        _ = try await makeSourceGraph(
            in: sourceContainer.mainContext,
            credentials: sourceCredentials
        )
        let sourceCoordinator = DurabilityCoordinator(
            bridge: SwiftDataArchiveBridge(
                context: sourceContainer.mainContext,
                credentials: sourceCredentials
            ),
            generator: "WhatFunTests"
        )
        let key = SymmetricKey(data: Data(repeating: 0x4D, count: 32))
        let salt = Data(repeating: 0x2A, count: 16)
        let backup = try await sourceCoordinator.makeFullBackup(
            exportedAt: timestamp,
            encryptionKey: key,
            encryptionSalt: salt,
            keyDerivationIterations: 210_000
        )
        #expect(!String(decoding: backup, as: UTF8.self).contains("token=private"))
        let decodedManualBackup = try FullFidelityArchiveCodec.decode(backup)
        #expect(decodedManualBackup.encryptedPrivateData?.salt == salt)
        #expect(decodedManualBackup.encryptedPrivateData?.keyDerivationIterations == 210_000)

        let dailyDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WhatFunDailyPrivateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dailyDirectory) }
        let dailyStore = try DailyBackupStore(directory: dailyDirectory)
        let dailyCoordinator = DurabilityCoordinator(
            bridge: SwiftDataArchiveBridge(
                context: sourceContainer.mainContext,
                credentials: sourceCredentials
            ),
            dailyStore: dailyStore,
            generator: "WhatFunTests"
        )
        let dailyURL = try await dailyCoordinator.writeDailyBackup(for: timestamp)
        let dailyData = try Data(contentsOf: dailyURL)
        let dailyEnvelope = try FullFidelityArchiveCodec.decode(dailyData)
        #expect(dailyEnvelope.encryptedPrivateData == nil)
        #expect(!String(decoding: dailyData, as: UTF8.self).contains("token=private"))
        #expect(try await dailyCoordinator.dailyBackupURLs() == [dailyURL])
        _ = try await dailyCoordinator.restoreLatestDailyBackup(mode: .replaceAll)
        let dailyRestoredReference = try #require(
            try sourceContainer.mainContext.fetch(FetchDescriptor<ExternalReference>()).first
        )
        let dailyRestoredKey = try #require(dailyRestoredReference.credentialKeychainID)
        #expect(await sourceCredentials.value(for: dailyRestoredKey) ==
            "https://private.example/feed?token=private")

        let destinationContainer = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let sentinel = LibraryItem(mediaKind: .book, title: "Keep if validation fails")
        destinationContainer.mainContext.insert(sentinel)
        try destinationContainer.mainContext.save()
        let coordinator = DurabilityCoordinator(
            bridge: SwiftDataArchiveBridge(
                context: destinationContainer.mainContext,
                credentials: InMemoryCredentialStore()
            )
        )

        let wrongKey = SymmetricKey(data: Data(repeating: 0x7E, count: 32))
        do {
            _ = try await coordinator.restoreFullBackup(
                backup,
                encryptionKey: wrongKey,
                mode: .replaceAll
            )
            Issue.record("Expected private payload authentication to fail")
        } catch {
            // Authentication fails before SwiftDataArchiveBridge.restore is called.
        }
        let itemsAfterFailure = try destinationContainer.mainContext.fetch(FetchDescriptor<LibraryItem>())
        #expect(itemsAfterFailure.map(\.id).contains(sentinel.id))

        _ = try await coordinator.restoreFullBackup(
            backup,
            encryptionKey: key,
            mode: .replaceAll
        )
        let restoredItems = try destinationContainer.mainContext.fetch(FetchDescriptor<LibraryItem>())
        #expect(restoredItems.count == 1)
        #expect(restoredItems.first?.title == "A City in Episodes")
    }

    private func makeSourceGraph(
        in context: ModelContext,
        credentials: InMemoryCredentialStore
    ) async throws -> FixtureIDs {
        let ids = FixtureIDs()
        let item = LibraryItem(
            id: ids.itemID,
            mediaKind: .tvShow,
            title: "A City in Episodes",
            createdAt: timestamp
        )
        item.comment = "Preserve the full history."
        item.isFavorite = true
        item.releaseYear = 2024
        item.userEditedFieldMask = 17
        item.metadataLastRefreshedAt = timestamp
        context.insert(item)

        let unit = ContentUnit(
            id: ids.unitID,
            item: item,
            kind: .tvSeason,
            title: "Season 2",
            sortOrder: 2,
            createdAt: timestamp
        )
        unit.seasonNumber = 2
        unit.numberValue = 2
        unit.numberLabel = "2"
        unit.releaseDate = timestamp
        unit.ratingHalfSteps = 9
        context.insert(unit)

        let episode = ContentUnit(
            id: ids.episodeUnitID,
            item: item,
            kind: .tvEpisode,
            title: "Episode 1",
            sortOrder: 1,
            parent: unit,
            createdAt: timestamp
        )
        episode.episodeNumber = 1
        episode.releaseDate = timestamp
        context.insert(episode)
        unit.children = [episode]
        item.units = [unit, episode]

        let cycle = ConsumptionCycle(
            id: ids.cycleID,
            item: item,
            targetUnit: unit,
            kind: .installmentContinuation,
            ordinal: 1,
            createdAt: timestamp
        )
        context.insert(cycle)
        item.cycles = [cycle]
        unit.cycles = [cycle]

        let session = ConsumptionSession(
            id: ids.sessionID,
            cycle: cycle,
            targetUnit: unit,
            occurredAt: timestamp,
            timeZoneIdentifier: "Asia/Singapore",
            durationSeconds: 2_700,
            note: "One evening",
            source: .manual
        )
        session.endedAt = timestamp.addingTimeInterval(2_700)
        session.elapsedSeconds = 2_700
        session.mediaDurationSecondsSnapshot = 2_700
        session.completionPercent = 100
        session.createdAt = timestamp
        session.updatedAt = timestamp
        context.insert(session)
        cycle.sessions = [session]
        unit.sessions = [session]

        let event = ActivityEvent(
            id: ids.eventID,
            item: item,
            cycle: cycle,
            targetUnit: unit,
            scope: .unit,
            kind: .completed,
            fromStatus: .inProgress,
            toStatus: .completed,
            effectiveAt: timestamp.addingTimeInterval(2_700),
            timeZoneIdentifier: "Asia/Singapore",
            source: .manual
        )
        event.recordedAt = timestamp.addingTimeInterval(2_700)
        context.insert(event)
        item.activityEvents = [event]
        cycle.activityEvents = [event]
        unit.activityEvents = [event]

        let quote = NotableQuote(
            id: ids.quoteID,
            episode: unit,
            text: "Every record is a memory.",
            timestampSeconds: 1_234,
            sortOrder: 7,
            sessionID: session.id,
            createdAt: timestamp
        )
        quote.updatedAt = timestamp.addingTimeInterval(10)
        context.insert(quote)
        unit.notableQuotes = [quote]

        let tag = Facet(id: ids.tagID, kind: .tag, name: "Comfort", createdAt: timestamp)
        let membership = ItemFacetMembership(
            id: ids.tagMembershipID,
            item: item,
            facet: tag,
            createdAt: timestamp
        )
        context.insert(tag)
        context.insert(membership)
        tag.memberships = [membership]
        item.facetMemberships = [membership]

        let list = UserList(id: ids.listID, name: "Keep Around", createdAt: timestamp)
        let listMembership = ListMembership(
            id: ids.listMembershipID,
            list: list,
            item: item,
            positionRank: "0001",
            addedAt: timestamp
        )
        context.insert(list)
        context.insert(listMembership)
        list.memberships = [listMembership]
        item.listMemberships = [listMembership]

        let reference = ExternalReference(
            id: ids.referenceID,
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "feed",
            externalID: "private-source-id",
            createdAt: timestamp
        )
        reference.isActiveFeed = true
        reference.isPrivateFeed = true
        reference.credentialKeychainID = ids.sourceCredentialKey
        context.insert(reference)
        item.externalReferences = [reference]
        await credentials.set(ids.privateFeedURL, for: ids.sourceCredentialKey)

        ActivityProjection.rebuild(item, now: timestamp.addingTimeInterval(3_600))
        // Distinct stale timestamps: a restore that rewrote or cross-copied any
        // updatedAt would break the round-trip assertions unambiguously.
        item.updatedAt = timestamp.addingTimeInterval(1)
        cycle.updatedAt = timestamp.addingTimeInterval(2)
        unit.updatedAt = timestamp.addingTimeInterval(3)
        episode.updatedAt = timestamp.addingTimeInterval(4)
        try context.save()
        return ids
    }
}

private nonisolated struct FixtureIDs: Sendable {
    let itemID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let unitID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let cycleID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    let sessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
    let eventID = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!
    let quoteID = UUID(uuidString: "20000000-0000-0000-0000-000000000006")!
    let tagID = UUID(uuidString: "20000000-0000-0000-0000-000000000007")!
    let tagMembershipID = UUID(uuidString: "20000000-0000-0000-0000-000000000008")!
    let listID = UUID(uuidString: "20000000-0000-0000-0000-000000000009")!
    let listMembershipID = UUID(uuidString: "20000000-0000-0000-0000-00000000000A")!
    let referenceID = UUID(uuidString: "20000000-0000-0000-0000-00000000000B")!
    let episodeUnitID = UUID(uuidString: "20000000-0000-0000-0000-00000000000C")!
    let sourceCredentialKey = "source-private-feed-key"
    let privateFeedURL = "https://private.example/feed?token=private"
}
