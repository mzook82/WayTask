import Foundation
import XCTest
@testable import WayTask

final class ProductCatalogServiceTests: XCTestCase {
    func testBundledHebrewCatalogDecodesAndLoadsAllActiveProducts() throws {
        let products = try ProductCatalogService(bundle: .main).loadProducts()

        XCTAssertEqual(products.count, 147)
        XCTAssertEqual(Set(products.map(\.id)).count, products.count)
        XCTAssertTrue(products.allSatisfy(\.isActive))
        XCTAssertEqual(
            products.first(where: { $0.id == "bread_white" })?.name,
            "לחם לבן"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "toilet_paper" })?.aliases
                .contains("נייר שירותים"),
            true
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "salt" })?.categoryId,
            "spices"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "sugar" })?.categoryId,
            "baking"
        )
        XCTAssertEqual(
            products.first(where: { $0.id == "flour" })?.categoryId,
            "baking"
        )
    }

    func testCatalogMetadataDecodes() throws {
        let data = try bundledCatalogData()
        let document = try JSONDecoder().decode(ProductCatalogDocument.self, from: data)

        XCTAssertEqual(document.catalogVersion, 2)
        XCTAssertEqual(document.locale, "he-IL")
        XCTAssertEqual(document.products.count, 147)
    }

    func testDuplicateCatalogIDIsRejectedBeforeProductsAreExposed() throws {
        let duplicate = makeProduct(id: "duplicate")
        let data = try makeData(products: [duplicate, duplicate])

        XCTAssertThrowsError(
            try ProductCatalogService().loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.duplicateProductID("duplicate") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEmptyRequiredFieldIsRejected() throws {
        let invalid = CatalogProduct(
            id: "empty_name",
            name: "  ",
            categoryId: "pantry",
            aliases: [],
            keywords: [],
            popularityScore: 50,
            isActive: true
        )
        let data = try makeData(products: [invalid])

        XCTAssertThrowsError(
            try ProductCatalogService().loadProducts(data: data)
        ) { error in
            guard case ProductCatalogError.emptyRequiredField(
                productID: "empty_name",
                field: "name"
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testInactiveProductsAreValidatedButExcluded() throws {
        let active = makeProduct(id: "active")
        let inactive = CatalogProduct(
            id: "inactive",
            name: "מוצר ישן",
            categoryId: "pantry",
            aliases: [],
            keywords: [],
            popularityScore: 20,
            isActive: false
        )
        let data = try makeData(products: [active, inactive])

        let products = try ProductCatalogService().loadProducts(data: data)

        XCTAssertEqual(products.map(\.id), ["active"])
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

    private func makeData(products: [CatalogProduct]) throws -> Data {
        try JSONEncoder().encode(
            ProductCatalogDocument(
                catalogVersion: 1,
                locale: "he-IL",
                products: products
            )
        )
    }

    private func makeProduct(id: String) -> CatalogProduct {
        CatalogProduct(
            id: id,
            name: "מוצר",
            categoryId: "pantry",
            aliases: [],
            keywords: [],
            popularityScore: 50,
            isActive: true
        )
    }
}

private final class MissingCatalogBundleToken {}
