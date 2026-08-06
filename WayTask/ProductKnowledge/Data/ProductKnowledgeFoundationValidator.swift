import Foundation

nonisolated enum ProductKnowledgeFoundationIssueSeverity:
    String,
    Codable,
    Comparable,
    Sendable
{
    case error
    case warning

    static func < (
        lhs: ProductKnowledgeFoundationIssueSeverity,
        rhs: ProductKnowledgeFoundationIssueSeverity
    ) -> Bool {
        lhs == .error && rhs == .warning
    }
}

nonisolated enum ProductKnowledgeFoundationIssueCode:
    String,
    Codable,
    Sendable
{
    case duplicateStableID
    case missingCanonicalName
    case missingCategory
    case invalidCategory
    case duplicateLocaleNameDefinition
    case aliasCollision
    case conflictingBarcode
    case invalidLocaleCode
    case invalidNormalizedKey
    case unindexableEntry
    case indistinguishableExactIdentity
    case possibleNormalizedNameCollision
    case invalidCatalogVersion
    case invalidSemanticKey
}

nonisolated struct ProductKnowledgeFoundationIssue:
    Codable,
    Equatable,
    Sendable
{
    let severity: ProductKnowledgeFoundationIssueSeverity
    let code: ProductKnowledgeFoundationIssueCode
    let recordIDs: [String]
    let details: String
}

nonisolated struct ProductKnowledgeFoundationValidationReport:
    Codable,
    Equatable,
    Sendable
{
    let issues: [ProductKnowledgeFoundationIssue]

    var errors: [ProductKnowledgeFoundationIssue] {
        issues.filter { $0.severity == .error }
    }

    var warnings: [ProductKnowledgeFoundationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var isValid: Bool {
        errors.isEmpty
    }
}

/// Deterministic, report-only validator. It never merges, repairs, replaces,
/// or reorders source records.
nonisolated struct ProductKnowledgeFoundationValidator: Sendable {
    func validate(
        _ snapshot: ProductKnowledgeSnapshot
    ) -> ProductKnowledgeFoundationValidationReport {
        var issues: [ProductKnowledgeFoundationIssue] = []
        let categoryIDs = Set(snapshot.categories.map(\.id))
        appendDuplicateIDs(
            snapshot.categories.map { $0.id.rawValue },
            kind: "category",
            to: &issues
        )
        appendDuplicateIDs(
            snapshot.products.map { $0.id.rawValue },
            kind: "product",
            to: &issues
        )
        appendDuplicateIDs(
            snapshot.names.map { $0.id.rawValue },
            kind: "name",
            to: &issues
        )

        if let version = snapshot.metadata.catalogVersion, version <= 0 {
            append(
                .error,
                .invalidCatalogVersion,
                ids: [],
                "Catalog version must be positive.",
                to: &issues
            )
        }
        for locale in snapshot.metadata.supportedLocales
            where ProductKnowledgeNormalizer.localeIdentifier(locale) == nil {
            append(
                .error,
                .invalidLocaleCode,
                ids: [locale],
                "Catalog metadata contains an invalid supported locale.",
                to: &issues
            )
        }

        let productIDs = Set(snapshot.products.map(\.id))
        let namesByProduct = Dictionary(grouping: snapshot.names, by: \.productID)
        var displayOwners: [String: Set<ProductID>] = [:]
        var aliasOwners: [String: Set<ProductID>] = [:]
        var barcodeOwners: [String: Set<ProductID>] = [:]
        var exactIdentityOwners: [String: Set<ProductID>] = [:]
        var seenNameDefinitions: Set<NameDefinitionKey> = []

        for category in snapshot.categories {
            if !isStableID(category.id.rawValue) {
                append(
                    .error,
                    .invalidCategory,
                    ids: [category.id.rawValue],
                    "Category ID is not stable lowercase ASCII.",
                    to: &issues
                )
            }
        }

        for product in snapshot.products {
            let productNames = namesByProduct[product.id] ?? []
            if !categoryIDs.contains(product.primaryCategoryID) {
                append(
                    .error,
                    .missingCategory,
                    ids: [product.id.rawValue, product.primaryCategoryID.rawValue],
                    "Product references a category that is not in the snapshot.",
                    to: &issues
                )
            }
            if ProductKnowledgeNormalizer.searchText(product.semanticKey).value.isEmpty {
                append(
                    .error,
                    .invalidSemanticKey,
                    ids: [product.id.rawValue],
                    "Semantic identity key cannot be normalized.",
                    to: &issues
                )
            }
            if !productNames.contains(where: { $0.kind == .canonical }) {
                append(
                    .error,
                    .missingCanonicalName,
                    ids: [product.id.rawValue],
                    "Product has no canonical name record.",
                    to: &issues
                )
            }
            if !productNames.contains(where: {
                $0.kind.isDisplayCapable
                    && !ProductKnowledgeNormalizer.searchText($0.value).value.isEmpty
            }) {
                append(
                    .error,
                    .unindexableEntry,
                    ids: [product.id.rawValue],
                    "Product has no indexable display record.",
                    to: &issues
                )
            }

            for barcode in product.barcodes {
                guard let key = ProductKnowledgeNormalizer.barcode(barcode) else {
                    append(
                        .error,
                        .invalidNormalizedKey,
                        ids: [product.id.rawValue],
                        "Barcode has no valid normalized identity key.",
                        to: &issues
                    )
                    continue
                }
                barcodeOwners[key, default: []].insert(product.id)
            }

            let identityKey = exactIdentityKey(product)
            exactIdentityOwners[identityKey, default: []].insert(product.id)
        }

        for name in snapshot.names {
            if !productIDs.contains(name.productID) {
                append(
                    .error,
                    .unindexableEntry,
                    ids: [name.id.rawValue, name.productID.rawValue],
                    "Name references an unknown product.",
                    to: &issues
                )
            }
            guard let locale = ProductKnowledgeNormalizer.localeIdentifier(
                name.locale
            ) else {
                append(
                    .error,
                    .invalidLocaleCode,
                    ids: [name.id.rawValue],
                    "Name locale is not a valid BCP-47-style identifier.",
                    to: &issues
                )
                continue
            }
            let normalized = ProductKnowledgeNormalizer.searchText(
                name.value,
                localeIdentifier: locale
            ).value
            guard !normalized.isEmpty else {
                append(
                    .error,
                    .invalidNormalizedKey,
                    ids: [name.id.rawValue],
                    "Name has no searchable normalized key.",
                    to: &issues
                )
                continue
            }

            let definition = NameDefinitionKey(
                productID: name.productID,
                locale: locale.lowercased(),
                kind: name.kind,
                normalizedValue: normalized
            )
            if !seenNameDefinitions.insert(definition).inserted {
                append(
                    .warning,
                    .duplicateLocaleNameDefinition,
                    ids: [name.productID.rawValue, name.id.rawValue],
                    "Product repeats the same normalized locale/name definition.",
                    to: &issues
                )
            }

            switch name.kind {
            case .canonical, .localizedDisplay:
                displayOwners[normalized, default: []].insert(name.productID)
            case .alias:
                aliasOwners[normalized, default: []].insert(name.productID)
            case .keyword:
                break
            }
        }

        for (key, owners) in aliasOwners where owners.count > 1 {
            append(
                .error,
                .aliasCollision,
                ids: owners.map(\.rawValue).sorted(),
                "Alias key '\(key)' resolves to more than one stable product ID.",
                to: &issues
            )
        }
        for (key, aliases) in aliasOwners {
            let conflictingDisplays = (displayOwners[key] ?? []).subtracting(aliases)
            if !conflictingDisplays.isEmpty {
                append(
                    .error,
                    .aliasCollision,
                    ids: (aliases.union(conflictingDisplays))
                        .map(\.rawValue).sorted(),
                    "Alias key '\(key)' conflicts with another product display name.",
                    to: &issues
                )
            }
        }
        for (key, owners) in barcodeOwners where owners.count > 1 {
            append(
                .error,
                .conflictingBarcode,
                ids: owners.map(\.rawValue).sorted(),
                "Normalized barcode '\(key)' belongs to multiple product IDs.",
                to: &issues
            )
        }
        for (key, owners) in exactIdentityOwners where owners.count > 1 {
            append(
                .error,
                .indistinguishableExactIdentity,
                ids: owners.map(\.rawValue).sorted(),
                "Multiple records share exact semantic and variant identity '\(key)'.",
                to: &issues
            )
        }
        for (key, owners) in displayOwners where owners.count > 1 {
            append(
                .warning,
                .possibleNormalizedNameCollision,
                ids: owners.map(\.rawValue).sorted(),
                "Normalized display key '\(key)' needs human duplicate review.",
                to: &issues
            )
        }

        return ProductKnowledgeFoundationValidationReport(
            issues: issues.sorted(by: isIssueOrderedBefore)
        )
    }

    private func exactIdentityKey(_ product: ProductEntity) -> String {
        let components = [
            product.semanticKey,
            product.brand ?? "",
            product.variantDescriptors.sorted().joined(separator: "|"),
            product.packageDescriptor ?? "",
            product.unit ?? ""
        ].map { ProductKnowledgeNormalizer.searchText($0).value }
        return components.joined(separator: "\u{1F}")
    }

    private func appendDuplicateIDs(
        _ values: [String],
        kind: String,
        to issues: inout [ProductKnowledgeFoundationIssue]
    ) {
        let duplicates = Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        for value in duplicates {
            append(
                .error,
                .duplicateStableID,
                ids: [value],
                "Duplicate \(kind) stable ID.",
                to: &issues
            )
        }
    }

    private func append(
        _ severity: ProductKnowledgeFoundationIssueSeverity,
        _ code: ProductKnowledgeFoundationIssueCode,
        ids: [String],
        _ details: String,
        to issues: inout [ProductKnowledgeFoundationIssue]
    ) {
        issues.append(
            ProductKnowledgeFoundationIssue(
                severity: severity,
                code: code,
                recordIDs: ids,
                details: details
            )
        )
    }

    private func isIssueOrderedBefore(
        _ lhs: ProductKnowledgeFoundationIssue,
        _ rhs: ProductKnowledgeFoundationIssue
    ) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
        if lhs.code.rawValue != rhs.code.rawValue {
            return lhs.code.rawValue < rhs.code.rawValue
        }
        if lhs.recordIDs != rhs.recordIDs {
            return lhs.recordIDs.lexicographicallyPrecedes(rhs.recordIDs)
        }
        return lhs.details < rhs.details
    }

    private func isStableID(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              (97...122).contains(first.value) else { return false }
        return value.unicodeScalars.allSatisfy {
            (97...122).contains($0.value)
                || (48...57).contains($0.value)
                || $0.value == 95
        }
    }
}

nonisolated private struct NameDefinitionKey: Hashable {
    let productID: ProductID
    let locale: String
    let kind: ProductNameKind
    let normalizedValue: String
}
