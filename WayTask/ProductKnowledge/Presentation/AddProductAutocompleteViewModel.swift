import Combine
import Foundation

nonisolated enum ProductSuggestionPhase: Equatable, Sendable {
    case idle
    case searchingSlow
    case replacingResults
    case results
    case noMatch
    case unavailable
    case selectedCatalog
    case selectedCustom
}

nonisolated enum ProductAutocompleteStatusSlotContent: Equatable, Sendable {
    case hidden
    case searching
    case noMatch
    case unavailable
}

nonisolated struct ProductAutocompletePresentationSlots: Equatable, Sendable {
    let isActive: Bool
    let statusContent: ProductAutocompleteStatusSlotContent
    let showsResults: Bool
    let customActionName: String?

    static let empty = ProductAutocompletePresentationSlots(
        isActive: false,
        statusContent: .hidden,
        showsResults: false,
        customActionName: nil
    )
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

nonisolated struct AddProductCustomSelection: Hashable, Sendable {
    let name: String
    let preselectionQuery: String
}

nonisolated enum AddProductSelection: Hashable, Sendable {
    case catalog(AddProductCatalogSelection)
    case custom(AddProductCustomSelection)
}

typealias ProductAutocompleteSuggestionProvider = @Sendable (
    _ query: String,
    _ localeIdentifier: String,
    _ limit: Int
) async -> [ProductSearchResult]

typealias ProductAutocompleteSlowSearchDelay = @Sendable () async -> Void
typealias ProductAutocompletePersonalizationUpdater = @Sendable (
    _ history: [ProductCatalogSelectionHistory]
) async -> Void

nonisolated enum ProductAutocompleteLocaleResolver {
    static func preferredApplicationLocaleIdentifier(
        environmentLocaleIdentifier: String,
        preferredLanguages: [String]
    ) -> String {
        if let preferredLanguage = preferredLanguages.lazy
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return preferredLanguage
        }

        let environmentLocaleIdentifier = environmentLocaleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return environmentLocaleIdentifier.isEmpty
            ? "en"
            : environmentLocaleIdentifier
    }
}

@MainActor
final class AddProductAutocompleteViewModel: ObservableObject {
    @Published private(set) var phase: ProductSuggestionPhase = .idle
    @Published private(set) var results: [ProductSearchResult] = []
    @Published private(set) var selectedCatalogProduct: AddProductCatalogSelection?
    @Published private(set) var selectedCustomProduct: AddProductCustomSelection?
    @Published private(set) var rawQuery = ""
    @Published private(set) var isSavingProduct = false
    @Published private(set) var targetAcquisitionPresentationState:
        ProductAcquisitionPresentationState = .idle

    private let suggestionProvider: ProductAutocompleteSuggestionProvider?
    private let personalizationUpdater:
        ProductAutocompletePersonalizationUpdater?
    private let slowSearchDelay: ProductAutocompleteSlowSearchDelay
    private let targetAcquisitionConsumer = AddProductSaveCoordinator()

    private var generation = 0
    private var lastNormalizedQuery: String?
    private var lastLocaleIdentifier: String?
    private var searchTask: Task<Void, Never>?
    private var slowStatusTask: Task<Void, Never>?

    var canChangeSelection: Bool {
        selection != nil && !isSavingProduct
    }

    var allowsNameFieldFocus: Bool {
        selection == nil && !isSavingProduct
    }

    var presentationSlots: ProductAutocompletePresentationSlots {
        let customActionName = customProductActionName
        guard selection == nil,
              customActionName != nil ||
                !results.isEmpty ||
                phase != .idle else {
            return .empty
        }

        let statusContent: ProductAutocompleteStatusSlotContent
        switch phase {
        case .searchingSlow:
            statusContent = .searching
        case .noMatch:
            statusContent = .noMatch
        case .unavailable:
            statusContent = .unavailable
        case .idle, .replacingResults, .results, .selectedCatalog, .selectedCustom:
            statusContent = .hidden
        }

        return ProductAutocompletePresentationSlots(
            isActive: true,
            statusContent: statusContent,
            showsResults:
                !results.isEmpty &&
                (phase == .replacingResults || phase == .results),
            customActionName: customActionName
        )
    }

    var keepsSuggestionAreaVisible: Bool {
        presentationSlots.isActive
    }

    var allowsCatalogResultSelection: Bool {
        phase == .results
    }

    var allowsManualProductSave: Bool {
        selectedCustomProduct != nil && !isSavingProduct
    }

    var allowsCatalogProductSave: Bool {
        selectedCatalogProduct != nil && !isSavingProduct
    }

    var canConfirmProduct: Bool {
        selection != nil && !isSavingProduct
    }

    var selection: AddProductSelection? {
        if let selectedCatalogProduct {
            return .catalog(selectedCatalogProduct)
        }
        if let selectedCustomProduct {
            return .custom(selectedCustomProduct)
        }
        return nil
    }

    var selectedFieldValue: String? {
        if let selectedCatalogProduct {
            return selectedCatalogProduct.displayName
        }
        if let selectedCustomProduct {
            return selectedCustomProduct.name
        }
        return nil
    }

    var customProductActionName: String? {
        guard selectedCatalogProduct == nil,
              selectedCustomProduct == nil,
              !hasExactCatalogNameMatch else {
            return nil
        }

        let trimmedName = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedName.isEmpty ? nil : trimmedName
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
            personalizationUpdater = nil
        case .catalog(let search):
            suggestionProvider = { query, _, limit in
                await search.suggestions(
                    matching: query,
                    limit: limit
                )
                .map { $0.asProductSearchResult() }
            }
            personalizationUpdater = { history in
                await search.updatePersonalization(history)
            }
        case .unavailable:
            suggestionProvider = nil
            personalizationUpdater = nil
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
        personalizationUpdater = nil
        self.slowSearchDelay = slowSearchDelay
    }

    func updatePersonalization(
        _ history: [ProductCatalogSelectionHistory]
    ) {
        guard let personalizationUpdater else {
            return
        }

        Task {
            await personalizationUpdater(history)
        }
    }

    func updateQuery(_ rawQuery: String, localeIdentifier: String) {
        guard selectedCatalogProduct == nil,
              selectedCustomProduct == nil else {
            return
        }

        self.rawQuery = rawQuery
        let normalizedQuery = ProductSearchNormalizer.normalize(rawQuery).value
        guard normalizedQuery != lastNormalizedQuery ||
                localeIdentifier != lastLocaleIdentifier else {
            return
        }

        invalidateCurrentSearch()
        lastNormalizedQuery = normalizedQuery
        lastLocaleIdentifier = localeIdentifier

        guard !normalizedQuery.isEmpty else {
            results = []
            phase = .idle
            return
        }

        guard let suggestionProvider else {
            results = []
            phase = .unavailable
            return
        }

        phase = results.isEmpty ? .idle : .replacingResults
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
    func acceptTextFieldEdit(
        _ proposedValue: String,
        localeIdentifier: String
    ) -> String {
        guard let selectedFieldValue else {
            updateQuery(
                proposedValue,
                localeIdentifier: localeIdentifier
            )
            return proposedValue
        }

        // A keyboard can deliver a final marked-text or autocorrection write
        // while SwiftUI is replacing the field with the selected summary.
        // Once selection is committed, keep its exact display value authoritative.
        return selectedFieldValue
    }

    @discardableResult
    func selectCatalogProduct(
        _ result: ProductSearchResult,
        preselectionQuery: String
    ) -> Bool {
        guard allowsCatalogResultSelection,
              results.contains(result) else {
            return false
        }

        invalidateCurrentSearch()
        results = []
        selectedCustomProduct = nil
        selectedCatalogProduct = AddProductCatalogSelection(
            result: result,
            preselectionQuery: preselectionQuery
        )
        rawQuery = result.displayName
        phase = .selectedCatalog
        return true
    }

    @discardableResult
    func selectCustomProduct() -> AddProductCustomSelection? {
        guard let name = customProductActionName else {
            return nil
        }

        let selection = AddProductCustomSelection(
            name: name,
            preselectionQuery: rawQuery
        )
        invalidateCurrentSearch()
        results = []
        selectedCatalogProduct = nil
        selectedCustomProduct = selection
        phase = .selectedCustom
        return selection
    }

    func changeCatalogSelection(localeIdentifier: String) -> String? {
        guard !isSavingProduct,
              let selectedCatalogProduct else {
            return nil
        }

        return restoreEditing(
            preselectionQuery: selectedCatalogProduct.preselectionQuery,
            localeIdentifier: localeIdentifier
        )
    }

    func changeCustomProductSelection(localeIdentifier: String) -> String? {
        guard !isSavingProduct,
              let selectedCustomProduct else {
            return nil
        }

        return restoreEditing(
            preselectionQuery: selectedCustomProduct.preselectionQuery,
            localeIdentifier: localeIdentifier
        )
    }

    private func restoreEditing(
        preselectionQuery: String,
        localeIdentifier: String
    ) -> String {
        invalidateCurrentSearch()
        selectedCatalogProduct = nil
        selectedCustomProduct = nil
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

    func selectedCustomSummaryAccessibilityLabel(
        localeIdentifier: String
    ) -> String? {
        guard let selectedCustomProduct else {
            return nil
        }
        return ProductAutocompleteCopy.selectedCustomSummaryAccessibilityLabel(
            selectedCustomProduct,
            localeIdentifier: localeIdentifier
        )
    }

    func beginSavingProduct() -> AddProductSelection? {
        guard !isSavingProduct,
              let selection else {
            return nil
        }

        isSavingProduct = true
        return selection
    }

    func finishSavingProductAfterFailure() {
        isSavingProduct = false
    }

    func prepareTargetAcquisitionConfirmation(
        productID: ProductStateProductID,
        commandID: ProductStateCommandID,
        effectiveAt: Date,
        imageData: Data?,
        confirmed: Bool
    ) -> ProductAcquisitionConfirmation? {
        guard let selection else { return nil }
        let evidence: ProductAcquisitionReviewedEvidence
        switch selection {
        case let .catalog(value):
            evidence = .catalog(selection: value, imageData: imageData)
        case let .custom(value):
            evidence = .custom(selection: value, imageData: imageData)
        }
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID,
            commandID: commandID,
            effectiveAt: effectiveAt,
            evidence: evidence,
            confirmed: confirmed
        )
        targetAcquisitionPresentationState =
            .awaitingAcquisitionConfirmation(confirmation)
        return confirmation
    }

    @discardableResult
    func confirmTargetAcquisition(
        _ confirmation: ProductAcquisitionConfirmation,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductAcquisitionResult {
        let result = targetAcquisitionConsumer.confirmTargetAcquisition(
            confirmation,
            using: authority
        )
        targetAcquisitionPresentationState = .acquisitionResult(result)
        return result
    }

    func prepareTargetRestoreConfirmation(
        for result: ProductAcquisitionResult,
        commandID: ProductStateCommandID,
        historyEventID: ProductStateHistoryEventID,
        effectiveAt: Date,
        confirmed: Bool
    ) -> ProductAcquisitionRestoreConfirmation? {
        guard result.requiresExplicitRestore else { return nil }
        let confirmation = ProductAcquisitionRestoreConfirmation(
            acquisitionResult: result,
            commandID: commandID,
            historyEventID: historyEventID,
            effectiveAt: effectiveAt,
            confirmed: confirmed
        )
        targetAcquisitionPresentationState =
            .awaitingRestoreConfirmation(confirmation)
        return confirmation
    }

    @discardableResult
    func confirmTargetRestore(
        _ confirmation: ProductAcquisitionRestoreConfirmation,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductAcquisitionRestoreResult {
        let result = targetAcquisitionConsumer.confirmTargetRestore(
            confirmation,
            using: authority
        )
        targetAcquisitionPresentationState = .restoreResult(result)
        return result
    }

    func reset() {
        invalidateCurrentSearch()
        lastNormalizedQuery = nil
        lastLocaleIdentifier = nil
        results = []
        selectedCatalogProduct = nil
        selectedCustomProduct = nil
        rawQuery = ""
        isSavingProduct = false
        phase = .idle
        targetAcquisitionPresentationState = .idle
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

        phase = results.isEmpty ? .searchingSlow : .replacingResults
        slowStatusTask = nil
    }

    private var hasExactCatalogNameMatch: Bool {
        let normalizedQuery = HebrewProductSearchNormalizer.normalize(rawQuery).value
        guard !normalizedQuery.isEmpty else {
            return false
        }

        return results.contains {
            $0.matchType == .exact
                && $0.matchedRecordAuthority == .primaryDisplayName
                && HebrewProductSearchNormalizer.normalize($0.displayName).value
                    == normalizedQuery
        }
    }
}

nonisolated enum ProductAutocompleteCopy {
    static func productNameFieldLabel(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "שם המוצר" : "Product name"
    }

    static func productNamePlaceholder(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "הקלדת שם מוצר" : "Type a product name"
    }

    static func productEntryGuidance(localeIdentifier: String) -> String {
        if isHebrew(localeIdentifier) {
            return "המוצר יישמר כאן תחילה. אפשר להוסיף אותו לקניות כשמתכננים לקנות אותו."
        }
        return "Saved here first. Add products to Shopping only when you plan to buy them."
    }

    static func searching(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "מחפש מוצרים…" : "Searching products…"
    }

    static func noMatch(localeIdentifier: String) -> String {
        "לא נמצא מוצר מתאים בקטלוג"
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

    static func customProduct(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "מוצר מותאם אישית" : "Custom Product"
    }

    static func alreadyPresentTitle(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "המוצר כבר שמור" : "Already in Products"
    }

    static func alreadyPresentMessage(
        productName: String,
        localeIdentifier: String
    ) -> String {
        if isHebrew(localeIdentifier) {
            return "״\(productName)״ כבר קיים ברשימת המוצרים. המוצר הקיים נשמר ללא שינוי."
        }
        return "“\(productName)” is already in Products. Your existing product was kept unchanged."
    }

    static func acknowledge(localeIdentifier: String) -> String {
        isHebrew(localeIdentifier) ? "אישור" : "OK"
    }

    static func customProductAction(
        name: String,
        localeIdentifier: String
    ) -> String {
        "הוסף את ״\(name)״ כמוצר מותאם אישית"
    }

    static func suggestionAccessibilityLabel(
        _ result: ProductSearchResult,
        localeIdentifier: String
    ) -> String {
        guard let secondaryName = result.secondaryName else {
            return "\(result.displayName), \(result.categoryDisplayName)"
        }

        if isHebrew(localeIdentifier) {
            return "\(result.displayName), נמצא גם בשם \(secondaryName), \(result.categoryDisplayName)"
        }
        return "\(result.displayName), matched as \(secondaryName), \(result.categoryDisplayName)"
    }

    static func selectedSummaryAccessibilityLabel(
        _ selection: AddProductCatalogSelection,
        localeIdentifier: String
    ) -> String {
        let secondaryName = selection.secondaryName.flatMap {
            $0.isEmpty ? nil : $0
        }
        if isHebrew(localeIdentifier) {
            if let secondaryName {
                return "\(selection.displayName) נבחר, \(secondaryName), \(selection.categoryDisplayName)"
            }
            return "\(selection.displayName) נבחר, \(selection.categoryDisplayName)"
        }
        if let secondaryName {
            return "\(selection.displayName) selected, \(secondaryName), \(selection.categoryDisplayName)"
        }
        return "\(selection.displayName) selected, \(selection.categoryDisplayName)"
    }

    static func selectedCustomSummaryAccessibilityLabel(
        _ selection: AddProductCustomSelection,
        localeIdentifier: String
    ) -> String {
        if isHebrew(localeIdentifier) {
            return "\(selection.name) נבחר, מוצר מותאם אישית. יש ללחוץ על הוספת מוצר לאישור."
        }
        return "\(selection.name) selected, Custom Product. Add Product to confirm."
    }

    private static func isHebrew(_ localeIdentifier: String) -> Bool {
        let normalized = localeIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized == "he" || normalized.hasPrefix("he-")
    }
}
