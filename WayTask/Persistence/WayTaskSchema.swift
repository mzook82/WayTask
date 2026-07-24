import SwiftData

enum WayTaskSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            GeoLocation.self,
            ShoppingItem.self,
            Product.self,
            ShoppingList.self,
            ShoppingListEntry.self,
            ProductHistory.self,
            ProductKnowledge.self,
            ShoppingSession.self
        ]
    }
}

enum WayTaskSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            WayTaskSchemaV1.self,
            WayTaskSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WayTaskSchemaV1.self,
                toVersion: WayTaskSchemaV2.self
            )
        ]
    }
}

enum WayTaskModelContainer {
    static var currentSchema: Schema {
        Schema(versionedSchema: WayTaskSchemaV2.self)
    }

    static func makeDefault() throws -> ModelContainer {
        try make(configurations: [])
    }

    static func make(configurations: [ModelConfiguration]) throws -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            migrationPlan: WayTaskSchemaMigrationPlan.self,
            configurations: configurations
        )
    }
}
