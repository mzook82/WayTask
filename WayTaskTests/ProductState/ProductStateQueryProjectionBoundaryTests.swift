import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateQueryProjectionBoundaryTests: XCTestCase {
    func testLibraryOrderingMembershipAndDirectRebuildAreDeterministic()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [
                product(2, createdAt: 2),
                product(3, lifecycle: .removed, createdAt: 0),
                product(1, createdAt: 1)
            ],
            lists: [list(10, revision: 4)],
            entries: [entry(11, list: 10, product: 1)]
        )
        let boundary = queryBoundary(repository)
        let request = ProductStateProductLibraryRequest(
            membershipScope: ProductStateListScopeRequest(
                listID: listID(10),
                expectedRevision: revision(4)
            )
        )

        let first = boundary.productLibrary(request)
        let second = boundary.productLibrary(request)
        guard case let .projection(projection) = first else {
            return XCTFail("Expected Product Library projection")
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            projection.products.map(\.product.id),
            [productID(1), productID(2)]
        )
        XCTAssertEqual(
            projection.products[0].membership?.state,
            .needed(entryID(11))
        )
        XCTAssertEqual(
            projection.products[1].membership?.state,
            .absent
        )
        XCTAssertEqual(
            projection.metadata.cachePolicy,
            .disabledDirectRebuild
        )
        XCTAssertEqual(repository.activeProductReadCount, 2)
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testBrowseAndOptionalInputsHaveExplicitEmptySemantics() throws {
        let repository = ProjectionRepositorySpy()
        let boundary = queryBoundary(repository)

        guard case let .projection(library) = boundary.productLibrary(
            ProductStateProductLibraryRequest(membershipScope: nil)
        ), case let .projection(removed) = boundary.removedProducts(),
        case let .projection(sessions) = boundary.activeSessions() else {
            return XCTFail("Expected empty browse projections")
        }
        XCTAssertTrue(library.products.isEmpty)
        XCTAssertTrue(removed.products.isEmpty)
        XCTAssertTrue(sessions.candidates.isEmpty)
        XCTAssertFalse(sessions.requiresExplicitSelection)

        let knowledge = boundary.knowledgeSearch(
            ProductStateKnowledgeSearchRequest(
                productID: nil,
                inputFingerprint: "empty-search",
                publicationVersion: "knowledge-v1",
                maximumCandidateCount: 0
            ),
            candidates: []
        )
        guard case let .projection(value) = knowledge else {
            return XCTFail("Expected explicit empty knowledge projection")
        }
        XCTAssertNil(value.explicitProductID)
        XCTAssertTrue(value.candidates.isEmpty)
        XCTAssertEqual(value.omittedCandidateCount, 0)
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testAcquisitionUsesOnlyExactEvidenceAndNeverInfersIdentity()
        throws {
        let sameNameActive = product(
            20,
            name: "Same Display Name",
            barcode: "active-code"
        )
        let tombstone = product(
            21,
            lifecycle: .removed,
            name: "Same Display Name",
            catalogID: "catalog-tombstone"
        )
        let repository = ProjectionRepositorySpy(
            products: [sameNameActive, tombstone]
        )
        let boundary = queryBoundary(repository)

        let create = boundary.acquisitionMatch(
            ProductStateAcquisitionMatchRequest(
                candidateProductID: productID(22),
                exactEvidence: []
            )
        )
        guard case let .projection(createProjection) = create else {
            return XCTFail("Expected create projection")
        }
        XCTAssertEqual(createProjection.match, .create(productID(22)))

        let restore = boundary.acquisitionMatch(
            ProductStateAcquisitionMatchRequest(
                candidateProductID: productID(23),
                exactEvidence: [.catalogID(catalogID("catalog-tombstone"))]
            )
        )
        guard case let .projection(restoreProjection) = restore,
              case let .restoreRequired(product) = restoreProjection.match
        else {
            return XCTFail("Expected exact tombstone match")
        }
        XCTAssertEqual(product.id, productID(21))

        let active = boundary.acquisitionMatch(
            ProductStateAcquisitionMatchRequest(
                candidateProductID: productID(24),
                exactEvidence: [.barcode("active-code")]
            )
        )
        guard case let .projection(activeProjection) = active,
              case let .alreadyActive(product) = activeProjection.match
        else {
            return XCTFail("Expected exact active match")
        }
        XCTAssertEqual(product.id, productID(20))
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testNamedListIsListScopedOrderedQualifiedAndRevisionAware()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [product(30), product(31)],
            lists: [list(40, revision: 8), list(41, revision: 99)],
            entries: [
                entry(44, list: 41, product: 30),
                entry(43, list: 40, product: 999, order: 3),
                entry(
                    42,
                    list: 40,
                    product: 31,
                    lifecycle: "resolved",
                    reason: "alreadyHave",
                    effectiveAt: date(9),
                    provenance: "userCommand",
                    order: 2
                ),
                entry(41, list: 40, product: 30, order: 1)
            ]
        )
        let boundary = queryBoundary(repository)
        let result = boundary.namedList(
            ProductStateListScopeRequest(
                listID: listID(40),
                expectedRevision: revision(7)
            )
        )
        guard case let .projection(projection) = result else {
            return XCTFail("Expected named-list projection")
        }

        XCTAssertEqual(projection.revision, revision(8))
        XCTAssertEqual(
            projection.metadata.freshness,
            .stale([.expectedListRevisionChanged])
        )
        XCTAssertEqual(
            projection.neededEntries.map(\.identity.id),
            [entryID(41), entryID(43)]
        )
        XCTAssertEqual(
            projection.resolvedEntries.map(\.identity.id),
            [entryID(42)]
        )
        guard case let .resolved(reason, raw, effectiveAt, provenance,
                                 _, _, _) =
            projection.resolvedEntries[0].state else {
            return XCTFail("Expected resolved state")
        }
        XCTAssertEqual(reason, .alreadyHave)
        XCTAssertEqual(raw, "alreadyHave")
        XCTAssertEqual(effectiveAt, date(9))
        XCTAssertEqual(provenance, "userCommand")
        XCTAssertEqual(
            projection.neededEntries[1].issues,
            [.missingProduct]
        )
        XCTAssertTrue(repository.requestedEntryListIDs.allSatisfy {
            $0 == uuid(40)
        })
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testMembershipDistinguishesAbsentNeededResolvedAndRestore()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [product(50), product(51, lifecycle: .removed)],
            lists: [list(60, revision: 3)],
            entries: [
                entry(
                    61,
                    list: 60,
                    product: 50,
                    lifecycle: "resolved",
                    reason: "noLongerNeeded",
                    effectiveAt: date(4),
                    provenance: "userCommand"
                )
            ]
        )
        let boundary = queryBoundary(repository)
        let scope = ProductStateListScopeRequest(
            listID: listID(60),
            expectedRevision: revision(3)
        )

        guard case let .projection(resolved) = boundary.membership(
            productID: productID(50),
            listScope: scope
        ), case let .projection(removed) = boundary.membership(
            productID: productID(51),
            listScope: scope
        ) else {
            return XCTFail("Expected scoped membership projections")
        }
        XCTAssertEqual(
            resolved.state,
            .resolved(
                entryID: entryID(61),
                reason: .noLongerNeeded,
                effectiveAt: date(4)
            )
        )
        XCTAssertEqual(resolved.permittedActions, [.reopen, .remove])
        XCTAssertEqual(removed.state, .absent)
        XCTAssertEqual(removed.permittedActions, [.restoreProduct])
    }

    func testListParityPreservesEveryNeededIDWithNamedExclusions()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [product(70), product(71)],
            lists: [list(80, revision: 5)],
            entries: [
                entry(81, list: 80, product: 70, order: 1),
                entry(82, list: 80, product: 71, order: 2),
                entry(83, list: 80, product: 999, order: 3)
            ]
        )
        let boundary = queryBoundary(repository)
        let result = boundary.listParity(
            ProductStatePlanInputRequest(
                listScope: ProductStateListScopeRequest(
                    listID: listID(80),
                    expectedRevision: revision(5)
                ),
                declaredInputFingerprint: "inputs-v1",
                explicitlyExcludedEntryIDs: [entryID(81)]
            )
        )
        guard case let .projection(parity) = result else {
            return XCTFail("Expected parity projection")
        }

        let shoppingIDs = parity.namedList.neededEntryIDs
        let planIDs = parity.planInput.eligibleEntries.map(\.identity.id)
            + parity.planInput.exclusions.map(\.entry.identity.id)
        let mapIDs = parity.mapContext.items.compactMap(\.entryID)
        let reminderIDs = parity.notificationOpportunity.items.compactMap(
            \.entryID
        )
        XCTAssertEqual(shoppingIDs, [entryID(81), entryID(82), entryID(83)])
        XCTAssertEqual(Set(shoppingIDs), Set(planIDs))
        XCTAssertEqual(shoppingIDs, mapIDs)
        XCTAssertEqual(shoppingIDs, reminderIDs)
        XCTAssertEqual(
            parity.planInput.exclusions.map(\.reason),
            [.explicitUserExclusion, .missingProduct]
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testPlanStatusNamesEveryStalenessDependency() throws {
        let repository = ProjectionRepositorySpy(
            products: [product(90)],
            lists: [list(91, revision: 6)],
            entries: [entry(92, list: 91, product: 90)]
        )
        let boundary = queryBoundary(repository)
        guard case let .projection(input) = boundary.planInput(
            ProductStatePlanInputRequest(
                listScope: ProductStateListScopeRequest(
                    listID: listID(91),
                    expectedRevision: nil
                ),
                declaredInputFingerprint: "current-fingerprint",
                explicitlyExcludedEntryIDs: []
            )
        ) else {
            return XCTFail("Expected plan input")
        }
        let foreignEntry = ProductStateListEntryIdentity(
            id: entryID(93),
            listID: listID(91),
            productID: productID(90)
        )
        let plan = ProductStateShoppingPlan(
            id: planID(94),
            sourceListID: listID(91),
            sourceRevision: revision(5),
            includedEntries: [foreignEntry],
            exclusions: [],
            status: .ready
        )

        let status = boundary.planStatus(
            ProductStatePlanStatusRequest(
                plan: plan,
                planInputFingerprint: "old-fingerprint",
                currentInput: input
            )
        )
        XCTAssertEqual(
            Set(status.staleReasons),
            [
                .sourceRevisionChanged,
                .includedEntriesChanged,
                .planningInputChanged
            ]
        )
        guard case .stale = status.status,
              case .stale = status.metadata.freshness else {
            return XCTFail("Expected explicit stale plan")
        }
    }

    func testActiveSessionLookupReturnsZeroOneOrExplicitMultiple()
        throws {
        let repository = ProjectionRepositorySpy(
            sessions: [
                session(102, lifecycle: .expired, startedAt: 2),
                session(101, lifecycle: .active, startedAt: 1),
                session(103, lifecycle: .finished, startedAt: 0)
            ]
        )
        let boundary = queryBoundary(repository)

        guard case let .projection(projection) = boundary.activeSessions()
        else {
            return XCTFail("Expected active-session lookup")
        }
        XCTAssertEqual(
            projection.candidates.map(\.sessionID),
            [sessionID(101), sessionID(102)]
        )
        XCTAssertTrue(projection.requiresExplicitSelection)
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testSessionProjectionUsesFrozenSnapshotAndReportsStaleness()
        throws {
        let frozenSession = session(
            110,
            sourceList: 111,
            sourceRevision: 7,
            revision: 3,
            startedAt: 1
        )
        let stop = sessionStop(112, session: 110, snapshot: 1, order: 1)
        let laterLine = sessionLine(
            114,
            session: 110,
            snapshot: 1,
            list: 111,
            entry: 116,
            product: 118,
            stop: 112,
            order: 2,
            name: "FROZEN TWO"
        )
        let earlierLine = sessionLine(
            113,
            session: 110,
            snapshot: 1,
            list: 111,
            entry: 115,
            product: 117,
            stop: 112,
            order: 1,
            name: "FROZEN ONE"
        )
        let repository = ProjectionRepositorySpy(
            products: [product(117, name: "LIVE NAME")],
            sessions: [frozenSession],
            lines: [laterLine, earlierLine],
            stops: [stop]
        )
        let boundary = queryBoundary(repository)

        let result = boundary.sessionSnapshot(
            ProductStateSessionSnapshotRequest(
                sessionID: sessionID(110),
                expectedRevision: sessionRevision(2)
            )
        )
        guard case let .projection(projection) = result else {
            return XCTFail("Expected frozen Session projection")
        }
        XCTAssertEqual(
            projection.lines.map(\.productNameSnapshot),
            ["FROZEN ONE", "FROZEN TWO"]
        )
        XCTAssertEqual(
            projection.metadata.freshness,
            .stale([.expectedSessionRevisionChanged])
        )
        XCTAssertEqual(projection.sourceRevision, .exact(revision(7)))
        XCTAssertEqual(repository.productIDReadCount, 0)
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testFinishReviewNeverDefaultsOutcomesAndValidatesSource()
        throws {
        let repository = ProjectionRepositorySpy(
            lists: [list(121, revision: 4)],
            sessions: [
                session(
                    120,
                    sourceList: 121,
                    sourceRevision: 4,
                    revision: 2,
                    startedAt: 1
                )
            ],
            lines: [
                sessionLine(
                    122,
                    session: 120,
                    snapshot: 1,
                    list: 121,
                    entry: 124,
                    product: 126,
                    stop: 128,
                    order: 1
                ),
                sessionLine(
                    123,
                    session: 120,
                    snapshot: 1,
                    list: 121,
                    entry: 125,
                    product: 127,
                    stop: 128,
                    order: 2
                )
            ],
            stops: [sessionStop(128, session: 120, snapshot: 1, order: 1)]
        )
        let boundary = queryBoundary(repository)
        let sessionRequest = ProductStateSessionSnapshotRequest(
            sessionID: sessionID(120),
            expectedRevision: sessionRevision(2)
        )

        guard case let .projection(incomplete) = boundary.finishReview(
            ProductStateFinishReviewRequest(
                session: sessionRequest,
                proposedOutcomes: [lineID(122): .purchased]
            )
        ) else {
            return XCTFail("Expected incomplete Finish review")
        }
        XCTAssertEqual(incomplete.status, .incomplete)
        XCTAssertEqual(incomplete.missingOutcomeLineIDs, [lineID(123)])
        XCTAssertNil(incomplete.lines[1].proposedOutcome)

        guard case let .projection(ready) = boundary.finishReview(
            ProductStateFinishReviewRequest(
                session: sessionRequest,
                proposedOutcomes: [
                    lineID(122): .purchased,
                    lineID(123): .carriedForward
                ]
            )
        ) else {
            return XCTFail("Expected ready Finish review")
        }
        XCTAssertEqual(ready.status, .ready)

        repository.lists = [list(121, revision: 5)]
        guard case let .projection(conflict) = boundary.finishReview(
            ProductStateFinishReviewRequest(
                session: sessionRequest,
                proposedOutcomes: [
                    lineID(122): .purchased,
                    lineID(123): .carriedForward
                ]
            )
        ) else {
            return XCTFail("Expected source conflict")
        }
        XCTAssertEqual(conflict.status, .sourceConflict)
        XCTAssertEqual(
            conflict.metadata.freshness,
            .stale([.sourceRevisionChanged])
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testHistoryProjectionRemainsImmutableAndProductUUIDScoped()
        throws {
        let event = historyEvent(130, product: 131)
        let history = ProjectionHistoryRepository(events: [event])
        let boundary = ProductStateHistoryQueryBoundary(
            historyRepository: history
        )
        let result = boundary.history(
            ProductStateHistoryQueryRequest(
                productID: productID(131),
                maximumEventCount: 20,
                order: .oldestFirst
            )
        )
        guard case let .success(projection, _) = result else {
            return XCTFail("Expected history projection")
        }
        XCTAssertEqual(projection.productID, productID(131))
        XCTAssertEqual(projection.events.map(\.eventID), [historyID(130)])
        XCTAssertEqual(history.mutationCallCount, 0)
    }

    func testCatalogProjectionPreservesProductIdentityAndProvenance()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [
                product(
                    140,
                    name: "User Snapshot",
                    catalogID: "catalog-a",
                    catalogSnapshot: "Offline Snapshot"
                )
            ]
        )
        let boundary = queryBoundary(repository)
        let evidence = ProductStatePublishedCatalogEvidence(
            catalogID: catalogID("catalog-a"),
            redirectsFrom: [],
            displayName: "Published Name",
            categoryID: "category-a",
            categoryDisplayName: "Published Category",
            iconKey: "icon-a",
            locale: "en",
            version: "catalog-v2"
        )

        guard case let .projection(current) = boundary.catalogLinkedProduct(
            productID: productID(140),
            catalogEvidence: evidence
        ), case let .projection(offline) = boundary.catalogLinkedProduct(
            productID: productID(140),
            catalogEvidence: nil
        ) else {
            return XCTFail("Expected Catalog-linked projections")
        }
        XCTAssertEqual(current.product.id, productID(140))
        XCTAssertEqual(current.status, .current)
        XCTAssertEqual(current.displayedName, "Published Name")
        XCTAssertEqual(
            current.metadata.provenances,
            [.targetProductState, .publishedCatalog(version: "catalog-v2")]
        )
        XCTAssertEqual(offline.status, .offlineSnapshot)
        XCTAssertEqual(offline.displayedName, "Offline Snapshot")
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testKnowledgeProjectionOrdersEvidenceWithoutInventingProductID()
        throws {
        let repository = ProjectionRepositorySpy()
        let boundary = queryBoundary(repository)
        let result = boundary.knowledgeSearch(
            ProductStateKnowledgeSearchRequest(
                productID: nil,
                inputFingerprint: "knowledge-query",
                publicationVersion: "knowledge-v4",
                maximumCandidateCount: 2
            ),
            candidates: [
                knowledge(151, confidence: 0.4),
                knowledge(153, confidence: 0.9),
                knowledge(152, confidence: 0.9)
            ]
        )
        guard case let .projection(projection) = result else {
            return XCTFail("Expected Product Knowledge projection")
        }
        XCTAssertEqual(
            projection.candidates.map(\.evidenceID),
            [uuid(152), uuid(153)]
        )
        XCTAssertTrue(projection.candidates.allSatisfy {
            $0.productID == nil
        })
        XCTAssertEqual(projection.omittedCandidateCount, 1)
        XCTAssertEqual(
            projection.metadata.provenances,
            [.publishedProductKnowledge(version: "knowledge-v4")]
        )
    }

    func testNotificationRoutesValidateOwnerRevisionAndSnapshot()
        throws {
        let repository = ProjectionRepositorySpy(
            lists: [list(160, revision: 5)],
            sessions: [session(161, revision: 2, startedAt: 1)]
        )
        let boundary = queryBoundary(repository)

        let currentList = boundary.notificationRoute(
            .list(listID(160), revision(5))
        )
        let staleList = boundary.notificationRoute(
            .list(listID(160), revision(4))
        )
        let currentSession = boundary.notificationRoute(
            .session(sessionID(161), sessionRevision(2), snapshotID(1))
        )
        let staleSnapshot = boundary.notificationRoute(
            .session(sessionID(161), sessionRevision(2), snapshotID(99))
        )

        XCTAssertEqual(currentList.route, .namedList(listID(160)))
        XCTAssertEqual(
            staleList.route,
            .safeShopping(.sourceRevisionChanged)
        )
        XCTAssertEqual(currentSession.route, .session(sessionID(161)))
        XCTAssertEqual(
            staleSnapshot.route,
            .safeShopping(.snapshotChanged)
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testSavedLocationEvidenceRequiresExactProductListEntryLink()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [product(170)],
            lists: [list(171)],
            entries: [entry(172, list: 171, product: 170)]
        )
        let boundary = queryBoundary(repository)
        let result = boundary.savedLocationEvidence(
            ProductStateSavedLocationEvidenceInput(
                locationID: uuid(173),
                displayNameSnapshot: "Saved Store",
                noteSnapshot: "Evidence only",
                latitude: nil,
                longitude: nil,
                evidenceVersion: "location-v1",
                links: [
                    ProductStateSavedLocationLinkInput(
                        productID: productID(170),
                        listID: listID(171),
                        entryID: entryID(172),
                        authority: .exactTargetReference
                    ),
                    ProductStateSavedLocationLinkInput(
                        productID: productID(999),
                        listID: listID(171),
                        entryID: entryID(172),
                        authority: .legacyEvidenceOnly
                    )
                ]
            )
        )
        guard case let .projection(projection) = result else {
            return XCTFail("Expected saved-location evidence")
        }
        XCTAssertEqual(
            projection.links.filter(\.isAuthoritativeProductStateLink)
                .count,
            1
        )
        XCTAssertEqual(projection.metadata.omissions.count, 1)
        XCTAssertEqual(
            projection.metadata.omissions.first?.reason,
            .unprovenLocationLink
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testDiscoveryAndStoreRecommendationsStayScopedAndEstimated()
        throws {
        let repository = ProjectionRepositorySpy(
            products: [product(180), product(181)],
            lists: [list(182, revision: 2)],
            entries: [
                entry(183, list: 182, product: 180, order: 1),
                entry(184, list: 182, product: 181, order: 2)
            ]
        )
        let boundary = queryBoundary(repository)
        guard case let .projection(list) = boundary.namedList(
            ProductStateListScopeRequest(
                listID: listID(182),
                expectedRevision: revision(2)
            )
        ) else {
            return XCTFail("Expected list context")
        }
        let discovery = boundary.discoveryContext(
            boundary.mapContext(list: list)
        )
        let stores = boundary.storeRecommendations(
            context: discovery,
            evidence: [
                ProductStatePublishedStoreEvidence(
                    storeID: "store-b",
                    coveredProductIDs: [productID(180), productID(181)],
                    confidence: 0.5,
                    evidenceAt: date(2),
                    publicationVersion: "stores-v1"
                ),
                ProductStatePublishedStoreEvidence(
                    storeID: "store-a",
                    coveredProductIDs: [productID(180)],
                    confidence: 0.9,
                    evidenceAt: date(1),
                    publicationVersion: "stores-v1"
                )
            ]
        )

        XCTAssertEqual(
            discovery.eligibleProductIDs,
            [productID(180), productID(181)]
        )
        XCTAssertEqual(
            stores.recommendations.map(\.storeID),
            ["store-b", "store-a"]
        )
        XCTAssertEqual(
            stores.recommendations[0].estimatedCoveredProductIDs,
            [productID(180), productID(181)]
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testMigrationRecoveryPreservesLedgerAndBlocksIncompleteState()
        throws {
        let sessionException = migrationException(
            193,
            session: 190,
            line: 192,
            ordinal: 2
        )
        let repository = ProjectionRepositorySpy(
            sessions: [session(190, startedAt: 1)],
            exceptions: [sessionException]
        )
        let boundary = queryBoundary(repository)
        let ledgerException = ProductStateSessionExceptionProjection(
            id: uuid(191),
            sessionID: nil,
            sessionLineID: nil,
            categoryRawValue: "globalRecovery",
            safeEvidenceDigest: "safe-global-digest",
            ordinal: 1,
            occurrenceCount: 1,
            recordedAt: date(1)
        )

        let result = boundary.migrationRecovery(
            ProductStateMigrationRecoveryInput(
                migrationVersion: "semantic-v1",
                semanticMigrationComplete: false,
                invariantsValid: true,
                exceptionLedger: [ledgerException]
            )
        )
        guard case let .projection(projection) = result else {
            return XCTFail("Expected recovery projection")
        }
        XCTAssertEqual(
            projection.targetWriteAvailability,
            .blockedMigrationIncomplete
        )
        XCTAssertEqual(
            projection.metadata.freshness,
            .unavailable(.migrationIncomplete)
        )
        XCTAssertEqual(
            projection.exceptions.map(\.id),
            [uuid(191), uuid(193)]
        )
        XCTAssertEqual(
            projection.sessionCandidates.map(\.sessionID),
            [sessionID(190)]
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testRepositoryFailureIsExplicitWithoutFallbackOrMutation()
        throws {
        let repository = ProjectionRepositorySpy()
        repository.shouldThrow = true
        let boundary = queryBoundary(repository)

        let listResult = boundary.namedList(
            ProductStateListScopeRequest(
                listID: listID(200),
                expectedRevision: nil
            )
        )
        let libraryResult = boundary.productLibrary(
            ProductStateProductLibraryRequest(membershipScope: nil)
        )
        guard case let .unavailable(listMetadata) = listResult,
              case let .unavailable(libraryMetadata) = libraryResult else {
            return XCTFail("Expected explicit repository failures")
        }
        XCTAssertEqual(
            listMetadata.freshness,
            .unavailable(.repositoryReadFailed)
        )
        XCTAssertEqual(
            libraryMetadata.freshness,
            .unavailable(.repositoryReadFailed)
        )
        XCTAssertEqual(repository.mutationCallCount, 0)
    }

    func testSwiftDataReadsLeaveCommittedProductStateByteSemanticsAlone()
        throws {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T13-ReadOnly",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let repositories = ProductStateRepositories(modelContext: context)
        let storedProduct = product(210, name: "Committed Product")
        let storedList = list(211, revision: 3)
        let storedEntry = entry(212, list: 211, product: 210)
        repositories.products.stageInsertion(of: storedProduct)
        repositories.shopping.stageInsertion(of: storedList)
        repositories.shopping.stageInsertion(of: storedEntry)
        try context.save()
        let before = (
            storedProduct.revision,
            storedProduct.libraryLifecycleRawValue,
            storedProduct.name,
            storedList.revision,
            storedEntry.lifecycleRawValue,
            storedEntry.quantity
        )

        let boundary = ProductStateQueryBoundary(repositories: repositories)
        _ = boundary.productLibrary(
            ProductStateProductLibraryRequest(membershipScope: nil)
        )
        _ = boundary.namedList(
            ProductStateListScopeRequest(
                listID: listID(211),
                expectedRevision: revision(3)
            )
        )
        _ = boundary.membership(
            productID: productID(210),
            listScope: ProductStateListScopeRequest(
                listID: listID(211),
                expectedRevision: revision(3)
            )
        )

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(storedProduct.revision, before.0)
        XCTAssertEqual(storedProduct.libraryLifecycleRawValue, before.1)
        XCTAssertEqual(storedProduct.name, before.2)
        XCTAssertEqual(storedList.revision, before.3)
        XCTAssertEqual(storedEntry.lifecycleRawValue, before.4)
        XCTAssertEqual(storedEntry.quantity, before.5)
        XCTAssertEqual(
            try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.Product>()
            ),
            1
        )
        XCTAssertEqual(
            try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            ),
            1
        )
    }
}

// MARK: - Isolated read repositories

@MainActor
private final class ProjectionRepositorySpy:
    ProductRepository, ShoppingRepository, ShoppingSessionRepository {
    var products: [WayTaskSchemaV4.Product]
    var lists: [WayTaskSchemaV4.ShoppingList]
    var entries: [WayTaskSchemaV4.ShoppingListEntry]
    var sessions: [WayTaskSchemaV4.ShoppingSession]
    var lines: [WayTaskSchemaV4.ShoppingSessionLine]
    var stops: [WayTaskSchemaV4.ShoppingSessionStop]
    var exceptions: [WayTaskSchemaV4.ProductStateMigrationException]
    var shouldThrow = false

    private(set) var mutationCallCount = 0
    private(set) var activeProductReadCount = 0
    private(set) var productIDReadCount = 0
    private(set) var requestedEntryListIDs: [UUID] = []

    init(
        products: [WayTaskSchemaV4.Product] = [],
        lists: [WayTaskSchemaV4.ShoppingList] = [],
        entries: [WayTaskSchemaV4.ShoppingListEntry] = [],
        sessions: [WayTaskSchemaV4.ShoppingSession] = [],
        lines: [WayTaskSchemaV4.ShoppingSessionLine] = [],
        stops: [WayTaskSchemaV4.ShoppingSessionStop] = [],
        exceptions: [WayTaskSchemaV4.ProductStateMigrationException] = []
    ) {
        self.products = products
        self.lists = lists
        self.entries = entries
        self.sessions = sessions
        self.lines = lines
        self.stops = stops
        self.exceptions = exceptions
    }

    func products(id: UUID) throws -> [WayTaskSchemaV4.Product] {
        try failIfRequired()
        productIDReadCount += 1
        return products.filter { $0.id == id }
    }

    func products(
        catalogProductIDRawValue: String
    ) throws -> [WayTaskSchemaV4.Product] {
        try failIfRequired()
        return products.filter {
            $0.catalogProductIDRawValue == catalogProductIDRawValue
        }
    }

    func products(barcode: String) throws -> [WayTaskSchemaV4.Product] {
        try failIfRequired()
        return products.filter { $0.barcode == barcode }
    }

    func products(
        libraryLifecycle: ProductLibraryLifecycle
    ) throws -> [WayTaskSchemaV4.Product] {
        try failIfRequired()
        if libraryLifecycle == .active { activeProductReadCount += 1 }
        return products.filter {
            $0.libraryLifecycleRawValue == libraryLifecycle.rawValue
        }
    }

    func stageInsertion(of product: WayTaskSchemaV4.Product) {
        mutationCallCount += 1
    }

    func shoppingLists(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingList] {
        try failIfRequired()
        return lists.filter { $0.id == id }
    }

    func shoppingEntries(
        id: UUID,
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        try failIfRequired()
        requestedEntryListIDs.append(listID)
        return entries.filter {
            $0.id == id && $0.shoppingListID == listID
        }
    }

    func shoppingEntries(
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        try failIfRequired()
        requestedEntryListIDs.append(listID)
        return entries.filter { $0.shoppingListID == listID }
    }

    func shoppingEntries(
        listID: UUID,
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        try failIfRequired()
        requestedEntryListIDs.append(listID)
        return entries.filter {
            $0.shoppingListID == listID && $0.productID == productID
        }
    }

    func shoppingEntries(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        try failIfRequired()
        return entries.filter { $0.productID == productID }
    }

    func stageInsertion(of list: WayTaskSchemaV4.ShoppingList) {
        mutationCallCount += 1
    }

    func stageInsertion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        mutationCallCount += 1
    }

    func stageDeletion(of list: WayTaskSchemaV4.ShoppingList) {
        mutationCallCount += 1
    }

    func stageDeletion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        mutationCallCount += 1
    }

    func shoppingSessions(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSession] {
        try failIfRequired()
        return sessions.filter { $0.id == id }
    }

    func shoppingSessions(
        lifecycle: ShoppingSessionLifecycle
    ) throws -> [WayTaskSchemaV4.ShoppingSession] {
        try failIfRequired()
        return sessions.filter {
            $0.lifecycleRawValue == lifecycle.rawValue
        }
    }

    func sessionLines(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionLine] {
        try failIfRequired()
        return lines.filter { $0.sessionID == sessionID }
    }

    func sessionStops(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionStop] {
        try failIfRequired()
        return stops.filter { $0.sessionID == sessionID }
    }

    func migrationExceptions(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ProductStateMigrationException] {
        try failIfRequired()
        return exceptions.filter { $0.sessionID == sessionID }
    }

    func stageInsertion(of session: WayTaskSchemaV4.ShoppingSession) {
        mutationCallCount += 1
    }

    private func failIfRequired() throws {
        if shouldThrow { throw ProjectionRepositoryError.unavailable }
    }
}

@MainActor
private final class ProjectionHistoryRepository: HistoryRepository {
    let events: [WayTaskSchemaV4.ProductHistoryEvent]
    private(set) var mutationCallCount = 0

    init(events: [WayTaskSchemaV4.ProductHistoryEvent]) {
        self.events = events
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
    ) {
        mutationCallCount += 1
    }
}

private enum ProjectionRepositoryError: Error {
    case unavailable
}

// MARK: - Deterministic fixtures

@MainActor
private func queryBoundary(
    _ repository: ProjectionRepositorySpy
) -> ProductStateQueryBoundary {
    ProductStateQueryBoundary(
        products: repository,
        shopping: repository,
        sessions: repository
    )
}

@MainActor
private func product(
    _ value: Int,
    lifecycle: ProductLibraryLifecycle = .active,
    name: String? = nil,
    barcode: String? = nil,
    catalogID: String? = nil,
    catalogSnapshot: String? = nil,
    createdAt: Int = 0
) -> WayTaskSchemaV4.Product {
    WayTaskSchemaV4.Product(
        id: uuid(value),
        revision: UInt64(value + 1),
        libraryLifecycleRawValue: lifecycle.rawValue,
        libraryRemovedAt: lifecycle == .removed ? date(value) : nil,
        name: name ?? "Product \(value)",
        brand: "Brand \(value)",
        category: "Category \(value)",
        barcode: barcode,
        sourceRawValue: "manual",
        catalogProductIDRawValue: catalogID,
        catalogDisplayNameSnapshot: catalogSnapshot,
        catalogDisplayLocaleSnapshot: "en",
        catalogCategoryIDSnapshotRawValue: "category-\(value)",
        catalogCategoryDisplayNameSnapshot: "Category Snapshot \(value)",
        catalogIconKeySnapshot: "icon-\(value)",
        catalogSnapshotUpdatedAt: date(value),
        createdAt: date(createdAt),
        updatedAt: date(createdAt + 1)
    )
}

@MainActor
private func list(
    _ value: Int,
    revision: UInt64 = 1
) -> WayTaskSchemaV4.ShoppingList {
    WayTaskSchemaV4.ShoppingList(
        id: uuid(value),
        revision: revision,
        title: "List \(value)",
        purposeRawValue: "named",
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

@MainActor
private func entry(
    _ value: Int,
    list: Int,
    product: Int,
    lifecycle: String = "needed",
    reason: String? = nil,
    effectiveAt: Date? = nil,
    provenance: String? = nil,
    order: Double = 0
) -> WayTaskSchemaV4.ShoppingListEntry {
    WayTaskSchemaV4.ShoppingListEntry(
        id: uuid(value),
        shoppingListID: uuid(list),
        productID: uuid(product),
        lifecycleRawValue: lifecycle,
        resolutionReasonRawValue: reason,
        resolutionEffectiveAt: effectiveAt,
        resolutionProvenanceRawValue: provenance,
        resolutionCommandID: provenance == nil ? nil : uuid(value + 1_000),
        quantity: 1,
        unitRawValue: "unit",
        note: "Note \(value)",
        sortOrder: order,
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

@MainActor
private func session(
    _ value: Int,
    sourceList: Int? = nil,
    sourceRevision: UInt64? = nil,
    revision: UInt64 = 1,
    lifecycle: ShoppingSessionLifecycle = .active,
    startedAt: Int
) -> WayTaskSchemaV4.ShoppingSession {
    WayTaskSchemaV4.ShoppingSession(
        id: uuid(value),
        sourceListID: sourceList.map(uuid),
        sourceRevision: sourceRevision,
        sourceRevisionProvenanceRawValue:
            sourceRevision == nil ? "legacyUnknown" : "exact",
        revision: revision,
        lifecycleRawValue: lifecycle.rawValue,
        migrationConditionRawValue:
            sourceRevision == nil ? "legacyIncomplete" : "native",
        snapshotID: uuid(1),
        snapshotVersion: 1,
        snapshotGeneration: 1,
        snapshotContentSignature: "snapshot-\(value)",
        startedAt: date(startedAt),
        activationStartedAt: date(startedAt),
        lastActivityAt: date(startedAt + 1),
        expirationPolicyVersion: 1
    )
}

@MainActor
private func sessionLine(
    _ value: Int,
    session: Int,
    snapshot: Int,
    list: Int,
    entry: Int,
    product: Int,
    stop: Int,
    order: Int,
    name: String? = nil
) -> WayTaskSchemaV4.ShoppingSessionLine {
    WayTaskSchemaV4.ShoppingSessionLine(
        id: uuid(value),
        sessionID: uuid(session),
        snapshotID: uuid(snapshot),
        snapshotVersion: 1,
        snapshotProvenanceRawValue: "native",
        sourceListID: uuid(list),
        sourceEntryID: uuid(entry),
        productID: uuid(product),
        stopID: uuid(stop),
        sortOrder: order,
        productNameSnapshot: name ?? "Frozen Product \(value)",
        quantitySnapshot: 1,
        executionStateRawValue: "remaining"
    )
}

@MainActor
private func sessionStop(
    _ value: Int,
    session: Int,
    snapshot: Int,
    order: Int
) -> WayTaskSchemaV4.ShoppingSessionStop {
    WayTaskSchemaV4.ShoppingSessionStop(
        id: uuid(value),
        sessionID: uuid(session),
        snapshotID: uuid(snapshot),
        sortOrder: order,
        storeReferenceIDRawValue: "store-\(value)",
        storeReferenceProvenanceRawValue: "published",
        displayNameSnapshot: "Store \(value)",
        evidenceAt: date(value),
        isSessionScopedTransient: false
    )
}

@MainActor
private func migrationException(
    _ value: Int,
    session: Int,
    line: Int,
    ordinal: Int
) -> WayTaskSchemaV4.ProductStateMigrationException {
    WayTaskSchemaV4.ProductStateMigrationException(
        id: uuid(value),
        sessionID: uuid(session),
        sessionLineID: uuid(line),
        categoryRawValue: "safeCategory",
        safeEvidenceDigest: "safe-digest-\(value)",
        ordinal: ordinal,
        occurrenceCount: 1,
        recordedAt: date(value)
    )
}

@MainActor
private func historyEvent(
    _ value: Int,
    product: Int
) -> WayTaskSchemaV4.ProductHistoryEvent {
    WayTaskSchemaV4.ProductHistoryEvent(
        id: uuid(value),
        productID: uuid(product),
        meaningRawValue: "needAdded",
        sourceListID: uuid(value + 1),
        sourceEntryID: uuid(value + 2),
        commandID: uuid(value + 3),
        provenanceRawValue: "userCommand",
        occurredAt: date(value)
    )
}

private func knowledge(
    _ value: Int,
    confidence: Double
) -> ProductStateKnowledgeCandidateInput {
    ProductStateKnowledgeCandidateInput(
        evidenceID: uuid(value),
        displayNameSnapshot: "Candidate \(value)",
        confidence: confidence,
        provenanceRawValue: "bundled"
    )
}

private func uuid(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        )
    )!
}

private func date(_ value: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(value))
}

private func productID(_ value: Int) -> ProductStateProductID {
    ProductStateProductID(rawValue: uuid(value))
}

private func catalogID(_ value: String) -> ProductStateCatalogID {
    ProductStateCatalogID(rawValue: value)
}

private func listID(_ value: Int) -> ProductStateListID {
    ProductStateListID(rawValue: uuid(value))
}

private func entryID(_ value: Int) -> ProductStateListEntryID {
    ProductStateListEntryID(rawValue: uuid(value))
}

private func planID(_ value: Int) -> ProductStatePlanID {
    ProductStatePlanID(rawValue: uuid(value))
}

private func sessionID(_ value: Int) -> ProductStateSessionID {
    ProductStateSessionID(rawValue: uuid(value))
}

private func sessionRevision(_ value: UInt64)
    -> ProductStateSessionRevision {
    ProductStateSessionRevision(value: value)
}

private func snapshotID(_ value: Int) -> ProductStateSessionSnapshotID {
    ProductStateSessionSnapshotID(rawValue: uuid(value))
}

private func lineID(_ value: Int) -> ProductStateSessionLineID {
    ProductStateSessionLineID(rawValue: uuid(value))
}

private func historyID(_ value: Int) -> ProductStateHistoryEventID {
    ProductStateHistoryEventID(rawValue: uuid(value))
}

private func revision(_ value: UInt64) -> ProductStateListRevision {
    ProductStateListRevision(value: value)
}
