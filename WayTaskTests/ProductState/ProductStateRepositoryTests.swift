import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateRepositoryTests: XCTestCase {
    func testProductRepositoryScopesIdentityAndLifecycleDeterministically()
        throws {
        let container = try makeTargetContainer()
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let firstActive = makeProduct(1, lifecycle: .active, createdAt: 20)
        let removed = makeProduct(2, lifecycle: .removed, createdAt: 10)
        let secondActive = makeProduct(3, lifecycle: .active, createdAt: 10)

        repositories.products.stageInsertion(of: firstActive)
        repositories.products.stageInsertion(of: removed)
        repositories.products.stageInsertion(of: secondActive)
        try context.save()

        let firstRead = try repositories.products.products(
            libraryLifecycle: .active
        )
        let secondRead = try repositories.products.products(
            libraryLifecycle: .active
        )

        XCTAssertEqual(firstRead.map(\.id), [uuid(3), uuid(1)])
        XCTAssertEqual(secondRead.map(\.id), firstRead.map(\.id))
        XCTAssertEqual(
            try repositories.products.products(id: uuid(2)).map(\.id),
            [uuid(2)]
        )
        XCTAssertTrue(
            try repositories.products.products(id: uuid(999)).isEmpty
        )
    }

    func testShoppingRepositoryKeepsNamedListsAndProductsIsolated() throws {
        let container = try makeTargetContainer()
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let listAID = uuid(10)
        let listBID = uuid(11)
        let sharedProductID = uuid(12)
        let otherProductID = uuid(13)
        let listAFirst = makeEntry(
            14,
            listID: listAID,
            productID: otherProductID,
            sortOrder: 1
        )
        let listASecond = makeEntry(
            15,
            listID: listAID,
            productID: sharedProductID,
            sortOrder: 2
        )
        let listBEntry = makeEntry(
            16,
            listID: listBID,
            productID: sharedProductID,
            sortOrder: 1
        )
        let listA = makeList(10, entries: [listASecond, listAFirst])
        let listB = makeList(11, entries: [listBEntry])

        repositories.shopping.stageInsertion(of: listB)
        repositories.shopping.stageInsertion(of: listA)
        try context.save()

        XCTAssertEqual(
            try repositories.shopping.shoppingLists(id: listAID).map(\.id),
            [listAID]
        )
        XCTAssertEqual(
            try repositories.shopping.shoppingEntries(listID: listAID)
                .map(\.id),
            [uuid(14), uuid(15)]
        )
        XCTAssertEqual(
            try repositories.shopping.shoppingEntries(
                listID: listAID,
                productID: sharedProductID
            ).map(\.id),
            [uuid(15)]
        )
        XCTAssertEqual(
            try repositories.shopping.shoppingEntries(
                listID: listBID,
                productID: sharedProductID
            ).map(\.id),
            [uuid(16)]
        )
        XCTAssertTrue(
            try repositories.shopping.shoppingEntries(
                id: uuid(16),
                listID: listAID
            ).isEmpty
        )
    }

    func testHistoryRepositoryScopesProductAndOrdersEventsDeterministically()
        throws {
        let container = try makeTargetContainer()
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let productID = uuid(20)
        let earlier = makeHistoryEvent(21, productID: productID, occurredAt: 10)
        let later = makeHistoryEvent(22, productID: productID, occurredAt: 20)
        let other = makeHistoryEvent(23, productID: uuid(24), occurredAt: 5)

        repositories.history.stageInsertion(of: later)
        repositories.history.stageInsertion(of: other)
        repositories.history.stageInsertion(of: earlier)
        try context.save()

        let firstRead = try repositories.history.historyEvents(
            productID: productID
        )
        let secondRead = try repositories.history.historyEvents(
            productID: productID
        )

        XCTAssertEqual(firstRead.map(\.id), [uuid(21), uuid(22)])
        XCTAssertEqual(secondRead.map(\.id), firstRead.map(\.id))
        XCTAssertEqual(
            try repositories.history.historyEvents(id: uuid(23)).map(\.id),
            [uuid(23)]
        )
    }

    func testSessionRepositoryScopesLifecycleLinesStopsAndExceptions() throws {
        let container = try makeTargetContainer()
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let active = makeSession(
            30,
            lifecycle: .active,
            startedAt: 20,
            includeOwnedRecords: true
        )
        let earlierActive = makeSession(
            31,
            lifecycle: .active,
            startedAt: 10
        )
        let finished = makeSession(
            32,
            lifecycle: .finished,
            startedAt: 5
        )

        repositories.sessions.stageInsertion(of: active)
        repositories.sessions.stageInsertion(of: finished)
        repositories.sessions.stageInsertion(of: earlierActive)
        try context.save()

        XCTAssertEqual(
            try repositories.sessions.shoppingSessions(lifecycle: .active)
                .map(\.id),
            [uuid(31), uuid(30)]
        )
        XCTAssertEqual(
            try repositories.sessions.shoppingSessions(id: uuid(32))
                .map(\.id),
            [uuid(32)]
        )
        XCTAssertEqual(
            try repositories.sessions.sessionLines(sessionID: uuid(30))
                .map(\.id),
            [uuid(34), uuid(33)]
        )
        XCTAssertEqual(
            try repositories.sessions.sessionStops(sessionID: uuid(30))
                .map(\.id),
            [uuid(36), uuid(35)]
        )
        XCTAssertEqual(
            try repositories.sessions.migrationExceptions(
                sessionID: uuid(30)
            ).map(\.id),
            [uuid(38), uuid(37)]
        )
        XCTAssertTrue(
            try repositories.sessions.sessionLines(sessionID: uuid(31))
                .isEmpty
        )
    }

    func testRepositoriesStageAcrossOneScopeWithoutIndependentSave() throws {
        let container = try makeTargetContainer()
        let stagingContext = makeContext(container)
        let repositories = ProductStateRepositories(
            modelContext: stagingContext
        )
        let product = makeProduct(50, lifecycle: .active, createdAt: 1)
        let list = makeList(51)
        let event = makeHistoryEvent(52, productID: product.id, occurredAt: 1)
        let session = makeSession(53, lifecycle: .active, startedAt: 1)

        repositories.products.stageInsertion(of: product)
        repositories.shopping.stageInsertion(of: list)
        repositories.history.stageInsertion(of: event)
        repositories.sessions.stageInsertion(of: session)

        XCTAssertFalse(stagingContext.autosaveEnabled)
        XCTAssertTrue(stagingContext.hasChanges)

        let beforeCommit = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertTrue(
            try beforeCommit.products.products(id: product.id).isEmpty
        )
        XCTAssertTrue(
            try beforeCommit.shopping.shoppingLists(id: list.id).isEmpty
        )
        XCTAssertTrue(
            try beforeCommit.history.historyEvents(id: event.id).isEmpty
        )
        XCTAssertTrue(
            try beforeCommit.sessions.shoppingSessions(id: session.id)
                .isEmpty
        )

        try stagingContext.save()

        let afterCommit = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertEqual(
            try afterCommit.products.products(id: product.id).map(\.id),
            [product.id]
        )
        XCTAssertEqual(
            try afterCommit.shopping.shoppingLists(id: list.id).map(\.id),
            [list.id]
        )
        XCTAssertEqual(
            try afterCommit.history.historyEvents(id: event.id).map(\.id),
            [event.id]
        )
        XCTAssertEqual(
            try afterCommit.sessions.shoppingSessions(id: session.id)
                .map(\.id),
            [session.id]
        )
    }

    func testShoppingDeletionIsStagedUntilExternalCommit() throws {
        let container = try makeTargetContainer()
        let setupContext = makeContext(container)
        let setupRepositories = ProductStateRepositories(
            modelContext: setupContext
        )
        let listID = uuid(60)
        let entry = makeEntry(
            61,
            listID: listID,
            productID: uuid(62),
            sortOrder: 1
        )
        setupRepositories.shopping.stageInsertion(
            of: makeList(60, entries: [entry])
        )
        try setupContext.save()

        let deletionContext = makeContext(container)
        let deletionRepositories = ProductStateRepositories(
            modelContext: deletionContext
        )
        let storedEntry = try XCTUnwrap(
            deletionRepositories.shopping.shoppingEntries(
                id: entry.id,
                listID: listID
            ).first
        )
        deletionRepositories.shopping.stageDeletion(of: storedEntry)

        let beforeCommit = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertEqual(
            try beforeCommit.shopping.shoppingEntries(listID: listID)
                .map(\.id),
            [entry.id]
        )

        try deletionContext.save()

        let afterCommit = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertTrue(
            try afterCommit.shopping.shoppingEntries(listID: listID).isEmpty
        )
    }

    func testRepeatedReadsDoNotMutateContextOrPersistAnything() throws {
        let container = try makeTargetContainer()
        let setupContext = makeContext(container)
        let setupRepositories = ProductStateRepositories(
            modelContext: setupContext
        )
        let product = makeProduct(70, lifecycle: .active, createdAt: 1)
        setupRepositories.products.stageInsertion(of: product)
        try setupContext.save()

        let readContext = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: readContext)

        XCTAssertFalse(readContext.hasChanges)
        let first = try repositories.products.products(id: product.id)
        let second = try repositories.products.products(id: product.id)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertFalse(readContext.hasChanges)
    }

    func testRepositoryConstructionDoesNotActivateTargetPersistence() throws {
        let targetContainer = try makeTargetContainer()
        _ = ProductStateRepositories(
            modelContext: makeContext(targetContainer)
        )

        XCTAssertEqual(
            Set(WayTaskModelContainer.currentSchema.entities.map(\.name)),
            [
                "GeoLocation",
                "ShoppingItem",
                "Product",
                "ShoppingList",
                "ShoppingListEntry",
                "ProductHistory",
                "ProductKnowledge",
                "ShoppingSession"
            ]
        )
        XCTAssertEqual(WayTaskSchemaMigrationPlan.schemas.count, 3)
        XCTAssertEqual(WayTaskSchemaMigrationPlan.stages.count, 2)
        XCTAssertFalse(
            WayTaskSchemaMigrationPlan.schemas.contains {
                ObjectIdentifier($0) == ObjectIdentifier(WayTaskSchemaV4.self)
            }
        )
    }

    private func makeTargetContainer() throws -> ModelContainer {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T03",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeProduct(
        _ value: Int,
        lifecycle: ProductLibraryLifecycle,
        createdAt: TimeInterval
    ) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: 1,
            libraryLifecycleRawValue: lifecycle.rawValue,
            libraryRemovedAt: lifecycle == .removed ? date(createdAt) : nil,
            name: "Product \(value)",
            sourceRawValue: ProductSource.manual.rawValue,
            createdAt: date(createdAt),
            updatedAt: date(createdAt)
        )
    }

    private func makeList(
        _ value: Int,
        entries: [WayTaskSchemaV4.ShoppingListEntry] = []
    ) -> WayTaskSchemaV4.ShoppingList {
        WayTaskSchemaV4.ShoppingList(
            id: uuid(value),
            revision: 1,
            title: "List \(value)",
            createdAt: date(Double(value)),
            updatedAt: date(Double(value)),
            entries: entries
        )
    }

    private func makeEntry(
        _ value: Int,
        listID: UUID,
        productID: UUID,
        sortOrder: Double
    ) -> WayTaskSchemaV4.ShoppingListEntry {
        WayTaskSchemaV4.ShoppingListEntry(
            id: uuid(value),
            shoppingListID: listID,
            productID: productID,
            lifecycleRawValue: "needed",
            quantity: 1,
            sortOrder: sortOrder,
            createdAt: date(Double(value)),
            updatedAt: date(Double(value))
        )
    }

    private func makeHistoryEvent(
        _ value: Int,
        productID: UUID,
        occurredAt: TimeInterval
    ) -> WayTaskSchemaV4.ProductHistoryEvent {
        WayTaskSchemaV4.ProductHistoryEvent(
            id: uuid(value),
            productID: productID,
            meaningRawValue: "needAdded",
            provenanceRawValue: "userCommand",
            occurredAt: date(occurredAt)
        )
    }

    private func makeSession(
        _ value: Int,
        lifecycle: ShoppingSessionLifecycle,
        startedAt: TimeInterval,
        includeOwnedRecords: Bool = false
    ) -> WayTaskSchemaV4.ShoppingSession {
        let sessionID = uuid(value)
        let snapshotID = uuid(value + 100)
        let lines: [WayTaskSchemaV4.ShoppingSessionLine]
        let stops: [WayTaskSchemaV4.ShoppingSessionStop]
        let exceptions: [WayTaskSchemaV4.ProductStateMigrationException]

        if includeOwnedRecords {
            lines = [
                makeLine(33, sessionID: sessionID, snapshotID: snapshotID),
                makeLine(34, sessionID: sessionID, snapshotID: snapshotID)
            ]
            stops = [
                makeStop(35, sessionID: sessionID, snapshotID: snapshotID),
                makeStop(36, sessionID: sessionID, snapshotID: snapshotID)
            ]
            exceptions = [
                makeException(37, sessionID: sessionID, ordinal: 2),
                makeException(38, sessionID: sessionID, ordinal: 1)
            ]
        } else {
            lines = []
            stops = []
            exceptions = []
        }

        return WayTaskSchemaV4.ShoppingSession(
            id: sessionID,
            sourceListID: uuid(value + 200),
            sourceRevision: 1,
            sourceRevisionProvenanceRawValue: "exact",
            revision: 1,
            lifecycleRawValue: lifecycle.rawValue,
            migrationConditionRawValue:
                ShoppingSessionMigrationCondition.native.rawValue,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "snapshot:\(value)",
            startedAt: date(startedAt),
            activationStartedAt: date(startedAt),
            lastActivityAt: date(startedAt),
            endedAt: lifecycle.isTerminal ? date(startedAt + 1) : nil,
            expirationPolicyVersion: 1,
            lines: lines,
            stops: stops,
            migrationExceptions: exceptions
        )
    }

    private func makeLine(
        _ value: Int,
        sessionID: UUID,
        snapshotID: UUID
    ) -> WayTaskSchemaV4.ShoppingSessionLine {
        WayTaskSchemaV4.ShoppingSessionLine(
            id: uuid(value),
            sessionID: sessionID,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "nativeStart",
            sortOrder: value == 34 ? 1 : 2,
            productNameSnapshot: "Line \(value)",
            quantitySnapshot: 1,
            executionStateRawValue:
                ShoppingSessionExecutionState.remaining.rawValue
        )
    }

    private func makeStop(
        _ value: Int,
        sessionID: UUID,
        snapshotID: UUID
    ) -> WayTaskSchemaV4.ShoppingSessionStop {
        WayTaskSchemaV4.ShoppingSessionStop(
            id: uuid(value),
            sessionID: sessionID,
            snapshotID: snapshotID,
            sortOrder: value == 36 ? 1 : 2,
            storeReferenceProvenanceRawValue: "fixture",
            displayNameSnapshot: "Stop \(value)",
            isSessionScopedTransient: true
        )
    }

    private func makeException(
        _ value: Int,
        sessionID: UUID,
        ordinal: Int
    ) -> WayTaskSchemaV4.ProductStateMigrationException {
        WayTaskSchemaV4.ProductStateMigrationException(
            id: uuid(value),
            sessionID: sessionID,
            categoryRawValue: "fixture",
            safeEvidenceDigest: "digest:\(value)",
            ordinal: ordinal,
            occurrenceCount: 1,
            recordedAt: date(Double(value))
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }
}
