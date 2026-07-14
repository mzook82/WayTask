import Combine
import CoreLocation
import Foundation
import UserNotifications

final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationService = GeofenceNotificationService()
    private let intentMatcher = ShoppingIntentMatcher()
    private let maxMonitoredShoppingRegions = 12
    private let maxTotalMonitoredRegions = 20
    private let smartNearbyRadius: CLLocationDistance = 50
    private var lastShoppingGeofenceSignature: String?
    private var cachedActiveShoppingItems: [ShoppingItem] = []
    private var cachedResolvedCandidates: [ShoppingGeofenceCandidate] = []
    private var geofenceRefreshGeneration = 0
    private var rawCurrentCoordinate: CLLocationCoordinate2D?
    private var lastCoordinatePublication = Date.distantPast
    private let coordinatePublicationMovementThreshold: CLLocationDistance = 15
    private let coordinatePublicationMaximumInterval: TimeInterval = 10

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        notificationService.requestAuthorizationIfNeeded()
        startLocationUpdatesIfAuthorized()
    }

    func requestWhenInUseAuthorization() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            startLocationUpdatesIfAuthorized()
        }
    }

    func requestAlwaysLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startLocationUpdatesIfAuthorized()
        default:
            break
        }
    }

    func startMonitoring(locations: [GeoLocation]) {
        let relevantLocations = locations
            .filter(shouldIncludeLocationInGeofenceResults)
            .filter { location in
                location.shoppingItems.contains { !$0.isCompleted }
            }
            .prefix(maxMonitoredShoppingRegions)

        for location in relevantLocations {
            startMonitoring(location: location)
        }
    }

    func startMonitoring(location: GeoLocation) {
        let openItemNames = location.shoppingItems
            .filter { !$0.isCompleted }
            .prefix(3)
            .map(\.name)

        guard !openItemNames.isEmpty else {
            stopMonitoringStore(withID: location.id)
            return
        }

        let candidate = ShoppingGeofenceCandidate(
            id: location.id,
            locationID: location.id,
            title: location.title,
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            radius: notificationRadius(for: location.radius),
            itemNames: Array(openItemNames),
            itemIDs: location.shoppingItems.filter { !$0.isCompleted }.prefix(3).map(\.id),
            shoppingListID: nil,
            sourceType: location.sourceType.rawValue,
            distanceMeters: distanceFromCurrentUser(to: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)),
            notificationType: "shoppingGeofence"
        )

        startMonitoring(candidate: candidate)
    }

    func refreshShoppingGeofences(
        items: [ShoppingItem],
        savedLocations: [GeoLocation],
        shoppingListID: UUID? = nil
    ) {
        let activeItems = items.filter { !$0.isCompleted }
        let visibleSavedLocations = savedLocations.filter(shouldIncludeLocationInGeofenceResults)
        cachedActiveShoppingItems = activeItems
        geofenceRefreshGeneration += 1
        let refreshGeneration = geofenceRefreshGeneration
        let coordinate = rawCurrentCoordinate

        Task { @MainActor [weak self] in
            guard let self else { return }
            let stores = await StoreResolutionEngine.shared.resolve(
                savedLocations: visibleSavedLocations,
                items: activeItems,
                around: coordinate
            )
            guard refreshGeneration == geofenceRefreshGeneration else { return }
            let candidates = geofenceCandidates(
                from: stores,
                items: activeItems,
                shoppingListID: shoppingListID
            )
            applyResolvedGeofenceCandidates(candidates, activeItems: activeItems, savedLocations: visibleSavedLocations)
        }
    }

    private func applyResolvedGeofenceCandidates(
        _ candidates: [ShoppingGeofenceCandidate],
        activeItems: [ShoppingItem],
        savedLocations: [GeoLocation]
    ) {
        let candidates = deduplicated(candidates).prefixArray(maxMonitoredShoppingRegions)
        cachedResolvedCandidates = candidates
        BetaDiagnosticsCenter.shared.recordGeofenceCandidates(candidates)
        let signature = geofenceSignature(for: candidates)
        evaluateSmartNearbyDetection(reason: "geofence refresh")

        #if DEBUG
        logGeofenceRefresh(activeItems: activeItems, savedLocations: savedLocations, candidates: candidates)
        #endif

        guard signature != lastShoppingGeofenceSignature else {
            #if DEBUG
            print("[WayTask Geofence] Region set unchanged. Monitored regions: \(locationManager.monitoredRegions.count)")
            #endif
            return
        }

        lastShoppingGeofenceSignature = signature
        stopManagedShoppingRegions()
        for candidate in candidates {
            startMonitoring(candidate: candidate)
        }
        publishBetaDiagnostics()

        #if DEBUG
        logMonitoredRegions()
        #endif
    }

    private func geofenceCandidates(
        from stores: [MapStore],
        items: [ShoppingItem],
        shoppingListID: UUID?
    ) -> [ShoppingGeofenceCandidate] {
        stores.compactMap { store in
            let taggedNames = Set(store.itemNames.map { $0.lowercased() })
            let directlyMatchedItems = items.filter { taggedNames.contains($0.name.lowercased()) }
            let matchingItems = directlyMatchedItems.isEmpty
                ? intentMatcher.relevantItems(from: items, for: store)
                : directlyMatchedItems
            guard !matchingItems.isEmpty else { return nil }

            return ShoppingGeofenceCandidate(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: notificationRadius(for: store.radius),
                itemNames: notificationItemNames(from: matchingItems),
                itemIDs: matchingItems.prefix(3).map(\.id),
                shoppingListID: shoppingListID,
                sourceType: store.sourceType.rawValue,
                distanceMeters: distanceFromCurrentUser(to: store.coordinate),
                notificationType: "shoppingGeofence"
            )
        }
    }

    func checkSmartNearbyDetection(reason: String = "manual") {
        evaluateSmartNearbyDetection(reason: reason)
    }

    func publishBetaDiagnostics() {
        guard BetaDiagnosticsCenter.shared.isEnabled else {
            return
        }

        let regions = locationManager.monitoredRegions.compactMap { region -> BetaGeofenceRegion? in
            guard let circularRegion = region as? CLCircularRegion,
                  let payload = ShoppingGeofencePayload(identifier: circularRegion.identifier) else {
                return nil
            }
            return BetaGeofenceRegion(
                id: circularRegion.identifier,
                title: payload.title,
                coordinate: circularRegion.center,
                radius: circularRegion.radius,
                source: payload.sourceType
            )
        }
        BetaDiagnosticsCenter.shared.updateMonitoredRegions(regions)
    }

    private func shouldIncludeLocationInGeofenceResults(_ location: GeoLocation) -> Bool {
        guard location.sourceType == .debugSeed else {
            return true
        }

        #if DEBUG
        return DebugSeedStoreService.isEnabled
        #else
        return false
        #endif
    }

    private func notificationItemNames(from items: [ShoppingItem]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()

            guard !name.isEmpty, !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            names.append(name)

            if names.count == 3 {
                break
            }
        }

        return names
    }

    private func startMonitoring(candidate: ShoppingGeofenceCandidate) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            BetaDiagnosticsCenter.shared.geofenceSuppressed(reason: "Region monitoring is unavailable on this device")
            #if DEBUG
            print("[WayTask Geofence] Region monitoring is not available on this device.")
            #endif
            return
        }

        let payload = ShoppingGeofencePayload(candidate: candidate)
        stopMonitoringStore(withID: candidate.id)

        guard locationManager.monitoredRegions.count < maxTotalMonitoredRegions else {
            BetaDiagnosticsCenter.shared.geofenceSuppressed(reason: "Core Location monitored-region limit reached for \(candidate.title)")
            #if DEBUG
            print("[WayTask Geofence] Region limit reached. Skipping \(candidate.title).")
            #endif
            return
        }

        #if DEBUG
        let distanceText = distanceFromUserText(to: candidate.coordinate)
        print("[WayTask Geofence] Start monitoring: \(candidate.title) | source: \(candidate.sourceType) | center: \(candidate.coordinate.latitude), \(candidate.coordinate.longitude) | radius: \(Int(candidate.radius))m | distance: \(distanceText) | matched items: \(candidate.itemNames.count)")
        #endif

        let region = CLCircularRegion(
            center: candidate.coordinate,
            radius: candidate.radius,
            identifier: payload.identifier
        )

        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
    }

    private func stopManagedShoppingRegions() {
        for region in locationManager.monitoredRegions where ShoppingGeofencePayload(identifier: region.identifier) != nil {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func stopMonitoringStore(withID id: UUID) {
        for region in locationManager.monitoredRegions where region.identifier.contains(id.uuidString) {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func notificationRadius(for radius: CLLocationDistance) -> CLLocationDistance {
        min(max(radius, 150), 250)
    }

    private func distanceFromCurrentUser(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let currentCoordinate = rawCurrentCoordinate else {
            return nil
        }

        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let storeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: storeLocation)
    }

    private func geofenceSignature(for candidates: [ShoppingGeofenceCandidate]) -> String {
        candidates
            .map { candidate in
                "\(candidate.id.uuidString)-\(candidate.title)-\(candidate.coordinate.latitude)-\(candidate.coordinate.longitude)-\(candidate.radius)-\(candidate.sourceType)-\(candidate.itemNames.joined(separator: ","))"
            }
            .joined(separator: "|")
    }

    private func deduplicated(_ candidates: [ShoppingGeofenceCandidate]) -> [ShoppingGeofenceCandidate] {
        var seen = Set<UUID>()
        var result: [ShoppingGeofenceCandidate] = []

        for candidate in candidates where !seen.contains(candidate.id) {
            seen.insert(candidate.id)
            result.append(candidate)
        }

        return result
    }

    private func startLocationUpdatesIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        default:
            break
        }

        #if DEBUG
        print("[WayTask Geofence] Location authorization status: \(locationManager.authorizationStatus.rawValue)")
        #endif
    }

    private func sendEntryNotification(for region: CLRegion) {
        guard let request = notificationService.notificationRequest(for: region.identifier) else {
            #if DEBUG
            print("[WayTask Geofence] No notification request created for region: \(region.identifier)")
            #endif
            return
        }

        addNotificationRequest(request)
    }

    private func evaluateSmartNearbyDetection(reason: String) {
        guard !cachedActiveShoppingItems.isEmpty else {
            #if DEBUG
            print("[WayTask Nearby] Skipped \(reason): no active shopping items.")
            #endif
            return
        }

        guard let currentCoordinate = rawCurrentCoordinate else {
            #if DEBUG
            print("[WayTask Nearby] Skipped \(reason): user location unavailable.")
            #endif
            return
        }

        guard !cachedResolvedCandidates.isEmpty else {
            #if DEBUG
            print("[WayTask Nearby] Skipped \(reason): no relevant saved stores.")
            #endif
            return
        }

        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let nearestCandidate = cachedResolvedCandidates
            .map { candidate in
                let storeLocation = CLLocation(
                    latitude: candidate.coordinate.latitude,
                    longitude: candidate.coordinate.longitude
                )
                return (candidate: candidate, distance: userLocation.distance(from: storeLocation))
            }
            .sorted { $0.distance < $1.distance }
            .first

        guard let nearestCandidate else {
            return
        }

        #if DEBUG
        print("[WayTask Nearby] Nearest relevant saved store during \(reason): \(nearestCandidate.candidate.title) | distance: \(Int(nearestCandidate.distance.rounded()))m | matched items: \(nearestCandidate.candidate.itemNames.joined(separator: ", "))")
        #endif

        guard nearestCandidate.distance <= smartNearbyRadius else {
            #if DEBUG
            print("[WayTask Nearby] Blocked \(nearestCandidate.candidate.title): outside \(Int(smartNearbyRadius))m nearby radius.")
            #endif
            return
        }

        let payload = ShoppingGeofencePayload(candidate: nearestCandidate.candidate)
        guard let request = notificationService.notificationRequest(for: payload.identifier) else {
            #if DEBUG
            print("[WayTask Nearby] Blocked \(nearestCandidate.candidate.title): cooldown or invalid notification payload.")
            #endif
            return
        }

        #if DEBUG
        print("[WayTask Nearby] Allowed \(nearestCandidate.candidate.title): scheduling nearby notification.")
        #endif

        addNotificationRequest(request)
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) {
        notificationCenter.add(request) { error in
            let userInfo = request.content.userInfo
            let store = (userInfo["storeTitle"] as? String) ?? "Unknown store"
            let notificationType = (userInfo["notificationType"] as? String) ?? "shoppingGeofence"
            let listID = (userInfo["shoppingListID"] as? String).flatMap(UUID.init(uuidString:))
            let itemNames = ((userInfo["matchedItemNames"] as? String) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let latitude = (userInfo["latitude"] as? String).flatMap(Double.init)
            let longitude = (userInfo["longitude"] as? String).flatMap(Double.init)
            let coordinate = latitude.flatMap { latitude in
                longitude.map { longitude in
                    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                }
            }
            Task { @MainActor in
                BetaDiagnosticsCenter.shared.notificationDecision(
                    fired: error == nil,
                    type: notificationType,
                    store: store,
                    coordinate: coordinate,
                    shoppingListID: listID,
                    matchedProducts: itemNames,
                    reason: error?.localizedDescription ?? "Notification request accepted by UNUserNotificationCenter"
                )
                if let error {
                    BetaDiagnosticsCenter.shared.recordError(
                        category: .notification,
                        message: "Notification scheduling failed",
                        detail: error.localizedDescription
                    )
                    SentryReportingService.shared.capture(
                        error: error,
                        message: .notificationSchedulingFailed,
                        operation: .notification,
                        category: .integration,
                        area: .shopping,
                        numericContext: [.itemCount: itemNames.count]
                    )
                }
            }
            #if DEBUG
            if let error {
                print("[WayTask Geofence] Notification scheduling failed: \(error.localizedDescription)")
            } else {
                print("[WayTask Geofence] Notification handed to notification center: \(request.identifier)")
            }
            #endif
        }
    }

    private func publishCoordinateForUIIfNeeded(_ coordinate: CLLocationCoordinate2D, now: Date = Date()) {
        guard let publishedCoordinate = currentCoordinate else {
            currentCoordinate = coordinate
            lastCoordinatePublication = now
            return
        }

        guard publishedCoordinate.latitude != coordinate.latitude ||
                publishedCoordinate.longitude != coordinate.longitude else {
            return
        }

        let movement = CLLocation(
            latitude: publishedCoordinate.latitude,
            longitude: publishedCoordinate.longitude
        ).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let interval = now.timeIntervalSince(lastCoordinatePublication)
        guard movement >= coordinatePublicationMovementThreshold ||
                interval >= coordinatePublicationMaximumInterval else {
            return
        }

        currentCoordinate = coordinate
        lastCoordinatePublication = now
    }

    #if DEBUG
    private func logGeofenceRefresh(
        activeItems: [ShoppingItem],
        savedLocations: [GeoLocation],
        candidates: [ShoppingGeofenceCandidate]
    ) {
        let coordinateText: String
        if let currentCoordinate = rawCurrentCoordinate {
            coordinateText = "\(currentCoordinate.latitude), \(currentCoordinate.longitude)"
        } else {
            coordinateText = "unavailable"
        }

        print("[WayTask Geofence] Refresh | active items: \(activeItems.count) | saved locations: \(savedLocations.count) | user coordinate: \(coordinateText) | candidates: \(candidates.count)")

        for candidate in candidates {
            print("[WayTask Geofence] Candidate: \(candidate.title) | source: \(candidate.sourceType) | center: \(candidate.coordinate.latitude), \(candidate.coordinate.longitude) | radius: \(Int(candidate.radius))m | distance: \(distanceFromUserText(to: candidate.coordinate)) | matched items: \(candidate.itemNames.count) | names: \(candidate.itemNames.joined(separator: ", "))")
        }
    }

    private func logMonitoredRegions() {
        let regions = locationManager.monitoredRegions.compactMap { $0 as? CLCircularRegion }
        print("[WayTask Geofence] Monitored region count: \(regions.count)")

        for region in regions {
            let payload = ShoppingGeofencePayload(identifier: region.identifier)
            print("[WayTask Geofence] Region: \(region.identifier) | source: \(payload?.sourceType ?? "unknown") | center: \(region.center.latitude), \(region.center.longitude) | radius: \(Int(region.radius))m | distance: \(distanceFromUserText(to: region.center)) | matched items: \(payload?.itemNames.count ?? 0) | names: \(payload?.itemNames.joined(separator: ", ") ?? "")")
        }
    }

    private func distanceFromUserText(to coordinate: CLLocationCoordinate2D) -> String {
        guard let currentCoordinate = rawCurrentCoordinate else {
            return "unknown"
        }

        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let storeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return "\(Int(userLocation.distance(from: storeLocation).rounded()))m"
    }
    #endif
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }

        startLocationUpdatesIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else {
            return
        }

        rawCurrentCoordinate = coordinate
        publishCoordinateForUIIfNeeded(coordinate)

        #if DEBUG
        print("[WayTask Geofence] User location updated: \(coordinate.latitude), \(coordinate.longitude)")
        #endif

        evaluateSmartNearbyDetection(reason: "location update")
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        #if DEBUG
        if let circularRegion = region as? CLCircularRegion {
            let payload = ShoppingGeofencePayload(identifier: circularRegion.identifier)
            print("[WayTask Geofence] Did start monitoring: \(circularRegion.identifier) | source: \(payload?.sourceType ?? "unknown") | center: \(circularRegion.center.latitude), \(circularRegion.center.longitude) | radius: \(Int(circularRegion.radius))m | distance: \(distanceFromUserText(to: circularRegion.center)) | matched items: \(payload?.itemNames.count ?? 0) | names: \(payload?.itemNames.joined(separator: ", ") ?? "")")
        } else {
            print("[WayTask Geofence] Did start monitoring non-circular region: \(region.identifier)")
        }
        #endif
        publishBetaDiagnostics()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        #if DEBUG
        print("[WayTask Geofence] didEnterRegion: \(region.identifier)")
        #endif
        if let circularRegion = region as? CLCircularRegion {
            let payload = ShoppingGeofencePayload(identifier: circularRegion.identifier)
            BetaDiagnosticsCenter.shared.geofenceTriggered(
                title: payload?.title ?? circularRegion.identifier,
                entered: true,
                distance: distanceFromCurrentUser(to: circularRegion.center)
            )
        }
        sendEntryNotification(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let payload = ShoppingGeofencePayload(identifier: circularRegion.identifier)
        BetaDiagnosticsCenter.shared.geofenceTriggered(
            title: payload?.title ?? circularRegion.identifier,
            entered: false,
            distance: distanceFromCurrentUser(to: circularRegion.center)
        )
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        BetaDiagnosticsCenter.shared.geofenceSuppressed(reason: "Monitoring failed: \(error.localizedDescription)")
        if !isExpectedLocationAuthorizationError(error) {
            SentryReportingService.shared.capture(
                error: error,
                message: .geofenceMonitoringFailed,
                operation: .geofence,
                category: .integration,
                area: .map
            )
        }
        #if DEBUG
        print("Region monitoring failed: \(error.localizedDescription)")
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location manager failed: \(error.localizedDescription)")
        #endif
    }

    private func isExpectedLocationAuthorizationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == kCLErrorDomain,
              let code = CLError.Code(rawValue: nsError.code) else {
            return false
        }

        return code == .denied || code == .regionMonitoringDenied
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
