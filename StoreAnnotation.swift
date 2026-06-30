import Foundation
import MapKit

final class StoreAnnotation: NSObject, MKAnnotation {
    let store: MapStore
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(store: MapStore) {
        self.store = store
        self.coordinate = store.coordinate
        self.title = store.title
        self.subtitle = store.matchingItemsLabel
        super.init()
    }
}
