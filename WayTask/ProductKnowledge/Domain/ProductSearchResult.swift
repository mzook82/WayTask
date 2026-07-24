import Foundation

nonisolated enum ProductSearchMatchType: Hashable, Sendable {
    case exact
    case fullNamePrefix
    case wordPrefix
}

nonisolated enum ProductSearchRecordAuthority: Hashable, Sendable {
    case primaryDisplayName
    case preferredDisplayName
    case displayName
    case alias
}

nonisolated struct ProductSearchResult: Identifiable, Hashable, Sendable {
    let productID: ProductID
    let displayName: String
    let displayLocale: String
    let secondaryName: String?
    let categoryID: ProductCategoryID
    let categoryDisplayName: String
    let iconKey: String
    let matchedRecordAuthority: ProductSearchRecordAuthority
    let matchType: ProductSearchMatchType
    let matchedLocale: String

    var id: ProductID {
        productID
    }
}
