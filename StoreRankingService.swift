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
        userCoordinate: CLLocationCoordinate2D? = nil,
        coverageScore: Double? = nil
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

        if store.itemNames.count > 1 {
            score += min(Double(store.itemNames.count) * 4, 18)
        }

        let categoryMatched = matchesSuggestedCategory(store: store, request: request)
        if categoryMatched {
            score += 25
            reasons.append("Matches product category")
        }

        if store.isOpen == true {
            score += 15
            reasons.append("Open now")
        } else if store.isOpen == nil {
            score += 6
        }

        if let userCoordinate {
            let distance = distance(from: userCoordinate, to: store.coordinate)

            if distance < 500 {
                score += 32
                reasons.append("Closest store")
            } else if distance < 1500 {
                score += 24
                reasons.append("Nearby")
            } else if distance < 3000 {
                score += 10
                reasons.append("Nearby")
            } else {
                score -= 18
            }
        } else {
            score += 8
            reasons.append("Nearby suggestion")
        }

        if let coverageScore {
            let normalizedCoverage = min(max(coverageScore, 0), 1)
            score += normalizedCoverage * 30

            if normalizedCoverage >= 1 {
                reasons.append("Covers your full list")
            } else if normalizedCoverage >= 0.5 {
                reasons.append("Covers multiple list items")
            }
        }

        let savedLocationIsNearby: Bool
        if let userCoordinate {
            savedLocationIsNearby = distance(from: userCoordinate, to: store.coordinate) <= 1500
        } else {
            savedLocationIsNearby = true
        }

        if store.isSavedLocation && savedLocationIsNearby {
            score += 22
            reasons.append("Saved by you")
        }

        let normalizedScore = min(score, 100)
        let maxConfidence = categoryMatched ? 0.95 : 0.54
        let confidence = min(max(normalizedScore / 100, 0.2), maxConfidence)
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
            .filter { store in
                let storeDistance: CLLocationDistance?
                if let userCoordinate {
                    storeDistance = distance(from: userCoordinate, to: store.coordinate)
                } else {
                    storeDistance = nil
                }
                return ShoppingStoreCategoryFilter.isEligible(
                    storeTitle: store.title,
                    storeCategories: store.storeCategories,
                    requestedCategories: request.storeCategories,
                    distanceMeters: storeDistance
                )
            }
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
        if request.storeCategories.contains(.generalStore), store.isSavedLocation, !store.storeCategories.isEmpty {
            return true
        }

        return request.storeCategories.contains { category in
            store.storeCategories.contains { $0.matches(category) } ||
            storeTitle.contains(categoryKeyword(for: category)) ||
            storeTitle.contains(category.sampleStoreName.lowercased())
        }
    }

    private func categoryKeyword(for category: ShoppingStoreCategory) -> String {
        switch category {
        case .grocery:
            return "grocery"
        case .supermarket:
            return "market"
        case .convenienceStore:
            return "convenience"
        case .coffeeShop:
            return "coffee"
        case .petStore:
            return "pet"
        case .electronicsStore:
            return "electronics"
        case .homeImprovement:
            return "hardware"
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
