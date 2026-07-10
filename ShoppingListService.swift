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

    @discardableResult
    func addManualProduct(
        name: String,
        imageData: Data?,
        in modelContext: ModelContext
    ) throws -> Product

    @discardableResult
    func upsertRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> Product

    @discardableResult
    func addProductToShopping(
        _ product: Product,
        shoppingListID: UUID,
        in modelContext: ModelContext
    ) throws -> ShoppingListEntry

    func removeProductFromShopping(
        _ product: Product,
        shoppingListID: UUID,
        in modelContext: ModelContext
    ) throws

    func makeShoppingItem(from candidate: ProductCandidate, fallbackImageData: Data?) -> ShoppingItem
}

struct ShoppingListService: ShoppingListServicing {
    private let shoppingMemoryService = ShoppingMemoryService()
    private let productKnowledgeService = ProductKnowledgeService()
    private let backfillService = ShoppingListBackfillService()

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

    @discardableResult
    func addManualProduct(
        name: String,
        imageData: Data?,
        in modelContext: ModelContext
    ) throws -> Product {
        let product = Product(
            name: name,
            imageData: imageData,
            dateAdded: Date(),
            updatedAt: Date(),
            source: .manual
        )
        modelContext.insert(product)
        try modelContext.save()
        return product
    }

    @discardableResult
    func upsertRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> Product {
        let products = try modelContext.fetch(FetchDescriptor<Product>())
        let product: Product

        if let barcode = normalizedText(candidate.barcode),
           let existing = products.first(where: { normalizedText($0.barcode) == barcode }) {
            existing.refresh(from: candidate, fallbackImageData: fallbackImageData)
            product = existing
        } else if let existing = products.first(where: { productMatches($0, candidate: candidate) }) {
            existing.refresh(from: candidate, fallbackImageData: fallbackImageData)
            product = existing
        } else {
            product = Product(candidate: candidate, fallbackImageData: fallbackImageData)
            modelContext.insert(product)
        }

        try productKnowledgeService.learn(
            from: candidate,
            fallbackImageData: fallbackImageData,
            in: modelContext
        )
        try modelContext.save()
        return product
    }

    @discardableResult
    func addProductToShopping(
        _ product: Product,
        shoppingListID: UUID,
        in modelContext: ModelContext
    ) throws -> ShoppingListEntry {
        var entries = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
        if let existingEntry = entries.first(where: { $0.shoppingListID == shoppingListID && $0.productID == product.id }) {
            existingEntry.isChecked = false
            if let item = legacyItem(for: existingEntry, in: modelContext) {
                item.isCompleted = false
                product.legacyShoppingItemID = item.id
            } else {
                let item = product.makeShoppingItem()
                modelContext.insert(item)
                existingEntry.legacyShoppingItemID = item.id
                product.legacyShoppingItemID = item.id
            }
            try modelContext.save()
            return existingEntry
        }

        let item = try openCompatibilityItem(for: product, in: modelContext)
        let entry = ShoppingListEntry(
            shoppingListID: shoppingListID,
            product: product,
            legacyShoppingItemID: item.id,
            quantity: 1,
            isChecked: false,
            createdAt: Date(),
            sortOrder: (entries.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(entry)
        entries.append(entry)
        try modelContext.save()
        recordShoppingMemoryIfPossible(for: item, in: modelContext)
        recordProductKnowledgeIfPossible(for: item, candidate: nil, fallbackImageData: nil, in: modelContext)
        return entry
    }

    func removeProductFromShopping(
        _ product: Product,
        shoppingListID: UUID,
        in modelContext: ModelContext
    ) throws {
        let entries = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
        let matchingEntries = entries.filter { $0.shoppingListID == shoppingListID && $0.productID == product.id }

        for entry in matchingEntries {
            if let item = legacyItem(for: entry, in: modelContext) {
                item.isCompleted = true
            }
            modelContext.delete(entry)
        }

        try modelContext.save()
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
        _ = try? backfillService.ensureDefaultListsAndBackfill(in: modelContext)
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

    private func openCompatibilityItem(for product: Product, in modelContext: ModelContext) throws -> ShoppingItem {
        let items = try modelContext.fetch(FetchDescriptor<ShoppingItem>())

        if let legacyID = product.legacyShoppingItemID,
           let item = items.first(where: { $0.id == legacyID }) {
            refresh(item, from: product)
            item.isCompleted = false
            return item
        }

        if let barcode = normalizedText(product.barcode),
           let item = items.first(where: { normalizedText($0.barcode) == barcode }) {
            refresh(item, from: product)
            item.isCompleted = false
            product.legacyShoppingItemID = item.id
            return item
        }

        let item = product.makeShoppingItem()
        modelContext.insert(item)
        product.legacyShoppingItemID = item.id
        return item
    }

    private func legacyItem(for entry: ShoppingListEntry, in modelContext: ModelContext) -> ShoppingItem? {
        guard let legacyShoppingItemID = entry.legacyShoppingItemID,
              let items = try? modelContext.fetch(FetchDescriptor<ShoppingItem>()) else {
            return nil
        }

        return items.first { $0.id == legacyShoppingItemID }
    }

    private func refresh(_ item: ShoppingItem, from product: Product) {
        item.name = product.name
        item.imageData = product.imageData
        item.brand = product.brand
        item.category = product.category
        item.barcode = product.barcode
        item.imageURLString = product.imageURL?.absoluteString
        item.sourceRawValue = product.source.rawValue
        item.productType = product.productType
        item.flavor = product.flavor
        item.packageSize = product.packageSize
        item.packageType = product.packageType
        item.visibleText = product.visibleText
        item.searchKeywords = product.searchKeywords
    }

    private func normalizedText(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }

    private func productMatches(_ product: Product, candidate: ProductCandidate) -> Bool {
        guard normalizedText(product.name) == normalizedText(candidate.name) else {
            return false
        }

        let productBrand = normalizedText(product.brand)
        let candidateBrand = normalizedText(candidate.brand)
        if productBrand != nil || candidateBrand != nil {
            return productBrand == candidateBrand
        }

        let productCategory = normalizedText(product.category)
        let candidateCategory = normalizedText(candidate.category)
        if productCategory != nil || candidateCategory != nil {
            return productCategory == candidateCategory
        }

        return false
    }
}

struct ShoppingListBackfillResult {
    let weeklyListID: UUID?
    let productIDs: [UUID]
}

struct ShoppingListBackfillService {
    @discardableResult
    func ensureDefaultListsAndBackfill(in modelContext: ModelContext) throws -> ShoppingListBackfillResult {
        let lists = try modelContext.fetch(FetchDescriptor<ShoppingList>())
        let weeklyList = ensureList(kind: .weekly, title: "Weekly Shopping", isDefault: true, existingLists: lists, in: modelContext)
        _ = ensureList(kind: .completed, title: "Completed", isDefault: false, existingLists: lists, in: modelContext)
        _ = ensureList(kind: .recent, title: "Recent", isDefault: false, existingLists: lists, in: modelContext)

        let legacyItems = try modelContext.fetch(FetchDescriptor<ShoppingItem>())
        var products = try modelContext.fetch(FetchDescriptor<Product>())
        let entries = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
        var productIDs: [UUID] = []

        for item in legacyItems {
            let product = product(for: item, products: &products, in: modelContext)
            product.refresh(from: item)
            productIDs.append(product.id)

            if let existingEntry = entries.first(where: { entry in
                entry.shoppingListID == weeklyList.id &&
                (entry.legacyShoppingItemID == item.id || entry.productID == product.id)
            }) {
                if existingEntry.productID != product.id {
                    existingEntry.productID = product.id
                    existingEntry.product = product
                }

                if existingEntry.legacyShoppingItemID != item.id {
                    existingEntry.legacyShoppingItemID = item.id
                }
            }
        }

        try modelContext.save()
        return ShoppingListBackfillResult(weeklyListID: weeklyList.id, productIDs: productIDs)
    }

    private func ensureList(
        kind: ShoppingListKind,
        title: String,
        isDefault: Bool,
        existingLists: [ShoppingList],
        in modelContext: ModelContext
    ) -> ShoppingList {
        if let existing = existingLists.first(where: { $0.kind == kind }) {
            if existing.title != title || existing.isDefault != isDefault {
                existing.title = title
                existing.isDefault = isDefault
                existing.updatedAt = Date()
            }
            return existing
        }

        let list = ShoppingList(title: title, kind: kind, isDefault: isDefault)
        modelContext.insert(list)
        return list
    }

    private func product(
        for item: ShoppingItem,
        products: inout [Product],
        in modelContext: ModelContext
    ) -> Product {
        if let existing = products.first(where: { $0.legacyShoppingItemID == item.id }) {
            return existing
        }

        let product = Product(legacyItem: item)
        modelContext.insert(product)
        products.append(product)
        return product
    }
}
