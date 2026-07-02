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

        return try insert(item, location: location, in: modelContext)
    }

    @discardableResult
    func addRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem {
        let item = makeShoppingItem(from: candidate, fallbackImageData: fallbackImageData)
        return try insert(item, location: nil, in: modelContext)
    }

    func makeShoppingItem(from candidate: ProductCandidate, fallbackImageData: Data?) -> ShoppingItem {
        ShoppingItem(
            name: candidate.name,
            isCompleted: false,
            imageData: candidate.imageData ?? fallbackImageData,
            brand: candidate.brand,
            category: candidate.category,
            barcode: candidate.barcode,
            imageURL: candidate.imageURL,
            dateAdded: Date(),
            source: source(for: candidate.source)
        )
    }

    @discardableResult
    private func insert(
        _ item: ShoppingItem,
        location: GeoLocation?,
        in modelContext: ModelContext
    ) throws -> ShoppingItem {
        modelContext.insert(item)

        if let location {
            location.shoppingItems.append(item)
        }

        try modelContext.save()
        try verifyInsertedItem(item, in: modelContext)
        try shoppingMemoryService.recordProductAdded(item, in: modelContext)
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

    private func source(for candidateSource: ProductCandidateSource) -> ProductSource {
        switch candidateSource {
        case .cameraPhoto, .photoLibrary:
            return .camera
        case .barcode:
            return .barcode
        case .manual:
            return .manual
        case .unknown:
            return .manual
        }
    }
}
