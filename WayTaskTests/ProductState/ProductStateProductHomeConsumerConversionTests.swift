import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductStateProductHomeConsumerConversionTests: XCTestCase {
    func testLibraryPreservesExactProjectionOrderAndProductUUIDs() throws {
        let outcome = libraryOutcome([
            item(3, name: "Alpha"),
            item(1, name: "Zulu"),
            item(2, name: "Middle")
        ])

        let first = ProductLibraryPresentationConsumer.make(
            library: outcome,
            listScope: nil,
            catalog: [:]
        )
        let second = ProductLibraryPresentationConsumer.make(
            library: outcome,
            listScope: nil,
            catalog: [:]
        )
        let presentation = try availableLibrary(first)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            presentation.products.map(\.id),
            [productID(3), productID(1), productID(2)]
        )
        XCTAssertEqual(
            presentation.products.map(\.product.displayName),
            ["Alpha", "Zulu", "Middle"]
        )
    }

    func testDisplayNamesNeverBecomeOrderingOrIdentityFallback() throws {
        let sameName = libraryOutcome([
            item(8, name: "Same Name"),
            item(7, name: "Same Name")
        ])
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: sameName,
                listScope: nil,
                catalog: [:]
            )
        )

        XCTAssertEqual(
            presentation.products.map(\.id),
            [productID(8), productID(7)]
        )
        XCTAssertNotEqual(
            presentation.products[0].id,
            presentation.products[1].id
        )
    }

    func testSearchUsesProjectionFieldsWithoutInferringIdentity() throws {
        let outcome = libraryOutcome([
            item(10, name: "Crème Soap", brand: "North"),
            item(11, name: "Crème Soap", brand: "South"),
            item(12, name: "Rice", category: "Pantry")
        ])
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: nil,
                catalog: [:],
                searchText: "  CREME SOAP  "
            )
        )

        XCTAssertEqual(
            presentation.visibleProducts.map(\.id),
            [productID(10), productID(11)]
        )
        XCTAssertEqual(
            presentation.visibleProducts.map(\.product.displayName),
            ["Crème Soap", "Crème Soap"]
        )
    }

    func testSearchIncludesExactCatalogPresentationWithoutReplacingUUID()
        throws {
        let product = productProjection(20, name: "Saved Snapshot")
        let catalog = catalogProjection(
            product,
            displayedName: "Published Oat Drink",
            categoryID: "beverages"
        )
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([
                    ProductStateProductLibraryItem(
                        product: product,
                        membership: nil
                    )
                ]),
                listScope: nil,
                catalog: [product.id: .projection(catalog)],
                searchText: "oat drink"
            )
        )

        XCTAssertEqual(presentation.visibleProducts.map(\.id), [product.id])
        XCTAssertEqual(
            presentation.visibleProducts[0].product.displayName,
            "Saved Snapshot"
        )
        XCTAssertEqual(
            presentation.visibleProducts[0].catalog,
            .available(catalog)
        )
    }

    func testScopedMembershipFiltersPreserveNeededResolvedAndAmbiguous()
        throws {
        let scope = listScope(40, revision: 7)
        let rows = [
            item(1, membership: membership(1, list: 40, state: .absent)),
            item(
                2,
                membership: membership(
                    2,
                    list: 40,
                    state: .needed(entryID(102))
                )
            ),
            item(
                3,
                membership: membership(
                    3,
                    list: 40,
                    state: .resolved(
                        entryID: entryID(103),
                        reason: .alreadyHave,
                        effectiveAt: date(10)
                    )
                )
            ),
            item(
                4,
                membership: membership(
                    4,
                    list: 40,
                    state: .ambiguous([entryID(104), entryID(105)]),
                    actions: []
                )
            )
        ]
        let outcome = libraryOutcome(rows, listScope: scope)

        let inList = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: scope,
                catalog: [:],
                filter: .inNamedList
            )
        )
        let onlyLibrary = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: scope,
                catalog: [:],
                filter: .libraryOnly
            )
        )

        XCTAssertEqual(
            inList.visibleProducts.map(\.id),
            [productID(2), productID(3), productID(4)]
        )
        XCTAssertEqual(onlyLibrary.visibleProducts.map(\.id), [productID(1)])
    }

    func testMembershipWithoutNamedScopeIsRejected() {
        let outcome = libraryOutcome([
            item(1, membership: membership(1, list: 50, state: .absent))
        ], listScope: listScope(50, revision: 7))

        XCTAssertEqual(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: nil,
                catalog: [:]
            ),
            .invalid(.unexpectedMembership(productID(1)))
        )
    }

    func testMembershipFilterWithoutNamedScopeIsRejected() {
        XCTAssertEqual(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([item(1)]),
                listScope: nil,
                catalog: [:],
                filter: .libraryOnly
            ),
            .invalid(.filterRequiresNamedListScope)
        )
    }

    func testMissingMembershipForNamedScopeIsRejected() {
        let scope = listScope(51, revision: 7)

        XCTAssertEqual(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([item(1)], listScope: scope),
                listScope: scope,
                catalog: [:]
            ),
            .invalid(.missingMembership(productID(1)))
        )
    }

    func testStaleExpectedListRevisionNeverFallsBack() {
        let actualScope = listScope(52, revision: 7)
        let expectedScope = listScope(52, revision: 8)
        let outcome = libraryOutcome([
            item(1, membership: membership(1, list: 52, state: .absent))
        ], listScope: actualScope)

        XCTAssertEqual(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: expectedScope,
                catalog: [:]
            ),
            .invalid(
                .projectionRevisionMismatch(
                    expected: revision(8),
                    actual: revision(7)
                )
            )
        )
    }

    func testCategoryGroupingPreservesFirstGroupAndProductOrder() throws {
        let outcome = libraryOutcome([
            item(1, category: "Pantry"),
            item(2, category: "Cold"),
            item(3, category: "Pantry")
        ])
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: outcome,
                listScope: nil,
                catalog: [:],
                grouping: .category
            )
        )

        XCTAssertEqual(
            presentation.groups.map(\.title),
            ["Pantry", "Cold"]
        )
        XCTAssertEqual(
            presentation.groups[0].products.map(\.id),
            [productID(1), productID(3)]
        )
        XCTAssertEqual(
            presentation.groups[1].products.map(\.id),
            [productID(2)]
        )
    }

    func testCatalogIdentityMismatchIsExplicitAndDoesNotReplaceProduct()
        throws {
        let expected = productProjection(60, name: "Exact Product")
        let wrong = productProjection(61, name: "Same Display")
        let catalog = catalogProjection(
            wrong,
            displayedName: "Exact Product",
            categoryID: "same"
        )
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([
                    ProductStateProductLibraryItem(
                        product: expected,
                        membership: nil
                    )
                ]),
                listScope: nil,
                catalog: [expected.id: .projection(catalog)]
            )
        )

        XCTAssertEqual(presentation.products[0].id, expected.id)
        XCTAssertEqual(
            presentation.products[0].catalog,
            .identityMismatch(expected: expected.id, actual: wrong.id)
        )
    }

    func testKnowledgeProjectionPreservesEvidenceAndAttribution() throws {
        let projection = knowledgeProjection(product: 70)
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([item(70)]),
                listScope: nil,
                catalog: [:],
                knowledge: .projection(projection)
            )
        )

        XCTAssertEqual(presentation.knowledge, .available(projection))
        guard case let .available(value) = presentation.knowledge else {
            return XCTFail("Expected Product Knowledge presentation")
        }
        XCTAssertEqual(value.explicitProductID, productID(70))
        XCTAssertEqual(value.candidates.map(\.evidenceID), [uuid(700)])
        XCTAssertEqual(value.candidates.map(\.provenanceRawValue), ["bundled"])
    }

    func testKnowledgeNeverInfersProductIdentityFromCandidateText() throws {
        let projection = ProductStateKnowledgeSearchProjection(
            explicitProductID: productID(71),
            candidates: [
                ProductStateKnowledgeCandidateProjection(
                    evidenceID: uuid(701),
                    productID: productID(72),
                    displayNameSnapshot: "Same Name",
                    confidence: 0.9,
                    provenanceRawValue: "learned"
                )
            ],
            omittedCandidateCount: 0,
            metadata: metadata(scope: .product(productID(71)))
        )
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([item(71, name: "Same Name")]),
                listScope: nil,
                catalog: [:],
                knowledge: .projection(projection)
            )
        )

        XCTAssertEqual(
            presentation.knowledge,
            .identityMismatch(
                expected: productID(71),
                actual: productID(72)
            )
        )
    }

    func testRemovedSurfacePreservesUUIDRemovalTimeAndRestoreAvailability()
        throws {
        let removed = removedOutcome([80, 81])
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([item(82)]),
                removedProducts: removed,
                listScope: nil,
                catalog: [:]
            )
        )

        guard case let .available(rows, metadata) =
                presentation.removedProducts else {
            return XCTFail("Expected Removed Products presentation")
        }
        XCTAssertEqual(rows.map(\.id), [productID(80), productID(81)])
        XCTAssertEqual(rows[0].projection.product.libraryRemovedAt, date(80))
        XCTAssertTrue(rows.allSatisfy(\.projection.restoreAvailable))
        XCTAssertEqual(metadata.scope, .library(.removed))
        XCTAssertEqual(presentation.products.map(\.id), [productID(82)])
    }

    func testRemovedSurfaceRejectsActiveLifecycleInsteadOfRestoring() throws {
        let active = productProjection(83)
        let invalid = ProductStateRemovedProductsProjection(
            products: [
                ProductStateRemovedProductProjection(
                    product: active,
                    restoreAvailable: true
                )
            ],
            metadata: metadata(scope: .library(.removed))
        )
        let presentation = try availableLibrary(
            ProductLibraryPresentationConsumer.make(
                library: libraryOutcome([]),
                removedProducts: .projection(invalid),
                listScope: nil,
                catalog: [:]
            )
        )

        XCTAssertEqual(
            presentation.removedProducts,
            .invalidProduct(productID(83))
        )
    }

    func testChooserUsesExactListRevisionAndPermittedAction() throws {
        let scope = listScope(90, revision: 11)
        let library = ProductLibraryPresentationConsumer.make(
            library: libraryOutcome([
                item(
                    1,
                    membership: membership(
                        1,
                        list: 90,
                        revision: 11,
                        state: .absent,
                        actions: [.add]
                    )
                )
            ], listScope: scope),
            listScope: scope,
            catalog: [:]
        )
        let chooser = ProductChooserPresentationConsumer.make(
            library: library,
            listScope: scope
        )
        guard case let .available(listID, listRevision, rows, _) = chooser
        else {
            return XCTFail("Expected exact chooser presentation")
        }

        XCTAssertEqual(listID, ProductStateListID(rawValue: uuid(90)))
        XCTAssertEqual(listRevision, revision(11))
        XCTAssertEqual(rows.map(\.id), [productID(1)])
        XCTAssertEqual(
            ProductChooserPresentationConsumer.intent(
                for: rows[0],
                action: .add
            ),
            ProductChooserMembershipIntent(
                productID: productID(1),
                listID: listID,
                listRevision: revision(11),
                action: .add
            )
        )
        XCTAssertNil(
            ProductChooserPresentationConsumer.intent(
                for: rows[0],
                action: .restoreProduct
            )
        )
    }

    func testEmptyChooserStillRequiresAndPreservesExactRevision() {
        let scope = listScope(91, revision: 12)
        let library = ProductLibraryPresentationConsumer.make(
            library: libraryOutcome([], listScope: scope),
            listScope: scope,
            catalog: [:]
        )

        XCTAssertEqual(
            ProductChooserPresentationConsumer.make(
                library: library,
                listScope: scope
            ),
            .available(
                listID: ProductStateListID(rawValue: uuid(91)),
                listRevision: revision(12),
                products: [],
                metadata: metadata(
                    scope: .library(.active),
                    listRevision: revision(12)
                )
            )
        )
    }

    func testHomeUsesLibraryOrderAndExactNamedListCounts() throws {
        let library = ProductLibraryPresentationConsumer.make(
            library: libraryOutcome((1...10).map { item($0) }),
            listScope: nil,
            catalog: [:]
        )
        let later = namedList(102, createdAt: 20, needed: 1)
        let earlier = namedList(
            101,
            createdAt: 10,
            needed: 2,
            resolved: 1,
            unresolved: 1
        )
        let home = ProductHomePresentationConsumer.make(
            library: library,
            namedLists: [.projection(later), .projection(earlier)],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: .idle
        )

        XCTAssertEqual(home.productLibraryCount, 10)
        XCTAssertEqual(
            home.productCards.map(\.id),
            (1...8).map(productID)
        )
        XCTAssertEqual(home.namedLists.map(\.id), [earlier.id, later.id])
        XCTAssertEqual(home.namedLists[0].neededCount, 2)
        XCTAssertEqual(home.namedLists[0].resolvedCount, 1)
        XCTAssertEqual(home.namedLists[0].unresolvedCount, 1)
        XCTAssertEqual(
            ProductHomeRouteConsumer.namedList(home.namedLists[0]),
            .namedList(earlier.id, earlier.revision)
        )
    }

    func testHomePreservesT14PlanStateWithoutListMutation() {
        let status = ShoppingPlanConsumerStatus(
            readiness: .stale,
            attention: .exclusionsAndUnresolvedEntries,
            staleReasons: [.sourceRevisionChanged],
            invalidReasons: [.unclassifiedPlanningIntent],
            unavailableReason: nil,
            sourceListID: ProductStateListID(rawValue: uuid(110)),
            sourceRevision: revision(4),
            inputFingerprint: "exact-input",
            includedEntryIDs: [entryID(1)],
            explicitlyExcludedEntryIDs: [entryID(2)],
            unresolvedEntryIDs: [entryID(3)]
        )
        let home = ProductHomePresentationConsumer.make(
            library: .idle,
            namedLists: [],
            planStatus: status,
            acquisition: .idle
        )

        XCTAssertEqual(home.plan, ProductHomePlanPresentation(status))
        XCTAssertEqual(home.plan.sourceRevision, revision(4))
        XCTAssertEqual(home.plan.inputFingerprint, "exact-input")
    }

    func testHomePreservesT15AcquisitionEvidenceAndCreatedOutcome() {
        let result = acquisitionResult(
            120,
            outcome: .created(productID: productID(120), revision: 1)
        )
        let state = ProductAcquisitionPresentationState.acquisitionResult(result)
        let home = ProductHomePresentationConsumer.make(
            library: .idle,
            namedLists: [],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: state
        )

        XCTAssertEqual(home.acquisition, state)
        XCTAssertEqual(home.acquisition, .acquisitionResult(result))
        XCTAssertEqual(
            ProductHomeRouteConsumer.acquisition(state),
            .acquisitionResult(productID(120))
        )
    }

    func testRestoreRequiredRoutesOnlyToExplicitAcquisitionResult() {
        let result = acquisitionResult(
            121,
            outcome: .restoreRequired(productID: productID(121), revision: 9)
        )
        let state = ProductAcquisitionPresentationState.acquisitionResult(result)

        XCTAssertTrue(result.requiresExplicitRestore)
        XCTAssertEqual(
            ProductHomeRouteConsumer.acquisition(state),
            .acquisitionResult(productID(121))
        )
    }

    func testAmbiguousAcquisitionNeverFabricatesProductRoute() {
        let result = acquisitionResult(
            122,
            outcome: .ambiguity(requestedProductID: productID(122))
        )

        XCTAssertNil(result.authoritativeProductID)
        XCTAssertNil(
            ProductHomeRouteConsumer.acquisition(.acquisitionResult(result))
        )
    }

    func testAppStatePublishesOnlyTargetConsumerState() throws {
        let manager = AppStateManager()
        let scope = listScope(130, revision: 5)
        let acquisition = ProductAcquisitionPresentationState
            .acquisitionResult(
                acquisitionResult(
                    131,
                    outcome: .alreadyActive(
                        productID: productID(131),
                        revision: 2
                    )
                )
            )
        let state = manager.publishProductHomeConsumerState(
            library: libraryOutcome([
                item(
                    131,
                    membership: membership(
                        131,
                        list: 130,
                        revision: 5,
                        state: .absent
                    )
                )
            ], listScope: scope),
            listScope: scope,
            catalog: [:],
            namedLists: [.projection(namedList(130, revision: 5))],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: acquisition
        )

        XCTAssertEqual(manager.productHomeConsumerState, state)
        XCTAssertEqual(state.acquisition, acquisition)
        XCTAssertEqual(manager.selectedTab, .home)
        XCTAssertNil(manager.productStateShoppingPlan)
        XCTAssertEqual(manager.productStateShoppingPlanStatus.readiness, .noUsablePlan)
        XCTAssertNil(manager.currentShoppingListID)
        XCTAssertTrue(manager.currentProductLibraryIDs.isEmpty)
    }

    func testAppStateRoutesOnlyExactProjectedIdentities() throws {
        let manager = AppStateManager()
        let list = namedList(140, revision: 6)
        _ = manager.publishProductHomeConsumerState(
            library: libraryOutcome([item(141)]),
            listScope: nil,
            catalog: [:],
            namedLists: [.projection(list)],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: .idle
        )

        XCTAssertFalse(
            manager.presentProductHomeRoute(.product(productID(999)))
        )
        XCTAssertTrue(
            manager.presentProductHomeRoute(.product(productID(141)))
        )
        XCTAssertEqual(manager.productHomeRoute, .product(productID(141)))
        XCTAssertTrue(
            manager.presentProductHomeRoute(
                .namedList(list.id, list.revision)
            )
        )
        XCTAssertEqual(
            manager.productHomeSelectedListScope,
            ProductStateListScopeRequest(
                listID: list.id,
                expectedRevision: list.revision
            )
        )
        XCTAssertFalse(
            manager.presentProductHomeRoute(
                .namedList(list.id, revision(7))
            )
        )
    }

    func testAppStateClearsStaleExactRouteWithoutFallback() {
        let manager = AppStateManager()
        _ = manager.publishProductHomeConsumerState(
            library: libraryOutcome([item(150)]),
            listScope: nil,
            catalog: [:],
            namedLists: [],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: .idle
        )
        XCTAssertTrue(
            manager.presentProductHomeRoute(.product(productID(150)))
        )

        _ = manager.publishProductHomeConsumerState(
            library: libraryOutcome([]),
            listScope: nil,
            catalog: [:],
            namedLists: [],
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: .idle
        )

        XCTAssertNil(manager.productHomeRoute)
        XCTAssertNil(manager.productHomeSelectedListScope)
        XCTAssertEqual(manager.selectedTab, .home)
    }

    func testUnavailableProjectionProducesOneBoundedState() {
        let unavailable = metadata(
            scope: .library(.active),
            freshness: .unavailable(.repositoryReadFailed)
        )
        let state = ProductLibraryPresentationConsumer.make(
            library: .unavailable(unavailable),
            listScope: nil,
            catalog: [:]
        )

        XCTAssertEqual(state, .unavailable(unavailable))
        XCTAssertEqual(
            ProductChooserPresentationConsumer.make(
                library: state,
                listScope: listScope(160, revision: 1)
            ),
            .unavailable(unavailable)
        )
    }

    func testTargetPresentationSectionsContainNoPersistenceOrCommands()
        throws {
        let root = sourceRoot()
        let product = try source(
            root.appendingPathComponent("ProductListView.swift")
        )
        let home = try source(
            root.appendingPathComponent("WayTask/HomeView.swift")
        )
        let content = try source(
            root.appendingPathComponent("WayTask/ContentView.swift")
        )
        let app = try source(
            root.appendingPathComponent("WayTask/AppStateManager.swift")
        )
        let targetSections = [
            section(
                product,
                from: "// MARK: - T-16 Product Library presentation consumer",
                to: "struct ProductListView: View"
            ),
            section(
                home,
                from: "// MARK: - T-16 Home presentation consumer",
                to: "struct HomeView: View"
            ),
            section(
                content,
                from: "// MARK: - T-16 root and chooser presentation consumers",
                to: "struct ContentView: View"
            ),
            section(
                app,
                from: "func publishProductHomeConsumerState(",
                to: "private func derivedProjectionOwnersMatch("
            )
        ]

        for target in targetSections {
            XCTAssertFalse(target.contains("ModelContext"))
            XCTAssertFalse(target.contains("modelContext"))
            XCTAssertFalse(target.contains("ProductStateCommandCoordinator"))
            XCTAssertFalse(target.contains("ProductStateProductCommand"))
            XCTAssertFalse(target.contains(".save("))
            XCTAssertFalse(target.contains("transaction"))
            XCTAssertFalse(target.contains("ShoppingSession"))
        }
    }

    func testT16TargetPresentationRemainsInactiveUntilCutover() throws {
        let root = sourceRoot()
        let productionViews = [
            "ProductListView.swift",
            "WayTask/HomeView.swift",
            "WayTask/ContentView.swift"
        ]

        for path in productionViews {
            let value = try source(root.appendingPathComponent(path))
            XCTAssertFalse(value.contains("publishProductHomeConsumerState("))
        }
        XCTAssertFalse(
            try source(
                root.appendingPathComponent("WayTask/WayTaskApp.swift")
            ).contains("publishProductHomeConsumerState(")
        )
    }
}

private func availableLibrary(
    _ state: ProductLibraryPresentationState
) throws -> ProductLibraryPresentation {
    guard case let .available(value) = state else {
        throw T16TestFailure.expectedAvailableLibrary
    }
    return value
}

private enum T16TestFailure: Error {
    case expectedAvailableLibrary
}

private func item(
    _ value: Int,
    name: String? = nil,
    brand: String? = nil,
    category: String? = nil,
    membership: ProductStateMembershipProjection? = nil
) -> ProductStateProductLibraryItem {
    ProductStateProductLibraryItem(
        product: productProjection(
            value,
            name: name,
            brand: brand,
            category: category
        ),
        membership: membership
    )
}

private func productProjection(
    _ value: Int,
    lifecycle: ProductLibraryLifecycle = .active,
    name: String? = nil,
    brand: String? = nil,
    category: String? = nil
) -> ProductStateProductProjection {
    ProductStateProductProjection(
        id: productID(value),
        revision: UInt64(value + 1),
        libraryLifecycle: lifecycle,
        libraryRemovedAt: lifecycle == .removed ? date(value) : nil,
        displayName: name ?? "Product \(value)",
        brand: brand ?? "Brand \(value)",
        category: category ?? "Category \(value)",
        barcode: "barcode-\(value)",
        catalogID: ProductStateCatalogID(rawValue: "catalog-\(value)"),
        catalogDisplayNameSnapshot: "Catalog Snapshot \(value)",
        catalogDisplayLocaleSnapshot: "en",
        catalogCategoryIDSnapshot: nil,
        catalogCategoryDisplayNameSnapshot: nil,
        catalogIconKeySnapshot: "icon-\(value)",
        catalogSnapshotUpdatedAt: date(value),
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

private func libraryOutcome(
    _ items: [ProductStateProductLibraryItem],
    listScope: ProductStateListScopeRequest? = nil
) -> ProductStateProjectionOutcome<ProductStateProductLibraryProjection> {
    .projection(
        ProductStateProductLibraryProjection(
            products: items,
            metadata: metadata(
                scope: .library(.active),
                listRevision: listScope?.expectedRevision
            )
        )
    )
}

private func removedOutcome(
    _ values: [Int]
) -> ProductStateProjectionOutcome<ProductStateRemovedProductsProjection> {
    .projection(
        ProductStateRemovedProductsProjection(
            products: values.map {
                ProductStateRemovedProductProjection(
                    product: productProjection($0, lifecycle: .removed),
                    restoreAvailable: true
                )
            },
            metadata: metadata(scope: .library(.removed))
        )
    )
}

private func membership(
    _ product: Int,
    list: Int,
    revision revisionValue: UInt64 = 7,
    state: ProductStateMembershipState,
    actions: [ProductStateMembershipAction] = [.add, .remove]
) -> ProductStateMembershipProjection {
    let listID = ProductStateListID(rawValue: uuid(list))
    return ProductStateMembershipProjection(
        productID: productID(product),
        listID: listID,
        listRevision: revision(revisionValue),
        state: state,
        permittedActions: actions,
        metadata: metadata(
            scope: .list(listID),
            listRevision: revision(revisionValue)
        )
    )
}

private func catalogProjection(
    _ product: ProductStateProductProjection,
    displayedName: String,
    categoryID: String?
) -> ProductStateCatalogLinkedProductProjection {
    ProductStateCatalogLinkedProductProjection(
        product: product,
        status: .current,
        displayedName: displayedName,
        displayedCategoryID: categoryID,
        displayedCategoryName: categoryID.map { "Published \($0)" },
        displayedIconKey: "published-icon",
        displayedLocale: "en",
        metadata: metadata(scope: .product(product.id))
    )
}

private func knowledgeProjection(
    product value: Int
) -> ProductStateKnowledgeSearchProjection {
    let id = productID(value)
    return ProductStateKnowledgeSearchProjection(
        explicitProductID: id,
        candidates: [
            ProductStateKnowledgeCandidateProjection(
                evidenceID: uuid(value * 10),
                productID: id,
                displayNameSnapshot: "Knowledge \(value)",
                confidence: 0.95,
                provenanceRawValue: "bundled"
            )
        ],
        omittedCandidateCount: 0,
        metadata: metadata(scope: .product(id))
    )
}

private func namedList(
    _ value: Int,
    revision revisionValue: UInt64 = 3,
    createdAt: Int? = nil,
    needed: Int = 0,
    resolved: Int = 0,
    unresolved: Int = 0
) -> ProductStateNamedListProjection {
    let id = ProductStateListID(rawValue: uuid(value))
    let revision = revision(revisionValue)
    return ProductStateNamedListProjection(
        id: id,
        revision: revision,
        title: "List \(value)",
        purposeRawValue: "named",
        neededEntries: (0..<needed).map {
            listEntry(value * 100 + $0, list: value, state: .needed)
        },
        resolvedEntries: (0..<resolved).map {
            listEntry(
                value * 100 + 20 + $0,
                list: value,
                state: .resolved(
                    reason: .purchased,
                    reasonRawValue: ShoppingListResolutionReason.purchased.rawValue,
                    effectiveAt: date(value),
                    provenanceRawValue: "userCommand",
                    commandID: ProductStateCommandID(rawValue: uuid(value + 5_000)),
                    sessionID: nil,
                    sessionLineID: nil
                )
            )
        },
        unresolvedEntries: (0..<unresolved).map {
            listEntry(
                value * 100 + 40 + $0,
                list: value,
                state: .unresolved(rawValue: "future")
            )
        },
        createdAt: date(createdAt ?? value),
        updatedAt: date((createdAt ?? value) + 1),
        metadata: metadata(scope: .list(id), listRevision: revision)
    )
}

private func listEntry(
    _ value: Int,
    list: Int,
    state: ProductStateListEntryProjectionState
) -> ProductStateListEntryProjection {
    let identity = ProductStateListEntryIdentity(
        id: entryID(value),
        listID: ProductStateListID(rawValue: uuid(list)),
        productID: productID(value)
    )
    return ProductStateListEntryProjection(
        identity: identity,
        state: state,
        quantity: 1,
        unitRawValue: "unit",
        note: nil,
        sortOrder: Double(value),
        product: productProjection(value),
        issues: [],
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

private func acquisitionResult(
    _ value: Int,
    outcome: ProductAcquisitionOutcome
) -> ProductAcquisitionResult {
    ProductAcquisitionResult(
        confirmation: ProductAcquisitionConfirmation(
            productID: productID(value),
            commandID: ProductStateCommandID(rawValue: uuid(value + 1_000)),
            effectiveAt: date(value),
            evidence: .manual(
                name: "Reviewed Product \(value)",
                imageData: Data([UInt8(value % 255)])
            ),
            confirmed: true
        ),
        outcome: outcome,
        resolvedCatalogID: nil,
        commandDiagnostic: nil
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

private func listScope(
    _ value: Int,
    revision revisionValue: UInt64
) -> ProductStateListScopeRequest {
    ProductStateListScopeRequest(
        listID: ProductStateListID(rawValue: uuid(value)),
        expectedRevision: revision(revisionValue)
    )
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

private func source(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
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
