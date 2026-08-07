import CoreLocation
import Foundation

struct ShoppingStoreSuggestionRequest: Equatable, Sendable {
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
    case general
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
        case .general:
            return "General retail"
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
        case .general:
            return [.generalStore]
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

struct ShoppingPlanIntentGroupResult {
    let group: ShoppingIntentGroup
    let items: [ShoppingPlanInputItem]
    let request: ShoppingStoreSuggestionRequest

    var entryIDs: [ProductStateListEntryID] {
        items.map(\.identity.id)
    }

    var productIDs: [ProductStateProductID] {
        items.map(\.identity.productID)
    }

    var itemNames: [String] {
        items.map(\.displayName).deduplicatedCaseInsensitive()
    }
}

struct ShoppingPlanIntentClassification {
    let groups: [ShoppingPlanIntentGroupResult]
    let unresolvedItems: [ShoppingPlanInputItem]

    var accountedEntryIDs: [ProductStateListEntryID] {
        (groups.flatMap(\.entryIDs) +
            unresolvedItems.map(\.identity.id)).sorted {
                $0.rawValue.uuidString < $1.rawValue.uuidString
            }
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
    case catalogGrocery = "catalog.grocery"
    case catalogElectronics = "catalog.electronics"
    case catalogPet = "catalog.pet"
    case catalogPharmacy = "catalog.pharmacy"
    case catalogGeneral = "catalog.general"
    case catalogHousehold = "catalog.household"
    case groceryBaking = "grocery.baking"
    case groceryBakery = "grocery.bakery"
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
    private let catalogResolver: ShoppingItemCatalogResolver

    init(
        catalogResolver: ShoppingItemCatalogResolver =
            ShoppingItemCatalogResolver()
    ) {
        self.catalogResolver = catalogResolver
    }

    func resolve(for item: ShoppingItem) -> ProductIntentProfile {
        if let identity = catalogResolver.resolve(item: item) {
            return resolveCanonical(identity)
        }

        if item.catalogProductID != nil {
            return profile(
                category: .unknown,
                group: .other,
                confidence: 0,
                evidence: [
                    "catalog product ID is not present in the current catalog"
                ],
                primary: [],
                secondary: [],
                fallback: [],
                excluded: []
            )
        }

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

    /// T-14 classification consumes exact Product State snapshots. Display
    /// values can inform store intent but never establish Product identity.
    func resolve(for item: ShoppingPlanInputItem) -> ProductIntentProfile {
        if let categoryID = item.catalogCategoryID {
            return resolveCanonical(
                categoryID: categoryID,
                evidence: ["exact Product State Catalog snapshot"]
            )
        }

        let terms = [item.displayName, item.brand, item.category]
            .compactMap { $0 }
        let resolved = resolve(
            haystack: normalizedHaystack(from: terms),
            tokens: Set(tokens(from: terms)),
            itemName: ""
        )
        guard resolved.isUnresolved else {
            return resolved
        }
        return profile(
            category: .unknown,
            group: .other,
            confidence: resolved.confidence,
            evidence: ["no supported exact-plan classification"],
            primary: [],
            secondary: [],
            fallback: [],
            excluded: []
        )
    }

    private func resolveCanonical(
        _ identity: ResolvedShoppingItemCatalogIdentity
    ) -> ProductIntentProfile {
        let evidence = [
            "catalog product ID \(identity.productID)",
            "catalog category ID \(identity.categoryID)",
            identity.subcategoryID.map {
                "catalog subcategory ID \($0)"
            }
        ]
        .compactMap { $0 }

        return resolveCanonical(
            categoryID: identity.categoryID,
            evidence: evidence
        )
    }

    private func resolveCanonical(
        categoryID: String,
        evidence: [String]
    ) -> ProductIntentProfile {
        switch categoryID {
        case "dairy",
             "fruits_vegetables",
             "meat_fish",
             "pantry",
             "drinks",
             "frozen",
             "snacks":
            return profile(
                category: .catalogGrocery,
                group: .grocery,
                confidence: 1,
                evidence: evidence,
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .petStore,
                    .homeImprovement
                ]
            )
        case "bakery":
            return profile(
                category: .groceryBakery,
                group: .grocery,
                confidence: 1,
                evidence: evidence,
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .petStore,
                    .pharmacy,
                    .homeImprovement,
                    .coffeeShop
                ]
            )
        case "household", "cleaning":
            return profile(
                category: .catalogHousehold,
                group: .general,
                confidence: 1,
                evidence: evidence,
                primary: [.supermarket, .grocery, .homeImprovement],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .petStore,
                    .coffeeShop
                ]
            )
        case "personal_care", "pharmacy", "baby":
            return profile(
                category: .catalogPharmacy,
                group: .pharmacy,
                confidence: 1,
                evidence: evidence,
                primary: [.pharmacy],
                secondary: [.supermarket],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .petStore,
                    .homeImprovement
                ]
            )
        case "pets":
            return profile(
                category: .catalogPet,
                group: .pet,
                confidence: 1,
                evidence: evidence,
                primary: [.petStore],
                secondary: [.supermarket, .grocery],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .pharmacy,
                    .homeImprovement
                ]
            )
        case "electronics":
            return profile(
                category: .catalogElectronics,
                group: .electronics,
                confidence: 1,
                evidence: evidence,
                primary: [.electronicsStore],
                secondary: [],
                fallback: [.generalStore],
                excluded: [
                    .grocery,
                    .supermarket,
                    .convenienceStore,
                    .petStore,
                    .pharmacy,
                    .homeImprovement
                ]
            )
        case "home_garden":
            return profile(
                category: .catalogGeneral,
                group: .general,
                confidence: 1,
                evidence: evidence,
                primary: [.homeImprovement],
                secondary: [.generalStore],
                fallback: [],
                excluded: [
                    .electronicsStore,
                    .petStore,
                    .pharmacy
                ]
            )
        default:
            return profile(
                category: .catalogGeneral,
                group: .general,
                confidence: 1,
                evidence: evidence,
                primary: [.generalStore],
                secondary: [],
                fallback: [],
                excluded: []
            )
        }
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
            hasPhrase(["קפה"], in: haystack) || tokens.contains("coffee") {
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
            hasPhrase(["חלב", "קוטג׳", "קוטג'", "קוטג"], in: haystack) ||
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

        if hasPhrase([
            "trash bags", "garbage bags", "waste bags",
            "שקיות אשפה", "שקיות זבל", "שקיות לפח"
        ], in: haystack) {
            return profile(
                category: .catalogHousehold,
                group: .general,
                confidence: 0.94,
                evidence: ["matched household waste-bag terms"],
                primary: [.supermarket, .grocery, .homeImprovement],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .coffeeShop]
            )
        }

        if hasPhrase(["bread", "loaf", "לחם"], in: haystack) {
            return profile(
                category: .groceryBakery,
                group: .grocery,
                confidence: 0.9,
                evidence: ["matched bread or bakery terms"],
                primary: [.grocery, .supermarket],
                secondary: [.convenienceStore],
                fallback: [],
                excluded: [.electronicsStore, .petStore, .pharmacy, .homeImprovement, .coffeeShop]
            )
        }

        if hasPhrase(["hazelnut spread", "chocolate spread"], in: haystack) {
            return profile(
                category: .catalogGrocery,
                group: .grocery,
                confidence: 0.9,
                evidence: ["matched pantry spread terms"],
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

enum ProductStoreCompatibility: Int, Equatable, Sendable {
    case incompatible
    case unknown
    case plausibleButUnverified
    case supported

    var isEligibleForProductCoverage: Bool {
        self == .supported || self == .plausibleButUnverified
    }
}

enum RetailStoreType: String, Equatable, Hashable, Sendable {
    case grocery
    case supermarket
    case convenience
    case bakery
    case coffeeShop
    case pharmacy
    case household
    case hardware
    case pet
    case electronics
    case fashion
    case jewelry
    case footwear
    case general
}

enum StoreRetailTypeEvidence {
    static func types(for store: MapStore) -> Set<RetailStoreType> {
        let titleTypes = types(fromTitle: store.title)
        // A specific visible business type is stronger than a generic or
        // query-inherited MapKit category. This prevents a fashion result
        // returned by a grocery query from becoming grocery evidence.
        if !titleTypes.isEmpty {
            let explicitlyIncompatible = titleTypes.intersection([
                .fashion, .jewelry, .footwear
            ])
            if !explicitlyIncompatible.isEmpty {
                return explicitlyIncompatible
            }
            return titleTypes
        }

        return Set(store.storeCategories.map { category in
            switch category {
            case .grocery: .grocery
            case .supermarket: .supermarket
            case .convenienceStore: .convenience
            case .coffeeShop: .coffeeShop
            case .petStore: .pet
            case .electronicsStore: .electronics
            case .homeImprovement: .hardware
            case .pharmacy: .pharmacy
            case .generalStore: .general
            }
        })
    }

    private static func types(fromTitle title: String) -> Set<RetailStoreType> {
        let value = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = Set<RetailStoreType>()
        if contains(value, terms: [
            "fashion", "clothing", "apparel", "boutique", "אופנה",
            "בגדים", "ביגוד"
        ]) { result.insert(.fashion) }
        if contains(value, terms: [
            "jewelry", "jewellery", "jeweler", "jeweller", "תכשיט",
            "תכשיטים", "צורפות"
        ]) { result.insert(.jewelry) }
        if contains(value, terms: [
            "footwear", "shoe store", "shoes", "נעליים", "הנעלה"
        ]) { result.insert(.footwear) }
        if contains(value, terms: [
            "bakery", "bake shop", "מאפייה", "מאפיה"
        ]) { result.insert(.bakery) }
        if contains(value, terms: [
            "supermarket", "hypermarket", "סופרמרקט", "היפרמרקט"
        ]) { result.insert(.supermarket) }
        if contains(value, terms: [
            "grocery", "food market", "מכולת"
        ]) { result.insert(.grocery) }
        if contains(value, terms: [
            "convenience", "mini market", "minimarket", "מינימרקט"
        ]) { result.insert(.convenience) }
        if contains(value, terms: [
            "coffee", "cafe", "café", "בית קפה"
        ]) { result.insert(.coffeeShop) }
        if contains(value, terms: [
            "pharmacy", "drugstore", "chemist", "בית מרקחת", "פארם"
        ]) { result.insert(.pharmacy) }
        if contains(value, terms: [
            "household", "home store", "כלי בית", "מוצרי בית"
        ]) { result.insert(.household) }
        if contains(value, terms: [
            "hardware", "home improvement", "building supplies",
            "חומרי בניין", "כלי עבודה"
        ]) { result.insert(.hardware) }
        if contains(value, terms: ["pet store", "pet shop", "חנות חיות"]) {
            result.insert(.pet)
        }
        if contains(value, terms: [
            "electronics", "computer store", "mobile store", "חשמל",
            "אלקטרוניקה"
        ]) { result.insert(.electronics) }
        return result
    }

    private static func contains(_ value: String, terms: [String]) -> Bool {
        terms.contains { value.localizedCaseInsensitiveContains($0) }
    }
}

struct ProductIntentStoreEligibility {
    struct Evaluation: Equatable {
        let compatibility: ProductStoreCompatibility
        let reason: String

        var isEligible: Bool {
            compatibility.isEligibleForProductCoverage
        }
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
                return Evaluation(compatibility: .supported, reason: "saved item history")
            }

            return Evaluation(compatibility: .unknown, reason: "unknown intent has no allowed store types")
        }

        return evaluate(
            store: store,
            profile: ProductIntentProfile(
                normalizedCategory: .catalogGeneral,
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
            return Evaluation(compatibility: .supported, reason: "saved item history")
        }

        let allowed = profile.allowedStoreTypes
        guard !profile.isUnresolved, !allowed.isEmpty else {
            return Evaluation(compatibility: .unknown, reason: "unknown intent has no allowed store types")
        }

        let observedTypes = StoreRetailTypeEvidence.types(for: store)
        guard !observedTypes.isEmpty,
              observedTypes != [.general] else {
            return Evaluation(
                compatibility: .unknown,
                reason: "store type has insufficient compatibility evidence"
            )
        }

        if observedTypes.contains(where: {
            retailType($0, isAllowedFor: profile)
        }) {
            return Evaluation(
                compatibility: .plausibleButUnverified,
                reason: "product taxonomy is compatible with observed store type"
            )
        }

        return Evaluation(
            compatibility: .incompatible,
            reason: "observed store type is incompatible with product taxonomy"
        )
    }

    private static func rawItemHintMatched(store: MapStore, itemName: String) -> Bool {
        let expected = itemName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return store.itemNames.contains { storedItemName in
            storedItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(expected) == .orderedSame
        }
    }

    private static func retailType(
        _ type: RetailStoreType,
        isAllowedFor profile: ProductIntentProfile
    ) -> Bool {
        switch type {
        case .grocery:
            return profile.allowedStoreTypes.contains(.grocery)
        case .supermarket:
            return profile.allowedStoreTypes.contains(.supermarket)
        case .convenience:
            return profile.allowedStoreTypes.contains(.convenienceStore)
        case .bakery:
            return profile.normalizedCategory == .groceryBakery
        case .coffeeShop:
            return profile.normalizedCategory == .groceryCoffee
                || profile.allowedStoreTypes.contains(.coffeeShop)
        case .pharmacy:
            return profile.allowedStoreTypes.contains(.pharmacy)
        case .household:
            return profile.normalizedCategory == .catalogHousehold
                || profile.normalizedCategory == .householdCleaning
        case .hardware:
            return profile.allowedStoreTypes.contains(.homeImprovement)
        case .pet:
            return profile.allowedStoreTypes.contains(.petStore)
        case .electronics:
            return profile.allowedStoreTypes.contains(.electronicsStore)
        case .fashion, .jewelry, .footwear, .general:
            return false
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
            "תכשיט", "תכשיטים", "צורפות",
            "florist", "flower shop", "flower", "flowers",
            "law office", "law firm", "lawyer", "attorney", "legal",
            "insurance",
            "bank", "banking", "credit union",
            "office", "real estate", "accounting", "consulting",
            "boutique", "clothing", "fashion", "shoe", "furniture",
            "אופנה", "בגדים", "ביגוד", "נעליים", "הנעלה",
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
    private let resolver: ProductIntentResolver

    init(
        categoryMappings: [ShoppingStoreCategory: [String]] =
            ShoppingIntentMatcher.defaultCategoryMappings,
        catalogProducts: [CatalogProduct]? = nil
    ) {
        self.categoryMappings = categoryMappings
        resolver = ProductIntentResolver(
            catalogResolver: ShoppingItemCatalogResolver(
                products: catalogProducts
            )
        )
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

    func suggestionRequest(
        for item: ShoppingPlanInputItem
    ) -> ShoppingStoreSuggestionRequest {
        let profile = resolver.resolve(for: item)
        let categories = profile.allowedStoreTypes
        return ShoppingStoreSuggestionRequest(
            itemID: item.identity.productID.rawValue,
            itemName: item.displayName,
            itemCategory: item.category,
            storeCategories: categories,
            searchTerms: planSearchTerms(
                for: item,
                categories: categories
            ),
            intentProfile: profile
        )
    }

    func classify(
        _ authority: ShoppingPlanInputAuthority
    ) -> ShoppingPlanIntentClassification {
        let ordered = authority.items.sorted(by: planItemLessThan)
        let profiles = Dictionary(
            uniqueKeysWithValues: ordered.map {
                ($0.identity.id, resolver.resolve(for: $0))
            }
        )
        let resolved = ordered.filter {
            profiles[$0.identity.id]?.isUnresolved == false
        }
        let unresolved = ordered.filter {
            profiles[$0.identity.id]?.isUnresolved != false
        }
        let grouped = Dictionary(grouping: resolved) {
            profiles[$0.identity.id]?.intentGroup ?? .other
        }
        let groups: [ShoppingPlanIntentGroupResult] =
            ShoppingIntentGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else {
                return nil
            }
            let itemProfiles = items.compactMap {
                profiles[$0.identity.id]
            }
            let aggregate = ProductIntentProfile.aggregate(
                profiles: itemProfiles,
                group: group
            )
            let names = items.map(\.displayName)
                .deduplicatedCaseInsensitive()
            let terms = items.flatMap {
                planSearchTerms(
                    for: $0,
                    categories: aggregate.allowedStoreTypes
                )
            }.deduplicatedCaseInsensitive().sorted()
            let first = items[0]
            return ShoppingPlanIntentGroupResult(
                group: group,
                items: items,
                request: ShoppingStoreSuggestionRequest(
                    itemID: first.identity.productID.rawValue,
                    itemName: names.first ?? group.displayName,
                    itemCategory: group.displayName,
                    storeCategories: aggregate.allowedStoreTypes,
                    searchTerms: terms.isEmpty ? names : terms,
                    intentProfile: aggregate
                )
            )
        }
        return ShoppingPlanIntentClassification(
            groups: groups,
            unresolvedItems: unresolved
        )
    }

    func relevantPlanItems(
        from items: [ShoppingPlanInputItem],
        for store: MapStore
    ) -> [ShoppingPlanInputItem] {
        items.sorted(by: planItemLessThan).filter { item in
            let profile = resolver.resolve(for: item)
            guard !profile.isUnresolved else { return false }
            return ProductIntentStoreEligibility.evaluate(
                store: store,
                profile: profile,
                itemName: item.displayName
            ).isEligible
        }
    }

    func intentProfile(
        for item: ShoppingPlanInputItem
    ) -> ProductIntentProfile {
        resolver.resolve(for: item)
    }

    func compatibility(
        of item: ShoppingPlanInputItem,
        with store: MapStore
    ) -> ProductIntentStoreEligibility.Evaluation {
        ProductIntentStoreEligibility.evaluate(
            store: store,
            profile: resolver.resolve(for: item),
            itemName: item.displayName
        )
    }

    func resolutionIntents(
        for items: [ShoppingPlanInputItem],
        sourceListID: ProductStateListID,
        sourceRevision: ProductStateListRevision
    ) -> [StoreResolutionIntent] {
        let eligible = items.filter {
            !resolver.resolve(for: $0).isUnresolved
        }
        let grouped = Dictionary(grouping: eligible) { item in
            resolver.resolve(for: item).allowedStoreTypes
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
        }
        return grouped.keys.sorted().compactMap { key in
            guard let group = grouped[key], !group.isEmpty else { return nil }
            let categories = group
                .flatMap { resolver.resolve(for: $0).allowedStoreTypes }
                .deduplicated()
            guard !categories.isEmpty else { return nil }
            return StoreResolutionIntent(
                itemNames: group.map(\.displayName),
                storeCategories: categories,
                sourceListID: sourceListID,
                sourceRevision: sourceRevision,
                entryIDs: group.map(\.identity.id),
                productIDs: group.map(\.identity.productID)
            )
        }
    }

    func groupedIntents(for items: [ShoppingItem]) -> [ShoppingIntentGroupResult] {
        let activeItems = items.filter {
            !$0.isCompleted && !resolver.resolve(for: $0).isUnresolved
        }
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

        if categories.contains(
            where: { $0 == .generalStore || $0 == .homeImprovement }
        ) {
            return .general
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
            guard !profile.isUnresolved else {
                return false
            }

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

    func eligibleItems(from items: [ShoppingItem]) -> [ShoppingItem] {
        items.filter {
            !$0.isCompleted && !resolver.resolve(for: $0).isUnresolved
        }
    }

    func unresolvedItems(from items: [ShoppingItem]) -> [ShoppingItem] {
        items.filter {
            !$0.isCompleted && resolver.resolve(for: $0).isUnresolved
        }
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
        let eligibleItems = eligibleItems(from: items)
        return suggestionRequest(
            for: group,
            items: eligibleItems,
            fallbackItem: eligibleItems.first,
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

    private func planSearchTerms(
        for item: ShoppingPlanInputItem,
        categories: [ShoppingStoreCategory]
    ) -> [String] {
        ([item.displayName, item.brand, item.category].compactMap { $0 } +
            categories.map(\.displayName))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .deduplicatedCaseInsensitive()
            .sorted()
    }

    private func planItemLessThan(
        _ lhs: ShoppingPlanInputItem,
        _ rhs: ShoppingPlanInputItem
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.identity.id.rawValue.uuidString <
            rhs.identity.id.rawValue.uuidString
    }

    private func suggestionRequest(
        for group: ShoppingIntentGroup,
        items: [ShoppingItem],
        fallbackItem: ShoppingItem?,
        fallbackID: UUID = UUID()
    ) -> ShoppingStoreSuggestionRequest {
        let eligibleItems = items.filter {
            !resolver.resolve(for: $0).isUnresolved
        }
        let itemNames = eligibleItems.map(\.name)
            .deduplicatedCaseInsensitive()
        let categoryText = group.displayName
        let profiles = eligibleItems.map {
            resolver.resolve(for: $0)
        }
        let intentProfile = ProductIntentProfile.aggregate(profiles: profiles, group: group)
        let storeCategories = intentProfile.allowedStoreTypes
        let groupSearchTerms = eligibleItems
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

enum ShoppingMissionProductStateAdapter {
    static func neededItems(
        from entries: [ProductStateListEntryProjection]
    ) -> [ShoppingPlanInputItem] {
        entries.compactMap { entry in
            guard case .needed = entry.state,
                  entry.issues.isEmpty,
                  let product = entry.product,
                  product.libraryLifecycle == .active else {
                return nil
            }
            return ShoppingPlanInputItem(
                identity: entry.identity,
                quantity: entry.quantity,
                unitRawValue: entry.unitRawValue,
                sortOrder: entry.sortOrder,
                displayName: product.displayName,
                brand: product.brand,
                category: product.category,
                catalogID: product.catalogID,
                catalogCategoryID: product.catalogCategoryIDSnapshot,
                productLifecycle: product.libraryLifecycle
            )
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.identity.id.rawValue.uuidString
                < $1.identity.id.rawValue.uuidString
        }
    }
}

struct ShoppingMissionStoreRecommendation {
    let store: MapStore
    let matchedItems: [ShoppingPlanInputItem]
    let compatibilityScore: Int
    let dataQualityScore: Int
    let distanceMeters: CLLocationDistance
}

enum ShoppingMissionRecommendationAuthority {
    static func recommendations(
        stores: [MapStore],
        items: [ShoppingPlanInputItem],
        userCoordinate: CLLocationCoordinate2D?
    ) -> [ShoppingMissionStoreRecommendation] {
        let matcher = ShoppingIntentMatcher()
        return stores.compactMap { store in
            let matches = items.compactMap { item -> (
                ShoppingPlanInputItem,
                ProductIntentStoreEligibility.Evaluation
            )? in
                let evaluation = matcher.compatibility(of: item, with: store)
                guard evaluation.isEligible else { return nil }
                return (item, evaluation)
            }
            guard !matches.isEmpty else { return nil }

            let names = matches.map { $0.0.displayName }
                .deduplicatedCaseInsensitive()
            let compatibleStore = MapStore(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: store.radius,
                itemNames: names,
                completedItemNames: store.completedItemNames,
                isOpen: store.isOpen,
                rating: store.rating,
                storeCategories: store.storeCategories,
                queryEvidenceCategories: store.queryEvidenceCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
            let compatibility = matches.reduce(0) { partial, match in
                partial + match.1.compatibility.rawValue
            }
            let observedTypes = StoreRetailTypeEvidence.types(for: store)
            let dataQuality = observedTypes.isEmpty || observedTypes == [.general]
                ? 0 : 1
            return ShoppingMissionStoreRecommendation(
                store: compatibleStore,
                matchedItems: matches.map { $0.0 },
                compatibilityScore: compatibility,
                dataQualityScore: dataQuality,
                distanceMeters: distance(
                    from: userCoordinate,
                    to: store.coordinate
                )
            )
        }
        .sorted(by: recommendationPrecedes)
    }

    nonisolated private static func recommendationPrecedes(
        _ lhs: ShoppingMissionStoreRecommendation,
        _ rhs: ShoppingMissionStoreRecommendation
    ) -> Bool {
        if lhs.matchedItems.count != rhs.matchedItems.count {
            return lhs.matchedItems.count > rhs.matchedItems.count
        }
        if lhs.compatibilityScore != rhs.compatibilityScore {
            return lhs.compatibilityScore > rhs.compatibilityScore
        }
        if lhs.dataQualityScore != rhs.dataQualityScore {
            return lhs.dataQualityScore > rhs.dataQualityScore
        }
        let lhsOpen = openSortValue(lhs.store.isOpen)
        let rhsOpen = openSortValue(rhs.store.isOpen)
        if lhsOpen != rhsOpen { return lhsOpen > rhsOpen }
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        if lhs.store.title != rhs.store.title {
            return lhs.store.title.localizedStandardCompare(rhs.store.title)
                == .orderedAscending
        }
        return lhs.store.id.uuidString < rhs.store.id.uuidString
    }

    nonisolated private static func openSortValue(_ value: Bool?) -> Int {
        switch value {
        case true: 2
        case nil: 1
        case false: 0
        }
    }

    private static func distance(
        from origin: CLLocationCoordinate2D?,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        guard let origin else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            ))
    }
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
