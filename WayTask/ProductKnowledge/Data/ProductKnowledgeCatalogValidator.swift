import Foundation

nonisolated struct ProductKnowledgeCatalogValidator: Sendable {
    static let maximumRevisionOneByteCount = 100 * 1024
    static let supportedLocales = ["en", "he"]
    static let initialProductIDs = Set(
        (1...15).map { String(format: "prd_pilot_%04d", $0) }
    )

    private static let topLevelKeys: Set<String> = [
        "schemaVersion",
        "catalogRevision",
        "taxonomyVersion",
        "expectedProductCount",
        "supportedLocales",
        "categories",
        "products",
        "names"
    ]
    private static let categoryKeys: Set<String> = [
        "id",
        "names",
        "iconKey",
        "sortOrder",
        "status"
    ]
    private static let categoryNameKeys: Set<String> = ["en", "he"]
    private static let productKeys: Set<String> = [
        "id",
        "defaultNameID",
        "primaryCategoryID",
        "status"
    ]
    private static let nameKeys: Set<String> = [
        "id",
        "productID",
        "locale",
        "kind",
        "value",
        "isPreferred"
    ]

    static let taxonomyRules: [String: TaxonomyRule] = [
        "dairy": TaxonomyRule(
            en: "Dairy & Alternatives",
            he: "מוצרי חלב ותחליפים",
            iconKey: "product.dairy",
            sortOrder: 0
        ),
        "bakery": TaxonomyRule(
            en: "Bakery",
            he: "מאפייה",
            iconKey: "product.bread",
            sortOrder: 1
        ),
        "fruits_vegetables": TaxonomyRule(
            en: "Fruits & Vegetables",
            he: "פירות וירקות",
            iconKey: "product.fruit",
            sortOrder: 2
        ),
        "meat_fish": TaxonomyRule(
            en: "Meat, Fish & Alternatives",
            he: "בשר, דגים ותחליפים",
            iconKey: "product.meat",
            sortOrder: 3
        ),
        "pantry": TaxonomyRule(
            en: "Pantry",
            he: "מזווה",
            iconKey: "product.pantry",
            sortOrder: 4
        ),
        "drinks": TaxonomyRule(
            en: "Drinks",
            he: "משקאות",
            iconKey: "product.drink",
            sortOrder: 5
        ),
        "frozen": TaxonomyRule(
            en: "Frozen",
            he: "קפואים",
            iconKey: "product.frozen",
            sortOrder: 6
        ),
        "snacks": TaxonomyRule(
            en: "Snacks & Sweets",
            he: "חטיפים ומתוקים",
            iconKey: "product.snack",
            sortOrder: 7
        ),
        "household": TaxonomyRule(
            en: "Household",
            he: "מוצרי בית",
            iconKey: "product.household",
            sortOrder: 8
        ),
        "cleaning": TaxonomyRule(
            en: "Cleaning",
            he: "ניקיון",
            iconKey: "product.cleaning",
            sortOrder: 9
        ),
        "personal_care": TaxonomyRule(
            en: "Personal Care",
            he: "טיפוח אישי",
            iconKey: "product.personalcare",
            sortOrder: 10
        ),
        "pharmacy": TaxonomyRule(
            en: "Pharmacy & Health",
            he: "פארם ובריאות",
            iconKey: "product.pharmacy",
            sortOrder: 11
        ),
        "baby": TaxonomyRule(
            en: "Baby",
            he: "תינוקות",
            iconKey: "product.baby",
            sortOrder: 12
        ),
        "pets": TaxonomyRule(
            en: "Pets",
            he: "בעלי חיים",
            iconKey: "product.pet",
            sortOrder: 13
        ),
        "uncategorized": TaxonomyRule(
            en: "Uncategorized",
            he: "ללא קטגוריה",
            iconKey: "product.generic",
            sortOrder: 14
        )
    ]

    func validateRawShape(_ data: Data) throws {
        var violations: [ProductKnowledgeValidationViolation] = []

        if data.count > Self.maximumRevisionOneByteCount {
            violations.append(
                ProductKnowledgeValidationViolation(
                    code: .invalidResourceSize,
                    path: "$"
                )
            )
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProductKnowledgeError.decodingFailed
        }

        guard let root = jsonObject as? [String: Any] else {
            throw ProductKnowledgeError.validationFailed([
                ProductKnowledgeValidationViolation(
                    code: .invalidRecordShape,
                    path: "$"
                )
            ])
        }

        appendKeyViolations(
            actual: Set(root.keys),
            expected: Self.topLevelKeys,
            path: "$",
            to: &violations
        )
        validateRecords(
            root["categories"],
            path: "$.categories",
            expectedKeys: Self.categoryKeys,
            nestedNames: true,
            violations: &violations
        )
        validateRecords(
            root["products"],
            path: "$.products",
            expectedKeys: Self.productKeys,
            violations: &violations
        )
        validateRecords(
            root["names"],
            path: "$.names",
            expectedKeys: Self.nameKeys,
            violations: &violations
        )

        if !violations.isEmpty {
            throw ProductKnowledgeError.validationFailed(violations)
        }
    }

    func validate(_ catalog: ProductKnowledgeCatalog, resourceByteCount: Int? = nil) throws {
        if catalog.schemaVersion != 1 {
            throw ProductKnowledgeError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        if catalog.taxonomyVersion != "1.0" {
            throw ProductKnowledgeError.unsupportedTaxonomyVersion(catalog.taxonomyVersion)
        }

        var violations: [ProductKnowledgeValidationViolation] = []

        if let resourceByteCount,
           resourceByteCount > Self.maximumRevisionOneByteCount {
            append(.invalidResourceSize, path: "$", to: &violations)
        }
        if catalog.catalogRevision <= 0 {
            append(.invalidCatalogRevision, path: "$.catalogRevision", to: &violations)
        }
        if catalog.expectedProductCount != 15
            || catalog.products.count != catalog.expectedProductCount {
            append(.productCountMismatch, path: "$.expectedProductCount", to: &violations)
        }
        if catalog.supportedLocales != Self.supportedLocales {
            append(.unsupportedLocales, path: "$.supportedLocales", to: &violations)
        }

        validateCategories(catalog.categories, violations: &violations)
        validateProducts(
            catalog.products,
            availableCategoryIDs: Set(catalog.categories.map(\.id)),
            violations: &violations
        )
        validateNames(catalog.names, catalog: catalog, violations: &violations)

        if !violations.isEmpty {
            throw ProductKnowledgeError.validationFailed(violations)
        }
    }

    private func validateCategories(
        _ categories: [ProductKnowledgeCategoryRecord],
        violations: inout [ProductKnowledgeValidationViolation]
    ) {
        if categories.count != Self.taxonomyRules.count {
            append(.invalidCategoryCount, path: "$.categories", to: &violations)
        }

        let categoryIDs = categories.map(\.id)
        appendDuplicates(
            in: categoryIDs,
            code: .duplicateCategoryID,
            path: "$.categories",
            violations: &violations
        )

        let actualCategoryIDs = Set(categoryIDs)
        if actualCategoryIDs != Set(Self.taxonomyRules.keys) {
            append(.taxonomyMismatch, path: "$.categories", to: &violations)
        }

        appendDuplicates(
            in: categories.map(\.sortOrder),
            code: .duplicateCategorySortOrder,
            path: "$.categories",
            violations: &violations
        )

        for (index, category) in categories.enumerated() {
            let path = "$.categories[\(index)]"
            if !isValidCategoryID(category.id) {
                append(.invalidCategoryID, path: "\(path).id", id: category.id, to: &violations)
            }
            guard let rule = Self.taxonomyRules[category.id] else {
                continue
            }
            if category.names != ProductKnowledgeCategoryNamesRecord(en: rule.en, he: rule.he) {
                append(.categoryNameMismatch, path: "\(path).names", id: category.id, to: &violations)
            }
            if category.iconKey != rule.iconKey {
                append(.categoryIconMismatch, path: "\(path).iconKey", id: category.id, to: &violations)
            }
            if category.sortOrder != rule.sortOrder {
                append(
                    .categorySortOrderMismatch,
                    path: "\(path).sortOrder",
                    id: category.id,
                    to: &violations
                )
            }
            if category.status != .active {
                append(.invalidCategoryStatus, path: "\(path).status", id: category.id, to: &violations)
            }
        }
    }

    private func validateProducts(
        _ products: [ProductKnowledgeProductRecord],
        availableCategoryIDs: Set<String>,
        violations: inout [ProductKnowledgeValidationViolation]
    ) {
        let productIDs = products.map(\.id)
        appendDuplicates(
            in: productIDs,
            code: .duplicateProductID,
            path: "$.products",
            violations: &violations
        )

        if Set(productIDs) != Self.initialProductIDs {
            append(.initialProductSetMismatch, path: "$.products", to: &violations)
        }

        for (index, product) in products.enumerated() {
            let path = "$.products[\(index)]"
            if !Self.initialProductIDs.contains(product.id) {
                append(.invalidProductID, path: "\(path).id", id: product.id, to: &violations)
            }
            if !availableCategoryIDs.contains(product.primaryCategoryID) {
                append(
                    .missingCategoryReference,
                    path: "\(path).primaryCategoryID",
                    id: product.id,
                    to: &violations
                )
            }
            if product.status != .active {
                append(.invalidProductStatus, path: "\(path).status", id: product.id, to: &violations)
            }
        }
    }

    private func validateNames(
        _ names: [ProductKnowledgeNameRecord],
        catalog: ProductKnowledgeCatalog,
        violations: inout [ProductKnowledgeValidationViolation]
    ) {
        appendDuplicates(
            in: names.map(\.id),
            code: .duplicateNameID,
            path: "$.names",
            violations: &violations
        )

        let productIDs = Set(catalog.products.map(\.id))
        let supportedLocales = Set(catalog.supportedLocales)
        var seenRecords: Set<NameRecordKey> = []
        var preferredCounts: [ProductLocaleKey: Int] = [:]
        var displayValues: Set<ProductLocaleValueKey> = []
        var aliasValues: Set<ProductLocaleValueKey> = []

        for (index, name) in names.enumerated() {
            let path = "$.names[\(index)]"
            if !productIDs.contains(name.productID) {
                append(.missingProductReference, path: "\(path).productID", id: name.id, to: &violations)
            }

            let trimmedValue = name.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValue.isEmpty {
                append(.emptyNameValue, path: "\(path).value", id: name.id, to: &violations)
            } else if trimmedValue != name.value {
                append(.invalidNameWhitespace, path: "\(path).value", id: name.id, to: &violations)
            }
            if name.value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                append(
                    .disallowedControlCharacter,
                    path: "\(path).value",
                    id: name.id,
                    to: &violations
                )
            }
            if !supportedLocales.contains(name.locale) {
                append(.unsupportedNameLocale, path: "\(path).locale", id: name.id, to: &violations)
            }
            if name.kind == .alias && name.isPreferred {
                append(.preferredAlias, path: "\(path).isPreferred", id: name.id, to: &violations)
            }

            let recordKey = NameRecordKey(
                productID: name.productID,
                locale: name.locale,
                kind: name.kind,
                value: name.value
            )
            if !seenRecords.insert(recordKey).inserted {
                append(.duplicateNameRecord, path: path, id: name.id, to: &violations)
            }

            let valueKey = ProductLocaleValueKey(
                productID: name.productID,
                locale: name.locale,
                normalizedValue: normalizedComparisonValue(name.value)
            )
            if name.kind.isDisplayCapable {
                displayValues.insert(valueKey)
            } else if name.kind == .alias {
                if !aliasValues.insert(valueKey).inserted {
                    append(
                        .duplicateNormalizedAlias,
                        path: path,
                        id: name.id,
                        to: &violations
                    )
                }
            }

            if name.isPreferred && name.kind.isDisplayCapable {
                let preferredKey = ProductLocaleKey(productID: name.productID, locale: name.locale)
                preferredCounts[preferredKey, default: 0] += 1
            }
        }

        let aliasDisplayCollisions = displayValues
            .intersection(aliasValues)
            .sorted {
                ($0.productID, $0.locale, $0.normalizedValue)
                    < ($1.productID, $1.locale, $1.normalizedValue)
            }
        for duplicate in aliasDisplayCollisions {
            append(
                .aliasDisplayNameCollision,
                path: "$.names",
                id: duplicate.productID,
                to: &violations
            )
        }

        let namesByID = Dictionary(
            names.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, product) in catalog.products.enumerated() {
            let productPath = "$.products[\(index)].defaultNameID"
            if namesByID[product.defaultNameID].map({
                $0.productID == product.id
                    && $0.locale == "en"
                    && $0.kind == .canonical
                    && $0.isPreferred
            }) != true {
                append(
                    .invalidDefaultNameReference,
                    path: productPath,
                    id: product.id,
                    to: &violations
                )
            }

            for locale in Self.supportedLocales {
                let key = ProductLocaleKey(productID: product.id, locale: locale)
                let count = preferredCounts[key, default: 0]
                if count == 0 {
                    append(
                        .missingPreferredName,
                        path: "$.names",
                        id: "\(product.id):\(locale)",
                        to: &violations
                    )
                } else if count > 1 {
                    append(
                        .duplicatePreferredName,
                        path: "$.names",
                        id: "\(product.id):\(locale)",
                        to: &violations
                    )
                }
            }
        }
    }

    private func validateRecords(
        _ value: Any?,
        path: String,
        expectedKeys: Set<String>,
        nestedNames: Bool = false,
        violations: inout [ProductKnowledgeValidationViolation]
    ) {
        guard let records = value as? [Any] else {
            if value != nil {
                append(.invalidRecordShape, path: path, to: &violations)
            }
            return
        }

        for (index, value) in records.enumerated() {
            let recordPath = "\(path)[\(index)]"
            guard let record = value as? [String: Any] else {
                append(.invalidRecordShape, path: recordPath, to: &violations)
                continue
            }
            appendKeyViolations(
                actual: Set(record.keys),
                expected: expectedKeys,
                path: recordPath,
                to: &violations
            )

            if nestedNames {
                guard let names = record["names"] as? [String: Any] else {
                    if record["names"] != nil {
                        append(.invalidRecordShape, path: "\(recordPath).names", to: &violations)
                    }
                    continue
                }
                appendKeyViolations(
                    actual: Set(names.keys),
                    expected: Self.categoryNameKeys,
                    path: "\(recordPath).names",
                    to: &violations
                )
            }
        }
    }

    private func appendKeyViolations(
        actual: Set<String>,
        expected: Set<String>,
        path: String,
        to violations: inout [ProductKnowledgeValidationViolation]
    ) {
        for missing in expected.subtracting(actual).sorted() {
            append(.missingField, path: "\(path).\(missing)", to: &violations)
        }
        for unexpected in actual.subtracting(expected).sorted() {
            append(.unexpectedField, path: "\(path).\(unexpected)", to: &violations)
        }
    }

    private func appendDuplicates<Value: Hashable>(
        in values: [Value],
        code: ProductKnowledgeValidationCode,
        path: String,
        violations: inout [ProductKnowledgeValidationViolation]
    ) {
        var seen: Set<Value> = []
        var hasDuplicate = false
        for value in values where !seen.insert(value).inserted {
            hasDuplicate = true
        }
        if hasDuplicate {
            append(code, path: path, to: &violations)
        }
    }

    private func append(
        _ code: ProductKnowledgeValidationCode,
        path: String,
        id: String? = nil,
        to violations: inout [ProductKnowledgeValidationViolation]
    ) {
        violations.append(
            ProductKnowledgeValidationViolation(
                code: code,
                path: path,
                recordID: id
            )
        )
    }

    private func isValidCategoryID(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first,
              (97...122).contains(first.value) else {
            return false
        }
        return scalars.allSatisfy { scalar in
            (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar.value == 95
        }
    }

    private func normalizedComparisonValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

nonisolated extension ProductKnowledgeCatalogValidator {
    struct TaxonomyRule: Equatable, Sendable {
        let en: String
        let he: String
        let iconKey: String
        let sortOrder: Int
    }

    private struct ProductLocaleKey: Hashable {
        let productID: String
        let locale: String
    }

    private struct ProductLocaleValueKey: Hashable {
        let productID: String
        let locale: String
        let normalizedValue: String
    }

    private struct NameRecordKey: Hashable {
        let productID: String
        let locale: String
        let kind: ProductNameKind
        let value: String
    }
}
