import Foundation
import SwiftData

@Model
final class ProductKnowledge {
    var id: UUID
    var knowledgeKey: String
    var barcode: String?
    var productName: String
    var preferredDisplayName: String?
    var brand: String?
    var category: String?
    var productType: String?
    var flavor: String?
    var packageSize: String?
    var thumbnailData: Data?
    var imageURLString: String?
    var searchKeywordsRawValue: String?
    var aiConfidence: Double?
    var recognitionSourceRawValue: String?
    var dateLearned: Date
    var lastUsed: Date?
    var timesUsed: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        knowledgeKey: String,
        barcode: String? = nil,
        productName: String,
        preferredDisplayName: String? = nil,
        brand: String? = nil,
        category: String? = nil,
        productType: String? = nil,
        flavor: String? = nil,
        packageSize: String? = nil,
        thumbnailData: Data? = nil,
        imageURL: URL? = nil,
        searchKeywords: [String] = [],
        aiConfidence: Double? = nil,
        recognitionSource: ProductCandidateSource? = nil,
        dateLearned: Date = Date(),
        lastUsed: Date? = nil,
        timesUsed: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.knowledgeKey = knowledgeKey
        self.barcode = barcode
        self.productName = productName
        self.preferredDisplayName = preferredDisplayName
        self.brand = brand
        self.category = category
        self.productType = productType
        self.flavor = flavor
        self.packageSize = packageSize
        self.thumbnailData = thumbnailData
        self.imageURLString = imageURL?.absoluteString
        self.searchKeywordsRawValue = Self.encodeSearchKeywords(searchKeywords)
        self.aiConfidence = aiConfidence
        self.recognitionSourceRawValue = recognitionSource?.rawValue
        self.dateLearned = dateLearned
        self.lastUsed = lastUsed
        self.timesUsed = timesUsed
        self.updatedAt = updatedAt
    }

    var imageURL: URL? {
        guard let imageURLString else {
            return nil
        }

        return URL(string: imageURLString)
    }

    var recognitionSource: ProductCandidateSource? {
        get {
            guard let recognitionSourceRawValue else {
                return nil
            }

            return ProductCandidateSource(rawValue: recognitionSourceRawValue)
        }
        set {
            recognitionSourceRawValue = newValue?.rawValue
        }
    }

    var searchKeywords: [String] {
        get {
            guard let searchKeywordsRawValue else {
                return []
            }

            return searchKeywordsRawValue
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            searchKeywordsRawValue = Self.encodeSearchKeywords(newValue)
        }
    }

    private static func encodeSearchKeywords(_ keywords: [String]) -> String? {
        let normalized = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return nil
        }

        return normalized.joined(separator: "\n")
    }
}
