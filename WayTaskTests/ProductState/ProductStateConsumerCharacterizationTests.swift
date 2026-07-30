import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import WayTask

// These tests record shipped cross-surface consumer behavior only. Passing
// assertions involving a KD identifier document current legacy behavior; they
// do not approve that behavior or implement the cited WT-032A decisions.

@MainActor
final class ProductStateConsumerCharacterizationTests: XCTestCase {
    // Current behavior: CB-12. Known legacy defects: KD-01, KD-04,
    // KD-05, KD-12.
    // WT-032A target decisions cited: D-01, D-11, D-12, D-20, D-33.
    func testCurrentPlanInputExcludesCompletedCompatibilityItems()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-04", "KD-05", "KD-12"],
            decisionIDs: ["D-01", "D-11", "D-12", "D-20", "D-33"]
        )

        try withIsolatedContext(caseID: "e06-plan-input") { context in
            let states = try seedFlagMatrix(in: context)
            try assertFourFlagCombinations(states)
            let incompleteIDs = sortedIDs(
                states
                    .filter { !$0.item.isCompleted }
                    .map(\.item.id)
            )
            let completedIDs = Set(
                states
                    .filter(\.item.isCompleted)
                    .map(\.item.id)
            )
            let productIDsBefore = sortedIDs(
                states.map(\.product.id)
            )
            let request = syntheticRequest(
                itemID: try XCTUnwrap(states.first?.item.id),
                itemName: try XCTUnwrap(states.first?.item.name)
            )

            let plan = ShoppingPlan(
                id: stableID(namespace: 0x0601, index: 1),
                request: request,
                items: states.map(\.item),
                stores: [],
                buyingOptions: [],
                shoppingTripCoverages: [],
                generatedAt: fixedDate(2)
            )

            XCTAssertEqual(
                sortedIDs(plan.items.map(\.id)),
                incompleteIDs
            )
            XCTAssertFalse(
                plan.items.contains {
                    completedIDs.contains($0.id)
                }
            )
            XCTAssertEqual(
                sortedIDs(
                    try context.fetch(
                        FetchDescriptor<Product>()
                    ).map(\.id)
                ),
                productIDsBefore
            )
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingListEntry>()
                ),
                4
            )
            try assertFourFlagCombinations(states)

            // Current ShoppingPlan is an in-memory compatibility snapshot.
            // It has no durable source-list revision or exact entry-ID set.
            let currentFields = Set(
                Mirror(reflecting: plan).children.compactMap(\.label)
            )
            XCTAssertFalse(currentFields.contains("sourceListRevision"))
            XCTAssertFalse(currentFields.contains("sourceEntryIDs"))
            XCTAssertFalse(currentFields.contains("listRevision"))
        }
    }

    // Current behavior: CB-12. Known legacy defects: KD-01, KD-05,
    // KD-12.
    // WT-032A target decisions cited: D-01, D-12, D-13, D-14,
    // D-20, D-33.
    func testCurrentTripAndContextUseCompatibilityCompletion()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-05", "KD-12"],
            decisionIDs: [
                "D-01", "D-12", "D-13", "D-14", "D-20", "D-33"
            ]
        )

        try withIsolatedContext(caseID: "e06-trip-context") { context in
            let states = try seedFlagMatrix(in: context)
            try assertFourFlagCombinations(states)
            let items = states.map(\.item)
            let incompleteIDs = sortedIDs(
                items.filter { !$0.isCompleted }.map(\.id)
            )
            let completedIDs = Set(
                items.filter(\.isCompleted).map(\.id)
            )
            let matcher = ShoppingIntentMatcher()
            let store = syntheticStore(
                id: stableID(namespace: 0x0602, index: 1),
                itemNames: items.map(\.name)
            )
            let request = matcher.request(
                for: items,
                in: .grocery,
                fallbackID: stableID(namespace: 0x0602, index: 2)
            )

            XCTAssertEqual(
                sortedIDs(matcher.eligibleItems(from: items).map(\.id)),
                incompleteIDs
            )
            XCTAssertFalse(
                matcher.eligibleItems(from: items).contains {
                    completedIDs.contains($0.id)
                }
            )

            let coverages = ShoppingTripService(
                intentMatcher: matcher
            ).coverage(
                for: items,
                stores: [store],
                request: request,
                userCoordinate: store.coordinate
            )
            XCTAssertEqual(
                sortedIDs(
                    coverages.flatMap(\.matchedItems).map(\.id)
                ),
                incompleteIDs
            )
            XCTAssertFalse(
                coverages.flatMap(\.matchedItems).contains {
                    completedIDs.contains($0.id)
                }
            )

            let contextItems = states.map { state in
                ShoppingContextItem(
                    id: state.item.id,
                    name: state.item.name,
                    isCompleted: state.item.isCompleted,
                    productHints: ["SYNTHETIC_HINT"]
                )
            }
            let shoppingContext = ShoppingContext(
                currentLocation: nil,
                activeShoppingListItems: contextItems,
                nearbyStores: [
                    ShoppingContextStore(
                        id: store.id,
                        name: store.title,
                        coordinate: ShoppingCoordinate(
                            store.coordinate
                        ),
                        matchingItemNames: states
                            .filter { !$0.item.isCompleted }
                            .map(\.item.name),
                        isFavorite: false,
                        websiteURL: nil
                    )
                ],
                selectedInterests: [],
                timeOfDay: fixedDate(2),
                dayOfWeek: 2,
                recentSearches: [],
                favoriteStores: [],
                availableProductHints: ["SYNTHETIC_HINT"]
            )
            let decision = DecisionEngine().evaluate(
                mission: .completeShoppingList,
                context: shoppingContext
            )

            XCTAssertTrue(shoppingContext.hasActiveShoppingItems)
            XCTAssertEqual(
                shoppingContext.activeShoppingListItems.count,
                4
            )
            XCTAssertEqual(
                decision.outcome,
                .shoppingListItemsNearby
            )
            XCTAssertEqual(
                sortedIDs(decision.relatedItemIDs),
                incompleteIDs
            )
            XCTAssertFalse(
                decision.relatedItemIDs.contains {
                    completedIDs.contains($0)
                }
            )
            try assertFourFlagCombinations(states)
        }
    }

    // Current behavior: CB-12. Known legacy defects: KD-01, KD-12.
    // WT-032A target decisions cited: D-01, D-12, D-20, D-23, D-33.
    func testCurrentMapAndStoreInputsUseCompatibilityCompletion()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-12"],
            decisionIDs: ["D-01", "D-12", "D-20", "D-23", "D-33"]
        )

        try withIsolatedContext(caseID: "e06-map-store") { context in
            let states = try seedFlagMatrix(in: context)
            try assertFourFlagCombinations(states)
            let items = states.map(\.item)
            let incomplete = items.filter { !$0.isCompleted }
            let completed = items.filter(\.isCompleted)
            let incompleteIDs = sortedIDs(incomplete.map(\.id))
            let incompleteNames = incomplete.map(\.name).sorted()
            let completedNames = completed.map(\.name).sorted()
            let location = GeoLocation(
                id: stableID(namespace: 0x0603, index: 1),
                title: "SYNTHETIC_LOCATION_MAP_INPUT",
                latitude: 0,
                longitude: 0,
                radius: 200,
                storeCategory: .grocery,
                addressText: nil,
                notes: nil,
                sourceType: .userGenerated,
                shoppingItems: items
            )
            context.insert(location)
            try context.save()

            let engine = StoreResolutionEngine(
                searchService: MapKitStoreSearchService(),
                cacheDuration: 120,
                minimumRefreshInterval: 1.5
            )
            let intents = engine.intents(for: items)
            XCTAssertEqual(
                intents.flatMap(\.itemNames).sorted(),
                incompleteNames
            )
            XCTAssertFalse(
                intents.flatMap(\.itemNames).contains {
                    completedNames.contains($0)
                }
            )

            let localStores = LocalStoreSearchService()
                .fallbackStores(
                    around: CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                    shoppingItems: incompleteNames,
                    storeCategories: [.grocery]
                )
            XCTAssertEqual(localStores.count, 1)
            XCTAssertEqual(
                localStores.first?.itemNames.sorted(),
                incompleteNames
            )
            XCTAssertFalse(
                localStores.flatMap(\.itemNames).contains {
                    completedNames.contains($0)
                }
            )

            let mapViewModel = MapViewModel()
            mapViewModel.update(
                locations: [location],
                shoppingItems: items
            )
            XCTAssertEqual(
                mapViewModel.stores.first?.itemNames.sorted(),
                incompleteNames
            )
            XCTAssertEqual(
                mapViewModel.stores.first?
                    .completedItemNames.sorted(),
                completedNames
            )
            XCTAssertEqual(
                sortedIDs(mapViewModel.products.map(\.id)),
                incompleteIDs
            )
            XCTAssertEqual(location.shoppingItems.count, 4)
            try assertFourFlagCombinations(states)
        }
    }

    // Current behavior: CB-12. Known legacy defects: KD-01, KD-12.
    // WT-032A target decisions cited: D-01, D-19, D-20, D-23,
    // D-33.
    func testCurrentSavedLocationFilteringUsesCompatibilityCompletion()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-12"],
            decisionIDs: ["D-01", "D-19", "D-20", "D-23", "D-33"]
        )
        let fixture = try currentFixture("location-compatibility")

        try withIsolatedContext(caseID: "e06-saved-location") {
            context in
            let itemRecords = records(
                "ShoppingItem",
                in: fixture
            )
            XCTAssertEqual(itemRecords.count, 2)
            let activeRecord = try XCTUnwrap(
                itemRecords.first {
                    (try? boolField("isCompleted", in: $0)) == false
                }
            )
            let completedRecord = try XCTUnwrap(
                itemRecords.first {
                    (try? boolField("isCompleted", in: $0)) == true
                }
            )
            let locationRecord = try record(
                "GeoLocation",
                in: fixture
            )
            let activeItem = ShoppingItem(
                id: try recordID(activeRecord),
                name: try stringField("name", in: activeRecord),
                isCompleted: false,
                category: "groceries",
                dateAdded: fixedDate(0),
                source: .manual
            )
            let completedItem = ShoppingItem(
                id: try recordID(completedRecord),
                name: try stringField(
                    "name",
                    in: completedRecord
                ),
                isCompleted: true,
                category: "groceries",
                dateAdded: fixedDate(0),
                source: .manual
            )
            let location = GeoLocation(
                id: try recordID(locationRecord),
                title: try stringField("title", in: locationRecord),
                latitude: 0,
                longitude: 0,
                radius: 200,
                storeCategory: .grocery,
                addressText: nil,
                notes: nil,
                sourceType: .userGenerated,
                shoppingItems: [activeItem, completedItem]
            )
            context.insert(activeItem)
            context.insert(completedItem)
            context.insert(location)
            try context.save()

            let stores = StoreResolutionEngine.savedStores(
                from: [location]
            )
            let store = try XCTUnwrap(stores.first)
            XCTAssertEqual(stores.count, 1)
            XCTAssertEqual(store.locationID, location.id)
            XCTAssertEqual(store.itemNames, [activeItem.name])
            XCTAssertEqual(
                store.completedItemNames,
                [completedItem.name]
            )

            let mapViewModel = MapViewModel()
            mapViewModel.update(
                locations: [location],
                shoppingItems: [activeItem, completedItem]
            )
            XCTAssertEqual(
                mapViewModel.products.map(\.id),
                [activeItem.id]
            )
            XCTAssertFalse(
                mapViewModel.products.contains {
                    $0.id == completedItem.id
                }
            )

            // The saved location remains a consumer relationship. Filtering
            // neither creates Product authority nor mutates the relationship.
            XCTAssertEqual(
                Set(location.shoppingItems.map(\.id)),
                Set([activeItem.id, completedItem.id])
            )
            XCTAssertFalse(activeItem.isCompleted)
            XCTAssertTrue(completedItem.isCompleted)
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                0
            )
        }
    }

    // Current behavior: CB-15. Known legacy defect: KD-12.
    // WT-032A target decisions cited: D-20, D-21, D-23.
    func testCurrentGeofenceNotificationPayloadRoundTripsLegacySnapshot()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-15"],
            knownDefectIDs: ["KD-12"],
            decisionIDs: ["D-20", "D-21", "D-23"]
        )

        try withIsolatedContext(caseID: "e06-geofence-payload") {
            context in
            let states = try seedFlagMatrix(in: context)
            let activeStates = states.filter {
                !$0.item.isCompleted
            }
            let candidate = ShoppingGeofenceCandidate(
                id: stableID(namespace: 0x0605, index: 1),
                locationID: stableID(namespace: 0x0605, index: 2),
                title: "SYNTHETIC_LOCATION_NOTIFICATION",
                coordinate: CLLocationCoordinate2D(
                    latitude: 0,
                    longitude: 0
                ),
                radius: 200,
                itemNames: activeStates.map(\.item.name),
                itemIDs: activeStates.map(\.item.id),
                shoppingListID: activeStates.first?.list.id,
                sourceType: DataSourceType.userGenerated.rawValue,
                distanceMeters: 125,
                notificationType: "syntheticCurrentGeofence"
            )
            let originalProductIDs = sortedIDs(
                states.map(\.product.id)
            )
            let payload = ShoppingGeofencePayload(
                candidate: candidate
            )
            let identifier = payload.identifier
            let decoded = try XCTUnwrap(
                ShoppingGeofencePayload(identifier: identifier)
            )

            XCTAssertEqual(decoded.identifier, identifier)
            XCTAssertEqual(decoded.storeID, candidate.id)
            XCTAssertEqual(decoded.locationID, candidate.locationID)
            XCTAssertEqual(decoded.title, candidate.title)
            XCTAssertEqual(decoded.itemNames, candidate.itemNames)
            XCTAssertEqual(decoded.itemIDs, candidate.itemIDs)
            XCTAssertEqual(
                decoded.shoppingListID,
                candidate.shoppingListID
            )
            XCTAssertEqual(decoded.sourceType, candidate.sourceType)
            XCTAssertEqual(
                decoded.distanceMeters,
                candidate.distanceMeters
            )
            XCTAssertEqual(
                decoded.coordinate?.latitude,
                candidate.coordinate.latitude
            )
            XCTAssertEqual(
                decoded.coordinate?.longitude,
                candidate.coordinate.longitude
            )
            XCTAssertEqual(
                decoded.notificationType,
                candidate.notificationType
            )

            let userInfo = decoded.notificationUserInfo
            XCTAssertEqual(
                userInfo["storeID"],
                candidate.id.uuidString
            )
            XCTAssertEqual(
                userInfo["geoLocationID"],
                candidate.locationID?.uuidString
            )
            XCTAssertEqual(
                userInfo["shoppingListID"],
                candidate.shoppingListID?.uuidString
            )
            XCTAssertEqual(
                userInfo["matchedShoppingItemIDs"],
                candidate.itemIDs.map(\.uuidString)
                    .joined(separator: ",")
            )
            XCTAssertEqual(
                userInfo["matchedItemNames"],
                candidate.itemNames.joined(separator: ", ")
            )
            XCTAssertEqual(
                userInfo["notificationType"],
                candidate.notificationType
            )
            XCTAssertEqual(userInfo["latitude"], "0.0")
            XCTAssertEqual(userInfo["longitude"], "0.0")
            XCTAssertEqual(userInfo["opensTripMode"], "false")

            // The current payload exposes compatibility ShoppingItem IDs, not
            // Product UUID authority or a durable list revision.
            XCTAssertNil(userInfo["productID"])
            XCTAssertNil(userInfo["matchedProductIDs"])
            XCTAssertNil(userInfo["listRevision"])
            XCTAssertNil(
                ShoppingGeofencePayload(
                    identifier: "SYNTHETIC_INVALID_PAYLOAD"
                )
            )
            XCTAssertEqual(
                sortedIDs(
                    try context.fetch(
                        FetchDescriptor<Product>()
                    ).map(\.id)
                ),
                originalProductIDs
            )
            try assertFourFlagCombinations(states)

            // The concrete notification and Core Location services are not
            // invoked: this test stops at their shipped pure payload/userInfo
            // boundary and therefore schedules no notification or geofence.
        }
    }

    // Current behavior: CB-01, CB-05, CB-07, CB-14.
    // Known legacy defects: KD-08, KD-12.
    // WT-032A target decisions cited: D-19, D-20, D-21, D-22,
    // D-23, D-33.
    func testCatalogCustomAndStaleIdentitiesRemainDistinguishable()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-01", "CB-05", "CB-07", "CB-14"],
            knownDefectIDs: ["KD-08", "KD-12"],
            decisionIDs: [
                "D-19", "D-20", "D-21", "D-22", "D-23", "D-33"
            ]
        )
        let activeFixture = try currentFixture("catalog-active")
        let tombstoneFixture = try currentFixture(
            "catalog-tombstone"
        )
        let customFixture = try currentFixture("custom-product")
        let missingSessionFixture = try currentFixture(
            "session-missing-item"
        )

        try withIsolatedContext(caseID: "e06-consumer-identities") {
            context in
            let active = try makeProduct(from: activeFixture)
            let tombstone = try makeProduct(
                from: tombstoneFixture
            )
            let custom = try makeProduct(from: customFixture)
            let missingSessionRecord = try record(
                "ShoppingSession",
                in: missingSessionFixture
            )
            let unavailableItemIDs = try uuidArrayField(
                "itemIDs",
                in: missingSessionRecord
            )
            let session = ShoppingSession(
                id: try recordID(missingSessionRecord),
                startedAt: fixedDate(0),
                finishedAt: nil,
                isActive: true,
                itemIDs: unavailableItemIDs,
                collectedItemIDs: [],
                shoppingListID: nil
            )

            let staleItem = ShoppingItem(
                id: stableID(namespace: 0x0606, index: 1),
                name: "SYNTHETIC_PRODUCT_STALE_REFERENCE",
                isCompleted: false,
                category: "groceries",
                dateAdded: fixedDate(0),
                source: .manual,
                catalogProductIDRawValue:
                    "SYNTHETIC_CATALOG_STALE_REFERENCE",
                catalogCategoryIDRawValue:
                    "SYNTHETIC_CATALOG_STALE_CATEGORY"
            )
            let staleList = ShoppingList(
                id: stableID(namespace: 0x0606, index: 2),
                title: "SYNTHETIC_LIST_STALE_REFERENCE",
                kind: .weekly,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0),
                isDefault: false
            )
            let missingProductID = stableID(
                namespace: 0x0606,
                index: 3
            )
            let placeholder = Product(
                id: missingProductID,
                legacyShoppingItemID: staleItem.id,
                name: staleItem.name,
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let staleEntry = ShoppingListEntry(
                id: stableID(namespace: 0x0606, index: 4),
                shoppingListID: staleList.id,
                product: placeholder,
                legacyShoppingItemID: staleItem.id,
                quantity: 1,
                isChecked: false,
                createdAt: fixedDate(0),
                sortOrder: 0
            )
            staleEntry.product = nil
            staleEntry.productID = missingProductID

            context.insert(active)
            context.insert(tombstone)
            context.insert(custom)
            context.insert(session)
            context.insert(staleItem)
            context.insert(staleList)
            context.insert(staleEntry)
            try context.save()

            XCTAssertTrue(active.isCatalogLinked)
            XCTAssertFalse(active.isDeletedFromLibrary)
            XCTAssertNotNil(active.catalogProductID)
            XCTAssertTrue(tombstone.isCatalogLinked)
            XCTAssertTrue(tombstone.isDeletedFromLibrary)
            XCTAssertNotNil(tombstone.catalogProductID)
            XCTAssertFalse(custom.isCatalogLinked)
            XCTAssertFalse(custom.isDeletedFromLibrary)
            XCTAssertNil(custom.catalogProductID)

            let visibleProducts = try context.fetch(
                FetchDescriptor<Product>(
                    predicate: #Predicate { product in
                        product.deletedAt == nil
                    }
                )
            )
            XCTAssertEqual(
                Set(visibleProducts.map(\.id)),
                Set([active.id, custom.id])
            )
            XCTAssertFalse(
                visibleProducts.contains {
                    $0.id == tombstone.id
                }
            )

            let fallback = ProductKnowledgeIconResolver
                .fallbackSystemName
            XCTAssertEqual(
                ProductShoppingThumbnailPresentation(
                    product: active
                ).fallbackSystemName,
                fallback
            )
            XCTAssertEqual(
                ProductShoppingThumbnailPresentation(
                    product: tombstone
                ).fallbackSystemName,
                fallback
            )
            XCTAssertEqual(
                ProductShoppingThumbnailPresentation(
                    product: custom
                ).fallbackSystemName,
                fallback
            )

            let activeCatalogID =
                active.catalogProductIDRawValue
            let tombstoneCatalogID =
                tombstone.catalogProductIDRawValue
            let tombstoneDate = tombstone.deletedAt
            let resolver = ShoppingItemCatalogResolver(products: [])
            XCTAssertNil(resolver.iconKey(for: active))
            XCTAssertNil(resolver.iconKey(for: tombstone))
            XCTAssertNil(resolver.iconKey(for: custom))
            XCTAssertNil(
                resolver.resolve(
                    productIDRawValue:
                        staleItem.catalogProductIDRawValue
                )
            )

            resolver.hydrate(
                [staleItem],
                products: [active, tombstone, custom],
                entries: [staleEntry]
            )
            XCTAssertNil(staleItem.catalogProductIDRawValue)
            XCTAssertNil(staleItem.catalogCategoryIDRawValue)
            XCTAssertNil(staleItem.catalogSubcategoryIDRawValue)
            XCTAssertNil(staleEntry.product)
            XCTAssertEqual(staleEntry.productID, missingProductID)
            XCTAssertFalse(
                try context.fetch(
                    FetchDescriptor<Product>()
                ).contains {
                    $0.id == missingProductID
                }
            )

            XCTAssertEqual(session.itemIDs, unavailableItemIDs)
            XCTAssertTrue(
                unavailableItemIDs.allSatisfy { unavailableID in
                    !((try? context.fetch(
                        FetchDescriptor<ShoppingItem>()
                    )) ?? []).contains {
                        $0.id == unavailableID
                    }
                }
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                3
            )
            XCTAssertEqual(
                active.catalogProductIDRawValue,
                activeCatalogID
            )
            XCTAssertEqual(
                tombstone.catalogProductIDRawValue,
                tombstoneCatalogID
            )
            XCTAssertEqual(tombstone.deletedAt, tombstoneDate)
            XCTAssertTrue(tombstone.isDeletedFromLibrary)
        }
    }

    // MARK: - Isolated state and deterministic fixture materialization

    private struct FlagFixtureState {
        let caseID: String
        let product: Product
        let item: ShoppingItem
        let list: ShoppingList
        let entry: ShoppingListEntry
    }

    private func withIsolatedContext<T>(
        caseID: String,
        _ operation: (ModelContext) throws -> T
    ) throws -> T {
        var container: ModelContainer? =
            try ProductStateTestContainerFactory.makeInMemoryCurrent(
                caseID: caseID
            )
        var context: ModelContext? = ModelContext(
            try XCTUnwrap(container)
        )
        defer {
            context = nil
            container = nil
        }
        return try operation(try XCTUnwrap(context))
    }

    private func seedFlagMatrix(
        in context: ModelContext
    ) throws -> [FlagFixtureState] {
        let manifest = try ProductStateManifestLoader
            .loadFromTestBundle().manifest
        let caseIDs = [
            "flags-00",
            "flags-01",
            "flags-10",
            "flags-11"
        ]
        var states: [FlagFixtureState] = []

        for (index, caseID) in caseIDs.enumerated() {
            let fixture = try XCTUnwrap(
                manifest.cases.first { $0.caseID == caseID }
            )
            XCTAssertEqual(
                fixture.expectedCurrentBehavior.expectationKind,
                .currentBehavior
            )
            let productRecord = try record(
                "Product",
                in: fixture
            )
            let itemRecord = try record(
                "ShoppingItem",
                in: fixture
            )
            let listRecord = try record(
                "ShoppingList",
                in: fixture
            )
            let entryRecord = try record(
                "ShoppingListEntry",
                in: fixture
            )
            let product = Product(
                id: try recordID(productRecord),
                legacyShoppingItemID: try uuidField(
                    "legacyShoppingItemID",
                    in: productRecord
                ),
                name: try stringField("name", in: productRecord),
                category: "groceries",
                dateAdded: fixedDate(TimeInterval(index)),
                updatedAt: fixedDate(TimeInterval(index)),
                source: .manual
            )
            let item = ShoppingItem(
                id: try recordID(itemRecord),
                name: try stringField("name", in: itemRecord),
                isCompleted: try boolField(
                    "isCompleted",
                    in: itemRecord
                ),
                category: "groceries",
                dateAdded: fixedDate(TimeInterval(index)),
                source: .manual
            )
            let kind = try XCTUnwrap(
                ShoppingListKind(
                    rawValue: try stringField(
                        "kindRawValue",
                        in: listRecord
                    )
                )
            )
            let list = ShoppingList(
                id: try recordID(listRecord),
                title: try stringField("title", in: listRecord),
                kind: kind,
                createdAt: fixedDate(TimeInterval(index)),
                updatedAt: fixedDate(TimeInterval(index)),
                isDefault: false
            )
            let entry = ShoppingListEntry(
                id: try recordID(entryRecord),
                shoppingListID: list.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 1,
                isChecked: try boolField(
                    "isChecked",
                    in: entryRecord
                ),
                createdAt: fixedDate(TimeInterval(index)),
                sortOrder: Double(index)
            )
            context.insert(product)
            context.insert(item)
            context.insert(list)
            context.insert(entry)
            states.append(
                FlagFixtureState(
                    caseID: caseID,
                    product: product,
                    item: item,
                    list: list,
                    entry: entry
                )
            )
        }
        try context.save()
        return states
    }

    private func makeProduct(
        from fixture: ProductStateManifestCase
    ) throws -> Product {
        let productRecord = try record("Product", in: fixture)
        let catalogProductID = productRecord
            .fields["catalogProductIDRawValue"]?.stringValue
        let hasDeletionDate = productRecord.optionalFieldStates
            .contains {
                $0.field == "deletedAt" &&
                    $0.presence == .present
            }
        return Product(
            id: try recordID(productRecord),
            legacyShoppingItemID: nil,
            name: try stringField("name", in: productRecord),
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(0),
            deletedAt: hasDeletionDate ? fixedDate(1) : nil,
            source: catalogProductID == nil ? .manual : .catalog,
            catalogProductIDRawValue: catalogProductID,
            catalogDisplayNameSnapshot:
                productRecord
                    .fields["catalogDisplayNameSnapshot"]?
                    .stringValue,
            catalogDisplayLocaleSnapshot:
                productRecord
                    .fields["catalogDisplayLocaleSnapshot"]?
                    .stringValue,
            catalogCategoryIDSnapshotRawValue:
                productRecord
                    .fields[
                        "catalogCategoryIDSnapshotRawValue"
                    ]?.stringValue,
            catalogCategoryDisplayNameSnapshot:
                productRecord
                    .fields[
                        "catalogCategoryDisplayNameSnapshot"
                    ]?.stringValue,
            catalogIconKeySnapshot:
                productRecord
                    .fields["catalogIconKeySnapshot"]?
                    .stringValue,
            catalogSnapshotUpdatedAt:
                productRecord
                    .fields["catalogSnapshotUpdatedAt"] == nil
                    ? nil
                    : fixedDate(0)
        )
    }

    private func syntheticRequest(
        itemID: UUID,
        itemName: String
    ) -> ShoppingStoreSuggestionRequest {
        ShoppingStoreSuggestionRequest(
            itemID: itemID,
            itemName: itemName,
            itemCategory: "groceries",
            storeCategories: [.grocery],
            searchTerms: [itemName],
            intentProfile: nil
        )
    }

    private func syntheticStore(
        id: UUID,
        itemNames: [String]
    ) -> MapStore {
        MapStore(
            id: id,
            locationID: nil,
            title: "SYNTHETIC_STORE_CONSUMER",
            coordinate: CLLocationCoordinate2D(
                latitude: 0,
                longitude: 0
            ),
            radius: 200,
            itemNames: itemNames,
            completedItemNames: [],
            isOpen: true,
            rating: 4,
            storeCategories: [.grocery],
            queryEvidenceCategories: [.grocery],
            websiteURL: nil,
            sourceType: .local
        )
    }

    private func assertFourFlagCombinations(
        _ states: [FlagFixtureState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            states.map(\.caseID),
            ["flags-00", "flags-01", "flags-10", "flags-11"],
            file: file,
            line: line
        )
        let combinations = states.map { state in
            "\(state.entry.isChecked ? 1 : 0)\(state.item.isCompleted ? 1 : 0)"
        }
        XCTAssertEqual(
            combinations.sorted(),
            ["00", "01", "10", "11"],
            file: file,
            line: line
        )
        for state in states {
            XCTAssertEqual(
                state.entry.productID,
                state.product.id,
                file: file,
                line: line
            )
            XCTAssertEqual(
                state.entry.product?.id,
                state.product.id,
                file: file,
                line: line
            )
            XCTAssertEqual(
                state.entry.legacyShoppingItemID,
                state.item.id,
                file: file,
                line: line
            )
        }
    }

    // MARK: - Manifest access through the strict E-03 loader

    private func currentFixture(
        _ caseID: String
    ) throws -> ProductStateManifestCase {
        let manifest = try ProductStateManifestLoader
            .loadFromTestBundle().manifest
        let fixture = try XCTUnwrap(
            manifest.cases.first { $0.caseID == caseID }
        )
        XCTAssertEqual(
            fixture.expectedCurrentBehavior.expectationKind,
            .currentBehavior
        )
        return fixture
    }

    private func records(
        _ recordType: String,
        in fixture: ProductStateManifestCase
    ) -> [ProductStateManifestRecord] {
        fixture.records.filter { $0.recordType == recordType }
    }

    private func record(
        _ recordType: String,
        occurrence: Int = 0,
        in fixture: ProductStateManifestCase
    ) throws -> ProductStateManifestRecord {
        let matching = records(recordType, in: fixture)
        guard matching.indices.contains(occurrence) else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e06-record",
                    caseID: fixture.caseID
                )
        }
        return matching[occurrence]
    }

    private func recordID(
        _ record: ProductStateManifestRecord
    ) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: record.id))
    }

    private func stringField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> String {
        try XCTUnwrap(record.fields[field]?.stringValue)
    }

    private func boolField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> Bool {
        guard
            let value = record.fields[field],
            case .boolean(let result) = value
        else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e06-bool-field",
                    caseID: nil
                )
        }
        return result
    }

    private func uuidField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> UUID {
        try XCTUnwrap(
            UUID(
                uuidString: try stringField(
                    field,
                    in: record
                )
            )
        )
    }

    private func uuidArrayField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> [UUID] {
        guard
            let value = record.fields[field],
            let identifiers = value.stringArrayValue
        else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e06-uuid-array-field",
                    caseID: nil
                )
        }
        return try identifiers.map { identifier in
            try XCTUnwrap(UUID(uuidString: identifier))
        }
    }

    // MARK: - Traceability and deterministic values

    private func assertTraceability(
        currentBehaviorIDs: [String],
        knownDefectIDs: [String],
        decisionIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            currentBehaviorIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(
            knownDefectIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(
            decisionIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            currentBehaviorIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "CB-",
                    range: 1...16
                )
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            knownDefectIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "KD-",
                    range: 1...12
                )
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            decisionIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "D-",
                    range: 1...37
                )
            },
            file: file,
            line: line
        )
    }

    private func validIdentifier(
        _ value: String,
        prefix: String,
        range: ClosedRange<Int>
    ) -> Bool {
        guard value.hasPrefix(prefix) else {
            return false
        }
        let suffix = value.dropFirst(prefix.count)
        guard let number = Int(suffix), range.contains(number) else {
            return false
        }
        return suffix.count == 2
    }

    private func sortedIDs(_ values: [UUID]) -> [UUID] {
        ProductStateSyntheticValues.sortedUUIDs(values)
    }

    private func stableID(
        namespace: UInt16,
        index: UInt64
    ) -> UUID {
        ProductStateSyntheticValues.uuid(
            namespace: namespace,
            index: index
        )
    }

    private func fixedDate(_ day: TimeInterval) -> Date {
        ProductStateSyntheticValues.date(
            secondsAfterEpoch: day * 86_400
        )
    }
}
