import Foundation
import XCTest
@testable import WayTask

final class SmartProductKnowledgeFoundationTests: XCTestCase {
    func testProductionCatalogAdapterPreservesAllStableIdentities() throws {
        let snapshot = try productionSnapshot()
        let legacyProducts = try ProductCatalogService(bundle: .main)
            .loadProducts()

        XCTAssertEqual(legacyProducts.count, 700)
        XCTAssertEqual(snapshot.products.count, 700)
        XCTAssertEqual(
            Set(snapshot.products.map { $0.id.rawValue }),
            Set(legacyProducts.map(\.id))
        )
        XCTAssertEqual(snapshot.metadata.catalogVersion, 6)
        XCTAssertEqual(snapshot.metadata.catalogGenerationDate, "2026-08-06")
        XCTAssertEqual(snapshot.metadata.source, "canonical-catalog-v1+localizations-v1")
    }

    func testProductionFoundationValidationReportsNoUnsafeCondition() throws {
        let report = ProductKnowledgeFoundationValidator().validate(
            try productionSnapshot()
        )

        XCTAssertTrue(report.errors.isEmpty, "\(report.errors)")
        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.warnings.allSatisfy {
            $0.code == .duplicateLocaleNameDefinition
                || $0.code == .possibleNormalizedNameCollision
        })
    }

    func testProductionCatalogLoadValidationAndIndexMetrics() async throws {
        let clock = ContinuousClock()
        let loadStarted = clock.now
        let snapshot = try productionSnapshot()
        let report = ProductKnowledgeFoundationValidator().validate(snapshot)
        let loadAndValidationDuration = loadStarted.duration(to: clock.now)

        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(snapshot: snapshot)
        )
        let indexStarted = clock.now
        await search.prepare()
        let indexDuration = indexStarted.duration(to: clock.now)
        let statistics = await search.indexStatistics()

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(statistics.productCount, 700)
        XCTAssertLessThan(loadAndValidationDuration, .seconds(2))
        XCTAssertLessThan(indexDuration, .seconds(2))

        let metrics = "WT031A_PRODUCTION_METRICS " + [
            "loadValidateMs=\(milliseconds(loadAndValidationDuration))",
            "indexMs=\(milliseconds(indexDuration))",
            "products=\(statistics.productCount)",
            "searchableNames=\(statistics.searchableNameCount)",
            "indexedUTF8LowerBound=\(statistics.estimatedIndexedUTF8Bytes)",
            "errors=\(report.errors.count)",
            "warnings=\(report.warnings.count)"
        ].joined(separator: " ")
        print(metrics)
        XCTContext.runActivity(named: metrics) { _ in }
    }

    func testCuratedEnglishAndHebrewNamesResolveToSameStableIdentity()
        async throws {
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(
                snapshot: try productionSnapshot()
            )
        )
        let cases = [
            ("Bread", "לחם", "bread_white"),
            ("Milk", "חלב", "milk_3_percent"),
            ("Eggs", "ביצים", "eggs"),
            ("Rice", "אורז", "rice_white"),
            ("Water", "מים", "mineral_water"),
            ("Apples", "תפוחים", "apple")
        ]

        for (english, hebrew, expectedID) in cases {
            let englishResult = await search.suggestions(
                matching: english,
                locale: "en"
            )
            let hebrewResult = await search.suggestions(
                matching: hebrew,
                locale: "he-IL"
            )
            XCTAssertEqual(englishResult.first?.productID.rawValue, expectedID)
            XCTAssertEqual(hebrewResult.first?.productID.rawValue, expectedID)
        }
    }

    func testMapCompatibilityProductsRetainExactCatalogTaxonomy()
        async throws {
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(
                snapshot: try productionSnapshot()
            )
        )
        let cases: [(String, String, String)] = [
            ("קוטג׳", "cottage_cheese", "dairy"),
            ("חלב", "milk_3_percent", "dairy"),
            ("שקיות אשפה", "trash_bags", "household"),
            ("קפה", "coffee", "drinks"),
            ("לחם", "bread_white", "bakery"),
            ("Coffee", "coffee", "drinks"),
            ("Milk", "milk_3_percent", "dairy"),
            ("Hazelnut Spread", "hazelnut_spread", "pantry")
        ]

        for (query, productID, categoryID) in cases {
            let results = await search.suggestions(
                matching: query,
                locale: query == "Coffee" || query == "Milk" ||
                    query == "Hazelnut Spread" ? "en" : "he-IL"
            )
            let result = try XCTUnwrap(
                results.first,
                "Expected a Product Knowledge match for \(query)"
            )
            XCTAssertEqual(result.productID.rawValue, productID, query)
            XCTAssertEqual(result.categoryID.rawValue, categoryID, query)
        }
    }

    func testWT031CCuratedWaveSearchesAcrossEveryAddedCategory()
        async throws {
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(
                snapshot: try productionSnapshot()
            )
        )
        let exactCases: [(String, String, String)] = [
            ("פרוסות גבינה", "sliced_cheese", "dairy"),
            ("לחמניות המבורגר", "hamburger_buns", "bakery"),
            ("ענבים ירוקים", "green_grapes", "fruits_vegetables"),
            ("אנטרקוט", "entrecote", "meat_fish"),
            ("קמח כוסמת", "buckwheat_flour", "pantry"),
            ("שוקולד חלב", "milk_chocolate", "snacks"),
            ("קפה", "coffee", "drinks"),
            ("אבקת כביסה", "laundry_powder", "cleaning"),
            ("דאודורנט ספריי", "deodorant_spray", "personal_care"),
            ("מחית פירות לתינוק", "fruit_baby_puree", "baby"),
            ("מיטה לכלב", "dog_bed", "pets"),
            ("טבליות לצרבת", "antacid_tablets", "pharmacy"),
            ("שקיות סנדוויץ׳", "sandwich_bags", "household")
        ]

        for (query, expectedID, expectedCategory) in exactCases {
            let results = await search.suggestions(
                matching: query,
                locale: "he-IL"
            )
            let result = try XCTUnwrap(
                results.first,
                "Missing WT-031C result for \(query)"
            )
            XCTAssertEqual(result.productID, ProductID(expectedID))
            XCTAssertEqual(
                result.categoryID,
                ProductCategoryID(expectedCategory)
            )
            XCTAssertEqual(result.matchTier, .exactCanonical)
        }

        let hebrewPrefix = await search.suggestions(
            matching: "לחמניות המ",
            locale: "he-IL"
        )
        XCTAssertEqual(
            hebrewPrefix.first?.productID,
            ProductID("hamburger_buns")
        )

        let buckwheatAlias = await search.suggestions(
            matching: "קמח מכוסמת",
            locale: "he-IL"
        )
        XCTAssertEqual(
            buckwheatAlias.first?.productID,
            ProductID("buckwheat_flour")
        )
        XCTAssertEqual(buckwheatAlias.first?.matchTier, .exactAlias)

        let englishCoffee = await search.suggestions(
            matching: "Coffee",
            locale: "en"
        )
        let englishHazelnut = await search.suggestions(
            matching: "Hazelnut Spread",
            locale: "en"
        )
        XCTAssertEqual(englishCoffee.first?.productID, ProductID("coffee"))
        XCTAssertEqual(englishCoffee.first?.displayName, "Coffee")
        XCTAssertEqual(
            englishHazelnut.first?.productID,
            ProductID("hazelnut_spread")
        )

        let categoryEvidence = await search.suggestions(
            matching: "מכונת כביסה",
            locale: "he-IL"
        )
        let categoryIDs = Set(categoryEvidence.map(\.productID))
        XCTAssertTrue(categoryIDs.contains(ProductID("laundry_powder")))
        XCTAssertTrue(categoryIDs.contains(ProductID("laundry_liquid")))

        let aliasDeduplication = await search.suggestions(
            matching: "שקיות כריכים",
            locale: "he-IL"
        )
        XCTAssertEqual(
            aliasDeduplication.filter {
                $0.productID == ProductID("sandwich_bags")
            }.count,
            1
        )

        let noResult = await search.suggestions(
            matching: "מתאם קוונטי מותאם אישית",
            locale: "he-IL"
        )
        XCTAssertTrue(noResult.isEmpty)
        let existingMilk = await search.suggestions(
            matching: "חלב",
            locale: "he-IL"
        )
        XCTAssertEqual(
            existingMilk.first?.productID,
            ProductID("milk_3_percent")
        )
    }

    func testProductionShortQueriesEnforceDirectEvidenceAndStableExamples()
        async throws {
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(
                snapshot: try productionSnapshot()
            )
        )

        let latinOne = await search.suggestions(matching: "C", locale: "en")
        let colaPrefix = await search.suggestions(matching: "קו", locale: "he-IL")
        let ambiguous = await search.suggestions(matching: "חל", locale: "he-IL")
        let completedMilk = await search.suggestions(
            matching: "חלב",
            locale: "he-IL"
        )
        let latinMilk = await search.suggestions(matching: "Mi", locale: "en")

        XCTAssertEqual(latinOne.map(\.productID), [ProductID("coffee")])
        XCTAssertTrue(latinOne.allSatisfy {
            $0.displayLocale == "en"
                && $0.matchTier == .canonicalPrefix
                && $0.candidateConfidence == .strong
        })

        let colaIndex = try XCTUnwrap(
            colaPrefix.firstIndex { $0.productID == ProductID("cola") }
        )
        XCTAssertTrue(colaPrefix[...colaIndex].allSatisfy {
            $0.matchTier == .exactCanonical
                || $0.matchTier == .canonicalPrefix
        })

        XCTAssertTrue(ambiguous.contains {
            $0.productID == ProductID("challah")
        })
        XCTAssertTrue(ambiguous.contains {
            $0.productID == ProductID("milk_3_percent")
        })

        XCTAssertEqual(
            completedMilk.first?.productID,
            ProductID("milk_3_percent")
        )
        XCTAssertFalse(completedMilk.contains {
            $0.productID == ProductID("challah")
        })

        XCTAssertEqual(
            latinMilk.first?.productID,
            ProductID("milk_3_percent")
        )
        XCTAssertEqual(latinMilk.first?.displayName, "Milk 3%")
        XCTAssertEqual(
            latinMilk.dropFirst().first?.productID,
            ProductID("mineral_water")
        )
    }

    func testAliasKeepsLocalizedCanonicalDisplayAndExposesMatchMetadata()
        async throws {
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(
                snapshot: try productionSnapshot()
            )
        )

        let results = await search.suggestions(
            matching: "Bread",
            locale: "en"
        )
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.productID, ProductID("bread_white"))
        XCTAssertEqual(result.displayName, "White Bread")
        XCTAssertEqual(result.displayLocale, "en")
        XCTAssertEqual(result.secondaryName, "Bread")
        XCTAssertEqual(result.matchTier, .exactAlias)
        XCTAssertEqual(result.matchedRecordAuthority, .alias)
        XCTAssertEqual(result.matchedValue, "Bread")
        XCTAssertEqual(result.normalizedMatchedValue, "bread")
    }

    func testCategoryAndIconUseSameStableMeaning() async throws {
        let snapshot = try productionSnapshot()
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)
        let search = ProductKnowledgeSearch(repository: repository)
        let results = await search.suggestions(
            matching: "Bread",
            locale: "en"
        )
        let result = try XCTUnwrap(results.first)
        let icon = await repository.resolvedIconKey(productID: result.productID)

        XCTAssertEqual(result.categoryID, ProductCategoryID("bakery"))
        XCTAssertEqual(result.iconKey, "product.bread")
        XCTAssertEqual(icon, result.iconKey)
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: result.iconKey),
            "basket.fill"
        )
    }

    func testLocalizationDocumentRejectsVersionMismatchAndMalformedData() throws {
        let loader = BundledProductKnowledgeLocalizationLoader(bundle: .main)
        let valid = try loader.load(expectedCatalogVersion: 6)
        XCTAssertEqual(valid.names.count, 13)

        XCTAssertThrowsError(
            try loader.load(
                data: try JSONEncoder().encode(valid),
                expectedCatalogVersion: 7
            )
        ) { error in
            XCTAssertEqual(
                error as? ProductKnowledgeLocalizationError,
                .catalogVersionMismatch(expected: 7, actual: 6)
            )
        }
        XCTAssertThrowsError(
            try loader.load(
                data: Data("{ malformed".utf8),
                expectedCatalogVersion: 6
            )
        )
    }

    func testProductionReleaseManifestIsVersionedAndAtomicallyMatched() throws {
        let loader = BundledProductCatalogReleaseManifestLoader(bundle: .main)
        let manifest = try loader.load(
            expectedCatalogVersion: 6,
            expectedProductCount: 700
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.catalogVersion, 6)
        XCTAssertEqual(manifest.generationDate, "2026-08-06")
        XCTAssertEqual(manifest.productCount, 700)

        let data = try JSONEncoder().encode(manifest)
        XCTAssertThrowsError(
            try loader.load(
                data: data,
                expectedCatalogVersion: 7,
                expectedProductCount: 700
            )
        ) { error in
            XCTAssertEqual(
                error as? ProductCatalogReleaseManifestError,
                .catalogVersionMismatch(expected: 7, actual: 6)
            )
        }
        XCTAssertThrowsError(
            try loader.load(
                data: data,
                expectedCatalogVersion: 6,
                expectedProductCount: 701
            )
        ) { error in
            XCTAssertEqual(
                error as? ProductCatalogReleaseManifestError,
                .productCountMismatch(expected: 701, actual: 700)
            )
        }
    }

    func testProductionFactoryAcceptsOnlyTheMatchedBundledRelease() {
        switch ProductionProductKnowledgeFactory.makeSearchAvailability(
            bundle: .main
        ) {
        case .available:
            break
        case .catalog, .unavailable:
            XCTFail("Matched catalog, localization, taxonomy, and manifest must load")
        }
    }

    func testValidatorReportsEveryUnsafeFoundationCondition() {
        let first = product(
            id: "first",
            category: "missing",
            semanticKey: "shared",
            barcodes: ["0123-456"]
        )
        let second = product(
            id: "second",
            category: "missing",
            semanticKey: "shared",
            barcodes: ["0123456"]
        )
        let names = [
            name("first_en", product: "first", locale: "en", kind: .canonical, value: "Shared"),
            name("first_alias", product: "first", locale: "en", kind: .alias, value: "Collision"),
            name("second_en", product: "second", locale: "bad_locale!", kind: .canonical, value: "Other"),
            name("second_alias", product: "second", locale: "en", kind: .alias, value: "Collision")
        ]
        let snapshot = ProductKnowledgeSnapshot(
            metadata: metadata(productCount: 2),
            categories: [],
            products: [first, second],
            names: names
        )

        let codes = Set(
            ProductKnowledgeFoundationValidator().validate(snapshot)
                .errors.map(\.code)
        )
        XCTAssertTrue(codes.contains(.missingCategory))
        XCTAssertTrue(codes.contains(.aliasCollision))
        XCTAssertTrue(codes.contains(.conflictingBarcode))
        XCTAssertTrue(codes.contains(.invalidLocaleCode))
        XCTAssertTrue(codes.contains(.indistinguishableExactIdentity))
    }

    func testDifferentVariantEvidenceIsNotExactIdentity() {
        let category = ProductCategory(
            id: ProductCategoryID("dairy"),
            names: ProductCategoryNames(en: "Dairy", he: "חלב"),
            iconKey: "product.dairy",
            sortOrder: 0,
            status: .active
        )
        let first = product(
            id: "milk_regular",
            category: "dairy",
            semanticKey: "milk",
            variants: ["regular"]
        )
        let second = product(
            id: "milk_lactose_free",
            category: "dairy",
            semanticKey: "milk",
            variants: ["lactose free"]
        )
        let snapshot = ProductKnowledgeSnapshot(
            metadata: metadata(productCount: 2),
            categories: [category],
            products: [first, second],
            names: [
                name("regular", product: "milk_regular", locale: "en", kind: .canonical, value: "Milk"),
                name("free", product: "milk_lactose_free", locale: "en", kind: .canonical, value: "Lactose Free Milk")
            ]
        )
        let report = ProductKnowledgeFoundationValidator().validate(snapshot)

        XCTAssertFalse(report.errors.contains {
            $0.code == .indistinguishableExactIdentity
        })
    }

    func testCentralNormalizationPreservesDisplayAndNormalizesSearchAndGTIN() {
        let display = "  Crème—Brûlée's  "
        XCTAssertEqual(
            ProductKnowledgeNormalizer.searchText(display).value,
            "creme brulees"
        )
        XCTAssertEqual(display, "  Crème—Brûlée's  ")
        XCTAssertEqual(
            ProductKnowledgeNormalizer.barcode(" 0123-4567 "),
            "01234567"
        )
        XCTAssertEqual(
            ProductKnowledgeNormalizer.searchText("מֶלֶךְ").value,
            "מלכ"
        )
    }

    private func productionSnapshot() throws -> ProductKnowledgeSnapshot {
        let service = ProductCatalogService(bundle: .main)
        let productsURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: ProductCatalogService.resourceName,
                withExtension: ProductCatalogService.resourceExtension
            )
        )
        let document = try service.loadDocument(
            data: Data(contentsOf: productsURL)
        )
        let taxonomy = try ProductCatalogTaxonomyLoader(bundle: .main).load()
        let localizations = try BundledProductKnowledgeLocalizationLoader(
            bundle: .main
        ).load(expectedCatalogVersion: document.catalogVersion)
        let releaseManifest = try BundledProductCatalogReleaseManifestLoader(
            bundle: .main
        ).load(
            expectedCatalogVersion: document.catalogVersion,
            expectedProductCount: document.products.count
        )
        return ProductCatalogKnowledgeAdapter(
            document: document,
            taxonomy: taxonomy,
            localizations: localizations,
            releaseManifest: releaseManifest
        ).makeSnapshot()
    }

    private func metadata(productCount: Int) -> ProductKnowledgeSnapshotMetadata {
        ProductKnowledgeSnapshotMetadata(
            schemaVersion: 1,
            catalogRevision: 1,
            taxonomyVersion: "1",
            expectedProductCount: productCount,
            supportedLocales: ["en"],
            catalogVersion: 1,
            source: "test"
        )
    }

    private func product(
        id: String,
        category: String,
        semanticKey: String,
        variants: [String] = [],
        barcodes: [String] = []
    ) -> ProductEntity {
        ProductEntity(
            id: ProductID(id),
            defaultNameID: ProductNameID("\(id)_en"),
            primaryCategoryID: ProductCategoryID(category),
            semanticKey: semanticKey,
            variantDescriptors: variants,
            barcodes: barcodes,
            status: .active
        )
    }

    private func name(
        _ id: String,
        product: String,
        locale: String,
        kind: ProductNameKind,
        value: String
    ) -> ProductName {
        ProductName(
            id: ProductNameID(id),
            productID: ProductID(product),
            locale: locale,
            kind: kind,
            value: value,
            isPreferred: kind.isDisplayCapable
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
