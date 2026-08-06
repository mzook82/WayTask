import Foundation

nonisolated struct ProductKnowledgeSearchIndexStatistics: Equatable, Sendable {
    let productCount: Int
    let searchableNameCount: Int
    let exactKeyCount: Int
    let prefixKeyCount: Int
    let tokenPrefixKeyCount: Int
    let categoryKeyCount: Int
    let trigramKeyCount: Int
    /// Deterministic lower-bound diagnostic, not process resident memory.
    let estimatedIndexedUTF8Bytes: Int
}

actor ProductKnowledgeSearch {
    static nonisolated let defaultResultLimit = 10
    static nonisolated let maximumResultLimit = 20

    private let repository: any ProductKnowledgeRepository
    private var cachedIndex: ProductKnowledgeSearchIndex?
    private var indexLoadTask: Task<ProductKnowledgeSearchIndex, Never>?

    init(repository: any ProductKnowledgeRepository) {
        self.repository = repository
    }

    func prepare() async {
        _ = await searchIndex()
    }

    func indexStatistics() async -> ProductKnowledgeSearchIndexStatistics {
        await searchIndex().statistics
    }

    func suggestions(
        matching query: String,
        locale: String,
        limit: Int = ProductKnowledgeSearch.defaultResultLimit
    ) async -> [ProductSearchResult] {
        let normalizedQuery = ProductSearchNormalizer.normalize(
            query,
            localeIdentifier: locale
        )
        guard !normalizedQuery.value.isEmpty,
              limit > 0,
              !Task.isCancelled else {
            return []
        }

        let index = await searchIndex()
        guard !Task.isCancelled else { return [] }
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

/// Immutable index built once per catalog snapshot. Exact, full-prefix,
/// token-prefix, category, and trigram candidate maps avoid normalizing or
/// scanning the complete catalog on ordinary keystrokes.
nonisolated private struct ProductKnowledgeSearchIndex: Sendable {
    let statistics: ProductKnowledgeSearchIndexStatistics

    private let products: [IndexedProduct]
    private let canonicalExact: [String: [Int]]
    private let aliasExact: [String: [Int]]
    private let canonicalPrefixes: [String: [Int]]
    private let aliasPrefixes: [String: [Int]]
    private let tokenPrefixes: [String: [Int]]
    private let categoryPrefixes: [String: [Int]]
    private let fallbackTrigrams: [String: [Int]]

    init(snapshot: ProductKnowledgeSnapshot) {
        let categoriesByID = Dictionary(
            snapshot.categories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let namesByProductID = Dictionary(grouping: snapshot.names, by: \.productID)

        var indexedProducts: [IndexedProduct] = []
        for product in snapshot.products where product.status == .active {
            let names = (namesByProductID[product.id] ?? []).compactMap {
                name -> IndexedName? in
                let normalized = ProductSearchNormalizer.normalize(
                    name.value,
                    localeIdentifier: name.locale
                )
                guard !normalized.value.isEmpty else { return nil }
                return IndexedName(record: name, normalized: normalized)
            }
            guard !names.isEmpty else { continue }

            let category = categoriesByID[product.primaryCategoryID]
            let categoryTerms = [category?.names.en, category?.names.he]
                .compactMap { $0 }
                .map { ProductSearchNormalizer.normalize($0) }
                .filter { !$0.value.isEmpty }
            indexedProducts.append(
                IndexedProduct(
                    entity: product,
                    category: category,
                    categoryTerms: categoryTerms,
                    names: names
                )
            )
        }

        var canonicalExact: [String: [Int]] = [:]
        var aliasExact: [String: [Int]] = [:]
        var canonicalPrefixes: [String: [Int]] = [:]
        var aliasPrefixes: [String: [Int]] = [:]
        var tokenPrefixes: [String: [Int]] = [:]
        var categoryPrefixes: [String: [Int]] = [:]
        var fallbackTrigrams: [String: [Int]] = [:]
        var indexedBytes = 0

        for (productIndex, product) in indexedProducts.enumerated() {
            for name in product.names {
                let value = name.normalized.value
                indexedBytes += value.utf8.count
                switch name.record.kind {
                case .canonical, .localizedDisplay:
                    Self.append(productIndex, key: value, to: &canonicalExact)
                    Self.indexPrefixes(
                        value,
                        productIndex: productIndex,
                        into: &canonicalPrefixes
                    )
                case .alias:
                    Self.append(productIndex, key: value, to: &aliasExact)
                    Self.indexPrefixes(
                        value,
                        productIndex: productIndex,
                        into: &aliasPrefixes
                    )
                case .keyword:
                    break
                }

                for token in name.normalized.tokens {
                    Self.indexPrefixes(
                        token,
                        productIndex: productIndex,
                        into: &tokenPrefixes
                    )
                }
                Self.indexTrigrams(
                    value,
                    productIndex: productIndex,
                    into: &fallbackTrigrams
                )
            }

            for category in product.categoryTerms {
                indexedBytes += category.value.utf8.count
                Self.indexPrefixes(
                    category.value,
                    productIndex: productIndex,
                    into: &categoryPrefixes
                )
                for token in category.tokens {
                    Self.indexPrefixes(
                        token,
                        productIndex: productIndex,
                        into: &categoryPrefixes
                    )
                }
            }
        }

        products = indexedProducts
        self.canonicalExact = canonicalExact
        self.aliasExact = aliasExact
        self.canonicalPrefixes = canonicalPrefixes
        self.aliasPrefixes = aliasPrefixes
        self.tokenPrefixes = tokenPrefixes
        self.categoryPrefixes = categoryPrefixes
        self.fallbackTrigrams = fallbackTrigrams
        statistics = ProductKnowledgeSearchIndexStatistics(
            productCount: indexedProducts.count,
            searchableNameCount: indexedProducts.reduce(0) {
                $0 + $1.names.count
            },
            exactKeyCount: canonicalExact.count + aliasExact.count,
            prefixKeyCount: canonicalPrefixes.count + aliasPrefixes.count,
            tokenPrefixKeyCount: tokenPrefixes.count,
            categoryKeyCount: categoryPrefixes.count,
            trigramKeyCount: fallbackTrigrams.count,
            estimatedIndexedUTF8Bytes: indexedBytes
                + Self.keyByteCount(canonicalExact)
                + Self.keyByteCount(aliasExact)
                + Self.keyByteCount(canonicalPrefixes)
                + Self.keyByteCount(aliasPrefixes)
                + Self.keyByteCount(tokenPrefixes)
                + Self.keyByteCount(categoryPrefixes)
                + Self.keyByteCount(fallbackTrigrams)
        )
    }

    func suggestions(
        matching query: ProductSearchNormalizedText,
        locale: String,
        limit: Int
    ) -> [ProductSearchResult] {
        let candidates = candidateIndices(for: query)
        var ranked: [RankedProductCandidate] = []
        ranked.reserveCapacity(min(candidates.count, limit * 4))

        for productIndex in candidates.sorted() {
            guard !Task.isCancelled else { return [] }
            if let value = rankedCandidate(
                for: products[productIndex],
                query: query,
                locale: locale
            ) {
                ranked.append(value)
            }
        }

        return ranked
            .sorted(by: isRankedBefore)
            .prefix(limit)
            .map(\.result)
    }

    private func candidateIndices(
        for query: ProductSearchNormalizedText
    ) -> Set<Int> {
        var result: Set<Int> = []
        result.formUnion(canonicalExact[query.value] ?? [])
        result.formUnion(aliasExact[query.value] ?? [])
        result.formUnion(canonicalPrefixes[query.value] ?? [])
        result.formUnion(aliasPrefixes[query.value] ?? [])
        if let tokenCandidates = intersectedCandidates(
            for: query.tokens,
            in: tokenPrefixes
        ) {
            result.formUnion(tokenCandidates)
        }
        result.formUnion(categoryPrefixes[query.value] ?? [])

        // Fallback substring candidates are intentionally considered only
        // when none of the higher-quality indexes produced a candidate. This
        // keeps exact and prefix queries proportional to their result set
        // instead of to every record sharing a common first trigram.
        if result.isEmpty,
           query.value.count >= 4,
           let fallbackCandidates = intersectedCandidates(
                for: Array(Set(Self.trigrams(query.value))),
                in: fallbackTrigrams
           ) {
            result.formUnion(fallbackCandidates)
        }
        return result
    }

    private func intersectedCandidates(
        for keys: [String],
        in index: [String: [Int]]
    ) -> Set<Int>? {
        guard !keys.isEmpty else { return nil }
        let candidateLists = keys.compactMap { key -> [Int]? in
            guard let values = index[key], !values.isEmpty else { return nil }
            return values
        }
        guard candidateLists.count == keys.count,
              let smallest = candidateLists.min(by: { $0.count < $1.count }) else {
            return nil
        }

        var result = Set(smallest)
        for values in candidateLists where values.count != smallest.count
            || values != smallest {
            result.formIntersection(values)
            if result.isEmpty { break }
        }
        return result
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

        var matches = product.names.compactMap { name -> RankedMatch? in
            guard let quality = nameMatch(name, query: query) else {
                return nil
            }
            return RankedMatch(
                tier: quality.tier,
                matchType: quality.matchType,
                authority: authority(
                    for: name.record,
                    displayName: displayName.record
                ),
                matchedValue: name.record.value,
                normalizedMatchedValue: name.normalized.value,
                matchedLocale: name.record.locale,
                localeAffinity: localeAffinity(
                    name.record.locale,
                    requestedLocale: locale
                ),
                wordStartIndex: quality.wordStartIndex,
                recordID: name.record.id.rawValue
            )
        }
        matches.append(contentsOf: categoryMatches(
            product,
            query: query,
            requestedLocale: locale
        ))
        guard let bestMatch = matches.min(by: isMatchRankedBefore) else {
            return nil
        }

        let secondaryName: String?
        if bestMatch.authority == .alias
            || bestMatch.authority == .preferredDisplayName
            || bestMatch.authority == .displayName {
            secondaryName = bestMatch.matchedValue == displayName.record.value
                ? nil
                : bestMatch.matchedValue
        } else {
            secondaryName = nil
        }

        let result = ProductSearchResult(
            productID: product.entity.id,
            displayName: displayName.record.value,
            displayLocale: displayName.record.locale,
            secondaryName: secondaryName,
            categoryID: product.entity.primaryCategoryID,
            categoryDisplayName: categoryDisplayName(
                for: product.category,
                requestedLocale: locale
            ),
            iconKey: product.entity.iconKey
                ?? product.category?.iconKey
                ?? "product.generic",
            matchedRecordAuthority: bestMatch.authority,
            matchType: bestMatch.matchType,
            matchTier: bestMatch.tier,
            matchedValue: bestMatch.matchedValue,
            normalizedMatchedValue: bestMatch.normalizedMatchedValue,
            matchedLocale: bestMatch.matchedLocale
        )

        return RankedProductCandidate(
            result: result,
            match: bestMatch,
            normalizedDisplayName: displayName.normalized.value
        )
    }

    private func nameMatch(
        _ candidate: IndexedName,
        query: ProductSearchNormalizedText
    ) -> SearchQuality? {
        let isAlias = candidate.record.kind == .alias
        let isKeyword = candidate.record.kind == .keyword

        if candidate.normalized.value == query.value {
            if isKeyword {
                return SearchQuality(
                    tier: .conservativeFallback,
                    matchType: .fallback,
                    wordStartIndex: 0
                )
            }
            return SearchQuality(
                tier: isAlias ? .exactAlias : .exactCanonical,
                matchType: .exact,
                wordStartIndex: 0
            )
        }

        if candidate.normalized.value.hasPrefix(query.value) {
            if isKeyword {
                return SearchQuality(
                    tier: .conservativeFallback,
                    matchType: .fallback,
                    wordStartIndex: 0
                )
            }
            return SearchQuality(
                tier: isAlias ? .aliasPrefix : .canonicalPrefix,
                matchType: .fullNamePrefix,
                wordStartIndex: 0
            )
        }

        if let wordStart = contiguousTokenPrefixStart(
            candidate.normalized.tokens,
            queryTokens: query.tokens
        ) {
            return SearchQuality(
                tier: isKeyword
                    ? .conservativeFallback
                    : .tokenPrefix,
                matchType: isKeyword ? .fallback : .wordPrefix,
                wordStartIndex: wordStart
            )
        }

        guard query.value.count >= 4,
              candidate.normalized.value.contains(query.value) else {
            return nil
        }
        return SearchQuality(
            tier: .conservativeFallback,
            matchType: .fallback,
            wordStartIndex: Int.max
        )
    }

    private func categoryMatches(
        _ product: IndexedProduct,
        query: ProductSearchNormalizedText,
        requestedLocale: String
    ) -> [RankedMatch] {
        product.categoryTerms.compactMap { category -> RankedMatch? in
            let matches = category.value == query.value
                || category.value.hasPrefix(query.value)
                || contiguousTokenPrefixStart(
                    category.tokens,
                    queryTokens: query.tokens
                ) != nil
            guard matches else { return nil }
            let categoryLocale = primaryLanguage(normalizedLocale(requestedLocale))
                == "he" ? "he" : "en"
            return RankedMatch(
                tier: .categoryRelevance,
                matchType: .category,
                authority: .category,
                matchedValue: category.value,
                normalizedMatchedValue: category.value,
                matchedLocale: categoryLocale,
                localeAffinity: 0,
                wordStartIndex: 0,
                recordID: "category:\(product.entity.primaryCategoryID.rawValue)"
            )
        }
    }

    private func contiguousTokenPrefixStart(
        _ candidateTokens: [String],
        queryTokens: [String]
    ) -> Int? {
        guard !queryTokens.isEmpty,
              queryTokens.count <= candidateTokens.count else {
            return nil
        }
        let lastStartIndex = candidateTokens.count - queryTokens.count
        for startIndex in 0...lastStartIndex {
            if queryTokens.indices.allSatisfy({ queryIndex in
                candidateTokens[startIndex + queryIndex]
                    .hasPrefix(queryTokens[queryIndex])
            }) {
                return startIndex
            }
        }
        return nil
    }

    private func categoryDisplayName(
        for category: ProductCategory?,
        requestedLocale: String
    ) -> String {
        if primaryLanguage(normalizedLocale(requestedLocale)) == "he" {
            return category?.names.he ?? "ללא קטגוריה"
        }
        return category?.names.en ?? "Uncategorized"
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
        let requested = normalizedLocale(requestedLocale)

        if let exact = displayNames.first(where: {
            normalizedLocale($0.record.locale) == requested
        }) {
            return exact
        }

        let language = primaryLanguage(requested)
        if let languageMatch = displayNames.first(where: {
            primaryLanguage(normalizedLocale($0.record.locale)) == language
        }) {
            return languageMatch
        }

        if let english = displayNames.first(where: {
            primaryLanguage(normalizedLocale($0.record.locale)) == "en"
        }) {
            return english
        }

        return product.names.first {
            $0.record.id == product.entity.defaultNameID
        }
    }

    private func authority(
        for name: ProductName,
        displayName: ProductName
    ) -> ProductSearchRecordAuthority {
        if name.id == displayName.id {
            return .primaryDisplayName
        }
        if name.kind == .alias {
            return .alias
        }
        if name.kind == .keyword {
            return .keyword
        }
        if name.isPreferred && name.kind.isDisplayCapable {
            return .preferredDisplayName
        }
        return .displayName
    }

    private func localeAffinity(
        _ nameLocale: String,
        requestedLocale: String
    ) -> Int {
        let name = normalizedLocale(nameLocale)
        let requested = normalizedLocale(requestedLocale)
        if name == requested { return 0 }
        if primaryLanguage(name) == primaryLanguage(requested) { return 1 }
        if primaryLanguage(name) == "en" { return 2 }
        return 3
    }

    private func normalizedLocale(_ locale: String) -> String {
        locale
            .replacingOccurrences(of: "_", with: "-")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func primaryLanguage(_ locale: String) -> String {
        locale.split(separator: "-", maxSplits: 1).first.map(String.init)
            ?? locale
    }

    private func isMatchRankedBefore(
        _ lhs: RankedMatch,
        _ rhs: RankedMatch
    ) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier.rawValue < rhs.tier.rawValue }
        if lhs.localeAffinity != rhs.localeAffinity {
            return lhs.localeAffinity < rhs.localeAffinity
        }
        if lhs.wordStartIndex != rhs.wordStartIndex {
            return lhs.wordStartIndex < rhs.wordStartIndex
        }
        if lhs.normalizedMatchedValue.count != rhs.normalizedMatchedValue.count {
            return lhs.normalizedMatchedValue.count < rhs.normalizedMatchedValue.count
        }
        if lhs.normalizedMatchedValue != rhs.normalizedMatchedValue {
            return scalarLexicographicallyPrecedes(
                lhs.normalizedMatchedValue,
                rhs.normalizedMatchedValue
            )
        }
        return scalarLexicographicallyPrecedes(lhs.recordID, rhs.recordID)
    }

    private func isRankedBefore(
        _ lhs: RankedProductCandidate,
        _ rhs: RankedProductCandidate
    ) -> Bool {
        if lhs.match.tier != rhs.match.tier {
            return lhs.match.tier.rawValue < rhs.match.tier.rawValue
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

    private func scalarLexicographicallyPrecedes(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(
            rhs.unicodeScalars,
            by: { $0.value < $1.value }
        )
    }

    private static func append(
        _ productIndex: Int,
        key: String,
        to index: inout [String: [Int]]
    ) {
        guard !key.isEmpty else { return }
        if index[key]?.last != productIndex {
            index[key, default: []].append(productIndex)
        }
    }

    private static func indexPrefixes(
        _ value: String,
        productIndex: Int,
        into index: inout [String: [Int]]
    ) {
        var end = value.startIndex
        while end < value.endIndex {
            end = value.index(after: end)
            append(
                productIndex,
                key: String(value[..<end]),
                to: &index
            )
        }
    }

    private static func indexTrigrams(
        _ value: String,
        productIndex: Int,
        into index: inout [String: [Int]]
    ) {
        for trigram in trigrams(value) {
            append(productIndex, key: trigram, to: &index)
        }
    }

    private static func trigrams(_ value: String) -> [String] {
        let characters = Array(value)
        guard characters.count >= 3 else { return [] }
        return (0...(characters.count - 3)).map {
            String(characters[$0...($0 + 2)])
        }
    }

    private static func keyByteCount(_ index: [String: [Int]]) -> Int {
        index.reduce(0) { total, entry in
            total + entry.key.utf8.count
                + entry.value.count * MemoryLayout<Int>.stride
        }
    }
}

nonisolated private extension ProductKnowledgeSearchIndex {
    struct IndexedProduct: Sendable {
        let entity: ProductEntity
        let category: ProductCategory?
        let categoryTerms: [ProductSearchNormalizedText]
        let names: [IndexedName]
    }

    struct IndexedName: Sendable {
        let record: ProductName
        let normalized: ProductSearchNormalizedText
    }

    struct SearchQuality: Sendable {
        let tier: ProductSearchMatchTier
        let matchType: ProductSearchMatchType
        let wordStartIndex: Int
    }

    struct RankedMatch: Sendable {
        let tier: ProductSearchMatchTier
        let matchType: ProductSearchMatchType
        let authority: ProductSearchRecordAuthority
        let matchedValue: String
        let normalizedMatchedValue: String
        let matchedLocale: String
        let localeAffinity: Int
        let wordStartIndex: Int
        let recordID: String
    }

    struct RankedProductCandidate: Sendable {
        let result: ProductSearchResult
        let match: RankedMatch
        let normalizedDisplayName: String
    }
}
