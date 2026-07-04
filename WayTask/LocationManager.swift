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
    private let storeSearchService = LocalStoreSearchService()
    private let maxMonitoredShoppingRegions = 12
    private let maxTotalMonitoredRegions = 20
    private let smartNearbyRadius: CLLocationDistance = 50
    private var lastShoppingGeofenceSignature: String?
    private var cachedActiveShoppingItems: [ShoppingItem] = []
    private var cachedSavedLocations: [GeoLocation] = []

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
            sourceType: location.sourceType.rawValue,
            distanceMeters: distanceFromCurrentUser(to: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
        )

        startMonitoring(candidate: candidate)
    }

    func refreshShoppingGeofences(items: [ShoppingItem], savedLocations: [GeoLocation]) {
        let activeItems = items.filter { !$0.isCompleted }
        cachedActiveShoppingItems = activeItems
        cachedSavedLocations = savedLocations

        let candidates = relevantCandidates(for: activeItems, savedLocations: savedLocations)
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

        for candidate in candidates.prefix(maxMonitoredShoppingRegions) {
            startMonitoring(candidate: candidate)
        }

        #if DEBUG
        logMonitoredRegions()
        #endif
    }

    func checkSmartNearbyDetection(reason: String = "manual") {
        evaluateSmartNearbyDetection(reason: reason)
    }

    private func relevantCandidates(for items: [ShoppingItem], savedLocations: [GeoLocation]) -> [ShoppingGeofenceCandidate] {
        guard !items.isEmpty else {
            return []
        }

        let savedCandidates = savedLocationCandidates(for: items, savedLocations: savedLocations)

        if !savedCandidates.isEmpty {
            return deduplicated(savedCandidates).prefixArray(maxMonitoredShoppingRegions)
        }

        guard let currentCoordinate else {
            return []
        }

        return deduplicated(nearbyFallbackCandidates(for: items, around: currentCoordinate)).prefixArray(maxMonitoredShoppingRegions)
    }

    private func savedLocationCandidates(for items: [ShoppingItem], savedLocations: [GeoLocation]) -> [ShoppingGeofenceCandidate] {
        let activeItemIDs = Set(items.map(\.id))
        let activeItemNames = Set(items.map { $0.name.lowercased() })

        return savedLocations.compactMap { location in
            let directlyMatchedItems = location.shoppingItems.filter { item in
                !item.isCompleted && (activeItemIDs.contains(item.id) || activeItemNames.contains(item.name.lowercased()))
            }
            let categoryMatchedItems = items.filter { item in
                guard let storeCategory = location.storeCategory else {
                    return false
                }

                let itemCategories = intentMatcher.matchStoreCategories(for: item)
                return itemCategories.contains { $0.matches(storeCategory) } || itemCategories.contains(.generalStore)
            }
            let matchingItems = directlyMatchedItems.isEmpty ? categoryMatchedItems : directlyMatchedItems

            guard !matchingItems.isEmpty else {
                return nil
            }

            return ShoppingGeofenceCandidate(
                id: location.id,
                locationID: location.id,
                title: location.title,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                radius: notificationRadius(for: location.radius),
                itemNames: notificationItemNames(from: matchingItems),
                sourceType: location.sourceType.rawValue,
                distanceMeters: distanceFromCurrentUser(to: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
            )
        }
    }

    private func nearbyFallbackCandidates(for items: [ShoppingItem], around coordinate: CLLocationCoordinate2D) -> [ShoppingGeofenceCandidate] {
        let categories = matchedStoreCategories(for: items)
        let stores = storeSearchService.fallbackStores(
            around: coordinate,
            shoppingItems: items.map(\.name),
            storeCategories: categories
        )

        let itemNames = notificationItemNames(from: items)

        return stores.prefix(6).map { store in
            ShoppingGeofenceCandidate(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: notificationRadius(for: store.radius),
                itemNames: itemNames,
                sourceType: store.isSavedLocation ? "saved" : "fallback",
                distanceMeters: distanceFromCurrentUser(to: store.coordinate)
            )
        }
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

    private func matchedStoreCategories(for items: [ShoppingItem]) -> [ShoppingStoreCategory] {
        let categories = items.flatMap { intentMatcher.matchStoreCategories(for: $0) }
        let uniqueCategories = Array(Set(categories))
        return uniqueCategories.isEmpty ? [.generalStore] : uniqueCategories.sorted { $0.displayName < $1.displayName }
    }

    private func startMonitoring(candidate: ShoppingGeofenceCandidate) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            #if DEBUG
            print("[WayTask Geofence] Region monitoring is not available on this device.")
            #endif
            return
        }

        let payload = ShoppingGeofencePayload(candidate: candidate)
        stopMonitoringStore(withID: candidate.id)

        guard locationManager.monitoredRegions.count < maxTotalMonitoredRegions else {
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
        guard let currentCoordinate else {
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

        guard let currentCoordinate else {
            #if DEBUG
            print("[WayTask Nearby] Skipped \(reason): user location unavailable.")
            #endif
            return
        }

        let savedCandidates = savedLocationCandidates(
            for: cachedActiveShoppingItems,
            savedLocations: cachedSavedLocations
        )

        guard !savedCandidates.isEmpty else {
            #if DEBUG
            print("[WayTask Nearby] Skipped \(reason): no relevant saved stores.")
            #endif
            return
        }

        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let nearestCandidate = savedCandidates
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
            #if DEBUG
            if let error {
                print("[WayTask Geofence] Notification scheduling failed: \(error.localizedDescription)")
            } else {
                print("[WayTask Geofence] Notification handed to notification center: \(request.identifier)")
            }
            #endif
        }
    }

    #if DEBUG
    private func logGeofenceRefresh(
        activeItems: [ShoppingItem],
        savedLocations: [GeoLocation],
        candidates: [ShoppingGeofenceCandidate]
    ) {
        let coordinateText: String
        if let currentCoordinate {
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
        guard let currentCoordinate else {
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
        currentCoordinate = locations.last?.coordinate

        #if DEBUG
        if let currentCoordinate {
            print("[WayTask Geofence] User location updated: \(currentCoordinate.latitude), \(currentCoordinate.longitude)")
        }
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
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        #if DEBUG
        print("[WayTask Geofence] didEnterRegion: \(region.identifier)")
        #endif
        sendEntryNotification(for: region)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        #if DEBUG
        print("Region monitoring failed: \(error.localizedDescription)")
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location manager failed: \(error.localizedDescription)")
        #endif
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
