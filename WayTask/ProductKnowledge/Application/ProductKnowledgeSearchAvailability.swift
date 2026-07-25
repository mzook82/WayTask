nonisolated enum ProductKnowledgeSearchAvailability: Sendable {
    case available(ProductKnowledgeSearch)
    case catalog(ProductCatalogSearch)
    case unavailable
}
