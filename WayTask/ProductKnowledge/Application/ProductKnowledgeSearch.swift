import Foundation

actor ProductKnowledgeSearch {
    static nonisolated let defaultResultLimit = 8
    static nonisolated let maximumResultLimit = 20

    private let repository: any ProductKnowledgeRepository
    private var cachedIndex: ProductKnowledgeSearchIndex?
    private var indexLoadTask: Task<ProductKnowledgeSearchIndex, Never>?

    init(repository: any ProductKnowledgeRepository) {
        self.repository = repository
    }

    func suggestions(
        matching query: String,
        locale: String,
        limit: Int = ProductKnowledgeSearch.defaultResultLimit
    ) async -> [ProductSearchResult] {
        let normalizedQuery = ProductSearchNormalizer.normalize(query)
        guard !normalizedQuery.value.isEmpty, limit > 0 else {
            return []
        }

        let index = await searchIndex()
        return index.suggestions(
            matching: normalizedQuery,
            locale: locale,
            limit: min(limit, Self.maximumResultLimit)
        )
    }

    private func searchIndex() async -> ProductKnowledgeSearchIndex {
        if let cachedIndex {
            return cachedIndex
        }
        if let indexLoadTask {
            return await indexLoadTask.value
        }

        let repository = repository
        let task = Task {
            let snapshot = await repository.catalogSnapshot()
            return ProductKnowledgeSearchIndex(snapshot: snapshot)
        }
        indexLoadTask = task

        let index = await task.value
        cachedIndex = index
        indexLoadTask = nil
        return index
    }
}

nonisolated struct ProductSearchNormalizedText: Equatable, Sendable {
    let value: String
    let tokens: [String]
}

nonisolated enum ProductSearchNormalizer {
    private static let fixedLocale = Locale(identifier: "en_US_POSIX")
    private static let separator = UnicodeScalar(0x20)!

    static func normalize(_ input: String) -> ProductSearchNormalizedText {
        let decomposed = input.decomposedStringWithCompatibilityMapping
        let lowercased = decomposed.lowercased(with: fixedLocale)
        var normalizedScalars = String.UnicodeScalarView()
        var separatorPending = false

        for scalar in lowercased.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .uppercaseLetter,
                 .lowercaseLetter,
                 .titlecaseLetter,
                 .modifierLetter,
                 .otherLetter,
                 .decimalNumber:
                if separatorPending, !normalizedScalars.isEmpty {
                    normalizedScalars.append(separator)
                }
                normalizedScalars.append(scalar)
                separatorPending = false
            default:
                if !normalizedScalars.isEmpty {
                    separatorPending = true
                }
            }
        }

        let value = String(normalizedScalars)
        return ProductSearchNormalizedText(
            value: value,
            tokens: value.split(separator: " ").map(String.init)
        )
    }
}

nonisolated private struct ProductKnowledgeSearchIndex: Sendable {
    private let products: [IndexedProduct]

    init(snapshot: ProductKnowledgeSnapshot) {
        let categoriesByID = Dictionary(
            uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) }
        )
        let namesByProductID = Dictionary(grouping: snapshot.names, by: \.productID)

        products = snapshot.products.compactMap { product -> IndexedProduct? in
            guard product.status == .active else {
                return nil
            }

            let names = (namesByProductID[product.id] ?? []).compactMap {
                name -> IndexedName? in
                let normalized = ProductSearchNormalizer.normalize(name.value)
                guard !normalized.value.isEmpty else {
                    return nil
                }
                return IndexedName(record: name, normalized: normalized)
            }
            guard !names.isEmpty else {
                return nil
            }

            return IndexedProduct(
                entity: product,
                category: categoriesByID[product.primaryCategoryID],
                names: names
            )
        }
    }

    func suggestions(
        matching query: ProductSearchNormalizedText,
        locale: String,
        limit: Int
    ) -> [ProductSearchResult] {
        products
            .compactMap { rankedCandidate(for: $0, query: query, locale: locale) }
            .sorted(by: isRankedBefore)
            .prefix(limit)
            .map(\.result)
    }

    private func rankedCandidate(
        for product: IndexedProduct,
        query: ProductSearchNormalizedText,
        locale: String
    ) -> RankedProductCandidate? {
        guard let displayName = preferredDisplayName(
            for: product,
            requestedLocale: locale
        ) else {
            return nil
        }

        let matches = product.names.compactMap { name -> RankedNameMatch? in
            guard let match = match(name.normalized, query: query) else {
                return nil
            }

            let authority = authority(for: name.record, displayName: displayName.record)
            return RankedNameMatch(
                name: name,
                matchType: match.type,
                authority: authority,
                localeAffinity: localeAffinity(
                    name.record.locale,
                    requestedLocale: locale
                ),
                wordStartIndex: match.wordStartIndex
            )
        }
        guard let bestMatch = matches.min(by: isNameMatchRankedBefore) else {
            return nil
        }

        let displayNormalized = displayName.normalized
        let result = ProductSearchResult(
            productID: product.entity.id,
            displayName: displayName.record.value,
            secondaryName: bestMatch.name.record.value == displayName.record.value
                ? nil
                : bestMatch.name.record.value,
            categoryID: product.entity.primaryCategoryID,
            iconKey: product.category?.iconKey ?? "product.generic",
            matchedRecordAuthority: bestMatch.authority,
            matchType: bestMatch.matchType,
            matchedLocale: bestMatch.name.record.locale
        )

        return RankedProductCandidate(
            result: result,
            match: bestMatch,
            normalizedDisplayName: displayNormalized.value
        )
    }

    private func preferredDisplayName(
        for product: IndexedProduct,
        requestedLocale: String
    ) -> IndexedName? {
        let displayNames = product.names
            .filter { $0.record.isPreferred && $0.record.kind.isDisplayCapable }
            .sorted {
                scalarLexicographicallyPrecedes(
                    $0.record.id.rawValue,
                    $1.record.id.rawValue
                )
            }
        let normalizedRequestedLocale = normalizedLocale(requestedLocale)

        if let exact = displayNames.first(where: {
            normalizedLocale($0.record.locale) == normalizedRequestedLocale
        }) {
            return exact
        }

        let requestedLanguage = primaryLanguage(normalizedRequestedLocale)
        if let languageMatch = displayNames.first(where: {
            normalizedLocale($0.record.locale) == requestedLanguage
        }) {
            return languageMatch
        }

        if let english = displayNames.first(where: {
            normalizedLocale($0.record.locale) == "en"
        }) {
            return english
        }

        return product.names.first {
            $0.record.id == product.entity.defaultNameID
        }
    }

    private func match(
        _ candidate: ProductSearchNormalizedText,
        query: ProductSearchNormalizedText
    ) -> SearchMatch? {
        if candidate.value == query.value {
            return SearchMatch(type: .exact, wordStartIndex: 0)
        }

        if candidate.value.hasPrefix(query.value) {
            return SearchMatch(type: .fullNamePrefix, wordStartIndex: 0)
        }

        guard query.tokens.count <= candidate.tokens.count else {
            return nil
        }

        let lastStartIndex = candidate.tokens.count - query.tokens.count
        for startIndex in 0...lastStartIndex {
            let isMatch = query.tokens.indices.allSatisfy { queryIndex in
                candidate.tokens[startIndex + queryIndex]
                    .hasPrefix(query.tokens[queryIndex])
            }
            if isMatch {
                return SearchMatch(type: .wordPrefix, wordStartIndex: startIndex)
            }
        }

        return nil
    }

    private func authority(
        for name: ProductName,
        displayName: ProductName
    ) -> ProductSearchRecordAuthority {
        if name.id == displayName.id {
            return .primaryDisplayName
        }
        if name.isPreferred && name.kind.isDisplayCapable {
            return .preferredDisplayName
        }
        if name.kind.isDisplayCapable {
            return .displayName
        }
        return .alias
    }

    private func localeAffinity(
        _ nameLocale: String,
        requestedLocale: String
    ) -> Int {
        let normalizedNameLocale = normalizedLocale(nameLocale)
        let normalizedRequestedLocale = normalizedLocale(requestedLocale)

        if normalizedNameLocale == normalizedRequestedLocale {
            return 0
        }
        if primaryLanguage(normalizedNameLocale)
            == primaryLanguage(normalizedRequestedLocale) {
            return 1
        }
        if primaryLanguage(normalizedNameLocale) == "en" {
            return 2
        }
        return 3
    }

    private func normalizedLocale(_ locale: String) -> String {
        locale
            .replacingOccurrences(of: "_", with: "-")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func primaryLanguage(_ locale: String) -> String {
        locale
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? locale
    }

    private func isNameMatchRankedBefore(
        _ lhs: RankedNameMatch,
        _ rhs: RankedNameMatch
    ) -> Bool {
        if matchTypeRank(lhs.matchType) != matchTypeRank(rhs.matchType) {
            return matchTypeRank(lhs.matchType) < matchTypeRank(rhs.matchType)
        }
        if authorityRank(lhs.authority) != authorityRank(rhs.authority) {
            return authorityRank(lhs.authority) < authorityRank(rhs.authority)
        }
        if lhs.localeAffinity != rhs.localeAffinity {
            return lhs.localeAffinity < rhs.localeAffinity
        }
        if lhs.wordStartIndex != rhs.wordStartIndex {
            return lhs.wordStartIndex < rhs.wordStartIndex
        }
        if lhs.name.normalized.value.unicodeScalars.count
            != rhs.name.normalized.value.unicodeScalars.count {
            return lhs.name.normalized.value.unicodeScalars.count
                < rhs.name.normalized.value.unicodeScalars.count
        }
        if lhs.name.normalized.value != rhs.name.normalized.value {
            return scalarLexicographicallyPrecedes(
                lhs.name.normalized.value,
                rhs.name.normalized.value
            )
        }
        return scalarLexicographicallyPrecedes(
            lhs.name.record.id.rawValue,
            rhs.name.record.id.rawValue
        )
    }

    private func isRankedBefore(
        _ lhs: RankedProductCandidate,
        _ rhs: RankedProductCandidate
    ) -> Bool {
        if matchTypeRank(lhs.match.matchType) != matchTypeRank(rhs.match.matchType) {
            return matchTypeRank(lhs.match.matchType)
                < matchTypeRank(rhs.match.matchType)
        }
        if authorityRank(lhs.match.authority) != authorityRank(rhs.match.authority) {
            return authorityRank(lhs.match.authority)
                < authorityRank(rhs.match.authority)
        }
        if lhs.match.localeAffinity != rhs.match.localeAffinity {
            return lhs.match.localeAffinity < rhs.match.localeAffinity
        }
        if lhs.match.wordStartIndex != rhs.match.wordStartIndex {
            return lhs.match.wordStartIndex < rhs.match.wordStartIndex
        }
        if lhs.match.name.normalized.value.unicodeScalars.count
            != rhs.match.name.normalized.value.unicodeScalars.count {
            return lhs.match.name.normalized.value.unicodeScalars.count
                < rhs.match.name.normalized.value.unicodeScalars.count
        }
        if lhs.match.name.normalized.value != rhs.match.name.normalized.value {
            return scalarLexicographicallyPrecedes(
                lhs.match.name.normalized.value,
                rhs.match.name.normalized.value
            )
        }
        if lhs.normalizedDisplayName != rhs.normalizedDisplayName {
            return scalarLexicographicallyPrecedes(
                lhs.normalizedDisplayName,
                rhs.normalizedDisplayName
            )
        }
        return scalarLexicographicallyPrecedes(
            lhs.result.productID.rawValue,
            rhs.result.productID.rawValue
        )
    }

    private func matchTypeRank(_ type: ProductSearchMatchType) -> Int {
        switch type {
        case .exact:
            return 0
        case .fullNamePrefix:
            return 1
        case .wordPrefix:
            return 2
        }
    }

    private func authorityRank(_ authority: ProductSearchRecordAuthority) -> Int {
        switch authority {
        case .primaryDisplayName:
            return 0
        case .preferredDisplayName:
            return 1
        case .displayName:
            return 2
        case .alias:
            return 3
        }
    }

    private func scalarLexicographicallyPrecedes(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(
            rhs.unicodeScalars,
            by: { $0.value < $1.value }
        )
    }
}

nonisolated private extension ProductKnowledgeSearchIndex {
    struct IndexedProduct: Sendable {
        let entity: ProductEntity
        let category: ProductCategory?
        let names: [IndexedName]
    }

    struct IndexedName: Sendable {
        let record: ProductName
        let normalized: ProductSearchNormalizedText
    }

    struct SearchMatch: Sendable {
        let type: ProductSearchMatchType
        let wordStartIndex: Int
    }

    struct RankedNameMatch: Sendable {
        let name: IndexedName
        let matchType: ProductSearchMatchType
        let authority: ProductSearchRecordAuthority
        let localeAffinity: Int
        let wordStartIndex: Int
    }

    struct RankedProductCandidate: Sendable {
        let result: ProductSearchResult
        let match: RankedNameMatch
        let normalizedDisplayName: String
    }
}
