import Foundation

nonisolated enum ProductNameKind: String, Codable, Hashable, Sendable {
    case canonical
    case localizedDisplay
    case alias

    var isDisplayCapable: Bool {
        self != .alias
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
