import Foundation

nonisolated enum ProductNameKind: String, Codable, Hashable, Sendable {
    case canonical
    case localizedDisplay
    case alias
    case keyword

    var isDisplayCapable: Bool {
        self == .canonical || self == .localizedDisplay
    }
}

nonisolated struct ProductName: Identifiable, Codable, Hashable, Sendable {
    let id: ProductNameID
    let productID: ProductID
    let locale: String
    let kind: ProductNameKind
    let value: String
    let isPreferred: Bool
}
