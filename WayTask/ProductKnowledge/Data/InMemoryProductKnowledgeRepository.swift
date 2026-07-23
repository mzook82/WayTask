import Foundation

actor InMemoryProductKnowledgeRepository: ProductKnowledgeRepository {
    private let snapshotMetadata: ProductKnowledgeSnapshotMetadata
    private let entitiesByID: [ProductID: ProductEntity]
    private let namesByProductID: [ProductID: [ProductName]]
    private let namesByID: [ProductNameID: ProductName]
    private let categoriesByID: [ProductCategoryID: ProductCategory]

    init(snapshot: ProductKnowledgeSnapshot) {
        snapshotMetadata = snapshot.metadata
        entitiesByID = Dictionary(uniqueKeysWithValues: snapshot.products.map { ($0.id, $0) })
        namesByID = Dictionary(uniqueKeysWithValues: snapshot.names.map { ($0.id, $0) })
        categoriesByID = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })

        var groupedNames: [ProductID: [ProductName]] = [:]
        for name in snapshot.names {
            groupedNames[name.productID, default: []].append(name)
        }
        namesByProductID = groupedNames
    }

    func metadata() -> ProductKnowledgeSnapshotMetadata {
        snapshotMetadata
    }

    func entity(id: ProductID) -> ProductEntity? {
        entitiesByID[id]
    }

    func names(productID: ProductID) -> [ProductName] {
        namesByProductID[productID] ?? []
    }

    func category(id: ProductCategoryID) -> ProductCategory? {
        categoriesByID[id]
    }

    func preferredName(productID: ProductID, locale: String) -> ProductName? {
        guard let entity = entitiesByID[productID] else {
            return nil
        }

        let displayNames = (namesByProductID[productID] ?? []).filter {
            $0.isPreferred && $0.kind.isDisplayCapable
        }
        let normalizedLocale = locale.replacingOccurrences(of: "_", with: "-")

        if let exact = displayNames.first(where: {
            $0.locale.caseInsensitiveCompare(normalizedLocale) == .orderedSame
        }) {
            return exact
        }

        let requestedLanguage = normalizedLocale
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)
        if let requestedLanguage,
           let languageMatch = displayNames.first(where: {
               $0.locale.caseInsensitiveCompare(requestedLanguage) == .orderedSame
           }) {
            return languageMatch
        }

        if let english = displayNames.first(where: {
            $0.locale.caseInsensitiveCompare("en") == .orderedSame
        }) {
            return english
        }

        return namesByID[entity.defaultNameID]
    }

    func resolvedIconKey(productID: ProductID) -> String? {
        guard let entity = entitiesByID[productID] else {
            return nil
        }
        return categoriesByID[entity.primaryCategoryID]?.iconKey ?? "product.generic"
    }
}
