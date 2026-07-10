import Combine
import CoreLocation
import Foundation
import MapKit

struct MapStore: Identifiable {
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

struct MapProduct: Identifiable {
    let id: UUID
    let storeID: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
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
    @Published var searchText = ""
    @Published var selectedCategory: MapCategory = .all
    @Published var shoppingListOnly = false
    @Published private(set) var stores: [MapStore] = []
    @Published private(set) var products: [MapProduct] = []
    @Published var selectedStoreID: UUID?
    @Published var cameraTarget: MKCoordinateRegion?
    @Published var userCoordinate: CLLocationCoordinate2D?

    private let storeSearchService: StoreSearchService
    private let storeRankingService = StoreRankingService()
    private let intentMatcher = ShoppingIntentMatcher()
    private var savedStores: [MapStore] = []
    private var savedProducts: [MapProduct] = []
    private var activeShoppingItemNames: [String] = []
    private var activeShoppingItems: [ShoppingItem] = []
    private var activeSuggestionRequest: ShoppingStoreSuggestionRequest?
    private var isUsingSharedShoppingPlan = false
    private var hasCenteredOnUser = false
    private var storeSearchTask: Task<Void, Never>?

    init() {
        self.storeSearchService = MapKitStoreSearchService()
    }

    init(storeSearchService: StoreSearchService) {
        self.storeSearchService = storeSearchService
    }

    var selectedStore: MapStore? {
        guard let selectedStoreID else {
            return nil
        }

        return stores.first { $0.id == selectedStoreID }
    }

    var filteredStores: [MapStore] {
        stores.filter { store in
            matchesSearch(store) && matchesFilters(store)
        }
    }

    var filteredProducts: [MapProduct] {
        let visibleStores = filteredStores
        let visibleStoreIDs = Set(visibleStores.map(\.id))
        let visibleItemNamesByStoreID = Dictionary(
            uniqueKeysWithValues: visibleStores.map { store in
                (store.id, Set(store.itemNames.map { $0.lowercased() }))
            }
        )

        return products.filter { product in
            guard visibleStoreIDs.contains(product.storeID) else {
                return false
            }

            guard !activeShoppingItems.isEmpty,
                  let visibleItemNames = visibleItemNamesByStoreID[product.storeID] else {
                return true
            }

            return visibleItemNames.contains(product.name.lowercased())
        }
    }

    func update(locations: [GeoLocation]) {
        let visibleLocations = locations.filter(shouldIncludeLocationInResults)
        savedStores = visibleLocations.map(makeStore)
        savedProducts = visibleLocations.flatMap(makeProducts)

        if isUsingSharedShoppingPlan {
            products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
            if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
                self.selectedStoreID = nil
            }
            return
        }

        activeShoppingItemNames = visibleLocations
            .flatMap(\.shoppingItems)
            .filter { !$0.isCompleted }
            .map(\.name)
        rebuildDisplayStores()

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
    }

    func focusStore(id: UUID) {
        selectedStoreID = id

        guard let store = stores.first(where: { $0.locationID == id || $0.id == id }) else {
            return
        }

        cameraTarget = region(centeredOn: store.coordinate, latitudeDelta: 0.008, longitudeDelta: 0.008)
    }

    func followUser() {
        guard let userCoordinate else {
            return
        }

        cameraTarget = region(centeredOn: userCoordinate, latitudeDelta: 0.01, longitudeDelta: 0.01)
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
        isUsingSharedShoppingPlan = false
        activeSuggestionRequest = request
        activeShoppingItemNames = shoppingItems.isEmpty ? [request.itemName] : shoppingItems
        activeShoppingItems = []
        searchText = ""
        selectedCategory = .shoppingList
        shoppingListOnly = true
        rebuildDisplayStores()
        selectSuggestedStoreIfAvailable()
    }

    func applyStoreSuggestion(_ request: ShoppingStoreSuggestionRequest, shoppingItems: [ShoppingItem]) {
        isUsingSharedShoppingPlan = false
        activeSuggestionRequest = request
        activeShoppingItems = shoppingItems.filter { !$0.isCompleted }
        activeShoppingItemNames = activeShoppingItems.map(\.name)
        if activeShoppingItemNames.isEmpty {
            activeShoppingItemNames = [request.itemName]
        }
        searchText = ""
        selectedCategory = .shoppingList
        shoppingListOnly = true
        rebuildDisplayStores()
        selectSuggestedStoreIfAvailable()
    }

    func applyShoppingPlan(_ plan: ShoppingPlan) {
        isUsingSharedShoppingPlan = true
        storeSearchTask?.cancel()
        storeSearchTask = nil
        activeSuggestionRequest = plan.request
        activeShoppingItems = plan.items.filter { !$0.isCompleted }
        activeShoppingItemNames = activeShoppingItems.map(\.name)
        if activeShoppingItemNames.isEmpty {
            activeShoppingItemNames = [plan.request.itemName]
        }
        searchText = ""
        selectedCategory = .shoppingList
        shoppingListOnly = true
        stores = displayStores(from: plan.stores)
        products = savedProducts + stores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
        selectSuggestedStoreIfAvailable()
        focusPlanRegionIfPossible()
    }

    func setUserCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let shouldRefreshFallback = userCoordinate == nil || distance(from: userCoordinate, to: coordinate) > 50
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

    private func storeMatchesSuggestion(_ store: MapStore, request: ShoppingStoreSuggestionRequest) -> Bool {
        if !activeShoppingItems.isEmpty {
            return !store.itemNames.isEmpty && groupedRequests().contains { groupedRequest in
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
        let nextStores = savedStores
        let nextProducts = savedProducts

        stores = displayStores(from: nextStores)
        products = nextProducts

        guard let userCoordinate else {
            storeSearchTask?.cancel()
            storeSearchTask = nil
            return
        }

        let groups = intentMatcher.groupedIntents(for: activeShoppingItems)
        let discoveryRequests = groupedStoreDiscoveryRequests()
        ShoppingDiscoveryDebugLogger.logStoreSearchRequests(
            context: "Map suggested discovery",
            groups: groups,
            requests: discoveryRequests
        )
        storeSearchTask?.cancel()
        storeSearchTask = Task { [weak self] in
            guard let self else {
                return
            }

            let discoveredStores = await discoveredStoresByGroup(
                around: userCoordinate,
                discoveryRequests: discoveryRequests
            )

            guard !Task.isCancelled else {
                return
            }

            applyDiscoveredStores(discoveredStores)
        }
    }

    private func applyDiscoveredStores(_ discoveredStores: [MapStore]) {
        let appleMapStores = discoveredStores.filter { $0.sourceType == .appleMaps }
        let filteredDiscoveredStores = discoveredStores.filter { store in
            store.sourceType != .local || !hasAppleMapsMatch(for: store, in: appleMapStores)
        }
        let eligibleStores = (savedStores + filteredDiscoveredStores)
            .map(retagStoreForActiveIntentGroups)
            .filter { store in
            guard let activeSuggestionRequest else {
                return true
            }

            return storeMatchesSuggestion(store, request: activeSuggestionRequest)
        }
        let mergedStores = displayStores(from: eligibleStores)
        stores = mergedStores
        products = savedProducts + eligibleStores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
        selectSuggestedStoreIfAvailable()
    }

    private func displayStores(from stores: [MapStore]) -> [MapStore] {
        let deduplicatedStores = savedStorePrioritized(stores)
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

    private func groupedStoreDiscoveryRequests() -> [(request: ShoppingStoreSuggestionRequest, itemNames: [String])] {
        let groups = intentMatcher.groupedIntents(for: activeShoppingItems)
        if !groups.isEmpty {
            return groups.map { group in
                (request: group.request, itemNames: group.itemNames)
            }
        }

        guard let activeSuggestionRequest else {
            return []
        }

        let suggestionItems = activeShoppingItemNames.isEmpty
            ? [activeSuggestionRequest.itemName]
            : activeShoppingItemNames
        return [(request: activeSuggestionRequest, itemNames: suggestionItems)]
    }

    private func discoveredStoresByGroup(
        around coordinate: CLLocationCoordinate2D,
        discoveryRequests: [(request: ShoppingStoreSuggestionRequest, itemNames: [String])]
    ) async -> [MapStore] {
        var discoveredStores: [MapStore] = []

        for discoveryRequest in discoveryRequests {
            let groupStores = await storeSearchService.stores(
                around: coordinate,
                shoppingItems: discoveryRequest.itemNames,
                storeCategories: discoveryRequest.request.storeCategories
            )
            discoveredStores.append(contentsOf: groupStores)
        }

        return savedStorePrioritized(discoveredStores)
    }

    private func hasAppleMapsMatch(for store: MapStore, in appleMapStores: [MapStore]) -> Bool {
        appleMapStores.contains { appleStore in
            appleStore.storeCategories.contains { appleCategory in
                store.storeCategories.contains { storeCategory in
                    appleCategory.matches(storeCategory) || storeCategory.matches(appleCategory)
                }
            }
        }
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

    private func savedStorePrioritized(_ stores: [MapStore]) -> [MapStore] {
        stores.reduce(into: [MapStore]()) { result, store in
            let duplicatesExistingStore = result.contains { existingStore in
                existingStore.title.localizedCaseInsensitiveCompare(store.title) == .orderedSame
                    || distance(from: existingStore.coordinate, to: store.coordinate) < 25
            }

            if !duplicatesExistingStore {
                result.append(store)
            }
        }
    }

    private func makeStore(from location: GeoLocation) -> MapStore {
        let openItems = location.shoppingItems
            .filter { !$0.isCompleted }
            .map(\.name)
        let completedItems = location.shoppingItems
            .filter(\.isCompleted)
            .map(\.name)
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)

        return MapStore(
            id: location.id,
            locationID: location.id,
            title: location.title,
            coordinate: coordinate,
            radius: location.radius,
            itemNames: openItems,
            completedItemNames: completedItems,
            isOpen: true,
            rating: rating(for: location),
            storeCategories: location.storeCategory.map { [$0] } ?? [],
            queryEvidenceCategories: [],
            websiteURL: nil,
            sourceType: location.sourceType
        )
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
                id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", abs(store.id.hashValue + index)))") ?? UUID(),
                storeID: store.id,
                name: itemName,
                coordinate: productCoordinate(around: store.coordinate, index: index)
            )
        }
    }

    private func rating(for location: GeoLocation) -> Double {
        let itemCount = min(location.shoppingItems.count, 4)
        return 4.4 + (Double(itemCount) * 0.1)
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

    private func matchesFilters(_ store: MapStore) -> Bool {
        if let activeSuggestionRequest {
            guard storeMatchesSuggestion(store, request: activeSuggestionRequest) else {
                return false
            }
        }

        if shoppingListOnly && store.openItemCount == 0 {
            if isNearbySavedStore(store) {
                return true
            }

            guard let activeSuggestionRequest,
                  storeMatchesSuggestion(store, request: activeSuggestionRequest) else {
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

            return storeMatchesSuggestion(store, request: activeSuggestionRequest)
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
