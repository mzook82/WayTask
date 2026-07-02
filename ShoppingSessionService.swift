import Foundation
import SwiftData

protocol ShoppingSessionServicing {
    @discardableResult
    func startShopping(with items: [ShoppingItem], in modelContext: ModelContext) throws -> ShoppingSession
    func activeSession(in modelContext: ModelContext) throws -> ShoppingSession?
    func markItemCollected(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws
    func markItemRemaining(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws
    func remainingItemCount(for session: ShoppingSession) -> Int
    func finishShopping(_ session: ShoppingSession, in modelContext: ModelContext) throws
}

struct ShoppingSessionService: ShoppingSessionServicing {
    @discardableResult
    func startShopping(with items: [ShoppingItem], in modelContext: ModelContext) throws -> ShoppingSession {
        try finishExistingActiveSessions(in: modelContext)

        let activeItemIDs = items
            .filter { !$0.isCompleted }
            .map(\.id)
        let session = ShoppingSession(itemIDs: activeItemIDs)
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    func activeSession(in modelContext: ModelContext) throws -> ShoppingSession? {
        var descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { session in
                session.isActive == true
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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

        try modelContext.save()
    }

    func markItemRemaining(_ item: ShoppingItem, in session: ShoppingSession, modelContext: ModelContext) throws {
        session.collectedItemIDs = session.collectedItemIDs.filter { $0 != item.id }
        try modelContext.save()
    }

    func remainingItemCount(for session: ShoppingSession) -> Int {
        session.remainingItemCount
    }

    func finishShopping(_ session: ShoppingSession, in modelContext: ModelContext) throws {
        session.isActive = false
        session.finishedAt = Date()
        try modelContext.save()
    }

    private func finishExistingActiveSessions(in modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { session in
                session.isActive == true
            }
        )
        let activeSessions = try modelContext.fetch(descriptor)

        for session in activeSessions {
            session.isActive = false
            session.finishedAt = Date()
        }

        if !activeSessions.isEmpty {
            try modelContext.save()
        }
    }
}
