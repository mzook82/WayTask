import XCTest
@testable import WayTask

@MainActor
final class ProductCatalogAutocompleteTests: XCTestCase {
    func testHebrewWholeWheatSelectionLocksFullDisplayAndCanonicalID()
        async throws {
        let viewModel = try makeBundledViewModel()

        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                "לח",
                localeIdentifier: "he-IL"
            ),
            "לח"
        )
        try await waitUntil { viewModel.phase == .results }

        let result = try XCTUnwrap(
            viewModel.results.first {
                $0.productID == ProductID("bread_whole_wheat")
            }
        )
        XCTAssertEqual(result.displayName, "לחם מחיטה מלאה")
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "לח"
            )
        )

        XCTAssertEqual(
            viewModel.selectedCatalogProduct?.productID,
            ProductID("bread_whole_wheat")
        )
        XCTAssertEqual(
            viewModel.selectedCatalogProduct?.displayName,
            "לחם מחיטה מלאה"
        )
        XCTAssertEqual(viewModel.rawQuery, "לחם מחיטה מלאה")
        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                "לי",
                localeIdentifier: "he-IL"
            ),
            "לחם מחיטה מלאה"
        )

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(viewModel.rawQuery, "לחם מחיטה מלאה")
        XCTAssertEqual(viewModel.phase, .selectedCatalog)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testHebrewMilkSelectionRemainsCorrect() async throws {
        let viewModel = try makeBundledViewModel()

        _ = viewModel.acceptTextFieldEdit(
            "חלב",
            localeIdentifier: "he-IL"
        )
        try await waitUntil { viewModel.phase == .results }
        let result = try XCTUnwrap(
            viewModel.results.first {
                $0.productID == ProductID("milk_3_percent")
            }
        )

        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "חלב"
            )
        )
        XCTAssertEqual(viewModel.rawQuery, "חלב 3%")
        XCTAssertEqual(
            viewModel.selectedCatalogProduct?.productID,
            ProductID("milk_3_percent")
        )
    }

    func testComposedHebrewTextNeverBecomesPartialAfterSelection()
        async throws {
        let viewModel = try makeBundledViewModel()
        let composedQuery = "ל\u{05B8}ח"

        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                composedQuery,
                localeIdentifier: "he-IL"
            ),
            composedQuery
        )
        XCTAssertEqual(viewModel.rawQuery, composedQuery)
        try await waitUntil { viewModel.phase == .results }
        let result = try XCTUnwrap(
            viewModel.results.first {
                $0.productID == ProductID("bread_whole_wheat")
            }
        )

        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: composedQuery
            )
        )
        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                "ל\u{05B8}י",
                localeIdentifier: "he-IL"
            ),
            "לחם מחיטה מלאה"
        )
        XCTAssertEqual(viewModel.rawQuery, "לחם מחיטה מלאה")
    }

    func testEnglishSelectionContractRemainsUnchanged() async throws {
        let viewModel = makeViewModel(
            search: ProductCatalogSearch(
                products: [
                    product(id: "milk_en", name: "Milk")
                ]
            )
        )

        _ = viewModel.acceptTextFieldEdit(
            "mi",
            localeIdentifier: "en"
        )
        try await waitUntil { viewModel.phase == .results }
        let result = try XCTUnwrap(viewModel.results.first)

        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "mi"
            )
        )
        XCTAssertEqual(viewModel.rawQuery, "Milk")
        XCTAssertEqual(
            viewModel.selectedCatalogProduct?.productID,
            ProductID("milk_en")
        )
    }

    func testExactCatalogNameSuppressesCustomProductOption() async throws {
        let search = ProductCatalogSearch(products: [
            product(id: "bread", name: "לחם")
        ])
        let viewModel = makeViewModel(search: search)

        viewModel.updateQuery("לחם", localeIdentifier: "he-IL")
        try await waitUntil { viewModel.phase == .results }

        XCTAssertNil(viewModel.customProductActionName)
        XCTAssertEqual(viewModel.results.first?.displayName, "לחם")
    }

    func testUnmatchedQueryPreservesExactCustomProductText() async throws {
        let search = ProductCatalogSearch(products: [
            product(id: "bread", name: "לחם")
        ])
        let viewModel = makeViewModel(search: search)
        let customName = "  לחם מחמצת מהמאפייה  "

        viewModel.updateQuery(customName, localeIdentifier: "he-IL")
        try await waitUntil { viewModel.phase == .noMatch }

        XCTAssertEqual(
            viewModel.customProductActionName,
            "לחם מחמצת מהמאפייה"
        )
        let selection = try XCTUnwrap(viewModel.selectCustomProduct())
        XCTAssertEqual(selection.name, "לחם מחמצת מהמאפייה")
        XCTAssertEqual(selection.preselectionQuery, customName)
    }

    func testCatalogFailureStillAllowsCustomProductEntry() {
        let viewModel = AddProductAutocompleteViewModel(
            searchAvailability: .unavailable
        )

        viewModel.updateQuery("מוצר שלא קיים", localeIdentifier: "he-IL")

        XCTAssertEqual(viewModel.phase, .unavailable)
        XCTAssertEqual(viewModel.customProductActionName, "מוצר שלא קיים")
        XCTAssertNotNil(viewModel.selectCustomProduct())
    }

    func testCAT007NoMatchCopyIsAlwaysHebrew() {
        XCTAssertEqual(
            ProductAutocompleteCopy.noMatch(localeIdentifier: "en-US"),
            "לא נמצא מוצר מתאים בקטלוג"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.noMatch(localeIdentifier: "he-IL"),
            "לא נמצא מוצר מתאים בקטלוג"
        )
    }

    func testCAT008CustomAddCopyIsAlwaysHebrew() {
        XCTAssertEqual(
            ProductAutocompleteCopy.customProductAction(
                name: "מוצר חדש",
                localeIdentifier: "en-US"
            ),
            "הוסף את ״מוצר חדש״ כמוצר מותאם אישית"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.customProductAction(
                name: "מוצר חדש",
                localeIdentifier: "he-IL"
            ),
            "הוסף את ״מוצר חדש״ כמוצר מותאם אישית"
        )
    }

    private func makeViewModel(
        search: ProductCatalogSearch
    ) -> AddProductAutocompleteViewModel {
        AddProductAutocompleteViewModel(
            searchAvailability: .catalog(search),
            slowSearchDelay: {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        )
    }

    private func makeBundledViewModel() throws
        -> AddProductAutocompleteViewModel {
        makeViewModel(
            search: ProductCatalogSearch(
                products: try ProductCatalogService().loadProducts()
            )
        )
    }

    private func product(id: String, name: String) -> CatalogProduct {
        CatalogProduct(
            id: id,
            canonicalName: name,
            categoryId: "bakery",
            aliases: [],
            keywords: [],
            popularityScore: 50,
            isActive: true
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for view-model state.")
    }
}
