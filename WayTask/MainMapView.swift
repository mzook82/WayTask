import MapKit
import SwiftData
import SwiftUI

struct MainMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appStateManager: AppStateManager

    @Query private var locations: [GeoLocation]

    @StateObject private var locationManager = LocationManager()
    @StateObject private var mapViewModel = MapViewModel()

    @State private var mapCenter = CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818)
    @State private var showingAddLocationSheet = false
    @State private var newLocationTitle = ""
    @State private var selectedRadius = 200.0

    var body: some View {
        NavigationStack(path: $appStateManager.navigationPath) {
            mapContent
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        closeMap()
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddLocationSheet) {
                addLocationSheet
            }
            .navigationDestination(for: GeoLocation.self) { location in
                LocationDetailView(location: location)
            }
            .navigationDestination(for: UUID.self) { locationID in
                if let location = locations.first(where: { $0.id == locationID }) {
                    LocationDetailView(location: location)
                } else {
                    ContentUnavailableView(
                        "Location not found",
                        systemImage: "mappin.slash",
                        description: Text("The saved location for this notification is no longer available.")
                    )
                }
            }
            .onAppear {
                locationManager.requestWhenInUseAuthorization()
                startMonitoringSavedLocations()
                mapViewModel.update(locations: locations)
                focusSelectedLocation()
            }
            .onChange(of: mapSignatures) {
                startMonitoringSavedLocations()
                mapViewModel.update(locations: locations)
            }
            .onChange(of: appStateManager.focusedLocationID) {
                focusSelectedLocation()
            }
        }
    }

    private var mapContent: some View {
        ZStack {
            mapLayer
            filterLayer
            bottomControlsLayer
        }
    }

    private var mapLayer: some View {
        WayTaskMapView(
            stores: mapViewModel.filteredStores,
            products: mapViewModel.filteredProducts,
            selectedStoreID: mapViewModel.selectedStoreID,
            cameraTarget: mapViewModel.cameraTarget,
            onSelectStore: selectStore,
            onMapCenterChanged: { center in
                mapCenter = center
            },
            onUserLocationChanged: { coordinate in
                mapViewModel.setUserCoordinate(coordinate)
            }
        )
        .ignoresSafeArea()
    }

    private var filterLayer: some View {
        VStack(spacing: 0) {
            MapFilterBar(
                searchText: $mapViewModel.searchText,
                selectedCategory: $mapViewModel.selectedCategory,
                shoppingListOnly: $mapViewModel.shoppingListOnly
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
    }

    private var bottomControlsLayer: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 14) {
                MapBottomSheet(
                    store: mapViewModel.selectedStore,
                    distanceText: selectedStoreDistanceText,
                    canOpenItems: mapViewModel.selectedStore?.isSavedLocation == true,
                    onNavigate: navigateToSelectedStore,
                    onWebsite: openSelectedStoreWebsite,
                    onOpenItems: openSelectedStoreItems
                )
                .frame(maxWidth: .infinity)

                MapControls(
                    onFollowUser: followUser,
                    onAddLocation: {
                        showingAddLocationSheet = true
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var addLocationSheet: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    TextField("Location title", text: $newLocationTitle)
                }

                Section("Radius") {
                    Picker("Preset", selection: $selectedRadius) {
                        Text("Walking").tag(150.0)
                        Text("Nearby").tag(300.0)
                        Text("Driving").tag(600.0)
                    }
                    .pickerStyle(.segmented)

                    Slider(value: $selectedRadius, in: 100...1000, step: 50)

                    Text("\(Int(selectedRadius)) meters")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetForm()
                        showingAddLocationSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLocation()
                    }
                    .disabled(newLocationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var selectedStoreDistanceText: String {
        guard let store = mapViewModel.selectedStore else {
            return ""
        }

        return mapViewModel.distanceText(for: store)
    }

    private var mapSignatures: [String] {
        locations.map { location in
            let itemSignature = location.shoppingItems
                .map { "\($0.id.uuidString)-\($0.name)-\($0.isCompleted)" }
                .joined(separator: ",")

            return "\(location.id.uuidString)-\(location.title)-\(location.latitude)-\(location.longitude)-\(location.radius)-\(itemSignature)"
        }
    }

    private func saveLocation() {
        let title = newLocationTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            return
        }

        let location = GeoLocation(
            title: title,
            latitude: mapCenter.latitude,
            longitude: mapCenter.longitude,
            radius: selectedRadius
        )

        modelContext.insert(location)
        try? modelContext.save()
        locationManager.startMonitoring(location: location)
        mapViewModel.update(locations: locations + [location])
        mapViewModel.selectStore(id: location.id)

        resetForm()
        showingAddLocationSheet = false
    }

    private func resetForm() {
        newLocationTitle = ""
        selectedRadius = 200.0
    }

    private func startMonitoringSavedLocations() {
        locationManager.startMonitoring(locations: locations)
    }

    private func focusSelectedLocation() {
        guard let focusedLocationID = appStateManager.focusedLocationID else {
            return
        }

        mapViewModel.update(locations: locations)
        mapViewModel.focusStore(id: focusedLocationID)
    }

    private func selectStore(_ storeID: UUID) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            mapViewModel.selectStore(id: storeID)
        }
    }

    private func followUser() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            mapViewModel.followUser()
        }
    }

    private func navigateToSelectedStore() {
        guard let store = mapViewModel.selectedStore else {
            return
        }

        mapViewModel.openInMaps(store: store)
    }

    private func openSelectedStoreWebsite() {
        guard let url = mapViewModel.selectedStore?.websiteURL else {
            return
        }

        openURL(url)
    }

    private func openSelectedStoreItems() {
        guard let locationID = mapViewModel.selectedStore?.locationID else {
            return
        }

        appStateManager.navigationPath.append(locationID)
    }

    private func closeMap() {
        if !appStateManager.navigationPath.isEmpty {
            appStateManager.navigationPath.removeLast()
            return
        }

        appStateManager.focusedLocationID = nil
        appStateManager.selectedTab = .products
    }
}
