import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class CanonicalCatalogSelectionFlowTests: XCTestCase {
    private let resolver = ShoppingItemCatalogResolver()

    func testCurrentCatalogSearchRetainsIdentityForBreadMilkAndWholeWheat()
        async throws
    {
        let products = ProductCatalogService().loadProductsOrEmpty()
        let search = ProductCatalogSearch(products: products)

        let breadResults = await search.suggestions(matching: "לחם")
        let milkResults = await search.suggestions(matching: "חלב")
        let wholeWheatResults = await search.suggestions(
            matching: "לחם מחיטה מלאה"
        )
        let breadAliasResults = await search.suggestions(
            matching: "כיכר לחם"
        )
        let milkAliasResults = await search.suggestions(
            matching: "קרטון חלב"
        )

        let bread = try XCTUnwrap(
            breadResults.first { $0.product.id == "bread_white" }
        )
        let milk = try XCTUnwrap(
            milkResults.first { $0.product.id == "milk_3_percent" }
        )
        let wholeWheat = try XCTUnwrap(
            wholeWheatResults.first {
                $0.product.id == "bread_whole_wheat"
            }
        )

        XCTAssertEqual(
            bread.asProductSearchResult().productID,
            ProductID("bread_white")
        )
        XCTAssertEqual(
            milk.asProductSearchResult().productID,
            ProductID("milk_3_percent")
        )
        XCTAssertEqual(
            wholeWheat.asProductSearchResult().productID,
            ProductID("bread_whole_wheat")
        )
        XCTAssertEqual(
            breadAliasResults.first?.asProductSearchResult().productID,
            ProductID("bread_white")
        )
        XCTAssertEqual(
            milkAliasResults.first?.asProductSearchResult().productID,
            ProductID("milk_3_percent")
        )
        XCTAssertEqual(
            Set(breadResults.map(\.product.id)).count,
            breadResults.count
        )
        XCTAssertEqual(
            Set(milkResults.map(\.product.id)).count,
            milkResults.count
        )
    }

    func testPhysicalDeviceSelectionsPersistRehydrateAndGroupFromCanonicalIDs()
        throws
    {
        let container = try makeContainer()
        let context = ModelContext(container)
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        context.insert(list)
        try context.save()

        let cases = [
            FlowCase(
                sourceID: "prd_pilot_0002",
                name: "לחם",
                expectedID: "bread_white",
                categoryID: "bakery",
                subcategoryID: nil,
                iconKey: "product.bread"
            ),
            FlowCase(
                sourceID: "prd_pilot_0001",
                name: "חלב",
                expectedID: "milk_3_percent",
                categoryID: "dairy",
                subcategoryID: "dairy.milk",
                iconKey: "product.dairy"
            ),
            FlowCase(
                sourceID: "bread_whole_wheat",
                name: "לחם מחיטה מלאה",
                expectedID: "bread_whole_wheat",
                categoryID: "bakery",
                subcategoryID: nil,
                iconKey: "product.bread"
            )
        ]

        let coordinator = AddProductSaveCoordinator()
        for flow in cases {
            let outcome = try coordinator.save(
                selection: .catalog(flow.selection),
                imageData: nil,
                in: context
            )
            let product = try insertedProduct(from: outcome)
            XCTAssertEqual(
                product.catalogProductIDRawValue,
                flow.expectedID
            )
            _ = try ShoppingListService().addProductToShopping(
                product,
                shoppingListID: list.id,
                in: context
            )
        }

        let reloadedContext = ModelContext(container)
        let products = try reloadedContext.fetch(
            FetchDescriptor<Product>()
        )
        let entries = try reloadedContext.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let items = try reloadedContext.fetch(
            FetchDescriptor<ShoppingItem>()
        )
        resolver.hydrate(items, products: products, entries: entries)

        XCTAssertEqual(products.count, cases.count)
        XCTAssertEqual(entries.count, cases.count)
        XCTAssertEqual(items.count, cases.count)

        let matcher = ShoppingIntentMatcher()
        for flow in cases {
            let product = try XCTUnwrap(
                products.first {
                    $0.catalogProductIDRawValue == flow.expectedID
                }
            )
            let entry = try XCTUnwrap(
                entries.first { $0.productID == product.id }
            )
            let item = try XCTUnwrap(
                items.first { $0.id == entry.legacyShoppingItemID }
            )

            XCTAssertEqual(
                entry.product?.catalogProductIDRawValue,
                flow.expectedID
            )
            XCTAssertEqual(item.catalogProductIDRawValue, flow.expectedID)
            XCTAssertEqual(
                item.catalogCategoryIDRawValue,
                flow.categoryID
            )
            XCTAssertEqual(
                item.catalogSubcategoryIDRawValue,
                flow.subcategoryID
            )
            XCTAssertEqual(resolver.iconKey(for: product), flow.iconKey)
            XCTAssertEqual(resolver.iconKey(for: item), flow.iconKey)
            XCTAssertEqual(matcher.intentGroup(for: item), .grocery)
        }

        XCTAssertFalse(
            items.contains {
                matcher.intentGroup(for: $0) == .other
            }
        )
        XCTAssertEqual(
            matcher.groupedIntents(for: items).map(\.group),
            [.grocery]
        )
    }

    func testProductsAndShoppingUseSameSemanticIconWhileCustomUsesFallback() {
        let product = Product(
            name: "חלב",
            source: .catalog,
            catalogProductIDRawValue: "prd_pilot_0001",
            catalogIconKeySnapshot: "product.future"
        )
        let item = ShoppingItem(
            name: "חלב",
            source: .catalog,
            catalogProductIDRawValue: "prd_pilot_0001"
        )
        let customProduct = Product(
            name: "פריט מותאם",
            source: .manual
        )
        let customItem = ShoppingItem(
            name: "פריט מותאם",
            source: .manual
        )

        XCTAssertEqual(resolver.iconKey(for: product), "product.dairy")
        XCTAssertEqual(
            resolver.iconKey(for: product),
            resolver.iconKey(for: item)
        )
        XCTAssertEqual(
            ProductShoppingThumbnailPresentation(product: product)
                .fallbackSystemName,
            "drop.fill"
        )
        XCTAssertNil(resolver.iconKey(for: customProduct))
        XCTAssertNil(resolver.iconKey(for: customItem))
        XCTAssertEqual(
            ProductShoppingThumbnailPresentation(product: customProduct)
                .fallbackSystemName,
            ProductKnowledgeIconResolver.fallbackSystemName
        )
    }

    func testLegacyCatalogProductRepairsInPlaceWithoutDataLoss() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let item = ShoppingItem(name: "לחם", source: .catalog)
        let product = Product(
            legacyShoppingItemID: item.id,
            name: "לחם",
            source: .catalog,
            catalogProductIDRawValue: "prd_pilot_0002",
            catalogCategoryIDSnapshotRawValue: nil,
            catalogIconKeySnapshot: nil
        )
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let entry = ShoppingListEntry(
            shoppingListID: list.id,
            product: product,
            legacyShoppingItemID: item.id
        )
        context.insert(item)
        context.insert(product)
        context.insert(list)
        context.insert(entry)
        try context.save()

        let originalIDs = [
            item.id,
            product.id,
            list.id,
            entry.id
        ]
        let originalItemCount = try context.fetchCount(
            FetchDescriptor<ShoppingItem>()
        )
        let originalProductCount = try context.fetchCount(
            FetchDescriptor<Product>()
        )
        let originalEntryCount = try context.fetchCount(
            FetchDescriptor<ShoppingListEntry>()
        )

        _ = try ShoppingListBackfillService()
            .ensureDefaultListsAndBackfill(in: context)

        XCTAssertEqual(product.catalogProductIDRawValue, "bread_white")
        XCTAssertEqual(
            product.catalogCategoryIDSnapshotRawValue,
            "bakery"
        )
        XCTAssertEqual(product.catalogIconKeySnapshot, "product.bread")
        XCTAssertEqual(item.catalogProductIDRawValue, "bread_white")
        XCTAssertEqual(item.catalogCategoryIDRawValue, "bakery")
        XCTAssertEqual(
            [item.id, product.id, list.id, entry.id],
            originalIDs
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ShoppingItem>()),
            originalItemCount
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Product>()),
            originalProductCount
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ShoppingListEntry>()),
            originalEntryCount
        )
    }

    func testLogicalDuplicateCompatibilityDoesNotDeleteOrGuess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let current = Product(
            name: "חלב 3%",
            source: .catalog,
            catalogProductIDRawValue: "milk_3_percent"
        )
        let legacy = Product(
            name: "חלב",
            source: .catalog,
            catalogProductIDRawValue: "prd_pilot_0001"
        )
        let custom = Product(name: "חלב מיוחד", source: .manual)
        context.insert(current)
        context.insert(legacy)
        context.insert(custom)
        try context.save()
        let originalIDs = Set([current.id, legacy.id, custom.id])

        _ = try ShoppingListBackfillService()
            .ensureDefaultListsAndBackfill(in: context)

        let products = try context.fetch(FetchDescriptor<Product>())
        XCTAssertEqual(products.count, 3)
        XCTAssertEqual(Set(products.map(\.id)), originalIDs)
        XCTAssertEqual(
            current.catalogProductIDRawValue,
            "milk_3_percent"
        )
        XCTAssertEqual(
            legacy.catalogProductIDRawValue,
            "prd_pilot_0001"
        )
        XCTAssertNil(custom.catalogProductIDRawValue)
        XCTAssertEqual(
            resolver.resolve(
                productIDRawValue: legacy.catalogProductIDRawValue
            )?.productID,
            "milk_3_percent"
        )
    }

    private func insertedProduct(
        from outcome: AddProductSaveOutcome
    ) throws -> Product {
        guard case .catalogInserted(let product) = outcome else {
            XCTFail("Expected a new catalog product")
            throw FlowTestError.expectedCatalogInsertion
        }
        return product
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: WayTaskModelContainer.currentSchema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }
}

private struct FlowCase {
    let sourceID: String
    let name: String
    let expectedID: String
    let categoryID: String
    let subcategoryID: String?
    let iconKey: String

    var selection: AddProductCatalogSelection {
        AddProductCatalogSelection(
            result: ProductSearchResult(
                productID: ProductID(sourceID),
                displayName: name,
                displayLocale: "he",
                secondaryName: nil,
                categoryID: ProductCategoryID(categoryID),
                categoryDisplayName: "stale selection snapshot",
                iconKey: "product.future",
                matchedRecordAuthority: .primaryDisplayName,
                matchType: .exact,
                matchedLocale: "he"
            ),
            preselectionQuery: name
        )
    }
}

private enum FlowTestError: Error {
    case expectedCatalogInsertion
}
