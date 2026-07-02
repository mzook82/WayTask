import CoreLocation
import Foundation

struct LocalStoreDataProvider: StoreDataProvider {
    let sourceType: DataSourceType = .local
    let displayName = "Local Store Data"

    func stores(for request: StoreDataRequest) async throws -> [MapStore] {
        guard let coordinate = request.coordinate else {
            return []
        }

        return localStores(around: coordinate, shoppingItems: request.shoppingItems)
    }

    func localStores(around coordinate: CLLocationCoordinate2D, shoppingItems: [String]) -> [MapStore] {
        let activeItems = shoppingItems.isEmpty ? ["Shopping list"] : shoppingItems

        return [
            makeStore(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID(),
                title: "Nearby Market",
                coordinate: offset(coordinate, latitude: 0.0024, longitude: 0.0018),
                itemNames: Array(activeItems.prefix(3)),
                radius: 180,
                rating: 4.7,
                websiteURL: URL(string: "https://maps.apple.com")
            ),
            makeStore(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID(),
                title: "Local Pharmacy",
                coordinate: offset(coordinate, latitude: -0.0019, longitude: 0.0022),
                itemNames: Array(activeItems.suffix(min(activeItems.count, 2))),
                radius: 160,
                rating: 4.5,
                websiteURL: nil
            ),
            makeStore(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003") ?? UUID(),
                title: "Corner Grocery",
                coordinate: offset(coordinate, latitude: 0.0015, longitude: -0.0027),
                itemNames: Array(activeItems.prefix(2)),
                radius: 140,
                rating: 4.6,
                websiteURL: nil
            )
        ]
    }

    private func makeStore(
        id: UUID,
        title: String,
        coordinate: CLLocationCoordinate2D,
        itemNames: [String],
        radius: Double,
        rating: Double,
        websiteURL: URL?
    ) -> MapStore {
        MapStore(
            id: id,
            locationID: nil,
            title: title,
            coordinate: coordinate,
            radius: radius,
            itemNames: itemNames,
            completedItemNames: [],
            isOpen: true,
            rating: rating,
            websiteURL: websiteURL
        )
    }

    private func offset(_ coordinate: CLLocationCoordinate2D, latitude: CLLocationDegrees, longitude: CLLocationDegrees) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitude,
            longitude: coordinate.longitude + longitude
        )
    }
}
