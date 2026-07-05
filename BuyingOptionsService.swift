import CoreLocation
import Foundation

protocol BuyingOptionsServicing {
    func localOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore], userCoordinate: CLLocationCoordinate2D?) -> [BuyingOption]
    func suggestedStores(for request: ShoppingStoreSuggestionRequest) -> [MapStore]
}

struct BuyingOptionsService: BuyingOptionsServicing {
    private let storeRankingService = StoreRankingService()

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

        return storeOptions + futureOptions(for: request)
    }

    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption] {
        localOptions(for: request, stores: stores, userCoordinate: nil)
    }

    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore], userCoordinate: CLLocationCoordinate2D?) -> [BuyingOption] {
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

        return storeOptions + futureOptions(for: request)
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

    private func recommendationReasons(for store: MapStore, ranking: StoreScore) -> [String] {
        var reasons = ranking.reasons

        if store.itemNames.count > 1 {
            reasons.insert("Covers \(store.itemNames.count) items", at: 0)
        }

        return reasons.deduplicatedCaseInsensitive()
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
