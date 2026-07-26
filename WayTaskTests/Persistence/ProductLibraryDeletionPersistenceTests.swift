import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductLibraryDeletionPersistenceTests: XCTestCase {
    private let deletedAt =
        Date(timeIntervalSince1970: 1_900_000_000)

    func testDeletedProductRemainsDeletedAfterRelaunchWhileHistorySurvives()
        throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT029B-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL =
            directory.appendingPathComponent("WayTask.store")

        let fixture = try seedAndDeleteBread(at: storeURL)
        let container = try makeFileContainer(url: storeURL)
        let context = ModelContext(container)

        let backfill = ShoppingListBackfillService()
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)

        let products = try context.fetch(FetchDescriptor<Product>())
        let activeProducts = products.filter {
            !$0.isDeletedFromLibrary
        }
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let histories = try context.fetch(
            FetchDescriptor<ProductHistory>()
        )
        let items = try context.fetch(FetchDescriptor<ShoppingItem>())

        XCTAssertEqual(products.count, 1)
        XCTAssertTrue(activeProducts.isEmpty)
        XCTAssertEqual(products.first?.id, fixture.productID)
        XCTAssertEqual(products.first?.deletedAt, deletedAt)
        XCTAssertEqual(items.map(\.id), [fixture.itemID])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            Set(entries.map(\.shoppingListID)),
            Set([
                fixture.completedListID,
                fixture.recentListID
            ])
        )
        XCTAssertTrue(
            entries.allSatisfy {
                $0.productID == fixture.productID &&
                    $0.product?.id == fixture.productID
            }
        )
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(histories.first?.id, fixture.historyID)
        XCTAssertEqual(histories.first?.addCount, 4)
        XCTAssertEqual(
            histories.first?.lastCompletedDate,
            fixture.completedAt
        )
    }

    func testHistoricalEntryCannotRecreatePhysicallyMissingProduct()
        throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let item = ShoppingItem(
            name: "Bread",
            isCompleted: true,
            barcode: "729000000099"
        )
        let product = Product(
            legacyShoppingItemID: item.id,
            name: "Bread",
            barcode: item.barcode
        )
        let completed = ShoppingList(
            title: "Completed",
            kind: .completed
        )
        let historicalEntry = ShoppingListEntry(
            shoppingListID: completed.id,
            product: product,
            legacyShoppingItemID: item.id,
            isChecked: true
        )
        context.insert(item)
        context.insert(product)
        context.insert(completed)
        context.insert(historicalEntry)
        try context.save()

        let deletedProductID = product.id
        historicalEntry.product = nil
        try context.save()
        context.delete(product)
        try context.save()

        let relaunchedContext = ModelContext(container)
        _ = try ShoppingListBackfillService()
            .ensureDefaultListsAndBackfill(in: relaunchedContext)

        XCTAssertEqual(
            try relaunchedContext.fetchCount(
                FetchDescriptor<Product>()
            ),
            0
        )
        let entries = try relaunchedContext.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.productID, deletedProductID)
        XCTAssertNil(entries.first?.product)
        XCTAssertEqual(
            try relaunchedContext.fetchCount(
                FetchDescriptor<ShoppingItem>()
            ),
            1
        )
    }

    func testLegacyRepairUsesStableBarcodeToPreventDuplicateProducts()
        throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(
            ShoppingItem(
                name: "Bread",
                barcode: "729000000099"
            )
        )
        context.insert(
            ShoppingItem(
                name: "לחם",
                barcode: " 729000000099 "
            )
        )
        try context.save()

        let backfill = ShoppingListBackfillService()
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)
        _ = try backfill.ensureDefaultListsAndBackfill(in: context)

        let products = try context.fetch(FetchDescriptor<Product>())
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(
            products.first?.barcode?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "729000000099"
        )
        XCTAssertFalse(products.first?.isDeletedFromLibrary ?? true)
    }

    private func seedAndDeleteBread(
        at storeURL: URL
    ) throws -> DeletionFixture {
        let container = try makeFileContainer(url: storeURL)
        let context = ModelContext(container)
        let item = ShoppingItem(
            name: "Bread",
            barcode: "729000000099"
        )
        let product = Product(
            legacyShoppingItemID: item.id,
            name: "Bread",
            barcode: item.barcode,
            catalogProductIDRawValue: "bread_whole_wheat"
        )
        let weekly = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let completed = ShoppingList(
            title: "Completed",
            kind: .completed
        )
        let recent = ShoppingList(
            title: "Recent",
            kind: .recent
        )
        let weeklyEntry = ShoppingListEntry(
            shoppingListID: weekly.id,
            product: product,
            legacyShoppingItemID: item.id
        )
        let completedEntry = ShoppingListEntry(
            shoppingListID: completed.id,
            product: product,
            legacyShoppingItemID: item.id,
            isChecked: true
        )
        let recentEntry = ShoppingListEntry(
            shoppingListID: recent.id,
            product: product,
            legacyShoppingItemID: item.id,
            isChecked: true
        )
        let completedAt =
            Date(timeIntervalSince1970: 1_850_000_000)
        let history = ProductHistory(
            productKey: "barcode:729000000099",
            productName: "Bread",
            barcode: item.barcode,
            addCount: 4,
            lastCompletedDate: completedAt
        )

        context.insert(item)
        context.insert(product)
        context.insert(weekly)
        context.insert(completed)
        context.insert(recent)
        context.insert(weeklyEntry)
        context.insert(completedEntry)
        context.insert(recentEntry)
        context.insert(history)
        try context.save()

        try ProductLibraryDeletionService(
            clock: { self.deletedAt }
        ).delete(product, in: context)

        XCTAssertEqual(
            try context.fetchCount(
                FetchDescriptor<ShoppingListEntry>()
            ),
            2
        )
        XCTAssertTrue(product.isDeletedFromLibrary)

        return DeletionFixture(
            productID: product.id,
            itemID: item.id,
            completedListID: completed.id,
            recentListID: recent.id,
            historyID: history.id,
            completedAt: completedAt
        )
    }

    private func makeFileContainer(
        url: URL
    ) throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            "WT029B",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }

    private func makeInMemoryContainer() throws
        -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }
}

private struct DeletionFixture {
    let productID: UUID
    let itemID: UUID
    let completedListID: UUID
    let recentListID: UUID
    let historyID: UUID
    let completedAt: Date
}
