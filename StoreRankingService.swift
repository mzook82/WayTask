import CoreLocation
import Foundation

struct StoreScore: Equatable {
    let score: Double
    let confidence: Double
    let reasons: [String]

    var confidenceLabel: String {
        if confidence >= 0.8 {
            return "High confidence"
        }

        if confidence >= 0.55 {
            return "Good match"
        }

        return "Suggested match"
    }
}

struct StoreRankingService {
    func score(
        store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> StoreScore {
        var score = 0.0
        var reasons: [String] = []

        let matchedItem = store.itemNames.contains { itemName in
            itemName.localizedCaseInsensitiveContains(request.itemName) ||
            request.itemName.localizedCaseInsensitiveContains(itemName)
        }

        if matchedItem {
            score += 35
            reasons.append("Likely available")
        }

        if matchesSuggestedCategory(store: store, request: request) {
            score += 25
            reasons.append("Matches product category")
        }

        if store.isOpen {
            score += 15
            reasons.append("Open now")
        }

        if let userCoordinate {
            let distance = distance(from: userCoordinate, to: store.coordinate)

            if distance < 500 {
                score += 25
                reasons.append("Closest store")
            } else if distance < 1500 {
                score += 15
                reasons.append("Nearby")
            } else {
                score += 6
            }
        } else {
            score += 8
            reasons.append("Nearby suggestion")
        }

        if !store.isSavedLocation {
            score += 5
        }

        let normalizedScore = min(score, 100)
        let confidence = min(max(normalizedScore / 100, 0.2), 0.95)
        let fallbackReasons = reasons.isEmpty ? ["Suggested for this item"] : reasons

        return StoreScore(
            score: normalizedScore,
            confidence: confidence,
            reasons: fallbackReasons
        )
    }

    func rankedStores(
        _ stores: [MapStore],
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> [(store: MapStore, ranking: StoreScore)] {
        stores
            .map { store in
                (
                    store: store,
                    ranking: score(
                        store: store,
                        request: request,
                        userCoordinate: userCoordinate
                    )
                )
            }
            .sorted { lhs, rhs in
                lhs.ranking.score > rhs.ranking.score
            }
    }

    private func matchesSuggestedCategory(store: MapStore, request: ShoppingStoreSuggestionRequest) -> Bool {
        let storeTitle = store.title.lowercased()
        return request.storeCategories.contains { category in
            storeTitle.contains(categoryKeyword(for: category)) ||
            storeTitle.contains(category.sampleStoreName.lowercased())
        }
    }

    private func categoryKeyword(for category: ShoppingStoreCategory) -> String {
        switch category {
        case .supermarket:
            return "market"
        case .coffeeShop:
            return "coffee"
        case .petStore:
            return "pet"
        case .electronicsStore:
            return "electronics"
        case .pharmacy:
            return "pharmacy"
        case .generalStore:
            return "store"
        }
    }

    private func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLocation.distance(from: endLocation)
    }
}
