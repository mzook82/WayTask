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
    private var savedStores: [MapStore] = []
    private var savedProducts: [MapProduct] = []
    private var activeShoppingItemNames: [String] = []
    private var activeSuggestionRequest: ShoppingStoreSuggestionRequest?
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
        let visibleStoreIDs = Set(filteredStores.map(\.id))

        return products.filter { product in
            visibleStoreIDs.contains(product.storeID)
        }
    }

    func update(locations: [GeoLocation]) {
        let visibleLocations = locations.filter(shouldIncludeLocationInResults)
        savedStores = visibleLocations.map(makeStore)
        savedProducts = visibleLocations.flatMap(makeProducts)
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
        activeSuggestionRequest = request
        activeShoppingItemNames = shoppingItems.isEmpty ? [request.itemName] : shoppingItems
        searchText = ""
        selectedCategory = .shoppingList
        shoppingListOnly = true
        rebuildDisplayStores()
        selectSuggestedStoreIfAvailable()
    }

    func setUserCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let shouldRefreshFallback = userCoordinate == nil || distance(from: userCoordinate, to: coordinate) > 50
        userCoordinate = coordinate

        if shouldRefreshFallback {
            rebuildDisplayStores()
            selectSuggestedStoreIfAvailable()
        }

        if !hasCenteredOnUser {
            hasCenteredOnUser = true

            if activeSuggestionRequest == nil {
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

        if let savedStore = stores.first(where: { store in
            store.isSavedLocation && storeMatchesSuggestion(store, request: request)
        }) {
            selectStore(id: savedStore.id)
            return
        }

        if let firstSuggestedStore = stores.first(where: { store in
            !store.isSavedLocation && storeMatchesSuggestion(store, request: request)
        }) ?? stores.first(where: { !$0.isSavedLocation }) {
            selectStore(id: firstSuggestedStore.id)
        }
    }

    private func storeMatchesSuggestion(_ store: MapStore, request: ShoppingStoreSuggestionRequest) -> Bool {
        let storeDistance: CLLocationDistance?
        if let userCoordinate {
            storeDistance = distance(from: userCoordinate, to: store.coordinate)
        } else {
            storeDistance = nil
        }
        guard ShoppingStoreCategoryFilter.isEligible(
            storeTitle: store.title,
            storeCategories: store.storeCategories,
            requestedCategories: request.storeCategories,
            distanceMeters: storeDistance
        ) else {
            return false
        }

        let matchesItem = store.itemNames.contains { itemName in
            itemName.localizedCaseInsensitiveContains(request.itemName) ||
            request.itemName.localizedCaseInsensitiveContains(itemName)
        }
        let matchesCategory = store.storeCategories.contains { storeCategory in
            request.storeCategories.contains { requestCategory in
                storeCategory.matches(requestCategory)
            }
        }
        let matchesTitle = request.storeCategories.contains { category in
            store.title.localizedCaseInsensitiveContains(category.sampleStoreName) ||
            store.title.localizedCaseInsensitiveContains(category.storeFormTitle)
        }
        let genericRequestCanUseSavedCategory = request.storeCategories.contains(.generalStore) && store.isSavedLocation && !store.storeCategories.isEmpty

        return matchesItem || matchesCategory || matchesTitle || genericRequestCanUseSavedCategory
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

        stores = savedStorePrioritized(nextStores)
        products = nextProducts

        guard let userCoordinate else {
            storeSearchTask?.cancel()
            storeSearchTask = nil
            return
        }

        let suggestionItems = activeSuggestionRequest.map { [$0.itemName] } ?? activeShoppingItemNames
        let storeCategories = activeSuggestionRequest?.storeCategories ?? []
        storeSearchTask?.cancel()
        storeSearchTask = Task { [weak self] in
            guard let self else {
                return
            }

            let discoveredStores = await storeSearchService.stores(
                around: userCoordinate,
                shoppingItems: suggestionItems,
                storeCategories: storeCategories
            )

            guard !Task.isCancelled else {
                return
            }

            applyDiscoveredStores(discoveredStores)
        }
    }

    private func applyDiscoveredStores(_ discoveredStores: [MapStore]) {
        let relevantSavedStoreExists = activeSuggestionRequest.map { request in
            savedStores.contains { storeMatchesSuggestion($0, request: request) }
        } ?? false
        let filteredDiscoveredStores = relevantSavedStoreExists
            ? discoveredStores.filter { $0.sourceType != .local }
            : discoveredStores
        let eligibleStores = (savedStores + filteredDiscoveredStores).filter { store in
            guard let activeSuggestionRequest else {
                return true
            }

            let storeDistance: CLLocationDistance?
            if let userCoordinate {
                storeDistance = distance(from: userCoordinate, to: store.coordinate)
            } else {
                storeDistance = nil
            }
            return ShoppingStoreCategoryFilter.isEligible(
                storeTitle: store.title,
                storeCategories: store.storeCategories,
                requestedCategories: activeSuggestionRequest.storeCategories,
                distanceMeters: storeDistance
            )
        }
        let mergedStores = savedStorePrioritized(eligibleStores)
        stores = mergedStores
        products = savedProducts + eligibleStores.filter { !$0.isSavedLocation }.flatMap(makeProducts)
        selectSuggestedStoreIfAvailable()
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
            let storeDistance: CLLocationDistance?
            if let userCoordinate {
                storeDistance = distance(from: userCoordinate, to: store.coordinate)
            } else {
                storeDistance = nil
            }
            guard ShoppingStoreCategoryFilter.isEligible(
                storeTitle: store.title,
                storeCategories: store.storeCategories,
                requestedCategories: activeSuggestionRequest.storeCategories,
                distanceMeters: storeDistance
            ) else {
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
