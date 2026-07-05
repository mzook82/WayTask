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
            let cachedStores = retagStores(cached.stores, shoppingItems: shoppingItems)
            auditFallbackUsed(
                false,
                reason: "MapKit cache hit",
                coordinate: coordinate,
                requestedCategories: storeCategories,
                storeCount: cachedStores.count
            )
            return cachedStores
        }

        let mapKitStores = await searchMapKitStores(
            around: coordinate,
            shoppingItems: [],
            storeCategories: storeCategories
        )
        let fallbackUsed = mapKitStores.isEmpty

        let stores = fallbackUsed
            ? fallbackStores(around: coordinate, shoppingItems: shoppingItems, storeCategories: storeCategories)
            : retagStores(mapKitStores, shoppingItems: shoppingItems)

        auditFallbackUsed(
            fallbackUsed,
            reason: fallbackUsed ? "MapKit returned zero usable stores" : "MapKit returned usable stores",
            coordinate: coordinate,
            requestedCategories: storeCategories,
            storeCount: stores.count
        )

        if !mapKitStores.isEmpty {
            cache[cacheKey] = CacheEntry(stores: mapKitStores, timestamp: Date())
        }
        return stores
    }

    func refreshedStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) async -> [MapStore] {
        let cacheKey = cacheKey(
            coordinate: coordinate,
            storeCategories: storeCategories
        )
        let mapKitStores = await searchMapKitStores(
            around: coordinate,
            shoppingItems: [],
            storeCategories: storeCategories
        )

        if !mapKitStores.isEmpty {
            cache[cacheKey] = CacheEntry(stores: mapKitStores, timestamp: Date())
            auditFallbackUsed(
                false,
                reason: "MapKit refresh returned usable stores",
                coordinate: coordinate,
                requestedCategories: storeCategories,
                storeCount: mapKitStores.count
            )
            return retagStores(mapKitStores, shoppingItems: shoppingItems)
        }

        cache.removeValue(forKey: cacheKey)
        let fallbackStores = fallbackStores(
            around: coordinate,
            shoppingItems: shoppingItems,
            storeCategories: storeCategories
        )
        auditFallbackUsed(
            true,
            reason: "MapKit refresh returned zero usable stores",
            coordinate: coordinate,
            requestedCategories: storeCategories,
            storeCount: fallbackStores.count
        )
        return fallbackStores
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
                        requestedCategories: categories,
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

        let nearbySearchResults = searchResults.filter { store in
            ShoppingStoreCategoryFilter.isWithinPracticalDistance(
                from: coordinate,
                to: store.coordinate,
                requestedCategories: categories
            )
        }
        auditDistanceFiltering(
            acceptedStores: nearbySearchResults,
            rejectedStores: searchResults.filter { store in
                !ShoppingStoreCategoryFilter.isWithinPracticalDistance(
                    from: coordinate,
                    to: store.coordinate,
                    requestedCategories: categories
                )
            },
            coordinate: coordinate,
            requestedCategories: categories
        )

        return deduplicated(nearbySearchResults, around: coordinate)
    }

    private func searchMapKit(
        query: String,
        coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        requestedCategories: [ShoppingStoreCategory],
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
            var acceptedStores: [MapStore] = []
            var rejectedStores: [(name: String, category: String, distance: CLLocationDistance, reason: String)] = []

            for item in response.mapItems {
                let evaluation = makeMapStore(
                    from: item,
                    shoppingItems: shoppingItems,
                    requestedCategories: requestedCategories,
                    inferredCategory: inferredCategory,
                    queryCoordinate: coordinate
                )

                if let store = evaluation.store {
                    acceptedStores.append(store)
                } else {
                    rejectedStores.append((
                        name: item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unnamed MapKit result",
                        category: item.pointOfInterestCategory?.rawValue ?? "unknown",
                        distance: distance(from: coordinate, to: item.location.coordinate),
                        reason: evaluation.rejectionReason ?? "unknown rejection"
                    ))
                }
            }
            auditMapKitSearch(
                query: query,
                inferredCategory: inferredCategory,
                requestedCategories: requestedCategories,
                rawCount: response.mapItems.count,
                acceptedStores: acceptedStores,
                rejectedStores: rejectedStores,
                coordinate: coordinate
            )
            return acceptedStores
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
        requestedCategories: [ShoppingStoreCategory],
        inferredCategory: ShoppingStoreCategory,
        queryCoordinate: CLLocationCoordinate2D
    ) -> (store: MapStore?, rejectionReason: String?) {
        guard let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return (nil, "missing title")
        }

        let mapKitCategory = category(from: item.pointOfInterestCategory)
        let storeCategory = mapKitCategory == .generalStore && inferredCategory != .generalStore
            ? inferredCategory
            : (mapKitCategory ?? inferredCategory)
        let storeCategories = [storeCategory]
        let storeDistance = distance(from: queryCoordinate, to: item.location.coordinate)
        let rejectionReason: String?
        if isGroceryMapKitSearch(inferredCategory: inferredCategory, requestedCategories: requestedCategories) {
            rejectionReason = ShoppingStoreCategoryFilter.mapKitGroceryRejectionReason(
                storeTitle: title,
                storeCategories: storeCategories,
                pointOfInterestCategory: item.pointOfInterestCategory?.rawValue,
                requestedCategories: requestedCategories,
                distanceMeters: storeDistance
            )
        } else if ShoppingStoreCategoryFilter.shouldExclude(
            storeTitle: title,
            storeCategories: storeCategories,
            pointOfInterestCategory: item.pointOfInterestCategory?.rawValue,
            for: requestedCategories
        ) {
            rejectionReason = "filtered by category"
        } else {
            rejectionReason = nil
        }

        if let rejectionReason {
            return (nil, rejectionReason)
        }

        return (MapStore(
            id: UUID(),
            locationID: nil,
            title: title,
            coordinate: item.location.coordinate,
            radius: 180,
            itemNames: shoppingItems,
            completedItemNames: [],
            isOpen: nil,
            rating: nil,
            storeCategories: storeCategories,
            websiteURL: item.url,
            sourceType: .appleMaps
        ), nil)
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

    private func isGroceryMapKitSearch(
        inferredCategory: ShoppingStoreCategory,
        requestedCategories: [ShoppingStoreCategory]
    ) -> Bool {
        inferredCategory == .grocery ||
            inferredCategory == .supermarket ||
            inferredCategory == .convenienceStore
    }

    private func category(from pointOfInterestCategory: MKPointOfInterestCategory?) -> ShoppingStoreCategory? {
        guard let pointOfInterestCategory else {
            return nil
        }

        let rawValue = pointOfInterestCategory.rawValue.lowercased()
        if rawValue.contains("bakery") {
            return .grocery
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

    private func auditFallbackUsed(
        _ fallbackUsed: Bool,
        reason: String,
        coordinate: CLLocationCoordinate2D,
        requestedCategories: [ShoppingStoreCategory],
        storeCount: Int
    ) {
        #if DEBUG
        let categoryText = requestedCategories.map(\.rawValue).joined(separator: ",")
        print("[WayTask Store Audit] fallbackUsed=\(fallbackUsed) reason=\(reason) count=\(storeCount) categories=\(categoryText) coordinate=\(coordinate.latitude),\(coordinate.longitude)")
        #endif
    }

    private func auditMapKitSearch(
        query: String,
        inferredCategory: ShoppingStoreCategory,
        requestedCategories: [ShoppingStoreCategory],
        rawCount: Int,
        acceptedStores: [MapStore],
        rejectedStores: [(name: String, category: String, distance: CLLocationDistance, reason: String)],
        coordinate: CLLocationCoordinate2D
    ) {
        #if DEBUG
        let categoryText = requestedCategories.map(\.rawValue).joined(separator: ",")
        print("[WayTask Store Audit] MapKit query=\"\(query)\" category=\(inferredCategory.rawValue) requested=\(categoryText) raw=\(rawCount) accepted=\(acceptedStores.count) rejected=\(rejectedStores.count)")
        for store in acceptedStores {
            let distanceMeters = Int(distance(from: coordinate, to: store.coordinate))
            let storeCategoryText = store.storeCategories.map(\.rawValue).joined(separator: ",")
            print("[WayTask Store Audit] accepted name=\"\(store.title)\" source=\(store.sourceType.rawValue) distance=\(distanceMeters)m category=\(storeCategoryText)")
        }
        for rejectedStore in rejectedStores {
            print("[WayTask Store Audit] rejected name=\"\(rejectedStore.name)\" source=\(DataSourceType.appleMaps.rawValue) distance=\(Int(rejectedStore.distance))m category=\(rejectedStore.category) reason=\"\(rejectedStore.reason)\"")
        }
        #endif
    }

    private func auditDistanceFiltering(
        acceptedStores: [MapStore],
        rejectedStores: [MapStore],
        coordinate: CLLocationCoordinate2D,
        requestedCategories: [ShoppingStoreCategory]
    ) {
        #if DEBUG
        guard !rejectedStores.isEmpty else {
            return
        }

        print("[WayTask Store Audit] practical-distance accepted=\(acceptedStores.count) rejected=\(rejectedStores.count)")
        for store in rejectedStores {
            let distanceMeters = Int(distance(from: coordinate, to: store.coordinate))
            let reason = ShoppingStoreCategoryFilter.rejectionReason(
                storeTitle: store.title,
                storeCategories: store.storeCategories,
                requestedCategories: requestedCategories,
                distanceMeters: CLLocationDistance(distanceMeters)
            ) ?? "outside practical distance"
            print("[WayTask Store Audit] rejected name=\"\(store.title)\" source=\(store.sourceType.rawValue) distance=\(distanceMeters)m category=\(store.storeCategories.map(\.rawValue).joined(separator: ",")) reason=\"\(reason)\"")
        }
        #endif
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
