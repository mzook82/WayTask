import CoreLocation
import Foundation
import SwiftData

#if DEBUG
struct DebugSeedStoreService {
    static let seedStoreID = UUID(uuidString: "D0E3A8A8-9C2E-4D93-BD21-8242D9E4A111")!
    static let enabledUserDefaultsKey = "waytask.debugSeedStore.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledUserDefaultsKey)
    }

    private static let seedStoreName = "גבעון מרקט"
    private static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 31.9022, longitude: 35.2034)
    private static let seedOffsetDistance: CLLocationDistance = 52
    private static let seedOffsetBearingDegrees = 62.0

    func ensureSeedStore(
        near coordinate: CLLocationCoordinate2D?,
        in modelContext: ModelContext
    ) {
        do {
            let seedStoreID = Self.seedStoreID
            let descriptor = FetchDescriptor<GeoLocation>(
                predicate: #Predicate { location in
                    location.id == seedStoreID
                }
            )
            let existingStores = try modelContext.fetch(descriptor)
            let storeCoordinate = Self.storeCoordinate(near: coordinate)

            if let existingStore = existingStores.first {
                existingStore.title = Self.seedStoreName
                existingStore.latitude = storeCoordinate.latitude
                existingStore.longitude = storeCoordinate.longitude
                existingStore.radius = 200
                existingStore.storeCategory = .grocery
                existingStore.notes = "DEBUG seed store for local notification and store-flow testing."
                existingStore.sourceType = .debugSeed
            } else {
                let seedStore = GeoLocation(
                    id: Self.seedStoreID,
                    title: Self.seedStoreName,
                    latitude: storeCoordinate.latitude,
                    longitude: storeCoordinate.longitude,
                    radius: 200,
                    storeCategory: .grocery,
                    notes: "DEBUG seed store for local notification and store-flow testing.",
                    sourceType: .debugSeed
                )
                modelContext.insert(seedStore)
            }

            try modelContext.save()
        } catch {
            print("[WayTask Debug Seed] Failed to seed store: \(error.localizedDescription)")
        }
    }

    private static func storeCoordinate(near coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D {
        guard let coordinate else {
            return fallbackCoordinate
        }

        return coordinate.offset(
            meters: seedOffsetDistance,
            bearingDegrees: seedOffsetBearingDegrees
        )
    }
}

private extension CLLocationCoordinate2D {
    func offset(meters: CLLocationDistance, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_378_137.0
        let bearing = bearingDegrees * .pi / 180
        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180
        let angularDistance = meters / earthRadius

        let destinationLatitude = asin(
            sin(latitudeRadians) * cos(angularDistance) +
            cos(latitudeRadians) * sin(angularDistance) * cos(bearing)
        )
        let destinationLongitude = longitudeRadians + atan2(
            sin(bearing) * sin(angularDistance) * cos(latitudeRadians),
            cos(angularDistance) - sin(latitudeRadians) * sin(destinationLatitude)
        )

        return CLLocationCoordinate2D(
            latitude: destinationLatitude * 180 / .pi,
            longitude: destinationLongitude * 180 / .pi
        )
    }
}
#endif
