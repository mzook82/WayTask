import CoreLocation
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
    case convenienceStore
    case coffeeShop
    case petStore
    case electronicsStore
    case homeImprovement
    case pharmacy
    case generalStore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grocery:
            return "Grocery"
        case .supermarket:
            return "Supermarkets"
        case .convenienceStore:
            return "Convenience Stores"
        case .coffeeShop:
            return "Coffee Shops"
        case .petStore:
            return "Pet Stores"
        case .electronicsStore:
            return "Electronics Stores"
        case .homeImprovement:
            return "Home Improvement"
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
        case .convenienceStore:
            return "Convenience Store"
        case .coffeeShop:
            return "Coffee"
        case .petStore:
            return "Pet Store"
        case .electronicsStore:
            return "Electronics"
        case .homeImprovement:
            return "Home Improvement"
        case .pharmacy:
            return "Pharmacy"
        case .generalStore:
            return "General Store"
        }
    }

    func matches(_ other: ShoppingStoreCategory) -> Bool {
        self == other ||
        (self == .grocery && other == .supermarket) ||
        (self == .supermarket && other == .grocery) ||
        (self == .grocery && other == .convenienceStore) ||
        (self == .convenienceStore && other == .grocery)
    }

    var sampleStoreName: String {
        switch self {
        case .grocery:
            return "Grocery Store"
        case .supermarket:
            return "Nearby Supermarket"
        case .convenienceStore:
            return "Convenience Store"
        case .coffeeShop:
            return "Local Coffee Shop"
        case .petStore:
            return "Pet Supply Store"
        case .electronicsStore:
            return "Electronics Store"
        case .homeImprovement:
            return "Home Improvement Store"
        case .pharmacy:
            return "Nearby Pharmacy"
        case .generalStore:
            return "Nearby Store"
        }
    }
}

enum ShoppingStoreCategoryFilter {
    static let groceryPracticalDistance: CLLocationDistance = 5_000

    static func shouldExclude(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory] = [],
        pointOfInterestCategory: String? = nil,
        for requestedCategories: [ShoppingStoreCategory]
    ) -> Bool {
        guard isGroceryProductRequest(requestedCategories) else {
            return false
        }

        if explicitGroceryRejectionReason(
            storeTitle: storeTitle,
            pointOfInterestCategory: pointOfInterestCategory
        ) != nil {
            return true
        }

        return !isAllowedGroceryStore(
            storeTitle: storeTitle,
            storeCategories: storeCategories,
            requestedCategories: requestedCategories
        )
    }

    static func isEligible(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory],
        requestedCategories: [ShoppingStoreCategory],
        distanceMeters: CLLocationDistance? = nil
    ) -> Bool {
        guard !shouldExclude(
            storeTitle: storeTitle,
            storeCategories: storeCategories,
            for: requestedCategories
        ) else {
            return false
        }

        guard isGroceryProductRequest(requestedCategories),
              let distanceMeters else {
            return true
        }

        return distanceMeters <= groceryPracticalDistance
    }

    static func isGroceryProductRequest(_ storeCategories: [ShoppingStoreCategory]) -> Bool {
        storeCategories.contains { category in
            category == .grocery || category == .supermarket || category == .convenienceStore
        }
    }

    static func isAllowedGroceryStore(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory],
        requestedCategories: [ShoppingStoreCategory]
    ) -> Bool {
        let title = storeTitle.lowercased()
        let allowedTitleTerms = [
            "grocery", "supermarket", "market", "mini market", "minimarket",
            "convenience", "corner store", "bodega", "deli",
            "bakery", "bake shop", "bread",
            "coffee", "cafe", "café",
            "candy", "sweets", "chocolate",
            "food", "snack", "drink", "beverage", "juice", "produce"
        ]

        if allowedTitleTerms.contains(where: { title.contains($0) }) {
            return true
        }

        if storeCategories.contains(where: { category in
            category != .generalStore && requestedCategories.contains(category)
        }) {
            return true
        }

        if storeCategories.contains(where: { $0 == .grocery || $0 == .supermarket || $0 == .convenienceStore }) {
            return true
        }

        if storeCategories.contains(.coffeeShop) {
            return requestedCategories.contains(.coffeeShop)
        }

        if storeCategories.contains(.pharmacy) {
            return requestedCategories.contains(.pharmacy)
        }

        if title.contains("pharmacy") || title.contains("drugstore") {
            return requestedCategories.contains(.pharmacy)
        }

        return false
    }

    static func mapKitGroceryRejectionReason(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory],
        pointOfInterestCategory: String?,
        requestedCategories: [ShoppingStoreCategory],
        distanceMeters: CLLocationDistance?
    ) -> String? {
        guard isGroceryProductRequest(requestedCategories) else {
            return shouldExclude(
                storeTitle: storeTitle,
                storeCategories: storeCategories,
                pointOfInterestCategory: pointOfInterestCategory,
                for: requestedCategories
            ) ? "filtered by category" : nil
        }

        if let explicitReason = explicitGroceryRejectionReason(
            storeTitle: storeTitle,
            pointOfInterestCategory: pointOfInterestCategory
        ) {
            return explicitReason
        }

        if let distanceMeters, distanceMeters > groceryPracticalDistance {
            return "outside grocery distance cap (\(Int(distanceMeters))m)"
        }

        if !isAllowedGroceryStore(
            storeTitle: storeTitle,
            storeCategories: storeCategories,
            requestedCategories: requestedCategories
        ) {
            return "not an allowed grocery store"
        }

        return nil
    }

    static func rejectionReason(
        storeTitle: String,
        storeCategories: [ShoppingStoreCategory],
        requestedCategories: [ShoppingStoreCategory],
        distanceMeters: CLLocationDistance? = nil
    ) -> String? {
        if shouldExclude(
            storeTitle: storeTitle,
            storeCategories: storeCategories,
            for: requestedCategories
        ) {
            return isGroceryProductRequest(requestedCategories)
                ? "not an allowed grocery store"
                : "filtered by category"
        }

        if isGroceryProductRequest(requestedCategories),
           let distanceMeters,
           distanceMeters > groceryPracticalDistance {
            return "outside grocery distance cap (\(Int(distanceMeters))m)"
        }

        return nil
    }

    static func isWithinPracticalDistance(
        from userCoordinate: CLLocationCoordinate2D?,
        to storeCoordinate: CLLocationCoordinate2D,
        requestedCategories: [ShoppingStoreCategory]
    ) -> Bool {
        guard isGroceryProductRequest(requestedCategories),
              let userCoordinate else {
            return true
        }

        let distance = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude))
        return distance <= groceryPracticalDistance
    }

    private static func explicitGroceryRejectionReason(
        storeTitle: String,
        pointOfInterestCategory: String?
    ) -> String? {
        let title = storeTitle.lowercased()
        let poiCategory = pointOfInterestCategory?.lowercased() ?? ""
        let excludedTerms = [
            "jewelry", "jewellery", "jeweler", "jeweller",
            "florist", "flower shop", "flower", "flowers",
            "law office", "law firm", "lawyer", "attorney", "legal",
            "insurance",
            "bank", "banking", "credit union",
            "office", "real estate", "accounting", "consulting",
            "boutique", "clothing", "fashion", "shoe", "furniture",
            "salon", "beauty", "repair shop", "auto", "car dealer"
        ]

        let titleTokens = Set(title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        guard let matchedTerm = excludedTerms.first(where: { term in
            let normalizedPOITerm = term.replacingOccurrences(of: " ", with: "")
            if poiCategory.contains(normalizedPOITerm) {
                return true
            }

            if term.contains(" ") {
                return title.contains(term)
            }

            return titleTokens.contains(term)
        }) else {
            return nil
        }

        return "explicit grocery reject term: \(matchedTerm)"
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
        let productTerms = [
            item.name,
            item.brand,
            item.category,
            item.productType,
            item.flavor,
            item.packageSize
        ]
        .compactMap { $0 }

        let haystack = (productTerms + item.searchKeywords)
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

        terms.append(contentsOf: [
            item.productType,
            item.flavor,
            item.packageSize
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        terms.append(contentsOf: item.searchKeywords)
        terms.append(contentsOf: categories.map(\.displayName))
        return Array(Set(terms)).sorted()
    }

    static let defaultCategoryMappings: [ShoppingStoreCategory: [String]] = [
        .grocery: [
            "grocery", "groceries", "food", "snack", "snacks", "drink", "drinks", "beverage", "beverages",
            "milk", "bread", "cheese", "fruit", "vegetable", "vegetables", "cereal", "chocolate", "water",
            "juice", "soda", "cookie", "cookies", "cracker", "crackers", "chips", "pasta", "rice", "sauce",
            "yogurt", "butter", "egg", "eggs", "meat", "fish", "frozen", "canned", "candy"
        ],
        .supermarket: [
            "supermarket", "market"
        ],
        .convenienceStore: [
            "convenience", "corner store", "mini market"
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
        .homeImprovement: [
            "home improvement", "hardware", "tools", "paint", "garden", "repair", "household"
        ],
        .pharmacy: [
            "health", "medicine", "pharmacy", "vitamin", "care", "soap", "shampoo", "toothpaste", "baby", "medical"
        ]
    ]
}
