import Foundation
import SwiftData

// MARK: - Repository responsibilities

@MainActor
protocol ProductRepository: AnyObject {
    func products(id: UUID) throws -> [WayTaskSchemaV4.Product]

    func products(
        libraryLifecycle: ProductLibraryLifecycle
    ) throws -> [WayTaskSchemaV4.Product]

    func stageInsertion(of product: WayTaskSchemaV4.Product)
}

@MainActor
protocol ShoppingRepository: AnyObject {
    func shoppingLists(id: UUID) throws -> [WayTaskSchemaV4.ShoppingList]

    func shoppingEntries(
        id: UUID,
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry]

    func shoppingEntries(
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry]

    func shoppingEntries(
        listID: UUID,
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry]

    func stageInsertion(of list: WayTaskSchemaV4.ShoppingList)
    func stageInsertion(of entry: WayTaskSchemaV4.ShoppingListEntry)
    func stageDeletion(of list: WayTaskSchemaV4.ShoppingList)
    func stageDeletion(of entry: WayTaskSchemaV4.ShoppingListEntry)
}

@MainActor
protocol HistoryRepository: AnyObject {
    func historyEvents(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent]

    func historyEvents(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent]

    func stageInsertion(
        of event: WayTaskSchemaV4.ProductHistoryEvent
    )
}

@MainActor
protocol ShoppingSessionRepository: AnyObject {
    func shoppingSessions(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSession]

    func shoppingSessions(
        lifecycle: ShoppingSessionLifecycle
    ) throws -> [WayTaskSchemaV4.ShoppingSession]

    func sessionLines(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionLine]

    func sessionStops(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionStop]

    func migrationExceptions(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ProductStateMigrationException]

    func stageInsertion(of session: WayTaskSchemaV4.ShoppingSession)
}

// MARK: - Inactive target composition

/// A transaction owner may construct this bundle around one context. T-03
/// intentionally exposes no save or commit operation; all repositories stage
/// work in the same caller-owned context for a later authorized coordinator.
@MainActor
struct ProductStateRepositories {
    let products: any ProductRepository
    let shopping: any ShoppingRepository
    let history: any HistoryRepository
    let sessions: any ShoppingSessionRepository

    init(modelContext: ModelContext) {
        modelContext.autosaveEnabled = false
        let access = ProductStateRepositoryAccess(modelContext: modelContext)
        products = SwiftDataProductRepository(access: access)
        shopping = SwiftDataShoppingRepository(access: access)
        history = SwiftDataHistoryRepository(access: access)
        sessions = SwiftDataShoppingSessionRepository(access: access)
    }
}

// MARK: - Encapsulated SwiftData access

@MainActor
private final class ProductStateRepositoryAccess {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetch<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>
    ) throws -> [Model] {
        try modelContext.fetch(descriptor)
    }

    func stageInsertion<Model: PersistentModel>(of model: Model) {
        modelContext.insert(model)
    }

    func stageDeletion<Model: PersistentModel>(of model: Model) {
        modelContext.delete(model)
    }
}

@MainActor
private final class SwiftDataProductRepository: ProductRepository {
    private let access: ProductStateRepositoryAccess

    init(access: ProductStateRepositoryAccess) {
        self.access = access
    }

    func products(id: UUID) throws -> [WayTaskSchemaV4.Product] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.Product>(
            predicate: #Predicate { product in
                product.id == id
            },
            sortBy: productSort
        )
        return try access.fetch(descriptor)
    }

    func products(
        libraryLifecycle: ProductLibraryLifecycle
    ) throws -> [WayTaskSchemaV4.Product] {
        let lifecycleRawValue = libraryLifecycle.rawValue
        let descriptor = FetchDescriptor<WayTaskSchemaV4.Product>(
            predicate: #Predicate { product in
                product.libraryLifecycleRawValue == lifecycleRawValue
            },
            sortBy: productSort
        )
        return try access.fetch(descriptor)
    }

    func stageInsertion(of product: WayTaskSchemaV4.Product) {
        access.stageInsertion(of: product)
    }

    private var productSort: [SortDescriptor<WayTaskSchemaV4.Product>] {
        [
            SortDescriptor(\.createdAt),
            SortDescriptor(\.id)
        ]
    }
}

@MainActor
private final class SwiftDataShoppingRepository: ShoppingRepository {
    private let access: ProductStateRepositoryAccess

    init(access: ProductStateRepositoryAccess) {
        self.access = access
    }

    func shoppingLists(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingList] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingList>(
            predicate: #Predicate { list in
                list.id == id
            },
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.id)
            ]
        )
        return try access.fetch(descriptor)
    }

    func shoppingEntries(
        id: UUID,
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>(
            predicate: #Predicate { entry in
                entry.id == id && entry.shoppingListID == listID
            },
            sortBy: entrySort
        )
        return try access.fetch(descriptor)
    }

    func shoppingEntries(
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>(
            predicate: #Predicate { entry in
                entry.shoppingListID == listID
            },
            sortBy: entrySort
        )
        return try access.fetch(descriptor)
    }

    func shoppingEntries(
        listID: UUID,
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>(
            predicate: #Predicate { entry in
                entry.shoppingListID == listID
                    && entry.productID == productID
            },
            sortBy: entrySort
        )
        return try access.fetch(descriptor)
    }

    func stageInsertion(of list: WayTaskSchemaV4.ShoppingList) {
        access.stageInsertion(of: list)
    }

    func stageInsertion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        access.stageInsertion(of: entry)
    }

    func stageDeletion(of list: WayTaskSchemaV4.ShoppingList) {
        access.stageDeletion(of: list)
    }

    func stageDeletion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        access.stageDeletion(of: entry)
    }

    private var entrySort: [SortDescriptor<WayTaskSchemaV4.ShoppingListEntry>] {
        [
            SortDescriptor(\.sortOrder),
            SortDescriptor(\.id)
        ]
    }
}

@MainActor
private final class SwiftDataHistoryRepository: HistoryRepository {
    private let access: ProductStateRepositoryAccess

    init(access: ProductStateRepositoryAccess) {
        self.access = access
    }

    func historyEvents(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>(
            predicate: #Predicate { event in
                event.id == id
            },
            sortBy: historySort
        )
        return try access.fetch(descriptor)
    }

    func historyEvents(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>(
            predicate: #Predicate { event in
                event.productID == productID
            },
            sortBy: historySort
        )
        return try access.fetch(descriptor)
    }

    func stageInsertion(
        of event: WayTaskSchemaV4.ProductHistoryEvent
    ) {
        access.stageInsertion(of: event)
    }

    private var historySort:
        [SortDescriptor<WayTaskSchemaV4.ProductHistoryEvent>] {
        [
            SortDescriptor(\.occurredAt),
            SortDescriptor(\.id)
        ]
    }
}

@MainActor
private final class SwiftDataShoppingSessionRepository:
    ShoppingSessionRepository {
    private let access: ProductStateRepositoryAccess

    init(access: ProductStateRepositoryAccess) {
        self.access = access
    }

    func shoppingSessions(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSession] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingSession>(
            predicate: #Predicate { session in
                session.id == id
            },
            sortBy: sessionSort
        )
        return try access.fetch(descriptor)
    }

    func shoppingSessions(
        lifecycle: ShoppingSessionLifecycle
    ) throws -> [WayTaskSchemaV4.ShoppingSession] {
        let lifecycleRawValue = lifecycle.rawValue
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingSession>(
            predicate: #Predicate { session in
                session.lifecycleRawValue == lifecycleRawValue
            },
            sortBy: sessionSort
        )
        return try access.fetch(descriptor)
    }

    func sessionLines(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionLine] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingSessionLine>(
            predicate: #Predicate { line in
                line.sessionID == sessionID
            },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.id)
            ]
        )
        return try access.fetch(descriptor)
    }

    func sessionStops(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionStop] {
        let descriptor = FetchDescriptor<WayTaskSchemaV4.ShoppingSessionStop>(
            predicate: #Predicate { stop in
                stop.sessionID == sessionID
            },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.id)
            ]
        )
        return try access.fetch(descriptor)
    }

    func migrationExceptions(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ProductStateMigrationException] {
        let descriptor =
            FetchDescriptor<WayTaskSchemaV4.ProductStateMigrationException>(
                predicate: #Predicate { exception in
                    exception.sessionID == sessionID
                },
                sortBy: [
                    SortDescriptor(\.ordinal),
                    SortDescriptor(\.id)
                ]
            )
        return try access.fetch(descriptor)
    }

    func stageInsertion(of session: WayTaskSchemaV4.ShoppingSession) {
        access.stageInsertion(of: session)
    }

    private var sessionSort:
        [SortDescriptor<WayTaskSchemaV4.ShoppingSession>] {
        [
            SortDescriptor(\.startedAt),
            SortDescriptor(\.id)
        ]
    }
}
