import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductAutocompleteViewModelTests: XCTestCase {
    func testPreferredApplicationLanguageOverridesRegionalEnvironmentLocale() {
        XCTAssertEqual(
            ProductAutocompleteLocaleResolver
                .preferredApplicationLocaleIdentifier(
                    environmentLocaleIdentifier: "en_IL",
                    preferredLanguages: ["he-IL", "en"]
                ),
            "he-IL"
        )
        XCTAssertEqual(
            ProductAutocompleteLocaleResolver
                .preferredApplicationLocaleIdentifier(
                    environmentLocaleIdentifier: "he_IL",
                    preferredLanguages: []
                ),
            "he_IL"
        )
        XCTAssertEqual(
            ProductAutocompleteLocaleResolver
                .preferredApplicationLocaleIdentifier(
                    environmentLocaleIdentifier: " ",
                    preferredLanguages: [" "]
                ),
            "en"
        )
    }

    func testHebrewPreferredLanguageProducesHebrewSelectionMetadata() async throws {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)
        let viewModel = AddProductAutocompleteViewModel(
            searchAvailability: .available(
                ProductKnowledgeSearch(repository: repository)
            ),
            slowSearchDelay: longSlowSearchDelay
        )
        let localeIdentifier = ProductAutocompleteLocaleResolver
            .preferredApplicationLocaleIdentifier(
                environmentLocaleIdentifier: "en_IL",
                preferredLanguages: ["he-IL", "en"]
            )

        viewModel.updateQuery(
            "חלב",
            localeIdentifier: localeIdentifier
        )

        try await waitUntil {
            viewModel.phase == .results
        }
        let result = try XCTUnwrap(viewModel.results.first)
        XCTAssertEqual(result.productID, ProductID("prd_pilot_0001"))
        XCTAssertEqual(result.displayName, "חלב")
        XCTAssertEqual(result.displayLocale, "he")
        XCTAssertNil(result.secondaryName)
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "חלב"
            )
        )
        let selection = try XCTUnwrap(viewModel.selectedCatalogProduct)
        XCTAssertEqual(selection.productID, ProductID("prd_pilot_0001"))
        XCTAssertEqual(selection.displayName, "חלב")
        XCTAssertEqual(selection.displayLocale, "he")
    }

    func testEmptyAndWhitespaceQueriesStayIdleWithoutSearching() async {
        let recorder = ProductAutocompleteSearchRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        viewModel.updateQuery("", localeIdentifier: "en")
        viewModel.updateQuery(" \n\t ", localeIdentifier: "en")
        await Task.yield()

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNil(viewModel.customProductActionName)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertFalse(viewModel.keepsSuggestionAreaVisible)
        XCTAssertEqual(viewModel.presentationSlots, .empty)
        let requests = await recorder.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testOneNormalizedCharacterSearchesImmediatelyWithTenResultLimit() async throws {
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
                    limit: 10
                )
            ]
        )
        XCTAssertEqual(viewModel.results.map(\.displayName), ["Milk"])
        XCTAssertEqual(viewModel.customProductActionName, "M")
    }

    func testQueryReplacementKeepsPriorPresentationButRejectsStaleSelection() async throws {
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
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertTrue(viewModel.keepsSuggestionAreaVisible)
        XCTAssertTrue(viewModel.allowsCatalogResultSelection)
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: true,
                customActionName: "m"
            )
        )
        let staleResult = try XCTUnwrap(viewModel.results.first)

        viewModel.updateQuery("b", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .replacingResults)
        XCTAssertEqual(viewModel.results, [staleResult])
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertTrue(viewModel.keepsSuggestionAreaVisible)
        XCTAssertFalse(viewModel.allowsCatalogResultSelection)
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: true,
                customActionName: "b"
            )
        )
        XCTAssertFalse(
            viewModel.selectCatalogProduct(
                staleResult,
                preselectionQuery: "b"
            )
        )
        XCTAssertNil(viewModel.selectedCatalogProduct)

        try await waitUntil {
            viewModel.results.first?.displayName == "Bread"
        }

        XCTAssertEqual(viewModel.phase, .results)
        XCTAssertEqual(viewModel.results.map(\.displayName), ["Bread"])
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertTrue(viewModel.keepsSuggestionAreaVisible)
        XCTAssertTrue(viewModel.allowsCatalogResultSelection)
    }

    func testTypingAndDeletingPreserveEditableFocusIntent() async throws {
        let recorder = ProductAutocompleteSearchRecorder(
            responses: [
                "m": [makeResult(id: "milk", displayName: "Milk")],
                "mi": [makeResult(id: "milk", displayName: "Milk")]
            ]
        )
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("m", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        viewModel.updateQuery("mi", localeIdentifier: "en")
        XCTAssertEqual(viewModel.phase, .replacingResults)
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertNil(viewModel.selection)
        try await waitUntil {
            viewModel.phase == .results
        }

        viewModel.updateQuery("m", localeIdentifier: "en")
        XCTAssertEqual(viewModel.phase, .replacingResults)
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertNil(viewModel.selection)
        try await waitUntil {
            viewModel.phase == .results
        }

        XCTAssertTrue(viewModel.allowsNameFieldFocus)
        XCTAssertNil(viewModel.selection)
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
        XCTAssertFalse(viewModel.keepsSuggestionAreaVisible)
        XCTAssertEqual(viewModel.presentationSlots, .empty)
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
    }

    func testSearchingCustomOnlyAndNoMatchSharePersistentPresentationSlots() async throws {
        let gate = ProductAutocompleteSearchGate()
        let viewModel = AddProductAutocompleteViewModel(
            suggestionProvider: { query, _, _ in
                await gate.suggestions(for: query)
            },
            slowSearchDelay: { }
        )

        viewModel.updateQuery("z", localeIdentifier: "en")
        try await gate.waitUntilRequested("z")
        try await waitUntil {
            viewModel.phase == .searchingSlow
        }

        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .searching,
                showsResults: false,
                customActionName: "z"
            )
        )

        viewModel.updateQuery("zx", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: false,
                customActionName: "zx"
            )
        )

        try await gate.waitUntilRequested("zx")
        await gate.resolve("z", with: [])
        await gate.resolve("zx", with: [])
        try await waitUntil {
            viewModel.phase == .noMatch
        }

        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .noMatch,
                showsResults: false,
                customActionName: "zx"
            )
        )
    }

    func testUnmatchedTypingDeletionAndClearingPreservePresentationSlotIntent() async throws {
        let recorder = ProductAutocompleteSearchRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("nonsense", localeIdentifier: "en")
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: false,
                customActionName: "nonsense"
            )
        )
        try await waitUntil {
            viewModel.phase == .noMatch
        }
        XCTAssertEqual(
            viewModel.presentationSlots.statusContent,
            .noMatch
        )

        viewModel.updateQuery("nonsensex", localeIdentifier: "en")
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: false,
                customActionName: "nonsensex"
            )
        )
        try await waitUntil {
            viewModel.phase == .noMatch
        }

        viewModel.updateQuery("nonsense", localeIdentifier: "en")
        XCTAssertEqual(
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .hidden,
                showsResults: false,
                customActionName: "nonsense"
            )
        )
        try await waitUntil {
            viewModel.phase == .noMatch
        }

        viewModel.updateQuery(" \n ", localeIdentifier: "en")

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.presentationSlots, .empty)
        XCTAssertNil(viewModel.customProductActionName)
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
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
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
            viewModel.presentationSlots,
            ProductAutocompletePresentationSlots(
                isActive: true,
                statusContent: .unavailable,
                showsResults: false,
                customActionName: "m"
            )
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.unavailable(localeIdentifier: "en"),
            "Product suggestions are unavailable. You can still add this product manually."
        )
    }

    func testResultListIsCappedAtTenRows() async throws {
        let results = (0..<10).map {
            makeResult(id: "product_\($0)", displayName: "Product \($0)")
        }
        let recorder = ProductAutocompleteSearchRecorder(responses: ["p": results])
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updateQuery("p", localeIdentifier: "en")
        try await waitUntil {
            viewModel.phase == .results
        }

        XCTAssertEqual(viewModel.results.count, 10)
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

        XCTAssertTrue(viewModel.allowsNameFieldFocus)
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
        XCTAssertFalse(viewModel.allowsNameFieldFocus)
        XCTAssertFalse(viewModel.keepsSuggestionAreaVisible)
        XCTAssertFalse(viewModel.allowsCatalogResultSelection)
        XCTAssertFalse(viewModel.allowsManualProductSave)
        XCTAssertTrue(viewModel.allowsCatalogProductSave)
        XCTAssertTrue(viewModel.canConfirmProduct)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testLateHebrewFieldCommitCannotStartSearchOrRewriteSelection()
        async throws {
        let result = makeResult(
            id: "bread_whole_wheat",
            displayName: "לחם מחיטה מלאה",
            displayLocale: "he",
            categoryID: "bakery",
            categoryDisplayName: "מאפים ולחמים",
            iconKey: "product.bread"
        )
        let recorder = ProductAutocompleteSearchRecorder(
            responses: ["לח": [result]]
        )
        let viewModel = makeViewModel(recorder: recorder)

        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                "לח",
                localeIdentifier: "he-IL"
            ),
            "לח"
        )
        try await waitUntil {
            viewModel.phase == .results
        }
        XCTAssertTrue(
            viewModel.selectCatalogProduct(
                result,
                preselectionQuery: "לח"
            )
        )

        XCTAssertEqual(
            viewModel.acceptTextFieldEdit(
                "לי",
                localeIdentifier: "he-IL"
            ),
            "לחם מחיטה מלאה"
        )
        await Task.yield()
        await Task.yield()
        let requests = await recorder.requests

        XCTAssertEqual(
            requests.map(\.query),
            ["לח"]
        )
        XCTAssertEqual(viewModel.rawQuery, "לחם מחיטה מלאה")
        XCTAssertEqual(
            viewModel.selectedCatalogProduct?.productID,
            ProductID("bread_whole_wheat")
        )
        XCTAssertEqual(viewModel.phase, .selectedCatalog)
        XCTAssertTrue(viewModel.results.isEmpty)
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
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
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
        XCTAssertTrue(viewModel.allowsNameFieldFocus)
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

    func testDeviceQACopyLocalizesInputDuplicateFeedbackAndMixedLanguageSummary() {
        XCTAssertEqual(
            ProductAutocompleteCopy.productNameFieldLabel(
                localeIdentifier: "he-IL"
            ),
            "שם המוצר"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.productNamePlaceholder(
                localeIdentifier: "en"
            ),
            "Type a product name"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.alreadyPresentTitle(
                localeIdentifier: "he"
            ),
            "המוצר כבר שמור"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.alreadyPresentMessage(
                productName: "חלב",
                localeIdentifier: "en"
            ),
            "“חלב” is already in Products. Your existing product was kept unchanged."
        )

        let selection = AddProductCatalogSelection(
            result: makeResult(
                id: "milk",
                displayName: "חלב",
                displayLocale: "he",
                secondaryName: "Milk",
                categoryID: "dairy",
                categoryDisplayName: "מוצרי חלב ותחליפים"
            ),
            preselectionQuery: "milk"
        )

        XCTAssertEqual(
            ProductAutocompleteCopy.selectedSummaryAccessibilityLabel(
                selection,
                localeIdentifier: "he"
            ),
            "חלב נבחר, Milk, מוצרי חלב ותחליפים"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.suggestionAccessibilityLabel(
                makeResult(
                    id: "milk",
                    displayName: "חלב",
                    displayLocale: "he",
                    secondaryName: "Milk",
                    categoryID: "dairy",
                    categoryDisplayName: "מוצרי חלב ותחליפים"
                ),
                localeIdentifier: "he"
            ),
            "חלב, נמצא גם בשם Milk, מוצרי חלב ותחליפים"
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
        XCTAssertFalse(viewModel.keepsSuggestionAreaVisible)
        XCTAssertFalse(viewModel.allowsCatalogResultSelection)
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
            "הוסף את ״Custom Need״ כמוצר מותאם אישית"
        )
        XCTAssertEqual(
            ProductAutocompleteCopy.customProductAction(
                name: "צורך מיוחד",
                localeIdentifier: "he"
            ),
            "הוסף את ״צורך מיוחד״ כמוצר מותאם אישית"
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
