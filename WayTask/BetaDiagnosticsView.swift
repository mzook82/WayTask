import CoreLocation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BetaSettingsEntryView: View {
    @AppStorage(BetaDiagnosticsCenter.developerModeKey) private var developerModeEnabled = false
    @State private var activationTapCount = 0

    var body: some View {
        Group {
            if developerModeEnabled {
                SettingsView(showsDoneButton: false)
            } else {
                WayTaskFoundationPlaceholderView(
                    title: "Settings",
                    subtitle: "Settings tab foundation is ready. Existing settings logic remains unchanged.",
                    systemImage: "gearshape.fill"
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    activationTapCount += 1
                    if activationTapCount >= 7 {
                        developerModeEnabled = true
                        activationTapCount = 0
                    }
                }
            }
        }
    }
}

struct BetaDiagnosticsView: View {
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager
    @ObservedObject private var diagnostics = BetaDiagnosticsCenter.shared

    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]
    @Query private var locations: [GeoLocation]

    @AppStorage(BetaDiagnosticsCenter.developerModeKey) private var developerModeEnabled = false
    @State private var exportFormat: BetaDiagnosticsExportFormat = .markdown
    @State private var exportDocument = BetaDiagnosticsTextDocument(text: "")
    @State private var isShowingExporter = false
    @State private var copyConfirmation = false

    var body: some View {
        List {
            snapshotSection
            plannerSection
            storeDiscoverySection
            notificationSection
            geofenceSection
            mapSection
            recognitionSection
            performanceSection
            recentErrorsSection
            recentDecisionsSection
            exportSection
            privacySection
            developerModeSection
        }
        .navigationTitle("Beta Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            synchronizeLivePlannerContext()
        }
        .onChange(of: liveContextSignature) {
            synchronizeLivePlannerContext()
        }
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: exportFormat.contentType,
            defaultFilename: exportFormat.filename
        ) { _ in }
        .alert("Report copied", isPresented: $copyConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }

    private var snapshotSection: some View {
        Section("Beta Snapshot") {
            Button {
                synchronizeLivePlannerContext()
                diagnostics.captureSnapshot(screenName: "Beta Diagnostics")
            } label: {
                Label("Capture Beta Snapshot", systemImage: "camera.viewfinder")
            }

            if let snapshot = diagnostics.lastSnapshot {
                LabeledContent("Captured", value: snapshot.timestamp.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Screen", value: snapshot.screenName)
                LabeledContent("Runtime state", value: "Bundled")
                LabeledContent("Screenshot export", value: "Excluded")

                if let image = snapshot.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Captured diagnostics screen")
                }
            }
        }
    }

    private var plannerSection: some View {
        Section("Planner") {
            diagnosticRow("ShoppingPlan State", diagnostics.planner.state)
            diagnosticRow("Current Shopping List", diagnostics.planner.shoppingListName)
            diagnosticRow("Shopping List ID", diagnostics.planner.shoppingListID?.uuidString ?? "Unavailable")
            diagnosticRow("Products in Shopping", "\(diagnostics.planner.productCount)")
            diagnosticRow("Needed Products", "\(diagnostics.planner.neededCount)")
            diagnosticRow("Checked Products", "\(diagnostics.planner.checkedCount)")
            diagnosticRow("Planner Status", diagnostics.planner.status)
            diagnosticRow("Planning Stage", diagnostics.planner.stage)
            diagnosticRow("Planning Time", durationText(diagnostics.planner.lastDuration))
            diagnosticRow("Elapsed Time", elapsedPlannerText)
            diagnosticRow("Last Failure Reason", diagnostics.planner.lastFailureReason)
            diagnosticRow("Coverage", percentText(diagnostics.planner.coveragePercent))
            diagnosticRow("Matched Products", listText(diagnostics.planner.matchedProducts))
            diagnosticRow("Rejected Products", listText(diagnostics.planner.rejectedProducts))
            diagnosticRow("Best Store", diagnostics.planner.bestStore)
            diagnosticRow("Selection Reasons", listText(diagnostics.planner.selectionReasons))
            diagnosticRow("Planner Cache Status", diagnostics.planner.cacheStatus)
        }
    }

    private var storeDiscoverySection: some View {
        Section("Store Discovery") {
            diagnosticRow("Saved Stores", "\(diagnostics.discovery.savedStores)")
            diagnosticRow("MapKit Stores", "\(diagnostics.discovery.mapKitStores)")
            diagnosticRow("Merged Stores", "\(diagnostics.discovery.mergedStores)")
            diagnosticRow("Accepted Stores", "\(diagnostics.discovery.acceptedStores)")
            diagnosticRow("Rejected Stores", "\(diagnostics.discovery.rejectedStores)")
            diagnosticRow("Deduplicated Stores", "\(diagnostics.discovery.deduplicatedStores)")
            diagnosticRow("Search Radius", "\(diagnostics.discovery.searchRadiusMeters)m")
            diagnosticRow("Cache", diagnostics.discovery.cacheStatus)
            diagnosticRow("Last Search", dateText(diagnostics.discovery.lastSearchTime))
            diagnosticRow("Current Coordinate", coordinateText(diagnostics.discovery.currentCoordinate))
            diagnosticRow("Discovery Duration", durationText(diagnostics.discovery.duration))

            ForEach(diagnostics.discovery.stores) { store in
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.title).font(.subheadline.weight(.semibold))
                    Text("\(store.source) · \(coordinateText(store.coordinate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !diagnostics.discovery.rejectionReasons.isEmpty {
                DisclosureGroup("Rejection reasons") {
                    ForEach(diagnostics.discovery.rejectionReasons, id: \.self) { reason in
                        Text(reason).font(.caption)
                    }
                }
            }

            DisclosureGroup("Source states") {
                Text("Saved · MapKit · Transient · Future Community · Future Merchant")
                    .font(.caption)
            }
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            diagnosticRow("Authorization", diagnostics.notification.authorizationStatus)
            diagnosticRow("Last Notification", diagnostics.notification.lastNotification)
            diagnosticRow("Notification Type", diagnostics.notification.notificationType)
            diagnosticRow("Notification Time", dateText(diagnostics.notification.notificationTime))
            diagnosticRow("Store", diagnostics.notification.store)
            diagnosticRow("Coordinate", coordinateText(diagnostics.notification.coordinate))
            diagnosticRow("Shopping List", diagnostics.notification.shoppingListID?.uuidString ?? "Unavailable")
            diagnosticRow("Matched Products", listText(diagnostics.notification.matchedProducts))
            diagnosticRow("Deep Link Status", diagnostics.notification.deepLinkStatus)
            diagnosticRow("Tap Result", diagnostics.notification.tapResult)
            diagnosticRow("Bottom Sheet Opened", diagnostics.notification.bottomSheetOpened ? "Yes" : "No")
            diagnosticRow("Decision Reason", diagnostics.notification.decisionReason)
        }
    }

    private var geofenceSection: some View {
        Section("Geofence") {
            diagnosticRow("Currently Monitored Regions", "\(diagnostics.geofence.regions.count)")
            diagnosticRow("Entered Region", diagnostics.geofence.enteredRegion)
            diagnosticRow("Exited Region", diagnostics.geofence.exitedRegion)
            diagnosticRow("Last Trigger", dateText(diagnostics.geofence.lastTrigger))
            diagnosticRow("Current Store", diagnostics.geofence.currentStore)
            diagnosticRow("Current Distance", distanceText(diagnostics.geofence.currentDistance))
            diagnosticRow("Last Suppression", diagnostics.geofence.lastSuppressionReason)

            ForEach(diagnostics.geofence.regions) { region in
                VStack(alignment: .leading, spacing: 3) {
                    Text(region.title).font(.subheadline.weight(.semibold))
                    Text("\(Int(region.radius))m · \(region.source) · \(coordinateText(region.coordinate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mapSection: some View {
        Section("Map") {
            diagnosticRow("User Coordinate", coordinateText(diagnostics.map.userCoordinate))
            diagnosticRow("Map Camera", coordinateText(diagnostics.map.cameraCenter))
            diagnosticRow("Focused Store", diagnostics.map.focusedStore)
            diagnosticRow("Selected Store", diagnostics.map.selectedStore)
            diagnosticRow("Visible Stores", "\(diagnostics.map.visibleStores.count)")
            diagnosticRow("Visible Circles", "\(diagnostics.map.visibleCircleCount)")
            diagnosticRow("Current Zoom", diagnostics.map.zoom.map { String(format: "%.2f", $0) } ?? "Unavailable")
            diagnosticRow("Current Region", diagnostics.map.regionDescription)
        }
    }

    private var recognitionSection: some View {
        Section("Gemini & Recognition") {
            diagnosticRow("Gemini Requests", "\(diagnostics.recognition.geminiRequests)")
            diagnosticRow("Gemini Success", "\(diagnostics.recognition.geminiSuccesses)")
            diagnosticRow("Gemini Failures", "\(diagnostics.recognition.geminiFailures)")
            diagnosticRow("Fallback Count", "\(diagnostics.recognition.fallbackCount)")
            diagnosticRow("Barcode Count", "\(diagnostics.recognition.barcodeCount)")
            diagnosticRow("OpenFoodFacts Count", "\(diagnostics.recognition.openFoodFactsCount)")
            diagnosticRow("Manual Products", "\(diagnostics.recognition.manualProducts)")
            diagnosticRow("Recognition Time", durationText(diagnostics.recognition.lastRecognitionDuration))
            diagnosticRow("Cache Hits", "\(diagnostics.recognition.cacheHits)")
            diagnosticRow("Cache Misses", "\(diagnostics.recognition.cacheMisses)")
            diagnosticRow("Estimated Monthly Gemini Requests", "\(diagnostics.recognition.estimatedMonthlyGeminiRequests)")
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            diagnosticRow("Average Generate Plan Time", durationText(diagnostics.averagePlanDuration))
            diagnosticRow("Average Discovery Time", durationText(diagnostics.averageDiscoveryDuration))
            diagnosticRow("ShoppingPlan Cache", diagnostics.planner.cacheStatus)
            diagnosticRow("Store Cache", diagnostics.discovery.cacheStatus)
            diagnosticRow("Memory Cache", "\(diagnostics.events.count) / 200 events")
            diagnosticRow("Current Build", diagnostics.buildNumber)
            diagnosticRow("App Version", diagnostics.appVersion)
            diagnosticRow("Device Model", diagnostics.deviceModel)
            diagnosticRow("iOS Version", diagnostics.osVersion)
        }
    }

    private var recentErrorsSection: some View {
        Section("Recent Errors") {
            if diagnostics.recentErrors.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics.recentErrors) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(event.category.rawValue): \(event.message)")
                            .font(.subheadline.weight(.semibold))
                        Text(event.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recentDecisionsSection: some View {
        Section("Recent Runtime Decisions") {
            if diagnostics.events.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics.events.prefix(50)) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(event.category.rawValue): \(event.message)")
                            .font(.subheadline.weight(.semibold))
                        Text(event.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var exportSection: some View {
        Section("Export Beta Diagnostics Report") {
            Picker("Format", selection: $exportFormat) {
                ForEach(BetaDiagnosticsExportFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)

            ShareLink(item: currentReport) {
                Label("Share Report", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = currentReport
                copyConfirmation = true
            } label: {
                Label("Copy Report", systemImage: "doc.on.doc")
            }

            Button {
                exportDocument = BetaDiagnosticsTextDocument(text: currentReport)
                isShowingExporter = true
            } label: {
                Label("Save Report", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("No product photos or screenshots are exported", systemImage: "photo.badge.checkmark")
            Label("No email, authentication, or API keys", systemImage: "key.slash")
            Label("No route history or private account data", systemImage: "location.slash")
        }
    }

    private var developerModeSection: some View {
        Section("Developer Mode") {
            Toggle("Enable Beta Diagnostics", isOn: $developerModeEnabled)
        }
    }

    private var currentReport: String {
        switch exportFormat {
        case .markdown:
            diagnostics.markdownReport()
        case .json:
            diagnostics.jsonReport()
        }
    }

    private var elapsedPlannerText: String {
        guard let startedAt = diagnostics.planner.startedAt,
              diagnostics.planner.state == "Generating" else {
            return durationText(diagnostics.planner.lastDuration)
        }
        return durationText(Date().timeIntervalSince(startedAt))
    }

    private var liveContextSignature: String {
        let planID = appStateManager.shoppingPlan?.id.uuidString ?? "none"
        let entrySignature = shoppingListEntries.map { "\($0.id)-\($0.isChecked)" }.sorted().joined()
        return "\(planID)#\(entrySignature)#\(appStateManager.selectedShoppingListID?.uuidString ?? "none")"
    }

    private func synchronizeLivePlannerContext() {
        let listID = appStateManager.selectedShoppingListID ?? appStateManager.currentShoppingListID
        let list = shoppingLists.first { $0.id == listID }
        let entries = shoppingListEntries.filter { $0.shoppingListID == listID }
        diagnostics.updatePlannerContext(
            listName: list?.title ?? "Unavailable",
            listID: listID,
            products: entries.count,
            needed: entries.filter { !$0.isChecked }.count,
            checked: entries.filter(\.isChecked).count
        )
        diagnostics.synchronizePlanner(
            plan: appStateManager.shoppingPlan,
            state: appStateManager.shoppingPlanState
        )
        diagnostics.synchronizeStoreSnapshot(
            stores: appStateManager.shoppingPlan?.stores ?? [],
            savedCount: locations.filter { $0.sourceType != .debugSeed }.count
        )
        locationManager.publishBetaDiagnostics()
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func durationText(_ value: TimeInterval?) -> String {
        value.map { String(format: "%.2fs", $0) } ?? "Unavailable"
    }

    private func percentText(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "Unavailable"
    }

    private func dateText(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .standard) ?? "Unavailable"
    }

    private func coordinateText(_ value: CLLocationCoordinate2D?) -> String {
        guard let value else { return "Unavailable" }
        return coordinateText(value)
    }

    private func coordinateText(_ value: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", value.latitude, value.longitude)
    }

    private func distanceText(_ value: CLLocationDistance?) -> String {
        value.map { "\(Int($0.rounded()))m" } ?? "Unavailable"
    }

    private func listText(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

private enum BetaDiagnosticsExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .json: .json
        }
    }

    var filename: String {
        "WayTask-Beta-Diagnostics.\(rawValue == "markdown" ? "md" : "json")"
    }
}

private struct BetaDiagnosticsTextDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "md") ?? .plainText, .plainText, .json]
    }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
