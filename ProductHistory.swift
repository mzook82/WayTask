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
