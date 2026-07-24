import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class CatalogProductCompatibilityTests: XCTestCase {
    private let snapshotDate = Date(timeIntervalSince1970: 1_810_000_000)

    func testCatalogProductUsesUserUUIDForShoppingAndDoesNotCreateLegacyKnowledge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        context.insert(list)
        try context.save()
        let product = try saveCatalogProduct(in: context)

        let entry = try ShoppingListService().addProductToShopping(
            product,
            shoppingListID: list.id,
            in: context
        )

        XCTAssertEqual(entry.productID, product.id)
        XCTAssertEqual(entry.product?.id, product.id)
        XCTAssertEqual(entry.shoppingListID, list.id)
        XCTAssertNotEqual(entry.productID.uuidString, product.catalogProductIDRawValue)
        XCTAssertEqual(product.legacyShoppingItemID, entry.legacyShoppingItemID)

        let items = try context.fetch(FetchDescriptor<ShoppingItem>())
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.id, entry.legacyShoppingItemID)
        XCTAssertEqual(item.name, product.name)
        XCTAssertEqual(item.category, product.category)
        XCTAssertEqual(item.imageData, product.imageData)
        XCTAssertEqual(item.source, .catalog)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductKnowledge>()).isEmpty)
    }

    func testBackfillAndPhotoUpdatesPreserveCatalogIdentityAndSnapshots() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        context.insert(list)
        try context.save()
        let product = try saveCatalogProduct(in: context)
        _ = try ShoppingListService().addProductToShopping(
            product,
            shoppingListID: list.id,
            in: context
        )
        let item = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ShoppingItem>()).first
        )
        let originalCatalogValues = CatalogValues(product: product)
        let originalProductID = product.id
        let originalEntryCount = try context.fetchCount(
            FetchDescriptor<ShoppingListEntry>()
        )

        item.name = "Legacy overwrite attempt"
        item.category = "Legacy category"
        item.imageData = Data([0xff])
        item.sourceRawValue = ProductSource.manual.rawValue
        try context.save()

        let backfill = ShoppingListBackfillService()
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)
        let firstCounts = try compatibilityCounts(in: context)
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)
        let secondCounts = try compatibilityCounts(in: context)

        XCTAssertEqual(product.id, originalProductID)
        XCTAssertEqual(CatalogValues(product: product), originalCatalogValues)
        XCTAssertEqual(product.name, "חלב")
        XCTAssertEqual(product.category, "מוצרי חלב")
        XCTAssertEqual(product.imageData, Data([0x10, 0x20]))
        XCTAssertEqual(firstCounts, secondCounts)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ShoppingListEntry>()),
            originalEntryCount
        )

        let replacementPhoto = Data([0x99, 0x88, 0x77])
        let photoUpdateDate = snapshotDate.addingTimeInterval(500)
        product.imageData = replacementPhoto
        product.updatedAt = photoUpdateDate
        try context.save()

        let reloaded = try XCTUnwrap(
            try ModelContext(container).fetch(FetchDescriptor<Product>()).first {
                $0.id == originalProductID
            }
        )
        XCTAssertEqual(reloaded.imageData, replacementPhoto)
        XCTAssertEqual(reloaded.updatedAt, photoUpdateDate)
        XCTAssertEqual(CatalogValues(product: reloaded), originalCatalogValues)
    }

    func testUnresolvedRecognitionIgnoresCatalogLinkedProductForBarcodeAndMetadataMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let linked = try saveCatalogProduct(in: context)
        linked.brand = "Known Brand"
        linked.barcode = "729000000001"
        linked.category = "Dairy"
        try context.save()
        let originalValues = CatalogValues(product: linked)
        let originalName = linked.name
        let originalImage = linked.imageData
        let candidate = ProductCandidate(
            name: linked.name,
            brand: linked.brand,
            category: linked.category,
            confidence: 0.99,
            source: .barcode,
            imageData: Data([0xee]),
            barcode: linked.barcode
        )

        let recognized = try ShoppingListService().upsertRecognizedProduct(
            candidate,
            fallbackImageData: nil,
            in: context
        )

        XCTAssertNotEqual(recognized.id, linked.id)
        XCTAssertNil(recognized.catalogProductIDRawValue)
        XCTAssertEqual(recognized.source, .barcode)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 2)
        XCTAssertEqual(linked.name, originalName)
        XCTAssertEqual(linked.imageData, originalImage)
        XCTAssertEqual(CatalogValues(product: linked), originalValues)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductKnowledge>()), 1)
    }

    func testMalformedCatalogIdentityRemainsProtectedFromHeuristicRecognition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let linked = Product(
            name: "Protected Product",
            brand: "Brand",
            category: "Category",
            barcode: "12345",
            catalogProductIDRawValue: " malformed "
        )
        context.insert(linked)
        try context.save()
        let candidate = ProductCandidate(
            name: "Protected Product",
            brand: "Brand",
            category: "Category",
            source: .barcode,
            barcode: "12345"
        )

        let recognized = try ShoppingListService().upsertRecognizedProduct(
            candidate,
            fallbackImageData: nil,
            in: context
        )

        XCTAssertTrue(linked.isCatalogLinked)
        XCTAssertNil(linked.catalogProductID)
        XCTAssertNotEqual(recognized.id, linked.id)
        XCTAssertNil(recognized.catalogProductIDRawValue)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 2)
    }

    func testCatalogSnapshotDoesNotChangeWhenSameIdentityIsSavedFromUpdatedCatalogData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let original = try saveCatalogProduct(in: context)
        let originalValues = CatalogValues(product: original)
        let originalName = original.name
        let originalCategory = original.category
        let originalImage = original.imageData
        let originalSource = original.source
        let originalUpdatedAt = original.updatedAt
        let changedRequest = CatalogProductSaveRequest(
            productID: ProductID("prd_pilot_0001"),
            displayNameSnapshot: "Catalog Renamed Milk",
            displayLocaleSnapshot: "en",
            categoryIDSnapshot: ProductCategoryID("new-category"),
            categoryDisplayNameSnapshot: "New Category",
            iconKeySnapshot: "product.new-icon",
            imageData: Data([0xaa]),
            source: .camera
        )
        let service = CatalogProductPersistenceService(
            clock: { self.snapshotDate.addingTimeInterval(1_000) }
        )

        let outcome = try service.save(changedRequest, in: context)
        guard case .alreadyPresent(let existing) = outcome else {
            return XCTFail("Expected the saved snapshot to win")
        }

        XCTAssertEqual(existing.id, original.id)
        XCTAssertEqual(existing.name, originalName)
        XCTAssertEqual(existing.category, originalCategory)
        XCTAssertEqual(existing.imageData, originalImage)
        XCTAssertEqual(existing.source, originalSource)
        XCTAssertEqual(existing.updatedAt, originalUpdatedAt)
        XCTAssertEqual(CatalogValues(product: existing), originalValues)
    }

    private func saveCatalogProduct(in context: ModelContext) throws -> Product {
        let request = CatalogProductSaveRequest(
            productID: ProductID("prd_pilot_0001"),
            displayNameSnapshot: "חלב",
            displayLocaleSnapshot: "he",
            categoryIDSnapshot: ProductCategoryID("dairy"),
            categoryDisplayNameSnapshot: "מוצרי חלב",
            iconKeySnapshot: "product.dairy",
            imageData: Data([0x10, 0x20]),
            source: .catalog
        )
        let outcome = try CatalogProductPersistenceService(
            clock: { self.snapshotDate }
        ).save(request, in: context)
        guard case .inserted(let product) = outcome else {
            throw CompatibilityTestError.expectedInsertion
        }
        return product
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(configurations: [configuration])
    }

    private func compatibilityCounts(in context: ModelContext) throws -> CompatibilityCounts {
        CompatibilityCounts(
            items: try context.fetchCount(FetchDescriptor<ShoppingItem>()),
            products: try context.fetchCount(FetchDescriptor<Product>()),
            lists: try context.fetchCount(FetchDescriptor<ShoppingList>()),
            entries: try context.fetchCount(FetchDescriptor<ShoppingListEntry>())
        )
    }
}

private enum CompatibilityTestError: Error {
    case expectedInsertion
}

private struct CatalogValues: Equatable {
    let rawProductID: String?
    let displayName: String?
    let displayLocale: String?
    let categoryID: String?
    let categoryDisplayName: String?
    let iconKey: String?
    let updatedAt: Date?

    init(product: Product) {
        rawProductID = product.catalogProductIDRawValue
        displayName = product.catalogDisplayNameSnapshot
        displayLocale = product.catalogDisplayLocaleSnapshot
        categoryID = product.catalogCategoryIDSnapshotRawValue
        categoryDisplayName = product.catalogCategoryDisplayNameSnapshot
        iconKey = product.catalogIconKeySnapshot
        updatedAt = product.catalogSnapshotUpdatedAt
    }
}

private struct CompatibilityCounts: Equatable {
    let items: Int
    let products: Int
    let lists: Int
    let entries: Int
}
