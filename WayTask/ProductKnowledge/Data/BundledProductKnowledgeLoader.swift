import Foundation

nonisolated struct BundledProductKnowledgeLoader {
    static let resourceName = "product-knowledge-catalog-v1"
    static let resourceExtension = "json"

    private let bundle: Bundle
    private let validator: ProductKnowledgeCatalogValidator
    private let supportedSchemaVersions: Set<Int>
    private let supportedTaxonomyVersions: Set<String>

    init(
        bundle: Bundle = .main,
        validator: ProductKnowledgeCatalogValidator = ProductKnowledgeCatalogValidator(),
        supportedSchemaVersions: Set<Int> = [1],
        supportedTaxonomyVersions: Set<String> = ["1.0"]
    ) {
        self.bundle = bundle
        self.validator = validator
        self.supportedSchemaVersions = supportedSchemaVersions
        self.supportedTaxonomyVersions = supportedTaxonomyVersions
    }

    func load() throws -> ProductKnowledgeSnapshot {
        let resource = "\(Self.resourceName).\(Self.resourceExtension)"
        guard let resourceURL = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw ProductKnowledgeError.catalogMissing(resource: resource)
        }

        return try load(resourceURL: resourceURL)
    }

    func load(resourceURL: URL) throws -> ProductKnowledgeSnapshot {
        let resource = resourceURL.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: resourceURL)
        } catch {
            throw ProductKnowledgeError.catalogUnreadable(resource: resource)
        }

        return try load(data: data)
    }

    func load(data: Data) throws -> ProductKnowledgeSnapshot {
        let catalog: ProductKnowledgeCatalog
        do {
            catalog = try JSONDecoder().decode(ProductKnowledgeCatalog.self, from: data)
        } catch {
            throw ProductKnowledgeError.decodingFailed
        }

        guard supportedSchemaVersions.contains(catalog.schemaVersion) else {
            throw ProductKnowledgeError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard supportedTaxonomyVersions.contains(catalog.taxonomyVersion) else {
            throw ProductKnowledgeError.unsupportedTaxonomyVersion(catalog.taxonomyVersion)
        }

        try validator.validateRawShape(data)
        try validator.validate(catalog, resourceByteCount: data.count)
        return catalog.makeSnapshot()
    }
}
