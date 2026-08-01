import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class WayTaskSessionHistoryArchiveMigrationTests: XCTestCase {
    private let recordingTime = Date(timeIntervalSince1970: 1_800_010_000)
    private let digestKey = Data("wt033a-t08-synthetic-key".utf8)
    private let attemptSeed = UUID(
        uuidString: "08080808-0000-0000-0000-000000000008"
    )!

    func test01ActiveSessionPreservesIdentitySourceAndExactLine() throws {
        let plan = try normalize(baseSource())
        let session = try XCTUnwrap(plan.target.sessions.first)
        let line = try XCTUnwrap(session.lines.first)
        XCTAssertEqual(session.id, IDs.session)
        XCTAssertEqual(session.sourceListID, IDs.list)
        XCTAssertEqual(session.lifecycleRawValue, "active")
        XCTAssertEqual(session.migrationConditionRawValue, "legacyMapped")
        XCTAssertEqual(line.sourceEntryID, IDs.entry)
        XCTAssertEqual(line.productID, IDs.product)
        XCTAssertEqual(line.productNameSnapshot, privateName)
    }

    func test02FinishedSessionIsLegacyIncompleteWithoutFinalOutcome() throws {
        let plan = try normalize(
            baseSource(sessions: [
                session(
                    finishedAt: date(100),
                    isActive: false,
                    collectedRaw: IDs.item.uuidString
                )
            ])
        )
        let migrated = try XCTUnwrap(plan.target.sessions.first)
        let line = try XCTUnwrap(migrated.lines.first)
        XCTAssertEqual(migrated.lifecycleRawValue, "finished")
        XCTAssertEqual(
            migrated.migrationConditionRawValue,
            "legacyIncomplete"
        )
        XCTAssertEqual(line.executionStateRawValue, "collected")
        XCTAssertNil(line.finalOutcomeRawValue)
        XCTAssertEqual(line.legacyDispositionRawValue, "legacyUnknown")
        XCTAssertTrue(plan.target.historyEvents.isEmpty)
    }

    func test03InactiveUnfinishedSessionRemainsExplicitUnresolvedEvidence()
        throws
    {
        let plan = try normalize(
            baseSource(sessions: [session(isActive: false)])
        )
        let migrated = try XCTUnwrap(plan.target.sessions.first)
        XCTAssertEqual(migrated.lifecycleRawValue, "legacyInactive")
        XCTAssertEqual(
            migrated.migrationConditionRawValue,
            "legacyUnresolved"
        )
        XCTAssertTrue(
            categories(in: plan).contains(.sessionLifecycleContradiction)
        )
    }

    func test04ActiveAndFinishedEvidenceIsNotSilentlyReconciled() throws {
        let plan = try normalize(
            baseSource(sessions: [session(finishedAt: date(100))])
        )
        XCTAssertEqual(plan.target.sessions[0].lifecycleRawValue, "active")
        XCTAssertEqual(
            plan.target.sessions[0].migrationConditionRawValue,
            "legacyUnresolved"
        )
        XCTAssertTrue(
            categories(in: plan).contains(.sessionLifecycleContradiction)
        )
    }

    func test05MissingSourceListIdentityIsNilAndNeverFabricated() throws {
        let plan = try normalize(
            baseSource(sessions: [session(listID: nil)])
        )
        XCTAssertNil(plan.target.sessions[0].sourceListID)
        XCTAssertNil(plan.target.sessions[0].sourceRevision)
        XCTAssertEqual(
            plan.target.sessions[0].sourceRevisionProvenanceRawValue,
            "legacyUnknown"
        )
        XCTAssertTrue(
            categories(in: plan).contains(.missingSessionSourceList)
        )
    }

    func test06MissingExactEntryCreatesVisibleUnresolvedLine() throws {
        var source = baseSource()
        source = WayTaskSessionHistoryArchiveSourceSnapshot(
            productList: productList(entries: []),
            sessions: source.sessions,
            historyAggregates: source.historyAggregates,
            compatibilityItems: source.compatibilityItems,
            savedLocations: source.savedLocations
        )
        let plan = try normalize(source)
        let line = try XCTUnwrap(plan.target.sessions[0].lines.first)
        XCTAssertNil(line.sourceEntryID)
        XCTAssertNil(line.productID)
        XCTAssertEqual(line.productNameSnapshot, privateName)
        XCTAssertEqual(line.snapshotProvenanceRawValue, "legacyUnresolved")
        XCTAssertTrue(categories(in: plan).contains(.unresolvedSessionLine))
    }

    func test07CollectedEvidenceNeverCreatesPurchaseOrHistory() throws {
        let plan = try normalize(
            baseSource(sessions: [
                session(collectedRaw: IDs.item.uuidString)
            ])
        )
        let line = plan.target.sessions[0].lines[0]
        XCTAssertEqual(line.executionStateRawValue, "collected")
        XCTAssertNil(line.finalOutcomeRawValue)
        XCTAssertNil(line.finalOutcomeAt)
        XCTAssertTrue(plan.target.historyEvents.isEmpty)
    }

    func test08ForeignCollectedTokenIsRetainedAsExceptionNotLine() throws {
        let plan = try normalize(
            baseSource(sessions: [
                session(collectedRaw: IDs.foreign.uuidString)
            ])
        )
        XCTAssertEqual(plan.target.sessions[0].lines.count, 1)
        XCTAssertTrue(categories(in: plan).contains(.foreignCollectedToken))
        let exception = try XCTUnwrap(
            plan.target.sessions[0].exceptions.first {
                $0.categoryRawValue ==
                    WayTaskMigrationExceptionCategory
                        .foreignCollectedToken.rawValue
            }
        )
        XCTAssertEqual(exception.normalizedTokenID, IDs.foreign)
    }

    func test09DuplicateTokensCreateOneLineAndOrdinalEvidence() throws {
        let raw = [IDs.item, IDs.item].map(\.uuidString)
            .joined(separator: ",")
        let plan = try normalize(
            baseSource(sessions: [session(itemRaw: raw)])
        )
        XCTAssertEqual(plan.target.sessions[0].lines.count, 1)
        let duplicate = try XCTUnwrap(
            plan.target.sessions[0].exceptions.first {
                $0.categoryRawValue ==
                    WayTaskMigrationExceptionCategory
                        .duplicateSessionToken.rawValue
            }
        )
        XCTAssertEqual(duplicate.sourceCollectionRawValue, "item_ids")
        XCTAssertEqual(duplicate.sourceOrdinals, [1, 2])
        XCTAssertEqual(duplicate.occurrenceCount, 2)
        XCTAssertEqual(duplicate.normalizedTokenID, IDs.item)
    }

    func test10InvalidTokenEvidenceIsBoundedAndPrivacySafe() throws {
        let raw = "private-invalid-token"
        let plan = try normalize(
            baseSource(sessions: [session(itemRaw: raw)])
        )
        let invalid = try XCTUnwrap(
            plan.target.sessions[0].exceptions.first {
                $0.categoryRawValue ==
                    WayTaskMigrationExceptionCategory
                        .invalidSessionToken.rawValue
            }
        )
        XCTAssertEqual(invalid.sourceOrdinals, [1])
        XCTAssertEqual(invalid.sourceByteLength, raw.utf8.count)
        XCTAssertNil(invalid.normalizedTokenID)
        let data = try JSONEncoder().encode(
            plan.target.sessions[0].exceptions
        )
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains(raw))
        XCTAssertFalse(encoded.contains(privateName))
        XCTAssertFalse(encoded.contains(privateBarcode))
    }

    func test11EveryActiveClaimIsPreservedAsRecoveryCandidate() throws {
        let plan = try normalize(
            baseSource(sessions: [
                session(id: IDs.session),
                session(id: IDs.session2)
            ])
        )
        XCTAssertEqual(Set(plan.target.sessions.map(\.id)), [
            IDs.session, IDs.session2
        ])
        XCTAssertEqual(
            plan.exceptionFacts.filter {
                $0.category == .multipleSessionCandidates
            }.count,
            2
        )
    }

    func test12LegacyActivityAndActivationStartAtStartedAt() throws {
        let plan = try normalize(baseSource())
        let migrated = plan.target.sessions[0]
        XCTAssertEqual(migrated.startedAt, date(0))
        XCTAssertEqual(migrated.activationStartedAt, date(0))
        XCTAssertEqual(migrated.lastActivityAt, date(0))
        XCTAssertEqual(migrated.revision, 1)
        XCTAssertEqual(migrated.expirationPolicyVersion, 1)
    }

    func test13ValidLegacyStoreSnapshotIsPreservedExactly() throws {
        let plan = try normalize(baseSource())
        let stop = try XCTUnwrap(plan.target.sessions[0].stops.first)
        XCTAssertEqual(stop.storeReferenceIDRawValue, IDs.store.uuidString.lowercased())
        XCTAssertEqual(stop.displayNameSnapshot, privateStoreName)
        XCTAssertEqual(stop.latitudeSnapshot, 31.75)
        XCTAssertEqual(stop.longitudeSnapshot, 35.22)
        XCTAssertFalse(stop.isSessionScopedTransient)
    }

    func test14InvalidStoreCoordinatesDegradeWithoutGuessing() throws {
        let plan = try normalize(
            baseSource(sessions: [session(latitude: 400, longitude: 35)])
        )
        let stop = try XCTUnwrap(plan.target.sessions[0].stops.first)
        XCTAssertNil(stop.latitudeSnapshot)
        XCTAssertNil(stop.longitudeSnapshot)
        XCTAssertTrue(categories(in: plan).contains(.invalidSessionStore))
    }

    func test15LegacyHistoryAggregateRemainsByteSemanticAndUnlinked()
        throws
    {
        let history = legacyHistory()
        let plan = try normalize(
            baseSource(history: [history])
        )
        XCTAssertEqual(plan.target.historyAggregates, [history])
        XCTAssertTrue(plan.target.historyEvents.isEmpty)
        XCTAssertTrue(categories(in: plan).contains(.legacyHistoryUnlinked))
    }

    func test16CompletedAndRecentBecomeReadOnlyArchiveEvidence() throws {
        let completed = legacyList(id: IDs.archive, kind: .completed)
        let recent = legacyList(id: IDs.recent, kind: .recent)
        let archiveEntry = legacyEntry(
            id: IDs.archiveEntry,
            listID: IDs.archive,
            checked: true
        )
        let source = baseSource(
            productList: productList(
                lists: [legacyList(), completed, recent],
                entries: [legacyEntry(), archiveEntry]
            )
        )
        let plan = try normalize(source)
        XCTAssertEqual(Set(plan.target.archiveLists.map(\.id)), [
            IDs.archive, IDs.recent
        ])
        XCTAssertEqual(plan.target.archiveEntries.map(\.id), [IDs.archiveEntry])
        XCTAssertEqual(
            plan.target.archiveEntries[0].resolutionReasonRawValue,
            "legacyUnknown"
        )
        XCTAssertTrue(plan.target.historyEvents.isEmpty)
    }

    func test17SavedLocationAndCompatibilityRelationshipArePreserved()
        throws
    {
        let location = savedLocation(itemIDs: [IDs.item])
        let plan = try normalize(baseSource(locations: [location]))
        XCTAssertEqual(plan.target.savedLocations, [location])
        XCTAssertEqual(plan.target.compatibilityItems, [compatibilityItem()])
        XCTAssertFalse(categories(in: plan).contains(.savedLocationUnresolved))
    }

    func test18UnprovableSavedLocationLinkIsExplicitException() throws {
        let location = savedLocation(itemIDs: [IDs.foreign])
        let plan = try normalize(baseSource(locations: [location]))
        XCTAssertEqual(
            plan.target.savedLocations[0].shoppingItemIDs,
            [IDs.foreign]
        )
        XCTAssertTrue(categories(in: plan).contains(.savedLocationUnresolved))
    }

    func test19TombstonedSessionReferenceNeverRestoresProduct() throws {
        let source = baseSource(
            productList: productList(products: [legacyProduct(removed: date(50))])
        )
        let plan = try normalize(source)
        XCTAssertEqual(
            plan.target.productListBase.products[0].libraryLifecycleRawValue,
            "removed"
        )
        XCTAssertTrue(
            categories(in: plan).contains(.tombstoneActiveReference)
        )
    }

    func test20PerSessionExceptionCapacityRetainsOverflowCount() throws {
        let tokens = (0..<110).map { "invalid-private-token-\($0)" }
            .joined(separator: ",")
        let plan = try normalize(
            baseSource(sessions: [session(itemRaw: tokens)])
        )
        let exceptions = plan.target.sessions[0].exceptions
        XCTAssertEqual(exceptions.count, 101)
        let overflow = try XCTUnwrap(exceptions.last)
        XCTAssertEqual(
            overflow.categoryRawValue,
            WayTaskMigrationExceptionCategory.sessionExceptionOverflow.rawValue
        )
        XCTAssertGreaterThan(overflow.occurrenceCount, 0)
        XCTAssertEqual(overflow.ordinal, 101)
    }

    func test21EquivalentEnumerationOrdersAreSemanticallyStable() throws {
        let firstSource = baseSource(sessions: [
            session(id: IDs.session), session(id: IDs.session2)
        ])
        let secondSource = WayTaskSessionHistoryArchiveSourceSnapshot(
            productList: firstSource.productList,
            sessions: Array(firstSource.sessions.reversed()),
            historyAggregates: Array(
                firstSource.historyAggregates.reversed()
            ),
            compatibilityItems: Array(
                firstSource.compatibilityItems.reversed()
            ),
            savedLocations: Array(firstSource.savedLocations.reversed())
        )
        let first = try normalize(firstSource)
        let second = try normalize(secondSource)
        XCTAssertEqual(first.target, second.target)
        XCTAssertEqual(first.exceptionFacts, second.exceptionFacts)
        XCTAssertEqual(first.semanticDigest, second.semanticDigest)
    }

    func test22ActiveClaimExpiresAtInclusiveTwelveHourBoundary() throws {
        let startedAt = recordingTime.addingTimeInterval(-12 * 60 * 60)
        let plan = try normalize(
            baseSource(sessions: [session(startedAt: startedAt)])
        )
        let migrated = plan.target.sessions[0]
        XCTAssertEqual(migrated.lifecycleRawValue, "expired")
        XCTAssertEqual(migrated.expiredAt, recordingTime)
        XCTAssertEqual(migrated.expirationReasonRawValue, "legacyInactivity")
        XCTAssertEqual(migrated.lines.count, 1)
    }

    func test23MultipleExactItemMatchesRemainUnresolved() throws {
        let secondProduct = WayTaskLegacyProductRecord(
            sourceRecordID: IDs.product2,
            productID: IDs.product2,
            legacyShoppingItemID: IDs.item,
            name: "Synthetic second identity",
            createdAt: date(0),
            updatedAt: date(1)
        )
        let secondEntry = WayTaskLegacyShoppingEntryRecord(
            sourceRecordID: IDs.entry2,
            entryID: IDs.entry2,
            listID: IDs.list,
            productID: IDs.product2,
            relationshipProductID: IDs.product2,
            legacyShoppingItemID: IDs.item,
            quantity: 1,
            isChecked: false,
            createdAt: date(0),
            sortOrder: 4
        )
        let source = baseSource(
            productList: productList(
                products: [legacyProduct(), secondProduct],
                entries: [legacyEntry(), secondEntry]
            )
        )
        let plan = try normalize(source)
        let line = plan.target.sessions[0].lines[0]
        XCTAssertNil(line.sourceEntryID)
        XCTAssertNil(line.productID)
        XCTAssertTrue(categories(in: plan).contains(.ambiguousSessionItem))
    }

    func test24ProtectedV3CandidateCompletesT08AndPreservesSourceBytes()
        throws
    {
        let fixture = try makePhysicalFixture()
        defer { fixture.remove() }
        let before = try componentBytes(fixture.sourceStoreURL)
        XCTAssertTrue(before.keys.contains("-wal"))
        XCTAssertTrue(before.keys.contains("-shm"))
        let migration = WayTaskProductStateMigration()
        let foundation = try unwrapFoundation(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        let productList = try unwrapProductList(
            migration.migrateProductListSemantics(foundation)
        )
        let complete = try unwrapT08(
            migration.migrateSessionHistoryArchiveSemantics(productList)
        )
        XCTAssertEqual(complete.targetValidation.sessions.map(\.id), [IDs.session])
        XCTAssertEqual(complete.targetValidation.historyAggregates.map(\.id), [IDs.history])
        XCTAssertEqual(complete.targetValidation.archiveLists.map(\.id), [IDs.archive])
        XCTAssertEqual(complete.targetValidation.savedLocations.map(\.id), [IDs.location])
        XCTAssertTrue(complete.sessionHistoryLocationSemanticConversionCompleted)
        XCTAssertFalse(complete.promotionAuthorized)
        XCTAssertFalse(complete.startupActivationAuthorized)
        XCTAssertEqual(before, try componentBytes(fixture.sourceStoreURL))
        _ = migration.cleanupOwnedCandidate(foundation)
    }

    func test25T08FailureDiscardsOnlyOwnedAttemptAndKeepsSourceBytes()
        throws
    {
        let fixture = try makePhysicalFixture()
        defer { fixture.remove() }
        let before = try componentBytes(fixture.sourceStoreURL)
        let neighbor = fixture.candidateRootURL.appendingPathComponent(
            "unowned-neighbor.txt"
        )
        try Data("retain".utf8).write(to: neighbor)
        let live = WayTaskProductStateMigration()
        let foundation = try unwrapFoundation(
            live.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        let productList = try unwrapProductList(
            live.migrateProductListSemantics(foundation)
        )
        var dependencies =
            WayTaskSessionHistoryArchiveMigrationDependencies.live
        dependencies.extendTargetStore = { _, _ in
            throw SyntheticFailure.injected
        }
        let migration = WayTaskProductStateMigration(
            dependencies: .live,
            semanticDependencies: .live,
            sessionHistoryDependencies: dependencies
        )
        let failure = try unwrapFailure(
            migration.migrateSessionHistoryArchiveSemantics(productList)
        )
        XCTAssertEqual(failure.classification, .sessionHistoryTargetWriteFailed)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: foundation.candidateAttemptDirectoryURL.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbor.path))
        XCTAssertEqual(before, try componentBytes(fixture.sourceStoreURL))
    }

    func test26NoStartupPromotionOrApplicationDefaultStoreAccess() throws {
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
        let plan = try normalize(baseSource())
        XCTAssertTrue(plan.target.historyEvents.isEmpty)
        XCTAssertNotEqual(
            ModelConfiguration().url.standardizedFileURL,
            URL(fileURLWithPath: "/private/tmp/WT033A-T08-owned.store")
                .standardizedFileURL
        )
    }

    // MARK: - Pure fixtures

    private func normalize(
        _ source: WayTaskSessionHistoryArchiveSourceSnapshot
    ) throws -> WayTaskSessionHistoryArchiveSemanticPlan {
        let productListPlan = try WayTaskProductListSemanticNormalizer.normalize(
            source.productList,
            recordingTime: recordingTime
        )
        return try WayTaskSessionHistoryArchiveSemanticNormalizer.normalize(
            source,
            productListTarget: productListPlan.target,
            aliases: productListPlan.aliases,
            recordingTime: recordingTime,
            digestKey: digestKey
        )
    }

    private func baseSource(
        productList: WayTaskLegacyProductListSnapshot? = nil,
        sessions: [WayTaskLegacySessionRecord]? = nil,
        history: [WayTaskLegacyHistoryAggregateRecord] = [],
        locations: [WayTaskLegacySavedLocationRecord] = []
    ) -> WayTaskSessionHistoryArchiveSourceSnapshot {
        WayTaskSessionHistoryArchiveSourceSnapshot(
            productList: productList ?? self.productList(),
            sessions: sessions ?? [session()],
            historyAggregates: history,
            compatibilityItems: [compatibilityItem()],
            savedLocations: locations
        )
    }

    private func productList(
        products: [WayTaskLegacyProductRecord]? = nil,
        lists: [WayTaskLegacyShoppingListRecord]? = nil,
        entries: [WayTaskLegacyShoppingEntryRecord]? = nil
    ) -> WayTaskLegacyProductListSnapshot {
        WayTaskLegacyProductListSnapshot(
            products: products ?? [legacyProduct()],
            lists: lists ?? [legacyList()],
            entries: entries ?? [legacyEntry()],
            compatibilityRecords: [
                WayTaskLegacyCompatibilityRecord(
                    sourceRecordID: IDs.item,
                    compatibilityID: IDs.item,
                    isCompleted: false
                )
            ]
        )
    }

    private func legacyProduct(
        removed: Date? = nil
    ) -> WayTaskLegacyProductRecord {
        WayTaskLegacyProductRecord(
            sourceRecordID: IDs.product,
            productID: IDs.product,
            legacyShoppingItemID: IDs.item,
            name: privateName,
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            barcode: privateBarcode,
            createdAt: date(0),
            updatedAt: date(1),
            removedAt: removed
        )
    }

    private func legacyList(
        id: UUID = IDs.list,
        kind: ShoppingListKind = .weekly
    ) -> WayTaskLegacyShoppingListRecord {
        WayTaskLegacyShoppingListRecord(
            sourceRecordID: id,
            listID: id,
            title: "Synthetic List",
            kindRawValue: kind.rawValue,
            createdAt: date(0),
            updatedAt: date(1),
            isDefault: false
        )
    }

    private func legacyEntry(
        id: UUID = IDs.entry,
        listID: UUID = IDs.list,
        productID: UUID = IDs.product,
        checked: Bool = false
    ) -> WayTaskLegacyShoppingEntryRecord {
        WayTaskLegacyShoppingEntryRecord(
            sourceRecordID: id,
            entryID: id,
            listID: listID,
            productID: productID,
            relationshipProductID: productID,
            legacyShoppingItemID: IDs.item,
            quantity: 2,
            isChecked: checked,
            createdAt: date(0),
            sortOrder: 3
        )
    }

    private func compatibilityItem()
        -> WayTaskLegacyCompatibilityEvidenceRecord
    {
        WayTaskLegacyCompatibilityEvidenceRecord(
            id: IDs.item,
            name: privateName,
            isCompleted: false,
            imageData: Data([1, 2, 3]),
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            barcode: privateBarcode,
            imageURLString: "https://example.invalid/synthetic.png",
            dateAdded: date(0),
            sourceRawValue: ProductSource.manual.rawValue,
            productType: nil,
            flavor: nil,
            packageSize: nil,
            packageType: nil,
            visibleText: nil,
            searchKeywordsRawValue: nil
        )
    }

    private func session(
        id: UUID = IDs.session,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        isActive: Bool = true,
        itemRaw: String = IDs.item.uuidString,
        collectedRaw: String = "",
        listID: UUID? = IDs.list,
        latitude: Double? = 31.75,
        longitude: Double? = 35.22
    ) -> WayTaskLegacySessionRecord {
        WayTaskLegacySessionRecord(
            id: id,
            startedAt: startedAt ?? date(0),
            finishedAt: finishedAt,
            isActive: isActive,
            itemIDListRawValue: itemRaw,
            collectedItemIDListRawValue: collectedRaw,
            shoppingListID: listID,
            selectedStoreID: IDs.store,
            selectedStoreName: privateStoreName,
            selectedStoreLatitude: latitude,
            selectedStoreLongitude: longitude
        )
    }

    private func legacyHistory() -> WayTaskLegacyHistoryAggregateRecord {
        WayTaskLegacyHistoryAggregateRecord(
            id: IDs.history,
            productKey: "barcode:\(privateBarcode)",
            productName: privateName,
            barcode: privateBarcode,
            firstAddedDate: date(0),
            lastAddedDate: date(40),
            addCount: 3,
            lastSourceRawValue: ProductSource.manual.rawValue,
            averageInterval: 20,
            lastCompletedDate: date(30)
        )
    }

    private func savedLocation(
        itemIDs: [UUID]
    ) -> WayTaskLegacySavedLocationRecord {
        WayTaskLegacySavedLocationRecord(
            id: IDs.location,
            title: privateStoreName,
            latitude: 31.75,
            longitude: 35.22,
            radius: 200,
            storeCategoryRawValue: nil,
            addressText: "Synthetic Address",
            notes: "private synthetic note",
            sourceTypeRawValue: DataSourceType.userGenerated.rawValue,
            shoppingItemIDs: itemIDs
        )
    }

    private func categories(
        in plan: WayTaskSessionHistoryArchiveSemanticPlan
    ) -> Set<WayTaskMigrationExceptionCategory> {
        Set(plan.exceptionFacts.map(\.category))
    }

    private var privateName: String { "PRIVATE_T08_PRODUCT_NAME" }
    private var privateBarcode: String { "PRIVATE_T08_BARCODE_9988" }
    private var privateStoreName: String { "PRIVATE_T08_STORE_NAME" }

    // MARK: - Physical fixture

    private func makePhysicalFixture() throws -> PhysicalFixture {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "WT033A-T08-Test-\(UUID().uuidString)",
                isDirectory: true
            )
        let builderRoot = root.appendingPathComponent(
            "synthetic-builder",
            isDirectory: true
        )
        let sourceRoot = root.appendingPathComponent(
            "protected-source",
            isDirectory: true
        )
        let candidateRoot = root.appendingPathComponent(
            "owned-candidates",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: builderRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidateRoot,
            withIntermediateDirectories: true
        )
        let builderStore = builderRoot.appendingPathComponent("builder.store")
        let sourceStore = sourceRoot.appendingPathComponent("protected.store")
        let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
        let configuration = ModelConfiguration(
            "WT033A-T08-Synthetic-Builder",
            schema: schema,
            url: builderStore,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let item = ShoppingItem(
            id: IDs.item,
            name: privateName,
            barcode: privateBarcode,
            dateAdded: date(0)
        )
        let product = Product(
            id: IDs.product,
            legacyShoppingItemID: IDs.item,
            name: privateName,
            barcode: privateBarcode,
            dateAdded: date(0),
            updatedAt: date(1)
        )
        let list = ShoppingList(
            id: IDs.list,
            title: "Synthetic List",
            kind: .weekly,
            createdAt: date(0),
            updatedAt: date(1)
        )
        let archive = ShoppingList(
            id: IDs.archive,
            title: "Synthetic Archive",
            kind: .completed,
            createdAt: date(0),
            updatedAt: date(1)
        )
        let entry = ShoppingListEntry(
            id: IDs.entry,
            shoppingListID: IDs.list,
            product: product,
            legacyShoppingItemID: IDs.item,
            quantity: 2,
            createdAt: date(0),
            sortOrder: 1
        )
        let archiveEntry = ShoppingListEntry(
            id: IDs.archiveEntry,
            shoppingListID: IDs.archive,
            product: product,
            legacyShoppingItemID: IDs.item,
            quantity: 1,
            isChecked: true,
            createdAt: date(0),
            sortOrder: 1
        )
        let session = ShoppingSession(
            id: IDs.session,
            startedAt: date(0),
            itemIDs: [IDs.item],
            collectedItemIDs: [IDs.item],
            shoppingListID: IDs.list,
            selectedStoreID: IDs.store,
            selectedStoreName: privateStoreName,
            selectedStoreLatitude: 31.75,
            selectedStoreLongitude: 35.22
        )
        let history = ProductHistory(
            id: IDs.history,
            productKey: "barcode:\(privateBarcode)",
            productName: privateName,
            barcode: privateBarcode,
            firstAddedDate: date(0),
            lastAddedDate: date(10)
        )
        let location = GeoLocation(
            id: IDs.location,
            title: privateStoreName,
            latitude: 31.75,
            longitude: 35.22,
            notes: "private synthetic note",
            shoppingItems: [item]
        )
        context.insert(item)
        context.insert(product)
        context.insert(list)
        context.insert(archive)
        context.insert(entry)
        context.insert(archiveEntry)
        context.insert(session)
        context.insert(history)
        context.insert(location)
        try context.save()
        try copyStoreComponents(from: builderStore, to: sourceStore)
        return PhysicalFixture(
            rootURL: root,
            sourceStoreURL: sourceStore,
            candidateRootURL: candidateRoot
        )
    }

    private func copyStoreComponents(from source: URL, to target: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let sourceURL = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                continue
            }
            try FileManager.default.copyItem(
                at: sourceURL,
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

    private func unwrapProductList(
        _ result: WayTaskProductListSemanticMigrationResult
    ) throws -> WayTaskProductListSemanticReceipt {
        guard case let .complete(receipt) = result else {
            throw SyntheticFailure.unexpectedResult
        }
        return receipt
    }

    private func unwrapT08(
        _ result: WayTaskSessionHistoryArchiveMigrationResult
    ) throws -> WayTaskSessionHistoryArchiveMigrationReceipt {
        guard case let .complete(receipt) = result else {
            if case let .failed(failure) = result {
                XCTFail("T-08 migration failed: \(failure.classification)")
            }
            throw SyntheticFailure.unexpectedResult
        }
        return receipt
    }

    private func unwrapFailure(
        _ result: WayTaskSessionHistoryArchiveMigrationResult
    ) throws -> WayTaskMigrationFailure {
        guard case let .failed(failure) = result else {
            throw SyntheticFailure.unexpectedResult
        }
        return failure
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }

    private struct PhysicalFixture {
        let rootURL: URL
        let sourceStoreURL: URL
        let candidateRootURL: URL

        func request(seed: UUID) -> WayTaskMigrationRequest {
            WayTaskMigrationRequest(
                sourceStoreURL: sourceStoreURL,
                candidateRootURL: candidateRootURL,
                attemptSeed: seed
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private enum SyntheticFailure: Error {
        case injected
        case unexpectedResult
    }

    private enum IDs {
        nonisolated static let product = uuid("18000000-0000-0000-0000-000000000001")
        nonisolated static let item = uuid("18000000-0000-0000-0000-000000000002")
        nonisolated static let list = uuid("18000000-0000-0000-0000-000000000003")
        nonisolated static let entry = uuid("18000000-0000-0000-0000-000000000004")
        nonisolated static let session = uuid("18000000-0000-0000-0000-000000000005")
        nonisolated static let session2 = uuid("18000000-0000-0000-0000-000000000006")
        nonisolated static let store = uuid("18000000-0000-0000-0000-000000000007")
        nonisolated static let foreign = uuid("18000000-0000-0000-0000-000000000008")
        nonisolated static let history = uuid("18000000-0000-0000-0000-000000000009")
        nonisolated static let archive = uuid("18000000-0000-0000-0000-000000000010")
        nonisolated static let recent = uuid("18000000-0000-0000-0000-000000000011")
        nonisolated static let archiveEntry = uuid("18000000-0000-0000-0000-000000000012")
        nonisolated static let location = uuid("18000000-0000-0000-0000-000000000013")
        nonisolated static let product2 = uuid("18000000-0000-0000-0000-000000000014")
        nonisolated static let entry2 = uuid("18000000-0000-0000-0000-000000000015")

        nonisolated private static func uuid(_ value: String) -> UUID {
            UUID(uuidString: value)!
        }
    }
}
