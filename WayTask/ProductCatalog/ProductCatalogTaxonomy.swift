import Foundation

nonisolated struct ProductCatalogTaxonomyRegistry:
    Codable,
    Equatable,
    Sendable
{
    let taxonomyVersion: Int
    let locale: String
    let categories: [ProductCatalogTaxonomyCategory]
    let compatibilityMappings: [ProductCatalogCategoryCompatibilityMapping]

    func category(
        id: String
    ) -> ProductCatalogTaxonomyCategory? {
        categories.first { $0.id == id }
    }

    func subcategory(
        id: String
    ) -> ProductCatalogTaxonomySubcategory? {
        categories.lazy
            .flatMap(\.subcategories)
            .first { $0.id == id }
    }

    func compatibilityMapping(
        legacyCategoryId: String
    ) -> ProductCatalogCategoryCompatibilityMapping? {
        compatibilityMappings.first {
            $0.legacyCategoryId == legacyCategoryId
        }
    }
}

nonisolated struct ProductCatalogTaxonomyCategory:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let canonicalName: String
    let localizedNames: [String: String]
    let description: String?
    let subcategories: [ProductCatalogTaxonomySubcategory]
}

nonisolated struct ProductCatalogTaxonomySubcategory:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let canonicalName: String
    let localizedNames: [String: String]
    let parentCategoryId: String
}

nonisolated enum ProductCatalogCategoryMigrationMode:
    String,
    Codable,
    Equatable,
    Sendable
{
    case direct
    case subcategoryDefault = "subcategory_default"
    case productReviewRequired = "product_review_required"
}

nonisolated struct ProductCatalogCategoryCompatibilityMapping:
    Codable,
    Equatable,
    Sendable
{
    let legacyCategoryId: String
    let canonicalCategoryId: String
    let canonicalSubcategoryId: String?
    let migrationMode: ProductCatalogCategoryMigrationMode
}

nonisolated struct ProductCatalogTaxonomyLoader: Sendable {
    static let resourceName = "taxonomy"
    static let resourceExtension = "json"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load() throws -> ProductCatalogTaxonomyRegistry {
        let resource = "\(Self.resourceName).\(Self.resourceExtension)"
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw ProductCatalogError.taxonomyResourceMissing(resource)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProductCatalogError.taxonomyResourceUnreadable(resource)
        }
        return try load(data: data)
    }

    func load(data: Data) throws -> ProductCatalogTaxonomyRegistry {
        do {
            return try JSONDecoder().decode(
                ProductCatalogTaxonomyRegistry.self,
                from: data
            )
        } catch {
            throw ProductCatalogError.taxonomyDecodingFailed(
                String(describing: error)
            )
        }
    }
}
