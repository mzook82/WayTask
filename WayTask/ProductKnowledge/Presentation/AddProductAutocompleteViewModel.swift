import Combine
import Foundation

nonisolated enum ProductSuggestionPhase: Equatable, Sendable {
    case idle
    case searchingSlow
    case results
    case noMatch
    case unavailable
    case selectedCatalog
}

nonisolated struct AddProductCatalogSelection: Hashable, Sendable {
    let productID: ProductID
    let displayName: String
    let displayLocale: String
    let secondaryName: String?
    let categoryID: ProductCategoryID
    let categoryDisplayName: String
    let iconKey: String
    let preselectionQuery: String

    init(result: ProductSearchResult, preselectionQuery: String) {
        productID = result.productID
        displayName = result.displayName
        displayLocale = result.displayLocale
        secondaryName = result.secondaryName
        categoryID = result.categoryID
        categoryDisplayName = result.categoryDisplayName
        iconKey = result.iconKey
        self.preselectionQuery = preselectionQuery
    }
}

typealias ProductAutocompleteSuggestionProvider = @Sendable (
    _ query: String,
    _ localeIdentifier: String,
    _ limit: Int
) async -> [ProductSearchResult]

typealias ProductAutocompleteSlowSearchDelay = @Sendable () async -> Void

@MainActor
final class AddProductAutocompleteViewModel: ObservableObject {
    @Published private(set) var phase: ProductSuggestionPhase = .idle
    @Published private(set) var results: [ProductSearchResult] = []
    @Published private(set) var selectedCatalogProduct: AddProductCatalogSelection?

    private let suggestionProvider: ProductAutocompleteSuggestionProvider?
    private let slowSearchDelay: ProductAutocompleteSlowSearchDelay

    private var generation = 0
    private var lastNormalizedQuery: String?
    private var lastLocaleIdentifier: String?
    private var searchTask: Task<Void, Never>?
    private var slowStatusTask: Task<Void, Never>?

    var canChangeSelection: Bool {
        selectedCatalogProduct != nil
    }

    var allowsManualProductSave: Bool {
        selectedCatalogProduct == nil
    }

    init(
        searchAvailability: ProductKnowledgeSearchAvailability,
        slowSearchDelay: @escaping ProductAutocompleteSlowSearchDelay = {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    ) {
        switch searchAvailability {
        case .available(let search):
            suggestionProvider = { query, localeIdentifier, limit in
                await search.suggestions(
                    matching: query,
                    locale: localeIdentifier,
                    limit: limit
                )
            }
        case .unavailable:
            suggestionProvider = nil
        }
        self.slowSearchDelay = slowSearchDelay
    }

    init(
        suggestionProvider: @escaping ProductAutocompleteSuggestionProvider,
        slowSearchDelay: @escaping ProductAutocompleteSlowSearchDelay = {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    ) {
        self.suggestionProvider = suggestionProvider
        self.slowSearchDelay = slowSearchDelay
    }

    func updateQuery(_ rawQuery: String, localeIdentifier: String) {
        guard selectedCatalogProduct == nil else {
            return
        }

        let normalizedQuery = ProductSearchNormalizer.normalize(rawQuery).value
        guard normalizedQuery != lastNormalizedQuery ||
                localeIdentifier != lastLocaleIdentifier else {
            return
        }

        invalidateCurrentSearch()
        lastNormalizedQuery = normalizedQuery
        lastLocaleIdentifier = localeIdentifier
        results = []

        guard !normalizedQuery.isEmpty else {
            phase = .idle
            return
        }

        guard let suggestionProvider else {
            phase = .unavailable
            return
        }

        phase = .idle
        let requestGeneration = generation

        searchTask = Task { [weak self] in
            let suggestions = await suggestionProvider(
                normalizedQuery,
                localeIdentifier,
                ProductKnowledgeSearch.defaultResultLimit
            )
            guard !Task.isCancelled else {
                return
            }

            self?.publish(
                suggestions,
                generation: requestGeneration,
                normalizedQuery: normalizedQuery,
                localeIdentifier: localeIdentifier
            )
        }

        let slowSearchDelay = slowSearchDelay
        slowStatusTask = Task { [weak self] in
            await slowSearchDelay()
            guard !Task.isCancelled else {
                return
            }

            self?.publishSlowStatus(
                generation: requestGeneration,
                normalizedQuery: normalizedQuery,
                localeIdentifier: localeIdentifier
            )
        }
    }

    @discardableResult
    func selectCatalogProduct(
        _ result: ProductSearchResult,
        preselectionQuery: String
    ) -> Bool {
        guard phase == .results, results.contains(result) else {
            return false
        }

        invalidateCurrentSearch()
        results = []
        selectedCatalogProduct = AddProductCatalogSelection(
            result: result,
            preselectionQuery: preselectionQuery
        )
        phase = .selectedCatalog
        return true
    }

    func changeCatalogSelection(localeIdentifier: String) -> String? {
        guard let selectedCatalogProduct else {
            return nil
        }

        let preselectionQuery = selectedCatalogProduct.preselectionQuery
        invalidateCurrentSearch()
        self.selectedCatalogProduct = nil
        lastNormalizedQuery = nil
        lastLocaleIdentifier = nil
        results = []
        phase = .idle
        updateQuery(
            preselectionQuery,
            localeIdentifier: localeIdentifier
        )
        return preselectionQuery
    }

    func selectedSummaryAccessibilityLabel(localeIdentifier: String) -> String? {
        guard let selectedCatalogProduct else {
            return nil
        }
        return ProductAutocompleteCopy.selectedSummaryAccessibilityLabel(
            selectedCatalogProduct,
            localeIdentifier: localeIdentifier
        )
    }

    func reset() {
        invalidateCurrentSearch()
        lastNormalizedQuery = nil
        lastLocaleIdentifier = nil
        results = []
        selectedCatalogProduct = nil
        phase = .idle
    }

    private func invalidateCurrentSearch() {
        generation &+= 1
        searchTask?.cancel()
        slowStatusTask?.cancel()
        searchTask = nil
        slowStatusTask = nil
    }

    private func publish(
        _ suggestions: [ProductSearchResult],
        generation requestGeneration: Int,
        normalizedQuery: String,
        localeIdentifier: String
    ) {
        guard requestGeneration == generation,
              normalizedQuery == lastNormalizedQuery,
              localeIdentifier == lastLocaleIdentifier else {
            return
        }

        slowStatusTask?.cancel()
        slowStatusTask = nil
        searchTask = nil
        results = Array(suggestions.prefix(ProductKnowledgeSearch.defaultResultLimit))
        phase = results.isEmpty ? .noMatch : .results
    }

    private func publishSlowStatus(
        generation requestGeneration: Int,
        normalizedQuery: String,
        localeIdentifier: String
    ) {
        guard requestGeneration == generation,
              normalizedQuery == lastNormalizedQuery,
              localeIdentifier == lastLocaleIdentifier,
              searchTask != nil else {
            return
        }

        phase = .searchingSlow
        slowStatusTask = nil
    }
}

nonisolated enum ProductAutocompleteCopy {
    static func searching(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "מחפש מוצרים…" : "Searching products…"
    }

    static func noMatch(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "לא נמצא מוצר מתאים בקטלוג" : "No catalog match"
    }

    static func unavailable(localeIdentifier: String) -> String {
        if isHebrew(localeIdentifier) {
            return "הצעות למוצרים אינן זמינות כרגע. עדיין אפשר להוסיף את המוצר ידנית."
        }
        return "Product suggestions are unavailable. You can still add this product manually."
    }

    static func selected(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "נבחר" : "Selected"
    }

    static func change(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "שינוי" : "Change"
    }

    static func changeAccessibilityLabel(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "שינוי המוצר שנבחר" : "Change selected product"
    }

    static func suggestionAccessibilityLabel(
        _ result: ProductSearchResult,
        localeIdentifier: String
    ) -> String {
        guard let secondaryName = result.secondaryName else {
            return "\(result.displayName), \(result.categoryDisplayName)"
        }

        if isHebrew(localeIdentifier) {
            return "\(result.displayName), \(result.categoryDisplayName), נמצא גם בשם \(secondaryName)"
        }
        return "\(result.displayName), \(result.categoryDisplayName), matched as \(secondaryName)"
    }

    static func selectedSummaryAccessibilityLabel(
        _ selection: AddProductCatalogSelection,
        localeIdentifier: String
    ) -> String {
        if isHebrew(localeIdentifier) {
            return "\(selection.displayName) נבחר, \(selection.categoryDisplayName)"
        }
        return "\(selection.displayName) selected, \(selection.categoryDisplayName)"
    }

    private static func isHebrew(_ localeIdentifier: String) -> Bool {
        let normalized = localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized == "he" || normalized.hasPrefix("he-")
    }
}
