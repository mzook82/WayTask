import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class StartupRepairIdempotencyTests: XCTestCase {
    func testPartiallyRepairedStartupStateCompletesAndRepeatedRelaunchIsStable()
        throws
    {
        let fixture = try makeFileFixture(
            name: "PartialRepair"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let itemID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
        let productID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
        let listID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000001"
        )!
        let entryID = UUID(
            uuidString: "40000000-0000-0000-0000-000000000001"
        )!

        do {
            let container = try makeFileContainer(
                at: fixture.storeURL
            )
            let context = ModelContext(container)
            let item = ShoppingItem(
                id: itemID,
                name: "Milk",
                barcode: "729000000001"
            )
            let product = Product(
                id: productID,
                legacyShoppingItemID: itemID,
                name: "Milk",
                barcode: item.barcode
            )
            let weekly = ShoppingList(
                id: listID,
                title: "Weekly Shopping",
                kind: .weekly,
                isDefault: true
            )
            let entry = ShoppingListEntry(
                id: entryID,
                shoppingListID: listID,
                product: product,
                legacyShoppingItemID: itemID
            )
            context.insert(item)
            context.insert(product)
            context.insert(weekly)
            context.insert(entry)
            try context.save()

            entry.product = nil
            entry.productID = productID
            try context.save()
        }

        let first = try repairAndSnapshot(
            at: fixture.storeURL
        )
        let second = try repairAndSnapshot(
            at: fixture.storeURL
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.products.count, 1)
        XCTAssertEqual(first.entries.count, 1)
        XCTAssertEqual(first.entries[0].productID, productID)
        XCTAssertEqual(first.entries[0].relatedProductID, productID)
        XCTAssertEqual(first.lists.count, 3)
    }

    func testStartupWithMissingOptionalCatalogMetadataRepairsOnce()
        throws
    {
        let container = try WayTaskModelContainer.makeInMemory()
        let context = ModelContext(container)
        let product = Product(
            name: "Legacy catalog milk",
            catalogProductIDRawValue: "prd_pilot_0001"
        )
        context.insert(product)
        try context.save()

        let repair = ShoppingListBackfillService()
        _ = try repair.ensureDefaultListsAndBackfill(
            in: context
        )
        let firstSnapshot = ProductRepairSnapshot(product)
        _ = try repair.ensureDefaultListsAndBackfill(
            in: context
        )
        let secondSnapshot = ProductRepairSnapshot(product)

        XCTAssertEqual(
            product.catalogProductIDRawValue,
            "milk_3_percent"
        )
        XCTAssertEqual(
            product.catalogDisplayNameSnapshot,
            "חלב 3%"
        )
        XCTAssertEqual(
            product.catalogDisplayLocaleSnapshot,
            "he"
        )
        XCTAssertEqual(
            product.catalogCategoryIDSnapshotRawValue,
            "dairy"
        )
        XCTAssertEqual(
            product.catalogCategoryDisplayNameSnapshot,
            "מוצרי חלב"
        )
        XCTAssertEqual(
            product.catalogIconKeySnapshot,
            "product.dairy"
        )
        XCTAssertNotNil(product.catalogSnapshotUpdatedAt)
        XCTAssertEqual(firstSnapshot, secondSnapshot)
    }

    func testRepeatedStartupAfterInterruptedDefaultListRepairIsIdempotent()
        throws
    {
        let container = try WayTaskModelContainer.makeInMemory()
        let context = ModelContext(container)
        let weekly = ShoppingList(
            title: "Interrupted title",
            kind: .weekly,
            isDefault: false
        )
        context.insert(weekly)
        try context.save()

        let repair = ShoppingListBackfillService()
        let firstResult =
            try repair.ensureDefaultListsAndBackfill(in: context)
        let first = try persistenceSnapshot(in: context)
        let secondResult =
            try repair.ensureDefaultListsAndBackfill(in: context)
        let second = try persistenceSnapshot(in: context)

        XCTAssertEqual(firstResult.weeklyListID, weekly.id)
        XCTAssertEqual(secondResult.weeklyListID, weekly.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lists.count, 3)
        XCTAssertEqual(
            first.lists.map(\.kindRawValue).sorted(),
            ShoppingListKind.allCases.map(\.rawValue).sorted()
        )
        XCTAssertEqual(weekly.title, "Weekly Shopping")
        XCTAssertTrue(weekly.isDefault)
    }

    func testStartupAfterTombstonedProductDoesNotResurrectIt()
        throws
    {
        let container = try WayTaskModelContainer.makeInMemory()
        let context = ModelContext(container)
        let item = ShoppingItem(name: "Bread")
        let deletedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let product = Product(
            legacyShoppingItemID: item.id,
            name: "Bread",
            deletedAt: deletedAt
        )
        let weekly = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let entry = ShoppingListEntry(
            shoppingListID: weekly.id,
            product: product,
            legacyShoppingItemID: item.id
        )
        context.insert(item)
        context.insert(product)
        context.insert(weekly)
        context.insert(entry)
        try context.save()

        let repair = ShoppingListBackfillService()
        _ = try repair.ensureDefaultListsAndBackfill(in: context)
        let first = try persistenceSnapshot(in: context)
        _ = try repair.ensureDefaultListsAndBackfill(in: context)
        let second = try persistenceSnapshot(in: context)

        XCTAssertEqual(first, second)
        XCTAssertEqual(product.deletedAt, deletedAt)
        XCTAssertTrue(product.isDeletedFromLibrary)
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(
            first.entries.allSatisfy {
                $0.shoppingListID != weekly.id
            }
        )
    }

    func testLegacyRepairedProductsDoNotOscillateAcrossRelaunches()
        throws
    {
        let fixture = try makeFileFixture(
            name: "LegacyRepair"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        do {
            let container = try makeFileContainer(
                at: fixture.storeURL
            )
            let context = ModelContext(container)
            context.insert(
                ShoppingItem(
                    id: UUID(
                        uuidString:
                            "10000000-0000-0000-0000-000000000001"
                    )!,
                    name: "Bread",
                    barcode: "729000000099"
                )
            )
            context.insert(
                ShoppingItem(
                    id: UUID(
                        uuidString:
                            "20000000-0000-0000-0000-000000000001"
                    )!,
                    name: "לחם",
                    barcode: " 729000000099 "
                )
            )
            try context.save()
        }

        let first = try repairAndSnapshot(
            at: fixture.storeURL
        )
        let second = try repairAndSnapshot(
            at: fixture.storeURL
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.products.count, 1)
        XCTAssertEqual(first.products[0].name, "Bread")
    }

    func testStartupAfterExplicitProductDeletionRemainsStable()
        throws
    {
        let container = try WayTaskModelContainer.makeInMemory()
        let context = ModelContext(container)
        let item = ShoppingItem(name: "Explicit deletion")
        let product = Product(
            legacyShoppingItemID: item.id,
            name: item.name
        )
        let weekly = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let entry = ShoppingListEntry(
            shoppingListID: weekly.id,
            product: product,
            legacyShoppingItemID: item.id
        )
        context.insert(item)
        context.insert(product)
        context.insert(weekly)
        context.insert(entry)
        try context.save()

        try ProductLibraryDeletionService(
            clock: {
                Date(timeIntervalSince1970: 1_900_000_100)
            }
        ).delete(product, in: context)
        let repair = ShoppingListBackfillService()
        _ = try repair.ensureDefaultListsAndBackfill(in: context)
        let first = try persistenceSnapshot(in: context)
        _ = try repair.ensureDefaultListsAndBackfill(in: context)
        let second = try persistenceSnapshot(in: context)

        XCTAssertEqual(first, second)
        XCTAssertTrue(product.isDeletedFromLibrary)
        XCTAssertTrue(item.isCompleted)
        XCTAssertFalse(
            first.entries.contains {
                $0.shoppingListID == weekly.id
            }
        )
    }

    private func repairAndSnapshot(
        at storeURL: URL
    ) throws -> PersistenceRepairSnapshot {
        let container = try makeFileContainer(at: storeURL)
        let context = ModelContext(container)
        _ = try ShoppingListBackfillService()
            .ensureDefaultListsAndBackfill(in: context)
        return try persistenceSnapshot(in: context)
    }

    private func persistenceSnapshot(
        in context: ModelContext
    ) throws -> PersistenceRepairSnapshot {
        let products = try context
            .fetch(FetchDescriptor<Product>())
            .map(ProductRepairSnapshot.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let lists = try context
            .fetch(FetchDescriptor<ShoppingList>())
            .map {
                ListRepairSnapshot(
                    id: $0.id,
                    title: $0.title,
                    kindRawValue: $0.kindRawValue,
                    updatedAt: $0.updatedAt,
                    isDefault: $0.isDefault
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let entries = try context
            .fetch(FetchDescriptor<ShoppingListEntry>())
            .map {
                EntryRepairSnapshot(
                    id: $0.id,
                    shoppingListID: $0.shoppingListID,
                    productID: $0.productID,
                    legacyShoppingItemID:
                        $0.legacyShoppingItemID,
                    relatedProductID: $0.product?.id
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let items = try context
            .fetch(FetchDescriptor<ShoppingItem>())
            .map {
                ItemRepairSnapshot(
                    id: $0.id,
                    name: $0.name,
                    isCompleted: $0.isCompleted
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return PersistenceRepairSnapshot(
            products: products,
            lists: lists,
            entries: entries,
            items: items
        )
    }

    private func makeFileFixture(
        name: String
    ) throws -> (
        directory: URL,
        storeURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT029B2-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            directory,
            directory.appendingPathComponent("WayTask.store")
        )
    }

    private func makeFileContainer(
        at storeURL: URL
    ) throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            "WT029B2",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }
}

private struct ProductRepairSnapshot: Equatable {
    let id: UUID
    let legacyShoppingItemID: UUID?
    let name: String
    let updatedAt: Date
    let deletedAt: Date?
    let catalogProductIDRawValue: String?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshotRawValue: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?

    init(_ product: Product) {
        id = product.id
        legacyShoppingItemID = product.legacyShoppingItemID
        name = product.name
        updatedAt = product.updatedAt
        deletedAt = product.deletedAt
        catalogProductIDRawValue =
            product.catalogProductIDRawValue
        catalogDisplayNameSnapshot =
            product.catalogDisplayNameSnapshot
        catalogDisplayLocaleSnapshot =
            product.catalogDisplayLocaleSnapshot
        catalogCategoryIDSnapshotRawValue =
            product.catalogCategoryIDSnapshotRawValue
        catalogCategoryDisplayNameSnapshot =
            product.catalogCategoryDisplayNameSnapshot
        catalogIconKeySnapshot =
            product.catalogIconKeySnapshot
        catalogSnapshotUpdatedAt =
            product.catalogSnapshotUpdatedAt
    }
}

private struct ListRepairSnapshot: Equatable {
    let id: UUID
    let title: String
    let kindRawValue: String
    let updatedAt: Date
    let isDefault: Bool
}

private struct EntryRepairSnapshot: Equatable {
    let id: UUID
    let shoppingListID: UUID
    let productID: UUID
    let legacyShoppingItemID: UUID?
    let relatedProductID: UUID?
}

private struct ItemRepairSnapshot: Equatable {
    let id: UUID
    let name: String
    let isCompleted: Bool
}

private struct PersistenceRepairSnapshot: Equatable {
    let products: [ProductRepairSnapshot]
    let lists: [ListRepairSnapshot]
    let entries: [EntryRepairSnapshot]
    let items: [ItemRepairSnapshot]
}
