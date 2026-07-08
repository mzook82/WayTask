import CoreLocation
import Foundation

struct StoreCoverage: Identifiable {
    var id: String { "\(store.id.uuidString)-\(group.rawValue)" }

    let store: MapStore
    let group: ShoppingIntentGroup
    let matchedItems: [ShoppingItem]
    let missingItems: [ShoppingItem]
    let coverageScore: Double
    let distance: CLLocationDistance?
    let ranking: StoreScore

    var matchedItemCount: Int {
        matchedItems.count
    }

    var missingItemCount: Int {
        missingItems.count
    }

    var coversAllItems: Bool {
        !matchedItems.isEmpty && missingItems.isEmpty
    }
}
