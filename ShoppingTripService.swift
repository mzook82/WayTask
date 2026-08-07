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

enum ShoppingPlanStoreAvailabilityClaim:
    String, Equatable, Sendable {
    case estimatedOnly
}

struct ShoppingPlanStoreCoverage {
    let store: MapStore
    let group: ShoppingIntentGroup
    let matchedEntryIDs: [ProductStateListEntryID]
    let matchedProductIDs: [ProductStateProductID]
    let missingEntryIDs: [ProductStateListEntryID]
    let missingProductIDs: [ProductStateProductID]
    let coverageScore: Double
    let distance: CLLocationDistance?
    let ranking: StoreScore
    let availabilityClaim: ShoppingPlanStoreAvailabilityClaim
    let namedExclusions: [ShoppingPlanConsumerExclusion]
    let classificationUnresolvedEntryIDs: [ProductStateListEntryID]
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

    /// T-14 trip preparation is a read-only estimate for one exact Plan Input.
    /// It neither starts a Session nor interprets compatibility completion.
    func coverage(
        for authority: ShoppingPlanInputAuthority,
        classification: ShoppingPlanIntentClassification,
        stores: [MapStore],
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> [ShoppingPlanStoreCoverage] {
        guard classification.accountedEntryIDs ==
            authority.items.map(\.identity.id).sorted(by: entryIDLessThan)
        else {
            return []
        }

        let orderedStores = stores.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        return classification.groups.flatMap { group in
            orderedStores.compactMap { store in
                makePlanCoverage(
                    store: store,
                    group: group,
                    authority: authority,
                    classification: classification,
                    userCoordinate: userCoordinate
                )
            }
        }.sorted(by: planCoverageLessThan)
    }

    private func makePlanCoverage(
        store: MapStore,
        group: ShoppingPlanIntentGroupResult,
        authority: ShoppingPlanInputAuthority,
        classification: ShoppingPlanIntentClassification,
        userCoordinate: CLLocationCoordinate2D?
    ) -> ShoppingPlanStoreCoverage? {
        let relevantStore = storeWithRelevantPlanItems(store, group: group)
        guard rankingService.isRelevant(
            store: relevantStore,
            request: group.request,
            userCoordinate: userCoordinate
        ) else {
            return nil
        }

        let matched = intentMatcher.relevantPlanItems(
            from: group.items,
            for: relevantStore
        )
        guard !matched.isEmpty else { return nil }
        let matchedIDs = Set(matched.map(\.identity.id))
        let missing = group.items.filter {
            !matchedIDs.contains($0.identity.id)
        }
        let score = Double(matched.count) /
            Double(max(group.items.count, 1))
        let distance = userCoordinate.map {
            self.distance(from: $0, to: store.coordinate)
        }
        let ranking = rankingService.score(
            store: relevantStore,
            request: group.request,
            userCoordinate: userCoordinate,
            coverage: StoreRealityCoverage(
                matchedItemCount: matched.count,
                totalItemCount: group.items.count
            )
        )
        return ShoppingPlanStoreCoverage(
            store: relevantStore,
            group: group.group,
            matchedEntryIDs: matched.map(\.identity.id),
            matchedProductIDs: matched.map(\.identity.productID),
            missingEntryIDs: missing.map(\.identity.id),
            missingProductIDs: missing.map(\.identity.productID),
            coverageScore: score,
            distance: distance,
            ranking: ranking,
            availabilityClaim: .estimatedOnly,
            namedExclusions: authority.exclusions,
            classificationUnresolvedEntryIDs:
                classification.unresolvedItems.map(\.identity.id)
        )
    }

    private func storeWithRelevantPlanItems(
        _ store: MapStore,
        group: ShoppingPlanIntentGroupResult
    ) -> MapStore {
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

    private func planCoverageLessThan(
        _ lhs: ShoppingPlanStoreCoverage,
        _ rhs: ShoppingPlanStoreCoverage
    ) -> Bool {
        if lhs.ranking.score != rhs.ranking.score {
            return lhs.ranking.score > rhs.ranking.score
        }
        let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
        let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.store.id != rhs.store.id {
            return lhs.store.id.uuidString < rhs.store.id.uuidString
        }
        if lhs.group != rhs.group {
            return lhs.group.rawValue < rhs.group.rawValue
        }
        return lhs.matchedEntryIDs.map { $0.rawValue.uuidString }
            .joined(separator: "|") <
            rhs.matchedEntryIDs.map { $0.rawValue.uuidString }
                .joined(separator: "|")
    }

    private func entryIDLessThan(
        _ lhs: ProductStateListEntryID,
        _ rhs: ProductStateListEntryID
    ) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
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

        let matchedItems = intentMatcher.relevantItems(
            from: group.items,
            for: relevantStore
        )
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
