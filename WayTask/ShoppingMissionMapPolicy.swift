import CoreLocation
import Foundation

enum MapLocationFreshnessPolicy {
    static let maximumAutomaticLocationAge: TimeInterval = 30
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 500
    static let meaningfulInactivityInterval: TimeInterval = 15 * 60

    static func isUsableForAutomaticRecenter(
        _ location: CLLocation,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && age >= -5
            && age <= maximumAutomaticLocationAge
    }

    static func shouldRefreshAfterActivation(
        inactiveSince: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let inactiveSince else { return true }
        return now.timeIntervalSince(inactiveSince)
            >= meaningfulInactivityInterval
    }

    static func shouldAutomaticallyFollowAfterActivation(
        inactiveSince: Date?,
        isUserExploring: Bool,
        now: Date = Date()
    ) -> Bool {
        !isUserExploring || shouldRefreshAfterActivation(
            inactiveSince: inactiveSince,
            now: now
        )
    }
}

enum ShoppingMissionMapSelectionPolicy {
    static func toggledSelection(
        current: UUID?,
        tapped: UUID
    ) -> UUID? {
        current == tapped ? nil : tapped
    }

    static func validSelection(
        current: UUID?,
        availableStoreIDs: Set<UUID>
    ) -> UUID? {
        guard let current, availableStoreIDs.contains(current) else {
            return nil
        }
        return current
    }
}

enum ShoppingMissionMapMarkerPolicy {
    /// Product matches remain visible in the store sheet. A separate product
    /// marker at the exact recommended store creates a second tappable marker
    /// for one physical destination and can look like a duplicate store.
    static func renderedProducts(
        storeIDs: Set<UUID>,
        products: [MapProduct]
    ) -> [MapProduct] {
        products.filter { !storeIDs.contains($0.storeID) }
    }
}

enum ShoppingMissionMapPublicationPolicy {
    static func shouldPublish<Value: Equatable>(
        current: Value,
        proposed: Value
    ) -> Bool {
        current != proposed
    }
}

enum ShoppingMissionStoreIdentityPolicy {
    private static let exactNameDistance: CLLocationDistance = 50
    private static let relatedNameDistance: CLLocationDistance = 20

    static func representsSamePhysicalStore(
        _ lhs: MapStore,
        _ rhs: MapStore
    ) -> Bool {
        if lhs.id == rhs.id { return true }
        if let lhsLocationID = lhs.locationID,
           lhsLocationID == rhs.locationID {
            return true
        }

        let separation = distance(lhs.coordinate, rhs.coordinate)
        let lhsName = normalizedName(lhs.title)
        let rhsName = normalizedName(rhs.title)
        if !lhsName.isEmpty,
           lhsName == rhsName,
           separation <= exactNameDistance {
            return true
        }

        return separation <= relatedNameDistance
            && namesLikelyRepresentSameBusiness(lhsName, rhsName)
    }

    static func hasSameVisibleName(_ lhs: MapStore, _ rhs: MapStore) -> Bool {
        let lhsName = normalizedName(lhs.title)
        return !lhsName.isEmpty && lhsName == normalizedName(rhs.title)
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func namesLikelyRepresentSameBusiness(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) {
            return true
        }

        let generic: Set<String> = [
            "store", "market", "shop", "supermarket", "grocery", "food",
            "mini", "the"
        ]
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
            .subtracting(generic)
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
            .subtracting(generic)
        return !lhsTokens.isEmpty
            && !rhsTokens.isEmpty
            && !lhsTokens.isDisjoint(with: rhsTokens)
    }

    private static func distance(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(
                latitude: rhs.latitude,
                longitude: rhs.longitude
            ))
    }
}
