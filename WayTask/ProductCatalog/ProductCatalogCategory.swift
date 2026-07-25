import Foundation

nonisolated struct ProductCatalogCategoryMetadata: Sendable {
    let displayName: String
    let searchTerms: [String]
    let iconKey: String

    static func metadata(for id: String) -> ProductCatalogCategoryMetadata {
        values[id] ?? ProductCatalogCategoryMetadata(
            displayName: "ללא קטגוריה",
            searchTerms: [],
            iconKey: "product.generic"
        )
    }

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
        "disposable_products": .init(
            displayName: "כלים חד-פעמיים",
            searchTerms: ["חד פעמי", "כלים חד פעמיים"],
            iconKey: "product.household"
        ),
        "household_products": .init(
            displayName: "מוצרי בית",
            searchTerms: ["מוצרי בית", "לבית"],
            iconKey: "product.household"
        )
    ]
}
