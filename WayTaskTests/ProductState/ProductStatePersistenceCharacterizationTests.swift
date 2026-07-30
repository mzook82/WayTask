import Foundation
import SwiftData
import XCTest
@testable import WayTask

// These tests record shipped persistence behavior only. Passing assertions
// involving a KD identifier document current legacy behavior; they do not
// approve that behavior or implement the cited WT-032A target decisions.

@MainActor
final class ProductStatePersistenceCharacterizationTests: XCTestCase {
    // Current behavior: CB-01...CB-16. Known legacy defects: KD-01...KD-12.
    // WT-032A target decisions cited for replacement: D-01...D-37.
    func testManifestLoadsAllRequiredCases() throws {
        assertTraceability(
            currentBehaviorIDs: (1...16).map { String(format: "CB-%02d", $0) },
            knownDefectIDs: (1...12).map { String(format: "KD-%02d", $0) },
            decisionIDs: (1...37).map { String(format: "D-%02d", $0) }
        )

        try withOwnedDirectory(caseID: "e05-manifest") { _ in
            let loaded = try ProductStateManifestLoader
                .loadFromTestBundle()
            let sourceData = try ProductStateManifestLoader
                .sourceManifestData()
            let caseIDs = loaded.manifest.cases.map(\.caseID)

            XCTAssertEqual(loaded.manifest.manifestSchemaVersion, 1)
            XCTAssertEqual(
                loaded.manifest.expectationKind,
                .currentBehavior
            )
            XCTAssertEqual(loaded.manifest.cases.count, 19)
            XCTAssertEqual(Set(caseIDs).count, 19)
            XCTAssertEqual(
                Set(caseIDs),
                ProductStateManifestValidator.requiredCaseIDs
            )
            XCTAssertTrue(
                loaded.manifest.cases.allSatisfy {
                    $0.expectedCurrentBehavior.expectationKind
                        == .currentBehavior
                }
            )

            // The E-03 loader performs the strict field, deterministic UUID,
            // timestamp, current-behavior, and privacy-safe validation.
            XCTAssertEqual(loaded.bundledData, sourceData)
            XCTAssertEqual(
                ProductStateSHA256.hexDigest(loaded.bundledData),
                ProductStateSHA256.hexDigest(sourceData)
            )
            XCTAssertNotNil(
                ProductStateCharacterizationSupportError.safeToken(
                    loaded.manifest.manifestID
                )
            )
            XCTAssertNotNil(
                ProductStateCharacterizationSupportError.safeToken(
                    loaded.manifest.syntheticNamespace
                )
            )
        }
    }

    // Current behavior: CB-12. Known legacy defects: KD-01, KD-12.
    // WT-032A target decisions cited: D-01, D-02, D-20, D-33.
    func testCurrentSchemaPersistsAllCheckedCompletedCombinations()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-12"],
            decisionIDs: ["D-01", "D-02", "D-20", "D-33"]
        )
        let manifest = try ProductStateManifestLoader
            .loadFromTestBundle().manifest
        let fixtures = try [
            fixtureCase("flags-00", in: manifest),
            fixtureCase("flags-01", in: manifest),
            fixtureCase("flags-10", in: manifest),
            fixtureCase("flags-11", in: manifest)
        ]
        var expectations: [FlagMatrixExpectation] = []

        try withWorkingCopy(
            caseID: "e05-flags",
            sourceGeneration: .current,
            seed: { context in
                for (index, fixture) in fixtures.enumerated() {
                    let productRecord = try fixtureRecord(
                        "Product",
                        in: fixture
                    )
                    let itemRecord = try fixtureRecord(
                        "ShoppingItem",
                        in: fixture
                    )
                    let listRecord = try fixtureRecord(
                        "ShoppingList",
                        in: fixture
                    )
                    let entryRecord = try fixtureRecord(
                        "ShoppingListEntry",
                        in: fixture
                    )
                    let productID = try recordID(productRecord)
                    let itemID = try recordID(itemRecord)
                    let listID = try recordID(listRecord)
                    let entryID = try recordID(entryRecord)
                    let productName = try stringField(
                        "name",
                        in: productRecord
                    )
                    let isChecked = try boolField(
                        "isChecked",
                        in: entryRecord
                    )
                    let isCompleted = try boolField(
                        "isCompleted",
                        in: itemRecord
                    )
                    let item = ShoppingItem(
                        id: itemID,
                        name: productName,
                        isCompleted: isCompleted,
                        dateAdded: fixedDate(Double(index)),
                        source: .manual
                    )
                    let product = Product(
                        id: productID,
                        legacyShoppingItemID: itemID,
                        name: productName,
                        dateAdded: fixedDate(Double(index)),
                        updatedAt: fixedDate(Double(index)),
                        source: .manual
                    )
                    let list = ShoppingList(
                        id: listID,
                        title: try stringField(
                            "title",
                            in: listRecord
                        ),
                        kind: .weekly,
                        createdAt: fixedDate(Double(index)),
                        updatedAt: fixedDate(Double(index)),
                        isDefault: index == 0
                    )
                    let entry = ShoppingListEntry(
                        id: entryID,
                        shoppingListID: listID,
                        product: product,
                        legacyShoppingItemID: itemID,
                        quantity: 1,
                        isChecked: isChecked,
                        createdAt: fixedDate(Double(index)),
                        sortOrder: Double(index)
                    )
                    context.insert(item)
                    context.insert(product)
                    context.insert(list)
                    context.insert(entry)
                    expectations.append(
                        FlagMatrixExpectation(
                            entryID: entryID,
                            itemID: itemID,
                            isChecked: isChecked,
                            isCompleted: isCompleted
                        )
                    )
                }
            },
            operation: { workingCopy in
                let first = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertFlagMatrix(
                        expectations,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-flags",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertFlagMatrix(
                        expectations,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-flags",
                        in: context
                    )
                }
                try assertSnapshotsEqual(first, reopened)
            }
        )
        XCTAssertEqual(
            Set(
                expectations.map {
                    "\($0.isChecked)-\($0.isCompleted)"
                }
            ),
            ["false-false", "false-true", "true-false", "true-true"]
        )
    }

    // Current behavior: CB-16. Known legacy defects: KD-01, KD-10, KD-11.
    // WT-032A target decisions cited: D-24, D-25, D-28, D-30, D-31, D-33.
    func testV1WorkingCopyMigratesToCurrentSemanticSnapshot()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-16"],
            knownDefectIDs: ["KD-01", "KD-10", "KD-11"],
            decisionIDs: [
                "D-24", "D-25", "D-28", "D-30", "D-31", "D-33"
            ]
        )
        let expected = migrationExpectation(
            namespace: 0x0511,
            generation: .v1
        )

        try withWorkingCopy(
            caseID: "e05-v1-migration",
            sourceGeneration: .v1,
            seed: { context in
                try seedV1(expected, in: context)
            },
            operation: { workingCopy in
                let migrated = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        expected,
                        in: context,
                        caseID: "e05-v1-migration"
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        expected,
                        in: context,
                        caseID: "e05-v1-migration"
                    )
                }
                try assertSnapshotsEqual(migrated, reopened)
            }
        )
    }

    // Current behavior: CB-16. Known legacy defect: KD-01.
    // WT-032A target decisions cited: D-24, D-25, D-33.
    func testV2WorkingCopyMigratesToCurrentSemanticSnapshot()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-16"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-24", "D-25", "D-33"]
        )
        let expected = migrationExpectation(
            namespace: 0x0512,
            generation: .v2
        )

        try withWorkingCopy(
            caseID: "e05-v2-migration",
            sourceGeneration: .v2,
            seed: { context in
                try seedV2(expected, in: context)
            },
            operation: { workingCopy in
                let migrated = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        expected,
                        in: context,
                        caseID: "e05-v2-migration"
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        expected,
                        in: context,
                        caseID: "e05-v2-migration"
                    )
                }
                try assertSnapshotsEqual(migrated, reopened)
            }
        )
    }

    // Current behavior: CB-16. Known legacy defect: KD-01.
    // WT-032A target decisions cited: D-24, D-33.
    func testV3WorkingCopyReopensWithCurrentSemanticSnapshot()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-16"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-24", "D-33"]
        )

        try withWorkingCopy(
            caseID: "e05-v3-reopen",
            sourceGeneration: .v3,
            seed: { context in
                try ProductStateSyntheticCurrentFixture.seed(in: context)
            },
            operation: { workingCopy in
                let first = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try snapshot(
                        caseID: "e05-v3-reopen",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try snapshot(
                        caseID: "e05-v3-reopen",
                        in: context
                    )
                }
                try assertSnapshotsEqual(first, reopened)
                XCTAssertEqual(first.entityCounts["Product"], 1)
                XCTAssertEqual(
                    first.entityCounts["ShoppingListEntry"],
                    1
                )
                XCTAssertEqual(
                    first.entityCounts["ShoppingSession"],
                    1
                )
                XCTAssertEqual(first.entityCounts["GeoLocation"], 1)
            }
        )
    }

    // Current behavior: CB-04. Known legacy defect: KD-03.
    // WT-032A target decisions cited: D-09, D-26, D-37.
    func testCurrentLegacyDuplicateEntriesSurviveReopen()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-04"],
            knownDefectIDs: ["KD-03"],
            decisionIDs: ["D-09", "D-26", "D-37"]
        )
        let fixture = try fixtureCase(
            "duplicate-entry",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )

        try withWorkingCopy(
            caseID: "e05-duplicates",
            sourceGeneration: .current,
            seed: { context in
                try seedDuplicateFixture(fixture, in: context)
            },
            operation: { workingCopy in
                let first = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertDuplicateFixture(fixture, in: context)
                    return try snapshot(
                        caseID: "e05-duplicates",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertDuplicateFixture(fixture, in: context)
                    return try snapshot(
                        caseID: "e05-duplicates",
                        in: context
                    )
                }
                try assertSnapshotsEqual(first, reopened)
            }
        )
    }

    // Current behavior: CB-13, CB-14. Known legacy defect: KD-02.
    // WT-032A target decisions cited: D-24, D-25, D-27, D-33.
    func testStartupRepairReconnectsExistingProductReference()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-14"],
            knownDefectIDs: ["KD-02"],
            decisionIDs: ["D-24", "D-25", "D-27", "D-33"]
        )
        let fixture = try fixtureCase(
            "orphan-existing-product-id",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )
        let entryID = try recordID(
            fixtureRecord("ShoppingListEntry", in: fixture)
        )
        let productID = try recordID(
            fixtureRecord("Product", in: fixture)
        )

        try withWorkingCopy(
            caseID: "e05-repair-existing",
            sourceGeneration: .current,
            seed: { context in
                try seedExistingProductOrphan(
                    fixture,
                    in: context
                )
            },
            operation: { workingCopy in
                let repaired = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    let result = try ShoppingListBackfillService()
                        .ensureDefaultListsAndBackfill(in: context)
                    let entry = try XCTUnwrap(
                        try context.fetch(
                            FetchDescriptor<ShoppingListEntry>()
                        ).first { $0.id == entryID }
                    )
                    XCTAssertEqual(entry.productID, productID)
                    XCTAssertEqual(entry.product?.id, productID)
                    XCTAssertGreaterThanOrEqual(
                        result.repairActionCount,
                        1
                    )
                    XCTAssertEqual(
                        try context.fetchCount(
                            FetchDescriptor<Product>()
                        ),
                        1
                    )
                    return try snapshot(
                        caseID: "e05-repair-existing",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    let entry = try XCTUnwrap(
                        try context.fetch(
                            FetchDescriptor<ShoppingListEntry>()
                        ).first { $0.id == entryID }
                    )
                    XCTAssertEqual(entry.product?.id, productID)
                    return try snapshot(
                        caseID: "e05-repair-existing",
                        in: context
                    )
                }
                try assertSnapshotsEqual(repaired, reopened)
            }
        )
    }

    // Current behavior: CB-13, CB-14. Known legacy defect: KD-02.
    // WT-032A target decisions cited: D-25, D-27, D-30.
    func testStartupRepairDoesNotRecreateMissingProduct()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-14"],
            knownDefectIDs: ["KD-02"],
            decisionIDs: ["D-25", "D-27", "D-30"]
        )
        let fixture = try fixtureCase(
            "orphan-missing-product",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )
        let entryRecord = try fixtureRecord(
            "ShoppingListEntry",
            in: fixture
        )
        let missingProductID = try uuidField(
            "productID",
            in: entryRecord
        )
        let entryID = try recordID(entryRecord)

        try withWorkingCopy(
            caseID: "e05-repair-missing",
            sourceGeneration: .current,
            seed: { context in
                try seedMissingProductOrphan(
                    fixture,
                    in: context
                )
            },
            operation: { workingCopy in
                let repaired = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    _ = try ShoppingListBackfillService()
                        .ensureDefaultListsAndBackfill(in: context)
                    let products = try context.fetch(
                        FetchDescriptor<Product>()
                    )
                    let entry = try XCTUnwrap(
                        try context.fetch(
                            FetchDescriptor<ShoppingListEntry>()
                        ).first { $0.id == entryID }
                    )

                    // Current repair does not fabricate the unavailable UUID.
                    // For an active incomplete compatibility item it creates
                    // a distinct replacement Product and relinks the entry.
                    XCTAssertFalse(
                        products.contains { $0.id == missingProductID }
                    )
                    XCTAssertEqual(products.count, 1)
                    XCTAssertNotNil(entry.product)
                    XCTAssertNotEqual(entry.productID, missingProductID)
                    XCTAssertEqual(entry.productID, entry.product?.id)
                    return try snapshot(
                        caseID: "e05-repair-missing",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    let products = try context.fetch(
                        FetchDescriptor<Product>()
                    )
                    XCTAssertFalse(
                        products.contains { $0.id == missingProductID }
                    )
                    return try snapshot(
                        caseID: "e05-repair-missing",
                        in: context
                    )
                }
                try assertSnapshotsEqual(repaired, reopened)
            }
        )
    }

    // Current behavior: CB-05, CB-08, CB-13, CB-14.
    // Known legacy defects: KD-10, KD-11.
    // WT-032A target decisions cited: D-06, D-07, D-19, D-30, D-31.
    func testStartupRepairPreservesCompletedRecentAndHistoryReferences()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-05", "CB-08", "CB-13", "CB-14"],
            knownDefectIDs: ["KD-10", "KD-11"],
            decisionIDs: ["D-06", "D-07", "D-19", "D-30", "D-31"]
        )
        let fixture = try fixtureCase(
            "completed-recent-only",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )
        let productID = try recordID(
            fixtureRecord("Product", in: fixture)
        )
        let retainedEntryIDs = try fixtureRecords(
            "ShoppingListEntry",
            in: fixture
        ).map(recordID)
        let historyID = stableID(namespace: 0x0519, index: 1)

        try withWorkingCopy(
            caseID: "e05-retained-history",
            sourceGeneration: .current,
            seed: { context in
                try seedCompletedRecentAndHistory(
                    fixture,
                    historyID: historyID,
                    in: context
                )
            },
            operation: { workingCopy in
                let repaired = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    _ = try ShoppingListBackfillService()
                        .ensureDefaultListsAndBackfill(in: context)
                    try assertRetainedHistoricalState(
                        productID: productID,
                        entryIDs: retainedEntryIDs,
                        historyID: historyID,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-retained-history",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertRetainedHistoricalState(
                        productID: productID,
                        entryIDs: retainedEntryIDs,
                        historyID: historyID,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-retained-history",
                        in: context
                    )
                }
                try assertSnapshotsEqual(repaired, reopened)
            }
        )
    }

    // Current behavior: CB-05, CB-13. Known legacy defect: KD-11.
    // WT-032A target decisions cited: D-15, D-18, D-30, D-32.
    func testStartupRepairPreservesTombstoneWithoutResurrection()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-05", "CB-13"],
            knownDefectIDs: ["KD-11"],
            decisionIDs: ["D-15", "D-18", "D-30", "D-32"]
        )
        let fixture = try fixtureCase(
            "tombstone-weekly-completed-recent",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )
        let productID = try recordID(
            fixtureRecord("Product", in: fixture)
        )
        let itemID = try recordID(
            fixtureRecord("ShoppingItem", in: fixture)
        )
        let tombstoneDate = fixedDate(1)

        try withWorkingCopy(
            caseID: "e05-tombstone",
            sourceGeneration: .current,
            seed: { context in
                try seedTombstoneFixture(fixture, in: context)
            },
            operation: { workingCopy in
                let repaired = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    _ = try ShoppingListBackfillService()
                        .ensureDefaultListsAndBackfill(in: context)
                    try assertTombstoneState(
                        productID: productID,
                        itemID: itemID,
                        tombstoneDate: tombstoneDate,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-tombstone",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertTombstoneState(
                        productID: productID,
                        itemID: itemID,
                        tombstoneDate: tombstoneDate,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-tombstone",
                        in: context
                    )
                }
                try assertSnapshotsEqual(repaired, reopened)
            }
        )
    }

    // Current behavior: CB-09, CB-10, CB-11.
    // Known legacy defects: KD-06, KD-09.
    // WT-032A target decisions cited: D-12, D-28, D-29, D-36.
    func testCurrentSessionArraysSurviveReopen() throws {
        assertTraceability(
            currentBehaviorIDs: ["CB-09", "CB-10", "CB-11"],
            knownDefectIDs: ["KD-06", "KD-09"],
            decisionIDs: ["D-12", "D-28", "D-29", "D-36"]
        )
        let manifest = try ProductStateManifestLoader
            .loadFromTestBundle().manifest
        let activeFixture = try fixtureCase(
            "active-session-collected",
            in: manifest
        )
        let finishedFixture = try fixtureCase(
            "finished-session-no-reconcile",
            in: manifest
        )
        let activeExpected = try sessionExpectation(
            activeFixture,
            finishedAt: nil,
            shoppingListID: nil
        )
        let finishedExpected = try sessionExpectation(
            finishedFixture,
            finishedAt: fixedDate(2),
            shoppingListID: recordID(
                fixtureRecord("ShoppingList", in: finishedFixture)
            )
        )

        try withWorkingCopy(
            caseID: "e05-sessions",
            sourceGeneration: .current,
            seed: { context in
                try seedSessionFixtures(
                    activeFixture: activeFixture,
                    finishedFixture: finishedFixture,
                    activeExpected: activeExpected,
                    finishedExpected: finishedExpected,
                    in: context
                )
            },
            operation: { workingCopy in
                let first = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertSessions(
                        [activeExpected, finishedExpected],
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-sessions",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertSessions(
                        [activeExpected, finishedExpected],
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-sessions",
                        in: context
                    )
                }
                try assertSnapshotsEqual(first, reopened)
            }
        )
    }

    // Current behavior: CB-12, CB-15. Known legacy defects: KD-01, KD-12.
    // WT-032A target decisions cited: D-20, D-23, D-33.
    func testSavedLocationRelationshipsSurviveReopen()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12", "CB-15"],
            knownDefectIDs: ["KD-01", "KD-12"],
            decisionIDs: ["D-20", "D-23", "D-33"]
        )
        let fixture = try fixtureCase(
            "location-compatibility",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )
        let locationID = try recordID(
            fixtureRecord("GeoLocation", in: fixture)
        )
        let itemIDs = try fixtureRecords(
            "ShoppingItem",
            in: fixture
        ).map(recordID)

        try withWorkingCopy(
            caseID: "e05-location",
            sourceGeneration: .current,
            seed: { context in
                try seedLocationFixture(fixture, in: context)
            },
            operation: { workingCopy in
                let first = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertLocation(
                        locationID: locationID,
                        itemIDs: itemIDs,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-location",
                        in: context
                    )
                }
                let reopened = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertLocation(
                        locationID: locationID,
                        itemIDs: itemIDs,
                        in: context
                    )
                    return try snapshot(
                        caseID: "e05-location",
                        in: context
                    )
                }
                try assertSnapshotsEqual(first, reopened)
            }
        )
    }

    // Current behavior: CB-13, CB-14. Known legacy defects: KD-02, KD-11.
    // WT-032A target decisions cited: D-24, D-25, D-27, D-30, D-32, D-33.
    func testStartupRepairSecondPassHasIdenticalSemanticDigest()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-14"],
            knownDefectIDs: ["KD-02", "KD-11"],
            decisionIDs: [
                "D-24", "D-25", "D-27", "D-30", "D-32", "D-33"
            ]
        )
        let fixture = try fixtureCase(
            "orphan-existing-product-id",
            in: ProductStateManifestLoader
                .loadFromTestBundle().manifest
        )

        try withWorkingCopy(
            caseID: "e05-repair-idempotent",
            sourceGeneration: .current,
            seed: { context in
                try seedExistingProductOrphan(
                    fixture,
                    in: context
                )
            },
            operation: { workingCopy in
                try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    let firstResult =
                        try ShoppingListBackfillService()
                            .ensureDefaultListsAndBackfill(in: context)
                    let first = try snapshot(
                        caseID: "e05-repair-idempotent",
                        in: context
                    )
                    let secondResult =
                        try ShoppingListBackfillService()
                            .ensureDefaultListsAndBackfill(in: context)
                    let second = try snapshot(
                        caseID: "e05-repair-idempotent",
                        in: context
                    )

                    XCTAssertGreaterThanOrEqual(
                        firstResult.repairActionCount,
                        1
                    )
                    XCTAssertEqual(secondResult.repairActionCount, 0)
                    try assertSnapshotsEqual(first, second)
                }
            }
        )
    }

    // Current behavior: CB-16. Known legacy defect: KD-01.
    // WT-032A target decisions cited: D-24, D-25, D-33, D-34.
    func testMigrationWorkingCopyDoesNotMutateSourceFixture()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-16"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-24", "D-25", "D-33", "D-34"]
        )
        let v1 = migrationExpectation(
            namespace: 0x051A,
            generation: .v1
        )
        let v2 = migrationExpectation(
            namespace: 0x051B,
            generation: .v2
        )

        try withWorkingCopy(
            caseID: "e05-source-v1",
            sourceGeneration: .v1,
            seed: { context in
                try seedV1(v1, in: context)
            },
            operation: { workingCopy in
                _ = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        v1,
                        in: context,
                        caseID: "e05-source-v1"
                    )
                }
            }
        )
        try withWorkingCopy(
            caseID: "e05-source-v2",
            sourceGeneration: .v2,
            seed: { context in
                try seedV2(v2, in: context)
            },
            operation: { workingCopy in
                _ = try withContainer(
                    generation: .current,
                    workingCopy: workingCopy
                ) { context in
                    try assertMigratedFixture(
                        v2,
                        in: context,
                        caseID: "e05-source-v2"
                    )
                }
            }
        )
    }

    // Current behavior: CB-16. Known legacy defect: KD-01.
    // WT-032A target decisions cited: D-24, D-25, D-34.
    func testFailedWorkingCopyOpenDoesNotMutateSourceFixture()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-16"],
            knownDefectIDs: ["KD-01"],
            decisionIDs: ["D-24", "D-25", "D-34"]
        )

        try withWorkingCopy(
            caseID: "e05-failed-open",
            sourceGeneration: .current,
            seed: { context in
                try ProductStateSyntheticCurrentFixture.seed(in: context)
            },
            operation: { workingCopy in
                let components =
                    ProductStateStoreFingerprinting.componentURLs(
                        for: workingCopy.workingStoreURL
                    )
                for component in components where
                    component.role != "store" &&
                    FileManager.default.fileExists(
                        atPath: component.url.path
                    )
                {
                    try FileManager.default.removeItem(at: component.url)
                }
                let invalidStore = Data(
                    "WT032B_SYNTHETIC_INVALID_STORE".utf8
                )
                try invalidStore.write(
                    to: workingCopy.workingStoreURL,
                    options: .atomic
                )

                var openedContainer: ModelContainer?
                var capturedError: Error?
                do {
                    openedContainer = try workingCopy.makeContainer(
                        generation: .current
                    )
                    if let openedContainer {
                        let context = ModelContext(openedContainer)
                        _ = try context.fetchCount(
                            FetchDescriptor<Product>()
                        )
                    }
                } catch {
                    capturedError = error
                }

                XCTAssertNil(openedContainer)
                let error = try XCTUnwrap(capturedError)
                XCTAssertEqual(
                    (error as? LocalizedError)?.errorDescription,
                    "Product State container creation failed [current] for e05-failed-open-working."
                )
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: workingCopy.workingStoreURL.path
                    )
                )
            }
        )
    }

    // MARK: - Owned-store orchestration

    private func withOwnedDirectory<T>(
        caseID: String,
        operation: (ProductStateOwnedTemporaryDirectory) throws -> T
    ) throws -> T {
        var directory: ProductStateOwnedTemporaryDirectory? =
            try ProductStateOwnedTemporaryDirectory(caseID: caseID)
        let root = try XCTUnwrap(directory).rootURL
        defer { try? directory?.cleanup() }

        let result = try operation(try XCTUnwrap(directory))
        try directory?.cleanup()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path)
        )
        directory = nil
        return result
    }

    private func withWorkingCopy(
        caseID: String,
        sourceGeneration: ProductStateSchemaGeneration,
        seed: (ModelContext) throws -> Void,
        operation: (ProductStateWorkingCopy) throws -> Void
    ) throws {
        var sourceLease: ProductStateFileBackedContainerLease? =
            try ProductStateFileBackedContainerLease(
                caseID: "\(caseID)-source",
                generation: sourceGeneration
            )
        let sourceRoot = try XCTUnwrap(sourceLease)
            .ownedDirectory.rootURL
        var sourceContext: ModelContext? = ModelContext(
            try XCTUnwrap(try XCTUnwrap(sourceLease).container)
        )
        var workingCopy: ProductStateWorkingCopy?
        defer {
            sourceContext = nil
            sourceLease?.releasePersistentReferences()
            try? workingCopy?.cleanup()
            try? sourceLease?.cleanup()
        }

        try seed(try XCTUnwrap(sourceContext))
        try sourceContext?.save()
        sourceContext = nil
        sourceLease?.releasePersistentReferences()

        workingCopy = try ProductStateWorkingCopy(
            sourceStoreURL: try XCTUnwrap(sourceLease).storeURL,
            caseID: "\(caseID)-working"
        )
        let workingRoot = try XCTUnwrap(workingCopy)
            .ownedDirectory.rootURL
        let expectedSourceFingerprint = try XCTUnwrap(workingCopy)
            .sourceFingerprint

        try operation(try XCTUnwrap(workingCopy))
        try workingCopy?.verifySourceUnchanged()
        XCTAssertEqual(
            try ProductStateStoreFingerprinting.fingerprint(
                storeURL: try XCTUnwrap(sourceLease).storeURL,
                caseID: caseID
            ),
            expectedSourceFingerprint
        )

        try workingCopy?.cleanup()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workingRoot.path)
        )
        workingCopy = nil
        try sourceLease?.cleanup()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourceRoot.path)
        )
        sourceLease = nil
    }

    private func withContainer<T>(
        generation: ProductStateSchemaGeneration,
        workingCopy: ProductStateWorkingCopy,
        operation: (ModelContext) throws -> T
    ) throws -> T {
        var container: ModelContainer? = try workingCopy.makeContainer(
            generation: generation
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

    // MARK: - Migration fixtures

    private struct MigrationExpectation {
        let generation: ProductStateSchemaGeneration
        let itemID: UUID
        let productID: UUID
        let listID: UUID
        let entryID: UUID
        let historyID: UUID
        let sessionID: UUID
        let locationID: UUID
        let productName: String
        let productImageData: Data
        let catalogProductID: String?
        let catalogDisplayName: String?
        let catalogDisplayLocale: String?
        let catalogCategoryID: String?
        let catalogCategoryDisplayName: String?
        let catalogIconKey: String?
        let catalogUpdatedAt: Date?
    }

    private struct CommonMigrationEntities {
        let item: ShoppingItem
        let list: ShoppingList
    }

    private func migrationExpectation(
        namespace: UInt16,
        generation: ProductStateSchemaGeneration
    ) -> MigrationExpectation {
        let hasCatalog = generation == .v2
        return MigrationExpectation(
            generation: generation,
            itemID: stableID(namespace: namespace, index: 1),
            productID: stableID(namespace: namespace, index: 2),
            listID: stableID(namespace: namespace, index: 3),
            entryID: stableID(namespace: namespace, index: 4),
            historyID: stableID(namespace: namespace, index: 5),
            sessionID: stableID(namespace: namespace, index: 6),
            locationID: stableID(namespace: namespace, index: 7),
            productName: "SYNTHETIC_PRODUCT_MIGRATION_\(generation.rawValue.uppercased())",
            productImageData: Data([0x03, 0x2B, UInt8(namespace & 0xFF)]),
            catalogProductID:
                hasCatalog ? "SYNTHETIC_CATALOG_MIGRATION_V2" : nil,
            catalogDisplayName:
                hasCatalog ? "SYNTHETIC_CATALOG_DISPLAY_V2" : nil,
            catalogDisplayLocale:
                hasCatalog ? "synthetic-locale" : nil,
            catalogCategoryID:
                hasCatalog ? "SYNTHETIC_CATALOG_CATEGORY_V2" : nil,
            catalogCategoryDisplayName:
                hasCatalog ? "SYNTHETIC_CATEGORY_DISPLAY_V2" : nil,
            catalogIconKey:
                hasCatalog ? "SYNTHETIC_CATALOG_ICON_V2" : nil,
            catalogUpdatedAt: hasCatalog ? fixedDate(1) : nil
        )
    }

    private func seedMigrationCommon(
        _ expected: MigrationExpectation,
        in context: ModelContext
    ) -> CommonMigrationEntities {
        let item = ShoppingItem(
            id: expected.itemID,
            name: expected.productName,
            isCompleted: true,
            imageData: Data([0x03, 0x2B, 0x05]),
            barcode: "SYNTHETIC_BARCODE_MIGRATION",
            dateAdded: fixedDate(0),
            source: .manual
        )
        let list = ShoppingList(
            id: expected.listID,
            title: "SYNTHETIC_LIST_MIGRATION",
            kind: .weekly,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(0),
            isDefault: true
        )
        let history = ProductHistory(
            id: expected.historyID,
            productKey: "name:synthetic_product_migration",
            productName: expected.productName,
            firstAddedDate: fixedDate(0),
            lastAddedDate: fixedDate(1),
            addCount: 2,
            lastSource: .manual,
            averageInterval: 86_400,
            lastCompletedDate: fixedDate(1)
        )
        let session = ShoppingSession(
            id: expected.sessionID,
            startedAt: fixedDate(0),
            finishedAt: fixedDate(1),
            isActive: false,
            itemIDs: [expected.itemID],
            collectedItemIDs: [expected.itemID],
            shoppingListID: expected.listID
        )
        let location = GeoLocation(
            id: expected.locationID,
            title: "SYNTHETIC_LOCATION_MIGRATION",
            latitude: 0,
            longitude: 0,
            radius: 100,
            shoppingItems: [item]
        )
        context.insert(item)
        context.insert(list)
        context.insert(history)
        context.insert(session)
        context.insert(location)
        return CommonMigrationEntities(item: item, list: list)
    }

    private func seedV1(
        _ expected: MigrationExpectation,
        in context: ModelContext
    ) throws {
        let common = seedMigrationCommon(expected, in: context)
        let product = WayTaskSchemaV1.Product(
            id: expected.productID,
            legacyShoppingItemID: expected.itemID,
            name: expected.productName,
            imageData: expected.productImageData,
            barcode: "SYNTHETIC_BARCODE_MIGRATION",
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(1),
            sourceRawValue: ProductSource.manual.rawValue
        )
        let entry = WayTaskSchemaV1.ShoppingListEntry(
            id: expected.entryID,
            shoppingListID: common.list.id,
            product: product,
            legacyShoppingItemID: common.item.id,
            quantity: 2,
            isChecked: true,
            createdAt: fixedDate(0),
            sortOrder: 0
        )
        context.insert(product)
        context.insert(entry)
        try context.save()
    }

    private func seedV2(
        _ expected: MigrationExpectation,
        in context: ModelContext
    ) throws {
        let common = seedMigrationCommon(expected, in: context)
        let product = WayTaskSchemaV2.Product(
            id: expected.productID,
            legacyShoppingItemID: expected.itemID,
            name: expected.productName,
            imageData: expected.productImageData,
            barcode: "SYNTHETIC_BARCODE_MIGRATION",
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(1),
            sourceRawValue: ProductSource.manual.rawValue,
            catalogProductIDRawValue: expected.catalogProductID,
            catalogDisplayNameSnapshot: expected.catalogDisplayName,
            catalogDisplayLocaleSnapshot: expected.catalogDisplayLocale,
            catalogCategoryIDSnapshotRawValue:
                expected.catalogCategoryID,
            catalogCategoryDisplayNameSnapshot:
                expected.catalogCategoryDisplayName,
            catalogIconKeySnapshot: expected.catalogIconKey,
            catalogSnapshotUpdatedAt: expected.catalogUpdatedAt
        )
        let entry = WayTaskSchemaV2.ShoppingListEntry(
            id: expected.entryID,
            shoppingListID: common.list.id,
            product: product,
            legacyShoppingItemID: common.item.id,
            quantity: 2,
            isChecked: true,
            createdAt: fixedDate(0),
            sortOrder: 0
        )
        context.insert(product)
        context.insert(entry)
        try context.save()
    }

    private func assertMigratedFixture(
        _ expected: MigrationExpectation,
        in context: ModelContext,
        caseID: String
    ) throws -> ProductStateCanonicalSemanticSnapshot {
        let product = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Product>())
                .first { $0.id == expected.productID }
        )
        let entry = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ShoppingListEntry>())
                .first { $0.id == expected.entryID }
        )
        XCTAssertEqual(product.id, expected.productID)
        XCTAssertEqual(
            product.legacyShoppingItemID,
            expected.itemID
        )
        XCTAssertEqual(product.name, expected.productName)
        XCTAssertEqual(product.imageData, expected.productImageData)
        XCTAssertEqual(
            product.barcode,
            "SYNTHETIC_BARCODE_MIGRATION"
        )
        XCTAssertEqual(product.dateAdded, fixedDate(0))
        XCTAssertEqual(product.updatedAt, fixedDate(1))
        XCTAssertNil(product.deletedAt)
        XCTAssertEqual(
            product.catalogProductIDRawValue,
            expected.catalogProductID
        )
        XCTAssertEqual(
            product.catalogDisplayNameSnapshot,
            expected.catalogDisplayName
        )
        XCTAssertEqual(
            product.catalogDisplayLocaleSnapshot,
            expected.catalogDisplayLocale
        )
        XCTAssertEqual(
            product.catalogCategoryIDSnapshotRawValue,
            expected.catalogCategoryID
        )
        XCTAssertEqual(
            product.catalogCategoryDisplayNameSnapshot,
            expected.catalogCategoryDisplayName
        )
        XCTAssertEqual(
            product.catalogIconKeySnapshot,
            expected.catalogIconKey
        )
        XCTAssertEqual(
            product.catalogSnapshotUpdatedAt,
            expected.catalogUpdatedAt
        )
        XCTAssertEqual(entry.productID, expected.productID)
        XCTAssertEqual(entry.product?.id, expected.productID)
        XCTAssertEqual(entry.legacyShoppingItemID, expected.itemID)
        XCTAssertTrue(entry.isChecked)

        let result = try snapshot(caseID: caseID, in: context)
        XCTAssertEqual(result.entityCounts["Product"], 1)
        XCTAssertEqual(result.entityCounts["ShoppingItem"], 1)
        XCTAssertEqual(
            result.entityCounts["ShoppingListEntry"],
            1
        )
        XCTAssertEqual(result.entityCounts["ProductHistory"], 1)
        XCTAssertEqual(result.entityCounts["ShoppingSession"], 1)
        XCTAssertEqual(result.entityCounts["GeoLocation"], 1)
        let semanticProduct = try semanticRecord(
            kind: "Product",
            id: expected.productID,
            in: result
        )
        XCTAssertEqual(
            semanticProduct.fields["catalogSnapshotFieldCount"],
            .integer(expected.generation == .v2 ? 7 : 0)
        )
        return result
    }

    // MARK: - Current-schema fixture seeding and assertions

    private struct FlagMatrixExpectation {
        let entryID: UUID
        let itemID: UUID
        let isChecked: Bool
        let isCompleted: Bool
    }

    private struct SessionExpectation {
        let sessionID: UUID
        let itemIDs: [UUID]
        let collectedItemIDs: [UUID]
        let isActive: Bool
        let finishedAt: Date?
        let shoppingListID: UUID?
    }

    private func assertFlagMatrix(
        _ expectations: [FlagMatrixExpectation],
        in context: ModelContext
    ) throws {
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let items = try context.fetch(
            FetchDescriptor<ShoppingItem>()
        )
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(items.count, 4)
        for expected in expectations {
            let entry = try XCTUnwrap(
                entries.first { $0.id == expected.entryID }
            )
            let item = try XCTUnwrap(
                items.first { $0.id == expected.itemID }
            )
            XCTAssertEqual(entry.isChecked, expected.isChecked)
            XCTAssertEqual(item.isCompleted, expected.isCompleted)
            XCTAssertEqual(
                entry.legacyShoppingItemID,
                expected.itemID
            )
        }
    }

    private func seedDuplicateFixture(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let productRecord = try fixtureRecord("Product", in: fixture)
        let itemRecord = try fixtureRecord(
            "ShoppingItem",
            in: fixture
        )
        let listRecord = try fixtureRecord(
            "ShoppingList",
            in: fixture
        )
        let entryRecords = fixtureRecords(
            "ShoppingListEntry",
            in: fixture
        )
        let productID = try recordID(productRecord)
        let itemID = try recordID(itemRecord)
        let listID = try recordID(listRecord)
        let productName = try stringField("name", in: productRecord)
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
            isCompleted: try boolField(
                "isCompleted",
                in: itemRecord
            ),
            dateAdded: fixedDate(0),
            source: .manual
        )
        let list = ShoppingList(
            id: listID,
            title: try stringField("title", in: listRecord),
            kind: .weekly,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(0),
            isDefault: true
        )
        context.insert(product)
        context.insert(item)
        context.insert(list)
        for (index, record) in entryRecords.enumerated() {
            context.insert(
                ShoppingListEntry(
                    id: try recordID(record),
                    shoppingListID: listID,
                    product: product,
                    legacyShoppingItemID: itemID,
                    quantity: 1,
                    isChecked: try boolField(
                        "isChecked",
                        in: record
                    ),
                    createdAt: fixedDate(Double(index)),
                    sortOrder: Double(index)
                )
            )
        }
    }

    private func assertDuplicateFixture(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let productID = try recordID(
            fixtureRecord("Product", in: fixture)
        )
        let listID = try recordID(
            fixtureRecord("ShoppingList", in: fixture)
        )
        let expectedEntryIDs = try Set(
            fixtureRecords("ShoppingListEntry", in: fixture)
                .map(recordID)
        )
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        ).filter {
            $0.productID == productID &&
                $0.shoppingListID == listID
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.id)), expectedEntryIDs)
        XCTAssertEqual(Set(entries.map(\.isChecked)), [false, true])
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Product>()),
            1
        )
    }

    private func seedExistingProductOrphan(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let productRecord = try fixtureRecord("Product", in: fixture)
        let itemRecord = try fixtureRecord(
            "ShoppingItem",
            in: fixture
        )
        let listRecord = try fixtureRecord(
            "ShoppingList",
            in: fixture
        )
        let entryRecord = try fixtureRecord(
            "ShoppingListEntry",
            in: fixture
        )
        let productID = try recordID(productRecord)
        let itemID = try recordID(itemRecord)
        let productName = try stringField("name", in: productRecord)
        let item = ShoppingItem(
            id: itemID,
            name: productName,
            isCompleted: false,
            dateAdded: fixedDate(0),
            source: .manual
        )
        let product = Product(
            id: productID,
            legacyShoppingItemID: itemID,
            name: productName,
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(0),
            source: .manual
        )
        let lists = makeDefaultLists(
            weeklyID: try recordID(listRecord),
            namespace: 0x0521
        )
        let entry = ShoppingListEntry(
            id: try recordID(entryRecord),
            shoppingListID: lists.weekly.id,
            product: product,
            legacyShoppingItemID: itemID,
            quantity: 1,
            isChecked: false,
            createdAt: fixedDate(0),
            sortOrder: 0
        )
        entry.product = nil
        entry.productID = productID
        context.insert(item)
        context.insert(product)
        insert(lists: lists, in: context)
        context.insert(entry)
    }

    private func seedMissingProductOrphan(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let itemRecord = try fixtureRecord(
            "ShoppingItem",
            in: fixture
        )
        let listRecord = try fixtureRecord(
            "ShoppingList",
            in: fixture
        )
        let entryRecord = try fixtureRecord(
            "ShoppingListEntry",
            in: fixture
        )
        let itemID = try recordID(itemRecord)
        let missingProductID = try uuidField(
            "productID",
            in: entryRecord
        )
        let productName = try stringField("name", in: itemRecord)
        let item = ShoppingItem(
            id: itemID,
            name: productName,
            isCompleted: false,
            dateAdded: fixedDate(0),
            source: .manual
        )
        let placeholder = Product(
            id: missingProductID,
            legacyShoppingItemID: itemID,
            name: productName,
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(0),
            source: .manual
        )
        let lists = makeDefaultLists(
            weeklyID: try recordID(listRecord),
            namespace: 0x0522
        )
        let entry = ShoppingListEntry(
            id: try recordID(entryRecord),
            shoppingListID: lists.weekly.id,
            product: placeholder,
            legacyShoppingItemID: itemID,
            quantity: 1,
            isChecked: false,
            createdAt: fixedDate(0),
            sortOrder: 0
        )
        entry.product = nil
        entry.productID = missingProductID
        context.insert(item)
        insert(lists: lists, in: context)
        context.insert(entry)
    }

    private func seedCompletedRecentAndHistory(
        _ fixture: ProductStateManifestCase,
        historyID: UUID,
        in context: ModelContext
    ) throws {
        let productRecord = try fixtureRecord("Product", in: fixture)
        let itemRecord = try fixtureRecord(
            "ShoppingItem",
            in: fixture
        )
        let listRecords = fixtureRecords("ShoppingList", in: fixture)
        let entryRecords = fixtureRecords(
            "ShoppingListEntry",
            in: fixture
        )
        let productID = try recordID(productRecord)
        let itemID = try recordID(itemRecord)
        let productName = try stringField("name", in: productRecord)
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
            isCompleted: true,
            dateAdded: fixedDate(0),
            source: .manual
        )
        let weekly = ShoppingList(
            id: stableID(namespace: 0x0523, index: 1),
            title: "Weekly Shopping",
            kind: .weekly,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(0),
            isDefault: true
        )
        let completed = ShoppingList(
            id: try recordID(listRecords[0]),
            title: "Completed",
            kind: .completed,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(0)
        )
        let recent = ShoppingList(
            id: try recordID(listRecords[1]),
            title: "Recent",
            kind: .recent,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(0)
        )
        let history = ProductHistory(
            id: historyID,
            productKey:
                "name:\(productName.lowercased())",
            productName: productName,
            firstAddedDate: fixedDate(0),
            lastAddedDate: fixedDate(3),
            addCount: 2,
            lastSource: .manual,
            lastCompletedDate: fixedDate(3)
        )
        let entries = [
            ShoppingListEntry(
                id: try recordID(entryRecords[0]),
                shoppingListID: completed.id,
                product: product,
                legacyShoppingItemID: itemID,
                isChecked: true,
                createdAt: fixedDate(1),
                sortOrder: 0
            ),
            ShoppingListEntry(
                id: try recordID(entryRecords[1]),
                shoppingListID: recent.id,
                product: product,
                legacyShoppingItemID: itemID,
                isChecked: true,
                createdAt: fixedDate(2),
                sortOrder: 1
            )
        ]
        context.insert(product)
        context.insert(item)
        context.insert(weekly)
        context.insert(completed)
        context.insert(recent)
        context.insert(history)
        entries.forEach(context.insert)
    }

    private func assertRetainedHistoricalState(
        productID: UUID,
        entryIDs: [UUID],
        historyID: UUID,
        in context: ModelContext
    ) throws {
        let products = try context.fetch(FetchDescriptor<Product>())
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let histories = try context.fetch(
            FetchDescriptor<ProductHistory>()
        )
        let item = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ShoppingItem>()).first
        )
        XCTAssertEqual(products.map(\.id), [productID])
        XCTAssertEqual(Set(entries.map(\.id)), Set(entryIDs))
        XCTAssertEqual(
            Set(entries.map(\.shoppingListID)),
            Set(
                lists.filter {
                    $0.kind == .completed || $0.kind == .recent
                }.map(\.id)
            )
        )
        XCTAssertTrue(entries.allSatisfy { $0.productID == productID })
        XCTAssertEqual(histories.map(\.id), [historyID])
        XCTAssertTrue(item.isCompleted)
        XCTAssertFalse(
            entries.contains { entry in
                lists.first { $0.id == entry.shoppingListID }?
                    .kind == .weekly
            }
        )
    }

    private func seedTombstoneFixture(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let productRecord = try fixtureRecord("Product", in: fixture)
        let itemRecord = try fixtureRecord(
            "ShoppingItem",
            in: fixture
        )
        let listRecords = fixtureRecords("ShoppingList", in: fixture)
        let entryRecords = fixtureRecords(
            "ShoppingListEntry",
            in: fixture
        )
        let historyRecord = try fixtureRecord(
            "ProductHistory",
            in: fixture
        )
        let productID = try recordID(productRecord)
        let itemID = try recordID(itemRecord)
        let productName = try stringField("name", in: productRecord)
        let product = Product(
            id: productID,
            legacyShoppingItemID: itemID,
            name: productName,
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(1),
            deletedAt: fixedDate(1),
            source: .manual
        )
        let item = ShoppingItem(
            id: itemID,
            name: productName,
            isCompleted: false,
            dateAdded: fixedDate(0),
            source: .manual
        )
        let lists = [
            ShoppingList(
                id: try recordID(listRecords[0]),
                title: "Weekly Shopping",
                kind: .weekly,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0),
                isDefault: true
            ),
            ShoppingList(
                id: try recordID(listRecords[1]),
                title: "Completed",
                kind: .completed,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0)
            ),
            ShoppingList(
                id: try recordID(listRecords[2]),
                title: "Recent",
                kind: .recent,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0)
            )
        ]
        let history = ProductHistory(
            id: try recordID(historyRecord),
            productKey: try stringField(
                "productKey",
                in: historyRecord
            ),
            productName: productName,
            firstAddedDate: fixedDate(0),
            lastAddedDate: fixedDate(3),
            addCount: 1,
            lastSource: .manual,
            lastCompletedDate: fixedDate(3)
        )
        context.insert(product)
        context.insert(item)
        lists.forEach(context.insert)
        context.insert(history)
        for (index, record) in entryRecords.enumerated() {
            context.insert(
                ShoppingListEntry(
                    id: try recordID(record),
                    shoppingListID: lists[index].id,
                    product: product,
                    legacyShoppingItemID: itemID,
                    isChecked: try boolField(
                        "isChecked",
                        in: record
                    ),
                    createdAt: fixedDate(Double(index)),
                    sortOrder: Double(index)
                )
            )
        }
    }

    private func assertTombstoneState(
        productID: UUID,
        itemID: UUID,
        tombstoneDate: Date,
        in context: ModelContext
    ) throws {
        let product = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Product>())
                .first { $0.id == productID }
        )
        let item = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ShoppingItem>())
                .first { $0.id == itemID }
        )
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        XCTAssertEqual(product.deletedAt, tombstoneDate)
        XCTAssertTrue(product.isDeletedFromLibrary)
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.productID == productID })
        XCTAssertEqual(
            Set(
                entries.compactMap { entry in
                    lists.first { $0.id == entry.shoppingListID }?.kind
                }
            ),
            [.completed, .recent]
        )
        XCTAssertEqual(
            try context.fetchCount(
                FetchDescriptor<ProductHistory>()
            ),
            1
        )
    }

    private func sessionExpectation(
        _ fixture: ProductStateManifestCase,
        finishedAt: Date?,
        shoppingListID: UUID?
    ) throws -> SessionExpectation {
        let record = try fixtureRecord(
            "ShoppingSession",
            in: fixture
        )
        return SessionExpectation(
            sessionID: try recordID(record),
            itemIDs: try uuidArrayField("itemIDs", in: record),
            collectedItemIDs: try uuidArrayField(
                "collectedItemIDs",
                in: record
            ),
            isActive: try boolField("isActive", in: record),
            finishedAt: finishedAt,
            shoppingListID: shoppingListID
        )
    }

    private func seedSessionFixtures(
        activeFixture: ProductStateManifestCase,
        finishedFixture: ProductStateManifestCase,
        activeExpected: SessionExpectation,
        finishedExpected: SessionExpectation,
        in context: ModelContext
    ) throws {
        let activeItems = try fixtureRecords(
            "ShoppingItem",
            in: activeFixture
        ).enumerated().map { index, record in
            ShoppingItem(
                id: try recordID(record),
                name: try stringField("name", in: record),
                isCompleted: try boolField(
                    "isCompleted",
                    in: record
                ),
                dateAdded: fixedDate(Double(index)),
                source: .manual
            )
        }
        let finishedItemRecord = try fixtureRecord(
            "ShoppingItem",
            in: finishedFixture
        )
        let finishedItem = ShoppingItem(
            id: try recordID(finishedItemRecord),
            name: try stringField("name", in: finishedItemRecord),
            isCompleted: try boolField(
                "isCompleted",
                in: finishedItemRecord
            ),
            dateAdded: fixedDate(2),
            source: .manual
        )
        let active = ShoppingSession(
            id: activeExpected.sessionID,
            startedAt: fixedDate(0),
            finishedAt: activeExpected.finishedAt,
            isActive: activeExpected.isActive,
            itemIDs: activeExpected.itemIDs,
            collectedItemIDs: activeExpected.collectedItemIDs,
            shoppingListID: activeExpected.shoppingListID
        )
        let finished = ShoppingSession(
            id: finishedExpected.sessionID,
            startedAt: fixedDate(0),
            finishedAt: finishedExpected.finishedAt,
            isActive: finishedExpected.isActive,
            itemIDs: finishedExpected.itemIDs,
            collectedItemIDs: finishedExpected.collectedItemIDs,
            shoppingListID: finishedExpected.shoppingListID
        )
        activeItems.forEach(context.insert)
        context.insert(finishedItem)
        context.insert(active)
        context.insert(finished)
    }

    private func assertSessions(
        _ expectations: [SessionExpectation],
        in context: ModelContext
    ) throws {
        let sessions = try context.fetch(
            FetchDescriptor<ShoppingSession>()
        )
        XCTAssertEqual(sessions.count, expectations.count)
        for expected in expectations {
            let session = try XCTUnwrap(
                sessions.first { $0.id == expected.sessionID }
            )
            XCTAssertEqual(session.itemIDs, expected.itemIDs)
            XCTAssertEqual(
                session.collectedItemIDs,
                expected.collectedItemIDs
            )
            XCTAssertEqual(session.isActive, expected.isActive)
            XCTAssertEqual(session.finishedAt, expected.finishedAt)
            XCTAssertEqual(
                session.shoppingListID,
                expected.shoppingListID
            )
        }
    }

    private func seedLocationFixture(
        _ fixture: ProductStateManifestCase,
        in context: ModelContext
    ) throws {
        let itemRecords = fixtureRecords(
            "ShoppingItem",
            in: fixture
        )
        let locationRecord = try fixtureRecord(
            "GeoLocation",
            in: fixture
        )
        let items = try itemRecords.enumerated().map { index, record in
            ShoppingItem(
                id: try recordID(record),
                name: try stringField("name", in: record),
                isCompleted: try boolField(
                    "isCompleted",
                    in: record
                ),
                dateAdded: fixedDate(Double(index)),
                source: .manual
            )
        }
        let location = GeoLocation(
            id: try recordID(locationRecord),
            title: try stringField("title", in: locationRecord),
            latitude: 0,
            longitude: 0,
            radius: 100,
            shoppingItems: items
        )
        items.forEach(context.insert)
        context.insert(location)
    }

    private func assertLocation(
        locationID: UUID,
        itemIDs: [UUID],
        in context: ModelContext
    ) throws {
        let location = try XCTUnwrap(
            try context.fetch(FetchDescriptor<GeoLocation>())
                .first { $0.id == locationID }
        )
        XCTAssertEqual(
            Set(location.shoppingItems.map(\.id)),
            Set(itemIDs)
        )
        let byID = Dictionary(
            uniqueKeysWithValues:
                location.shoppingItems.map { ($0.id, $0) }
        )
        XCTAssertFalse(try XCTUnwrap(byID[itemIDs[0]]).isCompleted)
        XCTAssertTrue(try XCTUnwrap(byID[itemIDs[1]]).isCompleted)
        XCTAssertEqual(location.latitude, 0)
        XCTAssertEqual(location.longitude, 0)
    }

    private struct DefaultLists {
        let weekly: ShoppingList
        let completed: ShoppingList
        let recent: ShoppingList
    }

    private func makeDefaultLists(
        weeklyID: UUID,
        namespace: UInt16
    ) -> DefaultLists {
        DefaultLists(
            weekly: ShoppingList(
                id: weeklyID,
                title: "Weekly Shopping",
                kind: .weekly,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0),
                isDefault: true
            ),
            completed: ShoppingList(
                id: stableID(namespace: namespace, index: 1),
                title: "Completed",
                kind: .completed,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0)
            ),
            recent: ShoppingList(
                id: stableID(namespace: namespace, index: 2),
                title: "Recent",
                kind: .recent,
                createdAt: fixedDate(0),
                updatedAt: fixedDate(0)
            )
        )
    }

    private func insert(
        lists: DefaultLists,
        in context: ModelContext
    ) {
        context.insert(lists.weekly)
        context.insert(lists.completed)
        context.insert(lists.recent)
    }

    // MARK: - Snapshot, manifest, and traceability assertions

    private func snapshot(
        caseID: String,
        in context: ModelContext
    ) throws -> ProductStateCanonicalSemanticSnapshot {
        let result = try ProductStateCanonicalSnapshotBuilder
            .makeCurrentSnapshot(caseID: caseID, in: context)
        XCTAssertEqual(result.formatVersion, 1)
        XCTAssertTrue(result.syntheticData)
        XCTAssertFalse(result.records.isEmpty)
        return result
    }

    private func assertSnapshotsEqual(
        _ lhs: ProductStateCanonicalSemanticSnapshot,
        _ rhs: ProductStateCanonicalSemanticSnapshot
    ) throws {
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(
            try lhs.canonicalJSONData(),
            try rhs.canonicalJSONData()
        )
        XCTAssertEqual(
            try lhs.sha256Digest(),
            try rhs.sha256Digest()
        )
    }

    private func semanticRecord(
        kind: String,
        id: UUID,
        in snapshot: ProductStateCanonicalSemanticSnapshot
    ) throws -> ProductStateSemanticRecord {
        try XCTUnwrap(
            snapshot.records.first {
                $0.entityKind == kind && $0.stableID == id
            }
        )
    }

    private func fixtureCase(
        _ caseID: String,
        in manifest: ProductStateCurrentBehaviorManifest
    ) throws -> ProductStateManifestCase {
        try XCTUnwrap(
            manifest.cases.first { $0.caseID == caseID }
        )
    }

    private func fixtureRecords(
        _ recordType: String,
        in fixture: ProductStateManifestCase
    ) -> [ProductStateManifestRecord] {
        fixture.records.filter { $0.recordType == recordType }
    }

    private func fixtureRecord(
        _ recordType: String,
        occurrence: Int = 0,
        in fixture: ProductStateManifestCase
    ) throws -> ProductStateManifestRecord {
        let records = fixtureRecords(recordType, in: fixture)
        guard records.indices.contains(occurrence) else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e05-record",
                    caseID: fixture.caseID
                )
        }
        return records[occurrence]
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
            let rawValue = record.fields[field],
            case .boolean(let value) = rawValue
        else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e05-bool-field",
                    caseID: nil
                )
        }
        return value
    }

    private func uuidField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> UUID {
        try XCTUnwrap(
            UUID(uuidString: try stringField(field, in: record))
        )
    }

    private func uuidArrayField(
        _ field: String,
        in record: ProductStateManifestRecord
    ) throws -> [UUID] {
        guard
            let rawValue = record.fields[field],
            case .array(let values) = rawValue
        else {
            throw ProductStateCharacterizationSupportError
                .manifestValidationFailed(
                    code: "e05-uuid-array-field",
                    caseID: nil
                )
        }
        return try values.map { value in
            try XCTUnwrap(
                value.stringValue.flatMap(UUID.init(uuidString:))
            )
        }
    }

    private func assertTraceability(
        currentBehaviorIDs: [String],
        knownDefectIDs: [String],
        decisionIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(currentBehaviorIDs.isEmpty, file: file, line: line)
        XCTAssertFalse(knownDefectIDs.isEmpty, file: file, line: line)
        XCTAssertFalse(decisionIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(
            currentBehaviorIDs.allSatisfy {
                validIdentifier($0, prefix: "CB-", range: 1...16)
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            knownDefectIDs.allSatisfy {
                validIdentifier($0, prefix: "KD-", range: 1...12)
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            decisionIDs.allSatisfy {
                validIdentifier($0, prefix: "D-", range: 1...37)
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
