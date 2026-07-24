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

@Model
final class Product {
    var id: UUID
    var legacyShoppingItemID: UUID?
    var name: String
    var imageData: Data?
    var brand: String?
    var category: String?
    var barcode: String?
    var imageURLString: String?
    var dateAdded: Date
    var updatedAt: Date
    var sourceRawValue: String
    var productType: String?
    var flavor: String?
    var packageSize: String?
    var packageType: String?
    var visibleText: String?
    var searchKeywordsRawValue: String?
    var catalogProductIDRawValue: String?
    var catalogDisplayNameSnapshot: String?
    var catalogDisplayLocaleSnapshot: String?
    var catalogCategoryIDSnapshotRawValue: String?
    var catalogCategoryDisplayNameSnapshot: String?
    var catalogIconKeySnapshot: String?
    var catalogSnapshotUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        legacyShoppingItemID: UUID? = nil,
        name: String,
        imageData: Data? = nil,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        imageURL: URL? = nil,
        dateAdded: Date = Date(),
        updatedAt: Date = Date(),
        source: ProductSource = .manual,
        productType: String? = nil,
        flavor: String? = nil,
        packageSize: String? = nil,
        packageType: String? = nil,
        visibleText: String? = nil,
        searchKeywords: [String] = [],
        catalogProductIDRawValue: String? = nil,
        catalogDisplayNameSnapshot: String? = nil,
        catalogDisplayLocaleSnapshot: String? = nil,
        catalogCategoryIDSnapshotRawValue: String? = nil,
        catalogCategoryDisplayNameSnapshot: String? = nil,
        catalogIconKeySnapshot: String? = nil,
        catalogSnapshotUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.legacyShoppingItemID = legacyShoppingItemID
        self.name = name
        self.imageData = imageData
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.imageURLString = imageURL?.absoluteString
        self.dateAdded = dateAdded
        self.updatedAt = updatedAt
        self.sourceRawValue = source.rawValue
        self.productType = productType
        self.flavor = flavor
        self.packageSize = packageSize
        self.packageType = packageType
        self.visibleText = visibleText
        self.searchKeywordsRawValue = Self.encodeSearchKeywords(searchKeywords)
        self.catalogProductIDRawValue = catalogProductIDRawValue
        self.catalogDisplayNameSnapshot = catalogDisplayNameSnapshot
        self.catalogDisplayLocaleSnapshot = catalogDisplayLocaleSnapshot
        self.catalogCategoryIDSnapshotRawValue = catalogCategoryIDSnapshotRawValue
        self.catalogCategoryDisplayNameSnapshot = catalogCategoryDisplayNameSnapshot
        self.catalogIconKeySnapshot = catalogIconKeySnapshot
        self.catalogSnapshotUpdatedAt = catalogSnapshotUpdatedAt
    }

    convenience init(legacyItem item: ShoppingItem) {
        self.init(
            legacyShoppingItemID: item.id,
            name: item.name,
            imageData: item.imageData,
            brand: item.brand,
            category: item.category,
            barcode: item.barcode,
            imageURL: item.imageURL,
            dateAdded: item.dateAdded,
            updatedAt: Date(),
            source: item.source,
            productType: item.productType,
            flavor: item.flavor,
            packageSize: item.packageSize,
            packageType: item.packageType,
            visibleText: item.visibleText,
            searchKeywords: item.searchKeywords
        )
    }

    convenience init(candidate: ProductCandidate, fallbackImageData: Data?) {
        let source: ProductSource
        switch candidate.source {
        case .cameraPhoto, .photoLibrary:
            source = .camera
        case .barcode:
            source = .barcode
        case .ai:
            source = .ai
        case .manual:
            source = .manual
        case .unknown:
            source = .manual
        }

        self.init(
            name: candidate.name,
            imageData: Self.productImageData(for: candidate, fallbackImageData: fallbackImageData),
            brand: candidate.brand,
            category: candidate.category,
            barcode: candidate.barcode,
            imageURL: candidate.imageURL,
            dateAdded: Date(),
            updatedAt: Date(),
            source: source,
            productType: candidate.productType,
            flavor: candidate.flavor,
            packageSize: candidate.packageSize,
            packageType: candidate.packageType,
            visibleText: candidate.visibleText,
            searchKeywords: candidate.searchKeywords.isEmpty ? candidate.productHints : candidate.searchKeywords
        )
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

    var catalogProductID: ProductID? {
        guard let catalogProductIDRawValue else {
            return nil
        }

        let trimmed = catalogProductIDRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == catalogProductIDRawValue else {
            return nil
        }

        return ProductID(catalogProductIDRawValue)
    }

    var isCatalogLinked: Bool {
        catalogProductIDRawValue != nil
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

    func refresh(from item: ShoppingItem) {
        guard !isCatalogLinked else {
            return
        }

        let nextImageURLString = item.imageURL?.absoluteString
        let nextSearchKeywordsRawValue = Self.encodeSearchKeywords(item.searchKeywords)

        guard legacyShoppingItemID != item.id ||
            name != item.name ||
            imageData != item.imageData ||
            brand != item.brand ||
            category != item.category ||
            barcode != item.barcode ||
            imageURLString != nextImageURLString ||
            sourceRawValue != item.source.rawValue ||
            productType != item.productType ||
            flavor != item.flavor ||
            packageSize != item.packageSize ||
            packageType != item.packageType ||
            visibleText != item.visibleText ||
            searchKeywordsRawValue != nextSearchKeywordsRawValue else {
            return
        }

        legacyShoppingItemID = item.id
        name = item.name
        imageData = item.imageData
        brand = item.brand
        category = item.category
        barcode = item.barcode
        imageURLString = nextImageURLString
        sourceRawValue = item.source.rawValue
        productType = item.productType
        flavor = item.flavor
        packageSize = item.packageSize
        packageType = item.packageType
        visibleText = item.visibleText
        searchKeywordsRawValue = nextSearchKeywordsRawValue
        updatedAt = Date()
    }

    func refresh(from candidate: ProductCandidate, fallbackImageData: Data?) {
        guard !isCatalogLinked else {
            return
        }

        let incomingImageData = Self.productImageData(for: candidate, fallbackImageData: fallbackImageData)
        let nextImageData = incomingImageData ?? imageData
        let nextImageURLString = candidate.imageURL?.absoluteString
        let nextSearchKeywords = candidate.searchKeywords.isEmpty ? candidate.productHints : candidate.searchKeywords
        let nextSearchKeywordsRawValue = Self.encodeSearchKeywords(nextSearchKeywords)
        let nextSource = Self.source(for: candidate.source)
        let nextBrand = candidate.brand ?? brand
        let nextCategory = candidate.category ?? category
        let nextBarcode = candidate.barcode ?? barcode
        let nextProductType = candidate.productType ?? productType
        let nextFlavor = candidate.flavor ?? flavor
        let nextPackageSize = candidate.packageSize ?? packageSize
        let nextPackageType = candidate.packageType ?? packageType
        let nextVisibleText = candidate.visibleText ?? visibleText

        guard name != candidate.name ||
            imageData != nextImageData ||
            brand != nextBrand ||
            category != nextCategory ||
            barcode != nextBarcode ||
            imageURLString != nextImageURLString ||
            sourceRawValue != nextSource.rawValue ||
            productType != nextProductType ||
            flavor != nextFlavor ||
            packageSize != nextPackageSize ||
            packageType != nextPackageType ||
            visibleText != nextVisibleText ||
            searchKeywordsRawValue != nextSearchKeywordsRawValue else {
            return
        }

        name = candidate.name
        imageData = nextImageData
        brand = nextBrand
        category = nextCategory
        barcode = nextBarcode
        imageURLString = nextImageURLString ?? imageURLString
        sourceRawValue = nextSource.rawValue
        productType = nextProductType
        flavor = nextFlavor
        packageSize = nextPackageSize
        packageType = nextPackageType
        visibleText = nextVisibleText
        searchKeywordsRawValue = nextSearchKeywordsRawValue ?? searchKeywordsRawValue
        updatedAt = Date()
    }

    func makeShoppingItem() -> ShoppingItem {
        ShoppingItem(
            name: name,
            isCompleted: false,
            imageData: imageData,
            brand: brand,
            category: category,
            barcode: barcode,
            imageURL: imageURL,
            dateAdded: Date(),
            source: source,
            productType: productType,
            flavor: flavor,
            packageSize: packageSize,
            packageType: packageType,
            visibleText: visibleText,
            searchKeywords: searchKeywords
        )
    }

    private static func source(for candidateSource: ProductCandidateSource) -> ProductSource {
        switch candidateSource {
        case .cameraPhoto, .photoLibrary:
            return .camera
        case .barcode:
            return .barcode
        case .ai:
            return .ai
        case .manual:
            return .manual
        case .unknown:
            return .manual
        }
    }

    private static func productImageData(for candidate: ProductCandidate, fallbackImageData: Data?) -> Data? {
        if let imageData = candidate.imageData {
            return imageData
        }

        if candidate.imageURL != nil {
            return nil
        }

        return fallbackImageData
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

enum ShoppingListKind: String, Codable, CaseIterable, Sendable {
    case weekly
    case completed
    case recent
}

@Model
final class ShoppingList {
    var id: UUID
    var title: String
    var kindRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kind: ShoppingListKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDefault = isDefault
    }

    var kind: ShoppingListKind {
        get { ShoppingListKind(rawValue: kindRawValue) ?? .weekly }
        set {
            kindRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}

@Model
final class ShoppingListEntry {
    var id: UUID
    var shoppingListID: UUID
    var productID: UUID
    var legacyShoppingItemID: UUID?
    var quantity: Double
    var isChecked: Bool
    var createdAt: Date
    var sortOrder: Double

    @Relationship(deleteRule: .nullify)
    var product: Product?

    init(
        id: UUID = UUID(),
        shoppingListID: UUID,
        product: Product,
        legacyShoppingItemID: UUID? = nil,
        quantity: Double = 1,
        isChecked: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Double = 0
    ) {
        self.id = id
        self.shoppingListID = shoppingListID
        self.productID = product.id
        self.legacyShoppingItemID = legacyShoppingItemID
        self.quantity = quantity
        self.isChecked = isChecked
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.product = product
    }
}
