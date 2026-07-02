import Foundation
import SwiftData

protocol ShoppingMemoryServicing {
    @discardableResult
    func recordProductAdded(_ item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory
    func productHistory(for item: ShoppingItem, in modelContext: ModelContext) throws -> ProductHistory?
    func productHistory(productKey: String, in modelContext: ModelContext) throws -> ProductHistory?
    func frequentlyAddedProducts(limit: Int, in modelContext: ModelContext) throws -> [ProductHistory]
}

struct ShoppingMemoryService: ShoppingMemoryServicing {
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
}
