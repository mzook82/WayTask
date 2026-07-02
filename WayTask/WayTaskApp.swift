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
    @StateObject private var appStateManager = AppStateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStateManager)
        }
        .modelContainer(for: [
            GeoLocation.self,
            ShoppingItem.self,
            ProductHistory.self,
            ShoppingSession.self
        ])
    }
}
