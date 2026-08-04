import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductStateShoppingConsumerConversionTests: XCTestCase {
    func testConsumerPreservesExactListProductAndEntryIdentities() throws {
        let projection = namedList(
            needed: [
                entry(3, product: 30, order: 3),
                entry(1, product: 10, order: 1)
            ],
            resolved: [
                entry(
                    2,
                    product: 20,
                    order: 2,
                    state: resolved(.alreadyHave)
                )
            ]
        )

        let first = make(projection)
        let second = make(projection)
        let presentation = try available(first)

        XCTAssertEqual(first, second)
        XCTAssertEqual(presentation.listID, listID(100))
        XCTAssertEqual(presentation.listRevision, revision(7))
        XCTAssertEqual(
            presentation.entries.map(\.id),
            [entryID(1), entryID(2), entryID(3)]
        )
        XCTAssertEqual(
            presentation.entries.map(\.productID),
            [productID(10), productID(20), productID(30)]
        )
        XCTAssertTrue(
            presentation.entries.allSatisfy { $0.listID == listID(100) }
        )
    }

    func testNeededResolvedAndUnresolvedSectionOrderIsPreserved() throws {
        let projection = namedList(
            needed: [
                entry(4, product: 4, order: 4),
                entry(2, product: 2, order: 2)
            ],
            resolved: [
                entry(5, product: 5, order: 5, state: resolved(.purchased)),
                entry(1, product: 1, order: 1, state: resolved(.alreadyHave))
            ],
            unresolved: [
                entry(3, product: 3, order: 3, state: .unresolved(rawValue: "future"))
            ]
        )
        let value = try available(make(projection))

        XCTAssertEqual(value.neededEntries.map(\.id), [entryID(4), entryID(2)])
        XCTAssertEqual(value.resolvedEntries.map(\.id), [entryID(5), entryID(1)])
        XCTAssertEqual(value.unresolvedEntries.map(\.id), [entryID(3)])
        XCTAssertEqual(
            value.entries.map(\.id),
            [entryID(1), entryID(2), entryID(3), entryID(4), entryID(5)]
        )
    }

    func testDuplicateEntryIdentityIsRejectedWithoutMergingProducts() {
        let duplicate = entry(1, product: 20, order: 2)
        let projection = namedList(
            needed: [entry(1, product: 10, order: 1)],
            resolved: [
                replacingState(duplicate, with: resolved(.alreadyHave))
            ]
        )

        XCTAssertEqual(
            make(projection).content,
            .invalid(.duplicateEntryIdentity(entryID(1)))
        )
    }

    func testListScopeAndRevisionMustMatchProjectionMetadata() {
        let projection = namedList(needed: [entry(1)])
        let wrongScope = replacingMetadata(
            projection,
            with: metadata(
                scope: .list(listID(101)),
                listRevision: revision(7)
            )
        )
        let wrongRevision = replacingMetadata(
            projection,
            with: metadata(
                scope: .list(listID(100)),
                listRevision: revision(8)
            )
        )

        XCTAssertEqual(
            make(wrongScope).content,
            .invalid(
                .listScopeMismatch(
                    expected: listID(100),
                    actual: .list(listID(101))
                )
            )
        )
        XCTAssertEqual(
            make(wrongRevision).content,
            .invalid(
                .listRevisionMismatch(
                    expected: revision(7),
                    actual: revision(8)
                )
            )
        )
    }

    func testEntryListMismatchNeverFallsBackToSelectedList() {
        let invalid = entry(1, list: 999)

        XCTAssertEqual(
            make(namedList(needed: [invalid])).content,
            .invalid(
                .entryListMismatch(
                    entryID: entryID(1),
                    expected: listID(100),
                    actual: listID(999)
                )
            )
        )
    }

    func testProductProjectionMustMatchExactEntryProductUUID() {
        let invalid = entry(1, product: 10, projectedProduct: 11)

        XCTAssertEqual(
            make(namedList(needed: [invalid])).content,
            .invalid(
                .entryProductMismatch(
                    entryID: entryID(1),
                    expected: productID(10),
                    actual: productID(11)
                )
            )
        )
    }

    func testProductLifecycleAndMissingProductRemainPresentationEvidence()
        throws {
        let removed = entry(
            1,
            product: 10,
            lifecycle: .removed,
            issues: [.removedProduct]
        )
        let missing = entry(
            2,
            product: 20,
            includeProduct: false,
            issues: [.missingProduct]
        )
        let value = try available(make(namedList(needed: [removed, missing])))

        XCTAssertEqual(value.entries[0].productID, productID(10))
        XCTAssertEqual(value.entries[0].productLifecycle, .removed)
        XCTAssertEqual(value.entries[1].productID, productID(20))
        XCTAssertNil(value.entries[1].product)
        XCTAssertEqual(value.entries[1].displayName, "Product unavailable")
    }

    func testFiltersAreStableSubsequencesOfExactListOrder() throws {
        let projection = namedList(
            needed: [entry(1, order: 1), entry(4, order: 4)],
            resolved: [
                entry(2, order: 2, state: resolved(.alreadyHave)),
                entry(3, order: 3, state: resolved(.noLongerNeeded))
            ]
        )

        let needed = try available(make(projection, filter: .needed))
        let resolved = try available(make(projection, filter: .resolved))
        let reason = try available(
            make(projection, filter: .resolutionReason(.noLongerNeeded))
        )

        XCTAssertEqual(needed.visibleEntries.map(\.id), [entryID(1), entryID(4)])
        XCTAssertEqual(resolved.visibleEntries.map(\.id), [entryID(2), entryID(3)])
        XCTAssertEqual(reason.visibleEntries.map(\.id), [entryID(3)])
    }

    func testSearchUsesOnlyImmutableProjectedProductFieldsAndKeepsOrder()
        throws {
        let projection = namedList(
            needed: [
                entry(1, name: "Crème Soap", brand: "North"),
                entry(2, name: "Crème Soap", brand: "South"),
                entry(3, name: "Rice", category: "Pantry")
            ]
        )
        let value = try available(make(projection, searchText: "  CREME SOAP "))

        XCTAssertEqual(value.visibleEntries.map(\.id), [entryID(1), entryID(2)])
        XCTAssertEqual(value.visibleEntries.map(\.productID), [productID(1), productID(2)])
    }

    func testSearchTextNeverCreatesOrSubstitutesProductIdentity() throws {
        let value = try available(
            make(
                namedList(needed: [
                    entry(8, product: 80, name: "Same"),
                    entry(7, product: 70, name: "Same")
                ]),
                searchText: "same"
            )
        )

        XCTAssertEqual(value.visibleEntries.map(\.id), [entryID(7), entryID(8)])
        XCTAssertEqual(value.visibleEntries.map(\.productID), [productID(70), productID(80)])
    }

    func testShoppingIntentGroupingPreservesGroupAndEntryOrder() throws {
        let projection = namedList(needed: [
            entry(3, product: 30, order: 3, name: "Bread", category: "Bakery"),
            entry(1, product: 10, order: 1, name: "Milk", category: "Dairy"),
            entry(2, product: 20, order: 2, name: "USB Cable", category: "Electronics")
        ])
        let value = try available(make(projection))

        XCTAssertEqual(
            value.groups.map(\.id),
            [.shoppingIntent(.grocery), .shoppingIntent(.electronics)]
        )
        XCTAssertEqual(value.groups[0].entries.map(\.id), [entryID(1), entryID(3)])
        XCTAssertEqual(value.groups[1].entries.map(\.id), [entryID(2)])
    }

    func testUnresolvedIntentAndProjectionRowsRemainVisible() throws {
        let value = try available(
            make(
                namedList(
                    needed: [
                        entry(1, name: "Obscure Artifact", category: nil)
                    ],
                    unresolved: [
                        entry(
                            2,
                            includeProduct: false,
                            state: .unresolved(rawValue: "future"),
                            issues: [.missingProduct]
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(value.groups.last?.id, .unresolved)
        XCTAssertEqual(
            value.groups.last?.entries.map(\.id),
            [entryID(1), entryID(2)]
        )
    }

    func testListOrderGroupingUsesExactVisibleOrder() throws {
        let value = try available(
            make(
                namedList(needed: [entry(2, order: 2), entry(1, order: 1)]),
                grouping: .listOrder
            )
        )

        XCTAssertEqual(value.groups.map(\.id), [.listOrder])
        XCTAssertEqual(value.groups[0].entries.map(\.id), [entryID(1), entryID(2)])
    }

    func testCompletionPresentationIsReadOnlyAndKeepsResolutionReasons()
        throws {
        let value = try available(
            make(
                namedList(
                    needed: [entry(1)],
                    resolved: [
                        entry(2, state: resolved(.purchased)),
                        entry(3, state: resolved(.alreadyHave)),
                        entry(4, state: resolved(.noLongerNeeded)),
                        entry(5, state: resolved(.legacyUnknown)),
                        entry(6, state: resolved(nil, raw: "future"))
                    ],
                    unresolved: [
                        entry(7, state: .unresolved(rawValue: "future"))
                    ]
                )
            )
        )
        let completion = value.completion

        XCTAssertTrue(completion.isReadOnly)
        XCTAssertEqual(completion.totalCount, 7)
        XCTAssertEqual(completion.resolvedCount, 5)
        XCTAssertEqual(completion.resolvedFraction, 5.0 / 7.0)
        XCTAssertEqual(completion.purchasedEntryIDs, [entryID(2)])
        XCTAssertEqual(completion.alreadyHaveEntryIDs, [entryID(3)])
        XCTAssertEqual(completion.noLongerNeededEntryIDs, [entryID(4)])
        XCTAssertEqual(completion.legacyUnknownEntryIDs, [entryID(5)])
        XCTAssertEqual(completion.unresolvedReasonEntryIDs, [entryID(6)])
    }

    func testResolutionPresentationPreservesEffectiveTimeAndProvenance()
        throws {
        let state = resolved(.alreadyHave)
        let value = try available(
            make(namedList(resolved: [entry(1, state: state)]))
        )

        XCTAssertEqual(value.resolvedEntries[0].state, state)
        XCTAssertEqual(value.resolvedEntries[0].stateTitle, "Already Have")
        XCTAssertTrue(
            value.resolvedEntries[0].accessibilityLabel.contains("Already Have")
        )
    }

    func testQuantityActionRequestCarriesExactScopeWithoutChangingRow()
        throws {
        let value = try available(make(namedList(needed: [entry(1, quantity: 2)])))
        let row = value.entries[0]
        let request = ShoppingWorkspaceProjectionConsumer.actionRequest(
            for: row,
            in: value,
            action: .updateQuantity(3)
        )

        XCTAssertEqual(
            request,
            ShoppingWorkspaceListActionRequest(
                entryID: entryID(1),
                productID: productID(1),
                listID: listID(100),
                listRevision: revision(7),
                action: .updateQuantity(3)
            )
        )
        XCTAssertEqual(row.quantity, 2)
        XCTAssertNil(
            ShoppingWorkspaceProjectionConsumer.actionRequest(
                for: row,
                in: value,
                action: .updateQuantity(0)
            )
        )
    }

    func testResolveRequestAllowsOnlyNonPurchasePresentationReasons()
        throws {
        let value = try available(make(namedList(needed: [entry(1)])))
        let row = value.entries[0]

        XCTAssertNotNil(action(.resolve(.alreadyHave), row: row, in: value))
        XCTAssertNotNil(action(.resolve(.noLongerNeeded), row: row, in: value))
        XCTAssertNil(action(.resolve(.purchased), row: row, in: value))
        XCTAssertNil(action(.resolve(.legacyUnknown), row: row, in: value))
    }

    func testReopenAndRemoveRequestsPreserveExactEntryIdentity() throws {
        let value = try available(
            make(namedList(resolved: [entry(1, state: resolved(.alreadyHave))]))
        )
        let row = value.entries[0]

        XCTAssertEqual(action(.reopen, row: row, in: value)?.entryID, entryID(1))
        XCTAssertEqual(action(.remove, row: row, in: value)?.productID, productID(1))
        XCTAssertNil(action(.resolve(.alreadyHave), row: row, in: value))
    }

    func testRemovedMissingAndUnresolvedRowsProduceNoActionRequest() throws {
        let value = try available(
            make(
                namedList(
                    needed: [
                        entry(
                            1,
                            lifecycle: .removed,
                            issues: [.removedProduct]
                        ),
                        entry(
                            2,
                            includeProduct: false,
                            issues: [.missingProduct]
                        )
                    ],
                    unresolved: [
                        entry(3, state: .unresolved(rawValue: "future"))
                    ]
                )
            )
        )

        for row in value.entries {
            XCTAssertNil(action(.remove, row: row, in: value))
            XCTAssertNil(action(.reopen, row: row, in: value))
        }
    }

    func testActionRequestRejectsRowFromAnotherImmutablePresentation()
        throws {
        let first = try available(make(namedList(needed: [entry(1)])))
        let second = try available(
            make(namedList(needed: [entry(1, quantity: 2)]))
        )

        XCTAssertNil(
            action(.remove, row: first.entries[0], in: second)
        )
    }

    func testPlanPresentationPreservesT14StatusAndExactCurrentControl()
        throws {
        let projection = namedList(needed: [entry(1), entry(2)])
        let status = planStatus(
            readiness: .currentReady,
            included: [entryID(1)],
            excluded: [entryID(2)]
        )
        let state = make(projection, planStatus: status)
        _ = try available(state)

        XCTAssertEqual(state.plan?.state.readiness, .currentReady)
        XCTAssertEqual(state.plan?.state.sourceListID, listID(100))
        XCTAssertEqual(state.plan?.state.sourceRevision, revision(7))
        XCTAssertEqual(state.plan?.state.includedEntryIDs, [entryID(1)])
        XCTAssertEqual(state.plan?.state.explicitlyExcludedEntryIDs, [entryID(2)])
        XCTAssertEqual(state.plan?.control, .current(listID(100), revision(7)))
    }

    func testPlanControlsMapEveryReadOnlyT14ReadinessState() throws {
        let projection = namedList(needed: [entry(1)])
        let cases: [
            (ShoppingPlanConsumerReadiness, ShoppingWorkspacePlanControlPresentation)
        ] = [
            (.noUsablePlan, .generate(listID(100), revision(7))),
            (.generating, .generating(listID(100), revision(7))),
            (.currentReady, .current(listID(100), revision(7))),
            (.stale, .regenerate(listID(100), revision(7))),
            (.unavailable, .unavailable(listID(100), revision(7), .repositoryReadFailed)),
            (.invalidOrIncomplete, .reviewList(listID(100), revision(7)))
        ]

        for (readiness, expected) in cases {
            let status = planStatus(
                readiness: readiness,
                unavailable: readiness == .unavailable
                    ? .repositoryReadFailed : nil
            )
            XCTAssertEqual(make(projection, planStatus: status).plan?.control, expected)
        }
    }

    func testEmptyListPlanControlDoesNotInventAPlanAction() throws {
        let state = make(namedList(), planStatus: emptyPlanStatus())
        _ = try available(state)

        XCTAssertEqual(state.plan?.control, .empty(listID(100), revision(7)))
    }

    func testPlanListRevisionAndEntryMismatchesAreExplicit() {
        let projection = namedList(needed: [entry(1)])
        let wrongList = planStatus(list: 101)
        let wrongRevision = planStatus(revisionValue: 8)
        let wrongEntry = planStatus(included: [entryID(999)])

        XCTAssertEqual(
            make(projection, planStatus: wrongList).content,
            .invalid(.planListMismatch(expected: listID(100), actual: listID(101)))
        )
        XCTAssertEqual(
            make(projection, planStatus: wrongRevision).content,
            .invalid(.planRevisionMismatch(expected: revision(7), actual: revision(8)))
        )
        XCTAssertEqual(
            make(projection, planStatus: wrongEntry).content,
            .invalid(.planEntryMismatch(entryID(999)))
        )
    }

    func testCurrentPlanWithoutExactSourceScopeIsRejected() {
        let missing = ShoppingPlanConsumerStatus(
            readiness: .currentReady,
            attention: .none,
            staleReasons: [],
            invalidReasons: [],
            unavailableReason: nil,
            sourceListID: nil,
            sourceRevision: nil,
            inputFingerprint: "missing-scope",
            includedEntryIDs: [entryID(1)],
            explicitlyExcludedEntryIDs: [],
            unresolvedEntryIDs: []
        )

        XCTAssertEqual(
            make(
                namedList(needed: [entry(1)]),
                planStatus: missing
            ).content,
            .invalid(.planScopeMissing(.currentReady))
        )
    }

    func testT16ChooserProjectionIsPreservedOnlyForExactListRevision()
        throws {
        let chooser = chooserState(list: 100, revisionValue: 7)
        let state = make(namedList(needed: [entry(1)]), chooser: chooser)
        _ = try available(state)

        XCTAssertEqual(state.chooser, chooser)
        XCTAssertEqual(
            make(
                namedList(needed: [entry(1)]),
                chooser: chooserState(list: 101, revisionValue: 7)
            ).content,
            .invalid(.chooserListMismatch(expected: listID(100), actual: listID(101)))
        )
        XCTAssertEqual(
            make(
                namedList(needed: [entry(1)]),
                chooser: chooserState(list: 100, revisionValue: 8)
            ).content,
            .invalid(.chooserRevisionMismatch(expected: revision(7), actual: revision(8)))
        )
    }

    func testT15AcquisitionPresentationIsPreservedWithoutAcquiring()
        throws {
        let result = ProductAcquisitionResult(
            confirmation: ProductAcquisitionConfirmation(
                productID: productID(50),
                commandID: ProductStateCommandID(rawValue: uuid(5_050)),
                effectiveAt: date(50),
                evidence: .manual(name: "Reviewed", imageData: nil),
                confirmed: true
            ),
            outcome: .restoreRequired(productID: productID(50), revision: 9),
            resolvedCatalogID: nil,
            commandDiagnostic: nil
        )
        let acquisition = ProductAcquisitionPresentationState
            .acquisitionResult(result)
        let state = make(namedList(), acquisition: acquisition)
        _ = try available(state)

        XCTAssertEqual(state.acquisition, acquisition)
        XCTAssertTrue(result.requiresExplicitRestore)
    }

    func testUnavailableNamedListRetainsReadOnlyAdjacentPresentation() {
        let unavailable = metadata(
            scope: .list(listID(100)),
            freshness: .unavailable(.repositoryReadFailed),
            listRevision: revision(7)
        )
        let chooser = chooserState(list: 100, revisionValue: 7)
        let state = ShoppingWorkspaceProjectionConsumer.make(
            namedList: .unavailable(unavailable),
            planStatus: emptyPlanStatus(),
            chooser: chooser,
            acquisition: .idle
        )

        XCTAssertEqual(state.content, .unavailable(unavailable))
        XCTAssertEqual(state.chooser, chooser)
        XCTAssertNil(state.plan)
        XCTAssertEqual(state.acquisition, .idle)
    }

    func testTargetConsumerContainsNoPersistenceLegacyOrCommandAuthority()
        throws {
        let source = try shoppingSource()
        let target = section(
            source,
            from: "// MARK: - T-17 Shopping presentation consumer",
            to: "struct ShoppingWorkspaceView: View"
        )
        let forbidden = [
            "ModelContext",
            "modelContext",
            "@Query",
            "@Environment",
            "ShoppingItem",
            "ShoppingListEntry",
            "isChecked",
            "isCompleted",
            "ProductStateCommandCoordinator",
            "ProductStateProductCommand",
            "ProductStateShoppingCommand",
            "ProductStateTransaction",
            "ShoppingSession",
            ".save(",
            ".delete(",
            "restoreToLibrary(",
            "startShopping("
        ]

        for value in forbidden {
            XCTAssertFalse(target.contains(value), "Unexpected target authority: \(value)")
        }
    }

    func testT17TargetConsumerRemainsInactiveUntilApprovedCutover()
        throws {
        let source = try shoppingSource()
        let runtime = section(
            source,
            from: "struct ShoppingWorkspaceView: View",
            to: "private enum ShoppingWorkspaceScrollTarget"
        )

        XCTAssertFalse(runtime.contains("ShoppingWorkspaceProjectionConsumer.make("))
        XCTAssertFalse(
            try appSource("WayTask/WayTaskApp.swift")
                .contains("ShoppingWorkspaceProjectionConsumer.make(")
        )
        XCTAssertFalse(
            try appSource("WayTask/ContentView.swift")
                .contains("ShoppingWorkspaceProjectionConsumer.make(")
        )
    }
}

private enum T17TestFailure: Error {
    case expectedAvailable
}

private func available(
    _ state: ShoppingWorkspaceProjectionConsumerState
) throws -> ShoppingWorkspaceProjectionPresentation {
    guard case let .available(value) = state.content else {
        throw T17TestFailure.expectedAvailable
    }
    return value
}

private func make(
    _ projection: ProductStateNamedListProjection,
    planStatus: ShoppingPlanConsumerStatus? = nil,
    chooser: ProductChooserPresentationState = .idle,
    acquisition: ProductAcquisitionPresentationState = .idle,
    searchText: String = "",
    filter: ShoppingWorkspaceProjectionFilter = .all,
    grouping: ShoppingWorkspaceProjectionGrouping = .shoppingIntent
) -> ShoppingWorkspaceProjectionConsumerState {
    ShoppingWorkspaceProjectionConsumer.make(
        namedList: .projection(projection),
        planStatus: planStatus ?? emptyPlanStatus(),
        chooser: chooser,
        acquisition: acquisition,
        searchText: searchText,
        filter: filter,
        grouping: grouping
    )
}

private func action(
    _ value: ShoppingWorkspaceListAction,
    row: ShoppingWorkspaceProjectionRow,
    in presentation: ShoppingWorkspaceProjectionPresentation
) -> ShoppingWorkspaceListActionRequest? {
    ShoppingWorkspaceProjectionConsumer.actionRequest(
        for: row,
        in: presentation,
        action: value
    )
}

private func namedList(
    needed: [ProductStateListEntryProjection] = [],
    resolved: [ProductStateListEntryProjection] = [],
    unresolved: [ProductStateListEntryProjection] = []
) -> ProductStateNamedListProjection {
    ProductStateNamedListProjection(
        id: listID(100),
        revision: revision(7),
        title: "Exact List",
        purposeRawValue: "named",
        neededEntries: needed,
        resolvedEntries: resolved,
        unresolvedEntries: unresolved,
        createdAt: date(1),
        updatedAt: date(2),
        metadata: metadata(
            scope: .list(listID(100)),
            listRevision: revision(7)
        )
    )
}

private func replacingMetadata(
    _ value: ProductStateNamedListProjection,
    with metadata: ProductStateProjectionMetadata
) -> ProductStateNamedListProjection {
    ProductStateNamedListProjection(
        id: value.id,
        revision: value.revision,
        title: value.title,
        purposeRawValue: value.purposeRawValue,
        neededEntries: value.neededEntries,
        resolvedEntries: value.resolvedEntries,
        unresolvedEntries: value.unresolvedEntries,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
        metadata: metadata
    )
}

private func entry(
    _ value: Int,
    list: Int = 100,
    product productValue: Int? = nil,
    projectedProduct: Int? = nil,
    order: Double? = nil,
    quantity: Double = 1,
    name: String? = nil,
    brand: String? = nil,
    category: String? = "General",
    lifecycle: ProductLibraryLifecycle = .active,
    includeProduct: Bool = true,
    state: ProductStateListEntryProjectionState = .needed,
    issues: [ProductStateProjectionOmissionReason] = []
) -> ProductStateListEntryProjection {
    let productValue = productValue ?? value
    return ProductStateListEntryProjection(
        identity: ProductStateListEntryIdentity(
            id: entryID(value),
            listID: listID(list),
            productID: productID(productValue)
        ),
        state: state,
        quantity: quantity,
        unitRawValue: "unit",
        note: "note-\(value)",
        sortOrder: order ?? Double(value),
        product: includeProduct
            ? productProjection(
                projectedProduct ?? productValue,
                name: name,
                brand: brand,
                category: category,
                lifecycle: lifecycle
            ) : nil,
        issues: issues,
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

private func replacingState(
    _ value: ProductStateListEntryProjection,
    with state: ProductStateListEntryProjectionState
) -> ProductStateListEntryProjection {
    ProductStateListEntryProjection(
        identity: value.identity,
        state: state,
        quantity: value.quantity,
        unitRawValue: value.unitRawValue,
        note: value.note,
        sortOrder: value.sortOrder,
        product: value.product,
        issues: value.issues,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt
    )
}

private func resolved(
    _ reason: ShoppingListResolutionReason?,
    raw: String? = nil
) -> ProductStateListEntryProjectionState {
    .resolved(
        reason: reason,
        reasonRawValue: raw ?? reason?.rawValue,
        effectiveAt: date(500),
        provenanceRawValue: "userCommand",
        commandID: ProductStateCommandID(rawValue: uuid(9_000)),
        sessionID: nil,
        sessionLineID: nil
    )
}

private func productProjection(
    _ value: Int,
    name: String? = nil,
    brand: String? = nil,
    category: String? = "General",
    lifecycle: ProductLibraryLifecycle = .active
) -> ProductStateProductProjection {
    let inferred: (String, String?, String?)
    switch value {
    case 10: inferred = ("Milk", "Dairy", "Dairy")
    case 20: inferred = ("USB Cable", nil, "Electronics")
    case 30: inferred = ("Bread", "Bakery", "Bakery")
    default: inferred = ("Product \(value)", "Brand \(value)", category)
    }
    return ProductStateProductProjection(
        id: productID(value),
        revision: UInt64(value + 1),
        libraryLifecycle: lifecycle,
        libraryRemovedAt: lifecycle == .removed ? date(value) : nil,
        displayName: name ?? inferred.0,
        brand: brand ?? inferred.1,
        category: category ?? inferred.2,
        barcode: "barcode-\(value)",
        catalogID: ProductStateCatalogID(rawValue: "catalog-\(value)"),
        catalogDisplayNameSnapshot: name ?? inferred.0,
        catalogDisplayLocaleSnapshot: "en",
        catalogCategoryIDSnapshot: category?.lowercased(),
        catalogCategoryDisplayNameSnapshot: category,
        catalogIconKeySnapshot: "icon-\(value)",
        catalogSnapshotUpdatedAt: date(value),
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

private func planStatus(
    readiness: ShoppingPlanConsumerReadiness = .currentReady,
    list: Int = 100,
    revisionValue: UInt64 = 7,
    included: [ProductStateListEntryID] = [],
    excluded: [ProductStateListEntryID] = [],
    unresolved: [ProductStateListEntryID] = [],
    unavailable: ProductStateProjectionUnavailableReason? = nil
) -> ShoppingPlanConsumerStatus {
    ShoppingPlanConsumerStatus(
        readiness: readiness,
        attention: excluded.isEmpty ? .none : .explicitExclusions,
        staleReasons: readiness == .stale ? [.sourceRevisionChanged] : [],
        invalidReasons: readiness == .invalidOrIncomplete
            ? [.invalidEligibleEntry] : [],
        unavailableReason: unavailable,
        sourceListID: listID(list),
        sourceRevision: revision(revisionValue),
        inputFingerprint: "t14-exact-input",
        includedEntryIDs: included,
        explicitlyExcludedEntryIDs: excluded,
        unresolvedEntryIDs: unresolved
    )
}

private func emptyPlanStatus() -> ShoppingPlanConsumerStatus {
    ShoppingPlanConsumerBoundary.emptyConsumerStatus()
}

private func chooserState(
    list: Int,
    revisionValue: UInt64
) -> ProductChooserPresentationState {
    .available(
        listID: listID(list),
        listRevision: revision(revisionValue),
        products: [],
        metadata: metadata(
            scope: .library(.active),
            listRevision: revision(revisionValue)
        )
    )
}

private func metadata(
    scope: ProductStateProjectionScope,
    freshness: ProductStateProjectionFreshness = .current,
    listRevision: ProductStateListRevision? = nil
) -> ProductStateProjectionMetadata {
    ProductStateProjectionMetadata(
        scope: scope,
        freshness: freshness,
        listRevision: listRevision,
        sessionRevision: nil,
        sessionSnapshotID: nil,
        provenances: [.targetProductState],
        omissions: [],
        cachePolicy: .disabledDirectRebuild
    )
}

private func listID(_ value: Int) -> ProductStateListID {
    ProductStateListID(rawValue: uuid(value))
}

private func productID(_ value: Int) -> ProductStateProductID {
    ProductStateProductID(rawValue: uuid(value))
}

private func entryID(_ value: Int) -> ProductStateListEntryID {
    ProductStateListEntryID(rawValue: uuid(value))
}

private func revision(_ value: UInt64) -> ProductStateListRevision {
    ProductStateListRevision(value: value)
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

private func sourceRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func shoppingSource() throws -> String {
    try appSource("WayTask/ShoppingWorkspaceView.swift")
}

private func appSource(_ path: String) throws -> String {
    try String(
        contentsOf: sourceRoot().appendingPathComponent(path),
        encoding: .utf8
    )
}

private func section(
    _ source: String,
    from start: String,
    to end: String
) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(
              of: end,
              range: startRange.upperBound..<source.endIndex
          ) else {
        return source
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
