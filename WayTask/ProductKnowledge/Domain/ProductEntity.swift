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

nonisolated enum ProductEntityStatus: String, Codable, Hashable, Sendable {
    case active
    case inactive
}

nonisolated struct ProductEntity: Identifiable, Codable, Hashable, Sendable {
    let id: ProductID
    let defaultNameID: ProductNameID
    let primaryCategoryID: ProductCategoryID
    let status: ProductEntityStatus
}
