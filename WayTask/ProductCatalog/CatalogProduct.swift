import Foundation

nonisolated struct CatalogProduct: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let categoryId: String
    let aliases: [String]
    let keywords: [String]
    let popularityScore: Int
    let isActive: Bool
}

nonisolated struct ProductCatalogDocument: Codable, Equatable, Sendable {
    let catalogVersion: Int
    let locale: String
    let products: [CatalogProduct]
}
