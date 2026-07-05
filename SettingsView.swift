import AppIntents
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var locations: [GeoLocation]
    @Query private var productKnowledge: [ProductKnowledge]
    @State private var isShowingStoreEditor = false
    @State private var editingStore: GeoLocation?
    #if DEBUG
    @AppStorage(DebugSeedStoreService.enabledUserDefaultsKey) private var isDebugStoreEnabled = false
    #endif

    private var customStores: [GeoLocation] {
        locations
            .filter { $0.sourceType == .userGenerated || $0.sourceType == .debugSeed }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                List {
                    customStoresSection
                    notificationsSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .tint(WayTaskDesign.accent)
                }
            }
            .sheet(isPresented: $isShowingStoreEditor) {
                CustomStoreEditorView(
                    store: editingStore,
                    currentCoordinate: locationManager.currentCoordinate
                )
                .environmentObject(locationManager)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var customStoresSection: some View {
        Section {
            Button {
                editingStore = nil
                isShowingStoreEditor = true
            } label: {
                Label("Add Custom Store", systemImage: "plus.circle.fill")
                    .foregroundStyle(WayTaskDesign.accent)
            }

            if customStores.isEmpty {
                Text("Custom stores you add here will appear in Map, Buying Options, Shopping Trip, and nearby notifications.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customStores) { store in
                    customStoreRow(store)
                }
                .onDelete(perform: deleteStores)
            }
        } header: {
            Text("Custom Stores")
        } footer: {
            Text("Use this for real stores that do not appear in Apple Maps. Coordinates are required for map and notification support.")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Label("Nearby shopping reminders use saved store coordinates and active shopping items.", systemImage: "bell.badge")
                .font(.subheadline)

            Button("Request Notification Permission") {
                GeofenceNotificationService().requestAuthorizationIfNeeded()
            }
            .foregroundStyle(WayTaskDesign.accent)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("App name", value: "WayTask")
            LabeledContent("Version", value: "1.8 Beta")
            LabeledContent("AI", value: "Gemini Vision")
            LabeledContent("Product Knowledge", value: "Enabled")
            LabeledContent("Learned products", value: "\(productKnowledge.count)")
            LabeledContent("Store sources", value: "Saved, Apple Maps, fallback")
            LabeledContent("Custom stores", value: "\(customStores.filter { $0.sourceType == .userGenerated }.count)")

            #if DEBUG
            Toggle("Debug Store", isOn: $isDebugStoreEnabled)
            LabeledContent("Debug seed", value: customStores.contains { $0.sourceType == .debugSeed } ? "Enabled" : "Not seeded")
            #endif
        } header: {
            Text("About WayTask")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("WayTask remembers confirmed products on this device to make future scans faster.")
                Text("Product Knowledge is stored locally on this device.")
            }
        }
    }

    private func customStoreRow(_ store: GeoLocation) -> some View {
        Button {
            guard store.sourceType == .userGenerated else {
                return
            }

            editingStore = store
            isShowingStoreEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(store.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if store.sourceType == .debugSeed {
                        Text("DEBUG")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WayTaskDesign.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(WayTaskDesign.accent.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text(store.storeCategory?.displayName ?? "Store")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let address = store.addressText?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .disabled(store.sourceType == .debugSeed)
    }

    private func deleteStores(at offsets: IndexSet) {
        let deletableStores = customStores
        for index in offsets {
            let store = deletableStores[index]
            guard store.sourceType == .userGenerated else {
                continue
            }

            modelContext.delete(store)
        }

        try? modelContext.save()
    }
}

private struct CustomStoreEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let store: GeoLocation?
    let currentCoordinate: CLLocationCoordinate2D?

    @State private var storeName: String
    @State private var selectedCategory: ShoppingStoreCategory
    @State private var useCurrentLocation: Bool
    @State private var addressText: String
    @State private var notes: String
    @State private var radius: Double
    @State private var errorMessage: String?
    @State private var isResolvingAddress = false

    init(store: GeoLocation?, currentCoordinate: CLLocationCoordinate2D?) {
        self.store = store
        self.currentCoordinate = currentCoordinate
        _storeName = State(initialValue: store?.title ?? "")
        _selectedCategory = State(initialValue: store?.storeCategory ?? .generalStore)
        _useCurrentLocation = State(initialValue: store == nil)
        _addressText = State(initialValue: store?.addressText ?? "")
        _notes = State(initialValue: store?.notes ?? "")
        _radius = State(initialValue: store?.radius ?? 200)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Store") {
                    TextField("Store name", text: $storeName)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ShoppingStoreCategory.allCases) { category in
                            Text(category.storeFormTitle).tag(category)
                        }
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Location") {
                    Toggle("Use current location", isOn: $useCurrentLocation)

                    TextField("Address optional", text: $addressText, axis: .vertical)
                        .lineLimit(1...3)

                    Text(locationHelpText)
                        .font(.caption)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }

                Section("Radius") {
                    Picker("Preset", selection: $radius) {
                        Text("Walking").tag(150.0)
                        Text("Nearby").tag(300.0)
                        Text("Driving").tag(600.0)
                    }
                    .pickerStyle(.segmented)

                    Slider(value: $radius, in: 100...1000, step: 50)
                    Text("\(Int(radius)) meters")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store == nil ? "Add Store" : "Edit Store")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isResolvingAddress ? "Saving..." : "Save") {
                        saveStore()
                    }
                    .disabled(!canSave || isResolvingAddress)
                }
            }
        }
    }

    private var canSave: Bool {
        !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var locationHelpText: String {
        if let errorMessage {
            return errorMessage
        }

        if useCurrentLocation {
            return currentCoordinate == nil
                ? "Waiting for current location. You can enter an address, but coordinates are required for map and notifications."
                : "Saves this store at your current location."
        }

        return "Enter an address so WayTask can resolve coordinates for map and notification support."
    }

    private func saveStore() {
        errorMessage = nil
        isResolvingAddress = true

        Task {
            do {
                let coordinate = try await resolveCoordinate()
                try await MainActor.run {
                    try persistStore(coordinate: coordinate)
                    isResolvingAddress = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Unable to save this store. Use current location or enter a more specific address, then try again."
                    isResolvingAddress = false
                }
            }
        }
    }

    private func resolveCoordinate() async throws -> CLLocationCoordinate2D {
        if useCurrentLocation, let currentCoordinate {
            return currentCoordinate
        }

        let trimmedAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAddress.isEmpty {
            if let request = MKGeocodingRequest(addressString: trimmedAddress) {
                let mapItems = try await request.mapItems
                if let coordinate = mapItems.first?.location.coordinate {
                    return coordinate
                }
            }
        }

        if let store, !useCurrentLocation {
            return CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude)
        }

        throw CustomStoreEditorError.coordinateUnavailable
    }

    private func persistStore(coordinate: CLLocationCoordinate2D) throws {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let store {
            store.title = name
            store.latitude = coordinate.latitude
            store.longitude = coordinate.longitude
            store.radius = radius
            store.storeCategory = selectedCategory
            store.addressText = trimmedAddress.isEmpty ? nil : trimmedAddress
            store.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            store.sourceType = .userGenerated
        } else {
            let newStore = GeoLocation(
                title: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: radius,
                storeCategory: selectedCategory,
                addressText: trimmedAddress.isEmpty ? nil : trimmedAddress,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                sourceType: .userGenerated
            )
            modelContext.insert(newStore)
        }

        try modelContext.save()
    }
}

private enum CustomStoreEditorError: Error {
    case coordinateUnavailable
}
