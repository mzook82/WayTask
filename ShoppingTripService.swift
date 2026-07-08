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
    private let intentMatcher: ShoppingIntentMatcher

    init(
        rankingService: StoreRankingService = StoreRankingService(),
        intentMatcher: ShoppingIntentMatcher = ShoppingIntentMatcher()
    ) {
        self.rankingService = rankingService
        self.intentMatcher = intentMatcher
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

        let groups = intentMatcher.groupedIntents(for: activeItems)

        return groups
            .flatMap { group in
                stores.compactMap { store in
                    makeCoverage(
                        for: store,
                        group: group,
                        fallbackRequest: request,
                        userCoordinate: userCoordinate
                    )
                }
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
        group: ShoppingIntentGroupResult,
        fallbackRequest: ShoppingStoreSuggestionRequest?,
        userCoordinate: CLLocationCoordinate2D?
    ) -> StoreCoverage? {
        let groupRequest = intentMatcher.request(for: group)
        let relevantStore = storeWithRelevantItems(store, group: group)

        guard rankingService.isRelevant(
            store: relevantStore,
            request: groupRequest,
            userCoordinate: userCoordinate
        ) else {
            return nil
        }

        let matchedItems = group.items.filter { item in
            storeLikelyMatches(item, in: relevantStore)
        }
        let matchedIDs = Set(matchedItems.map(\.id))
        let missingItems = group.items.filter { !matchedIDs.contains($0.id) }
        let coverageScore = Double(matchedItems.count) / Double(max(group.items.count, 1))

        guard !matchedItems.isEmpty else {
            return nil
        }

        let storeDistance: CLLocationDistance?
        if let userCoordinate {
            storeDistance = distance(from: userCoordinate, to: store.coordinate)
        } else {
            storeDistance = nil
        }
        let rankingRequest = fallbackRequestForGroup(
            fallbackRequest,
            groupRequest: groupRequest
        )
        let ranking = rankingService.score(
            store: relevantStore,
            request: rankingRequest,
            userCoordinate: userCoordinate,
            coverageScore: coverageScore,
            coverage: StoreRealityCoverage(
                matchedItemCount: matchedItems.count,
                totalItemCount: group.items.count
            )
        )
        let coverageReason = "Covers \(matchedItems.count)/\(group.items.count) \(group.group.displayName.lowercased()) items"
        let coverageRanking = StoreScore(
            score: ranking.score,
            confidence: ranking.confidence,
            reasons: ([coverageReason] + groupAwareReasons(from: ranking.reasons)).deduplicatedCaseInsensitive(),
            signals: ranking.signals
        )

        return StoreCoverage(
            store: relevantStore,
            group: group.group,
            matchedItems: matchedItems,
            missingItems: missingItems,
            coverageScore: coverageScore,
            distance: storeDistance,
            ranking: coverageRanking
        )
    }

    private func groupAwareReasons(from reasons: [String]) -> [String] {
        reasons.filter { !$0.hasPrefix("Covers ") }
    }

    private func storeWithRelevantItems(_ store: MapStore, group: ShoppingIntentGroupResult) -> MapStore {
        MapStore(
            id: store.id,
            locationID: store.locationID,
            title: store.title,
            coordinate: store.coordinate,
            radius: store.radius,
            itemNames: group.itemNames,
            completedItemNames: store.completedItemNames,
            isOpen: store.isOpen,
            rating: store.rating,
            storeCategories: store.storeCategories,
            queryEvidenceCategories: store.queryEvidenceCategories,
            websiteURL: store.websiteURL,
            sourceType: store.sourceType
        )
    }

    private func fallbackRequestForGroup(
        _ fallbackRequest: ShoppingStoreSuggestionRequest?,
        groupRequest: ShoppingStoreSuggestionRequest
    ) -> ShoppingStoreSuggestionRequest {
        guard let fallbackRequest,
              fallbackRequest.storeCategories.contains(where: { fallbackCategory in
                  groupRequest.storeCategories.contains { $0.matches(fallbackCategory) }
              }) else {
            return groupRequest
        }

        return ShoppingStoreSuggestionRequest(
            itemID: groupRequest.itemID,
            itemName: groupRequest.itemName,
            itemCategory: groupRequest.itemCategory,
            storeCategories: groupRequest.storeCategories,
            searchTerms: (groupRequest.searchTerms + fallbackRequest.searchTerms).deduplicatedCaseInsensitive(),
            intentProfile: groupRequest.intentProfile
        )
    }

    private func storeLikelyMatches(_ item: ShoppingItem, in store: MapStore) -> Bool {
        let productTerms = [
            item.name,
            item.brand,
            item.category,
            item.productType,
            item.flavor,
            item.packageSize,
            item.packageType
        ]
        .compactMap { $0 }
        let itemTokens = tokens(from: productTerms + item.searchKeywords)
        guard !itemTokens.isEmpty else {
            return false
        }

        let itemCategories = Set(intentMatcher.matchStoreCategories(for: item))
        let storeCategories = Set(store.storeCategories)
        if storeCategories.contains(where: { storeCategory in
            itemCategories.contains { itemCategory in
                storeCategory.matches(itemCategory)
            }
        }) {
            return true
        }

        let storeTokens = tokens(from: store.itemNames + [store.title] + store.storeCategories.map(\.displayName))
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
            storeCategories: firstItem.map { intentMatcher.matchStoreCategories(for: $0) } ?? [],
            searchTerms: [firstItem?.name ?? store.title],
            intentProfile: firstItem.map { intentMatcher.intentProfile(for: $0) }
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

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
    }
}
