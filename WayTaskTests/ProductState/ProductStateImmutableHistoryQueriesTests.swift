import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateImmutableHistoryQueriesTests: XCTestCase {
    func testExactProductQueryPreservesEveryAuthorizedEventField()
        throws {
        let fixture = try makeFixture("exact-fields")
        let event = makeEvent(
            id: 1,
            product: 2,
            meaning: "needResolved",
            reason: "alreadyHave",
            list: 3,
            entry: 4,
            command: 5,
            provenance: "userCommand",
            at: date(6),
            displaySnapshot: 7
        )
        fixture.repositories.history.stageInsertion(of: event)
        try fixture.context.save()
        let before = eventSnapshot(event)

        let result = query(fixture, product: 2)
        guard case let .success(projection, diagnostic) = result,
              let projected = projection.events.first else {
            return XCTFail("Expected exact Product History projection")
        }

        XCTAssertEqual(projected.eventID, historyID(1))
        XCTAssertEqual(projected.productID, productID(2))
        XCTAssertEqual(projected.kind, .needResolved)
        XCTAssertEqual(projected.meaningRawValue, "needResolved")
        XCTAssertEqual(projected.resolutionReason, .alreadyHave)
        XCTAssertEqual(projected.resolutionReasonRawValue, "alreadyHave")
        XCTAssertNil(projected.sessionOutcome)
        XCTAssertNil(projected.sessionOutcomeRawValue)
        XCTAssertEqual(projected.sourceListID, listID(3))
        XCTAssertEqual(projected.sourceEntryID, entryID(4))
        XCTAssertNil(projected.sessionID)
        XCTAssertNil(projected.sessionLineID)
        XCTAssertEqual(projected.commandID, commandID(5))
        XCTAssertEqual(projected.provenance, .nativeUserCommand)
        XCTAssertEqual(projected.provenanceRawValue, "userCommand")
        XCTAssertEqual(projected.occurredAt, date(6))
        XCTAssertEqual(projected.displaySnapshotID, uuid(7))
        XCTAssertEqual(projected.contribution, .included)
        XCTAssertEqual(diagnostic.outcome, .success)
        XCTAssertEqual(eventSnapshot(event), before)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testOrderingWindowAndNoExpiryRetentionAreDeterministic()
        throws {
        let fixture = try makeFixture("ordering-retention")
        for value in [1, 2, 3] {
            fixture.repositories.history.stageInsertion(
                of: makeEvent(
                    id: value,
                    product: 10,
                    meaning: "needAdded",
                    list: 11,
                    entry: 12 + value,
                    command: 20 + value,
                    at: date(value)
                )
            )
        }
        try fixture.context.save()

        let result = query(
            fixture,
            product: 10,
            maximumEventCount: 2,
            order: .newestFirst
        )
        guard case let .success(projection, diagnostic) = result else {
            return XCTFail("Expected bounded history projection")
        }

        XCTAssertEqual(projection.events.map(\.occurredAt), [date(3), date(2)])
        XCTAssertEqual(projection.retainedEventCount, 3)
        XCTAssertEqual(projection.returnedEventCount, 2)
        XCTAssertEqual(projection.omittedEventCount, 1)
        XCTAssertEqual(
            projection.retentionPolicy,
            .retainAllNoAutomaticExpiryV103
        )
        XCTAssertEqual(diagnostic.retainedEventCount, 3)
        XCTAssertEqual(
            try fixture.context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
            ),
            3
        )
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testDuplicateEventAndCausalReplayContributeAtMostOnce()
        throws {
        let first = makeEvent(
            id: 30,
            product: 31,
            meaning: "needAdded",
            list: 32,
            entry: 33,
            command: 34,
            at: date(1)
        )
        let identicalID = makeEvent(
            id: 30,
            product: 31,
            meaning: "needAdded",
            list: 32,
            entry: 33,
            command: 34,
            at: date(1)
        )
        let replay = makeEvent(
            id: 35,
            product: 31,
            meaning: "needAdded",
            list: 32,
            entry: 33,
            command: 34,
            at: date(2)
        )
        let boundary = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(
                events: [replay, identicalID, first]
            )
        )

        let result = boundary.history(request(product: 31))
        guard case let .success(projection, diagnostic) = result else {
            return XCTFail("Expected replay-safe projection")
        }

        XCTAssertEqual(projection.aggregate.needAddedCount, 1)
        XCTAssertEqual(projection.aggregate.nativeUserCommandEventCount, 1)
        XCTAssertEqual(projection.aggregate.duplicateContributionCount, 2)
        XCTAssertEqual(diagnostic.duplicateContributionCount, 2)
        XCTAssertEqual(
            projection.events.filter { $0.contribution == .included }.count,
            1
        )
        XCTAssertEqual(
            projection.events.filter {
                $0.contribution == .duplicateEventIdentity
            }.count,
            1
        )
        XCTAssertEqual(
            projection.events.filter {
                $0.contribution == .duplicateCausalReplay
            }.count,
            1
        )
    }

    func testNamedProvenanceRemainsSeparatedAndOrdered()
        throws {
        let events = [
            makeEvent(
                id: 40,
                product: 41,
                meaning: "needAdded",
                list: 42,
                entry: 43,
                command: 44,
                provenance: "userCommand",
                at: date(1)
            ),
            makeEvent(
                id: 45,
                product: 41,
                meaning: "sessionOutcome",
                outcome: "purchased",
                list: 42,
                entry: 43,
                session: 46,
                line: 47,
                command: 48,
                provenance: "sessionFinish",
                at: date(2)
            ),
            makeEvent(
                id: 49,
                product: 41,
                meaning: "legacyActivity",
                provenance: "legacyMigration",
                at: date(3)
            ),
            makeEvent(
                id: 50,
                product: 41,
                meaning: "mystery",
                provenance: "mystery",
                at: date(4)
            )
        ]
        let boundary = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: events.reversed())
        )

        guard case let .success(projection, diagnostic) = boundary.history(
            request(product: 41)
        ) else {
            return XCTFail("Expected provenance-aware projection")
        }

        XCTAssertEqual(
            projection.events.map(\.provenance),
            [
                .nativeUserCommand,
                .nativeSessionFinish,
                .legacyMigration,
                .unsupported
            ]
        )
        XCTAssertEqual(projection.aggregate.nativeUserCommandEventCount, 1)
        XCTAssertEqual(projection.aggregate.nativeSessionFinishEventCount, 1)
        XCTAssertEqual(projection.aggregate.legacyMigrationEventCount, 1)
        XCTAssertEqual(projection.aggregate.unsupportedEvidenceCount, 1)
        XCTAssertEqual(projection.aggregate.confirmedPurchaseCount, 1)
        XCTAssertEqual(
            diagnostic.provenanceCounts.map(\.provenance),
            [
                .nativeUserCommand,
                .nativeSessionFinish,
                .legacyMigration,
                .unsupported
            ]
        )
    }

    func testPurchaseRequiresExactNativeSessionFinishEvidence()
        throws {
        let events = [
            makeEvent(
                id: 60,
                product: 61,
                meaning: "needResolved",
                reason: "purchased",
                list: 62,
                entry: 63,
                command: 64,
                provenance: "userCommand",
                at: date(1)
            ),
            makeEvent(
                id: 65,
                product: 61,
                meaning: "sessionOutcome",
                outcome: "purchased",
                command: 66,
                provenance: "sessionFinish",
                at: date(2)
            ),
            makeEvent(
                id: 67,
                product: 61,
                meaning: "sessionOutcome",
                outcome: "purchased",
                session: 68,
                line: 69,
                command: 70,
                provenance: "legacyMigration",
                at: date(3)
            ),
            makeEvent(
                id: 71,
                product: 61,
                meaning: "needResolved",
                reason: "alreadyHave",
                list: 62,
                entry: 63,
                command: 72,
                provenance: "userCommand",
                at: date(4)
            )
        ]
        let boundary = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: events)
        )

        guard case let .success(projection, _) = boundary.history(
            request(product: 61)
        ) else {
            return XCTFail("Expected conservative aggregate")
        }

        XCTAssertEqual(projection.aggregate.confirmedPurchaseCount, 0)
        XCTAssertEqual(projection.aggregate.needResolvedAlreadyHaveCount, 1)
        XCTAssertEqual(projection.aggregate.legacyMigrationEventCount, 1)
        XCTAssertEqual(projection.aggregate.unsupportedEvidenceCount, 2)
    }

    func testExactSessionFinishPurchasePreservesCausalIdentities()
        throws {
        let event = makeEvent(
            id: 80,
            product: 81,
            meaning: "sessionOutcome",
            reason: "purchased",
            outcome: "purchased",
            list: 82,
            entry: 83,
            session: 84,
            line: 85,
            command: 86,
            provenance: "sessionFinish",
            at: date(7),
            displaySnapshot: 87
        )
        let boundary = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: [event])
        )

        guard case let .success(projection, _) = boundary.history(
            request(product: 81)
        ), let projected = projection.events.first else {
            return XCTFail("Expected exact Finish evidence")
        }

        XCTAssertEqual(projection.aggregate.confirmedPurchaseCount, 1)
        XCTAssertEqual(projected.sessionOutcome, .purchased)
        XCTAssertEqual(projected.sessionID, sessionID(84))
        XCTAssertEqual(projected.sessionLineID, lineID(85))
        XCTAssertEqual(projected.commandID, commandID(86))
        XCTAssertEqual(projected.sourceListID, listID(82))
        XCTAssertEqual(projected.sourceEntryID, entryID(83))
        XCTAssertEqual(projected.displaySnapshotID, uuid(87))
    }

    func testEquivalentEnumerationProducesIdenticalProjection()
        throws {
        let events = [
            makeEvent(
                id: 90,
                product: 91,
                meaning: "needAdded",
                list: 92,
                entry: 93,
                command: 94,
                at: date(3)
            ),
            makeEvent(
                id: 95,
                product: 91,
                meaning: "needReopened",
                list: 92,
                entry: 93,
                command: 96,
                at: date(2)
            ),
            makeEvent(
                id: 97,
                product: 91,
                meaning: "listMembershipRemoved",
                list: 92,
                entry: 93,
                command: 98,
                at: date(1)
            )
        ]
        let first = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: events)
        ).history(request(product: 91))
        let second = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: events.reversed())
        ).history(request(product: 91))

        XCTAssertEqual(first, second)
    }

    func testInvalidAndUnavailableQueriesArePrivacySafeAndNonMutating()
        throws {
        let invalid = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: [])
        ).history(
            request(product: 100, maximumEventCount: 0)
        )
        let unavailable = ProductStateHistoryQueryBoundary(
            historyRepository: ThrowingHistoryRepository()
        ).history(request(product: 100))

        guard case let .invalidRequest(invalidDiagnostic) = invalid,
              case let .unavailable(unavailableDiagnostic) = unavailable else {
            return XCTFail("Expected deterministic query failures")
        }
        XCTAssertEqual(invalidDiagnostic.failure, .invalidLimit)
        XCTAssertEqual(
            unavailableDiagnostic.failure,
            .repositoryReadFailed
        )
        let encoded = try JSONEncoder().encode(unavailableDiagnostic)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for privateValue in [
            "PRIVATE PRODUCT", "PRIVATE LIST", "PRIVATE BARCODE",
            "PRIVATE NOTE", "/private/path", "raw database failure"
        ] {
            XCTAssertFalse(text.contains(privateValue))
        }
    }

    func testShoppingMemoryKeepsNativeAndLegacyAuthoritySeparate()
        throws {
        let event = makeEvent(
            id: 110,
            product: 111,
            meaning: "needAdded",
            list: 112,
            entry: 113,
            command: 114,
            at: date(2)
        )
        let queries = ProductStateHistoryQueryBoundary(
            historyRepository: StubHistoryRepository(events: [event])
        )
        let linked = legacyEvidence(
            id: 115,
            product: 111,
            count: 8,
            completedAt: date(8)
        )
        let unlinked = legacyEvidence(
            id: 116,
            product: nil,
            count: 20,
            completedAt: date(9)
        )

        let result = ShoppingMemoryService().targetHistoryMemory(
            request(product: 111),
            using: queries,
            legacyEvidence: [unlinked, linked]
        )
        guard case let .success(projection, diagnostic) = result else {
            return XCTFail("Expected target Shopping Memory projection")
        }

        XCTAssertEqual(projection.nativeHistory.aggregate.needAddedCount, 1)
        XCTAssertEqual(
            projection.nativeHistory.aggregate.confirmedPurchaseCount,
            0
        )
        XCTAssertEqual(projection.linkedLegacyEvidence, [linked])
        XCTAssertEqual(projection.rejectedLegacyEvidenceCount, 1)
        XCTAssertEqual(
            Set(projection.provenances),
            [.nativeUserCommand, .retainedLegacyAggregate]
        )
        XCTAssertEqual(diagnostic.linkedLegacyEvidenceCount, 1)
        XCTAssertEqual(diagnostic.rejectedLegacyEvidenceCount, 1)
        XCTAssertEqual(linked.legacyCompletionObservedAt, date(8))
    }

    func testShoppingMemoryPropagatesQueryFailureWithoutLegacyFallback()
        throws {
        let legacy = legacyEvidence(
            id: 120,
            product: 121,
            count: 99,
            completedAt: date(4)
        )
        let result = ShoppingMemoryService().targetHistoryMemory(
            request(product: 121),
            using: ThrowingHistoryQuery(),
            legacyEvidence: [legacy]
        )

        guard case let .unavailable(diagnostic) = result else {
            return XCTFail("Expected unavailable without fallback")
        }
        XCTAssertEqual(diagnostic.nativeEventCount, 0)
        XCTAssertEqual(diagnostic.linkedLegacyEvidenceCount, 0)
        XCTAssertEqual(diagnostic.rejectedLegacyEvidenceCount, 1)
        XCTAssertTrue(diagnostic.provenances.isEmpty)
    }

    func testCatalogUsesOnlyExactNativeIdentityAndNeedAddedEvidence()
        throws {
        let valid = aggregate(
            product: 130,
            needAdded: 3,
            lastNeedAddedAt: date(5),
            confirmedPurchase: 7
        )
        let wrongIdentity = aggregate(
            product: 131,
            needAdded: 20,
            lastNeedAddedAt: date(6)
        )
        let purchaseOnly = aggregate(
            product: 132,
            needAdded: 0,
            lastNeedAddedAt: nil,
            confirmedPurchase: 50
        )

        let result = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [
                ProductCatalogNativeHistoryInput(
                    productID: productID(130),
                    exactCatalogProductID: "catalog-exact",
                    displayNameSnapshot: "PRIVATE NAME",
                    history: valid
                ),
                ProductCatalogNativeHistoryInput(
                    productID: productID(130),
                    exactCatalogProductID: "catalog-wrong",
                    displayNameSnapshot: "SAME NAME",
                    history: wrongIdentity
                ),
                ProductCatalogNativeHistoryInput(
                    productID: productID(132),
                    exactCatalogProductID: "purchase-only",
                    displayNameSnapshot: "PURCHASE",
                    history: purchaseOnly
                )
            ],
            legacy: [],
            maximumRecordCount: 10
        )

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.catalogProductID, "catalog-exact")
        XCTAssertEqual(result.records.first?.selectionCount, 3)
        XCTAssertEqual(
            result.records.first?.provenance,
            .nativeCommittedCommandEvents
        )
        XCTAssertEqual(result.diagnostic.rejectedInputCount, 2)
    }

    func testCatalogLegacyEvidenceStaysLabeledAndDoesNotBecomeNative()
        throws {
        let legacy = legacyEvidence(
            id: 140,
            product: nil,
            count: 6,
            completedAt: date(7)
        )
        let result = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [],
            legacy: [
                ProductCatalogLegacyHistoryInput(
                    displayNameSnapshot: "  Legacy---Bread  ",
                    evidence: legacy
                )
            ],
            maximumRecordCount: 10
        )

        XCTAssertEqual(result.records.count, 1)
        XCTAssertNil(result.records.first?.catalogProductID)
        XCTAssertEqual(result.records.first?.selectionCount, 6)
        XCTAssertEqual(
            result.records.first?.provenance,
            .retainedLegacyAggregate
        )
        XCTAssertEqual(
            result.diagnostic.provenances,
            [.retainedLegacyAggregate]
        )
    }

    func testCatalogReplayAndBoundsAreDeterministicWithoutDoubleCount()
        throws {
        let first = ProductCatalogNativeHistoryInput(
            productID: productID(150),
            exactCatalogProductID: "catalog-a",
            displayNameSnapshot: "A",
            history: aggregate(
                product: 150,
                needAdded: 4,
                lastNeedAddedAt: date(4)
            )
        )
        let second = ProductCatalogNativeHistoryInput(
            productID: productID(151),
            exactCatalogProductID: "catalog-b",
            displayNameSnapshot: "B",
            history: aggregate(
                product: 151,
                needAdded: 3,
                lastNeedAddedAt: date(3)
            )
        )

        let lhs = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [second, first, first],
            legacy: [],
            maximumRecordCount: 1
        )
        let rhs = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [first, first, second],
            legacy: [],
            maximumRecordCount: 1
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.records.count, 1)
        XCTAssertEqual(lhs.records.first?.selectionCount, 4)
        XCTAssertEqual(lhs.diagnostic.duplicateInputCount, 1)
    }

    func testCatalogConflictingExactIdentityIsRejectedRatherThanSelected()
        throws {
        let history = aggregate(
            product: 155,
            needAdded: 2,
            lastNeedAddedAt: date(2)
        )
        let result = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [
                ProductCatalogNativeHistoryInput(
                    productID: productID(155),
                    exactCatalogProductID: "catalog-a",
                    displayNameSnapshot: "A",
                    history: history
                ),
                ProductCatalogNativeHistoryInput(
                    productID: productID(155),
                    exactCatalogProductID: "catalog-b",
                    displayNameSnapshot: "B",
                    history: history
                )
            ],
            legacy: [],
            maximumRecordCount: 10
        )

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.diagnostic.rejectedInputCount, 2)
        XCTAssertEqual(result.diagnostic.duplicateInputCount, 0)
    }

    func testLegacyAggregatePreservesUnsupportedCountWithoutReinterpretation()
        throws {
        let evidence = ProductStateLegacyHistoryAggregateEvidence(
            legacyRecordID: uuid(156),
            provenProductID: nil,
            observationCount: -4,
            firstObservedAt: date(1),
            lastObservedAt: date(2),
            averageInterval: nil,
            legacyCompletionObservedAt: date(3)
        )
        let result = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [],
            legacy: [
                ProductCatalogLegacyHistoryInput(
                    displayNameSnapshot: "Legacy",
                    evidence: evidence
                )
            ],
            maximumRecordCount: 10
        )

        XCTAssertEqual(evidence.observationCount, -4)
        XCTAssertEqual(evidence.legacyCompletionObservedAt, date(3))
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.diagnostic.rejectedInputCount, 1)
    }

    func testPersonalizationProfileExposesEveryContributingProvenance()
        async throws {
        let now = date(10)
        let index = ProductCatalogPersonalizationIndex(history: [
            ProductCatalogSelectionHistory(
                catalogProductID: "catalog-160",
                productName: "Native",
                selectionCount: 2,
                mostRecentSelectionDate: now,
                provenance: .nativeCommittedCommandEvents
            ),
            ProductCatalogSelectionHistory(
                catalogProductID: "catalog-160",
                productName: "Legacy",
                selectionCount: 9,
                mostRecentSelectionDate: date(9),
                provenance: .retainedLegacyAggregate
            )
        ])

        let profile = try XCTUnwrap(
            index.profile(
                catalogProductID: "catalog-160",
                normalizedNames: []
            )
        )
        XCTAssertEqual(profile.selectionCount, 9)
        XCTAssertEqual(
            profile.provenances,
            [.nativeCommittedCommandEvents, .retainedLegacyAggregate]
        )
    }

    func testCatalogDiagnosticContainsNoPrivateDisplayContent()
        throws {
        let result = ProductCatalogTargetHistoryBuilder.makeHistory(
            native: [
                ProductCatalogNativeHistoryInput(
                    productID: productID(170),
                    exactCatalogProductID: "catalog-private",
                    displayNameSnapshot: "PRIVATE CATALOG DISPLAY",
                    history: aggregate(
                        product: 170,
                        needAdded: 1,
                        lastNeedAddedAt: date(1)
                    )
                )
            ],
            legacy: [],
            maximumRecordCount: 10
        )
        let encoded = try JSONEncoder().encode(result.diagnostic)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(text.contains("PRIVATE CATALOG DISPLAY"))
        XCTAssertFalse(text.contains("catalog-private"))
        XCTAssertEqual(result.diagnostic.returnedRecordCount, 1)
    }

    func testT12ScopeIsReadOnlyInactiveAndDoesNotImplementT13()
        throws {
        let root = repositoryRoot
        let queries = try source(
            "WayTask/ProductState/Application/ProductStateQueries.swift",
            root
        )
        let memory = try source("ShoppingMemoryService.swift", root)
        let catalog = try source(
            "WayTask/ProductCatalog/ProductCatalogPersonalization.swift",
            root
        )
        let startup = try source(
            "WayTask/Persistence/WayTaskStartupPersistence.swift",
            root
        )
        let app = try source("WayTask/WayTaskApp.swift", root)
        let content = try source("WayTask/ContentView.swift", root)
        let productView = try source("ProductListView.swift", root)
        let schema = try source("WayTask/Persistence/WayTaskSchema.swift", root)

        XCTAssertTrue(queries.contains("final class ProductStateHistoryQueryBoundary"))
        XCTAssertFalse(queries.contains("import SwiftData"))
        XCTAssertFalse(queries.contains("ModelContext"))
        XCTAssertFalse(queries.contains("ModelContainer"))
        XCTAssertFalse(queries.contains("stageInsertion"))
        XCTAssertFalse(queries.contains("stageDeletion"))
        XCTAssertFalse(queries.contains(".save("))
        XCTAssertFalse(queries.contains("fatalError"))
        XCTAssertFalse(queries.contains("defaultStoreURL"))
        XCTAssertFalse(queries.contains("RevisionCache"))
        XCTAssertFalse(queries.contains("MapProjection"))
        XCTAssertTrue(memory.contains("func targetHistoryMemory("))
        XCTAssertTrue(catalog.contains("ProductCatalogTargetHistoryBuilder"))
        XCTAssertFalse(startup.contains("ProductStateHistoryQueryBoundary"))
        XCTAssertFalse(app.contains("ProductStateHistoryQueryBoundary"))
        XCTAssertFalse(content.contains("ProductStateHistoryQueryBoundary"))
        XCTAssertFalse(productView.contains("ProductStateHistoryQueryBoundary"))
        XCTAssertTrue(
            schema.contains("Schema(versionedSchema: WayTaskSchemaV3.self)")
        )
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T12-\(name)-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return Fixture(
            container: container,
            context: context,
            repositories: ProductStateRepositories(modelContext: context)
        )
    }

    private func query(
        _ fixture: Fixture,
        product: Int,
        maximumEventCount: Int = 100,
        order: ProductStateHistoryQueryOrder = .oldestFirst
    ) -> ProductStateHistoryQueryOutcome {
        ProductStateHistoryQueryBoundary(
            historyRepository: fixture.repositories.history
        ).history(
            request(
                product: product,
                maximumEventCount: maximumEventCount,
                order: order
            )
        )
    }

    private func request(
        product: Int,
        maximumEventCount: Int = 100,
        order: ProductStateHistoryQueryOrder = .oldestFirst
    ) -> ProductStateHistoryQueryRequest {
        ProductStateHistoryQueryRequest(
            productID: productID(product),
            maximumEventCount: maximumEventCount,
            order: order
        )
    }

    private func makeEvent(
        id: Int,
        product: Int,
        meaning: String,
        reason: String? = nil,
        outcome: String? = nil,
        list: Int? = nil,
        entry: Int? = nil,
        session: Int? = nil,
        line: Int? = nil,
        command: Int? = nil,
        provenance: String = "userCommand",
        at: Date,
        displaySnapshot: Int? = nil
    ) -> WayTaskSchemaV4.ProductHistoryEvent {
        WayTaskSchemaV4.ProductHistoryEvent(
            id: uuid(id),
            productID: uuid(product),
            meaningRawValue: meaning,
            resolutionReasonRawValue: reason,
            sessionOutcomeRawValue: outcome,
            sourceListID: list.map(uuid),
            sourceEntryID: entry.map(uuid),
            sessionID: session.map(uuid),
            sessionLineID: line.map(uuid),
            commandID: command.map(uuid),
            provenanceRawValue: provenance,
            occurredAt: at,
            displaySnapshotID: displaySnapshot.map(uuid)
        )
    }

    private func eventSnapshot(
        _ event: WayTaskSchemaV4.ProductHistoryEvent
    ) -> [String] {
        [
            event.id.uuidString,
            event.productID.uuidString,
            event.meaningRawValue,
            event.resolutionReasonRawValue ?? "",
            event.sessionOutcomeRawValue ?? "",
            event.sourceListID?.uuidString ?? "",
            event.sourceEntryID?.uuidString ?? "",
            event.sessionID?.uuidString ?? "",
            event.sessionLineID?.uuidString ?? "",
            event.commandID?.uuidString ?? "",
            event.provenanceRawValue,
            String(event.occurredAt.timeIntervalSince1970),
            event.displaySnapshotID?.uuidString ?? ""
        ]
    }

    private func legacyEvidence(
        id: Int,
        product: Int?,
        count: Int,
        completedAt: Date?
    ) -> ProductStateLegacyHistoryAggregateEvidence {
        ProductStateLegacyHistoryAggregateEvidence(
            legacyRecordID: uuid(id),
            provenProductID: product.map(productID),
            observationCount: count,
            firstObservedAt: date(1),
            lastObservedAt: date(3),
            averageInterval: 120,
            legacyCompletionObservedAt: completedAt
        )
    }

    private func aggregate(
        product: Int,
        needAdded: Int,
        lastNeedAddedAt: Date?,
        confirmedPurchase: Int = 0
    ) -> ProductStateHistoryAggregate {
        ProductStateHistoryAggregate(
            productID: productID(product),
            nativeUserCommandEventCount: needAdded,
            nativeSessionFinishEventCount: confirmedPurchase,
            legacyMigrationEventCount: 0,
            needAddedCount: needAdded,
            needResolvedAlreadyHaveCount: 0,
            needResolvedNoLongerNeededCount: 0,
            needReopenedCount: 0,
            listMembershipRemovedCount: 0,
            productRemovedFromLibraryCount: 0,
            productRestoredToLibraryCount: 0,
            confirmedPurchaseCount: confirmedPurchase,
            sessionAlreadyHaveCount: 0,
            sessionNoLongerNeededCount: 0,
            sessionUnavailableCount: 0,
            sessionSkippedCount: 0,
            sessionCarriedForwardCount: 0,
            duplicateContributionCount: 0,
            unsupportedEvidenceCount: 0,
            firstIncludedEventAt: lastNeedAddedAt,
            lastIncludedEventAt: lastNeedAddedAt,
            mostRecentNeedAddedAt: lastNeedAddedAt
        )
    }

    private func date(_ value: Int) -> Date {
        Date(timeIntervalSince1970: 2_000_000_000 + Double(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(value))
    }

    private func entryID(_ value: Int) -> ProductStateListEntryID {
        ProductStateListEntryID(rawValue: uuid(value))
    }

    private func sessionID(_ value: Int) -> ProductStateSessionID {
        ProductStateSessionID(rawValue: uuid(value))
    }

    private func lineID(_ value: Int) -> ProductStateSessionLineID {
        ProductStateSessionLineID(rawValue: uuid(value))
    }

    private func commandID(_ value: Int) -> ProductStateCommandID {
        ProductStateCommandID(rawValue: uuid(value))
    }

    private func historyID(_ value: Int) -> ProductStateHistoryEventID {
        ProductStateHistoryEventID(rawValue: uuid(value))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String, _ root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

@MainActor
private final class StubHistoryRepository: HistoryRepository {
    private let events: [WayTaskSchemaV4.ProductHistoryEvent]

    init<S: Sequence>(events: S)
        where S.Element == WayTaskSchemaV4.ProductHistoryEvent {
        self.events = Array(events)
    }

    func historyEvents(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        events.filter { $0.id == id }
    }

    func historyEvents(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        events.filter { $0.productID == productID }
    }

    func stageInsertion(
        of event: WayTaskSchemaV4.ProductHistoryEvent
    ) {}
}

@MainActor
private final class ThrowingHistoryRepository: HistoryRepository {
    private struct ReadFailure: Error {}

    func historyEvents(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        throw ReadFailure()
    }

    func historyEvents(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        throw ReadFailure()
    }

    func stageInsertion(
        of event: WayTaskSchemaV4.ProductHistoryEvent
    ) {}
}

@MainActor
private final class ThrowingHistoryQuery: ProductStateHistoryQuerying {
    func history(
        _ request: ProductStateHistoryQueryRequest
    ) -> ProductStateHistoryQueryOutcome {
        .unavailable(
            ProductStateHistoryQueryDiagnostic(
                productID: request.productID.rawValue,
                outcome: .unavailable,
                failure: .repositoryReadFailed,
                retentionPolicy: .retainAllNoAutomaticExpiryV103,
                retainedEventCount: 0,
                returnedEventCount: 0,
                omittedEventCount: 0,
                duplicateContributionCount: 0,
                unsupportedEvidenceCount: 0,
                provenanceCounts: []
            )
        )
    }
}
