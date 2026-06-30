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
    let isOpen: Bool
    let rating: Double
    let websiteURL: URL?

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
    private var hasCenteredOnUser = false

    init() {
        self.storeSearchService = LocalStoreSearchService()
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
        savedStores = locations.map(makeStore)
        savedProducts = locations.flatMap(makeProducts)
        activeShoppingItemNames = locations
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

    func setUserCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let shouldRefreshFallback = userCoordinate == nil || distance(from: userCoordinate, to: coordinate) > 50
        userCoordinate = coordinate

        if shouldRefreshFallback {
            rebuildDisplayStores()
        }

        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            followUser()
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

    private func rebuildDisplayStores() {
        var nextStores = savedStores
        var nextProducts = savedProducts

        if let userCoordinate {
            let fallbackStores = storeSearchService.fallbackStores(
                around: userCoordinate,
                shoppingItems: activeShoppingItemNames
            )
            nextStores.append(contentsOf: fallbackStores)
            nextProducts.append(contentsOf: fallbackStores.flatMap(makeProducts))
        }

        stores = nextStores
        products = nextProducts
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
            websiteURL: nil
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
        if shoppingListOnly && store.openItemCount == 0 {
            return false
        }

        switch selectedCategory {
        case .all:
            return true
        case .open:
            return store.isOpen
        case .shoppingList:
            return store.openItemCount > 0
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
