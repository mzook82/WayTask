import Foundation

nonisolated enum ProductCatalogHistoryProvenance:
    String, CaseIterable, Codable, Hashable, Sendable {
    case nativeCommittedCommandEvents
    case retainedLegacyAggregate
    case legacyCompatibilityObservation
}

nonisolated struct ProductCatalogSelectionHistory: Equatable, Sendable {
    let catalogProductID: String?
    let productName: String
    let selectionCount: Int
    let mostRecentSelectionDate: Date
    let provenance: ProductCatalogHistoryProvenance

    init(
        catalogProductID: String?,
        productName: String,
        selectionCount: Int,
        mostRecentSelectionDate: Date,
        provenance: ProductCatalogHistoryProvenance =
            .legacyCompatibilityObservation
    ) {
        self.catalogProductID = catalogProductID
        self.productName = productName
        self.selectionCount = selectionCount
        self.mostRecentSelectionDate = mostRecentSelectionDate
        self.provenance = provenance
    }
}

nonisolated struct ProductCatalogPersonalizationProfile: Equatable, Sendable {
    let selectionCount: Int
    let mostRecentSelectionDate: Date
    let provenances: Set<ProductCatalogHistoryProvenance>

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
                mostRecentSelectionDate: record.mostRecentSelectionDate,
                provenances: [record.provenance]
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
        normalizedNames: [String]
    ) -> ProductCatalogPersonalizationProfile? {
        if let exact = profilesByCatalogID[catalogProductID] {
            return exact
        }
        for normalizedName in normalizedNames {
            if let fallback = profilesByNormalizedName[normalizedName] {
                return fallback
            }
        }
        return nil
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
            ),
            provenances: current.provenances.union(incoming.provenances)
        )
    }
}

struct ProductCatalogNativeHistoryInput: Equatable, Sendable {
    let productID: ProductStateProductID
    let exactCatalogProductID: String
    let displayNameSnapshot: String
    let history: ProductStateHistoryAggregate
}

struct ProductCatalogLegacyHistoryInput: Equatable, Sendable {
    let displayNameSnapshot: String
    let evidence: ProductStateLegacyHistoryAggregateEvidence
}

enum ProductCatalogTargetHistoryOutcomeKind:
    String, Codable, Sendable {
    case success
    case invalidRequest
}

struct ProductCatalogTargetHistoryDiagnostic:
    Equatable, Codable, Sendable {
    let outcome: ProductCatalogTargetHistoryOutcomeKind
    let nativeInputCount: Int
    let legacyInputCount: Int
    let rejectedInputCount: Int
    let duplicateInputCount: Int
    let returnedRecordCount: Int
    let provenances: [ProductCatalogHistoryProvenance]
}

struct ProductCatalogTargetHistoryProjection: Equatable, Sendable {
    let records: [ProductCatalogSelectionHistory]
    let diagnostic: ProductCatalogTargetHistoryDiagnostic
}

/// T-12 target-only personalization input. Native need-added evidence and
/// retained legacy aggregates remain labeled and never become purchase truth.
@MainActor
enum ProductCatalogTargetHistoryBuilder {
    static func makeHistory(
        native: [ProductCatalogNativeHistoryInput],
        legacy: [ProductCatalogLegacyHistoryInput],
        maximumRecordCount: Int
    ) -> ProductCatalogTargetHistoryProjection {
        guard maximumRecordCount > 0 else {
            return ProductCatalogTargetHistoryProjection(
                records: [],
                diagnostic: ProductCatalogTargetHistoryDiagnostic(
                    outcome: .invalidRequest,
                    nativeInputCount: native.count,
                    legacyInputCount: legacy.count,
                    rejectedInputCount: native.count + legacy.count,
                    duplicateInputCount: 0,
                    returnedRecordCount: 0,
                    provenances: []
                )
            )
        }

        var records: [RecordKey: ProductCatalogSelectionHistory] = [:]
        var rejected = 0
        var duplicates = 0

        let nativeGroups = Dictionary(grouping: native, by: \.productID)
        for productID in nativeGroups.keys.sorted(by: productIDLessThan) {
            guard let group = nativeGroups[productID] else { continue }
            var candidates: [(
                catalogID: String,
                record: ProductCatalogSelectionHistory
            )] = []
            for input in group.sorted(by: nativeLessThan) {
                guard let candidate = nativeCandidate(input) else {
                    rejected += 1
                    continue
                }
                candidates.append(candidate)
            }
            guard !candidates.isEmpty else { continue }
            let catalogIDs = Set(candidates.map(\.catalogID))
            guard catalogIDs.count == 1,
                  let catalogID = catalogIDs.first else {
                rejected += candidates.count
                continue
            }
            duplicates += max(candidates.count - 1, 0)

            let key = RecordKey(
                provenance: .nativeCommittedCommandEvents,
                identity: catalogID
            )
            for candidate in candidates {
                records[key] = conservativeMerge(
                    records[key],
                    candidate.record
                )
            }
        }

        let legacyGroups = Dictionary(
            grouping: legacy,
            by: { $0.evidence.legacyRecordID }
        )
        for recordID in legacyGroups.keys.sorted(by: uuidLessThan) {
            guard let group = legacyGroups[recordID] else { continue }
            let orderedGroup = group.sorted(by: legacyLessThan)
            guard let first = orderedGroup.first else { continue }
            guard orderedGroup.allSatisfy({ $0 == first }) else {
                rejected += orderedGroup.count
                continue
            }
            duplicates += max(orderedGroup.count - 1, 0)
            let normalizedName = HebrewProductSearchNormalizer
                .normalize(first.displayNameSnapshot)
                .value
            guard first.evidence.observationCount > 0,
                  !normalizedName.isEmpty else {
                rejected += 1
                continue
            }

            let key = RecordKey(
                provenance: .retainedLegacyAggregate,
                identity: normalizedName
            )
            let incoming = ProductCatalogSelectionHistory(
                catalogProductID: nil,
                productName: first.displayNameSnapshot,
                selectionCount: first.evidence.observationCount,
                mostRecentSelectionDate: first.evidence.lastObservedAt,
                provenance: .retainedLegacyAggregate
            )
            records[key] = conservativeMerge(records[key], incoming)
        }

        let ordered = records.values.sorted(by: recordLessThan)
        let returned = Array(ordered.prefix(maximumRecordCount))
        let provenances = Array(Set(returned.map(\.provenance))).sorted {
            $0.rawValue < $1.rawValue
        }
        return ProductCatalogTargetHistoryProjection(
            records: returned,
            diagnostic: ProductCatalogTargetHistoryDiagnostic(
                outcome: .success,
                nativeInputCount: native.count,
                legacyInputCount: legacy.count,
                rejectedInputCount: rejected,
                duplicateInputCount: duplicates,
                returnedRecordCount: returned.count,
                provenances: provenances
            )
        )
    }

    private static func nativeCandidate(
        _ input: ProductCatalogNativeHistoryInput
    ) -> (
        catalogID: String,
        record: ProductCatalogSelectionHistory
    )? {
        let catalogID = input.exactCatalogProductID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard input.history.productID == input.productID,
              !catalogID.isEmpty,
              input.history.safePersonalizationSignalCount > 0,
              let occurredAt = input.history.mostRecentNeedAddedAt else {
            return nil
        }
        return (
            catalogID,
            ProductCatalogSelectionHistory(
                catalogProductID: catalogID,
                productName: input.displayNameSnapshot,
                selectionCount:
                    input.history.safePersonalizationSignalCount,
                mostRecentSelectionDate: occurredAt,
                provenance: .nativeCommittedCommandEvents
            )
        )
    }

    private static func conservativeMerge(
        _ current: ProductCatalogSelectionHistory?,
        _ incoming: ProductCatalogSelectionHistory
    ) -> ProductCatalogSelectionHistory {
        guard let current else { return incoming }
        return ProductCatalogSelectionHistory(
            catalogProductID: current.catalogProductID,
            productName: current.productName.isEmpty
                ? incoming.productName : current.productName,
            selectionCount: max(
                current.selectionCount,
                incoming.selectionCount
            ),
            mostRecentSelectionDate: max(
                current.mostRecentSelectionDate,
                incoming.mostRecentSelectionDate
            ),
            provenance: current.provenance
        )
    }

    private static func nativeLessThan(
        _ lhs: ProductCatalogNativeHistoryInput,
        _ rhs: ProductCatalogNativeHistoryInput
    ) -> Bool {
        if lhs.productID != rhs.productID {
            return lhs.productID.rawValue.uuidString
                < rhs.productID.rawValue.uuidString
        }
        if lhs.exactCatalogProductID != rhs.exactCatalogProductID {
            return lhs.exactCatalogProductID < rhs.exactCatalogProductID
        }
        if lhs.displayNameSnapshot != rhs.displayNameSnapshot {
            return lhs.displayNameSnapshot < rhs.displayNameSnapshot
        }
        if lhs.history.safePersonalizationSignalCount
            != rhs.history.safePersonalizationSignalCount {
            return lhs.history.safePersonalizationSignalCount
                < rhs.history.safePersonalizationSignalCount
        }
        return (lhs.history.mostRecentNeedAddedAt ?? .distantPast)
            < (rhs.history.mostRecentNeedAddedAt ?? .distantPast)
    }

    private static func legacyLessThan(
        _ lhs: ProductCatalogLegacyHistoryInput,
        _ rhs: ProductCatalogLegacyHistoryInput
    ) -> Bool {
        if lhs.evidence.legacyRecordID != rhs.evidence.legacyRecordID {
            return lhs.evidence.legacyRecordID.uuidString
                < rhs.evidence.legacyRecordID.uuidString
        }
        if lhs.displayNameSnapshot != rhs.displayNameSnapshot {
            return lhs.displayNameSnapshot < rhs.displayNameSnapshot
        }
        if lhs.evidence.observationCount != rhs.evidence.observationCount {
            return lhs.evidence.observationCount
                < rhs.evidence.observationCount
        }
        return lhs.evidence.lastObservedAt < rhs.evidence.lastObservedAt
    }

    private static func recordLessThan(
        _ lhs: ProductCatalogSelectionHistory,
        _ rhs: ProductCatalogSelectionHistory
    ) -> Bool {
        if lhs.provenance != rhs.provenance {
            return lhs.provenance.rawValue < rhs.provenance.rawValue
        }
        let lhsIdentity = lhs.catalogProductID
            ?? HebrewProductSearchNormalizer.normalize(lhs.productName).value
        let rhsIdentity = rhs.catalogProductID
            ?? HebrewProductSearchNormalizer.normalize(rhs.productName).value
        return lhsIdentity < rhsIdentity
    }

    private struct RecordKey: Hashable {
        let provenance: ProductCatalogHistoryProvenance
        let identity: String
    }

    private static func productIDLessThan(
        _ lhs: ProductStateProductID,
        _ rhs: ProductStateProductID
    ) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    private static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
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
