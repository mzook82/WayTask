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
    let sourceType: String
    let distanceMeters: CLLocationDistance?

    static func == (lhs: ShoppingGeofenceCandidate, rhs: ShoppingGeofenceCandidate) -> Bool {
        lhs.id == rhs.id &&
        lhs.locationID == rhs.locationID &&
        lhs.title == rhs.title &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.radius == rhs.radius &&
        lhs.itemNames == rhs.itemNames &&
        lhs.sourceType == rhs.sourceType &&
        lhs.distanceMeters == rhs.distanceMeters
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
    let sourceType: String
    let distanceMeters: CLLocationDistance?

    init(candidate: ShoppingGeofenceCandidate) {
        self.storeID = candidate.id
        self.locationID = candidate.locationID
        self.title = candidate.title
        self.itemNames = candidate.itemNames
        self.sourceType = candidate.sourceType
        self.distanceMeters = candidate.distanceMeters
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
    }

    var identifier: String {
        [
            Self.prefix,
            storeID.uuidString,
            locationID?.uuidString ?? "none",
            Self.sanitize(title),
            Self.sanitize(sourceType),
            itemNames.map(Self.sanitize).joined(separator: Self.itemSeparator),
            distanceMeters.map { String(Int($0.rounded())) } ?? ""
        ]
        .joined(separator: Self.separator)
    }

    var notificationUserInfo: [String: String] {
        var userInfo = [
            "storeID": storeID.uuidString,
            "storeTitle": title,
            "matchedItemCount": "\(itemNames.count)",
            "matchedItemNames": itemNames.joined(separator: ", "),
            "storeSourceType": sourceType,
            "opensTripMode": "true",
            "distanceMeters": distanceMeters.map { String(Int($0.rounded())) } ?? ""
        ]

        if let locationID {
            userInfo["geoLocationID"] = locationID.uuidString
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
            #if DEBUG
            print("[WayTask Geofence] Notification authorization status: \(settings.authorizationStatus.rawValue)")
            #endif

            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
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

    func notificationRequest(for regionIdentifier: String, now: Date = Date()) -> UNNotificationRequest? {
        guard let payload = ShoppingGeofencePayload(identifier: regionIdentifier) else {
            #if DEBUG
            print("[WayTask Geofence] Ignoring non-shopping region: \(regionIdentifier)")
            #endif
            return nil
        }

        guard !payload.itemNames.isEmpty else {
            #if DEBUG
            print("[WayTask Geofence] Skipping notification with no matched items for store: \(payload.title)")
            #endif
            return nil
        }

        guard shouldNotify(payload, now: now) else {
            #if DEBUG
            print("[WayTask Geofence] Cooldown blocked notification for store: \(payload.title)")
            #endif
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "You're near \(payload.title)"
        content.body = notificationBody(for: payload)
        content.sound = .default
        content.userInfo = payload.notificationUserInfo

        recordNotificationSent(for: payload, now: now)

        #if DEBUG
        print("[WayTask Geofence] Scheduling notification for \(payload.title), source: \(payload.sourceType), matched items: \(payload.itemNames.joined(separator: ", "))")
        #endif

        return UNNotificationRequest(
            identifier: "shopping-geofence-\(payload.storeID.uuidString)-\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
    }

    private func notificationBody(for payload: ShoppingGeofencePayload) -> String {
        let itemCount = payload.itemNames.count
        let distanceSuffix = payload.distanceMeters.map { " \(distanceText(for: $0))" } ?? ""

        if itemCount == 1 {
            return "\(payload.itemNames[0]) may be available here.\(distanceSuffix)"
        }

        if itemCount > 1 {
            let visibleNames = payload.itemNames.prefix(2).joined(separator: ", ")
            let listSuffix = itemCount > 2 ? ", and more." : "."
            return "\(itemCount) items may be available here: \(visibleNames)\(listSuffix)\(distanceSuffix)"
        }

        return "Your shopping list may have a match here.\(distanceSuffix)"
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
