import XCTest
import SwiftData
@testable import WayTask

final class LegacyProductCreationCharacterizationTests: XCTestCase {
    func testManualProductCreationPersistsTheExistingProductShape() throws {
        let modelContext = try makeModelContext()
        let service = ShoppingListService()
        let imageData = Data([0x01, 0x02, 0x03])

        let product = try service.addManualProduct(
            name: "Protein Vanilla Pudding",
            imageData: imageData,
            in: modelContext
        )

        let persistedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        XCTAssertEqual(persistedProducts.count, 1)
        XCTAssertEqual(persistedProducts.first?.id, product.id)
        XCTAssertEqual(product.name, "Protein Vanilla Pudding")
        XCTAssertEqual(product.imageData, imageData)
        XCTAssertEqual(product.source, .manual)
        XCTAssertNil(product.brand)
        XCTAssertNil(product.category)
        XCTAssertNil(product.barcode)
        XCTAssertNil(product.legacyShoppingItemID)
        XCTAssertNil(product.catalogProductIDRawValue)
        XCTAssertNil(product.catalogDisplayNameSnapshot)
        XCTAssertNil(product.catalogDisplayLocaleSnapshot)
        XCTAssertNil(product.catalogCategoryIDSnapshotRawValue)
        XCTAssertNil(product.catalogCategoryDisplayNameSnapshot)
        XCTAssertNil(product.catalogIconKeySnapshot)
        XCTAssertNil(product.catalogSnapshotUpdatedAt)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<ShoppingListEntry>()).isEmpty)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<ShoppingItem>()).isEmpty)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<ProductKnowledge>()).isEmpty)
    }

    func testDuplicateManualProductNamesRemainIndependentProducts() throws {
        let modelContext = try makeModelContext()
        let service = ShoppingListService()

        let first = try service.addManualProduct(
            name: "Protein Vanilla Pudding",
            imageData: nil,
            in: modelContext
        )
        let second = try service.addManualProduct(
            name: "Protein Vanilla Pudding",
            imageData: nil,
            in: modelContext
        )
        let products = try modelContext.fetch(FetchDescriptor<Product>())

        XCTAssertEqual(products.count, 2)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(
            products.filter { $0.name == "Protein Vanilla Pudding" }.count,
            2
        )
        XCTAssertTrue(products.allSatisfy { $0.catalogProductIDRawValue == nil })
    }

    func testManualProductServicePreservesCallerSuppliedWhitespace() throws {
        let modelContext = try makeModelContext()
        let service = ShoppingListService()
        let callerSuppliedName = "  Custom Need  "

        let product = try service.addManualProduct(
            name: callerSuppliedName,
            imageData: nil,
            in: modelContext
        )

        XCTAssertEqual(product.name, callerSuppliedName)
    }

    func testManualProductCanStillEnterTheExistingShoppingFlow() throws {
        let modelContext = try makeModelContext()
        let service = ShoppingListService()
        let list = ShoppingList(title: "Weekly", kind: .weekly, isDefault: true)
        modelContext.insert(list)
        try modelContext.save()

        let product = try service.addManualProduct(
            name: "Uncatalogued custom need",
            imageData: nil,
            in: modelContext
        )
        let entry = try service.addProductToShopping(
            product,
            shoppingListID: list.id,
            in: modelContext
        )

        XCTAssertEqual(entry.productID, product.id)
        XCTAssertEqual(entry.shoppingListID, list.id)
        XCTAssertEqual(entry.product?.id, product.id)
        XCTAssertNotNil(entry.legacyShoppingItemID)
        XCTAssertEqual(product.legacyShoppingItemID, entry.legacyShoppingItemID)
        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<ShoppingListEntry>()).count, 1)
        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<ShoppingItem>()).count, 1)
    }

    func testOnlyProductCarriesTheSevenCatalogPersistenceFields() throws {
        let schema = makeSchema()
        let catalogPropertyNames: Set<String> = [
            "catalogProductIDRawValue",
            "catalogDisplayNameSnapshot",
            "catalogDisplayLocaleSnapshot",
            "catalogCategoryIDSnapshotRawValue",
            "catalogCategoryDisplayNameSnapshot",
            "catalogIconKeySnapshot",
            "catalogSnapshotUpdatedAt"
        ]
        let productEntity = try XCTUnwrap(schema.entity(for: Product.self))
        let compatibilityEntities = [
            try XCTUnwrap(schema.entity(for: ShoppingItem.self)),
            try XCTUnwrap(schema.entity(for: ShoppingListEntry.self))
        ]

        XCTAssertTrue(
            catalogPropertyNames.isSubset(
                of: Set(productEntity.properties.map(\.name))
            )
        )
        for entity in compatibilityEntities {
            let propertyNames = Set(entity.properties.map(\.name))
            XCTAssertTrue(
                propertyNames.isDisjoint(with: catalogPropertyNames),
                "\(entity.name) unexpectedly contains catalog persistence fields"
            )
        }
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeSchema() -> Schema {
        WayTaskModelContainer.currentSchema
    }
}
