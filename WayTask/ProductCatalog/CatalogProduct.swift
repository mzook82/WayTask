import Foundation

nonisolated indirect enum CatalogMetadataValue:
    Codable,
    Hashable,
    Sendable
{
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: CatalogMetadataValue])
    case array([CatalogMetadataValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [String: CatalogMetadataValue].self
        ) {
            self = .object(value)
        } else if let value = try? container.decode(
            [CatalogMetadataValue].self
        ) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported catalog metadata value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

nonisolated struct CatalogProduct:
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: String
    let canonicalName: String
    let categoryId: String
    let subcategoryId: String?
    let aliases: [String]
    let keywords: [String]
    let brandTerms: [String]
    let semanticKey: String?
    let brand: String?
    let variantDescriptors: [String]
    let packageDescriptor: String?
    let unit: String?
    let barcodes: [String]
    let provenance: String?
    let popularityScore: Int
    let isActive: Bool
    let replacementProductId: String?
    let deprecatedSinceCatalogVersion: Int?
    let legacyNames: [String]
    let metadata: [String: CatalogMetadataValue]?

    init(
        id: String,
        canonicalName: String,
        categoryId: String,
        subcategoryId: String? = nil,
        aliases: [String],
        keywords: [String],
        brandTerms: [String] = [],
        semanticKey: String? = nil,
        brand: String? = nil,
        variantDescriptors: [String] = [],
        packageDescriptor: String? = nil,
        unit: String? = nil,
        barcodes: [String] = [],
        provenance: String? = nil,
        popularityScore: Int,
        isActive: Bool,
        replacementProductId: String? = nil,
        deprecatedSinceCatalogVersion: Int? = nil,
        legacyNames: [String] = [],
        metadata: [String: CatalogMetadataValue]? = nil
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
        self.aliases = aliases
        self.keywords = keywords
        self.brandTerms = brandTerms
        self.semanticKey = semanticKey
        self.brand = brand
        self.variantDescriptors = variantDescriptors
        self.packageDescriptor = packageDescriptor
        self.unit = unit
        self.barcodes = barcodes
        self.provenance = provenance
        self.popularityScore = popularityScore
        self.isActive = isActive
        self.replacementProductId = replacementProductId
        self.deprecatedSinceCatalogVersion =
            deprecatedSinceCatalogVersion
        self.legacyNames = legacyNames
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalName
        case categoryId
        case subcategoryId
        case aliases
        case keywords
        case brandTerms
        case semanticKey
        case brand
        case variantDescriptors
        case packageDescriptor
        case unit
        case barcodes
        case provenance
        case popularityScore
        case isActive
        case replacementProductId
        case deprecatedSinceCatalogVersion
        case legacyNames
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard container.contains(.subcategoryId) else {
            throw DecodingError.keyNotFound(
                CodingKeys.subcategoryId,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription:
                        "Canonical products require subcategoryId, which may be null."
                )
            )
        }

        id = try container.decode(String.self, forKey: .id)
        canonicalName = try container.decode(
            String.self,
            forKey: .canonicalName
        )
        categoryId = try container.decode(String.self, forKey: .categoryId)
        subcategoryId = try container.decodeIfPresent(
            String.self,
            forKey: .subcategoryId
        )
        aliases = try container.decode([String].self, forKey: .aliases)
        keywords = try container.decode([String].self, forKey: .keywords)
        brandTerms = try container.decode(
            [String].self,
            forKey: .brandTerms
        )
        semanticKey = try container.decodeIfPresent(
            String.self,
            forKey: .semanticKey
        )
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        variantDescriptors = try container.decodeIfPresent(
            [String].self,
            forKey: .variantDescriptors
        ) ?? []
        packageDescriptor = try container.decodeIfPresent(
            String.self,
            forKey: .packageDescriptor
        )
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        barcodes = try container.decodeIfPresent(
            [String].self,
            forKey: .barcodes
        ) ?? []
        provenance = try container.decodeIfPresent(
            String.self,
            forKey: .provenance
        )
        popularityScore = try container.decode(
            Int.self,
            forKey: .popularityScore
        )
        isActive = try container.decode(Bool.self, forKey: .isActive)
        replacementProductId = try container.decodeIfPresent(
            String.self,
            forKey: .replacementProductId
        )
        deprecatedSinceCatalogVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .deprecatedSinceCatalogVersion
        )
        legacyNames = try container.decodeIfPresent(
            [String].self,
            forKey: .legacyNames
        ) ?? []
        metadata = try container.decodeIfPresent(
            [String: CatalogMetadataValue].self,
            forKey: .metadata
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(canonicalName, forKey: .canonicalName)
        try container.encode(categoryId, forKey: .categoryId)
        if let subcategoryId {
            try container.encode(subcategoryId, forKey: .subcategoryId)
        } else {
            try container.encodeNil(forKey: .subcategoryId)
        }
        try container.encode(aliases, forKey: .aliases)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(brandTerms, forKey: .brandTerms)
        try container.encodeIfPresent(semanticKey, forKey: .semanticKey)
        try container.encodeIfPresent(brand, forKey: .brand)
        if !variantDescriptors.isEmpty {
            try container.encode(
                variantDescriptors,
                forKey: .variantDescriptors
            )
        }
        try container.encodeIfPresent(
            packageDescriptor,
            forKey: .packageDescriptor
        )
        try container.encodeIfPresent(unit, forKey: .unit)
        if !barcodes.isEmpty {
            try container.encode(barcodes, forKey: .barcodes)
        }
        try container.encodeIfPresent(provenance, forKey: .provenance)
        try container.encode(popularityScore, forKey: .popularityScore)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(
            replacementProductId,
            forKey: .replacementProductId
        )
        try container.encodeIfPresent(
            deprecatedSinceCatalogVersion,
            forKey: .deprecatedSinceCatalogVersion
        )
        if !legacyNames.isEmpty {
            try container.encode(legacyNames, forKey: .legacyNames)
        }
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

nonisolated enum ProductCatalogSourceFormat: String, Equatable, Sendable {
    case legacyV2 = "legacy_v2"
    case canonicalV1 = "canonical_v1"
}

nonisolated struct ProductCatalogDocument: Equatable, Sendable {
    let schemaVersion: Int?
    let catalogVersion: Int
    let taxonomyVersion: Int?
    let locale: String
    let products: [CatalogProduct]
    let sourceFormat: ProductCatalogSourceFormat
}
