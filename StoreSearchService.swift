import CoreLocation
import Foundation
import MapKit

protocol StoreSearchService {
    func stores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory]
    ) async -> [MapStore]

    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory]
    ) -> [MapStore]
}

struct LocalStoreSearchService: StoreSearchService {
    private let provider = LocalStoreDataProvider()

    func stores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) async -> [MapStore] {
        fallbackStores(
            around: coordinate,
            shoppingItems: shoppingItems,
            storeCategories: storeCategories
        )
    }

    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) -> [MapStore] {
        provider.localStores(
            around: coordinate,
            shoppingItems: shoppingItems,
            storeCategories: storeCategories
        )
    }
}

final class MapKitStoreSearchService: StoreSearchService {
    private struct CacheEntry {
        let stores: [MapStore]
        let timestamp: Date
    }

    private let fallbackProvider = LocalStoreSearchService()
    private let cacheDuration: TimeInterval
    private var cache: [String: CacheEntry] = [:]

    init(cacheDuration: TimeInterval = 120) {
        self.cacheDuration = cacheDuration
    }

    func stores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) async -> [MapStore] {
        let cacheKey = cacheKey(
            coordinate: coordinate,
            storeCategories: storeCategories
        )

        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return retagStores(cached.stores, shoppingItems: shoppingItems)
        }

        let mapKitStores = await searchMapKitStores(
            around: coordinate,
            shoppingItems: [],
            storeCategories: storeCategories
        )

        let stores = mapKitStores.isEmpty
            ? fallbackStores(around: coordinate, shoppingItems: shoppingItems, storeCategories: storeCategories)
            : retagStores(mapKitStores, shoppingItems: shoppingItems)

        if !mapKitStores.isEmpty {
            cache[cacheKey] = CacheEntry(stores: mapKitStores, timestamp: Date())
        }
        return stores
    }

    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) -> [MapStore] {
        fallbackProvider.fallbackStores(
            around: coordinate,
            shoppingItems: shoppingItems,
            storeCategories: storeCategories
        )
    }

    private func searchMapKitStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory]
    ) async -> [MapStore] {
        let categories = storeCategories.isEmpty ? defaultDiscoveryCategories : storeCategories
        let queries = categories.flatMap(searchQueries(for:)).deduplicatedCaseInsensitive()

        let searchResults = await withTaskGroup(of: [MapStore].self) { group in
            for query in queries {
                group.addTask {
                    await self.searchMapKit(
                        query: query,
                        coordinate: coordinate,
                        shoppingItems: shoppingItems,
                        inferredCategory: self.category(for: query)
                    )
                }
            }

            var combinedStores: [MapStore] = []
            for await stores in group {
                combinedStores.append(contentsOf: stores)
            }
            return combinedStores
        }

        return deduplicated(searchResults, around: coordinate)
    }

    private func searchMapKit(
        query: String,
        coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        inferredCategory: ShoppingStoreCategory
    ) async -> [MapStore] {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: region)
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                makeMapStore(
                    from: item,
                    shoppingItems: shoppingItems,
                    inferredCategory: inferredCategory
                )
            }
        } catch {
            #if DEBUG
            print("[WayTask Store Search] MapKit search failed for \(query): \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func makeMapStore(
        from item: MKMapItem,
        shoppingItems: [String],
        inferredCategory: ShoppingStoreCategory
    ) -> MapStore? {
        guard let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        return MapStore(
            id: UUID(),
            locationID: nil,
            title: title,
            coordinate: item.location.coordinate,
            radius: 180,
            itemNames: shoppingItems,
            completedItemNames: [],
            isOpen: nil,
            rating: nil,
            storeCategories: [category(from: item.pointOfInterestCategory) ?? inferredCategory],
            websiteURL: item.url,
            sourceType: .appleMaps
        )
    }

    private func retagStores(_ stores: [MapStore], shoppingItems: [String]) -> [MapStore] {
        stores.map { store in
            MapStore(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: store.radius,
                itemNames: shoppingItems,
                completedItemNames: store.completedItemNames,
                isOpen: store.isOpen,
                rating: store.rating,
                storeCategories: store.storeCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
        }
    }

    private func deduplicated(_ stores: [MapStore], around coordinate: CLLocationCoordinate2D) -> [MapStore] {
        stores
            .sorted { lhs, rhs in
                distance(from: coordinate, to: lhs.coordinate) < distance(from: coordinate, to: rhs.coordinate)
            }
            .reduce(into: [MapStore]()) { result, store in
                let isDuplicate = result.contains { existingStore in
                    existingStore.title.localizedCaseInsensitiveCompare(store.title) == .orderedSame ||
                    distance(from: existingStore.coordinate, to: store.coordinate) < 35
                }

                if !isDuplicate {
                    result.append(store)
                }
            }
            .prefixArray(12)
    }

    private var defaultDiscoveryCategories: [ShoppingStoreCategory] {
        [.grocery, .supermarket, .convenienceStore, .pharmacy, .petStore, .electronicsStore, .homeImprovement]
    }

    private func searchQueries(for category: ShoppingStoreCategory) -> [String] {
        switch category {
        case .grocery:
            return ["grocery store", "food market"]
        case .supermarket:
            return ["supermarket"]
        case .convenienceStore:
            return ["convenience store", "mini market"]
        case .coffeeShop:
            return ["coffee shop"]
        case .petStore:
            return ["pet store"]
        case .electronicsStore:
            return ["electronics store"]
        case .homeImprovement:
            return ["hardware store", "home improvement store"]
        case .pharmacy:
            return ["pharmacy"]
        case .generalStore:
            return ["store", "market"]
        }
    }

    private func category(for query: String) -> ShoppingStoreCategory {
        let lowercasedQuery = query.lowercased()

        if lowercasedQuery.contains("supermarket") {
            return .supermarket
        }

        if lowercasedQuery.contains("convenience") || lowercasedQuery.contains("mini market") {
            return .convenienceStore
        }

        if lowercasedQuery.contains("coffee") {
            return .coffeeShop
        }

        if lowercasedQuery.contains("pet") {
            return .petStore
        }

        if lowercasedQuery.contains("electronics") {
            return .electronicsStore
        }

        if lowercasedQuery.contains("hardware") || lowercasedQuery.contains("home improvement") {
            return .homeImprovement
        }

        if lowercasedQuery.contains("pharmacy") {
            return .pharmacy
        }

        if lowercasedQuery.contains("grocery") || lowercasedQuery.contains("food market") {
            return .grocery
        }

        return .generalStore
    }

    private func category(from pointOfInterestCategory: MKPointOfInterestCategory?) -> ShoppingStoreCategory? {
        guard let pointOfInterestCategory else {
            return nil
        }

        switch pointOfInterestCategory {
        case .foodMarket:
            return .grocery
        case .pharmacy:
            return .pharmacy
        case .cafe:
            return .coffeeShop
        case .store:
            return .generalStore
        default:
            return nil
        }
    }

    private func cacheKey(
        coordinate: CLLocationCoordinate2D,
        storeCategories: [ShoppingStoreCategory]
    ) -> String {
        let roundedLatitude = (coordinate.latitude * 200).rounded() / 200
        let roundedLongitude = (coordinate.longitude * 200).rounded() / 200
        let categoryKey = storeCategories.map(\.rawValue).sorted().joined(separator: ",")
        return "\(roundedLatitude),\(roundedLongitude)|\(categoryKey)"
    }

    private func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
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

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
