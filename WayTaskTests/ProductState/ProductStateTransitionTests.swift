import Foundation
import XCTest
@testable import WayTask

final class ProductStateTransitionTests: XCTestCase {
    func testTargetVocabularyContainsEveryApprovedCase() {
        XCTAssertEqual(
            Set(ProductLibraryLifecycle.allCases),
            [.active, .removed]
        )
        XCTAssertEqual(
            Set(ShoppingListResolutionReason.allCases),
            [.purchased, .alreadyHave, .noLongerNeeded, .legacyUnknown]
        )
        XCTAssertEqual(
            Set(ShoppingSessionLifecycle.allCases),
            [.active, .expired, .finished, .abandoned]
        )
        XCTAssertEqual(
            Set(ShoppingSessionExecutionState.allCases),
            [.remaining, .collected]
        )
        XCTAssertEqual(
            Set(ShoppingSessionFinalOutcome.allCases),
            [
                .purchased,
                .alreadyHave,
                .noLongerNeeded,
                .unavailable,
                .skipped,
                .carriedForward
            ]
        )
        XCTAssertEqual(
            Set(ShoppingSessionMigrationCondition.allCases),
            [
                .native,
                .legacyMapped,
                .legacyIncomplete,
                .legacyUnresolved
            ]
        )
        XCTAssertFalse(
            ShoppingSessionFinalOutcome.allCases
                .map(\.rawValue)
                .contains(ShoppingSessionLegacyDisposition.legacyUnknown.rawValue)
        )
    }

    func testPlanStatusRepresentsIdleGeneratingReadyFailedAndStale() {
        let statuses: [ShoppingPlanStatus] = [
            .idle,
            .generating,
            .ready,
            .failed(ProductStateFailureCode(rawValue: "synthetic_failure")),
            .stale(.sourceRevisionChanged)
        ]

        XCTAssertEqual(statuses.count, 5)
        XCTAssertEqual(statuses[0], .idle)
        XCTAssertEqual(statuses[1], .generating)
        XCTAssertEqual(statuses[2], .ready)
        XCTAssertEqual(
            statuses[3],
            .failed(ProductStateFailureCode(rawValue: "synthetic_failure"))
        )
        XCTAssertEqual(statuses[4], .stale(.sourceRevisionChanged))
    }

    func testStableProductIdentitySurvivesCatalogAndLibraryChanges() {
        let productID = productID(1)
        let original = ProductStateProductSnapshot(
            id: productID,
            catalogID: ProductStateCatalogID(rawValue: "catalog.old"),
            libraryLifecycle: .active
        )
        let removed = ProductStateProductSnapshot(
            id: productID,
            catalogID: ProductStateCatalogID(rawValue: "catalog.new"),
            libraryLifecycle: .removed
        )
        let restored = ProductStateProductSnapshot(
            id: productID,
            catalogID: nil,
            libraryLifecycle: .active
        )

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(
                productTransitions: [
                    ProductLibraryTransition(
                        before: original,
                        after: removed,
                        action: .removeFromLibrary,
                        hasExplicitUserIntent: true
                    ),
                    ProductLibraryTransition(
                        before: removed,
                        after: restored,
                        action: .restoreToLibrary,
                        hasExplicitUserIntent: true
                    )
                ]
            )
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertEqual(original.id, removed.id)
        XCTAssertEqual(removed.id, restored.id)
        XCTAssertNotEqual(original.catalogID, removed.catalogID)
    }

    func testListMembershipIsEntryOwnedAndListScoped() {
        let productID = productID(1)
        let firstListID = listID(1)
        let secondListID = listID(2)
        let firstEntry = entryIdentity(
            id: 1,
            listID: firstListID,
            productID: productID
        )
        let secondEntry = entryIdentity(
            id: 2,
            listID: secondListID,
            productID: productID
        )
        let firstList = ProductStateShoppingListSnapshot(
            id: firstListID,
            revision: ProductStateListRevision(value: 4),
            entries: [
                ProductStateListEntrySnapshot(
                    identity: firstEntry,
                    lifecycle: .needed
                )
            ]
        )
        let secondList = ProductStateShoppingListSnapshot(
            id: secondListID,
            revision: ProductStateListRevision(value: 9),
            entries: [
                ProductStateListEntrySnapshot(
                    identity: secondEntry,
                    lifecycle: .needed
                )
            ]
        )

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(
                lists: [firstList, secondList],
                membershipClaims: [
                    ProductStateListMembershipKey(
                        listID: firstListID,
                        productID: productID
                    ),
                    ProductStateListMembershipKey(
                        listID: secondListID,
                        productID: productID
                    )
                ]
            )
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertTrue(firstList.contains(productID: productID))
        XCTAssertTrue(secondList.contains(productID: productID))
        XCTAssertNotEqual(firstEntry.id, secondEntry.id)
        XCTAssertNotEqual(firstEntry.listID, secondEntry.listID)
    }

    func testResolveAndReopenPreserveExactEntryIdentity() {
        let identity = entryIdentity(
            id: 1,
            listID: listID(1),
            productID: productID(1)
        )
        let commandID = commandID(1)
        let needed = ProductStateListEntrySnapshot(
            identity: identity,
            lifecycle: .needed
        )
        let resolved = ProductStateListEntrySnapshot(
            identity: identity,
            lifecycle: .resolved(
                ShoppingListResolution(
                    reason: .alreadyHave,
                    effectiveAt: Date(timeIntervalSince1970: 100),
                    provenance: .userCommand(commandID)
                )
            )
        )

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(
                entryTransitions: [
                    ShoppingListEntryTransition(
                        before: needed,
                        after: resolved,
                        action: .resolve,
                        commandListID: identity.listID
                    ),
                    ShoppingListEntryTransition(
                        before: resolved,
                        after: needed,
                        action: .reopen,
                        commandListID: identity.listID
                    )
                ]
            )
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertEqual(needed.identity, resolved.identity)
    }

    func testPlanCapturesExactSourceRevisionEntriesAndExclusions() {
        let sourceListID = listID(1)
        let included = entryIdentity(
            id: 1,
            listID: sourceListID,
            productID: productID(1)
        )
        let excluded = entryIdentity(
            id: 2,
            listID: sourceListID,
            productID: productID(2)
        )
        let plan = ProductStateShoppingPlan(
            id: ProductStatePlanID(rawValue: uuid(30)),
            sourceListID: sourceListID,
            sourceRevision: ProductStateListRevision(value: 7),
            includedEntries: [included],
            exclusions: [
                ShoppingPlanExclusion(
                    entry: excluded,
                    reason: .userExcluded
                )
            ],
            status: .ready
        )

        XCTAssertEqual(plan.sourceListID, sourceListID)
        XCTAssertEqual(plan.sourceRevision.value, 7)
        XCTAssertEqual(plan.includedEntries, [included])
        XCTAssertEqual(plan.exclusions.first?.entry, excluded)
        XCTAssertEqual(plan.status, .ready)
    }

    func testCollectionIsProvisionalAndFinishAssignsOutcome() {
        let before = session(
            lifecycle: .active,
            revision: 1,
            executionState: .remaining,
            finalOutcome: nil
        )
        var collected = before
        collected.revision = ProductStateSessionRevision(value: 2)
        collected.lines[0].executionState = .collected

        let collectTransition = ShoppingSessionTransition(
            before: before,
            after: collected,
            action: .collect(before.lines[0].snapshot.id),
            effects: .none
        )

        var finished = collected
        finished.lifecycle = .finished
        finished.revision = ProductStateSessionRevision(value: 3)
        finished.lines[0].finalOutcome = .purchased
        let finishTransition = ShoppingSessionTransition(
            before: collected,
            after: finished,
            action: .finish,
            effects: ShoppingSessionSemanticEffects(
                resolvedEntries: [finished.lines[0].snapshot.sourceEntry],
                historyMeanings: [.sessionOutcome(.purchased)]
            )
        )

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(
                sessionTransitions: [collectTransition, finishTransition]
            )
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertEqual(collected.lines[0].executionState, .collected)
        XCTAssertNil(collected.lines[0].finalOutcome)
        XCTAssertEqual(finished.lines[0].finalOutcome, .purchased)
    }

    func testExpireResumeAndAbandonTransitionsPreserveLines() {
        let active = session(
            lifecycle: .active,
            revision: 1,
            executionState: .collected,
            finalOutcome: nil
        )
        var expired = active
        expired.lifecycle = .expired
        expired.revision = ProductStateSessionRevision(value: 2)
        var resumed = expired
        resumed.lifecycle = .active
        resumed.revision = ProductStateSessionRevision(value: 3)
        var abandoned = resumed
        abandoned.lifecycle = .abandoned
        abandoned.revision = ProductStateSessionRevision(value: 4)

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(
                sessionTransitions: [
                    ShoppingSessionTransition(
                        before: active,
                        after: expired,
                        action: .expire,
                        effects: .none
                    ),
                    ShoppingSessionTransition(
                        before: expired,
                        after: resumed,
                        action: .resume,
                        effects: .none
                    ),
                    ShoppingSessionTransition(
                        before: resumed,
                        after: abandoned,
                        action: .abandon,
                        effects: .none
                    )
                ]
            )
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertEqual(active.lines, expired.lines)
        XCTAssertEqual(expired.lines, resumed.lines)
        XCTAssertEqual(resumed.lines, abandoned.lines)
        XCTAssertFalse(expired.lifecycle.isTerminal)
        XCTAssertTrue(abandoned.lifecycle.isTerminal)
    }

    func testHistoryPurchaseRequiresSessionFinishProvenance() {
        let lineID = ProductStateSessionLineID(rawValue: uuid(42))
        let event = ProductStateHistoryEvent(
            id: ProductStateHistoryEventID(rawValue: uuid(50)),
            productID: productID(1),
            meaning: .sessionOutcome(.purchased),
            provenance: .sessionFinish(
                commandID: commandID(1),
                sessionID: ProductStateSessionID(rawValue: uuid(40)),
                lineID: lineID
            ),
            occurredAt: Date(timeIntervalSince1970: 200)
        )

        let violations = ProductStateInvariantValidator().validate(
            ProductStateInvariantInput(historyEvents: [event])
        )

        XCTAssertTrue(violations.isEmpty)
        XCTAssertEqual(event.productID, productID(1))
        XCTAssertEqual(event.meaning, .sessionOutcome(.purchased))
    }

    func testCommandResultVocabularyHasEveryRequiredSemanticResult() {
        let id = commandID(1)
        let receipt = ProductStateCommandReceipt(
            commandID: id,
            effects: .none
        )
        let violation = ProductStateInvariantViolation(
            code: .globalProductShoppingState
        )
        let results: [ProductStateCommandResult] = [
            .committed(receipt),
            .noOp(receipt),
            .conflict(commandID: id, conflict: .staleRevision),
            .validationFailure(commandID: id, violations: [violation]),
            .unavailable(
                commandID: id,
                reason: .durableAuthorityUnavailable
            )
        ]

        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0.commandID == id })
    }

    private func session(
        lifecycle: ShoppingSessionLifecycle,
        revision: UInt64,
        executionState: ShoppingSessionExecutionState,
        finalOutcome: ShoppingSessionFinalOutcome?
    ) -> ProductStateShoppingSession {
        let sourceListID = listID(1)
        let snapshotID = ProductStateSessionSnapshotID(rawValue: uuid(41))
        let stopID = ProductStateSessionStopID(rawValue: uuid(43))
        let sourceEntry = entryIdentity(
            id: 1,
            listID: sourceListID,
            productID: productID(1)
        )
        let line = ShoppingSessionLine(
            snapshot: ShoppingSessionLineSnapshot(
                id: ProductStateSessionLineID(rawValue: uuid(42)),
                snapshotID: snapshotID,
                sourceEntry: sourceEntry,
                productID: sourceEntry.productID,
                stopID: stopID
            ),
            executionState: executionState,
            finalOutcome: finalOutcome,
            legacyDisposition: nil
        )
        return ProductStateShoppingSession(
            id: ProductStateSessionID(rawValue: uuid(40)),
            snapshotID: snapshotID,
            sourceListID: sourceListID,
            sourceRevision: .exact(ProductStateListRevision(value: 4)),
            stopIDs: [stopID],
            migrationCondition: .native,
            lifecycle: lifecycle,
            revision: ProductStateSessionRevision(value: revision),
            lines: [line]
        )
    }

    private func entryIdentity(
        id: Int,
        listID: ProductStateListID,
        productID: ProductStateProductID
    ) -> ProductStateListEntryIdentity {
        ProductStateListEntryIdentity(
            id: ProductStateListEntryID(rawValue: uuid(10 + id)),
            listID: listID,
            productID: productID
        )
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(20 + value))
    }

    private func commandID(_ value: Int) -> ProductStateCommandID {
        ProductStateCommandID(rawValue: uuid(60 + value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
