import Foundation

nonisolated enum ProductKnowledgeValidationCode: String, Codable, Hashable, Sendable {
    case invalidRecordShape
    case unexpectedField
    case missingField
    case invalidResourceSize
    case invalidCatalogRevision
    case productCountMismatch
    case unsupportedLocales
    case invalidCategoryCount
    case duplicateCategoryID
    case invalidCategoryID
    case taxonomyMismatch
    case categoryNameMismatch
    case categoryIconMismatch
    case duplicateCategorySortOrder
    case categorySortOrderMismatch
    case invalidCategoryStatus
    case duplicateProductID
    case invalidProductID
    case initialProductSetMismatch
    case missingCategoryReference
    case invalidProductStatus
    case invalidDefaultNameReference
    case duplicateNameID
    case missingProductReference
    case emptyNameValue
    case invalidNameWhitespace
    case disallowedControlCharacter
    case unsupportedNameLocale
    case preferredAlias
    case duplicatePreferredName
    case missingPreferredName
    case aliasDisplayNameCollision
    case duplicateNormalizedAlias
    case duplicateNameRecord
}

nonisolated struct ProductKnowledgeValidationViolation: Codable, Equatable, Hashable, Sendable {
    let code: ProductKnowledgeValidationCode
    let path: String
    let recordID: String?

    init(code: ProductKnowledgeValidationCode, path: String, recordID: String? = nil) {
        self.code = code
        self.path = path
        self.recordID = recordID
    }
}

nonisolated enum ProductKnowledgeError: Error, Equatable, Sendable {
    case catalogMissing(resource: String)
    case catalogUnreadable(resource: String)
    case unsupportedSchemaVersion(Int)
    case unsupportedTaxonomyVersion(String)
    case decodingFailed
    case validationFailed([ProductKnowledgeValidationViolation])
    case repositoryUnavailable
}

extension ProductKnowledgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .catalogMissing(let resource):
            return "The bundled Product Knowledge catalog is missing: \(resource)."
        case .catalogUnreadable(let resource):
            return "The bundled Product Knowledge catalog could not be read: \(resource)."
        case .unsupportedSchemaVersion(let version):
            return "The Product Knowledge schema version is unsupported: \(version)."
        case .unsupportedTaxonomyVersion(let version):
            return "The Product Knowledge taxonomy version is unsupported: \(version)."
        case .decodingFailed:
            return "The Product Knowledge catalog could not be decoded."
        case .validationFailed(let violations):
            return "The Product Knowledge catalog failed validation with \(violations.count) violation(s)."
        case .repositoryUnavailable:
            return "The Product Knowledge repository is unavailable."
        }
    }
}
