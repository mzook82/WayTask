import Foundation
import XCTest
@testable import WayTask

final class ProductKnowledgeSearchTests: XCTestCase {
    func testNormalizerAppliesApprovedUnicodeContract() {
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("  Paper \t Towels  ").value,
            "paper towels"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("DISHWASHING-LIQUID").value,
            "dishwashing liquid"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("Café").value,
            "cafe"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("Cafe\u{301}").value,
            "cafe"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("חָלָב").value,
            "חלב"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("נייר־סופג").value,
            "נייר סופג"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("Ｆｕｌｌ １２").value,
            "full 12"
        )
        XCTAssertEqual(
            ProductSearchNormalizer.normalize("***\u{05B8}").value,
            ""
        )
        XCTAssertNotEqual(
            ProductSearchNormalizer.normalize("ך").value,
            ProductSearchNormalizer.normalize("כ").value
        )
    }

    func testBundledCatalogSupportsApprovedEnglishHebrewAndAliasExamples() async throws {
        let search = try makeBundledSearch()
        let cases: [SearchExpectation] = [
            SearchExpectation("Milk", "en", "prd_pilot_0001", .exact),
            SearchExpectation("חלב", "he", "prd_pilot_0001", .exact),
            SearchExpectation("חָלָב", "he", "prd_pilot_0001", .exact),
            SearchExpectation("mil", "en", "prd_pilot_0001", .fullNamePrefix),
            SearchExpectation("ביצי", "he", "prd_pilot_0003", .fullNamePrefix),
            SearchExpectation("dishw", "en", "prd_pilot_0013", .fullNamePrefix),
            SearchExpectation("soap", "en", "prd_pilot_0013", .wordPrefix),
            SearchExpectation("towels", "en", "prd_pilot_0014", .wordPrefix),
            SearchExpectation("נייר ס", "he", "prd_pilot_0014", .fullNamePrefix),
            SearchExpectation("אוכל ל", "he", "prd_pilot_0011", .fullNamePrefix),
            SearchExpectation("ירקות ק", "he", "prd_pilot_0015", .fullNamePrefix),
            SearchExpectation("עגבניה", "he", "prd_pilot_0006", .exact),
            SearchExpectation("Tooth Paste", "en", "prd_pilot_0010", .exact),
            SearchExpectation("Washing-Up", "en", "prd_pilot_0013", .fullNamePrefix),
            SearchExpectation("Kitchen", "en", "prd_pilot_0014", .fullNamePrefix),
            SearchExpectation("liquid", "en", "prd_pilot_0013", .wordPrefix),
            SearchExpectation("Frozen Veg", "en", "prd_pilot_0015", .exact),
            SearchExpectation("coffee", "he", "prd_pilot_0008", .exact),
            SearchExpectation("קפה", "en", "prd_pilot_0008", .exact),
            SearchExpectation("to", "en", "prd_pilot_0006", .fullNamePrefix)
        ]

        for expectation in cases {
            let results = await search.suggestions(
                matching: expectation.query,
                locale: expectation.locale
            )

            XCTAssertEqual(
                results.first?.productID.rawValue,
                expectation.productID,
                "Unexpected top result for \(expectation.query)"
            )
            XCTAssertEqual(
                results.first?.matchType,
                expectation.matchType,
                "Unexpected match type for \(expectation.query)"
            )
        }
    }

    func testCrossLanguageAndAliasResultsExposeOnlyApprovedDisplayMetadata() async throws {
        let search = try makeBundledSearch()

        let hebrewUI = await search.suggestions(matching: "milk", locale: "he")
        let englishUI = await search.suggestions(matching: "חלב", locale: "en")
        let alias = await search.suggestions(matching: "dishw", locale: "en")

        XCTAssertEqual(hebrewUI.first?.displayName, "חלב")
        XCTAssertEqual(hebrewUI.first?.displayLocale, "he")
        XCTAssertEqual(hebrewUI.first?.secondaryName, "Milk")
        XCTAssertEqual(hebrewUI.first?.matchedLocale, "en")
        XCTAssertEqual(
            hebrewUI.first?.categoryDisplayName,
            "מוצרי חלב ותחליפים"
        )
        XCTAssertEqual(
            hebrewUI.first?.matchedRecordAuthority,
            .preferredDisplayName
        )

        XCTAssertEqual(englishUI.first?.displayName, "Milk")
        XCTAssertEqual(englishUI.first?.displayLocale, "en")
        XCTAssertEqual(englishUI.first?.secondaryName, "חלב")
        XCTAssertEqual(englishUI.first?.matchedLocale, "he")
        XCTAssertEqual(
            englishUI.first?.categoryDisplayName,
            "Dairy & Alternatives"
        )
        XCTAssertEqual(
            englishUI.first?.matchedRecordAuthority,
            .preferredDisplayName
        )

        XCTAssertEqual(alias.first?.displayName, "Dish Soap")
        XCTAssertEqual(alias.first?.secondaryName, "Dishwashing Liquid")
        XCTAssertEqual(alias.first?.displayLocale, "en")
        XCTAssertEqual(alias.first?.categoryID, ProductCategoryID("cleaning"))
        XCTAssertEqual(alias.first?.categoryDisplayName, "Cleaning")
        XCTAssertEqual(alias.first?.iconKey, "product.cleaning")
        XCTAssertEqual(alias.first?.matchedRecordAuthority, .alias)
    }

    func testOneCharacterQueriesUseStablePilotRanking() async throws {
        let search = try makeBundledSearch()

        let english = await search.suggestions(matching: "w", locale: "en")
        let hebrew = await search.suggestions(matching: "מ", locale: "he")

        XCTAssertEqual(
            english.map(\.productID.rawValue),
            ["prd_pilot_0007", "prd_pilot_0013", "prd_pilot_0012"]
        )
        XCTAssertEqual(
            hebrew.map(\.productID.rawValue),
            [
                "prd_pilot_0007",
                "prd_pilot_0014",
                "prd_pilot_0011",
                "prd_pilot_0010",
                "prd_pilot_0012",
                "prd_pilot_0015"
            ]
        )
        XCTAssertNil(english.first?.secondaryName)
    }

    func testNonpreferredDisplayRecordReportsDisplayAuthority() async {
        let base = SearchFixtureFactory.makeSnapshot([
            .init(id: "product", english: "Primary")
        ])
        let extraName = ProductName(
            id: ProductNameID("name_product_searchable"),
            productID: ProductID("product"),
            locale: "en",
            kind: .canonical,
            value: "Searchable",
            isPreferred: false
        )
        let snapshot = ProductKnowledgeSnapshot(
            metadata: base.metadata,
            categories: base.categories,
            products: base.products,
            names: base.names + [extraName]
        )
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(
            matching: "searchable",
            locale: "en"
        )

        XCTAssertEqual(results.first?.displayName, "Primary")
        XCTAssertEqual(results.first?.secondaryName, "Searchable")
        XCTAssertEqual(results.first?.matchedRecordAuthority, .displayName)
    }

    func testDisplayNameFallbackMatchesRepositoryContract() async throws {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)
        let search = ProductKnowledgeSearch(repository: repository)
        let locales = ["he", "he-IL", "en_US", "EN-us", "fr-FR"]

        for locale in locales {
            let results = await search.suggestions(matching: "milk", locale: locale)
            let preferredName = await repository.preferredName(
                productID: ProductID("prd_pilot_0001"),
                locale: locale
            )

            XCTAssertEqual(
                results.first?.displayName,
                preferredName?.value,
                "Display fallback drifted for \(locale)"
            )
        }
    }

    func testExactThenFullPrefixThenWordPrefixRanking() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "product_exact", english: "Paper"),
            .init(id: "product_prefix", english: "Paper Towels"),
            .init(id: "product_word", english: "Kitchen Paper")
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(matching: "paper", locale: "en")

        XCTAssertEqual(
            results.map(\.productID.rawValue),
            ["product_exact", "product_prefix", "product_word"]
        )
        XCTAssertEqual(
            results.map(\.matchType),
            [.exact, .fullNamePrefix, .wordPrefix]
        )
    }

    func testExactAliasOutranksDisplayNamePrefix() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "display_prefix", english: "Kitchen Paper Goods"),
            .init(
                id: "exact_alias",
                english: "Paper Towels",
                aliases: [("en", "Kitchen Paper")]
            )
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(
            matching: "Kitchen Paper",
            locale: "en"
        )

        XCTAssertEqual(
            results.map(\.productID.rawValue),
            ["exact_alias", "display_prefix"]
        )
        XCTAssertEqual(results.first?.matchType, .exact)
        XCTAssertEqual(results.first?.matchedRecordAuthority, .alias)
    }

    func testDisplayNameAuthorityOutranksAliasWithinSameMatchQuality() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "display", english: "Shared"),
            .init(
                id: "alias",
                english: "Other",
                aliases: [("en", "Shared")]
            )
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(matching: "shared", locale: "en")

        XCTAssertEqual(
            results.map(\.productID.rawValue),
            ["display", "alias"]
        )
        XCTAssertEqual(results.first?.matchedRecordAuthority, .primaryDisplayName)
        XCTAssertEqual(results.last?.matchedRecordAuthority, .alias)
    }

    func testLocaleAffinityBreaksEqualSemanticTies() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "english", english: "Same"),
            .init(id: "hebrew", english: nil, hebrew: "Same")
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(matching: "same", locale: "en")

        XCTAssertEqual(
            results.map(\.productID.rawValue),
            ["english", "hebrew"]
        )
    }

    func testWordPrefixRequiresContiguousOrderedTokenPrefixes() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "dish", english: "Dish Soap"),
            .init(id: "paper", english: "Paper Towels"),
            .init(id: "washing", english: "Washing Up Liquid")
        ])
        let search = makeSearch(snapshot: snapshot)

        let soap = await search.suggestions(matching: "soap", locale: "en")
        let multiword = await search.suggestions(matching: "wash up l", locale: "en")
        let substring = await search.suggestions(matching: "ish", locale: "en")
        let reordered = await search.suggestions(matching: "towels paper", locale: "en")
        let skipped = await search.suggestions(matching: "washing liquid", locale: "en")

        XCTAssertEqual(soap.first?.productID, ProductID("dish"))
        XCTAssertEqual(soap.first?.matchType, .wordPrefix)
        XCTAssertEqual(multiword.first?.productID, ProductID("washing"))
        XCTAssertTrue(substring.isEmpty)
        XCTAssertTrue(reordered.isEmpty)
        XCTAssertTrue(skipped.isEmpty)
    }

    func testMultipleMatchingRecordsProduceOneResultPerProduct() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(
                id: "dish",
                english: "Dish Soap",
                aliases: [
                    ("en", "Dishwashing Liquid"),
                    ("en", "Washing Up Liquid")
                ]
            )
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(matching: "liquid", locale: "en")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.productID, ProductID("dish"))
        XCTAssertEqual(results.first?.secondaryName, "Dishwashing Liquid")
    }

    func testInactiveProductsAreExcluded() async {
        let snapshot = SearchFixtureFactory.makeSnapshot([
            .init(id: "active", english: "Milk"),
            .init(id: "inactive", english: "Milk Powder", status: .inactive)
        ])
        let search = makeSearch(snapshot: snapshot)

        let results = await search.suggestions(matching: "milk", locale: "en")

        XCTAssertEqual(results.map(\.productID.rawValue), ["active"])
    }

    func testLimitsAreAppliedAfterRankingAndDeduplication() async {
        let definitions = (0..<25).map { index in
            SearchFixtureFactory.ProductDefinition(
                id: String(format: "product_%02d", index),
                english: "Product \(String(format: "%02d", index))"
            )
        }
        let search = makeSearch(
            snapshot: SearchFixtureFactory.makeSnapshot(definitions)
        )

        let defaultResults = await search.suggestions(matching: "p", locale: "en")
        let threeResults = await search.suggestions(
            matching: "p",
            locale: "en",
            limit: 3
        )
        let clampedResults = await search.suggestions(
            matching: "p",
            locale: "en",
            limit: 100
        )
        let zeroResults = await search.suggestions(
            matching: "p",
            locale: "en",
            limit: 0
        )
        let negativeResults = await search.suggestions(
            matching: "p",
            locale: "en",
            limit: -1
        )

        XCTAssertEqual(defaultResults.count, 8)
        XCTAssertEqual(threeResults.count, 3)
        XCTAssertEqual(clampedResults.count, 20)
        XCTAssertTrue(zeroResults.isEmpty)
        XCTAssertTrue(negativeResults.isEmpty)
    }

    func testEmptyQueriesDoNotLoadCatalogSnapshot() async {
        let repository = SnapshotCountingRepository(
            snapshot: SearchFixtureFactory.makeSnapshot([
                .init(id: "milk", english: "Milk")
            ])
        )
        let search = ProductKnowledgeSearch(repository: repository)

        let empty = await search.suggestions(matching: "", locale: "en")
        let whitespace = await search.suggestions(matching: " \n\t ", locale: "en")
        let punctuation = await search.suggestions(matching: "***", locale: "en")

        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(whitespace.isEmpty)
        XCTAssertTrue(punctuation.isEmpty)
        let snapshotCallCount = await repository.catalogSnapshotCallCount()
        XCTAssertEqual(snapshotCallCount, 0)
    }

    func testConcurrentInitialSearchesLoadOneSnapshotAndReturnSameOrder() async {
        let repository = SnapshotCountingRepository(
            snapshot: SearchFixtureFactory.makeSnapshot([
                .init(id: "milk", english: "Milk"),
                .init(id: "milk_powder", english: "Milk Powder")
            ])
        )
        let search = ProductKnowledgeSearch(repository: repository)

        let resultSets = await withTaskGroup(
            of: [ProductSearchResult].self,
            returning: [[ProductSearchResult]].self
        ) { group in
            for _ in 0..<64 {
                group.addTask {
                    await search.suggestions(matching: "mil", locale: "en")
                }
            }

            var values: [[ProductSearchResult]] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        let expectedIDs = ["milk", "milk_powder"]
        XCTAssertEqual(resultSets.count, 64)
        XCTAssertTrue(resultSets.allSatisfy {
            $0.map(\.productID.rawValue) == expectedIDs
        })
        let snapshotCallCount = await repository.catalogSnapshotCallCount()
        XCTAssertEqual(snapshotCallCount, 1)
    }

    func testSourceOrderingDoesNotAffectStableResultOrdering() async {
        let definitions: [SearchFixtureFactory.ProductDefinition] = [
            .init(id: "product_c", english: "Same"),
            .init(id: "product_a", english: "Same"),
            .init(id: "product_b", english: "Same")
        ]
        let forward = makeSearch(
            snapshot: SearchFixtureFactory.makeSnapshot(definitions)
        )
        let reversed = makeSearch(
            snapshot: SearchFixtureFactory.makeSnapshot(
                definitions.reversed(),
                reverseNames: true
            )
        )

        let forwardResults = await forward.suggestions(
            matching: "same",
            locale: "en"
        )
        let reversedResults = await reversed.suggestions(
            matching: "same",
            locale: "en"
        )

        XCTAssertEqual(
            forwardResults.map(\.productID.rawValue),
            ["product_a", "product_b", "product_c"]
        )
        XCTAssertEqual(forwardResults, reversedResults)
    }

    func testNoFuzzyTypoOrUnapprovedBrandAndSubtypeMatching() async throws {
        let search = try makeBundledSearch()

        let typo = await search.suggestions(matching: "ilk", locale: "en")
        let brand = await search.suggestions(matching: "Tnuva Milk", locale: "en")
        let subtype = await search.suggestions(
            matching: "Whole Wheat Bread",
            locale: "en"
        )

        XCTAssertTrue(typo.isEmpty)
        XCTAssertTrue(brand.isEmpty)
        XCTAssertTrue(subtype.isEmpty)
    }

    private func makeBundledSearch() throws -> ProductKnowledgeSearch {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        return makeSearch(snapshot: snapshot)
    }

    private func makeSearch(
        snapshot: ProductKnowledgeSnapshot
    ) -> ProductKnowledgeSearch {
        ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(snapshot: snapshot)
        )
    }
}

nonisolated private struct SearchExpectation {
    let query: String
    let locale: String
    let productID: String
    let matchType: ProductSearchMatchType

    init(
        _ query: String,
        _ locale: String,
        _ productID: String,
        _ matchType: ProductSearchMatchType
    ) {
        self.query = query
        self.locale = locale
        self.productID = productID
        self.matchType = matchType
    }
}

nonisolated private enum SearchFixtureFactory {
    struct ProductDefinition: Sendable {
        let id: String
        let english: String?
        let hebrew: String?
        let aliases: [(locale: String, value: String)]
        let status: ProductEntityStatus

        init(
            id: String,
            english: String?,
            hebrew: String? = nil,
            aliases: [(String, String)] = [],
            status: ProductEntityStatus = .active
        ) {
            self.id = id
            self.english = english
            self.hebrew = hebrew
            self.aliases = aliases
            self.status = status
        }
    }

    static func makeSnapshot<S: Sequence>(
        _ definitions: S,
        reverseNames: Bool = false
    ) -> ProductKnowledgeSnapshot where S.Element == ProductDefinition {
        let definitions = Array(definitions)
        let category = ProductCategory(
            id: ProductCategoryID("test"),
            names: ProductCategoryNames(en: "Test", he: "בדיקה"),
            iconKey: "product.test",
            sortOrder: 0,
            status: .active
        )
        var products: [ProductEntity] = []
        var names: [ProductName] = []

        for definition in definitions {
            let defaultLocale = definition.english == nil ? "he" : "en"
            let defaultNameID = ProductNameID(
                "name_\(definition.id)_\(defaultLocale)"
            )
            products.append(
                ProductEntity(
                    id: ProductID(definition.id),
                    defaultNameID: defaultNameID,
                    primaryCategoryID: category.id,
                    status: definition.status
                )
            )

            if let english = definition.english {
                names.append(
                    ProductName(
                        id: ProductNameID("name_\(definition.id)_en"),
                        productID: ProductID(definition.id),
                        locale: "en",
                        kind: .canonical,
                        value: english,
                        isPreferred: true
                    )
                )
            }
            if let hebrew = definition.hebrew {
                names.append(
                    ProductName(
                        id: ProductNameID("name_\(definition.id)_he"),
                        productID: ProductID(definition.id),
                        locale: "he",
                        kind: .localizedDisplay,
                        value: hebrew,
                        isPreferred: true
                    )
                )
            }
            for (index, alias) in definition.aliases.enumerated() {
                names.append(
                    ProductName(
                        id: ProductNameID("name_\(definition.id)_alias_\(index)"),
                        productID: ProductID(definition.id),
                        locale: alias.locale,
                        kind: .alias,
                        value: alias.value,
                        isPreferred: false
                    )
                )
            }
        }

        return ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeSnapshotMetadata(
                schemaVersion: 1,
                catalogRevision: 1,
                taxonomyVersion: "1.0",
                expectedProductCount: products.count,
                supportedLocales: ["en", "he"]
            ),
            categories: [category],
            products: products,
            names: reverseNames ? Array(names.reversed()) : names
        )
    }
}

private actor SnapshotCountingRepository: ProductKnowledgeRepository {
    private let snapshot: ProductKnowledgeSnapshot
    private let backing: InMemoryProductKnowledgeRepository
    private var snapshotCalls = 0

    init(snapshot: ProductKnowledgeSnapshot) {
        self.snapshot = snapshot
        backing = InMemoryProductKnowledgeRepository(snapshot: snapshot)
    }

    func catalogSnapshot() async -> ProductKnowledgeSnapshot {
        snapshotCalls += 1
        await Task.yield()
        return snapshot
    }

    func catalogSnapshotCallCount() -> Int {
        snapshotCalls
    }

    func metadata() async -> ProductKnowledgeSnapshotMetadata {
        await backing.metadata()
    }

    func entity(id: ProductID) async -> ProductEntity? {
        await backing.entity(id: id)
    }

    func names(productID: ProductID) async -> [ProductName] {
        await backing.names(productID: productID)
    }

    func category(id: ProductCategoryID) async -> ProductCategory? {
        await backing.category(id: id)
    }

    func preferredName(
        productID: ProductID,
        locale: String
    ) async -> ProductName? {
        await backing.preferredName(productID: productID, locale: locale)
    }

    func resolvedIconKey(productID: ProductID) async -> String? {
        await backing.resolvedIconKey(productID: productID)
    }
}
