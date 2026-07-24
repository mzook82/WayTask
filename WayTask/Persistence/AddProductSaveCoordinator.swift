import Foundation
import SwiftData

enum AddProductSaveOutcome {
    case catalogInserted(Product)
    case catalogAlreadyPresent(Product)
    case manualInserted(Product)
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

    init() {
        let catalogPersistenceService = CatalogProductPersistenceService()
        let shoppingListService = ShoppingListService()
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
        manualSave: @escaping ManualSave
    ) {
        self.catalogSave = catalogSave
        self.manualSave = manualSave
    }

    func save(
        selection: AddProductSelection,
        imageData: Data?,
        in modelContext: ModelContext
    ) throws -> AddProductSaveOutcome {
        switch selection {
        case .catalog(let catalogSelection):
            let request = CatalogProductSaveRequest(
                productID: catalogSelection.productID,
                displayNameSnapshot: catalogSelection.displayName,
                displayLocaleSnapshot: catalogSelection.displayLocale,
                categoryIDSnapshot: catalogSelection.categoryID,
                categoryDisplayNameSnapshot:
                    catalogSelection.categoryDisplayName,
                iconKeySnapshot: catalogSelection.iconKey,
                imageData: imageData,
                source: .catalog
            )

            switch try catalogSave(request, modelContext) {
            case .inserted(let product):
                return .catalogInserted(product)
            case .alreadyPresent(let product):
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
}
