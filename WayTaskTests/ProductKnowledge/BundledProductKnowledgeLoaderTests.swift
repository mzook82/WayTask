import XCTest
@testable import WayTask

final class BundledProductKnowledgeLoaderTests: XCTestCase {
    func testLoadsValidDataAtomically() throws {
        let loader = BundledProductKnowledgeLoader()

        let snapshot = try loader.load(
            data: ProductKnowledgeFixtureFactory.makeData()
        )

        XCTAssertEqual(snapshot.products.count, 15)
        XCTAssertEqual(snapshot.categories.count, 15)
        XCTAssertEqual(snapshot.metadata.schemaVersion, 1)
    }

    func testMalformedDataProducesStableDecodingError() {
        let loader = BundledProductKnowledgeLoader()

        XCTAssertThrowsError(try loader.load(data: Data("{".utf8))) { error in
            XCTAssertEqual(error as? ProductKnowledgeError, .decodingFailed)
        }
    }

    func testUnsupportedSchemaVersionIsRejectedBeforeCatalogVisibility() throws {
        let loader = BundledProductKnowledgeLoader()
        let data = try ProductKnowledgeFixtureFactory.makeData(
            from: ProductKnowledgeFixtureFactory.makeCatalog(schemaVersion: 2)
        )

        XCTAssertThrowsError(try loader.load(data: data)) { error in
            XCTAssertEqual(error as? ProductKnowledgeError, .unsupportedSchemaVersion(2))
        }
    }

    func testUnsupportedTaxonomyVersionIsRejectedBeforeCatalogVisibility() throws {
        let loader = BundledProductKnowledgeLoader()
        let data = try ProductKnowledgeFixtureFactory.makeData(
            from: ProductKnowledgeFixtureFactory.makeCatalog(taxonomyVersion: "2.0")
        )

        XCTAssertThrowsError(try loader.load(data: data)) { error in
            XCTAssertEqual(error as? ProductKnowledgeError, .unsupportedTaxonomyVersion("2.0"))
        }
    }

    func testInvalidCatalogReturnsValidationErrorAndNoPartialSnapshot() throws {
        let loader = BundledProductKnowledgeLoader()
        let data = try ProductKnowledgeFixtureFactory.makeData(
            from: ProductKnowledgeFixtureFactory.makeCatalog(expectedProductCount: 14)
        )

        XCTAssertThrowsError(try loader.load(data: data)) { error in
            XCTAssertTrue(
                ProductKnowledgeFixtureFactory.validationCodes(from: error)
                    .contains(.productCountMismatch)
            )
        }
    }

    func testMissingBundleResourceReturnsTypedError() {
        let loader = BundledProductKnowledgeLoader(
            bundle: Bundle(for: MissingResourceBundleToken.self)
        )

        XCTAssertThrowsError(try loader.load()) { error in
            XCTAssertEqual(
                error as? ProductKnowledgeError,
                .catalogMissing(resource: "product-knowledge-catalog-v1.json")
            )
        }
    }

    func testUnreadableLocatedResourceReturnsTypedError() {
        let loader = BundledProductKnowledgeLoader()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unreadable-product-knowledge.json")

        XCTAssertThrowsError(try loader.load(resourceURL: missingURL)) { error in
            XCTAssertEqual(
                error as? ProductKnowledgeError,
                .catalogUnreadable(resource: "unreadable-product-knowledge.json")
            )
        }
    }
}

private final class MissingResourceBundleToken {}
