import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateTransactionCoordinatorTests: XCTestCase {
    func testCreateCommitsOnlyAfterExactlyOneAtomicSave() throws {
        let container = try makeTargetContainer("single-save")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let command = createProductCommand(command: 1, product: 2)
        let prepared = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .normal
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        let expectedReceipt = ProductStateCommandReceipt(
            commandID: command.id,
            effects: ProductStateCommandEffects(
                revisionChanges: [
                    ProductStateRevisionChange(
                        before: ProductStateRevision(
                            scope: .product(productID(2)),
                            value: 0
                        ),
                        after: ProductStateRevision(
                            scope: .product(productID(2)),
                            value: 1
                        )
                    )
                ],
                historyEventIDs: []
            )
        )
        XCTAssertEqual(result.commandResult, .committed(expectedReceipt))
        XCTAssertEqual(result.disposition, .committed)
        XCTAssertTrue(result.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 0)
        XCTAssertEqual(scope.maximumConcurrentCommitCount, 1)
        XCTAssertFalse(context.hasChanges)

        let durable = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertEqual(
            try durable.products.products(id: uuid(2)).map(\.revision),
            [1]
        )
        XCTAssertEqual(
            try historyTransactions(
                container: container,
                commandID: command.id
            ).count,
            1
        )
    }

    func testResolveCommitsShoppingRevisionEntryAndHistoryTogether()
        throws {
        let fixture = try makeNeededEntryFixture("cross-repository")
        let command = resolveCommand(
            command: 10,
            identity: fixture.identity,
            history: 11,
            revision: 1
        )
        let prepared = ProductStateCommandCoordinator(
            repositories: fixture.repositories
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: fixture.context,
            mode: .normal
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertTrue(result.claimsDurableSuccess)
        XCTAssertEqual(result.disposition, .committed)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 0)

        guard case let .committed(receipt) = result.commandResult else {
            return XCTFail("Expected committed receipt")
        }
        XCTAssertEqual(receipt.commandID, command.id)
        XCTAssertEqual(
            receipt.effects.revisionChanges,
            [
                ProductStateRevisionChange(
                    before: ProductStateRevision(
                        scope: .list(fixture.identity.listID),
                        value: 1
                    ),
                    after: ProductStateRevision(
                        scope: .list(fixture.identity.listID),
                        value: 2
                    )
                )
            ]
        )
        XCTAssertEqual(receipt.effects.historyEventIDs, [historyID(11)])

        let durable = ProductStateRepositories(
            modelContext: makeContext(fixture.container)
        )
        let lists = try durable.shopping.shoppingLists(id: uuid(101))
        let entries = try durable.shopping.shoppingEntries(
            id: fixture.identity.id.rawValue,
            listID: fixture.identity.listID.rawValue
        )
        let events = try durable.history.historyEvents(id: uuid(11))
        XCTAssertEqual(lists.map(\.revision), [2])
        XCTAssertEqual(entries.map(\.lifecycleRawValue), ["resolved"])
        XCTAssertEqual(
            entries.map(\.resolutionReasonRawValue),
            [ShoppingListResolutionReason.alreadyHave.rawValue]
        )
        XCTAssertEqual(events.map(\.commandID), [command.id.rawValue])
    }

    func testDefiniteSaveFailureRollsBackEveryParticipant() throws {
        let fixture = try makeNeededEntryFixture("definite-failure")
        let command = resolveCommand(
            command: 20,
            identity: fixture.identity,
            history: 21,
            revision: 1
        )
        let prepared = ProductStateCommandCoordinator(
            repositories: fixture.repositories
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: fixture.context,
            mode: .definitelyNotCommitted
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertEqual(
            result.commandResult,
            .unavailable(
                commandID: command.id,
                reason: .durableAuthorityUnavailable
            )
        )
        XCTAssertEqual(result.disposition, .rolledBack(.saveFailed))
        XCTAssertFalse(result.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 1)
        XCTAssertFalse(fixture.context.hasChanges)

        let durable = ProductStateRepositories(
            modelContext: makeContext(fixture.container)
        )
        XCTAssertEqual(
            try durable.shopping.shoppingLists(id: uuid(101))
                .map(\.revision),
            [1]
        )
        XCTAssertEqual(
            try durable.shopping.shoppingEntries(
                id: fixture.identity.id.rawValue,
                listID: fixture.identity.listID.rawValue
            ).map(\.lifecycleRawValue),
            ["needed"]
        )
        XCTAssertTrue(
            try durable.history.historyEvents(id: uuid(21)).isEmpty
        )
        XCTAssertTrue(
            try historyTransactions(
                container: fixture.container,
                commandID: command.id
            ).isEmpty
        )
    }

    func testUnknownResultAfterSaveReconcilesByStableCommandIdentity()
        throws {
        let container = try makeTargetContainer("unknown-after")
        let context = makeContext(container)
        let command = createProductCommand(command: 30, product: 31)
        let prepared = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(modelContext: context)
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .unknownAfterSave
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        guard case .committed = result.commandResult else {
            return XCTFail("Expected reconciled committed result")
        }
        XCTAssertEqual(result.disposition, .reconciledCommitted)
        XCTAssertTrue(result.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 1)
        XCTAssertEqual(scope.reconciliationCount, 2)
        XCTAssertEqual(
            try ProductStateRepositories(
                modelContext: makeContext(container)
            ).products.products(id: uuid(31)).count,
            1
        )
        XCTAssertEqual(
            try historyTransactions(
                container: container,
                commandID: command.id
            ).count,
            1
        )
    }

    func testUnknownResultBeforeSaveRollsBackAndReportsUnavailable()
        throws {
        let container = try makeTargetContainer("unknown-before")
        let context = makeContext(container)
        let command = createProductCommand(command: 40, product: 41)
        let prepared = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(modelContext: context)
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .unknownBeforeSave
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertEqual(
            result.commandResult,
            .unavailable(
                commandID: command.id,
                reason: .durableAuthorityUnavailable
            )
        )
        XCTAssertEqual(result.disposition, .rolledBack(.saveFailed))
        XCTAssertFalse(result.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 1)
        XCTAssertEqual(
            try ProductStateRepositories(
                modelContext: makeContext(container)
            ).products.products(id: uuid(41)).count,
            0
        )
    }

    func testRepeatedPreparedResultDoesNotCommitOrReviseTwice() throws {
        let container = try makeTargetContainer("idempotent-retry")
        let context = makeContext(container)
        let command = createProductCommand(command: 50, product: 51)
        let prepared = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(modelContext: context)
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .normal
        )
        let coordinator = ProductStateTransactionCoordinator(scope: scope)

        let first = coordinator.commit(prepared)
        let second = coordinator.commit(prepared)

        XCTAssertEqual(first.commandResult, second.commandResult)
        XCTAssertEqual(first.disposition, .committed)
        XCTAssertEqual(second.disposition, .reconciledCommitted)
        XCTAssertTrue(first.claimsDurableSuccess)
        XCTAssertTrue(second.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 1)
        XCTAssertEqual(
            try ProductStateRepositories(
                modelContext: makeContext(container)
            ).products.products(id: uuid(51)).count,
            1
        )
        XCTAssertEqual(
            try historyTransactions(
                container: container,
                commandID: command.id
            ).count,
            1
        )
    }

    func testDuplicateHistoryIdentityRejectsBeforeCommit() throws {
        let fixture = try makeNeededEntryFixture("duplicate-history")
        let existing = WayTaskSchemaV4.ProductHistoryEvent(
            id: uuid(61),
            productID: fixture.identity.productID.rawValue,
            meaningRawValue: "needAdded",
            commandID: uuid(999),
            provenanceRawValue: "userCommand",
            occurredAt: instant
        )
        fixture.repositories.history.stageInsertion(of: existing)
        try fixture.context.save()

        let command = resolveCommand(
            command: 60,
            identity: fixture.identity,
            history: 61,
            revision: 1
        )
        let prepared = ProductStateCommandCoordinator(
            repositories: fixture.repositories
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: fixture.context,
            mode: .normal
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertEqual(
            result.disposition,
            .rolledBack(.stagedStateMismatch)
        )
        XCTAssertFalse(result.claimsDurableSuccess)
        XCTAssertEqual(scope.commitCount, 0)
        XCTAssertEqual(scope.rollbackCount, 1)

        let durable = ProductStateRepositories(
            modelContext: makeContext(fixture.container)
        )
        XCTAssertEqual(
            try durable.history.historyEvents(id: uuid(61)).count,
            1
        )
        XCTAssertEqual(
            try durable.shopping.shoppingLists(id: uuid(101))
                .map(\.revision),
            [1]
        )
        XCTAssertEqual(
            try durable.shopping.shoppingEntries(
                id: fixture.identity.id.rawValue,
                listID: fixture.identity.listID.rawValue
            ).map(\.lifecycleRawValue),
            ["needed"]
        )
    }

    func testUnrelatedStagedChangeRejectsWholeTransaction() throws {
        let container = try makeTargetContainer("staged-mismatch")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let command = createProductCommand(command: 70, product: 71)
        let prepared = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(command)
        repositories.shopping.stageInsertion(
            of: WayTaskSchemaV4.ShoppingList(
                id: uuid(72),
                revision: 1,
                title: "Unrelated",
                createdAt: instant,
                updatedAt: instant
            )
        )
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .normal
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertEqual(
            result.disposition,
            .rolledBack(.stagedStateMismatch)
        )
        XCTAssertEqual(scope.commitCount, 0)
        XCTAssertEqual(scope.rollbackCount, 1)
        let durable = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertTrue(try durable.products.products(id: uuid(71)).isEmpty)
        XCTAssertTrue(try durable.shopping.shoppingLists(id: uuid(72)).isEmpty)
    }

    func testDuplicateRevisionAndHistoryEffectsRejectBeforeSave() throws {
        let identity = entryIdentity(entry: 76, list: 75, product: 74)
        let revisionContext = makeContext(
            try makeTargetContainer("duplicate-revision-effect")
        )
        let revisionScope = FaultInjectingTransactionScope(
            modelContext: revisionContext,
            mode: .normal
        )
        let revisionCommandID = commandID(73)
        let duplicateRevision = ProductStatePreparedCommandResult.staged(
            commandID: revisionCommandID,
            effects: [
                .entryUpdated(identity: identity, listRevision: 2),
                .entryReopened(identity: identity, listRevision: 3)
            ]
        )

        let revisionResult = ProductStateTransactionCoordinator(
            scope: revisionScope
        ).commit(duplicateRevision)

        XCTAssertEqual(
            revisionResult.disposition,
            .rolledBack(.finalInvariantFailure)
        )
        XCTAssertEqual(revisionScope.commitCount, 0)
        XCTAssertEqual(revisionScope.rollbackCount, 1)

        let historyContext = makeContext(
            try makeTargetContainer("duplicate-history-effect")
        )
        let historyScope = FaultInjectingTransactionScope(
            modelContext: historyContext,
            mode: .normal
        )
        let duplicateHistory = ProductStatePreparedCommandResult.staged(
            commandID: commandID(77),
            effects: [
                .historyEventInserted(historyID(78)),
                .historyEventInserted(historyID(78))
            ]
        )

        let historyResult = ProductStateTransactionCoordinator(
            scope: historyScope
        ).commit(duplicateHistory)

        XCTAssertEqual(
            historyResult.disposition,
            .rolledBack(.finalInvariantFailure)
        )
        XCTAssertEqual(historyScope.commitCount, 0)
        XCTAssertEqual(historyScope.rollbackCount, 1)
    }

    func testStaleConflictAndNoOpNeverCommit() throws {
        let container = try makeTargetContainer("non-commit-results")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        repositories.products.stageInsertion(
            of: makeProduct(81, name: "Original", revision: 1)
        )
        try context.save()

        let staleCommand = editProductCommand(
            command: 80,
            product: 81,
            name: "Changed",
            expectedRevision: 2
        )
        let stalePrepared = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(staleCommand)
        let staleScope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .normal
        )
        let staleResult = ProductStateTransactionCoordinator(
            scope: staleScope
        ).commit(stalePrepared)

        XCTAssertEqual(
            staleResult.commandResult,
            .conflict(
                commandID: staleCommand.id,
                conflict: .staleRevision
            )
        )
        XCTAssertEqual(staleScope.commitCount, 0)
        XCTAssertEqual(staleScope.rollbackCount, 1)

        let noOpCommand = editProductCommand(
            command: 82,
            product: 81,
            name: "Original",
            expectedRevision: 1
        )
        let noOpPrepared = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(noOpCommand)
        let noOpScope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .normal
        )
        let noOpResult = ProductStateTransactionCoordinator(
            scope: noOpScope
        ).commit(noOpPrepared)

        XCTAssertEqual(
            noOpResult.commandResult,
            .noOp(
                ProductStateCommandReceipt(
                    commandID: noOpCommand.id,
                    effects: .none
                )
            )
        )
        XCTAssertEqual(noOpResult.disposition, .noCommitRequired)
        XCTAssertEqual(noOpScope.commitCount, 0)
        XCTAssertEqual(noOpScope.rollbackCount, 0)
    }

    func testUnknownInconsistentResultNeverClaimsDurableSuccess() throws {
        let container = try makeTargetContainer("unknown-inconsistent")
        let context = makeContext(container)
        let command = createProductCommand(command: 90, product: 91)
        let prepared = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(modelContext: context)
        ).prepare(command)
        let scope = FaultInjectingTransactionScope(
            modelContext: context,
            mode: .unknownBeforeSave,
            reconciliationOverride: .inconsistent
        )

        let result = ProductStateTransactionCoordinator(
            scope: scope
        ).commit(prepared)

        XCTAssertEqual(result.disposition, .outcomeUnknown)
        XCTAssertFalse(result.claimsDurableSuccess)
        XCTAssertEqual(
            result.commandResult,
            .unavailable(
                commandID: command.id,
                reason: .durableAuthorityUnavailable
            )
        )
        XCTAssertEqual(scope.commitCount, 1)
        XCTAssertEqual(scope.rollbackCount, 1)
    }

    func testSerializationAndOwnershipHaveNoProductionLeakage() throws {
        let root = repositoryRoot()
        let transactionURL = root.appendingPathComponent(
            "WayTask/ProductState/Application/" +
                "ProductStateTransactionCoordinator.swift"
        )
        let repositoryURL = root.appendingPathComponent(
            "WayTask/ProductState/Persistence/ProductStateRepositories.swift"
        )
        let projectURL = root.appendingPathComponent(
            "WayTask.xcodeproj/project.pbxproj"
        )
        let transactionSource = try String(
            contentsOf: transactionURL,
            encoding: .utf8
        )
        let repositorySource = try String(
            contentsOf: repositoryURL,
            encoding: .utf8
        )
        let projectSource = try String(
            contentsOf: projectURL,
            encoding: .utf8
        )

        let imports = transactionSource.split(separator: "\n")
            .filter { $0.hasPrefix("import ") }
            .map(String.init)
        XCTAssertEqual(Set(imports), ["import Foundation", "import SwiftData"])
        XCTAssertTrue(
            transactionSource.contains(
                "@MainActor\nfinal class ProductStateTransactionCoordinator"
            )
        )
        XCTAssertEqual(
            transactionSource.components(separatedBy: "modelContext.save()")
                .count - 1,
            1
        )
        XCTAssertFalse(repositorySource.contains(".save("))
        XCTAssertFalse(repositorySource.contains("func commit("))
        XCTAssertFalse(repositorySource.contains("func rollback("))
        XCTAssertTrue(
            projectSource.contains("IPHONEOS_DEPLOYMENT_TARGET = 26.5;")
        )

        for forbidden in [
            "import SwiftUI",
            "import CoreLocation",
            "import MapKit",
            "import UserNotifications",
            "import AVFoundation",
            "import Network",
            "import Sentry",
            "URLSession",
            "NotificationCenter",
            "ProductKnowledgeService",
            "CatalogProductPersistenceService"
        ] {
            XCTAssertFalse(transactionSource.contains(forbidden))
        }

        let productionRoot = root.appendingPathComponent("WayTask")
        let enumerator = FileManager.default.enumerator(
            at: productionRoot,
            includingPropertiesForKeys: nil
        )
        var externalCallers: [String] = []
        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.pathExtension == "swift",
                  candidate != transactionURL
            else { continue }
            let source = try String(contentsOf: candidate, encoding: .utf8)
            if source.contains("ProductStateTransactionCoordinator(") {
                externalCallers.append(candidate.path)
            }
        }
        XCTAssertTrue(externalCallers.isEmpty, externalCallers.joined(separator: "\n"))
    }

    // MARK: Fixtures

    private struct NeededEntryFixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
        let identity: ProductStateListEntryIdentity
    }

    private let instant = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeNeededEntryFixture(
        _ name: String
    ) throws -> NeededEntryFixture {
        let container = try makeTargetContainer(name)
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        let identity = entryIdentity(entry: 102, list: 101, product: 100)
        let product = makeProduct(100, name: "Product", revision: 1)
        let entry = WayTaskSchemaV4.ShoppingListEntry(
            id: identity.id.rawValue,
            shoppingListID: identity.listID.rawValue,
            productID: identity.productID.rawValue,
            lifecycleRawValue: "needed",
            quantity: 1,
            sortOrder: 1,
            createdAt: instant,
            updatedAt: instant,
            product: product
        )
        let list = WayTaskSchemaV4.ShoppingList(
            id: identity.listID.rawValue,
            revision: 1,
            title: "List",
            createdAt: instant,
            updatedAt: instant,
            entries: [entry]
        )
        repositories.products.stageInsertion(of: product)
        repositories.shopping.stageInsertion(of: list)
        try context.save()

        return NeededEntryFixture(
            container: container,
            context: context,
            repositories: repositories,
            identity: identity
        )
    }

    private func makeTargetContainer(_ name: String) throws -> ModelContainer {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T05-\(name)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func historyTransactions(
        container: ModelContainer,
        commandID: ProductStateCommandID
    ) throws -> [DefaultHistoryTransaction] {
        let context = makeContext(container)
        let author = commandID.rawValue.uuidString
        return try context.fetchHistory(
            HistoryDescriptor<DefaultHistoryTransaction>()
        ).filter { $0.author == author }
    }

    private func createProductCommand(
        command: Int,
        product: Int
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: nil,
            effectiveAt: instant,
            intent: .createProduct(
                CreateProductCommand(
                    productID: productID(product),
                    name: "Product \(product)",
                    sourceRawValue: "manual",
                    catalogID: nil
                )
            )
        )
    }

    private func editProductCommand(
        command: Int,
        product: Int,
        name: String,
        expectedRevision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: ProductStateExpectedRevision(
                revision: ProductStateRevision(
                    scope: .product(productID(product)),
                    value: expectedRevision
                )
            ),
            effectiveAt: instant,
            intent: .editProduct(
                EditProductCommand(
                    productID: productID(product),
                    name: name
                )
            )
        )
    }

    private func resolveCommand(
        command: Int,
        identity: ProductStateListEntryIdentity,
        history: Int,
        revision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: ProductStateExpectedRevision(
                revision: ProductStateRevision(
                    scope: .list(identity.listID),
                    value: revision
                )
            ),
            effectiveAt: instant,
            intent: .resolveListNeed(
                ResolveListNeedCommand(
                    entry: identity,
                    historyEventID: historyID(history),
                    reason: .alreadyHave
                )
            )
        )
    }

    private func makeProduct(
        _ value: Int,
        name: String,
        revision: UInt64
    ) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: revision,
            libraryLifecycleRawValue: ProductLibraryLifecycle.active.rawValue,
            name: name,
            sourceRawValue: "manual",
            createdAt: instant,
            updatedAt: instant
        )
    }

    private func entryIdentity(
        entry: Int,
        list: Int,
        product: Int
    ) -> ProductStateListEntryIdentity {
        ProductStateListEntryIdentity(
            id: ProductStateListEntryID(rawValue: uuid(entry)),
            listID: ProductStateListID(rawValue: uuid(list)),
            productID: productID(product)
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func commandID(_ value: Int) -> ProductStateCommandID {
        ProductStateCommandID(rawValue: uuid(value))
    }

    private func historyID(_ value: Int) -> ProductStateHistoryEventID {
        ProductStateHistoryEventID(rawValue: uuid(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}

@MainActor
private final class FaultInjectingTransactionScope:
    ProductStateTransactionScope {
    enum Mode {
        case normal
        case definitelyNotCommitted
        case unknownBeforeSave
        case unknownAfterSave
    }

    private let base: SwiftDataProductStateTransactionScope
    private let mode: Mode
    private let reconciliationOverride: ProductStateCommitReconciliation?
    private(set) var commitCount = 0
    private(set) var rollbackCount = 0
    private(set) var reconciliationCount = 0
    private(set) var maximumConcurrentCommitCount = 0
    private var activeCommitCount = 0

    init(
        modelContext: ModelContext,
        mode: Mode,
        reconciliationOverride: ProductStateCommitReconciliation? = nil
    ) {
        base = SwiftDataProductStateTransactionScope(
            modelContext: modelContext
        )
        self.mode = mode
        self.reconciliationOverride = reconciliationOverride
    }

    var hasChanges: Bool { base.hasChanges }

    func verifyStagedConsistency(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws {
        try base.verifyStagedConsistency(
            commandID: commandID,
            effects: effects
        )
    }

    func commitOnce(commandID: ProductStateCommandID) throws {
        commitCount += 1
        activeCommitCount += 1
        maximumConcurrentCommitCount = max(
            maximumConcurrentCommitCount,
            activeCommitCount
        )
        defer { activeCommitCount -= 1 }

        switch mode {
        case .normal:
            try base.commitOnce(commandID: commandID)
        case .definitelyNotCommitted:
            throw ProductStateTransactionCommitFailure.definitelyNotCommitted
        case .unknownBeforeSave:
            throw ProductStateTransactionCommitFailure.outcomeUnknown
        case .unknownAfterSave:
            try base.commitOnce(commandID: commandID)
            throw ProductStateTransactionCommitFailure.outcomeUnknown
        }
    }

    func rollback() {
        rollbackCount += 1
        base.rollback()
    }

    func reconcile(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws -> ProductStateCommitReconciliation {
        reconciliationCount += 1
        if reconciliationCount > 1,
           let reconciliationOverride
        {
            return reconciliationOverride
        }
        return try base.reconcile(
            commandID: commandID,
            effects: effects
        )
    }
}
