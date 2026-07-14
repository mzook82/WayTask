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

struct StoreResolutionIntent: Hashable {
    let itemNames: [String]
    let storeCategories: [ShoppingStoreCategory]

    init(itemNames: [String], storeCategories: [ShoppingStoreCategory]) {
        self.itemNames = itemNames.deduplicatedCaseInsensitive()
        self.storeCategories = storeCategories.deduplicated()
    }
}

@MainActor
final class StoreResolutionEngine {
    static let shared = StoreResolutionEngine()

    private struct CacheEntry {
        let stores: [MapStore]
        let timestamp: Date
    }

    private let searchService: MapKitStoreSearchService
    private let intentMatcher = ShoppingIntentMatcher()
    private let cacheDuration: TimeInterval
    private let minimumRefreshInterval: TimeInterval
    private var discoveryCache: [String: CacheEntry] = [:]
    private var inFlightSearches: [String: Task<[MapStore], Never>] = [:]
    private var lastSearchStartedAt: [String: Date] = [:]

    init(
        searchService: MapKitStoreSearchService,
        cacheDuration: TimeInterval = 120,
        minimumRefreshInterval: TimeInterval = 1.5
    ) {
        self.searchService = searchService
        self.cacheDuration = cacheDuration
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    convenience init(
        cacheDuration: TimeInterval = 120,
        minimumRefreshInterval: TimeInterval = 1.5
    ) {
        self.init(
            searchService: MapKitStoreSearchService(),
            cacheDuration: cacheDuration,
            minimumRefreshInterval: minimumRefreshInterval
        )
    }

    func intents(
        for items: [ShoppingItem],
        fallback request: ShoppingStoreSuggestionRequest? = nil
    ) -> [StoreResolutionIntent] {
        let groups = intentMatcher.groupedIntents(for: items.filter { !$0.isCompleted })
        if !groups.isEmpty {
            return groups.map { group in
                StoreResolutionIntent(
                    itemNames: group.itemNames,
                    storeCategories: group.request.storeCategories
                )
            }
        }

        guard let request else {
            return []
        }

        return [StoreResolutionIntent(
            itemNames: request.searchTerms.isEmpty ? [request.itemName] : request.searchTerms,
            storeCategories: request.storeCategories
        )]
    }

    func resolve(
        savedLocations: [GeoLocation],
        items: [ShoppingItem],
        around coordinate: CLLocationCoordinate2D?,
        fallback request: ShoppingStoreSuggestionRequest? = nil,
        forceRefresh: Bool = false
    ) async -> [MapStore] {
        await resolve(
            savedStores: Self.savedStores(from: savedLocations),
            intents: intents(for: items, fallback: request),
            around: coordinate,
            forceRefresh: forceRefresh
        )
    }

    func resolve(
        savedStores: [MapStore],
        intents: [StoreResolutionIntent],
        around coordinate: CLLocationCoordinate2D?,
        forceRefresh: Bool = false
    ) async -> [MapStore] {
        let startedAt = Date()
        let diagnosticID = BetaDiagnosticsCenter.shared.beginStoreDiscovery(
            savedCount: savedStores.count,
            coordinate: coordinate
        )
        let stableSavedStores = savedStores.map { $0.materializedWithStableIdentity() }
        guard let coordinate, !intents.isEmpty else {
            let stores = deduplicated(stableSavedStores)
            BetaDiagnosticsCenter.shared.finishStoreDiscovery(
                id: diagnosticID,
                stores: stores,
                savedCount: stableSavedStores.count,
                duration: Date().timeIntervalSince(startedAt)
            )
            return stores
        }

        let key = cacheKey(coordinate: coordinate, intents: intents)
        let discoveredStores = await discoveredStores(
            around: coordinate,
            intents: intents,
            key: key,
            diagnosticID: diagnosticID,
            forceRefresh: forceRefresh
        )
        let stores = deduplicated(stableSavedStores + discoveredStores)
        BetaDiagnosticsCenter.shared.finishStoreDiscovery(
            id: diagnosticID,
            stores: stores,
            savedCount: stableSavedStores.count,
            duration: Date().timeIntervalSince(startedAt)
        )
        return stores
    }

    func deduplicated(_ stores: [MapStore]) -> [MapStore] {
        var result: [MapStore] = []

        for candidate in stores.map({ $0.materializedWithStableIdentity() }) {
            guard let duplicateIndex = result.firstIndex(where: { existing in
                existing.id == candidate.id ||
                    (
                        existing.title.localizedCaseInsensitiveCompare(candidate.title) == .orderedSame &&
                        distance(from: existing.coordinate, to: candidate.coordinate) < 80
                    ) || distance(from: existing.coordinate, to: candidate.coordinate) < 35
            }) else {
                result.append(candidate)
                continue
            }

            result[duplicateIndex] = merged(result[duplicateIndex], candidate)
        }

        return result
    }

    static func savedStores(from locations: [GeoLocation]) -> [MapStore] {
        locations
            .filter(shouldIncludeSavedLocation)
            .map { location in
                MapStore(
                    id: location.id,
                    locationID: location.id,
                    title: location.title,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    radius: location.radius,
                    itemNames: location.shoppingItems.filter { !$0.isCompleted }.map(\.name),
                    completedItemNames: location.shoppingItems.filter(\.isCompleted).map(\.name),
                    isOpen: true,
                    rating: nil,
                    storeCategories: location.storeCategory.map { [$0] } ?? [],
                    queryEvidenceCategories: [],
                    websiteURL: nil,
                    sourceType: location.sourceType
                )
            }
    }

    private func discoveredStores(
        around coordinate: CLLocationCoordinate2D,
        intents: [StoreResolutionIntent],
        key: String,
        diagnosticID: UUID?,
        forceRefresh: Bool
    ) async -> [MapStore] {
        let now = Date()
        if let cached = discoveryCache[key],
           !forceRefresh || now.timeIntervalSince(cached.timestamp) < minimumRefreshInterval,
           now.timeIntervalSince(cached.timestamp) < cacheDuration {
            BetaDiagnosticsCenter.shared.storeCacheResult(id: diagnosticID, hit: true, reason: "Coordinate and shopping intent cache")
            return retag(cached.stores, intents: intents)
        }

        if let inFlight = inFlightSearches[key] {
            BetaDiagnosticsCenter.shared.storeCacheResult(id: diagnosticID, hit: true, reason: "Identical in-flight discovery reused")
            return retag(await inFlight.value, intents: intents)
        }

        if forceRefresh,
           let lastSearch = lastSearchStartedAt[key],
           now.timeIntervalSince(lastSearch) < minimumRefreshInterval,
           let cached = discoveryCache[key] {
            BetaDiagnosticsCenter.shared.storeCacheResult(id: diagnosticID, hit: true, reason: "Forced refresh throttled")
            return retag(cached.stores, intents: intents)
        }

        BetaDiagnosticsCenter.shared.storeCacheResult(id: diagnosticID, hit: false, reason: "No current coordinate and shopping intent entry")
        lastSearchStartedAt[key] = now
        let task = Task { [searchService] in
            await BetaDiagnosticsCenter.$discoveryContextID.withValue(diagnosticID) {
                var stores: [MapStore] = []
                for intent in intents {
                    let groupStores: [MapStore]
                    if forceRefresh {
                        groupStores = await searchService.refreshedStores(
                            around: coordinate,
                            shoppingItems: intent.itemNames,
                            storeCategories: intent.storeCategories
                        )
                    } else {
                        groupStores = await searchService.stores(
                            around: coordinate,
                            shoppingItems: intent.itemNames,
                            storeCategories: intent.storeCategories
                        )
                    }
                    stores.append(contentsOf: groupStores.filter { $0.sourceType != .local })
                }
                return stores.map { $0.materializedWithStableIdentity() }
            }
        }
        inFlightSearches[key] = task
        let stores = deduplicated(await task.value)
        inFlightSearches[key] = nil
        discoveryCache[key] = CacheEntry(stores: stores, timestamp: Date())
        return retag(stores, intents: intents)
    }

    private func retag(_ stores: [MapStore], intents: [StoreResolutionIntent]) -> [MapStore] {
        stores.map { store in
            let matchedNames = intents
                .filter { intent in
                    intent.storeCategories.isEmpty || store.storeCategories.contains { storeCategory in
                        intent.storeCategories.contains { $0.matches(storeCategory) }
                    }
                }
                .flatMap(\.itemNames)
                .deduplicatedCaseInsensitive()

            return MapStore(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: store.radius,
                itemNames: matchedNames.isEmpty ? store.itemNames : matchedNames,
                completedItemNames: store.completedItemNames,
                isOpen: store.isOpen,
                rating: store.rating,
                storeCategories: store.storeCategories,
                queryEvidenceCategories: store.queryEvidenceCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
        }
    }

    private func merged(_ primary: MapStore, _ duplicate: MapStore) -> MapStore {
        let saved = primary.isSavedLocation ? primary : (duplicate.isSavedLocation ? duplicate : primary)
        let other = saved.id == primary.id ? duplicate : primary
        return MapStore(
            id: saved.id,
            locationID: saved.locationID,
            title: saved.title,
            coordinate: saved.coordinate,
            radius: saved.radius,
            itemNames: (saved.itemNames + other.itemNames).deduplicatedCaseInsensitive(),
            completedItemNames: (saved.completedItemNames + other.completedItemNames).deduplicatedCaseInsensitive(),
            isOpen: saved.isOpen ?? other.isOpen,
            rating: saved.rating ?? other.rating,
            storeCategories: (saved.storeCategories + other.storeCategories).deduplicated(),
            queryEvidenceCategories: (saved.queryEvidenceCategories + other.queryEvidenceCategories).deduplicated(),
            websiteURL: saved.websiteURL ?? other.websiteURL,
            sourceType: saved.sourceType
        )
    }

    private func cacheKey(
        coordinate: CLLocationCoordinate2D,
        intents: [StoreResolutionIntent]
    ) -> String {
        let latitudeBucket = Int((coordinate.latitude * 500).rounded())
        let longitudeBucket = Int((coordinate.longitude * 500).rounded())
        let intentKey = intents.map { intent in
            let names = intent.itemNames.map { $0.lowercased() }.sorted().joined(separator: ",")
            let categories = intent.storeCategories.map(\.rawValue).sorted().joined(separator: ",")
            return "\(categories):\(names)"
        }
        .sorted()
        .joined(separator: "|")
        return "\(latitudeBucket),\(longitudeBucket)#\(intentKey)"
    }

    private func distance(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private static func shouldIncludeSavedLocation(_ location: GeoLocation) -> Bool {
        guard location.sourceType == .debugSeed else {
            return true
        }

        #if DEBUG
        return DebugSeedStoreService.isEnabled
        #else
        return false
        #endif
    }
}

struct LocalStoreSearchService: StoreSearchService {
    private let provider = LocalStoreDataProvider()

    func stores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) async -> [MapStore] {
        guard !shoppingItems.isEmpty || !storeCategories.isEmpty else {
            return fallbackStores(
                around: coordinate,
                shoppingItems: shoppingItems,
                storeCategories: storeCategories
            )
        }

        guard shoppingItems.isEmpty || !storeCategories.isEmpty else {
            return []
        }

        return fallbackStores(
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
        guard shoppingItems.isEmpty || !storeCategories.isEmpty else {
            return []
        }

        return provider.localStores(
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

    private struct StoreSearchEvidence {
        let store: MapStore
        let query: String
        let queryCategory: ShoppingStoreCategory
        let evidenceCategory: ShoppingStoreCategory
        let pointOfInterestCategory: String?
    }

    private struct StoreAggregate {
        var evidence: [StoreSearchEvidence]

        var representative: StoreSearchEvidence {
            evidence.sorted { lhs, rhs in
                if lhs.store.title.count == rhs.store.title.count {
                    return lhs.store.title < rhs.store.title
                }

                return lhs.store.title.count > rhs.store.title.count
            }.first ?? evidence[0]
        }

        var evidenceCategories: [ShoppingStoreCategory] {
            evidence.map(\.evidenceCategory).deduplicated()
        }

        var queryCategories: [ShoppingStoreCategory] {
            evidence.map(\.queryCategory).deduplicated()
        }

        var queryEvidenceText: String {
            queryCategories.map(\.rawValue).joined(separator: ",")
        }
    }

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
        guard shoppingItems.isEmpty || !storeCategories.isEmpty else {
            auditFallbackUsed(
                true,
                reason: "Unresolved product intent has no allowed store categories",
                coordinate: coordinate,
                requestedCategories: storeCategories,
                storeCount: 0
            )
            return []
        }

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

        let stores = retagStores(mapKitStores, shoppingItems: shoppingItems)

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
        guard shoppingItems.isEmpty || !storeCategories.isEmpty else {
            auditFallbackUsed(
                true,
                reason: "Unresolved product intent has no allowed store categories",
                coordinate: coordinate,
                requestedCategories: storeCategories,
                storeCount: 0
            )
            return []
        }

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
        auditFallbackUsed(
            true,
            reason: "MapKit refresh returned zero usable stores; synthetic stores suppressed",
            coordinate: coordinate,
            requestedCategories: storeCategories,
            storeCount: 0
        )
        return []
    }

    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) -> [MapStore] {
        []
    }

    private func searchMapKitStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory]
    ) async -> [MapStore] {
        let categories = storeCategories.isEmpty ? defaultDiscoveryCategories : storeCategories
        let queries = categories.flatMap(searchQueries(for:)).deduplicatedCaseInsensitive()

        let searchResults = await withTaskGroup(of: [StoreSearchEvidence].self) { group in
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

            var combinedStores: [StoreSearchEvidence] = []
            for await stores in group {
                combinedStores.append(contentsOf: stores)
            }
            return combinedStores
        }

        return aggregate(searchResults, around: coordinate).prefixArray(12)
    }

    private func searchMapKit(
        query: String,
        coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        requestedCategories: [ShoppingStoreCategory],
        inferredCategory: ShoppingStoreCategory
    ) async -> [StoreSearchEvidence] {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: region)
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            var acceptedStores: [StoreSearchEvidence] = []
            var rejectedStores: [(name: String, category: String, distance: CLLocationDistance, reason: String)] = []

            for item in response.mapItems {
                let evaluation = makeMapStoreEvidence(
                    from: item,
                    query: query,
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
            if BetaDiagnosticsCenter.shared.isEnabled {
                BetaDiagnosticsCenter.shared.recordMapKitQuery(
                    query: query,
                    accepted: acceptedStores.count,
                    rejected: rejectedStores.map { ($0.name, $0.reason) }
                )
            }
            return acceptedStores
        } catch {
            BetaDiagnosticsCenter.shared.recordError(
                category: .storeDiscovery,
                message: "MapKit search failed",
                detail: "\(query): \(error.localizedDescription)"
            )
            if BetaDiagnosticsCenter.shared.isEnabled {
                BetaDiagnosticsCenter.shared.recordMapKitQuery(
                    query: query,
                    accepted: 0,
                    rejected: [(query, "MapKit error: \(error.localizedDescription)")]
                )
            }
            #if DEBUG
            print("[WayTask Store Search] MapKit search failed for \(query): \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func makeMapStoreEvidence(
        from item: MKMapItem,
        query: String,
        shoppingItems: [String],
        requestedCategories: [ShoppingStoreCategory],
        inferredCategory: ShoppingStoreCategory,
        queryCoordinate: CLLocationCoordinate2D
    ) -> (store: StoreSearchEvidence?, rejectionReason: String?) {
        guard let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return (nil, "missing title")
        }

        let mapKitCategory = category(from: item.pointOfInterestCategory)
        let canInheritQueryCategory = canInheritCategoryFromQuery(item.pointOfInterestCategory)
        let storeCategory = mapKitCategory == .generalStore && inferredCategory != .generalStore && canInheritQueryCategory
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

        let store = MapStore(
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
            queryEvidenceCategories: [],
            websiteURL: item.url,
            sourceType: .appleMaps
        )
        return (StoreSearchEvidence(
            store: store,
            query: query,
            queryCategory: inferredCategory,
            evidenceCategory: storeCategory,
            pointOfInterestCategory: item.pointOfInterestCategory?.rawValue
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
                queryEvidenceCategories: store.queryEvidenceCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
        }
    }

    private func aggregate(_ evidence: [StoreSearchEvidence], around coordinate: CLLocationCoordinate2D) -> [MapStore] {
        var aggregates: [StoreAggregate] = []

        for result in evidence.sorted(by: { lhs, rhs in
            distance(from: coordinate, to: lhs.store.coordinate) < distance(from: coordinate, to: rhs.store.coordinate)
        }) {
            if let index = aggregates.firstIndex(where: { aggregateMatches($0, result) }) {
                aggregates[index].evidence.append(result)
            } else {
                aggregates.append(StoreAggregate(evidence: [result]))
            }
        }

        let stores = aggregates
            .map(makeAggregatedStore)
            .sorted { lhs, rhs in
                distance(from: coordinate, to: lhs.coordinate) < distance(from: coordinate, to: rhs.coordinate)
            }

        auditAggregation(aggregates: aggregates, stores: stores, coordinate: coordinate)
        return stores
    }

    private func aggregateMatches(_ aggregate: StoreAggregate, _ result: StoreSearchEvidence) -> Bool {
        aggregate.evidence.contains { existing in
            let storeDistance = distance(from: existing.store.coordinate, to: result.store.coordinate)
            return (
                normalizedStoreName(existing.store.title) == normalizedStoreName(result.store.title) &&
                storeDistance < 80
            ) || (
                storeDistance < 35 &&
                namesLikelyMatch(existing.store.title, result.store.title)
            )
        }
    }

    private func makeAggregatedStore(_ aggregate: StoreAggregate) -> MapStore {
        let representative = aggregate.representative.store
        let strongestCategory = strongestCategory(
            for: aggregate.evidenceCategories,
            title: representative.title
        )

        return MapStore(
            id: representative.id,
            locationID: representative.locationID,
            title: representative.title,
            coordinate: representative.coordinate,
            radius: representative.radius,
            itemNames: representative.itemNames,
            completedItemNames: representative.completedItemNames,
            isOpen: representative.isOpen,
            rating: representative.rating,
            storeCategories: [strongestCategory],
            queryEvidenceCategories: aggregate.queryCategories,
            websiteURL: representative.websiteURL,
            sourceType: representative.sourceType
        )
    }

    private func strongestCategory(
        for categories: [ShoppingStoreCategory],
        title: String
    ) -> ShoppingStoreCategory {
        let lowercasedTitle = title.lowercased()
        if categories.contains(.coffeeShop) || lowercasedTitle.contains("coffee") || lowercasedTitle.contains("cafe") || lowercasedTitle.contains("café") {
            return .coffeeShop
        }

        return categories.max { lhs, rhs in
            categoryConfidence(lhs, title: lowercasedTitle) < categoryConfidence(rhs, title: lowercasedTitle)
        } ?? .generalStore
    }

    private func categoryConfidence(_ category: ShoppingStoreCategory, title: String) -> Int {
        switch category {
        case .coffeeShop:
            return 100
        case .petStore:
            return titleContainsAny(title, ["pet", "petco", "petsmart"]) ? 95 : 75
        case .electronicsStore:
            return titleContainsAny(title, ["electronics", "computer", "phone", "mobile", "apple", "best buy", "micro center"]) ? 95 : 75
        case .pharmacy:
            return titleContainsAny(title, ["pharmacy", "drugstore", "drug store", "chemist", "cvs", "walgreens", "rite aid"]) ? 95 : 75
        case .homeImprovement:
            return titleContainsAny(title, ["hardware", "home improvement", "home depot", "lowe"]) ? 95 : 75
        case .supermarket:
            return 90
        case .grocery:
            return 80
        case .convenienceStore:
            return 70
        case .generalStore:
            return 10
        }
    }

    private func titleContainsAny(_ title: String, _ terms: [String]) -> Bool {
        terms.contains { title.contains($0) }
    }

    private func normalizedStoreName(_ title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func namesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhsName = normalizedStoreName(lhs)
        let rhsName = normalizedStoreName(rhs)
        if lhsName == rhsName || lhsName.contains(rhsName) || rhsName.contains(lhsName) {
            return true
        }

        let lhsTokens = significantTokens(lhsName)
        let rhsTokens = significantTokens(rhsName)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return false
        }

        return !lhsTokens.isDisjoint(with: rhsTokens)
    }

    private func significantTokens(_ normalizedTitle: String) -> Set<String> {
        let genericTokens: Set<String> = ["store", "market", "shop", "supermarket", "grocery", "food", "mini", "the"]
        return Set(normalizedTitle.split(separator: " ").map(String.init).filter { token in
            token.count > 2 && !genericTokens.contains(token)
        })
    }

    private var defaultDiscoveryCategories: [ShoppingStoreCategory] {
        [.grocery, .supermarket, .convenienceStore, .pharmacy, .petStore, .electronicsStore, .homeImprovement]
    }

    private func searchQueries(for category: ShoppingStoreCategory) -> [String] {
        switch category {
        case .grocery:
            return ["grocery store", "food market", "grocery", "hypermarket"]
        case .supermarket:
            return ["supermarket", "hypermarket"]
        case .convenienceStore:
            return ["convenience store", "mini market", "neighborhood market"]
        case .coffeeShop:
            return ["coffee shop", "cafe"]
        case .petStore:
            return ["pet store", "pet supplies"]
        case .electronicsStore:
            return ["electronics store", "computer store", "mobile phone store"]
        case .homeImprovement:
            return ["hardware store", "home improvement store", "building supplies"]
        case .pharmacy:
            return ["pharmacy", "chemist", "drugstore"]
        case .generalStore:
            return ["store", "market"]
        }
    }

    private func category(for query: String) -> ShoppingStoreCategory {
        let lowercasedQuery = query.lowercased()

        if lowercasedQuery.contains("supermarket") || lowercasedQuery.contains("hypermarket") {
            return .supermarket
        }

        if lowercasedQuery.contains("convenience") || lowercasedQuery.contains("mini market") || lowercasedQuery.contains("neighborhood market") {
            return .convenienceStore
        }

        if lowercasedQuery.contains("coffee") || lowercasedQuery.contains("cafe") {
            return .coffeeShop
        }

        if lowercasedQuery.contains("pet") {
            return .petStore
        }

        if lowercasedQuery.contains("electronics") || lowercasedQuery.contains("computer") || lowercasedQuery.contains("mobile phone") {
            return .electronicsStore
        }

        if lowercasedQuery.contains("hardware") || lowercasedQuery.contains("home improvement") || lowercasedQuery.contains("building supplies") {
            return .homeImprovement
        }

        if lowercasedQuery.contains("pharmacy") || lowercasedQuery.contains("chemist") || lowercasedQuery.contains("drugstore") {
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
        case .restaurant:
            return .generalStore
        default:
            return nil
        }
    }

    private func canInheritCategoryFromQuery(_ pointOfInterestCategory: MKPointOfInterestCategory?) -> Bool {
        guard let pointOfInterestCategory else {
            return true
        }

        return pointOfInterestCategory == .store
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
        acceptedStores: [StoreSearchEvidence],
        rejectedStores: [(name: String, category: String, distance: CLLocationDistance, reason: String)],
        coordinate: CLLocationCoordinate2D
    ) {
        #if DEBUG
        let categoryText = requestedCategories.map(\.rawValue).joined(separator: ",")
        print("[WayTask Store Audit] MapKit query=\"\(query)\" category=\(inferredCategory.rawValue) requested=\(categoryText) raw=\(rawCount) accepted=\(acceptedStores.count) rejected=\(rejectedStores.count)")
        for evidence in acceptedStores {
            let store = evidence.store
            let distanceMeters = Int(distance(from: coordinate, to: store.coordinate))
            let storeCategoryText = store.storeCategories.map(\.rawValue).joined(separator: ",")
            print("[WayTask Store Audit] accepted name=\"\(store.title)\" source=\(store.sourceType.rawValue) distance=\(distanceMeters)m category=\(storeCategoryText) queryEvidence=\"\(evidence.queryCategory.rawValue)\"")
        }
        for rejectedStore in rejectedStores {
            print("[WayTask Store Audit] rejected name=\"\(rejectedStore.name)\" source=\(DataSourceType.appleMaps.rawValue) distance=\(Int(rejectedStore.distance))m category=\(rejectedStore.category) reason=\"\(rejectedStore.reason)\"")
        }
        #endif
    }

    private func auditAggregation(
        aggregates: [StoreAggregate],
        stores: [MapStore],
        coordinate: CLLocationCoordinate2D
    ) {
        #if DEBUG
        print("[WayTask Store Aggregation] raw=\(aggregates.reduce(0) { $0 + $1.evidence.count }) aggregated=\(stores.count)")
        for aggregate in aggregates {
            let store = makeAggregatedStore(aggregate)
            let distanceMeters = Int(distance(from: coordinate, to: store.coordinate))
            print("[WayTask Store Aggregation] store=\"\(store.title)\" distance=\(distanceMeters)m category=\(store.storeCategories.map(\.rawValue).joined(separator: ",")) returnedBy=\(aggregate.queryEvidenceText)")
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

private extension Array where Element == ShoppingStoreCategory {
    func deduplicated() -> [ShoppingStoreCategory] {
        reduce(into: [ShoppingStoreCategory]()) { result, category in
            if !result.contains(category) {
                result.append(category)
            }
        }
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
