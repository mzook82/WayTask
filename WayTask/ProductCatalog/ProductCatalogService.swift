import Foundation

nonisolated protocol ProductCatalogProviding: Sendable {
    func loadProducts() throws -> [CatalogProduct]
}

nonisolated enum ProductCatalogError: Error, LocalizedError, Sendable {
    case resourceMissing(String)
    case resourceUnreadable(String)
    case decodingFailed(String)
    case invalidCatalogVersion(Int)
    case invalidLocale(String)
    case duplicateProductID(String)
    case invalidProductID(String)
    case emptyRequiredField(productID: String, field: String)
    case invalidPopularityScore(productID: String, score: Int)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let resource):
            return "Catalog resource is missing: \(resource)"
        case .resourceUnreadable(let resource):
            return "Catalog resource could not be read: \(resource)"
        case .decodingFailed(let details):
            return "Catalog JSON could not be decoded: \(details)"
        case .invalidCatalogVersion(let version):
            return "Catalog version must be positive; received \(version)."
        case .invalidLocale(let locale):
            return "Catalog locale must be he-IL; received \(locale)."
        case .duplicateProductID(let id):
            return "Catalog contains the duplicate product ID \(id)."
        case .invalidProductID(let id):
            return "Catalog product ID is not stable or portable: \(id)."
        case .emptyRequiredField(let productID, let field):
            return "Catalog product \(productID) has an empty \(field) field."
        case .invalidPopularityScore(let productID, let score):
            return "Catalog product \(productID) has invalid popularity score \(score)."
        }
    }
}

nonisolated struct ProductCatalogService: ProductCatalogProviding {
    static let resourceName = "product_catalog_he"
    static let resourceExtension = "json"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
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
        let document: ProductCatalogDocument
        do {
            document = try JSONDecoder().decode(ProductCatalogDocument.self, from: data)
        } catch {
            throw ProductCatalogError.decodingFailed(String(describing: error))
        }

        try validate(document)
        return document.products.filter(\.isActive)
    }

    func loadProductsOrEmpty() -> [CatalogProduct] {
        do {
            return try loadProducts()
        } catch {
            return []
        }
    }

    private func validate(_ document: ProductCatalogDocument) throws {
        guard document.catalogVersion > 0 else {
            throw ProductCatalogError.invalidCatalogVersion(document.catalogVersion)
        }
        guard document.locale == "he-IL" else {
            throw ProductCatalogError.invalidLocale(document.locale)
        }

        var seenIDs: Set<String> = []
        for product in document.products {
            guard seenIDs.insert(product.id).inserted else {
                throw ProductCatalogError.duplicateProductID(product.id)
            }
            guard isPortableStableID(product.id) else {
                throw ProductCatalogError.invalidProductID(product.id)
            }

            try requireNonempty(product.name, field: "name", productID: product.id)
            try requireNonempty(
                product.categoryId,
                field: "categoryId",
                productID: product.id
            )
            for alias in product.aliases {
                try requireNonempty(alias, field: "aliases", productID: product.id)
            }
            for keyword in product.keywords {
                try requireNonempty(keyword, field: "keywords", productID: product.id)
            }
            guard (0...100).contains(product.popularityScore) else {
                throw ProductCatalogError.invalidPopularityScore(
                    productID: product.id,
                    score: product.popularityScore
                )
            }
        }
    }

    private func requireNonempty(
        _ value: String,
        field: String,
        productID: String
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProductCatalogError.emptyRequiredField(
                productID: productID,
                field: field
            )
        }
    }

    private func isPortableStableID(_ id: String) -> Bool {
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

    private func log(_ error: Error) {
        #if DEBUG
        print("[WayTask Product Catalog] \(error.localizedDescription)")
        #endif
    }
}
