import Foundation
@testable import WayTask

nonisolated enum ProductKnowledgeScalabilityFixture {
    static let productCount = 5_000
    static let aliasCountPerProduct = 2

    static func makeCatalog(count: Int = productCount)
        -> ProductKnowledgeCatalog {
        let category = ProductKnowledgeCategoryRecord(
            id: "pantry",
            names: ProductKnowledgeCategoryNamesRecord(
                en: "Pantry",
                he: "מזווה"
            ),
            iconKey: "product.pantry",
            sortOrder: 0,
            status: .active
        )
        var products: [ProductKnowledgeProductRecord] = []
        var names: [ProductKnowledgeNameRecord] = []
        products.reserveCapacity(count)
        names.reserveCapacity(count * (2 + aliasCountPerProduct))

        for index in 0..<count {
            let number = String(format: "%04d", index)
            let productID = "fixture_product_\(number)"
            let canonicalNameID = "fixture_name_\(number)_en"
            products.append(
                ProductKnowledgeProductRecord(
                    id: productID,
                    defaultNameID: canonicalNameID,
                    primaryCategoryID: category.id,
                    status: .active
                )
            )
            names.append(
                ProductKnowledgeNameRecord(
                    id: canonicalNameID,
                    productID: productID,
                    locale: "en",
                    kind: .canonical,
                    value: "Scalable Product \(number)",
                    isPreferred: true
                )
            )
            names.append(
                ProductKnowledgeNameRecord(
                    id: "fixture_name_\(number)_he",
                    productID: productID,
                    locale: "he",
                    kind: .localizedDisplay,
                    value: "מוצר מדרג \(number)",
                    isPreferred: true
                )
            )
            names.append(
                ProductKnowledgeNameRecord(
                    id: "fixture_name_\(number)_alias_1",
                    productID: productID,
                    locale: "en",
                    kind: .alias,
                    value: "Fixture Alias \(number)",
                    isPreferred: false
                )
            )
            names.append(
                ProductKnowledgeNameRecord(
                    id: "fixture_name_\(number)_alias_2",
                    productID: productID,
                    locale: "en",
                    kind: .alias,
                    value: "Search Token \(number)",
                    isPreferred: false
                )
            )
        }

        return ProductKnowledgeCatalog(
            schemaVersion: 1,
            catalogRevision: 1,
            taxonomyVersion: "1.0",
            expectedProductCount: count,
            supportedLocales: ["en", "he"],
            categories: [category],
            products: products,
            names: names
        )
    }

    static func makeEncodedCatalog(count: Int = productCount) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(makeCatalog(count: count))
    }
}
