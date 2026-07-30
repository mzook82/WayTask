import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import WayTask

// These tests record shipped behavior only. Passing assertions involving a
// KD identifier document a current defect; they do not approve that behavior
// or implement the cited WT-032A target decisions.

@MainActor
final class ProductStateDomainCharacterizationTests: XCTestCase {
    // Current behavior: CB-01. Known legacy defect: KD-01.
    // WT-032A target decisions cited for replacement: D-01, D-02, D-33.
    func testCurrentLegacyAddCreatesEntryAndCompatibilityItem()
        throws
    {
        let fixture = try currentFixture(
            "custom-product",
            currentBehaviorIDs: ["CB-01"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-01", "D-02", "D-33"]
        )
        let productID = try recordID(
            "Product",
            in: fixture
        )
        let productName = try stringField(
            "name",
            recordType: "Product",
            in: fixture
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let product = Product(
                id: productID,
                name: productName,
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let list = ShoppingList(
                id: stableID(namespace: 0x0401, index: 1),
                title: "SYNTHETIC_LIST_ADD",
                kind: .weekly,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0),
                isDefault: true
            )
            context.insert(product)
            context.insert(list)
            try context.save()

            let originalProductID = product.id
            let entry = try ShoppingListService()
                .addProductToShopping(
                    product,
                    shoppingListID: list.id,
                    in: context
                )
            let entries = try context.fetch(
                FetchDescriptor<ShoppingListEntry>()
            )
            let items = try context.fetch(
                FetchDescriptor<ShoppingItem>()
            )
            let item = try XCTUnwrap(items.first)

            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(entry.productID, originalProductID)
            XCTAssertEqual(entry.product?.id, originalProductID)
            XCTAssertEqual(entry.shoppingListID, list.id)
            XCTAssertEqual(entry.legacyShoppingItemID, item.id)
            XCTAssertEqual(product.legacyShoppingItemID, item.id)
            XCTAssertFalse(entry.isChecked)
            XCTAssertFalse(item.isCompleted)

            // Adjacent Product identity/lifecycle remains unchanged. The
            // compatibility item is still current authority for completion.
            XCTAssertEqual(product.id, originalProductID)
            XCTAssertEqual(product.name, productName)
            XCTAssertNil(product.deletedAt)
        }
    }

    // Current behavior: CB-02. Known legacy defect: KD-01.
    // WT-032A target decisions cited for replacement: D-01, D-02, D-33.
    func testCurrentLegacyAddToCheckedEntryReopensEntry()
        throws
    {
        let fixture = try currentFixture(
            "flags-11",
            currentBehaviorIDs: ["CB-02"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-01", "D-02", "D-33"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let state = try makeListState(
                fixture: fixture,
                context: context,
                listOccurrence: 0,
                entryOccurrence: 0
            )
            state.entry.quantity = 3
            state.entry.isChecked = true
            state.item.isCompleted = true
            try context.save()

            let originalEntryID = state.entry.id
            let originalItemID = state.item.id
            let originalQuantity = state.entry.quantity
            let returnedEntry = try ShoppingListService()
                .addProductToShopping(
                    state.product,
                    shoppingListID: state.list.id,
                    in: context
                )

            // The existing add API silently performs the reopen; there is no
            // approved explicit Reopen command in the shipped API.
            XCTAssertEqual(returnedEntry.id, originalEntryID)
            XCTAssertFalse(returnedEntry.isChecked)
            XCTAssertFalse(state.item.isCompleted)
            XCTAssertEqual(returnedEntry.legacyShoppingItemID, originalItemID)

            // Adjacent identity, quantity, and record counts do not change.
            XCTAssertEqual(returnedEntry.quantity, originalQuantity)
            XCTAssertEqual(state.product.legacyShoppingItemID, originalItemID)
            XCTAssertNil(state.product.deletedAt)
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingListEntry>()
                ),
                1
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ShoppingItem>()),
                1
            )
        }
    }

    // Current behavior: CB-03. Known legacy defects: KD-01, KD-02.
    // WT-032A target decisions cited for replacement: D-01, D-08, D-10.
    func testCurrentLegacyRemoveFromOneListCompletesSharedCompatibilityItem()
        throws
    {
        let fixture = try currentFixture(
            "multi-list-shared-compatibility",
            currentBehaviorIDs: ["CB-03"],
            knownDefectIDs: ["KD-01", "KD-02"],
            decisionIDs: ["D-01", "D-08", "D-10"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let product = Product(
                id: try recordID("Product", in: fixture),
                legacyShoppingItemID:
                    try recordID("ShoppingItem", in: fixture),
                name: try stringField(
                    "name",
                    recordType: "Product",
                    in: fixture
                ),
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let item = ShoppingItem(
                id: try recordID("ShoppingItem", in: fixture),
                name: product.name,
                isCompleted: false,
                dateAdded: fixedDate(0),
                source: .manual
            )
            let firstList = try makeList(
                fixture: fixture,
                occurrence: 0
            )
            let secondList = try makeList(
                fixture: fixture,
                occurrence: 1
            )
            let firstEntry = ShoppingListEntry(
                id: try recordID(
                    "ShoppingListEntry",
                    occurrence: 0,
                    in: fixture
                ),
                shoppingListID: firstList.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 1,
                isChecked: false,
                createdAt: fixedDate(0),
                sortOrder: 0
            )
            let secondEntry = ShoppingListEntry(
                id: try recordID(
                    "ShoppingListEntry",
                    occurrence: 1,
                    in: fixture
                ),
                shoppingListID: secondList.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 2,
                isChecked: false,
                createdAt: fixedDate(1),
                sortOrder: 1
            )
            context.insert(product)
            context.insert(item)
            context.insert(firstList)
            context.insert(secondList)
            context.insert(firstEntry)
            context.insert(secondEntry)
            try context.save()

            try ShoppingListService().removeProductFromShopping(
                product,
                shoppingListID: firstList.id,
                in: context
            )
            let remainingEntries = try context.fetch(
                FetchDescriptor<ShoppingListEntry>()
            )

            // Requested entry removal occurred for the first list.
            XCTAssertFalse(
                remainingEntries.contains {
                    $0.shoppingListID == firstList.id
                }
            )
            XCTAssertEqual(remainingEntries.count, 1)

            // Current legacy defect: the shared compatibility item consumed
            // by the untouched second list is now globally completed.
            let retained = try XCTUnwrap(remainingEntries.first)
            XCTAssertEqual(retained.id, secondEntry.id)
            XCTAssertEqual(retained.shoppingListID, secondList.id)
            XCTAssertFalse(retained.isChecked)
            XCTAssertEqual(retained.quantity, 2)
            XCTAssertEqual(retained.legacyShoppingItemID, item.id)
            XCTAssertTrue(item.isCompleted)

            // Product identity and library lifecycle are adjacent unchanged
            // state; this is not target list-scoped authority.
            XCTAssertEqual(product.id, try recordID("Product", in: fixture))
            XCTAssertNil(product.deletedAt)
        }
    }

    // Current behavior: CB-04. Known legacy defect: KD-03.
    // WT-032A target decisions cited for replacement: D-09, D-26, D-37.
    func testCurrentLegacyPersistenceAllowsDuplicateLogicalEntries()
        throws
    {
        let fixture = try currentFixture(
            "duplicate-entry",
            currentBehaviorIDs: ["CB-04"],
            knownDefectIDs: ["KD-03"],
            decisionIDs: ["D-09", "D-26", "D-37"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let product = Product(
                id: try recordID("Product", in: fixture),
                legacyShoppingItemID:
                    try recordID("ShoppingItem", in: fixture),
                name: try stringField(
                    "name",
                    recordType: "Product",
                    in: fixture
                ),
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let item = ShoppingItem(
                id: try recordID("ShoppingItem", in: fixture),
                name: product.name,
                isCompleted: false,
                dateAdded: fixedDate(0),
                source: .manual
            )
            let list = try makeList(fixture: fixture, occurrence: 0)
            let first = ShoppingListEntry(
                id: try recordID(
                    "ShoppingListEntry",
                    occurrence: 0,
                    in: fixture
                ),
                shoppingListID: list.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 1,
                isChecked: false,
                createdAt: fixedDate(0),
                sortOrder: 0
            )
            let second = ShoppingListEntry(
                id: try recordID(
                    "ShoppingListEntry",
                    occurrence: 1,
                    in: fixture
                ),
                shoppingListID: list.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 2,
                isChecked: true,
                createdAt: fixedDate(1),
                sortOrder: 1
            )
            context.insert(product)
            context.insert(item)
            context.insert(list)
            context.insert(first)
            context.insert(second)
            try context.save()

            let entries = try context.fetch(
                FetchDescriptor<ShoppingListEntry>()
            ).sorted { $0.id.uuidString < $1.id.uuidString }

            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(Set(entries.map(\.shoppingListID)), [list.id])
            XCTAssertEqual(Set(entries.map(\.productID)), [product.id])
            XCTAssertNotEqual(entries[0].id, entries[1].id)
            XCTAssertEqual(Set(entries.map(\.isChecked)), [false, true])

            // No target uniqueness enforcement was added; adjacent records
            // remain singletons and the shared compatibility state is open.
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                1
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ShoppingItem>()),
                1
            )
            XCTAssertFalse(item.isCompleted)
            XCTAssertNil(product.deletedAt)
        }
    }

    // Current behavior: CB-05. Known legacy defects: KD-10, KD-11.
    // WT-032A target decisions cited: D-06, D-15, D-18, D-19, D-30, D-31.
    func testCurrentLegacyLibraryRemovalRemovesWeeklyButRetainsCompletedRecentAndHistory()
        throws
    {
        let fixture = try currentFixture(
            "tombstone-weekly-completed-recent",
            currentBehaviorIDs: ["CB-05"],
            knownDefectIDs: ["KD-10", "KD-11"],
            decisionIDs: [
                "D-06",
                "D-15",
                "D-18",
                "D-19",
                "D-30",
                "D-31"
            ]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let productID = try recordID("Product", in: fixture)
            let itemID = try recordID("ShoppingItem", in: fixture)
            let productName = try stringField(
                "name",
                recordType: "Product",
                in: fixture
            )
            let product = Product(
                id: productID,
                legacyShoppingItemID: itemID,
                name: productName,
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let item = ShoppingItem(
                id: itemID,
                name: productName,
                isCompleted: false,
                dateAdded: fixedDate(0),
                source: .manual
            )
            let weekly = try makeList(fixture: fixture, occurrence: 0)
            let completed = try makeList(
                fixture: fixture,
                occurrence: 1
            )
            let recent = try makeList(
                fixture: fixture,
                occurrence: 2
            )
            let weeklyEntry = try makeEntry(
                fixture: fixture,
                occurrence: 0,
                list: weekly,
                product: product,
                item: item
            )
            let completedEntry = try makeEntry(
                fixture: fixture,
                occurrence: 1,
                list: completed,
                product: product,
                item: item
            )
            let recentEntry = try makeEntry(
                fixture: fixture,
                occurrence: 2,
                list: recent,
                product: product,
                item: item
            )
            let completedAt = fixedDate(3)
            let history = ProductHistory(
                id: try recordID("ProductHistory", in: fixture),
                productKey:
                    "name:\(productName.lowercased())",
                productName: productName,
                firstAddedDate: fixedDate(0),
                lastAddedDate: fixedDate(1),
                addCount: 1,
                lastSource: .manual,
                lastCompletedDate: completedAt
            )
            context.insert(product)
            context.insert(item)
            context.insert(weekly)
            context.insert(completed)
            context.insert(recent)
            context.insert(weeklyEntry)
            context.insert(completedEntry)
            context.insert(recentEntry)
            context.insert(history)
            try context.save()

            let deletedAt = fixedDate(1)
            try ProductLibraryDeletionService(
                clock: { deletedAt }
            ).delete(product, in: context)
            let entries = try context.fetch(
                FetchDescriptor<ShoppingListEntry>()
            )

            XCTAssertEqual(product.deletedAt, deletedAt)
            XCTAssertEqual(product.updatedAt, deletedAt)
            XCTAssertTrue(item.isCompleted)
            XCTAssertFalse(
                entries.contains {
                    $0.id == weeklyEntry.id
                }
            )
            XCTAssertEqual(
                Set(entries.map(\.id)),
                [completedEntry.id, recentEntry.id]
            )

            // Completed/Recent membership and aggregate history remain under
            // the current legacy behavior; this does not approve that target.
            XCTAssertTrue(entries.allSatisfy(\.isChecked))
            XCTAssertEqual(history.id, try recordID(
                "ProductHistory",
                in: fixture
            ))
            XCTAssertEqual(history.addCount, 1)
            XCTAssertEqual(history.lastCompletedDate, completedAt)
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ProductHistory>()),
                1
            )
        }
    }

    // Current behavior: CB-05, CB-06. Known legacy defect: KD-07.
    // WT-032A target decisions cited: D-15, D-16, D-18, D-32.
    func testCurrentLegacyLibraryRemovalDoesNotBlockActiveSession()
        throws
    {
        let fixture = try currentFixture(
            "tombstone-active-session",
            currentBehaviorIDs: ["CB-05", "CB-06"],
            knownDefectIDs: ["KD-07"],
            decisionIDs: ["D-15", "D-16", "D-18", "D-32"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let state = try makeListState(
                fixture: fixture,
                context: context,
                listOccurrence: 0,
                entryOccurrence: 0
            )
            let session = ShoppingSession(
                id: try recordID("ShoppingSession", in: fixture),
                startedAt: fixedDate(0),
                isActive: true,
                itemIDs: [state.item.id],
                collectedItemIDs: [],
                shoppingListID: state.list.id
            )
            context.insert(session)
            try context.save()
            let originalSessionItems = session.itemIDs

            let deletedAt = fixedDate(1)
            XCTAssertNoThrow(
                try ProductLibraryDeletionService(
                    clock: { deletedAt }
                ).delete(state.product, in: context)
            )

            XCTAssertEqual(state.product.deletedAt, deletedAt)
            XCTAssertTrue(state.item.isCompleted)
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingListEntry>()
                ),
                0
            )

            // Current defect evidence: active session state is neither
            // queried nor blocked or reconciled by Product removal.
            XCTAssertTrue(session.isActive)
            XCTAssertNil(session.finishedAt)
            XCTAssertEqual(session.itemIDs, originalSessionItems)
            XCTAssertEqual(session.shoppingListID, state.list.id)
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingSession>()
                ),
                1
            )
        }
    }

    // Current behavior: CB-07. Known legacy defect: KD-08.
    // WT-032A target decisions cited for replacement: D-17, D-22.
    func testCurrentLegacyBarcodeUpsertRestoresTombstone()
        throws
    {
        let fixture = try currentFixture(
            "history-compatibility-key",
            currentBehaviorIDs: ["CB-07"],
            knownDefectIDs: ["KD-08"],
            decisionIDs: ["D-17", "D-22"]
        )
        let barcode = try stringField(
            "barcode",
            recordType: "ShoppingItem",
            in: fixture
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let productID = stableID(namespace: 0x0407, index: 1)
            let deletedAt = fixedDate(1)
            let product = Product(
                id: productID,
                name: "SYNTHETIC_PRODUCT_BARCODE_OLD",
                barcode: barcode,
                dateAdded: fixedDate(0),
                updatedAt: deletedAt,
                deletedAt: deletedAt,
                source: .barcode
            )
            context.insert(product)
            try context.save()

            let candidate = ProductCandidate(
                id: stableID(namespace: 0x0407, index: 2),
                name: "SYNTHETIC_PRODUCT_BARCODE_RESTORED",
                source: .barcode,
                barcode: barcode
            )
            let restored = try ShoppingListService()
                .upsertRecognizedProduct(
                    candidate,
                    fallbackImageData: nil,
                    in: context
                )

            XCTAssertEqual(restored.id, productID)
            XCTAssertNil(restored.deletedAt)
            XCTAssertEqual(
                restored.name,
                "SYNTHETIC_PRODUCT_BARCODE_RESTORED"
            )
            XCTAssertEqual(restored.barcode, barcode)

            // The implicit scanner restore keeps this a non-catalog Product
            // and does not create a second Product identity.
            XCTAssertNil(restored.catalogProductIDRawValue)
            XCTAssertNil(restored.legacyShoppingItemID)
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                1
            )
        }
    }

    // Current behavior: CB-07. Known legacy defect: KD-08.
    // WT-032A target decisions cited: D-15, D-17, D-18, D-22, D-35.
    func testCurrentLegacyCatalogPersistenceRestoresTombstone()
        throws
    {
        let fixture = try currentFixture(
            "catalog-tombstone",
            currentBehaviorIDs: ["CB-07"],
            knownDefectIDs: ["KD-08"],
            decisionIDs: [
                "D-15",
                "D-17",
                "D-18",
                "D-22",
                "D-35"
            ]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let productID = try recordID("Product", in: fixture)
            let catalogID = try stringField(
                "catalogProductIDRawValue",
                recordType: "Product",
                in: fixture
            )
            let deletedAt = fixedDate(1)
            let product = Product(
                id: productID,
                name: "SYNTHETIC_PRODUCT_CATALOG_OLD",
                dateAdded: fixedDate(0),
                updatedAt: deletedAt,
                deletedAt: deletedAt,
                source: .catalog,
                catalogProductIDRawValue: catalogID,
                catalogDisplayNameSnapshot:
                    "SYNTHETIC_CATALOG_DISPLAY_OLD",
                catalogDisplayLocaleSnapshot: "synthetic-locale",
                catalogCategoryIDSnapshotRawValue:
                    "SYNTHETIC_CATALOG_CATEGORY_OLD",
                catalogCategoryDisplayNameSnapshot:
                    "SYNTHETIC_CATALOG_CATEGORY_DISPLAY_OLD",
                catalogIconKeySnapshot:
                    "SYNTHETIC_CATALOG_ICON_OLD",
                catalogSnapshotUpdatedAt: fixedDate(0)
            )
            context.insert(product)
            try context.save()

            let restoredAt = fixedDate(2)
            let request = CatalogProductSaveRequest(
                productID: ProductID(catalogID),
                displayNameSnapshot:
                    "SYNTHETIC_CATALOG_DISPLAY_RESTORED",
                displayLocaleSnapshot: "synthetic-locale",
                categoryIDSnapshot: ProductCategoryID(
                    "SYNTHETIC_CATALOG_CATEGORY_RESTORED"
                ),
                categoryDisplayNameSnapshot:
                    "SYNTHETIC_CATALOG_CATEGORY_DISPLAY_RESTORED",
                iconKeySnapshot:
                    "SYNTHETIC_CATALOG_ICON_RESTORED",
                imageData: nil,
                source: .catalog
            )
            let outcome = try CatalogProductPersistenceService(
                clock: { restoredAt }
            ).save(request, in: context)
            let restored = try insertedProduct(from: outcome)

            XCTAssertEqual(restored.id, productID)
            XCTAssertNil(restored.deletedAt)
            XCTAssertEqual(restored.updatedAt, restoredAt)
            XCTAssertEqual(restored.catalogProductIDRawValue, catalogID)
            XCTAssertEqual(
                restored.name,
                "SYNTHETIC_CATALOG_DISPLAY_RESTORED"
            )
            XCTAssertEqual(
                restored.catalogSnapshotUpdatedAt,
                restoredAt
            )

            // Existing identity is restored in place; adjacent optional
            // compatibility and barcode identities remain absent.
            XCTAssertNil(restored.legacyShoppingItemID)
            XCTAssertNil(restored.barcode)
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                1
            )
        }
    }

    // Current behavior: CB-08. Known legacy defects: KD-10, KD-11.
    // WT-032A target decisions cited: D-06, D-07, D-19, D-31.
    func testCurrentLegacyHistoryAggregatesByBarcodeThenNormalizedName()
        throws
    {
        let fixture = try currentFixture(
            "history-compatibility-key",
            currentBehaviorIDs: ["CB-08"],
            knownDefectIDs: ["KD-10", "KD-11"],
            decisionIDs: ["D-06", "D-07", "D-19", "D-31"]
        )
        // Current lookup lowercases the requested history key before its
        // case-sensitive comparison, so use the fixture token's current
        // lookup-compatible form while still exercising barcode-first
        // aggregation.
        let barcode = try stringField(
            "barcode",
            recordType: "ShoppingItem",
            occurrence: 0,
            in: fixture
        ).lowercased()
        let firstName = try stringField(
            "name",
            recordType: "ShoppingItem",
            occurrence: 0,
            in: fixture
        )
        let fallbackName = try stringField(
            "name",
            recordType: "ShoppingItem",
            occurrence: 1,
            in: fixture
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let barcodeFirst = ShoppingItem(
                id: try recordID(
                    "ShoppingItem",
                    occurrence: 0,
                    in: fixture
                ),
                name: firstName,
                isCompleted: true,
                barcode: barcode,
                dateAdded: fixedDate(0),
                source: .barcode
            )
            let barcodeSecond = ShoppingItem(
                id: stableID(namespace: 0x0409, index: 1),
                name: "SYNTHETIC_PRODUCT_HISTORY_OTHER_NAME",
                isCompleted: false,
                barcode: "  \(barcode)  ",
                dateAdded: fixedDate(1),
                source: .barcode
            )
            let nameFirst = ShoppingItem(
                id: try recordID(
                    "ShoppingItem",
                    occurrence: 1,
                    in: fixture
                ),
                name: fallbackName,
                isCompleted: false,
                dateAdded: fixedDate(2),
                source: .manual
            )
            let nameSecond = ShoppingItem(
                id: stableID(namespace: 0x0409, index: 2),
                name: "  \(fallbackName.lowercased())  ",
                isCompleted: true,
                dateAdded: fixedDate(3),
                source: .manual
            )
            context.insert(barcodeFirst)
            context.insert(barcodeSecond)
            context.insert(nameFirst)
            context.insert(nameSecond)
            try context.save()

            let service = ShoppingMemoryService()
            let barcodeHistory = try service.recordProductAdded(
                barcodeFirst,
                in: context
            )
            let sameBarcodeHistory = try service.recordProductAdded(
                barcodeSecond,
                in: context
            )
            let nameHistory = try service.recordProductAdded(
                nameFirst,
                in: context
            )
            let sameNameHistory = try service.recordProductAdded(
                nameSecond,
                in: context
            )

            XCTAssertEqual(barcodeHistory.id, sameBarcodeHistory.id)
            XCTAssertEqual(
                barcodeHistory.productKey,
                "barcode:\(barcode)"
            )
            XCTAssertEqual(barcodeHistory.addCount, 2)
            XCTAssertEqual(
                barcodeHistory.firstAddedDate,
                barcodeFirst.dateAdded
            )
            XCTAssertEqual(
                barcodeHistory.lastAddedDate,
                barcodeSecond.dateAdded
            )
            XCTAssertEqual(
                barcodeHistory.lastCompletedDate,
                barcodeFirst.dateAdded
            )

            XCTAssertEqual(nameHistory.id, sameNameHistory.id)
            XCTAssertEqual(
                nameHistory.productKey,
                "name:\(fallbackName.lowercased())"
            )
            XCTAssertEqual(nameHistory.addCount, 2)
            XCTAssertEqual(
                nameHistory.lastCompletedDate,
                nameSecond.dateAdded
            )

            // Four distinct compatibility UUIDs aggregate into only two
            // mutable barcode/name histories, not UUID-first events.
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ProductHistory>()),
                2
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ShoppingItem>()),
                4
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<Product>()),
                0
            )
        }
    }

    // Current behavior: CB-09. Known legacy defect: KD-06.
    // WT-032A target decisions cited: D-12, D-13, D-14, D-28, D-29.
    func testCurrentLegacySessionStartReturnsExistingActiveSession()
        throws
    {
        let fixture = try currentFixture(
            "session-missing-item",
            currentBehaviorIDs: ["CB-09"],
            knownDefectIDs: ["KD-06"],
            decisionIDs: [
                "D-12",
                "D-13",
                "D-14",
                "D-28",
                "D-29"
            ]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let originalItem = ShoppingItem(
                id: stableID(namespace: 0x040A, index: 1),
                name: "SYNTHETIC_PRODUCT_SESSION_ORIGINAL",
                isCompleted: false,
                dateAdded: fixedDate(0),
                source: .manual
            )
            let requestedItem = ShoppingItem(
                id: stableID(namespace: 0x040A, index: 2),
                name: "SYNTHETIC_PRODUCT_SESSION_REQUESTED",
                isCompleted: false,
                dateAdded: fixedDate(1),
                source: .manual
            )
            let originalListID = stableID(
                namespace: 0x040A,
                index: 3
            )
            let requestedListID = stableID(
                namespace: 0x040A,
                index: 4
            )
            let originalStoreID = stableID(
                namespace: 0x040A,
                index: 5
            )
            let active = ShoppingSession(
                id: try recordID("ShoppingSession", in: fixture),
                startedAt: fixedDate(0),
                isActive: true,
                itemIDs: [originalItem.id],
                collectedItemIDs: [],
                shoppingListID: originalListID,
                selectedStoreID: originalStoreID,
                selectedStoreName: "SYNTHETIC_STORE_ORIGINAL",
                selectedStoreLatitude: 0.125,
                selectedStoreLongitude: -0.125
            )
            context.insert(originalItem)
            context.insert(requestedItem)
            context.insert(active)
            try context.save()

            let requestedStore = MapStore(
                id: stableID(namespace: 0x040A, index: 6),
                locationID: nil,
                title: "SYNTHETIC_STORE_REQUESTED",
                coordinate: CLLocationCoordinate2D(
                    latitude: -0.25,
                    longitude: 0.25
                ),
                radius: 175,
                itemNames: [requestedItem.name],
                completedItemNames: [],
                isOpen: true,
                rating: nil,
                storeCategories: [],
                queryEvidenceCategories: [],
                websiteURL: nil,
                sourceType: .debugSeed
            )
            let returned = try ShoppingSessionService()
                .startShopping(
                    with: [requestedItem],
                    shoppingListID: requestedListID,
                    selectedStore: requestedStore,
                    in: context
                )

            XCTAssertEqual(returned.id, active.id)
            XCTAssertTrue(returned.isActive)
            XCTAssertEqual(returned.itemIDs, [originalItem.id])
            XCTAssertFalse(returned.itemIDs.contains(requestedItem.id))

            // New list/store context is not validated or adopted.
            XCTAssertEqual(returned.shoppingListID, originalListID)
            XCTAssertNotEqual(returned.shoppingListID, requestedListID)
            XCTAssertEqual(returned.selectedStoreID, originalStoreID)
            XCTAssertEqual(
                returned.selectedStoreName,
                "SYNTHETIC_STORE_ORIGINAL"
            )
            XCTAssertNil(returned.finishedAt)
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingSession>()
                ),
                1
            )
        }
    }

    // Current behavior: CB-10. Known legacy defect: KD-09.
    // WT-032A target decisions cited for replacement: D-03, D-35.
    func testCurrentSessionCollectionDoesNotMutateListOrHistory()
        throws
    {
        let fixture = try currentFixture(
            "active-session-collected",
            currentBehaviorIDs: ["CB-10"],
            knownDefectIDs: ["KD-09"],
            decisionIDs: ["D-03", "D-35"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let item = ShoppingItem(
                id: try recordID(
                    "ShoppingItem",
                    occurrence: 0,
                    in: fixture
                ),
                name: try stringField(
                    "name",
                    recordType: "ShoppingItem",
                    occurrence: 0,
                    in: fixture
                ),
                isCompleted: false,
                dateAdded: fixedDate(0),
                source: .manual
            )
            let product = Product(
                id: stableID(namespace: 0x040B, index: 1),
                legacyShoppingItemID: item.id,
                name: item.name,
                dateAdded: fixedDate(0),
                updatedAt: fixedDate(0),
                source: .manual
            )
            let list = ShoppingList(
                id: stableID(namespace: 0x040B, index: 2),
                title: "SYNTHETIC_LIST_SESSION_COLLECTION",
                kind: .weekly,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0),
                isDefault: true
            )
            let entry = ShoppingListEntry(
                id: stableID(namespace: 0x040B, index: 3),
                shoppingListID: list.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 2,
                isChecked: false,
                createdAt: fixedDate(0),
                sortOrder: 0
            )
            let history = ProductHistory(
                id: stableID(namespace: 0x040B, index: 4),
                productKey: "name:\(item.name.lowercased())",
                productName: item.name,
                firstAddedDate: fixedDate(0),
                lastAddedDate: fixedDate(0),
                addCount: 4,
                lastSource: .manual,
                lastCompletedDate: nil
            )
            let session = ShoppingSession(
                id: try recordID("ShoppingSession", in: fixture),
                startedAt: fixedDate(0),
                isActive: true,
                itemIDs: [item.id],
                collectedItemIDs: [],
                shoppingListID: list.id
            )
            context.insert(item)
            context.insert(product)
            context.insert(list)
            context.insert(entry)
            context.insert(history)
            context.insert(session)
            try context.save()

            try ShoppingSessionService().markItemCollected(
                item,
                in: session,
                modelContext: context
            )

            XCTAssertEqual(session.collectedItemIDs, [item.id])
            XCTAssertEqual(session.remainingItemCount, 0)
            XCTAssertTrue(session.isActive)
            XCTAssertNil(session.finishedAt)

            // Adjacent list, compatibility, Product, and history state does
            // not reconcile when the session-local line is collected.
            XCTAssertFalse(entry.isChecked)
            XCTAssertEqual(entry.quantity, 2)
            XCTAssertFalse(item.isCompleted)
            XCTAssertNil(product.deletedAt)
            XCTAssertEqual(history.addCount, 4)
            XCTAssertNil(history.lastCompletedDate)
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ProductHistory>()),
                1
            )
        }
    }

    // Current behavior: CB-11. Known legacy defect: KD-09.
    // WT-032A target decisions cited: D-03, D-04, D-35, D-36.
    func testCurrentLegacySessionFinishChangesHeaderWithoutReconciliation()
        throws
    {
        let fixture = try currentFixture(
            "finished-session-no-reconcile",
            currentBehaviorIDs: ["CB-11"],
            knownDefectIDs: ["KD-09"],
            decisionIDs: ["D-03", "D-04", "D-35", "D-36"]
        )

        try withIsolatedContext(caseID: fixture.caseID) { context in
            let state = try makeListState(
                fixture: fixture,
                context: context,
                listOccurrence: 0,
                entryOccurrence: 0
            )
            let history = ProductHistory(
                id: try recordID("ProductHistory", in: fixture),
                productKey:
                    "name:\(state.product.name.lowercased())",
                productName: state.product.name,
                firstAddedDate: fixedDate(0),
                lastAddedDate: fixedDate(0),
                addCount: 1,
                lastSource: .manual,
                lastCompletedDate: nil
            )
            let session = ShoppingSession(
                id: try recordID("ShoppingSession", in: fixture),
                startedAt: fixedDate(0),
                isActive: true,
                itemIDs: [state.item.id],
                collectedItemIDs: [state.item.id],
                shoppingListID: state.list.id
            )
            context.insert(history)
            context.insert(session)
            try context.save()
            let originalItemIDs = session.itemIDs
            let originalCollectedIDs = session.collectedItemIDs

            try ShoppingSessionService().finishShopping(
                session,
                in: context
            )

            XCTAssertFalse(session.isActive)
            XCTAssertNotNil(session.finishedAt)
            XCTAssertEqual(session.itemIDs, originalItemIDs)
            XCTAssertEqual(
                session.collectedItemIDs,
                originalCollectedIDs
            )
            XCTAssertEqual(session.shoppingListID, state.list.id)

            // Current Finish has no WT-032A atomic reconciliation. There is
            // no persisted Shopping Plan state exposed by this API.
            XCTAssertFalse(state.entry.isChecked)
            XCTAssertFalse(state.item.isCompleted)
            XCTAssertNil(state.product.deletedAt)
            XCTAssertEqual(history.addCount, 1)
            XCTAssertNil(history.lastCompletedDate)
            XCTAssertEqual(
                try context.fetchCount(
                    FetchDescriptor<ShoppingListEntry>()
                ),
                1
            )
            XCTAssertEqual(
                try context.fetchCount(FetchDescriptor<ProductHistory>()),
                1
            )
        }
    }

    // MARK: - Test-local assertions and fixture materialization

    private struct ListState {
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

    private func currentFixture(
        _ caseID: String,
        currentBehaviorIDs: [String],
        knownDefectIDs: [String],
        decisionIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ProductStateManifestCase {
        let manifest = try ProductStateManifestLoader
            .loadFromTestBundle().manifest
        let fixture = try XCTUnwrap(
            manifest.cases.first { $0.caseID == caseID },
            file: file,
            line: line
        )

        XCTAssertEqual(
            fixture.expectedCurrentBehavior.expectationKind,
            .currentBehavior,
            file: file,
            line: line
        )
        XCTAssertFalse(
            currentBehaviorIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(knownDefectIDs.isEmpty, file: file, line: line)
        XCTAssertFalse(decisionIDs.isEmpty, file: file, line: line)
        for identifier in currentBehaviorIDs {
            XCTAssertTrue(
                validIdentifier(identifier, prefix: "CB-", range: 1...16),
                file: file,
                line: line
            )
        }
        for identifier in knownDefectIDs {
            XCTAssertTrue(
                validIdentifier(identifier, prefix: "KD-", range: 1...12),
                file: file,
                line: line
            )
        }
        for identifier in decisionIDs {
            XCTAssertTrue(
                validIdentifier(identifier, prefix: "D-", range: 1...37),
                file: file,
                line: line
            )
        }
        return fixture
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

    private func records(
        _ recordType: String,
        in fixture: ProductStateManifestCase
    ) -> [ProductStateManifestRecord] {
        fixture.records.filter { $0.recordType == recordType }
    }

    private func recordID(
        _ recordType: String,
        occurrence: Int = 0,
        in fixture: ProductStateManifestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UUID {
        let matchingRecords = records(recordType, in: fixture)
        guard matchingRecords.indices.contains(occurrence) else {
            XCTFail(
                "Synthetic fixture record is unavailable.",
                file: file,
                line: line
            )
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "domain-record",
                    caseID: fixture.caseID
                )
        }
        return try XCTUnwrap(
            UUID(uuidString: matchingRecords[occurrence].id),
            file: file,
            line: line
        )
    }

    private func stringField(
        _ field: String,
        recordType: String,
        occurrence: Int = 0,
        in fixture: ProductStateManifestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let matchingRecords = records(recordType, in: fixture)
        guard matchingRecords.indices.contains(occurrence) else {
            XCTFail(
                "Synthetic fixture record is unavailable.",
                file: file,
                line: line
            )
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "domain-field-record",
                    caseID: fixture.caseID
                )
        }
        return try XCTUnwrap(
            matchingRecords[occurrence].fields[field]?.stringValue,
            file: file,
            line: line
        )
    }

    private func makeList(
        fixture: ProductStateManifestCase,
        occurrence: Int
    ) throws -> ShoppingList {
        let record = records("ShoppingList", in: fixture)[occurrence]
        let id = try XCTUnwrap(UUID(uuidString: record.id))
        let title = try XCTUnwrap(record.fields["title"]?.stringValue)
        let kindRawValue = try XCTUnwrap(
            record.fields["kindRawValue"]?.stringValue
        )
        let kind = try XCTUnwrap(
            ShoppingListKind(rawValue: kindRawValue)
        )
        return ShoppingList(
            id: id,
            title: title,
            kind: kind,
            createdAt: fixedDate(TimeInterval(occurrence)),
            updatedAt: fixedDate(TimeInterval(occurrence)),
            isDefault: occurrence == 0
        )
    }

    private func makeEntry(
        fixture: ProductStateManifestCase,
        occurrence: Int,
        list: ShoppingList,
        product: Product,
        item: ShoppingItem
    ) throws -> ShoppingListEntry {
        ShoppingListEntry(
            id: try recordID(
                "ShoppingListEntry",
                occurrence: occurrence,
                in: fixture
            ),
            shoppingListID: list.id,
            product: product,
            legacyShoppingItemID: item.id,
            quantity: 1,
            isChecked: occurrence > 0,
            createdAt: fixedDate(TimeInterval(occurrence)),
            sortOrder: Double(occurrence)
        )
    }

    private func makeListState(
        fixture: ProductStateManifestCase,
        context: ModelContext,
        listOccurrence: Int,
        entryOccurrence: Int
    ) throws -> ListState {
        let productID = try recordID("Product", in: fixture)
        let itemID = try recordID("ShoppingItem", in: fixture)
        let productName = try stringField(
            "name",
            recordType: "Product",
            in: fixture
        )
        let product = Product(
            id: productID,
            legacyShoppingItemID: itemID,
            name: productName,
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(0),
            source: .manual
        )
        let item = ShoppingItem(
            id: itemID,
            name: productName,
            isCompleted: false,
            dateAdded: fixedDate(0),
            source: .manual
        )
        let list = try makeList(
            fixture: fixture,
            occurrence: listOccurrence
        )
        let entry = ShoppingListEntry(
            id: try recordID(
                "ShoppingListEntry",
                occurrence: entryOccurrence,
                in: fixture
            ),
            shoppingListID: list.id,
            product: product,
            legacyShoppingItemID: item.id,
            quantity: 1,
            isChecked: false,
            createdAt: fixedDate(0),
            sortOrder: 0
        )
        context.insert(product)
        context.insert(item)
        context.insert(list)
        context.insert(entry)
        try context.save()
        return ListState(
            product: product,
            item: item,
            list: list,
            entry: entry
        )
    }

    private func insertedProduct(
        from outcome: CatalogProductSaveOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Product {
        guard case .inserted(let product) = outcome else {
            XCTFail(
                "Current catalog restore did not return inserted.",
                file: file,
                line: line
            )
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "catalog-restore-outcome",
                    caseID: "catalog-tombstone"
                )
        }
        return product
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
