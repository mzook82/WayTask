//
//  Untitled.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import Combine
import Foundation
import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case products
    case camera
    case discover
    case map
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

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        guard let idString = userInfo["geoLocationID"] as? String,
              let id = UUID(uuidString: idString) else {
            return
        }

        await MainActor.run {
            navigationPath = NavigationPath()
            focusMap(on: id)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
