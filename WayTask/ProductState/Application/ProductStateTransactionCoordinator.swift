import Foundation
import SwiftData

enum ProductStateTransactionCommitFailure: Error, Equatable, Sendable {
    case definitelyNotCommitted
    case outcomeUnknown
}

enum ProductStateCommitReconciliation: Equatable, Sendable {
    case committed
    case notCommitted
    case inconsistent
}

enum ProductStateTransactionFailure: String, Equatable, Sendable {
    case preparedResultRejected
    case stagedStateMismatch
    case finalInvariantFailure
    case saveFailed
    case reconciliationFailed
    case commitOutcomeUnknown
}

enum ProductStateTransactionDisposition: Equatable, Sendable {
    case committed
    case noCommitRequired
    case reconciledCommitted
    case rolledBack(ProductStateTransactionFailure)
    case outcomeUnknown
}

struct ProductStateTransactionResult: Equatable, Sendable {
    let commandResult: ProductStateCommandResult
    let preparedResult: ProductStatePreparedCommandResult
    let disposition: ProductStateTransactionDisposition

    var commandID: ProductStateCommandID { commandResult.commandID }

    var claimsDurableSuccess: Bool {
        guard case .committed = commandResult else { return false }
        switch disposition {
        case .committed, .reconciledCommitted:
            return true
        case .noCommitRequired, .rolledBack, .outcomeUnknown:
            return false
        }
    }
}

@MainActor
protocol ProductStateTransactionScope: AnyObject {
    var hasChanges: Bool { get }

    func verifyStagedConsistency(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws

    func commitOnce(commandID: ProductStateCommandID) throws
    func rollback()

    func reconcile(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws -> ProductStateCommitReconciliation
}

/// The only T-05 owner of durable Product State commit and rollback.
///
/// Synchronous MainActor isolation serializes command commits on every
/// supported deployment target. All repositories participating in a prepared
/// command must share the one context supplied to this coordinator.
@MainActor
final class ProductStateTransactionCoordinator {
    private let scope: any ProductStateTransactionScope
    private let invariantValidator: ProductStateInvariantValidator

    init(
        modelContext: ModelContext,
        invariantValidator: ProductStateInvariantValidator? = nil
    ) {
        modelContext.autosaveEnabled = false
        scope = SwiftDataProductStateTransactionScope(
            modelContext: modelContext
        )
        self.invariantValidator = invariantValidator
            ?? ProductStateInvariantValidator()
    }

    init(
        scope: any ProductStateTransactionScope,
        invariantValidator: ProductStateInvariantValidator? = nil
    ) {
        self.scope = scope
        self.invariantValidator = invariantValidator
            ?? ProductStateInvariantValidator()
    }

    func commit(
        _ prepared: ProductStatePreparedCommandResult
    ) -> ProductStateTransactionResult {
        switch prepared {
        case let .staged(commandID, effects):
            return commitStaged(
                prepared,
                commandID: commandID,
                effects: effects
            )

        case let .noOp(commandID):
            guard !scope.hasChanges else {
                return rollbackUnavailable(
                    prepared,
                    commandID: commandID,
                    failure: .stagedStateMismatch
                )
            }
            return ProductStateTransactionResult(
                commandResult: .noOp(
                    ProductStateCommandReceipt(
                        commandID: commandID,
                        effects: .none
                    )
                ),
                preparedResult: prepared,
                disposition: .noCommitRequired
            )

        case let .conflict(commandID, conflict):
            scope.rollback()
            return ProductStateTransactionResult(
                commandResult: mapConflict(
                    commandID: commandID,
                    conflict: conflict
                ),
                preparedResult: prepared,
                disposition: .rolledBack(.preparedResultRejected)
            )

        case let .validationFailure(commandID, failure):
            scope.rollback()
            return ProductStateTransactionResult(
                commandResult: .validationFailure(
                    commandID: commandID,
                    violations: failure.invariantViolations.map {
                        ProductStateInvariantViolation(code: $0)
                    }
                ),
                preparedResult: prepared,
                disposition: .rolledBack(.preparedResultRejected)
            )

        case let .unavailable(commandID, reason):
            scope.rollback()
            return ProductStateTransactionResult(
                commandResult: .unavailable(
                    commandID: commandID,
                    reason: reason
                ),
                preparedResult: prepared,
                disposition: .rolledBack(.preparedResultRejected)
            )
        }
    }

    private func commitStaged(
        _ prepared: ProductStatePreparedCommandResult,
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) -> ProductStateTransactionResult {
        guard let receipt = makeReceipt(
            commandID: commandID,
            effects: effects
        ) else {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .finalInvariantFailure
            )
        }

        let committedResult = ProductStateCommandResult.committed(receipt)
        let violations = invariantValidator.validate(
            ProductStateInvariantInput(commandResults: [committedResult])
        )
        guard violations.isEmpty else {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .finalInvariantFailure
            )
        }

        do {
            switch try scope.reconcile(
                commandID: commandID,
                effects: effects
            ) {
            case .committed:
                scope.rollback()
                return ProductStateTransactionResult(
                    commandResult: committedResult,
                    preparedResult: prepared,
                    disposition: .reconciledCommitted
                )
            case .notCommitted:
                break
            case .inconsistent:
                return rollbackUnavailable(
                    prepared,
                    commandID: commandID,
                    failure: .stagedStateMismatch
                )
            }
        } catch {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .reconciliationFailed
            )
        }

        guard scope.hasChanges else {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .stagedStateMismatch
            )
        }

        do {
            try scope.verifyStagedConsistency(
                commandID: commandID,
                effects: effects
            )
        } catch {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .stagedStateMismatch
            )
        }

        do {
            try scope.commitOnce(commandID: commandID)
            return ProductStateTransactionResult(
                commandResult: committedResult,
                preparedResult: prepared,
                disposition: .committed
            )
        } catch ProductStateTransactionCommitFailure.definitelyNotCommitted {
            return rollbackUnavailable(
                prepared,
                commandID: commandID,
                failure: .saveFailed
            )
        } catch {
            scope.rollback()
            return reconcileUnknownCommit(
                prepared,
                committedResult: committedResult,
                commandID: commandID,
                effects: effects
            )
        }
    }

    private func reconcileUnknownCommit(
        _ prepared: ProductStatePreparedCommandResult,
        committedResult: ProductStateCommandResult,
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) -> ProductStateTransactionResult {
        do {
            switch try scope.reconcile(
                commandID: commandID,
                effects: effects
            ) {
            case .committed:
                return ProductStateTransactionResult(
                    commandResult: committedResult,
                    preparedResult: prepared,
                    disposition: .reconciledCommitted
                )
            case .notCommitted:
                return ProductStateTransactionResult(
                    commandResult: .unavailable(
                        commandID: commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    preparedResult: prepared,
                    disposition: .rolledBack(.saveFailed)
                )
            case .inconsistent:
                return ProductStateTransactionResult(
                    commandResult: .unavailable(
                        commandID: commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    preparedResult: prepared,
                    disposition: .outcomeUnknown
                )
            }
        } catch {
            return ProductStateTransactionResult(
                commandResult: .unavailable(
                    commandID: commandID,
                    reason: .durableAuthorityUnavailable
                ),
                preparedResult: prepared,
                disposition: .outcomeUnknown
            )
        }
    }

    private func rollbackUnavailable(
        _ prepared: ProductStatePreparedCommandResult,
        commandID: ProductStateCommandID,
        failure: ProductStateTransactionFailure
    ) -> ProductStateTransactionResult {
        scope.rollback()
        return ProductStateTransactionResult(
            commandResult: .unavailable(
                commandID: commandID,
                reason: .durableAuthorityUnavailable
            ),
            preparedResult: prepared,
            disposition: .rolledBack(failure)
        )
    }

    private func mapConflict(
        commandID: ProductStateCommandID,
        conflict: ProductStateCommandPipelineConflict
    ) -> ProductStateCommandResult {
        switch conflict {
        case let .approved(approved):
            .conflict(commandID: commandID, conflict: approved)
        case .missingTarget, .duplicateTarget:
            .conflict(commandID: commandID, conflict: .ambiguousIdentity)
        }
    }

    private func makeReceipt(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) -> ProductStateCommandReceipt? {
        guard !effects.isEmpty,
              Set(effects).count == effects.count
        else { return nil }

        var revisions: [
            ProductStateRevisionScope: (before: UInt64, after: UInt64)
        ] = [:]
        var historyIDs: [ProductStateHistoryEventID] = []

        for effect in effects {
            let change: (
                scope: ProductStateRevisionScope,
                before: UInt64,
                after: UInt64
            )?

            switch effect {
            case let .productInserted(id, revision):
                change = (.product(id), 0, revision)
            case let .productEdited(id, before, after),
                 let .productRestored(id, before, after):
                change = (.product(id), before, after)
            case let .listInserted(id, revision):
                change = (.list(id), 0, revision)
            case let .listRenamed(id, before, after):
                change = (.list(id), before, after)
            case let .entryInserted(identity, revision),
                 let .entryUpdated(identity, revision),
                 let .entryResolved(identity, _, revision),
                 let .entryReopened(identity, revision),
                 let .entryDeleted(identity, revision):
                guard revision > 0 else { return nil }
                change = (.list(identity.listID), revision - 1, revision)
            case let .historyEventInserted(id):
                historyIDs.append(id)
                change = nil
            }

            if let change {
                if let existing = revisions[change.scope],
                   existing != (change.before, change.after)
                {
                    return nil
                }
                revisions[change.scope] = (change.before, change.after)
            }
        }

        guard Set(historyIDs).count == historyIDs.count else { return nil }

        let revisionChanges = revisions
            .map { scope, values in
                ProductStateRevisionChange(
                    before: ProductStateRevision(
                        scope: scope,
                        value: values.before
                    ),
                    after: ProductStateRevision(
                        scope: scope,
                        value: values.after
                    )
                )
            }
            .sorted { revisionSortKey($0.before.scope)
                < revisionSortKey($1.before.scope) }

        return ProductStateCommandReceipt(
            commandID: commandID,
            effects: ProductStateCommandEffects(
                revisionChanges: revisionChanges,
                historyEventIDs: historyIDs.sorted {
                    $0.rawValue.uuidString < $1.rawValue.uuidString
                }
            )
        )
    }

    private func revisionSortKey(
        _ scope: ProductStateRevisionScope
    ) -> String {
        switch scope {
        case let .product(id):
            "product:\(id.rawValue.uuidString)"
        case let .list(id):
            "list:\(id.rawValue.uuidString)"
        case let .session(id):
            "session:\(id.rawValue.uuidString)"
        case let .history(id):
            "history:\(id.rawValue.uuidString)"
        }
    }
}

@MainActor
final class SwiftDataProductStateTransactionScope:
    ProductStateTransactionScope {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        modelContext.autosaveEnabled = false
    }

    var hasChanges: Bool { modelContext.hasChanges }

    func verifyStagedConsistency(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws {
        modelContext.processPendingChanges()
        guard modelContext.hasChanges else {
            throw ProductStateTransactionScopeError.noStagedChanges
        }

        let expected = expectedInventory(for: effects)
        let actual = try actualInventory()
        guard expected == actual else {
            throw ProductStateTransactionScopeError.unexpectedStagedChanges
        }

        let repositories = ProductStateRepositories(
            modelContext: modelContext
        )
        guard try evaluate(
            commandID: commandID,
            effects: effects,
            repositories: repositories
        ) == .committed else {
            throw ProductStateTransactionScopeError.effectMismatch
        }
    }

    func commitOnce(commandID: ProductStateCommandID) throws {
        modelContext.author = commandID.rawValue.uuidString
        do {
            try modelContext.save()
        } catch {
            throw ProductStateTransactionCommitFailure.outcomeUnknown
        }
    }

    func rollback() {
        modelContext.rollback()
    }

    func reconcile(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    ) throws -> ProductStateCommitReconciliation {
        let readContext = ModelContext(modelContext.container)
        readContext.autosaveEnabled = false
        let author = commandID.rawValue.uuidString
        let transactions = try readContext.fetchHistory(
            HistoryDescriptor<DefaultHistoryTransaction>()
        ).filter { $0.author == author }

        let repositories = ProductStateRepositories(
            modelContext: readContext
        )
        let effectState = try evaluate(
            commandID: commandID,
            effects: effects,
            repositories: repositories
        )

        if transactions.count == 1 && effectState == .committed {
            return .committed
        }
        if transactions.isEmpty && effectState == .notCommitted {
            return .notCommitted
        }
        return .inconsistent
    }

    private enum ProductStateTransactionScopeError: Error {
        case noStagedChanges
        case unexpectedStagedChanges
        case effectMismatch
        case unknownModel
    }

    private enum ModelKind: String, Comparable {
        case product
        case list
        case entry
        case history
        case session
        case sessionLine
        case sessionStop
        case migrationException

        static func < (lhs: ModelKind, rhs: ModelKind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct ModelKey: Hashable, Comparable {
        let kind: ModelKind
        let id: UUID

        static func < (lhs: ModelKey, rhs: ModelKey) -> Bool {
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private struct ChangeInventory: Equatable {
        var inserted: [ModelKey] = []
        var changed: [ModelKey] = []
        var deleted: [ModelKey] = []
    }

    private func expectedInventory(
        for effects: [ProductStateStagedEffect]
    ) -> ChangeInventory {
        var inventory = ChangeInventory()

        for effect in effects {
            switch effect {
            case let .productInserted(id, _):
                inventory.inserted.append(
                    ModelKey(kind: .product, id: id.rawValue)
                )
            case let .productEdited(id, _, _),
                 let .productRestored(id, _, _):
                inventory.changed.append(
                    ModelKey(kind: .product, id: id.rawValue)
                )
            case let .listInserted(id, _):
                inventory.inserted.append(
                    ModelKey(kind: .list, id: id.rawValue)
                )
            case let .listRenamed(id, _, _):
                inventory.changed.append(
                    ModelKey(kind: .list, id: id.rawValue)
                )
            case let .entryInserted(identity, _):
                inventory.inserted.append(
                    ModelKey(kind: .entry, id: identity.id.rawValue)
                )
                inventory.changed.append(
                    ModelKey(kind: .list, id: identity.listID.rawValue)
                )
            case let .entryUpdated(identity, _),
                 let .entryResolved(identity, _, _),
                 let .entryReopened(identity, _):
                inventory.changed.append(
                    ModelKey(kind: .entry, id: identity.id.rawValue)
                )
                inventory.changed.append(
                    ModelKey(kind: .list, id: identity.listID.rawValue)
                )
            case let .entryDeleted(identity, _):
                inventory.deleted.append(
                    ModelKey(kind: .entry, id: identity.id.rawValue)
                )
                inventory.changed.append(
                    ModelKey(kind: .list, id: identity.listID.rawValue)
                )
            case let .historyEventInserted(id):
                inventory.inserted.append(
                    ModelKey(kind: .history, id: id.rawValue)
                )
            }
        }

        inventory.inserted.sort()
        inventory.changed.sort()
        inventory.deleted.sort()
        return inventory
    }

    private func actualInventory() throws -> ChangeInventory {
        let inserted = try modelContext.insertedModelsArray
            .map(modelKey)
            .sorted()
        let deleted = try modelContext.deletedModelsArray
            .map(modelKey)
            .sorted()
        let stagedKeys = Set(inserted + deleted)
        let changed = try modelContext.changedModelsArray
            .map(modelKey)
            .filter { !stagedKeys.contains($0) }
            .sorted()

        return ChangeInventory(
            inserted: inserted,
            changed: changed,
            deleted: deleted
        )
    }

    private func modelKey(
        _ model: any PersistentModel
    ) throws -> ModelKey {
        switch model {
        case let value as WayTaskSchemaV4.Product:
            ModelKey(kind: .product, id: value.id)
        case let value as WayTaskSchemaV4.ShoppingList:
            ModelKey(kind: .list, id: value.id)
        case let value as WayTaskSchemaV4.ShoppingListEntry:
            ModelKey(kind: .entry, id: value.id)
        case let value as WayTaskSchemaV4.ProductHistoryEvent:
            ModelKey(kind: .history, id: value.id)
        case let value as WayTaskSchemaV4.ShoppingSession:
            ModelKey(kind: .session, id: value.id)
        case let value as WayTaskSchemaV4.ShoppingSessionLine:
            ModelKey(kind: .sessionLine, id: value.id)
        case let value as WayTaskSchemaV4.ShoppingSessionStop:
            ModelKey(kind: .sessionStop, id: value.id)
        case let value as WayTaskSchemaV4.ProductStateMigrationException:
            ModelKey(kind: .migrationException, id: value.id)
        default:
            throw ProductStateTransactionScopeError.unknownModel
        }
    }

    private enum EffectState {
        case committed
        case notCommitted
        case inconsistent
    }

    private func evaluate(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect],
        repositories: ProductStateRepositories
    ) throws -> ProductStateCommitReconciliation {
        guard !effects.isEmpty else { return .inconsistent }
        let states = try effects.map {
            try effectState(
                $0,
                commandID: commandID,
                repositories: repositories
            )
        }
        if states.allSatisfy({ $0 == .committed }) {
            return .committed
        }
        if states.allSatisfy({ $0 == .notCommitted }) {
            return .notCommitted
        }
        return .inconsistent
    }

    private func effectState(
        _ effect: ProductStateStagedEffect,
        commandID: ProductStateCommandID,
        repositories: ProductStateRepositories
    ) throws -> EffectState {
        switch effect {
        case let .productInserted(id, revision):
            let rows = try repositories.products.products(id: id.rawValue)
            if rows.isEmpty { return .notCommitted }
            guard rows.count == 1 else { return .inconsistent }
            return rows[0].revision == revision
                ? .committed : .inconsistent

        case let .productEdited(id, before, after):
            return try productRevisionState(
                id: id,
                before: before,
                after: after,
                lifecycle: nil,
                repositories: repositories
            )

        case let .productRestored(id, before, after):
            return try productRevisionState(
                id: id,
                before: before,
                after: after,
                lifecycle: .active,
                repositories: repositories
            )

        case let .listInserted(id, revision):
            let rows = try repositories.shopping.shoppingLists(
                id: id.rawValue
            )
            if rows.isEmpty { return .notCommitted }
            guard rows.count == 1 else { return .inconsistent }
            return rows[0].revision == revision
                ? .committed : .inconsistent

        case let .listRenamed(id, before, after):
            return try listRevisionState(
                id: id,
                before: before,
                after: after,
                repositories: repositories
            )

        case let .entryInserted(identity, revision):
            return try entryState(
                identity: identity,
                revision: revision,
                expectedLifecycle: .needed,
                expectedReason: nil,
                deletion: false,
                repositories: repositories
            )

        case let .entryUpdated(identity, revision):
            return try entryState(
                identity: identity,
                revision: revision,
                expectedLifecycle: nil,
                expectedReason: nil,
                deletion: false,
                repositories: repositories
            )

        case let .entryResolved(identity, reason, revision):
            return try entryState(
                identity: identity,
                revision: revision,
                expectedLifecycle: .resolved,
                expectedReason: reason,
                deletion: false,
                repositories: repositories
            )

        case let .entryReopened(identity, revision):
            return try entryState(
                identity: identity,
                revision: revision,
                expectedLifecycle: .needed,
                expectedReason: nil,
                deletion: false,
                repositories: repositories
            )

        case let .entryDeleted(identity, revision):
            return try entryState(
                identity: identity,
                revision: revision,
                expectedLifecycle: nil,
                expectedReason: nil,
                deletion: true,
                repositories: repositories
            )

        case let .historyEventInserted(id):
            let rows = try repositories.history.historyEvents(id: id.rawValue)
            if rows.isEmpty { return .notCommitted }
            guard rows.count == 1,
                  rows[0].commandID == commandID.rawValue
            else { return .inconsistent }
            return .committed
        }
    }

    private func productRevisionState(
        id: ProductStateProductID,
        before: UInt64,
        after: UInt64,
        lifecycle: ProductLibraryLifecycle?,
        repositories: ProductStateRepositories
    ) throws -> EffectState {
        let rows = try repositories.products.products(id: id.rawValue)
        guard rows.count == 1 else { return .inconsistent }
        let product = rows[0]
        if product.revision == before { return .notCommitted }
        guard product.revision == after else { return .inconsistent }
        if let lifecycle,
           product.libraryLifecycleRawValue != lifecycle.rawValue
        {
            return .inconsistent
        }
        return .committed
    }

    private func listRevisionState(
        id: ProductStateListID,
        before: UInt64,
        after: UInt64,
        repositories: ProductStateRepositories
    ) throws -> EffectState {
        let rows = try repositories.shopping.shoppingLists(id: id.rawValue)
        guard rows.count == 1 else { return .inconsistent }
        if rows[0].revision == before { return .notCommitted }
        return rows[0].revision == after ? .committed : .inconsistent
    }

    private func entryState(
        identity: ProductStateListEntryIdentity,
        revision: UInt64,
        expectedLifecycle: ShoppingListEntryLifecycleKind?,
        expectedReason: ShoppingListResolutionReason?,
        deletion: Bool,
        repositories: ProductStateRepositories
    ) throws -> EffectState {
        guard revision > 0 else { return .inconsistent }
        let lists = try repositories.shopping.shoppingLists(
            id: identity.listID.rawValue
        )
        guard lists.count == 1 else { return .inconsistent }
        let entries = try repositories.shopping.shoppingEntries(
            id: identity.id.rawValue,
            listID: identity.listID.rawValue
        ).filter { $0.productID == identity.productID.rawValue }

        let listRevision = lists[0].revision
        if deletion {
            if listRevision == revision && entries.isEmpty {
                return .committed
            }
            if listRevision == revision - 1 && entries.count == 1 {
                return .notCommitted
            }
            return .inconsistent
        }

        if listRevision == revision - 1 && entries.isEmpty {
            return .notCommitted
        }
        if listRevision == revision - 1 && entries.count == 1 {
            return .notCommitted
        }
        guard listRevision == revision,
              entries.count == 1
        else { return .inconsistent }

        if let expectedLifecycle,
           entries[0].lifecycleRawValue != expectedLifecycle.rawValue
        {
            return .inconsistent
        }
        if let expectedReason,
           entries[0].resolutionReasonRawValue != expectedReason.rawValue
        {
            return .inconsistent
        }

        let currentMembership = try repositories.shopping.shoppingEntries(
            listID: identity.listID.rawValue,
            productID: identity.productID.rawValue
        )
        return currentMembership.count == 1
            ? .committed : .inconsistent
    }
}

private enum ShoppingListEntryLifecycleKind: String {
    case needed
    case resolved
}
