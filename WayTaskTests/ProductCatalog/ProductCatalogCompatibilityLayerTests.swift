import Foundation
import SwiftData
import XCTest
@testable import WayTask

final class ProductCatalogCompatibilityLayerTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testPersonalizationAggregatesBySameCanonicalIDAcrossFormats()
        async throws {
        let service = ProductCatalogService(bundle: .main)
        let legacy = try service.loadProducts(data: legacyMilkData())
        let canonical = try service.loadProducts(data: canonicalMilkData())
        let history = [
            ProductCatalogSelectionHistory(
                catalogProductID: "milk_3_percent",
                productName: "שם היסטורי",
                selectionCount: 8,
                mostRecentSelectionDate:
                    referenceDate.addingTimeInterval(-86_400)
            )
        ]
        let legacySearch = ProductCatalogSearch(products: legacy)
        let canonicalSearch = ProductCatalogSearch(products: canonical)
        await legacySearch.updatePersonalization(history)
        await canonicalSearch.updatePersonalization(history)

        let legacyResult = await legacySearch.suggestions(
            matching: "חלב",
            referenceDate: referenceDate
        ).first
        let canonicalResult = await canonicalSearch.suggestions(
            matching: "חלב",
            referenceDate: referenceDate
        ).first

        XCTAssertEqual(legacyResult?.id, "milk_3_percent")
        XCTAssertEqual(canonicalResult?.id, "milk_3_percent")
        XCTAssertEqual(
            legacyResult?.personalizationBoost,
            canonicalResult?.personalizationBoost
        )
        XCTAssertGreaterThan(
            legacyResult?.personalizationBoost ?? 0,
            0
        )
    }

    @MainActor
    func testCustomProductRemainsUnlinkedAfterCatalogCompatibilityDecode()
        throws {
        _ = try ProductCatalogService(bundle: .main)
            .loadProducts(data: canonicalMilkData())
        let custom = Product(
            name: "פודינג חלבון וניל מהמאפייה",
            source: .manual
        )
        let history = ProductCatalogPersonalizationHistoryBuilder.makeHistory(
            products: [custom],
            shoppingListEntries: [],
            productHistories: []
        )

        XCTAssertEqual(custom.name, "פודינג חלבון וניל מהמאפייה")
        XCTAssertNil(custom.catalogProductIDRawValue)
        XCTAssertEqual(history.count, 1)
        XCTAssertNil(history.first?.catalogProductID)
    }

    @MainActor
    func testSchemaFormatsCannotCreateDuplicateCatalogLinkedProduct()
        async throws {
        let service = ProductCatalogService(bundle: .main)
        let legacyProduct = try XCTUnwrap(
            service.loadProducts(data: legacyMilkData()).first
        )
        let canonicalProduct = try XCTUnwrap(
            service.loadProducts(data: canonicalMilkData()).first
        )
        let legacyResult = try await searchResult(for: legacyProduct)
        let canonicalResult = try await searchResult(for: canonicalProduct)
        let container = try makeContainer()
        let context = ModelContext(container)
        let persistence = CatalogProductPersistenceService()

        let first = try persistence.save(
            CatalogProductSaveRequest(
                searchResult: legacyResult,
                imageData: nil
            ),
            in: context
        )
        let second = try persistence.save(
            CatalogProductSaveRequest(
                searchResult: canonicalResult,
                imageData: nil
            ),
            in: context
        )

        guard case .inserted(let inserted) = first else {
            return XCTFail("Expected first insert")
        }
        guard case .alreadyPresent(let existing) = second else {
            return XCTFail("Expected canonical-ID deduplication")
        }
        XCTAssertEqual(inserted.id, existing.id)
        XCTAssertEqual(
            inserted.catalogProductIDRawValue,
            "milk_3_percent"
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Product>()),
            1
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ShoppingListEntry>()),
            0
        )
    }

    private func searchResult(
        for product: CatalogProduct
    ) async throws -> ProductSearchResult {
        let suggestions = await ProductCatalogSearch(products: [product])
            .suggestions(matching: "חלב")
        let suggestion = try XCTUnwrap(suggestions.first)
        return suggestion.asProductSearchResult()
    }

    private func legacyMilkData() -> Data {
        Data(
            """
            {
              "catalogVersion": 2,
              "locale": "he-IL",
              "products": [{
                "id": "milk_3_percent",
                "name": "חלב 3%",
                "categoryId": "dairy",
                "aliases": ["חלב"],
                "keywords": ["מקרר"],
                "popularityScore": 96,
                "isActive": true
              }]
            }
            """.utf8
        )
    }

    private func canonicalMilkData() -> Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "catalogVersion": 2,
              "taxonomyVersion": 1,
              "locale": "he-IL",
              "products": [{
                "id": "milk_3_percent",
                "canonicalName": "חלב 3%",
                "categoryId": "dairy",
                "subcategoryId": null,
                "aliases": ["חלב"],
                "keywords": ["מקרר"],
                "brandTerms": [],
                "popularityScore": 96,
                "isActive": true
              }]
            }
            """.utf8
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(
            configurations: [configuration]
        )
    }
}
