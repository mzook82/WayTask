import Foundation

enum ShoppingListDuplicateEvidence: Equatable, Sendable {
    case exactProductIdentity
    case matchingCatalogIdentity
    case matchingBarcode
    case normalizedDisplayName
}

struct ShoppingListDuplicateMatch: Equatable, Sendable {
    let existingEntryID: ProductStateListEntryID
    let evidence: ShoppingListDuplicateEvidence

    var isExactProductIdentity: Bool {
        evidence == .exactProductIdentity
    }
}

/// Presentation-safe duplicate classification for adding a library product to
/// one named shopping list. It never mutates or merges product records.
enum ShoppingListDuplicatePolicy {
    static func match(
        candidate: ProductStateProductProjection,
        entries: [ProductStateListEntryProjection]
    ) -> ShoppingListDuplicateMatch? {
        if let exact = entries.first(where: {
            $0.identity.productID == candidate.id
        }) {
            return ShoppingListDuplicateMatch(
                existingEntryID: exact.identity.id,
                evidence: .exactProductIdentity
            )
        }

        for entry in entries {
            guard let existing = entry.product else { continue }

            if let candidateCatalogID = candidate.catalogID,
               candidateCatalogID == existing.catalogID {
                return ShoppingListDuplicateMatch(
                    existingEntryID: entry.identity.id,
                    evidence: .matchingCatalogIdentity
                )
            }

            if let candidateBarcode = normalizedOptional(candidate.barcode),
               candidateBarcode == normalizedOptional(existing.barcode) {
                return ShoppingListDuplicateMatch(
                    existingEntryID: entry.identity.id,
                    evidence: .matchingBarcode
                )
            }

            guard normalizedName(candidate.displayName)
                    == normalizedName(existing.displayName),
                  !normalizedName(candidate.displayName).isEmpty,
                  !hasConflictingVariantEvidence(candidate, existing)
            else { continue }

            return ShoppingListDuplicateMatch(
                existingEntryID: entry.identity.id,
                evidence: .normalizedDisplayName
            )
        }

        return nil
    }

    private static func hasConflictingVariantEvidence(
        _ candidate: ProductStateProductProjection,
        _ existing: ProductStateProductProjection
    ) -> Bool {
        if let candidateCatalogID = candidate.catalogID,
           let existingCatalogID = existing.catalogID,
           candidateCatalogID != existingCatalogID {
            return true
        }
        if let candidateBarcode = normalizedOptional(candidate.barcode),
           let existingBarcode = normalizedOptional(existing.barcode),
           candidateBarcode != existingBarcode {
            return true
        }
        if let candidateBrand = normalizedOptional(candidate.brand),
           let existingBrand = normalizedOptional(existing.brand),
           candidateBrand != existingBrand {
            return true
        }
        return false
    }

    private static func normalizedName(_ value: String) -> String {
        ProductSearchNormalizer.normalize(value).value
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = ProductSearchNormalizer.normalize(value).value
        return normalized.isEmpty ? nil : normalized
    }
}

enum CatalogCustomCreationPolicy {
    static func offeredName(
        for query: String,
        searchCompletedWithoutMatch: Bool
    ) -> String? {
        guard searchCompletedWithoutMatch else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ProductSearchNormalizer.normalize(trimmed).value
        guard normalized.count >= 2 else { return nil }
        return trimmed
    }
}
