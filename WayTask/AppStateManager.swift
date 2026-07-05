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

enum AppTab: Hashable {
    case products
    case camera
    case discover
    case map
}

struct NearbyShoppingOpportunity: Identifiable, Equatable {
    let id: String
    let storeID: UUID?
    let locationID: UUID?
    let title: String
    let itemNames: [String]
    let sourceType: String
    let distanceMeters: CLLocationDistance
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

final class AppStateManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var selectedTab: AppTab = .products
    @Published var navigationPath = NavigationPath()
    @Published var focusedLocationID: UUID?
    @Published var shoppingListRevision = UUID()
    @Published var recentlyAddedShoppingItemID: UUID?
    @Published var storeSuggestionRequest: ShoppingStoreSuggestionRequest?
    @Published var buyingOptions: [BuyingOption] = []
    @Published var shoppingTripCoverages: [StoreCoverage] = []
    @Published var isTripMapMode = false
    @Published private(set) var nearbyOpportunities: [NearbyShoppingOpportunity] = []

    private let nearbyStoreSearchService = MapKitStoreSearchService()
    private let nearbyIntentMatcher = ShoppingIntentMatcher()
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

    func suggestStores(
        for request: ShoppingStoreSuggestionRequest,
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        storeSuggestionRequest = request
        self.buyingOptions = buyingOptions
        self.shoppingTripCoverages = shoppingTripCoverages
        isTripMapMode = false
        selectedTab = .map
    }

    func showTripOnMap(
        for request: ShoppingStoreSuggestionRequest,
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        storeSuggestionRequest = request
        self.buyingOptions = buyingOptions
        self.shoppingTripCoverages = shoppingTripCoverages
        isTripMapMode = true
        selectedTab = .map
    }

    func openShoppingNotificationOnMap(storeID: UUID?, locationID: UUID?) {
        navigationPath = NavigationPath()
        storeSuggestionRequest = nil
        buyingOptions = []
        shoppingTripCoverages = []
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

        let activeItemNames = notificationItemNames(from: activeItems)
        let categories = matchedStoreCategories(for: activeItems)
        let visibleSavedLocations = savedLocations.filter(shouldIncludeLocationInNearbyResults)
        let savedOpportunities = nearbySavedOpportunities(
            for: activeItems,
            savedLocations: visibleSavedLocations,
            currentCoordinate: currentCoordinate
        )
        let mapStores = await nearbyStoreSearchService.stores(
            around: currentCoordinate,
            shoppingItems: activeItemNames,
            storeCategories: categories
        )

        guard refreshGeneration == nearbyRefreshGeneration else {
            return
        }

        let mapOpportunities = nearbyMapOpportunities(
            from: mapStores,
            itemNames: activeItemNames,
            requestedCategories: categories,
            currentCoordinate: currentCoordinate
        )

        nearbyOpportunities = deduplicatedNearbyOpportunities(savedOpportunities + mapOpportunities)
            .sorted { $0.distanceMeters < $1.distanceMeters }
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
                return itemCategories.contains { $0.matches(storeCategory) } || itemCategories.contains(.generalStore)
            }
            let matchingItems = directlyMatchedItems.isEmpty ? categoryMatchedItems : directlyMatchedItems

            guard !matchingItems.isEmpty else {
                return nil
            }

            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let storeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = userLocation.distance(from: storeLocation)

            let itemCategories = matchedStoreCategories(for: matchingItems)
            guard ShoppingStoreCategoryFilter.isEligible(
                storeTitle: location.title,
                storeCategories: location.storeCategory.map { [$0] } ?? [],
                requestedCategories: itemCategories,
                distanceMeters: distance
            ) else {
                return nil
            }

            guard distance <= nearbyRadius else {
                return nil
            }

            return NearbyShoppingOpportunity(
                id: "saved-\(location.id.uuidString)",
                storeID: location.id,
                locationID: location.id,
                title: location.title,
                itemNames: notificationItemNames(from: matchingItems),
                sourceType: location.sourceType.rawValue,
                distanceMeters: distance,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                detectedAt: Date()
            )
        }
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
        itemNames: [String],
        requestedCategories: [ShoppingStoreCategory],
        currentCoordinate: CLLocationCoordinate2D
    ) -> [NearbyShoppingOpportunity] {
        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)

        return stores.compactMap { store in
            let storeLocation = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude)
            let distance = userLocation.distance(from: storeLocation)

            guard ShoppingStoreCategoryFilter.isEligible(
                storeTitle: store.title,
                storeCategories: store.storeCategories,
                requestedCategories: requestedCategories,
                distanceMeters: distance
            ) else {
                return nil
            }

            guard distance <= nearbyRadius else {
                return nil
            }

            return NearbyShoppingOpportunity(
                id: stableOpportunityID(for: store),
                storeID: store.locationID ?? store.id,
                locationID: store.locationID,
                title: store.title,
                itemNames: store.itemNames.isEmpty ? itemNames : store.itemNames,
                sourceType: store.sourceType.rawValue,
                distanceMeters: distance,
                latitude: store.coordinate.latitude,
                longitude: store.coordinate.longitude,
                detectedAt: Date()
            )
        }
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
        return uniqueCategories.isEmpty ? [.generalStore] : uniqueCategories.sorted { $0.displayName < $1.displayName }
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
