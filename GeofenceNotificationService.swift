import Combine
import CoreLocation
import Foundation
import UserNotifications

struct ShoppingGeofenceCandidate: Identifiable, Equatable {
    let id: UUID
    let locationID: UUID?
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let itemNames: [String]
    let itemIDs: [UUID]
    let shoppingListID: UUID?
    let sourceType: String
    let distanceMeters: CLLocationDistance?
    let notificationType: String

    static func == (lhs: ShoppingGeofenceCandidate, rhs: ShoppingGeofenceCandidate) -> Bool {
        lhs.id == rhs.id &&
        lhs.locationID == rhs.locationID &&
        lhs.title == rhs.title &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.radius == rhs.radius &&
        lhs.itemNames == rhs.itemNames &&
        lhs.itemIDs == rhs.itemIDs &&
        lhs.shoppingListID == rhs.shoppingListID &&
        lhs.sourceType == rhs.sourceType &&
        lhs.distanceMeters == rhs.distanceMeters &&
        lhs.notificationType == rhs.notificationType
    }
}

struct ShoppingGeofencePayload {
    nonisolated private static let prefix = "waytask-shopping"
    nonisolated private static let separator = "|"
    nonisolated private static let itemSeparator = ";"

    let storeID: UUID
    let locationID: UUID?
    let title: String
    let itemNames: [String]
    let itemIDs: [UUID]
    let shoppingListID: UUID?
    let sourceType: String
    let distanceMeters: CLLocationDistance?
    let coordinate: CLLocationCoordinate2D?
    let notificationType: String

    init(candidate: ShoppingGeofenceCandidate) {
        self.storeID = candidate.id
        self.locationID = candidate.locationID
        self.title = candidate.title
        self.itemNames = candidate.itemNames
        self.itemIDs = candidate.itemIDs
        self.shoppingListID = candidate.shoppingListID
        self.sourceType = candidate.sourceType
        self.distanceMeters = candidate.distanceMeters
        self.coordinate = candidate.coordinate
        self.notificationType = candidate.notificationType
    }

    init?(identifier: String) {
        let components = identifier.split(separator: Self.separator.first!, omittingEmptySubsequences: false)

        guard components.count >= 4,
              components[0] == Self.prefix,
              let storeID = UUID(uuidString: String(components[1])) else {
            return nil
        }

        self.storeID = storeID
        self.locationID = UUID(uuidString: String(components[2]))
        self.title = Self.restore(String(components[3]))
        self.sourceType = components.count > 4 ? Self.restore(String(components[4])) : "saved"

        if components.count > 5, !components[5].isEmpty {
            self.itemNames = components[5]
                .split(separator: Self.itemSeparator.first!)
                .map { Self.restore(String($0)) }
        } else {
            self.itemNames = []
        }

        if components.count > 6 {
            self.distanceMeters = Double(components[6])
        } else {
            self.distanceMeters = nil
        }

        if components.count > 8,
           let latitude = Double(components[7]),
           let longitude = Double(components[8]) {
            self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            self.coordinate = nil
        }
        if components.count > 9, !components[9].isEmpty {
            self.itemIDs = components[9].split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        } else {
            self.itemIDs = []
        }
        self.shoppingListID = components.count > 10 ? UUID(uuidString: String(components[10])) : nil
        self.notificationType = components.count > 11 ? Self.restore(String(components[11])) : "shoppingGeofence"
    }

    var identifier: String {
        [
            Self.prefix,
            storeID.uuidString,
            locationID?.uuidString ?? "none",
            Self.sanitize(title),
            Self.sanitize(sourceType),
            itemNames.map(Self.sanitize).joined(separator: Self.itemSeparator),
            distanceMeters.map { String(Int($0.rounded())) } ?? "",
            coordinate.map { String($0.latitude) } ?? "",
            coordinate.map { String($0.longitude) } ?? "",
            itemIDs.map(\.uuidString).joined(separator: ","),
            shoppingListID?.uuidString ?? "",
            Self.sanitize(notificationType)
        ]
        .joined(separator: Self.separator)
    }

    var notificationUserInfo: [String: String] {
        var userInfo = [
            "storeID": storeID.uuidString,
            "storeTitle": title,
            "matchedItemCount": "\(itemNames.count)",
            "matchedItemNames": itemNames.joined(separator: ", "),
            "matchedShoppingItemIDs": itemIDs.map(\.uuidString).joined(separator: ","),
            "storeSourceType": sourceType,
            "sourceType": sourceType,
            "notificationType": notificationType,
            "opensTripMode": "false",
            "distanceMeters": distanceMeters.map { String(Int($0.rounded())) } ?? ""
        ]

        if let locationID {
            userInfo["geoLocationID"] = locationID.uuidString
        }
        if let shoppingListID {
            userInfo["shoppingListID"] = shoppingListID.uuidString
        }
        if let coordinate {
            userInfo["latitude"] = String(coordinate.latitude)
            userInfo["longitude"] = String(coordinate.longitude)
        }

        return userInfo
    }

    nonisolated private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: separator, with: " ")
            .replacingOccurrences(of: itemSeparator, with: " ")
    }

    nonisolated private static func restore(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GeofenceNotificationService {
    enum SuppressionReason: Equatable {
        case invalidPayload
        case noMatchedProducts
        case cooldown
    }

    enum RequestOutcome {
        case request(UNNotificationRequest)
        case suppressed(SuppressionReason)
    }

    private let notificationCenter: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let cooldown: TimeInterval

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard,
        cooldown: TimeInterval? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        self.cooldown = cooldown ?? Self.defaultCooldown
    }

    private static var defaultCooldown: TimeInterval {
        #if DEBUG
        45
        #else
        6 * 60 * 60
        #endif
    }

    func requestAuthorizationIfNeeded() {
        notificationCenter.getNotificationSettings { settings in
            Task { @MainActor in
                BetaDiagnosticsCenter.shared.notificationAuthorization(
                    status: authorizationStatusText(settings.authorizationStatus)
                )
            }
            #if DEBUG
            print("[WayTask Geofence] Notification authorization status: \(settings.authorizationStatus.rawValue)")
            #endif

            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                Task { @MainActor in
                    BetaDiagnosticsCenter.shared.notificationAuthorization(
                        status: error.map { "Error: \($0.localizedDescription)" } ?? (granted ? "Authorized" : "Denied")
                    )
                    if let error {
                        BetaDiagnosticsCenter.shared.recordError(
                            category: .notification,
                            message: "Notification authorization failed",
                            detail: error.localizedDescription
                        )
                        SentryReportingService.shared.capture(
                            error: error,
                            message: .notificationAuthorizationFailed,
                            operation: .notification,
                            category: .integration,
                            area: .settings
                        )
                    }
                }
                #if DEBUG
                if let error {
                    print("[WayTask Geofence] Notification authorization request failed: \(error.localizedDescription)")
                } else {
                    print("[WayTask Geofence] Notification authorization granted: \(granted)")
                }
                #endif
            }
        }
    }

    private func authorizationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }

    func notificationRequest(
        for regionIdentifier: String,
        now: Date = Date()
    ) -> UNNotificationRequest? {
        switch notificationRequestOutcome(
            for: regionIdentifier,
            now: now
        ) {
        case let .request(value): return value
        case .suppressed: return nil
        }
    }

    func notificationRequestOutcome(
        for regionIdentifier: String,
        now: Date = Date()
    ) -> RequestOutcome {
        guard let payload = ShoppingGeofencePayload(identifier: regionIdentifier) else {
            BetaDiagnosticsCenter.shared.recordError(
                category: .notification,
                message: "Notification payload rejected",
                detail: "Region identifier was not a WayTask shopping payload"
            )
            BetaDiagnosticsCenter.shared.notificationDecision(
                fired: false,
                type: "unknown",
                store: "Unknown region",
                coordinate: nil,
                shoppingListID: nil,
                matchedProducts: [],
                reason: "Region identifier was not a WayTask shopping payload"
            )
            #if DEBUG
            print("[WayTask Geofence] Ignoring non-shopping region: \(regionIdentifier)")
            #endif
            return .suppressed(.invalidPayload)
        }

        guard !payload.itemNames.isEmpty else {
            BetaDiagnosticsCenter.shared.notificationDecision(
                fired: false,
                type: payload.notificationType,
                store: payload.title,
                coordinate: payload.coordinate,
                shoppingListID: payload.shoppingListID,
                matchedProducts: [],
                reason: "No matched shopping products"
            )
            #if DEBUG
            print("[WayTask Geofence] Skipping notification with no matched items for store: \(payload.title)")
            #endif
            return .suppressed(.noMatchedProducts)
        }

        guard shouldNotify(payload, now: now) else {
            BetaDiagnosticsCenter.shared.notificationDecision(
                fired: false,
                type: payload.notificationType,
                store: payload.title,
                coordinate: payload.coordinate,
                shoppingListID: payload.shoppingListID,
                matchedProducts: payload.itemNames,
                reason: "Notification cooldown active"
            )
            #if DEBUG
            print("[WayTask Geofence] Cooldown blocked notification for store: \(payload.title)")
            #endif
            return .suppressed(.cooldown)
        }

        let content = UNMutableNotificationContent()
        content.title = "You're near \(payload.title)"
        content.body = notificationBody(for: payload)
        content.sound = .default
        content.userInfo = payload.notificationUserInfo

        #if DEBUG
        print("[WayTask Geofence] Scheduling notification for \(payload.title), source: \(payload.sourceType), matched items: \(payload.itemNames.joined(separator: ", "))")
        #endif

        return .request(
            UNNotificationRequest(
                identifier: "shopping-geofence-\(payload.storeID.uuidString)-\(Int(now.timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
        )
    }

    func recordNotificationRequestAccepted(
        for regionIdentifier: String,
        now: Date = Date()
    ) {
        guard let payload = ShoppingGeofencePayload(
            identifier: regionIdentifier
        ) else { return }
        recordNotificationSent(for: payload, now: now)
    }

    private func notificationBody(for payload: ShoppingGeofencePayload) -> String {
        let itemCount = payload.itemNames.count
        let distanceSuffix = payload.distanceMeters.map { " \(distanceText(for: $0))" } ?? ""

        if itemCount == 1 {
            return "\(payload.itemNames[0]) is likely here. Availability is estimated.\(distanceSuffix)"
        }

        if itemCount > 1 {
            let visibleNames = payload.itemNames.prefix(2).joined(separator: ", ")
            let listSuffix = itemCount > 2 ? ", and more." : "."
            return "\(itemCount) items are likely here: \(visibleNames)\(listSuffix) Availability is estimated. Some items may require another store.\(distanceSuffix)"
        }

        return "Recommended Store. Availability is estimated.\(distanceSuffix)"
    }

    private func distanceText(for distance: CLLocationDistance) -> String {
        if distance >= 1000 {
            return String(format: "About %.1f km away.", distance / 1000)
        }

        return "About \(max(Int(distance.rounded()), 1)) m away."
    }

    private func shouldNotify(_ payload: ShoppingGeofencePayload, now: Date) -> Bool {
        let key = lastNotificationKey(for: payload)
        let lastSent = userDefaults.double(forKey: key)

        guard lastSent > 0 else {
            return true
        }

        return now.timeIntervalSince1970 - lastSent >= cooldown
    }

    private func recordNotificationSent(for payload: ShoppingGeofencePayload, now: Date) {
        userDefaults.set(now.timeIntervalSince1970, forKey: lastNotificationKey(for: payload))
    }

    private func lastNotificationKey(for payload: ShoppingGeofencePayload) -> String {
        "waytask.geofence.lastSent.\(payload.storeID.uuidString)"
    }
}

enum ProductionNearbyNotificationDiagnosticState: Equatable {
    case idle
    case permissionMissing(notification: String, location: String)
    case noEligibleStores
    case geofenceNotArmed(String)
    case osMonitoringLimit
    case arming(Int)
    case registrationSucceeded(Int)
    case notificationSuppressedByCooldown
    case notificationRequestAcceptedDeliveryUnproven
}

struct ProductionNearbyNotificationDeepLink: Equatable {
    let storeID: UUID
    let storeTitle: String
    let shoppingListID: UUID?
}

/// App-scoped production owner for Product State nearby notifications.
/// Region monitoring is low-power and persists in iOS; coordinate acquisition
/// is one-shot and only runs when the mission or foreground state changes.
@MainActor
final class ProductionNearbyNotificationCoordinator:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate,
    UNUserNotificationCenterDelegate {
    @Published private(set) var diagnosticState:
        ProductionNearbyNotificationDiagnosticState = .idle
    @Published private(set) var pendingDeepLink:
        ProductionNearbyNotificationDeepLink?

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationService = GeofenceNotificationService()
    private let resolutionEngine = StoreResolutionEngine.shared
    private let intentMatcher = ShoppingIntentMatcher()
    private let userDefaults = UserDefaults.standard
    private let approvedRegionIdentifiersKey =
        "waytask.productionNearby.approvedRegions.v1"
    private let missionSignatureKey =
        "waytask.productionNearby.missionSignature.v1"
    private let maximumShoppingRegions = 12
    private let maximumSystemRegions = 20
    private var items: [ShoppingPlanInputItem] = []
    private var intents: [StoreResolutionIntent] = []
    private var listID: ProductStateListID?
    private var missionSignature: String?
    private var refreshGeneration = 0
    private var pendingRegionIdentifiers = Set<String>()
    private var approvedRegionIdentifiers: Set<String>
    private var remainingFreshLocationRetries = 0
    private var regionRegistrationWasLimited = false
    private var regionRegistrationFailed = false

    override init() {
        approvedRegionIdentifiers = Set(
            UserDefaults.standard.stringArray(
                forKey: "waytask.productionNearby.approvedRegions.v1"
            ) ?? []
        )
        missionSignature = UserDefaults.standard.string(
            forKey: "waytask.productionNearby.missionSignature.v1"
        )
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        locationManager.pausesLocationUpdatesAutomatically = true
        notificationCenter.delegate = self
    }

    func configure(
        list: ProductStateNamedListProjection?,
        activate: Bool = true
    ) {
        let nextItems = ShoppingMissionProductStateAdapter.neededItems(
            from: list?.neededEntries ?? []
        )
        let nextIntents: [StoreResolutionIntent]
        if let list {
            nextIntents = intentMatcher.resolutionIntents(
                for: nextItems,
                sourceListID: list.id,
                sourceRevision: list.revision
            )
        } else {
            nextIntents = []
        }
        let nextSignature = [
            list?.id.rawValue.uuidString ?? "no-list",
            list.map { String($0.revision.value) } ?? "no-revision",
            nextItems.map {
                [
                    $0.identity.id.rawValue.uuidString,
                    $0.displayName,
                    $0.catalogCategoryID ?? ""
                ].joined(separator: "=")
            }.joined(separator: "|")
        ].joined(separator: ":")

        let missionChanged = missionSignature != nextSignature
        items = nextItems
        intents = nextIntents
        listID = list?.id
        missionSignature = nextSignature
        userDefaults.set(nextSignature, forKey: missionSignatureKey)
        refreshGeneration &+= 1
        if missionChanged {
            stopManagedRegions()
            pendingRegionIdentifiers.removeAll()
            setApprovedRegionIdentifiers([])
        }
        guard !items.isEmpty, !intents.isEmpty else {
            publish(.noEligibleStores)
            return
        }
        if activate { applicationDidBecomeActive() }
    }

    func applicationDidBecomeActive() {
        Task { [weak self] in
            await self?.activateIfAuthorized()
        }
    }

    func consumeDeepLink() {
        pendingDeepLink = nil
    }

    private func activateIfAuthorized() async {
        var notificationSettings = await notificationCenter
            .notificationSettings()
        if notificationSettings.authorizationStatus == .notDetermined {
            do {
                _ = try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
            } catch {
                publish(.permissionMissing(
                    notification: "Error: \(error.localizedDescription)",
                    location: locationAuthorizationDescription
                ))
                return
            }
            notificationSettings = await notificationCenter
                .notificationSettings()
        }
        let notificationAuthorized = [
            UNAuthorizationStatus.authorized,
            .provisional,
            .ephemeral
        ].contains(notificationSettings.authorizationStatus)
        BetaDiagnosticsCenter.shared.notificationAuthorization(
            status: notificationAuthorizationDescription(
                notificationSettings.authorizationStatus
            )
        )
        guard notificationAuthorized else {
            publish(.permissionMissing(
                notification: notificationAuthorizationDescription(
                    notificationSettings.authorizationStatus
                ),
                location: locationAuthorizationDescription
            ))
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            publish(.permissionMissing(
                notification: "Authorized",
                location: "Not determined"
            ))
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            publish(.permissionMissing(
                notification: "Authorized",
                location: "When In Use; Always is required for background entry"
            ))
        case .authorizedAlways:
            guard CLLocationManager.isMonitoringAvailable(
                for: CLCircularRegion.self
            ) else {
                publish(.geofenceNotArmed(
                    "Region monitoring is unavailable on this device"
                ))
                return
            }
            guard !items.isEmpty, !intents.isEmpty else {
                stopManagedRegions()
                publish(.noEligibleStores)
                return
            }
            requestFreshCandidateLocation()
        case .denied:
            publish(.permissionMissing(
                notification: "Authorized",
                location: "Denied"
            ))
        case .restricted:
            publish(.permissionMissing(
                notification: "Authorized",
                location: "Restricted"
            ))
        @unknown default:
            publish(.permissionMissing(
                notification: "Authorized",
                location: "Unknown"
            ))
        }
    }

    private func refreshCandidates(around location: CLLocation) {
        guard MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
            location
        ) else {
            publish(.geofenceNotArmed(
                "Fresh usable location has not been received"
            ))
            return
        }
        let generation = refreshGeneration
        let currentItems = items
        let currentIntents = intents
        let currentListID = listID
        Task { [weak self] in
            guard let self else { return }
            let resolved = await resolutionEngine.resolve(
                savedStores: [],
                intents: currentIntents,
                around: location.coordinate,
                forceRefresh: false
            )
            guard generation == refreshGeneration else { return }
            let recommendations = ShoppingMissionRecommendationAuthority
                .recommendations(
                    stores: resolved,
                    items: currentItems,
                    userCoordinate: location.coordinate
                )
            let candidates = recommendations.map { recommendation in
                ShoppingGeofenceCandidate(
                    id: recommendation.store.id,
                    locationID: recommendation.store.locationID,
                    title: recommendation.store.title,
                    coordinate: recommendation.store.coordinate,
                    radius: min(
                        max(recommendation.store.radius, 150),
                        250
                    ),
                    itemNames: Array(
                        recommendation.store.itemNames.prefix(3)
                    ),
                    itemIDs: recommendation.matchedItems.prefix(3).map {
                        $0.identity.id.rawValue
                    },
                    shoppingListID: currentListID?.rawValue,
                    sourceType: recommendation.store.sourceType.rawValue,
                    distanceMeters: recommendation.distanceMeters,
                    notificationType: "shoppingGeofence"
                )
            }
            apply(candidates: candidates)
        }
    }

    private func requestFreshCandidateLocation() {
        remainingFreshLocationRetries = 2
        locationManager.requestLocation()
    }

    private func retryFreshCandidateLocationIfNeeded() -> Bool {
        guard remainingFreshLocationRetries > 0 else { return false }
        remainingFreshLocationRetries -= 1
        locationManager.requestLocation()
        return true
    }

    private func apply(candidates: [ShoppingGeofenceCandidate]) {
        let rankedCandidates = Array(candidates.prefix(
            maximumShoppingRegions
        ))
        BetaDiagnosticsCenter.shared.recordGeofenceCandidates(
            rankedCandidates
        )
        guard !rankedCandidates.isEmpty else {
            stopManagedRegions()
            setApprovedRegionIdentifiers([])
            publish(.noEligibleStores)
            return
        }

        let desired = rankedCandidates.map {
            ShoppingGeofencePayload(candidate: $0).identifier
        }
        let monitoredManaged = Set(locationManager.monitoredRegions.compactMap {
            ShoppingGeofencePayload(identifier: $0.identifier) == nil
                ? nil : $0.identifier
        })
        if monitoredManaged == Set(desired) {
            setApprovedRegionIdentifiers(Set(desired))
            publish(.registrationSucceeded(monitoredManaged.count))
            publishMonitoredRegions()
            return
        }

        stopManagedRegions()
        let unmanagedCount = locationManager.monitoredRegions.filter {
            ShoppingGeofencePayload(identifier: $0.identifier) == nil
        }.count
        let availableCount = max(maximumSystemRegions - unmanagedCount, 0)
        guard availableCount > 0 else {
            setApprovedRegionIdentifiers([])
            publish(.osMonitoringLimit)
            return
        }
        let registrations = Array(
            zip(rankedCandidates, desired).prefix(availableCount)
        )
        regionRegistrationWasLimited =
            registrations.count < rankedCandidates.count
        regionRegistrationFailed = false
        pendingRegionIdentifiers = Set(registrations.map(\.1))
        setApprovedRegionIdentifiers(pendingRegionIdentifiers)
        publish(.arming(registrations.count))
        for (candidate, identifier) in registrations {
            let region = CLCircularRegion(
                center: candidate.coordinate,
                radius: candidate.radius,
                identifier: identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
        }
    }

    private func stopManagedRegions() {
        for region in locationManager.monitoredRegions where
            ShoppingGeofencePayload(identifier: region.identifier) != nil {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func setApprovedRegionIdentifiers(_ identifiers: Set<String>) {
        approvedRegionIdentifiers = identifiers
        userDefaults.set(
            identifiers.sorted(),
            forKey: approvedRegionIdentifiersKey
        )
    }

    private func publishMonitoredRegions() {
        let regions = locationManager.monitoredRegions.compactMap {
            region -> BetaGeofenceRegion? in
            guard let circular = region as? CLCircularRegion,
                  let payload = ShoppingGeofencePayload(
                      identifier: circular.identifier
                  ) else { return nil }
            return BetaGeofenceRegion(
                id: circular.identifier,
                title: payload.title,
                coordinate: circular.center,
                radius: circular.radius,
                source: payload.sourceType
            )
        }
        BetaDiagnosticsCenter.shared.updateMonitoredRegions(regions)
    }

    private func publish(
        _ state: ProductionNearbyNotificationDiagnosticState
    ) {
        diagnosticState = state
        switch state {
        case let .permissionMissing(notification, location):
            BetaDiagnosticsCenter.shared.geofenceSuppressed(
                reason: "Permission missing: notifications \(notification); location \(location)"
            )
        case .noEligibleStores:
            BetaDiagnosticsCenter.shared.geofenceSuppressed(
                reason: "No compatibility-approved stores"
            )
        case let .geofenceNotArmed(reason):
            BetaDiagnosticsCenter.shared.geofenceSuppressed(reason: reason)
        case .osMonitoringLimit:
            BetaDiagnosticsCenter.shared.geofenceSuppressed(
                reason: "Core Location monitored-region limit reached"
            )
        case .idle, .arming, .registrationSucceeded,
             .notificationSuppressedByCooldown,
             .notificationRequestAcceptedDeliveryUnproven:
            break
        }
    }

    private var locationAuthorizationDescription: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "When In Use"
        @unknown default: "Unknown"
        }
    }

    private func notificationAuthorizationDescription(
        _ status: UNAuthorizationStatus
    ) -> String {
        switch status {
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        applicationDidBecomeActive()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last(where: {
            MapLocationFreshnessPolicy.isUsableForAutomaticRecenter($0)
        }) else {
            if retryFreshCandidateLocationIfNeeded() { return }
            publish(.geofenceNotArmed(
                "Location callback contained only stale or inaccurate values"
            ))
            return
        }
        remainingFreshLocationRetries = 0
        refreshCandidates(around: location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        publish(.geofenceNotArmed(
            "Location request failed: \(error.localizedDescription)"
        ))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didStartMonitoringFor region: CLRegion
    ) {
        pendingRegionIdentifiers.remove(region.identifier)
        publishMonitoredRegions()
        if pendingRegionIdentifiers.isEmpty, !regionRegistrationFailed {
            let count = locationManager.monitoredRegions.filter {
                ShoppingGeofencePayload(identifier: $0.identifier) != nil
            }.count
            if regionRegistrationWasLimited {
                publish(.osMonitoringLimit)
            } else {
                publish(.registrationSucceeded(count))
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        regionRegistrationFailed = true
        if let region {
            pendingRegionIdentifiers.remove(region.identifier)
            var approved = approvedRegionIdentifiers
            approved.remove(region.identifier)
            setApprovedRegionIdentifiers(approved)
        }
        publish(.geofenceNotArmed(
            "OS region registration failed: \(error.localizedDescription)"
        ))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circular = region as? CLCircularRegion,
              let payload = ShoppingGeofencePayload(
                  identifier: circular.identifier
              ) else { return }
        guard approvedRegionIdentifiers.contains(circular.identifier) else {
            publish(.geofenceNotArmed(
                "Region entry was not approved for the current shopping mission"
            ))
            return
        }
        BetaDiagnosticsCenter.shared.geofenceTriggered(
            title: payload.title,
            entered: true,
            distance: nil
        )
        switch notificationService.notificationRequestOutcome(
            for: circular.identifier,
            now: Date()
        ) {
        case let .request(request):
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await notificationCenter.add(request)
                    notificationService.recordNotificationRequestAccepted(
                        for: circular.identifier
                    )
                    publish(.notificationRequestAcceptedDeliveryUnproven)
                    BetaDiagnosticsCenter.shared.notificationRequestAccepted(
                        type: payload.notificationType,
                        store: payload.title,
                        coordinate: payload.coordinate,
                        shoppingListID: payload.shoppingListID,
                        matchedProducts: payload.itemNames
                    )
                } catch {
                    publish(.geofenceNotArmed(
                        "Notification scheduling failed: \(error.localizedDescription)"
                    ))
                }
            }
        case let .suppressed(reason):
            if reason == .cooldown {
                publish(.notificationSuppressedByCooldown)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let value = info["storeID"] as? String,
              let storeID = UUID(uuidString: value) else { return }
        let title = info["storeTitle"] as? String ?? "Nearby store"
        let listID = (info["shoppingListID"] as? String)
            .flatMap(UUID.init(uuidString:))
        pendingDeepLink = ProductionNearbyNotificationDeepLink(
            storeID: storeID,
            storeTitle: title,
            shoppingListID: listID
        )
        BetaDiagnosticsCenter.shared.notificationTapped(
            store: title,
            deepLinkStatus: "Production Map route accepted"
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - T-20 inactive Product State platform projections

/// A compact transport token. It deliberately contains only one opaque local
/// ledger identity; owner, revision, Product, Store, and coordinate values are
/// resolved from the committed T-20 ledger before any future platform action.
struct ProductStateOpaqueReminderToken: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case geofence = "g"
        case notification = "n"
    }

    static let version = 1

    let kind: Kind
    let opaqueID: UUID

    var encoded: String {
        "wt-r\(Self.version)-\(kind.rawValue)-\(opaqueID.uuidString.lowercased())"
    }

    init(kind: Kind, opaqueID: UUID) {
        self.kind = kind
        self.opaqueID = opaqueID
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "-", maxSplits: 3)
        guard parts.count == 4,
              parts[0] == "wt",
              parts[1] == "r\(Self.version)",
              let kind = Kind(rawValue: String(parts[2])),
              let opaqueID = UUID(uuidString: String(parts[3])) else {
            return nil
        }
        self.kind = kind
        self.opaqueID = opaqueID
    }
}

struct ProductStatePlatformGeofenceProjection: Equatable, Sendable {
    let identifier: String
    let geofenceID: ProductStateGeofenceID
    let registrationID: ProductStateReminderRegistrationID
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let notifyOnEntry: Bool
    let notifyOnExit: Bool
}

struct ProductStatePlatformNotificationProjection: Equatable, Sendable {
    let identifier: String
    let notificationID: ProductStateNotificationID
    let semanticContent: ProductStateNotificationSemanticContent
    let opaqueUserInfo: [String: String]
}

/// Converts immutable Product State values to inert platform descriptions.
/// It has no notification center, location manager, permission prompt, or
/// scheduling closure, so T-20 cannot activate OS behavior.
struct ProductStateGeofenceNotificationProjectionAdapter {
    func geofence(
        _ registration: ProductStateReminderRegistrationProjection
    ) -> ProductStatePlatformGeofenceProjection {
        let token = ProductStateOpaqueReminderToken(
            kind: .geofence,
            opaqueID: registration.payload.geofenceID.rawValue
        )
        return ProductStatePlatformGeofenceProjection(
            identifier: token.encoded,
            geofenceID: registration.payload.geofenceID,
            registrationID: registration.payload.registrationID,
            latitude: registration.latitude,
            longitude: registration.longitude,
            radiusMeters: registration.radiusMeters,
            notifyOnEntry: true,
            notifyOnExit: false
        )
    }

    func notification(
        _ delivery: ProductStateNotificationDeliveryProjection
    ) -> ProductStatePlatformNotificationProjection {
        let token = ProductStateOpaqueReminderToken(
            kind: .notification,
            opaqueID: delivery.notificationID.rawValue
        )
        return ProductStatePlatformNotificationProjection(
            identifier: token.encoded,
            notificationID: delivery.notificationID,
            semanticContent: delivery.content,
            opaqueUserInfo: [
                "waytaskReminderVersion": String(
                    ProductStateOpaqueReminderToken.version
                ),
                "waytaskReminderToken": token.encoded
            ]
        )
    }
}
