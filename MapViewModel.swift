import Combine
import CoreLocation
import Foundation
import MapKit

// MARK: - T-18 immutable Map presentation consumer

struct ProductStateMapStorePresentationInput: Equatable {
    let id: UUID
    let savedLocationID: UUID?
    let title: String
    let coordinate: ShoppingCoordinate
    let radius: Double
    let isOpen: Bool?
    let rating: Double?
    let categories: [ShoppingStoreCategory]
    let queryEvidenceCategories: [ShoppingStoreCategory]
    let websiteURL: URL?
    let sourceType: DataSourceType

    init(store: MapStore) {
        id = store.id
        savedLocationID = store.locationID
        title = store.title
        coordinate = ShoppingCoordinate(store.coordinate)
        radius = store.radius
        isOpen = store.isOpen
        rating = store.rating
        categories = store.storeCategories
        queryEvidenceCategories = store.queryEvidenceCategories
        websiteURL = store.websiteURL
        sourceType = store.sourceType
    }
}

enum ProductStateMapMarkerID: Hashable, Sendable {
    case savedLocation(UUID)
    case store(UUID)
    case productAtStore(ProductStateProductID, UUID)
    case productAtSavedLocation(
        ProductStateProductID,
        UUID,
        ProductStateListEntryID
    )
}

enum ProductStateMapMarkerKind: Equatable, Sendable {
    case savedLocation(UUID)
    case store(UUID)
    case product(
        ProductStateProductID,
        storeID: UUID?,
        savedLocationID: UUID?
    )
}

struct ProductStateMapMarkerPresentation: Identifiable, Equatable {
    let id: ProductStateMapMarkerID
    let kind: ProductStateMapMarkerKind
    let title: String
    let coordinate: ShoppingCoordinate
    let listID: ProductStateListID
    let listRevision: ProductStateListRevision
    let recommendationIndex: Int?
}

enum ProductStateMapSavedLocationLinkState: Equatable, Sendable {
    case exactCurrentList
    case outsideCurrentList
    case unproven
}

struct ProductStateMapSavedLocationLinkPresentation: Equatable {
    let productID: ProductStateProductID?
    let listID: ProductStateListID?
    let entryID: ProductStateListEntryID?
    let authority: ProductStateSavedLocationLinkAuthority
    let state: ProductStateMapSavedLocationLinkState
}

enum ProductStateMapSavedLocationIssue: Equatable, Sendable {
    case missingCoordinate
    case incompleteCoordinate
}

struct ProductStateMapSavedLocationPresentation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let note: String?
    let coordinate: ShoppingCoordinate?
    let links: [ProductStateMapSavedLocationLinkPresentation]
    let issues: [ProductStateMapSavedLocationIssue]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateMapCoverageReasonPresentation: Equatable {
    let group: ShoppingIntentGroup
    let matchedEntryIDs: [ProductStateListEntryID]
    let matchedProductIDs: [ProductStateProductID]
    let missingEntryIDs: [ProductStateListEntryID]
    let missingProductIDs: [ProductStateProductID]
    let coverageScore: Double
    let distance: CLLocationDistance?
    let rankingScore: Double
    let rankingConfidence: Double
    let rankingReasons: [String]
    let rankingSignals: [StoreRealitySignalResult]
    let availabilityClaim: ShoppingPlanStoreAvailabilityClaim
    let namedExclusionEntryIDs: [ProductStateListEntryID]
    let classificationUnresolvedEntryIDs: [ProductStateListEntryID]
}

struct ProductStateMapRecommendationPresentation: Identifiable, Equatable {
    let id: UUID
    let publishedStoreID: String
    let store: ProductStateMapStorePresentationInput
    let estimatedCoveredProductIDs: [ProductStateProductID]
    let uncoveredProductIDs: [ProductStateProductID]
    let confidence: Double
    let evidenceAt: Date
    let coverageReasons: [ProductStateMapCoverageReasonPresentation]

    var coveredProductCount: Int {
        estimatedCoveredProductIDs.count
    }

    var uncoveredProductCount: Int {
        uncoveredProductIDs.count
    }
}

enum ProductStateMapUnresolvedSource: Equatable, Sendable {
    case shoppingEntry
    case planClassification
    case discoveryContext
    case savedLocation(UUID)
}

struct ProductStateMapUnresolvedProductPresentation: Equatable {
    let source: ProductStateMapUnresolvedSource
    let ordinal: Int
    let entryID: ProductStateListEntryID?
    let productID: ProductStateProductID?
    let displayNameSnapshot: String?
    let reason: ProductStatePlanInputExclusionReason?
}

struct ProductStateMapExcludedProductPresentation: Equatable {
    let entryID: ProductStateListEntryID
    let productID: ProductStateProductID
    let displayNameSnapshot: String
    let reason: ProductStatePlanInputExclusionReason?
}

enum ProductStateMapProjectionFilter: Equatable, Sendable {
    case all
    case openStores
    case shoppingList
    case stores
    case products
    case savedLocations
    case unresolved
    case coveredProduct(ProductStateProductID)
}

enum ProductStateMapProjectionSelection: Equatable, Sendable {
    case none
    case marker(
        ProductStateMapMarkerID,
        ProductStateListID,
        ProductStateListRevision
    )
}

struct ProductStateMapSelectedPresentation: Equatable {
    let marker: ProductStateMapMarkerPresentation
    let isVisible: Bool
}

enum ProductStateMapNavigationIntent: Equatable, Sendable {
    case product(
        ProductStateProductID,
        ProductStateListID,
        ProductStateListRevision,
        storeID: UUID?,
        savedLocationID: UUID?
    )
    case store(
        UUID,
        ProductStateListID,
        ProductStateListRevision,
        ShoppingCoordinate
    )
    case savedLocation(
        UUID,
        ProductStateListID,
        ProductStateListRevision
    )
}

struct ProductStateMapStalenessPresentation: Equatable {
    let projectionReasons: [ProductStateProjectionStaleReason]
    let planReasons: [ShoppingPlanStaleReason]
}

struct ProductStateMapUnavailablePresentation: Equatable {
    let listID: ProductStateListID?
    let listRevision: ProductStateListRevision?
    let metadata: ProductStateProjectionMetadata
    let planReason: ProductStateProjectionUnavailableReason?
}

enum ProductStateMapProjectionInvalidReason: Equatable {
    case shoppingConsumerInactive
    case shoppingConsumerInvalid(ShoppingWorkspaceProjectionInvalidReason)
    case listScopeMismatch
    case listRevisionMismatch
    case planScopeMismatch
    case planInvalid([ShoppingPlanConsumerInvalidReason])
    case sessionContextRequiresT19
    case contextOwnerMismatch
    case contextMetadataMismatch
    case discoveryMismatch
    case recommendationMetadataMismatch
    case recommendationOrderMismatch
    case duplicateStoreIdentity(UUID)
    case invalidStoreCoordinate(UUID)
    case missingStoreIdentity(String)
    case duplicateRecommendationIdentity(String)
    case invalidRecommendation(String)
    case recommendationProductMismatch(
        String,
        ProductStateProductID
    )
    case duplicateCoverage(UUID, ShoppingIntentGroup)
    case coverageOrderMismatch
    case invalidCoverage(UUID)
    case coverageRecommendationMismatch(UUID)
    case coverageEntryMismatch(ProductStateListEntryID)
    case coverageProductMismatch(ProductStateProductID)
    case conflictingExclusionReason(ProductStateListEntryID)
    case duplicateSavedLocation(UUID)
    case savedLocationScopeMismatch(UUID)
    case invalidSavedLocationCoordinate(UUID)
    case savedLocationLinkMismatch(UUID)
    case selectionScopeMismatch
    case selectionNotFound(ProductStateMapMarkerID)
    case recommendationsWithoutUsablePlan
}

struct ProductStateMapProjectionPresentation: Equatable {
    let listID: ProductStateListID
    let listRevision: ProductStateListRevision
    let markers: [ProductStateMapMarkerPresentation]
    let visibleMarkers: [ProductStateMapMarkerPresentation]
    let recommendations: [ProductStateMapRecommendationPresentation]
    let visibleRecommendations: [ProductStateMapRecommendationPresentation]
    let savedLocations: [ProductStateMapSavedLocationPresentation]
    let unavailableSavedLocations: [ProductStateProjectionMetadata]
    let excludedProducts: [ProductStateMapExcludedProductPresentation]
    let unresolvedProducts: [ProductStateMapUnresolvedProductPresentation]
    let visibleUnresolvedProducts:
        [ProductStateMapUnresolvedProductPresentation]
    let selected: ProductStateMapSelectedPresentation?
    let filter: ProductStateMapProjectionFilter
    let searchText: String
    let metadata: ProductStateProjectionMetadata

    var clusteringInputIDs: [ProductStateMapMarkerID] {
        markers.map(\.id)
    }
}

enum ProductStateMapProjectionContent: Equatable {
    case idle
    case available(ProductStateMapProjectionPresentation)
    case stale(
        ProductStateMapProjectionPresentation,
        ProductStateMapStalenessPresentation
    )
    case unavailable(ProductStateMapUnavailablePresentation)
    case invalid(ProductStateMapProjectionInvalidReason)
}

struct ProductStateMapProjectionConsumerState: Equatable {
    let content: ProductStateMapProjectionContent

    static let idle = ProductStateMapProjectionConsumerState(
        content: .idle
    )
}

enum ProductStateMapProjectionConsumer {
    static func make(
        shopping: ShoppingWorkspaceProjectionConsumerState,
        mapContext: ProductStateProjectionOutcome<
            ProductStateMapShoppingContextProjection
        >,
        discovery: ProductStateProjectionOutcome<
            ProductStateDiscoveryContextProjection
        >,
        recommendations: ProductStateProjectionOutcome<
            ProductStateStoreRecommendationsProjection
        >,
        stores: [ProductStateMapStorePresentationInput],
        coverages: [ShoppingPlanStoreCoverage],
        savedLocations: [
            ProductStateProjectionOutcome<
                ProductStateSavedLocationEvidenceProjection
            >
        ],
        selection: ProductStateMapProjectionSelection = .none,
        filter: ProductStateMapProjectionFilter = .all,
        searchText: String = ""
    ) -> ProductStateMapProjectionConsumerState {
        let shoppingPresentation: ShoppingWorkspaceProjectionPresentation
        switch shopping.content {
        case .idle:
            return invalid(.shoppingConsumerInactive)
        case let .unavailable(metadata):
            return unavailable(metadata: metadata)
        case let .invalid(reason):
            return invalid(.shoppingConsumerInvalid(reason))
        case let .available(presentation):
            shoppingPresentation = presentation
        }

        guard shoppingPresentation.metadata.scope ==
            .list(shoppingPresentation.listID) else {
            return invalid(.listScopeMismatch)
        }
        guard shoppingPresentation.metadata.listRevision ==
            shoppingPresentation.listRevision else {
            return invalid(.listRevisionMismatch)
        }
        guard let plan = shopping.plan else {
            return invalid(.planScopeMismatch)
        }
        if plan.state.readiness == .invalidOrIncomplete {
            return invalid(.planInvalid(plan.state.invalidReasons))
        }

        let map: ProductStateMapShoppingContextProjection
        switch mapContext {
        case let .unavailable(metadata):
            return unavailable(
                metadata: metadata,
                listID: shoppingPresentation.listID,
                revision: shoppingPresentation.listRevision
            )
        case let .projection(value):
            map = value
        }
        let discoveryValue: ProductStateDiscoveryContextProjection
        switch discovery {
        case let .unavailable(metadata):
            return unavailable(
                metadata: metadata,
                listID: shoppingPresentation.listID,
                revision: shoppingPresentation.listRevision
            )
        case let .projection(value):
            discoveryValue = value
        }
        let recommendationValue: ProductStateStoreRecommendationsProjection
        switch recommendations {
        case let .unavailable(metadata):
            return unavailable(
                metadata: metadata,
                listID: shoppingPresentation.listID,
                revision: shoppingPresentation.listRevision
            )
        case let .projection(value):
            recommendationValue = value
        }

        if let invalidReason = validateScope(
            shopping: shoppingPresentation,
            plan: plan.state,
            map: map,
            discovery: discoveryValue,
            recommendations: recommendationValue
        ) {
            return invalid(invalidReason)
        }
        if let unavailableMetadata = firstUnavailableMetadata([
            shoppingPresentation.metadata,
            map.metadata,
            discoveryValue.metadata,
            recommendationValue.metadata
        ]) {
            return unavailable(
                metadata: unavailableMetadata,
                listID: shoppingPresentation.listID,
                revision: shoppingPresentation.listRevision,
                planReason: plan.state.unavailableReason
            )
        }
        if plan.state.readiness == .unavailable {
            return unavailable(
                metadata: recommendationValue.metadata,
                listID: shoppingPresentation.listID,
                revision: shoppingPresentation.listRevision,
                planReason: plan.state.unavailableReason
            )
        }
        if [.noUsablePlan, .generating].contains(plan.state.readiness),
           !recommendationValue.recommendations.isEmpty ||
            !coverages.isEmpty {
            return invalid(.recommendationsWithoutUsablePlan)
        }

        let allRows = shoppingPresentation.entries
        var rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ] = [:]
        for row in allRows {
            guard rowsByEntry[row.id] == nil else {
                return invalid(
                    .shoppingConsumerInvalid(
                        .duplicateEntryIdentity(row.id)
                    )
                )
            }
            rowsByEntry[row.id] = row
        }
        if let invalidReason = validateContext(
            map,
            discovery: discoveryValue,
            plan: plan.state,
            rowsByEntry: rowsByEntry
        ) {
            return invalid(invalidReason)
        }
        if let invalidReason = validateStores(stores) {
            return invalid(invalidReason)
        }
        if let invalidReason = validateRecommendations(
            recommendationValue,
            stores: stores,
            eligibleProductIDs: discoveryValue.eligibleProductIDs
        ) {
            return invalid(invalidReason)
        }
        if let invalidReason = validateCoverages(
            coverages,
            stores: stores,
            recommendations: recommendationValue.recommendations,
            plan: plan.state,
            rowsByEntry: rowsByEntry
        ) {
            return invalid(invalidReason)
        }

        let savedResult = makeSavedLocations(
            savedLocations,
            listID: shoppingPresentation.listID,
            rowsByEntry: rowsByEntry
        )
        if let invalidReason = savedResult.invalidReason {
            return invalid(invalidReason)
        }
        let saved = savedResult.values
        let excludedResult = makeExcluded(
            plan.state.explicitlyExcludedEntryIDs,
            coverages: coverages,
            rowsByEntry: rowsByEntry
        )
        if let invalidReason = excludedResult.invalidReason {
            return invalid(invalidReason)
        }
        let unresolved = makeUnresolved(
            shopping: shoppingPresentation,
            plan: plan.state,
            discovery: discoveryValue,
            savedLocations: saved
        )
        let recommendationPresentations = makeRecommendations(
            recommendationValue.recommendations,
            stores: stores,
            coverages: coverages
        )
        let markerResult = makeMarkers(
            shopping: shoppingPresentation,
            stores: stores,
            recommendations: recommendationPresentations,
            savedLocations: saved,
            rowsByEntry: rowsByEntry
        )
        if let invalidReason = markerResult.invalidReason {
            return invalid(invalidReason)
        }

        let normalizedSearch = normalized(searchText)
        let visibleMarkers = markerResult.values.filter {
            markerMatches(
                $0,
                filter: filter,
                normalizedSearch: normalizedSearch,
                stores: stores,
                recommendations: recommendationPresentations,
                savedLocations: saved,
                shopping: shoppingPresentation
            )
        }
        let visibleMarkerIDs = Set(visibleMarkers.map(\.id))
        let visibleRecommendations = recommendationPresentations.filter {
            recommendationMatches(
                $0,
                filter: filter,
                normalizedSearch: normalizedSearch,
                visibleMarkerIDs: visibleMarkerIDs,
                shopping: shoppingPresentation
            )
        }
        let visibleUnresolved = filter == .unresolved
            ? unresolved.filter {
                unresolvedMatches($0, normalizedSearch: normalizedSearch)
            }
            : []
        let selectedResult = makeSelection(
            selection,
            listID: shoppingPresentation.listID,
            revision: shoppingPresentation.listRevision,
            markers: markerResult.values,
            visibleIDs: visibleMarkerIDs
        )
        if let invalidReason = selectedResult.invalidReason {
            return invalid(invalidReason)
        }

        let presentation = ProductStateMapProjectionPresentation(
            listID: shoppingPresentation.listID,
            listRevision: shoppingPresentation.listRevision,
            markers: markerResult.values,
            visibleMarkers: visibleMarkers,
            recommendations: recommendationPresentations,
            visibleRecommendations: visibleRecommendations,
            savedLocations: saved,
            unavailableSavedLocations: savedResult.unavailable,
            excludedProducts: excludedResult.values,
            unresolvedProducts: unresolved,
            visibleUnresolvedProducts: visibleUnresolved,
            selected: selectedResult.value,
            filter: filter,
            searchText: searchText,
            metadata: recommendationValue.metadata
        )
        let staleness = makeStaleness(
            metadata: [
                shoppingPresentation.metadata,
                map.metadata,
                discoveryValue.metadata,
                recommendationValue.metadata
            ] + saved.map(\.metadata),
            plan: plan.state
        )
        if plan.state.readiness == .stale ||
            !staleness.projectionReasons.isEmpty ||
            !staleness.planReasons.isEmpty {
            return ProductStateMapProjectionConsumerState(
                content: .stale(presentation, staleness)
            )
        }
        return ProductStateMapProjectionConsumerState(
            content: .available(presentation)
        )
    }

    static func navigationIntent(
        for markerID: ProductStateMapMarkerID,
        in presentation: ProductStateMapProjectionPresentation
    ) -> ProductStateMapNavigationIntent? {
        guard let marker = presentation.markers.first(where: {
            $0.id == markerID
        }) else { return nil }
        switch marker.kind {
        case let .savedLocation(locationID):
            return .savedLocation(
                locationID,
                presentation.listID,
                presentation.listRevision
            )
        case let .store(storeID):
            return .store(
                storeID,
                presentation.listID,
                presentation.listRevision,
                marker.coordinate
            )
        case let .product(productID, storeID, savedLocationID):
            return .product(
                productID,
                presentation.listID,
                presentation.listRevision,
                storeID: storeID,
                savedLocationID: savedLocationID
            )
        }
    }

    private static func validateScope(
        shopping: ShoppingWorkspaceProjectionPresentation,
        plan: ProductHomePlanPresentation,
        map: ProductStateMapShoppingContextProjection,
        discovery: ProductStateDiscoveryContextProjection,
        recommendations: ProductStateStoreRecommendationsProjection
    ) -> ProductStateMapProjectionInvalidReason? {
        guard plan.sourceListID == nil ||
            plan.sourceListID == shopping.listID,
            plan.sourceRevision == nil ||
            plan.sourceRevision == shopping.listRevision else {
            return .planScopeMismatch
        }
        switch map.owner {
        case let .list(listID, revision):
            guard listID == shopping.listID,
                  revision == shopping.listRevision,
                  map.metadata.scope == .list(listID) else {
                return .contextMetadataMismatch
            }
        case let .plan(planID, listID, revision):
            guard listID == shopping.listID,
                  revision == shopping.listRevision,
                  map.metadata.scope == .plan(planID, listID) else {
                return .contextMetadataMismatch
            }
        case .session:
            return .sessionContextRequiresT19
        }
        if [.currentReady, .stale].contains(plan.readiness) {
            guard case .plan = map.owner else {
                return .planScopeMismatch
            }
        }
        guard map.metadata.listRevision == shopping.listRevision else {
            return .listRevisionMismatch
        }
        guard map.metadata.provenances.contains(.targetProductState) else {
            return .contextMetadataMismatch
        }
        guard discovery.owner == map.owner,
              discovery.metadata.scope == map.metadata.scope,
              discovery.metadata.listRevision ==
                shopping.listRevision else {
            return .discoveryMismatch
        }
        guard discovery.metadata.provenances
            .contains(.targetProductState) else {
            return .discoveryMismatch
        }
        guard recommendations.owner == map.owner,
              recommendations.metadata.scope == map.metadata.scope,
              recommendations.metadata.listRevision ==
                shopping.listRevision else {
            return .recommendationMetadataMismatch
        }
        guard recommendations.metadata.provenances
            .contains(.targetProductState),
              recommendations.metadata.provenances.contains(where: {
                  if case .publishedStoreEvidence = $0 { return true }
                  return false
              }) else {
            return .recommendationMetadataMismatch
        }
        return nil
    }

    private static func validateContext(
        _ map: ProductStateMapShoppingContextProjection,
        discovery: ProductStateDiscoveryContextProjection,
        plan: ProductHomePlanPresentation,
        rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ]
    ) -> ProductStateMapProjectionInvalidReason? {
        for item in map.items {
            if let entryID = item.entryID,
               let row = rowsByEntry[entryID] {
                guard item.productID == row.productID else {
                    return .coverageEntryMismatch(entryID)
                }
            } else if item.isQualified {
                return .contextMetadataMismatch
            }
            if item.sessionLineID != nil {
                return .sessionContextRequiresT19
            }
            if item.isQualified && item.productID == nil {
                return .contextMetadataMismatch
            }
        }
        let expectedEligible = Array(
            Set(map.items.compactMap {
                $0.isQualified ? $0.productID : nil
            })
        ).sorted { productLess($0, $1) }
        guard discovery.eligibleProductIDs == expectedEligible,
              discovery.unresolvedItems == map.items.filter({
                  !$0.isQualified || $0.productID == nil
              }) else {
            return .discoveryMismatch
        }
        if case .plan = map.owner {
            let exactEntryIDs = map.items.compactMap {
                $0.isQualified ? $0.entryID : nil
            }
            guard exactEntryIDs == plan.includedEntryIDs else {
                return .contextMetadataMismatch
            }
        }
        return nil
    }

    private static func validateStores(
        _ stores: [ProductStateMapStorePresentationInput]
    ) -> ProductStateMapProjectionInvalidReason? {
        var seen = Set<UUID>()
        for store in stores {
            guard seen.insert(store.id).inserted else {
                return .duplicateStoreIdentity(store.id)
            }
            guard valid(store.coordinate) else {
                return .invalidStoreCoordinate(store.id)
            }
        }
        return nil
    }

    private static func validateRecommendations(
        _ projection: ProductStateStoreRecommendationsProjection,
        stores: [ProductStateMapStorePresentationInput],
        eligibleProductIDs: [ProductStateProductID]
    ) -> ProductStateMapProjectionInvalidReason? {
        let sorted = projection.recommendations.sorted {
            recommendationLess($0, $1)
        }
        guard sorted == projection.recommendations else {
            return .recommendationOrderMismatch
        }
        let storeIDs = Set(stores.map { $0.id.uuidString })
        var seen = Set<String>()
        for recommendation in projection.recommendations {
            guard seen.insert(recommendation.storeID).inserted else {
                return .duplicateRecommendationIdentity(
                    recommendation.storeID
                )
            }
            guard storeIDs.contains(recommendation.storeID) else {
                return .missingStoreIdentity(recommendation.storeID)
            }
            guard recommendation.confidence.isFinite,
                  (0...1).contains(recommendation.confidence),
                  recommendation.estimatedCoveredProductIDs ==
                    Array(Set(
                        recommendation.estimatedCoveredProductIDs
                    )).sorted(by: { productLess($0, $1) }),
                  recommendation.uncoveredProductIDs ==
                    Array(Set(
                        recommendation.uncoveredProductIDs
                    )).sorted(by: { productLess($0, $1) }),
                  Set(recommendation.estimatedCoveredProductIDs)
                    .isDisjoint(with: Set(
                        recommendation.uncoveredProductIDs
                    )),
                  Set(
                    recommendation.estimatedCoveredProductIDs +
                        recommendation.uncoveredProductIDs
                  ) == Set(eligibleProductIDs) else {
                return .invalidRecommendation(recommendation.storeID)
            }
        }
        return nil
    }

    private static func validateCoverages(
        _ coverages: [ShoppingPlanStoreCoverage],
        stores: [ProductStateMapStorePresentationInput],
        recommendations: [ProductStateStoreRecommendationProjection],
        plan: ProductHomePlanPresentation,
        rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ]
    ) -> ProductStateMapProjectionInvalidReason? {
        guard coverageKeys(coverages) ==
            coverageKeys(coverages.sorted {
                coverageLess($0, $1)
            }) else {
            return .coverageOrderMismatch
        }
        let storeIDs = Set(stores.map(\.id))
        let recommendationIDs = Set(recommendations.map(\.storeID))
        let included = Set(plan.includedEntryIDs)
        let excluded = Set(plan.explicitlyExcludedEntryIDs)
        let unresolved = Set(plan.unresolvedEntryIDs)
        var seen = Set<String>()
        for coverage in coverages {
            let key = "\(coverage.store.id.uuidString)|\(coverage.group.rawValue)"
            guard seen.insert(key).inserted else {
                return .duplicateCoverage(
                    coverage.store.id,
                    coverage.group
                )
            }
            guard storeIDs.contains(coverage.store.id),
                  coverage.coverageScore.isFinite,
                  (0...1).contains(coverage.coverageScore),
                  coverage.ranking.score.isFinite,
                  coverage.ranking.confidence.isFinite,
                  (0...1).contains(coverage.ranking.confidence),
                  coverage.availabilityClaim == .estimatedOnly,
                  coverage.matchedEntryIDs.count ==
                    coverage.matchedProductIDs.count,
                  coverage.missingEntryIDs.count ==
                    coverage.missingProductIDs.count else {
                return .invalidCoverage(coverage.store.id)
            }
            guard recommendationIDs.contains(
                coverage.store.id.uuidString
            ) else {
                return .coverageRecommendationMismatch(coverage.store.id)
            }
            let entryProductPairs = Array(zip(
                coverage.matchedEntryIDs,
                coverage.matchedProductIDs
            )) + Array(zip(
                coverage.missingEntryIDs,
                coverage.missingProductIDs
            ))
            for (entryID, productID) in entryProductPairs {
                guard included.contains(entryID),
                      rowsByEntry[entryID]?.productID == productID else {
                    return .coverageEntryMismatch(entryID)
                }
            }
            for value in coverage.namedExclusions {
                guard excluded.contains(value.identity.id),
                      rowsByEntry[value.identity.id]?.productID ==
                        value.identity.productID else {
                    return .coverageEntryMismatch(value.identity.id)
                }
            }
            guard Set(coverage.classificationUnresolvedEntryIDs)
                .isSubset(of: unresolved) else {
                return .invalidCoverage(coverage.store.id)
            }
        }
        return nil
    }

    private static func makeSavedLocations(
        _ outcomes: [
            ProductStateProjectionOutcome<
                ProductStateSavedLocationEvidenceProjection
            >
        ],
        listID: ProductStateListID,
        rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ]
    ) -> (
        values: [ProductStateMapSavedLocationPresentation],
        unavailable: [ProductStateProjectionMetadata],
        invalidReason: ProductStateMapProjectionInvalidReason?
    ) {
        var values: [ProductStateMapSavedLocationPresentation] = []
        var unavailable: [ProductStateProjectionMetadata] = []
        var seen = Set<UUID>()
        for outcome in outcomes {
            switch outcome {
            case let .unavailable(metadata):
                guard case let .location(locationID) = metadata.scope else {
                    return ([], [], .contextMetadataMismatch)
                }
                guard seen.insert(locationID).inserted else {
                    return ([], [], .duplicateSavedLocation(locationID))
                }
                unavailable.append(metadata)
            case let .projection(value):
                guard seen.insert(value.locationID).inserted else {
                    return ([], [], .duplicateSavedLocation(value.locationID))
                }
                guard value.metadata.scope ==
                    .location(value.locationID) else {
                    return (
                        [],
                        [],
                        .savedLocationScopeMismatch(value.locationID)
                    )
                }
                if case .unavailable = value.metadata.freshness {
                    unavailable.append(value.metadata)
                    continue
                }
                let coordinateResult = savedCoordinate(value)
                if coordinateResult.invalid {
                    return (
                        [],
                        [],
                        .invalidSavedLocationCoordinate(value.locationID)
                    )
                }
                var links: [ProductStateMapSavedLocationLinkPresentation] = []
                for link in value.links {
                    let state: ProductStateMapSavedLocationLinkState
                    if link.isAuthoritativeProductStateLink {
                        guard link.authority == .exactTargetReference,
                              let productID = link.productID,
                              let linkedListID = link.listID,
                              let entryID = link.entryID else {
                            return (
                                [],
                                [],
                                .savedLocationLinkMismatch(value.locationID)
                            )
                        }
                        if linkedListID == listID {
                            guard rowsByEntry[entryID]?.productID ==
                                productID else {
                                return (
                                    [],
                                    [],
                                    .savedLocationLinkMismatch(
                                        value.locationID
                                    )
                                )
                            }
                            state = .exactCurrentList
                        } else {
                            state = .outsideCurrentList
                        }
                    } else {
                        state = .unproven
                    }
                    links.append(
                        ProductStateMapSavedLocationLinkPresentation(
                            productID: link.productID,
                            listID: link.listID,
                            entryID: link.entryID,
                            authority: link.authority,
                            state: state
                        )
                    )
                }
                values.append(
                    ProductStateMapSavedLocationPresentation(
                        id: value.locationID,
                        title: value.displayNameSnapshot,
                        note: value.noteSnapshot,
                        coordinate: coordinateResult.coordinate,
                        links: links,
                        issues: coordinateResult.issues,
                        metadata: value.metadata
                    )
                )
            }
        }
        values.sort { $0.id.uuidString < $1.id.uuidString }
        unavailable.sort { scopeKey($0.scope) < scopeKey($1.scope) }
        return (values, unavailable, nil)
    }

    private static func makeExcluded(
        _ entryIDs: [ProductStateListEntryID],
        coverages: [ShoppingPlanStoreCoverage],
        rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ]
    ) -> (
        values: [ProductStateMapExcludedProductPresentation],
        invalidReason: ProductStateMapProjectionInvalidReason?
    ) {
        var reasons: [
            ProductStateListEntryID: ProductStatePlanInputExclusionReason
        ] = [:]
        for coverage in coverages {
            for exclusion in coverage.namedExclusions {
                if let existing = reasons[exclusion.identity.id],
                   existing != exclusion.reason {
                    return (
                        [],
                        .conflictingExclusionReason(exclusion.identity.id)
                    )
                }
                reasons[exclusion.identity.id] = exclusion.reason
            }
        }
        var result: [ProductStateMapExcludedProductPresentation] = []
        for entryID in entryIDs {
            guard let row = rowsByEntry[entryID] else {
                return ([], .coverageEntryMismatch(entryID))
            }
            result.append(
                ProductStateMapExcludedProductPresentation(
                    entryID: entryID,
                    productID: row.productID,
                    displayNameSnapshot: row.displayName,
                    reason: reasons[entryID]
                )
            )
        }
        return (result, nil)
    }

    private static func makeUnresolved(
        shopping: ShoppingWorkspaceProjectionPresentation,
        plan: ProductHomePlanPresentation,
        discovery: ProductStateDiscoveryContextProjection,
        savedLocations: [ProductStateMapSavedLocationPresentation]
    ) -> [ProductStateMapUnresolvedProductPresentation] {
        var result: [ProductStateMapUnresolvedProductPresentation] = []
        for (index, row) in shopping.unresolvedEntries.enumerated() {
            result.append(
                ProductStateMapUnresolvedProductPresentation(
                    source: .shoppingEntry,
                    ordinal: index,
                    entryID: row.id,
                    productID: row.productID,
                    displayNameSnapshot: row.product?.displayName,
                    reason: nil
                )
            )
        }
        for (index, entryID) in plan.unresolvedEntryIDs.enumerated() {
            let row = shopping.entries.first { $0.id == entryID }
            result.append(
                ProductStateMapUnresolvedProductPresentation(
                    source: .planClassification,
                    ordinal: index,
                    entryID: entryID,
                    productID: row?.productID,
                    displayNameSnapshot: row?.product?.displayName,
                    reason: nil
                )
            )
        }
        for (index, item) in discovery.unresolvedItems.enumerated() {
            result.append(
                ProductStateMapUnresolvedProductPresentation(
                    source: .discoveryContext,
                    ordinal: index,
                    entryID: item.entryID,
                    productID: item.productID,
                    displayNameSnapshot: item.displayNameSnapshot,
                    reason: nil
                )
            )
        }
        for location in savedLocations {
            for (index, link) in location.links.enumerated()
                where link.state != .exactCurrentList {
                result.append(
                    ProductStateMapUnresolvedProductPresentation(
                        source: .savedLocation(location.id),
                        ordinal: index,
                        entryID: link.entryID,
                        productID: link.productID,
                        displayNameSnapshot: nil,
                        reason: nil
                    )
                )
            }
        }
        return result
    }

    private static func makeRecommendations(
        _ recommendations: [ProductStateStoreRecommendationProjection],
        stores: [ProductStateMapStorePresentationInput],
        coverages: [ShoppingPlanStoreCoverage]
    ) -> [ProductStateMapRecommendationPresentation] {
        let storesByID = Dictionary(
            uniqueKeysWithValues: stores.map { ($0.id.uuidString, $0) }
        )
        return recommendations.compactMap { recommendation in
            guard let store = storesByID[recommendation.storeID] else {
                return nil
            }
            return ProductStateMapRecommendationPresentation(
                id: store.id,
                publishedStoreID: recommendation.storeID,
                store: store,
                estimatedCoveredProductIDs:
                    recommendation.estimatedCoveredProductIDs,
                uncoveredProductIDs: recommendation.uncoveredProductIDs,
                confidence: recommendation.confidence,
                evidenceAt: recommendation.evidenceAt,
                coverageReasons: coverages.filter {
                    $0.store.id == store.id
                }.map { coveragePresentation($0) }
            )
        }
    }

    private static func makeMarkers(
        shopping: ShoppingWorkspaceProjectionPresentation,
        stores: [ProductStateMapStorePresentationInput],
        recommendations: [ProductStateMapRecommendationPresentation],
        savedLocations: [ProductStateMapSavedLocationPresentation],
        rowsByEntry: [
            ProductStateListEntryID: ShoppingWorkspaceProjectionRow
        ]
    ) -> (
        values: [ProductStateMapMarkerPresentation],
        invalidReason: ProductStateMapProjectionInvalidReason?
    ) {
        var markers: [ProductStateMapMarkerPresentation] = []
        for location in savedLocations {
            guard let coordinate = location.coordinate else { continue }
            markers.append(
                ProductStateMapMarkerPresentation(
                    id: .savedLocation(location.id),
                    kind: .savedLocation(location.id),
                    title: location.title,
                    coordinate: coordinate,
                    listID: shopping.listID,
                    listRevision: shopping.listRevision,
                    recommendationIndex: nil
                )
            )
            for link in location.links where
                link.state == .exactCurrentList {
                guard let productID = link.productID,
                      let entryID = link.entryID,
                      let row = rowsByEntry[entryID] else {
                    return (
                        [],
                        .savedLocationLinkMismatch(location.id)
                    )
                }
                markers.append(
                    ProductStateMapMarkerPresentation(
                        id: .productAtSavedLocation(
                            productID,
                            location.id,
                            entryID
                        ),
                        kind: .product(
                            productID,
                            storeID: nil,
                            savedLocationID: location.id
                        ),
                        title: row.displayName,
                        coordinate: coordinate,
                        listID: shopping.listID,
                        listRevision: shopping.listRevision,
                        recommendationIndex: nil
                    )
                )
            }
        }
        let recommendationIndex = Dictionary(
            uniqueKeysWithValues: recommendations.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let recommendationByStore = Dictionary(
            uniqueKeysWithValues: recommendations.map { ($0.id, $0) }
        )
        for store in stores.sorted(by: {
            storeLess($0, $1)
        }) {
            let index = recommendationIndex[store.id]
            markers.append(
                ProductStateMapMarkerPresentation(
                    id: .store(store.id),
                    kind: .store(store.id),
                    title: store.title,
                    coordinate: store.coordinate,
                    listID: shopping.listID,
                    listRevision: shopping.listRevision,
                    recommendationIndex: index
                )
            )
            guard let recommendation = recommendationByStore[store.id]
            else { continue }
            for productID in recommendation.estimatedCoveredProductIDs {
                guard let row = shopping.entries.first(where: {
                    $0.productID == productID
                }) else {
                    return (
                        [],
                        .recommendationProductMismatch(
                            recommendation.publishedStoreID,
                            productID
                        )
                    )
                }
                markers.append(
                    ProductStateMapMarkerPresentation(
                        id: .productAtStore(productID, store.id),
                        kind: .product(
                            productID,
                            storeID: store.id,
                            savedLocationID: nil
                        ),
                        title: row.displayName,
                        coordinate: store.coordinate,
                        listID: shopping.listID,
                        listRevision: shopping.listRevision,
                        recommendationIndex: index
                    )
                )
            }
        }
        guard Set(markers.map(\.id)).count == markers.count else {
            return ([], .contextMetadataMismatch)
        }
        return (markers, nil)
    }

    private static func makeSelection(
        _ selection: ProductStateMapProjectionSelection,
        listID: ProductStateListID,
        revision: ProductStateListRevision,
        markers: [ProductStateMapMarkerPresentation],
        visibleIDs: Set<ProductStateMapMarkerID>
    ) -> (
        value: ProductStateMapSelectedPresentation?,
        invalidReason: ProductStateMapProjectionInvalidReason?
    ) {
        switch selection {
        case .none:
            return (nil, nil)
        case let .marker(markerID, selectedListID, selectedRevision):
            guard selectedListID == listID,
                  selectedRevision == revision else {
                return (nil, .selectionScopeMismatch)
            }
            guard let marker = markers.first(where: {
                $0.id == markerID
            }) else {
                return (nil, .selectionNotFound(markerID))
            }
            return (
                ProductStateMapSelectedPresentation(
                    marker: marker,
                    isVisible: visibleIDs.contains(markerID)
                ),
                nil
            )
        }
    }

    private static func markerMatches(
        _ marker: ProductStateMapMarkerPresentation,
        filter: ProductStateMapProjectionFilter,
        normalizedSearch: String,
        stores: [ProductStateMapStorePresentationInput],
        recommendations: [ProductStateMapRecommendationPresentation],
        savedLocations: [ProductStateMapSavedLocationPresentation],
        shopping: ShoppingWorkspaceProjectionPresentation
    ) -> Bool {
        let textMatches: Bool
        if normalizedSearch.isEmpty {
            textMatches = true
        } else {
            switch marker.kind {
            case let .store(storeID):
                textMatches = normalized(marker.title)
                    .contains(normalizedSearch) ||
                    recommendationProductTextMatches(
                        storeID: storeID,
                        recommendations: recommendations,
                        shopping: shopping,
                        normalizedSearch: normalizedSearch
                    )
            case let .savedLocation(locationID):
                textMatches = normalized(marker.title)
                    .contains(normalizedSearch) ||
                    savedLocationProductTextMatches(
                        locationID: locationID,
                        savedLocations: savedLocations,
                        shopping: shopping,
                        normalizedSearch: normalizedSearch
                    )
            case .product:
                textMatches = normalized(marker.title)
                    .contains(normalizedSearch)
            }
        }
        guard textMatches else { return false }
        switch filter {
        case .all:
            return true
        case .openStores:
            guard case let .store(storeID) = marker.kind else {
                return false
            }
            return stores.first { $0.id == storeID }?.isOpen == true
        case .shoppingList:
            switch marker.kind {
            case .product:
                return true
            case let .store(storeID):
                return recommendations.contains {
                    $0.id == storeID && !$0.estimatedCoveredProductIDs.isEmpty
                }
            case let .savedLocation(locationID):
                return savedLocations.first {
                    $0.id == locationID
                }?.links.contains {
                    $0.state == .exactCurrentList
                } == true
            }
        case .stores:
            if case .store = marker.kind { return true }
            return false
        case .products:
            if case .product = marker.kind { return true }
            return false
        case .savedLocations:
            if case .savedLocation = marker.kind { return true }
            return false
        case .unresolved:
            return false
        case let .coveredProduct(expected):
            if case let .product(productID, _, _) = marker.kind {
                return productID == expected
            }
            return false
        }
    }

    private static func recommendationMatches(
        _ recommendation: ProductStateMapRecommendationPresentation,
        filter: ProductStateMapProjectionFilter,
        normalizedSearch: String,
        visibleMarkerIDs: Set<ProductStateMapMarkerID>,
        shopping: ShoppingWorkspaceProjectionPresentation
    ) -> Bool {
        let textMatches = normalizedSearch.isEmpty ||
            normalized(recommendation.store.title)
                .contains(normalizedSearch) ||
            recommendation.estimatedCoveredProductIDs.contains {
                productID in
                shopping.entries.contains {
                    $0.productID == productID &&
                        normalized($0.displayName)
                            .contains(normalizedSearch)
                }
            }
        guard textMatches else { return false }
        switch filter {
        case .savedLocations, .unresolved:
            return false
        case .openStores:
            return recommendation.store.isOpen == true
        case .products:
            return recommendation.estimatedCoveredProductIDs.contains {
                visibleMarkerIDs.contains(
                    .productAtStore($0, recommendation.id)
                )
            }
        case let .coveredProduct(productID):
            return recommendation.estimatedCoveredProductIDs
                .contains(productID)
        case .all, .shoppingList, .stores:
            return visibleMarkerIDs.contains(.store(recommendation.id)) ||
                filter == .shoppingList
        }
    }

    private static func recommendationProductTextMatches(
        storeID: UUID,
        recommendations: [ProductStateMapRecommendationPresentation],
        shopping: ShoppingWorkspaceProjectionPresentation,
        normalizedSearch: String
    ) -> Bool {
        guard let recommendation = recommendations.first(where: {
            $0.id == storeID
        }) else { return false }
        return recommendation.estimatedCoveredProductIDs.contains {
            productID in
            shopping.entries.contains {
                $0.productID == productID &&
                    normalized($0.displayName).contains(normalizedSearch)
            }
        }
    }

    private static func savedLocationProductTextMatches(
        locationID: UUID,
        savedLocations: [ProductStateMapSavedLocationPresentation],
        shopping: ShoppingWorkspaceProjectionPresentation,
        normalizedSearch: String
    ) -> Bool {
        guard let location = savedLocations.first(where: {
            $0.id == locationID
        }) else { return false }
        let productIDs = Set(location.links.compactMap {
            $0.state == .exactCurrentList ? $0.productID : nil
        })
        return shopping.entries.contains {
            productIDs.contains($0.productID) &&
                normalized($0.displayName).contains(normalizedSearch)
        }
    }

    private static func unresolvedMatches(
        _ value: ProductStateMapUnresolvedProductPresentation,
        normalizedSearch: String
    ) -> Bool {
        normalizedSearch.isEmpty ||
            normalized(value.displayNameSnapshot ?? "")
                .contains(normalizedSearch)
    }

    private static func makeStaleness(
        metadata: [ProductStateProjectionMetadata],
        plan: ProductHomePlanPresentation
    ) -> ProductStateMapStalenessPresentation {
        let projectionReasons = Array(Set(metadata.flatMap {
            if case let .stale(reasons) = $0.freshness {
                return reasons
            }
            return []
        })).sorted { $0.rawValue < $1.rawValue }
        let planReasons = Array(Set(plan.staleReasons)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ProductStateMapStalenessPresentation(
            projectionReasons: projectionReasons,
            planReasons: planReasons
        )
    }

    private static func firstUnavailableMetadata(
        _ values: [ProductStateProjectionMetadata]
    ) -> ProductStateProjectionMetadata? {
        values.first {
            if case .unavailable = $0.freshness { return true }
            return false
        }
    }

    private static func unavailable(
        metadata: ProductStateProjectionMetadata,
        listID: ProductStateListID? = nil,
        revision: ProductStateListRevision? = nil,
        planReason: ProductStateProjectionUnavailableReason? = nil
    ) -> ProductStateMapProjectionConsumerState {
        ProductStateMapProjectionConsumerState(
            content: .unavailable(
                ProductStateMapUnavailablePresentation(
                    listID: listID,
                    listRevision: revision,
                    metadata: metadata,
                    planReason: planReason
                )
            )
        )
    }

    private static func invalid(
        _ reason: ProductStateMapProjectionInvalidReason
    ) -> ProductStateMapProjectionConsumerState {
        ProductStateMapProjectionConsumerState(content: .invalid(reason))
    }

    private static func coveragePresentation(
        _ coverage: ShoppingPlanStoreCoverage
    ) -> ProductStateMapCoverageReasonPresentation {
        ProductStateMapCoverageReasonPresentation(
            group: coverage.group,
            matchedEntryIDs: coverage.matchedEntryIDs,
            matchedProductIDs: coverage.matchedProductIDs,
            missingEntryIDs: coverage.missingEntryIDs,
            missingProductIDs: coverage.missingProductIDs,
            coverageScore: coverage.coverageScore,
            distance: coverage.distance,
            rankingScore: coverage.ranking.score,
            rankingConfidence: coverage.ranking.confidence,
            rankingReasons: coverage.ranking.reasons,
            rankingSignals: coverage.ranking.signals,
            availabilityClaim: coverage.availabilityClaim,
            namedExclusionEntryIDs:
                coverage.namedExclusions.map(\.identity.id),
            classificationUnresolvedEntryIDs:
                coverage.classificationUnresolvedEntryIDs
        )
    }

    private static func savedCoordinate(
        _ value: ProductStateSavedLocationEvidenceProjection
    ) -> (
        coordinate: ShoppingCoordinate?,
        issues: [ProductStateMapSavedLocationIssue],
        invalid: Bool
    ) {
        switch (value.latitude, value.longitude) {
        case (nil, nil):
            return (nil, [.missingCoordinate], false)
        case let (.some(latitude), .some(longitude)):
            let coordinate = ShoppingCoordinate(
                latitude: latitude,
                longitude: longitude
            )
            return valid(coordinate)
                ? (coordinate, [], false) : (nil, [], true)
        case (.some, nil), (nil, .some):
            return (nil, [.incompleteCoordinate], false)
        }
    }

    private static func valid(_ coordinate: ShoppingCoordinate) -> Bool {
        coordinate.latitude.isFinite &&
            coordinate.longitude.isFinite &&
            (-90...90).contains(coordinate.latitude) &&
            (-180...180).contains(coordinate.longitude)
    }

    private static func productLess(
        _ lhs: ProductStateProductID,
        _ rhs: ProductStateProductID
    ) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    private static func recommendationLess(
        _ lhs: ProductStateStoreRecommendationProjection,
        _ rhs: ProductStateStoreRecommendationProjection
    ) -> Bool {
        if lhs.estimatedCoveredProductIDs.count !=
            rhs.estimatedCoveredProductIDs.count {
            return lhs.estimatedCoveredProductIDs.count >
                rhs.estimatedCoveredProductIDs.count
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.storeID != rhs.storeID {
            return lhs.storeID < rhs.storeID
        }
        if lhs.evidenceAt != rhs.evidenceAt {
            return lhs.evidenceAt < rhs.evidenceAt
        }
        return lhs.estimatedCoveredProductIDs.map {
            $0.rawValue.uuidString
        }.joined(separator: "|") <
            rhs.estimatedCoveredProductIDs.map {
                $0.rawValue.uuidString
            }.joined(separator: "|")
    }

    private static func storeLess(
        _ lhs: ProductStateMapStorePresentationInput,
        _ rhs: ProductStateMapStorePresentationInput
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func coverageLess(
        _ lhs: ShoppingPlanStoreCoverage,
        _ rhs: ShoppingPlanStoreCoverage
    ) -> Bool {
        if lhs.ranking.score != rhs.ranking.score {
            return lhs.ranking.score > rhs.ranking.score
        }
        let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
        let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.store.id != rhs.store.id {
            return lhs.store.id.uuidString < rhs.store.id.uuidString
        }
        if lhs.group != rhs.group {
            return lhs.group.rawValue < rhs.group.rawValue
        }
        return lhs.matchedEntryIDs.map {
            $0.rawValue.uuidString
        }.joined(separator: "|") <
            rhs.matchedEntryIDs.map {
                $0.rawValue.uuidString
            }.joined(separator: "|")
    }

    private static func coverageKeys(
        _ values: [ShoppingPlanStoreCoverage]
    ) -> [String] {
        values.map {
            [
                String($0.ranking.score),
                String($0.distance ?? .greatestFiniteMagnitude),
                $0.store.id.uuidString,
                $0.group.rawValue,
                $0.matchedEntryIDs.map {
                    $0.rawValue.uuidString
                }.joined(separator: "|")
            ].joined(separator: "|")
        }
    }

    private static func scopeKey(
        _ scope: ProductStateProjectionScope
    ) -> String {
        switch scope {
        case let .location(id): return "location|\(id.uuidString)"
        case let .list(id): return "list|\(id.rawValue.uuidString)"
        case let .plan(id, listID):
            return "plan|\(id.rawValue.uuidString)|\(listID.rawValue.uuidString)"
        default: return String(describing: scope)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RuntimeStore: Identifiable, Equatable {
    let id: UUID
    let locationID: UUID?
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let itemNames: [String]
    let completedItemNames: [String]
    let isOpen: Bool?
    let rating: Double?
    let storeCategories: [ShoppingStoreCategory]
    let queryEvidenceCategories: [ShoppingStoreCategory]
    let websiteURL: URL?
    let sourceType: DataSourceType

    static func == (lhs: RuntimeStore, rhs: RuntimeStore) -> Bool {
        lhs.id == rhs.id &&
            lhs.locationID == rhs.locationID &&
            lhs.title == rhs.title &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.radius == rhs.radius &&
            lhs.itemNames == rhs.itemNames &&
            lhs.completedItemNames == rhs.completedItemNames &&
            lhs.isOpen == rhs.isOpen &&
            lhs.rating == rhs.rating &&
            lhs.storeCategories == rhs.storeCategories &&
            lhs.queryEvidenceCategories == rhs.queryEvidenceCategories &&
            lhs.websiteURL == rhs.websiteURL &&
            lhs.sourceType == rhs.sourceType
    }

    var openItemCount: Int {
        itemNames.count
    }

    var isSavedLocation: Bool {
        locationID != nil
    }

    var matchingItemsLabel: String {
        guard !itemNames.isEmpty else {
            return "No active shopping items"
        }

        return itemNames.joined(separator: ", ")
    }

    var proximityRadius: CLLocationDistance {
        min(max(radius, 150), 250)
    }

    func materializedWithStableIdentity() -> RuntimeStore {
        guard locationID == nil else {
            return self
        }

        return RuntimeStore(
            id: StoreRuntimeIdentity.transientID(
                title: title,
                coordinate: coordinate,
                sourceType: sourceType
            ),
            locationID: nil,
            title: title,
            coordinate: coordinate,
            radius: radius,
            itemNames: itemNames,
            completedItemNames: completedItemNames,
            isOpen: isOpen,
            rating: rating,
            storeCategories: storeCategories,
            queryEvidenceCategories: queryEvidenceCategories,
            websiteURL: websiteURL,
            sourceType: sourceType
        )
    }
}

typealias MapStore = RuntimeStore

enum StoreRuntimeIdentity {
    static func transientID(
        title: String,
        coordinate: CLLocationCoordinate2D,
        sourceType: DataSourceType
    ) -> UUID {
        let latitudeBucket = Int((coordinate.latitude * 100_000).rounded())
        let longitudeBucket = Int((coordinate.longitude * 100_000).rounded())
        let normalizedTitle = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let identity = "\(sourceType.rawValue)|\(normalizedTitle)|\(latitudeBucket)|\(longitudeBucket)"
        let first = stableHash(identity, seed: 14_695_981_039_346_656_037)
        let second = stableHash(identity, seed: 10_995_116_282_110_995_483)
        let bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
            + withUnsafeBytes(of: second.bigEndian, Array.init)

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func stableHash(_ value: String, seed: UInt64) -> UInt64 {
        value.utf8.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
    }
}

struct MapProduct: Identifiable, Equatable {
    let id: UUID
    let storeID: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapProduct, rhs: MapProduct) -> Bool {
        lhs.id == rhs.id &&
            lhs.storeID == rhs.storeID &&
            lhs.name == rhs.name &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

enum MapCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case shoppingList = "List"

    var id: String {
        rawValue
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    var searchText = "" {
        didSet { mapInputDidChange(from: oldValue, to: searchText) }
    }
    var selectedCategory: MapCategory = .all {
        didSet { mapInputDidChange(from: oldValue, to: selectedCategory) }
    }
    var shoppingListOnly = false {
        didSet { mapInputDidChange(from: oldValue, to: shoppingListOnly) }
    }
    private(set) var stores: [MapStore] = [] {
        didSet { mapInputDidChange(from: oldValue, to: stores) }
    }
    private(set) var products: [MapProduct] = [] {
        didSet { mapInputDidChange(from: oldValue, to: products) }
    }
    var selectedStoreID: UUID? {
        didSet { valueDidChange(from: oldValue, to: selectedStoreID) }
    }
    var cameraTarget: MKCoordinateRegion? {
        didSet {
            guard !regionsEqual(oldValue, cameraTarget) else { return }
            registerObjectChange()
        }
    }
    private(set) var userCoordinate: CLLocationCoordinate2D? {
        didSet {
            guard !coordinatesEqual(oldValue, userCoordinate) else { return }
            filterCacheNeedsRefresh = true
            registerObjectChange()
        }
    }

    private let storeResolutionEngine: StoreResolutionEngine
    private let storeRankingService = StoreRankingService()
    private let intentMatcher = ShoppingIntentMatcher()
    private var savedStores: [MapStore] = []
    private var savedProducts: [MapProduct] = []
    private var activeShoppingItemNames: [String] = []
    private var activeShoppingItems: [ShoppingItem] = []
    private var activeSuggestionRequest: ShoppingStoreSuggestionRequest?
    private var isUsingSharedShoppingPlan = false
    private var lastAppliedShoppingPlanContentSignature: String?
    private var hasCenteredOnUser = false
    private var storeSearchTask: Task<Void, Never>?
    private var cachedFilteredStores: [MapStore] = []
    private var cachedFilteredProducts: [MapProduct] = []
    private var filterCacheNeedsRefresh = true
    private var publicationBatchDepth = 0
    private var batchHasObjectChange = false
    private var lastUserCoordinatePublication = Date.distantPast
    private let userCoordinateMovementThreshold: CLLocationDistance = 15
    private let userCoordinateMaximumInterval: TimeInterval = 10

    #if DEBUG
    private var applyShoppingPlanCount = 0
    #endif

    init() {
        self.storeResolutionEngine = .shared
    }

    init(storeSearchService: StoreSearchService) {
        if let mapKitSearchService = storeSearchService as? MapKitStoreSearchService {
            self.storeResolutionEngine = StoreResolutionEngine(searchService: mapKitSearchService)
        } else {
            self.storeResolutionEngine = .shared
        }
    }

    var selectedStore: MapStore? {
        guard let selectedStoreID else {
            return nil
        }

        return stores.first { $0.id == selectedStoreID }
    }

    var filteredStores: [MapStore] {
        refreshFilterCacheIfNeeded()
        return cachedFilteredStores
    }

    var filteredProducts: [MapProduct] {
        refreshFilterCacheIfNeeded()
        return cachedFilteredProducts
    }

    func update(locations: [GeoLocation], shoppingItems: [ShoppingItem] = []) {
        let previousStores = stores
        let visibleLocations = locations.filter(shouldIncludeLocationInResults)
        savedStores = StoreResolutionEngine.savedStores(from: visibleLocations)
        savedProducts = visibleLocations.flatMap(makeProducts)

        if isUsingSharedShoppingPlan {
            products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
            if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
                self.selectedStoreID = nil
            }
            return
        }

        activeShoppingItems = shoppingItems.filter { !$0.isCompleted }
        activeShoppingItemNames = activeShoppingItems.map(\.name)
        filterCacheNeedsRefresh = true
        rebuildDisplayStores()
        BetaDiagnosticsCenter.shared.recordStoreTransition(
            previous: previousStores,
            next: stores,
            reason: "Saved stores or shopping items changed"
        )
        publishMapDiagnostics()

        if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
            self.selectedStoreID = nil
        }
    }

    func selectStore(id: UUID) {
        selectedStoreID = id

        guard let store = stores.first(where: { $0.id == id }) else {
            return
        }

        cameraTarget = region(centeredOn: store.coordinate, latitudeDelta: 0.008, longitudeDelta: 0.008)
        publishMapDiagnostics()
    }

    func focusStore(id: UUID) {
        selectedStoreID = id

        guard let store = stores.first(where: { $0.locationID == id || $0.id == id }) else {
            return
        }

        cameraTarget = region(centeredOn: store.coordinate, latitudeDelta: 0.008, longitudeDelta: 0.008)
        publishMapDiagnostics(focusedStore: store.title)
    }

    func materializeAndFocusStore(
        id: UUID,
        locationID: UUID?,
        title: String,
        coordinate: CLLocationCoordinate2D,
        sourceType: DataSourceType,
        matchingItemNames: [String]
    ) {
        let previousStores = stores
        if let index = stores.firstIndex(where: { $0.id == id || $0.locationID == locationID }) {
            let existing = stores[index]
            if !matchingItemNames.isEmpty {
                stores[index] = MapStore(
                    id: existing.id,
                    locationID: existing.locationID,
                    title: existing.title,
                    coordinate: existing.coordinate,
                    radius: existing.radius,
                    itemNames: matchingItemNames,
                    completedItemNames: existing.completedItemNames,
                    isOpen: existing.isOpen,
                    rating: existing.rating,
                    storeCategories: existing.storeCategories,
                    queryEvidenceCategories: existing.queryEvidenceCategories,
                    websiteURL: existing.websiteURL,
                    sourceType: existing.sourceType
                )
                products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
            }
            selectStore(id: stores[index].id)
            BetaDiagnosticsCenter.shared.notificationBottomSheetOpened(store: stores[index].title)
            return
        }

        let transientStore = MapStore(
            id: id,
            locationID: locationID,
            title: title,
            coordinate: coordinate,
            radius: 180,
            itemNames: matchingItemNames,
            completedItemNames: [],
            isOpen: nil,
            rating: nil,
            storeCategories: [],
            queryEvidenceCategories: [],
            websiteURL: nil,
            sourceType: sourceType
        ).materializedWithStableIdentity()
        stores = storeResolutionEngine.deduplicated(stores + [transientStore])
        products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
        let selectedID = stores.first { store in
            store.id == transientStore.id ||
                (
                    store.title.localizedCaseInsensitiveCompare(transientStore.title) == .orderedSame &&
                    distance(from: store.coordinate, to: transientStore.coordinate) < 35
                )
        }?.id
        if let selectedID {
            selectStore(id: selectedID)
            BetaDiagnosticsCenter.shared.recordStoreTransition(
                previous: previousStores,
                next: stores,
                reason: "Notification materialized a transient store"
            )
            BetaDiagnosticsCenter.shared.notificationBottomSheetOpened(store: transientStore.title)
        } else {
            BetaDiagnosticsCenter.shared.recordError(
                category: .map,
                message: "Transient store selection failed",
                detail: transientStore.title
            )
        }
    }

    func followUser() {
        guard let userCoordinate else {
            return
        }

        cameraTarget = region(centeredOn: userCoordinate, latitudeDelta: 0.01, longitudeDelta: 0.01)
        publishMapDiagnostics()
    }

    func selectTripStore(from coverage: StoreCoverage) {
        let matchedItemNames = Set(coverage.matchedItems.map { $0.name.lowercased() })
        let targetStore = stores.first { store in
            store.id == coverage.store.id
        } ?? stores.first { store in
            store.title.localizedCaseInsensitiveCompare(coverage.store.title) == .orderedSame
        } ?? stores.first { store in
            store.itemNames.contains { matchedItemNames.contains($0.lowercased()) }
        }

        if let targetStore {
            selectStore(id: targetStore.id)
        }
    }

    func applyStoreSuggestion(_ request: ShoppingStoreSuggestionRequest) {
        applyStoreSuggestion(request, shoppingItems: [request.itemName])
    }

    func applyStoreSuggestion(_ request: ShoppingStoreSuggestionRequest, shoppingItems: [String]) {
        performPublicationBatch {
            isUsingSharedShoppingPlan = false
            lastAppliedShoppingPlanContentSignature = nil
            activeSuggestionRequest = request
            activeShoppingItemNames = shoppingItems.isEmpty ? [request.itemName] : shoppingItems
            activeShoppingItems = []
            filterCacheNeedsRefresh = true
            searchText = ""
            selectedCategory = .shoppingList
            shoppingListOnly = true
            rebuildDisplayStores()
            selectSuggestedStoreIfAvailable()
        }
    }

    func applyStoreSuggestion(_ request: ShoppingStoreSuggestionRequest, shoppingItems: [ShoppingItem]) {
        performPublicationBatch {
            isUsingSharedShoppingPlan = false
            lastAppliedShoppingPlanContentSignature = nil
            activeSuggestionRequest = request
            activeShoppingItems = shoppingItems.filter { !$0.isCompleted }
            activeShoppingItemNames = activeShoppingItems.map(\.name)
            if activeShoppingItemNames.isEmpty {
                activeShoppingItemNames = [request.itemName]
            }
            filterCacheNeedsRefresh = true
            searchText = ""
            selectedCategory = .shoppingList
            shoppingListOnly = true
            rebuildDisplayStores()
            selectSuggestedStoreIfAvailable()
        }
    }

    func applyShoppingPlan(_ plan: ShoppingPlan) {
        guard lastAppliedShoppingPlanContentSignature != plan.contentSignature else {
            return
        }

        let previousStores = stores
        performPublicationBatch {
            isUsingSharedShoppingPlan = true
            lastAppliedShoppingPlanContentSignature = plan.contentSignature
            storeSearchTask?.cancel()
            storeSearchTask = nil
            activeSuggestionRequest = plan.request
            activeShoppingItems = plan.items.filter { !$0.isCompleted }
            activeShoppingItemNames = activeShoppingItems.map(\.name)
            if activeShoppingItemNames.isEmpty {
                activeShoppingItemNames = [plan.request.itemName]
            }
            filterCacheNeedsRefresh = true
            searchText = ""
            selectedCategory = .shoppingList
            shoppingListOnly = true
            stores = displayStores(from: plan.stores)
            products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
            selectSuggestedStoreIfAvailable()
            focusPlanRegionIfPossible()
            registerObjectChange()
        }

        #if DEBUG
        applyShoppingPlanCount += 1
        print("[WayTask Map Performance] applyShoppingPlan=\(applyShoppingPlanCount) plan=\(plan.id.uuidString)")
        #endif

        BetaDiagnosticsCenter.shared.recordStoreTransition(
            previous: previousStores,
            next: stores,
            reason: "Ready ShoppingPlan applied to Map"
        )
        publishMapDiagnostics()
    }

    func setUserCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let now = Date()
        let movement = distance(from: userCoordinate, to: coordinate)
        let shouldPublish = userCoordinate == nil ||
            movement >= userCoordinateMovementThreshold ||
            now.timeIntervalSince(lastUserCoordinatePublication) >= userCoordinateMaximumInterval
        guard shouldPublish else {
            return
        }

        let shouldRefreshFallback = userCoordinate == nil || movement > 50
        lastUserCoordinatePublication = now
        performPublicationBatch {
            userCoordinate = coordinate

            if shouldRefreshFallback && isUsingSharedShoppingPlan {
                focusPlanRegionIfPossible()
            } else if shouldRefreshFallback && !isUsingSharedShoppingPlan {
                rebuildDisplayStores()
                selectSuggestedStoreIfAvailable()
            }

            if !hasCenteredOnUser {
                hasCenteredOnUser = true

                if isUsingSharedShoppingPlan {
                    focusPlanRegionIfPossible()
                } else if activeSuggestionRequest == nil {
                    followUser()
                }
            }
        }
        publishMapDiagnostics()
    }

    func distanceText(for store: MapStore) -> String {
        guard let userCoordinate else {
            return "Distance unavailable"
        }

        let distance = distance(from: userCoordinate, to: store.coordinate)

        if distance >= 1000 {
            return String(format: "%.1f km away", distance / 1000)
        }

        return "\(Int(distance)) m away"
    }

    func openInMaps(store: MapStore) {
        let location = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = store.title
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func selectSuggestedStoreIfAvailable() {
        guard let request = activeSuggestionRequest else {
            return
        }

        if let selectedStoreID,
           stores.contains(where: { $0.id == selectedStoreID && storeMatchesSuggestion($0, request: request) }) {
            return
        }

        if let firstSuggestedStore = stores.first(where: { storeMatchesSuggestion($0, request: request) }) {
            selectStore(id: firstSuggestedStore.id)
        }
    }

    private func focusPlanRegionIfPossible() {
        guard isUsingSharedShoppingPlan else {
            return
        }

        let relevantStores = stores.filter { !$0.itemNames.isEmpty }
        let planStores = relevantStores.isEmpty ? stores : relevantStores
        var coordinates = planStores.prefix(4).map(\.coordinate)

        if let userCoordinate {
            coordinates.append(userCoordinate)
        }

        guard !coordinates.isEmpty else {
            if userCoordinate != nil {
                followUser()
            }
            return
        }

        cameraTarget = region(containing: coordinates)
    }

    private func storeMatchesSuggestion(
        _ store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        groupedRequests cachedRequests: [ShoppingStoreSuggestionRequest]? = nil
    ) -> Bool {
        if !activeShoppingItems.isEmpty {
            let requests = cachedRequests ?? groupedRequests()
            return !store.itemNames.isEmpty && requests.contains { groupedRequest in
                storeRankingService.isRelevant(
                    store: store,
                    request: groupedRequest,
                    userCoordinate: userCoordinate
                )
            }
        }

        return storeRankingService.isRelevant(
            store: store,
            request: request,
            userCoordinate: userCoordinate
        )
    }

    private func shouldIncludeLocationInResults(_ location: GeoLocation) -> Bool {
        guard location.sourceType == .debugSeed else {
            return true
        }

        #if DEBUG
        return DebugSeedStoreService.isEnabled
        #else
        return false
        #endif
    }

    private func isNearbySavedStore(_ store: MapStore) -> Bool {
        guard store.isSavedLocation else {
            return false
        }

        guard let userCoordinate else {
            return true
        }

        return distance(from: userCoordinate, to: store.coordinate) <= 1500
    }

    private func rebuildDisplayStores() {
        performPublicationBatch {
            let nextStores = savedStores
            let nextProducts = savedProducts

            stores = displayStores(from: nextStores)
            products = nextProducts

            guard let userCoordinate else {
                storeSearchTask?.cancel()
                storeSearchTask = nil
                return
            }

            let intents = mapDiscoveryIntents()
            storeSearchTask?.cancel()
            storeSearchTask = Task { [weak self] in
                guard let self else {
                    return
                }

                let resolvedStores = await storeResolutionEngine.resolve(
                    savedStores: savedStores,
                    intents: intents,
                    around: userCoordinate
                )

                guard !Task.isCancelled else {
                    return
                }

                applyDiscoveredStores(resolvedStores)
            }
        }
    }

    private func applyDiscoveredStores(_ discoveredStores: [MapStore]) {
        let previousStores = stores
        let eligibleStores = discoveredStores
            .map(retagStoreForActiveIntentGroups)
            .filter { store in
            guard let activeSuggestionRequest else {
                return true
            }

            return storeMatchesSuggestion(store, request: activeSuggestionRequest)
        }
        performPublicationBatch {
            let mergedStores = displayStores(from: eligibleStores)
            stores = mergedStores
            products = savedProducts + eligibleStores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
            selectSuggestedStoreIfAvailable()
        }
        BetaDiagnosticsCenter.shared.recordStoreTransition(
            previous: previousStores,
            next: stores,
            reason: "Shared store discovery completed"
        )
        publishMapDiagnostics()
    }

    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        guard BetaDiagnosticsCenter.shared.isEnabled else { return }
        BetaDiagnosticsCenter.shared.updateMap(
            userCoordinate: userCoordinate,
            region: region,
            focusedStore: nil,
            selectedStore: selectedStore?.title,
            stores: filteredStores
        )
    }

    private func publishMapDiagnostics(focusedStore: String? = nil) {
        guard BetaDiagnosticsCenter.shared.isEnabled else { return }
        BetaDiagnosticsCenter.shared.updateMap(
            userCoordinate: userCoordinate,
            region: cameraTarget,
            focusedStore: focusedStore,
            selectedStore: selectedStore?.title,
            stores: filteredStores
        )
    }

    private func displayStores(from stores: [MapStore]) -> [MapStore] {
        let deduplicatedStores = storeResolutionEngine.deduplicated(stores)
            .map(retagStoreForActiveIntentGroups)

        guard let activeSuggestionRequest else {
            return deduplicatedStores
        }

        if !activeShoppingItems.isEmpty {
            let requests = groupedRequests()
            return deduplicatedStores
                .filter { store in
                    !store.itemNames.isEmpty && requests.contains { request in
                        storeRankingService.isRelevant(
                            store: store,
                            request: request,
                            userCoordinate: userCoordinate
                        )
                    }
                }
                .sorted { lhs, rhs in
                    let lhsScore = bestGroupedScore(for: lhs, requests: requests)
                    let rhsScore = bestGroupedScore(for: rhs, requests: requests)
                    if lhsScore == rhsScore {
                        return distanceForSort(to: lhs.coordinate) < distanceForSort(to: rhs.coordinate)
                    }

                    return lhsScore > rhsScore
                }
        }

        return storeRankingService.rankedStores(
            deduplicatedStores,
            request: activeSuggestionRequest,
            userCoordinate: userCoordinate
        )
        .map(\.store)
    }

    private func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return region(centeredOn: userCoordinate ?? CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818), latitudeDelta: 0.01, longitudeDelta: 0.01)
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.8, 0.01)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.8, 0.01)
        return region(centeredOn: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }

    private func groupedRequests() -> [ShoppingStoreSuggestionRequest] {
        intentMatcher.groupedIntents(for: activeShoppingItems).map(\.request)
    }

    private func mapDiscoveryIntents() -> [StoreResolutionIntent] {
        let intents = storeResolutionEngine.intents(
            for: activeShoppingItems,
            fallback: activeSuggestionRequest
        )
        if !intents.isEmpty {
            return intents
        }

        guard activeShoppingItems.isEmpty else {
            return []
        }

        return [StoreResolutionIntent(
            itemNames: [],
            storeCategories: [.grocery, .supermarket, .convenienceStore, .pharmacy, .petStore, .electronicsStore, .homeImprovement]
        )]
    }

    private func bestGroupedScore(for store: MapStore, requests: [ShoppingStoreSuggestionRequest]) -> Double {
        requests.map { request in
            storeRankingService.score(
                store: store,
                request: request,
                userCoordinate: userCoordinate,
                coverage: StoreRealityCoverage(
                    matchedItemCount: store.itemNames.count,
                    totalItemCount: max(store.itemNames.count, 1)
                )
            ).score
        }
        .max() ?? 0
    }

    private func retagStoreForActiveIntentGroups(_ store: MapStore) -> MapStore {
        guard !activeShoppingItems.isEmpty else {
            return store
        }

        let relevantItems = intentMatcher.relevantItems(from: activeShoppingItems, for: store)
        return MapStore(
            id: store.id,
            locationID: store.locationID,
            title: store.title,
            coordinate: store.coordinate,
            radius: store.radius,
            itemNames: relevantItems.map(\.name).deduplicatedCaseInsensitive(),
            completedItemNames: store.completedItemNames,
            isOpen: store.isOpen,
            rating: store.rating,
            storeCategories: store.storeCategories,
            queryEvidenceCategories: store.queryEvidenceCategories,
            websiteURL: store.websiteURL,
            sourceType: store.sourceType
        )
    }

    private func distanceForSort(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let userCoordinate else {
            return .greatestFiniteMagnitude
        }

        return distance(from: userCoordinate, to: coordinate)
    }

    private func makeProducts(from location: GeoLocation) -> [MapProduct] {
        let baseCoordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let activeItems = location.shoppingItems.filter { !$0.isCompleted }

        return activeItems.enumerated().map { index, item in
            MapProduct(
                id: item.id,
                storeID: location.id,
                name: item.name,
                coordinate: productCoordinate(around: baseCoordinate, index: index)
            )
        }
    }

    private func makeProducts(from store: MapStore) -> [MapProduct] {
        store.itemNames.enumerated().map { index, itemName in
            MapProduct(
                id: StoreRuntimeIdentity.transientID(
                    title: "\(store.title)|\(itemName)|\(index)",
                    coordinate: store.coordinate,
                    sourceType: store.sourceType
                ),
                storeID: store.id,
                name: itemName,
                coordinate: productCoordinate(around: store.coordinate, index: index)
            )
        }
    }

    private func productCoordinate(around coordinate: CLLocationCoordinate2D, index: Int) -> CLLocationCoordinate2D {
        let angle = Double(index) * .pi / 3
        let offset = 0.00055

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + cos(angle) * offset,
            longitude: coordinate.longitude + sin(angle) * offset
        )
    }

    private func matchesSearch(_ store: MapStore) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return true
        }

        return store.title.localizedCaseInsensitiveContains(query)
            || store.itemNames.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilters(
        _ store: MapStore,
        groupedRequests cachedRequests: [ShoppingStoreSuggestionRequest]
    ) -> Bool {
        if let activeSuggestionRequest {
            guard storeMatchesSuggestion(
                store,
                request: activeSuggestionRequest,
                groupedRequests: cachedRequests
            ) else {
                return false
            }
        }

        if shoppingListOnly && store.openItemCount == 0 {
            if isNearbySavedStore(store) {
                return true
            }

            guard let activeSuggestionRequest,
                  storeMatchesSuggestion(
                      store,
                      request: activeSuggestionRequest,
                      groupedRequests: cachedRequests
                  ) else {
                return false
            }
        }

        switch selectedCategory {
        case .all:
            return true
        case .open:
            return store.isOpen ?? true
        case .shoppingList:
            if store.openItemCount > 0 {
                return true
            }

            if isNearbySavedStore(store) {
                return true
            }

            guard let activeSuggestionRequest else {
                return false
            }

            return storeMatchesSuggestion(
                store,
                request: activeSuggestionRequest,
                groupedRequests: cachedRequests
            )
        }
    }

    private func refreshFilterCacheIfNeeded() {
        guard filterCacheNeedsRefresh else {
            return
        }

        let requests = activeShoppingItems.isEmpty ? [] : groupedRequests()
        let visibleStores = stores.filter { store in
            matchesSearch(store) && matchesFilters(store, groupedRequests: requests)
        }
        let visibleStoreIDs = Set(visibleStores.map(\.id))
        let visibleItemNamesByStoreID = Dictionary(
            uniqueKeysWithValues: visibleStores.map { store in
                (store.id, Set(store.itemNames.map { $0.lowercased() }))
            }
        )
        let visibleProducts = products.filter { product in
            guard visibleStoreIDs.contains(product.storeID) else {
                return false
            }

            guard !activeShoppingItems.isEmpty,
                  let visibleItemNames = visibleItemNamesByStoreID[product.storeID] else {
                return true
            }

            return visibleItemNames.contains(product.name.lowercased())
        }

        cachedFilteredStores = visibleStores
        cachedFilteredProducts = visibleProducts
        filterCacheNeedsRefresh = false
    }

    private func mapInputDidChange<Value: Equatable>(from oldValue: Value, to newValue: Value) {
        guard oldValue != newValue else {
            return
        }

        filterCacheNeedsRefresh = true
        registerObjectChange()
    }

    private func valueDidChange<Value: Equatable>(from oldValue: Value, to newValue: Value) {
        guard oldValue != newValue else {
            return
        }

        registerObjectChange()
    }

    private func registerObjectChange() {
        if publicationBatchDepth > 0 {
            batchHasObjectChange = true
            return
        }

        refreshFilterCacheIfNeeded()
        objectWillChange.send()
    }

    private func performPublicationBatch(_ updates: () -> Void) {
        publicationBatchDepth += 1
        updates()
        publicationBatchDepth -= 1

        guard publicationBatchDepth == 0 else {
            return
        }

        refreshFilterCacheIfNeeded()
        if batchHasObjectChange {
            batchHasObjectChange = false
            objectWillChange.send()
        }
    }

    private func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        default:
            return false
        }
    }

    private func regionsEqual(_ lhs: MKCoordinateRegion?, _ rhs: MKCoordinateRegion?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.center.latitude == rhs.center.latitude &&
                lhs.center.longitude == rhs.center.longitude &&
                lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
                lhs.span.longitudeDelta == rhs.span.longitudeDelta
        default:
            return false
        }
    }

    private func region(centeredOn coordinate: CLLocationCoordinate2D, latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func distance(from start: CLLocationCoordinate2D?, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let start else {
            return .greatestFiniteMagnitude
        }

        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLocation.distance(from: endLocation)
    }
}
