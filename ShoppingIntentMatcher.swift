import Foundation

struct ShoppingStoreSuggestionRequest: Equatable {
    let itemID: UUID
    let itemName: String
    let itemCategory: String?
    let storeCategories: [ShoppingStoreCategory]
    let searchTerms: [String]
}

enum ShoppingStoreCategory: String, CaseIterable, Identifiable, Equatable, Hashable {
    case grocery
    case supermarket
    case coffeeShop
    case petStore
    case electronicsStore
    case pharmacy
    case generalStore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grocery:
            return "Grocery"
        case .supermarket:
            return "Supermarkets"
        case .coffeeShop:
            return "Coffee Shops"
        case .petStore:
            return "Pet Stores"
        case .electronicsStore:
            return "Electronics Stores"
        case .pharmacy:
            return "Pharmacies"
        case .generalStore:
            return "Stores"
        }
    }

    var storeFormTitle: String {
        switch self {
        case .grocery:
            return "Grocery"
        case .supermarket:
            return "Supermarket"
        case .coffeeShop:
            return "Coffee"
        case .petStore:
            return "Pet Store"
        case .electronicsStore:
            return "Electronics"
        case .pharmacy:
            return "Pharmacy"
        case .generalStore:
            return "General Store"
        }
    }

    func matches(_ other: ShoppingStoreCategory) -> Bool {
        self == other ||
        (self == .grocery && other == .supermarket) ||
        (self == .supermarket && other == .grocery)
    }

    var sampleStoreName: String {
        switch self {
        case .grocery:
            return "Grocery Store"
        case .supermarket:
            return "Nearby Supermarket"
        case .coffeeShop:
            return "Local Coffee Shop"
        case .petStore:
            return "Pet Supply Store"
        case .electronicsStore:
            return "Electronics Store"
        case .pharmacy:
            return "Nearby Pharmacy"
        case .generalStore:
            return "Nearby Store"
        }
    }
}

struct ShoppingIntentMatcher {
    var categoryMappings: [ShoppingStoreCategory: [String]]

    init(categoryMappings: [ShoppingStoreCategory: [String]] = ShoppingIntentMatcher.defaultCategoryMappings) {
        self.categoryMappings = categoryMappings
    }

    func suggestionRequest(for item: ShoppingItem) -> ShoppingStoreSuggestionRequest {
        let matchedCategories = matchStoreCategories(for: item)
        let terms = searchTerms(for: item, categories: matchedCategories)

        return ShoppingStoreSuggestionRequest(
            itemID: item.id,
            itemName: item.name,
            itemCategory: item.category,
            storeCategories: matchedCategories,
            searchTerms: terms
        )
    }

    func matchStoreCategories(for item: ShoppingItem) -> [ShoppingStoreCategory] {
        let haystack = [item.name, item.brand, item.category]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let matches = categoryMappings.compactMap { category, keywords in
            keywords.contains { haystack.contains($0.lowercased()) } ? category : nil
        }

        return matches.isEmpty ? [.generalStore] : Array(Set(matches)).sorted { $0.displayName < $1.displayName }
    }

    private func searchTerms(for item: ShoppingItem, categories: [ShoppingStoreCategory]) -> [String] {
        var terms = [item.name]

        if let category = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            terms.append(category)
        }

        terms.append(contentsOf: categories.map(\.displayName))
        return Array(Set(terms)).sorted()
    }

    static let defaultCategoryMappings: [ShoppingStoreCategory: [String]] = [
        .grocery: [
            "grocery", "groceries", "food", "snack", "drink", "milk", "bread", "cheese", "fruit", "vegetable", "cereal", "chocolate", "water"
        ],
        .supermarket: [
            "supermarket", "market"
        ],
        .coffeeShop: [
            "coffee", "espresso", "latte", "cappuccino", "tea", "cafe"
        ],
        .petStore: [
            "pet", "dog", "cat", "pet food", "animal", "litter"
        ],
        .electronicsStore: [
            "electronics", "phone", "charger", "cable", "battery", "headphones", "computer", "laptop", "camera"
        ],
        .pharmacy: [
            "health", "medicine", "pharmacy", "vitamin", "care", "soap", "shampoo", "toothpaste", "baby", "medical"
        ]
    ]
}
