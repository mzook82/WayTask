import Foundation
import SwiftData

// Keep the shipped V2 model graph frozen so existing V2 stores can be
// identified and migrated after Product gains durable deletion state.
enum WayTaskSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            GeoLocation.self,
            ShoppingItem.self,
            WayTaskSchemaV2.Product.self,
            ShoppingList.self,
            WayTaskSchemaV2.ShoppingListEntry.self,
            ProductHistory.self,
            ProductKnowledge.self,
            ShoppingSession.self
        ]
    }

    @Model
    final class Product {
        var id: UUID
        var legacyShoppingItemID: UUID?
        var name: String
        var imageData: Data?
        var brand: String?
        var category: String?
        var barcode: String?
        var imageURLString: String?
        var dateAdded: Date
        var updatedAt: Date
        var sourceRawValue: String
        var productType: String?
        var flavor: String?
        var packageSize: String?
        var packageType: String?
        var visibleText: String?
        var searchKeywordsRawValue: String?
        var catalogProductIDRawValue: String?
        var catalogDisplayNameSnapshot: String?
        var catalogDisplayLocaleSnapshot: String?
        var catalogCategoryIDSnapshotRawValue: String?
        var catalogCategoryDisplayNameSnapshot: String?
        var catalogIconKeySnapshot: String?
        var catalogSnapshotUpdatedAt: Date?

        init(
            id: UUID = UUID(),
            legacyShoppingItemID: UUID? = nil,
            name: String,
            imageData: Data? = nil,
            brand: String? = nil,
            category: String? = nil,
            barcode: String? = nil,
            imageURLString: String? = nil,
            dateAdded: Date = Date(),
            updatedAt: Date = Date(),
            sourceRawValue: String = ProductSource.manual.rawValue,
            productType: String? = nil,
            flavor: String? = nil,
            packageSize: String? = nil,
            packageType: String? = nil,
            visibleText: String? = nil,
            searchKeywordsRawValue: String? = nil,
            catalogProductIDRawValue: String? = nil,
            catalogDisplayNameSnapshot: String? = nil,
            catalogDisplayLocaleSnapshot: String? = nil,
            catalogCategoryIDSnapshotRawValue: String? = nil,
            catalogCategoryDisplayNameSnapshot: String? = nil,
            catalogIconKeySnapshot: String? = nil,
            catalogSnapshotUpdatedAt: Date? = nil
        ) {
            self.id = id
            self.legacyShoppingItemID = legacyShoppingItemID
            self.name = name
            self.imageData = imageData
            self.brand = brand
            self.category = category
            self.barcode = barcode
            self.imageURLString = imageURLString
            self.dateAdded = dateAdded
            self.updatedAt = updatedAt
            self.sourceRawValue = sourceRawValue
            self.productType = productType
            self.flavor = flavor
            self.packageSize = packageSize
            self.packageType = packageType
            self.visibleText = visibleText
            self.searchKeywordsRawValue = searchKeywordsRawValue
            self.catalogProductIDRawValue = catalogProductIDRawValue
            self.catalogDisplayNameSnapshot = catalogDisplayNameSnapshot
            self.catalogDisplayLocaleSnapshot =
                catalogDisplayLocaleSnapshot
            self.catalogCategoryIDSnapshotRawValue =
                catalogCategoryIDSnapshotRawValue
            self.catalogCategoryDisplayNameSnapshot =
                catalogCategoryDisplayNameSnapshot
            self.catalogIconKeySnapshot = catalogIconKeySnapshot
            self.catalogSnapshotUpdatedAt = catalogSnapshotUpdatedAt
        }
    }

    @Model
    final class ShoppingListEntry {
        var id: UUID
        var shoppingListID: UUID
        var productID: UUID
        var legacyShoppingItemID: UUID?
        var quantity: Double
        var isChecked: Bool
        var createdAt: Date
        var sortOrder: Double

        @Relationship(deleteRule: .nullify)
        var product: WayTaskSchemaV2.Product?

        init(
            id: UUID = UUID(),
            shoppingListID: UUID,
            product: WayTaskSchemaV2.Product,
            legacyShoppingItemID: UUID? = nil,
            quantity: Double = 1,
            isChecked: Bool = false,
            createdAt: Date = Date(),
            sortOrder: Double = 0
        ) {
            self.id = id
            self.shoppingListID = shoppingListID
            self.productID = product.id
            self.legacyShoppingItemID = legacyShoppingItemID
            self.quantity = quantity
            self.isChecked = isChecked
            self.createdAt = createdAt
            self.sortOrder = sortOrder
            self.product = product
        }
    }
}

enum WayTaskSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
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

// T-02 registers the approved target graph without activating it. The live
// container and migration plan remain on V3 until later authorized steps.
enum WayTaskSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            GeoLocation.self,
            ShoppingItem.self,
            WayTaskSchemaV4.Product.self,
            WayTaskSchemaV4.ShoppingList.self,
            WayTaskSchemaV4.ShoppingListEntry.self,
            ProductHistory.self,
            WayTaskSchemaV4.ProductHistoryEvent.self,
            ProductKnowledge.self,
            WayTaskSchemaV4.ShoppingSession.self,
            WayTaskSchemaV4.ShoppingSessionLine.self,
            WayTaskSchemaV4.ShoppingSessionStop.self,
            WayTaskSchemaV4.ProductStateMigrationException.self
        ]
    }
}

enum WayTaskSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            WayTaskSchemaV1.self,
            WayTaskSchemaV2.self,
            WayTaskSchemaV3.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WayTaskSchemaV1.self,
                toVersion: WayTaskSchemaV2.self
            ),
            .lightweight(
                fromVersion: WayTaskSchemaV2.self,
                toVersion: WayTaskSchemaV3.self
            )
        ]
    }
}

// T-06 uses a separate, inactive plan for task-owned candidate copies. It
// deliberately stops at the shipped V3 representation: T-07 and T-08 own the
// semantic conversion into V4, and T-09 owns production startup activation.
enum WayTaskProtectedCandidatePhysicalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            WayTaskSchemaV1.self,
            WayTaskSchemaV2.self,
            WayTaskSchemaV3.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WayTaskSchemaV1.self,
                toVersion: WayTaskSchemaV2.self
            ),
            .lightweight(
                fromVersion: WayTaskSchemaV2.self,
                toVersion: WayTaskSchemaV3.self
            )
        ]
    }
}

enum WayTaskModelContainer {
    static var currentSchema: Schema {
        Schema(versionedSchema: WayTaskSchemaV3.self)
    }

    static var inactiveTargetProductStateSchema: Schema {
        Schema(versionedSchema: WayTaskSchemaV4.self)
    }

    static var defaultStoreURL: URL {
        ModelConfiguration().url
    }

    static func makeDefault() throws -> ModelContainer {
        try make(configurations: [])
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: true
        )
        return try make(configurations: [configuration])
    }

    static func make(configurations: [ModelConfiguration]) throws
        -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            migrationPlan: WayTaskSchemaMigrationPlan.self,
            configurations: configurations
        )
    }
}
