import Foundation
import XCTest
@testable import WayTask

final class ProductStateInvariantValidatorTests: XCTestCase {
    func testAuthorityBoundaryViolationsAreExplicit() {
        let violations = validate(
            ProductStateInvariantInput(
                authorityAudit: ProductStateAuthorityAudit(
                    authorityCounts: [.productLibrary: 2],
                    hasGlobalProductShoppingState: true,
                    usesCatalogIdentityAsProductIdentity: true,
                    hasExternalAuthorityClaim: true,
                    compatibilityValueIsAuthoritative: true
                )
            )
        )

        XCTAssertEqual(
            Set(violations.map(\.code)),
            [
                .missingAuthorityForLifecycle,
                .multipleAuthoritiesForLifecycle,
                .globalProductShoppingState,
                .catalogIdentitySubstitutedForProduct,
                .externalAuthorityClaim,
                .compatibilityAuthorityClaim
            ]
        )
    }

    func testProductIdentityAndRestoreViolationsAreRejected() {
        let before = ProductStateProductSnapshot(
            id: productID(1),
            catalogID: ProductStateCatalogID(rawValue: "catalog.one"),
            libraryLifecycle: .removed
        )
        let after = ProductStateProductSnapshot(
            id: productID(2),
            catalogID: ProductStateCatalogID(rawValue: "catalog.one"),
            libraryLifecycle: .active
        )
        let violations = validate(
            ProductStateInvariantInput(
                productTransitions: [
                    ProductLibraryTransition(
                        before: before,
                        after: after,
                        action: .restoreToLibrary,
                        hasExplicitUserIntent: false
                    )
                ]
            )
        )

        XCTAssertEqual(
            Set(violations.map(\.code)),
            [.productIdentityChanged, .implicitProductRestore]
        )
    }

    func testDuplicateMembershipCrossListAndReopenViolationsAreRejected() {
        let firstListID = listID(1)
        let secondListID = listID(2)
        let scopedProductID = productID(1)
        let first = entryIdentity(
            id: 1,
            listID: firstListID,
            productID: scopedProductID
        )
        let duplicate = entryIdentity(
            id: 2,
            listID: firstListID,
            productID: scopedProductID
        )
        let foreign = entryIdentity(
            id: 3,
            listID: secondListID,
            productID: scopedProductID
        )
        let resolved = ProductStateListEntrySnapshot(
            identity: first,
            lifecycle: .resolved(
                ShoppingListResolution(
                    reason: .legacyUnknown,
                    effectiveAt: Date(timeIntervalSince1970: 100),
                    provenance: .userCommand(commandID(1))
                )
            )
        )
        let reopenedWithDifferentIdentity = ProductStateListEntrySnapshot(
            identity: foreign,
            lifecycle: .needed
        )
        let list = ProductStateShoppingListSnapshot(
            id: firstListID,
            revision: ProductStateListRevision(value: 1),
            entries: [
                ProductStateListEntrySnapshot(
                    identity: first,
                    lifecycle: .needed
                ),
                ProductStateListEntrySnapshot(
                    identity: duplicate,
                    lifecycle: .needed
                ),
                ProductStateListEntrySnapshot(
                    identity: foreign,
                    lifecycle: .needed
                )
            ]
        )

        let violations = validate(
            ProductStateInvariantInput(
                lists: [list],
                membershipClaims: [
                    ProductStateListMembershipKey(
                        listID: firstListID,
                        productID: productID(99)
                    )
                ],
                entryTransitions: [
                    ShoppingListEntryTransition(
                        before: resolved,
                        after: reopenedWithDifferentIdentity,
                        action: .reopen,
                        commandListID: firstListID
                    )
                ]
            )
        )

        XCTAssertTrue(violations.contains(code: .duplicateCurrentListEntry))
        XCTAssertTrue(violations.contains(code: .entryMembershipWithoutEntry))
        XCTAssertTrue(violations.contains(code: .entryListScopeMismatch))
        XCTAssertTrue(violations.contains(code: .crossListMutation))
        XCTAssertTrue(violations.contains(code: .reopenChangedEntryIdentity))
        XCTAssertTrue(violations.contains(code: .invalidEntryTransition))
        XCTAssertTrue(violations.contains(code: .legacyUnknownOutsideMigration))
    }

    func testPurchasedAndLegacyUnknownResolutionRequireApprovedProvenance() {
        let identity = entryIdentity(
            id: 1,
            listID: listID(1),
            productID: productID(1)
        )
        let list = ProductStateShoppingListSnapshot(
            id: identity.listID,
            revision: ProductStateListRevision(value: 1),
            entries: [
                ProductStateListEntrySnapshot(
                    identity: identity,
                    lifecycle: .resolved(
                        ShoppingListResolution(
                            reason: .purchased,
                            effectiveAt: Date(timeIntervalSince1970: 1),
                            provenance: .userCommand(commandID(1))
                        )
                    )
                ),
                ProductStateListEntrySnapshot(
                    identity: entryIdentity(
                        id: 2,
                        listID: identity.listID,
                        productID: productID(2)
                    ),
                    lifecycle: .resolved(
                        ShoppingListResolution(
                            reason: .legacyUnknown,
                            effectiveAt: Date(timeIntervalSince1970: 2),
                            provenance: .userCommand(commandID(2))
                        )
                    )
                )
            ]
        )

        let violations = validate(
            ProductStateInvariantInput(lists: [list])
        )

        XCTAssertTrue(
            violations.contains(code: .purchasedResolutionWithoutFinish)
        )
        XCTAssertTrue(
            violations.contains(code: .legacyUnknownOutsideMigration)
        )
    }

    func testNativeFinishedExpiredAndMigrationRestrictionsAreEnforced() {
        let unfinished = session(
            id: 1,
            lifecycle: .finished,
            revision: 1,
            outcome: nil
        )
        let expiredWithOutcome = session(
            id: 2,
            lifecycle: .expired,
            revision: 1,
            outcome: .skipped
        )
        var nativeWithLegacy = session(
            id: 3,
            lifecycle: .active,
            revision: 1,
            outcome: nil
        )
        nativeWithLegacy.lines[0].legacyDisposition = .legacyUnknown
        let secondActive = session(
            id: 4,
            lifecycle: .active,
            revision: 1,
            outcome: nil
        )

        let violations = validate(
            ProductStateInvariantInput(
                sessions: [
                    unfinished,
                    expiredWithOutcome,
                    nativeWithLegacy,
                    secondActive
                ]
            )
        )

        XCTAssertTrue(
            violations.contains(code: .finishedSessionMissingFinalOutcome)
        )
        XCTAssertTrue(
            violations.contains(code: .nonFinishedSessionHasFinalOutcome)
        )
        XCTAssertTrue(
            violations.contains(code: .nativeSessionHasLegacyDisposition)
        )
        XCTAssertTrue(
            violations.contains(code: .multipleNativeNonTerminalSessions)
        )
    }

    func testCollectedCannotBecomePurchasedBeforeFinish() {
        let before = session(
            id: 1,
            lifecycle: .active,
            revision: 1,
            executionState: .remaining,
            outcome: nil
        )
        var after = before
        after.revision = ProductStateSessionRevision(value: 2)
        after.lines[0].executionState = .collected
        let transition = ShoppingSessionTransition(
            before: before,
            after: after,
            action: .collect(before.lines[0].snapshot.id),
            effects: ShoppingSessionSemanticEffects(
                resolvedEntries: [after.lines[0].snapshot.sourceEntry],
                historyMeanings: [.sessionOutcome(.purchased)]
            )
        )

        let violations = validate(
            ProductStateInvariantInput(sessionTransitions: [transition])
        )

        XCTAssertTrue(
            violations.contains(code: .collectedTreatedAsPurchased)
        )
        XCTAssertTrue(
            violations.contains(code: .provisionalExecutionHasFinalEffects)
        )
        XCTAssertEqual(after.lines[0].executionState, .collected)
        XCTAssertNil(after.lines[0].finalOutcome)
    }

    func testAbandonRejectsListAndHistoryMeaning() {
        let before = session(
            id: 1,
            lifecycle: .active,
            revision: 1,
            executionState: .collected,
            outcome: nil
        )
        var after = before
        after.lifecycle = .abandoned
        after.revision = ProductStateSessionRevision(value: 2)
        let transition = ShoppingSessionTransition(
            before: before,
            after: after,
            action: .abandon,
            effects: ShoppingSessionSemanticEffects(
                resolvedEntries: [after.lines[0].snapshot.sourceEntry],
                historyMeanings: [.sessionOutcome(.purchased)]
            )
        )

        let violations = validate(
            ProductStateInvariantInput(sessionTransitions: [transition])
        )

        XCTAssertTrue(
            violations.contains(
                code: .abandonedSessionHasListResolutionMeaning
            )
        )
        XCTAssertTrue(
            violations.contains(
                code: .abandonedSessionHasPurchaseHistoryMeaning
            )
        )
    }

    func testSessionSnapshotMutationAndRevisionDriftAreRejected() {
        let before = session(
            id: 1,
            lifecycle: .active,
            revision: 1,
            outcome: nil
        )
        var after = before
        after.revision = ProductStateSessionRevision(value: 4)
        after.lines[0] = ShoppingSessionLine(
            snapshot: ShoppingSessionLineSnapshot(
                id: before.lines[0].snapshot.id,
                snapshotID: ProductStateSessionSnapshotID(
                    rawValue: uuid(999)
                ),
                sourceEntry: before.lines[0].snapshot.sourceEntry,
                productID: before.lines[0].snapshot.productID,
                stopID: before.lines[0].snapshot.stopID
            ),
            executionState: .collected,
            finalOutcome: nil,
            legacyDisposition: nil
        )

        let violations = validate(
            ProductStateInvariantInput(
                sessionTransitions: [
                    ShoppingSessionTransition(
                        before: before,
                        after: after,
                        action: .collect(before.lines[0].snapshot.id),
                        effects: .none
                    )
                ]
            )
        )

        XCTAssertTrue(
            violations.contains(code: .immutableSessionSnapshotChanged)
        )
        XCTAssertTrue(violations.contains(code: .invalidSessionRevision))
    }

    func testHistoryIsImmutableAndPurchaseRequiresSuccessfulFinish() {
        let eventID = ProductStateHistoryEventID(rawValue: uuid(300))
        let original = ProductStateHistoryEvent(
            id: eventID,
            productID: productID(1),
            meaning: .needResolved(.purchased),
            provenance: .userCommand(commandID(1)),
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let mutated = ProductStateHistoryEvent(
            id: eventID,
            productID: productID(1),
            meaning: .sessionOutcome(.purchased),
            provenance: .userCommand(commandID(1)),
            occurredAt: Date(timeIntervalSince1970: 2)
        )

        let violations = validate(
            ProductStateInvariantInput(
                historyEvents: [original, mutated],
                historyMutations: [
                    ProductHistoryEventMutation(
                        before: original,
                        after: mutated
                    )
                ]
            )
        )

        XCTAssertTrue(
            violations.contains(code: .duplicateHistoryEventIdentity)
        )
        XCTAssertTrue(violations.contains(code: .historyEventMutated))
        XCTAssertTrue(
            violations.contains(code: .purchaseHistoryWithoutFinish)
        )
        XCTAssertTrue(
            violations.contains(code: .sessionOutcomeHistoryWithoutFinish)
        )
    }

    func testCommandRetriesCannotDriftOrDuplicateEffects() {
        let firstCommandID = commandID(1)
        let secondCommandID = commandID(2)
        let historyID = ProductStateHistoryEventID(rawValue: uuid(400))
        let validChange = ProductStateRevisionChange(
            before: ProductStateRevision(
                scope: .list(listID(1)),
                value: 2
            ),
            after: ProductStateRevision(
                scope: .list(listID(1)),
                value: 3
            )
        )
        let invalidChange = ProductStateRevisionChange(
            before: ProductStateRevision(
                scope: .list(listID(1)),
                value: 2
            ),
            after: ProductStateRevision(
                scope: .list(listID(1)),
                value: 5
            )
        )
        let first = ProductStateCommandResult.committed(
            ProductStateCommandReceipt(
                commandID: firstCommandID,
                effects: ProductStateCommandEffects(
                    revisionChanges: [validChange],
                    historyEventIDs: [historyID]
                )
            )
        )
        let driftedRetry = ProductStateCommandResult.committed(
            ProductStateCommandReceipt(
                commandID: firstCommandID,
                effects: ProductStateCommandEffects(
                    revisionChanges: [invalidChange, validChange],
                    historyEventIDs: [historyID, historyID]
                )
            )
        )
        let secondOwner = ProductStateCommandResult.committed(
            ProductStateCommandReceipt(
                commandID: secondCommandID,
                effects: ProductStateCommandEffects(
                    revisionChanges: [],
                    historyEventIDs: [historyID]
                )
            )
        )
        let invalidNoOp = ProductStateCommandResult.noOp(
            ProductStateCommandReceipt(
                commandID: commandID(3),
                effects: ProductStateCommandEffects(
                    revisionChanges: [validChange],
                    historyEventIDs: []
                )
            )
        )

        let violations = validate(
            ProductStateInvariantInput(
                commandResults: [
                    first,
                    driftedRetry,
                    secondOwner,
                    invalidNoOp
                ]
            )
        )

        XCTAssertTrue(
            violations.contains(code: .commandRetryChangedResult)
        )
        XCTAssertTrue(
            violations.contains(code: .invalidCommittedRevisionChange)
        )
        XCTAssertTrue(violations.contains(code: .duplicateRevisionEffect))
        XCTAssertTrue(violations.contains(code: .duplicateHistoryEffect))
        XCTAssertTrue(violations.contains(code: .noOpCommandHasEffects))
    }

    func testInvariantFailuresAreDeterministicAndCodesAreUnique() {
        let input = ProductStateInvariantInput(
            authorityAudit: ProductStateAuthorityAudit(
                authorityCounts: [
                    .productLibrary: 3,
                    .sessionExecution: 2
                ],
                hasGlobalProductShoppingState: true,
                usesCatalogIdentityAsProductIdentity: true,
                hasExternalAuthorityClaim: true,
                compatibilityValueIsAuthoritative: true
            ),
            productTransitions: [
                ProductLibraryTransition(
                    before: ProductStateProductSnapshot(
                        id: productID(1),
                        catalogID: nil,
                        libraryLifecycle: .removed
                    ),
                    after: ProductStateProductSnapshot(
                        id: productID(2),
                        catalogID: nil,
                        libraryLifecycle: .active
                    ),
                    action: .restoreToLibrary,
                    hasExplicitUserIntent: false
                )
            ]
        )
        let validator = ProductStateInvariantValidator()
        let first = validator.validate(input)
        let second = validator.validate(input)
        let codes = first.map(\.code)

        XCTAssertEqual(first, second)
        XCTAssertEqual(codes, codes.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertEqual(
            Set(ProductStateInvariantCode.allCases).count,
            ProductStateInvariantCode.allCases.count
        )
    }

    func testValidNativeSnapshotHasNoViolations() {
        let valid = session(
            id: 1,
            lifecycle: .active,
            revision: 1,
            executionState: .remaining,
            outcome: nil
        )
        let input = ProductStateInvariantInput(
            authorityAudit: ProductStateAuthorityAudit(
                authorityCounts: [
                    .productLibrary: 1,
                    .listMembership: 1,
                    .entryResolution: 1,
                    .plan: 1,
                    .sessionExecution: 1,
                    .history: 1
                ]
            ),
            sessions: [valid]
        )

        XCTAssertTrue(validate(input).isEmpty)
    }

    private func validate(_ input: ProductStateInvariantInput)
        -> [ProductStateInvariantViolation]
    {
        ProductStateInvariantValidator().validate(input)
    }

    private func session(
        id: Int,
        lifecycle: ShoppingSessionLifecycle,
        revision: UInt64,
        executionState: ShoppingSessionExecutionState = .remaining,
        outcome: ShoppingSessionFinalOutcome?
    ) -> ProductStateShoppingSession {
        let sourceListID = listID(10 + id)
        let snapshotID = ProductStateSessionSnapshotID(
            rawValue: uuid(100 + id)
        )
        let stopID = ProductStateSessionStopID(rawValue: uuid(120 + id))
        let sourceEntry = entryIdentity(
            id: 10 + id,
            listID: sourceListID,
            productID: productID(10 + id)
        )
        let line = ShoppingSessionLine(
            snapshot: ShoppingSessionLineSnapshot(
                id: ProductStateSessionLineID(rawValue: uuid(140 + id)),
                snapshotID: snapshotID,
                sourceEntry: sourceEntry,
                productID: sourceEntry.productID,
                stopID: stopID
            ),
            executionState: executionState,
            finalOutcome: outcome,
            legacyDisposition: nil
        )
        return ProductStateShoppingSession(
            id: ProductStateSessionID(rawValue: uuid(160 + id)),
            snapshotID: snapshotID,
            sourceListID: sourceListID,
            sourceRevision: .exact(ProductStateListRevision(value: 1)),
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
            id: ProductStateListEntryID(rawValue: uuid(200 + id)),
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

private extension Array where Element == ProductStateInvariantViolation {
    func contains(code: ProductStateInvariantCode) -> Bool {
        contains { $0.code == code }
    }
}
