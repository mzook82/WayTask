import Foundation
import XCTest
@testable import WayTask

final class ProductCatalogServiceTests: XCTestCase {
    func testBundledHebrewCatalogDecodesAndLoadsAllActiveProducts() throws {
        let products = try ProductCatalogService(bundle: .main).loadProducts()

        XCTAssertEqual(products.count, 700)
        XCTAssertEqual(Set(products.map(\.id)).count, products.count)
        XCTAssertTrue(products.allSatisfy(\.isActive))
        XCTAssertEqual(
            products.first(where: { $0.id == "bread_white" })?
                .canonicalName,
            "לחם לבן"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "toilet_paper" })?.aliases
                .contains("נייר שירותים"),
            true
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "salt" })?.categoryId,
            "pantry"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "salt" })?.subcategoryId,
            "pantry.spices"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "sugar" })?.subcategoryId,
            "pantry.baking"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "flour" })?.subcategoryId,
            "pantry.baking"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "cornflakes" })?
                .canonicalName,
            "דגני בוקר"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "cola" })?.brandTerms,
            ["קוקה קולה"]
        )
    }

    func testBundledCatalogMetadataIdentifiesWT031CCanonicalFormat() throws {
        let document = try ProductCatalogService(bundle: .main)
            .loadDocument(data: bundledCatalogData())

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.catalogVersion, 6)
        XCTAssertEqual(document.taxonomyVersion, 1)
        XCTAssertEqual(document.locale, "he-IL")
        XCTAssertEqual(document.sourceFormat, .canonicalV1)
        XCTAssertEqual(document.products.count, 700)
    }

    func testCanonicalSchemaVersionOneDecodesDirectly() throws {
        let product = makeProduct(
            id: "trash_bags",
            canonicalName: "שקיות אשפה",
            categoryId: "household",
            subcategoryId: "household.waste_bags",
            aliases: ["שקיות זבל"],
            brandTerms: ["מותג בדיקה"],
            replacementProductId: nil,
            metadata: [
                "reviewed": .boolean(true),
                "source": .string("fixture")
            ]
        )
        let data = try makeCanonicalData(products: [product])

        let document = try ProductCatalogService(bundle: .main)
            .loadDocument(data: data)

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.taxonomyVersion, 1)
        XCTAssertEqual(document.sourceFormat, .canonicalV1)
        XCTAssertEqual(document.products, [product])
    }

    func testLegacyAndCanonicalFormatsProduceEquivalentCanonicalProduct() throws {
        let legacyData = try makeLegacyData(products: [
            LegacyProduct(
                id: "bread_test",
                name: "לחם בדיקה",
                categoryId: "bakery",
                aliases: ["כיכר בדיקה"],
                keywords: ["מאפייה"],
                popularityScore: 70,
                isActive: true
            )
        ])
        let canonicalProduct = makeProduct(
            id: "bread_test",
            canonicalName: "לחם בדיקה",
            categoryId: "bakery",
            aliases: ["כיכר בדיקה"],
            keywords: ["מאפייה"],
            popularity: 70
        )
        let canonicalData = try makeCanonicalData(
            products: [canonicalProduct]
        )
        let service = ProductCatalogService(bundle: .main)

        let legacy = try service.loadDocument(data: legacyData)
        let canonical = try service.loadDocument(data: canonicalData)

        XCTAssertEqual(legacy.products, canonical.products)
        XCTAssertEqual(legacy.products.first?.id, "bread_test")
        XCTAssertEqual(
            legacy.products.first?.aliases,
            canonical.products.first?.aliases
        )
    }

    func testMissingOptionalCanonicalMigrationFieldsUseSafeDefaults() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "catalogVersion": 1,
              "taxonomyVersion": 1,
              "locale": "he-IL",
              "products": [{
                "id": "simple_product",
                "canonicalName": "מוצר פשוט",
                "categoryId": "pantry",
                "subcategoryId": null,
                "aliases": [],
                "keywords": [],
                "brandTerms": [],
                "popularityScore": 50,
                "isActive": true
              }]
            }
            """.utf8
        )

        let product = try ProductCatalogService(bundle: .main)
            .loadProducts(data: data)
            .first

        XCTAssertNil(product?.replacementProductId)
        XCTAssertNil(product?.deprecatedSinceCatalogVersion)
        XCTAssertEqual(product?.legacyNames, [])
        XCTAssertNil(product?.metadata)
    }

    func testUnsupportedCanonicalSchemaVersionIsRejected() throws {
        let data = try makeCanonicalData(
            products: [makeProduct()],
            schemaVersion: 99
        )

        XCTAssertThrowsError(
            try ProductCatalogService(bundle: .main)
                .loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.unsupportedSchemaVersion(99) =
                    error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testIncompatibleTaxonomyVersionIsRejected() throws {
        let data = try makeCanonicalData(
            products: [makeProduct()],
            taxonomyVersion: 99
        )

        XCTAssertThrowsError(
            try ProductCatalogService(bundle: .main)
                .loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.incompatibleTaxonomyVersion(
                catalog: 99,
                registry: 1
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDuplicateCatalogIDIsRejectedBeforeProductsAreExposed()
        throws {
        let duplicate = makeProduct(id: "duplicate")
        let data = try makeCanonicalData(products: [duplicate, duplicate])

        XCTAssertThrowsError(
            try ProductCatalogService(bundle: .main)
                .loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.duplicateProductID("duplicate") =
                    error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEmptyRequiredFieldIsRejected() throws {
        let invalid = makeProduct(
            id: "empty_name",
            canonicalName: "  "
        )
        let data = try makeCanonicalData(products: [invalid])

        XCTAssertThrowsError(
            try ProductCatalogService(bundle: .main)
                .loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.emptyRequiredField(
                productID: "empty_name",
                field: "canonicalName"
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testInactiveProductsAreValidatedButExcluded() throws {
        let active = makeProduct(id: "active")
        let inactive = makeProduct(
            id: "inactive",
            canonicalName: "מוצר ישן",
            isActive: false
        )
        let data = try makeCanonicalData(products: [active, inactive])

        let products = try ProductCatalogService(bundle: .main)
            .loadProducts(data: data)

        XCTAssertEqual(products.map(\.id), ["active"])
    }

    func testAllBundledProductIDsArePreservedByCanonicalDecoding()
        throws {
        let data = try bundledCatalogData()
        let rawDocument = try JSONDecoder().decode(
            IDDocument.self,
            from: data
        )
        let decodedIDs = try ProductCatalogService(bundle: .main)
            .loadDocument(data: data)
            .products
            .map(\.id)

        XCTAssertEqual(decodedIDs.count, 700)
        XCTAssertEqual(decodedIDs, rawDocument.products.map(\.id))
        XCTAssertEqual(Set(decodedIDs).count, 700)
    }

    func testMalformedCatalogReturnsEmptySafeFallback() {
        let service = ProductCatalogService(
            bundle: Bundle(for: MissingCatalogBundleToken.self)
        )

        XCTAssertEqual(service.loadProductsOrEmpty(), [])
    }

    private func bundledCatalogData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: ProductCatalogService.resourceName,
                withExtension: ProductCatalogService.resourceExtension
            )
        )
        return try Data(contentsOf: url)
    }

    private func makeLegacyData(
        products: [LegacyProduct],
        catalogVersion: Int = 2
    ) throws -> Data {
        try JSONEncoder().encode(
            LegacyDocument(
                catalogVersion: catalogVersion,
                locale: "he-IL",
                products: products
            )
        )
    }

    private func makeCanonicalData(
        products: [CatalogProduct],
        schemaVersion: Int = 1,
        taxonomyVersion: Int = 1,
        catalogVersion: Int = 1
    ) throws -> Data {
        try JSONEncoder().encode(
            CanonicalDocument(
                schemaVersion: schemaVersion,
                catalogVersion: catalogVersion,
                taxonomyVersion: taxonomyVersion,
                locale: "he-IL",
                products: products
            )
        )
    }

    private func makeProduct(
        id: String = "test_product",
        canonicalName: String = "מוצר",
        categoryId: String = "pantry",
        subcategoryId: String? = nil,
        aliases: [String] = [],
        keywords: [String] = [],
        brandTerms: [String] = [],
        popularity: Int = 50,
        isActive: Bool = true,
        replacementProductId: String? = nil,
        deprecatedSinceCatalogVersion: Int? = nil,
        metadata: [String: CatalogMetadataValue]? = nil
    ) -> CatalogProduct {
        CatalogProduct(
            id: id,
            canonicalName: canonicalName,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            aliases: aliases,
            keywords: keywords,
            brandTerms: brandTerms,
            popularityScore: popularity,
            isActive: isActive,
            replacementProductId: replacementProductId,
            deprecatedSinceCatalogVersion:
                deprecatedSinceCatalogVersion,
            metadata: metadata
        )
    }
}

private struct LegacyDocument: Encodable {
    let catalogVersion: Int
    let locale: String
    let products: [LegacyProduct]
}

private struct LegacyProduct: Encodable {
    let id: String
    let name: String
    let categoryId: String
    let aliases: [String]
    let keywords: [String]
    let popularityScore: Int
    let isActive: Bool
}

private struct CanonicalDocument: Encodable {
    let schemaVersion: Int
    let catalogVersion: Int
    let taxonomyVersion: Int
    let locale: String
    let products: [CatalogProduct]
}

private struct IDDocument: Decodable {
    struct Product: Decodable {
        let id: String
    }

    let products: [Product]
}

private final class MissingCatalogBundleToken {}
