import Foundation

nonisolated struct ProductCatalogCategoryMetadata: Sendable {
    let displayName: String
    let searchTerms: [String]
    let iconKey: String

    static func metadata(
        for id: String,
        subcategoryId: String? = nil
    ) -> ProductCatalogCategoryMetadata {
        let compatibilityKey = subcategoryId.flatMap {
            canonicalSubcategoryCompatibilityKeys[$0]
        }
        return values[compatibilityKey ?? id] ?? ProductCatalogCategoryMetadata(
            displayName: "ללא קטגוריה",
            searchTerms: [],
            iconKey: "product.generic"
        )
    }

    // Canonical taxonomy remains broad while the current UI presents established
    // aisle-level labels. This mapping preserves those labels and category-search
    // terms without changing the canonical product category identity.
    private static let canonicalSubcategoryCompatibilityKeys: [
        String: String
    ] = [
        "dairy.alternatives": "dairy_alternatives",
        "fruits_vegetables.fruits": "fruits",
        "fruits_vegetables.vegetables": "vegetables",
        "meat_fish.meat": "meat",
        "meat_fish.fish": "fish",
        "pantry.pasta_rice": "pasta_rice",
        "pantry.canned_food": "canned_food",
        "pantry.breakfast": "breakfast",
        "pantry.breakfast_cereal": "breakfast",
        "pantry.baking": "baking",
        "pantry.spices": "spices",
        "frozen.food": "frozen_food",
        "household.paper_products": "paper_products",
        "household.disposable_products": "disposable_products",
        "household.storage": "household_products",
        "household.waste_bags": "paper_products",
        "pets.supplies": "pet_supplies"
    ]

    private static let values: [String: ProductCatalogCategoryMetadata] = [
        "bakery": .init(
            displayName: "מאפייה",
            searchTerms: ["מאפייה", "לחמים"],
            iconKey: "product.bread"
        ),
        "dairy": .init(
            displayName: "מוצרי חלב",
            searchTerms: ["מוצרי חלב", "חלב"],
            iconKey: "product.dairy"
        ),
        "dairy_alternatives": .init(
            displayName: "תחליפי חלב",
            searchTerms: ["תחליפי חלב", "ללא חלב", "טבעוני"],
            iconKey: "product.dairy"
        ),
        "fruits_vegetables": .init(
            displayName: "פירות וירקות",
            searchTerms: ["פירות", "ירקות", "תוצרת טרייה"],
            iconKey: "product.fruit"
        ),
        "fruits": .init(
            displayName: "פירות",
            searchTerms: ["פירות", "פרי"],
            iconKey: "product.fruit"
        ),
        "vegetables": .init(
            displayName: "ירקות",
            searchTerms: ["ירקות", "ירק"],
            iconKey: "product.fruit"
        ),
        "meat": .init(
            displayName: "בשר",
            searchTerms: ["בשר", "קצבייה"],
            iconKey: "product.meat"
        ),
        "fish": .init(
            displayName: "דגים",
            searchTerms: ["דגים", "דג"],
            iconKey: "product.meat"
        ),
        "meat_fish": .init(
            displayName: "בשר ודגים",
            searchTerms: ["בשר", "דגים", "קצבייה"],
            iconKey: "product.meat"
        ),
        "frozen": .init(
            displayName: "קפואים",
            searchTerms: ["מזון קפוא", "קפואים"],
            iconKey: "product.frozen"
        ),
        "frozen_food": .init(
            displayName: "מזון קפוא",
            searchTerms: ["מזון קפוא", "קפואים"],
            iconKey: "product.frozen"
        ),
        "pantry": .init(
            displayName: "מזווה",
            searchTerms: ["מזווה", "יבשים"],
            iconKey: "product.pantry"
        ),
        "pasta_rice": .init(
            displayName: "פסטה ואורז",
            searchTerms: ["פסטה ואורז", "פסטה", "אורז"],
            iconKey: "product.pantry"
        ),
        "canned_food": .init(
            displayName: "שימורים",
            searchTerms: ["שימורים", "קופסאות שימורים"],
            iconKey: "product.pantry"
        ),
        "breakfast": .init(
            displayName: "ארוחת בוקר",
            searchTerms: ["ארוחת בוקר", "דגני בוקר"],
            iconKey: "product.pantry"
        ),
        "snacks": .init(
            displayName: "חטיפים",
            searchTerms: ["חטיפים", "ממתקים"],
            iconKey: "product.snack"
        ),
        "drinks": .init(
            displayName: "משקאות",
            searchTerms: ["משקאות", "שתייה"],
            iconKey: "product.drink"
        ),
        "baking": .init(
            displayName: "אפייה",
            searchTerms: ["אפייה", "מוצרי אפייה"],
            iconKey: "product.pantry"
        ),
        "spices": .init(
            displayName: "תבלינים",
            searchTerms: ["תבלינים", "תבלין"],
            iconKey: "product.pantry"
        ),
        "cleaning": .init(
            displayName: "ניקיון",
            searchTerms: ["ניקיון", "חומרי ניקוי"],
            iconKey: "product.cleaning"
        ),
        "paper_products": .init(
            displayName: "מוצרי נייר",
            searchTerms: ["מוצרי נייר", "נייר"],
            iconKey: "product.household"
        ),
        "household": .init(
            displayName: "מוצרי בית",
            searchTerms: ["מוצרי בית", "לבית"],
            iconKey: "product.household"
        ),
        "personal_care": .init(
            displayName: "טיפוח אישי",
            searchTerms: ["טיפוח אישי", "היגיינה"],
            iconKey: "product.personalcare"
        ),
        "pharmacy": .init(
            displayName: "פארם",
            searchTerms: ["פארם", "בית מרקחת", "בריאות"],
            iconKey: "product.pharmacy"
        ),
        "baby": .init(
            displayName: "תינוקות",
            searchTerms: ["תינוקות", "תינוק"],
            iconKey: "product.baby"
        ),
        "pet_supplies": .init(
            displayName: "ציוד לבעלי חיים",
            searchTerms: ["בעלי חיים", "חיות מחמד", "ציוד לחיות"],
            iconKey: "product.pet"
        ),
        "pets": .init(
            displayName: "בעלי חיים",
            searchTerms: ["בעלי חיים", "חיות מחמד", "ציוד לחיות"],
            iconKey: "product.pet"
        ),
        "disposable_products": .init(
            displayName: "כלים חד-פעמיים",
            searchTerms: ["חד פעמי", "כלים חד פעמיים"],
            iconKey: "product.household"
        ),
        "household_products": .init(
            displayName: "מוצרי בית",
            searchTerms: ["מוצרי בית", "לבית"],
            iconKey: "product.household"
        ),
        "apparel": .init(
            displayName: "ביגוד והנעלה",
            searchTerms: ["ביגוד", "הנעלה"],
            iconKey: "product.generic"
        ),
        "electronics": .init(
            displayName: "אלקטרוניקה",
            searchTerms: ["אלקטרוניקה", "חשמל"],
            iconKey: "product.generic"
        ),
        "home_garden": .init(
            displayName: "בית וגינה",
            searchTerms: ["בית וגינה", "כלי בית"],
            iconKey: "product.household"
        ),
        "office_school": .init(
            displayName: "משרד ובית ספר",
            searchTerms: ["משרד", "בית ספר", "כתיבה"],
            iconKey: "product.generic"
        ),
        "automotive": .init(
            displayName: "רכב",
            searchTerms: ["רכב", "מכונית"],
            iconKey: "product.generic"
        ),
        "sports_outdoors": .init(
            displayName: "ספורט וטיולים",
            searchTerms: ["ספורט", "טיולים"],
            iconKey: "product.generic"
        ),
        "toys_games": .init(
            displayName: "צעצועים ומשחקים",
            searchTerms: ["צעצועים", "משחקים"],
            iconKey: "product.generic"
        ),
        "books_media": .init(
            displayName: "ספרים ומדיה",
            searchTerms: ["ספרים", "מדיה"],
            iconKey: "product.generic"
        ),
        "uncategorized": .init(
            displayName: "ללא קטגוריה",
            searchTerms: [],
            iconKey: "product.generic"
        )
    ]
}
