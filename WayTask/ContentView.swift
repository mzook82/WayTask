//
//  ContentView.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import CoreLocation
import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var items: [ShoppingItem]
    @Query private var locations: [GeoLocation]
    @Query private var shoppingSessions: [ShoppingSession]

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

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkle.magnifyingglass")
                }
                .tag(AppTab.discover)

            MainMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(AppTab.map)
        }
        .onAppear {
            seedDebugStoreIfNeeded()
            refreshShoppingGeofences()
        }
        .onChange(of: geofenceRefreshSignature) {
            refreshShoppingGeofences()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            seedDebugStoreIfNeeded()
            refreshShoppingGeofences()
            locationManager.checkSmartNearbyDetection(reason: "app active")
        }
    }

    private var geofenceRefreshSignature: String {
        let itemSignature = items
            .filter { !$0.isCompleted }
            .map { item in
                "\(item.id.uuidString)-\(item.name)-\(item.category ?? "")-\(item.isCompleted)"
            }
            .sorted()
            .joined(separator: "|")

        let locationSignature = locations
            .map { location in
                let locationItemSignature = location.shoppingItems
                    .filter { !$0.isCompleted }
                    .map { "\($0.id.uuidString)-\($0.name)" }
                    .sorted()
                    .joined(separator: ",")

                return "\(location.id.uuidString)-\(location.title)-\(location.latitude)-\(location.longitude)-\(location.radius)-\(location.storeCategoryRawValue ?? "")-\(location.addressText ?? "")-\(location.notes ?? "")-\(locationItemSignature)"
            }
            .sorted()
            .joined(separator: "|")

        let sessionSignature = shoppingSessions
            .map { session in
                "\(session.id.uuidString)-\(session.isActive)-\(session.finishedAt?.timeIntervalSince1970 ?? 0)-\(session.collectedItemIDListRawValue)"
            }
            .sorted()
            .joined(separator: "|")

        let coordinateSignature: String
        if let coordinate = locationManager.currentCoordinate {
            let latitudeBucket = Int((coordinate.latitude * 2_000).rounded())
            let longitudeBucket = Int((coordinate.longitude * 2_000).rounded())
            coordinateSignature = "\(latitudeBucket)-\(longitudeBucket)"
        } else {
            coordinateSignature = "no-location"
        }

        return "\(itemSignature)#\(locationSignature)#\(sessionSignature)#\(coordinateSignature)"
    }

    private func refreshShoppingGeofences() {
        locationManager.refreshShoppingGeofences(items: items, savedLocations: locations)
    }

    private func seedDebugStoreIfNeeded() {
        #if DEBUG
        DebugSeedStoreService().ensureSeedStore(
            near: locationManager.currentCoordinate,
            in: modelContext
        )
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStateManager())
        .environmentObject(LocationManager())
}
