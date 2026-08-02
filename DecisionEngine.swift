import Foundation

enum DecisionOutcome: String, Codable, Equatable, Sendable {
    case noRecommendationAvailable
    case nearbyStoresAvailable
    case shoppingListItemsNearby
    case contextInsufficient
}

struct DecisionResult: Codable, Equatable, Sendable {
    let outcome: DecisionOutcome
    let mission: ShoppingMission
    let message: String
    let relatedStoreIDs: [UUID]
    let relatedItemIDs: [UUID]
    let relatedProductIDs: [UUID]
    let excludedEntryIDs: [UUID]
    let unresolvedEntryIDs: [UUID]
    let sourceListID: UUID?
    let sourceListRevision: UInt64?
    let inputFingerprint: String?

    init(
        outcome: DecisionOutcome,
        mission: ShoppingMission,
        message: String,
        relatedStoreIDs: [UUID] = [],
        relatedItemIDs: [UUID] = [],
        relatedProductIDs: [UUID] = [],
        excludedEntryIDs: [UUID] = [],
        unresolvedEntryIDs: [UUID] = [],
        sourceListID: UUID? = nil,
        sourceListRevision: UInt64? = nil,
        inputFingerprint: String? = nil
    ) {
        self.outcome = outcome
        self.mission = mission
        self.message = message
        self.relatedStoreIDs = relatedStoreIDs
        self.relatedItemIDs = relatedItemIDs
        self.relatedProductIDs = relatedProductIDs
        self.excludedEntryIDs = excludedEntryIDs
        self.unresolvedEntryIDs = unresolvedEntryIDs
        self.sourceListID = sourceListID
        self.sourceListRevision = sourceListRevision
        self.inputFingerprint = inputFingerprint
    }
}

protocol DecisionEngineServicing {
    func evaluate(mission: ShoppingMission, context: ShoppingContext) -> DecisionResult
}

struct DecisionEngine: DecisionEngineServicing {
    func evaluate(mission: ShoppingMission, context: ShoppingContext) -> DecisionResult {
        if context.authority == .exactPlanInput {
            return evaluateExactPlan(mission: mission, context: context)
        }

        guard context.hasLocationSignal || context.hasActiveShoppingItems || context.hasNearbyStores else {
            return DecisionResult(
                outcome: .contextInsufficient,
                mission: mission,
                message: "More shopping context is needed before making a recommendation."
            )
        }

        let storesWithMatchingItems = context.nearbyStores.filter { !$0.matchingItemNames.isEmpty }

        if context.hasActiveShoppingItems && !storesWithMatchingItems.isEmpty {
            return DecisionResult(
                outcome: .shoppingListItemsNearby,
                mission: mission,
                message: "Shopping list items are available near relevant stores.",
                relatedStoreIDs: storesWithMatchingItems.map(\.id),
                relatedItemIDs: context.activeShoppingListItems.filter { !$0.isCompleted }.map(\.id)
            )
        }

        if context.hasNearbyStores {
            return DecisionResult(
                outcome: .nearbyStoresAvailable,
                mission: mission,
                message: "Nearby stores are available for this mission.",
                relatedStoreIDs: context.nearbyStores.map(\.id)
            )
        }

        return DecisionResult(
            outcome: .noRecommendationAvailable,
            mission: mission,
            message: "No recommendation is available yet."
        )
    }

    private func evaluateExactPlan(
        mission: ShoppingMission,
        context: ShoppingContext
    ) -> DecisionResult {
        let stores = context.nearbyStores.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let matchingStores = stores.filter {
            !$0.matchingItemNames.isEmpty
        }
        let items = context.activeShoppingListItems.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let common = (
            entryIDs: items.compactMap(\.entryID),
            productIDs: items.compactMap(\.productID),
            excludedIDs: context.explicitExclusions.map(\.entryID),
            unresolvedIDs: context.unresolvedEntries.map(\.entryID)
        )

        let outcome: DecisionOutcome
        let message: String
        let relatedStores: [UUID]
        if !items.isEmpty && !matchingStores.isEmpty {
            outcome = .shoppingListItemsNearby
            message = "Published evidence estimates relevant nearby stores. Availability is not verified."
            relatedStores = matchingStores.map(\.id)
        } else if !stores.isEmpty {
            outcome = .nearbyStoresAvailable
            message = "Nearby stores are available as decision support; item availability is not verified."
            relatedStores = stores.map(\.id)
        } else if items.isEmpty && context.currentLocation == nil {
            outcome = .contextInsufficient
            message = "The exact Plan input has no usable store-decision context."
            relatedStores = []
        } else {
            outcome = .noRecommendationAvailable
            message = "No estimated store recommendation is available for this Plan input."
            relatedStores = []
        }

        return DecisionResult(
            outcome: outcome,
            mission: mission,
            message: message,
            relatedStoreIDs: relatedStores,
            relatedItemIDs: common.entryIDs,
            relatedProductIDs: common.productIDs,
            excludedEntryIDs: common.excludedIDs,
            unresolvedEntryIDs: common.unresolvedIDs,
            sourceListID: context.sourceListID,
            sourceListRevision: context.sourceListRevision,
            inputFingerprint: context.inputFingerprint
        )
    }
}
