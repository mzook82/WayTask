import Foundation

nonisolated struct ProductCatalogCompatibilityDecoder: Sendable {
    static let canonicalSchemaVersion = 1

    func decode(_ data: Data) throws -> ProductCatalogDocument {
        let decoder = JSONDecoder()
        let probe = try decoder.decode(DocumentProbe.self, from: data)

        if probe.schemaVersion == nil {
            let legacy = try decoder.decode(
                LegacyProductCatalogDocument.self,
                from: data
            )
            return ProductCatalogDocument(
                schemaVersion: nil,
                catalogVersion: legacy.catalogVersion,
                taxonomyVersion: nil,
                locale: legacy.locale,
                products: legacy.products.map(\.canonicalProduct),
                sourceFormat: .legacyV2
            )
        }

        let canonical = try decoder.decode(
            CanonicalProductCatalogDocument.self,
            from: data
        )
        return ProductCatalogDocument(
            schemaVersion: canonical.schemaVersion,
            catalogVersion: canonical.catalogVersion,
            taxonomyVersion: canonical.taxonomyVersion,
            locale: canonical.locale,
            products: canonical.products,
            sourceFormat: .canonicalV1
        )
    }
}

nonisolated private extension ProductCatalogCompatibilityDecoder {
    struct DocumentProbe: Decodable {
        let schemaVersion: Int?
    }

    struct LegacyProductCatalogDocument: Decodable {
        let catalogVersion: Int
        let locale: String
        let products: [LegacyCatalogProduct]
    }

    struct LegacyCatalogProduct: Decodable {
        let id: String
        let name: String
        let categoryId: String
        let aliases: [String]
        let keywords: [String]
        let popularityScore: Int
        let isActive: Bool

        var canonicalProduct: CatalogProduct {
            CatalogProduct(
                id: id,
                canonicalName: name,
                categoryId: categoryId,
                subcategoryId: nil,
                aliases: aliases,
                keywords: keywords,
                brandTerms: [],
                popularityScore: popularityScore,
                isActive: isActive
            )
        }
    }

    struct CanonicalProductCatalogDocument: Decodable {
        let schemaVersion: Int
        let catalogVersion: Int
        let taxonomyVersion: Int
        let locale: String
        let products: [CatalogProduct]
    }
}
