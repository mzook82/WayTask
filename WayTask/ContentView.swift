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
            WayTaskFoundationPlaceholderView(
                title: "Home",
                subtitle: "Version 1.0 home surface is ready for implementation.",
                systemImage: "house.fill"
            )
            .tabItem {
                Label(AppTab.home.title, systemImage: AppTab.home.systemImageName)
            }
            .tag(AppTab.home)

            ProductListView()
                .tabItem {
                    Label(AppTab.products.title, systemImage: AppTab.products.systemImageName)
                }
                .tag(AppTab.products)

            WayTaskFoundationPlaceholderView(
                title: "Shopping",
                subtitle: "Shopping lists and planner migration will be implemented in a later sprint.",
                systemImage: "list.bullet.rectangle.fill"
            )
                .tabItem {
                    Label(AppTab.shopping.title, systemImage: AppTab.shopping.systemImageName)
                }
                .tag(AppTab.shopping)

            MainMapView()
                .tabItem {
                    Label(AppTab.map.title, systemImage: AppTab.map.systemImageName)
                }
                .tag(AppTab.map)

            WayTaskFoundationPlaceholderView(
                title: "Settings",
                subtitle: "Settings tab foundation is ready. Existing settings logic remains unchanged.",
                systemImage: "gearshape.fill"
            )
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.systemImageName)
            }
            .tag(AppTab.settings)
        }
        .tint(WayTaskDesign.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            seedDebugStoreIfNeeded()
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
        }
        .onChange(of: geofenceRefreshSignature) {
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            seedDebugStoreIfNeeded()
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
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

    private func refreshNearbyOpportunities() {
        Task {
            await appStateManager.refreshNearbyOpportunities(
                items: items,
                savedLocations: locations,
                currentCoordinate: locationManager.currentCoordinate
            )
        }
    }

    private func seedDebugStoreIfNeeded() {
        #if DEBUG
        guard DebugSeedStoreService.isEnabled else {
            return
        }

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

private struct WayTaskFoundationPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(spacing: WayTaskDesign.Spacing.xl) {
                    WayTaskNavigationBar(title: title, subtitle: "Foundation")

                    Spacer(minLength: WayTaskDesign.Spacing.lg)

                    WayTaskEmptyState(
                        title: title,
                        message: subtitle,
                        systemImage: systemImage
                    )
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)

                    Spacer(minLength: WayTaskDesign.Spacing.lg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
