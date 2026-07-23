import Foundation

nonisolated struct ProductKnowledgeCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let catalogRevision: Int
    let taxonomyVersion: String
    let expectedProductCount: Int
    let supportedLocales: [String]
    let categories: [ProductKnowledgeCategoryRecord]
    let products: [ProductKnowledgeProductRecord]
    let names: [ProductKnowledgeNameRecord]

    func makeSnapshot() -> ProductKnowledgeSnapshot {
        ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeSnapshotMetadata(
                schemaVersion: schemaVersion,
                catalogRevision: catalogRevision,
                taxonomyVersion: taxonomyVersion,
                expectedProductCount: expectedProductCount,
                supportedLocales: supportedLocales
            ),
            categories: categories.map {
                ProductCategory(
                    id: ProductCategoryID($0.id),
                    names: ProductCategoryNames(
                        en: $0.names.en,
                        he: $0.names.he
                    ),
                    iconKey: $0.iconKey,
                    sortOrder: $0.sortOrder,
                    status: $0.status
                )
            },
            products: products.map {
                ProductEntity(
                    id: ProductID($0.id),
                    defaultNameID: ProductNameID($0.defaultNameID),
                    primaryCategoryID: ProductCategoryID($0.primaryCategoryID),
                    status: $0.status
                )
            },
            names: names.map {
                ProductName(
                    id: ProductNameID($0.id),
                    productID: ProductID($0.productID),
                    locale: $0.locale,
                    kind: $0.kind,
                    value: $0.value,
                    isPreferred: $0.isPreferred
                )
            }
        )
    }
}

nonisolated struct ProductKnowledgeCategoryRecord: Codable, Equatable, Sendable {
    let id: String
    let names: ProductKnowledgeCategoryNamesRecord
    let iconKey: String
    let sortOrder: Int
    let status: ProductCategoryStatus
}

nonisolated struct ProductKnowledgeCategoryNamesRecord: Codable, Equatable, Sendable {
    let en: String
    let he: String
}

nonisolated struct ProductKnowledgeProductRecord: Codable, Equatable, Sendable {
    let id: String
    let defaultNameID: String
    let primaryCategoryID: String
    let status: ProductEntityStatus
}

nonisolated struct ProductKnowledgeNameRecord: Codable, Equatable, Sendable {
    let id: String
    let productID: String
    let locale: String
    let kind: ProductNameKind
    let value: String
    let isPreferred: Bool
}
