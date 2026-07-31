import Foundation
import SwiftData

@Model
final class ProductHistory {
    var id: UUID
    var productKey: String
    var productName: String
    var barcode: String?
    var firstAddedDate: Date
    var lastAddedDate: Date
    var addCount: Int
    var lastSourceRawValue: String
    var averageInterval: TimeInterval?
    var lastCompletedDate: Date?

    init(
        id: UUID = UUID(),
        productKey: String,
        productName: String,
        barcode: String? = nil,
        firstAddedDate: Date = Date(),
        lastAddedDate: Date = Date(),
        addCount: Int = 1,
        lastSource: ProductSource = .manual,
        averageInterval: TimeInterval? = nil,
        lastCompletedDate: Date? = nil
    ) {
        self.id = id
        self.productKey = productKey
        self.productName = productName
        self.barcode = barcode
        self.firstAddedDate = firstAddedDate
        self.lastAddedDate = lastAddedDate
        self.addCount = addCount
        self.lastSourceRawValue = lastSource.rawValue
        self.averageInterval = averageInterval
        self.lastCompletedDate = lastCompletedDate
    }

    var lastSource: ProductSource {
        ProductSource(rawValue: lastSourceRawValue) ?? .manual
    }
}

// The aggregate above remains the inactive compatibility record. Target
// authority is represented by immutable, Product-UUID-keyed event rows.
extension WayTaskSchemaV4 {
    @Model
    final class ProductHistoryEvent {
        var id: UUID
        var productID: UUID
        var meaningRawValue: String
        var resolutionReasonRawValue: String?
        var sessionOutcomeRawValue: String?
        var sourceListID: UUID?
        var sourceEntryID: UUID?
        var sessionID: UUID?
        var sessionLineID: UUID?
        var commandID: UUID?
        var provenanceRawValue: String
        var occurredAt: Date
        var displaySnapshotID: UUID?

        @Relationship(deleteRule: .nullify)
        var product: Product?

        init(
            id: UUID,
            productID: UUID,
            meaningRawValue: String,
            resolutionReasonRawValue: String? = nil,
            sessionOutcomeRawValue: String? = nil,
            sourceListID: UUID? = nil,
            sourceEntryID: UUID? = nil,
            sessionID: UUID? = nil,
            sessionLineID: UUID? = nil,
            commandID: UUID? = nil,
            provenanceRawValue: String,
            occurredAt: Date,
            displaySnapshotID: UUID? = nil,
            product: Product? = nil
        ) {
            self.id = id
            self.productID = productID
            self.meaningRawValue = meaningRawValue
            self.resolutionReasonRawValue = resolutionReasonRawValue
            self.sessionOutcomeRawValue = sessionOutcomeRawValue
            self.sourceListID = sourceListID
            self.sourceEntryID = sourceEntryID
            self.sessionID = sessionID
            self.sessionLineID = sessionLineID
            self.commandID = commandID
            self.provenanceRawValue = provenanceRawValue
            self.occurredAt = occurredAt
            self.displaySnapshotID = displaySnapshotID
            self.product = product
        }
    }
}
