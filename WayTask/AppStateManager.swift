//
//  Untitled.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import Combine
import CoreLocation
import Foundation
import SwiftUI
import UserNotifications

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case products
    case shopping
    case map
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .products:
            return "Products"
        case .shopping:
            return "Shopping"
        case .map:
            return "Map"
        case .settings:
            return "Settings"
        }
    }

    var systemImageName: String {
        switch self {
        case .home:
            return "house.fill"
        case .products:
            return "shippingbox.fill"
        case .shopping:
            return "list.bullet.rectangle.fill"
        case .map:
            return "map.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct NearbyShoppingOpportunity: Identifiable, Equatable {
    let id: String
    let storeID: UUID?
    let locationID: UUID?
    let title: String
    let itemNames: [String]
    let sourceType: String
    let distanceMeters: CLLocationDistance
    let realityScore: Double
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let detectedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km away", distanceMeters / 1000)
        }

        return "\(max(Int(distanceMeters.rounded()), 1)) m away"
    }

    var itemSummary: String {
        if itemNames.isEmpty {
            return "Your shopping list may have a match here."
        }

        if itemNames.count == 1 {
            return "\(itemNames[0]) may be available here."
        }

        let visibleNames = itemNames.prefix(2).joined(separator: ", ")
        let suffix = itemNames.count > 2 ? ", and more" : ""
        return "\(itemNames.count) items may be available here: \(visibleNames)\(suffix)."
    }
}

struct ShoppingPlan: Identifiable {
    let id: UUID
    let request: ShoppingStoreSuggestionRequest
    let items: [ShoppingItem]
    let stores: [MapStore]
    let buyingOptions: [BuyingOption]
    let shoppingTripCoverages: [StoreCoverage]
    let generatedAt: Date
    let contentSignature: String

    init(
        id: UUID = UUID(),
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.items = items.filter { !$0.isCompleted }
        self.stores = stores
        self.buyingOptions = buyingOptions
        self.shoppingTripCoverages = shoppingTripCoverages
        self.generatedAt = generatedAt
        self.contentSignature = ShoppingPlan.makeContentSignature(
            request: request,
            items: self.items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
    }

    var bestCoverage: StoreCoverage? {
        shoppingTripCoverages.first
    }

    private static func makeContentSignature(
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage]
    ) -> String {
        [
            requestSignature(request),
            itemSignature(items),
            storeSignature(stores),
            buyingOptionSignature(buyingOptions),
            coverageSignature(shoppingTripCoverages)
        ].joined(separator: "|")
    }

    private static func requestSignature(_ request: ShoppingStoreSuggestionRequest) -> String {
        [
            request.itemID.uuidString,
            request.itemName,
            request.itemCategory ?? "",
            request.storeCategories.map(\.rawValue).joined(separator: ","),
            request.searchTerms.joined(separator: ","),
            intentProfileSignature(request.intentProfile)
        ].joined(separator: ":")
    }

    private static func intentProfileSignature(_ profile: ProductIntentProfile?) -> String {
        guard let profile else {
            return ""
        }

        return [
            profile.normalizedCategory.rawValue,
            profile.intentGroup.rawValue,
            String(format: "%.2f", profile.confidence),
            profile.evidence.sorted().joined(separator: ","),
            profile.primaryAllowedStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.secondaryAllowedStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.fallbackStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.excludedStoreTypes.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "/")
    }

    private static func itemSignature(_ items: [ShoppingItem]) -> String {
        items
            .map { item in
                [
                    item.id.uuidString,
                    item.name,
                    item.brand ?? "",
                    item.category ?? "",
                    item.isCompleted ? "1" : "0"
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func storeSignature(_ stores: [MapStore]) -> String {
        stores
            .map { store in
                [
                    store.id.uuidString,
                    store.title,
                    String(format: "%.5f", store.coordinate.latitude),
                    String(format: "%.5f", store.coordinate.longitude),
                    store.itemNames.sorted().joined(separator: ","),
                    store.completedItemNames.sorted().joined(separator: ","),
                    store.storeCategories.map(\.rawValue).sorted().joined(separator: ","),
                    store.sourceType.rawValue
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func buyingOptionSignature(_ buyingOptions: [BuyingOption]) -> String {
        buyingOptions
            .map { option in
                [
                    option.title,
                    option.subtitle,
                    option.optionType.rawValue,
                    option.storeName,
                    option.distanceText,
                    option.source.rawValue,
                    String(format: "%.2f", option.ranking?.score ?? -1),
                    option.confidenceLabel ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: ";")
    }

    private static func coverageSignature(_ coverages: [StoreCoverage]) -> String {
        coverages
            .map { coverage in
                [
                    coverage.id,
                    coverage.store.title,
                    coverage.group.rawValue,
                    coverage.matchedItems.map(\.id.uuidString).sorted().joined(separator: ","),
                    coverage.missingItems.map(\.id.uuidString).sorted().joined(separator: ","),
                    String(format: "%.4f", coverage.coverageScore),
                    String(format: "%.1f", coverage.distance ?? -1),
                    String(format: "%.2f", coverage.ranking.score),
                    String(format: "%.2f", coverage.ranking.confidence)
                ].joined(separator: ":")
            }
            .joined(separator: ";")
    }
}

enum ShoppingPlanGenerationStage: String, CaseIterable, Equatable {
    case preparingList
    case findingStores
    case matchingProducts
    case calculatingCoverage
    case rankingOptions

    var title: String {
        switch self {
        case .preparingList:
            return "Preparing your shopping list"
        case .findingStores:
            return "Finding nearby stores"
        case .matchingProducts:
            return "Matching products to stores"
        case .calculatingCoverage:
            return "Calculating coverage"
        case .rankingOptions:
            return "Ranking the best options"
        }
    }
}

enum ShoppingPlanGenerationState: Equatable {
    case idle
    case generating(stage: ShoppingPlanGenerationStage, startedAt: Date)
    case ready(generatedAt: Date)
    case failed(message: String, actionTitle: String?)
    case stale(reason: String)

    var isGenerating: Bool {
        if case .generating = self {
            return true
        }

        return false
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    var stageTitle: String? {
        if case let .generating(stage, _) = self {
            return stage.title
        }

        return nil
    }

    var startedAt: Date? {
        if case let .generating(_, startedAt) = self {
            return startedAt
        }

        return nil
    }
}

final class AppStateManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var selectedTab: AppTab = .home
    @Published var navigationPath = NavigationPath()
    @Published var focusedLocationID: UUID?
    @Published var shoppingListRevision = UUID()
    @Published var recentlyAddedShoppingItemID: UUID?
    @Published private(set) var shoppingPlan: ShoppingPlan?
    @Published private(set) var shoppingPlanState: ShoppingPlanGenerationState = .idle
    @Published private(set) var currentShoppingListID: UUID?
    @Published var selectedShoppingListID: UUID?
    @Published private(set) var currentProductLibraryIDs: [UUID] = []
    @Published var isTripMapMode = false
    @Published private(set) var nearbyOpportunities: [NearbyShoppingOpportunity] = []

    private let nearbyStoreSearchService = MapKitStoreSearchService()
    private let nearbyIntentMatcher = ShoppingIntentMatcher()
    private let storeRankingService = StoreRankingService()
    private let nearbyRadius: CLLocationDistance = 350
    private let maxNearbyOpportunities = 8
    private let nearbyDismissCooldown: TimeInterval = 15 * 60
    private let userDefaults = UserDefaults.standard
    private var nearbyRefreshGeneration = 0

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var visibleNearbyOpportunity: NearbyShoppingOpportunity? {
        nearbyOpportunities.first { !isNearbyOpportunityDismissed($0) }
    }

    var storeSuggestionRequest: ShoppingStoreSuggestionRequest? {
        shoppingPlan?.request
    }

    var buyingOptions: [BuyingOption] {
        shoppingPlan?.buyingOptions ?? []
    }

    var shoppingTripCoverages: [StoreCoverage] {
        shoppingPlan?.shoppingTripCoverages ?? []
    }

    var hasNearbyOpportunityBadge: Bool {
        visibleNearbyOpportunity != nil
    }

    func focusMap(on locationID: UUID) {
        isTripMapMode = false
        selectedTab = .map
        focusedLocationID = locationID
    }

    func shoppingListDidChange(revealing itemID: UUID? = nil) {
        recentlyAddedShoppingItemID = itemID
        shoppingListRevision = UUID()
    }

    func setCurrentShoppingList(_ listID: UUID?) {
        currentShoppingListID = listID

        if selectedShoppingListID == nil {
            selectedShoppingListID = listID
        }
    }

    func setCurrentProductLibrary(_ products: [Product]) {
        currentProductLibraryIDs = products
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    func suggestStores(
        for request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem] = [],
        stores: [MapStore] = [],
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        setShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
        isTripMapMode = false
        selectedTab = .map
    }

    func showTripOnMap(
        for request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem] = [],
        stores: [MapStore] = [],
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        setShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
        isTripMapMode = true
        selectedTab = .map
    }

    func setShoppingPlan(
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage]
    ) {
        let nextPlan = ShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )

        if shoppingPlan?.contentSignature == nextPlan.contentSignature {
            markShoppingPlanReady(generatedAt: shoppingPlan?.generatedAt ?? Date())
            return
        }

        shoppingPlan = nextPlan
        markShoppingPlanReady(generatedAt: nextPlan.generatedAt)
    }

    func clearShoppingPlan() {
        shoppingPlan = nil
        shoppingPlanState = .idle
    }

    func beginShoppingPlanGeneration(stage: ShoppingPlanGenerationStage = .preparingList) {
        shoppingPlanState = .generating(stage: stage, startedAt: Date())
    }

    func updateShoppingPlanGeneration(stage: ShoppingPlanGenerationStage) {
        let startedAt = shoppingPlanState.startedAt ?? Date()
        shoppingPlanState = .generating(stage: stage, startedAt: startedAt)
    }

    func markShoppingPlanReady(generatedAt: Date = Date()) {
        shoppingPlanState = .ready(generatedAt: generatedAt)
    }

    func markShoppingPlanFailed(message: String, actionTitle: String? = "Try Again") {
        shoppingPlan = nil
        shoppingPlanState = .failed(message: message, actionTitle: actionTitle)
    }

    func markShoppingPlanStale(reason: String) {
        shoppingPlan = nil
        shoppingPlanState = .stale(reason: reason)
    }

    func openShoppingNotificationOnMap(storeID: UUID?, locationID: UUID?) {
        navigationPath = NavigationPath()
        clearShoppingPlan()
        isTripMapMode = true
        focusedLocationID = locationID ?? storeID
        selectedTab = .map
    }

    func dismissNearbyOpportunity(_ opportunity: NearbyShoppingOpportunity) {
        let dismissUntil = Date().addingTimeInterval(nearbyDismissCooldown)
        userDefaults.set(dismissUntil.timeIntervalSince1970, forKey: dismissalKey(for: opportunity))
        objectWillChange.send()
    }

    func openNearbyOpportunityOnMap(_ opportunity: NearbyShoppingOpportunity) {
        guard let locationID = opportunity.locationID else {
            focusedLocationID = nil
            selectedTab = .map
            return
        }

        focusMap(on: locationID)
    }

    func refreshNearbyOpportunities(
        items: [ShoppingItem],
        savedLocations: [GeoLocation],
        currentCoordinate: CLLocationCoordinate2D?
    ) async {
        nearbyRefreshGeneration += 1
        let refreshGeneration = nearbyRefreshGeneration

        guard let currentCoordinate else {
            nearbyOpportunities = []
            return
        }

        let activeItems = items.filter { !$0.isCompleted }
        guard !activeItems.isEmpty else {
            nearbyOpportunities = []
            return
        }

        let activeGroups = nearbyIntentMatcher.groupedIntents(for: activeItems)
        ShoppingDiscoveryDebugLogger.logGroups(
            context: "Nearby",
            groups: activeGroups
        )
        let visibleSavedLocations = savedLocations.filter(shouldIncludeLocationInNearbyResults)
        let savedOpportunities = nearbySavedOpportunities(
            for: activeItems,
            savedLocations: visibleSavedLocations,
            currentCoordinate: currentCoordinate
        )
        let mapStores = await nearbyStoresByGroup(
            activeGroups,
            around: currentCoordinate,
        )

        guard refreshGeneration == nearbyRefreshGeneration else {
            return
        }

        let mapOpportunities = nearbyMapOpportunities(
            from: mapStores,
            activeItems: activeItems,
            currentCoordinate: currentCoordinate
        )

        nearbyOpportunities = deduplicatedNearbyOpportunities(savedOpportunities + mapOpportunities)
            .sorted { lhs, rhs in
                if lhs.realityScore == rhs.realityScore {
                    return lhs.distanceMeters < rhs.distanceMeters
                }

                return lhs.realityScore > rhs.realityScore
            }
            .prefixArray(maxNearbyOpportunities)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        await MainActor.run {
            let storeID = (userInfo["storeID"] as? String).flatMap(UUID.init(uuidString:))
            let locationID = (userInfo["geoLocationID"] as? String).flatMap(UUID.init(uuidString:))

            openShoppingNotificationOnMap(storeID: storeID, locationID: locationID)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func nearbySavedOpportunities(
        for activeItems: [ShoppingItem],
        savedLocations: [GeoLocation],
        currentCoordinate: CLLocationCoordinate2D
    ) -> [NearbyShoppingOpportunity] {
        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let activeItemIDs = Set(activeItems.map(\.id))
        let activeItemNames = Set(activeItems.map { $0.name.lowercased() })

        return savedLocations.compactMap { location in
            let directlyMatchedItems = location.shoppingItems.filter { item in
                !item.isCompleted && (activeItemIDs.contains(item.id) || activeItemNames.contains(item.name.lowercased()))
            }
            let categoryMatchedItems = activeItems.filter { item in
                guard let storeCategory = location.storeCategory else {
                    return false
                }

                let itemCategories = nearbyIntentMatcher.matchStoreCategories(for: item)
                return itemCategories.contains { $0.matches(storeCategory) }
            }
            let matchingItems = directlyMatchedItems.isEmpty ? categoryMatchedItems : directlyMatchedItems

            guard !matchingItems.isEmpty else {
                return nil
            }

            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let storeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = userLocation.distance(from: storeLocation)

            let store = MapStore(
                id: location.id,
                locationID: location.id,
                title: location.title,
                coordinate: coordinate,
                radius: location.radius,
                itemNames: notificationItemNames(from: matchingItems),
                completedItemNames: [],
                isOpen: true,
                rating: nil,
                storeCategories: location.storeCategory.map { [$0] } ?? [],
                queryEvidenceCategories: [],
                websiteURL: nil,
                sourceType: location.sourceType
            )
            let groupMatchedItems = nearbyIntentMatcher.relevantItems(from: activeItems, for: store)
            guard !groupMatchedItems.isEmpty else {
                return nil
            }
            let groupItemNames = notificationItemNames(from: groupMatchedItems)
            let groupCategories = matchedStoreCategories(for: groupMatchedItems)
            let groupRequest = nearbyRealityRequest(
                itemNames: groupItemNames,
                categories: groupCategories,
                fallbackID: location.id
            )
            let groupedStore = MapStore(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: store.radius,
                itemNames: groupItemNames,
                completedItemNames: store.completedItemNames,
                isOpen: store.isOpen,
                rating: store.rating,
                storeCategories: store.storeCategories,
                queryEvidenceCategories: store.queryEvidenceCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
            guard storeRankingService.isRelevant(
                store: groupedStore,
                request: groupRequest,
                userCoordinate: currentCoordinate
            ) else {
                return nil
            }

            guard distance <= nearbyRadius else {
                return nil
            }

            let ranking = storeRankingService.score(
                store: groupedStore,
                request: groupRequest,
                userCoordinate: currentCoordinate,
                coverage: StoreRealityCoverage(
                    matchedItemCount: groupMatchedItems.count,
                    totalItemCount: groupMatchedItems.count
                )
            )

            return NearbyShoppingOpportunity(
                id: "saved-\(location.id.uuidString)",
                storeID: location.id,
                locationID: location.id,
                title: location.title,
                itemNames: groupedStore.itemNames,
                sourceType: location.sourceType.rawValue,
                distanceMeters: distance,
                realityScore: ranking.score,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                detectedAt: Date()
            )
        }
    }

    private func nearbyStoresByGroup(
        _ groups: [ShoppingIntentGroupResult],
        around coordinate: CLLocationCoordinate2D
    ) async -> [MapStore] {
        var stores: [MapStore] = []

        let requests = groups.map { group in
            (request: group.request, itemNames: group.itemNames)
        }
        ShoppingDiscoveryDebugLogger.logStoreSearchRequests(
            context: "Nearby",
            groups: groups,
            requests: requests
        )

        for group in groups {
            let groupStores = await nearbyStoreSearchService.stores(
                around: coordinate,
                shoppingItems: group.itemNames,
                storeCategories: group.request.storeCategories
            )
            stores.append(contentsOf: groupStores)
        }

        return deduplicatedStores(stores)
    }

    private func shouldIncludeLocationInNearbyResults(_ location: GeoLocation) -> Bool {
        guard location.sourceType == .debugSeed else {
            return true
        }

        #if DEBUG
        return DebugSeedStoreService.isEnabled
        #else
        return false
        #endif
    }

    private func nearbyMapOpportunities(
        from stores: [MapStore],
        activeItems: [ShoppingItem],
        currentCoordinate: CLLocationCoordinate2D
    ) -> [NearbyShoppingOpportunity] {
        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)

        return stores.compactMap { store in
            let matchingItems = nearbyIntentMatcher.relevantItems(from: activeItems, for: store)
            guard !matchingItems.isEmpty else {
                return nil
            }

            let itemNames = notificationItemNames(from: matchingItems)
            let requestedCategories = matchedStoreCategories(for: matchingItems)
            let request = nearbyRealityRequest(
                itemNames: itemNames,
                categories: requestedCategories,
                fallbackID: store.id
            )
            let groupedStore = MapStore(
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
            let storeLocation = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude)
            let distance = userLocation.distance(from: storeLocation)

            guard storeRankingService.isRelevant(
                store: groupedStore,
                request: request,
                userCoordinate: currentCoordinate
            ) else {
                return nil
            }

            guard distance <= nearbyRadius else {
                return nil
            }

            let ranking = storeRankingService.score(
                store: groupedStore,
                request: request,
                userCoordinate: currentCoordinate,
                coverage: StoreRealityCoverage(
                    matchedItemCount: matchingItems.count,
                    totalItemCount: matchingItems.count
                )
            )

            return NearbyShoppingOpportunity(
                id: stableOpportunityID(for: store),
                storeID: store.locationID ?? store.id,
                locationID: store.locationID,
                title: store.title,
                itemNames: groupedStore.itemNames,
                sourceType: store.sourceType.rawValue,
                distanceMeters: distance,
                realityScore: ranking.score,
                latitude: store.coordinate.latitude,
                longitude: store.coordinate.longitude,
                detectedAt: Date()
            )
        }
    }

    private func nearbyRealityRequest(
        itemNames: [String],
        categories: [ShoppingStoreCategory],
        fallbackID: UUID
    ) -> ShoppingStoreSuggestionRequest {
        let itemName = itemNames.first ?? "Shopping list"
        return ShoppingStoreSuggestionRequest(
            itemID: fallbackID,
            itemName: itemName,
            itemCategory: nil,
            storeCategories: categories,
            searchTerms: itemNames,
            intentProfile: nil
        )
    }

    private func stableOpportunityID(for store: MapStore) -> String {
        if let locationID = store.locationID {
            return "saved-\(locationID.uuidString)"
        }

        let latitude = Int((store.coordinate.latitude * 100_000).rounded())
        let longitude = Int((store.coordinate.longitude * 100_000).rounded())
        return "\(store.sourceType.rawValue)-\(store.title.lowercased())-\(latitude)-\(longitude)"
    }

    private func matchedStoreCategories(for items: [ShoppingItem]) -> [ShoppingStoreCategory] {
        let categories = items.flatMap { nearbyIntentMatcher.matchStoreCategories(for: $0) }
        let uniqueCategories = Array(Set(categories))
        return uniqueCategories.sorted { $0.displayName < $1.displayName }
    }

    private func notificationItemNames(from items: [ShoppingItem]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()

            guard !name.isEmpty, !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            names.append(name)

            if names.count == 3 {
                break
            }
        }

        return names
    }

    private func deduplicatedNearbyOpportunities(_ opportunities: [NearbyShoppingOpportunity]) -> [NearbyShoppingOpportunity] {
        var result: [NearbyShoppingOpportunity] = []

        for opportunity in opportunities {
            let isDuplicate = result.contains { existing in
                existing.id == opportunity.id ||
                existing.title.localizedCaseInsensitiveCompare(opportunity.title) == .orderedSame ||
                distance(from: existing.coordinate, to: opportunity.coordinate) < 35
            }

            if !isDuplicate {
                result.append(opportunity)
            }
        }

        return result
    }

    private func deduplicatedStores(_ stores: [MapStore]) -> [MapStore] {
        var result: [MapStore] = []

        for store in stores {
            let isDuplicate = result.contains { existing in
                existing.title.localizedCaseInsensitiveCompare(store.title) == .orderedSame ||
                distance(from: existing.coordinate, to: store.coordinate) < 35
            }

            if !isDuplicate {
                result.append(store)
            }
        }

        return result
    }

    private func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func isNearbyOpportunityDismissed(_ opportunity: NearbyShoppingOpportunity) -> Bool {
        let dismissedUntil = userDefaults.double(forKey: dismissalKey(for: opportunity))

        guard dismissedUntil > 0 else {
            return false
        }

        return Date().timeIntervalSince1970 < dismissedUntil
    }

    private func dismissalKey(for opportunity: NearbyShoppingOpportunity) -> String {
        "waytask.nearbyOpportunity.dismissedUntil.\(opportunity.id)"
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
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
