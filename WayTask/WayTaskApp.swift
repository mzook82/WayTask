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
    @StateObject private var onboardingCoordinator: OnboardingCoordinator
    @StateObject private var featureTourCoordinator: FeatureTourCoordinator
    private let modelContainer: ModelContainer?
    private let startupMigrationDecision:
        WayTaskStartupMigrationGateDecision
    private let productKnowledgeSearchAvailability: ProductKnowledgeSearchAvailability

    init() {
        SentryReportingService.shared.startIfConfigured()
        do {
            let result = try WayTaskStartupPersistenceBootstrap
                .live()
                .start()
            modelContainer = result.modelContainer
            startupMigrationDecision = result.migrationGateDecision
        } catch {
            modelContainer = nil
            startupMigrationDecision = WayTaskStartupMigrationGate()
                .unavailableDecision()
        }
        _appStateManager = StateObject(wrappedValue: AppStateManager())
        _locationManager = StateObject(wrappedValue: LocationManager())
        let onboardingCoordinator = OnboardingCoordinator()
        _onboardingCoordinator = StateObject(
            wrappedValue: onboardingCoordinator
        )
        _featureTourCoordinator = StateObject(
            wrappedValue: FeatureTourCoordinator(
                presentOnLaunch:
                    onboardingCoordinator.hasCompletedOnboarding
            )
        )
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
            if let modelContainer {
                startupRoot
                    .modelContainer(modelContainer)
            } else {
                WayTaskStartupMigrationGateView(
                    decision: startupMigrationDecision
                )
            }
        }
    }

    @ViewBuilder
    private var startupRoot: some View {
        if startupMigrationDecision.allowsLegacyV3ApplicationContent {
            Group {
                if onboardingCoordinator.isPresented {
                    OnboardingFlowView(
                        onSkip: {
                            onboardingCoordinator.complete()
                            featureTourCoordinator.skip()
                        },
                        onComplete: {
                            featureTourCoordinator.start()
                            onboardingCoordinator.complete()
                        }
                    )
                } else {
                    ContentView(
                        productKnowledgeSearchAvailability:
                            productKnowledgeSearchAvailability
                    )
                }
            }
            .environmentObject(appStateManager)
            .environmentObject(locationManager)
            .environmentObject(featureTourCoordinator)
        } else {
            WayTaskStartupMigrationGateView(
                decision: startupMigrationDecision
            )
        }
    }
}
