import Foundation

protocol BuyingOptionsServicing {
    func localOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption]
    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption]
}

struct BuyingOptionsService: BuyingOptionsServicing {
    private let storeRankingService = StoreRankingService()

    func localOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption] {
        let storeOptions = request.storeCategories.enumerated().map { index, category in
            let ranking = StoreScore(
                score: max(78 - Double(index * 6), 60),
                confidence: max(0.78 - Double(index) * 0.06, 0.6),
                reasons: [
                    "Matches product category",
                    "Likely available",
                    "Nearby suggestion"
                ]
            )

            return BuyingOption(
                title: "Find \(request.itemName)",
                subtitle: "Likely available at \(category.displayName.lowercased()).",
                optionType: .suggestedStore,
                storeName: category.sampleStoreName,
                distanceText: "Nearby",
                priceText: nil,
                websiteURL: URL(string: "https://maps.apple.com"),
                confidenceLabel: ranking.confidenceLabel,
                source: .local,
                ranking: ranking,
                recommendationReasons: ranking.reasons
            )
        }

        return storeOptions + futureOptions(for: request)
    }

    func localOptions(for request: ShoppingStoreSuggestionRequest, stores: [MapStore]) -> [BuyingOption] {
        let matchingStores = stores.filter { store in
            store.itemNames.contains { itemName in
                itemName.localizedCaseInsensitiveContains(request.itemName) ||
                request.itemName.localizedCaseInsensitiveContains(itemName)
            }
        }

        let sourceStores = matchingStores.isEmpty ? stores : matchingStores

        let rankedStores = storeRankingService.rankedStores(
            sourceStores,
            request: request
        )

        let storeOptions = rankedStores.map { rankedStore in
            BuyingOption(
                title: "Buy \(request.itemName)",
                subtitle: rankedStore.store.matchingItemsLabel,
                optionType: rankedStore.store.isSavedLocation ? .nearbyStore : .suggestedStore,
                storeName: rankedStore.store.title,
                distanceText: "Nearby",
                priceText: nil,
                websiteURL: rankedStore.store.websiteURL,
                confidenceLabel: rankedStore.ranking.confidenceLabel,
                source: rankedStore.store.isSavedLocation ? .userGenerated : .local,
                ranking: rankedStore.ranking,
                recommendationReasons: rankedStore.ranking.reasons
            )
        }

        return storeOptions + futureOptions(for: request)
    }

    private func futureOptions(for request: ShoppingStoreSuggestionRequest) -> [BuyingOption] {
        [
            BuyingOption(
                title: "Online buying options",
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
}
