import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("Recently Deleted maintenance", .serialized)
@MainActor
struct TrashPurgeServiceTests {
    @Test("Expired records purge credentials, reminders, and canonical items")
    func purgesExpiredItem() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let credentials = InMemoryCredentialStore()
        let reminders = InMemoryReminderScheduler()
        let item = LibraryItem(mediaKind: .podcast, title: "Private Show")
        try ActivityService(context: context).register(item)

        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "feed",
            externalID: "private-feed"
        )
        reference.isPrivateFeed = true
        reference.credentialKeychainID = "feed-key"
        context.insert(reference)
        item.externalReferences = [reference]
        await credentials.set("https://private.example/feed", for: "feed-key")

        let reminder = StartReminder(
            item: item,
            fireAt: Date(timeIntervalSince1970: 1_000),
            notificationIdentifier: "start-private-show"
        )
        context.insert(reminder)
        item.reminders = [reminder]
        await reminders.schedule(
            ReminderRequest(
                identifier: reminder.notificationIdentifier,
                title: "Start",
                body: "Start",
                fireAt: reminder.fireAt,
                timeZoneIdentifier: "UTC"
            )
        )

        item.trashedAt = Date(timeIntervalSince1970: 2_000)
        item.purgeAfter = Date(timeIntervalSince1970: 3_000)
        try context.save()

        let service = TrashPurgeService(
            context: context,
            credentials: credentials,
            reminders: reminders
        )
        let result = try await service.purgeExpired(at: Date(timeIntervalSince1970: 4_000))

        #expect(result.itemCount == 1)
        #expect(try context.fetch(FetchDescriptor<LibraryItem>()).isEmpty)
        #expect(await credentials.value(for: "feed-key") == nil)
        #expect(await reminders.request(identifier: reminder.notificationIdentifier) == nil)
    }

    @Test("Records inside the recovery window remain intact")
    func retainsRecoverableItem() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .book, title: "Recoverable")
        try ActivityService(context: context).register(item)
        item.trashedAt = Date(timeIntervalSince1970: 2_000)
        item.purgeAfter = Date(timeIntervalSince1970: 5_000)
        try context.save()

        let result = try await TrashPurgeService(
            context: context,
            credentials: InMemoryCredentialStore(),
            reminders: InMemoryReminderScheduler()
        ).purgeExpired(at: Date(timeIntervalSince1970: 4_000))

        #expect(result.itemCount == 0)
        #expect(try context.fetch(FetchDescriptor<LibraryItem>()).count == 1)
    }
}

