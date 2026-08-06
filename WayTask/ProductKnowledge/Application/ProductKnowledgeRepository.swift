import Foundation

nonisolated struct ProductKnowledgeSnapshotMetadata: Equatable, Sendable {
    let schemaVersion: Int
    let catalogRevision: Int
    let taxonomyVersion: String
    let expectedProductCount: Int
    let supportedLocales: [String]
    let catalogVersion: Int?
    let source: String?

    init(
        schemaVersion: Int,
        catalogRevision: Int,
        taxonomyVersion: String,
        expectedProductCount: Int,
        supportedLocales: [String],
        catalogVersion: Int? = nil,
        source: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.catalogRevision = catalogRevision
        self.taxonomyVersion = taxonomyVersion
        self.expectedProductCount = expectedProductCount
        self.supportedLocales = supportedLocales
        self.catalogVersion = catalogVersion
        self.source = source
    }
}

nonisolated struct ProductKnowledgeSnapshot: Equatable, Sendable {
    let metadata: ProductKnowledgeSnapshotMetadata
    let categories: [ProductCategory]
    let products: [ProductEntity]
    let names: [ProductName]
}

nonisolated protocol ProductKnowledgeRepository: Sendable {
    func catalogSnapshot() async -> ProductKnowledgeSnapshot
    func metadata() async -> ProductKnowledgeSnapshotMetadata
    func entity(id: ProductID) async -> ProductEntity?
    func names(productID: ProductID) async -> [ProductName]
    func category(id: ProductCategoryID) async -> ProductCategory?
    func preferredName(productID: ProductID, locale: String) async -> ProductName?
    func resolvedIconKey(productID: ProductID) async -> String?
}
