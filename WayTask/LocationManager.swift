import CoreLocation
import Combine
import Foundation
import UserNotifications

final class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        requestNotificationPermission()
        requestAlwaysLocationPermission()
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func startMonitoring(locations: [GeoLocation]) {
        for location in locations {
            startMonitoring(location: location)
        }
    }

    func startMonitoring(location: GeoLocation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return
        }

        stopMonitoringLocation(withID: location.id)

        let center = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )

        let radius = min(location.radius, locationManager.maximumRegionMonitoringDistance)
        let openItemNames = location.shoppingItems
            .filter { !$0.isCompleted }
            .prefix(3)
            .map(\.name)
        let payload = MonitoredRegionPayload(
            id: location.id,
            title: location.title,
            itemNames: Array(openItemNames)
        )
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: payload.identifier
        )

        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
    }

    private func stopMonitoringLocation(withID id: UUID) {
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix(id.uuidString) {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendEntryNotification(for region: CLRegion) {
        guard let payload = MonitoredRegionPayload(identifier: region.identifier) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "אתה ליד \(payload.title)!"
        content.body = payload.notificationBody
        content.sound = .default
        content.userInfo = [
            "geoLocationID": payload.id.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "region-entry-\(payload.id.uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        sendEntryNotification(for: region)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Region monitoring failed: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}

private struct MonitoredRegionPayload {
    let id: UUID
    let title: String
    let itemNames: [String]

    var identifier: String {
        let encodedItems = itemNames.map(sanitize).joined(separator: ",")
        return "\(id.uuidString)|\(sanitize(title))|\(encodedItems)"
    }

    var notificationBody: String {
        guard !itemNames.isEmpty else {
            return "אל תשכח לבדוק את רשימת הפריטים שלך."
        }

        return "אל תשכח לקנות: \(itemNames.joined(separator: ", "))"
    }

    init(id: UUID, title: String, itemNames: [String]) {
        self.id = id
        self.title = title
        self.itemNames = itemNames
    }

    init?(identifier: String) {
        let components = identifier.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)

        guard let idComponent = components.first,
              let id = UUID(uuidString: String(idComponent)) else {
            return nil
        }

        self.id = id
        self.title = components.count > 1 ? String(components[1]) : "המיקום הזה"
        self.itemNames = components.count > 2 && !components[2].isEmpty
            ? components[2].split(separator: ",").map(String.init)
            : []
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
    }
}
