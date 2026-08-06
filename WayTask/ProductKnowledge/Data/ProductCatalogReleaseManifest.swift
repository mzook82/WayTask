import Foundation

nonisolated struct ProductCatalogReleaseManifest:
    Codable,
    Equatable,
    Sendable
{
    let schemaVersion: Int
    let catalogVersion: Int
    let generationDate: String
    let productCount: Int
}

nonisolated enum ProductCatalogReleaseManifestError:
    Error,
    Equatable,
    Sendable
{
    case resourceMissing(String)
    case resourceUnreadable(String)
    case decodingFailed
    case unsupportedSchemaVersion(Int)
    case invalidGenerationDate(String)
    case catalogVersionMismatch(expected: Int, actual: Int)
    case productCountMismatch(expected: Int, actual: Int)
}

/// Runtime gate for the immutable release metadata emitted by the editorial
/// importer. It does not participate in ProductState persistence.
nonisolated struct BundledProductCatalogReleaseManifestLoader: Sendable {
    static let resourceName = "product-catalog-release-v1"
    static let resourceExtension = "json"

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(
        expectedCatalogVersion: Int,
        expectedProductCount: Int
    ) throws -> ProductCatalogReleaseManifest {
        let resource = "\(Self.resourceName).\(Self.resourceExtension)"
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw ProductCatalogReleaseManifestError.resourceMissing(resource)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProductCatalogReleaseManifestError.resourceUnreadable(resource)
        }
        return try load(
            data: data,
            expectedCatalogVersion: expectedCatalogVersion,
            expectedProductCount: expectedProductCount
        )
    }

    func load(
        data: Data,
        expectedCatalogVersion: Int,
        expectedProductCount: Int
    ) throws -> ProductCatalogReleaseManifest {
        let manifest: ProductCatalogReleaseManifest
        do {
            manifest = try JSONDecoder().decode(
                ProductCatalogReleaseManifest.self,
                from: data
            )
        } catch {
            throw ProductCatalogReleaseManifestError.decodingFailed
        }
        guard manifest.schemaVersion == 1 else {
            throw ProductCatalogReleaseManifestError
                .unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard Self.isValidDate(manifest.generationDate) else {
            throw ProductCatalogReleaseManifestError
                .invalidGenerationDate(manifest.generationDate)
        }
        guard manifest.catalogVersion == expectedCatalogVersion else {
            throw ProductCatalogReleaseManifestError.catalogVersionMismatch(
                expected: expectedCatalogVersion,
                actual: manifest.catalogVersion
            )
        }
        guard manifest.productCount == expectedProductCount else {
            throw ProductCatalogReleaseManifestError.productCountMismatch(
                expected: expectedProductCount,
                actual: manifest.productCount
            )
        }
        return manifest
    }

    private static func isValidDate(_ value: String) -> Bool {
        guard value.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }
}
