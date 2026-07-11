import Foundation
import SwiftData

struct TrashPurgeResult: Sendable, Equatable {
    let itemCount: Int
    let listCount: Int
}

@MainActor
struct TrashPurgeService {
    let context: ModelContext
    let credentials: any CredentialStoring
    let reminders: any ReminderScheduling

    func purgeExpired(at date: Date = .now) async throws -> TrashPurgeResult {
        let items = try context.fetch(FetchDescriptor<LibraryItem>())
            .filter { $0.trashedAt != nil && ($0.purgeAfter ?? .distantFuture) <= date }
        let lists = try context.fetch(FetchDescriptor<UserList>())
            .filter { $0.trashedAt != nil && ($0.purgeAfter ?? .distantFuture) <= date }

        for item in items {
            try await permanentlyDelete(item)
        }
        for list in lists {
            permanentlyDelete(list)
        }
        try context.save()
        return TrashPurgeResult(itemCount: items.count, listCount: lists.count)
    }

    func permanentlyDelete(_ item: LibraryItem) async throws {
        for reminder in item.reminders ?? [] {
            await reminders.cancel(identifier: reminder.notificationIdentifier)
        }
        for reference in item.externalReferences ?? [] {
            if let key = reference.credentialKeychainID {
                try? await credentials.removeValue(for: key)
            }
        }
        for membership in item.listMemberships ?? [] {
            membership.list?.memberships = (membership.list?.memberships ?? [])
                .filter { $0.id != membership.id }
            context.delete(membership)
        }
        for membership in item.facetMemberships ?? [] {
            membership.facet?.memberships = (membership.facet?.memberships ?? [])
                .filter { $0.id != membership.id }
            context.delete(membership)
        }
        context.delete(item)
    }

    func permanentlyDelete(_ list: UserList) {
        for membership in list.memberships ?? [] {
            membership.item?.listMemberships = (membership.item?.listMemberships ?? [])
                .filter { $0.id != membership.id }
            context.delete(membership)
        }
        context.delete(list)
    }
}

