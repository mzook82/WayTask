import Foundation

nonisolated enum ProductSearchMatchType: Hashable, Sendable {
    case exact
    case fullNamePrefix
    case wordPrefix
    case category
    case fallback
}

nonisolated enum ProductSearchRecordAuthority: Hashable, Sendable {
    case primaryDisplayName
    case preferredDisplayName
    case displayName
    case alias
    case keyword
    case category
}

/// Public ranking metadata retained for future match highlighting and search
/// diagnostics. Raw values are the documented deterministic contract.
nonisolated enum ProductSearchMatchTier: Int, Codable, Hashable, Sendable {
    case exactCanonical = 0
    case exactAlias = 1
    case canonicalPrefix = 2
    case aliasPrefix = 3
    case tokenPrefix = 4
    case categoryRelevance = 5
    case conservativeFallback = 6
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
    let matchTier: ProductSearchMatchTier
    let matchedValue: String
    let normalizedMatchedValue: String
    let matchedLocale: String

    var id: ProductID {
        productID
    }

    init(
        productID: ProductID,
        displayName: String,
        displayLocale: String,
        secondaryName: String?,
        categoryID: ProductCategoryID,
        categoryDisplayName: String,
        iconKey: String,
        matchedRecordAuthority: ProductSearchRecordAuthority,
        matchType: ProductSearchMatchType,
        matchTier: ProductSearchMatchTier? = nil,
        matchedValue: String? = nil,
        normalizedMatchedValue: String? = nil,
        matchedLocale: String
    ) {
        self.productID = productID
        self.displayName = displayName
        self.displayLocale = displayLocale
        self.secondaryName = secondaryName
        self.categoryID = categoryID
        self.categoryDisplayName = categoryDisplayName
        self.iconKey = iconKey
        self.matchedRecordAuthority = matchedRecordAuthority
        self.matchType = matchType
        self.matchTier = matchTier ?? Self.compatibilityTier(
            authority: matchedRecordAuthority,
            matchType: matchType
        )
        self.matchedValue = matchedValue ?? secondaryName ?? displayName
        self.normalizedMatchedValue = normalizedMatchedValue
            ?? ProductSearchNormalizer.normalize(
                matchedValue ?? secondaryName ?? displayName
            ).value
        self.matchedLocale = matchedLocale
    }

    private static func compatibilityTier(
        authority: ProductSearchRecordAuthority,
        matchType: ProductSearchMatchType
    ) -> ProductSearchMatchTier {
        switch matchType {
        case .exact:
            return authority == .alias ? .exactAlias : .exactCanonical
        case .fullNamePrefix:
            return authority == .alias ? .aliasPrefix : .canonicalPrefix
        case .wordPrefix:
            return .tokenPrefix
        case .category:
            return .categoryRelevance
        case .fallback:
            return .conservativeFallback
        }
    }
}
