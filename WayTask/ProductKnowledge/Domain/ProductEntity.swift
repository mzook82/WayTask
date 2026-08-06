import Foundation

nonisolated struct ProductID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ProductNameID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ProductCategoryID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ProductSubcategoryID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated enum ProductEntityStatus: String, Codable, Hashable, Sendable {
    case active
    case inactive
}

/// Product type is the default. Brand, variant, and package evidence are kept
/// orthogonal so a display string never becomes the sole identity boundary.
nonisolated enum ProductKnowledgeIdentityKind: String, Codable, Hashable, Sendable {
    case genericProductType
    case brandedProduct
}

nonisolated struct ProductKnowledgeProvenance: Codable, Hashable, Sendable {
    let source: String
    let sourceRecordID: String?

    init(source: String, sourceRecordID: String? = nil) {
        self.source = source
        self.sourceRecordID = sourceRecordID
    }
}

nonisolated struct ProductEntity: Identifiable, Codable, Hashable, Sendable {
    let id: ProductID
    let defaultNameID: ProductNameID
    let primaryCategoryID: ProductCategoryID
    let subcategoryID: ProductSubcategoryID?
    let semanticKey: String
    let identityKind: ProductKnowledgeIdentityKind
    let brand: String?
    let variantDescriptors: [String]
    let packageDescriptor: String?
    let unit: String?
    let barcodes: [String]
    let iconKey: String?
    let catalogVersion: Int
    let provenance: ProductKnowledgeProvenance?
    let status: ProductEntityStatus

    init(
        id: ProductID,
        defaultNameID: ProductNameID,
        primaryCategoryID: ProductCategoryID,
        subcategoryID: ProductSubcategoryID? = nil,
        semanticKey: String? = nil,
        identityKind: ProductKnowledgeIdentityKind = .genericProductType,
        brand: String? = nil,
        variantDescriptors: [String] = [],
        packageDescriptor: String? = nil,
        unit: String? = nil,
        barcodes: [String] = [],
        iconKey: String? = nil,
        catalogVersion: Int = 1,
        provenance: ProductKnowledgeProvenance? = nil,
        status: ProductEntityStatus
    ) {
        self.id = id
        self.defaultNameID = defaultNameID
        self.primaryCategoryID = primaryCategoryID
        self.subcategoryID = subcategoryID
        self.semanticKey = semanticKey ?? id.rawValue
        self.identityKind = identityKind
        self.brand = brand
        self.variantDescriptors = variantDescriptors
        self.packageDescriptor = packageDescriptor
        self.unit = unit
        self.barcodes = barcodes
        self.iconKey = iconKey
        self.catalogVersion = catalogVersion
        self.provenance = provenance
        self.status = status
    }
}
