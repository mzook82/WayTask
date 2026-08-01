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
    private let catalogResolver = ShoppingItemCatalogResolver()

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

    /// T-10 target-only recognition route. Exact barcode evidence can locate
    /// an existing Product, but a tombstone is returned as restore-required;
    /// this adapter never restores or adds list membership implicitly.
    func acquireTargetProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        productID: ProductStateProductID,
        commandID: ProductStateCommandID,
        effectiveAt: Date,
        reviewed: Bool,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductStateProductCommandExecution {
        authority.acquire(
            ProductStateProductAcquisitionRequest(
                commandID: commandID,
                productID: productID,
                effectiveAt: effectiveAt,
                reviewed: reviewed,
                name: candidate.name,
                imageData: productImageData(
                    for: candidate,
                    fallbackImageData: fallbackImageData
                ),
                brand: candidate.brand,
                category: candidate.category,
                barcode: candidate.barcode,
                imageURLString: candidate.imageURL?.absoluteString,
                sourceRawValue: source(for: candidate.source).rawValue
            )
        )
    }

    @discardableResult
    func upsertRecognizedProduct(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?,
        in modelContext: ModelContext
    ) throws -> Product {
        let products = try modelContext.fetch(FetchDescriptor<Product>())
        let unlinkedProducts = products.filter { $0.catalogProductIDRawValue == nil }
        let activeUnlinkedProducts = unlinkedProducts.filter {
            !$0.isDeletedFromLibrary
        }
        let product: Product

        if let barcode = normalizedText(candidate.barcode),
           let existing = unlinkedProducts.first(where: { normalizedText($0.barcode) == barcode }) {
            // Scanning the same barcode is an explicit user request to restore
            // this identity; passive repair never calls this path.
            existing.restoreToLibrary()
            existing.refresh(from: candidate, fallbackImageData: fallbackImageData)
            product = existing
        } else if let existing = activeUnlinkedProducts.first(where: {
            productMatches($0, candidate: candidate)
        }) {
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
                refresh(item, from: product)
                item.isCompleted = false
                product.legacyShoppingItemID = item.id
            } else {
                let item = product.makeShoppingItem()
                catalogResolver.hydrate(item, from: product)
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
        if product.catalogProductIDRawValue == nil {
            recordProductKnowledgeIfPossible(for: item, candidate: nil, fallbackImageData: nil, in: modelContext)
        }
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
        catalogResolver.hydrate(item, from: product)
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
        catalogResolver.hydrate(item, from: product)
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

@MainActor
struct ProductLibraryDeletionService {
    typealias Clock = () -> Date

    private let clock: Clock

    init(clock: @escaping Clock = Date.init) {
        self.clock = clock
    }

    func delete(
        _ product: Product,
        in modelContext: ModelContext
    ) throws {
        let lists = try modelContext.fetch(FetchDescriptor<ShoppingList>())
        let activeListIDs = Set(
            lists.filter { $0.kind == .weekly }.map(\.id)
        )
        let entries = try modelContext.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let legacyItems = try modelContext.fetch(
            FetchDescriptor<ShoppingItem>()
        )
        let legacyItemsByID = legacyItems.reduce(
            into: [UUID: ShoppingItem]()
        ) { result, item in
            result[item.id] = item
        }

        product.markDeletedFromLibrary(at: clock())

        // Removing a library product also removes it from current shopping,
        // while completed and recent list entries remain durable history.
        for entry in entries where
            entry.productID == product.id &&
            activeListIDs.contains(entry.shoppingListID)
        {
            if let legacyShoppingItemID = entry.legacyShoppingItemID,
               let item = legacyItemsByID[legacyShoppingItemID] {
                item.isCompleted = true
            }
            modelContext.delete(entry)
        }

        try modelContext.save()
    }

    /// T-10 target-only adapter. The caller supplies the exact impact summary;
    /// Product, all editable lists, and the required history event are then
    /// owned by one Product Command Authority transaction.
    func removeFromTargetLibrary(
        productID: ProductStateProductID,
        commandID: ProductStateCommandID,
        historyEventID: ProductStateHistoryEventID,
        expectedProductRevision: UInt64,
        expectedAffectedListRevisions:
            [ProductStateListRevisionExpectation],
        effectiveAt: Date? = nil,
        confirmed: Bool,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductStateProductCommandExecution {
        let effectiveAt = effectiveAt ?? clock()
        let command = ProductStateCommand(
            id: commandID,
            expectedRevision: ProductStateExpectedRevision(
                revision: ProductStateRevision(
                    scope: .product(productID),
                    value: expectedProductRevision
                )
            ),
            effectiveAt: effectiveAt,
            intent: .removeProductFromLibrary(
                RemoveProductFromLibraryCommand(
                    productID: productID,
                    historyEventID: historyEventID,
                    confirmed: confirmed
                )
            )
        )
        return authority.removeFromLibrary(
            command,
            expectedAffectedListRevisions:
                expectedAffectedListRevisions
        )
    }
}

struct ShoppingListBackfillResult {
    let weeklyListID: UUID?
    let productIDs: [UUID]
    let repairActionCount: Int
}

struct ShoppingListBackfillService {
    private let catalogResolver = ShoppingItemCatalogResolver()

    @discardableResult
    func ensureDefaultListsAndBackfill(in modelContext: ModelContext) throws -> ShoppingListBackfillResult {
        let lists = try modelContext
            .fetch(FetchDescriptor<ShoppingList>())
            .sorted(by: stableIDOrder)
        let legacyItems = try modelContext
            .fetch(FetchDescriptor<ShoppingItem>())
            .sorted(by: stableIDOrder)
        var products = try modelContext
            .fetch(FetchDescriptor<Product>())
            .sorted(by: stableIDOrder)
        let entries = try modelContext
            .fetch(FetchDescriptor<ShoppingListEntry>())
            .sorted(by: stableIDOrder)
        var productIDs = Set<UUID>()
        var repairActionCount = 0
        let hasExistingState =
            !lists.isEmpty ||
            !legacyItems.isEmpty ||
            !products.isEmpty ||
            !entries.isEmpty
        let weeklyList = ensureList(
            kind: .weekly,
            title: "Weekly Shopping",
            isDefault: true,
            existingLists: lists,
            countCreationAsRepair: hasExistingState,
            repairActionCount: &repairActionCount,
            in: modelContext
        )
        _ = ensureList(
            kind: .completed,
            title: "Completed",
            isDefault: false,
            existingLists: lists,
            countCreationAsRepair: hasExistingState,
            repairActionCount: &repairActionCount,
            in: modelContext
        )
        _ = ensureList(
            kind: .recent,
            title: "Recent",
            isDefault: false,
            existingLists: lists,
            countCreationAsRepair: hasExistingState,
            repairActionCount: &repairActionCount,
            in: modelContext
        )

        repairActionCount += repairCatalogProducts(
            products.filter { !$0.isDeletedFromLibrary }
        )

        for item in legacyItems {
            let productCountBeforeRepair = products.count
            guard let product = product(
                for: item,
                entries: entries,
                products: &products,
                weeklyListID: weeklyList.id,
                in: modelContext
            ) else {
                continue
            }
            if products.count > productCountBeforeRepair {
                repairActionCount += 1
            }

            if product.isDeletedFromLibrary {
                repairActionCount += removeActiveEntries(
                    for: product,
                    item: item,
                    entries: entries,
                    weeklyListID: weeklyList.id,
                    in: modelContext
                )
                continue
            }

            if product.catalogProductIDRawValue == nil,
               product.legacyShoppingItemID == nil ||
                product.legacyShoppingItemID == item.id
            {
                if product.refresh(from: item) {
                    repairActionCount += 1
                }
            }
            catalogResolver.hydrate(item, from: product)
            productIDs.insert(product.id)

            if let existingEntry = entries.first(where: { entry in
                entry.shoppingListID == weeklyList.id &&
                (entry.legacyShoppingItemID == item.id || entry.productID == product.id)
            }) {
                if existingEntry.productID != product.id ||
                    existingEntry.product?.id != product.id
                {
                    existingEntry.productID = product.id
                    existingEntry.product = product
                    repairActionCount += 1
                }

                if existingEntry.legacyShoppingItemID != item.id {
                    existingEntry.legacyShoppingItemID = item.id
                    repairActionCount += 1
                }
            }
        }

        try modelContext.save()
        return ShoppingListBackfillResult(
            weeklyListID: weeklyList.id,
            productIDs: productIDs.sorted {
                $0.uuidString < $1.uuidString
            },
            repairActionCount: repairActionCount
        )
    }

    private func repairCatalogProducts(
        _ products: [Product]
    ) -> Int {
        let resolvableProducts = products.compactMap { product in
            catalogResolver.resolve(
                productIDRawValue: product.catalogProductIDRawValue
            ).map { identity in
                (product: product, canonicalID: identity.productID)
            }
        }
        let groups = Dictionary(
            grouping: resolvableProducts,
            by: { $0.canonicalID }
        )
        let referenceDate = Date()
        var repairActionCount = 0

        for (canonicalID, group) in groups {
            let canRewriteIdentity = group.count == 1
            for value in group {
                if catalogResolver.repairCanonicalMetadata(
                    for: value.product,
                    rewriteProductID: canRewriteIdentity,
                    referenceDate: referenceDate
                ) {
                    repairActionCount += 1
                }
            }

            guard !canRewriteIdentity else {
                continue
            }

            #if DEBUG
            let userProductIDs = group
                .map(\.product.id.uuidString)
                .sorted()
                .joined(separator: ",")
            print(
                "[WayTask Catalog Identity] logical duplicate canonicalID=\(canonicalID) userProductIDs=\(userProductIDs); IDs preserved for non-destructive review"
            )
            #endif
        }
        return repairActionCount
    }

    private func ensureList(
        kind: ShoppingListKind,
        title: String,
        isDefault: Bool,
        existingLists: [ShoppingList],
        countCreationAsRepair: Bool,
        repairActionCount: inout Int,
        in modelContext: ModelContext
    ) -> ShoppingList {
        if let existing = existingLists.first(where: { $0.kind == kind }) {
            if existing.title != title || existing.isDefault != isDefault {
                existing.title = title
                existing.isDefault = isDefault
                existing.updatedAt = Date()
                repairActionCount += 1
            }
            return existing
        }

        let list = ShoppingList(title: title, kind: kind, isDefault: isDefault)
        modelContext.insert(list)
        if countCreationAsRepair {
            repairActionCount += 1
        }
        return list
    }

    private func product(
        for item: ShoppingItem,
        entries: [ShoppingListEntry],
        products: inout [Product],
        weeklyListID: UUID,
        in modelContext: ModelContext
    ) -> Product? {
        if let existing = products.first(where: { $0.legacyShoppingItemID == item.id }) {
            return existing
        }

        if let linkedProduct = entries.lazy.compactMap({ entry -> Product? in
            guard entry.legacyShoppingItemID == item.id else {
                return nil
            }
            return entry.product
        }).first {
            if linkedProduct.legacyShoppingItemID == nil {
                linkedProduct.legacyShoppingItemID = item.id
            }
            return linkedProduct
        }

        if let catalogProductID = canonicalProductID(for: item),
           let existing = products.first(where: {
               canonicalProductID(for: $0) == catalogProductID
           }) {
            return existing
        }

        if let barcode = normalizedBarcode(item.barcode),
           let existing = products.first(where: {
               normalizedBarcode($0.barcode) == barcode
           }) {
            return existing
        }

        let itemEntries = entries.filter {
            $0.legacyShoppingItemID == item.id
        }
        let isCurrentWeeklyItem = itemEntries.contains {
            $0.shoppingListID == weeklyListID
        }
        let isUnlinkedActiveLegacyItem =
            itemEntries.isEmpty && !item.isCompleted
        guard isCurrentWeeklyItem || isUnlinkedActiveLegacyItem else {
            // Completed/recent history is a consumer of Product identity, not
            // a source allowed to create an active library Product.
            return nil
        }

        let product = Product(legacyItem: item)
        modelContext.insert(product)
        products.append(product)
        return product
    }

    private func removeActiveEntries(
        for product: Product,
        item: ShoppingItem,
        entries: [ShoppingListEntry],
        weeklyListID: UUID,
        in modelContext: ModelContext
    ) -> Int {
        var repairActionCount = 0
        if !item.isCompleted {
            item.isCompleted = true
            repairActionCount += 1
        }
        for entry in entries where
            entry.shoppingListID == weeklyListID &&
            (
                entry.productID == product.id ||
                entry.legacyShoppingItemID == item.id
            )
        {
            modelContext.delete(entry)
            repairActionCount += 1
        }
        return repairActionCount
    }

    private func canonicalProductID(for item: ShoppingItem) -> String? {
        catalogResolver.resolve(
            productIDRawValue: item.catalogProductIDRawValue
        )?.productID
    }

    private func canonicalProductID(for product: Product) -> String? {
        catalogResolver.resolve(
            productIDRawValue: product.catalogProductIDRawValue
        )?.productID
    }

    private func normalizedBarcode(_ barcode: String?) -> String? {
        let normalized = barcode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private func stableIDOrder<T: Identifiable>(
        _ lhs: T,
        _ rhs: T
    ) -> Bool where T.ID == UUID {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
