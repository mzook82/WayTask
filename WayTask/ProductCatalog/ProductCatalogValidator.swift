import Foundation

nonisolated struct ProductCatalogValidator: Sendable {
    private static let supportedLocale = "he-IL"

    let taxonomy: ProductCatalogTaxonomyRegistry

    func validate(_ document: ProductCatalogDocument) throws {
        try validateTaxonomy()
        try validateMetadata(document)
        try validateProducts(document)
    }

    private func validateMetadata(
        _ document: ProductCatalogDocument
    ) throws {
        guard document.catalogVersion > 0 else {
            throw ProductCatalogError.invalidCatalogVersion(
                document.catalogVersion
            )
        }
        guard document.locale == Self.supportedLocale else {
            throw ProductCatalogError.invalidLocale(document.locale)
        }

        switch document.sourceFormat {
        case .legacyV2:
            guard document.schemaVersion == nil,
                  document.taxonomyVersion == nil else {
                throw ProductCatalogError.invalidLegacyMetadata
            }
        case .canonicalV1:
            guard document.schemaVersion ==
                    ProductCatalogCompatibilityDecoder.canonicalSchemaVersion
            else {
                throw ProductCatalogError.unsupportedSchemaVersion(
                    document.schemaVersion ?? -1
                )
            }
            guard document.taxonomyVersion == taxonomy.taxonomyVersion else {
                throw ProductCatalogError.incompatibleTaxonomyVersion(
                    catalog: document.taxonomyVersion ?? -1,
                    registry: taxonomy.taxonomyVersion
                )
            }
        }
    }

    private func validateTaxonomy() throws {
        guard taxonomy.taxonomyVersion > 0 else {
            throw ProductCatalogError.invalidTaxonomyVersion(
                taxonomy.taxonomyVersion
            )
        }
        guard taxonomy.locale == Self.supportedLocale else {
            throw ProductCatalogError.invalidTaxonomyLocale(taxonomy.locale)
        }

        var categoryIDs: Set<String> = []
        var subcategoryIDs: Set<String> = []
        for category in taxonomy.categories {
            guard Self.isStableID(category.id) else {
                throw ProductCatalogError.invalidTaxonomyRecordID(
                    kind: "category",
                    id: category.id
                )
            }
            guard categoryIDs.insert(category.id).inserted else {
                throw ProductCatalogError.duplicateTaxonomyRecordID(
                    kind: "category",
                    id: category.id
                )
            }
            try Self.requireNonemptyTaxonomy(
                category.canonicalName,
                kind: "category",
                id: category.id,
                field: "canonicalName"
            )
            try validateHebrewName(
                category.localizedNames,
                kind: "category",
                id: category.id
            )

            for subcategory in category.subcategories {
                guard Self.isStableSubcategoryID(subcategory.id) else {
                    throw ProductCatalogError.invalidTaxonomyRecordID(
                        kind: "subcategory",
                        id: subcategory.id
                    )
                }
                guard subcategoryIDs.insert(subcategory.id).inserted else {
                    throw ProductCatalogError.duplicateTaxonomyRecordID(
                        kind: "subcategory",
                        id: subcategory.id
                    )
                }
                guard subcategory.parentCategoryId == category.id else {
                    throw ProductCatalogError.taxonomySubcategoryParentMismatch(
                        subcategoryID: subcategory.id,
                        declaredParentID: subcategory.parentCategoryId,
                        containingCategoryID: category.id
                    )
                }
                try Self.requireNonemptyTaxonomy(
                    subcategory.canonicalName,
                    kind: "subcategory",
                    id: subcategory.id,
                    field: "canonicalName"
                )
                try validateHebrewName(
                    subcategory.localizedNames,
                    kind: "subcategory",
                    id: subcategory.id
                )
            }
        }

        var legacyIDs: Set<String> = []
        for mapping in taxonomy.compatibilityMappings {
            guard Self.isStableID(mapping.legacyCategoryId) else {
                throw ProductCatalogError.invalidTaxonomyRecordID(
                    kind: "legacy category mapping",
                    id: mapping.legacyCategoryId
                )
            }
            guard legacyIDs.insert(mapping.legacyCategoryId).inserted else {
                throw ProductCatalogError.duplicateTaxonomyRecordID(
                    kind: "legacy category mapping",
                    id: mapping.legacyCategoryId
                )
            }
            guard categoryIDs.contains(mapping.canonicalCategoryId) else {
                throw ProductCatalogError.orphanCompatibilityCategory(
                    legacyCategoryID: mapping.legacyCategoryId,
                    canonicalCategoryID: mapping.canonicalCategoryId
                )
            }
            if let subcategoryID = mapping.canonicalSubcategoryId {
                guard let subcategory = taxonomy.subcategory(
                    id: subcategoryID
                ) else {
                    throw ProductCatalogError.orphanCompatibilitySubcategory(
                        legacyCategoryID: mapping.legacyCategoryId,
                        canonicalSubcategoryID: subcategoryID
                    )
                }
                guard subcategory.parentCategoryId ==
                        mapping.canonicalCategoryId else {
                    throw ProductCatalogError.compatibilityParentMismatch(
                        legacyCategoryID: mapping.legacyCategoryId,
                        canonicalCategoryID: mapping.canonicalCategoryId,
                        canonicalSubcategoryID: subcategoryID
                    )
                }
            }
        }
    }

    private func validateProducts(
        _ document: ProductCatalogDocument
    ) throws {
        var productsByID: [String: CatalogProduct] = [:]
        var canonicalNames: [String: String] = [:]

        for product in document.products {
            guard productsByID[product.id] == nil else {
                throw ProductCatalogError.duplicateProductID(product.id)
            }
            productsByID[product.id] = product

            guard Self.isStableID(product.id) else {
                throw ProductCatalogError.invalidProductID(product.id)
            }
            try Self.requireNonempty(
                product.canonicalName,
                field: "canonicalName",
                productID: product.id
            )
            try Self.requireNonempty(
                product.categoryId,
                field: "categoryId",
                productID: product.id
            )
            try validateTextValues(
                product.aliases,
                field: "aliases",
                productID: product.id,
                enforcesNormalizedUniqueness:
                    document.sourceFormat == .canonicalV1
            )
            try validateTextValues(
                product.keywords,
                field: "keywords",
                productID: product.id,
                enforcesNormalizedUniqueness:
                    document.sourceFormat == .canonicalV1
            )
            try validateTextValues(
                product.brandTerms,
                field: "brandTerms",
                productID: product.id,
                enforcesNormalizedUniqueness:
                    document.sourceFormat == .canonicalV1
            )
            try validateTextValues(
                product.legacyNames,
                field: "legacyNames",
                productID: product.id,
                enforcesNormalizedUniqueness: true
            )
            guard (0...100).contains(product.popularityScore) else {
                throw ProductCatalogError.invalidPopularityScore(
                    productID: product.id,
                    score: product.popularityScore
                )
            }

            try validateTaxonomyAssignment(
                product,
                sourceFormat: document.sourceFormat
            )

            let normalizedName = HebrewProductSearchNormalizer
                .normalize(product.canonicalName)
                .value
            if let existingID = canonicalNames[normalizedName] {
                throw ProductCatalogError.duplicateCanonicalName(
                    normalizedName: normalizedName,
                    productIDs: [existingID, product.id].sorted()
                )
            }
            canonicalNames[normalizedName] = product.id
        }

        let activeAliases = try validateAliases(
            document.products,
            activeCanonicalNames: canonicalNames.filter {
                productsByID[$0.value]?.isActive == true
            },
            sourceFormat: document.sourceFormat
        )
        try validateBrandTerms(
            document.products,
            activeCanonicalNames: canonicalNames.filter {
                productsByID[$0.value]?.isActive == true
            },
            activeAliases: activeAliases
        )
        try validateReplacements(
            document.products,
            productsByID: productsByID,
            catalogVersion: document.catalogVersion
        )
    }

    private func validateTaxonomyAssignment(
        _ product: CatalogProduct,
        sourceFormat: ProductCatalogSourceFormat
    ) throws {
        switch sourceFormat {
        case .legacyV2:
            guard product.subcategoryId == nil else {
                throw ProductCatalogError.legacySubcategoryNotSupported(
                    productID: product.id,
                    subcategoryID: product.subcategoryId ?? ""
                )
            }
            guard taxonomy.compatibilityMapping(
                legacyCategoryId: product.categoryId
            ) != nil else {
                throw ProductCatalogError.invalidCategoryReference(
                    productID: product.id,
                    categoryID: product.categoryId,
                    sourceFormat: sourceFormat.rawValue
                )
            }
        case .canonicalV1:
            guard taxonomy.category(id: product.categoryId) != nil else {
                throw ProductCatalogError.invalidCategoryReference(
                    productID: product.id,
                    categoryID: product.categoryId,
                    sourceFormat: sourceFormat.rawValue
                )
            }
            guard let subcategoryID = product.subcategoryId else {
                return
            }
            guard let subcategory = taxonomy.subcategory(
                id: subcategoryID
            ) else {
                throw ProductCatalogError.invalidSubcategoryReference(
                    productID: product.id,
                    subcategoryID: subcategoryID
                )
            }
            guard subcategory.parentCategoryId == product.categoryId else {
                throw ProductCatalogError.subcategoryParentMismatch(
                    productID: product.id,
                    categoryID: product.categoryId,
                    subcategoryID: subcategoryID,
                    expectedParentID: subcategory.parentCategoryId
                )
            }
        }
    }

    private func validateAliases(
        _ products: [CatalogProduct],
        activeCanonicalNames: [String: String],
        sourceFormat: ProductCatalogSourceFormat
    ) throws -> [String: String] {
        var aliasesByNormalizedValue: [String: (String, String)] = [:]

        for product in products where product.isActive {
            let ownCanonicalName = HebrewProductSearchNormalizer
                .normalize(product.canonicalName)
                .value
            for alias in product.aliases {
                let normalizedAlias = HebrewProductSearchNormalizer
                    .normalize(alias)
                    .value

                if sourceFormat == .canonicalV1,
                   normalizedAlias == ownCanonicalName {
                    throw ProductCatalogError.duplicateNormalizedValue(
                        productID: product.id,
                        field: "aliases",
                        normalizedValue: normalizedAlias
                    )
                }

                if let canonicalOwner = activeCanonicalNames[normalizedAlias],
                   canonicalOwner != product.id {
                    throw ProductCatalogError.aliasMatchesCanonicalName(
                        alias: alias,
                        aliasProductID: product.id,
                        canonicalProductID: canonicalOwner
                    )
                }

                if let existing = aliasesByNormalizedValue[normalizedAlias],
                   existing.0 != product.id {
                    throw ProductCatalogError.aliasSharedByProducts(
                        normalizedAlias: normalizedAlias,
                        productIDs: [existing.0, product.id].sorted(),
                        aliases: [existing.1, alias].sorted()
                    )
                }
                aliasesByNormalizedValue[normalizedAlias] =
                    (product.id, alias)
            }
        }
        return aliasesByNormalizedValue.mapValues { $0.0 }
    }

    private func validateBrandTerms(
        _ products: [CatalogProduct],
        activeCanonicalNames: [String: String],
        activeAliases: [String: String]
    ) throws {
        for product in products where product.isActive {
            for brandTerm in product.brandTerms {
                let normalizedBrandTerm = HebrewProductSearchNormalizer
                    .normalize(brandTerm)
                    .value
                if let canonicalProductID =
                    activeCanonicalNames[normalizedBrandTerm] {
                    throw ProductCatalogError
                        .brandTermMatchesCanonicalName(
                            brandTerm: brandTerm,
                            brandProductID: product.id,
                            canonicalProductID: canonicalProductID
                        )
                }
                if let aliasProductID = activeAliases[normalizedBrandTerm] {
                    throw ProductCatalogError.brandTermMatchesAlias(
                        brandTerm: brandTerm,
                        brandProductID: product.id,
                        aliasProductID: aliasProductID
                    )
                }
            }
        }
    }

    private func validateReplacements(
        _ products: [CatalogProduct],
        productsByID: [String: CatalogProduct],
        catalogVersion: Int
    ) throws {
        for product in products {
            if product.isActive, product.replacementProductId != nil {
                throw ProductCatalogError.activeProductHasReplacement(
                    productID: product.id
                )
            }
            if product.isActive,
               product.deprecatedSinceCatalogVersion != nil {
                throw ProductCatalogError.activeProductIsDeprecated(
                    productID: product.id
                )
            }
            if let deprecatedVersion =
                product.deprecatedSinceCatalogVersion,
               !(1...catalogVersion).contains(deprecatedVersion) {
                throw ProductCatalogError.invalidDeprecationVersion(
                    productID: product.id,
                    deprecatedVersion: deprecatedVersion,
                    catalogVersion: catalogVersion
                )
            }

            guard let replacementID = product.replacementProductId else {
                continue
            }
            guard replacementID != product.id else {
                throw ProductCatalogError.replacementLoop(
                    productIDs: [product.id, product.id]
                )
            }
            guard productsByID[replacementID] != nil else {
                throw ProductCatalogError.replacementTargetMissing(
                    productID: product.id,
                    replacementProductID: replacementID
                )
            }
        }

        for product in products where product.replacementProductId != nil {
            var path: [String] = []
            var seen: [String: Int] = [:]
            var currentID: String? = product.id

            while let id = currentID,
                  let current = productsByID[id] {
                if let cycleStart = seen[id] {
                    let cycle = Array(path[cycleStart...]) + [id]
                    throw ProductCatalogError.replacementLoop(
                        productIDs: cycle
                    )
                }
                seen[id] = path.count
                path.append(id)
                currentID = current.replacementProductId
            }
        }

        for product in products {
            guard let replacementID = product.replacementProductId,
                  let replacement = productsByID[replacementID] else {
                continue
            }
            guard replacement.isActive else {
                throw ProductCatalogError.replacementTargetInactive(
                    productID: product.id,
                    replacementProductID: replacementID
                )
            }
        }
    }

    private func validateTextValues(
        _ values: [String],
        field: String,
        productID: String,
        enforcesNormalizedUniqueness: Bool
    ) throws {
        var normalizedValues: Set<String> = []
        for value in values {
            try Self.requireNonempty(
                value,
                field: field,
                productID: productID
            )
            guard enforcesNormalizedUniqueness else {
                continue
            }
            let normalized = HebrewProductSearchNormalizer.normalize(value).value
            guard normalizedValues.insert(normalized).inserted else {
                throw ProductCatalogError.duplicateNormalizedValue(
                    productID: productID,
                    field: field,
                    normalizedValue: normalized
                )
            }
        }
    }

    private func validateHebrewName(
        _ localizedNames: [String: String],
        kind: String,
        id: String
    ) throws {
        guard let hebrewName = localizedNames[Self.supportedLocale] else {
            throw ProductCatalogError.missingTaxonomyHebrewName(
                kind: kind,
                id: id,
                locale: Self.supportedLocale
            )
        }
        try Self.requireNonemptyTaxonomy(
            hebrewName,
            kind: kind,
            id: id,
            field: "localizedNames.\(Self.supportedLocale)"
        )
    }

    private static func requireNonempty(
        _ value: String,
        field: String,
        productID: String
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw ProductCatalogError.emptyRequiredField(
                productID: productID,
                field: field
            )
        }
    }

    private static func requireNonemptyTaxonomy(
        _ value: String,
        kind: String,
        id: String,
        field: String
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw ProductCatalogError.emptyTaxonomyField(
                kind: kind,
                id: id,
                field: field
            )
        }
    }

    private static func isStableID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first,
              (0x61...0x7A).contains(first.value) else {
            return false
        }
        return id.unicodeScalars.allSatisfy {
            (0x61...0x7A).contains($0.value)
                || (0x30...0x39).contains($0.value)
                || $0.value == 0x5F
        }
    }

    private static func isStableSubcategoryID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2
            && parts.allSatisfy { isStableID(String($0)) }
    }
}
