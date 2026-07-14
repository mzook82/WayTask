//
//  WayTaskApp.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import SwiftUI
import SwiftData

@main
struct WayTaskApp: App {
    @StateObject private var appStateManager: AppStateManager
    @StateObject private var locationManager: LocationManager

    init() {
        SentryReportingService.shared.startIfConfigured()
        _appStateManager = StateObject(wrappedValue: AppStateManager())
        _locationManager = StateObject(wrappedValue: LocationManager())
        #if DEBUG
        print(SecretsManager.isGeminiConfigured ? "Gemini configured ✔" : "Gemini unavailable")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStateManager)
                .environmentObject(locationManager)
        }
        .modelContainer(for: [
            GeoLocation.self,
            ShoppingItem.self,
            Product.self,
            ShoppingList.self,
            ShoppingListEntry.self,
            ProductHistory.self,
            ProductKnowledge.self,
            ShoppingSession.self
        ])
    }
}
