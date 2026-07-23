import Foundation

nonisolated enum ProductCategoryStatus: String, Codable, Hashable, Sendable {
    case active
    case inactive
}

nonisolated struct ProductCategoryNames: Codable, Hashable, Sendable {
    let en: String
    let he: String
}

nonisolated struct ProductCategory: Identifiable, Codable, Hashable, Sendable {
    let id: ProductCategoryID
    let names: ProductCategoryNames
    let iconKey: String
    let sortOrder: Int
    let status: ProductCategoryStatus
}
