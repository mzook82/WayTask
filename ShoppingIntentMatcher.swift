import CoreLocation
import Foundation

struct ShoppingStoreSuggestionRequest: Equatable {
    let itemID: UUID
    let itemName: String
    let itemCategory: String?
    let storeCategories: [ShoppingStoreCategory]
    let searchTerms: [String]
    let intentProfile: ProductIntentProfile?
}

enum ShoppingIntentGroup: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case grocery
    case electronics
    case pet
    case pharmacy
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grocery:
            return "Grocery"
        case .electronics:
            return "Electronics"
        case .pet:
            return "Pet store"
        case .pharmacy:
            return "Pharmacy"
        case .other:
            return "Other"
        }
    }

    var storeCategories: [ShoppingStoreCategory] {
        switch self {
        case .grocery:
            return [.grocery, .supermarket, .convenienceStore]
        case .electronics:
            return [.electronicsStore]
        case .pet:
            return [.petStore]
        case .pharmacy:
            return [.pharmacy]
        case .other:
            return []
        }
    }

    func matches(storeCategory: ShoppingStoreCategory) -> Bool {
        storeCategories.contains { $0.matches(storeCategory) }
    }
}

struct ShoppingIntentGroupResult {
    let group: ShoppingIntentGroup
    let items: [ShoppingItem]
    let request: ShoppingStoreSuggestionRequest

    var itemNames: [String] {
        items.map(\.name).deduplicatedCaseInsensitive()
    }
}

enum ShoppingStoreCategory: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
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

enum NormalizedProductCategory: String, Equatable, Hashable, Codable, Sendable {
    case unknown
    case groceryBaking = "grocery.baking"
    case groceryCondiment = "grocery.condiment"
    case groceryCoffee = "grocery.coffee"
    case groceryDairy = "grocery.dairy"
    case groceryBeverage = "grocery.beverage"
    case petFoodCat = "pet.food.cat"
    case petFoodDog = "pet.food.dog"
    case electronicsAccessory = "electronics.accessory"
    case pharmacyMedicine = "pharmacy.medicine"
    case householdCleaning = "household.cleaning"
}

struct ProductIntentProfile: Equatable, Sendable {
    let normalizedCategory: NormalizedProductCategory
    let intentGroup: ShoppingIntentGroup
    let confidence: Double
    let evidence: [String]
    let primaryAllowedStoreTypes: [ShoppingStoreCategory]
    let secondaryAllowedStoreTypes: [ShoppingStoreCategory]
    let fallbackStoreTypes: [ShoppingStoreCategory]
    let excludedStoreTypes: [ShoppingStoreCategory]

    var allowedStoreTypes: [ShoppingStoreCategory] {
        (primaryAllowedStoreTypes + secondaryAllowedStoreTypes + fallbackStoreTypes)
            .deduplicated()
    }

    var isUnresolved: Bool {
        normalizedCategory == .unknown || allowedStoreTypes.isEmpty
    }

    static func aggregate(
        profiles: [ProductIntentProfile],
        group: ShoppingIntentGroup,
        fallbackCategory: NormalizedProductCategory = .unknown
    ) -> ProductIntentProfile {
        let allowed = profiles.flatMap(\.allowedStoreTypes).deduplicated()
        let excluded = profiles
            .flatMap(\.excludedStoreTypes)
            .filter { excludedCategory in
                !allowed.contains { $0.matches(excludedCategory) || excludedCategory.matches($0) }
            }
            .deduplicated()
        let confidence = profiles.isEmpty
            ? 0
            : profiles.map(\.confidence).reduce(0, +) / Double(profiles.count)
        let categories = Set(profiles.map(\.normalizedCategory))
        let normalizedCategory = categories.count == 1 ? profiles.first?.normalizedCategory ?? fallbackCategory : fallbackCategory

        return ProductIntentProfile(
            normalizedCategory: normalizedCategory,
            intentGroup: group,
            confidence: confidence,
            evidence: profiles.flatMap(\.evidence).deduplicatedCaseInsensitive(),
            primaryAllowedStoreTypes: profiles.flatMap(\.primaryAllowedStoreTypes).deduplicated(),
            secondaryAllowedStoreTypes: profiles.flatMap(\.secondaryAllowedStoreTypes).deduplicated(),
            fallbackStoreTypes: profiles.flatMap(\.fallbackStoreTypes).deduplicated(),
            excludedStoreTypes: excluded
        )
    }
}

enum ShoppingDiscoveryDebugLogger {
    static func logGroups(
        context: String,
        groups: [ShoppingIntentGroupResult]
    ) {
        #if DEBUG
        print("[WayTask Discovery Pipeline] \(context)")
        print("[WayTask Discovery Pipeline] ShoppingIntentGroups created: \(groups.count)")
        for group in groups {
            let itemNames = group.itemNames.joined(separator: ", ")
            print("[WayTask Discovery Pipeline] Group: \(group.group.displayName)")
            print("[WayTask Discovery Pipeline] Items: \(itemNames.isEmpty ? "none" : itemNames)")
        }
        #endif
    }

    static func logStoreSearchRequests(
        context: String,
        groups: [ShoppingIntentGroupResult],
        requests: [(request: ShoppingStoreSuggestionRequest, itemNames: [String])]
    ) {
        #if DEBUG
        print("[WayTask Discovery Pipeline] \(context)")
        print("[WayTask Discovery Pipeline] StoreSearch requests executed: \(requests.count)")
        if requests.count > 1 && requests.count == groups.count {
            print("[WayTask Discovery Pipeline] Grouped discovery active")
        } else if groups.count > 1 && requests.count == 1 {
            print("[WayTask Discovery Pipeline] Legacy merged discovery path still active")
        } else if requests.count == 1 {
            print("[WayTask Discovery Pipeline] Grouped discovery active")
        }

        for (index, discoveryRequest) in requests.enumerated() {
            logStoreSearchRequest(
                context: context,
                index: index,
                request: discoveryRequest.request,
                itemNames: discoveryRequest.itemNames
            )
        }
        #endif
    }

    static func logStoreSearchRequest(
        context: String,
        index: Int,
        request: ShoppingStoreSuggestionRequest,
        itemNames: [String]
    ) {
        #if DEBUG
        let categoryText = request.storeCategories.map(\.rawValue).joined(separator: ", ")
        let itemText = itemNames.joined(separator: ", ")
        print("[WayTask Discovery Pipeline] StoreSearch request #\(index + 1)")
        print("[WayTask Discovery Pipeline] Requested categories: \(categoryText.isEmpty ? "none" : categoryText)")
        print("[WayTask Discovery Pipeline] Request items: \(itemText.isEmpty ? request.itemName : itemText)")
        #endif
    }
}

struct ProductIntentResolver {
    func resolve(for item: ShoppingItem) -> ProductIntentProfile {
        let terms = [
            item.name,
            item.brand,
            item.category,
            item.productType,
            item.flavor,
            item.packageSize,
            item.packageType,
            item.visibleText
        ]
        .compactMap { $0 } + item.searchKeywords
        let haystack = normalizedHaystack(from: terms)
        let tokenSet = Set(tokens(from: terms))
        let profile = resolve(haystack: haystack, tokens: tokenSet, itemName: item.name)

        #if DEBUG
        let allowed = profile.allowedStoreTypes.map(\.rawValue).joined(separator: ",")
        let excluded = profile.excludedStoreTypes.map(\.rawValue).joined(separator: ",")
        print("[WayTask Product Intent] item=\"\(item.name)\" category=\(profile.normalizedCategory.rawValue) intent=\(profile.intentGroup.rawValue) confidence=\(String(format: "%.2f", profile.confidence)) allowed=\(allowed) excluded=\(excluded) evidence=\"\(profile.evidence.joined(separator: "; "))\"")
        #endif

        return profile
    }

    private func resolve(haystack: String, tokens: Set<String>, itemName: String) -> ProductIntentProfile {
        if hasPhrase(["cat food", "kitten food", "cat treat", "cat treats"], in: haystack) ||
            (tokens.contains("cat") && foodTokensIntersect(tokens)) {
            return profile(
                category: .petFoodCat,
                group: .pet,
                confidence: 0.94,
                evidence: ["matched cat food terms"],
                primary: [.petStore],
                secondary: [.supermarket, .grocery],
                fallback: [.convenienceStore],
                excluded: [.electronicsStore, .homeImprovement, .pharmacy, .coffeeShop]
            )
        }

        if hasPhrase(["dog food", "puppy food", "dog treat", "dog treats"], in: haystack) ||
            (tokens.contains("dog") && foodTokensIntersect(tokens)) {
            return profile(
                category: .petFoodDog,
                group: .pet,
                confidence: 0.94,
                evidence: ["matched dog food terms"],
                primary: [.petStore],
                secondary: [.supermarket, .grocery],
                fallback: [.convenienceStore],
                excluded: [.electronicsStore, .homeImprovement, .pharmacy, .coffeeShop]
            )
        }

        if hasPhrase(["usb-c", "usb c", "iphone cable", "charging cable", "phone charger", "usb charger"], in: haystack) ||
            hasAnyToken(["usb", "charger", "cable", "iphone"], in: tokens) {
            return profile(
                category: .electronicsAccessory,
                group: .electronics,
                confidence: 0.92,
                evidence: ["matched electronics accessory terms"],
                primary: [.electronicsStore],
                secondary: [],
                fallback: [],
                excluded: [.grocery, .supermarket, .convenienceStore, .petStore, .pharmacy, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["medicine", "medication", "pain reliever", "cold medicine", "cough syrup"], in: haystack) ||
            hasAnyToken(["medicine", "medication", "pharmacy", "vitamin", "medical"], in: tokens) {
            return profile(
                category: .pharmacyMedicine,
                group: .pharmacy,
                confidence: 0.9,
                evidence: ["matched medicine or pharmacy terms"],
                primary: [.pharmacy],
                secondary: [],
                fallback: [.supermarket],
                excluded: [.electronicsStore, .petStore, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["baking soda", "bicarbonate soda", "sodium bicarbonate"], in: haystack) {
            return profile(
                category: .groceryBaking,
                group: .grocery,
                confidence: 0.95,
                evidence: ["matched baking soda terms"],
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .pharmacy, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["white vinegar", "apple cider vinegar", "vinegar"], in: haystack) ||
            tokens.contains("vinegar") {
            return profile(
                category: .groceryCondiment,
                group: .grocery,
                confidence: 0.93,
                evidence: ["matched vinegar terms"],
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .pharmacy, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["protein drink", "protein shake", "protein beverage"], in: haystack) ||
            (tokens.contains("protein") && (tokens.contains("drink") || tokens.contains("shake") || tokens.contains("beverage"))) {
            return profile(
                category: .groceryBeverage,
                group: .grocery,
                confidence: 0.9,
                evidence: ["matched protein drink terms"],
                primary: [.grocery, .supermarket],
                secondary: [.pharmacy, .convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .homeImprovement]
            )
        }

        if hasPhrase(["coffee beans", "ground coffee", "instant coffee", "coffee"], in: haystack) ||
            tokens.contains("coffee") {
            return profile(
                category: .groceryCoffee,
                group: .grocery,
                confidence: 0.88,
                evidence: ["matched coffee terms"],
                primary: [.grocery, .supermarket],
                secondary: [.coffeeShop, .convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .pharmacy, .homeImprovement]
            )
        }

        if hasPhrase(["milk", "whole milk", "skim milk", "oat milk", "almond milk"], in: haystack) ||
            tokens.contains("milk") {
            return profile(
                category: .groceryDairy,
                group: .grocery,
                confidence: 0.9,
                evidence: ["matched milk terms"],
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .pharmacy, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["cleaning product", "cleaning products", "laundry bleach", "bleach", "disinfectant"], in: haystack) ||
            hasAnyToken(["bleach", "cleaner", "cleaning", "disinfectant", "detergent"], in: tokens) {
            return profile(
                category: .householdCleaning,
                group: .grocery,
                confidence: 0.88,
                evidence: ["matched cleaning product terms"],
                primary: [.grocery, .supermarket],
                secondary: [.pharmacy, .homeImprovement],
                fallback: [.convenienceStore],
                excluded: [.electronicsStore, .petStore, .coffeeShop]
            )
        }

        if hasAnyToken(["grocery", "groceries", "food", "snack", "drink", "beverage", "bread", "cheese", "fruit", "vegetable", "cereal", "chocolate", "water", "juice", "soda", "cookie", "cracker", "chips", "pasta", "rice", "sauce", "yogurt", "butter", "egg", "meat", "fish", "frozen", "canned", "candy"], in: tokens) {
            return profile(
                category: .groceryBeverage,
                group: .grocery,
                confidence: 0.74,
                evidence: ["matched general grocery terms"],
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .homeImprovement]
            )
        }

        return profile(
            category: .unknown,
            group: .other,
            confidence: 0.18,
            evidence: ["no supported product intent match for \(itemName)"],
            primary: [],
            secondary: [],
            fallback: [],
            excluded: []
        )
    }

    private func profile(
        category: NormalizedProductCategory,
        group: ShoppingIntentGroup,
        confidence: Double,
        evidence: [String],
        primary: [ShoppingStoreCategory],
        secondary: [ShoppingStoreCategory],
        fallback: [ShoppingStoreCategory],
        excluded: [ShoppingStoreCategory]
    ) -> ProductIntentProfile {
        ProductIntentProfile(
            normalizedCategory: category,
            intentGroup: group,
            confidence: confidence,
            evidence: evidence,
            primaryAllowedStoreTypes: primary.deduplicated(),
            secondaryAllowedStoreTypes: secondary.deduplicated(),
            fallbackStoreTypes: fallback.deduplicated(),
            excludedStoreTypes: excluded.deduplicated()
        )
    }

    private func normalizedHaystack(from values: [String]) -> String {
        values
            .map { $0.lowercased() }
            .joined(separator: " ")
            .replacingOccurrences(of: "&", with: " and ")
    }

    private func tokens(from values: [String]) -> [String] {
        values
            .flatMap { value in
                value
                    .lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
            }
            .filter { !$0.isEmpty }
    }

    private func hasPhrase(_ phrases: [String], in haystack: String) -> Bool {
        phrases.contains { phrase in
            haystack.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func hasAnyToken(_ candidates: [String], in tokens: Set<String>) -> Bool {
        candidates.contains { tokens.contains($0) }
    }

    private func foodTokensIntersect(_ tokens: Set<String>) -> Bool {
        !tokens.intersection(["food", "treat", "treats", "kibble", "meal"]).isEmpty
    }
}

struct ProductIntentStoreEligibility {
    struct Evaluation {
        let isEligible: Bool
        let reason: String
    }

    static func evaluate(
        store: MapStore,
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> Evaluation {
        if let profile = request.intentProfile {
            return evaluate(store: store, profile: profile, itemName: request.itemName)
        }

        guard !request.storeCategories.isEmpty else {
            if store.isSavedLocation && rawItemHintMatched(store: store, itemName: request.itemName) {
                return Evaluation(isEligible: true, reason: "saved item history")
            }

            return Evaluation(isEligible: false, reason: "unknown intent has no allowed store types")
        }

        return evaluate(
            store: store,
            profile: ProductIntentProfile(
                normalizedCategory: .unknown,
                intentGroup: .other,
                confidence: 0.5,
                evidence: ["legacy request categories"],
                primaryAllowedStoreTypes: request.storeCategories,
                secondaryAllowedStoreTypes: [],
                fallbackStoreTypes: [],
                excludedStoreTypes: []
            ),
            itemName: request.itemName
        )
    }

    static func evaluate(
        store: MapStore,
        profile: ProductIntentProfile,
        itemName: String
    ) -> Evaluation {
        if store.isSavedLocation && rawItemHintMatched(store: store, itemName: itemName) {
            return Evaluation(isEligible: true, reason: "saved item history")
        }

        let allowed = profile.allowedStoreTypes
        guard !allowed.isEmpty else {
            return Evaluation(isEligible: false, reason: "unknown intent has no allowed store types")
        }

        if store.storeCategories.contains(where: { storeCategory in
            profile.excludedStoreTypes.contains { excludedCategory in
                storeCategory.matches(excludedCategory) || excludedCategory.matches(storeCategory)
            }
        }),
           !store.storeCategories.contains(where: { storeCategory in
               allowed.contains { allowedCategory in
                   storeCategory.matches(allowedCategory) || allowedCategory.matches(storeCategory)
               }
           }) {
            return Evaluation(isEligible: false, reason: "store type excluded for product intent")
        }

        if store.storeCategories.contains(where: { storeCategory in
            allowed.contains { allowedCategory in
                storeCategory.matches(allowedCategory) || allowedCategory.matches(storeCategory)
            }
        }) {
            return Evaluation(isEligible: true, reason: "store category allowed for product intent")
        }

        if titleMatchesAllowedStoreType(store.title, allowed: allowed) {
            return Evaluation(isEligible: true, reason: "store title matches allowed product intent")
        }

        return Evaluation(isEligible: false, reason: "store type not allowed for product intent")
    }

    private static func rawItemHintMatched(store: MapStore, itemName: String) -> Bool {
        store.itemNames.contains { storedItemName in
            storedItemName.localizedCaseInsensitiveContains(itemName) ||
            itemName.localizedCaseInsensitiveContains(storedItemName)
        }
    }

    private static func titleMatchesAllowedStoreType(_ title: String, allowed: [ShoppingStoreCategory]) -> Bool {
        let normalizedTitle = title.lowercased()
        return allowed.contains { category in
            titleTerms(for: category).contains { normalizedTitle.contains($0) }
        }
    }

    private static func titleTerms(for category: ShoppingStoreCategory) -> [String] {
        switch category {
        case .grocery:
            return ["grocery", "food market", "produce", "deli", "bakery", "walmart", "costco", "aldi", "kroger", "safeway", "whole foods"]
        case .supermarket:
            return ["supermarket", "hypermarket", "market", "mart", "carrefour", "lidl", "tesco", "shoprite"]
        case .convenienceStore:
            return ["convenience", "corner store", "mini market", "minimarket", "bodega"]
        case .coffeeShop:
            return ["coffee", "cafe", "café", "espresso"]
        case .petStore:
            return ["pet store", "pet supply", "pet shop", "petco", "petsmart"]
        case .electronicsStore:
            return ["electronics", "computer store", "mobile store", "phone store", "apple store", "best buy", "micro center"]
        case .homeImprovement:
            return ["hardware", "home improvement"]
        case .pharmacy:
            return ["pharmacy", "drugstore", "drug store", "chemist", "cvs", "walgreens", "rite aid"]
        case .generalStore:
            return []
        }
    }
}

enum ShoppingStoreCategoryFilter {
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

        return true
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

        return nil
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
    private let resolver = ProductIntentResolver()

    init(categoryMappings: [ShoppingStoreCategory: [String]] = ShoppingIntentMatcher.defaultCategoryMappings) {
        self.categoryMappings = categoryMappings
    }

    func suggestionRequest(for item: ShoppingItem) -> ShoppingStoreSuggestionRequest {
        let profile = resolver.resolve(for: item)
        let matchedCategories = profile.allowedStoreTypes
        let terms = searchTerms(for: item, categories: matchedCategories)

        return ShoppingStoreSuggestionRequest(
            itemID: item.id,
            itemName: item.name,
            itemCategory: item.category,
            storeCategories: matchedCategories,
            searchTerms: terms,
            intentProfile: profile
        )
    }

    func groupedIntents(for items: [ShoppingItem]) -> [ShoppingIntentGroupResult] {
        let activeItems = items.filter { !$0.isCompleted }
        let groupedItems = Dictionary(grouping: activeItems) { item in
            intentGroup(for: item)
        }

        let results: [ShoppingIntentGroupResult] = ShoppingIntentGroup.allCases.compactMap { group in
            guard let items = groupedItems[group],
                  let firstItem = items.first else {
                return nil
            }

            let request = suggestionRequest(
                for: group,
                items: items,
                fallbackItem: firstItem
            )
            return ShoppingIntentGroupResult(
                group: group,
                items: items,
                request: request
            )
        }

        return results
    }

    func intentGroup(for item: ShoppingItem) -> ShoppingIntentGroup {
        resolver.resolve(for: item).intentGroup
    }

    func intentGroup(for categories: [ShoppingStoreCategory]) -> ShoppingIntentGroup {
        if categories.contains(.electronicsStore) {
            return .electronics
        }

        if categories.contains(.petStore) {
            return .pet
        }

        if categories.contains(.pharmacy) {
            return .pharmacy
        }

        if categories.contains(where: { category in
            category == .grocery || category == .supermarket || category == .convenienceStore
        }) {
            return .grocery
        }

        return .other
    }

    func relevantItems(from items: [ShoppingItem], for store: MapStore) -> [ShoppingItem] {
        let activeItems = items.filter { !$0.isCompleted }
        guard !activeItems.isEmpty else {
            return []
        }

        return activeItems.filter { item in
            let profile = resolver.resolve(for: item)
            return ProductIntentStoreEligibility.evaluate(
                store: store,
                profile: profile,
                itemName: item.name
            ).isEligible
        }
    }

    func intentProfile(for item: ShoppingItem) -> ProductIntentProfile {
        resolver.resolve(for: item)
    }

    func aggregateProfile(for items: [ShoppingItem], fallbackGroup: ShoppingIntentGroup = .other) -> ProductIntentProfile {
        let profiles = items.map { resolver.resolve(for: $0) }
        let resolvedGroups = Set(profiles.filter { !$0.isUnresolved }.map(\.intentGroup))
        let group = resolvedGroups.count == 1 ? resolvedGroups.first ?? fallbackGroup : fallbackGroup
        return ProductIntentProfile.aggregate(profiles: profiles, group: group)
    }

    func request(for group: ShoppingIntentGroupResult) -> ShoppingStoreSuggestionRequest {
        group.request
    }

    func request(for items: [ShoppingItem], in group: ShoppingIntentGroup, fallbackID: UUID = UUID()) -> ShoppingStoreSuggestionRequest {
        suggestionRequest(
            for: group,
            items: items,
            fallbackItem: items.first,
            fallbackID: fallbackID
        )
    }

    func matchStoreCategories(for item: ShoppingItem) -> [ShoppingStoreCategory] {
        resolver.resolve(for: item).allowedStoreTypes
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

    private func suggestionRequest(
        for group: ShoppingIntentGroup,
        items: [ShoppingItem],
        fallbackItem: ShoppingItem?,
        fallbackID: UUID = UUID()
    ) -> ShoppingStoreSuggestionRequest {
        let itemNames = items.map(\.name).deduplicatedCaseInsensitive()
        let categoryText = group.displayName
        let profiles = items.map { resolver.resolve(for: $0) }
        let intentProfile = ProductIntentProfile.aggregate(profiles: profiles, group: group)
        let storeCategories = intentProfile.allowedStoreTypes
        let groupSearchTerms = items
            .flatMap { item in
                searchTerms(for: item, categories: storeCategories)
            }
            .deduplicatedCaseInsensitive()

        return ShoppingStoreSuggestionRequest(
            itemID: fallbackItem?.id ?? fallbackID,
            itemName: itemNames.first ?? categoryText,
            itemCategory: categoryText,
            storeCategories: storeCategories,
            searchTerms: groupSearchTerms.isEmpty ? itemNames : groupSearchTerms,
            intentProfile: intentProfile
        )
    }

    private func intentGroups(forStoreCategories categories: [ShoppingStoreCategory]) -> Set<ShoppingIntentGroup> {
        let groups = Set(categories.map { intentGroup(for: [$0]) })
        return groups.isEmpty ? [.other] : groups
    }

    static let defaultCategoryMappings: [ShoppingStoreCategory: [String]] = [
        .grocery: [
            "grocery", "groceries", "food", "snack", "snacks", "drink", "drinks", "beverage", "beverages",
            "milk", "bread", "cheese", "fruit", "vegetable", "vegetables", "cereal", "chocolate", "water",
            "juice", "soda", "cookie", "cookies", "cracker", "crackers", "chips", "pasta", "rice", "sauce",
            "yogurt", "butter", "egg", "eggs", "meat", "fish", "frozen", "canned", "candy",
            "baking", "baking soda", "coffee", "protein", "protein drink"
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
            "pet", "dog", "cat", "cat food", "dog food", "pet food", "animal", "litter"
        ],
        .electronicsStore: [
            "electronics", "phone", "iphone", "usb", "usb-c", "charger", "cable", "battery", "headphones", "computer", "laptop", "camera"
        ],
        .homeImprovement: [
            "home improvement", "hardware", "tools", "paint", "garden", "repair", "household"
        ],
        .pharmacy: [
            "health", "medicine", "pharmacy", "vitamin", "care", "soap", "shampoo", "toothpaste", "baby", "medical"
        ]
    ]
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
    }
}

private extension Array where Element == ShoppingStoreCategory {
    func deduplicated() -> [ShoppingStoreCategory] {
        reduce(into: [ShoppingStoreCategory]()) { result, category in
            if !result.contains(category) {
                result.append(category)
            }
        }
    }
}
