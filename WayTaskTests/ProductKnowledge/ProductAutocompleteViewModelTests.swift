import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductAutocompleteViewModelTests: XCTestCase {
    func testEmptyAndWhitespaceQueriesStayIdleWithoutSearching() async {
        let recorder = ProductAutocompleteSearchRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("", localeIdentifier: "en")
        viewModel.updateQuery(" \n\t ", localeIdentifier: "en")
        await Task.yield()

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNil(viewModel.customProductActionName)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        let requests = await recorder.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testOneNormalizedCharacterSearchesImmediatelyWithEightResultLimit() async throws {
        let recorder = ProductAutocompleteSearchRecorder(
            responses: ["m": [makeResult(id: "milk", displayName: "Milk")]]
        )
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("M", localeIdentifier: "en_US")

        try await waitUntil {
            viewModel.phase == .results
        }
        let requests = await recorder.requests
        XCTAssertEqual(
            requests,
            [
                ProductAutocompleteSearchRequest(
                    query: "m",
                    localeIdentifier: "en_US",
                    limit: 8
                )
            ]
        )
        XCTAssertEqual(viewModel.results.map(\.displayName), ["Milk"])
        XCTAssertEqual(viewModel.customProductActionName, "M")
    }

    func testDifferentQueryReplacesDisplayedResults() async throws {
        let recorder = ProductAutocompleteSearchRecorder(
            responses: [
                "m": [makeResult(id: "milk", displayName: "Milk")],
                "b": [makeResult(id: "bread", displayName: "Bread")]
            ]
        )
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.results.first?.displayName == "Milk"
        }

        viewModel.updateQuery("b", localeIdentifier: "en")
        XCTAssertTrue(viewModel.results.isEmpty)
        try await waitUntil {
            viewModel.results.first?.displayName == "Bread"
        }

        XCTAssertEqual(viewModel.phase, .results)
        XCTAssertEqual(viewModel.results.map(\.displayName), ["Bread"])
    }

    func testClearingQueryImmediatelyClearsResultsAndInvalidatesSearch() async throws {
        let recorder = ProductAutocompleteSearchRecorder(
            responses: ["m": [makeResult(id: "milk", displayName: "Milk")]]
        )
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        viewModel.updateQuery("  ", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testOlderCompletionCannotReplaceLatestQueryResults() async throws {
        let gate = ProductAutocompleteSearchGate()
        let viewModel = AddProductAutocompleteViewModel(
            suggestionProvider: { query, _, _ in
                await gate.suggestions(for: query)
            },
            slowSearchDelay: longSlowSearchDelay
        )
        let oldResult = makeResult(id: "milk", displayName: "Milk")
        let latestResult = makeResult(id: "bread", displayName: "Bread")

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await gate.waitUntilRequested("m")
        viewModel.updateQuery("b", localeIdentifier: "en")
        try await gate.waitUntilRequested("b")

        await gate.resolve("b", with: [latestResult])
        try await waitUntil {
            viewModel.results == [latestResult]
        }

        await gate.resolve("m", with: [oldResult])
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(viewModel.phase, .results)
        XCTAssertEqual(viewModel.results, [latestResult])
    }

    func testUnavailableSearchShowsApprovedNontechnicalStateForNonemptyQuery() {
        let viewModel = AddProductAutocompleteViewModel(
            searchAvailability: .unavailable,
            slowSearchDelay: longSlowSearchDelay
        )

        viewModel.updateQuery("m", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .unavailable)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.customProductActionName, "m")
        XCTAssertEqual(
            ProductAutocompleteCopy.unavailable(localeIdentifier: "en"),
            "Product suggestions are unavailable. You can still add this product manually."
        )
    }

    func testResultListIsCappedAtEightRows() async throws {
        let results = (0..<10).map {
            makeResult(id: "product_\($0)", displayName: "Product \($0)")
        }
        let recorder = ProductAutocompleteSearchRecorder(responses: ["p": results])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("p", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        XCTAssertEqual(viewModel.results.count, 8)
    }

    func testSelectionRequiresExplicitCurrentResultAndRetainsApprovedMetadata() async throws {
        let result = makeResult(
            id: "milk",
            displayName: "חלב",
            displayLocale: "he",
            secondaryName: "Milk",
            categoryID: "dairy",
            categoryDisplayName: "מוצרי חלב ותחליפים",
            iconKey: "product.dairy"
        )
        let recorder = ProductAutocompleteSearchRecorder(responses: ["ח": [result]])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("ח", localeIdentifier: "he-IL")
        try await waitUntil {
            viewModel.phase == .results
        }

        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "  ח  "
            )
        )

        let selection = try XCTUnwrap(viewModel.selectedCatalogProduct)
        XCTAssertEqual(viewModel.phase, .selectedCatalog)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(selection.productID, ProductID("milk"))
        XCTAssertEqual(selection.displayName, "חלב")
        XCTAssertEqual(selection.displayLocale, "he")
        XCTAssertEqual(selection.secondaryName, "Milk")
        XCTAssertEqual(selection.categoryID, ProductCategoryID("dairy"))
        XCTAssertEqual(selection.categoryDisplayName, "מוצרי חלב ותחליפים")
        XCTAssertEqual(selection.iconKey, "product.dairy")
        XCTAssertEqual(selection.preselectionQuery, "  ח  ")
        XCTAssertTrue(viewModel.canChangeSelection)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertTrue(viewModel.allowsCatalogProductSave)
        XCTAssertTrue(viewModel.canConfirmProduct)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testNoncurrentResultCannotBeSelectedAndNoResultIsSelectedAutomatically() async throws {
        let current = makeResult(id: "milk", displayName: "Milk")
        let other = makeResult(id: "bread", displayName: "Bread")
        let recorder = ProductAutocompleteSearchRecorder(responses: ["m": [current]])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertFalse(
            viewModel.selectCatalogProduct(
                other,
                preselectionQuery: "m"
            )
        )
        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertEqual(viewModel.phase, .results)
        XCTAssertEqual(viewModel.results, [current])
    }

    func testChangeRestoresExactPreselectionQueryAndRerunsSuggestions() async throws {
        let result = makeResult(id: "milk", displayName: "Milk")
        let recorder = ProductAutocompleteSearchRecorder(responses: ["mil": [result]])
        let viewModel = makeViewModel(recorder: recorder)
        let rawQuery = "  MiL  "

        viewModel.updateQuery(rawQuery, localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: rawQuery
            )
        )

        let restoredQuery = viewModel.changeCatalogSelection(
            localeIdentifier: "en"
        )

        XCTAssertEqual(restoredQuery, rawQuery)
        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertFalse(viewModel.canChangeSelection)
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertEqual(viewModel.results, [result])
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.query), ["mil", "mil"])
    }

    func testLateOldResultCannotOverrideRestoredChangeResults() async throws {
        let gate = ProductAutocompleteSearchGate()
        let viewModel = AddProductAutocompleteViewModel(
            suggestionProvider: { query, _, _ in
                await gate.suggestions(for: query)
            },
            slowSearchDelay: longSlowSearchDelay
        )
        let staleResult = makeResult(id: "milk", displayName: "Milk")
        let selectedResult = makeResult(id: "bread", displayName: "Bread")
        let restoredResult = makeResult(id: "bread", displayName: "Bread")

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await gate.waitUntilRequested("m")
        viewModel.updateQuery("b", localeIdentifier: "en")
        try await gate.waitUntilRequested("b")
        await gate.resolve("b", with: [selectedResult])
        try await waitUntil {
            viewModel.results == [selectedResult]
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                selectedResult,
                preselectionQuery: "b"
            )
        )

        XCTAssertEqual(
            viewModel.changeCatalogSelection(localeIdentifier: "en"),
            "b"
        )
        try await gate.waitUntilRequested("b")
        await gate.resolve("b", with: [restoredResult])
        try await waitUntil {
            viewModel.results == [restoredResult]
        }

        await gate.resolve("m", with: [staleResult])
        await Task.yield()
        await Task.yield()

        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertEqual(viewModel.phase, .results)
        XCTAssertEqual(viewModel.results, [restoredResult])
    }

    func testResetClearsSelectionAndNextFlowStartsWithoutStaleSelection() async throws {
        let milk = makeResult(id: "milk", displayName: "Milk")
        let bread = makeResult(id: "bread", displayName: "Bread")
        let recorder = ProductAutocompleteSearchRecorder(
            responses: ["m": [milk], "b": [bread]]
        )
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                milk,
                preselectionQuery: "m"
            )
        )

        viewModel.reset()

        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertFalse(viewModel.canChangeSelection)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)

        viewModel.updateQuery("b", localeIdentifier: "en")
        try await waitUntil {
            viewModel.results == [bread]
        }
        XCTAssertNil(viewModel.selectedCatalogProduct)
    }

    func testSelectedSummaryExposesLocalizedAccessibilityStateOnlyWhileSelected() async throws {
        let result = makeResult(
            id: "milk",
            displayName: "Milk",
            categoryID: "dairy",
            categoryDisplayName: "Dairy"
        )
        let recorder = ProductAutocompleteSearchRecorder(responses: ["m": [result]])
        let viewModel = makeViewModel(recorder: recorder)

        XCTAssertNil(
            viewModel.selectedSummaryAccessibilityLabel(
                localeIdentifier: "en"
            )
        )
        XCTAssertFalse(viewModel.canChangeSelection)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "m"
            )
        )

        XCTAssertEqual(
            viewModel.selectedSummaryAccessibilityLabel(
                localeIdentifier: "en"
            ),
            "Milk selected, Dairy"
        )
        XCTAssertTrue(viewModel.canChangeSelection)
        XCTAssertEqual(
            ProductAutocompleteCopy.changeAccessibilityLabel(
                localeIdentifier: "he"
            ),
            "שינוי המוצר שנבחר"
        )
    }

    func testCustomActionUsesTrimmedRawTextWithoutRepeatingEquivalentSearch() async throws {
        let result = makeResult(id: "milk", displayName: "Milk")
        let recorder = ProductAutocompleteSearchRecorder(responses: ["mil": [result]])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("  MiL  ", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertEqual(viewModel.customProductActionName, "MiL")

        viewModel.updateQuery("\nMIL\n", localeIdentifier: "en")

        XCTAssertEqual(viewModel.customProductActionName, "MIL")
        XCTAssertEqual(viewModel.results, [result])
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.query), ["mil"])
    }

    func testCustomActionAppearsWithoutCatalogResultsAndSupportsNormalizationEmptyText() async throws {
        let recorder = ProductAutocompleteSearchRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("Mystery Product", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .noMatch
        }

        XCTAssertEqual(viewModel.customProductActionName, "Mystery Product")
        XCTAssertFalse(viewModel.allowsManualProductSave)

        viewModel.updateQuery("  +++  ", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.customProductActionName, "+++")
    }

    func testCustomSelectionRetainsTrimmedNameAndRequiresLaterManualConfirmation() async throws {
        let catalogResult = makeResult(id: "milk", displayName: "Milk")
        let recorder = ProductAutocompleteSearchRecorder(
            responses: ["vanilla pudding": [catalogResult]]
        )
        let viewModel = makeViewModel(recorder: recorder)
        let rawQuery = "  Vanilla   Pudding  "

        viewModel.updateQuery(rawQuery, localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        let selection = try XCTUnwrap(viewModel.selectCustomProduct())

        XCTAssertEqual(
            selection,
            AddProductCustomSelection(
                name: "Vanilla   Pudding",
                preselectionQuery: rawQuery
            )
        )
        XCTAssertEqual(viewModel.selectedCustomProduct, selection)
        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertEqual(viewModel.phase, .selectedCustom)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNil(viewModel.customProductActionName)
        XCTAssertTrue(viewModel.canChangeSelection)
        XCTAssertTrue(viewModel.allowsManualProductSave)
        XCTAssertFalse(viewModel.allowsCatalogProductSave)
        XCTAssertTrue(viewModel.canConfirmProduct)
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCustomChangeRestoresOriginalQuerySuggestionsAndConfirmationGuard() async throws {
        let result = makeResult(id: "milk", displayName: "Milk")
        let recorder = ProductAutocompleteSearchRecorder(responses: ["mil": [result]])
        let viewModel = makeViewModel(recorder: recorder)
        let rawQuery = "  MiL  "

        viewModel.updateQuery(rawQuery, localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertNotNil(viewModel.selectCustomProduct())

        let restoredQuery = viewModel.changeCustomProductSelection(
            localeIdentifier: "en"
        )

        XCTAssertEqual(restoredQuery, rawQuery)
        XCTAssertNil(viewModel.selectedCustomProduct)
        XCTAssertFalse(viewModel.canChangeSelection)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertEqual(viewModel.customProductActionName, "MiL")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertEqual(viewModel.results, [result])
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.query), ["mil", "mil"])
    }

    func testResetClearsCustomSelectionAndManualConfirmation() async throws {
        let recorder = ProductAutocompleteSearchRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("  Custom Need  ", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .noMatch
        }
        XCTAssertNotNil(viewModel.selectCustomProduct())

        viewModel.reset()

        XCTAssertNil(viewModel.selectedCustomProduct)
        XCTAssertNil(viewModel.selectedCatalogProduct)
        XCTAssertNil(viewModel.customProductActionName)
        XCTAssertEqual(viewModel.rawQuery, "")
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertFalse(viewModel.canChangeSelection)
        XCTAssertFalse(viewModel.allowsManualProductSave)
    }

    func testCustomActionAndSelectedSummaryExposeLocalizedAccessibilityCopy() {
        let viewModel = AddProductAutocompleteViewModel(
            searchAvailability: .unavailable,
            slowSearchDelay: longSlowSearchDelay
        )
        viewModel.updateQuery("  Custom Need  ", localeIdentifier: "en")

        XCTAssertEqual(
            ProductAutocompleteCopy.customProductAction(
                name: "Custom Need",
                localeIdentifier: "en"
            ),
            "Add “Custom Need” as a custom product"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.customProductAction(
                name: "צורך מיוחד",
                localeIdentifier: "he"
            ),
            "הוספת ״צורך מיוחד״ כמוצר מותאם אישית"
        )

        let selection = viewModel.selectCustomProduct()

        XCTAssertNotNil(selection)
        XCTAssertEqual(
            viewModel.selectedCustomSummaryAccessibilityLabel(
                localeIdentifier: "en"
            ),
            "Custom Need selected, Custom Product. Add Product to confirm."
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.customProduct(localeIdentifier: "he"),
            "מוצר מותאם אישית"
        )
        XCTAssertTrue(viewModel.canChangeSelection)
    }

    func testCatalogSavingPreventsDuplicateConfirmationAndFailureAllowsRetry() async throws {
        let result = makeResult(id: "milk", displayName: "Milk")
        let recorder = ProductAutocompleteSearchRecorder(responses: ["m": [result]])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "m"
            )
        )
        let selectedCatalogProduct = try XCTUnwrap(
            viewModel.selectedCatalogProduct
        )

        XCTAssertEqual(
            viewModel.beginSavingProduct(),
            .catalog(selectedCatalogProduct)
        )
        XCTAssertTrue(viewModel.isSavingProduct)
        XCTAssertNil(viewModel.beginSavingProduct())
        XCTAssertFalse(viewModel.canConfirmProduct)
        XCTAssertFalse(viewModel.canChangeSelection)
        XCTAssertFalse(viewModel.allowsCatalogProductSave)
        XCTAssertEqual(
            viewModel.selectedCatalogProduct,
            selectedCatalogProduct
        )

        viewModel.finishSavingProductAfterFailure()

        XCTAssertFalse(viewModel.isSavingProduct)
        XCTAssertTrue(viewModel.canConfirmProduct)
        XCTAssertTrue(viewModel.canChangeSelection)
        XCTAssertTrue(viewModel.allowsCatalogProductSave)
        XCTAssertEqual(
            viewModel.selectedCatalogProduct,
            selectedCatalogProduct
        )
        XCTAssertEqual(
            viewModel.beginSavingProduct(),
            .catalog(selectedCatalogProduct)
        )
    }

    private func makeViewModel(
        recorder: ProductAutocompleteSearchRecorder
    ) -> AddProductAutocompleteViewModel {
        AddProductAutocompleteViewModel(
            suggestionProvider: { query, localeIdentifier, limit in
                await recorder.suggestions(
                    query: query,
                    localeIdentifier: localeIdentifier,
                    limit: limit
                )
            },
            slowSearchDelay: longSlowSearchDelay
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for autocomplete state.", file: file, line: line)
    }
}

private let longSlowSearchDelay: ProductAutocompleteSlowSearchDelay = {
    try? await Task.sleep(nanoseconds: 10_000_000_000)
}

nonisolated private func makeResult(
    id: String,
    displayName: String,
    displayLocale: String = "en",
    secondaryName: String? = nil,
    categoryID: String = "test",
    categoryDisplayName: String = "Test",
    iconKey: String = "product.generic"
) -> ProductSearchResult {
    ProductSearchResult(
        productID: ProductID(id),
        displayName: displayName,
        displayLocale: displayLocale,
        secondaryName: secondaryName,
        categoryID: ProductCategoryID(categoryID),
        categoryDisplayName: categoryDisplayName,
        iconKey: iconKey,
        matchedRecordAuthority: .primaryDisplayName,
        matchType: .fullNamePrefix,
        matchedLocale: "en"
    )
}

nonisolated private struct ProductAutocompleteSearchRequest: Equatable, Sendable {
    let query: String
    let localeIdentifier: String
    let limit: Int
}

private actor ProductAutocompleteSearchRecorder {
    private(set) var requests: [ProductAutocompleteSearchRequest] = []
    private let responses: [String: [ProductSearchResult]]

    init(responses: [String: [ProductSearchResult]] = [:]) {
        self.responses = responses
    }

    func suggestions(
        query: String,
        localeIdentifier: String,
        limit: Int
    ) -> [ProductSearchResult] {
        requests.append(
            ProductAutocompleteSearchRequest(
                query: query,
                localeIdentifier: localeIdentifier,
                limit: limit
            )
        )
        return responses[query] ?? []
    }
}

private actor ProductAutocompleteSearchGate {
    private var continuations: [
        String: CheckedContinuation<[ProductSearchResult], Never>
    ] = [:]

    func suggestions(for query: String) async -> [ProductSearchResult] {
        await withCheckedContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilRequested(_ query: String) async throws {
        for _ in 0..<200 {
            if continuations[query] != nil {
                return
            }
            await Task.yield()
        }
        throw ProductAutocompleteTestError.requestNotStarted(query)
    }

    func resolve(_ query: String, with results: [ProductSearchResult]) {
        continuations.removeValue(forKey: query)?.resume(returning: results)
    }
}

nonisolated private enum ProductAutocompleteTestError: Error {
    case requestNotStarted(String)
}
