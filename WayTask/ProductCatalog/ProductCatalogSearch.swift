import Foundation

nonisolated enum CatalogProductMatchLevel: Int, Comparable, Sendable {
    case exactName
    case namePrefix
    case nameWordPrefix
    case nameContains
    case aliasPrefix
    case aliasContains
    case keywordPrefix
    case keywordContains
    case category

    static func < (
        lhs: CatalogProductMatchLevel,
        rhs: CatalogProductMatchLevel
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct CatalogProductSuggestion: Identifiable, Sendable {
    let product: CatalogProduct
    let matchLevel: CatalogProductMatchLevel
    let matchedValue: String
    let categoryDisplayName: String
    let iconKey: String
    let personalizationBoost: Int

    var id: String {
        product.id
    }

    func asProductSearchResult() -> ProductSearchResult {
        let authority: ProductSearchRecordAuthority
        let matchType: ProductSearchMatchType
        let secondaryName: String?

        switch matchLevel {
        case .exactName:
            authority = .primaryDisplayName
            matchType = .exact
            secondaryName = nil
        case .namePrefix:
            authority = .primaryDisplayName
            matchType = .fullNamePrefix
            secondaryName = nil
        case .nameWordPrefix, .nameContains:
            authority = .primaryDisplayName
            matchType = .wordPrefix
            secondaryName = nil
        case .aliasPrefix, .aliasContains:
            authority = .alias
            matchType = .wordPrefix
            secondaryName = matchedValue
        case .keywordPrefix, .keywordContains, .category:
            authority = .alias
            matchType = .wordPrefix
            secondaryName = nil
        }

        return ProductSearchResult(
            productID: ProductID(product.id),
            displayName: product.canonicalName,
            displayLocale: "he",
            secondaryName: secondaryName,
            categoryID: ProductCategoryID(product.categoryId),
            categoryDisplayName: categoryDisplayName,
            iconKey: iconKey,
            matchedRecordAuthority: authority,
            matchType: matchType,
            matchedLocale: "he"
        )
    }
}

typealias HebrewProductSearchNormalizedText =
    ProductKnowledgeNormalizedText

nonisolated enum HebrewProductSearchNormalizer {
    static func normalize(_ input: String) -> HebrewProductSearchNormalizedText {
        ProductKnowledgeNormalizer.searchText(
            input,
            localeIdentifier: "he-IL"
        )
    }
}

actor ProductCatalogSearch {
    static nonisolated let defaultResultLimit = 10
    static nonisolated let maximumResultLimit = 12

    private let products: [IndexedProduct]
    private var personalizationIndex = ProductCatalogPersonalizationIndex(
        history: []
    )

    init(products: [CatalogProduct]) {
        self.products = products
            .filter(\.isActive)
            .compactMap(IndexedProduct.init)
    }

    func suggestions(
        matching query: String,
        limit: Int = ProductCatalogSearch.defaultResultLimit,
        referenceDate: Date = Date()
    ) -> [CatalogProductSuggestion] {
        let normalizedQuery = HebrewProductSearchNormalizer.normalize(query)
        guard !normalizedQuery.value.isEmpty, limit > 0 else {
            return []
        }

        let ranked = products
            .compactMap {
                candidate(
                    for: $0,
                    query: normalizedQuery,
                    referenceDate: referenceDate
                )
            }
            .sorted(by: isRankedBefore)

        var seenIDs: Set<String> = []
        var seenNames: Set<String> = []
        var suggestions: [CatalogProductSuggestion] = []
        for candidate in ranked {
            guard seenIDs.insert(candidate.product.product.id).inserted,
                  seenNames.insert(candidate.product.name.value).inserted else {
                continue
            }

            suggestions.append(candidate.suggestion)
            if suggestions.count == min(limit, Self.maximumResultLimit) {
                break
            }
        }
        return suggestions
    }

    func updatePersonalization(
        _ history: [ProductCatalogSelectionHistory]
    ) {
        personalizationIndex = ProductCatalogPersonalizationIndex(
            history: history
        )
    }

    private func candidate(
        for product: IndexedProduct,
        query: HebrewProductSearchNormalizedText,
        referenceDate: Date
    ) -> RankedCandidate? {
        guard let match = bestMatch(for: product, query: query.value) else {
            return nil
        }

        let category = ProductCatalogCategoryMetadata.metadata(
            for: product.product.categoryId,
            subcategoryId: product.product.subcategoryId
        )
        let personalizationBoost = personalizationIndex.profile(
            catalogProductID: product.product.id,
            normalizedNames: product.personalizationNames
        )?.totalBoost(relativeTo: referenceDate) ?? 0
        return RankedCandidate(
            product: product,
            suggestion: CatalogProductSuggestion(
                product: product.product,
                matchLevel: match.level,
                matchedValue: match.value,
                categoryDisplayName: category.displayName,
                iconKey: category.iconKey,
                personalizationBoost: personalizationBoost
            ),
            finalScore:
                baseMatchScore(match.level)
                + product.product.popularityScore
                + personalizationBoost
        )
    }

    private func bestMatch(for product: IndexedProduct, query: String) -> Match? {
        let queryLength = query.unicodeScalars.filter { $0.value != 0x20 }.count
        if product.name.value == query {
            return Match(
                level: .exactName,
                value: product.product.canonicalName
            )
        }
        if product.name.value.hasPrefix(query) {
            return Match(
                level: .namePrefix,
                value: product.product.canonicalName
            )
        }
        if beginsAtWordBoundary(product.name.value, query: query) {
            return Match(
                level: .nameWordPrefix,
                value: product.product.canonicalName
            )
        }
        guard queryLength >= 3 else {
            return nil
        }
        if product.name.value.contains(query) {
            return Match(
                level: .nameContains,
                value: product.product.canonicalName
            )
        }
        if let alias = shortestMatch(
            in: product.aliases,
            where: { $0.normalized.value.hasPrefix(query) }
        ) {
            return Match(level: .aliasPrefix, value: alias.original)
        }
        if let alias = shortestMatch(
            in: product.aliases,
            where: { $0.normalized.value.contains(query) }
        ) {
            return Match(level: .aliasContains, value: alias.original)
        }
        guard queryLength >= 4 else {
            return nil
        }
        if let keyword = shortestMatch(
            in: product.keywords,
            where: { $0.normalized.value.hasPrefix(query) }
        ) {
            return Match(level: .keywordPrefix, value: keyword.original)
        }
        if let keyword = shortestMatch(
            in: product.keywords,
            where: { $0.normalized.value.contains(query) }
        ) {
            return Match(level: .keywordContains, value: keyword.original)
        }

        let category = ProductCatalogCategoryMetadata.metadata(
            for: product.product.categoryId,
            subcategoryId: product.product.subcategoryId
        )
        if category.searchTerms.contains(where: {
            let normalized = HebrewProductSearchNormalizer.normalize($0).value
            return normalized == query
                || (queryLength >= 4 && normalized.hasPrefix(query))
        }) {
            return Match(level: .category, value: category.displayName)
        }
        return nil
    }

    private func beginsAtWordBoundary(_ value: String, query: String) -> Bool {
        value.contains(" \(query)")
    }

    private func shortestMatch(
        in values: [IndexedValue],
        where predicate: (IndexedValue) -> Bool
    ) -> IndexedValue? {
        values
            .filter(predicate)
            .min {
                if $0.normalized.value.count != $1.normalized.value.count {
                    return $0.normalized.value.count < $1.normalized.value.count
                }
                return scalarLexicographicallyPrecedes($0.original, $1.original)
            }
    }

    private func isRankedBefore(_ lhs: RankedCandidate, _ rhs: RankedCandidate) -> Bool {
        if lhs.finalScore != rhs.finalScore {
            return lhs.finalScore > rhs.finalScore
        }
        if lhs.suggestion.matchLevel != rhs.suggestion.matchLevel {
            return lhs.suggestion.matchLevel < rhs.suggestion.matchLevel
        }
        if lhs.product.name.value.count != rhs.product.name.value.count {
            return lhs.product.name.value.count < rhs.product.name.value.count
        }
        if lhs.product.name.value != rhs.product.name.value {
            return scalarLexicographicallyPrecedes(
                lhs.product.name.value,
                rhs.product.name.value
            )
        }
        return scalarLexicographicallyPrecedes(
            lhs.product.product.id,
            rhs.product.product.id
        )
    }

    private func scalarLexicographicallyPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(
            rhs.unicodeScalars,
            by: { $0.value < $1.value }
        )
    }

    private func baseMatchScore(_ level: CatalogProductMatchLevel) -> Int {
        (CatalogProductMatchLevel.category.rawValue - level.rawValue + 1)
            * 1_000
    }
}

nonisolated private extension ProductCatalogSearch {
    struct IndexedValue: Sendable {
        let original: String
        let normalized: HebrewProductSearchNormalizedText
    }

    struct IndexedProduct: Sendable {
        let product: CatalogProduct
        let name: HebrewProductSearchNormalizedText
        let aliases: [IndexedValue]
        let keywords: [IndexedValue]
        let personalizationNames: [String]

        init?(product: CatalogProduct) {
            let name = HebrewProductSearchNormalizer.normalize(
                product.canonicalName
            )
            guard !name.value.isEmpty else {
                return nil
            }

            self.product = product
            self.name = name
            aliases = (
                product.aliases
                + product.brandTerms
                + product.legacyNames
            ).compactMap {
                let normalized = HebrewProductSearchNormalizer.normalize($0)
                return normalized.value.isEmpty
                    ? nil
                    : IndexedValue(original: $0, normalized: normalized)
            }
            keywords = product.keywords.compactMap {
                let normalized = HebrewProductSearchNormalizer.normalize($0)
                return normalized.value.isEmpty
                    ? nil
                    : IndexedValue(original: $0, normalized: normalized)
            }
            personalizationNames = ([name.value] + aliases.map(\.normalized.value))
                .reduce(into: [String]()) { result, value in
                    if !result.contains(value) {
                        result.append(value)
                    }
                }
        }
    }

    struct Match: Sendable {
        let level: CatalogProductMatchLevel
        let value: String
    }

    struct RankedCandidate: Sendable {
        let product: IndexedProduct
        let suggestion: CatalogProductSuggestion
        let finalScore: Int
    }
}
