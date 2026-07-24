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
        do {
            let snapshot = try BundledProductKnowledgeLoader().load()
            let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)
            productKnowledgeSearchAvailability = .available(
                ProductKnowledgeSearch(repository: repository)
            )
        } catch {
            productKnowledgeSearchAvailability = .unavailable
            SentryReportingService.shared.capture(
                error: error,
                message: .productKnowledgeUnavailable,
                operation: .diagnostics,
                category: .operational,
                area: .products
            )
            #if DEBUG
            print("[WayTask Product Knowledge] Suggestions unavailable.")
            #endif
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
