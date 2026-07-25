import Foundation
import XCTest
@testable import WayTask

final class ProductCatalogPersonalizationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testFrequencyBoostReordersProductsWithinTheSameStrongLevel() async {
        let search = makeBreadSearch()
        await search.updatePersonalization([
            history(
                catalogProductID: "bread_whole",
                name: "לחם מלא",
                count: 8,
                daysAgo: 40
            )
        ])

        let results = await search.suggestions(
            matching: "ל",
            referenceDate: referenceDate
        )

        XCTAssertEqual(results.first?.id, "bread_whole")
        XCTAssertEqual(results.first?.personalizationBoost, 23)
    }

    func testRecencyBoostReordersOtherwiseEqualStrongMatches() async {
        let search = ProductCatalogSearch(products: [
            product(id: "recent", name: "חלב טרי", popularity: 80),
            product(id: "older", name: "חלב מלא", popularity: 80)
        ])
        await search.updatePersonalization([
            history(
                catalogProductID: "recent",
                name: "חלב טרי",
                count: 1,
                daysAgo: 1
            ),
            history(
                catalogProductID: "older",
                name: "חלב מלא",
                count: 1,
                daysAgo: 120
            )
        ])

        let results = await search.suggestions(
            matching: "ח",
            referenceDate: referenceDate
        )

        XCTAssertEqual(results.first?.id, "recent")
        XCTAssertEqual(results.first?.personalizationBoost, 10)
        XCTAssertEqual(results.last?.personalizationBoost, 0)
    }

    func testPersonalizationNeverOverridesStrongerTextualRelevance() async {
        let search = ProductCatalogSearch(products: [
            product(id: "exact", name: "סוכר", popularity: 1),
            product(
                id: "keyword",
                name: "מוצר אהוב",
                keywords: ["סוכר חום"],
                popularity: 100
            )
        ])
        await search.updatePersonalization([
            history(
                catalogProductID: "keyword",
                name: "מוצר אהוב",
                count: 100,
                daysAgo: 0
            )
        ])

        let results = await search.suggestions(
            matching: "סוכר",
            referenceDate: referenceDate
        )

        XCTAssertEqual(results.first?.id, "exact")
        XCTAssertEqual(results.first?.matchLevel, .exactName)
        XCTAssertEqual(results.last?.matchLevel, .keywordPrefix)
    }

    func testUnrelatedHistoryNeverIntroducesAProductIntoResults() async {
        let search = makeBreadSearch()
        await search.updatePersonalization([
            history(
                catalogProductID: "bread_whole",
                name: "לחם מלא",
                count: 100,
                daysAgo: 0
            )
        ])

        let results = await search.suggestions(
            matching: "שמ",
            referenceDate: referenceDate
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testCatalogProductIDTakesPriorityOverHistoryName() async {
        let search = makeBreadSearch()
        await search.updatePersonalization([
            history(
                catalogProductID: "bread_whole",
                name: "שם ישן שאינו תואם",
                count: 9,
                daysAgo: 2
            )
        ])

        let results = await search.suggestions(
            matching: "לח",
            referenceDate: referenceDate
        )

        XCTAssertEqual(results.first?.id, "bread_whole")
        XCTAssertGreaterThan(results.first?.personalizationBoost ?? 0, 0)
    }

    func testNormalizedNameFallbackSupportsLegacyAndCustomHistory() async {
        let search = ProductCatalogSearch(products: [
            product(id: "full", name: "לחם מלא", popularity: 75),
            product(id: "white", name: "לחם לבן", popularity: 80)
        ])
        await search.updatePersonalization([
            history(
                catalogProductID: nil,
                name: "  לחם---מלא  ",
                count: 8,
                daysAgo: 3
            )
        ])

        let results = await search.suggestions(
            matching: "לח",
            referenceDate: referenceDate
        )

        XCTAssertEqual(results.first?.id, "full")
        XCTAssertGreaterThan(results.first?.personalizationBoost ?? 0, 0)
    }

    private func makeBreadSearch() -> ProductCatalogSearch {
        ProductCatalogSearch(products: [
            product(id: "bread_white", name: "לחם לבן", popularity: 90),
            product(id: "bread_whole", name: "לחם מלא", popularity: 80)
        ])
    }

    private func product(
        id: String,
        name: String,
        keywords: [String] = [],
        popularity: Int
    ) -> CatalogProduct {
        CatalogProduct(
            id: id,
            name: name,
            categoryId: "bakery",
            aliases: [],
            keywords: keywords,
            popularityScore: popularity,
            isActive: true
        )
    }

    private func history(
        catalogProductID: String?,
        name: String,
        count: Int,
        daysAgo: Int
    ) -> ProductCatalogSelectionHistory {
        ProductCatalogSelectionHistory(
            catalogProductID: catalogProductID,
            productName: name,
            selectionCount: count,
            mostRecentSelectionDate: referenceDate.addingTimeInterval(
                -Double(daysAgo) * 24 * 60 * 60
            )
        )
    }
}

@MainActor
final class ProductCatalogPersonalizationHistoryBuilderTests: XCTestCase {
    func testBuilderMapsCatalogLinkedHistoryToExactProductID() {
        let selectedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let product = Product(
            name: "חלב 3%",
            dateAdded: selectedAt.addingTimeInterval(-100),
            source: .catalog,
            catalogProductIDRawValue: "milk_3_percent",
            catalogDisplayNameSnapshot: "חלב 3%"
        )
        let history = ProductHistory(
            productKey: "name:חלב 3%",
            productName: "חלב 3%",
            firstAddedDate: selectedAt.addingTimeInterval(-1_000),
            lastAddedDate: selectedAt,
            addCount: 7,
            lastSource: .catalog
        )

        let records = ProductCatalogPersonalizationHistoryBuilder.makeHistory(
            products: [product],
            shoppingListEntries: [],
            productHistories: [history]
        )

        let record = records.first {
            $0.catalogProductID == "milk_3_percent"
        }
        XCTAssertEqual(record?.selectionCount, 7)
        XCTAssertEqual(record?.mostRecentSelectionDate, selectedAt)
    }

    func testBuilderKeepsLegacyCustomHistoryAsNormalizedNameFallback() {
        let selectedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let history = ProductHistory(
            productKey: "name:לחם מלא",
            productName: "  לחם---מלא ",
            firstAddedDate: selectedAt,
            lastAddedDate: selectedAt,
            addCount: 4,
            lastSource: .manual
        )

        let records = ProductCatalogPersonalizationHistoryBuilder.makeHistory(
            products: [],
            shoppingListEntries: [],
            productHistories: [history]
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.catalogProductID)
        XCTAssertEqual(
            HebrewProductSearchNormalizer
                .normalize(records.first?.productName ?? "")
                .value,
            "לחמ מלא"
        )
        XCTAssertEqual(records.first?.selectionCount, 4)
    }
}
