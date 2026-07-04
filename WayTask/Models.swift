import Foundation
import SwiftData

@Model
final class GeoLocation {
    var id: UUID
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var storeCategoryRawValue: String?
    var notes: String?

    @Relationship(deleteRule: .cascade)
    var shoppingItems: [ShoppingItem]

    init(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200.0,
        storeCategory: ShoppingStoreCategory? = nil,
        notes: String? = nil,
        shoppingItems: [ShoppingItem] = []
    ) {
        self.id = id
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.storeCategoryRawValue = storeCategory?.rawValue
        self.notes = notes
        self.shoppingItems = shoppingItems
    }

    var storeCategory: ShoppingStoreCategory? {
        get {
            guard let storeCategoryRawValue else {
                return nil
            }

            return ShoppingStoreCategory(rawValue: storeCategoryRawValue)
        }
        set {
            storeCategoryRawValue = newValue?.rawValue
        }
    }
}

@Model
final class ShoppingItem {
    var id: UUID
    var name: String
    var isCompleted: Bool
    var imageData: Data?
    var brand: String?
    var category: String?
    var barcode: String?
    var imageURLString: String?
    var dateAdded: Date
    var sourceRawValue: String

    init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        imageData: Data? = nil,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        imageURL: URL? = nil,
        dateAdded: Date = Date(),
        source: ProductSource = .manual
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.imageData = imageData
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.imageURLString = imageURL?.absoluteString
        self.dateAdded = dateAdded
        self.sourceRawValue = source.rawValue
    }

    var imageURL: URL? {
        guard let imageURLString else {
            return nil
        }

        return URL(string: imageURLString)
    }

    var source: ProductSource {
        ProductSource(rawValue: sourceRawValue) ?? .manual
    }
}
