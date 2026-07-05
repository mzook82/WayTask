import Foundation
import SwiftData

enum ShoppingListServiceError: LocalizedError {
    case insertVerificationFailed(itemID: UUID, name: String, barcode: String?, fetchedCount: Int)

    var errorDescription: String? {
        switch self {
        case .insertVerificationFailed(let itemID, let name, let barcode, let fetchedCount):
            return "The shopping item was not found after saving. id=\(itemID), name=\(name), barcode=\(barcode ?? "nil"), fetchedCount=\(fetchedCount)"
        }
    }
}

protocol ShoppingListServicing {
    @discardableResult
    func addManualItem(
        name: String,
        imageData: Data?,
        location: GeoLocation?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem

    @discardableResult
    func addRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem

    func makeShoppingItem(from candidate: ProductCandidate, fallbackImageData: Data?) -> ShoppingItem
}

struct ShoppingListService: ShoppingListServicing {
    private let shoppingMemoryService = ShoppingMemoryService()
    private let productKnowledgeService = ProductKnowledgeService()

    @discardableResult
    func addManualItem(
        name: String,
        imageData: Data?,
        location: GeoLocation?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem {
        let item = ShoppingItem(
            name: name,
            imageData: imageData,
            source: .manual
        )

        return try insert(item, location: location, candidate: nil, fallbackImageData: nil, in: modelContext)
    }

    @discardableResult
    func addRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem {
        let item = makeShoppingItem(from: candidate, fallbackImageData: fallbackImageData)
        return try insert(item, location: nil, candidate: candidate, fallbackImageData: fallbackImageData, in: modelContext)
    }

    func makeShoppingItem(from candidate: ProductCandidate, fallbackImageData: Data?) -> ShoppingItem {
        ShoppingItem(
            name: candidate.name,
            isCompleted: false,
            imageData: productImageData(for: candidate, fallbackImageData: fallbackImageData),
            brand: candidate.brand,
            category: candidate.category,
            barcode: candidate.barcode,
            imageURL: candidate.imageURL,
            dateAdded: Date(),
            source: source(for: candidate.source),
            productType: candidate.productType,
            flavor: candidate.flavor,
            packageSize: candidate.packageSize,
            packageType: candidate.packageType,
            visibleText: candidate.visibleText,
            searchKeywords: candidate.searchKeywords
        )
    }

    @discardableResult
    private func insert(
        _ item: ShoppingItem,
        location: GeoLocation?,
        candidate: ProductCandidate?,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem {
        modelContext.insert(item)

        if let location {
            location.shoppingItems.append(item)
        }

        try modelContext.save()
        try verifyInsertedItem(item, in: modelContext)
        recordShoppingMemoryIfPossible(for: item, in: modelContext)
        recordProductKnowledgeIfPossible(for: item, candidate: candidate, fallbackImageData: fallbackImageData, in: modelContext)
        return item
    }

    private func verifyInsertedItem(_ item: ShoppingItem, in modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<ShoppingItem>()
        let matches = try modelContext.fetch(descriptor)

        guard matches.contains(where: { match in
            match.id == item.id &&
            match.name == item.name &&
            match.barcode == item.barcode
        }) else {
            throw ShoppingListServiceError.insertVerificationFailed(
                itemID: item.id,
                name: item.name,
                barcode: item.barcode,
                fetchedCount: matches.count
            )
        }
    }

    private func recordShoppingMemoryIfPossible(for item: ShoppingItem, in modelContext: ModelContext) {
        do {
            try shoppingMemoryService.recordProductAdded(item, in: modelContext)
        } catch {
            assertionFailure("Shopping memory recording failed: \(error.localizedDescription)")
        }
    }

    private func recordProductKnowledgeIfPossible(
        for item: ShoppingItem,
        candidate: ProductCandidate?,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) {
        do {
            if let candidate {
                try productKnowledgeService.learn(
                    from: candidate,
                    fallbackImageData: fallbackImageData,
                    in: modelContext
                )
            } else {
                try productKnowledgeService.learn(from: item, in: modelContext)
            }
        } catch {
            assertionFailure("Product knowledge recording failed: \(error.localizedDescription)")
        }
    }

    private func source(for candidateSource: ProductCandidateSource) -> ProductSource {
        switch candidateSource {
        case .cameraPhoto, .photoLibrary:
            return .camera
        case .barcode:
            return .barcode
        case .ai:
            return .ai
        case .manual:
            return .manual
        case .unknown:
            return .manual
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
