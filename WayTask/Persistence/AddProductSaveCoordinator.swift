import Foundation
import SwiftData

enum AddProductSaveOutcome {
    case catalogInserted(Product)
    case catalogAlreadyPresent(Product)
    case manualInserted(Product)
}

enum AddProductSaveCoordinatorError: LocalizedError {
    case unresolvedCatalogIdentity(sourceProductID: String)
    case persistedCatalogIdentityMismatch(
        expectedProductID: String,
        persistedProductID: String?
    )

    var errorDescription: String? {
        switch self {
        case .unresolvedCatalogIdentity(let sourceProductID):
            return "The selected catalog product \(sourceProductID) is not available in the current catalog."
        case .persistedCatalogIdentityMismatch(
            let expectedProductID,
            let persistedProductID
        ):
            return "Catalog identity was not preserved while saving \(expectedProductID) (persisted: \(persistedProductID ?? "none"))."
        }
    }
}

@MainActor
struct AddProductSaveCoordinator {
    typealias CatalogSave = (
        _ request: CatalogProductSaveRequest,
        _ modelContext: ModelContext
    ) throws -> CatalogProductSaveOutcome

    typealias ManualSave = (
        _ name: String,
        _ imageData: Data?,
        _ modelContext: ModelContext
    ) throws -> Product

    private let catalogSave: CatalogSave
    private let manualSave: ManualSave
    private let catalogResolver: ShoppingItemCatalogResolver

    init() {
        let catalogPersistenceService = CatalogProductPersistenceService()
        let shoppingListService = ShoppingListService()
        catalogResolver = ShoppingItemCatalogResolver()
        catalogSave = { request, modelContext in
            try catalogPersistenceService.save(request, in: modelContext)
        }
        manualSave = { name, imageData, modelContext in
            try shoppingListService.addManualProduct(
                name: name,
                imageData: imageData,
                in: modelContext
            )
        }
    }

    init(
        catalogSave: @escaping CatalogSave,
        manualSave: @escaping ManualSave,
        catalogResolver: ShoppingItemCatalogResolver =
            ShoppingItemCatalogResolver()
    ) {
        self.catalogSave = catalogSave
        self.manualSave = manualSave
        self.catalogResolver = catalogResolver
    }

    func save(
        selection: AddProductSelection,
        imageData: Data?,
        in modelContext: ModelContext
    ) throws -> AddProductSaveOutcome {
        switch selection {
        case .catalog(let catalogSelection):
            guard let identity = catalogResolver.resolve(
                productIDRawValue: catalogSelection.productID.rawValue
            ) else {
                Self.logUnresolvedCatalogSelection(catalogSelection)
                throw AddProductSaveCoordinatorError
                    .unresolvedCatalogIdentity(
                        sourceProductID:
                            catalogSelection.productID.rawValue
                    )
            }
            let metadata = catalogResolver.currentCategoryMetadata(
                for: identity
            )
            let request = CatalogProductSaveRequest(
                productID: ProductID(identity.productID),
                displayNameSnapshot: catalogSelection.displayName,
                displayLocaleSnapshot: catalogSelection.displayLocale,
                categoryIDSnapshot: ProductCategoryID(
                    identity.categoryID
                ),
                categoryDisplayNameSnapshot: metadata.displayName,
                iconKeySnapshot: metadata.iconKey,
                imageData: imageData,
                source: .catalog
            )
            Self.logCatalogSelectionBoundary(
                sourceProductID: catalogSelection.productID.rawValue,
                identity: identity,
                iconKey: metadata.iconKey
            )

            switch try catalogSave(request, modelContext) {
            case .inserted(let product):
                try validatePersistedIdentity(
                    product,
                    expected: identity
                )
                return .catalogInserted(product)
            case .alreadyPresent(let product):
                try validatePersistedIdentity(
                    product,
                    expected: identity
                )
                return .catalogAlreadyPresent(product)
            }

        case .custom(let customSelection):
            return .manualInserted(
                try manualSave(
                    customSelection.name,
                    imageData,
                    modelContext
                )
            )
        }
    }

    /// T-10 target-only route. Existing V3 callers remain on `save` until
    /// their authorized consumer-conversion steps; this route never receives
    /// a ModelContext and cannot persist or restore outside Command Authority.
    func acquireTargetProduct(
        selection: AddProductSelection,
        imageData: Data?,
        productID: ProductStateProductID,
        commandID: ProductStateCommandID,
        effectiveAt: Date,
        reviewed: Bool,
        using authority: ProductStateProductCommandAuthority
    ) throws -> ProductStateProductCommandExecution {
        switch selection {
        case .catalog(let catalogSelection):
            guard let identity = catalogResolver.resolve(
                productIDRawValue: catalogSelection.productID.rawValue
            ) else {
                throw AddProductSaveCoordinatorError
                    .unresolvedCatalogIdentity(
                        sourceProductID:
                            catalogSelection.productID.rawValue
                    )
            }
            let metadata = catalogResolver.currentCategoryMetadata(
                for: identity
            )
            let request = CatalogProductSaveRequest(
                productID: ProductID(identity.productID),
                displayNameSnapshot: catalogSelection.displayName,
                displayLocaleSnapshot: catalogSelection.displayLocale,
                categoryIDSnapshot: ProductCategoryID(
                    identity.categoryID
                ),
                categoryDisplayNameSnapshot: metadata.displayName,
                iconKeySnapshot: metadata.iconKey,
                imageData: imageData,
                source: .catalog
            )
            return try CatalogProductPersistenceService()
                .acquireTargetProduct(
                    request,
                    productID: productID,
                    commandID: commandID,
                    effectiveAt: effectiveAt,
                    reviewed: reviewed,
                    using: authority
                )

        case .custom(let customSelection):
            return authority.acquire(
                ProductStateProductAcquisitionRequest(
                    commandID: commandID,
                    productID: productID,
                    effectiveAt: effectiveAt,
                    reviewed: reviewed,
                    name: customSelection.name,
                    imageData: imageData,
                    sourceRawValue: ProductSource.manual.rawValue
                )
            )
        }
    }

    private func validatePersistedIdentity(
        _ product: Product,
        expected identity: ResolvedShoppingItemCatalogIdentity
    ) throws {
        let persistedIdentity = catalogResolver.resolve(
            productIDRawValue: product.catalogProductIDRawValue
        )
        guard persistedIdentity?.productID == identity.productID else {
            #if DEBUG
            assertionFailure(
                "Catalog identity loss at selection-to-persistence boundary: expected \(identity.productID), persisted \(product.catalogProductIDRawValue ?? "nil")"
            )
            #endif
            throw AddProductSaveCoordinatorError
                .persistedCatalogIdentityMismatch(
                    expectedProductID: identity.productID,
                    persistedProductID:
                        product.catalogProductIDRawValue
                )
        }

        #if DEBUG
        print(
            "[WayTask Catalog Identity] persisted product=\(product.id.uuidString) catalogID=\(persistedIdentity?.productID ?? "nil")"
        )
        #endif
    }

    private static func logCatalogSelectionBoundary(
        sourceProductID: String,
        identity: ResolvedShoppingItemCatalogIdentity,
        iconKey: String
    ) {
        #if DEBUG
        print(
            "[WayTask Catalog Identity] selected sourceID=\(sourceProductID) canonicalID=\(identity.productID) categoryID=\(identity.categoryID) subcategoryID=\(identity.subcategoryID ?? "nil") iconKey=\(iconKey)"
        )
        #endif
    }

    private static func logUnresolvedCatalogSelection(
        _ selection: AddProductCatalogSelection
    ) {
        #if DEBUG
        print(
            "[WayTask Catalog Identity] rejected unresolved catalog selection sourceID=\(selection.productID.rawValue) query=\(selection.preselectionQuery)"
        )
        #endif
    }
}
