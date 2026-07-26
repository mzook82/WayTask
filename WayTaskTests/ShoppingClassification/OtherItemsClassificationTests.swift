import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class OtherItemsClassificationTests: XCTestCase {
    func testCanonicalMilkAndBreadUseTaxonomyIDsWhenSnapshotsAreMissing() {
        let matcher = makeMatcher()
        let milk = ShoppingItem(
            name: "חלב 3%",
            category: nil,
            catalogProductIDRawValue: "milk_3_percent"
        )
        let bread = ShoppingItem(
            name: "לחם מחיטה מלאה",
            category: nil,
            catalogProductIDRawValue: "bread_whole_wheat"
        )

        XCTAssertEqual(matcher.intentGroup(for: milk), .grocery)
        XCTAssertEqual(matcher.intentGroup(for: bread), .grocery)
        XCTAssertFalse(matcher.intentProfile(for: milk).isUnresolved)
        XCTAssertFalse(matcher.intentProfile(for: bread).isUnresolved)
        XCTAssertEqual(
            matcher.groupedIntents(for: [milk, bread]).map(\.group),
            [.grocery]
        )

        let resolver = ShoppingItemCatalogResolver(
            products: catalogProducts
        )
        XCTAssertEqual(
            resolver.resolve(item: milk),
            ResolvedShoppingItemCatalogIdentity(
                productID: "milk_3_percent",
                categoryID: "dairy",
                subcategoryID: "dairy.milk",
                canonicalName: "חלב 3%"
            )
        )
        XCTAssertEqual(
            resolver.resolve(item: bread)?.categoryID,
            "bakery"
        )
    }

    func testCanonicalIdentitySurvivesLibraryShoppingPlannerAndMap()
        throws
    {
        let container = try makeContainer()
        let context = ModelContext(container)
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let product = Product(
            name: "חלב 3%",
            category: nil,
            source: .catalog,
            catalogProductIDRawValue: "milk_3_percent"
        )
        context.insert(list)
        context.insert(product)
        try context.save()

        _ = try ShoppingListService().addProductToShopping(
            product,
            shoppingListID: list.id,
            in: context
        )

        // Simulate the next screen (or app launch) loading the persisted
        // Library → Shopping relationship, then deriving current taxonomy.
        let reloadedContext = ModelContext(container)
        let items = try reloadedContext.fetch(
            FetchDescriptor<ShoppingItem>()
        )
        let products = try reloadedContext.fetch(
            FetchDescriptor<Product>()
        )
        let entries = try reloadedContext.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        ShoppingItemCatalogResolver(products: catalogProducts).hydrate(
            items,
            products: products,
            entries: entries
        )
        let item = try XCTUnwrap(items.first)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.product?.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(item.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(item.catalogCategoryIDRawValue, "dairy")
        XCTAssertEqual(
            item.catalogSubcategoryIDRawValue,
            "dairy.milk"
        )

        let matcher = makeMatcher()
        let store = groceryStore()
        let request = matcher.request(for: [item], in: .grocery)
        let coverages = ShoppingTripService(
            intentMatcher: matcher
        ).coverage(
            for: [item],
            stores: [store],
            request: request,
            userCoordinate: store.coordinate
        )
        let coverage = try XCTUnwrap(coverages.first)
        XCTAssertEqual(coverage.matchedItems.map(\.id), [item.id])
        XCTAssertEqual(
            coverage.matchedItems.first?.catalogProductIDRawValue,
            "milk_3_percent"
        )

        let plan = ShoppingPlan(
            request: request,
            items: [item],
            stores: [store],
            buyingOptions: [],
            shoppingTripCoverages: coverages
        )
        XCTAssertEqual(
            plan.items.first?.catalogProductIDRawValue,
            "milk_3_percent"
        )

        let mapViewModel = MapViewModel()
        mapViewModel.applyShoppingPlan(plan)
        XCTAssertEqual(
            mapViewModel.filteredStores.first?.itemNames,
            [item.name]
        )
    }

    func testLegacyCatalogItemRecoversCurrentTaxonomyWithoutDataLoss()
        throws
    {
        let container = try makeContainer()
        let context = ModelContext(container)
        let item = ShoppingItem(
            name: "Legacy display",
            category: nil
        )
        let product = Product(
            legacyShoppingItemID: item.id,
            name: "Stale product snapshot",
            category: nil,
            source: .catalog,
            catalogProductIDRawValue: "milk_3_percent",
            catalogDisplayNameSnapshot: nil,
            catalogCategoryIDSnapshotRawValue: nil,
            catalogCategoryDisplayNameSnapshot: nil
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

        let originalIDs = PersistenceIDs(
            item: item.id,
            product: product.id,
            list: list.id,
            entry: entry.id
        )
        let originalCounts = try persistenceCounts(in: context)

        let result = try ShoppingListBackfillService()
            .ensureDefaultListsAndBackfill(in: context)

        XCTAssertEqual(result.weeklyListID, list.id)
        XCTAssertEqual(item.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(item.catalogCategoryIDRawValue, "dairy")
        XCTAssertEqual(
            item.catalogSubcategoryIDRawValue,
            "dairy.milk"
        )
        XCTAssertEqual(product.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(
            product.catalogCategoryIDSnapshotRawValue,
            "dairy"
        )
        XCTAssertEqual(product.catalogIconKeySnapshot, "product.dairy")
        let finalCounts = try persistenceCounts(in: context)
        XCTAssertEqual(finalCounts.items, originalCounts.items)
        XCTAssertEqual(finalCounts.products, originalCounts.products)
        XCTAssertEqual(finalCounts.entries, originalCounts.entries)
        XCTAssertEqual(finalCounts.lists, originalCounts.lists + 2)
        XCTAssertEqual(
            PersistenceIDs(
                item: item.id,
                product: product.id,
                list: list.id,
                entry: entry.id
            ),
            originalIDs
        )
    }

    func testUnresolvedCustomItemRemainsVisibleAndUnlinked()
        throws
    {
        let container = try makeContainer()
        let context = ModelContext(container)
        let list = ShoppingList(
            title: "Weekly Shopping",
            kind: .weekly,
            isDefault: true
        )
        let product = Product(
            name: "פריט מיוחד ללא סיווג",
            source: .manual
        )
        context.insert(list)
        context.insert(product)
        try context.save()

        _ = try ShoppingListService().addProductToShopping(
            product,
            shoppingListID: list.id,
            in: context
        )
        let item = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ShoppingItem>())
                .first
        )
        let matcher = makeMatcher()

        XCTAssertEqual(item.name, product.name)
        XCTAssertNil(product.catalogProductIDRawValue)
        XCTAssertNil(item.catalogProductIDRawValue)
        XCTAssertEqual(matcher.intentGroup(for: item), .other)
        XCTAssertEqual(
            matcher.unresolvedItems(from: [item]).map(\.id),
            [item.id]
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ShoppingListEntry>()),
            1
        )
    }

    func testOneUnresolvedCustomItemDoesNotBlockCanonicalPlanning() {
        let matcher = makeMatcher()
        let milk = ShoppingItem(
            name: "חלב 3%",
            catalogProductIDRawValue: "milk_3_percent"
        )
        let custom = ShoppingItem(
            name: "פריט מיוחד ללא סיווג",
            source: .manual
        )
        let allItems = [custom, milk]
        let eligible = matcher.eligibleItems(from: allItems)
        let unresolved = matcher.unresolvedItems(from: allItems)

        XCTAssertEqual(eligible.map(\.id), [milk.id])
        XCTAssertEqual(unresolved.map(\.id), [custom.id])
        XCTAssertEqual(
            matcher.groupedIntents(for: allItems)
                .flatMap(\.items)
                .map(\.id),
            [milk.id]
        )

        let store = groceryStore()
        let request = matcher.request(for: eligible, in: .grocery)
        let coverage = ShoppingTripService(
            intentMatcher: matcher
        ).coverage(
            for: allItems,
            stores: [store],
            request: request,
            userCoordinate: store.coordinate
        )

        XCTAssertEqual(coverage.first?.matchedItems.map(\.id), [milk.id])
        XCTAssertFalse(
            coverage.flatMap(\.matchedItems)
                .contains { $0.id == custom.id }
        )
    }

    func testMapAndStoreMatchingIncludeCanonicalProducts() {
        let matcher = makeMatcher()
        let milk = ShoppingItem(
            name: "שם תצוגה שאינו משמש לסיווג",
            catalogProductIDRawValue: "milk_3_percent"
        )
        let store = groceryStore()

        XCTAssertEqual(
            matcher.relevantItems(from: [milk], for: store).map(\.id),
            [milk.id]
        )
        XCTAssertEqual(
            StoreResolutionEngine(
                searchService: MapKitStoreSearchService()
            ).intents(for: [milk]).first?.storeCategories,
            [.grocery, .supermarket, .convenienceStore]
        )
    }

    func testUnresolvedItemsDoNotProduceFalseStoreOrNotificationMatches() {
        let matcher = makeMatcher()
        let custom = ShoppingItem(
            name: "פריט מיוחד ללא סיווג",
            source: .manual
        )
        let savedStore = MapStore(
            id: UUID(),
            locationID: UUID(),
            title: "Explicit legacy store",
            coordinate: CLLocationCoordinate2D(
                latitude: 31.7683,
                longitude: 35.2137
            ),
            radius: 200,
            itemNames: [custom.name],
            completedItemNames: [],
            isOpen: true,
            rating: nil,
            storeCategories: [.generalStore],
            queryEvidenceCategories: [],
            websiteURL: nil,
            sourceType: .userGenerated
        )

        XCTAssertTrue(matcher.groupedIntents(for: [custom]).isEmpty)
        XCTAssertTrue(
            matcher.relevantItems(from: [custom], for: savedStore)
                .isEmpty
        )
        XCTAssertTrue(
            ShoppingTripService(
                intentMatcher: matcher
            ).coverage(
                for: [custom],
                stores: [savedStore],
                request: nil,
                userCoordinate: savedStore.coordinate
            ).isEmpty
        )
        XCTAssertTrue(
            StoreResolutionEngine(
                searchService: MapKitStoreSearchService()
            ).intents(for: [custom]).isEmpty
        )
    }

    private var catalogProducts: [CatalogProduct] {
        [
            CatalogProduct(
                id: "milk_3_percent",
                canonicalName: "חלב 3%",
                categoryId: "dairy",
                subcategoryId: "dairy.milk",
                aliases: ["חלב"],
                keywords: ["מוצרי חלב"],
                popularityScore: 100,
                isActive: true
            ),
            CatalogProduct(
                id: "bread_whole_wheat",
                canonicalName: "לחם מחיטה מלאה",
                categoryId: "bakery",
                subcategoryId: nil,
                aliases: ["לחם מלא"],
                keywords: ["מאפייה"],
                popularityScore: 94,
                isActive: true
            )
        ]
    }

    private func makeMatcher() -> ShoppingIntentMatcher {
        ShoppingIntentMatcher(
            catalogProducts: catalogProducts
        )
    }

    private func groceryStore() -> MapStore {
        MapStore(
            id: UUID(),
            locationID: nil,
            title: "Canonical Grocery",
            coordinate: CLLocationCoordinate2D(
                latitude: 31.7683,
                longitude: 35.2137
            ),
            radius: 200,
            itemNames: [],
            completedItemNames: [],
            isOpen: true,
            rating: 4.8,
            storeCategories: [.supermarket],
            queryEvidenceCategories: [.supermarket],
            websiteURL: nil,
            sourceType: .appleMaps
        )
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

    private func persistenceCounts(
        in context: ModelContext
    ) throws -> PersistenceCounts {
        PersistenceCounts(
            items: try context.fetchCount(
                FetchDescriptor<ShoppingItem>()
            ),
            products: try context.fetchCount(
                FetchDescriptor<Product>()
            ),
            lists: try context.fetchCount(
                FetchDescriptor<ShoppingList>()
            ),
            entries: try context.fetchCount(
                FetchDescriptor<ShoppingListEntry>()
            )
        )
    }
}

private struct PersistenceIDs: Equatable {
    let item: UUID
    let product: UUID
    let list: UUID
    let entry: UUID
}

private struct PersistenceCounts: Equatable {
    let items: Int
    let products: Int
    let lists: Int
    let entries: Int
}
