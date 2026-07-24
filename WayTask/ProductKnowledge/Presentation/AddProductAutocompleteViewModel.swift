import Combine
import Foundation

nonisolated enum ProductSuggestionPhase: Equatable, Sendable {
    case idle
    case searchingSlow
    case results
    case noMatch
    case unavailable
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

    private let suggestionProvider: ProductAutocompleteSuggestionProvider?
    private let slowSearchDelay: ProductAutocompleteSlowSearchDelay

    private var generation = 0
    private var lastNormalizedQuery: String?
    private var lastLocaleIdentifier: String?
    private var searchTask: Task<Void, Never>?
    private var slowStatusTask: Task<Void, Never>?

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

    func reset() {
        invalidateCurrentSearch()
        lastNormalizedQuery = nil
        lastLocaleIdentifier = nil
        results = []
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

    private static func isHebrew(_ localeIdentifier: String) -> Bool {
        let normalized = localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized == "he" || normalized.hasPrefix("he-")
    }
}
