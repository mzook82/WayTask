import Foundation
import SwiftData

struct ProductStateShoppingMemoryProjection: Equatable, Sendable {
    let productID: ProductStateProductID
    let nativeHistory: ProductStateProductHistoryProjection
    let linkedLegacyEvidence: [ProductStateLegacyHistoryAggregateEvidence]
    let rejectedLegacyEvidenceCount: Int

    var provenances: [ProductStateHistoryNamedProvenance] {
        var values = nativeHistory.provenanceCounts.map(\.provenance)
        if !linkedLegacyEvidence.isEmpty {
            values.append(.retainedLegacyAggregate)
        }
        return Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }
}

enum ProductStateShoppingMemoryQueryOutcomeKind:
    String, Codable, Sendable {
    case success
    case invalidRequest
    case unavailable
}

struct ProductStateShoppingMemoryDiagnostic:
    Equatable, Codable, Sendable {
    let productID: UUID
    let outcome: ProductStateShoppingMemoryQueryOutcomeKind
    let nativeEventCount: Int
    let linkedLegacyEvidenceCount: Int
    let rejectedLegacyEvidenceCount: Int
    let duplicateContributionCount: Int
    let unsupportedEvidenceCount: Int
    let provenances: [ProductStateHistoryNamedProvenance]
}

enum ProductStateShoppingMemoryQueryOutcome: Equatable, Sendable {
    case success(
        projection: ProductStateShoppingMemoryProjection,
        diagnostic: ProductStateShoppingMemoryDiagnostic
    )
    case invalidRequest(ProductStateShoppingMemoryDiagnostic)
    case unavailable(ProductStateShoppingMemoryDiagnostic)
}

protocol ShoppingMemoryServicing {
    @discardableResult
    func recordProductAdded(_ item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory
    func productHistory(for item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory?
    func productHistory(productKey: String, in modelContext: ModelContext) throws -> ProductHistory?
    func frequentlyAddedProducts(limit: Int, in modelContext: ModelContext) throws -> [ProductHistory]
}

struct ShoppingMemoryService: ShoppingMemoryServicing {
    /// T-12 target-only, read-only consumption. Native event authority and
    /// retained legacy aggregate evidence remain separately represented.
    @MainActor
    func targetHistoryMemory(
        _ request: ProductStateHistoryQueryRequest,
        using queries: any ProductStateHistoryQuerying,
        legacyEvidence: [ProductStateLegacyHistoryAggregateEvidence] = []
    ) -> ProductStateShoppingMemoryQueryOutcome {
        switch queries.history(request) {
        case let .success(history, _):
            let linked = legacyEvidence.filter {
                $0.provenProductID == request.productID
            }.sorted(by: legacyEvidenceLessThan)
            let rejectedCount = legacyEvidence.count - linked.count
            let projection = ProductStateShoppingMemoryProjection(
                productID: request.productID,
                nativeHistory: history,
                linkedLegacyEvidence: linked,
                rejectedLegacyEvidenceCount: rejectedCount
            )
            return .success(
                projection: projection,
                diagnostic: targetDiagnostic(
                    projection: projection,
                    outcome: .success
                )
            )

        case .invalidRequest:
            return .invalidRequest(
                emptyTargetDiagnostic(
                    productID: request.productID,
                    outcome: .invalidRequest,
                    rejectedLegacyEvidenceCount: legacyEvidence.count
                )
            )

        case .unavailable:
            return .unavailable(
                emptyTargetDiagnostic(
                    productID: request.productID,
                    outcome: .unavailable,
                    rejectedLegacyEvidenceCount: legacyEvidence.count
                )
            )
        }
    }

    @discardableResult
    func recordProductAdded(_ item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory {
        let key = productKey(for: item)
        let now = item.dateAdded

        if let existingHistory = try productHistory(productKey: key, in: modelContext) {
            update(existingHistory, with: item, addedAt: now)
            try modelContext.save()
            return existingHistory
        }

        let history = ProductHistory(
            productKey: key,
            productName: item.name,
            barcode: normalizedBarcode(item.barcode),
            firstAddedDate: now,
            lastAddedDate: now,
            addCount: 1,
            lastSource: item.source,
            averageInterval: nil,
            lastCompletedDate: item.isCompleted ? now : nil
        )
        modelContext.insert(history)
        try modelContext.save()
        return history
    }

    func productHistory(for item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory? {
        try productHistory(productKey: productKey(for: item), in: modelContext)
    }

    func productHistory(productKey: String, in modelContext: ModelContext) throws -> ProductHistory? {
        let normalizedKey = productKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptor = FetchDescriptor<ProductHistory>()
        return try modelContext.fetch(descriptor).first { history in
            history.productKey == normalizedKey
        }
    }

    func frequentlyAddedProducts(limit: Int = 10, in modelContext: ModelContext) throws -> [ProductHistory] {
        var descriptor = FetchDescriptor<ProductHistory>(
            sortBy: [
                SortDescriptor(\.addCount, order: .reverse),
                SortDescriptor(\.lastAddedDate, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func update(_ history: ProductHistory, with item: ShoppingItem, addedAt date: Date) {
        let previousLastAddedDate = history.lastAddedDate
        history.productName = item.name
        history.barcode = normalizedBarcode(item.barcode) ?? history.barcode
        history.lastAddedDate = date
        history.addCount += 1
        history.lastSourceRawValue = item.source.rawValue

        if item.isCompleted {
            history.lastCompletedDate = date
        }

        let interval = date.timeIntervalSince(previousLastAddedDate)
        guard interval > 0 else {
            return
        }

        if let currentAverage = history.averageInterval, history.addCount > 2 {
            let previousObservationCount = Double(history.addCount - 2)
            history.averageInterval = ((currentAverage * previousObservationCount) + interval) / Double(history.addCount - 1)
        } else {
            history.averageInterval = interval
        }
    }

    private func productKey(for item: ShoppingItem) -> String {
        if let barcode = normalizedBarcode(item.barcode) {
            return "barcode:\(barcode)"
        }

        return "name:\(item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func normalizedBarcode(_ barcode: String?) -> String? {
        let normalized = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }

    private func legacyEvidenceLessThan(
        _ lhs: ProductStateLegacyHistoryAggregateEvidence,
        _ rhs: ProductStateLegacyHistoryAggregateEvidence
    ) -> Bool {
        if lhs.lastObservedAt != rhs.lastObservedAt {
            return lhs.lastObservedAt > rhs.lastObservedAt
        }
        return lhs.legacyRecordID.uuidString < rhs.legacyRecordID.uuidString
    }

    private func targetDiagnostic(
        projection: ProductStateShoppingMemoryProjection,
        outcome: ProductStateShoppingMemoryQueryOutcomeKind
    ) -> ProductStateShoppingMemoryDiagnostic {
        ProductStateShoppingMemoryDiagnostic(
            productID: projection.productID.rawValue,
            outcome: outcome,
            nativeEventCount: projection.nativeHistory.retainedEventCount,
            linkedLegacyEvidenceCount:
                projection.linkedLegacyEvidence.count,
            rejectedLegacyEvidenceCount:
                projection.rejectedLegacyEvidenceCount,
            duplicateContributionCount:
                projection.nativeHistory.aggregate
                    .duplicateContributionCount,
            unsupportedEvidenceCount:
                projection.nativeHistory.aggregate.unsupportedEvidenceCount,
            provenances: projection.provenances
        )
    }

    private func emptyTargetDiagnostic(
        productID: ProductStateProductID,
        outcome: ProductStateShoppingMemoryQueryOutcomeKind,
        rejectedLegacyEvidenceCount: Int
    ) -> ProductStateShoppingMemoryDiagnostic {
        ProductStateShoppingMemoryDiagnostic(
            productID: productID.rawValue,
            outcome: outcome,
            nativeEventCount: 0,
            linkedLegacyEvidenceCount: 0,
            rejectedLegacyEvidenceCount: rejectedLegacyEvidenceCount,
            duplicateContributionCount: 0,
            unsupportedEvidenceCount: 0,
            provenances: []
        )
    }
}
