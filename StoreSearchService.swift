import CoreLocation
import Foundation

protocol StoreSearchService {
    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory]
    ) -> [MapStore]
}

struct LocalStoreSearchService: StoreSearchService {
    private let provider = LocalStoreDataProvider()

    func fallbackStores(
        around coordinate: CLLocationCoordinate2D,
        shoppingItems: [String],
        storeCategories: [ShoppingStoreCategory] = []
    ) -> [MapStore] {
        provider.localStores(
            around: coordinate,
            shoppingItems: shoppingItems,
            storeCategories: storeCategories
        )
    }
}
