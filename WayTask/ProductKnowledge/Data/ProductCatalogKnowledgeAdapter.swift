import Foundation

nonisolated struct ProductKnowledgeLocalizationDocument:
    Codable,
    Equatable,
    Sendable
{
    let schemaVersion: Int
    let catalogVersion: Int
    let supportedLocales: [String]
    let names: [ProductKnowledgeLocalizedNameRecord]
}

nonisolated struct ProductKnowledgeLocalizedNameRecord:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let productID: String
    let locale: String
    let kind: ProductNameKind
    let value: String
    let isPreferred: Bool
}

nonisolated enum ProductKnowledgeLocalizationError:
    Error,
    Equatable,
    Sendable
{
    case resourceMissing(String)
    case resourceUnreadable(String)
    case decodingFailed
    case unsupportedSchemaVersion(Int)
    case catalogVersionMismatch(expected: Int, actual: Int)
}

nonisolated struct BundledProductKnowledgeLocalizationLoader: Sendable {
    static let resourceName = "product-knowledge-localizations-v1"
    static let resourceExtension = "json"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(expectedCatalogVersion: Int) throws
        -> ProductKnowledgeLocalizationDocument {
        let resource = "\(Self.resourceName).\(Self.resourceExtension)"
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw ProductKnowledgeLocalizationError.resourceMissing(resource)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProductKnowledgeLocalizationError.resourceUnreadable(resource)
        }
        return try load(data: data, expectedCatalogVersion: expectedCatalogVersion)
    }

    func load(data: Data, expectedCatalogVersion: Int) throws
        -> ProductKnowledgeLocalizationDocument {
        let document: ProductKnowledgeLocalizationDocument
        do {
            document = try JSONDecoder().decode(
                ProductKnowledgeLocalizationDocument.self,
                from: data
            )
        } catch {
            throw ProductKnowledgeLocalizationError.decodingFailed
        }
        guard document.schemaVersion == 1 else {
            throw ProductKnowledgeLocalizationError.unsupportedSchemaVersion(
                document.schemaVersion
            )
        }
        guard document.catalogVersion == expectedCatalogVersion else {
            throw ProductKnowledgeLocalizationError.catalogVersionMismatch(
                expected: expectedCatalogVersion,
                actual: document.catalogVersion
            )
        }
        return document
    }
}

/// Compatibility boundary from the audited canonical catalog into the single
/// Product Knowledge search representation. Persisted catalog IDs are copied,
/// never inferred from display text, and custom products never enter here.
nonisolated struct ProductCatalogKnowledgeAdapter: Sendable {
    let document: ProductCatalogDocument
    let taxonomy: ProductCatalogTaxonomyRegistry
    let localizations: ProductKnowledgeLocalizationDocument?

    func makeSnapshot() -> ProductKnowledgeSnapshot {
        let categories = taxonomy.categories.enumerated().map {
            index, category in
            ProductCategory(
                id: ProductCategoryID(category.id),
                names: ProductCategoryNames(
                    en: category.canonicalName,
                    he: category.localizedNames["he-IL"]
                        ?? ProductCatalogCategoryMetadata.metadata(
                            for: category.id
                        ).displayName
                ),
                iconKey: ProductCatalogCategoryMetadata.metadata(
                    for: category.id
                ).iconKey,
                sortOrder: index,
                status: .active
            )
        }

        let products = document.products.map { product in
            let categoryMetadata = ProductCatalogCategoryMetadata.metadata(
                for: product.categoryId,
                subcategoryId: product.subcategoryId
            )
            return ProductEntity(
                id: ProductID(product.id),
                defaultNameID: ProductNameID(baseCanonicalNameID(product.id)),
                primaryCategoryID: ProductCategoryID(product.categoryId),
                subcategoryID: product.subcategoryId.map {
                    ProductSubcategoryID($0)
                },
                semanticKey: product.semanticKey ?? product.id,
                identityKind: product.brand == nil
                    ? .genericProductType
                    : .brandedProduct,
                brand: product.brand,
                variantDescriptors: product.variantDescriptors,
                packageDescriptor: product.packageDescriptor,
                unit: product.unit,
                barcodes: product.barcodes,
                iconKey: categoryMetadata.iconKey,
                catalogVersion: document.catalogVersion,
                provenance: ProductKnowledgeProvenance(
                    source: product.provenance ?? "bundled-catalog",
                    sourceRecordID: product.id
                ),
                status: product.isActive ? .active : .inactive
            )
        }

        var names: [ProductName] = []
        names.reserveCapacity(
            document.products.reduce(0) {
                $0 + 1 + $1.aliases.count + $1.legacyNames.count
                    + $1.keywords.count + $1.brandTerms.count
            } + (localizations?.names.count ?? 0)
        )
        for product in document.products {
            names.append(
                ProductName(
                    id: ProductNameID(baseCanonicalNameID(product.id)),
                    productID: ProductID(product.id),
                    locale: document.locale,
                    kind: .canonical,
                    value: product.canonicalName,
                    isPreferred: true
                )
            )
            appendNames(
                product.aliases + product.legacyNames,
                kind: .alias,
                productID: product.id,
                locale: document.locale,
                prefix: "alias",
                to: &names
            )
            appendNames(
                product.keywords + product.brandTerms,
                kind: .keyword,
                productID: product.id,
                locale: document.locale,
                prefix: "keyword",
                to: &names
            )
        }
        names.append(contentsOf: (localizations?.names ?? []).map {
            ProductName(
                id: ProductNameID($0.id),
                productID: ProductID($0.productID),
                locale: $0.locale,
                kind: $0.kind,
                value: $0.value,
                isPreferred: $0.isPreferred
            )
        })

        let locales = Set(
            [document.locale] + (localizations?.supportedLocales ?? [])
        ).sorted()
        return ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeSnapshotMetadata(
                schemaVersion: 1,
                catalogRevision: document.catalogVersion,
                taxonomyVersion: String(taxonomy.taxonomyVersion),
                expectedProductCount: document.products.count,
                supportedLocales: locales,
                catalogVersion: document.catalogVersion,
                source: "canonical-catalog-v1+localizations-v1"
            ),
            categories: categories,
            products: products,
            names: names
        )
    }

    private func appendNames(
        _ values: [String],
        kind: ProductNameKind,
        productID: String,
        locale: String,
        prefix: String,
        to names: inout [ProductName]
    ) {
        for (index, value) in values.enumerated() {
            names.append(
                ProductName(
                    id: ProductNameID(
                        "catalog_name_\(productID)_\(prefix)_\(index + 1)"
                    ),
                    productID: ProductID(productID),
                    locale: locale,
                    kind: kind,
                    value: value,
                    isPreferred: false
                )
            )
        }
    }

    private func baseCanonicalNameID(_ productID: String) -> String {
        "catalog_name_\(productID)_canonical"
    }
}

enum ProductionProductKnowledgeFactory {
    static func makeSearchAvailability(
        bundle: Bundle = .main
    ) -> ProductKnowledgeSearchAvailability {
        do {
            let service = ProductCatalogService(bundle: bundle)
            guard let catalogURL = bundle.url(
                forResource: ProductCatalogService.resourceName,
                withExtension: ProductCatalogService.resourceExtension
            ) else {
                return .unavailable
            }
            let data = try Data(contentsOf: catalogURL)
            let document = try service.loadDocument(data: data)
            let taxonomy = try ProductCatalogTaxonomyLoader(bundle: bundle).load()
            let localizations: ProductKnowledgeLocalizationDocument?
            do {
                localizations = try BundledProductKnowledgeLocalizationLoader(
                    bundle: bundle
                ).load(expectedCatalogVersion: document.catalogVersion)
            } catch {
                localizations = nil
                #if DEBUG
                print("[WayTask Product Knowledge] Localization overlay unavailable: \(error)")
                #endif
            }

            let snapshot = ProductCatalogKnowledgeAdapter(
                document: document,
                taxonomy: taxonomy,
                localizations: localizations
            ).makeSnapshot()
            let report = ProductKnowledgeFoundationValidator().validate(snapshot)
            guard report.errors.isEmpty else {
                #if DEBUG
                print("[WayTask Product Knowledge] Foundation validation failed: \(report.errors)")
                #endif
                return .unavailable
            }

            let search = ProductKnowledgeSearch(
                repository: InMemoryProductKnowledgeRepository(snapshot: snapshot)
            )
            Task(priority: .utility) {
                await search.prepare()
            }
            return .available(search)
        } catch {
            #if DEBUG
            print("[WayTask Product Knowledge] Runtime catalog unavailable: \(error)")
            #endif
            return .unavailable
        }
    }
}
