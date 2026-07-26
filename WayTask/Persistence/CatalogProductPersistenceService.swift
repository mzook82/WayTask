import Foundation
import SwiftData

nonisolated struct CatalogProductSaveRequest: Sendable {
    let productID: ProductID
    let displayNameSnapshot: String
    let displayLocaleSnapshot: String
    let categoryIDSnapshot: ProductCategoryID
    let categoryDisplayNameSnapshot: String
    let iconKeySnapshot: String
    let imageData: Data?
    let source: ProductSource

    init(
        productID: ProductID,
        displayNameSnapshot: String,
        displayLocaleSnapshot: String,
        categoryIDSnapshot: ProductCategoryID,
        categoryDisplayNameSnapshot: String,
        iconKeySnapshot: String,
        imageData: Data?,
        source: ProductSource
    ) {
        self.productID = productID
        self.displayNameSnapshot = displayNameSnapshot
        self.displayLocaleSnapshot = displayLocaleSnapshot
        self.categoryIDSnapshot = categoryIDSnapshot
        self.categoryDisplayNameSnapshot = categoryDisplayNameSnapshot
        self.iconKeySnapshot = iconKeySnapshot
        self.imageData = imageData
        self.source = source
    }

    init(
        searchResult: ProductSearchResult,
        imageData: Data?,
        source: ProductSource = .catalog
    ) {
        self.init(
            productID: searchResult.productID,
            displayNameSnapshot: searchResult.displayName,
            displayLocaleSnapshot: searchResult.displayLocale,
            categoryIDSnapshot: searchResult.categoryID,
            categoryDisplayNameSnapshot: searchResult.categoryDisplayName,
            iconKeySnapshot: searchResult.iconKey,
            imageData: imageData,
            source: source
        )
    }
}

nonisolated enum CatalogProductSaveField: String, Sendable {
    case productID
    case displayName
    case displayLocale
    case categoryID
    case categoryDisplayName
    case iconKey
}

enum CatalogProductSaveOutcome {
    case inserted(Product)
    case alreadyPresent(Product)
}

enum CatalogProductPersistenceError: LocalizedError {
    case invalidField(CatalogProductSaveField)
    case unsupportedSource(ProductSource)
    case lookupFailed(productID: String, underlying: Error)
    case duplicateCatalogIdentity(productID: String, userProductIDs: [UUID])
    case saveFailed(productID: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidField(let field):
            return "The catalog product has an invalid \(field.rawValue) value."
        case .unsupportedSource(let source):
            return "The \(source.rawValue) source cannot create a catalog-linked product."
        case .lookupFailed(let productID, let underlying):
            return "Catalog product lookup failed for \(productID): \(underlying.localizedDescription)"
        case .duplicateCatalogIdentity(let productID, let userProductIDs):
            let ids = userProductIDs.map(\.uuidString).joined(separator: ", ")
            return "Multiple user products reference catalog product \(productID): \(ids)"
        case .saveFailed(let productID, let underlying):
            return "Catalog product save failed for \(productID): \(underlying.localizedDescription)"
        }
    }
}

@MainActor
struct CatalogProductPersistenceService {
    typealias Clock = () -> Date
    typealias ContextSaver = (ModelContext) throws -> Void

    private let clock: Clock
    private let saveContext: ContextSaver

    init(
        clock: @escaping Clock = Date.init,
        saveContext: @escaping ContextSaver = { try $0.save() }
    ) {
        self.clock = clock
        self.saveContext = saveContext
    }

    func save(
        _ request: CatalogProductSaveRequest,
        in modelContext: ModelContext
    ) throws -> CatalogProductSaveOutcome {
        try validate(request)

        let rawProductID = request.productID.rawValue
        let matches: [Product]

        do {
            let descriptor = FetchDescriptor<Product>(
                predicate: #Predicate { product in
                    product.catalogProductIDRawValue == rawProductID
                }
            )
            matches = try modelContext.fetch(descriptor).sorted {
                $0.id.uuidString < $1.id.uuidString
            }
        } catch {
            throw CatalogProductPersistenceError.lookupFailed(
                productID: rawProductID,
                underlying: error
            )
        }

        let activeMatches = matches.filter {
            !$0.isDeletedFromLibrary
        }

        if activeMatches.count > 1 {
            throw CatalogProductPersistenceError.duplicateCatalogIdentity(
                productID: rawProductID,
                userProductIDs: activeMatches.map(\.id)
            )
        }

        if let existing = activeMatches.first {
            return .alreadyPresent(existing)
        }

        let now = clock()
        if let deletedProduct = matches.first {
            let restoreSnapshot = CatalogProductRestoreSnapshot(product: deletedProduct)
            restore(
                deletedProduct,
                from: request,
                at: now
            )
            do {
                try saveContext(modelContext)
            } catch {
                restoreSnapshot.restore(deletedProduct)
                throw CatalogProductPersistenceError.saveFailed(
                    productID: rawProductID,
                    underlying: error
                )
            }
            return .inserted(deletedProduct)
        }

        let product = Product(
            name: request.displayNameSnapshot,
            imageData: request.imageData,
            category: request.categoryDisplayNameSnapshot,
            dateAdded: now,
            updatedAt: now,
            source: request.source,
            catalogProductIDRawValue: rawProductID,
            catalogDisplayNameSnapshot: request.displayNameSnapshot,
            catalogDisplayLocaleSnapshot: request.displayLocaleSnapshot,
            catalogCategoryIDSnapshotRawValue: request.categoryIDSnapshot.rawValue,
            catalogCategoryDisplayNameSnapshot: request.categoryDisplayNameSnapshot,
            catalogIconKeySnapshot: request.iconKeySnapshot,
            catalogSnapshotUpdatedAt: now
        )
        modelContext.insert(product)

        do {
            try saveContext(modelContext)
        } catch {
            modelContext.delete(product)
            modelContext.processPendingChanges()
            throw CatalogProductPersistenceError.saveFailed(
                productID: rawProductID,
                underlying: error
            )
        }

        return .inserted(product)
    }

    private func restore(
        _ product: Product,
        from request: CatalogProductSaveRequest,
        at date: Date
    ) {
        product.restoreToLibrary(at: date)
        product.name = request.displayNameSnapshot
        product.imageData = request.imageData ?? product.imageData
        product.category = request.categoryDisplayNameSnapshot
        product.sourceRawValue = request.source.rawValue
        product.catalogProductIDRawValue = request.productID.rawValue
        product.catalogDisplayNameSnapshot =
            request.displayNameSnapshot
        product.catalogDisplayLocaleSnapshot =
            request.displayLocaleSnapshot
        product.catalogCategoryIDSnapshotRawValue =
            request.categoryIDSnapshot.rawValue
        product.catalogCategoryDisplayNameSnapshot =
            request.categoryDisplayNameSnapshot
        product.catalogIconKeySnapshot = request.iconKeySnapshot
        product.catalogSnapshotUpdatedAt = date
    }

    private func validate(_ request: CatalogProductSaveRequest) throws {
        try validateExactNonempty(
            request.productID.rawValue,
            field: .productID
        )
        try validateNonempty(
            request.displayNameSnapshot,
            field: .displayName
        )
        try validateExactNonempty(
            request.displayLocaleSnapshot,
            field: .displayLocale
        )
        try validateExactNonempty(
            request.categoryIDSnapshot.rawValue,
            field: .categoryID
        )
        try validateNonempty(
            request.categoryDisplayNameSnapshot,
            field: .categoryDisplayName
        )
        try validateExactNonempty(
            request.iconKeySnapshot,
            field: .iconKey
        )

        switch request.source {
        case .catalog, .barcode, .camera, .ai:
            break
        case .manual, .discover:
            throw CatalogProductPersistenceError.unsupportedSource(request.source)
        }
    }

    private func validateNonempty(
        _ value: String,
        field: CatalogProductSaveField
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogProductPersistenceError.invalidField(field)
        }
    }

    private func validateExactNonempty(
        _ value: String,
        field: CatalogProductSaveField
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw CatalogProductPersistenceError.invalidField(field)
        }
    }
}

private struct CatalogProductRestoreSnapshot {
    let deletedAt: Date?
    let updatedAt: Date
    let name: String
    let imageData: Data?
    let category: String?
    let sourceRawValue: String
    let catalogProductIDRawValue: String?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshotRawValue: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?

    init(product: Product) {
        deletedAt = product.deletedAt
        updatedAt = product.updatedAt
        name = product.name
        imageData = product.imageData
        category = product.category
        sourceRawValue = product.sourceRawValue
        catalogProductIDRawValue = product.catalogProductIDRawValue
        catalogDisplayNameSnapshot = product.catalogDisplayNameSnapshot
        catalogDisplayLocaleSnapshot = product.catalogDisplayLocaleSnapshot
        catalogCategoryIDSnapshotRawValue = product.catalogCategoryIDSnapshotRawValue
        catalogCategoryDisplayNameSnapshot = product.catalogCategoryDisplayNameSnapshot
        catalogIconKeySnapshot = product.catalogIconKeySnapshot
        catalogSnapshotUpdatedAt = product.catalogSnapshotUpdatedAt
    }

    func restore(_ product: Product) {
        product.deletedAt = deletedAt
        product.updatedAt = updatedAt
        product.name = name
        product.imageData = imageData
        product.category = category
        product.sourceRawValue = sourceRawValue
        product.catalogProductIDRawValue = catalogProductIDRawValue
        product.catalogDisplayNameSnapshot = catalogDisplayNameSnapshot
        product.catalogDisplayLocaleSnapshot = catalogDisplayLocaleSnapshot
        product.catalogCategoryIDSnapshotRawValue = catalogCategoryIDSnapshotRawValue
        product.catalogCategoryDisplayNameSnapshot = catalogCategoryDisplayNameSnapshot
        product.catalogIconKeySnapshot = catalogIconKeySnapshot
        product.catalogSnapshotUpdatedAt = catalogSnapshotUpdatedAt
    }
}
