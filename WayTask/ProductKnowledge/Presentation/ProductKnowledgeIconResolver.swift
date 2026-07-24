nonisolated enum ProductKnowledgeIconResolver {
    static let fallbackSystemName = "shippingbox.fill"

    static func systemName(for semanticKey: String) -> String {
        switch semanticKey {
        case "product.dairy":
            return "drop.fill"
        case "product.bread":
            return "birthday.cake.fill"
        case "product.fruit":
            return "carrot.fill"
        case "product.meat":
            return "fork.knife"
        case "product.pantry":
            return "shippingbox.fill"
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
            return "figure.stand"
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
}
