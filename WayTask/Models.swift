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
    var addressText: String?
    var notes: String?
    var sourceTypeRawValue: String?

    @Relationship(deleteRule: .cascade)
    var shoppingItems: [ShoppingItem]

    init(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200.0,
        storeCategory: ShoppingStoreCategory? = nil,
        addressText: String? = nil,
        notes: String? = nil,
        sourceType: DataSourceType = .userGenerated,
        shoppingItems: [ShoppingItem] = []
    ) {
        self.id = id
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.storeCategoryRawValue = storeCategory?.rawValue
        self.addressText = addressText
        self.notes = notes
        self.sourceTypeRawValue = sourceType.rawValue
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

    var sourceType: DataSourceType {
        get {
            guard let sourceTypeRawValue else {
                return .userGenerated
            }

            return DataSourceType(rawValue: sourceTypeRawValue) ?? .userGenerated
        }
        set {
            sourceTypeRawValue = newValue.rawValue
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
    var productType: String?
    var flavor: String?
    var packageSize: String?
    var packageType: String?
    var visibleText: String?
    var searchKeywordsRawValue: String?

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
        source: ProductSource = .manual,
        productType: String? = nil,
        flavor: String? = nil,
        packageSize: String? = nil,
        packageType: String? = nil,
        visibleText: String? = nil,
        searchKeywords: [String] = []
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
        self.productType = productType
        self.flavor = flavor
        self.packageSize = packageSize
        self.packageType = packageType
        self.visibleText = visibleText
        self.searchKeywordsRawValue = Self.encodeSearchKeywords(searchKeywords)
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

    var searchKeywords: [String] {
        get {
            guard let searchKeywordsRawValue else {
                return []
            }

            return searchKeywordsRawValue
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            searchKeywordsRawValue = Self.encodeSearchKeywords(newValue)
        }
    }

    private static func encodeSearchKeywords(_ keywords: [String]) -> String? {
        let normalized = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return nil
        }

        return normalized.joined(separator: "\n")
    }
}
