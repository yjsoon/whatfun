import SwiftData

enum WhatFunSchemaV1: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        [
            LibraryItem.self,
            ContentUnit.self,
            ConsumptionCycle.self,
            ConsumptionSession.self,
            ActivityEvent.self,
            NotableQuote.self,
            ArtworkAsset.self,
            ExternalReference.self,
            Credit.self,
            Facet.self,
            ItemFacetMembership.self,
            UserList.self,
            ListMembership.self,
            SmartRule.self,
            SmartRuleValue.self,
            StartReminder.self
        ]
    }
}

enum WhatFunMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [WhatFunSchemaV1.self]
    }

    nonisolated static var stages: [MigrationStage] {
        []
    }
}

