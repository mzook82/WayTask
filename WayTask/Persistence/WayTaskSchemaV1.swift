import Foundation
import SwiftData

enum WayTaskSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            GeoLocation.self,
            ShoppingItem.self,
            WayTaskSchemaV1.Product.self,
            ShoppingList.self,
            WayTaskSchemaV1.ShoppingListEntry.self,
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
            searchKeywordsRawValue: String? = nil
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
        var product: WayTaskSchemaV1.Product?

        init(
            id: UUID = UUID(),
            shoppingListID: UUID,
            product: WayTaskSchemaV1.Product,
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
