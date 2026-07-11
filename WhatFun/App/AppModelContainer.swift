import SwiftData

enum AppModelContainer {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WhatFunSchemaV1.self)
        let configuration = ModelConfiguration(
            "WhatFun",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WhatFunMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

