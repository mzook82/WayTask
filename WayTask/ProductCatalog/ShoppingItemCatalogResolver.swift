import Foundation

nonisolated struct ResolvedShoppingItemCatalogIdentity:
    Equatable,
    Sendable
{
    let productID: String
    let categoryID: String
    let subcategoryID: String?
    let canonicalName: String
}

nonisolated struct ShoppingItemCatalogResolver: Sendable {
    // ProductKnowledge was the first catalog shipped by WayTask. Its stable
    // product IDs predate the current ProductCatalog ID namespace. This explicit
    // crosswalk is intentionally ID-only: custom and text-only products are
    // never inferred from their names.
    private static let legacyProductIDCompatibilityMap: [String: String] = [
        "prd_pilot_0001": "milk_3_percent",
        "prd_pilot_0002": "bread_white",
        "prd_pilot_0003": "eggs",
        "prd_pilot_0004": "rice_white",
        "prd_pilot_0005": "apple",
        "prd_pilot_0006": "tomato",
        "prd_pilot_0007": "mineral_water",
        "prd_pilot_0008": "instant_coffee",
        "prd_pilot_0009": "shampoo",
        "prd_pilot_0010": "toothpaste",
        "prd_pilot_0011": "dog_food",
        "prd_pilot_0012": "baby_wipes",
        "prd_pilot_0013": "dish_liquid",
        "prd_pilot_0014": "paper_towels",
        "prd_pilot_0015": "frozen_mixed_vegetables"
    ]

    private static let bundledProductsByID: [String: CatalogProduct] = {
        Dictionary(
            uniqueKeysWithValues:
                ProductCatalogService()
                    .loadProductsOrEmpty()
                    .map { ($0.id, $0) }
        )
    }()

    private let productsByID: [String: CatalogProduct]

    init(products: [CatalogProduct]? = nil) {
        if let products {
            productsByID = Dictionary(
                uniqueKeysWithValues: products.map { ($0.id, $0) }
            )
        } else {
            productsByID = Self.bundledProductsByID
        }
    }

    func resolve(
        productIDRawValue: String?
    ) -> ResolvedShoppingItemCatalogIdentity? {
        guard let sourceProductID = normalizedIdentifier(productIDRawValue)
        else {
            return nil
        }
        let currentProductID =
            Self.legacyProductIDCompatibilityMap[sourceProductID] ??
            sourceProductID
        guard let product = productsByID[currentProductID] else {
            return nil
        }

        return ResolvedShoppingItemCatalogIdentity(
            productID: product.id,
            categoryID: product.categoryId,
            subcategoryID: product.subcategoryId,
            canonicalName: product.canonicalName
        )
    }

    func resolve(
        item: ShoppingItem
    ) -> ResolvedShoppingItemCatalogIdentity? {
        resolve(productIDRawValue: item.catalogProductIDRawValue)
    }

    func iconKey(productIDRawValue: String?) -> String? {
        guard let identity = resolve(productIDRawValue: productIDRawValue)
        else {
            return nil
        }

        return ProductCatalogCategoryMetadata.metadata(
            for: identity.categoryID,
            subcategoryId: identity.subcategoryID
        ).iconKey
    }

    func iconKey(for product: Product) -> String? {
        iconKey(productIDRawValue: product.catalogProductIDRawValue)
    }

    func iconKey(for item: ShoppingItem) -> String? {
        iconKey(productIDRawValue: item.catalogProductIDRawValue)
    }

    func currentCategoryMetadata(
        for identity: ResolvedShoppingItemCatalogIdentity
    ) -> ProductCatalogCategoryMetadata {
        ProductCatalogCategoryMetadata.metadata(
            for: identity.categoryID,
            subcategoryId: identity.subcategoryID
        )
    }

    @discardableResult
    func repairCanonicalMetadata(
        for product: Product,
        rewriteProductID: Bool = true,
        referenceDate: Date = Date()
    ) -> Bool {
        guard let identity = resolve(
            productIDRawValue: product.catalogProductIDRawValue
        ) else {
            return false
        }

        let metadata = currentCategoryMetadata(for: identity)
        var changed = false

        if rewriteProductID,
           product.catalogProductIDRawValue != identity.productID {
            product.catalogProductIDRawValue = identity.productID
            changed = true
        }
        if product.catalogCategoryIDSnapshotRawValue != identity.categoryID {
            product.catalogCategoryIDSnapshotRawValue = identity.categoryID
            changed = true
        }
        if product.catalogCategoryDisplayNameSnapshot != metadata.displayName {
            product.catalogCategoryDisplayNameSnapshot = metadata.displayName
            changed = true
        }
        if product.catalogIconKeySnapshot != metadata.iconKey {
            product.catalogIconKeySnapshot = metadata.iconKey
            changed = true
        }
        if product.category != metadata.displayName {
            product.category = metadata.displayName
            changed = true
        }
        if changed {
            product.catalogSnapshotUpdatedAt = referenceDate
        }

        return changed
    }

    func hydrate(_ item: ShoppingItem, from product: Product) {
        let persistedProductID = product.catalogProductID?.rawValue
        let productID: String?
        let categoryID: String?
        let subcategoryID: String?

        if let identity = resolve(productIDRawValue: persistedProductID) {
            productID = identity.productID
            categoryID = identity.categoryID
            subcategoryID = identity.subcategoryID
        } else {
            productID = persistedProductID
            categoryID = normalizedIdentifier(
                product.catalogCategoryIDSnapshotRawValue
            )
            subcategoryID = nil
        }

        if item.catalogProductIDRawValue != productID {
            item.catalogProductIDRawValue = productID
        }
        if item.catalogCategoryIDRawValue != categoryID {
            item.catalogCategoryIDRawValue = categoryID
        }
        if item.catalogSubcategoryIDRawValue != subcategoryID {
            item.catalogSubcategoryIDRawValue = subcategoryID
        }
    }

    func hydrate(
        _ items: [ShoppingItem],
        products: [Product],
        entries: [ShoppingListEntry]
    ) {
        var productsByLegacyItemID = products.reduce(
            into: [UUID: Product]()
        ) { result, product in
            if let legacyShoppingItemID =
                product.legacyShoppingItemID
            {
                result[legacyShoppingItemID] = product
            }
        }

        for entry in entries {
            guard let legacyShoppingItemID =
                    entry.legacyShoppingItemID,
                  productsByLegacyItemID[legacyShoppingItemID] == nil
            else {
                continue
            }

            if let product = entry.product ??
                products.first(where: { $0.id == entry.productID })
            {
                productsByLegacyItemID[legacyShoppingItemID] =
                    product
            }
        }

        for item in items {
            guard let product = productsByLegacyItemID[item.id] else {
                if item.catalogProductIDRawValue != nil {
                    item.catalogProductIDRawValue = nil
                }
                if item.catalogCategoryIDRawValue != nil {
                    item.catalogCategoryIDRawValue = nil
                }
                if item.catalogSubcategoryIDRawValue != nil {
                    item.catalogSubcategoryIDRawValue = nil
                }
                continue
            }

            hydrate(item, from: product)
        }
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, trimmed == value else {
            return nil
        }

        return value
    }
}
