import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("WhatFun schema", .serialized)
@MainActor
struct SchemaTests {
    @Test("Version one creates a complete in-memory store")
    func createsContainer() throws {
        let container = try makeContainer()
        #expect(container.schema.entities.count == WhatFunSchemaV1.models.count)
    }

    @Test("Podcast episodes retain notable quotes")
    func podcastQuoteRelationship() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = LibraryItem(mediaKind: .podcast, title: "Search Engine")
        let episode = ContentUnit(
            item: show,
            kind: .podcastEpisode,
            title: "An episode worth keeping"
        )
        episode.isNotable = true
        let quote = NotableQuote(
            episode: episode,
            text: "A useful thought",
            timestampSeconds: 742,
            comment: "Come back to this"
        )

        context.insert(show)
        context.insert(episode)
        context.insert(quote)
        try context.save()

        let quotes = try context.fetch(FetchDescriptor<NotableQuote>())
        #expect(quotes.count == 1)
        #expect(quotes.first?.episode?.id == episode.id)
        #expect(quotes.first?.timestampSeconds == 742)
    }

    @Test("Manual list order and item identity are explicit")
    func listMembership() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .comic, title: "Saga")
        let list = UserList(name: "Read next")
        let membership = ListMembership(
            list: list,
            item: item,
            positionRank: "000001"
        )
        context.insert(item)
        context.insert(list)
        context.insert(membership)
        try context.save()

        let memberships = try context.fetch(FetchDescriptor<ListMembership>())
        #expect(memberships.first?.itemID == item.id)
        #expect(memberships.first?.listID == list.id)
        #expect(memberships.first?.positionRank == "000001")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: WhatFunSchemaV1.self)
        let configuration = ModelConfiguration(
            "WhatFunSchemaTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WhatFunMigrationPlan.self,
            configurations: configuration
        )
    }
}

