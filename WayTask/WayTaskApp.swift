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
    private let modelContainer: ModelContainer
    private let productKnowledgeSearchAvailability: ProductKnowledgeSearchAvailability

    init() {
        SentryReportingService.shared.startIfConfigured()
        do {
            modelContainer = try WayTaskModelContainer.makeDefault()
        } catch {
            fatalError("Unable to open the WayTask data store: \(error.localizedDescription)")
        }
        _appStateManager = StateObject(wrappedValue: AppStateManager())
        _locationManager = StateObject(wrappedValue: LocationManager())
        let catalogProducts = ProductCatalogService().loadProductsOrEmpty()
        if catalogProducts.isEmpty {
            productKnowledgeSearchAvailability = .unavailable
            #if DEBUG
            print("[WayTask Product Catalog] Suggestions unavailable; custom entry remains enabled.")
            #endif
        } else {
            productKnowledgeSearchAvailability = .catalog(
                ProductCatalogSearch(products: catalogProducts)
            )
        }
        #if DEBUG
        print(SecretsManager.isGeminiConfigured ? "Gemini configured ✔" : "Gemini unavailable")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                productKnowledgeSearchAvailability: productKnowledgeSearchAvailability
            )
                .environmentObject(appStateManager)
                .environmentObject(locationManager)
        }
        .modelContainer(modelContainer)
    }
}
