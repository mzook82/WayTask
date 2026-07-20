import CoreLocation
import Foundation
import SwiftData

protocol ShoppingSessionServicing {
    @discardableResult
    func startShopping(with items: [ShoppingItem], in modelContext: ModelContext) throws -> ShoppingSession
    @discardableResult
    func startShopping(
        with items: [ShoppingItem],
        shoppingListID: UUID,
        selectedStore: MapStore,
        in modelContext: ModelContext
    ) throws -> ShoppingSession
    func activeSession(in modelContext: ModelContext) throws -> ShoppingSession?
    func markItemCollected(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws
    func markItemRemaining(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws
    func remainingItemCount(for session: ShoppingSession) -> Int
    func finishShopping(_ session: ShoppingSession, in modelContext: ModelContext) throws
}

struct ShoppingSessionService: ShoppingSessionServicing {
    @discardableResult
    func startShopping(with items: [ShoppingItem], in modelContext: ModelContext) throws -> ShoppingSession {
        try createOrResumeShoppingSession(
            with: items,
            shoppingListID: nil,
            selectedStore: nil,
            in: modelContext
        )
    }

    @discardableResult
    func startShopping(
        with items: [ShoppingItem],
        shoppingListID: UUID,
        selectedStore: MapStore,
        in modelContext: ModelContext
    ) throws -> ShoppingSession {
        try createOrResumeShoppingSession(
            with: items,
            shoppingListID: shoppingListID,
            selectedStore: selectedStore,
            in: modelContext
        )
    }

    private func createOrResumeShoppingSession(
        with items: [ShoppingItem],
        shoppingListID: UUID?,
        selectedStore: MapStore?,
        in modelContext: ModelContext
    ) throws -> ShoppingSession {
        do {
            if let activeSession = try activeSession(in: modelContext) {
                return activeSession
            }

            let activeItemIDs = items
                .filter { !$0.isCompleted }
                .map(\.id)
            let session = ShoppingSession(
                itemIDs: activeItemIDs,
                shoppingListID: shoppingListID,
                selectedStoreID: selectedStore?.id,
                selectedStoreName: selectedStore?.title,
                selectedStoreLatitude: selectedStore?.coordinate.latitude,
                selectedStoreLongitude: selectedStore?.coordinate.longitude
            )
            modelContext.insert(session)
            try modelContext.save()
            SentryReportingService.shared.breadcrumb(
                .shoppingSessionStarted,
                area: .shopping,
                numericContext: [.itemCount: activeItemIDs.count]
            )
            return session
        } catch {
            reportPersistenceError(error, itemCount: items.count)
            throw error
        }
    }

    func activeSession(in modelContext: ModelContext) throws -> ShoppingSession? {
        var descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { session in
                session.isActive == true
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            reportPersistenceError(error)
            throw error
        }
    }

    func markItemCollected(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws {
        var itemIDs = session.itemIDs
        if !itemIDs.contains(item.id) {
            itemIDs.append(item.id)
            session.itemIDs = itemIDs
        }

        var collectedItemIDs = session.collectedItemIDs
        if !collectedItemIDs.contains(item.id) {
            collectedItemIDs.append(item.id)
            session.collectedItemIDs = collectedItemIDs
        }

        do {
            try modelContext.save()
        } catch {
            reportPersistenceError(error, itemCount: session.itemIDs.count)
            throw error
        }
    }

    func markItemRemaining(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws {
        session.collectedItemIDs = session.collectedItemIDs.filter { $0 != item.id }
        do {
            try modelContext.save()
        } catch {
            reportPersistenceError(error, itemCount: session.itemIDs.count)
            throw error
        }
    }

    func remainingItemCount(for session: ShoppingSession) -> Int {
        session.remainingItemCount
    }

    func finishShopping(_ session: ShoppingSession, in modelContext: ModelContext) throws {
        session.isActive = false
        session.finishedAt = Date()
        do {
            try modelContext.save()
            SentryReportingService.shared.breadcrumb(
                .shoppingSessionCompleted,
                area: .shopping,
                numericContext: [.itemCount: session.itemIDs.count]
            )
        } catch {
            reportPersistenceError(error, itemCount: session.itemIDs.count)
            throw error
        }
    }

    private func reportPersistenceError(_ error: Error, itemCount: Int? = nil) {
        let context = itemCount.map { [SentryNumericContext.itemCount: $0] } ?? [:]
        SentryReportingService.shared.capture(
            error: error,
            message: .persistenceFailed,
            operation: .persistence,
            category: .persistence,
            area: .shopping,
            numericContext: context
        )
    }
}
