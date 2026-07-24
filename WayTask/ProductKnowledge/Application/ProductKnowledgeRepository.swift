import Foundation

nonisolated struct ProductKnowledgeSnapshotMetadata: Equatable, Sendable {
    let schemaVersion: Int
    let catalogRevision: Int
    let taxonomyVersion: String
    let expectedProductCount: Int
    let supportedLocales: [String]
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
