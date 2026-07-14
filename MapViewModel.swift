import Combine
import CoreLocation
import Foundation
import MapKit

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
