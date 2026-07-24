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

    init() {
        SentryReportingService.shared.startIfConfigured()
        do {
            modelContainer = try WayTaskModelContainer.makeDefault()
        } catch {
            fatalError("Unable to open the WayTask data store: \(error.localizedDescription)")
        }
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
        .modelContainer(modelContainer)
    }
}
