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
    displayName: String
) -> ProductSearchResult {
    ProductSearchResult(
        productID: ProductID(id),
        displayName: displayName,
        displayLocale: "en",
        secondaryName: nil,
        categoryID: ProductCategoryID("test"),
        categoryDisplayName: "Test",
        iconKey: "product.generic",
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
