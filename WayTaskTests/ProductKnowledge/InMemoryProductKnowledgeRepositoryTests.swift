import XCTest
@testable import WayTask

final class InMemoryProductKnowledgeRepositoryTests: XCTestCase {
    func testExactIDReadsAndUnknownIDs() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )

        let entity = await repository.entity(id: ProductID("prd_pilot_0001"))
        let missing = await repository.entity(id: ProductID("prd_missing"))

        XCTAssertEqual(entity?.id, ProductID("prd_pilot_0001"))
        XCTAssertNil(missing)
    }

    func testNamesAndCategoriesAreReadByExactIdentity() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )

        let names = await repository.names(productID: ProductID("prd_pilot_0001"))
        let category = await repository.category(id: ProductCategoryID("dairy"))

        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(category?.iconKey, "product.dairy")
    }

    func testPreferredNameUsesExactRequestedLocaleBeforeFallbacks() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )
        let productID = ProductID("prd_pilot_0001")

        let exactHebrew = await repository.preferredName(productID: productID, locale: "he")

        XCTAssertEqual(exactHebrew?.id, ProductNameID("name_prd_pilot_0001_he"))
        XCTAssertEqual(exactHebrew?.locale, "he")
    }

    func testPreferredNameUsesLanguageThenEnglishFallbackOrder() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )
        let productID = ProductID("prd_pilot_0001")

        let hebrew = await repository.preferredName(productID: productID, locale: "he-IL")
        let english = await repository.preferredName(productID: productID, locale: "fr-FR")

        XCTAssertEqual(hebrew?.id, ProductNameID("name_prd_pilot_0001_he"))
        XCTAssertEqual(english?.locale, "en")
    }

    func testPreferredNameUsesApprovedDefaultNameAsFinalFallback() async {
        let productID = ProductID("prd_pilot_0001")
        let defaultName = ProductName(
            id: ProductNameID("default_name"),
            productID: productID,
            locale: "en",
            kind: .canonical,
            value: "Default",
            isPreferred: false
        )
        let snapshot = ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeFixtureFactory.makeSnapshot().metadata,
            categories: [],
            products: [
                ProductEntity(
                    id: productID,
                    defaultNameID: defaultName.id,
                    primaryCategoryID: ProductCategoryID("missing"),
                    status: .active
                )
            ],
            names: [defaultName]
        )
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)

        let resolved = await repository.preferredName(
            productID: productID,
            locale: "fr-FR"
        )

        XCTAssertEqual(resolved, defaultName)
    }

    func testResolvedIconUsesCategoryAndUnknownProductReturnsNil() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )

        let icon = await repository.resolvedIconKey(productID: ProductID("prd_pilot_0001"))
        let missing = await repository.resolvedIconKey(productID: ProductID("prd_missing"))

        XCTAssertEqual(icon, "product.dairy")
        XCTAssertNil(missing)
    }

    func testResolvedIconUsesGenericFallbackWhenReferencedCategoryIsUnavailable() async {
        let product = ProductEntity(
            id: ProductID("prd_pilot_0001"),
            defaultNameID: ProductNameID("name_prd_pilot_0001_en"),
            primaryCategoryID: ProductCategoryID("missing"),
            status: .active
        )
        let snapshot = ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeFixtureFactory.makeSnapshot().metadata,
            categories: [],
            products: [product],
            names: []
        )
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)

        let icon = await repository.resolvedIconKey(productID: product.id)

        XCTAssertEqual(icon, "product.generic")
    }

    func testReturnedValuesAndRepeatedReadsRemainStableCopies() async {
        let snapshot = ProductKnowledgeFixtureFactory.makeSnapshot()
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)

        let metadata = await repository.metadata()
        var firstRead = await repository.names(productID: ProductID("prd_pilot_0001"))
        let originalCount = firstRead.count
        firstRead.removeAll()
        let secondRead = await repository.names(productID: ProductID("prd_pilot_0001"))

        XCTAssertEqual(metadata, snapshot.metadata)
        XCTAssertTrue(firstRead.isEmpty)
        XCTAssertEqual(secondRead.count, originalCount)
        XCTAssertEqual(secondRead, snapshot.names.filter {
            $0.productID == ProductID("prd_pilot_0001")
        })
    }

    func testConcurrentReadsReturnStableEntityValues() async {
        let repository = InMemoryProductKnowledgeRepository(
            snapshot: ProductKnowledgeFixtureFactory.makeSnapshot()
        )
        let productID = ProductID("prd_pilot_0001")

        let entities = await withTaskGroup(
            of: ProductEntity?.self,
            returning: [ProductEntity?].self
        ) { group in
            for _ in 0..<64 {
                group.addTask {
                    await repository.entity(id: productID)
                }
            }

            var values: [ProductEntity?] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(entities.count, 64)
        XCTAssertTrue(entities.allSatisfy {
            $0?.id == productID && $0?.status == .active
        })
    }

    func testInvalidCatalogPropagatesTypedFailureBeforeRepositoryConstruction() throws {
        let data = try ProductKnowledgeFixtureFactory.makeData(
            from: ProductKnowledgeFixtureFactory.makeCatalog(expectedProductCount: 14)
        )

        XCTAssertThrowsError(try makeRepository(from: data)) { error in
            XCTAssertTrue(
                ProductKnowledgeFixtureFactory.validationCodes(from: error)
                    .contains(.productCountMismatch)
            )
        }
    }

    private func makeRepository(
        from data: Data
    ) throws -> InMemoryProductKnowledgeRepository {
        let snapshot = try BundledProductKnowledgeLoader().load(data: data)
        return InMemoryProductKnowledgeRepository(snapshot: snapshot)
    }
}
