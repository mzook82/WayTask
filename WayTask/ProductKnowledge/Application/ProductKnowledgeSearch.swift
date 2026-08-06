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
    private let keywordPrefixes: [String: [Int]]
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
                return IndexedName(
                    record: name,
                    normalized: normalized,
                    script: ProductKnowledgeNormalizer.queryScript(normalized)
                )
            }
            guard !names.isEmpty else { continue }

            let category = categoriesByID[product.primaryCategoryID]
            let categoryTerms = [
                (category?.names.en, "en"),
                (category?.names.he, "he")
            ].compactMap { value, locale -> IndexedCategoryTerm? in
                guard let value else { return nil }
                let normalized = ProductSearchNormalizer.normalize(
                    value,
                    localeIdentifier: locale
                )
                guard !normalized.value.isEmpty else { return nil }
                return IndexedCategoryTerm(
                    normalized: normalized,
                    locale: locale,
                    script: ProductKnowledgeNormalizer.queryScript(normalized)
                )
            }
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
        var keywordPrefixes: [String: [Int]] = [:]
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
                    Self.indexPrefixes(
                        value,
                        productIndex: productIndex,
                        into: &keywordPrefixes
                    )
                }

                for token in name.normalized.tokens {
                    if name.record.kind == .keyword {
                        Self.indexPrefixes(
                            token,
                            productIndex: productIndex,
                            into: &keywordPrefixes
                        )
                    } else {
                        Self.indexPrefixes(
                            token,
                            productIndex: productIndex,
                            into: &tokenPrefixes
                        )
                    }
                }
                Self.indexTrigrams(
                    value,
                    productIndex: productIndex,
                    into: &fallbackTrigrams
                )
            }

            for category in product.categoryTerms {
                indexedBytes += category.normalized.value.utf8.count
                Self.indexPrefixes(
                    category.normalized.value,
                    productIndex: productIndex,
                    into: &categoryPrefixes
                )
                for token in category.normalized.tokens {
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
        self.keywordPrefixes = keywordPrefixes
        self.categoryPrefixes = categoryPrefixes
        self.fallbackTrigrams = fallbackTrigrams
        statistics = ProductKnowledgeSearchIndexStatistics(
            productCount: indexedProducts.count,
            searchableNameCount: indexedProducts.reduce(0) {
                $0 + $1.names.count
            },
            exactKeyCount: canonicalExact.count + aliasExact.count,
            prefixKeyCount: canonicalPrefixes.count + aliasPrefixes.count,
            tokenPrefixKeyCount: tokenPrefixes.count + keywordPrefixes.count,
            categoryKeyCount: categoryPrefixes.count,
            trigramKeyCount: fallbackTrigrams.count,
            estimatedIndexedUTF8Bytes: indexedBytes
                + Self.keyByteCount(canonicalExact)
                + Self.keyByteCount(aliasExact)
                + Self.keyByteCount(canonicalPrefixes)
                + Self.keyByteCount(aliasPrefixes)
                + Self.keyByteCount(tokenPrefixes)
                + Self.keyByteCount(keywordPrefixes)
                + Self.keyByteCount(categoryPrefixes)
                + Self.keyByteCount(fallbackTrigrams)
        )
    }

    func suggestions(
        matching query: ProductSearchNormalizedText,
        locale: String,
        limit: Int
    ) -> [ProductSearchResult] {
        let queryScript = ProductKnowledgeNormalizer.queryScript(query)
        let queryPolicy = QueryLengthPolicy(query)
        let candidates = candidateIndices(for: query, policy: queryPolicy)
        var ranked: [RankedProductCandidate] = []
        ranked.reserveCapacity(min(candidates.count, limit * 4))

        for productIndex in candidates.sorted() {
            guard !Task.isCancelled else { return [] }
            if let value = rankedCandidate(
                for: products[productIndex],
                query: query,
                queryScript: queryScript,
                locale: locale,
                policy: queryPolicy
            ) {
                ranked.append(value)
            }
        }

        return gatedCandidates(
            ranked,
            queryScript: queryScript,
            policy: queryPolicy
        )
            .sorted { isRankedBefore($0, $1, policy: queryPolicy) }
            .prefix(limit)
            .map(\.result)
    }

    private func candidateIndices(
        for query: ProductSearchNormalizedText,
        policy: QueryLengthPolicy
    ) -> Set<Int> {
        var result: Set<Int> = []
        result.formUnion(canonicalExact[query.value] ?? [])
        result.formUnion(canonicalPrefixes[query.value] ?? [])

        guard policy != .oneCharacter else {
            return result
        }

        result.formUnion(aliasExact[query.value] ?? [])
        result.formUnion(aliasPrefixes[query.value] ?? [])
        if let tokenCandidates = intersectedCandidates(
            for: query.tokens,
            in: tokenPrefixes
        ) {
            result.formUnion(tokenCandidates)
        }

        guard policy == .standard else {
            return result
        }

        if let keywordCandidates = intersectedCandidates(
            for: query.tokens,
            in: keywordPrefixes
        ) {
            result.formUnion(keywordCandidates)
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
        queryScript: ProductKnowledgeQueryScript,
        locale: String,
        policy: QueryLengthPolicy
    ) -> RankedProductCandidate? {
        var matches = product.names.compactMap { name -> RankedMatch? in
            guard let quality = nameMatch(name, query: query, policy: policy) else {
                return nil
            }
            return RankedMatch(
                tier: quality.tier,
                matchType: quality.matchType,
                authorityRank: authorityRank(for: name.record.kind),
                nameID: name.record.id,
                nameKind: name.record.kind,
                isPreferredName: name.record.isPreferred,
                matchedValue: name.record.value,
                normalizedMatchedValue: name.normalized.value,
                matchedLocale: name.record.locale,
                scriptAffinity: scriptAffinity(
                    candidateScript: name.script,
                    queryScript: queryScript
                ),
                localeAffinity: localeAffinity(
                    name.record.locale,
                    requestedLocale: locale
                ),
                wordStartIndex: quality.wordStartIndex,
                tokenCompletionDistance: quality.tokenCompletionDistance,
                nameCompletionDistance: quality.nameCompletionDistance,
                recordID: name.record.id.rawValue
            )
        }
        if policy == .standard {
            matches.append(contentsOf: categoryMatches(
                product,
                query: query,
                queryScript: queryScript,
                requestedLocale: locale
            ))
        }
        guard let bestMatch = matches.min(by: {
            isMatchRankedBefore($0, $1, policy: policy)
        }) else {
            return nil
        }
        guard let displayName = resultDisplayName(
            for: product,
            bestMatch: bestMatch,
            queryScript: queryScript,
            requestedLocale: locale
        ) else {
            return nil
        }
        let matchedAuthority = authority(
            for: bestMatch,
            displayName: displayName.record
        )

        let secondaryName: String?
        if matchedAuthority == .alias
            || matchedAuthority == .preferredDisplayName
            || matchedAuthority == .displayName {
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
                queryScript: queryScript,
                requestedLocale: locale
            ),
            iconKey: product.entity.iconKey
                ?? product.category?.iconKey
                ?? "product.generic",
            matchedRecordAuthority: matchedAuthority,
            matchType: bestMatch.matchType,
            matchTier: bestMatch.tier,
            matchedValue: bestMatch.matchedValue,
            normalizedMatchedValue: bestMatch.normalizedMatchedValue,
            matchedLocale: bestMatch.matchedLocale
        )

        return RankedProductCandidate(
            result: result,
            match: bestMatch,
            displayScriptAffinity: scriptAffinity(
                candidateScript: displayName.script,
                queryScript: queryScript
            ),
            normalizedDisplayName: displayName.normalized.value
        )
    }

    private func nameMatch(
        _ candidate: IndexedName,
        query: ProductSearchNormalizedText,
        policy: QueryLengthPolicy
    ) -> SearchQuality? {
        let isAlias = candidate.record.kind == .alias
        let isKeyword = candidate.record.kind == .keyword

        if policy == .oneCharacter,
           !candidate.record.kind.isDisplayCapable {
            return nil
        }
        if policy != .standard, isKeyword {
            return nil
        }

        if candidate.normalized.value == query.value {
            if isKeyword {
                return SearchQuality(
                    tier: .conservativeFallback,
                    matchType: .fallback,
                    wordStartIndex: 0,
                    tokenCompletionDistance: 0,
                    nameCompletionDistance: 0
                )
            }
            return SearchQuality(
                tier: isAlias ? .exactAlias : .exactCanonical,
                matchType: .exact,
                wordStartIndex: 0,
                tokenCompletionDistance: 0,
                nameCompletionDistance: 0
            )
        }

        if candidate.normalized.value.hasPrefix(query.value) {
            let tokenCompletionDistance = directTokenCompletionDistance(
                candidateTokens: candidate.normalized.tokens,
                queryTokens: query.tokens,
                startIndex: 0
            )
            if isKeyword {
                return SearchQuality(
                    tier: .conservativeFallback,
                    matchType: .fallback,
                    wordStartIndex: 0,
                    tokenCompletionDistance: tokenCompletionDistance,
                    nameCompletionDistance:
                        candidate.normalized.value.count - query.value.count
                )
            }
            return SearchQuality(
                tier: isAlias ? .aliasPrefix : .canonicalPrefix,
                matchType: .fullNamePrefix,
                wordStartIndex: 0,
                tokenCompletionDistance: tokenCompletionDistance,
                nameCompletionDistance:
                    candidate.normalized.value.count - query.value.count
            )
        }

        if let wordStart = contiguousTokenPrefixStart(
            candidate.normalized.tokens,
            queryTokens: query.tokens
        ) {
            guard policy != .oneCharacter else { return nil }
            return SearchQuality(
                tier: isKeyword
                    ? .conservativeFallback
                    : .tokenPrefix,
                matchType: isKeyword ? .fallback : .wordPrefix,
                wordStartIndex: wordStart,
                tokenCompletionDistance: directTokenCompletionDistance(
                    candidateTokens: candidate.normalized.tokens,
                    queryTokens: query.tokens,
                    startIndex: wordStart
                ),
                nameCompletionDistance: candidate.normalized.value.count
            )
        }

        guard policy == .standard,
              query.value.count >= 4,
              candidate.normalized.value.contains(query.value) else {
            return nil
        }
        return SearchQuality(
            tier: .conservativeFallback,
            matchType: .fallback,
            wordStartIndex: Int.max,
            tokenCompletionDistance: Int.max,
            nameCompletionDistance: Int.max
        )
    }

    private func directTokenCompletionDistance(
        candidateTokens: [String],
        queryTokens: [String],
        startIndex: Int
    ) -> Int {
        guard let queryToken = queryTokens.last else { return Int.max }
        let candidateIndex = startIndex + queryTokens.count - 1
        guard candidateTokens.indices.contains(candidateIndex) else {
            return Int.max
        }
        return max(candidateTokens[candidateIndex].count - queryToken.count, 0)
    }

    private func categoryMatches(
        _ product: IndexedProduct,
        query: ProductSearchNormalizedText,
        queryScript: ProductKnowledgeQueryScript,
        requestedLocale: String
    ) -> [RankedMatch] {
        product.categoryTerms.compactMap { category -> RankedMatch? in
            let matches = category.normalized.value == query.value
                || category.normalized.value.hasPrefix(query.value)
                || contiguousTokenPrefixStart(
                    category.normalized.tokens,
                    queryTokens: query.tokens
                ) != nil
            guard matches else { return nil }
            return RankedMatch(
                tier: .categoryRelevance,
                matchType: .category,
                authorityRank: authorityRank(for: nil),
                nameID: nil,
                nameKind: nil,
                isPreferredName: false,
                matchedValue: category.normalized.value,
                normalizedMatchedValue: category.normalized.value,
                matchedLocale: category.locale,
                scriptAffinity: scriptAffinity(
                    candidateScript: category.script,
                    queryScript: queryScript
                ),
                localeAffinity: localeAffinity(
                    category.locale,
                    requestedLocale: requestedLocale
                ),
                wordStartIndex: 0,
                tokenCompletionDistance: Int.max,
                nameCompletionDistance: Int.max,
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
        queryScript: ProductKnowledgeQueryScript,
        requestedLocale: String
    ) -> String {
        if queryScript == .hebrew
            || (queryScript == .mixedOrIndeterminate
                && primaryLanguage(normalizedLocale(requestedLocale)) == "he") {
            return category?.names.he ?? "ללא קטגוריה"
        }
        return category?.names.en ?? "Uncategorized"
    }

    private func resultDisplayName(
        for product: IndexedProduct,
        bestMatch: RankedMatch,
        queryScript: ProductKnowledgeQueryScript,
        requestedLocale: String
    ) -> IndexedName? {
        if queryScript != .mixedOrIndeterminate {
            if let nameID = bestMatch.nameID,
               let matched = product.names.first(where: { $0.record.id == nameID }),
               matched.record.kind.isDisplayCapable,
               matched.script == queryScript {
                return matched
            }

            if let localized = preferredDisplayName(
                for: product,
                matching: queryScript
            ) {
                return localized
            }
        }

        return applicationPreferredDisplayName(
            for: product,
            requestedLocale: requestedLocale
        )
    }

    private func preferredDisplayName(
        for product: IndexedProduct,
        matching script: ProductKnowledgeQueryScript
    ) -> IndexedName? {
        product.names
            .filter {
                $0.record.isPreferred
                    && $0.record.kind.isDisplayCapable
                    && $0.script == script
            }
            .sorted {
                scalarLexicographicallyPrecedes(
                    $0.record.id.rawValue,
                    $1.record.id.rawValue
                )
            }
            .first
    }

    private func applicationPreferredDisplayName(
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
        for match: RankedMatch,
        displayName: ProductName
    ) -> ProductSearchRecordAuthority {
        if match.nameID == displayName.id {
            return .primaryDisplayName
        }
        if match.nameKind == .alias {
            return .alias
        }
        if match.nameKind == .keyword {
            return .keyword
        }
        if match.nameKind == nil {
            return .category
        }
        if match.isPreferredName && match.nameKind?.isDisplayCapable == true {
            return .preferredDisplayName
        }
        return .displayName
    }

    private func authorityRank(for kind: ProductNameKind?) -> Int {
        switch kind {
        case .canonical, .localizedDisplay: 0
        case .alias: 1
        case .keyword: 2
        case nil: 3
        }
    }

    private func scriptAffinity(
        candidateScript: ProductKnowledgeQueryScript,
        queryScript: ProductKnowledgeQueryScript
    ) -> Int {
        guard queryScript != .mixedOrIndeterminate else { return 0 }
        if candidateScript == queryScript { return 0 }
        if candidateScript == .mixedOrIndeterminate { return 1 }
        return 2
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

    private func gatedCandidates(
        _ candidates: [RankedProductCandidate],
        queryScript: ProductKnowledgeQueryScript,
        policy: QueryLengthPolicy
    ) -> [RankedProductCandidate] {
        guard queryScript != .mixedOrIndeterminate else {
            return candidates
        }

        switch policy {
        case .standard:
            return candidates
        case .oneCharacter:
            return candidates.filter {
                $0.match.scriptAffinity == 0
                    && $0.displayScriptAffinity == 0
                    && ($0.match.tier == .exactCanonical
                        || $0.match.tier == .canonicalPrefix)
            }
        case .twoCharacters:
            let sameScriptCandidates = candidates.filter {
                $0.match.scriptAffinity == 0 && $0.displayScriptAffinity == 0
            }
            let bestSameScriptBand = sameScriptCandidates
                .map { shortStrengthBand($0.match.tier) }
                .min()

            return candidates.filter { candidate in
                if candidate.match.scriptAffinity == 0,
                   candidate.displayScriptAffinity == 0 {
                    return true
                }

                guard candidate.match.scriptAffinity == 0,
                      candidate.match.tier == .exactCanonical
                        || candidate.match.tier == .canonicalPrefix
                        || candidate.match.tier == .exactAlias
                        || candidate.match.tier == .aliasPrefix else {
                    return false
                }

                guard let bestSameScriptBand else { return true }
                return bestSameScriptBand
                    > shortStrengthBand(candidate.match.tier)
            }
        }
    }

    private func isMatchRankedBefore(
        _ lhs: RankedMatch,
        _ rhs: RankedMatch,
        policy: QueryLengthPolicy
    ) -> Bool {
        if policy != .standard {
            let lhsBand = shortStrengthBand(lhs.tier)
            let rhsBand = shortStrengthBand(rhs.tier)
            if lhsBand != rhsBand { return lhsBand < rhsBand }

            if isDirectPrefix(lhs.tier) {
                if lhs.tokenCompletionDistance != rhs.tokenCompletionDistance {
                    return lhs.tokenCompletionDistance < rhs.tokenCompletionDistance
                }
                if lhs.nameCompletionDistance != rhs.nameCompletionDistance {
                    return lhs.nameCompletionDistance < rhs.nameCompletionDistance
                }
                if lhs.authorityRank != rhs.authorityRank {
                    return lhs.authorityRank < rhs.authorityRank
                }
            }
            if lhs.scriptAffinity != rhs.scriptAffinity {
                return lhs.scriptAffinity < rhs.scriptAffinity
            }
            return deterministicMatchTieBreak(lhs, rhs)
        }

        let lhsGroup = strengthGroup(lhs.tier)
        let rhsGroup = strengthGroup(rhs.tier)
        if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
        if lhs.scriptAffinity != rhs.scriptAffinity {
            return lhs.scriptAffinity < rhs.scriptAffinity
        }

        if lhsGroup == SearchStrengthGroup.directPrefix.rawValue {
            if lhs.tokenCompletionDistance != rhs.tokenCompletionDistance {
                return lhs.tokenCompletionDistance < rhs.tokenCompletionDistance
            }
            if lhs.nameCompletionDistance != rhs.nameCompletionDistance {
                return lhs.nameCompletionDistance < rhs.nameCompletionDistance
            }
            if lhs.authorityRank != rhs.authorityRank {
                return lhs.authorityRank < rhs.authorityRank
            }
        }

        return deterministicMatchTieBreak(lhs, rhs)
    }

    private func deterministicMatchTieBreak(
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
        _ rhs: RankedProductCandidate,
        policy: QueryLengthPolicy
    ) -> Bool {
        if policy != .standard {
            let lhsBand = shortStrengthBand(lhs.match.tier)
            let rhsBand = shortStrengthBand(rhs.match.tier)
            if lhsBand != rhsBand { return lhsBand < rhsBand }

            if isDirectPrefix(lhs.match.tier) {
                if lhs.match.tokenCompletionDistance
                    != rhs.match.tokenCompletionDistance {
                    return lhs.match.tokenCompletionDistance
                        < rhs.match.tokenCompletionDistance
                }
                if lhs.match.nameCompletionDistance
                    != rhs.match.nameCompletionDistance {
                    return lhs.match.nameCompletionDistance
                        < rhs.match.nameCompletionDistance
                }
                if lhs.match.authorityRank != rhs.match.authorityRank {
                    return lhs.match.authorityRank < rhs.match.authorityRank
                }
            }
            if lhs.match.scriptAffinity != rhs.match.scriptAffinity {
                return lhs.match.scriptAffinity < rhs.match.scriptAffinity
            }
            if lhs.displayScriptAffinity != rhs.displayScriptAffinity {
                return lhs.displayScriptAffinity < rhs.displayScriptAffinity
            }
            return deterministicProductTieBreak(lhs, rhs)
        }

        let lhsGroup = strengthGroup(lhs.match.tier)
        let rhsGroup = strengthGroup(rhs.match.tier)
        if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
        if lhs.match.scriptAffinity != rhs.match.scriptAffinity {
            return lhs.match.scriptAffinity < rhs.match.scriptAffinity
        }
        if lhs.displayScriptAffinity != rhs.displayScriptAffinity {
            return lhs.displayScriptAffinity < rhs.displayScriptAffinity
        }

        if lhsGroup == SearchStrengthGroup.directPrefix.rawValue {
            if lhs.match.tokenCompletionDistance
                != rhs.match.tokenCompletionDistance {
                return lhs.match.tokenCompletionDistance
                    < rhs.match.tokenCompletionDistance
            }
            if lhs.match.nameCompletionDistance
                != rhs.match.nameCompletionDistance {
                return lhs.match.nameCompletionDistance
                    < rhs.match.nameCompletionDistance
            }
            if lhs.match.authorityRank != rhs.match.authorityRank {
                return lhs.match.authorityRank < rhs.match.authorityRank
            }
        }

        return deterministicProductTieBreak(lhs, rhs)
    }

    private func deterministicProductTieBreak(
        _ lhs: RankedProductCandidate,
        _ rhs: RankedProductCandidate
    ) -> Bool {
        if lhs.match.tier != rhs.match.tier {
            return lhs.match.tier.rawValue < rhs.match.tier.rawValue
        }
        if lhs.match.localeAffinity != rhs.match.localeAffinity {
            return lhs.match.localeAffinity < rhs.match.localeAffinity
        }
        if lhs.match.wordStartIndex != rhs.match.wordStartIndex {
            return lhs.match.wordStartIndex < rhs.match.wordStartIndex
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

    private func isDirectPrefix(_ tier: ProductSearchMatchTier) -> Bool {
        tier == .canonicalPrefix || tier == .aliasPrefix
    }

    private func shortStrengthBand(_ tier: ProductSearchMatchTier) -> Int {
        switch tier {
        case .exactCanonical: 0
        case .canonicalPrefix: 1
        case .exactAlias: 2
        case .aliasPrefix: 3
        case .tokenPrefix: 4
        case .categoryRelevance: 5
        case .conservativeFallback: 6
        }
    }

    private func strengthGroup(_ tier: ProductSearchMatchTier) -> Int {
        switch tier {
        case .exactCanonical, .exactAlias:
            SearchStrengthGroup.exact.rawValue
        case .canonicalPrefix, .aliasPrefix:
            SearchStrengthGroup.directPrefix.rawValue
        case .tokenPrefix:
            SearchStrengthGroup.tokenPrefix.rawValue
        case .categoryRelevance:
            SearchStrengthGroup.category.rawValue
        case .conservativeFallback:
            SearchStrengthGroup.fallback.rawValue
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
    enum QueryLengthPolicy: Sendable {
        case oneCharacter
        case twoCharacters
        case standard

        init(_ query: ProductSearchNormalizedText) {
            let count = query.value.unicodeScalars.reduce(into: 0) {
                if CharacterSet.alphanumerics.contains($1) {
                    $0 += 1
                }
            }
            switch count {
            case 1: self = .oneCharacter
            case 2: self = .twoCharacters
            default: self = .standard
            }
        }
    }

    enum SearchStrengthGroup: Int, Sendable {
        case exact
        case directPrefix
        case tokenPrefix
        case category
        case fallback
    }

    struct IndexedProduct: Sendable {
        let entity: ProductEntity
        let category: ProductCategory?
        let categoryTerms: [IndexedCategoryTerm]
        let names: [IndexedName]
    }

    struct IndexedCategoryTerm: Sendable {
        let normalized: ProductSearchNormalizedText
        let locale: String
        let script: ProductKnowledgeQueryScript
    }

    struct IndexedName: Sendable {
        let record: ProductName
        let normalized: ProductSearchNormalizedText
        let script: ProductKnowledgeQueryScript
    }

    struct SearchQuality: Sendable {
        let tier: ProductSearchMatchTier
        let matchType: ProductSearchMatchType
        let wordStartIndex: Int
        let tokenCompletionDistance: Int
        let nameCompletionDistance: Int
    }

    struct RankedMatch: Sendable {
        let tier: ProductSearchMatchTier
        let matchType: ProductSearchMatchType
        let authorityRank: Int
        let nameID: ProductNameID?
        let nameKind: ProductNameKind?
        let isPreferredName: Bool
        let matchedValue: String
        let normalizedMatchedValue: String
        let matchedLocale: String
        let scriptAffinity: Int
        let localeAffinity: Int
        let wordStartIndex: Int
        let tokenCompletionDistance: Int
        let nameCompletionDistance: Int
        let recordID: String
    }

    struct RankedProductCandidate: Sendable {
        let result: ProductSearchResult
        let match: RankedMatch
        let displayScriptAffinity: Int
        let normalizedDisplayName: String
    }
}
