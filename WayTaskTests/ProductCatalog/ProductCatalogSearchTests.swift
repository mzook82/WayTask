import XCTest
@testable import WayTask

final class ProductCatalogSearchTests: XCTestCase {
    func testExactNameRanksAboveHigherPopularityPrefix() async {
        let search = ProductCatalogSearch(products: [
            product(id: "exact", name: "לחם", popularity: 10),
            product(id: "prefix", name: "לחם לבן", popularity: 100)
        ])

        let results = await search.suggestions(matching: "לחם")

        XCTAssertEqual(results.map(\.id), ["exact", "prefix"])
        XCTAssertEqual(results.first?.matchLevel, .exactName)
    }

    func testProductNamePrefixRanksAboveWordAliasAndKeywordMatches() async {
        let search = ProductCatalogSearch(products: [
            product(id: "prefix", name: "אפייה ביתית", popularity: 10),
            product(id: "word", name: "מוצרי אפייה", popularity: 100),
            product(
                id: "alias",
                name: "מאפה",
                aliases: ["אפייה כפרית"],
                popularity: 100
            ),
            product(
                id: "keyword",
                name: "טוסטר",
                keywords: ["אפייה"],
                popularity: 100
            )
        ])

        let results = await search.suggestions(matching: "אפיי")

        XCTAssertEqual(
            results.map(\.matchLevel),
            [.namePrefix, .nameWordPrefix, .aliasPrefix, .keywordPrefix]
        )
    }

    func testWordPrefixMatchIsRecognized() async {
        let search = ProductCatalogSearch(products: [
            product(id: "chicken", name: "חזה עוף")
        ])

        let result = await search.suggestions(matching: "עוף")

        XCTAssertEqual(result.first?.id, "chicken")
        XCTAssertEqual(result.first?.matchLevel, .nameWordPrefix)
    }

    func testMultiwordPhraseAtWordBoundaryIsAWordPrefixMatch() async {
        let search = ProductCatalogSearch(products: [
            product(id: "oat", name: "משקה שיבולת שועל")
        ])

        let result = await search.suggestions(matching: "שיבולת שועל")

        XCTAssertEqual(result.first?.id, "oat")
        XCTAssertEqual(result.first?.matchLevel, .nameWordPrefix)
    }

    func testAliasFindsToiletPaper() async {
        let search = ProductCatalogSearch(products: [
            product(
                id: "toilet_paper",
                name: "נייר טואלט",
                aliases: ["נייר שירותים"]
            )
        ])

        let result = await search.suggestions(matching: "נייר שירותים")

        XCTAssertEqual(result.first?.id, "toilet_paper")
        XCTAssertEqual(result.first?.matchLevel, .aliasPrefix)
        XCTAssertEqual(result.first?.matchedValue, "נייר שירותים")
    }

    func testKeywordMatchDoesNotOutrankProductNameMatch() async {
        let search = ProductCatalogSearch(products: [
            product(id: "name", name: "אפייה ביתית", popularity: 10),
            product(
                id: "keyword",
                name: "קמח לבן",
                keywords: ["אפייה"],
                popularity: 100
            )
        ])

        let result = await search.suggestions(matching: "אפיי")

        XCTAssertEqual(result.map(\.id), ["name", "keyword"])
        XCTAssertEqual(result.last?.matchLevel, .keywordPrefix)
    }

    func testPopularityBreaksTiesWithinSameMatchLevel() async {
        let search = ProductCatalogSearch(products: [
            product(id: "low", name: "לחם כפרי", popularity: 20),
            product(id: "high", name: "לחם שיפון", popularity: 90)
        ])

        let result = await search.suggestions(matching: "לח")

        XCTAssertEqual(result.map(\.id), ["high", "low"])
    }

    func testDuplicateIDsAndIdenticalDisplayNamesAreRemoved() async {
        let search = ProductCatalogSearch(products: [
            product(id: "same", name: "לחם לבן", popularity: 90),
            product(id: "same", name: "לחם אחר", popularity: 80),
            product(id: "other", name: "לחם לבן", popularity: 70)
        ])

        let result = await search.suggestions(matching: "לח")

        XCTAssertEqual(result.map(\.id), ["same"])
    }

    func testEmptyAndPunctuationOnlyQueriesReturnNoResults() async {
        let search = ProductCatalogSearch(products: [
            product(
                id: "keyword",
                name: "מוצר",
                keywords: ["מילת חיפוש"]
            )
        ])

        let empty = await search.suggestions(matching: "  \n ")
        let punctuation = await search.suggestions(matching: "׳״---...")

        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(punctuation.isEmpty)
    }

    func testResultLimitIsClampedToTwelve() async {
        let products = (0..<20).map {
            product(
                id: "bread_\($0)",
                name: "לחם \($0)",
                popularity: 100 - $0
            )
        }
        let search = ProductCatalogSearch(products: products)

        let result = await search.suggestions(matching: "ל", limit: 100)

        XCTAssertEqual(result.count, 12)
    }

    func testHebrewNormalizationHandlesWhitespacePunctuationQuotesAndFinalLetters() {
        XCTAssertEqual(
            HebrewProductSearchNormalizer.normalize("  ג׳ל---כביסה  ").value,
            "גל כביסה"
        )
        XCTAssertEqual(
            HebrewProductSearchNormalizer.normalize("מֶלֶךְ").value,
            "מלכ"
        )
        XCTAssertEqual(
            HebrewProductSearchNormalizer.normalize("  A   B  ").value,
            "a b"
        )
    }

    func testBundledHebrewExamples() async throws {
        let products = try ProductCatalogService(bundle: .main).loadProducts()
        let search = ProductCatalogSearch(products: products)

        let lamed = await search.suggestions(matching: "ל")
        let breadPrefix = await search.suggestions(matching: "לח")
        let bread = await search.suggestions(matching: "לחם")
        let milk = await search.suggestions(matching: "חלב")
        let toiletPaper = await search.suggestions(matching: "נייר שירותים")
        let cornflakes = await search.suggestions(matching: "קורנפלקס")
        let toothpaste = await search.suggestions(matching: "משחת שיניים")
        let dogFood = await search.suggestions(matching: "מזון לכלבים")
        let oatMilk = await search.suggestions(matching: "חלב שיבולת שועל")

        XCTAssertEqual(lamed.first?.id, "bread_white")
        XCTAssertEqual(Array(breadPrefix.prefix(4)).map(\.product.categoryId), [
            "bakery", "bakery", "bakery", "bakery"
        ])
        XCTAssertEqual(bread.first?.id, "bread_white")
        XCTAssertEqual(milk.first?.id, "milk_3_percent")
        XCTAssertEqual(toiletPaper.first?.id, "toilet_paper")
        XCTAssertEqual(cornflakes.first?.id, "cornflakes")
        XCTAssertEqual(toothpaste.first?.id, "toothpaste")
        XCTAssertEqual(dogFood.first?.id, "dog_food")
        XCTAssertEqual(oatMilk.first?.id, "oat_drink")
    }

    func testCAT001SaltIsAnExactSpiceResult() async throws {
        let search = try bundledSearch()

        let results = await search.suggestions(matching: "מלח")

        XCTAssertEqual(results.first?.id, "salt")
        XCTAssertEqual(results.first?.matchLevel, .exactName)
        XCTAssertEqual(results.first?.product.categoryId, "pantry")
        XCTAssertEqual(
            results.first?.product.subcategoryId,
            "pantry.spices"
        )
    }

    func testCAT002SugarPrefixAndExactRankGenericSugarFirst() async throws {
        let search = try bundledSearch()

        let prefixResults = await search.suggestions(matching: "סוכ")
        let exactResults = await search.suggestions(matching: "סוכר")

        XCTAssertEqual(prefixResults.first?.id, "sugar")
        XCTAssertEqual(exactResults.first?.id, "sugar")
        XCTAssertEqual(exactResults.first?.matchLevel, .exactName)
    }

    func testCAT003FlourTwoCharacterAndExactQueriesRankGenericFlourFirst()
        async throws {
        let search = try bundledSearch()

        let prefixResults = await search.suggestions(matching: "קמ")
        let exactResults = await search.suggestions(matching: "קמח")

        XCTAssertEqual(prefixResults.first?.id, "flour")
        XCTAssertEqual(exactResults.first?.id, "flour")
        XCTAssertTrue(
            prefixResults.allSatisfy {
                $0.matchLevel <= .nameWordPrefix
            }
        )
    }

    func testCAT004TwoCharacterPastaQueryExcludesWeakMatches() async throws {
        let search = try bundledSearch()

        let results = await search.suggestions(matching: "פס")

        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThan(results.count, 10)
        XCTAssertTrue(
            results.allSatisfy {
                $0.matchLevel <= .nameWordPrefix
                    && HebrewProductSearchNormalizer
                        .normalize($0.product.canonicalName)
                        .value
                        .hasPrefix("פס")
            }
        )
    }

    func testCAT005SingleLetterLamedKeepsNamePrefixesFirst() async throws {
        let search = try bundledSearch()

        let results = await search.suggestions(matching: "ל")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(
            results.prefix(5).allSatisfy {
                $0.matchLevel == .namePrefix
            }
        )
    }

    func testCAT006SingleLetterHetKeepsNamePrefixesFirst() async throws {
        let search = try bundledSearch()

        let results = await search.suggestions(matching: "ח")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(
            results.prefix(5).allSatisfy {
                $0.matchLevel == .namePrefix
            }
        )
    }

    func testStrongNamePrefixAlwaysOutranksWeakKeywordMatch() async {
        let search = ProductCatalogSearch(products: [
            product(id: "prefix", name: "פסטרמה", popularity: 1),
            product(
                id: "keyword",
                name: "מוצר פופולרי",
                keywords: ["פסטרמה"],
                popularity: 100
            )
        ])

        let results = await search.suggestions(matching: "פסטר")

        XCTAssertEqual(results.map(\.id), ["prefix", "keyword"])
    }

    func testSearchReturnsFewerThanTenRatherThanAddingWeakTwoCharacterMatches()
        async {
        let search = ProductCatalogSearch(products: [
            product(id: "strong", name: "פסטה"),
            product(
                id: "weak_keyword",
                name: "מוצר אחר",
                keywords: ["פסטה"]
            ),
            product(
                id: "weak_alias",
                name: "מוצר נוסף",
                aliases: ["פסטה"]
            )
        ])

        let results = await search.suggestions(matching: "פס")

        XCTAssertEqual(results.map(\.id), ["strong"])
    }

    private func bundledSearch() throws -> ProductCatalogSearch {
        ProductCatalogSearch(
            products: try ProductCatalogService(bundle: .main).loadProducts()
        )
    }

    private func product(
        id: String,
        name: String,
        categoryId: String = "pantry",
        aliases: [String] = [],
        keywords: [String] = [],
        popularity: Int = 50,
        isActive: Bool = true
    ) -> CatalogProduct {
        CatalogProduct(
            id: id,
            canonicalName: name,
            categoryId: categoryId,
            aliases: aliases,
            keywords: keywords,
            popularityScore: popularity,
            isActive: isActive
        )
    }
}
