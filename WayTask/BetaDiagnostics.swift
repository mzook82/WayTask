import Combine
import CoreLocation
import Foundation
import MapKit
import UIKit

enum BetaDiagnosticCategory: String, CaseIterable {
    case planner = "Planner"
    case storeDiscovery = "Store Discovery"
    case notification = "Notifications"
    case geofence = "Geofence"
    case map = "Map"
    case recognition = "Gemini"
    case performance = "Performance"
}

struct BetaDiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: BetaDiagnosticCategory
    let message: String
    let detail: String
    let isError: Bool
}

struct BetaDiagnosticStore: Identifiable, Hashable {
    let id: UUID
    let title: String
    let source: String
    let coordinate: CLLocationCoordinate2D
    let itemNames: [String]

    static func == (lhs: BetaDiagnosticStore, rhs: BetaDiagnosticStore) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.source == rhs.source
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(source)
    }
}

struct BetaPlannerDiagnostics {
    var state = "Idle"
    var shoppingListName = "Unavailable"
    var shoppingListID: UUID?
    var productCount = 0
    var neededCount = 0
    var checkedCount = 0
    var status = "Not started"
    var stage = "None"
    var startedAt: Date?
    var lastDuration: TimeInterval?
    var lastFailureReason = "None"
    var coveragePercent: Double?
    var matchedProducts: [String] = []
    var rejectedProducts: [String] = []
    var bestStore = "None"
    var selectionReasons: [String] = []
    var cacheStatus = "Unknown"
}

struct BetaStoreDiscoveryDiagnostics {
    var savedStores = 0
    var mapKitStores = 0
    var mergedStores = 0
    var acceptedStores = 0
    var rejectedStores = 0
    var deduplicatedStores = 0
    var searchRadiusMeters = 3_000
    var cacheStatus = "No search"
    var lastSearchTime: Date?
    var currentCoordinate: CLLocationCoordinate2D?
    var duration: TimeInterval?
    var stores: [BetaDiagnosticStore] = []
    var rejectionReasons: [String] = []
    var activeSearchStartedAt: Date?
}

struct BetaNotificationDiagnostics {
    var authorizationStatus = "Unknown"
    var lastNotification = "None"
    var notificationType = "None"
    var notificationTime: Date?
    var store = "None"
    var coordinate: CLLocationCoordinate2D?
    var shoppingListID: UUID?
    var matchedProducts: [String] = []
    var deepLinkStatus = "Not attempted"
    var tapResult = "Not tapped"
    var bottomSheetOpened = false
    var decisionReason = "None"
}

struct BetaGeofenceRegion: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let source: String
}

struct BetaGeofenceDiagnostics {
    var regions: [BetaGeofenceRegion] = []
    var enteredRegion = "None"
    var exitedRegion = "None"
    var lastTrigger: Date?
    var currentStore = "None"
    var currentDistance: CLLocationDistance?
    var lastSuppressionReason = "None"
}

struct BetaMapDiagnostics {
    var userCoordinate: CLLocationCoordinate2D?
    var cameraCenter: CLLocationCoordinate2D?
    var focusedStore = "None"
    var selectedStore = "None"
    var visibleStores: [BetaDiagnosticStore] = []
    var visibleCircleCount = 0
    var zoom: Double?
    var regionDescription = "Unavailable"
}

struct BetaRecognitionDiagnostics {
    var geminiRequests = 0
    var geminiSuccesses = 0
    var geminiFailures = 0
    var fallbackCount = 0
    var barcodeCount = 0
    var openFoodFactsCount = 0
    var manualProducts = 0
    var lastRecognitionDuration: TimeInterval?
    var averageRecognitionDuration: TimeInterval?
    var cacheHits = 0
    var cacheMisses = 0
    var estimatedMonthlyGeminiRequests = 0
}

struct BetaSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let screenName: String
    let image: UIImage?
    let markdownReport: String
    let jsonReport: String
}

@MainActor
final class BetaDiagnosticsCenter: ObservableObject {
    static let shared = BetaDiagnosticsCenter()
    static let developerModeKey = "waytask.betaDiagnostics.developerMode.v1"
    @TaskLocal static var discoveryContextID: UUID?

    @Published private(set) var planner = BetaPlannerDiagnostics()
    @Published private(set) var discovery = BetaStoreDiscoveryDiagnostics()
    @Published private(set) var notification = BetaNotificationDiagnostics()
    @Published private(set) var geofence = BetaGeofenceDiagnostics()
    @Published private(set) var map = BetaMapDiagnostics()
    @Published private(set) var recognition = BetaRecognitionDiagnostics()
    @Published private(set) var events: [BetaDiagnosticEvent] = []
    @Published private(set) var lastSnapshot: BetaSnapshot?

    private let defaults = UserDefaults.standard
    private let maximumEvents = 200
    private let maximumRejectionReasons = 40
    private var planDurationTotal: TimeInterval
    private var planDurationCount: Int
    private var discoveryDurationTotal: TimeInterval
    private var discoveryDurationCount: Int
    private var discoverySessions: [UUID: BetaStoreDiscoveryDiagnostics] = [:]

    private init() {
        planDurationTotal = defaults.double(forKey: "waytask.betaDiagnostics.planDurationTotal")
        planDurationCount = defaults.integer(forKey: "waytask.betaDiagnostics.planDurationCount")
        discoveryDurationTotal = defaults.double(forKey: "waytask.betaDiagnostics.discoveryDurationTotal")
        discoveryDurationCount = defaults.integer(forKey: "waytask.betaDiagnostics.discoveryDurationCount")
        loadRecognitionCounters()
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.developerModeKey)
    }

    var averagePlanDuration: TimeInterval? {
        planDurationCount > 0 ? planDurationTotal / Double(planDurationCount) : nil
    }

    var averageDiscoveryDuration: TimeInterval? {
        discoveryDurationCount > 0 ? discoveryDurationTotal / Double(discoveryDurationCount) : nil
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }

    var osVersion: String {
        UIDevice.current.systemVersion
    }

    var recentErrors: [BetaDiagnosticEvent] {
        events.filter(\.isError).prefixArray(30)
    }

    func updatePlannerContext(
        listName: String,
        listID: UUID?,
        products: Int,
        needed: Int,
        checked: Int
    ) {
        guard isEnabled else { return }
        planner.shoppingListName = listName
        planner.shoppingListID = listID
        planner.productCount = products
        planner.neededCount = needed
        planner.checkedCount = checked
    }

    func synchronizePlanner(plan: ShoppingPlan?, state: ShoppingPlanGenerationState) {
        guard isEnabled else { return }
        switch state {
        case .idle:
            planner.state = "Idle"
            planner.status = "Not started"
            planner.stage = "None"
        case let .generating(stage, startedAt):
            planner.state = "Generating"
            planner.status = "Running"
            planner.stage = stage.title
            planner.startedAt = startedAt
        case .ready:
            planner.state = "Ready"
            planner.status = "Succeeded"
            planner.stage = "Ready"
        case let .failed(message, _):
            planner.state = "Failed"
            planner.status = "Failed"
            planner.stage = "Failed"
            planner.lastFailureReason = message
        case let .stale(reason):
            planner.state = "Stale"
            planner.status = "Invalidated"
            planner.stage = "None"
            planner.lastFailureReason = reason
        }

        if let plan {
            planner.bestStore = plan.bestCoverage?.store.title ?? plan.stores.first?.title ?? "None"
            planner.coveragePercent = plan.bestCoverage.map { $0.coverageScore * 100 }
            planner.matchedProducts = plan.bestCoverage?.matchedItems.map(\.name) ?? []
            planner.rejectedProducts = plan.bestCoverage?.missingItems.map(\.name) ?? []
            planner.selectionReasons = plan.bestCoverage?.ranking.reasons ?? []
        }
    }

    func synchronizeStoreSnapshot(stores: [MapStore], savedCount: Int) {
        guard isEnabled, discovery.lastSearchTime == nil else { return }
        discovery.savedStores = savedCount
        discovery.mapKitStores = stores.filter { $0.sourceType == .appleMaps }.count
        discovery.mergedStores = stores.count
        discovery.acceptedStores = discovery.mapKitStores
        discovery.deduplicatedStores = stores.count
        discovery.stores = stores.map(BetaDiagnosticStore.init)
    }

    func plannerStarted(stage: String) {
        guard isEnabled else { return }
        planner.state = "Generating"
        planner.status = "Running"
        planner.stage = stage
        planner.startedAt = Date()
        planner.lastFailureReason = "None"
        append(.planner, "Generate Plan started", stage)
    }

    func plannerStageChanged(_ stage: String) {
        guard isEnabled else { return }
        planner.stage = stage
        append(.planner, "Planning stage changed", stage)
    }

    func plannerSucceeded(plan: ShoppingPlan, cacheHit: Bool) {
        guard isEnabled else { return }
        let now = Date()
        let duration = planner.state == "Generating" ? planner.startedAt.map { now.timeIntervalSince($0) } : nil
        planner.state = "Ready"
        planner.status = "Succeeded"
        planner.stage = "Ready"
        planner.lastDuration = duration
        planner.startedAt = nil
        planner.cacheStatus = cacheHit ? "Content signature hit" : "New plan published"
        planner.bestStore = plan.bestCoverage?.store.title ?? plan.stores.first?.title ?? "None"
        planner.coveragePercent = plan.bestCoverage.map { $0.coverageScore * 100 }
        planner.matchedProducts = plan.bestCoverage?.matchedItems.map(\.name) ?? []
        planner.rejectedProducts = plan.bestCoverage?.missingItems.map(\.name) ?? []
        planner.selectionReasons = plan.bestCoverage?.ranking.reasons ?? []
        if let duration {
            recordPlanDuration(duration)
        }
        let rankingDetail = plan.shoppingTripCoverages.prefix(5).map { coverage in
            "\(coverage.store.title): \(String(format: "%.1f", coverage.ranking.score)) [\(coverage.ranking.reasons.joined(separator: "; "))]"
        }
        .joined(separator: " | ")
        append(.planner, "Generate Plan succeeded", rankingDetail)
    }

    func plannerFailed(reason: String) {
        guard isEnabled else { return }
        let duration = planner.state == "Generating" ? planner.startedAt.map { Date().timeIntervalSince($0) } : nil
        planner.state = "Failed"
        planner.status = "Failed"
        planner.stage = "Failed"
        planner.lastFailureReason = reason
        planner.lastDuration = duration
        planner.startedAt = nil
        if let duration {
            recordPlanDuration(duration)
        }
        append(.planner, "Generate Plan failed", reason, isError: true)
    }

    func plannerMarkedStale(reason: String) {
        guard isEnabled else { return }
        planner.state = "Stale"
        planner.status = "Invalidated"
        append(.planner, "ShoppingPlan became stale", reason)
    }

    func beginStoreDiscovery(savedCount: Int, coordinate: CLLocationCoordinate2D?) -> UUID? {
        guard isEnabled else { return nil }
        let id = UUID()
        var session = BetaStoreDiscoveryDiagnostics()
        session.savedStores = savedCount
        session.currentCoordinate = coordinate
        session.activeSearchStartedAt = Date()
        discoverySessions[id] = session
        return id
    }

    func storeCacheResult(id: UUID?, hit: Bool, reason: String) {
        guard isEnabled else { return }
        if let id, var session = discoverySessions[id] {
            session.cacheStatus = hit ? "Hit" : "Miss"
            discoverySessions[id] = session
        }
        append(.storeDiscovery, hit ? "Store cache hit" : "Store cache miss", reason)
    }

    func recordMapKitQuery(query: String, accepted: Int, rejected: [(String, String)]) {
        guard isEnabled else { return }
        if let id = Self.discoveryContextID, var session = discoverySessions[id] {
            session.acceptedStores += accepted
            session.rejectedStores += rejected.count
            session.rejectionReasons.append(contentsOf: rejected.map { "\($0.0): \($0.1)" })
            session.rejectionReasons = Array(session.rejectionReasons.suffix(maximumRejectionReasons))
            discoverySessions[id] = session
        }
        append(.storeDiscovery, "MapKit query completed", "\(query): \(accepted) accepted, \(rejected.count) rejected")
    }

    func finishStoreDiscovery(id: UUID?, stores: [MapStore], savedCount: Int, duration: TimeInterval?) {
        guard isEnabled else { return }
        var session = id.flatMap { discoverySessions[$0] } ?? BetaStoreDiscoveryDiagnostics()
        let mapKitCount = stores.filter { $0.sourceType == .appleMaps }.count
        session.savedStores = savedCount
        session.mapKitStores = mapKitCount
        session.mergedStores = stores.count
        session.deduplicatedStores = stores.count
        session.acceptedStores = max(session.acceptedStores, mapKitCount)
        session.lastSearchTime = Date()
        session.duration = duration
        session.activeSearchStartedAt = nil
        session.stores = stores.map(BetaDiagnosticStore.init)
        discovery = session
        if let id { discoverySessions.removeValue(forKey: id) }
        if let duration {
            recordDiscoveryDuration(duration)
        }
        append(.storeDiscovery, "Resolved store set published", "saved=\(savedCount), mapKit=\(mapKitCount), merged=\(stores.count)")
    }

    func recordStoreTransition(previous: [MapStore], next: [MapStore], reason: String) {
        guard isEnabled else { return }
        let previousIDs = Set(previous.map(\.id))
        let nextIDs = Set(next.map(\.id))
        let appeared = next.filter { !previousIDs.contains($0.id) }.map(\.title)
        let disappeared = previous.filter { !nextIDs.contains($0.id) }.map(\.title)
        if !appeared.isEmpty {
            append(.storeDiscovery, "Stores appeared", "\(appeared.joined(separator: ", ")) | \(reason)")
        }
        if !disappeared.isEmpty {
            append(.storeDiscovery, "Stores disappeared", "\(disappeared.joined(separator: ", ")) | \(reason)")
        }
    }

    func notificationDecision(
        fired: Bool,
        type: String,
        store: String,
        coordinate: CLLocationCoordinate2D?,
        shoppingListID: UUID?,
        matchedProducts: [String],
        reason: String
    ) {
        guard isEnabled else { return }
        notification.lastNotification = fired ? "Fired" : "Suppressed"
        notification.notificationType = type
        notification.notificationTime = Date()
        notification.store = store
        notification.coordinate = coordinate
        notification.shoppingListID = shoppingListID
        notification.matchedProducts = matchedProducts
        notification.decisionReason = reason
        append(.notification, fired ? "Notification fired" : "Notification did not fire", "\(store): \(reason)")
    }

    func notificationAuthorization(status: String) {
        guard isEnabled else { return }
        notification.authorizationStatus = status
        append(.notification, "Notification authorization checked", status)
    }

    func notificationTapped(store: String, deepLinkStatus: String) {
        guard isEnabled else { return }
        notification.tapResult = "Tapped"
        notification.deepLinkStatus = deepLinkStatus
        append(.notification, "Notification tapped", "\(store): \(deepLinkStatus)")
    }

    func notificationBottomSheetOpened(store: String) {
        guard isEnabled else { return }
        notification.bottomSheetOpened = true
        notification.deepLinkStatus = "Store selected"
        append(.notification, "Map bottom sheet opened", store)
    }

    func recordGeofenceCandidates(_ candidates: [ShoppingGeofenceCandidate]) {
        guard isEnabled else { return }
        let detail = candidates
            .map { "\($0.title) [\($0.sourceType)]" }
            .joined(separator: ", ")
        append(.geofence, "Geofence candidates resolved", detail.isEmpty ? "None" : detail)
    }

    func updateMonitoredRegions(_ regions: [BetaGeofenceRegion]) {
        guard isEnabled else { return }
        geofence.regions = regions
        append(.geofence, "Core Location monitored regions updated", "\(regions.count) regions")
    }

    func geofenceSuppressed(reason: String) {
        guard isEnabled else { return }
        geofence.lastSuppressionReason = reason
        append(.geofence, "Geofence monitoring skipped", reason, isError: true)
    }

    func geofenceTriggered(title: String, entered: Bool, distance: CLLocationDistance?) {
        guard isEnabled else { return }
        geofence.lastTrigger = Date()
        geofence.currentStore = title
        geofence.currentDistance = distance
        if entered {
            geofence.enteredRegion = title
        } else {
            geofence.exitedRegion = title
        }
        append(.geofence, entered ? "Entered region" : "Exited region", title)
    }

    func updateMap(
        userCoordinate: CLLocationCoordinate2D?,
        region: MKCoordinateRegion?,
        focusedStore: String?,
        selectedStore: String?,
        stores: [MapStore]
    ) {
        guard isEnabled else { return }
        map.userCoordinate = userCoordinate
        if let focusedStore {
            map.focusedStore = focusedStore
        }
        map.selectedStore = selectedStore ?? "None"
        map.visibleStores = stores.map(BetaDiagnosticStore.init)
        map.visibleCircleCount = stores.count
        if let region {
            map.cameraCenter = region.center
            map.zoom = log2(360 / max(region.span.longitudeDelta, 0.000_001))
            map.regionDescription = "center \(coordinateText(region.center)), span \(String(format: "%.5f", region.span.latitudeDelta)) x \(String(format: "%.5f", region.span.longitudeDelta))"
        }
    }

    func recognitionStarted(kind: String, fallback: Bool) -> Date {
        guard isEnabled else { return Date() }
        if kind == "Gemini" {
            recognition.geminiRequests += 1
            if fallback { recognition.fallbackCount += 1 }
            if defaults.object(forKey: "waytask.betaDiagnostics.firstGeminiRequest") == nil {
                defaults.set(Date().timeIntervalSince1970, forKey: "waytask.betaDiagnostics.firstGeminiRequest")
            }
        } else if kind == "Barcode" {
            recognition.barcodeCount += 1
            recognition.openFoodFactsCount += 1
        }
        persistRecognitionCounters()
        append(.recognition, "\(kind) request started", fallback ? "Fallback request" : "Primary request")
        return Date()
    }

    func recognitionFinished(kind: String, success: Bool, startedAt: Date, reason: String) {
        guard isEnabled else { return }
        let duration = Date().timeIntervalSince(startedAt)
        if kind == "Gemini" {
            if success { recognition.geminiSuccesses += 1 } else { recognition.geminiFailures += 1 }
        }
        recognition.lastRecognitionDuration = duration
        let durationTotal = defaults.double(forKey: "waytask.betaDiagnostics.recognitionDurationTotal") + duration
        let durationCount = defaults.integer(forKey: "waytask.betaDiagnostics.recognitionDurationCount") + 1
        defaults.set(durationTotal, forKey: "waytask.betaDiagnostics.recognitionDurationTotal")
        defaults.set(durationCount, forKey: "waytask.betaDiagnostics.recognitionDurationCount")
        recognition.averageRecognitionDuration = durationTotal / Double(durationCount)
        persistRecognitionCounters()
        append(.recognition, "\(kind) request \(success ? "succeeded" : "failed")", reason, isError: !success)
    }

    func manualProductAdded() {
        guard isEnabled else { return }
        recognition.manualProducts += 1
        persistRecognitionCounters()
        append(.recognition, "Manual product added", "Local manual entry")
    }

    func recognitionCache(hit: Bool, source: String) {
        guard isEnabled else { return }
        if hit { recognition.cacheHits += 1 } else { recognition.cacheMisses += 1 }
        persistRecognitionCounters()
        append(.recognition, hit ? "Recognition cache hit" : "Recognition cache miss", source)
    }

    func recordError(category: BetaDiagnosticCategory, message: String, detail: String) {
        guard isEnabled else { return }
        append(category, message, detail, isError: true)
    }

    @discardableResult
    func captureSnapshot(screenName: String) -> BetaSnapshot {
        let image = captureCurrentScreen()
        let snapshot = BetaSnapshot(
            timestamp: Date(),
            screenName: screenName,
            image: image,
            markdownReport: markdownReport(),
            jsonReport: jsonReport()
        )
        lastSnapshot = snapshot
        append(.performance, "Beta Snapshot captured", "\(screenName); screenshot retained in memory only")
        return snapshot
    }

    func markdownReport() -> String {
        let now = Date()
        return """
        # WayTask Beta Diagnostics Report

        ## App
        - App: WayTask
        - Build: \(buildNumber)
        - Version: \(appVersion)
        - Device: \(deviceModel)
        - iOS: \(osVersion)
        - Date: \(Self.dateFormatter.string(from: now))
        - Time: \(Self.timeFormatter.string(from: now))

        ## Planner
        - State: \(planner.state)
        - Shopping List: \(planner.shoppingListName) (\(planner.shoppingListID?.uuidString ?? "Unavailable"))
        - Products / Needed / Checked: \(planner.productCount) / \(planner.neededCount) / \(planner.checkedCount)
        - Stage: \(planner.stage)
        - Coverage: \(percentText(planner.coveragePercent))
        - Planning Time: \(durationText(planner.lastDuration))
        - Best Store: \(planner.bestStore)
        - Selection Reasons: \(listText(planner.selectionReasons))
        - Matched Products: \(listText(planner.matchedProducts))
        - Rejected Products: \(listText(planner.rejectedProducts))
        - Last Failure: \(planner.lastFailureReason)
        - Planner Cache: \(planner.cacheStatus)

        ## Store Discovery
        - Saved: \(discovery.savedStores)
        - MapKit: \(discovery.mapKitStores)
        - Merged: \(discovery.mergedStores)
        - Accepted: \(discovery.acceptedStores)
        - Rejected: \(discovery.rejectedStores)
        - Deduplicated: \(discovery.deduplicatedStores)
        - Search Radius: \(discovery.searchRadiusMeters)m
        - Cache: \(discovery.cacheStatus)
        - Current Coordinate: \(coordinateText(discovery.currentCoordinate))
        - Discovery Time: \(durationText(discovery.duration))
        - Stores: \(discovery.stores.map { "\($0.title) [\($0.source)]" }.joined(separator: ", ").nilIfEmpty ?? "None")

        ## Notifications
        - Authorization: \(notification.authorizationStatus)
        - Last Notification: \(notification.lastNotification)
        - Type: \(notification.notificationType)
        - Time: \(dateTimeText(notification.notificationTime))
        - Store: \(notification.store)
        - Coordinate: \(coordinateText(notification.coordinate))
        - Shopping List: \(notification.shoppingListID?.uuidString ?? "Unavailable")
        - Matched Products: \(listText(notification.matchedProducts))
        - Deep Link: \(notification.deepLinkStatus)
        - Tap Result: \(notification.tapResult)
        - Bottom Sheet Opened: \(notification.bottomSheetOpened ? "Yes" : "No")
        - Decision Reason: \(notification.decisionReason)

        ## Geofence
        - Current Regions: \(geofence.regions.count)
        - Regions: \(geofence.regions.map { "\($0.title) \(Int($0.radius))m [\($0.source)]" }.joined(separator: ", ").nilIfEmpty ?? "None")
        - Entered Region: \(geofence.enteredRegion)
        - Exited Region: \(geofence.exitedRegion)
        - Last Trigger: \(dateTimeText(geofence.lastTrigger))
        - Current Store: \(geofence.currentStore)
        - Current Distance: \(distanceText(geofence.currentDistance))
        - Last Suppression: \(geofence.lastSuppressionReason)

        ## Map
        - User Coordinate: \(coordinateText(map.userCoordinate))
        - Visible Stores: \(map.visibleStores.count)
        - Visible Circles: \(map.visibleCircleCount)
        - Focused Store: \(map.focusedStore)
        - Selected Store: \(map.selectedStore)
        - Camera: \(coordinateText(map.cameraCenter))
        - Zoom: \(map.zoom.map { String(format: "%.2f", $0) } ?? "Unavailable")
        - Region: \(map.regionDescription)

        ## Gemini
        - Requests: \(recognition.geminiRequests)
        - Success: \(recognition.geminiSuccesses)
        - Failure: \(recognition.geminiFailures)
        - Fallback Count: \(recognition.fallbackCount)
        - Barcode Count: \(recognition.barcodeCount)
        - OpenFoodFacts Count: \(recognition.openFoodFactsCount)
        - Manual Products: \(recognition.manualProducts)
        - Recognition Time: \(durationText(recognition.lastRecognitionDuration))
        - Cache Hits / Misses: \(recognition.cacheHits) / \(recognition.cacheMisses)
        - Estimated Monthly Gemini Requests: \(recognition.estimatedMonthlyGeminiRequests) (local usage projection)

        ## Performance
        - Average Generate Plan: \(durationText(averagePlanDuration))
        - Average Discovery: \(durationText(averageDiscoveryDuration))
        - ShoppingPlan Cache: \(planner.cacheStatus)
        - Store Cache: \(discovery.cacheStatus)
        - Memory Cache: \(events.count) / \(maximumEvents) diagnostic events

        ## Recent Errors
        \(recentErrorMarkdown())

        ## Recent Decisions
        \(recentDecisionMarkdown())

        ## Privacy
        This report excludes product photos, screenshots, email, authentication data, API keys, route history, and private account data.
        """
    }

    func jsonReport() -> String {
        let dictionary: [String: Any] = [
            "report": "WayTask Beta Diagnostics Report",
            "app": ["version": appVersion, "build": buildNumber, "device": deviceModel, "ios": osVersion, "timestamp": ISO8601DateFormatter().string(from: Date())],
            "planner": ["state": planner.state, "list": planner.shoppingListName, "listID": planner.shoppingListID?.uuidString ?? "", "coveragePercent": jsonNumber(planner.coveragePercent), "planningSeconds": jsonNumber(planner.lastDuration), "bestStore": planner.bestStore, "selectionReasons": planner.selectionReasons, "matchedProducts": planner.matchedProducts, "rejectedProducts": planner.rejectedProducts, "failure": planner.lastFailureReason, "cache": planner.cacheStatus],
            "storeDiscovery": ["saved": discovery.savedStores, "mapKit": discovery.mapKitStores, "merged": discovery.mergedStores, "accepted": discovery.acceptedStores, "rejected": discovery.rejectedStores, "deduplicated": discovery.deduplicatedStores, "cache": discovery.cacheStatus, "durationSeconds": jsonNumber(discovery.duration), "coordinate": jsonCoordinate(discovery.currentCoordinate), "rejectionReasons": discovery.rejectionReasons, "stores": discovery.stores.map { ["id": $0.id.uuidString, "title": $0.title, "source": $0.source, "coordinate": jsonCoordinate($0.coordinate), "matchedProducts": $0.itemNames] }],
            "notifications": ["authorization": notification.authorizationStatus, "last": notification.lastNotification, "type": notification.notificationType, "store": notification.store, "coordinate": jsonCoordinate(notification.coordinate), "listID": notification.shoppingListID?.uuidString ?? "", "matchedProducts": notification.matchedProducts, "deepLink": notification.deepLinkStatus, "tapResult": notification.tapResult, "bottomSheetOpened": notification.bottomSheetOpened, "decisionReason": notification.decisionReason],
            "geofence": ["regionCount": geofence.regions.count, "regions": geofence.regions.map { ["title": $0.title, "source": $0.source, "radius": $0.radius, "coordinate": jsonCoordinate($0.coordinate)] }, "entered": geofence.enteredRegion, "exited": geofence.exitedRegion, "currentStore": geofence.currentStore, "currentDistance": jsonNumber(geofence.currentDistance), "lastSuppression": geofence.lastSuppressionReason],
            "map": ["userCoordinate": jsonCoordinate(map.userCoordinate), "camera": jsonCoordinate(map.cameraCenter), "visibleStores": map.visibleStores.count, "visibleCircles": map.visibleCircleCount, "focusedStore": map.focusedStore, "selectedStore": map.selectedStore, "zoom": jsonNumber(map.zoom), "region": map.regionDescription],
            "gemini": ["requests": recognition.geminiRequests, "success": recognition.geminiSuccesses, "failure": recognition.geminiFailures, "fallbacks": recognition.fallbackCount, "recognitionSeconds": jsonNumber(recognition.lastRecognitionDuration), "estimatedMonthlyRequests": recognition.estimatedMonthlyGeminiRequests],
            "performance": ["averagePlanSeconds": jsonNumber(averagePlanDuration), "averageDiscoverySeconds": jsonNumber(averageDiscoveryDuration), "shoppingPlanCache": planner.cacheStatus, "storeCache": discovery.cacheStatus],
            "recentErrors": recentErrors.map { ["category": $0.category.rawValue, "message": $0.message, "detail": $0.detail, "timestamp": ISO8601DateFormatter().string(from: $0.timestamp)] },
            "recentDecisions": events.prefix(50).map { ["category": $0.category.rawValue, "message": $0.message, "detail": $0.detail, "timestamp": ISO8601DateFormatter().string(from: $0.timestamp)] },
            "privacy": ["productPhotosExported": false, "screenshotsExported": false, "credentialsExported": false, "routeHistoryExported": false]
        ]
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) else {
            return "{\"error\":\"Unable to generate diagnostics JSON\"}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func append(_ category: BetaDiagnosticCategory, _ message: String, _ detail: String, isError: Bool = false) {
        events.insert(BetaDiagnosticEvent(timestamp: Date(), category: category, message: message, detail: detail, isError: isError), at: 0)
        if events.count > maximumEvents {
            events.removeLast(events.count - maximumEvents)
        }
    }

    private func recordPlanDuration(_ duration: TimeInterval) {
        planDurationTotal += duration
        planDurationCount += 1
        defaults.set(planDurationTotal, forKey: "waytask.betaDiagnostics.planDurationTotal")
        defaults.set(planDurationCount, forKey: "waytask.betaDiagnostics.planDurationCount")
    }

    private func recordDiscoveryDuration(_ duration: TimeInterval) {
        discoveryDurationTotal += duration
        discoveryDurationCount += 1
        defaults.set(discoveryDurationTotal, forKey: "waytask.betaDiagnostics.discoveryDurationTotal")
        defaults.set(discoveryDurationCount, forKey: "waytask.betaDiagnostics.discoveryDurationCount")
    }

    private func loadRecognitionCounters() {
        recognition.geminiRequests = defaults.integer(forKey: "waytask.betaDiagnostics.geminiRequests")
        recognition.geminiSuccesses = defaults.integer(forKey: "waytask.betaDiagnostics.geminiSuccesses")
        recognition.geminiFailures = defaults.integer(forKey: "waytask.betaDiagnostics.geminiFailures")
        recognition.fallbackCount = defaults.integer(forKey: "waytask.betaDiagnostics.fallbackCount")
        recognition.barcodeCount = defaults.integer(forKey: "waytask.betaDiagnostics.barcodeCount")
        recognition.openFoodFactsCount = defaults.integer(forKey: "waytask.betaDiagnostics.openFoodFactsCount")
        recognition.manualProducts = defaults.integer(forKey: "waytask.betaDiagnostics.manualProducts")
        recognition.cacheHits = defaults.integer(forKey: "waytask.betaDiagnostics.recognitionCacheHits")
        recognition.cacheMisses = defaults.integer(forKey: "waytask.betaDiagnostics.recognitionCacheMisses")
        let total = defaults.double(forKey: "waytask.betaDiagnostics.recognitionDurationTotal")
        let count = defaults.integer(forKey: "waytask.betaDiagnostics.recognitionDurationCount")
        recognition.averageRecognitionDuration = count > 0 ? total / Double(count) : nil
        updateMonthlyEstimate()
    }

    private func persistRecognitionCounters() {
        defaults.set(recognition.geminiRequests, forKey: "waytask.betaDiagnostics.geminiRequests")
        defaults.set(recognition.geminiSuccesses, forKey: "waytask.betaDiagnostics.geminiSuccesses")
        defaults.set(recognition.geminiFailures, forKey: "waytask.betaDiagnostics.geminiFailures")
        defaults.set(recognition.fallbackCount, forKey: "waytask.betaDiagnostics.fallbackCount")
        defaults.set(recognition.barcodeCount, forKey: "waytask.betaDiagnostics.barcodeCount")
        defaults.set(recognition.openFoodFactsCount, forKey: "waytask.betaDiagnostics.openFoodFactsCount")
        defaults.set(recognition.manualProducts, forKey: "waytask.betaDiagnostics.manualProducts")
        defaults.set(recognition.cacheHits, forKey: "waytask.betaDiagnostics.recognitionCacheHits")
        defaults.set(recognition.cacheMisses, forKey: "waytask.betaDiagnostics.recognitionCacheMisses")
        updateMonthlyEstimate()
    }

    private func updateMonthlyEstimate() {
        let firstTimestamp = defaults.double(forKey: "waytask.betaDiagnostics.firstGeminiRequest")
        guard firstTimestamp > 0, recognition.geminiRequests > 0 else {
            recognition.estimatedMonthlyGeminiRequests = 0
            return
        }
        let observedDays = max(Date().timeIntervalSince1970 - firstTimestamp, 86_400) / 86_400
        recognition.estimatedMonthlyGeminiRequests = Int(ceil((Double(recognition.geminiRequests) / observedDays) * 30))
    }

    private func captureCurrentScreen() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func recentErrorMarkdown() -> String {
        guard !recentErrors.isEmpty else { return "- None" }
        return recentErrors.map { event in
            "- [\(event.category.rawValue)] \(event.message): \(event.detail)"
        }
        .joined(separator: "\n")
    }

    private func recentDecisionMarkdown() -> String {
        guard !events.isEmpty else { return "- None" }
        return events.prefix(50).map { event in
            "- [\(event.category.rawValue)] \(event.message): \(event.detail)"
        }
        .joined(separator: "\n")
    }

    private func jsonNumber(_ value: Double?) -> Any {
        value.map { NSNumber(value: $0) } ?? NSNull()
    }

    private func jsonCoordinate(_ value: CLLocationCoordinate2D?) -> Any {
        guard let value else { return NSNull() }
        return ["latitude": value.latitude, "longitude": value.longitude]
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "Unavailable" }
        return coordinateText(coordinate)
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        duration.map { String(format: "%.2fs", $0) } ?? "Unavailable"
    }

    private func distanceText(_ distance: CLLocationDistance?) -> String {
        distance.map { "\(Int($0.rounded()))m" } ?? "Unavailable"
    }

    private func percentText(_ percent: Double?) -> String {
        percent.map { String(format: "%.0f%%", $0) } ?? "Unavailable"
    }

    private func listText(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    private func dateTimeText(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return "\(Self.dateFormatter.string(from: date)) \(Self.timeFormatter.string(from: date))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private extension BetaDiagnosticStore {
    init(store: MapStore) {
        id = store.id
        title = store.title
        source = store.diagnosticSourceLabel
        coordinate = store.coordinate
        itemNames = store.itemNames
    }
}

private extension MapStore {
    var diagnosticSourceLabel: String {
        if isSavedLocation { return "Saved" }
        switch sourceType {
        case .appleMaps:
            return "MapKit / Transient"
        case .publicDatabase, .openStreetMap:
            return "Future Community"
        case .retailAPI:
            return "Future Merchant"
        case .local, .debugSeed, .aiProvider, .userGenerated:
            return "Transient"
        }
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
