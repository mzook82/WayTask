import Foundation
import SwiftData
import XCTest
@testable import WayTask

final class ProductCatalogMigrationTests: XCTestCase {
    private let service = ProductCatalogService(
        bundle: Bundle(for: ProductCatalogMigrationBundleToken.self)
    )
    private let referenceDate = Date(
        timeIntervalSince1970: 2_000_000_000
    )

    func testBundledCatalogIsCanonicalV3AndPassesFullValidator() throws {
        let data = try canonicalCatalogData()
        let document = try service.loadDocument(data: data)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        let records = try XCTUnwrap(
            object["products"] as? [[String: Any]]
        )

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.catalogVersion, 3)
        XCTAssertEqual(document.taxonomyVersion, 1)
        XCTAssertEqual(document.locale, "he-IL")
        XCTAssertEqual(document.sourceFormat, .canonicalV1)
        XCTAssertEqual(document.products.count, 147)
        XCTAssertTrue(document.products.allSatisfy(\.isActive))

        for record in records {
            XCTAssertNotNil(record["canonicalName"])
            XCTAssertNil(record["name"])
            XCTAssertTrue(record.keys.contains("subcategoryId"))
            XCTAssertNotNil(record["aliases"])
            XCTAssertNotNil(record["keywords"])
            XCTAssertNotNil(record["brandTerms"])
            XCTAssertNotNil(record["popularityScore"])
            XCTAssertNotNil(record["isActive"])
        }
    }

    func testTaxonomyReviewManifestCompletesEveryProductAndAmbiguousGroup()
        throws {
        let manifest: TaxonomyReviewManifest = try decodeFixture(
            named: "product-taxonomy-review"
        )
        let legacy = try legacyDocument()
        let canonical = try canonicalDocument()
        let taxonomy = try ProductCatalogTaxonomyLoader(
            bundle: fixtureBundle
        ).load()
        let allowedStatuses: Set<String> = [
            "confirmed",
            "reclassified",
            "canonical_name_updated",
            "alias_updated",
            "brand_term_updated"
        ]
        let reviewRequiredCategories = Set(
            taxonomy.compatibilityMappings
                .filter { $0.migrationMode == .productReviewRequired }
                .map(\.legacyCategoryId)
        )
        let legacyByID = Dictionary(
            uniqueKeysWithValues: legacy.products.map { ($0.id, $0) }
        )
        let canonicalByID = Dictionary(
            uniqueKeysWithValues: canonical.products.map { ($0.id, $0) }
        )

        XCTAssertEqual(manifest.reviewVersion, 1)
        XCTAssertEqual(manifest.catalogVersion, 3)
        XCTAssertEqual(manifest.taxonomyVersion, taxonomy.taxonomyVersion)
        XCTAssertEqual(manifest.productCount, 147)
        XCTAssertEqual(manifest.products.count, 147)
        XCTAssertEqual(Set(manifest.products.map(\.productId)).count, 147)
        XCTAssertEqual(reviewRequiredCategories.count, 8)

        var reviewedAmbiguousProducts = 0
        for review in manifest.products {
            let legacyProduct = try XCTUnwrap(
                legacyByID[review.productId],
                "Manifest references unknown legacy ID \(review.productId)"
            )
            let canonicalProduct = try XCTUnwrap(
                canonicalByID[review.productId],
                "Manifest references unknown canonical ID \(review.productId)"
            )

            XCTAssertTrue(allowedStatuses.contains(review.reviewStatus))
            XCTAssertEqual(
                review.previousLegacyCategoryId,
                legacyProduct.categoryId
            )
            XCTAssertEqual(
                review.canonicalCategoryId,
                canonicalProduct.categoryId
            )
            XCTAssertEqual(
                review.canonicalSubcategoryId,
                canonicalProduct.subcategoryId
            )

            if reviewRequiredCategories.contains(
                review.previousLegacyCategoryId
            ) {
                reviewedAmbiguousProducts += 1
                XCTAssertTrue(
                    review.note?.contains("Individually reviewed") == true,
                    "Ambiguous assignment lacks review evidence: \(review.productId)"
                )
            }
        }

        XCTAssertEqual(reviewedAmbiguousProducts, 48)
        XCTAssertEqual(
            Set(manifest.products.map(\.productId)),
            Set(canonical.products.map(\.id))
        )
    }

    func testLegacyAndCanonicalCatalogsPreserveIDsAndCoreSemantics()
        throws {
        let legacy = try legacyDocument()
        let canonical = try canonicalDocument()
        let legacyByID = Dictionary(
            uniqueKeysWithValues: legacy.products.map { ($0.id, $0) }
        )

        XCTAssertEqual(legacy.products.map(\.id), canonical.products.map(\.id))
        XCTAssertEqual(Set(canonical.products.map(\.id)).count, 147)

        for product in canonical.products {
            let previous = try XCTUnwrap(legacyByID[product.id])
            XCTAssertEqual(product.keywords, previous.keywords)
            XCTAssertEqual(
                product.popularityScore,
                previous.popularityScore
            )
            XCTAssertEqual(product.isActive, previous.isActive)
        }

        let cereal = try XCTUnwrap(
            canonical.products.first { $0.id == "cornflakes" }
        )
        XCTAssertEqual(cereal.canonicalName, "דגני בוקר")
        XCTAssertTrue(cereal.aliases.contains("קורנפלקס"))
        XCTAssertTrue(cereal.legacyNames.contains("קורנפלקס"))
    }

    func testRepresentativeSearchRemainsSemanticallyEquivalent()
        async throws {
        let legacySearch = ProductCatalogSearch(
            products: try legacyDocument().products
        )
        let canonicalSearch = ProductCatalogSearch(
            products: try canonicalDocument().products
        )
        let expectations: [(query: String, expectedID: String?)] = [
            ("ל", "bread_white"),
            ("לח", "bread_white"),
            ("לחם", "bread_white"),
            ("ח", "milk_3_percent"),
            ("חלב", "milk_3_percent"),
            ("מלח", "salt"),
            ("סוכר", "sugar"),
            ("קמח", "flour"),
            ("נייר שירותים", "toilet_paper"),
            ("שקיות זבל", "trash_bags"),
            ("קורנפלקס", "cornflakes"),
            ("חלב שיבולת שועל", "oat_drink"),
            ("נס קפה", "instant_coffee"),
            ("מזון לכלבים", "dog_food"),
            ("פודינג חלבון וניל מהמאפייה", nil)
        ]

        for expectation in expectations {
            let legacy = await legacySearch.suggestions(
                matching: expectation.query
            )
            let canonical = await canonicalSearch.suggestions(
                matching: expectation.query
            )

            XCTAssertEqual(
                legacy.first?.id,
                expectation.expectedID,
                "Unexpected legacy result for \(expectation.query)"
            )
            XCTAssertEqual(
                canonical.first?.id,
                expectation.expectedID,
                "Unexpected canonical result for \(expectation.query)"
            )
            XCTAssertEqual(
                canonical.map(\.id),
                legacy.map(\.id),
                "Ranking changed for \(expectation.query)"
            )
        }
    }

    func testAliasesBrandTermsAndLegacyNamesResolveCanonicalIDs()
        async throws {
        let search = ProductCatalogSearch(
            products: try canonicalDocument().products
        )
        let expectations = [
            ("שקיות זבל", "trash_bags"),
            ("קורנפלקס", "cornflakes"),
            ("קוקה קולה", "cola"),
            ("אקמול", "paracetamol"),
            ("גרבר", "baby_puree")
        ]

        for (query, productID) in expectations {
            let result = await search.suggestions(matching: query).first
            XCTAssertEqual(result?.id, productID)
            XCTAssertEqual(result?.matchLevel, .aliasPrefix)
        }
    }

    func testCanonicalNameMigrationPreservesIDAndLegacyNamePersonalization()
        async throws {
        let products = try canonicalDocument().products
        let search = ProductCatalogSearch(products: products)

        await search.updatePersonalization([
            ProductCatalogSelectionHistory(
                catalogProductID: "cornflakes",
                productName: "קורנפלקס",
                selectionCount: 8,
                mostRecentSelectionDate:
                    referenceDate.addingTimeInterval(-86_400)
            )
        ])
        let exactIDResult = await search.suggestions(
            matching: "קורנפלקס",
            referenceDate: referenceDate
        ).first

        XCTAssertEqual(exactIDResult?.id, "cornflakes")
        XCTAssertGreaterThan(exactIDResult?.personalizationBoost ?? 0, 0)

        await search.updatePersonalization([
            ProductCatalogSelectionHistory(
                catalogProductID: nil,
                productName: "  קורנפלקס  ",
                selectionCount: 8,
                mostRecentSelectionDate:
                    referenceDate.addingTimeInterval(-86_400)
            )
        ])
        let legacyNameResult = await search.suggestions(
            matching: "קורנפלקס",
            referenceDate: referenceDate
        ).first

        XCTAssertEqual(legacyNameResult?.id, "cornflakes")
        XCTAssertGreaterThan(legacyNameResult?.personalizationBoost ?? 0, 0)
    }

    @MainActor
    func testAllLegacyIDsRemainPersistenceIdentitiesAfterMigration()
        throws {
        let legacy = try legacyDocument()
        let canonical = try canonicalDocument()
        let container = try makeContainer()
        let context = ModelContext(container)
        let persistence = CatalogProductPersistenceService()
        var insertedByID: [String: Product] = [:]

        for product in legacy.products {
            let outcome = try persistence.save(
                saveRequest(for: product),
                in: context
            )
            guard case .inserted(let inserted) = outcome else {
                return XCTFail("Expected initial insert for \(product.id)")
            }
            insertedByID[product.id] = inserted
        }

        let cereal = try XCTUnwrap(insertedByID["cornflakes"])
        let shoppingEntry = ShoppingListEntry(
            shoppingListID: UUID(),
            product: cereal
        )
        context.insert(shoppingEntry)
        try context.save()
        let linkedProductID = shoppingEntry.productID

        for product in canonical.products {
            let outcome = try persistence.save(
                saveRequest(for: product),
                in: context
            )
            guard case .alreadyPresent(let existing) = outcome else {
                return XCTFail("Expected ID match for \(product.id)")
            }
            XCTAssertEqual(
                existing.catalogProductIDRawValue,
                product.id
            )
        }

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Product>()),
            147
        )
        XCTAssertEqual(shoppingEntry.productID, linkedProductID)
        XCTAssertEqual(
            shoppingEntry.product?.catalogProductIDRawValue,
            "cornflakes"
        )
    }

    @MainActor
    func testCustomProductsRemainCustomAfterCanonicalMigration() throws {
        _ = try canonicalDocument()
        let custom = Product(
            name: "פודינג חלבון וניל מהמאפייה",
            source: .manual
        )

        XCTAssertNil(custom.catalogProductIDRawValue)
        XCTAssertEqual(custom.source, .manual)
        XCTAssertEqual(custom.name, "פודינג חלבון וניל מהמאפייה")
    }

    private var fixtureBundle: Bundle {
        Bundle(for: ProductCatalogMigrationBundleToken.self)
    }

    private func legacyDocument() throws -> ProductCatalogDocument {
        try service.loadDocument(data: legacyCatalogData())
    }

    private func canonicalDocument() throws -> ProductCatalogDocument {
        try service.loadDocument(data: canonicalCatalogData())
    }

    private func canonicalCatalogData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: ProductCatalogService.resourceName,
                withExtension: ProductCatalogService.resourceExtension
            )
        )
        return try Data(contentsOf: url)
    }

    private func legacyCatalogData() throws -> Data {
        try fixtureData(named: "product_catalog_he_legacy_v2")
    }

    private func decodeFixture<Value: Decodable>(
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
            "Missing migration fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func saveRequest(
        for product: CatalogProduct
    ) -> CatalogProductSaveRequest {
        let category = ProductCatalogCategoryMetadata.metadata(
            for: product.categoryId,
            subcategoryId: product.subcategoryId
        )
        return CatalogProductSaveRequest(
            productID: ProductID(product.id),
            displayNameSnapshot: product.canonicalName,
            displayLocaleSnapshot: "he",
            categoryIDSnapshot: ProductCategoryID(product.categoryId),
            categoryDisplayNameSnapshot: category.displayName,
            iconKeySnapshot: category.iconKey,
            imageData: nil,
            source: .catalog
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: WayTaskModelContainer.currentSchema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }
}

private struct TaxonomyReviewManifest: Decodable {
    struct Review: Decodable {
        let productId: String
        let previousLegacyCategoryId: String
        let canonicalCategoryId: String
        let canonicalSubcategoryId: String?
        let reviewStatus: String
        let note: String?
    }

    let reviewVersion: Int
    let catalogVersion: Int
    let taxonomyVersion: Int
    let locale: String
    let productCount: Int
    let products: [Review]
}

private final class ProductCatalogMigrationBundleToken {}
