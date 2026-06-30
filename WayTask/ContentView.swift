//
//  ContentView.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStateManager: AppStateManager

    var body: some View {
        TabView(selection: $appStateManager.selectedTab) {
            ProductListView()
                .tabItem {
                    Label("Products", systemImage: "checklist")
                }
                .tag(AppTab.products)

            CameraView()
                .tabItem {
                    Label("Scan", systemImage: "camera")
                }
                .tag(AppTab.camera)

            MainMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(AppTab.map)
        }
    }
}

#Preview {
    ContentView()
}
