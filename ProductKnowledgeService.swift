import Foundation
import SwiftData

protocol ProductKnowledgeServicing {
    func productKnowledge(forBarcode barcode: String, in modelContext: ModelContext) throws -> ProductKnowledge?
    func productCandidate(forBarcode barcode: String, in modelContext: ModelContext) throws -> ProductCandidate?

    @discardableResult
    func learn(
        from candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ProductKnowledge

    @discardableResult
    func learn(
        from item: ShoppingItem,
        in modelContext: ModelContext
    ) throws -> ProductKnowledge
}

struct ProductKnowledgeService: ProductKnowledgeServicing {
    func productKnowledge(forBarcode barcode: String, in modelContext: ModelContext) throws -> ProductKnowledge? {
        guard let normalizedBarcode = normalizeBarcode(barcode) else {
            return nil
        }

        return try productKnowledge(forKey: "barcode:\(normalizedBarcode)", in: modelContext)
    }

    func productCandidate(forBarcode barcode: String, in modelContext: ModelContext) throws -> ProductCandidate? {
        try productKnowledge(forBarcode: barcode, in: modelContext).map(makeCandidate)
    }

    @discardableResult
    func learn(
        from candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ProductKnowledge {
        let record = KnowledgeRecord(
            barcode: normalizeBarcode(candidate.barcode),
            productName: candidate.name,
            preferredDisplayName: candidate.name,
            brand: candidate.brand,
            category: candidate.category,
            productType: candidate.productType,
            flavor: candidate.flavor,
            packageSize: candidate.packageSize,
            thumbnailData: productImageData(for: candidate, fallbackImageData: fallbackImageData),
            imageURL: candidate.imageURL,
            searchKeywords: candidate.searchKeywords.isEmpty ? candidate.productHints : candidate.searchKeywords,
            aiConfidence: candidate.confidence,
            recognitionSource: candidate.source
        )

        return try learn(record, in: modelContext)
    }

    @discardableResult
    func learn(
        from item: ShoppingItem,
        in modelContext: ModelContext
    ) throws -> ProductKnowledge {
        let record = KnowledgeRecord(
            barcode: normalizeBarcode(item.barcode),
            productName: item.name,
            preferredDisplayName: item.name,
            brand: item.brand,
            category: item.category,
            productType: item.productType,
            flavor: item.flavor,
            packageSize: item.packageSize,
            thumbnailData: item.imageData,
            imageURL: item.imageURL,
            searchKeywords: item.searchKeywords,
            aiConfidence: nil,
            recognitionSource: candidateSource(for: item.source)
        )

        return try learn(record, in: modelContext)
    }

    private func learn(_ record: KnowledgeRecord, in modelContext: ModelContext) throws -> ProductKnowledge {
        let productName = normalizedRequiredText(record.productName, fallback: "Product")
        let key = knowledgeKey(barcode: record.barcode, productName: productName)
        let now = Date()

        if let existing = try productKnowledge(forKey: key, in: modelContext) {
            update(existing, with: record, productName: productName, now: now)
            try modelContext.save()
            return existing
        }

        let knowledge = ProductKnowledge(
            knowledgeKey: key,
            barcode: record.barcode,
            productName: productName,
            preferredDisplayName: normalizedOptionalText(record.preferredDisplayName) ?? productName,
            brand: normalizedOptionalText(record.brand),
            category: normalizedOptionalText(record.category),
            productType: normalizedOptionalText(record.productType),
            flavor: normalizedOptionalText(record.flavor),
            packageSize: normalizedOptionalText(record.packageSize),
            thumbnailData: record.thumbnailData,
            imageURL: record.imageURL,
            searchKeywords: mergedKeywords([], record.searchKeywords),
            aiConfidence: record.aiConfidence,
            recognitionSource: record.recognitionSource,
            dateLearned: now,
            lastUsed: now,
            timesUsed: 1,
            updatedAt: now
        )

        modelContext.insert(knowledge)
        try modelContext.save()
        return knowledge
    }

    private func update(
        _ knowledge: ProductKnowledge,
        with record: KnowledgeRecord,
        productName: String,
        now: Date
    ) {
        knowledge.productName = productName
        knowledge.preferredDisplayName = normalizedOptionalText(record.preferredDisplayName) ?? productName
        knowledge.barcode = record.barcode
        knowledge.brand = normalizedOptionalText(record.brand)
        knowledge.category = normalizedOptionalText(record.category)
        knowledge.productType = normalizedOptionalText(record.productType)
        knowledge.flavor = normalizedOptionalText(record.flavor)
        knowledge.packageSize = normalizedOptionalText(record.packageSize)
        knowledge.thumbnailData = record.thumbnailData ?? knowledge.thumbnailData

        if let imageURL = record.imageURL {
            knowledge.imageURLString = imageURL.absoluteString
        }

        knowledge.searchKeywords = mergedKeywords(knowledge.searchKeywords, record.searchKeywords)
        knowledge.aiConfidence = record.aiConfidence ?? knowledge.aiConfidence
        knowledge.recognitionSource = record.recognitionSource ?? knowledge.recognitionSource
        knowledge.lastUsed = now
        knowledge.timesUsed += 1
        knowledge.updatedAt = now
    }

    private func productKnowledge(forKey key: String, in modelContext: ModelContext) throws -> ProductKnowledge? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var descriptor = FetchDescriptor<ProductKnowledge>(
            predicate: #Predicate { knowledge in
                knowledge.knowledgeKey == normalizedKey
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func makeCandidate(from knowledge: ProductKnowledge) -> ProductCandidate {
        let displayName = normalizedOptionalText(knowledge.preferredDisplayName) ?? knowledge.productName
        let keywords = knowledge.searchKeywords
        let hints = mergedKeywords(
            [knowledge.brand, knowledge.category, knowledge.productType, knowledge.flavor, knowledge.packageSize].compactMap { $0 },
            keywords
        )

        return ProductCandidate(
            name: displayName,
            brand: knowledge.brand,
            category: knowledge.category,
            confidence: knowledge.aiConfidence,
            productType: knowledge.productType,
            flavor: knowledge.flavor,
            packageSize: knowledge.packageSize,
            source: knowledge.recognitionSource ?? .barcode,
            productHints: hints,
            searchKeywords: keywords,
            imageURL: knowledge.imageURL,
            imageData: knowledge.thumbnailData,
            barcode: knowledge.barcode
        )
    }

    private func knowledgeKey(barcode: String?, productName: String) -> String {
        if let barcode {
            return "barcode:\(barcode)"
        }

        return "name:\(productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func normalizeBarcode(_ barcode: String?) -> String? {
        let normalized = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }

    private func normalizedRequiredText(_ value: String, fallback: String) -> String {
        normalizedOptionalText(value) ?? fallback
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }

    private func mergedKeywords(_ existing: [String], _ incoming: [String]) -> [String] {
        (existing + incoming)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, keyword in
                if !result.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }) {
                    result.append(keyword)
                }
            }
    }

    private func candidateSource(for productSource: ProductSource) -> ProductCandidateSource {
        switch productSource {
        case .manual:
            return .manual
        case .barcode:
            return .barcode
        case .camera:
            return .cameraPhoto
        case .ai:
            return .ai
        case .discover:
            return .unknown
        }
    }

    private func productImageData(for candidate: ProductCandidate, fallbackImageData: Data?) -> Data? {
        if let imageData = candidate.imageData {
            return imageData
        }

        if candidate.imageURL != nil {
            return nil
        }

        return fallbackImageData
    }
}

private struct KnowledgeRecord {
    let barcode: String?
    let productName: String
    let preferredDisplayName: String?
    let brand: String?
    let category: String?
    let productType: String?
    let flavor: String?
    let packageSize: String?
    let thumbnailData: Data?
    let imageURL: URL?
    let searchKeywords: [String]
    let aiConfidence: Double?
    let recognitionSource: ProductCandidateSource?
}
