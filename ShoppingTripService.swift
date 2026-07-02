import CoreLocation
import Foundation

protocol ShoppingTripServicing {
    func coverage(
        for shoppingItems: [ShoppingItem],
        stores: [MapStore],
        request: ShoppingStoreSuggestionRequest?,
        userCoordinate: CLLocationCoordinate2D?
    ) -> [StoreCoverage]
}

struct ShoppingTripService: ShoppingTripServicing {
    private let rankingService: StoreRankingService

    init(rankingService: StoreRankingService = StoreRankingService()) {
        self.rankingService = rankingService
    }

    func coverage(
        for shoppingItems: [ShoppingItem],
        stores: [MapStore],
        request: ShoppingStoreSuggestionRequest? = nil,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> [StoreCoverage] {
        let activeItems = shoppingItems.filter { !$0.isCompleted }
        guard !activeItems.isEmpty else {
            return []
        }

        return stores
            .map { store in
                makeCoverage(
                    for: store,
                    shoppingItems: activeItems,
                    request: request,
                    userCoordinate: userCoordinate
                )
            }
            .sorted { lhs, rhs in
                if lhs.ranking.score == rhs.ranking.score {
                    return (lhs.distance ?? .greatestFiniteMagnitude) < (rhs.distance ?? .greatestFiniteMagnitude)
                }

                return lhs.ranking.score > rhs.ranking.score
            }
    }

    private func makeCoverage(
        for store: MapStore,
        shoppingItems: [ShoppingItem],
        request: ShoppingStoreSuggestionRequest?,
        userCoordinate: CLLocationCoordinate2D?
    ) -> StoreCoverage {
        let matchedItems = shoppingItems.filter { item in
            storeLikelyMatches(item, in: store)
        }
        let matchedIDs = Set(matchedItems.map(\.id))
        let missingItems = shoppingItems.filter { !matchedIDs.contains($0.id) }
        let coverageScore = Double(matchedItems.count) / Double(max(shoppingItems.count, 1))
        let storeDistance: CLLocationDistance?
        if let userCoordinate {
            storeDistance = distance(from: userCoordinate, to: store.coordinate)
        } else {
            storeDistance = nil
        }
        let rankingRequest = request ?? fallbackRequest(for: shoppingItems, store: store)
        let ranking = rankingService.score(
            store: store,
            request: rankingRequest,
            userCoordinate: userCoordinate,
            coverageScore: coverageScore
        )

        return StoreCoverage(
            store: store,
            matchedItems: matchedItems,
            missingItems: missingItems,
            coverageScore: coverageScore,
            distance: storeDistance,
            ranking: ranking
        )
    }

    private func storeLikelyMatches(_ item: ShoppingItem, in store: MapStore) -> Bool {
        let itemTokens = tokens(from: [item.name, item.brand, item.category])
        guard !itemTokens.isEmpty else {
            return false
        }

        let storeTokens = tokens(from: store.itemNames + [store.title])
        return itemTokens.contains { token in
            storeTokens.contains(token)
        }
    }

    private func fallbackRequest(for items: [ShoppingItem], store: MapStore) -> ShoppingStoreSuggestionRequest {
        let firstItem = items.first
        return ShoppingStoreSuggestionRequest(
            itemID: firstItem?.id ?? store.id,
            itemName: firstItem?.name ?? store.title,
            itemCategory: firstItem?.category,
            storeCategories: [.generalStore],
            searchTerms: [firstItem?.name ?? store.title]
        )
    }

    private func tokens(from values: [String?]) -> Set<String> {
        Set(
            values
                .compactMap { $0 }
                .flatMap { value in
                    value
                        .lowercased()
                        .split { !$0.isLetter && !$0.isNumber }
                        .map(String.init)
                }
                .filter { $0.count > 2 }
        )
    }

    private func tokens(from values: [String]) -> Set<String> {
        tokens(from: values.map(Optional.some))
    }

    private func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLocation.distance(from: endLocation)
    }
}
