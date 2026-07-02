import CoreLocation
import Foundation

struct StoreDataRequest: Sendable {
    let coordinate: CLLocationCoordinate2D?
    let shoppingItems: [String]
    let searchText: String?
    let radius: Double?

    init(
        coordinate: CLLocationCoordinate2D? = nil,
        shoppingItems: [String] = [],
        searchText: String? = nil,
        radius: Double? = nil
    ) {
        self.coordinate = coordinate
        self.shoppingItems = shoppingItems
        self.searchText = searchText
        self.radius = radius
    }
}

protocol StoreDataProvider: DataProvider where Request == StoreDataRequest, Response == [MapStore] {
    func stores(for request: StoreDataRequest) async throws -> [MapStore]
}

extension StoreDataProvider {
    func fetch(_ request: StoreDataRequest) async throws -> [MapStore] {
        try await stores(for: request)
    }
}
