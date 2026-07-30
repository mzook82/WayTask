import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import WayTask

// These tests record observational timing for shipped behavior only. Timing
// values are evidence, not thresholds, and do not approve current KD behavior
// or implement the cited WT-032A decisions.

@MainActor
final class ProductStatePerformanceBaselineTests: XCTestCase {
    private let warmUpCount = 3
    private let sampleCount = 30

    // Current behavior: CB-01, CB-05, CB-09, CB-12, CB-13.
    // Known legacy defects: KD-01, KD-03, KD-05, KD-06, KD-12.
    // WT-032A target decisions cited: D-08-D-12, D-18, D-24,
    // D-35-D-37.
    func testFunctionalProfileProjectionCorrectness()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: [
                "CB-01", "CB-05", "CB-09", "CB-12", "CB-13"
            ],
            knownDefectIDs: [
                "KD-01", "KD-03", "KD-05", "KD-06", "KD-12"
            ],
            decisionIDs: [
                "D-08", "D-09", "D-10", "D-11", "D-12",
                "D-18", "D-24", "D-35", "D-36", "D-37"
            ]
        )

        let profile = ProductStateFixtureProfile.functional
        let container = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e08-functional")
        let fixture = try seedFixture(
            profile: profile,
            container: container,
            caseID: "e08-functional"
        )
        try assertProfileCounts(fixture, profile: profile)

        let selected = selectedListProjection(
            fixture: fixture,
            listID: try XCTUnwrap(fixture.lists.first?.id),
            includeChecked: false
        )
        XCTAssertEqual(selected.count, 4)
        XCTAssertTrue(selected.allSatisfy { !$0.isCompleted })

        let activeProducts = try fixture.context.fetch(
            FetchDescriptor<Product>(
                predicate: #Predicate { product in
                    product.deletedAt == nil
                }
            )
        )
        XCTAssertEqual(activeProducts.count, 19)
        XCTAssertEqual(
            fixture.products.filter(\.isDeletedFromLibrary).count,
            6
        )

        let plan = ShoppingPlan(
            id: stableID(namespace: 0x08F0, index: 1),
            request: syntheticRequest(
                item: try XCTUnwrap(fixture.items.first)
            ),
            items: fixture.items,
            stores: [],
            buyingOptions: [],
            shoppingTripCoverages: [],
            generatedAt: fixedDate(1)
        )
        XCTAssertEqual(plan.items.count, 13)
        XCTAssertTrue(plan.items.allSatisfy { !$0.isCompleted })

        let activeSession = try ShoppingSessionService()
            .activeSession(in: fixture.context)
        XCTAssertEqual(activeSession?.id, fixture.session.id)
        XCTAssertEqual(activeSession?.itemIDs.count, 25)

        let firstSnapshot =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e08-functional",
                    in: fixture.context
                )
        let secondSnapshot =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e08-functional",
                    in: fixture.context
                )
        XCTAssertEqual(
            try firstSnapshot.canonicalJSONData(),
            try secondSnapshot.canonicalJSONData()
        )
        XCTAssertEqual(
            try firstSnapshot.sha256Digest(),
            try secondSnapshot.sha256Digest()
        )
        XCTAssertEqual(firstSnapshot.entityCounts["Product"], 25)
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingList"],
            3
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingListEntry"],
            20
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingItem"],
            25
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["ProductHistory"],
            10
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingSession"],
            1
        )
    }

    // Current behavior: CB-01-CB-04. Known legacy defects: KD-02,
    // KD-03. WT-032A target decisions cited: D-08-D-10, D-37.
    func testReferenceSelectedListProjectionBaseline()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: [
                "CB-01", "CB-02", "CB-03", "CB-04"
            ],
            knownDefectIDs: ["KD-02", "KD-03"],
            decisionIDs: ["D-08", "D-09", "D-10", "D-37"]
        )

        let fixture = try makeReferenceFixture(
            caseID: "e08-selected-list"
        )
        let identity = try semanticIdentity(
            fixture,
            caseID: "e08-selected-list"
        )
        let selectedListID = try XCTUnwrap(
            fixture.lists.first?.id
        )
        var observedCounts: [Int] = []
        var observedFirstIDs: [UUID?] = []

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let projection = selectedListProjection(
                    fixture: fixture,
                    listID: selectedListID,
                    includeChecked: false
                )
                observedCounts.append(projection.count)
                observedFirstIDs.append(projection.first?.id)
            }

        assertStatistics(statistics)
        XCTAssertEqual(Set(observedCounts), [250])
        XCTAssertEqual(
            Set(observedFirstIDs.compactMap { $0 }).count,
            1
        )
        try recordMeasurement(
            caseID: "e08-selected-list",
            operation: "selected_list_projection",
            statistics: statistics,
            identity: identity,
            traceability: Traceability(
                currentBehaviorIDs: [
                    "CB-01", "CB-02", "CB-03", "CB-04"
                ],
                knownDefectIDs: ["KD-02", "KD-03"],
                decisionIDs: ["D-08", "D-09", "D-10", "D-37"]
            )
        )
    }

    // Current behavior: CB-05. Known legacy defect: KD-11.
    // WT-032A target decision cited: D-18.
    func testReferenceLibraryFilteringBaseline()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-05"],
            knownDefectIDs: ["KD-11"],
            decisionIDs: ["D-18"]
        )

        let fixture = try makeReferenceFixture(
            caseID: "e08-library-filtering"
        )
        let identity = try semanticIdentity(
            fixture,
            caseID: "e08-library-filtering"
        )
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { product in
                product.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.id)]
        )
        var observedCounts: [Int] = []
        var observedFirstIDs: [UUID?] = []

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let products = try fixture.context.fetch(descriptor)
                observedCounts.append(products.count)
                observedFirstIDs.append(products.first?.id)
            }

        assertStatistics(statistics)
        XCTAssertEqual(Set(observedCounts), [1_500])
        XCTAssertEqual(
            Set(observedFirstIDs.compactMap { $0 }).count,
            1
        )
        XCTAssertEqual(
            fixture.products.filter(\.isDeletedFromLibrary).count,
            500
        )
        try recordMeasurement(
            caseID: "e08-library-filtering",
            operation: "product_library_filtering",
            statistics: statistics,
            identity: identity,
            traceability: Traceability(
                currentBehaviorIDs: ["CB-05"],
                knownDefectIDs: ["KD-11"],
                decisionIDs: ["D-18"]
            )
        )
    }

    // Current behavior: CB-12. Known legacy defects: KD-01,
    // KD-04, KD-05. WT-032A target decisions cited: D-11, D-12.
    func testReferencePlanInputProjectionBaseline()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-12"],
            knownDefectIDs: ["KD-01", "KD-04", "KD-05"],
            decisionIDs: ["D-11", "D-12"]
        )

        let fixture = try makeReferenceFixture(
            caseID: "e08-plan-input"
        )
        let identity = try semanticIdentity(
            fixture,
            caseID: "e08-plan-input"
        )
        let request = syntheticRequest(
            item: try XCTUnwrap(fixture.items.first)
        )
        var observedCounts: [Int] = []
        var lastSignature: String?

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let plan = ShoppingPlan(
                    id: stableID(namespace: 0x08F3, index: 1),
                    request: request,
                    items: fixture.items,
                    stores: [],
                    buyingOptions: [],
                    shoppingTripCoverages: [],
                    generatedAt: fixedDate(2)
                )
                observedCounts.append(plan.items.count)
                lastSignature = plan.contentSignature
            }

        assertStatistics(statistics)
        XCTAssertEqual(Set(observedCounts), [1_000])
        XCTAssertNotNil(lastSignature)
        XCTAssertEqual(
            fixture.items.filter(\.isCompleted).count,
            1_000
        )
        try recordMeasurement(
            caseID: "e08-plan-input",
            operation: "shopping_plan_input_projection",
            statistics: statistics,
            identity: identity,
            traceability: Traceability(
                currentBehaviorIDs: ["CB-12"],
                knownDefectIDs: ["KD-01", "KD-04", "KD-05"],
                decisionIDs: ["D-11", "D-12"]
            )
        )
    }

    // Current behavior: CB-09. Known legacy defect: KD-06.
    // WT-032A target decisions cited: D-35-D-37.
    func testReferenceActiveSessionLookupBaseline()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-09"],
            knownDefectIDs: ["KD-06"],
            decisionIDs: ["D-35", "D-36", "D-37"]
        )

        let fixture = try makeReferenceFixture(
            caseID: "e08-active-session"
        )
        let identity = try semanticIdentity(
            fixture,
            caseID: "e08-active-session"
        )
        let service = ShoppingSessionService()
        var observedIDs: [UUID?] = []
        var observedLineCounts: [Int] = []

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let session = try service.activeSession(
                    in: fixture.context
                )
                observedIDs.append(session?.id)
                observedLineCounts.append(
                    session?.itemIDs.count ?? 0
                )
            }

        assertStatistics(statistics)
        XCTAssertEqual(
            Set(observedIDs.compactMap { $0 }),
            [fixture.session.id]
        )
        XCTAssertEqual(Set(observedLineCounts), [500])
        try recordMeasurement(
            caseID: "e08-active-session",
            operation: "active_session_lookup",
            statistics: statistics,
            identity: identity,
            traceability: Traceability(
                currentBehaviorIDs: ["CB-09"],
                knownDefectIDs: ["KD-06"],
                decisionIDs: ["D-35", "D-36", "D-37"]
            )
        )
    }

    // Current behavior: CB-13, CB-14, CB-16. Known legacy defect:
    // KD-03. WT-032A target decisions cited: D-24, D-37.
    func testReferenceStartupRepairBaseline()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-14", "CB-16"],
            knownDefectIDs: ["KD-03"],
            decisionIDs: ["D-24", "D-37"]
        )

        let caseID = "e08-startup-repair"
        let lease = try ProductStateFileBackedContainerLease(
            caseID: caseID,
            generation: .current
        )
        var fixture: SeededFixture? = try seedFixture(
            profile: .reference,
            container: try XCTUnwrap(lease.container),
            caseID: caseID
        )
        defer {
            fixture = nil
            lease.releasePersistentReferences()
            try? lease.cleanup()
        }
        let seeded = try XCTUnwrap(fixture)
        try assertProfileCounts(seeded, profile: .reference)

        let beforeIdentity = try semanticIdentity(
            seeded,
            caseID: caseID
        )
        let beforeStoreSize = try storeFootprint(
            storeURL: lease.storeURL,
            caseID: caseID
        )
        var observedRepairCounts: [Int] = []

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let result = try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(
                        in: seeded.context
                    )
                observedRepairCounts.append(
                    result.repairActionCount
                )
            }

        assertStatistics(statistics)
        XCTAssertEqual(Set(observedRepairCounts), [0])
        try assertProfileCounts(seeded, profile: .reference)
        let afterIdentity = try semanticIdentity(
            seeded,
            caseID: caseID
        )
        let afterStoreSize = try storeFootprint(
            storeURL: lease.storeURL,
            caseID: caseID
        )
        XCTAssertEqual(
            beforeIdentity.canonicalJSON,
            afterIdentity.canonicalJSON
        )
        XCTAssertEqual(
            beforeIdentity.semanticDigest,
            afterIdentity.semanticDigest
        )
        XCTAssertEqual(
            beforeIdentity.entityCounts,
            afterIdentity.entityCounts
        )

        try recordMeasurement(
            caseID: caseID,
            operation: "startup_repair",
            statistics: statistics,
            identity: afterIdentity,
            traceability: Traceability(
                currentBehaviorIDs: ["CB-13", "CB-14", "CB-16"],
                knownDefectIDs: ["KD-03"],
                decisionIDs: ["D-24", "D-37"]
            ),
            storeSizeBeforeBytes: beforeStoreSize,
            storeSizeAfterBytes: afterStoreSize
        )

        fixture = nil
        lease.releasePersistentReferences()
        try lease.cleanup()
        XCTAssertTrue(lease.ownedDirectory.isCleaned)
    }

    // Current behavior: CB-13, CB-16. Known legacy defects: KD-03,
    // KD-12. WT-032A target decisions cited: D-24, D-35-D-37.
    func testReferenceProfileSemanticDigestIsStable()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-16"],
            knownDefectIDs: ["KD-03", "KD-12"],
            decisionIDs: ["D-24", "D-35", "D-36", "D-37"]
        )

        var firstFixture: SeededFixture? =
            try makeReferenceFixture(caseID: "e08-semantic-digest")
        let firstSeeded = try XCTUnwrap(firstFixture)
        let firstIdentity = try semanticIdentity(
            firstSeeded,
            caseID: "e08-semantic-digest"
        )
        var observedDigests: [String] = []
        var observedCounts: [[String: Int]] = []

        let statistics = try ProductStatePerformanceSampler
            .measure(
                warmUpCount: warmUpCount,
                sampleCount: sampleCount
            ) {
                let identity = try semanticIdentity(
                    firstSeeded,
                    caseID: "e08-semantic-digest"
                )
                observedDigests.append(identity.semanticDigest)
                observedCounts.append(identity.entityCounts)
            }

        assertStatistics(statistics)
        XCTAssertEqual(
            Set(observedDigests),
            [firstIdentity.semanticDigest]
        )
        XCTAssertTrue(
            observedCounts.allSatisfy {
                $0 == firstIdentity.entityCounts
            }
        )

        firstFixture = nil
        let secondFixture = try makeReferenceFixture(
            caseID: "e08-semantic-digest"
        )
        let secondIdentity = try semanticIdentity(
            secondFixture,
            caseID: "e08-semantic-digest"
        )
        XCTAssertEqual(
            firstIdentity.canonicalJSON,
            secondIdentity.canonicalJSON
        )
        XCTAssertEqual(
            firstIdentity.semanticDigest,
            secondIdentity.semanticDigest
        )
        XCTAssertEqual(
            firstIdentity.entityCounts,
            secondIdentity.entityCounts
        )
        XCTAssertEqual(
            firstIdentity.relationshipCounts,
            secondIdentity.relationshipCounts
        )
        XCTAssertEqual(
            firstIdentity.orderedRecordKeys,
            secondIdentity.orderedRecordKeys
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["Product"],
            2_000
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["ShoppingList"],
            20
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["ShoppingListEntry"],
            10_000
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["ShoppingItem"],
            2_000
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["ProductHistory"],
            5_000
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["ShoppingSession"],
            1
        )
        XCTAssertEqual(
            firstIdentity.entityCounts["GeoLocation"],
            20
        )
        XCTAssertEqual(
            firstIdentity.relationshipCounts[
                "GeoLocation.shoppingItems"
            ],
            50
        )

        try recordMeasurement(
            caseID: "e08-semantic-digest",
            operation: "semantic_digest",
            statistics: statistics,
            identity: firstIdentity,
            traceability: Traceability(
                currentBehaviorIDs: ["CB-13", "CB-16"],
                knownDefectIDs: ["KD-03", "KD-12"],
                decisionIDs: [
                    "D-24", "D-35", "D-36", "D-37"
                ]
            )
        )
    }

    // MARK: - Exact deterministic profiles

    private struct SeededFixture {
        let context: ModelContext
        let products: [Product]
        let lists: [ShoppingList]
        let entries: [ShoppingListEntry]
        let items: [ShoppingItem]
        let histories: [ProductHistory]
        let session: ShoppingSession
        let locations: [GeoLocation]
    }

    private func makeReferenceFixture(
        caseID: String
    ) throws -> SeededFixture {
        let container = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: caseID)
        return try seedFixture(
            profile: .reference,
            container: container,
            caseID: caseID
        )
    }

    private func seedFixture(
        profile: ProductStateFixtureProfile,
        container: ModelContainer,
        caseID: String
    ) throws -> SeededFixture {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var products: [Product] = []
        var items: [ShoppingItem] = []
        products.reserveCapacity(profile.productCount)
        items.reserveCapacity(profile.compatibilityItemCount)

        for index in 0..<profile.productCount {
            let itemID = profile.stableUUID(
                entityNamespace: 0x0802,
                index: index
            )
            let productID = profile.stableUUID(
                entityNamespace: 0x0801,
                index: index
            )
            let date = fixedDate(TimeInterval(index))
            let isCompleted = index.isMultiple(of: 2) == false
            let deletedAt = index % 4 == 1
                ? fixedDate(TimeInterval(index + 1))
                : nil
            let name =
                "SYNTHETIC_PRODUCT_\(profile.identifier)_\(index)"
            let item = ShoppingItem(
                id: itemID,
                name: name,
                isCompleted: isCompleted,
                category: "synthetic-groceries",
                dateAdded: date,
                source: .manual
            )
            let product = Product(
                id: productID,
                legacyShoppingItemID: itemID,
                name: name,
                category: "synthetic-groceries",
                dateAdded: date,
                updatedAt: deletedAt ?? date,
                deletedAt: deletedAt,
                source: .manual
            )
            context.insert(item)
            context.insert(product)
            items.append(item)
            products.append(product)
        }

        var lists: [ShoppingList] = []
        lists.reserveCapacity(profile.namedListCount)
        for index in 0..<profile.namedListCount {
            let definition: (
                title: String,
                kind: ShoppingListKind,
                isDefault: Bool
            )
            switch index {
            case 0:
                definition = (
                    "Weekly Shopping",
                    .weekly,
                    true
                )
            case 1:
                definition = ("Completed", .completed, false)
            case 2:
                definition = ("Recent", .recent, false)
            default:
                definition = (
                    "SYNTHETIC_LIST_\(profile.identifier)_\(index)",
                    .weekly,
                    false
                )
            }
            let date = fixedDate(TimeInterval(index))
            let list = ShoppingList(
                id: profile.stableUUID(
                    entityNamespace: 0x0803,
                    index: index
                ),
                title: definition.title,
                kind: definition.kind,
                createdAt: date,
                updatedAt: date,
                isDefault: definition.isDefault
            )
            context.insert(list)
            lists.append(list)
        }

        var entries: [ShoppingListEntry] = []
        entries.reserveCapacity(profile.entryCount)
        for index in 0..<profile.entryCount {
            let productIndex = index % products.count
            let listIndex = index % lists.count
            let entry = ShoppingListEntry(
                id: profile.stableUUID(
                    entityNamespace: 0x0804,
                    index: index
                ),
                shoppingListID: lists[listIndex].id,
                product: products[productIndex],
                legacyShoppingItemID: items[productIndex].id,
                quantity: Double((index % 3) + 1),
                isChecked:
                    (index / profile.namedListCount) % 2 == 1,
                createdAt: fixedDate(TimeInterval(index)),
                sortOrder:
                    Double(index / profile.namedListCount)
            )
            context.insert(entry)
            entries.append(entry)
        }

        var histories: [ProductHistory] = []
        histories.reserveCapacity(profile.historyRecordCount)
        for index in 0..<profile.historyRecordCount {
            let date = fixedDate(TimeInterval(index))
            let history = ProductHistory(
                id: profile.stableUUID(
                    entityNamespace: 0x0805,
                    index: index
                ),
                productKey:
                    "name:synthetic_\(profile.identifier)_\(index)",
                productName:
                    "SYNTHETIC_HISTORY_\(profile.identifier)_\(index)",
                firstAddedDate: date,
                lastAddedDate: date,
                addCount: (index % 10) + 1,
                lastSource: .manual
            )
            context.insert(history)
            histories.append(history)
        }

        let lineCount = profile.sessionLineCount
            ?? profile.compatibilityItemCount
        let lineIDs = Array(items.prefix(lineCount).map(\.id))
        let session = ShoppingSession(
            id: profile.stableUUID(
                entityNamespace: 0x0806,
                index: 0
            ),
            startedAt: fixedDate(0),
            finishedAt: nil,
            isActive: true,
            itemIDs: lineIDs,
            collectedItemIDs:
                Array(lineIDs.prefix(lineIDs.count / 4)),
            shoppingListID: lists.first?.id
        )
        context.insert(session)

        var locations: [GeoLocation] = []
        locations.reserveCapacity(profile.savedLocationCount)
        var relationshipCursor = 0
        for index in 0..<profile.savedLocationCount {
            let baseRelationshipCount =
                profile.savedLocationRelationshipCount /
                    max(profile.savedLocationCount, 1)
            let remainder =
                profile.savedLocationRelationshipCount %
                    max(profile.savedLocationCount, 1)
            let relationshipCount =
                baseRelationshipCount + (index < remainder ? 1 : 0)
            let relatedItems = (0..<relationshipCount).map {
                offset in
                items[
                    (relationshipCursor + offset) % items.count
                ]
            }
            relationshipCursor += relationshipCount
            let location = GeoLocation(
                id: profile.stableUUID(
                    entityNamespace: 0x0807,
                    index: index
                ),
                title:
                    "SYNTHETIC_LOCATION_\(profile.identifier)_\(index)",
                latitude: 0,
                longitude: 0,
                radius: 200,
                storeCategory: .grocery,
                addressText: nil,
                notes: nil,
                sourceType: .userGenerated,
                shoppingItems: relatedItems
            )
            context.insert(location)
            locations.append(location)
        }

        try context.save()
        let fixture = SeededFixture(
            context: context,
            products: products,
            lists: lists,
            entries: entries,
            items: items,
            histories: histories,
            session: session,
            locations: locations
        )
        try assertProfileCounts(fixture, profile: profile)
        XCTAssertEqual(
            locations.reduce(0) {
                $0 + $1.shoppingItems.count
            },
            profile.savedLocationRelationshipCount
        )
        return fixture
    }

    private func assertProfileCounts(
        _ fixture: SeededFixture,
        profile: ProductStateFixtureProfile,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<Product>()
            ),
            profile.productCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<ShoppingList>()
            ),
            profile.namedListCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<ShoppingListEntry>()
            ),
            profile.entryCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<ShoppingItem>()
            ),
            profile.compatibilityItemCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<ProductHistory>()
            ),
            profile.historyRecordCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<ShoppingSession>()
            ),
            profile.sessionCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<GeoLocation>()
            ),
            profile.savedLocationCount,
            file: file,
            line: line
        )
        if let sessionLineCount = profile.sessionLineCount {
            XCTAssertEqual(
                fixture.session.itemIDs.count,
                sessionLineCount,
                file: file,
                line: line
            )
        }
    }

    // MARK: - Current projection boundaries

    private func selectedListProjection(
        fixture: SeededFixture,
        listID: UUID,
        includeChecked: Bool
    ) -> [ShoppingItem] {
        let itemsByID = fixture.items.reduce(
            into: [UUID: ShoppingItem]()
        ) { result, item in
            result[item.id] = item
        }
        return fixture.entries
            .filter {
                $0.shoppingListID == listID &&
                    (includeChecked || !$0.isChecked)
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap { entry in
                guard let legacyID = entry.legacyShoppingItemID else {
                    return nil
                }
                return itemsByID[legacyID]
            }
    }

    private func syntheticRequest(
        item: ShoppingItem
    ) -> ShoppingStoreSuggestionRequest {
        ShoppingStoreSuggestionRequest(
            itemID: item.id,
            itemName: item.name,
            itemCategory: "synthetic-groceries",
            storeCategories: [.grocery],
            searchTerms: [item.name],
            intentProfile: nil
        )
    }

    // MARK: - Semantic identity and safe measurement evidence

    private struct SemanticIdentity {
        let canonicalJSON: Data
        let semanticDigest: String
        let entityCounts: [String: Int]
        let relationshipCounts: [String: Int]
        let orderedRecordKeys: [String]
    }

    private func semanticIdentity(
        _ fixture: SeededFixture,
        caseID: String
    ) throws -> SemanticIdentity {
        let snapshot =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: caseID,
                    in: fixture.context
                )
        let relationshipCounts = Dictionary(
            uniqueKeysWithValues:
                Dictionary(
                    grouping: snapshot.relationshipCounts
                ) {
                    "\($0.entityKind).\($0.relationship)"
                }
                .map { key, values in
                    (
                        key,
                        values.reduce(0) { $0 + $1.count }
                    )
                }
        )
        return SemanticIdentity(
            canonicalJSON: try snapshot.canonicalJSONData(),
            semanticDigest: try snapshot.sha256Digest(),
            entityCounts: snapshot.entityCounts,
            relationshipCounts: relationshipCounts,
            orderedRecordKeys: snapshot.records.map {
                "\($0.entityKind):\($0.stableID.uuidString)"
            }
        )
    }

    private struct Traceability: Encodable {
        let currentBehaviorIDs: [String]
        let knownDefectIDs: [String]
        let decisionIDs: [String]
    }

    private struct MeasurementEnvironment: Encodable {
        let configuration: String
        let architecture: String
        let operatingSystem: String
        let thermalState: String
    }

    private struct MeasurementEnvelope: Encodable {
        let formatVersion: Int
        let syntheticData: Bool
        let expectationKind: String
        let caseID: String
        let operationStage: String
        let profileIdentifier: String
        let fixtureSeed: String
        let schemaGeneration: String
        let warmUpCount: Int
        let sampleCount: Int
        let minimumSeconds: Double
        let maximumSeconds: Double
        let p50Seconds: Double
        let p95Seconds: Double
        let entityCounts: [String: Int]
        let relationshipCounts: [String: Int]
        let semanticDigest: String
        let storeSizeBeforeBytes: Int?
        let storeSizeAfterBytes: Int?
        let traceability: Traceability
        let environment: MeasurementEnvironment
    }

    private func recordMeasurement(
        caseID: String,
        operation: String,
        statistics: ProductStateTimingStatistics,
        identity: SemanticIdentity,
        traceability: Traceability,
        storeSizeBeforeBytes: Int? = nil,
        storeSizeAfterBytes: Int? = nil
    ) throws {
        let envelope = MeasurementEnvelope(
            formatVersion: 1,
            syntheticData: true,
            expectationKind: "currentBehaviorBaseline",
            caseID: caseID,
            operationStage: operation,
            profileIdentifier:
                ProductStateFixtureProfile.reference.identifier,
            fixtureSeed: String(
                format: "%08llX",
                ProductStateFixtureProfile.reference.seed
            ),
            schemaGeneration: "v3-current",
            warmUpCount: statistics.warmUpCount,
            sampleCount: statistics.sampleCount,
            minimumSeconds: statistics.minimumSeconds,
            maximumSeconds: statistics.maximumSeconds,
            p50Seconds: statistics.p50Seconds,
            p95Seconds: statistics.p95Seconds,
            entityCounts: identity.entityCounts,
            relationshipCounts: identity.relationshipCounts,
            semanticDigest: identity.semanticDigest,
            storeSizeBeforeBytes: storeSizeBeforeBytes,
            storeSizeAfterBytes: storeSizeAfterBytes,
            traceability: traceability,
            environment: measurementEnvironment
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes
        ]
        let data = try encoder.encode(envelope)
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: UTType.json.identifier
        )
        attachment.name =
            "SYNTHETIC_ProductState_Performance_\(operation)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var measurementEnvironment: MeasurementEnvironment {
        #if WT032B_RELEASE_BASELINE
        let configuration = "release"
        #elseif DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif

        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif

        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalState = "nominal"
        case .fair:
            thermalState = "fair"
        case .serious:
            thermalState = "serious"
        case .critical:
            thermalState = "critical"
        @unknown default:
            thermalState = "unknown"
        }
        return MeasurementEnvironment(
            configuration: configuration,
            architecture: architecture,
            operatingSystem:
                ProcessInfo.processInfo.operatingSystemVersionString,
            thermalState: thermalState
        )
    }

    private func storeFootprint(
        storeURL: URL,
        caseID: String
    ) throws -> Int {
        try ProductStateStoreFingerprinting.fingerprint(
            storeURL: storeURL,
            caseID: caseID
        ).components.reduce(0) {
            $0 + $1.byteCount
        }
    }

    private func assertStatistics(
        _ statistics: ProductStateTimingStatistics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            statistics.warmUpCount,
            warmUpCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            statistics.sampleCount,
            sampleCount,
            file: file,
            line: line
        )
        let values = [
            statistics.minimumSeconds,
            statistics.maximumSeconds,
            statistics.p50Seconds,
            statistics.p95Seconds
        ]
        XCTAssertTrue(
            values.allSatisfy {
                $0.isFinite && $0 >= 0
            },
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            statistics.minimumSeconds,
            statistics.p50Seconds,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            statistics.p50Seconds,
            statistics.p95Seconds,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            statistics.p95Seconds,
            statistics.maximumSeconds,
            file: file,
            line: line
        )
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

    private func stableID(
        namespace: UInt16,
        index: UInt64
    ) -> UUID {
        ProductStateSyntheticValues.uuid(
            namespace: namespace,
            index: index
        )
    }

    private func fixedDate(_ seconds: TimeInterval) -> Date {
        ProductStateSyntheticValues.date(
            secondsAfterEpoch: seconds
        )
    }
}
