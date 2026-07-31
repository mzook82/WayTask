import Foundation

/// T-04 prepares deterministic repository changes but never commits them.
/// Durable transaction ownership and idempotent retry remain deferred to T-05.
@MainActor
final class ProductStateCommandCoordinator {
    private let products: any ProductRepository
    private let shopping: any ShoppingRepository
    private let history: any HistoryRepository
    private let sessions: any ShoppingSessionRepository
    private let shapeValidator: ProductStateCommandShapeValidator
    private let invariantValidator: ProductStateInvariantValidator

    init(
        repositories: ProductStateRepositories,
        shapeValidator: ProductStateCommandShapeValidator? = nil,
        invariantValidator: ProductStateInvariantValidator? = nil
    ) {
        self.products = repositories.products
        self.shopping = repositories.shopping
        self.history = repositories.history
        self.sessions = repositories.sessions
        self.shapeValidator = shapeValidator ?? ProductStateCommandShapeValidator()
        self.invariantValidator = invariantValidator
            ?? ProductStateInvariantValidator()
    }

    init(
        products: any ProductRepository,
        shopping: any ShoppingRepository,
        history: any HistoryRepository,
        sessions: any ShoppingSessionRepository,
        shapeValidator: ProductStateCommandShapeValidator? = nil,
        invariantValidator: ProductStateInvariantValidator? = nil
    ) {
        self.products = products
        self.shopping = shopping
        self.history = history
        self.sessions = sessions
        self.shapeValidator = shapeValidator ?? ProductStateCommandShapeValidator()
        self.invariantValidator = invariantValidator
            ?? ProductStateInvariantValidator()
    }

    func prepare(
        _ command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        let shapeViolations = shapeValidator.validate(command)
        guard shapeViolations.isEmpty else {
            return validationFailure(
                command,
                shape: shapeViolations
            )
        }

        do {
            return try prepareValidated(command)
        } catch {
            return .unavailable(
                commandID: command.id,
                reason: .durableAuthorityUnavailable
            )
        }
    }

    private func prepareValidated(
        _ command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        switch command.intent {
        case let .createProduct(value):
            return try prepareCreateProduct(value, command: command)
        case let .editProduct(value):
            return try prepareEditProduct(value, command: command)
        case .removeProductFromLibrary:
            return deferred(command)
        case let .restoreProductToLibrary(value):
            return try prepareRestoreProduct(value, command: command)
        case let .createNamedList(value):
            return try prepareCreateList(value, command: command)
        case let .renameNamedList(value):
            return try prepareRenameList(value, command: command)
        case let .addProductToList(value):
            return try prepareAddEntry(value, command: command)
        case let .updateListEntry(value):
            return try prepareUpdateEntry(value, command: command)
        case let .resolveListNeed(value):
            return try prepareResolveEntry(value, command: command)
        case let .reopenListNeed(value):
            return try prepareReopenEntry(value, command: command)
        case let .removeProductFromNamedList(value):
            return try prepareRemoveEntry(value, command: command)
        case .generatePlan, .supersedePlan, .startSession, .resumeSession,
             .markLineCollected, .undoLineCollection,
             .prepareFinishOutcome, .finishSession, .abandonSession,
             .createSavedLocation, .editSavedLocation,
             .removeSavedLocation:
            return deferred(command)
        }
    }

    // MARK: Product and Library

    private func prepareCreateProduct(
        _ value: CreateProductCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let stored = try products.products(id: value.productID.rawValue)
        if stored.count > 1 {
            return duplicate(command, scope: command.scope)
        }
        if let stored = stored.first {
            if stored.libraryLifecycleRawValue
                == ProductLibraryLifecycle.active.rawValue
            {
                return .noOp(commandID: command.id)
            }
            return .conflict(
                commandID: command.id,
                conflict: .approved(.removedProduct)
            )
        }

        let product = WayTaskSchemaV4.Product(
            id: value.productID.rawValue,
            revision: 1,
            libraryLifecycleRawValue: ProductLibraryLifecycle.active.rawValue,
            name: value.name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceRawValue: value.sourceRawValue,
            catalogProductIDRawValue: value.catalogID?.rawValue,
            createdAt: command.effectiveAt,
            updatedAt: command.effectiveAt
        )
        products.stageInsertion(of: product)

        return .staged(
            commandID: command.id,
            effects: [
                .productInserted(id: value.productID, revision: 1)
            ]
        )
    }

    private func prepareEditProduct(
        _ value: EditProductCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let stored = try products.products(id: value.productID.rawValue)
        guard let product = try exactlyOneProduct(
            stored,
            id: value.productID,
            command: command
        ) else {
            return identityConflict(
                count: stored.count,
                scope: command.scope,
                command: command
            )
        }
        guard product.libraryLifecycleRawValue
                == ProductLibraryLifecycle.active.rawValue
        else {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.removedProduct)
            )
        }
        if let conflict = revisionConflict(
            command,
            actual: product.revision
        ) {
            return conflict
        }

        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard product.name != name else {
            return .noOp(commandID: command.id)
        }
        guard let nextRevision = nextRevision(product.revision) else {
            return invalidRevision(command)
        }

        let beforeRevision = product.revision
        product.name = name
        product.revision = nextRevision
        product.updatedAt = command.effectiveAt

        return .staged(
            commandID: command.id,
            effects: [
                .productEdited(
                    id: value.productID,
                    beforeRevision: beforeRevision,
                    afterRevision: nextRevision
                )
            ]
        )
    }

    private func prepareRestoreProduct(
        _ value: RestoreProductToLibraryCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let stored = try products.products(id: value.productID.rawValue)
        guard let product = try exactlyOneProduct(
            stored,
            id: value.productID,
            command: command
        ) else {
            return identityConflict(
                count: stored.count,
                scope: command.scope,
                command: command
            )
        }
        if let conflict = revisionConflict(
            command,
            actual: product.revision
        ) {
            return conflict
        }
        if product.libraryLifecycleRawValue
            == ProductLibraryLifecycle.active.rawValue
        {
            return .noOp(commandID: command.id)
        }
        guard product.libraryLifecycleRawValue
                == ProductLibraryLifecycle.removed.rawValue,
              let nextRevision = nextRevision(product.revision)
        else {
            return invalidProductTransition(command)
        }

        let before = ProductStateProductSnapshot(
            id: value.productID,
            catalogID: product.catalogProductIDRawValue.map {
                ProductStateCatalogID(rawValue: $0)
            },
            libraryLifecycle: .removed
        )
        let after = ProductStateProductSnapshot(
            id: value.productID,
            catalogID: before.catalogID,
            libraryLifecycle: .active
        )
        let invariantViolations = invariantValidator.validate(
            .init(
                productTransitions: [
                    ProductLibraryTransition(
                        before: before,
                        after: after,
                        action: .restoreToLibrary,
                        hasExplicitUserIntent: value.confirmed
                    )
                ]
            )
        )
        guard invariantViolations.isEmpty else {
            return validationFailure(
                command,
                invariants: invariantViolations
            )
        }

        let beforeRevision = product.revision
        product.libraryLifecycleRawValue =
            ProductLibraryLifecycle.active.rawValue
        product.libraryRemovedAt = nil
        product.revision = nextRevision
        product.updatedAt = command.effectiveAt

        let event = makeHistoryEvent(
            id: value.historyEventID,
            productID: value.productID,
            meaning: "productRestoredToLibrary",
            command: command
        )
        history.stageInsertion(of: event)

        return .staged(
            commandID: command.id,
            effects: [
                .productRestored(
                    id: value.productID,
                    beforeRevision: beforeRevision,
                    afterRevision: nextRevision
                ),
                .historyEventInserted(value.historyEventID)
            ]
        )
    }

    // MARK: Named lists and entries

    private func prepareCreateList(
        _ value: CreateNamedListCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let stored = try shopping.shoppingLists(id: value.listID.rawValue)
        if stored.count > 1 {
            return duplicate(command, scope: command.scope)
        }
        if let list = stored.first {
            let title = value.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if list.title == title
                && list.purposeRawValue == value.purposeRawValue
            {
                return .noOp(commandID: command.id)
            }
            return duplicate(command, scope: command.scope)
        }

        let list = WayTaskSchemaV4.ShoppingList(
            id: value.listID.rawValue,
            revision: 1,
            title: value.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            purposeRawValue: value.purposeRawValue,
            createdAt: command.effectiveAt,
            updatedAt: command.effectiveAt
        )
        shopping.stageInsertion(of: list)

        return .staged(
            commandID: command.id,
            effects: [
                .listInserted(id: value.listID, revision: 1)
            ]
        )
    }

    private func prepareRenameList(
        _ value: RenameNamedListCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let stored = try shopping.shoppingLists(id: value.listID.rawValue)
        guard let list = stored.count == 1 ? stored[0] : nil else {
            return identityConflict(
                count: stored.count,
                scope: command.scope,
                command: command
            )
        }
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }

        let title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard list.title != title else {
            return .noOp(commandID: command.id)
        }
        guard let nextRevision = nextRevision(list.revision) else {
            return invalidRevision(command)
        }

        let beforeRevision = list.revision
        list.title = title
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        return .staged(
            commandID: command.id,
            effects: [
                .listRenamed(
                    id: value.listID,
                    beforeRevision: beforeRevision,
                    afterRevision: nextRevision
                )
            ]
        )
    }

    private func prepareAddEntry(
        _ value: AddProductToListCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let listResult = try loadList(
            value.entry.listID,
            command: command
        )
        guard case let .success(list) = listResult else {
            return listResult.failure!
        }
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }

        let productRows = try products.products(
            id: value.entry.productID.rawValue
        )
        guard productRows.count == 1 else {
            return identityConflict(
                count: productRows.count,
                scope: .product(value.entry.productID),
                command: command
            )
        }
        guard productRows[0].libraryLifecycleRawValue
                == ProductLibraryLifecycle.active.rawValue
        else {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.removedProduct)
            )
        }

        let existing = try shopping.shoppingEntries(
            listID: value.entry.listID.rawValue,
            productID: value.entry.productID.rawValue
        )
        if existing.count > 1 {
            return duplicate(command, scope: command.scope)
        }
        if let entry = existing.first {
            if entry.lifecycleRawValue == "needed" {
                return .noOp(commandID: command.id)
            }
            return .conflict(
                commandID: command.id,
                conflict: .approved(.reopenRequired)
            )
        }
        guard let nextRevision = nextRevision(list.revision) else {
            return invalidRevision(command)
        }

        let entry = WayTaskSchemaV4.ShoppingListEntry(
            id: value.entry.id.rawValue,
            shoppingListID: value.entry.listID.rawValue,
            productID: value.entry.productID.rawValue,
            lifecycleRawValue: "needed",
            quantity: value.quantity,
            unitRawValue: value.unitRawValue,
            note: value.note,
            sortOrder: value.sortOrder,
            createdAt: command.effectiveAt,
            updatedAt: command.effectiveAt,
            product: productRows[0]
        )
        shopping.stageInsertion(of: entry)
        list.entries.append(entry)
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        let event = makeHistoryEvent(
            id: value.historyEventID,
            productID: value.entry.productID,
            meaning: "needAdded",
            sourceListID: value.entry.listID,
            sourceEntryID: value.entry.id,
            command: command
        )
        history.stageInsertion(of: event)

        return .staged(
            commandID: command.id,
            effects: [
                .entryInserted(
                    identity: value.entry,
                    listRevision: nextRevision
                ),
                .historyEventInserted(value.historyEventID)
            ]
        )
    }

    private func prepareUpdateEntry(
        _ value: UpdateListEntryCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let loaded = try loadListAndEntry(value.entry, command: command)
        guard case let .success((list, entry)) = loaded else {
            return loaded.failure!
        }
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }
        if try isProtectedBySession(value.entry.id) {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.activeSession)
            )
        }

        if entry.quantity == value.quantity
            && entry.unitRawValue == value.unitRawValue
            && entry.note == value.note
            && entry.sortOrder == value.sortOrder
        {
            return .noOp(commandID: command.id)
        }
        guard let nextRevision = nextRevision(list.revision) else {
            return invalidRevision(command)
        }

        entry.quantity = value.quantity
        entry.unitRawValue = value.unitRawValue
        entry.note = value.note
        entry.sortOrder = value.sortOrder
        entry.updatedAt = command.effectiveAt
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        return .staged(
            commandID: command.id,
            effects: [
                .entryUpdated(
                    identity: value.entry,
                    listRevision: nextRevision
                )
            ]
        )
    }

    private func prepareResolveEntry(
        _ value: ResolveListNeedCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let loaded = try loadListAndEntry(value.entry, command: command)
        guard case let .success((list, entry)) = loaded else {
            return loaded.failure!
        }
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }
        if try isProtectedBySession(value.entry.id) {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.activeSession)
            )
        }
        if entry.lifecycleRawValue == "resolved" {
            if entry.resolutionReasonRawValue == value.reason.rawValue {
                return .noOp(commandID: command.id)
            }
            return .conflict(
                commandID: command.id,
                conflict: .approved(.reopenRequired)
            )
        }
        guard entry.lifecycleRawValue == "needed",
              let nextRevision = nextRevision(list.revision)
        else {
            return invalidEntryTransition(command)
        }

        let before = ProductStateListEntrySnapshot(
            identity: value.entry,
            lifecycle: .needed
        )
        let resolution = ShoppingListResolution(
            reason: value.reason,
            effectiveAt: command.effectiveAt,
            provenance: .userCommand(command.id)
        )
        let after = ProductStateListEntrySnapshot(
            identity: value.entry,
            lifecycle: .resolved(resolution)
        )
        let invariantViolations = invariantValidator.validate(
            .init(
                entryTransitions: [
                    ShoppingListEntryTransition(
                        before: before,
                        after: after,
                        action: .resolve,
                        commandListID: value.entry.listID
                    )
                ]
            )
        )
        guard invariantViolations.isEmpty else {
            return validationFailure(
                command,
                invariants: invariantViolations
            )
        }

        entry.lifecycleRawValue = "resolved"
        entry.resolutionReasonRawValue = value.reason.rawValue
        entry.resolutionEffectiveAt = command.effectiveAt
        entry.resolutionProvenanceRawValue = "userCommand"
        entry.resolutionCommandID = command.id.rawValue
        entry.updatedAt = command.effectiveAt
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        let event = makeHistoryEvent(
            id: value.historyEventID,
            productID: value.entry.productID,
            meaning: "needResolved",
            resolutionReason: value.reason,
            sourceListID: value.entry.listID,
            sourceEntryID: value.entry.id,
            command: command
        )
        history.stageInsertion(of: event)

        return .staged(
            commandID: command.id,
            effects: [
                .entryResolved(
                    identity: value.entry,
                    reason: value.reason,
                    listRevision: nextRevision
                ),
                .historyEventInserted(value.historyEventID)
            ]
        )
    }

    private func prepareReopenEntry(
        _ value: ReopenListNeedCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let loaded = try loadListAndEntry(value.entry, command: command)
        guard case let .success((list, entry)) = loaded else {
            return loaded.failure!
        }
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }
        if try isProtectedBySession(value.entry.id) {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.activeSession)
            )
        }
        if entry.lifecycleRawValue == "needed" {
            return .noOp(commandID: command.id)
        }
        guard let resolution = domainResolution(entry),
              let nextRevision = nextRevision(list.revision)
        else {
            return invalidEntryTransition(command)
        }

        let before = ProductStateListEntrySnapshot(
            identity: value.entry,
            lifecycle: .resolved(resolution)
        )
        let after = ProductStateListEntrySnapshot(
            identity: value.entry,
            lifecycle: .needed
        )
        let invariantViolations = invariantValidator.validate(
            .init(
                entryTransitions: [
                    ShoppingListEntryTransition(
                        before: before,
                        after: after,
                        action: .reopen,
                        commandListID: value.entry.listID
                    )
                ]
            )
        )
        guard invariantViolations.isEmpty else {
            return validationFailure(
                command,
                invariants: invariantViolations
            )
        }

        entry.lifecycleRawValue = "needed"
        entry.resolutionReasonRawValue = nil
        entry.resolutionEffectiveAt = nil
        entry.resolutionProvenanceRawValue = nil
        entry.resolutionCommandID = nil
        entry.resolutionSessionID = nil
        entry.resolutionSessionLineID = nil
        entry.updatedAt = command.effectiveAt
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        let event = makeHistoryEvent(
            id: value.historyEventID,
            productID: value.entry.productID,
            meaning: "needReopened",
            sourceListID: value.entry.listID,
            sourceEntryID: value.entry.id,
            command: command
        )
        history.stageInsertion(of: event)

        return .staged(
            commandID: command.id,
            effects: [
                .entryReopened(
                    identity: value.entry,
                    listRevision: nextRevision
                ),
                .historyEventInserted(value.historyEventID)
            ]
        )
    }

    private func prepareRemoveEntry(
        _ value: RemoveProductFromNamedListCommand,
        command: ProductStateCommand
    ) throws -> ProductStatePreparedCommandResult {
        let listRows = try shopping.shoppingLists(
            id: value.entry.listID.rawValue
        )
        guard listRows.count == 1 else {
            return identityConflict(
                count: listRows.count,
                scope: .list(value.entry.listID),
                command: command
            )
        }
        let list = listRows[0]
        if let conflict = revisionConflict(command, actual: list.revision) {
            return conflict
        }

        let entries = try shopping.shoppingEntries(
            id: value.entry.id.rawValue,
            listID: value.entry.listID.rawValue
        ).filter { $0.productID == value.entry.productID.rawValue }
        if entries.isEmpty {
            return .noOp(commandID: command.id)
        }
        guard entries.count == 1 else {
            return duplicate(command, scope: command.scope)
        }
        if try isProtectedBySession(value.entry.id) {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.activeSession)
            )
        }
        guard let nextRevision = nextRevision(list.revision) else {
            return invalidRevision(command)
        }

        let entry = entries[0]
        list.entries.removeAll { $0.id == entry.id }
        shopping.stageDeletion(of: entry)
        list.revision = nextRevision
        list.updatedAt = command.effectiveAt

        let event = makeHistoryEvent(
            id: value.historyEventID,
            productID: value.entry.productID,
            meaning: "listMembershipRemoved",
            sourceListID: value.entry.listID,
            sourceEntryID: value.entry.id,
            command: command
        )
        history.stageInsertion(of: event)

        return .staged(
            commandID: command.id,
            effects: [
                .entryDeleted(
                    identity: value.entry,
                    listRevision: nextRevision
                ),
                .historyEventInserted(value.historyEventID)
            ]
        )
    }

    // MARK: Helpers

    private func deferred(
        _ command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        .unavailable(
            commandID: command.id,
            reason: .unsupportedOperation
        )
    }

    private func revisionConflict(
        _ command: ProductStateCommand,
        actual: UInt64
    ) -> ProductStatePreparedCommandResult? {
        guard command.expectedRevision?.revision.value != actual else {
            return nil
        }
        return .conflict(
            commandID: command.id,
            conflict: .approved(.staleRevision)
        )
    }

    private func nextRevision(_ value: UInt64) -> UInt64? {
        let result = value.addingReportingOverflow(1)
        return result.overflow ? nil : result.partialValue
    }

    private func exactlyOneProduct(
        _ rows: [WayTaskSchemaV4.Product],
        id: ProductStateProductID,
        command: ProductStateCommand
    ) throws -> WayTaskSchemaV4.Product? {
        rows.count == 1 ? rows[0] : nil
    }

    private enum LoadResult<Value> {
        case success(Value)
        case failure(ProductStatePreparedCommandResult)

        var failure: ProductStatePreparedCommandResult? {
            if case let .failure(value) = self { return value }
            return nil
        }
    }

    private func loadList(
        _ id: ProductStateListID,
        command: ProductStateCommand
    ) throws -> LoadResult<WayTaskSchemaV4.ShoppingList> {
        let rows = try shopping.shoppingLists(id: id.rawValue)
        guard rows.count == 1 else {
            return .failure(
                identityConflict(
                    count: rows.count,
                    scope: .list(id),
                    command: command
                )
            )
        }
        return .success(rows[0])
    }

    private func loadListAndEntry(
        _ identity: ProductStateListEntryIdentity,
        command: ProductStateCommand
    ) throws -> LoadResult<(
        WayTaskSchemaV4.ShoppingList,
        WayTaskSchemaV4.ShoppingListEntry
    )> {
        let list = try loadList(identity.listID, command: command)
        guard case let .success(storedList) = list else {
            return .failure(list.failure!)
        }

        let entries = try shopping.shoppingEntries(
            id: identity.id.rawValue,
            listID: identity.listID.rawValue
        ).filter { $0.productID == identity.productID.rawValue }
        guard entries.count == 1 else {
            return .failure(
                identityConflict(
                    count: entries.count,
                    scope: .entry(identity),
                    command: command
                )
            )
        }
        return .success((storedList, entries[0]))
    }

    private func isProtectedBySession(
        _ entryID: ProductStateListEntryID
    ) throws -> Bool {
        let nonTerminal = try sessions.shoppingSessions(lifecycle: .active)
            + sessions.shoppingSessions(lifecycle: .expired)
        for session in nonTerminal {
            let lines = try sessions.sessionLines(sessionID: session.id)
            if lines.contains(where: { $0.sourceEntryID == entryID.rawValue }) {
                return true
            }
        }
        return false
    }

    private func domainResolution(
        _ entry: WayTaskSchemaV4.ShoppingListEntry
    ) -> ShoppingListResolution? {
        guard entry.lifecycleRawValue == "resolved",
              let rawReason = entry.resolutionReasonRawValue,
              let reason = ShoppingListResolutionReason(rawValue: rawReason),
              let effectiveAt = entry.resolutionEffectiveAt
        else {
            return nil
        }

        let provenance: ShoppingListResolutionProvenance
        switch entry.resolutionProvenanceRawValue {
        case "legacyMigration":
            provenance = .legacyMigration
        case "sessionFinish":
            guard let commandID = entry.resolutionCommandID,
                  let sessionID = entry.resolutionSessionID,
                  let lineID = entry.resolutionSessionLineID
            else { return nil }
            provenance = .sessionFinish(
                commandID: ProductStateCommandID(rawValue: commandID),
                sessionID: ProductStateSessionID(rawValue: sessionID),
                lineID: ProductStateSessionLineID(rawValue: lineID)
            )
        case "userCommand":
            guard let commandID = entry.resolutionCommandID else { return nil }
            provenance = .userCommand(
                ProductStateCommandID(rawValue: commandID)
            )
        default:
            return nil
        }

        return ShoppingListResolution(
            reason: reason,
            effectiveAt: effectiveAt,
            provenance: provenance
        )
    }

    private func makeHistoryEvent(
        id: ProductStateHistoryEventID,
        productID: ProductStateProductID,
        meaning: String,
        resolutionReason: ShoppingListResolutionReason? = nil,
        sourceListID: ProductStateListID? = nil,
        sourceEntryID: ProductStateListEntryID? = nil,
        command: ProductStateCommand
    ) -> WayTaskSchemaV4.ProductHistoryEvent {
        WayTaskSchemaV4.ProductHistoryEvent(
            id: id.rawValue,
            productID: productID.rawValue,
            meaningRawValue: meaning,
            resolutionReasonRawValue: resolutionReason?.rawValue,
            sourceListID: sourceListID?.rawValue,
            sourceEntryID: sourceEntryID?.rawValue,
            commandID: command.id.rawValue,
            provenanceRawValue: "userCommand",
            occurredAt: command.effectiveAt
        )
    }

    private func identityConflict(
        count: Int,
        scope: ProductStateCommandScope,
        command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        if count == 0 {
            return .conflict(
                commandID: command.id,
                conflict: .missingTarget(scope)
            )
        }
        return duplicate(command, scope: scope)
    }

    private func duplicate(
        _ command: ProductStateCommand,
        scope: ProductStateCommandScope
    ) -> ProductStatePreparedCommandResult {
        .conflict(
            commandID: command.id,
            conflict: .duplicateTarget(scope)
        )
    }

    private func validationFailure(
        _ command: ProductStateCommand,
        shape: [ProductStateCommandShapeViolationCode] = [],
        invariants: [ProductStateInvariantViolation] = []
    ) -> ProductStatePreparedCommandResult {
        .validationFailure(
            commandID: command.id,
            failure: ProductStatePreparedValidationFailure(
                shapeViolations: shape,
                invariantViolations: invariants.map(\.code)
            )
        )
    }

    private func invalidRevision(
        _ command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        validationFailure(
            command,
            invariants: [
                ProductStateInvariantViolation(
                    code: .invalidCommittedRevisionChange
                )
            ]
        )
    }

    private func invalidProductTransition(
        _ command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        validationFailure(
            command,
            invariants: [
                ProductStateInvariantViolation(
                    code: .invalidProductLibraryTransition
                )
            ]
        )
    }

    private func invalidEntryTransition(
        _ command: ProductStateCommand
    ) -> ProductStatePreparedCommandResult {
        validationFailure(
            command,
            invariants: [
                ProductStateInvariantViolation(code: .invalidEntryTransition)
            ]
        )
    }
}
