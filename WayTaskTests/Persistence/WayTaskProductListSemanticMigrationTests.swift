import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class WayTaskProductListSemanticMigrationTests: XCTestCase {
    private let recordingTime = Date(timeIntervalSince1970: 1_800_007_000)
    private let attemptSeed = UUID(
        uuidString: "07070707-0000-0000-0000-000000000007"
    )!

    func test01V1ProductListSemanticMigration() throws {
        try assertPhysicalSemanticMigration(from: .v1)
    }

    func test02V2ProductListSemanticMigration() throws {
        try assertPhysicalSemanticMigration(from: .v2)
    }

    func test03V3ProductListSemanticMigration() throws {
        let receipt = try runPhysicalSemanticMigration(from: .v3)
        defer { cleanup(receipt) }
        let product = try XCTUnwrap(receipt.targetValidation.products.first)
        XCTAssertEqual(product.catalogProductIDRawValue, IDs.catalogID)
        XCTAssertEqual(
            product.catalogDisplayNameSnapshot,
            "Synthetic Catalog Snapshot"
        )
    }

    func test04AllFourLegacyFlagCombinationsAreDeterministic() throws {
        for isChecked in [false, true] {
            for isCompleted in [false, true] {
                let plan = try normalize(
                    baseSnapshot(
                        isChecked: isChecked,
                        isCompleted: isCompleted
                    )
                )
                let entry = try XCTUnwrap(plan.target.entries.first)
                XCTAssertEqual(
                    entry.lifecycleRawValue,
                    isChecked ? "resolved" : "needed"
                )
                XCTAssertEqual(
                    entry.resolutionReasonRawValue,
                    isChecked ? "legacyUnknown" : nil
                )
                XCTAssertEqual(
                    entry.resolutionProvenanceRawValue,
                    isChecked ? "legacyMigration" : nil
                )
                XCTAssertEqual(
                    count(.legacyFlagContradiction, in: plan),
                    !isChecked && isCompleted ? 1 : 0
                )
                XCTAssertEqual(plan.target.products.count, 1)
                XCTAssertEqual(plan.target.lists.count, 1)
                XCTAssertEqual(plan.target.entries.count, 1)
                XCTAssertEqual(plan.target.lists[0].revision, 1)
            }
        }
    }

    func test05ProductUUIDIsPreservedExactly() throws {
        let plan = try normalize(baseSnapshot())
        XCTAssertEqual(plan.target.products.map(\.id), [IDs.product])
    }

    func test06ListUUIDIsPreservedExactly() throws {
        let plan = try normalize(baseSnapshot())
        XCTAssertEqual(plan.target.lists.map(\.id), [IDs.list])
    }

    func test07EntryUUIDIsPreservedExactly() throws {
        let plan = try normalize(baseSnapshot())
        XCTAssertEqual(plan.target.entries.map(\.id), [IDs.entry])
    }

    func test08CatalogIdentityAndSnapshotsArePreserved() throws {
        let plan = try normalize(baseSnapshot())
        let product = try XCTUnwrap(plan.target.products.first)
        XCTAssertEqual(product.catalogProductIDRawValue, IDs.catalogID)
        XCTAssertEqual(product.catalogDisplayNameSnapshot, "Catalog Display")
        XCTAssertEqual(product.catalogDisplayLocaleSnapshot, "en")
        XCTAssertEqual(product.catalogCategoryIDSnapshotRawValue, "food")
        XCTAssertEqual(
            product.catalogCategoryDisplayNameSnapshot,
            "Food Snapshot"
        )
        XCTAssertEqual(product.catalogIconKeySnapshot, "basket")
    }

    func test09DurableInitialListRevisionIsOnePerList() throws {
        let plan = try normalize(baseSnapshot())
        XCTAssertEqual(
            plan.target.lists.map(\.revision),
            [WayTaskProductListSemanticPlan.initialListRevision]
        )
    }

    func test10OneProductInMultipleListsHasIsolatedEntries() throws {
        var snapshot = baseSnapshot()
        snapshot = WayTaskLegacyProductListSnapshot(
            products: snapshot.products,
            lists: snapshot.lists + [list(id: IDs.list2)],
            entries: snapshot.entries + [
                entry(
                    id: IDs.entry2,
                    listID: IDs.list2,
                    productID: IDs.product
                )
            ],
            compatibilityRecords: snapshot.compatibilityRecords
        )
        let plan = try normalize(snapshot)
        XCTAssertEqual(plan.target.products.count, 1)
        XCTAssertEqual(plan.target.lists.count, 2)
        XCTAssertEqual(plan.target.entries.count, 2)
        XCTAssertEqual(Set(plan.target.entries.map(\.shoppingListID)), [
            IDs.list, IDs.list2
        ])
    }

    func test11ExactDuplicateProductMergeIsDeterministic() throws {
        let first = product(sourceRecordID: IDs.productRow1)
        let second = product(
            sourceRecordID: IDs.productRow2,
            createdAt: first.createdAt.addingTimeInterval(5)
        )
        let plan = try normalize(
            snapshot(products: [second, first])
        )
        XCTAssertEqual(plan.target.products.count, 1)
        XCTAssertEqual(plan.target.products[0].id, IDs.product)
        XCTAssertEqual(count(.duplicateMerge, in: plan), 1)
        XCTAssertEqual(
            plan.aliases.filter { $0.kind == .product }.count,
            1
        )
    }

    func test12ExactDuplicateEntryUsesD26MergeValues() throws {
        let earlier = entry(
            id: IDs.entry,
            sourceRecordID: IDs.entryRow1,
            quantity: 2,
            isChecked: true,
            createdAt: date(10),
            sortOrder: 4
        )
        let later = entry(
            id: IDs.entry2,
            sourceRecordID: IDs.entryRow2,
            quantity: 5,
            isChecked: false,
            createdAt: date(20),
            sortOrder: 1
        )
        let plan = try normalize(snapshot(entries: [later, earlier]))
        let migrated = try XCTUnwrap(plan.target.entries.first)
        XCTAssertEqual(migrated.id, IDs.entry)
        XCTAssertEqual(migrated.quantity, 5)
        XCTAssertEqual(migrated.sortOrder, 1)
        XCTAssertEqual(migrated.createdAt, date(10))
        XCTAssertEqual(migrated.lifecycleRawValue, "needed")
    }

    func test13CanonicalSelectionIsIndependentOfEnumerationOrder() throws {
        let rows = [
            entry(
                id: IDs.entry2,
                sourceRecordID: IDs.entryRow2,
                createdAt: date(10)
            ),
            entry(
                id: IDs.entry,
                sourceRecordID: IDs.entryRow1,
                createdAt: date(10)
            )
        ]
        let first = try normalize(snapshot(entries: rows))
        let second = try normalize(snapshot(entries: Array(rows.reversed())))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.target.entries[0].id, IDs.entry)
    }

    func test14AliasEvidencePreservesEveryMergedEntryIdentity() throws {
        let plan = try normalize(
            snapshot(entries: [
                entry(id: IDs.entry),
                entry(id: IDs.entry2),
                entry(id: IDs.entry3)
            ])
        )
        let aliases = plan.aliases.filter { $0.kind == .shoppingEntry }
        XCTAssertEqual(aliases.count, 2)
        XCTAssertEqual(Set(aliases.map(\.sourceIdentity)), [
            IDs.entry2, IDs.entry3
        ])
        XCTAssertEqual(Set(aliases.map(\.canonicalIdentity)), [IDs.entry])
        XCTAssertEqual(aliases.map(\.ordinal), [1, 2])
    }

    func test15SameNameDifferentProductIdentitiesNeverMerge() throws {
        let plan = try normalize(
            snapshot(
                products: [
                    product(),
                    product(id: IDs.product2, name: privateName)
                ],
                entries: [
                    entry(id: IDs.entry),
                    entry(
                        id: IDs.entry2,
                        productID: IDs.product2
                    )
                ]
            )
        )
        XCTAssertEqual(plan.target.products.count, 2)
        XCTAssertEqual(plan.target.entries.count, 2)
        XCTAssertFalse(plan.aliases.contains { $0.kind == .product })
    }

    func test16SameBarcodeDifferentProductIdentitiesNeverMerge() throws {
        let plan = try normalize(
            snapshot(
                products: [
                    product(),
                    product(
                        id: IDs.product2,
                        name: "Different Synthetic Name",
                        barcode: privateBarcode
                    )
                ],
                entries: [
                    entry(id: IDs.entry),
                    entry(id: IDs.entry2, productID: IDs.product2)
                ]
            )
        )
        XCTAssertEqual(Set(plan.target.products.map(\.id)), [
            IDs.product, IDs.product2
        ])
        XCTAssertEqual(plan.target.entries.count, 2)
    }

    func test17TombstoneAlwaysRemainsRemoved() throws {
        let plan = try normalize(
            snapshot(products: [product(removedAt: date(30))], entries: [])
        )
        XCTAssertEqual(
            plan.target.products[0].libraryLifecycleRawValue,
            ProductLibraryLifecycle.removed.rawValue
        )
        XCTAssertEqual(plan.target.products[0].libraryRemovedAt, date(30))
    }

    func test18TombstoneWithActiveMembershipIsClassifiedNotRestored()
        throws
    {
        let plan = try normalize(
            snapshot(products: [product(removedAt: date(30))])
        )
        XCTAssertEqual(plan.target.products[0].libraryLifecycleRawValue, "removed")
        XCTAssertEqual(plan.target.entries.count, 1)
        XCTAssertEqual(count(.tombstoneActiveReference, in: plan), 1)
    }

    func test19MissingProductIdentityBecomesException() throws {
        let plan = try normalize(
            snapshot(products: [product(id: nil)], entries: [])
        )
        XCTAssertTrue(categories(in: plan).contains(.missingProductIdentity))
        XCTAssertTrue(plan.target.products.isEmpty)
    }

    func test20MissingListIdentityBecomesException() throws {
        let plan = try normalize(
            snapshot(lists: [list(id: nil)], entries: [])
        )
        XCTAssertTrue(categories(in: plan).contains(.missingListIdentity))
        XCTAssertTrue(plan.target.lists.isEmpty)
    }

    func test21AmbiguousRelationshipUsesOnlyExactStoredProductUUID()
        throws
    {
        let plan = try normalize(
            snapshot(entries: [
                entry(
                    id: IDs.entry,
                    productID: IDs.product,
                    relationshipProductID: IDs.product2
                )
            ])
        )
        XCTAssertEqual(plan.target.entries[0].productID, IDs.product)
        XCTAssertEqual(count(.ambiguousRelationship, in: plan), 1)
    }

    func test22DuplicateRelationshipEdgeProducesOneEntry() throws {
        let plan = try normalize(
            snapshot(entries: [entry(id: IDs.entry), entry(id: IDs.entry2)])
        )
        XCTAssertEqual(plan.target.entries.count, 1)
        XCTAssertEqual(count(.duplicateMerge, in: plan), 1)
    }

    func test23DuplicateListMergeStillEstablishesOneRevision() throws {
        let plan = try normalize(
            snapshot(lists: [
                list(id: IDs.list, sourceRecordID: IDs.listRow2),
                list(id: IDs.list, sourceRecordID: IDs.listRow1)
            ])
        )
        XCTAssertEqual(plan.target.lists.count, 1)
        XCTAssertEqual(plan.target.lists[0].revision, 1)
        XCTAssertEqual(
            plan.aliases.filter { $0.kind == .shoppingList }.count,
            1
        )
    }

    func test24TargetCountsAndRelationshipsReconcile() throws {
        let plan = try normalize(baseSnapshot())
        XCTAssertEqual(plan.target.products.count, 1)
        XCTAssertEqual(plan.target.lists.count, 1)
        XCTAssertEqual(plan.target.entries.count, 1)
        XCTAssertEqual(plan.target.entries[0].productID, plan.target.products[0].id)
        XCTAssertEqual(plan.target.entries[0].shoppingListID, plan.target.lists[0].id)
    }

    func test25ExceptionLedgerIsBoundedDeterministicAndPrivacySafe()
        throws
    {
        let plan = try normalize(
            baseSnapshot(isChecked: false, isCompleted: true)
        )
        var first = WayTaskMigrationExceptionLedger(capacity: 1)
        var second = WayTaskMigrationExceptionLedger(capacity: 1)
        for fact in plan.exceptionFacts {
            first.record(
                category: fact.category,
                safeEvidenceDigest: fact.safeEvidenceDigest
            )
            second.record(
                category: fact.category,
                safeEvidenceDigest: fact.safeEvidenceDigest
            )
        }
        XCTAssertEqual(first, second)
        XCTAssertEqual(try first.encodedData(), try second.encodedData())
        XCTAssertGreaterThan(first.summary.totalOccurrenceCount, 0)
        let encoded = try XCTUnwrap(
            String(data: first.encodedData(), encoding: .utf8)
        )
        XCTAssertFalse(encoded.contains(privateName))
        XCTAssertFalse(encoded.contains(privateBarcode))
    }

    func test26EquivalentCleanSecondPassIsSemanticallyStable() throws {
        let firstFixture = try makeFixture(schema: .v3)
        let secondFixture = try cloneFixture(firstFixture)
        let firstSourceBefore = try componentBytes(
            firstFixture.sourceStoreURL
        )
        let secondSourceBefore = try componentBytes(
            secondFixture.sourceStoreURL
        )
        let first = try migrateFixture(firstFixture)
        let second = try migrateFixture(secondFixture)
        defer {
            cleanup(first)
            cleanup(second)
        }
        XCTAssertEqual(first.targetValidation, second.targetValidation)
        XCTAssertEqual(first.aliases, second.aliases)
        XCTAssertEqual(first.exceptionSummary, second.exceptionSummary)
        XCTAssertEqual(first.semanticDigest, second.semanticDigest)
        XCTAssertEqual(
            firstSourceBefore,
            try componentBytes(firstFixture.sourceStoreURL)
        )
        XCTAssertEqual(
            secondSourceBefore,
            try componentBytes(secondFixture.sourceStoreURL)
        )
    }

    func test27SourceAndSidecarBytesAreImmutableOnSemanticSuccess()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let before = try componentBytes(fixture.sourceStoreURL)
        XCTAssertTrue(before.keys.contains("-wal"))
        XCTAssertTrue(before.keys.contains("-shm"))
        let migration = WayTaskProductStateMigration()
        let foundation = try unwrapFoundation(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        let semantic = try unwrapSemantic(
            migration.migrateProductListSemantics(foundation)
        )
        XCTAssertEqual(before, try componentBytes(fixture.sourceStoreURL))
        XCTAssertTrue(semantic.semanticConversionCompleted)
        cleanup(semantic)
    }

    func test28SourceAndSidecarBytesAreImmutableOnSemanticFailure()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let before = try componentBytes(fixture.sourceStoreURL)
        XCTAssertTrue(before.keys.contains("-wal"))
        XCTAssertTrue(before.keys.contains("-shm"))
        let foundationMigration = WayTaskProductStateMigration()
        let foundation = try unwrapFoundation(
            foundationMigration.prepareCandidate(
                fixture.request(seed: attemptSeed)
            )
        )
        var semanticDependencies =
            WayTaskProductListSemanticMigrationDependencies.live
        semanticDependencies.createTargetStore = { _, _ in
            throw SyntheticFailure.injected
        }
        let result = WayTaskProductStateMigration(
            dependencies: .live,
            semanticDependencies: semanticDependencies
        ).migrateProductListSemantics(foundation)
        let failure = try unwrapFailure(result)
        XCTAssertEqual(failure.classification, .semanticTargetCreationFailed)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
        XCTAssertEqual(before, try componentBytes(fixture.sourceStoreURL))
    }

    func test29SemanticFailureCleansOnlyOwnedCandidateAttempt() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let neighbor = fixture.candidateRootURL.appendingPathComponent(
            "not-owned.txt"
        )
        try Data("retain".utf8).write(to: neighbor)
        let migration = WayTaskProductStateMigration()
        let foundation = try unwrapFoundation(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        var semanticDependencies =
            WayTaskProductListSemanticMigrationDependencies.live
        semanticDependencies.reopenTargetStore = { _ in
            throw SyntheticFailure.injected
        }
        let failure = try unwrapFailure(
            WayTaskProductStateMigration(
                dependencies: .live,
                semanticDependencies: semanticDependencies
            ).migrateProductListSemantics(foundation)
        )
        XCTAssertEqual(failure.classification, .semanticTargetReopenFailed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: foundation.candidateAttemptDirectoryURL.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbor.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.sourceStoreURL.path)
        )
    }

    func test30SessionHistoryArchiveAndLocationAreNotConverted() throws {
        let archive = list(id: IDs.list2, kind: .completed)
        let plan = try normalize(
            snapshot(
                lists: [list(), archive],
                entries: [
                    entry(id: IDs.entry),
                    entry(id: IDs.entry2, listID: IDs.list2)
                ]
            )
        )
        XCTAssertEqual(plan.deferredArchiveListCount, 1)
        XCTAssertEqual(plan.deferredArchiveEntryCount, 1)
        XCTAssertEqual(plan.target.lists.map(\.id), [IDs.list])
        XCTAssertEqual(plan.target.entries.map(\.id), [IDs.entry])

        let receipt = try runPhysicalSemanticMigration(from: .v3)
        defer { cleanup(receipt) }
        XCTAssertFalse(
            receipt.sessionHistoryLocationSemanticConversionCompleted
        )
        let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
        let configuration = ModelConfiguration(
            "WT033A-T07-No-T08-Reopen",
            schema: schema,
            url: receipt.targetStoreURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        XCTAssertEqual(
            try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
            ),
            0
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ProductHistory>()),
            0
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<GeoLocation>()),
            0
        )
    }

    func test31NoPromotionOrStartupActivationIsAuthorized() throws {
        let receipt = try runPhysicalSemanticMigration(from: .v3)
        defer { cleanup(receipt) }
        XCTAssertFalse(receipt.promotionAuthorized)
        XCTAssertFalse(receipt.startupActivationAuthorized)
        XCTAssertEqual(receipt.status, .productListSemanticMigrationComplete)
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "WayTask/Persistence/WayTaskProductStateMigration.swift"
            ),
            encoding: .utf8
        )
        for forbidden in [
            "replacePersistentStore", "destroyPersistentStore",
            "WayTaskStartupPersistence", "WayTaskApp", "ContentView",
            "import SwiftUI", "import MapKit", "URLSession"
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func test32ApplicationDefaultStoreIsNeverAccessed() throws {
        let receipt = try runPhysicalSemanticMigration(from: .v3)
        defer { cleanup(receipt) }
        let defaultURL = ModelConfiguration().url.standardizedFileURL
        XCTAssertNotEqual(
            receipt.foundationReceipt.candidateStoreURL.standardizedFileURL,
            defaultURL
        )
        XCTAssertNotEqual(receipt.targetStoreURL.standardizedFileURL, defaultURL)
        XCTAssertEqual(
            receipt.targetStoreURL.deletingLastPathComponent()
                .standardizedFileURL,
            receipt.foundationReceipt.candidateAttemptDirectoryURL
                .standardizedFileURL
        )
        XCTAssertTrue(
            receipt.ownedArtifactNames.contains(
                WayTaskProductStateMigration.productListTargetStoreFilename
            )
        )
    }

    // MARK: - Pure semantic fixtures

    private var firstInputProducts: [WayTaskLegacyProductRecord] {
        [product()]
    }

    private var firstInputLists: [WayTaskLegacyShoppingListRecord] {
        [list()]
    }

    private var firstInputEntries: [WayTaskLegacyShoppingEntryRecord] {
        [entry(id: IDs.entry)]
    }

    private var firstInputCompatibility: [WayTaskLegacyCompatibilityRecord] {
        [compatibility(isCompleted: false)]
    }

    private func baseSnapshot(
        isChecked: Bool = false,
        isCompleted: Bool = false
    ) -> WayTaskLegacyProductListSnapshot {
        snapshot(
            entries: [entry(id: IDs.entry, isChecked: isChecked)],
            compatibilityRecords: [
                compatibility(isCompleted: isCompleted)
            ]
        )
    }

    private func snapshot(
        products: [WayTaskLegacyProductRecord]? = nil,
        lists: [WayTaskLegacyShoppingListRecord]? = nil,
        entries: [WayTaskLegacyShoppingEntryRecord]? = nil,
        compatibilityRecords: [WayTaskLegacyCompatibilityRecord]? = nil
    ) -> WayTaskLegacyProductListSnapshot {
        WayTaskLegacyProductListSnapshot(
            products: products ?? firstInputProducts,
            lists: lists ?? firstInputLists,
            entries: entries ?? firstInputEntries,
            compatibilityRecords:
                compatibilityRecords ?? firstInputCompatibility
        )
    }

    private func product(
        id: UUID? = IDs.product,
        sourceRecordID: UUID? = nil,
        name: String = "SYNTHETIC_PRIVATE_PRODUCT",
        barcode: String? = "SYNTHETIC_PRIVATE_BARCODE",
        createdAt: Date? = nil,
        removedAt: Date? = nil
    ) -> WayTaskLegacyProductRecord {
        WayTaskLegacyProductRecord(
            sourceRecordID: sourceRecordID ?? id ?? IDs.productRow1,
            productID: id,
            legacyShoppingItemID: IDs.item,
            name: name,
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            barcode: barcode,
            imageURLString: "synthetic://image",
            sourceRawValue: ProductSource.manual.rawValue,
            catalogProductIDRawValue: IDs.catalogID,
            catalogDisplayNameSnapshot: "Catalog Display",
            catalogDisplayLocaleSnapshot: "en",
            catalogCategoryIDSnapshotRawValue: "food",
            catalogCategoryDisplayNameSnapshot: "Food Snapshot",
            catalogIconKeySnapshot: "basket",
            catalogSnapshotUpdatedAt: date(3),
            createdAt: createdAt ?? date(1),
            updatedAt: date(2),
            removedAt: removedAt
        )
    }

    private func list(
        id: UUID? = IDs.list,
        sourceRecordID: UUID? = nil,
        kind: ShoppingListKind = .weekly
    ) -> WayTaskLegacyShoppingListRecord {
        WayTaskLegacyShoppingListRecord(
            sourceRecordID: sourceRecordID ?? id ?? IDs.listRow1,
            listID: id,
            title: "Synthetic List",
            kindRawValue: kind.rawValue,
            createdAt: date(4),
            updatedAt: date(5),
            isDefault: false
        )
    }

    private func entry(
        id: UUID?,
        sourceRecordID: UUID? = nil,
        listID: UUID? = IDs.list,
        productID: UUID? = IDs.product,
        relationshipProductID: UUID? = IDs.product,
        quantity: Double = 2,
        isChecked: Bool = false,
        createdAt: Date? = nil,
        sortOrder: Double = 1
    ) -> WayTaskLegacyShoppingEntryRecord {
        WayTaskLegacyShoppingEntryRecord(
            sourceRecordID: sourceRecordID ?? id ?? IDs.entryRow1,
            entryID: id,
            listID: listID,
            productID: productID,
            relationshipProductID: relationshipProductID,
            legacyShoppingItemID: IDs.item,
            quantity: quantity,
            isChecked: isChecked,
            createdAt: createdAt ?? date(6),
            sortOrder: sortOrder
        )
    }

    private func compatibility(
        isCompleted: Bool
    ) -> WayTaskLegacyCompatibilityRecord {
        WayTaskLegacyCompatibilityRecord(
            sourceRecordID: IDs.item,
            compatibilityID: IDs.item,
            isCompleted: isCompleted
        )
    }

    private func normalize(
        _ snapshot: WayTaskLegacyProductListSnapshot
    ) throws -> WayTaskProductListSemanticPlan {
        try WayTaskProductListSemanticNormalizer.normalize(
            snapshot,
            recordingTime: recordingTime
        )
    }

    private func count(
        _ category: WayTaskMigrationExceptionCategory,
        in plan: WayTaskProductListSemanticPlan
    ) -> Int {
        plan.exceptionFacts.filter { $0.category == category }.count
    }

    private func categories(
        in plan: WayTaskProductListSemanticPlan
    ) -> Set<WayTaskMigrationExceptionCategory> {
        Set(plan.exceptionFacts.map(\.category))
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_007_000 + offset)
    }

    private var privateName: String { "SYNTHETIC_PRIVATE_PRODUCT" }
    private var privateBarcode: String { "SYNTHETIC_PRIVATE_BARCODE" }

    // MARK: - File-backed V1/V2/V3 fixtures

    private struct Fixture {
        let rootURL: URL
        let sourceStoreURL: URL
        let candidateRootURL: URL

        func request(seed: UUID) -> WayTaskMigrationRequest {
            WayTaskMigrationRequest(
                sourceStoreURL: sourceStoreURL,
                candidateRootURL: candidateRootURL,
                attemptSeed: seed,
                exceptionLedgerCapacity: 32
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func assertPhysicalSemanticMigration(
        from schema: WayTaskMigrationSchemaIdentity
    ) throws {
        let receipt = try runPhysicalSemanticMigration(from: schema)
        defer { cleanup(receipt) }
        XCTAssertEqual(
            receipt.foundationReceipt.sourceSchemaIdentity,
            schema
        )
        XCTAssertEqual(receipt.targetValidation.products.map(\.id), [IDs.product])
        XCTAssertEqual(receipt.targetValidation.lists.map(\.id), [IDs.list])
        XCTAssertEqual(receipt.targetValidation.entries.map(\.id), [IDs.entry])
        XCTAssertEqual(receipt.targetValidation.lists[0].revision, 1)
        XCTAssertEqual(
            receipt.targetValidation.entries[0].lifecycleRawValue,
            "resolved"
        )
        XCTAssertEqual(
            receipt.targetValidation.entries[0].resolutionReasonRawValue,
            "legacyUnknown"
        )
        XCTAssertTrue(receipt.productListSemanticConversionCompleted)
        XCTAssertFalse(receipt.promotionAuthorized)
    }

    private func runPhysicalSemanticMigration(
        from schema: WayTaskMigrationSchemaIdentity
    ) throws -> WayTaskProductListSemanticReceipt {
        let fixture = try makeFixture(schema: schema)
        return try migrateFixture(fixture)
    }

    private func migrateFixture(
        _ fixture: Fixture
    ) throws -> WayTaskProductListSemanticReceipt {
        let migration = WayTaskProductStateMigration()
        do {
            let foundation = try unwrapFoundation(
                migration.prepareCandidate(fixture.request(seed: attemptSeed))
            )
            let receipt = try unwrapSemantic(
                migration.migrateProductListSemantics(foundation)
            )
            RetainedFixtures.shared.roots[
                receipt.foundationReceipt.candidateAttemptDirectoryURL.path
            ] = fixture.rootURL
            return receipt
        } catch {
            fixture.remove()
            throw error
        }
    }

    private func cloneFixture(_ source: Fixture) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT033A-T07-CLONE-\(UUID().uuidString)",
                isDirectory: true
            )
        let sourceDirectory = root.appendingPathComponent(
            "protected-source",
            isDirectory: true
        )
        let candidateRoot = root.appendingPathComponent(
            "task-owned-candidates",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidateRoot,
            withIntermediateDirectories: true
        )
        let clone = Fixture(
            rootURL: root,
            sourceStoreURL: sourceDirectory.appendingPathComponent(
                "WayTask.store"
            ),
            candidateRootURL: candidateRoot
        )
        try copyStoreComponents(
            from: source.sourceStoreURL,
            to: clone.sourceStoreURL
        )
        return clone
    }

    private func makeFixture(
        schema identity: WayTaskMigrationSchemaIdentity
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT033A-T07-\(UUID().uuidString)",
                isDirectory: true
            )
        let builderDirectory = root.appendingPathComponent(
            "synthetic-builder",
            isDirectory: true
        )
        let sourceDirectory = root.appendingPathComponent(
            "protected-source",
            isDirectory: true
        )
        let candidateRoot = root.appendingPathComponent(
            "task-owned-candidates",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: builderDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidateRoot,
            withIntermediateDirectories: true
        )
        let builderURL = builderDirectory.appendingPathComponent("builder.store")
        let sourceURL = sourceDirectory.appendingPathComponent("WayTask.store")
        try writeFixture(identity, to: builderURL, copyTo: sourceURL)
        try FileManager.default.removeItem(at: builderDirectory)
        return Fixture(
            rootURL: root,
            sourceStoreURL: sourceURL,
            candidateRootURL: candidateRoot
        )
    }

    private func writeFixture(
        _ identity: WayTaskMigrationSchemaIdentity,
        to builderURL: URL,
        copyTo sourceURL: URL
    ) throws {
        switch identity {
        case .v1:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV1.self)
                let container = try fixtureContainer(schema, builderURL)
                let context = ModelContext(container)
                let product = WayTaskSchemaV1.Product(
                    id: IDs.product,
                    legacyShoppingItemID: IDs.item,
                    name: privateName,
                    barcode: privateBarcode,
                    dateAdded: date(1),
                    updatedAt: date(2)
                )
                insertCommon(
                    into: context,
                    product: product,
                    entry: WayTaskSchemaV1.ShoppingListEntry(
                        id: IDs.entry,
                        shoppingListID: IDs.list,
                        product: product,
                        legacyShoppingItemID: IDs.item,
                        quantity: 2,
                        isChecked: true,
                        createdAt: date(6),
                        sortOrder: 1
                    )
                )
                try context.save()
                try copyStoreComponents(from: builderURL, to: sourceURL)
            }
        case .v2:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV2.self)
                let container = try fixtureContainer(schema, builderURL)
                let context = ModelContext(container)
                let product = WayTaskSchemaV2.Product(
                    id: IDs.product,
                    legacyShoppingItemID: IDs.item,
                    name: privateName,
                    barcode: privateBarcode,
                    dateAdded: date(1),
                    updatedAt: date(2),
                    catalogProductIDRawValue: IDs.catalogID,
                    catalogDisplayNameSnapshot: "Synthetic Catalog Snapshot"
                )
                insertCommon(
                    into: context,
                    product: product,
                    entry: WayTaskSchemaV2.ShoppingListEntry(
                        id: IDs.entry,
                        shoppingListID: IDs.list,
                        product: product,
                        legacyShoppingItemID: IDs.item,
                        quantity: 2,
                        isChecked: true,
                        createdAt: date(6),
                        sortOrder: 1
                    )
                )
                try context.save()
                try copyStoreComponents(from: builderURL, to: sourceURL)
            }
        case .v3:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
                let container = try fixtureContainer(schema, builderURL)
                let context = ModelContext(container)
                let product = Product(
                    id: IDs.product,
                    legacyShoppingItemID: IDs.item,
                    name: privateName,
                    barcode: privateBarcode,
                    dateAdded: date(1),
                    updatedAt: date(2),
                    catalogProductIDRawValue: IDs.catalogID,
                    catalogDisplayNameSnapshot: "Synthetic Catalog Snapshot"
                )
                insertCommon(
                    into: context,
                    product: product,
                    entry: ShoppingListEntry(
                        id: IDs.entry,
                        shoppingListID: IDs.list,
                        product: product,
                        legacyShoppingItemID: IDs.item,
                        quantity: 2,
                        isChecked: true,
                        createdAt: date(6),
                        sortOrder: 1
                    )
                )
                try context.save()
                try copyStoreComponents(from: builderURL, to: sourceURL)
            }
        case .v4:
            throw SyntheticFailure.injected
        }
    }

    private func insertCommon<P: PersistentModel, E: PersistentModel>(
        into context: ModelContext,
        product: P,
        entry: E
    ) {
        context.insert(
            ShoppingItem(
                id: IDs.item,
                name: privateName,
                isCompleted: false,
                barcode: privateBarcode
            )
        )
        context.insert(product)
        context.insert(
            ShoppingList(
                id: IDs.list,
                title: "Synthetic List",
                kind: .weekly,
                createdAt: date(4),
                updatedAt: date(5),
                isDefault: false
            )
        )
        context.insert(entry)
    }

    private func fixtureContainer(
        _ schema: Schema,
        _ storeURL: URL
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    "WT033A-T07-Synthetic-Builder",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }

    private func copyStoreComponents(from source: URL, to target: URL)
        throws
    {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let sourceComponent = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(
                atPath: sourceComponent.path
            ) else { continue }
            try FileManager.default.copyItem(
                at: sourceComponent,
                to: URL(fileURLWithPath: target.path + suffix)
            )
        }
    }

    private func componentBytes(_ storeURL: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            result[suffix.isEmpty ? "database" : suffix] = try Data(
                contentsOf: url
            )
        }
        return result
    }

    private func unwrapFoundation(
        _ result: WayTaskMigrationPreparationResult
    ) throws -> WayTaskMigrationCandidateReceipt {
        guard case let .candidateReady(receipt) = result else {
            throw SyntheticFailure.unexpectedResult
        }
        return receipt
    }

    private func unwrapSemantic(
        _ result: WayTaskProductListSemanticMigrationResult
    ) throws -> WayTaskProductListSemanticReceipt {
        guard case let .complete(receipt) = result else {
            if case let .failed(failure) = result {
                XCTFail("Semantic migration failed: \(failure.classification)")
            }
            throw SyntheticFailure.unexpectedResult
        }
        return receipt
    }

    private func unwrapFailure(
        _ result: WayTaskProductListSemanticMigrationResult
    ) throws -> WayTaskMigrationFailure {
        guard case let .failed(failure) = result else {
            throw SyntheticFailure.unexpectedResult
        }
        return failure
    }

    private func cleanup(_ receipt: WayTaskProductListSemanticReceipt) {
        _ = WayTaskProductStateMigration().cleanupOwnedCandidate(
            receipt.foundationReceipt
        )
        if let root = RetainedFixtures.shared.roots.removeValue(
            forKey: receipt.foundationReceipt.candidateAttemptDirectoryURL.path
        ) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum SyntheticFailure: Error {
        case injected
        case unexpectedResult
    }

    private final class RetainedFixtures {
        static let shared = RetainedFixtures()
        var roots: [String: URL] = [:]
    }

    private enum IDs {
        nonisolated static let product = uuid("17000000-0000-0000-0000-000000000001")
        nonisolated static let product2 = uuid("17000000-0000-0000-0000-000000000002")
        nonisolated static let item = uuid("17000000-0000-0000-0000-000000000003")
        nonisolated static let list = uuid("17000000-0000-0000-0000-000000000004")
        nonisolated static let list2 = uuid("17000000-0000-0000-0000-000000000005")
        nonisolated static let entry = uuid("17000000-0000-0000-0000-000000000006")
        nonisolated static let entry2 = uuid("17000000-0000-0000-0000-000000000007")
        nonisolated static let entry3 = uuid("17000000-0000-0000-0000-000000000008")
        nonisolated static let productRow1 = uuid("17000000-0000-0000-0001-000000000001")
        nonisolated static let productRow2 = uuid("17000000-0000-0000-0001-000000000002")
        nonisolated static let listRow1 = uuid("17000000-0000-0000-0002-000000000001")
        nonisolated static let listRow2 = uuid("17000000-0000-0000-0002-000000000002")
        nonisolated static let entryRow1 = uuid("17000000-0000-0000-0003-000000000001")
        nonisolated static let entryRow2 = uuid("17000000-0000-0000-0003-000000000002")
        nonisolated static let catalogID = "synthetic.catalog.product"

        nonisolated private static func uuid(_ value: String) -> UUID {
            UUID(uuidString: value)!
        }
    }
}
