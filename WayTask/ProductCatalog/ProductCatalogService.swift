import Foundation

nonisolated protocol ProductCatalogProviding: Sendable {
    func loadProducts() throws -> [CatalogProduct]
}

nonisolated enum ProductCatalogError: Error, LocalizedError, Sendable {
    case resourceMissing(String)
    case resourceUnreadable(String)
    case decodingFailed(String)
    case taxonomyResourceMissing(String)
    case taxonomyResourceUnreadable(String)
    case taxonomyDecodingFailed(String)
    case unsupportedSchemaVersion(Int)
    case invalidLegacyMetadata
    case invalidCatalogVersion(Int)
    case invalidLocale(String)
    case invalidTaxonomyVersion(Int)
    case invalidTaxonomyLocale(String)
    case incompatibleTaxonomyVersion(catalog: Int, registry: Int)
    case duplicateProductID(String)
    case invalidProductID(String)
    case emptyRequiredField(productID: String, field: String)
    case invalidPopularityScore(productID: String, score: Int)
    case duplicateCanonicalName(
        normalizedName: String,
        productIDs: [String]
    )
    case duplicateNormalizedValue(
        productID: String,
        field: String,
        normalizedValue: String
    )
    case aliasMatchesCanonicalName(
        alias: String,
        aliasProductID: String,
        canonicalProductID: String
    )
    case aliasSharedByProducts(
        normalizedAlias: String,
        productIDs: [String],
        aliases: [String]
    )
    case brandTermMatchesCanonicalName(
        brandTerm: String,
        brandProductID: String,
        canonicalProductID: String
    )
    case brandTermMatchesAlias(
        brandTerm: String,
        brandProductID: String,
        aliasProductID: String
    )
    case invalidCategoryReference(
        productID: String,
        categoryID: String,
        sourceFormat: String
    )
    case invalidSubcategoryReference(
        productID: String,
        subcategoryID: String
    )
    case subcategoryParentMismatch(
        productID: String,
        categoryID: String,
        subcategoryID: String,
        expectedParentID: String
    )
    case legacySubcategoryNotSupported(
        productID: String,
        subcategoryID: String
    )
    case activeProductHasReplacement(productID: String)
    case activeProductIsDeprecated(productID: String)
    case invalidDeprecationVersion(
        productID: String,
        deprecatedVersion: Int,
        catalogVersion: Int
    )
    case replacementTargetMissing(
        productID: String,
        replacementProductID: String
    )
    case replacementTargetInactive(
        productID: String,
        replacementProductID: String
    )
    case replacementLoop(productIDs: [String])
    case invalidTaxonomyRecordID(kind: String, id: String)
    case duplicateTaxonomyRecordID(kind: String, id: String)
    case emptyTaxonomyField(kind: String, id: String, field: String)
    case missingTaxonomyHebrewName(
        kind: String,
        id: String,
        locale: String
    )
    case taxonomySubcategoryParentMismatch(
        subcategoryID: String,
        declaredParentID: String,
        containingCategoryID: String
    )
    case orphanCompatibilityCategory(
        legacyCategoryID: String,
        canonicalCategoryID: String
    )
    case orphanCompatibilitySubcategory(
        legacyCategoryID: String,
        canonicalSubcategoryID: String
    )
    case compatibilityParentMismatch(
        legacyCategoryID: String,
        canonicalCategoryID: String,
        canonicalSubcategoryID: String
    )

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let resource):
            return "Catalog resource is missing: \(resource)"
        case .resourceUnreadable(let resource):
            return "Catalog resource could not be read: \(resource)"
        case .decodingFailed(let details):
            return "Catalog JSON could not be decoded: \(details)"
        case .taxonomyResourceMissing(let resource):
            return "Catalog taxonomy resource is missing: \(resource)"
        case .taxonomyResourceUnreadable(let resource):
            return "Catalog taxonomy resource could not be read: \(resource)"
        case .taxonomyDecodingFailed(let details):
            return "Catalog taxonomy JSON could not be decoded: \(details)"
        case .unsupportedSchemaVersion(let version):
            return "Canonical catalog schemaVersion \(version) is unsupported; expected \(ProductCatalogCompatibilityDecoder.canonicalSchemaVersion)."
        case .invalidLegacyMetadata:
            return "Legacy v2 catalog metadata must not contain canonical schema or taxonomy versions."
        case .invalidCatalogVersion(let version):
            return "Catalog version must be positive; received \(version)."
        case .invalidLocale(let locale):
            return "Catalog locale must be he-IL; received \(locale)."
        case .invalidTaxonomyVersion(let version):
            return "Taxonomy version must be positive; received \(version)."
        case .invalidTaxonomyLocale(let locale):
            return "Taxonomy locale must be he-IL; received \(locale)."
        case .incompatibleTaxonomyVersion(let catalog, let registry):
            return "Catalog taxonomyVersion \(catalog) does not match registry version \(registry)."
        case .duplicateProductID(let id):
            return "Catalog contains the duplicate product ID \(id)."
        case .invalidProductID(let id):
            return "Catalog product ID is not stable lowercase ASCII: \(id)."
        case .emptyRequiredField(let productID, let field):
            return "Catalog product \(productID) has an empty \(field) field."
        case .invalidPopularityScore(let productID, let score):
            return "Catalog product \(productID) has invalid popularity score \(score); expected 0...100."
        case .duplicateCanonicalName(let normalizedName, let productIDs):
            return "Catalog products \(productIDs.joined(separator: ", ")) share normalized canonical name \(normalizedName)."
        case .duplicateNormalizedValue(
            let productID,
            let field,
            let normalizedValue
        ):
            return "Catalog product \(productID) repeats normalized \(field) value \(normalizedValue)."
        case .aliasMatchesCanonicalName(
            let alias,
            let aliasProductID,
            let canonicalProductID
        ):
            return "Alias \(alias) on \(aliasProductID) matches the canonical name of \(canonicalProductID)."
        case .aliasSharedByProducts(
            let normalizedAlias,
            let productIDs,
            let aliases
        ):
            return "Normalized alias \(normalizedAlias) is shared by \(productIDs.joined(separator: ", ")) via \(aliases.joined(separator: ", "))."
        case .brandTermMatchesCanonicalName(
            let brandTerm,
            let brandProductID,
            let canonicalProductID
        ):
            return "Brand term \(brandTerm) on \(brandProductID) matches the canonical name of \(canonicalProductID)."
        case .brandTermMatchesAlias(
            let brandTerm,
            let brandProductID,
            let aliasProductID
        ):
            return "Brand term \(brandTerm) on \(brandProductID) conflicts with an alias owned by \(aliasProductID)."
        case .invalidCategoryReference(
            let productID,
            let categoryID,
            let sourceFormat
        ):
            return "Catalog product \(productID) references unknown category \(categoryID) for \(sourceFormat)."
        case .invalidSubcategoryReference(let productID, let subcategoryID):
            return "Catalog product \(productID) references unknown subcategory \(subcategoryID)."
        case .subcategoryParentMismatch(
            let productID,
            let categoryID,
            let subcategoryID,
            let expectedParentID
        ):
            return "Catalog product \(productID) assigns \(subcategoryID), whose parent is \(expectedParentID), under category \(categoryID)."
        case .legacySubcategoryNotSupported(let productID, let subcategoryID):
            return "Legacy v2 product \(productID) unexpectedly contains subcategory \(subcategoryID)."
        case .activeProductHasReplacement(let productID):
            return "Active catalog product \(productID) must not declare a replacement."
        case .activeProductIsDeprecated(let productID):
            return "Active catalog product \(productID) must not declare deprecation metadata."
        case .invalidDeprecationVersion(
            let productID,
            let deprecatedVersion,
            let catalogVersion
        ):
            return "Catalog product \(productID) has deprecatedSinceCatalogVersion \(deprecatedVersion), outside 1...\(catalogVersion)."
        case .replacementTargetMissing(let productID, let replacementProductID):
            return "Inactive catalog product \(productID) replaces to missing product \(replacementProductID)."
        case .replacementTargetInactive(let productID, let replacementProductID):
            return "Inactive catalog product \(productID) replaces to inactive product \(replacementProductID)."
        case .replacementLoop(let productIDs):
            return "Catalog replacement loop detected: \(productIDs.joined(separator: " -> "))."
        case .invalidTaxonomyRecordID(let kind, let id):
            return "Taxonomy \(kind) ID is not stable ASCII: \(id)."
        case .duplicateTaxonomyRecordID(let kind, let id):
            return "Taxonomy contains duplicate \(kind) ID \(id)."
        case .emptyTaxonomyField(let kind, let id, let field):
            return "Taxonomy \(kind) \(id) has an empty \(field) field."
        case .missingTaxonomyHebrewName(let kind, let id, let locale):
            return "Taxonomy \(kind) \(id) is missing localized name \(locale)."
        case .taxonomySubcategoryParentMismatch(
            let subcategoryID,
            let declaredParentID,
            let containingCategoryID
        ):
            return "Taxonomy subcategory \(subcategoryID) declares parent \(declaredParentID) but is contained by \(containingCategoryID)."
        case .orphanCompatibilityCategory(
            let legacyCategoryID,
            let canonicalCategoryID
        ):
            return "Legacy category \(legacyCategoryID) maps to missing canonical category \(canonicalCategoryID)."
        case .orphanCompatibilitySubcategory(
            let legacyCategoryID,
            let canonicalSubcategoryID
        ):
            return "Legacy category \(legacyCategoryID) maps to missing canonical subcategory \(canonicalSubcategoryID)."
        case .compatibilityParentMismatch(
            let legacyCategoryID,
            let canonicalCategoryID,
            let canonicalSubcategoryID
        ):
            return "Legacy category \(legacyCategoryID) maps \(canonicalSubcategoryID) under incorrect canonical category \(canonicalCategoryID)."
        }
    }
}

nonisolated struct ProductCatalogService: ProductCatalogProviding {
    static let resourceName = "product_catalog_he"
    static let resourceExtension = "json"

    private let bundle: Bundle
    private let injectedTaxonomy: ProductCatalogTaxonomyRegistry?
    private let compatibilityDecoder = ProductCatalogCompatibilityDecoder()

    init(
        bundle: Bundle = .main,
        taxonomy: ProductCatalogTaxonomyRegistry? = nil
    ) {
        self.bundle = bundle
        injectedTaxonomy = taxonomy
    }

    func loadProducts() throws -> [CatalogProduct] {
        let resource = "\(Self.resourceName).\(Self.resourceExtension)"
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            let error = ProductCatalogError.resourceMissing(resource)
            log(error)
            throw error
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let catalogError = ProductCatalogError.resourceUnreadable(resource)
            log(catalogError)
            throw catalogError
        }

        do {
            return try loadProducts(data: data)
        } catch {
            log(error)
            throw error
        }
    }

    func loadProducts(data: Data) throws -> [CatalogProduct] {
        try loadDocument(data: data).products.filter(\.isActive)
    }

    func loadDocument(data: Data) throws -> ProductCatalogDocument {
        let document: ProductCatalogDocument
        do {
            document = try compatibilityDecoder.decode(data)
        } catch let error as ProductCatalogError {
            throw error
        } catch {
            throw ProductCatalogError.decodingFailed(
                String(describing: error)
            )
        }

        let taxonomy: ProductCatalogTaxonomyRegistry
        if let injectedTaxonomy {
            taxonomy = injectedTaxonomy
        } else {
            taxonomy = try ProductCatalogTaxonomyLoader(
                bundle: bundle
            ).load()
        }
        try ProductCatalogValidator(taxonomy: taxonomy).validate(document)
        return document
    }

    func loadProductsOrEmpty() -> [CatalogProduct] {
        do {
            return try loadProducts()
        } catch {
            return []
        }
    }

    private func log(_ error: Error) {
        #if DEBUG
        print("[WayTask Product Catalog] \(error.localizedDescription)")
        #endif
    }
}
