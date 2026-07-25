import XCTest
@testable import WayTask

@MainActor
final class ProductCatalogAutocompleteTests: XCTestCase {
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
