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
    let entryID: UUID?
    let productID: UUID?
    let quantity: Double?
    let unitRawValue: String?

    init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        productHints: [String] = [],
        entryID: UUID? = nil,
        productID: UUID? = nil,
        quantity: Double? = nil,
        unitRawValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.productHints = productHints
        self.entryID = entryID
        self.productID = productID
        self.quantity = quantity
        self.unitRawValue = unitRawValue
    }
}

enum ShoppingContextAuthority: String, Codable, Equatable, Sendable {
    case legacyCompatibility
    case exactPlanInput
}

struct ShoppingContextAccountedEntry:
    Codable, Equatable, Sendable {
    let entryID: UUID
    let productID: UUID
    let reason: String
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
    let authority: ShoppingContextAuthority
    let sourceListID: UUID?
    let sourceListRevision: UInt64?
    let inputFingerprint: String?
    let currentLocation: ShoppingCoordinate?
    let activeShoppingListItems: [ShoppingContextItem]
    let nearbyStores: [ShoppingContextStore]
    let selectedInterests: [String]
    let timeOfDay: Date?
    let dayOfWeek: Int?
    let recentSearches: [String]
    let favoriteStores: [ShoppingContextStore]
    let availableProductHints: [String]
    let explicitExclusions: [ShoppingContextAccountedEntry]
    let unresolvedEntries: [ShoppingContextAccountedEntry]

    init(
        authority: ShoppingContextAuthority = .legacyCompatibility,
        sourceListID: UUID? = nil,
        sourceListRevision: UInt64? = nil,
        inputFingerprint: String? = nil,
        currentLocation: ShoppingCoordinate? = nil,
        activeShoppingListItems: [ShoppingContextItem] = [],
        nearbyStores: [ShoppingContextStore] = [],
        selectedInterests: [String] = [],
        timeOfDay: Date? = nil,
        dayOfWeek: Int? = nil,
        recentSearches: [String] = [],
        favoriteStores: [ShoppingContextStore] = [],
        availableProductHints: [String] = [],
        explicitExclusions: [ShoppingContextAccountedEntry] = [],
        unresolvedEntries: [ShoppingContextAccountedEntry] = []
    ) {
        self.authority = authority
        self.sourceListID = sourceListID
        self.sourceListRevision = sourceListRevision
        self.inputFingerprint = inputFingerprint
        self.currentLocation = currentLocation
        self.activeShoppingListItems = activeShoppingListItems
        self.nearbyStores = nearbyStores
        self.selectedInterests = selectedInterests
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.recentSearches = recentSearches
        self.favoriteStores = favoriteStores
        self.availableProductHints = availableProductHints
        self.explicitExclusions = explicitExclusions
        self.unresolvedEntries = unresolvedEntries
    }

    static func exactPlanInput(
        _ input: ShoppingPlanInputAuthority,
        nearbyStores: [ShoppingContextStore] = [],
        currentLocation: ShoppingCoordinate? = nil,
        observedAt: Date? = nil
    ) -> ShoppingContext {
        let items = input.items.map { item in
            ShoppingContextItem(
                id: item.identity.id.rawValue,
                name: item.displayName,
                productHints: [item.brand, item.category]
                    .compactMap { $0 }
                    .sorted(),
                entryID: item.identity.id.rawValue,
                productID: item.identity.productID.rawValue,
                quantity: item.quantity,
                unitRawValue: item.unitRawValue
            )
        }
        let explicit = input.explicitExclusions.map {
            ShoppingContextAccountedEntry(
                entryID: $0.identity.id.rawValue,
                productID: $0.identity.productID.rawValue,
                reason: $0.reason.rawValue
            )
        }
        let unresolved = input.unresolvedEntries.map {
            ShoppingContextAccountedEntry(
                entryID: $0.identity.id.rawValue,
                productID: $0.identity.productID.rawValue,
                reason: $0.reason.rawValue
            )
        }
        return ShoppingContext(
            authority: .exactPlanInput,
            sourceListID: input.projection.listID.rawValue,
            sourceListRevision: input.projection.revision.value,
            inputFingerprint: input.inputFingerprint,
            currentLocation: currentLocation,
            activeShoppingListItems: items,
            nearbyStores: nearbyStores.sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            timeOfDay: observedAt,
            explicitExclusions: explicit,
            unresolvedEntries: unresolved
        )
    }

    var hasActiveShoppingItems: Bool {
        if authority == .exactPlanInput {
            return !activeShoppingListItems.isEmpty
        }
        return activeShoppingListItems.contains { !$0.isCompleted }
    }

    var hasNearbyStores: Bool {
        !nearbyStores.isEmpty
    }

    var hasLocationSignal: Bool {
        currentLocation != nil
    }
}
