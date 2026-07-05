import CoreLocation
import Foundation

struct StoreRealityCoverage: Equatable {
    let matchedItemCount: Int
    let totalItemCount: Int

    var score: Double {
        guard totalItemCount > 0 else {
            return 0
        }

        return Double(matchedItemCount) / Double(totalItemCount)
    }
}

struct StoreRealityFeedback: Codable, Equatable, Sendable {
    let storeID: UUID
    let storeName: String
    let itemName: String
    let foundHere: Bool
    let notFoundHere: Bool
    let lastConfirmedAt: Date?
    let confidenceScore: Double
}

enum StoreRealitySignalKind: String, Codable, Equatable, Sendable {
    case itemHint
    case categoryRelevance
    case knownStoreType
    case distance
    case shoppingListCoverage
    case savedStore
    case userFeedback
    case communityKnowledge
    case inventoryProvider
}

struct StoreRealitySignalResult: Codable, Equatable, Sendable {
    let kind: StoreRealitySignalKind
    let score: Double
    let confidenceCap: Double?
    let reason: String?

    init(
        kind: StoreRealitySignalKind,
        score: Double,
        confidenceCap: Double? = nil,
        reason: String? = nil
    ) {
        self.kind = kind
        self.score = score
        self.confidenceCap = confidenceCap
        self.reason = reason
    }
}

struct StoreScore: Equatable {
    let score: Double
    let confidence: Double
    let reasons: [String]
    let signals: [StoreRealitySignalResult]

    init(
        score: Double,
        confidence: Double,
        reasons: [String],
        signals: [StoreRealitySignalResult] = []
    ) {
        self.score = score
        self.confidence = confidence
        self.reasons = reasons
        self.signals = signals
    }

    var confidenceLabel: String {
        if confidence >= 0.78 {
            return "High confidence"
        }

        if confidence >= 0.55 {
            return "Good match"
        }

        return "Possible match"
    }
}

struct StoreRankingService {
    func score(
        store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil,
        coverageScore: Double? = nil,
        coverage: StoreRealityCoverage? = nil
    ) -> StoreScore {
        let context = StoreRealityScoreContext(
            store: store,
            request: request,
            userCoordinate: userCoordinate,
            coverage: coverage,
            legacyCoverageScore: coverageScore
        )
        let results = activeSignals.map { $0.evaluate(context: context) }
        let rawScore = results.reduce(0.0) { $0 + $1.score }
        let normalizedScore = min(max(rawScore, 0), 100)
        let maxConfidence = results.compactMap(\.confidenceCap).max() ?? 0.48
        let confidence = min(max(normalizedScore / 100, 0.2), maxConfidence)
        let reasons = results
            .compactMap(\.reason)
            .deduplicatedCaseInsensitive()
        let fallbackReasons = reasons.isEmpty ? ["Possible match"] : reasons

        return StoreScore(
            score: normalizedScore,
            confidence: confidence,
            reasons: fallbackReasons,
            signals: results
        )
    }

    func isRelevant(
        store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> Bool {
        let context = StoreRealityScoreContext(
            store: store,
            request: request,
            userCoordinate: userCoordinate
        )

        guard ShoppingStoreCategoryFilter.isEligible(
            storeTitle: store.title,
            storeCategories: store.storeCategories,
            requestedCategories: request.storeCategories,
            distanceMeters: context.distanceMeters
        ) else {
            return false
        }

        if context.hasRelevantCategory {
            return true
        }

        if context.store.isSavedLocation && context.rawItemHintMatched {
            return true
        }

        return context.requestIsOnlyGeneralStore && !context.store.storeCategories.isEmpty
    }

    func rankedStores(
        _ stores: [MapStore],
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> [(store: MapStore, ranking: StoreScore)] {
        stores
            .filter { store in
                isRelevant(
                    store: store,
                    request: request,
                    userCoordinate: userCoordinate
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
                if lhs.ranking.score == rhs.ranking.score {
                    return distanceForSort(from: userCoordinate, to: lhs.store.coordinate)
                        < distanceForSort(from: userCoordinate, to: rhs.store.coordinate)
                }

                return lhs.ranking.score > rhs.ranking.score
            }
    }

    private var activeSignals: [StoreRealitySignal] {
        [
            ItemHintSignal(),
            CategoryRelevanceSignal(),
            KnownStoreTypeSignal(),
            DistanceSignal(),
            ShoppingListCoverageSignal(),
            SavedStoreSignal(),
            FutureUserFeedbackSignal(),
            FutureCommunityKnowledgeSignal(),
            FutureInventoryProviderSignal()
        ]
    }

    private func distanceForSort(from start: CLLocationCoordinate2D?, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let start else {
            return .greatestFiniteMagnitude
        }

        return CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }
}

private struct StoreRealityScoreContext {
    let store: MapStore
    let request: ShoppingStoreSuggestionRequest
    let userCoordinate: CLLocationCoordinate2D?
    let coverage: StoreRealityCoverage?
    let legacyCoverageScore: Double?

    init(
        store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D?,
        coverage: StoreRealityCoverage? = nil,
        legacyCoverageScore: Double? = nil
    ) {
        self.store = store
        self.request = request
        self.userCoordinate = userCoordinate
        self.coverage = coverage
        self.legacyCoverageScore = legacyCoverageScore
    }

    var requestedSpecificCategories: [ShoppingStoreCategory] {
        request.storeCategories.filter { $0 != .generalStore }
    }

    var requestHasSpecificCategory: Bool {
        !requestedSpecificCategories.isEmpty
    }

    var requestIsOnlyGeneralStore: Bool {
        !request.storeCategories.isEmpty && request.storeCategories.allSatisfy { $0 == .generalStore }
    }

    var distanceMeters: CLLocationDistance? {
        guard let userCoordinate else {
            return nil
        }

        return CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude))
    }

    var rawItemHintMatched: Bool {
        store.itemNames.contains { itemName in
            itemName.localizedCaseInsensitiveContains(request.itemName) ||
            request.itemName.localizedCaseInsensitiveContains(itemName)
        }
    }

    var itemHintCanScore: Bool {
        rawItemHintMatched && (store.isSavedLocation || hasRelevantCategory)
    }

    var categoryMatch: StoreCategoryMatchQuality {
        StoreCategoryMatcher.matchQuality(
            storeTitle: store.title,
            storeCategories: store.storeCategories,
            requestedCategories: requestedSpecificCategories,
            requestIsOnlyGeneralStore: requestIsOnlyGeneralStore
        )
    }

    var hasRelevantCategory: Bool {
        categoryMatch != .none
    }

    var savedLocationIsNearby: Bool {
        guard store.isSavedLocation else {
            return false
        }

        guard let distanceMeters else {
            return true
        }

        return distanceMeters <= 1500
    }

    func storeTitleContains(anyOf terms: [String]) -> Bool {
        let title = store.title.lowercased()
        return terms.contains { title.contains($0) }
    }
}

private protocol StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult
}

private struct ItemHintSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        guard context.itemHintCanScore else {
            return StoreRealitySignalResult(kind: .itemHint, score: 0)
        }

        return StoreRealitySignalResult(
            kind: .itemHint,
            score: 20,
            confidenceCap: 0.84,
            reason: "May have this item"
        )
    }
}

private struct CategoryRelevanceSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        switch context.categoryMatch {
        case .strong:
            return StoreRealitySignalResult(
                kind: .categoryRelevance,
                score: 36,
                confidenceCap: 0.9,
                reason: categoryReason(for: context)
            )
        case .partial:
            return StoreRealitySignalResult(
                kind: .categoryRelevance,
                score: 22,
                confidenceCap: 0.74,
                reason: categoryReason(for: context)
            )
        case .general:
            return StoreRealitySignalResult(
                kind: .categoryRelevance,
                score: 8,
                confidenceCap: 0.52,
                reason: "Suggested store"
            )
        case .none:
            return StoreRealitySignalResult(
                kind: .categoryRelevance,
                score: context.requestHasSpecificCategory ? -28 : 0
            )
        }
    }

    private func categoryReason(for context: StoreRealityScoreContext) -> String {
        if context.store.storeCategories.contains(.petStore) || context.storeTitleContains(anyOf: ["pet store", "pet supply", "pet shop"]) {
            return "Pet store"
        }

        if context.store.storeCategories.contains(.electronicsStore) || context.storeTitleContains(anyOf: ["electronics", "computer", "phone", "mobile"]) {
            return "Electronics store"
        }

        if context.store.storeCategories.contains(.pharmacy) || context.storeTitleContains(anyOf: ["pharmacy", "drugstore", "drug store"]) {
            return "Pharmacy or health store"
        }

        if context.store.storeCategories.contains(where: { $0 == .grocery || $0 == .supermarket || $0 == .convenienceStore || $0 == .coffeeShop }) {
            return "Grocery store"
        }

        if context.request.storeCategories.contains(.petStore) {
            return "Pet store"
        }

        if context.request.storeCategories.contains(.electronicsStore) {
            return "Electronics store"
        }

        if context.request.storeCategories.contains(.pharmacy) {
            return "Pharmacy or health store"
        }

        if context.request.storeCategories.contains(where: { $0 == .grocery || $0 == .supermarket || $0 == .convenienceStore || $0 == .coffeeShop }) {
            return "Grocery store"
        }

        return "Matches product category"
    }
}

private struct KnownStoreTypeSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        let storeTitle = context.store.title.lowercased()

        if context.request.storeCategories.contains(where: { $0 == .grocery || $0 == .supermarket || $0 == .convenienceStore }),
           knownGroceryTerms.contains(where: { storeTitle.contains($0) }) {
            return StoreRealitySignalResult(
                kind: .knownStoreType,
                score: 14,
                confidenceCap: 0.94,
                reason: "Known grocery chain"
            )
        }

        if context.request.storeCategories.contains(.pharmacy),
           knownPharmacyTerms.contains(where: { storeTitle.contains($0) }) {
            return StoreRealitySignalResult(
                kind: .knownStoreType,
                score: 14,
                confidenceCap: 0.92,
                reason: "Known pharmacy"
            )
        }

        if context.request.storeCategories.contains(.petStore),
           knownPetStoreTerms.contains(where: { storeTitle.contains($0) }) {
            return StoreRealitySignalResult(
                kind: .knownStoreType,
                score: 14,
                confidenceCap: 0.9,
                reason: "Known pet store"
            )
        }

        if context.request.storeCategories.contains(.electronicsStore),
           knownElectronicsTerms.contains(where: { storeTitle.contains($0) }) {
            return StoreRealitySignalResult(
                kind: .knownStoreType,
                score: 14,
                confidenceCap: 0.9,
                reason: "Known electronics store"
            )
        }

        return StoreRealitySignalResult(kind: .knownStoreType, score: 0)
    }

    private var knownGroceryTerms: [String] {
        [
            "aldi", "carrefour", "costco", "kroger", "lidl", "safeway", "shoprite",
            "spinneys", "tesco", "trader joe", "walmart", "whole foods", "waitrose"
        ]
    }

    private var knownPharmacyTerms: [String] {
        ["boots", "cvs", "rite aid", "super-pharm", "walgreens"]
    }

    private var knownPetStoreTerms: [String] {
        ["petco", "petsmart"]
    }

    private var knownElectronicsTerms: [String] {
        ["apple store", "best buy", "currys", "micro center"]
    }
}

private struct DistanceSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        guard let distance = context.distanceMeters else {
            return StoreRealitySignalResult(
                kind: .distance,
                score: 5,
                confidenceCap: 0.58,
                reason: "Nearby suggestion"
            )
        }

        if distance < 500 {
            return StoreRealitySignalResult(
                kind: .distance,
                score: 24,
                confidenceCap: 0.82,
                reason: "Nearby"
            )
        }

        if distance < 1500 {
            return StoreRealitySignalResult(
                kind: .distance,
                score: 18,
                confidenceCap: 0.76,
                reason: "Nearby"
            )
        }

        if distance < 3000 {
            return StoreRealitySignalResult(
                kind: .distance,
                score: 9,
                confidenceCap: 0.64,
                reason: "Nearby"
            )
        }

        if distance < 5000 {
            return StoreRealitySignalResult(kind: .distance, score: 2, confidenceCap: 0.5)
        }

        return StoreRealitySignalResult(
            kind: .distance,
            score: ShoppingStoreCategoryFilter.isGroceryProductRequest(context.request.storeCategories) ? -30 : -18
        )
    }
}

private struct ShoppingListCoverageSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        if let coverage = context.coverage {
            let normalizedCoverage = min(max(coverage.score, 0), 1)
            let reason: String?
            if coverage.totalItemCount > 1, coverage.matchedItemCount > 0 {
                reason = "Covers \(coverage.matchedItemCount)/\(coverage.totalItemCount) items"
            } else {
                reason = nil
            }

            return StoreRealitySignalResult(
                kind: .shoppingListCoverage,
                score: normalizedCoverage * 30,
                confidenceCap: normalizedCoverage >= 0.8 ? 0.9 : 0.72,
                reason: reason
            )
        }

        guard let legacyCoverageScore = context.legacyCoverageScore else {
            return StoreRealitySignalResult(kind: .shoppingListCoverage, score: 0)
        }

        let normalizedCoverage = min(max(legacyCoverageScore, 0), 1)
        let reason: String?
        if normalizedCoverage >= 1 {
            reason = "Covers your list"
        } else if normalizedCoverage >= 0.5 {
            reason = "Covers multiple items"
        } else {
            reason = nil
        }

        return StoreRealitySignalResult(
            kind: .shoppingListCoverage,
            score: normalizedCoverage * 24,
            confidenceCap: normalizedCoverage >= 0.8 ? 0.86 : 0.68,
            reason: reason
        )
    }
}

private struct SavedStoreSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        guard context.store.isSavedLocation else {
            return StoreRealitySignalResult(kind: .savedStore, score: 0)
        }

        if context.savedLocationIsNearby && (context.hasRelevantCategory || context.itemHintCanScore) {
            return StoreRealitySignalResult(
                kind: .savedStore,
                score: 14,
                confidenceCap: 0.82,
                reason: "Saved by you"
            )
        }

        if !context.savedLocationIsNearby {
            return StoreRealitySignalResult(kind: .savedStore, score: -10)
        }

        return StoreRealitySignalResult(kind: .savedStore, score: 0)
    }
}

private struct FutureUserFeedbackSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        StoreRealitySignalResult(kind: .userFeedback, score: 0)
    }
}

private struct FutureCommunityKnowledgeSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        StoreRealitySignalResult(kind: .communityKnowledge, score: 0)
    }
}

private struct FutureInventoryProviderSignal: StoreRealitySignal {
    func evaluate(context: StoreRealityScoreContext) -> StoreRealitySignalResult {
        StoreRealitySignalResult(kind: .inventoryProvider, score: 0)
    }
}

private enum StoreCategoryMatchQuality {
    case strong
    case partial
    case general
    case none
}

private enum StoreCategoryMatcher {
    static func matchQuality(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory],
        requestedCategories: [ShoppingStoreCategory],
        requestIsOnlyGeneralStore: Bool
    ) -> StoreCategoryMatchQuality {
        let title = storeTitle.lowercased()

        if requestedCategories.isEmpty {
            return requestIsOnlyGeneralStore && !storeCategories.isEmpty ? .general : .none
        }

        if requestedCategories.contains(where: { requestedCategory in
            storeCategories.contains { storeCategoryMatches(storeCategory: $0, requestedCategory: requestedCategory) }
        }) {
            return .strong
        }

        if requestedCategories.contains(where: { category in
            strongTitleTerms(for: category).contains { title.contains($0) }
        }) {
            return .strong
        }

        if requestedCategories.contains(where: { category in
            partialTitleTerms(for: category).contains { title.contains($0) }
        }) {
            return .partial
        }

        return .none
    }

    private static func storeCategoryMatches(storeCategory: ShoppingStoreCategory, requestedCategory: ShoppingStoreCategory) -> Bool {
        if storeCategory.matches(requestedCategory) {
            return true
        }

        if requestedCategory == .petStore {
            return storeCategory == .supermarket || storeCategory == .grocery
        }

        if requestedCategory == .pharmacy {
            return storeCategory == .pharmacy
        }

        if requestedCategory == .electronicsStore {
            return storeCategory == .electronicsStore
        }

        return false
    }

    private static func strongTitleTerms(for category: ShoppingStoreCategory) -> [String] {
        switch category {
        case .grocery:
            return ["grocery", "food market", "produce", "deli", "bakery"]
        case .supermarket:
            return ["supermarket", "hypermarket"]
        case .convenienceStore:
            return ["convenience", "corner store", "mini market", "minimarket", "bodega"]
        case .coffeeShop:
            return ["coffee", "cafe", "bakery", "bake shop"]
        case .petStore:
            return ["pet store", "pet supply", "pet shop"]
        case .electronicsStore:
            return ["electronics", "computer store", "mobile store", "phone store"]
        case .homeImprovement:
            return ["hardware", "home improvement"]
        case .pharmacy:
            return ["pharmacy", "drugstore", "drug store", "chemist"]
        case .generalStore:
            return ["store"]
        }
    }

    private static func partialTitleTerms(for category: ShoppingStoreCategory) -> [String] {
        switch category {
        case .grocery, .supermarket, .convenienceStore:
            return ["market", "mart", "shop", "food", "snack", "beverage"]
        case .pharmacy:
            return ["health", "medical", "wellness", "personal care"]
        case .petStore:
            return ["pet", "animal", "supermarket", "grocery", "market"]
        case .electronicsStore:
            return ["phone", "mobile", "computer", "tech", "device", "cable"]
        case .homeImprovement:
            return ["tools", "paint", "garden"]
        case .coffeeShop:
            return ["espresso", "tea", "pastry", "bread"]
        case .generalStore:
            return ["store", "shop", "market"]
        }
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
