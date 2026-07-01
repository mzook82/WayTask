import CoreLocation
import Foundation

struct ShoppingCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ShoppingContextItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isCompleted: Bool
    let productHints: [String]

    init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        productHints: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.productHints = productHints
    }
}

struct ShoppingContextStore: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let coordinate: ShoppingCoordinate?
    let matchingItemNames: [String]
    let isFavorite: Bool
    let websiteURL: URL?

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: ShoppingCoordinate? = nil,
        matchingItemNames: [String] = [],
        isFavorite: Bool = false,
        websiteURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.matchingItemNames = matchingItemNames
        self.isFavorite = isFavorite
        self.websiteURL = websiteURL
    }
}

struct ShoppingContext: Codable, Equatable, Sendable {
    let currentLocation: ShoppingCoordinate?
    let activeShoppingListItems: [ShoppingContextItem]
    let nearbyStores: [ShoppingContextStore]
    let selectedInterests: [String]
    let timeOfDay: Date?
    let dayOfWeek: Int?
    let recentSearches: [String]
    let favoriteStores: [ShoppingContextStore]
    let availableProductHints: [String]

    init(
        currentLocation: ShoppingCoordinate? = nil,
        activeShoppingListItems: [ShoppingContextItem] = [],
        nearbyStores: [ShoppingContextStore] = [],
        selectedInterests: [String] = [],
        timeOfDay: Date? = nil,
        dayOfWeek: Int? = nil,
        recentSearches: [String] = [],
        favoriteStores: [ShoppingContextStore] = [],
        availableProductHints: [String] = []
    ) {
        self.currentLocation = currentLocation
        self.activeShoppingListItems = activeShoppingListItems
        self.nearbyStores = nearbyStores
        self.selectedInterests = selectedInterests
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.recentSearches = recentSearches
        self.favoriteStores = favoriteStores
        self.availableProductHints = availableProductHints
    }

    var hasActiveShoppingItems: Bool {
        activeShoppingListItems.contains { !$0.isCompleted }
    }

    var hasNearbyStores: Bool {
        !nearbyStores.isEmpty
    }

    var hasLocationSignal: Bool {
        currentLocation != nil
    }
}
