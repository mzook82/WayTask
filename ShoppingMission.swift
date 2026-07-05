import Foundation

enum ShoppingMission: String, CaseIterable, Codable, Identifiable, Sendable {
    case buyGroceries
    case buyHouseholdItems
    case findNearbyStore
    case completeShoppingList
    case discoverProducts
    case comparePrices
    case buyGift
    case cookRecipe
    case exploreNearby

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .buyGroceries:
            return "Shop for Groceries"
        case .buyHouseholdItems:
            return "Shop for Household Items"
        case .findNearbyStore:
            return "Find Nearby Store"
        case .completeShoppingList:
            return "Complete Shopping List"
        case .discoverProducts:
            return "Discover Products"
        case .comparePrices:
            return "Compare Prices"
        case .buyGift:
            return "Find Gift"
        case .cookRecipe:
            return "Cook Recipe"
        case .exploreNearby:
            return "Explore Nearby"
        }
    }
}
