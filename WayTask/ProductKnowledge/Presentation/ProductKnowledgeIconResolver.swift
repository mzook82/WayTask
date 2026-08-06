import Foundation

nonisolated enum ProductKnowledgeIconResolver {
    /// The one generic product icon used whenever category evidence is absent
    /// or unrecognized. Presentation never chooses an icon from source type.
    static let fallbackSystemName = "tag.fill"

    static func systemName(for semanticKey: String) -> String {
        switch semanticKey {
        case "product.dairy":
            return "drop.fill"
        case "product.bread":
            return "basket.fill"
        case "product.fruit":
            return "carrot.fill"
        case "product.meat":
            return "fork.knife"
        case "product.pantry":
            return "square.grid.2x2.fill"
        case "product.drink":
            return "cup.and.saucer.fill"
        case "product.frozen":
            return "snowflake"
        case "product.snack":
            return "popcorn.fill"
        case "product.household":
            return "house.fill"
        case "product.cleaning":
            return "sparkles"
        case "product.personalcare":
            return "comb.fill"
        case "product.pharmacy":
            return "cross.case.fill"
        case "product.baby":
            return "figure.child"
        case "product.pet":
            return "pawprint.fill"
        case "product.generic":
            return fallbackSystemName
        default:
            return fallbackSystemName
        }
    }

    static func systemName(forCatalogSnapshot semanticKey: String?) -> String {
        guard let semanticKey else {
            return fallbackSystemName
        }
        return systemName(for: semanticKey)
    }

    /// Resolves persisted and newly-created products through the same category
    /// path. A recognizable product type in the normalized display name wins
    /// so equivalent persisted records cannot diverge because one creation
    /// source captured a stale category snapshot. Category identity and the
    /// catalog semantic category remain the fallback authorities.
    static func systemName(
        categoryID: String?,
        categoryName: String?,
        productName: String?,
        semanticKey: String?
    ) -> String {
        if let key = resolvedSemanticKey(forNormalizedText: productName),
           key != "product.generic" {
            return systemName(for: key)
        }
        if let key = resolvedSemanticKey(forCategoryID: categoryID),
           key != "product.generic" {
            return systemName(for: key)
        }
        if let key = resolvedSemanticKey(forNormalizedText: categoryName),
           key != "product.generic" {
            return systemName(for: key)
        }
        if let semanticKey,
           semanticKey != "product.generic",
           systemName(for: semanticKey) != fallbackSystemName {
            return systemName(for: semanticKey)
        }
        return fallbackSystemName
    }

    static func systemName(for product: ProductStateProductProjection) -> String {
        systemName(
            categoryID: product.catalogCategoryIDSnapshot,
            categoryName: product.category
                ?? product.catalogCategoryDisplayNameSnapshot,
            productName: product.displayName,
            semanticKey: product.catalogIconKeySnapshot
        )
    }

    private static func resolvedSemanticKey(
        forCategoryID value: String?
    ) -> String? {
        guard let value else { return nil }
        let normalized = value.split(separator: ".").map {
            normalize(String($0))
        }.joined(separator: ".")
        let root = normalized.split(separator: ".").first.map(String.init)
        let categoryID = root ?? normalized
        let metadata = ProductCatalogCategoryMetadata.metadata(
            for: categoryID,
            subcategoryId: normalized.contains(".") ? normalized : nil
        )
        if metadata.iconKey != "product.generic" {
            return metadata.iconKey
        }
        return resolvedSemanticKey(forNormalizedCategory: categoryID)
    }

    private static func resolvedSemanticKey(
        forNormalizedText value: String?
    ) -> String? {
        guard let value else { return nil }
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return nil }
        return textRules.first { rule in
            rule.terms.contains { normalized.contains($0) }
        }?.key
    }

    private static func resolvedSemanticKey(
        forNormalizedCategory value: String
    ) -> String? {
        switch value {
        case "dairy", "milk", "dairy_alternatives": "product.dairy"
        case "bakery", "bread": "product.bread"
        case "fruits_vegetables", "fruits", "vegetables", "produce":
            "product.fruit"
        case "meat_fish", "meat", "fish": "product.meat"
        case "pantry", "pasta_rice", "canned_food", "breakfast",
             "baking", "spices": "product.pantry"
        case "drinks", "drink", "beverages": "product.drink"
        case "frozen", "frozen_food": "product.frozen"
        case "snacks", "snack": "product.snack"
        case "household", "paper_products", "disposable_products",
             "household_products", "home_garden": "product.household"
        case "cleaning": "product.cleaning"
        case "personal_care", "personalcare": "product.personalcare"
        case "pharmacy", "health": "product.pharmacy"
        case "baby": "product.baby"
        case "pets", "pet", "pet_supplies", "pet_food": "product.pet"
        case "uncategorized", "generic": "product.generic"
        default: nil
        }
    }

    private static func normalize(_ value: String) -> String {
        ProductKnowledgeNormalizer.searchText(value).value
            .replacingOccurrences(of: " ", with: "_")
    }

    private static let textRules: [(key: String, terms: [String])] = [
        ("product.pet", [
            "pet_food", "petfood", "pet_supplies", "pets", "pet_",
            "dog_food", "cat_food", "מזון_לחיות", "חיות_מחמד",
            "בעלי_חיים"
        ]),
        ("product.pharmacy", [
            "pharmacy", "medicine", "medical", "health", "פארם",
            "בית_מרקחת", "תרופה"
        ]),
        ("product.dairy", [
            "dairy", "milk", "cheese", "yogurt", "חלב", "גבינה",
            "יוגורט", "מוצרי_חלב"
        ]),
        ("product.bread", [
            "bakery", "bread", "loaf", "מאפייה", "לחם", "לחמים"
        ]),
        ("product.fruit", [
            "vegetable", "vegetables", "fruit", "produce", "ירקות",
            "ירק", "פירות", "פרי"
        ]),
        ("product.meat", [
            "meat", "fish", "poultry", "בשר", "דגים", "עוף"
        ]),
        ("product.frozen", ["frozen", "קפוא"]),
        ("product.snack", ["snack", "sweet", "חטיף", "ממתק"]),
        ("product.drink", [
            "drink", "beverage", "coffee", "משקה", "שתייה", "קפה"
        ]),
        ("product.cleaning", [
            "cleaning", "detergent", "ניקיון", "חומר_ניקוי"
        ]),
        ("product.personalcare", [
            "personal_care", "hygiene", "טיפוח", "היגיינה"
        ]),
        ("product.baby", ["baby", "infant", "תינוק"]),
        ("product.household", [
            "household", "paper_products", "disposable", "מוצרי_בית",
            "מוצרי_נייר", "חד_פעמי"
        ]),
        ("product.pantry", [
            "pantry", "pasta", "rice", "canned", "spice", "מזווה",
            "פסטה", "אורז", "שימורים", "תבלין"
        ])
    ]
}
