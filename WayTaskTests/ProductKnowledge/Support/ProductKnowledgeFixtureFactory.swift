import Foundation
@testable import WayTask

enum ProductKnowledgeFixtureFactory {
    static func makeCatalog(
        schemaVersion: Int = 1,
        catalogRevision: Int = 1,
        taxonomyVersion: String = "1.0",
        expectedProductCount: Int = 15,
        supportedLocales: [String] = ["en", "he"],
        categories: [ProductKnowledgeCategoryRecord]? = nil,
        products: [ProductKnowledgeProductRecord]? = nil,
        names: [ProductKnowledgeNameRecord]? = nil
    ) -> ProductKnowledgeCatalog {
        let resolvedCategories = categories ?? makeCategories()
        let resolvedProducts = products ?? makeProducts()
        let resolvedNames = names ?? makeNames(for: resolvedProducts)

        return ProductKnowledgeCatalog(
            schemaVersion: schemaVersion,
            catalogRevision: catalogRevision,
            taxonomyVersion: taxonomyVersion,
            expectedProductCount: expectedProductCount,
            supportedLocales: supportedLocales,
            categories: resolvedCategories,
            products: resolvedProducts,
            names: resolvedNames
        )
    }

    static func makeData(from catalog: ProductKnowledgeCatalog = makeCatalog()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(catalog)
    }

    static func makeSnapshot() -> ProductKnowledgeSnapshot {
        makeCatalog().makeSnapshot()
    }

    static func validationCodes(from error: Error) -> Set<ProductKnowledgeValidationCode> {
        guard case ProductKnowledgeError.validationFailed(let violations) = error else {
            return []
        }
        return Set(violations.map(\.code))
    }

    private static func makeCategories() -> [ProductKnowledgeCategoryRecord] {
        ProductKnowledgeCatalogValidator.taxonomyRules
            .map { id, rule in
                ProductKnowledgeCategoryRecord(
                    id: id,
                    names: ProductKnowledgeCategoryNamesRecord(en: rule.en, he: rule.he),
                    iconKey: rule.iconKey,
                    sortOrder: rule.sortOrder,
                    status: .active
                )
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func makeProducts() -> [ProductKnowledgeProductRecord] {
        (1...15).map { number in
            let productID = String(format: "prd_pilot_%04d", number)
            return ProductKnowledgeProductRecord(
                id: productID,
                defaultNameID: "name_\(productID)_en",
                primaryCategoryID: "dairy",
                status: .active
            )
        }
    }

    private static func makeNames(
        for products: [ProductKnowledgeProductRecord]
    ) -> [ProductKnowledgeNameRecord] {
        products.flatMap { product in
            [
                ProductKnowledgeNameRecord(
                    id: "name_\(product.id)_en",
                    productID: product.id,
                    locale: "en",
                    kind: .canonical,
                    value: "English \(product.id)",
                    isPreferred: true
                ),
                ProductKnowledgeNameRecord(
                    id: "name_\(product.id)_he",
                    productID: product.id,
                    locale: "he",
                    kind: .localizedDisplay,
                    value: "עברית \(product.id)",
                    isPreferred: true
                )
            ]
        }
    }
}
