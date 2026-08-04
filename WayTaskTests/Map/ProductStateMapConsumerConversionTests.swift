import CoreLocation
import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductStateMapConsumerConversionTests: XCTestCase {
    func testExactProductListStoreAndLocationIdentitiesArePreserved()
        throws
    {
        let presentation = try t18Available(t18State())

        XCTAssertEqual(presentation.listID, t18ListID(100))
        XCTAssertEqual(presentation.listRevision, t18Revision(7))
        XCTAssertEqual(
            presentation.recommendations.map(\.id),
            [t18UUID(201), t18UUID(202)]
        )
        XCTAssertTrue(
            presentation.markers.contains {
                $0.id == .productAtStore(
                    t18ProductID(10),
                    t18UUID(201)
                )
            }
        )
        XCTAssertTrue(
            presentation.markers.contains {
                $0.id == .productAtSavedLocation(
                    t18ProductID(10),
                    t18UUID(500),
                    t18EntryID(10)
                )
            }
        )
    }

    func testMarkerOrderingUsesExactIdentityAndNeverDisplayText()
        throws
    {
        let presentation = try t18Available(t18State())

        XCTAssertEqual(
            presentation.markers.map(\.id),
            [
                .savedLocation(t18UUID(500)),
                .productAtSavedLocation(
                    t18ProductID(10),
                    t18UUID(500),
                    t18EntryID(10)
                ),
                .store(t18UUID(201)),
                .productAtStore(t18ProductID(10), t18UUID(201)),
                .productAtStore(t18ProductID(20), t18UUID(201)),
                .store(t18UUID(202)),
                .productAtStore(t18ProductID(10), t18UUID(202))
            ]
        )
        XCTAssertEqual(
            presentation.clusteringInputIDs,
            presentation.markers.map(\.id)
        )
    }

    func testEquivalentStoreInputOrderProducesIdenticalMarkers()
        throws
    {
        let first = try t18Available(
            t18State(stores: t18Stores())
        )
        let second = try t18Available(
            t18State(stores: Array(t18Stores().reversed()))
        )

        XCTAssertEqual(first.markers, second.markers)
        XCTAssertEqual(first.recommendations, second.recommendations)
    }

    func testDuplicateStoreIdentityIsRejectedInsteadOfMerged() {
        let store = t18Stores()[0]
        let state = t18State(stores: [store, store])

        XCTAssertEqual(
            t18Invalid(state),
            .duplicateStoreIdentity(store.id)
        )
    }

    func testMissingRecommendedStoreIsExplicit() {
        let state = t18State(stores: [t18Stores()[1]])

        XCTAssertEqual(
            t18Invalid(state),
            .missingStoreIdentity(t18UUID(202).uuidString)
        )
    }

    func testRecommendationOrderMustRemainAuthoritative() {
        let projection = t18Recommendations(
            values: Array(t18RecommendationValues().reversed())
        )
        let state = t18State(recommendations: .projection(projection))

        XCTAssertEqual(
            t18Invalid(state),
            .recommendationOrderMismatch
        )
    }

    func testRecommendationCoverageAndReasonsRemainExact() throws {
        let presentation = try t18Available(t18State())
        let recommendation = try XCTUnwrap(
            presentation.recommendations.first
        )
        let reason = try XCTUnwrap(
            recommendation.coverageReasons.first
        )

        XCTAssertEqual(
            recommendation.estimatedCoveredProductIDs,
            [t18ProductID(10), t18ProductID(20)]
        )
        XCTAssertEqual(recommendation.uncoveredProductIDs, [])
        XCTAssertEqual(recommendation.coveredProductCount, 2)
        XCTAssertEqual(recommendation.uncoveredProductCount, 0)
        XCTAssertEqual(reason.group, .grocery)
        XCTAssertEqual(reason.rankingReasons, ["Exact published reason"])
        XCTAssertEqual(reason.rankingSignals.map(\.reason), ["Signal reason"])
        XCTAssertEqual(reason.availabilityClaim, .estimatedOnly)
    }

    func testRecommendationCoverageCannotBeFabricated() {
        let values = [
            ProductStateStoreRecommendationProjection(
                storeID: t18UUID(201).uuidString,
                estimatedCoveredProductIDs: [t18ProductID(10)],
                uncoveredProductIDs: [],
                confidence: 0.9,
                evidenceAt: t18Date(20)
            )
        ]
        let state = t18State(
            recommendations: .projection(
                t18Recommendations(values: values)
            ),
            stores: [t18Stores()[1]],
            coverages: [t18Coverages()[0]]
        )

        XCTAssertEqual(
            t18Invalid(state),
            .invalidRecommendation(t18UUID(201).uuidString)
        )
    }

    func testListScopeAndRevisionMismatchAreRejected() {
        let wrongList = t18MapContext(
            owner: .list(t18ListID(999), t18Revision(7)),
            scope: .list(t18ListID(999))
        )
        XCTAssertEqual(
            t18Invalid(t18State(mapContext: .projection(wrongList))),
            .contextMetadataMismatch
        )

        let wrongRevision = t18MapContext(
            owner: .list(t18ListID(100), t18Revision(8)),
            scope: .list(t18ListID(100)),
            revision: t18Revision(8)
        )
        XCTAssertEqual(
            t18Invalid(t18State(mapContext: .projection(wrongRevision))),
            .contextMetadataMismatch
        )
    }

    func testReadyPlanCannotFallBackToListOwnedMapContext() {
        let listContext = t18MapContext(
            owner: .list(t18ListID(100), t18Revision(7)),
            scope: .list(t18ListID(100))
        )

        XCTAssertEqual(
            t18Invalid(t18State(mapContext: .projection(listContext))),
            .planScopeMismatch
        )
    }

    func testPlanMapContextCannotDropIncludedEntry() {
        let base = t18MapContext()
        let shortened = ProductStateMapShoppingContextProjection(
            owner: base.owner,
            items: [base.items[0]],
            metadata: base.metadata
        )
        let discovery = ProductStateDiscoveryContextProjection(
            owner: base.owner,
            eligibleProductIDs: [t18ProductID(10)],
            unresolvedItems: [],
            metadata: base.metadata
        )
        let recommendations = t18Recommendations(
            values: [
                ProductStateStoreRecommendationProjection(
                    storeID: t18UUID(201).uuidString,
                    estimatedCoveredProductIDs: [t18ProductID(10)],
                    uncoveredProductIDs: [],
                    confidence: 0.9,
                    evidenceAt: t18Date(20)
                )
            ]
        )

        XCTAssertEqual(
            t18Invalid(
                t18State(
                    mapContext: .projection(shortened),
                    discovery: .projection(discovery),
                    recommendations: .projection(recommendations),
                    stores: [t18Stores()[1]],
                    coverages: []
                )
            ),
            .contextMetadataMismatch
        )
    }

    func testDiscoveryOwnerMismatchIsExplicit() {
        let discovery = t18Discovery(
            owner: .list(t18ListID(100), t18Revision(7)),
            scope: .list(t18ListID(100))
        )

        XCTAssertEqual(
            t18Invalid(t18State(discovery: .projection(discovery))),
            .discoveryMismatch
        )
    }

    func testRecommendationOwnerMismatchIsExplicit() {
        let recommendations = t18Recommendations(
            owner: .list(t18ListID(100), t18Revision(7)),
            scope: .list(t18ListID(100))
        )

        XCTAssertEqual(
            t18Invalid(
                t18State(recommendations: .projection(recommendations))
            ),
            .recommendationMetadataMismatch
        )
    }

    func testRecommendationRequiresPublishedStoreProvenance() {
        let base = t18Recommendations()
        let recommendations = ProductStateStoreRecommendationsProjection(
            owner: base.owner,
            recommendations: base.recommendations,
            metadata: t18Metadata(
                scope: .plan(t18PlanID(300), t18ListID(100)),
                revision: t18Revision(7)
            )
        )

        XCTAssertEqual(
            t18Invalid(
                t18State(recommendations: .projection(recommendations))
            ),
            .recommendationMetadataMismatch
        )
    }

    func testCoverageWithoutRecommendationIsRejectedNotDropped() {
        let extraStore = ProductStateMapStorePresentationInput(
            store: t18Store(203, open: true)
        )
        let extraCoverage = t18Coverage(
            store: t18Store(203, open: true),
            matched: [10],
            missing: [20],
            score: 60,
            distance: 140
        )
        let state = t18State(
            stores: t18Stores() + [extraStore],
            coverages: t18Coverages() + [extraCoverage]
        )

        XCTAssertEqual(
            t18Invalid(state),
            .coverageRecommendationMismatch(t18UUID(203))
        )
    }

    func testSessionOwnedContextIsRejectedUntilT19() {
        let context = t18MapContext(
            owner: .session(
                ProductStateSessionID(rawValue: t18UUID(700)),
                ProductStateSessionRevision(value: 1),
                ProductStateSessionSnapshotID(rawValue: t18UUID(701))
            ),
            scope: .session(
                ProductStateSessionID(rawValue: t18UUID(700))
            ),
            revision: nil
        )

        XCTAssertEqual(
            t18Invalid(t18State(mapContext: .projection(context))),
            .sessionContextRequiresT19
        )
    }

    func testProjectionStalenessIsNamedAndContentRemainsReadOnly()
        throws
    {
        let context = t18MapContext(
            freshness: .stale([.evidenceExpired])
        )
        let state = t18State(mapContext: .projection(context))

        guard case let .stale(presentation, reasons) = state.content else {
            return XCTFail("Expected stale Map presentation")
        }
        XCTAssertEqual(
            reasons.projectionReasons,
            [.evidenceExpired]
        )
        XCTAssertEqual(presentation.listID, t18ListID(100))
    }

    func testPlanStalenessIsPreservedWithoutChangingPlan() {
        let shopping = t18Shopping(
            status: t18PlanStatus(readiness: .stale)
        )
        let state = t18State(shopping: shopping)

        guard case let .stale(_, reasons) = state.content else {
            return XCTFail("Expected stale Plan presentation")
        }
        XCTAssertEqual(reasons.planReasons, [.sourceRevisionChanged])
    }

    func testUnavailableProjectionIsExplicit() {
        let unavailable = t18Metadata(
            scope: .plan(t18PlanID(300), t18ListID(100)),
            freshness: .unavailable(.repositoryReadFailed),
            revision: t18Revision(7)
        )
        let state = t18State(mapContext: .unavailable(unavailable))

        guard case let .unavailable(value) = state.content else {
            return XCTFail("Expected unavailable Map presentation")
        }
        XCTAssertEqual(value.metadata, unavailable)
        XCTAssertEqual(value.listID, t18ListID(100))
        XCTAssertEqual(value.listRevision, t18Revision(7))
    }

    func testUnavailablePlanStatusIsExplicit() {
        let shopping = t18Shopping(
            status: t18PlanStatus(readiness: .unavailable)
        )
        let state = t18State(shopping: shopping)

        guard case let .unavailable(value) = state.content else {
            return XCTFail("Expected unavailable Plan presentation")
        }
        XCTAssertEqual(value.listID, t18ListID(100))
        XCTAssertEqual(value.listRevision, t18Revision(7))
        XCTAssertEqual(value.planReason, .repositoryReadFailed)
    }

    func testInvalidPlanStatusIsExplicit() {
        let shopping = t18Shopping(
            status: t18PlanStatus(readiness: .invalidOrIncomplete)
        )

        XCTAssertEqual(
            t18Invalid(t18State(shopping: shopping)),
            .planInvalid([.invalidEligibleEntry])
        )
    }

    func testUnresolvedShoppingProductsRemainExplicit() throws {
        let unresolvedEntry = t18Entry(
            40,
            state: .unresolved(rawValue: "legacy_unknown"),
            issues: [.malformedEntryState]
        )
        let list = t18NamedList(
            unresolved: [unresolvedEntry]
        )
        let shopping = t18Shopping(
            list: list,
            status: t18PlanStatus()
        )
        let presentation = try t18Available(
            t18State(shopping: shopping)
        )

        XCTAssertTrue(
            presentation.unresolvedProducts.contains {
                $0.source == .shoppingEntry &&
                    $0.entryID == t18EntryID(40) &&
                    $0.productID == t18ProductID(40)
            }
        )
    }

    func testExcludedProductsRetainExactIdentityAndReason() throws {
        let presentation = try t18Available(t18State())

        XCTAssertEqual(presentation.excludedProducts.count, 1)
        XCTAssertEqual(
            presentation.excludedProducts.first?.entryID,
            t18EntryID(30)
        )
        XCTAssertEqual(
            presentation.excludedProducts.first?.productID,
            t18ProductID(30)
        )
        XCTAssertEqual(
            presentation.excludedProducts.first?.reason,
            .explicitUserExclusion
        )
    }

    func testExactSavedLocationLinkCreatesSeparateProductMarker()
        throws
    {
        let presentation = try t18Available(t18State())
        let location = try XCTUnwrap(presentation.savedLocations.first)

        XCTAssertEqual(location.id, t18UUID(500))
        XCTAssertEqual(location.note, "Saved note")
        XCTAssertEqual(location.links.first?.state, .exactCurrentList)
        XCTAssertTrue(
            presentation.markers.contains {
                $0.id == .productAtSavedLocation(
                    t18ProductID(10),
                    t18UUID(500),
                    t18EntryID(10)
                )
            }
        )
    }

    func testUnprovenSavedLocationLinkIsNotSilentlyDiscarded()
        throws
    {
        let location = t18SavedLocation(
            links: [
                ProductStateSavedLocationLinkProjection(
                    productID: t18ProductID(99),
                    listID: nil,
                    entryID: nil,
                    authority: .unproven,
                    isAuthoritativeProductStateLink: false
                )
            ]
        )
        let presentation = try t18Available(
            t18State(savedLocations: [.projection(location)])
        )

        XCTAssertEqual(
            presentation.savedLocations.first?.links.first?.state,
            .unproven
        )
        XCTAssertTrue(
            presentation.unresolvedProducts.contains {
                $0.source == .savedLocation(t18UUID(500)) &&
                    $0.productID == t18ProductID(99)
            }
        )
        XCTAssertFalse(
            presentation.markers.contains {
                if case let .productAtSavedLocation(
                    productID,
                    _,
                    _
                ) = $0.id {
                    return productID == t18ProductID(99)
                }
                return false
            }
        )
    }

    func testMissingSavedLocationCoordinateIsRetainedWithoutMarker()
        throws
    {
        let location = t18SavedLocation(latitude: nil, longitude: nil)
        let presentation = try t18Available(
            t18State(savedLocations: [.projection(location)])
        )

        XCTAssertEqual(
            presentation.savedLocations.first?.issues,
            [.missingCoordinate]
        )
        XCTAssertFalse(
            presentation.markers.contains {
                $0.id == .savedLocation(t18UUID(500))
            }
        )
    }

    func testUnavailableSavedLocationRemainsVisibleToDetailConsumer()
        throws
    {
        let metadata = t18Metadata(
            scope: .location(t18UUID(900)),
            freshness: .unavailable(.repositoryReadFailed)
        )
        let state = t18State(
            savedLocations: [
                .projection(t18SavedLocation()),
                .unavailable(metadata)
            ]
        )
        let presentation = try t18Available(state)

        XCTAssertEqual(
            presentation.unavailableSavedLocations,
            [metadata]
        )
        XCTAssertEqual(
            ProductStateLocationDetailProjectionConsumer.make(
                locationID: t18UUID(900),
                mapState: state
            ),
            .unavailable(metadata)
        )
    }

    func testDuplicateSavedLocationsAreRejectedWithoutMerging() {
        let location = t18SavedLocation()
        let state = t18State(
            savedLocations: [.projection(location), .projection(location)]
        )

        XCTAssertEqual(
            t18Invalid(state),
            .duplicateSavedLocation(t18UUID(500))
        )
    }

    func testFiltersProduceStableMarkerSubsequences() throws {
        let all = try t18Available(t18State())
        let products = try t18Available(
            t18State(filter: .products)
        )
        let stores = try t18Available(t18State(filter: .stores))
        let saved = try t18Available(
            t18State(filter: .savedLocations)
        )
        let open = try t18Available(t18State(filter: .openStores))

        XCTAssertEqual(
            products.visibleMarkers,
            all.markers.filter {
                if case .product = $0.kind { return true }
                return false
            }
        )
        XCTAssertEqual(
            stores.visibleMarkers.map(\.id),
            [.store(t18UUID(201)), .store(t18UUID(202))]
        )
        XCTAssertEqual(
            saved.visibleMarkers.map(\.id),
            [.savedLocation(t18UUID(500))]
        )
        XCTAssertEqual(
            open.visibleMarkers.map(\.id),
            [.store(t18UUID(201))]
        )
    }

    func testCoveredProductFilterPreservesExactRecommendationOrder()
        throws
    {
        let presentation = try t18Available(
            t18State(filter: .coveredProduct(t18ProductID(10)))
        )

        XCTAssertEqual(
            presentation.visibleMarkers.map(\.id),
            [
                .productAtSavedLocation(
                    t18ProductID(10),
                    t18UUID(500),
                    t18EntryID(10)
                ),
                .productAtStore(t18ProductID(10), t18UUID(201)),
                .productAtStore(t18ProductID(10), t18UUID(202))
            ]
        )
        XCTAssertEqual(
            presentation.visibleRecommendations.map(\.id),
            [t18UUID(201), t18UUID(202)]
        )
    }

    func testSearchUsesDisplayOnlyAndPreservesMarkerIdentity() throws {
        let presentation = try t18Available(
            t18State(searchText: "milk")
        )

        XCTAssertEqual(
            presentation.visibleMarkers.map(\.id),
            [
                .savedLocation(t18UUID(500)),
                .productAtSavedLocation(
                    t18ProductID(10),
                    t18UUID(500),
                    t18EntryID(10)
                ),
                .store(t18UUID(201)),
                .productAtStore(t18ProductID(10), t18UUID(201)),
                .store(t18UUID(202)),
                .productAtStore(t18ProductID(10), t18UUID(202))
            ]
        )
        XCTAssertEqual(
            presentation.visibleRecommendations.map(\.id),
            [t18UUID(201), t18UUID(202)]
        )
        XCTAssertNil(presentation.selected)
    }

    func testShoppingListFilterRetainsScopedSavedLocationMarker()
        throws
    {
        let presentation = try t18Available(
            t18State(filter: .shoppingList)
        )

        XCTAssertTrue(
            presentation.visibleMarkers.contains {
                $0.id == .savedLocation(t18UUID(500))
            }
        )
    }

    func testExactSelectionIsPreservedEvenWhenFilteredOut() throws {
        let selection = ProductStateMapProjectionSelection.marker(
            .store(t18UUID(201)),
            t18ListID(100),
            t18Revision(7)
        )
        let presentation = try t18Available(
            t18State(selection: selection, filter: .products)
        )

        XCTAssertEqual(
            presentation.selected?.marker.id,
            .store(t18UUID(201))
        )
        XCTAssertEqual(presentation.selected?.isVisible, false)
    }

    func testSelectionScopeMismatchNeverChoosesFallback() {
        let selection = ProductStateMapProjectionSelection.marker(
            .store(t18UUID(201)),
            t18ListID(999),
            t18Revision(7)
        )

        XCTAssertEqual(
            t18Invalid(t18State(selection: selection)),
            .selectionScopeMismatch
        )
    }

    func testUnknownSelectionNeverChoosesFirstMarker() {
        let markerID = ProductStateMapMarkerID.store(t18UUID(999))
        let selection = ProductStateMapProjectionSelection.marker(
            markerID,
            t18ListID(100),
            t18Revision(7)
        )

        XCTAssertEqual(
            t18Invalid(t18State(selection: selection)),
            .selectionNotFound(markerID)
        )
    }

    func testNavigationIntentIsInertAndCarriesExactScope() throws {
        let presentation = try t18Available(t18State())
        let markerID = ProductStateMapMarkerID.productAtStore(
            t18ProductID(10),
            t18UUID(201)
        )

        XCTAssertEqual(
            ProductStateMapProjectionConsumer.navigationIntent(
                for: markerID,
                in: presentation
            ),
            .product(
                t18ProductID(10),
                t18ListID(100),
                t18Revision(7),
                storeID: t18UUID(201),
                savedLocationID: nil
            )
        )
        XCTAssertNil(presentation.selected)
    }

    func testUnknownMarkerProducesNoNavigationIntent() throws {
        let presentation = try t18Available(t18State())

        XCTAssertNil(
            ProductStateMapProjectionConsumer.navigationIntent(
                for: .store(t18UUID(999)),
                in: presentation
            )
        )
    }

    func testMainMapScreenConsumesOnlyProjectionState() throws {
        let state = t18State()
        let presentation = try t18Available(state)

        XCTAssertEqual(
            ProductStateMainMapScreenConsumer.make(state),
            .available(ProductStateMainMapScreenPresentation(presentation))
        )
        guard case let .available(screen) =
            ProductStateMainMapScreenConsumer.make(state) else {
            return XCTFail("Expected exact Main Map presentation")
        }
        XCTAssertEqual(screen.markers, presentation.markers)
        XCTAssertEqual(screen.recommendations, presentation.recommendations)
        XCTAssertEqual(
            screen.unresolvedProducts,
            presentation.unresolvedProducts
        )
        XCTAssertEqual(
            screen.excludedProducts,
            presentation.excludedProducts
        )
    }

    func testLocationDetailUsesExactLocationWithoutFallback() {
        let state = t18State()

        guard case let .available(detail) =
            ProductStateLocationDetailProjectionConsumer.make(
                locationID: t18UUID(500),
                mapState: state
            ) else {
            return XCTFail("Expected exact saved location")
        }
        XCTAssertEqual(detail.locationID, t18UUID(500))
        XCTAssertEqual(detail.listID, t18ListID(100))
        XCTAssertEqual(detail.listRevision, t18Revision(7))
        XCTAssertEqual(
            ProductStateLocationDetailProjectionConsumer.make(
                locationID: t18UUID(999),
                mapState: state
            ),
            .notFound(t18UUID(999))
        )
    }

    func testTargetSectionsContainNoLegacyPersistenceOrSideEffects()
        throws
    {
        let mapSection = t18Section(
            try t18AppSource("MapViewModel.swift"),
            from: "// MARK: - T-18 immutable Map presentation consumer",
            to: "struct RuntimeStore: Identifiable"
        )
        let screenSection = t18Section(
            try t18AppSource("WayTask/MainMapView.swift"),
            from: "// MARK: - T-18 target Main Map presentation",
            to: "struct MainMapView: View"
        )
        let detailSection = t18Section(
            try t18AppSource("WayTask/LocationDetailView.swift"),
            from: "// MARK: - T-18 target saved-location presentation",
            to: "struct LocationDetailView: View"
        )
        let target = mapSection + screenSection + detailSection
        for forbidden in [
            "@Query",
            "ModelContext",
            "ShoppingItem.isCompleted",
            "ShoppingListEntry.isChecked",
            "StoreRuntimeIdentity",
            "materializedWithStableIdentity",
            "ProductStateCommandCoordinator",
            "ProductStateTransactionCoordinator",
            "ShoppingSessionService",
            "UNUserNotificationCenter",
            "CLCircularRegion",
            "startMonitoring",
            ".save()",
            ".delete(",
            "openURL(",
            "requestWhenInUseAuthorization"
        ] {
            XCTAssertFalse(target.contains(forbidden), forbidden)
        }
    }

    func testT18TargetConsumersRemainInactiveUntilCutover() throws {
        XCTAssertFalse(
            try t18AppSource("MapViewModel.swift")
                .contains("ProductStateMapProjectionConsumer.make(")
        )
        XCTAssertFalse(
            try t18AppSource("WayTask/MainMapView.swift")
                .contains("ProductStateMainMapScreenConsumer.make(")
        )
        XCTAssertFalse(
            try t18AppSource("WayTask/LocationDetailView.swift")
                .contains(
                    "ProductStateLocationDetailProjectionConsumer.make("
                )
        )
        XCTAssertFalse(
            try t18AppSource("WayTask/LocationManager.swift")
                .contains("ProductStateMapProjectionConsumer")
        )
    }
}

private enum T18TestFailure: Error {
    case expectedAvailable
}

private func t18Available(
    _ state: ProductStateMapProjectionConsumerState
) throws -> ProductStateMapProjectionPresentation {
    guard case let .available(value) = state.content else {
        throw T18TestFailure.expectedAvailable
    }
    return value
}

private func t18Invalid(
    _ state: ProductStateMapProjectionConsumerState
) -> ProductStateMapProjectionInvalidReason? {
    guard case let .invalid(reason) = state.content else { return nil }
    return reason
}

private func t18State(
    shopping: ShoppingWorkspaceProjectionConsumerState? = nil,
    mapContext: ProductStateProjectionOutcome<
        ProductStateMapShoppingContextProjection
    >? = nil,
    discovery: ProductStateProjectionOutcome<
        ProductStateDiscoveryContextProjection
    >? = nil,
    recommendations: ProductStateProjectionOutcome<
        ProductStateStoreRecommendationsProjection
    >? = nil,
    stores: [ProductStateMapStorePresentationInput]? = nil,
    coverages: [ShoppingPlanStoreCoverage]? = nil,
    savedLocations: [
        ProductStateProjectionOutcome<
            ProductStateSavedLocationEvidenceProjection
        >
    ]? = nil,
    selection: ProductStateMapProjectionSelection = .none,
    filter: ProductStateMapProjectionFilter = .all,
    searchText: String = ""
) -> ProductStateMapProjectionConsumerState {
    ProductStateMapProjectionConsumer.make(
        shopping: shopping ?? t18Shopping(),
        mapContext: mapContext ?? .projection(t18MapContext()),
        discovery: discovery ?? .projection(t18Discovery()),
        recommendations: recommendations ??
            .projection(t18Recommendations()),
        stores: stores ?? t18Stores(),
        coverages: coverages ?? t18Coverages(),
        savedLocations: savedLocations ??
            [.projection(t18SavedLocation())],
        selection: selection,
        filter: filter,
        searchText: searchText
    )
}

private func t18Shopping(
    list: ProductStateNamedListProjection? = nil,
    status: ShoppingPlanConsumerStatus? = nil
) -> ShoppingWorkspaceProjectionConsumerState {
    ShoppingWorkspaceProjectionConsumer.make(
        namedList: .projection(list ?? t18NamedList()),
        planStatus: status ?? t18PlanStatus()
    )
}

private func t18NamedList(
    unresolved: [ProductStateListEntryProjection] = []
) -> ProductStateNamedListProjection {
    ProductStateNamedListProjection(
        id: t18ListID(100),
        revision: t18Revision(7),
        title: "Exact Map List",
        purposeRawValue: "named",
        neededEntries: [t18Entry(10), t18Entry(20), t18Entry(30)],
        resolvedEntries: [],
        unresolvedEntries: unresolved,
        createdAt: t18Date(1),
        updatedAt: t18Date(2),
        metadata: t18Metadata(
            scope: .list(t18ListID(100)),
            revision: t18Revision(7)
        )
    )
}

private func t18Entry(
    _ value: Int,
    state: ProductStateListEntryProjectionState = .needed,
    issues: [ProductStateProjectionOmissionReason] = []
) -> ProductStateListEntryProjection {
    ProductStateListEntryProjection(
        identity: ProductStateListEntryIdentity(
            id: t18EntryID(value),
            listID: t18ListID(100),
            productID: t18ProductID(value)
        ),
        state: state,
        quantity: 1,
        unitRawValue: "unit",
        note: "note-\(value)",
        sortOrder: Double(value),
        product: t18Product(value),
        issues: issues,
        createdAt: t18Date(value),
        updatedAt: t18Date(value + 1)
    )
}

private func t18Product(_ value: Int) -> ProductStateProductProjection {
    let name: String
    let category: String
    switch value {
    case 10:
        name = "Milk"
        category = "Grocery"
    case 20:
        name = "Bread"
        category = "Grocery"
    case 30:
        name = "Excluded Cable"
        category = "Electronics"
    default:
        name = "Product \(value)"
        category = "Other"
    }
    return ProductStateProductProjection(
        id: t18ProductID(value),
        revision: UInt64(value),
        libraryLifecycle: .active,
        libraryRemovedAt: nil,
        displayName: name,
        brand: "Brand \(value)",
        category: category,
        barcode: nil,
        catalogID: ProductStateCatalogID(rawValue: "catalog-\(value)"),
        catalogDisplayNameSnapshot: name,
        catalogDisplayLocaleSnapshot: "en",
        catalogCategoryIDSnapshot: category.lowercased(),
        catalogCategoryDisplayNameSnapshot: category,
        catalogIconKeySnapshot: "icon-\(value)",
        catalogSnapshotUpdatedAt: t18Date(value),
        createdAt: t18Date(value),
        updatedAt: t18Date(value + 1)
    )
}

private func t18PlanStatus(
    readiness: ShoppingPlanConsumerReadiness = .currentReady
) -> ShoppingPlanConsumerStatus {
    ShoppingPlanConsumerStatus(
        readiness: readiness,
        attention: .explicitExclusions,
        staleReasons: readiness == .stale
            ? [.sourceRevisionChanged] : [],
        invalidReasons: readiness == .invalidOrIncomplete
            ? [.invalidEligibleEntry] : [],
        unavailableReason: readiness == .unavailable
            ? .repositoryReadFailed : nil,
        sourceListID: t18ListID(100),
        sourceRevision: t18Revision(7),
        inputFingerprint: "t18-input",
        includedEntryIDs: [t18EntryID(10), t18EntryID(20)],
        explicitlyExcludedEntryIDs: [t18EntryID(30)],
        unresolvedEntryIDs: []
    )
}

private func t18MapContext(
    owner: ProductStateShoppingContextOwner = .plan(
        t18PlanID(300),
        t18ListID(100),
        t18Revision(7)
    ),
    scope: ProductStateProjectionScope = .plan(
        t18PlanID(300),
        t18ListID(100)
    ),
    revision: ProductStateListRevision? = t18Revision(7),
    freshness: ProductStateProjectionFreshness = .current
) -> ProductStateMapShoppingContextProjection {
    ProductStateMapShoppingContextProjection(
        owner: owner,
        items: [10, 20].map {
            ProductStateShoppingContextItemProjection(
                productID: t18ProductID($0),
                entryID: t18EntryID($0),
                sessionLineID: nil,
                displayNameSnapshot: t18Product($0).displayName,
                isQualified: true
            )
        },
        metadata: t18Metadata(
            scope: scope,
            freshness: freshness,
            revision: revision
        )
    )
}

private func t18Discovery(
    owner: ProductStateShoppingContextOwner = .plan(
        t18PlanID(300),
        t18ListID(100),
        t18Revision(7)
    ),
    scope: ProductStateProjectionScope = .plan(
        t18PlanID(300),
        t18ListID(100)
    )
) -> ProductStateDiscoveryContextProjection {
    ProductStateDiscoveryContextProjection(
        owner: owner,
        eligibleProductIDs: [t18ProductID(10), t18ProductID(20)],
        unresolvedItems: [],
        metadata: t18Metadata(
            scope: scope,
            revision: t18Revision(7)
        )
    )
}

private func t18Recommendations(
    owner: ProductStateShoppingContextOwner = .plan(
        t18PlanID(300),
        t18ListID(100),
        t18Revision(7)
    ),
    scope: ProductStateProjectionScope = .plan(
        t18PlanID(300),
        t18ListID(100)
    ),
    values: [ProductStateStoreRecommendationProjection]? = nil
) -> ProductStateStoreRecommendationsProjection {
    ProductStateStoreRecommendationsProjection(
        owner: owner,
        recommendations: values ?? t18RecommendationValues(),
        metadata: t18Metadata(
            scope: scope,
            revision: t18Revision(7),
            provenances: [
                .targetProductState,
                .publishedStoreEvidence(version: "t18-store-v1")
            ]
        )
    )
}

private func t18RecommendationValues()
    -> [ProductStateStoreRecommendationProjection] {
    [
        ProductStateStoreRecommendationProjection(
            storeID: t18UUID(201).uuidString,
            estimatedCoveredProductIDs: [
                t18ProductID(10),
                t18ProductID(20)
            ],
            uncoveredProductIDs: [],
            confidence: 0.9,
            evidenceAt: t18Date(20)
        ),
        ProductStateStoreRecommendationProjection(
            storeID: t18UUID(202).uuidString,
            estimatedCoveredProductIDs: [t18ProductID(10)],
            uncoveredProductIDs: [t18ProductID(20)],
            confidence: 0.8,
            evidenceAt: t18Date(21)
        )
    ]
}

private func t18Stores() -> [ProductStateMapStorePresentationInput] {
    [t18Store(202, open: false), t18Store(201, open: true)]
        .map { ProductStateMapStorePresentationInput(store: $0) }
}

private func t18Store(_ value: Int, open: Bool) -> MapStore {
    MapStore(
        id: t18UUID(value),
        locationID: nil,
        title: value == 201 ? "Alpha Market" : "Beta Market",
        coordinate: CLLocationCoordinate2D(
            latitude: 32 + Double(value) / 10_000,
            longitude: 34 + Double(value) / 10_000
        ),
        radius: 200,
        itemNames: ["legacy-item"],
        completedItemNames: ["legacy-completed"],
        isOpen: open,
        rating: 4.5,
        storeCategories: [.grocery],
        queryEvidenceCategories: [.grocery],
        websiteURL: URL(string: "https://example.com/\(value)"),
        sourceType: .appleMaps
    )
}

private func t18Coverages() -> [ShoppingPlanStoreCoverage] {
    [
        t18Coverage(
            store: t18Store(201, open: true),
            matched: [10, 20],
            missing: [],
            score: 90,
            distance: 100
        ),
        t18Coverage(
            store: t18Store(202, open: false),
            matched: [10],
            missing: [20],
            score: 70,
            distance: 120
        )
    ]
}

private func t18Coverage(
    store: MapStore,
    matched: [Int],
    missing: [Int],
    score: Double,
    distance: Double
) -> ShoppingPlanStoreCoverage {
    ShoppingPlanStoreCoverage(
        store: store,
        group: .grocery,
        matchedEntryIDs: matched.map(t18EntryID),
        matchedProductIDs: matched.map(t18ProductID),
        missingEntryIDs: missing.map(t18EntryID),
        missingProductIDs: missing.map(t18ProductID),
        coverageScore: Double(matched.count) /
            Double(max(matched.count + missing.count, 1)),
        distance: distance,
        ranking: StoreScore(
            score: score,
            confidence: score / 100,
            reasons: ["Exact published reason"],
            signals: [
                StoreRealitySignalResult(
                    kind: .shoppingListCoverage,
                    score: score,
                    confidenceCap: score / 100,
                    reason: "Signal reason"
                )
            ]
        ),
        availabilityClaim: .estimatedOnly,
        namedExclusions: [
            ShoppingPlanConsumerExclusion(
                identity: t18Entry(30).identity,
                reason: .explicitUserExclusion
            )
        ],
        classificationUnresolvedEntryIDs: []
    )
}

private func t18SavedLocation(
    latitude: Double? = 32.1,
    longitude: Double? = 34.8,
    links: [ProductStateSavedLocationLinkProjection]? = nil
) -> ProductStateSavedLocationEvidenceProjection {
    ProductStateSavedLocationEvidenceProjection(
        locationID: t18UUID(500),
        displayNameSnapshot: "Exact Saved Store",
        noteSnapshot: "Saved note",
        latitude: latitude,
        longitude: longitude,
        links: links ?? [
            ProductStateSavedLocationLinkProjection(
                productID: t18ProductID(10),
                listID: t18ListID(100),
                entryID: t18EntryID(10),
                authority: .exactTargetReference,
                isAuthoritativeProductStateLink: true
            )
        ],
        metadata: t18Metadata(
            scope: .location(t18UUID(500)),
            provenances: [.savedLocationEvidence(version: "t18-location-v1")]
        )
    )
}

private func t18Metadata(
    scope: ProductStateProjectionScope,
    freshness: ProductStateProjectionFreshness = .current,
    revision: ProductStateListRevision? = nil,
    provenances: [ProductStateProjectionProvenance] = [.targetProductState]
) -> ProductStateProjectionMetadata {
    ProductStateProjectionMetadata(
        scope: scope,
        freshness: freshness,
        listRevision: revision,
        sessionRevision: nil,
        sessionSnapshotID: nil,
        provenances: provenances,
        omissions: [],
        cachePolicy: .disabledDirectRebuild
    )
}

private func t18ListID(_ value: Int) -> ProductStateListID {
    ProductStateListID(rawValue: t18UUID(value))
}

private func t18ProductID(_ value: Int) -> ProductStateProductID {
    ProductStateProductID(rawValue: t18UUID(value))
}

private func t18EntryID(_ value: Int) -> ProductStateListEntryID {
    ProductStateListEntryID(rawValue: t18UUID(value))
}

private func t18PlanID(_ value: Int) -> ProductStatePlanID {
    ProductStatePlanID(rawValue: t18UUID(value))
}

private func t18Revision(_ value: UInt64) -> ProductStateListRevision {
    ProductStateListRevision(value: value)
}

private func t18UUID(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        )
    )!
}

private func t18Date(_ value: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(value))
}

private func t18SourceRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func t18AppSource(_ path: String) throws -> String {
    try String(
        contentsOf: t18SourceRoot().appendingPathComponent(path),
        encoding: .utf8
    )
}

private func t18Section(
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
