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
        let existingSource = knowledge.recognitionSource
        let incomingSource = record.recognitionSource

        knowledge.productName = refreshedRequiredText(
            existing: knowledge.productName,
            incoming: productName,
            protectsDescriptiveText: true,
            existingSource: existingSource,
            incomingSource: incomingSource
        )
        knowledge.preferredDisplayName = refreshedOptionalText(
            existing: knowledge.preferredDisplayName,
            incoming: record.preferredDisplayName,
            protectsDescriptiveText: true,
            existingSource: existingSource,
            incomingSource: incomingSource
        ) ?? knowledge.productName
        knowledge.barcode = record.barcode ?? knowledge.barcode
        knowledge.brand = refreshedOptionalText(
            existing: knowledge.brand,
            incoming: record.brand,
            protectsDescriptiveText: false,
            existingSource: existingSource,
            incomingSource: incomingSource
        )
        knowledge.category = refreshedOptionalText(
            existing: knowledge.category,
            incoming: record.category,
            protectsDescriptiveText: false,
            existingSource: existingSource,
            incomingSource: incomingSource
        )
        knowledge.productType = refreshedOptionalText(
            existing: knowledge.productType,
            incoming: record.productType,
            protectsDescriptiveText: false,
            existingSource: existingSource,
            incomingSource: incomingSource
        )
        knowledge.flavor = refreshedOptionalText(
            existing: knowledge.flavor,
            incoming: record.flavor,
            protectsDescriptiveText: false,
            existingSource: existingSource,
            incomingSource: incomingSource
        )
        knowledge.packageSize = refreshedOptionalText(
            existing: knowledge.packageSize,
            incoming: record.packageSize,
            protectsDescriptiveText: false,
            existingSource: existingSource,
            incomingSource: incomingSource
        )

        if let thumbnailData = record.thumbnailData,
           knowledge.thumbnailData == nil || shouldRefreshValue(existingSource: existingSource, incomingSource: incomingSource) {
            knowledge.thumbnailData = thumbnailData
        }

        if let imageURL = record.imageURL,
           knowledge.imageURLString == nil || shouldRefreshValue(existingSource: existingSource, incomingSource: incomingSource) {
            knowledge.imageURLString = imageURL.absoluteString
        }

        knowledge.searchKeywords = mergedKeywords(knowledge.searchKeywords, record.searchKeywords)
        if shouldRefreshValue(existingSource: existingSource, incomingSource: incomingSource) {
            knowledge.aiConfidence = record.aiConfidence ?? knowledge.aiConfidence
            knowledge.recognitionSource = record.recognitionSource ?? knowledge.recognitionSource
        }
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

    private func refreshedRequiredText(
        existing: String,
        incoming: String,
        protectsDescriptiveText: Bool,
        existingSource: ProductCandidateSource?,
        incomingSource: ProductCandidateSource?
    ) -> String {
        refreshedOptionalText(
            existing: existing,
            incoming: incoming,
            protectsDescriptiveText: protectsDescriptiveText,
            existingSource: existingSource,
            incomingSource: incomingSource
        ) ?? existing
    }

    private func refreshedOptionalText(
        existing: String?,
        incoming: String?,
        protectsDescriptiveText: Bool,
        existingSource: ProductCandidateSource?,
        incomingSource: ProductCandidateSource?
    ) -> String? {
        guard let incoming = normalizedOptionalText(incoming) else {
            return normalizedOptionalText(existing)
        }

        guard let existing = normalizedOptionalText(existing) else {
            return incoming
        }

        guard shouldRefreshValue(existingSource: existingSource, incomingSource: incomingSource) else {
            return existing
        }

        return protectsDescriptiveText && isClearlyWeaker(incoming, than: existing) ? existing : incoming
    }

    private func shouldRefreshValue(
        existingSource: ProductCandidateSource?,
        incomingSource: ProductCandidateSource?
    ) -> Bool {
        sourcePriority(incomingSource) >= sourcePriority(existingSource)
    }

    private func sourcePriority(_ source: ProductCandidateSource?) -> Int {
        switch source {
        case .manual:
            return 4
        case .ai:
            return 3
        case .barcode:
            return 2
        case .cameraPhoto, .photoLibrary:
            return 1
        case .unknown, nil:
            return 0
        }
    }

    private func isClearlyWeaker(_ incoming: String, than existing: String) -> Bool {
        let incomingWords = wordCount(incoming)
        let existingWords = wordCount(existing)

        return incoming.count < existing.count / 2 && incomingWords < existingWords
    }

    private func wordCount(_ value: String) -> Int {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
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
