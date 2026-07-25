import Foundation
import XCTest
@testable import WayTask

final class SharedCatalogFixtureTests: XCTestCase {
    func testNormalizationFixturesExecuteAgainstIOSNormalizer() throws {
        let document: NormalizationFixtureDocument = try loadFixture(
            named: "normalization-fixtures"
        )

        XCTAssertEqual(document.fixtureVersion, 1)
        XCTAssertEqual(document.locale, "he-IL")
        XCTAssertEqual(
            document.normalizationContract,
            "hebrew_product_search_v1"
        )
        XCTAssertGreaterThanOrEqual(document.fixtures.count, 10)

        for fixture in document.fixtures {
            XCTAssertFalse(fixture.id.isEmpty)
            XCTAssertFalse(fixture.purpose.isEmpty)
            XCTAssertEqual(
                HebrewProductSearchNormalizer.normalize(fixture.input).value,
                fixture.expected,
                "Normalization fixture failed: \(fixture.id)"
            )
        }
    }

    func testAcceptanceFixtureLoadsAndResolvesCanonicalIdentities()
        async throws {
        let document: AcceptanceFixtureDocument = try loadFixture(
            named: "acceptance-fixtures"
        )
        let catalogData = try JSONEncoder().encode(document.catalog)
        let products = try ProductCatalogService(bundle: fixtureBundle)
            .loadProducts(data: catalogData)
        let search = ProductCatalogSearch(products: products)

        XCTAssertEqual(document.fixtureVersion, 1)
        XCTAssertEqual(document.locale, "he-IL")
        XCTAssertGreaterThanOrEqual(document.cases.count, 15)
        XCTAssertEqual(products.count, 8)

        for fixture in document.cases {
            let results = await search.suggestions(
                matching: fixture.query
            )

            guard let expectedProductID = fixture.expectedProductId else {
                XCTAssertTrue(
                    results.isEmpty,
                    "Expected no match for fixture \(fixture.id)"
                )
                XCTAssertTrue(fixture.customCreationAllowed)
                continue
            }

            let result = try XCTUnwrap(
                results.first,
                "Expected a result for fixture \(fixture.id)"
            )
            XCTAssertEqual(
                result.id,
                expectedProductID,
                "Wrong product for fixture \(fixture.id)"
            )
            XCTAssertEqual(
                result.product.canonicalName,
                fixture.expectedCanonicalName
            )
            XCTAssertEqual(result.product.categoryId, fixture.categoryId)
            XCTAssertEqual(
                result.product.subcategoryId,
                fixture.subcategoryId
            )

            switch fixture.matchSource {
            case "canonical_name":
                XCTAssertEqual(result.matchLevel, .exactName)
            case "alias":
                XCTAssertEqual(result.matchLevel, .aliasPrefix)
            default:
                XCTFail(
                    "Unsupported match source \(fixture.matchSource) in \(fixture.id)"
                )
            }
        }
    }

    func testSharedJSONSchemaDeclaresCanonicalRequiredFields() throws {
        let data = try fixtureData(named: "product-catalog.schema")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        let definitions = try XCTUnwrap(
            object["$defs"] as? [String: Any]
        )
        let product = try XCTUnwrap(
            definitions["product"] as? [String: Any]
        )
        let required = try XCTUnwrap(product["required"] as? [String])

        XCTAssertEqual(object["$schema"] as? String,
                       "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(Set(required), Set([
            "id",
            "canonicalName",
            "categoryId",
            "subcategoryId",
            "aliases",
            "keywords",
            "brandTerms",
            "popularityScore",
            "isActive"
        ]))
    }

    private var fixtureBundle: Bundle {
        Bundle(for: SharedCatalogFixtureBundleToken.self)
    }

    private func loadFixture<Value: Decodable>(
        named name: String
    ) throws -> Value {
        try JSONDecoder().decode(
            Value.self,
            from: fixtureData(named: name)
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(
            fixtureBundle.url(
                forResource: name,
                withExtension: "json"
            ),
            "Missing shared fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }
}

private struct NormalizationFixtureDocument: Decodable {
    struct Fixture: Decodable {
        let id: String
        let input: String
        let expected: String
        let purpose: String
    }

    let fixtureVersion: Int
    let locale: String
    let normalizationContract: String
    let fixtures: [Fixture]
}

private struct AcceptanceFixtureDocument: Decodable {
    struct Fixture: Decodable {
        let id: String
        let query: String
        let expectedProductId: String?
        let expectedCanonicalName: String?
        let matchSource: String
        let customCreationAllowed: Bool
        let categoryId: String?
        let subcategoryId: String?
    }

    let fixtureVersion: Int
    let locale: String
    let catalog: AcceptanceFixtureCatalog
    let cases: [Fixture]
}

private struct AcceptanceFixtureCatalog: Codable {
    let schemaVersion: Int
    let catalogVersion: Int
    let taxonomyVersion: Int
    let locale: String
    let products: [CatalogProduct]
}
