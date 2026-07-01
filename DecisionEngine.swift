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

    init(
        outcome: DecisionOutcome,
        mission: ShoppingMission,
        message: String,
        relatedStoreIDs: [UUID] = [],
        relatedItemIDs: [UUID] = []
    ) {
        self.outcome = outcome
        self.mission = mission
        self.message = message
        self.relatedStoreIDs = relatedStoreIDs
        self.relatedItemIDs = relatedItemIDs
    }
}

protocol DecisionEngineServicing {
    func evaluate(mission: ShoppingMission, context: ShoppingContext) -> DecisionResult
}

struct DecisionEngine: DecisionEngineServicing {
    func evaluate(mission: ShoppingMission, context: ShoppingContext) -> DecisionResult {
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
}
