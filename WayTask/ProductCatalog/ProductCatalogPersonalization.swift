import Foundation

nonisolated struct ProductCatalogSelectionHistory: Equatable, Sendable {
    let catalogProductID: String?
    let productName: String
    let selectionCount: Int
    let mostRecentSelectionDate: Date
}

nonisolated struct ProductCatalogPersonalizationProfile: Equatable, Sendable {
    let selectionCount: Int
    let mostRecentSelectionDate: Date

    func frequencyBoost() -> Int {
        min(max(selectionCount - 1, 0) * 5, 20)
    }

    func recencyBoost(relativeTo referenceDate: Date) -> Int {
        let age = max(referenceDate.timeIntervalSince(mostRecentSelectionDate), 0)
        let day: TimeInterval = 24 * 60 * 60

        if age <= 7 * day {
            return 10
        }
        if age <= 30 * day {
            return 6
        }
        if age <= 90 * day {
            return 3
        }
        return 0
    }

    func totalBoost(relativeTo referenceDate: Date) -> Int {
        frequencyBoost() + recencyBoost(relativeTo: referenceDate)
    }
}

nonisolated struct ProductCatalogPersonalizationIndex: Sendable {
    private let profilesByCatalogID: [
        String: ProductCatalogPersonalizationProfile
    ]
    private let profilesByNormalizedName: [
        String: ProductCatalogPersonalizationProfile
    ]

    init(history: [ProductCatalogSelectionHistory]) {
        var byCatalogID: [String: ProductCatalogPersonalizationProfile] = [:]
        var byNormalizedName: [String: ProductCatalogPersonalizationProfile] = [:]

        for record in history where record.selectionCount > 0 {
            let profile = ProductCatalogPersonalizationProfile(
                selectionCount: record.selectionCount,
                mostRecentSelectionDate: record.mostRecentSelectionDate
            )

            if let catalogProductID = record.catalogProductID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !catalogProductID.isEmpty {
                byCatalogID[catalogProductID] = Self.merged(
                    byCatalogID[catalogProductID],
                    with: profile
                )
                continue
            }

            let normalizedName = HebrewProductSearchNormalizer
                .normalize(record.productName)
                .value
            guard !normalizedName.isEmpty else {
                continue
            }
            byNormalizedName[normalizedName] = Self.merged(
                byNormalizedName[normalizedName],
                with: profile
            )
        }

        profilesByCatalogID = byCatalogID
        profilesByNormalizedName = byNormalizedName
    }

    func profile(
        catalogProductID: String,
        normalizedName: String
    ) -> ProductCatalogPersonalizationProfile? {
        profilesByCatalogID[catalogProductID]
            ?? profilesByNormalizedName[normalizedName]
    }

    private static func merged(
        _ current: ProductCatalogPersonalizationProfile?,
        with incoming: ProductCatalogPersonalizationProfile
    ) -> ProductCatalogPersonalizationProfile {
        guard let current else {
            return incoming
        }

        return ProductCatalogPersonalizationProfile(
            selectionCount: max(
                current.selectionCount,
                incoming.selectionCount
            ),
            mostRecentSelectionDate: max(
                current.mostRecentSelectionDate,
                incoming.mostRecentSelectionDate
            )
        )
    }
}

@MainActor
enum ProductCatalogPersonalizationHistoryBuilder {
    static func makeHistory(
        products: [Product],
        shoppingListEntries: [ShoppingListEntry],
        productHistories: [ProductHistory]
    ) -> [ProductCatalogSelectionHistory] {
        let productsByID = Dictionary(
            products.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var catalogIDsByNormalizedName: [String: Set<String>] = [:]
        var exactAggregates: [String: Aggregate] = [:]
        var fallbackAggregates: [String: Aggregate] = [:]
        var displayNamesByCatalogID: [String: String] = [:]
        var displayNamesByNormalizedName: [String: String] = [:]

        for product in products {
            let normalizedNames = normalizedNames(for: product)
            guard !normalizedNames.isEmpty else {
                continue
            }

            if let catalogProductID = normalizedCatalogProductID(for: product) {
                displayNamesByCatalogID[catalogProductID] = product.name
                for normalizedName in normalizedNames {
                    catalogIDsByNormalizedName[
                        normalizedName,
                        default: []
                    ].insert(catalogProductID)
                }
                merge(
                    Aggregate(
                        count: 1,
                        mostRecentDate: product.dateAdded
                    ),
                    into: &exactAggregates,
                    key: catalogProductID
                )
            } else if let normalizedName = normalizedNames.first {
                displayNamesByNormalizedName[normalizedName] = product.name
                merge(
                    Aggregate(
                        count: 1,
                        mostRecentDate: product.dateAdded
                    ),
                    into: &fallbackAggregates,
                    key: normalizedName
                )
            }
        }

        var historyAggregatesByName: [String: Aggregate] = [:]
        for history in productHistories {
            let normalizedName = HebrewProductSearchNormalizer
                .normalize(history.productName)
                .value
            guard !normalizedName.isEmpty else {
                continue
            }

            displayNamesByNormalizedName[normalizedName] = history.productName
            merge(
                Aggregate(
                    count: max(history.addCount, 1),
                    mostRecentDate: history.lastAddedDate
                ),
                into: &historyAggregatesByName,
                key: normalizedName,
                combinesCounts: true
            )
        }

        for entry in shoppingListEntries {
            guard let product = entry.product ?? productsByID[entry.productID] else {
                continue
            }

            if let catalogProductID = normalizedCatalogProductID(for: product) {
                displayNamesByCatalogID[catalogProductID] = product.name
                merge(
                    Aggregate(count: 1, mostRecentDate: entry.createdAt),
                    into: &exactAggregates,
                    key: catalogProductID,
                    combinesCounts: true
                )
            } else {
                let normalizedName = HebrewProductSearchNormalizer
                    .normalize(product.name)
                    .value
                guard !normalizedName.isEmpty else {
                    continue
                }
                displayNamesByNormalizedName[normalizedName] = product.name
                merge(
                    Aggregate(count: 1, mostRecentDate: entry.createdAt),
                    into: &fallbackAggregates,
                    key: normalizedName,
                    combinesCounts: true
                )
            }
        }

        for (normalizedName, historyAggregate) in historyAggregatesByName {
            let matchingCatalogIDs = catalogIDsByNormalizedName[normalizedName] ?? []
            if matchingCatalogIDs.count == 1,
               let catalogProductID = matchingCatalogIDs.first {
                merge(
                    historyAggregate,
                    into: &exactAggregates,
                    key: catalogProductID
                )
            } else {
                merge(
                    historyAggregate,
                    into: &fallbackAggregates,
                    key: normalizedName
                )
            }
        }

        let exactHistory = exactAggregates.map { catalogProductID, aggregate in
            ProductCatalogSelectionHistory(
                catalogProductID: catalogProductID,
                productName: displayNamesByCatalogID[catalogProductID] ?? "",
                selectionCount: aggregate.count,
                mostRecentSelectionDate: aggregate.mostRecentDate
            )
        }
        let fallbackHistory = fallbackAggregates.map {
            normalizedName,
            aggregate in
            ProductCatalogSelectionHistory(
                catalogProductID: nil,
                productName:
                    displayNamesByNormalizedName[normalizedName]
                    ?? normalizedName,
                selectionCount: aggregate.count,
                mostRecentSelectionDate: aggregate.mostRecentDate
            )
        }

        return (exactHistory + fallbackHistory).sorted {
            let lhsKey = $0.catalogProductID
                ?? HebrewProductSearchNormalizer.normalize($0.productName).value
            let rhsKey = $1.catalogProductID
                ?? HebrewProductSearchNormalizer.normalize($1.productName).value
            return lhsKey < rhsKey
        }
    }

    private static func normalizedNames(for product: Product) -> [String] {
        [product.name, product.catalogDisplayNameSnapshot]
            .compactMap { $0 }
            .map { HebrewProductSearchNormalizer.normalize($0).value }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) {
                    result.append(name)
                }
            }
    }

    private static func normalizedCatalogProductID(
        for product: Product
    ) -> String? {
        let normalized = product.catalogProductIDRawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func merge(
        _ incoming: Aggregate,
        into aggregates: inout [String: Aggregate],
        key: String,
        combinesCounts: Bool = false
    ) {
        guard let current = aggregates[key] else {
            aggregates[key] = incoming
            return
        }

        aggregates[key] = Aggregate(
            count: combinesCounts
                ? current.count + incoming.count
                : max(current.count, incoming.count),
            mostRecentDate: max(
                current.mostRecentDate,
                incoming.mostRecentDate
            )
        )
    }

    private struct Aggregate {
        let count: Int
        let mostRecentDate: Date
    }
}
