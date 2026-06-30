import Foundation
import MapKit

final class ProductAnnotation: NSObject, MKAnnotation {
    let product: MapProduct
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(product: MapProduct) {
        self.product = product
        self.coordinate = product.coordinate
        self.title = product.name
        self.subtitle = "Shopping item"
        super.init()
    }
}
