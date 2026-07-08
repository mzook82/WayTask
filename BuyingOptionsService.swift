import CoreLocation
import Foundation

protocol BuyingOptionsServicing {
    func localOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore], userCoordinate: CLLocationCoordinate2D?) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, shoppingItems: [ShoppingItem], stores: [MapStore], userCoordinate: CLLocationCoordinate2D?) -> [BuyingOption]
    func suggestedStores(for request: ShoppingStoreSuggestionRequest) -> [MapStore]
}

struct BuyingOptionsService: BuyingOptionsServicing {
    private let storeRankingService = StoreRankingService()
    private let intentMatcher = ShoppingIntentMatcher()

    func localOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption] {
        let rankedStores = storeRankingService.rankedStores(
            suggestedStores(for: request),
            request: request,
            userCoordinate: nil
        )

        let storeOptions = rankedStores.map { rankedStore in
            BuyingOption(
                title: "Suggested store for \(request.itemName)",
                subtitle: "Likely available at suggested nearby stores.",
                optionType: .suggestedStore,
                storeName: rankedStore.store.title,
                distanceText: "Nearby",
                priceText: nil,
                websiteURL: rankedStore.store.websiteURL,
                confidenceLabel: rankedStore.ranking.confidenceLabel,
                source: .local,
                ranking: rankedStore.ranking,
                recommendationReasons: rankedStore.ranking.reasons
            )
        }

        return storeOptions + futureOptionsIfAppropriate(for: request)
    }

    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption] {
        localOptions(for: request, stores: stores, userCoordinate: nil)
    }

    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore], userCoordinate: CLLocationCoordinate2D?) -> [BuyingOption] {
        localOptions(
            for: request,
            shoppingItems: [],
            stores: stores,
            userCoordinate: userCoordinate
        )
    }

    func localOptions(
        for request: ShoppingStoreSuggestionRequest,
        shoppingItems: [ShoppingItem],
        stores: [MapStore],
        userCoordinate: CLLocationCoordinate2D?
    ) -> [BuyingOption] {
        let activeGroups = intentMatcher.groupedIntents(for: shoppingItems)
        guard !activeGroups.isEmpty else {
            return ungroupedLocalOptions(
                for: request,
                stores: stores,
                userCoordinate: userCoordinate
            )
        }

        let storeOptions = activeGroups.flatMap { group in
            groupedStoreOptions(
                for: group,
                stores: stores,
                userCoordinate: userCoordinate
            )
        }
        .sorted { lhs, rhs in
            if (lhs.ranking?.score ?? 0) == (rhs.ranking?.score ?? 0) {
                return lhs.storeName < rhs.storeName
            }

            return (lhs.ranking?.score ?? 0) > (rhs.ranking?.score ?? 0)
        }

        return storeOptions + futureOptionsIfAppropriate(for: request)
    }

    private func ungroupedLocalOptions(
        for request: ShoppingStoreSuggestionRequest,
        stores: [MapStore],
        userCoordinate: CLLocationCoordinate2D?
    ) -> [BuyingOption] {
        let rankedStores = storeRankingService.rankedStores(
            stores,
            request: request,
            userCoordinate: userCoordinate
        )

        let storeOptions = rankedStores.map { rankedStore in
            let recommendationReasons = recommendationReasons(
                for: rankedStore.store,
                ranking: rankedStore.ranking
            )
            return BuyingOption(
                title: "Suggested store for \(request.itemName)",
                subtitle: subtitle(for: rankedStore.store),
                optionType: rankedStore.store.isSavedLocation ? .nearbyStore : .suggestedStore,
                storeName: rankedStore.store.title,
                distanceText: distanceText(from: userCoordinate, to: rankedStore.store.coordinate),
                priceText: nil,
                websiteURL: rankedStore.store.websiteURL,
                confidenceLabel: rankedStore.ranking.confidenceLabel,
                source: rankedStore.store.sourceType,
                ranking: rankedStore.ranking,
                recommendationReasons: recommendationReasons
            )
        }

        return storeOptions + futureOptionsIfAppropriate(for: request)
    }

    private func groupedStoreOptions(
        for group: ShoppingIntentGroupResult,
        stores: [MapStore],
        userCoordinate: CLLocationCoordinate2D?
    ) -> [BuyingOption] {
        let groupRequest = intentMatcher.request(for: group)

        return stores.compactMap { store in
            let relevantStore = storeWithRelevantItems(store, itemNames: group.itemNames)
            guard storeRankingService.isRelevant(
                store: relevantStore,
                request: groupRequest,
                userCoordinate: userCoordinate
            ) else {
                return nil
            }

            let ranking = storeRankingService.score(
                store: relevantStore,
                request: groupRequest,
                userCoordinate: userCoordinate,
                coverage: StoreRealityCoverage(
                    matchedItemCount: group.items.count,
                    totalItemCount: group.items.count
                )
            )
            let recommendationReasons = recommendationReasons(
                for: relevantStore,
                ranking: ranking,
                group: group
            )

            return BuyingOption(
                title: "\(group.group.displayName) option",
                subtitle: subtitle(for: relevantStore, group: group.group),
                optionType: relevantStore.isSavedLocation ? .nearbyStore : .suggestedStore,
                storeName: relevantStore.title,
                distanceText: distanceText(from: userCoordinate, to: relevantStore.coordinate),
                priceText: nil,
                websiteURL: relevantStore.websiteURL,
                confidenceLabel: ranking.confidenceLabel,
                source: relevantStore.sourceType,
                ranking: ranking,
                recommendationReasons: recommendationReasons
            )
        }
    }

    func suggestedStores(for request: ShoppingStoreSuggestionRequest) -> [MapStore] {
        request.storeCategories.enumerated().map { index, category in
            MapStore(
                id: UUID(uuidString: "30000000-0000-0000-0000-\(String(format: "%012d", index + 1))") ?? UUID(),
                locationID: nil,
                title: category.sampleStoreName,
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                radius: 180,
                itemNames: [request.itemName],
                completedItemNames: [],
                isOpen: true,
                rating: 4.5 + min(Double(index) * 0.1, 0.3),
                storeCategories: [category],
                queryEvidenceCategories: [],
                websiteURL: URL(string: "https://maps.apple.com"),
                sourceType: .local
            )
        }
    }

    private func futureOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption] {
        [
            BuyingOption(
                title: "Online store options",
                subtitle: "Online store lookup is planned for a future release.",
                optionType: .onlineStore,
                storeName: "Online",
                distanceText: "Coming soon",
                priceText: nil,
                websiteURL: nil,
                confidenceLabel: nil,
                source: .local
            ),
            BuyingOption(
                title: "Compare prices for \(request.itemName)",
                subtitle: "Price comparison will appear here when provider support is added.",
                optionType: .futurePriceComparison,
                storeName: "Price comparison",
                distanceText: "Coming soon",
                priceText: nil,
                websiteURL: nil,
                confidenceLabel: nil,
                source: .local
            )
        ]
    }

    private func futureOptionsIfAppropriate(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption] {
        if request.intentProfile?.isUnresolved == true {
            return []
        }

        return futureOptions(for: request)
    }

    private func distanceText(from userCoordinate: CLLocationCoordinate2D?, to storeCoordinate: CLLocationCoordinate2D) -> String {
        guard let userCoordinate else {
            return "Nearby"
        }

        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let storeLocation = CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude)
        let distance = userLocation.distance(from: storeLocation)

        if distance >= 1000 {
            return String(format: "%.1f km away", distance / 1000)
        }

        return "\(max(Int(distance), 1)) m away"
    }

    private func distance(from userCoordinate: CLLocationCoordinate2D, to storeCoordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude))
    }

    private func subtitle(for store: MapStore) -> String {
        guard !store.itemNames.isEmpty else {
            return "May have this item."
        }

        return store.matchingItemsLabel
    }

    private func subtitle(for store: MapStore, group: ShoppingIntentGroup) -> String {
        guard !store.itemNames.isEmpty else {
            return "May have \(group.displayName.lowercased()) items."
        }

        return store.matchingItemsLabel
    }

    private func recommendationReasons(for store: MapStore, ranking: StoreScore) -> [String] {
        var reasons = ranking.reasons

        if store.itemNames.count > 1 {
            reasons.insert("Covers \(store.itemNames.count) items", at: 0)
        }

        return reasons.deduplicatedCaseInsensitive()
    }

    private func recommendationReasons(
        for store: MapStore,
        ranking: StoreScore,
        group: ShoppingIntentGroupResult
    ) -> [String] {
        var reasons = ranking.reasons.filter { !$0.hasPrefix("Covers ") }

        if !group.items.isEmpty {
            reasons.insert("Covers \(group.items.count) \(group.group.displayName.lowercased()) items", at: 0)
        }

        return reasons.deduplicatedCaseInsensitive()
    }

    private func storeWithRelevantItems(_ store: MapStore, itemNames: [String]) -> MapStore {
        MapStore(
            id: store.id,
            locationID: store.locationID,
            title: store.title,
            coordinate: store.coordinate,
            radius: store.radius,
            itemNames: itemNames,
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

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
    }
}
