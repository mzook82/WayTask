import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateCommandPipelineTests: XCTestCase {
    func testCommandVocabularyContainsEveryApprovedCategory() {
        XCTAssertEqual(
            Set(ProductStateCommandCategory.allCases),
            [
                .createProduct,
                .editProduct,
                .removeProductFromLibrary,
                .restoreProductToLibrary,
                .createNamedList,
                .renameNamedList,
                .deleteNamedList,
                .addProductToList,
                .updateListEntry,
                .resolveListNeed,
                .reopenListNeed,
                .removeProductFromNamedList,
                .generatePlan,
                .supersedePlan,
                .startSession,
                .resumeSession,
                .markLineCollected,
                .undoLineCollection,
                .prepareFinishOutcome,
                .finishSession,
                .abandonSession,
                .createSavedLocation,
                .editSavedLocation,
                .removeSavedLocation
            ]
        )
    }

    func testShapeValidationIsDeterministicSortedAndDuplicateFree() {
        let zero = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ))
        let command = ProductStateCommand(
            id: ProductStateCommandID(rawValue: zero),
            expectedRevision: nil,
            effectiveAt: instant,
            intent: .editProduct(
                EditProductCommand(
                    productID: ProductStateProductID(rawValue: zero),
                    name: "  "
                )
            )
        )
        let validator = ProductStateCommandShapeValidator()

        let first = validator.validate(command)
        let second = validator.validate(command)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)
        XCTAssertEqual(first, first.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(
            Set(first),
            [
                .invalidCommandIdentity,
                .invalidScopeIdentity,
                .invalidName,
                .missingExpectedRevision
            ]
        )
    }

    func testCreateProductStagesWithoutDurableSuccessOrGlobalCompletion()
        throws {
        let container = try makeTargetContainer("create")
        let stagingContext = makeContext(container)
        let repositories = ProductStateRepositories(
            modelContext: stagingContext
        )
        let command = createProductCommand(command: 1, product: 2)

        let result = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(command)

        XCTAssertEqual(
            result,
            .staged(
                commandID: command.id,
                effects: [
                    .productInserted(
                        id: ProductStateProductID(rawValue: uuid(2)),
                        revision: 1
                    )
                ]
            )
        )
        XCTAssertFalse(result.claimsDurableSuccess)
        XCTAssertEqual(result.commandID, command.id)
        XCTAssertTrue(stagingContext.hasChanges)
        XCTAssertTrue(
            try repositories.shopping.shoppingLists(id: uuid(80)).isEmpty
        )
        XCTAssertTrue(
            try repositories.history.historyEvents(productID: uuid(2))
                .isEmpty
        )

        let independent = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        XCTAssertTrue(
            try independent.products.products(id: uuid(2)).isEmpty
        )
    }

    func testExpectedRevisionClassifiesNoOpAndConflictWithoutMutation()
        throws {
        let container = try makeTargetContainer("revision")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        repositories.products.stageInsertion(
            of: makeProduct(10, name: "Milk", revision: 4)
        )
        try context.save()
        let coordinator = ProductStateCommandCoordinator(
            repositories: repositories
        )
        let noOp = editProductCommand(
            command: 11,
            product: 10,
            name: "Milk",
            expectedRevision: 4
        )

        XCTAssertEqual(
            coordinator.prepare(noOp),
            .noOp(commandID: noOp.id)
        )
        XCTAssertFalse(context.hasChanges)

        let stale = editProductCommand(
            command: 12,
            product: 10,
            name: "Oat Milk",
            expectedRevision: 3
        )
        XCTAssertEqual(
            coordinator.prepare(stale),
            .conflict(
                commandID: stale.id,
                conflict: .approved(.staleRevision)
            )
        )
        let stored = try XCTUnwrap(
            repositories.products.products(id: uuid(10)).first
        )
        XCTAssertEqual(stored.name, "Milk")
        XCTAssertEqual(stored.revision, 4)
        XCTAssertFalse(context.hasChanges)
    }

    func testMissingExpectedRevisionIsValidationFailureBeforeRepositoryLoad()
        throws {
        let container = try makeTargetContainer("missing-revision")
        let repositories = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        let command = ProductStateCommand(
            id: commandID(20),
            expectedRevision: nil,
            effectiveAt: instant,
            intent: .renameNamedList(
                RenameNamedListCommand(
                    listID: listID(21),
                    title: "Renamed"
                )
            )
        )

        XCTAssertEqual(
            ProductStateCommandCoordinator(repositories: repositories)
                .prepare(command),
            .validationFailure(
                commandID: command.id,
                failure: ProductStatePreparedValidationFailure(
                    shapeViolations: [.missingExpectedRevision],
                    invariantViolations: []
                )
            )
        )
    }

    func testRepositoryFailureClassifiesUnavailableAndPreservesCommandID()
        throws {
        let container = try makeTargetContainer("unavailable")
        let repositories = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        let command = createProductCommand(command: 30, product: 31)
        let coordinator = ProductStateCommandCoordinator(
            products: UnavailableProductRepository(),
            shopping: repositories.shopping,
            history: repositories.history,
            sessions: repositories.sessions
        )

        let result = coordinator.prepare(command)

        XCTAssertEqual(
            result,
            .unavailable(
                commandID: command.id,
                reason: .durableAuthorityUnavailable
            )
        )
        XCTAssertFalse(result.claimsDurableSuccess)
    }

    func testProductRestorationRequiresExplicitIntentAndPreservesIdentity()
        throws {
        let container = try makeTargetContainer("restore")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        repositories.products.stageInsertion(
            of: makeProduct(
                40,
                name: "Bread",
                revision: 7,
                lifecycle: .removed
            )
        )
        try context.save()
        let coordinator = ProductStateCommandCoordinator(
            repositories: repositories
        )
        let rejected = restoreCommand(
            command: 41,
            product: 40,
            history: 42,
            revision: 7,
            confirmed: false
        )

        guard case let .validationFailure(_, failure) =
                coordinator.prepare(rejected)
        else {
            return XCTFail("Expected explicit-intent validation failure")
        }
        XCTAssertEqual(failure.shapeViolations, [.missingConfirmation])
        XCTAssertFalse(context.hasChanges)

        let accepted = restoreCommand(
            command: 43,
            product: 40,
            history: 44,
            revision: 7,
            confirmed: true
        )
        guard case let .staged(commandID, effects) =
                coordinator.prepare(accepted)
        else {
            return XCTFail("Expected staged restoration")
        }
        XCTAssertEqual(commandID, accepted.id)
        XCTAssertEqual(
            effects,
            [
                .productRestored(
                    id: productID(40),
                    beforeRevision: 7,
                    afterRevision: 8
                ),
                .historyEventInserted(historyID(44))
            ]
        )
        let product = try XCTUnwrap(
            repositories.products.products(id: uuid(40)).first
        )
        XCTAssertEqual(product.id, uuid(40))
        XCTAssertEqual(product.libraryLifecycleRawValue, "active")
        XCTAssertEqual(product.revision, 8)
    }

    func testAddEntryIsExactListScopedAndDoesNotAffectAnotherList()
        throws {
        let container = try makeTargetContainer("list-isolation")
        let context = makeContext(container)
        let repositories = ProductStateRepositories(modelContext: context)
        repositories.products.stageInsertion(
            of: makeProduct(50, name: "Eggs", revision: 1)
        )
        repositories.shopping.stageInsertion(of: makeList(51))
        repositories.shopping.stageInsertion(of: makeList(52))
        try context.save()
        let identity = entryIdentity(entry: 53, list: 51, product: 50)
        let command = ProductStateCommand(
            id: commandID(54),
            expectedRevision: expectedListRevision(1, list: 51),
            effectiveAt: instant,
            intent: .addProductToList(
                AddProductToListCommand(
                    entry: identity,
                    historyEventID: historyID(55),
                    quantity: 2,
                    unitRawValue: "carton",
                    note: nil,
                    sortOrder: 1
                )
            )
        )

        let result = ProductStateCommandCoordinator(
            repositories: repositories
        ).prepare(command)

        guard case .staged = result else {
            return XCTFail("Expected staged exact-list insertion")
        }
        XCTAssertEqual(
            try repositories.shopping.shoppingLists(id: uuid(51)).first?
                .revision,
            2
        )
        XCTAssertEqual(
            try repositories.shopping.shoppingLists(id: uuid(52)).first?
                .revision,
            1
        )
        XCTAssertEqual(
            try repositories.shopping.shoppingEntries(listID: uuid(51))
                .map(\.id),
            [uuid(53)]
        )
        XCTAssertTrue(
            try repositories.shopping.shoppingEntries(listID: uuid(52))
                .isEmpty
        )
    }

    func testResolutionRejectsPurchasedAndLegacyUnknownAsDirectCommands()
        throws {
        let container = try makeTargetContainer("resolution-shape")
        let repositories = ProductStateRepositories(
            modelContext: makeContext(container)
        )
        let coordinator = ProductStateCommandCoordinator(
            repositories: repositories
        )
        for (offset, reason) in [
            ShoppingListResolutionReason.purchased,
            .legacyUnknown
        ].enumerated() {
            let command = resolveCommand(
                command: 60 + offset,
                identity: entryIdentity(entry: 62, list: 63, product: 64),
                history: 65 + offset,
                revision: 1,
                reason: reason
            )

            guard case let .validationFailure(_, failure) =
                    coordinator.prepare(command)
            else {
                return XCTFail("Expected migration/session-only restriction")
            }
            XCTAssertEqual(
                failure.shapeViolations,
                [.invalidResolutionReason]
            )
            XCTAssertTrue(failure.invariantViolations.isEmpty)
        }
    }

    func testResolveAndReopenPreserveEntryIdentityAndStageHistory()
        throws {
        let container = try makeTargetContainer("resolve-reopen")
        let setupContext = makeContext(container)
        let setup = ProductStateRepositories(modelContext: setupContext)
        let identity = entryIdentity(entry: 70, list: 71, product: 72)
        let product = makeProduct(72, name: "Rice", revision: 1)
        let entry = makeEntry(identity, lifecycle: "needed")
        setup.products.stageInsertion(of: product)
        setup.shopping.stageInsertion(of: makeList(71, entries: [entry]))
        try setupContext.save()

        let resolveContext = makeContext(container)
        let resolveRepositories = ProductStateRepositories(
            modelContext: resolveContext
        )
        let resolve = resolveCommand(
            command: 73,
            identity: identity,
            history: 74,
            revision: 1,
            reason: .alreadyHave
        )
        guard case .staged = ProductStateCommandCoordinator(
            repositories: resolveRepositories
        ).prepare(resolve) else {
            return XCTFail("Expected staged resolution")
        }
        let resolved = try XCTUnwrap(
            resolveRepositories.shopping.shoppingEntries(
                id: uuid(70),
                listID: uuid(71)
            ).first
        )
        XCTAssertEqual(resolved.id, identity.id.rawValue)
        XCTAssertEqual(resolved.lifecycleRawValue, "resolved")
        XCTAssertEqual(resolved.resolutionReasonRawValue, "alreadyHave")
        XCTAssertEqual(
            try resolveRepositories.history.historyEvents(
                productID: uuid(72)
            ).map(\.id),
            [uuid(74)]
        )
        try resolveContext.save()

        let reopenContext = makeContext(container)
        let reopenRepositories = ProductStateRepositories(
            modelContext: reopenContext
        )
        let reopen = ProductStateCommand(
            id: commandID(75),
            expectedRevision: expectedListRevision(2, list: 71),
            effectiveAt: instant.addingTimeInterval(1),
            intent: .reopenListNeed(
                ReopenListNeedCommand(
                    entry: identity,
                    historyEventID: historyID(76)
                )
            )
        )
        guard case .staged = ProductStateCommandCoordinator(
            repositories: reopenRepositories
        ).prepare(reopen) else {
            return XCTFail("Expected staged reopen")
        }
        let reopened = try XCTUnwrap(
            reopenRepositories.shopping.shoppingEntries(
                id: uuid(70),
                listID: uuid(71)
            ).first
        )
        XCTAssertEqual(reopened.id, identity.id.rawValue)
        XCTAssertEqual(reopened.lifecycleRawValue, "needed")
        XCTAssertNil(reopened.resolutionReasonRawValue)
    }

    func testCollectedPreparedOutcomeAndFinishRemainSeparateAndDeferred()
        throws {
        let container = try makeTargetContainer("session-deferred")
        let coordinator = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(
                modelContext: makeContext(container)
            )
        )
        let session = ProductStateSessionID(rawValue: uuid(80))
        let line = ProductStateSessionLineID(rawValue: uuid(81))
        let expected = ProductStateExpectedRevision(
            revision: ProductStateRevision(
                scope: .session(session),
                value: 1
            )
        )
        let commands = [
            ProductStateCommand(
                id: commandID(82),
                expectedRevision: expected,
                effectiveAt: instant,
                intent: .markLineCollected(
                    SessionLineCommand(sessionID: session, lineID: line)
                )
            ),
            ProductStateCommand(
                id: commandID(83),
                expectedRevision: expected,
                effectiveAt: instant,
                intent: .prepareFinishOutcome(
                    PrepareFinishOutcomeCommand(
                        sessionID: session,
                        lineID: line,
                        outcome: .purchased
                    )
                )
            ),
            ProductStateCommand(
                id: commandID(84),
                expectedRevision: expected,
                effectiveAt: instant,
                intent: .finishSession(
                    FinishSessionCommand(
                        sessionID: session,
                        outcomes: [
                            FinishSessionLineOutcome(
                                lineID: line,
                                outcome: .purchased
                            )
                        ],
                        confirmed: true
                    )
                )
            )
        ]

        XCTAssertEqual(
            commands.map(\.category),
            [.markLineCollected, .prepareFinishOutcome, .finishSession]
        )
        for command in commands {
            let result = coordinator.prepare(command)
            XCTAssertEqual(
                result,
                .unavailable(
                    commandID: command.id,
                    reason: .unsupportedOperation
                )
            )
            XCTAssertFalse(result.claimsDurableSuccess)
        }
    }

    func testRepeatedIdenticalInputProducesSameResultAndStagedMeaning()
        throws {
        let command = createProductCommand(command: 90, product: 91)
        let firstContainer = try makeTargetContainer("determinism-a")
        let secondContainer = try makeTargetContainer("determinism-b")
        let firstContext = makeContext(firstContainer)
        let secondContext = makeContext(secondContainer)

        let first = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(
                modelContext: firstContext
            )
        ).prepare(command)
        let second = ProductStateCommandCoordinator(
            repositories: ProductStateRepositories(
                modelContext: secondContext
            )
        ).prepare(command)

        XCTAssertEqual(first, second)
        XCTAssertTrue(firstContext.hasChanges)
        XCTAssertTrue(secondContext.hasChanges)
        XCTAssertFalse(first.claimsDurableSuccess)
        XCTAssertFalse(second.claimsDurableSuccess)
    }

    func testApplicationSourcesHaveNoCommitContextOrIntegrationLeakage()
        throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let application = repositoryRoot
            .appendingPathComponent("WayTask/ProductState/Application")
        let sources = try [
            "ProductStateCommands.swift",
            "ProductStateCommandCoordinator.swift"
        ].map { filename in
            try String(
                contentsOf: application.appendingPathComponent(filename),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        let imports = sources.split(separator: "\n")
            .filter { $0.hasPrefix("import ") }
            .map(String.init)
        XCTAssertEqual(Set(imports), ["import Foundation"])

        for forbidden in [
            "import SwiftUI",
            "import SwiftData",
            "import CoreLocation",
            "import MapKit",
            "import UserNotifications",
            "import AVFoundation",
            "import Network",
            "import Sentry",
            "ModelContext(",
            ".save(",
            "autosaveEnabled",
            "func commit(",
            "func rollback(",
            "URLSession",
            "NotificationCenter",
            "ProductKnowledgeService",
            "CatalogProductPersistenceService",
            "completionState"
        ] {
            XCTAssertFalse(
                sources.contains(forbidden),
                "Forbidden T-04 source token: \(forbidden)"
            )
        }
    }

    // MARK: Fixtures

    private let instant = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeTargetContainer(_ name: String) throws -> ModelContainer {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T04-\(name)",
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

    private func restoreCommand(
        command: Int,
        product: Int,
        history: Int,
        revision: UInt64,
        confirmed: Bool
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: ProductStateExpectedRevision(
                revision: ProductStateRevision(
                    scope: .product(productID(product)),
                    value: revision
                )
            ),
            effectiveAt: instant,
            intent: .restoreProductToLibrary(
                RestoreProductToLibraryCommand(
                    productID: productID(product),
                    historyEventID: historyID(history),
                    confirmed: confirmed
                )
            )
        )
    }

    private func resolveCommand(
        command: Int,
        identity: ProductStateListEntryIdentity,
        history: Int,
        revision: UInt64,
        reason: ShoppingListResolutionReason
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
                    reason: reason
                )
            )
        )
    }

    private func expectedListRevision(
        _ value: UInt64,
        list: Int
    ) -> ProductStateExpectedRevision {
        ProductStateExpectedRevision(
            revision: ProductStateRevision(
                scope: .list(listID(list)),
                value: value
            )
        )
    }

    private func makeProduct(
        _ value: Int,
        name: String,
        revision: UInt64,
        lifecycle: ProductLibraryLifecycle = .active
    ) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: revision,
            libraryLifecycleRawValue: lifecycle.rawValue,
            libraryRemovedAt: lifecycle == .removed ? instant : nil,
            name: name,
            sourceRawValue: "manual",
            createdAt: instant,
            updatedAt: instant
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
            createdAt: instant,
            updatedAt: instant,
            entries: entries
        )
    }

    private func makeEntry(
        _ identity: ProductStateListEntryIdentity,
        lifecycle: String
    ) -> WayTaskSchemaV4.ShoppingListEntry {
        WayTaskSchemaV4.ShoppingListEntry(
            id: identity.id.rawValue,
            shoppingListID: identity.listID.rawValue,
            productID: identity.productID.rawValue,
            lifecycleRawValue: lifecycle,
            quantity: 1,
            sortOrder: 1,
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
            listID: listID(list),
            productID: productID(product)
        )
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(value))
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
private final class UnavailableProductRepository: ProductRepository {
    private enum Failure: Error { case unavailable }

    func products(id: UUID) throws -> [WayTaskSchemaV4.Product] {
        throw Failure.unavailable
    }

    func products(
        libraryLifecycle: ProductLibraryLifecycle
    ) throws -> [WayTaskSchemaV4.Product] {
        throw Failure.unavailable
    }

    func stageInsertion(of product: WayTaskSchemaV4.Product) {
        XCTFail("Unavailable repository must not stage")
    }
}
