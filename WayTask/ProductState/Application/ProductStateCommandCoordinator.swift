import Foundation

struct ProductStateListRevisionExpectation: Hashable, Sendable {
    let listID: ProductStateListID
    let revision: ProductStateListRevision
}

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

    /// T-10's Product command entry preserves T-04's general preparation
    /// contract while supplying the exact all-list impact summary required
    /// by Library removal. Other command families continue through `prepare`.
    func prepareProductCommand(
        _ command: ProductStateCommand,
        expectedAffectedListRevisions:
            [ProductStateListRevisionExpectation] = []
    ) -> ProductStatePreparedCommandResult {
        guard case let .removeProductFromLibrary(value) = command.intent else {
            return prepare(command)
        }

        let shapeViolations = shapeValidator.validate(command)
        guard shapeViolations.isEmpty else {
            return validationFailure(command, shape: shapeViolations)
        }

        do {
            return try prepareRemoveProduct(
                value,
                expectedAffectedListRevisions:
                    expectedAffectedListRevisions,
                command: command
            )
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

    private func prepareRemoveProduct(
        _ value: RemoveProductFromLibraryCommand,
        expectedAffectedListRevisions:
            [ProductStateListRevisionExpectation],
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
                == ProductLibraryLifecycle.active.rawValue else {
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

        let allEntries = try shopping.shoppingEntries(
            productID: value.productID.rawValue
        )
        let entriesByList = Dictionary(
            grouping: allEntries,
            by: \.shoppingListID
        )
        var editable: [(
            list: WayTaskSchemaV4.ShoppingList,
            entry: WayTaskSchemaV4.ShoppingListEntry
        )] = []
        let archivePurposes = Set(["completed", "recent"])

        for listID in entriesByList.keys.sorted(by: uuidLessThan) {
            let listRows = try shopping.shoppingLists(id: listID)
            guard listRows.count == 1 else {
                return identityConflict(
                    count: listRows.count,
                    scope: .list(ProductStateListID(rawValue: listID)),
                    command: command
                )
            }
            let list = listRows[0]
            if let purpose = list.purposeRawValue,
               archivePurposes.contains(purpose) {
                continue
            }
            guard let entries = entriesByList[listID],
                  entries.count == 1 else {
                return duplicate(
                    command,
                    scope: .list(ProductStateListID(rawValue: listID))
                )
            }
            editable.append((list, entries[0]))
        }

        let expectationGroups = Dictionary(
            grouping: expectedAffectedListRevisions,
            by: { $0.listID }
        )
        guard expectationGroups.values.allSatisfy({ $0.count == 1 }) else {
            return invalidRevision(command)
        }
        let expectedByList = expectationGroups.mapValues { $0[0].revision }
        let affectedListIDs = Set(editable.map {
            ProductStateListID(rawValue: $0.list.id)
        })
        guard Set(expectedByList.keys) == affectedListIDs else {
            return invalidRevision(command)
        }
        for impact in editable {
            let listID = ProductStateListID(rawValue: impact.list.id)
            guard expectedByList[listID]?.value == impact.list.revision else {
                return .conflict(
                    commandID: command.id,
                    conflict: .approved(.staleRevision)
                )
            }
        }

        let protectedEntryIDs = Set(allEntries.map(\.id))
        if try isProductProtectedBySession(
            value.productID,
            entryIDs: protectedEntryIDs
        ) {
            return .conflict(
                commandID: command.id,
                conflict: .approved(.activeSession)
            )
        }

        guard let productRevision = nextRevision(product.revision) else {
            return invalidRevision(command)
        }
        var listRevisions: [UUID: UInt64] = [:]
        for impact in editable {
            guard let revision = nextRevision(impact.list.revision) else {
                return invalidRevision(command)
            }
            listRevisions[impact.list.id] = revision
        }

        let before = ProductStateProductSnapshot(
            id: value.productID,
            catalogID: product.catalogProductIDRawValue.map {
                ProductStateCatalogID(rawValue: $0)
            },
            libraryLifecycle: .active
        )
        let after = ProductStateProductSnapshot(
            id: value.productID,
            catalogID: before.catalogID,
            libraryLifecycle: .removed
        )
        let invariantViolations = invariantValidator.validate(
            .init(
                productTransitions: [
                    ProductLibraryTransition(
                        before: before,
                        after: after,
                        action: .removeFromLibrary,
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

        let beforeProductRevision = product.revision
        product.libraryLifecycleRawValue =
            ProductLibraryLifecycle.removed.rawValue
        product.libraryRemovedAt = command.effectiveAt
        product.revision = productRevision
        product.updatedAt = command.effectiveAt

        var effects: [ProductStateStagedEffect] = [
            .productEdited(
                id: value.productID,
                beforeRevision: beforeProductRevision,
                afterRevision: productRevision
            )
        ]
        for impact in editable {
            let revision = listRevisions[impact.list.id]!
            impact.list.revision = revision
            impact.list.updatedAt = command.effectiveAt
            shopping.stageDeletion(of: impact.entry)
            effects.append(
                .entryDeleted(
                    identity: ProductStateListEntryIdentity(
                        id: ProductStateListEntryID(
                            rawValue: impact.entry.id
                        ),
                        listID: ProductStateListID(
                            rawValue: impact.list.id
                        ),
                        productID: value.productID
                    ),
                    listRevision: revision
                )
            )
        }

        history.stageInsertion(
            of: makeHistoryEvent(
                id: value.historyEventID,
                productID: value.productID,
                meaning: "productRemovedFromLibrary",
                command: command
            )
        )
        effects.append(.historyEventInserted(value.historyEventID))

        return .staged(commandID: command.id, effects: effects)
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
              product.libraryRemovedAt != nil,
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

    private func isProductProtectedBySession(
        _ productID: ProductStateProductID,
        entryIDs: Set<UUID>
    ) throws -> Bool {
        let nonTerminal = try sessions.shoppingSessions(lifecycle: .active)
            + sessions.shoppingSessions(lifecycle: .expired)
        for session in nonTerminal {
            let lines = try sessions.sessionLines(sessionID: session.id)
            if lines.contains(where: {
                $0.productID == productID.rawValue
                    || $0.sourceEntryID.map(entryIDs.contains) == true
            }) {
                return true
            }
        }
        return false
    }

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
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

// MARK: - T-10 durable Product command authority

enum ProductStateProductCommandWriteState: String, Codable, Sendable {
    case writableTarget
    case migrationIncomplete
    case nonDurable
}

enum ProductStateProductCommandOperation: String, Codable, Sendable {
    case acquire
    case edit
    case removeFromLibrary
    case restoreToLibrary
}

enum ProductStateProductCommandOutcomeKind: String, Codable, Sendable {
    case created
    case alreadyActive
    case restoreRequired
    case edited
    case removed
    case restored
    case noOp
    case conflict
    case validationFailure
    case unavailable
}

enum ProductStateProductCommandFailureClassification:
    String, Codable, Sendable {
    case migrationIncomplete
    case nonDurable
    case invalidRequest
    case staleRevision
    case activeSession
    case ambiguousIdentity
    case removedProduct
    case saveFailed
    case stagedStateMismatch
    case finalInvariantFailure
    case reconciliationFailed
    case outcomeUnknown
    case durableAuthorityUnavailable
}

enum ProductStateProductCommandDurability: String, Codable, Sendable {
    case committed
    case reconciledCommitted
    case noCommitRequired
    case rolledBack
    case outcomeUnknown
    case notAttempted
}

struct ProductStateProductCommandDiagnostic: Equatable, Codable, Sendable {
    let commandID: UUID
    let requestedProductID: UUID
    let authoritativeProductID: UUID?
    let operation: ProductStateProductCommandOperation
    let outcome: ProductStateProductCommandOutcomeKind
    let failure: ProductStateProductCommandFailureClassification?
    let durability: ProductStateProductCommandDurability
    let productRevisionBefore: UInt64?
    let productRevisionAfter: UInt64?
    let affectedListCount: Int
    let historyEventCount: Int
    let claimsDurableSuccess: Bool
}

struct ProductStateProductAcquisitionRequest: Hashable, Sendable {
    let commandID: ProductStateCommandID
    let productID: ProductStateProductID
    let effectiveAt: Date
    let reviewed: Bool
    let name: String
    let imageData: Data?
    let brand: String?
    let category: String?
    let barcode: String?
    let imageURLString: String?
    let sourceRawValue: String
    let catalogID: ProductStateCatalogID?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshotRawValue: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?

    init(
        commandID: ProductStateCommandID,
        productID: ProductStateProductID,
        effectiveAt: Date,
        reviewed: Bool,
        name: String,
        imageData: Data? = nil,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        imageURLString: String? = nil,
        sourceRawValue: String,
        catalogID: ProductStateCatalogID? = nil,
        catalogDisplayNameSnapshot: String? = nil,
        catalogDisplayLocaleSnapshot: String? = nil,
        catalogCategoryIDSnapshotRawValue: String? = nil,
        catalogCategoryDisplayNameSnapshot: String? = nil,
        catalogIconKeySnapshot: String? = nil,
        catalogSnapshotUpdatedAt: Date? = nil
    ) {
        self.commandID = commandID
        self.productID = productID
        self.effectiveAt = effectiveAt
        self.reviewed = reviewed
        self.name = name
        self.imageData = imageData
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.imageURLString = imageURLString
        self.sourceRawValue = sourceRawValue
        self.catalogID = catalogID
        self.catalogDisplayNameSnapshot = catalogDisplayNameSnapshot
        self.catalogDisplayLocaleSnapshot = catalogDisplayLocaleSnapshot
        self.catalogCategoryIDSnapshotRawValue =
            catalogCategoryIDSnapshotRawValue
        self.catalogCategoryDisplayNameSnapshot =
            catalogCategoryDisplayNameSnapshot
        self.catalogIconKeySnapshot = catalogIconKeySnapshot
        self.catalogSnapshotUpdatedAt = catalogSnapshotUpdatedAt
    }
}

struct ProductStateAffectedListRevision: Equatable, Sendable {
    let listID: ProductStateListID
    let before: ProductStateListRevision
    let after: ProductStateListRevision
}

struct ProductStateProductCommandCommitSummary: Equatable, Sendable {
    let commandID: ProductStateCommandID
    let productID: ProductStateProductID
    let productRevisionBefore: UInt64
    let productRevisionAfter: UInt64
    let affectedLists: [ProductStateAffectedListRevision]
    let historyEventIDs: [ProductStateHistoryEventID]
    let durability: ProductStateProductCommandDurability
}

enum ProductStateProductCommandOutcome: Equatable, Sendable {
    case created(ProductStateProductCommandCommitSummary)
    case alreadyActive(productID: ProductStateProductID, revision: UInt64)
    case restoreRequired(productID: ProductStateProductID, revision: UInt64)
    case edited(ProductStateProductCommandCommitSummary)
    case removed(ProductStateProductCommandCommitSummary)
    case restored(ProductStateProductCommandCommitSummary)
    case noOp(productID: ProductStateProductID, revision: UInt64)
    case conflict(ProductStateCommandConflict)
    case validationFailure
    case unavailable(ProductStateUnavailableReason)
}

struct ProductStateProductCommandExecution: Equatable, Sendable {
    let outcome: ProductStateProductCommandOutcome
    let diagnostic: ProductStateProductCommandDiagnostic

    var claimsDurableSuccess: Bool {
        diagnostic.claimsDurableSuccess
    }
}

/// The sole T-10 Product mutation entry. It accepts an already composed
/// repository bundle and T-05 transaction coordinator, so this Application
/// component neither imports SwiftData nor creates an independent context.
@MainActor
final class ProductStateProductCommandAuthority {
    typealias TransactionCommit = (
        ProductStatePreparedCommandResult
    ) -> ProductStateTransactionResult

    private let products: any ProductRepository
    private let coordinator: ProductStateCommandCoordinator
    private let commitPrepared: TransactionCommit
    private let writeState: ProductStateProductCommandWriteState

    init(
        repositories: ProductStateRepositories,
        transactionCoordinator: ProductStateTransactionCoordinator,
        writeState: ProductStateProductCommandWriteState
    ) {
        products = repositories.products
        coordinator = ProductStateCommandCoordinator(
            repositories: repositories
        )
        commitPrepared = { transactionCoordinator.commit($0) }
        self.writeState = writeState
    }

    init(
        products: any ProductRepository,
        coordinator: ProductStateCommandCoordinator,
        writeState: ProductStateProductCommandWriteState,
        commitPrepared: @escaping TransactionCommit
    ) {
        self.products = products
        self.coordinator = coordinator
        self.writeState = writeState
        self.commitPrepared = commitPrepared
    }

    func acquire(
        _ request: ProductStateProductAcquisitionRequest
    ) -> ProductStateProductCommandExecution {
        let operation = ProductStateProductCommandOperation.acquire
        if let blocked = blockedExecution(
            commandID: request.commandID,
            productID: request.productID,
            operation: operation
        ) {
            return blocked
        }
        guard isValid(request) else {
            return rejectedExecution(
                commandID: request.commandID,
                productID: request.productID,
                operation: operation,
                outcome: .validationFailure,
                failure: .invalidRequest
            )
        }

        let matches: [WayTaskSchemaV4.Product]
        do {
            matches = try acquisitionMatches(request)
        } catch {
            return unavailableExecution(
                commandID: request.commandID,
                productID: request.productID,
                operation: operation
            )
        }

        if matches.count > 1 {
            return rejectedExecution(
                commandID: request.commandID,
                productID: request.productID,
                operation: operation,
                outcome: .conflict(.ambiguousIdentity),
                failure: .ambiguousIdentity
            )
        }
        if let product = matches.first {
            let id = ProductStateProductID(rawValue: product.id)
            if product.libraryLifecycleRawValue
                == ProductLibraryLifecycle.active.rawValue {
                return semanticExecution(
                    commandID: request.commandID,
                    requestedProductID: request.productID,
                    authoritativeProductID: id,
                    operation: operation,
                    outcome: .alreadyActive(
                        productID: id,
                        revision: product.revision
                    ),
                    outcomeKind: .alreadyActive,
                    productRevision: product.revision
                )
            }
            if product.libraryLifecycleRawValue
                == ProductLibraryLifecycle.removed.rawValue,
               product.libraryRemovedAt != nil {
                return semanticExecution(
                    commandID: request.commandID,
                    requestedProductID: request.productID,
                    authoritativeProductID: id,
                    operation: operation,
                    outcome: .restoreRequired(
                        productID: id,
                        revision: product.revision
                    ),
                    outcomeKind: .restoreRequired,
                    failure: .removedProduct,
                    productRevision: product.revision
                )
            }
            return rejectedExecution(
                commandID: request.commandID,
                productID: request.productID,
                operation: operation,
                outcome: .validationFailure,
                failure: .invalidRequest
            )
        }

        let command = ProductStateCommand(
            id: request.commandID,
            expectedRevision: nil,
            effectiveAt: request.effectiveAt,
            intent: .createProduct(
                CreateProductCommand(
                    productID: request.productID,
                    name: request.name,
                    sourceRawValue: request.sourceRawValue,
                    catalogID: request.catalogID
                )
            )
        )
        let prepared = coordinator.prepareProductCommand(command)
        if case .staged = prepared {
            do {
                let rows = try products.products(id: request.productID.rawValue)
                guard rows.count == 1 else {
                    return finish(
                        .unavailable(
                            commandID: request.commandID,
                            reason: .durableAuthorityUnavailable
                        ),
                        operation: operation,
                        requestedProductID: request.productID
                    )
                }
                apply(request, to: rows[0])
            } catch {
                return finish(
                    .unavailable(
                        commandID: request.commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    operation: operation,
                    requestedProductID: request.productID
                )
            }
        }
        return finish(
            prepared,
            operation: operation,
            requestedProductID: request.productID
        )
    }

    func edit(
        _ command: ProductStateCommand
    ) -> ProductStateProductCommandExecution {
        execute(
            command,
            operation: .edit,
            expectedAffectedListRevisions: []
        )
    }

    func removeFromLibrary(
        _ command: ProductStateCommand,
        expectedAffectedListRevisions:
            [ProductStateListRevisionExpectation]
    ) -> ProductStateProductCommandExecution {
        execute(
            command,
            operation: .removeFromLibrary,
            expectedAffectedListRevisions:
                expectedAffectedListRevisions
        )
    }

    func restoreToLibrary(
        _ command: ProductStateCommand
    ) -> ProductStateProductCommandExecution {
        execute(
            command,
            operation: .restoreToLibrary,
            expectedAffectedListRevisions: []
        )
    }

    private func execute(
        _ command: ProductStateCommand,
        operation: ProductStateProductCommandOperation,
        expectedAffectedListRevisions:
            [ProductStateListRevisionExpectation]
    ) -> ProductStateProductCommandExecution {
        let requestedProductID = productID(for: command)
        guard operationMatches(command, operation: operation),
              let requestedProductID else {
            return rejectedExecution(
                commandID: command.id,
                productID: requestedProductID
                    ?? ProductStateProductID(rawValue: zeroUUID),
                operation: operation,
                outcome: .validationFailure,
                failure: .invalidRequest
            )
        }
        if let blocked = blockedExecution(
            commandID: command.id,
            productID: requestedProductID,
            operation: operation
        ) {
            return blocked
        }
        return finish(
            coordinator.prepareProductCommand(
                command,
                expectedAffectedListRevisions:
                    expectedAffectedListRevisions
            ),
            operation: operation,
            requestedProductID: requestedProductID
        )
    }

    private func finish(
        _ prepared: ProductStatePreparedCommandResult,
        operation: ProductStateProductCommandOperation,
        requestedProductID: ProductStateProductID
    ) -> ProductStateProductCommandExecution {
        let transaction = commitPrepared(prepared)
        let durability = durability(for: transaction.disposition)

        if transaction.claimsDurableSuccess,
           case let .staged(_, effects) = prepared,
           let summary = commitSummary(
                commandID: prepared.commandID,
                productID: requestedProductID,
                effects: effects,
                durability: durability
           ) {
            let outcome: ProductStateProductCommandOutcome
            let kind: ProductStateProductCommandOutcomeKind
            switch operation {
            case .acquire:
                outcome = .created(summary)
                kind = .created
            case .edit:
                outcome = .edited(summary)
                kind = .edited
            case .removeFromLibrary:
                outcome = .removed(summary)
                kind = .removed
            case .restoreToLibrary:
                outcome = .restored(summary)
                kind = .restored
            }
            return ProductStateProductCommandExecution(
                outcome: outcome,
                diagnostic: diagnostic(
                    commandID: prepared.commandID,
                    requestedProductID: requestedProductID,
                    authoritativeProductID: requestedProductID,
                    operation: operation,
                    outcome: kind,
                    durability: durability,
                    summary: summary,
                    claimsDurableSuccess: true
                )
            )
        }

        switch transaction.commandResult {
        case .noOp:
            let revision = currentRevision(for: requestedProductID) ?? 0
            let outcome: ProductStateProductCommandOutcome
            let kind: ProductStateProductCommandOutcomeKind
            if operation == .restoreToLibrary || operation == .acquire {
                outcome = .alreadyActive(
                    productID: requestedProductID,
                    revision: revision
                )
                kind = .alreadyActive
            } else {
                outcome = .noOp(
                    productID: requestedProductID,
                    revision: revision
                )
                kind = .noOp
            }
            return semanticExecution(
                commandID: prepared.commandID,
                requestedProductID: requestedProductID,
                authoritativeProductID: requestedProductID,
                operation: operation,
                outcome: outcome,
                outcomeKind: kind,
                durability: durability,
                productRevision: revision
            )

        case let .conflict(_, conflict):
            if operation == .acquire && conflict == .removedProduct,
               let revision = currentRevision(for: requestedProductID) {
                return semanticExecution(
                    commandID: prepared.commandID,
                    requestedProductID: requestedProductID,
                    authoritativeProductID: requestedProductID,
                    operation: operation,
                    outcome: .restoreRequired(
                        productID: requestedProductID,
                        revision: revision
                    ),
                    outcomeKind: .restoreRequired,
                    failure: .removedProduct,
                    durability: durability,
                    productRevision: revision
                )
            }
            return rejectedExecution(
                commandID: prepared.commandID,
                productID: requestedProductID,
                operation: operation,
                outcome: .conflict(conflict),
                failure: failure(for: conflict),
                durability: durability
            )

        case .validationFailure:
            return rejectedExecution(
                commandID: prepared.commandID,
                productID: requestedProductID,
                operation: operation,
                outcome: .validationFailure,
                failure: .invalidRequest,
                durability: durability
            )

        case let .unavailable(_, reason):
            return rejectedExecution(
                commandID: prepared.commandID,
                productID: requestedProductID,
                operation: operation,
                outcome: .unavailable(reason),
                failure: failure(for: transaction.disposition),
                durability: durability
            )

        case .committed:
            return unavailableExecution(
                commandID: prepared.commandID,
                productID: requestedProductID,
                operation: operation,
                durability: durability,
                failure: .stagedStateMismatch
            )
        }
    }

    private func acquisitionMatches(
        _ request: ProductStateProductAcquisitionRequest
    ) throws -> [WayTaskSchemaV4.Product] {
        var matches: [UUID: WayTaskSchemaV4.Product] = [:]
        for product in try products.products(id: request.productID.rawValue) {
            matches[product.id] = product
        }
        if let catalogID = request.catalogID {
            for product in try products.products(
                catalogProductIDRawValue: catalogID.rawValue
            ) {
                matches[product.id] = product
            }
        }
        if let barcode = request.barcode {
            for product in try products.products(barcode: barcode) {
                matches[product.id] = product
            }
        }
        return matches.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    private func apply(
        _ request: ProductStateProductAcquisitionRequest,
        to product: WayTaskSchemaV4.Product
    ) {
        product.imageData = request.imageData
        product.brand = request.brand
        product.category = request.category
        product.barcode = request.barcode
        product.imageURLString = request.imageURLString
        product.catalogDisplayNameSnapshot =
            request.catalogDisplayNameSnapshot
        product.catalogDisplayLocaleSnapshot =
            request.catalogDisplayLocaleSnapshot
        product.catalogCategoryIDSnapshotRawValue =
            request.catalogCategoryIDSnapshotRawValue
        product.catalogCategoryDisplayNameSnapshot =
            request.catalogCategoryDisplayNameSnapshot
        product.catalogIconKeySnapshot = request.catalogIconKeySnapshot
        product.catalogSnapshotUpdatedAt =
            request.catalogSnapshotUpdatedAt
    }

    private func isValid(
        _ request: ProductStateProductAcquisitionRequest
    ) -> Bool {
        guard request.reviewed,
              request.productID.rawValue != zeroUUID,
              request.commandID.rawValue != zeroUUID,
              request.effectiveAt.timeIntervalSince1970.isFinite,
              !request.name.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              !request.sourceRawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty
        else { return false }
        if let catalogID = request.catalogID {
            let trimmed = catalogID.rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if trimmed.isEmpty || trimmed != catalogID.rawValue {
                return false
            }
        }
        if let barcode = request.barcode {
            let trimmed = barcode.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if trimmed.isEmpty || trimmed != barcode {
                return false
            }
        }
        return true
    }

    private func operationMatches(
        _ command: ProductStateCommand,
        operation: ProductStateProductCommandOperation
    ) -> Bool {
        switch (operation, command.intent) {
        case (.edit, .editProduct),
             (.removeFromLibrary, .removeProductFromLibrary),
             (.restoreToLibrary, .restoreProductToLibrary):
            true
        default:
            false
        }
    }

    private func productID(
        for command: ProductStateCommand
    ) -> ProductStateProductID? {
        switch command.intent {
        case let .createProduct(value): value.productID
        case let .editProduct(value): value.productID
        case let .removeProductFromLibrary(value): value.productID
        case let .restoreProductToLibrary(value): value.productID
        default: nil
        }
    }

    private func commitSummary(
        commandID: ProductStateCommandID,
        productID: ProductStateProductID,
        effects: [ProductStateStagedEffect],
        durability: ProductStateProductCommandDurability
    ) -> ProductStateProductCommandCommitSummary? {
        var before: UInt64?
        var after: UInt64?
        var affectedLists: [ProductStateAffectedListRevision] = []
        var history: [ProductStateHistoryEventID] = []

        for effect in effects {
            switch effect {
            case let .productInserted(id, revision) where id == productID:
                before = 0
                after = revision
            case let .productEdited(id, prior, next) where id == productID,
                 let .productRestored(id, prior, next) where id == productID:
                before = prior
                after = next
            case let .entryDeleted(identity, revision):
                guard revision > 0 else { return nil }
                affectedLists.append(
                    ProductStateAffectedListRevision(
                        listID: identity.listID,
                        before: ProductStateListRevision(
                            value: revision - 1
                        ),
                        after: ProductStateListRevision(value: revision)
                    )
                )
            case let .historyEventInserted(id):
                history.append(id)
            default:
                break
            }
        }
        guard let before, let after else { return nil }
        affectedLists.sort {
            $0.listID.rawValue.uuidString
                < $1.listID.rawValue.uuidString
        }
        history.sort { $0.rawValue.uuidString < $1.rawValue.uuidString }
        return ProductStateProductCommandCommitSummary(
            commandID: commandID,
            productID: productID,
            productRevisionBefore: before,
            productRevisionAfter: after,
            affectedLists: affectedLists,
            historyEventIDs: history,
            durability: durability
        )
    }

    private func blockedExecution(
        commandID: ProductStateCommandID,
        productID: ProductStateProductID,
        operation: ProductStateProductCommandOperation
    ) -> ProductStateProductCommandExecution? {
        switch writeState {
        case .writableTarget:
            nil
        case .migrationIncomplete:
            rejectedExecution(
                commandID: commandID,
                productID: productID,
                operation: operation,
                outcome: .unavailable(.migrationIncomplete),
                failure: .migrationIncomplete
            )
        case .nonDurable:
            rejectedExecution(
                commandID: commandID,
                productID: productID,
                operation: operation,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .nonDurable
            )
        }
    }

    private func currentRevision(
        for productID: ProductStateProductID
    ) -> UInt64? {
        try? products.products(id: productID.rawValue).first?.revision
    }

    private func semanticExecution(
        commandID: ProductStateCommandID,
        requestedProductID: ProductStateProductID,
        authoritativeProductID: ProductStateProductID,
        operation: ProductStateProductCommandOperation,
        outcome: ProductStateProductCommandOutcome,
        outcomeKind: ProductStateProductCommandOutcomeKind,
        failure: ProductStateProductCommandFailureClassification? = nil,
        durability: ProductStateProductCommandDurability = .notAttempted,
        productRevision: UInt64
    ) -> ProductStateProductCommandExecution {
        ProductStateProductCommandExecution(
            outcome: outcome,
            diagnostic: diagnostic(
                commandID: commandID,
                requestedProductID: requestedProductID,
                authoritativeProductID: authoritativeProductID,
                operation: operation,
                outcome: outcomeKind,
                failure: failure,
                durability: durability,
                productRevisionBefore: productRevision,
                productRevisionAfter: productRevision
            )
        )
    }

    private func rejectedExecution(
        commandID: ProductStateCommandID,
        productID: ProductStateProductID,
        operation: ProductStateProductCommandOperation,
        outcome: ProductStateProductCommandOutcome,
        failure: ProductStateProductCommandFailureClassification,
        durability: ProductStateProductCommandDurability = .notAttempted
    ) -> ProductStateProductCommandExecution {
        ProductStateProductCommandExecution(
            outcome: outcome,
            diagnostic: diagnostic(
                commandID: commandID,
                requestedProductID: productID,
                authoritativeProductID: nil,
                operation: operation,
                outcome: outcomeKind(for: outcome),
                failure: failure,
                durability: durability
            )
        )
    }

    private func unavailableExecution(
        commandID: ProductStateCommandID,
        productID: ProductStateProductID,
        operation: ProductStateProductCommandOperation,
        durability: ProductStateProductCommandDurability = .notAttempted,
        failure: ProductStateProductCommandFailureClassification =
            .durableAuthorityUnavailable
    ) -> ProductStateProductCommandExecution {
        rejectedExecution(
            commandID: commandID,
            productID: productID,
            operation: operation,
            outcome: .unavailable(.durableAuthorityUnavailable),
            failure: failure,
            durability: durability
        )
    }

    private func diagnostic(
        commandID: ProductStateCommandID,
        requestedProductID: ProductStateProductID,
        authoritativeProductID: ProductStateProductID?,
        operation: ProductStateProductCommandOperation,
        outcome: ProductStateProductCommandOutcomeKind,
        failure: ProductStateProductCommandFailureClassification? = nil,
        durability: ProductStateProductCommandDurability,
        summary: ProductStateProductCommandCommitSummary? = nil,
        productRevisionBefore: UInt64? = nil,
        productRevisionAfter: UInt64? = nil,
        claimsDurableSuccess: Bool = false
    ) -> ProductStateProductCommandDiagnostic {
        ProductStateProductCommandDiagnostic(
            commandID: commandID.rawValue,
            requestedProductID: requestedProductID.rawValue,
            authoritativeProductID: authoritativeProductID?.rawValue,
            operation: operation,
            outcome: outcome,
            failure: failure,
            durability: durability,
            productRevisionBefore:
                summary?.productRevisionBefore ?? productRevisionBefore,
            productRevisionAfter:
                summary?.productRevisionAfter ?? productRevisionAfter,
            affectedListCount: summary?.affectedLists.count ?? 0,
            historyEventCount: summary?.historyEventIDs.count ?? 0,
            claimsDurableSuccess: claimsDurableSuccess
        )
    }

    private func durability(
        for disposition: ProductStateTransactionDisposition
    ) -> ProductStateProductCommandDurability {
        switch disposition {
        case .committed: .committed
        case .reconciledCommitted: .reconciledCommitted
        case .noCommitRequired: .noCommitRequired
        case .rolledBack: .rolledBack
        case .outcomeUnknown: .outcomeUnknown
        }
    }

    private func failure(
        for conflict: ProductStateCommandConflict
    ) -> ProductStateProductCommandFailureClassification {
        switch conflict {
        case .staleRevision: .staleRevision
        case .activeSession: .activeSession
        case .removedProduct: .removedProduct
        case .ambiguousIdentity, .existingNeededEntry, .reopenRequired,
             .unresolvedMigration:
            .ambiguousIdentity
        }
    }

    private func failure(
        for disposition: ProductStateTransactionDisposition
    ) -> ProductStateProductCommandFailureClassification {
        switch disposition {
        case .committed, .reconciledCommitted, .noCommitRequired:
            .durableAuthorityUnavailable
        case let .rolledBack(reason):
            switch reason {
            case .saveFailed: .saveFailed
            case .stagedStateMismatch: .stagedStateMismatch
            case .finalInvariantFailure: .finalInvariantFailure
            case .reconciliationFailed: .reconciliationFailed
            case .commitOutcomeUnknown: .outcomeUnknown
            case .preparedResultRejected: .invalidRequest
            }
        case .outcomeUnknown:
            .outcomeUnknown
        }
    }

    private func outcomeKind(
        for outcome: ProductStateProductCommandOutcome
    ) -> ProductStateProductCommandOutcomeKind {
        switch outcome {
        case .created: .created
        case .alreadyActive: .alreadyActive
        case .restoreRequired: .restoreRequired
        case .edited: .edited
        case .removed: .removed
        case .restored: .restored
        case .noOp: .noOp
        case .conflict: .conflict
        case .validationFailure: .validationFailure
        case .unavailable: .unavailable
        }
    }

    private var zeroUUID: UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ))
    }
}

// MARK: - T-11 durable Named List and Entry command authority

enum ProductStateNamedListCommandWriteState: String, Codable, Sendable {
    case writableTarget
    case migrationIncomplete
    case nonDurable
}

enum ProductStateNamedListCommandOperation: String, Codable, Sendable {
    case createNamedList
    case renameNamedList
    case addEntry
    case updateEntry
    case resolveEntry
    case reopenEntry
    case removeEntry
}

enum ProductStateNamedListCommandOutcomeKind: String, Codable, Sendable {
    case listCreated
    case listRenamed
    case entryAdded
    case existingNeeded
    case reopenRequired
    case entryUpdated
    case entryResolved
    case entryReopened
    case entryRemoved
    case noOp
    case conflict
    case validationFailure
    case unavailable
}

enum ProductStateNamedListCommandFailureClassification:
    String, Codable, Sendable {
    case migrationIncomplete
    case nonDurable
    case invalidRequest
    case staleRevision
    case activeSession
    case ambiguousIdentity
    case removedProduct
    case reopenRequired
    case unresolvedMigration
    case saveFailed
    case stagedStateMismatch
    case finalInvariantFailure
    case reconciliationFailed
    case outcomeUnknown
    case durableAuthorityUnavailable
}

enum ProductStateNamedListCommandDurability: String, Codable, Sendable {
    case committed
    case reconciledCommitted
    case noCommitRequired
    case rolledBack
    case outcomeUnknown
    case notAttempted
}

struct ProductStateNamedListCommandDiagnostic:
    Equatable, Codable, Sendable {
    let commandID: UUID
    let listID: UUID
    let requestedEntryID: UUID?
    let authoritativeEntryID: UUID?
    let productID: UUID?
    let operation: ProductStateNamedListCommandOperation
    let outcome: ProductStateNamedListCommandOutcomeKind
    let failure: ProductStateNamedListCommandFailureClassification?
    let durability: ProductStateNamedListCommandDurability
    let listRevisionBefore: UInt64?
    let listRevisionAfter: UInt64?
    let historyEventCount: Int
    let claimsDurableSuccess: Bool
}

struct ProductStateNamedListCommandCommitSummary: Equatable, Sendable {
    let commandID: ProductStateCommandID
    let listID: ProductStateListID
    let entry: ProductStateListEntryIdentity?
    let listRevisionBefore: ProductStateListRevision
    let listRevisionAfter: ProductStateListRevision
    let historyEventIDs: [ProductStateHistoryEventID]
    let durability: ProductStateNamedListCommandDurability
}

enum ProductStateNamedListCommandOutcome: Equatable, Sendable {
    case listCreated(ProductStateNamedListCommandCommitSummary)
    case listRenamed(ProductStateNamedListCommandCommitSummary)
    case entryAdded(ProductStateNamedListCommandCommitSummary)
    case existingNeeded(
        identity: ProductStateListEntryIdentity,
        listRevision: ProductStateListRevision
    )
    case reopenRequired(
        identity: ProductStateListEntryIdentity,
        listRevision: ProductStateListRevision
    )
    case entryUpdated(ProductStateNamedListCommandCommitSummary)
    case entryResolved(
        ProductStateNamedListCommandCommitSummary,
        reason: ShoppingListResolutionReason
    )
    case entryReopened(ProductStateNamedListCommandCommitSummary)
    case entryRemoved(ProductStateNamedListCommandCommitSummary)
    case noOp(
        listID: ProductStateListID,
        entry: ProductStateListEntryIdentity?,
        listRevision: ProductStateListRevision
    )
    case conflict(ProductStateCommandConflict)
    case validationFailure
    case unavailable(ProductStateUnavailableReason)
}

struct ProductStateNamedListCommandExecution: Equatable, Sendable {
    let outcome: ProductStateNamedListCommandOutcome
    let diagnostic: ProductStateNamedListCommandDiagnostic

    var claimsDurableSuccess: Bool {
        diagnostic.claimsDurableSuccess
    }
}

/// The sole T-11 mutation entry for Named Lists and their exact entries.
/// It composes T-04 preparation with the T-05 transaction owner and exposes
/// no SwiftData context, compatibility write, or list lifecycle operation.
@MainActor
final class ProductStateNamedListCommandAuthority {
    typealias TransactionCommit = (
        ProductStatePreparedCommandResult
    ) -> ProductStateTransactionResult

    private let shopping: any ShoppingRepository
    private let coordinator: ProductStateCommandCoordinator
    private let commitPrepared: TransactionCommit
    private let writeState: ProductStateNamedListCommandWriteState

    init(
        repositories: ProductStateRepositories,
        transactionCoordinator: ProductStateTransactionCoordinator,
        writeState: ProductStateNamedListCommandWriteState
    ) {
        shopping = repositories.shopping
        coordinator = ProductStateCommandCoordinator(
            repositories: repositories
        )
        commitPrepared = { transactionCoordinator.commit($0) }
        self.writeState = writeState
    }

    init(
        shopping: any ShoppingRepository,
        coordinator: ProductStateCommandCoordinator,
        writeState: ProductStateNamedListCommandWriteState,
        commitPrepared: @escaping TransactionCommit
    ) {
        self.shopping = shopping
        self.coordinator = coordinator
        self.writeState = writeState
        self.commitPrepared = commitPrepared
    }

    func createNamedList(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .createNamedList)
    }

    func renameNamedList(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .renameNamedList)
    }

    func addEntry(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .addEntry)
    }

    func updateEntry(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .updateEntry)
    }

    func resolveEntry(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .resolveEntry)
    }

    func reopenEntry(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .reopenEntry)
    }

    func removeEntry(
        _ command: ProductStateCommand
    ) -> ProductStateNamedListCommandExecution {
        execute(command, operation: .removeEntry)
    }

    private func execute(
        _ command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation
    ) -> ProductStateNamedListCommandExecution {
        guard operationMatches(command, operation: operation),
              let listID = listID(for: command)
        else {
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID(for: command) ?? zeroListID,
                outcome: .validationFailure,
                failure: .invalidRequest
            )
        }
        if let blocked = blockedExecution(
            command: command,
            operation: operation,
            listID: listID
        ) {
            return blocked
        }

        switch namedListAuthorization(
            command: command,
            operation: operation,
            listID: listID
        ) {
        case .authorized:
            break
        case .invalid:
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .validationFailure,
                failure: .invalidRequest
            )
        case .unavailable:
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .durableAuthorityUnavailable
            )
        }

        let prepared = coordinator.prepare(command)
        if case let .staged(commandID, effects) = prepared,
           !hasExactEffects(effects, for: operation) {
            let rejected = ProductStatePreparedCommandResult.unavailable(
                commandID: commandID,
                reason: .durableAuthorityUnavailable
            )
            _ = commitPrepared(rejected)
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .stagedStateMismatch,
                durability: .rolledBack
            )
        }
        return finish(
            prepared,
            command: command,
            operation: operation,
            listID: listID
        )
    }

    private func finish(
        _ prepared: ProductStatePreparedCommandResult,
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID
    ) -> ProductStateNamedListCommandExecution {
        let transaction = commitPrepared(prepared)
        let durability = durability(for: transaction.disposition)

        if transaction.claimsDurableSuccess,
           case let .staged(_, effects) = prepared,
           let summary = commitSummary(
                commandID: command.id,
                listID: listID,
                effects: effects,
                durability: durability
           ) {
            return committedExecution(
                command: command,
                operation: operation,
                summary: summary
            )
        }

        switch transaction.commandResult {
        case .noOp:
            return noOpExecution(
                command: command,
                operation: operation,
                listID: listID,
                durability: durability
            )

        case let .conflict(_, conflict):
            if operation == .addEntry,
               conflict == .reopenRequired,
               let identity = entryIdentity(for: command),
               let state = exactMembership(
                    listID: identity.listID,
                    productID: identity.productID
               ),
               state.entry.lifecycleRawValue == "resolved" {
                return semanticExecution(
                    command: command,
                    operation: operation,
                    listID: listID,
                    authoritativeEntry: state.identity,
                    outcome: .reopenRequired(
                        identity: state.identity,
                        listRevision: state.revision
                    ),
                    outcomeKind: .reopenRequired,
                    failure: .reopenRequired,
                    durability: durability,
                    listRevision: state.revision
                )
            }
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .conflict(conflict),
                failure: failure(for: conflict),
                durability: durability
            )

        case .validationFailure:
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .validationFailure,
                failure: .invalidRequest,
                durability: durability
            )

        case let .unavailable(_, reason):
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(reason),
                failure: failure(for: transaction.disposition),
                durability: durability
            )

        case .committed:
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .stagedStateMismatch,
                durability: durability
            )
        }
    }

    private func committedExecution(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        summary: ProductStateNamedListCommandCommitSummary
    ) -> ProductStateNamedListCommandExecution {
        let outcome: ProductStateNamedListCommandOutcome
        let kind: ProductStateNamedListCommandOutcomeKind
        switch operation {
        case .createNamedList:
            outcome = .listCreated(summary)
            kind = .listCreated
        case .renameNamedList:
            outcome = .listRenamed(summary)
            kind = .listRenamed
        case .addEntry:
            outcome = .entryAdded(summary)
            kind = .entryAdded
        case .updateEntry:
            outcome = .entryUpdated(summary)
            kind = .entryUpdated
        case .resolveEntry:
            guard case let .resolveListNeed(value) = command.intent else {
                return rejectedExecution(
                    command: command,
                    operation: operation,
                    listID: summary.listID,
                    outcome: .unavailable(.durableAuthorityUnavailable),
                    failure: .stagedStateMismatch,
                    durability: summary.durability
                )
            }
            outcome = .entryResolved(summary, reason: value.reason)
            kind = .entryResolved
        case .reopenEntry:
            outcome = .entryReopened(summary)
            kind = .entryReopened
        case .removeEntry:
            outcome = .entryRemoved(summary)
            kind = .entryRemoved
        }

        return ProductStateNamedListCommandExecution(
            outcome: outcome,
            diagnostic: diagnostic(
                command: command,
                operation: operation,
                listID: summary.listID,
                authoritativeEntry: summary.entry,
                outcome: kind,
                durability: summary.durability,
                summary: summary,
                claimsDurableSuccess: true
            )
        )
    }

    private func noOpExecution(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID,
        durability: ProductStateNamedListCommandDurability
    ) -> ProductStateNamedListCommandExecution {
        guard let revision = currentListRevision(listID) else {
            return rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .durableAuthorityUnavailable,
                durability: durability
            )
        }

        if operation == .addEntry,
           let requested = entryIdentity(for: command),
           let state = exactMembership(
                listID: requested.listID,
                productID: requested.productID
           ),
           state.entry.lifecycleRawValue == "needed" {
            return semanticExecution(
                command: command,
                operation: operation,
                listID: listID,
                authoritativeEntry: state.identity,
                outcome: .existingNeeded(
                    identity: state.identity,
                    listRevision: state.revision
                ),
                outcomeKind: .existingNeeded,
                durability: durability,
                listRevision: state.revision
            )
        }

        return semanticExecution(
            command: command,
            operation: operation,
            listID: listID,
            authoritativeEntry: entryIdentity(for: command),
            outcome: .noOp(
                listID: listID,
                entry: entryIdentity(for: command),
                listRevision: revision
            ),
            outcomeKind: .noOp,
            durability: durability,
            listRevision: revision
        )
    }

    private func hasExactEffects(
        _ effects: [ProductStateStagedEffect],
        for operation: ProductStateNamedListCommandOperation
    ) -> Bool {
        let stateEffects = effects.filter {
            switch $0 {
            case .listInserted, .listRenamed, .entryInserted,
                 .entryUpdated, .entryResolved, .entryReopened,
                 .entryDeleted:
                true
            default:
                false
            }
        }
        let historyCount = effects.reduce(into: 0) { count, effect in
            if case .historyEventInserted = effect { count += 1 }
        }
        guard stateEffects.count == 1 else { return false }
        switch (operation, stateEffects[0]) {
        case (.createNamedList, .listInserted),
             (.renameNamedList, .listRenamed),
             (.updateEntry, .entryUpdated):
            return historyCount == 0 && effects.count == 1
        case (.addEntry, .entryInserted),
             (.resolveEntry, .entryResolved),
             (.reopenEntry, .entryReopened),
             (.removeEntry, .entryDeleted):
            return historyCount == 1 && effects.count == 2
        default:
            return false
        }
    }

    private func commitSummary(
        commandID: ProductStateCommandID,
        listID: ProductStateListID,
        effects: [ProductStateStagedEffect],
        durability: ProductStateNamedListCommandDurability
    ) -> ProductStateNamedListCommandCommitSummary? {
        var entry: ProductStateListEntryIdentity?
        var before: UInt64?
        var after: UInt64?
        var history: [ProductStateHistoryEventID] = []

        for effect in effects {
            switch effect {
            case let .listInserted(id, revision) where id == listID:
                before = 0
                after = revision
            case let .listRenamed(id, prior, next) where id == listID:
                before = prior
                after = next
            case let .entryInserted(identity, revision),
                 let .entryUpdated(identity, revision),
                 let .entryReopened(identity, revision),
                 let .entryDeleted(identity, revision)
                where identity.listID == listID && revision > 0:
                entry = identity
                before = revision - 1
                after = revision
            case let .entryResolved(identity, _, revision)
                where identity.listID == listID && revision > 0:
                entry = identity
                before = revision - 1
                after = revision
            case let .historyEventInserted(id):
                history.append(id)
            default:
                break
            }
        }
        guard let before, let after else { return nil }
        history.sort { $0.rawValue.uuidString < $1.rawValue.uuidString }
        return ProductStateNamedListCommandCommitSummary(
            commandID: commandID,
            listID: listID,
            entry: entry,
            listRevisionBefore: ProductStateListRevision(value: before),
            listRevisionAfter: ProductStateListRevision(value: after),
            historyEventIDs: history,
            durability: durability
        )
    }

    private struct ExactMembership {
        let entry: WayTaskSchemaV4.ShoppingListEntry
        let identity: ProductStateListEntryIdentity
        let revision: ProductStateListRevision
    }

    private func exactMembership(
        listID: ProductStateListID,
        productID: ProductStateProductID
    ) -> ExactMembership? {
        do {
            let lists = try shopping.shoppingLists(id: listID.rawValue)
            let entries = try shopping.shoppingEntries(
                listID: listID.rawValue,
                productID: productID.rawValue
            )
            guard lists.count == 1, entries.count == 1 else { return nil }
            let entry = entries[0]
            return ExactMembership(
                entry: entry,
                identity: ProductStateListEntryIdentity(
                    id: ProductStateListEntryID(rawValue: entry.id),
                    listID: listID,
                    productID: productID
                ),
                revision: ProductStateListRevision(
                    value: lists[0].revision
                )
            )
        } catch {
            return nil
        }
    }

    private func currentListRevision(
        _ listID: ProductStateListID
    ) -> ProductStateListRevision? {
        do {
            let rows = try shopping.shoppingLists(id: listID.rawValue)
            guard rows.count == 1 else { return nil }
            return ProductStateListRevision(value: rows[0].revision)
        } catch {
            return nil
        }
    }

    private func operationMatches(
        _ command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation
    ) -> Bool {
        switch (operation, command.intent) {
        case (.createNamedList, .createNamedList),
             (.renameNamedList, .renameNamedList),
             (.addEntry, .addProductToList),
             (.updateEntry, .updateListEntry),
             (.resolveEntry, .resolveListNeed),
             (.reopenEntry, .reopenListNeed),
             (.removeEntry, .removeProductFromNamedList):
            true
        default:
            false
        }
    }

    private enum NamedListAuthorization {
        case authorized
        case invalid
        case unavailable
    }

    private func namedListAuthorization(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID
    ) -> NamedListAuthorization {
        if case let .createNamedList(value) = command.intent {
            return isAuthorizedPurpose(value.purposeRawValue)
                ? .authorized : .invalid
        }
        do {
            let rows = try shopping.shoppingLists(id: listID.rawValue)
            guard rows.count == 1 else { return .authorized }
            return isAuthorizedPurpose(rows[0].purposeRawValue)
                ? .authorized : .invalid
        } catch {
            return .unavailable
        }
    }

    private func isAuthorizedPurpose(_ purpose: String?) -> Bool {
        guard let purpose else { return true }
        let trimmed = purpose.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, trimmed == purpose else { return false }
        return purpose != "completed" && purpose != "recent"
    }

    private func listID(
        for command: ProductStateCommand
    ) -> ProductStateListID? {
        switch command.intent {
        case let .createNamedList(value): value.listID
        case let .renameNamedList(value): value.listID
        case let .addProductToList(value): value.entry.listID
        case let .updateListEntry(value): value.entry.listID
        case let .resolveListNeed(value): value.entry.listID
        case let .reopenListNeed(value): value.entry.listID
        case let .removeProductFromNamedList(value): value.entry.listID
        default: nil
        }
    }

    private func entryIdentity(
        for command: ProductStateCommand
    ) -> ProductStateListEntryIdentity? {
        switch command.intent {
        case let .addProductToList(value): value.entry
        case let .updateListEntry(value): value.entry
        case let .resolveListNeed(value): value.entry
        case let .reopenListNeed(value): value.entry
        case let .removeProductFromNamedList(value): value.entry
        default: nil
        }
    }

    private func blockedExecution(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID
    ) -> ProductStateNamedListCommandExecution? {
        switch writeState {
        case .writableTarget:
            nil
        case .migrationIncomplete:
            rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.migrationIncomplete),
                failure: .migrationIncomplete
            )
        case .nonDurable:
            rejectedExecution(
                command: command,
                operation: operation,
                listID: listID,
                outcome: .unavailable(.durableAuthorityUnavailable),
                failure: .nonDurable
            )
        }
    }

    private func semanticExecution(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID,
        authoritativeEntry: ProductStateListEntryIdentity?,
        outcome: ProductStateNamedListCommandOutcome,
        outcomeKind: ProductStateNamedListCommandOutcomeKind,
        failure: ProductStateNamedListCommandFailureClassification? = nil,
        durability: ProductStateNamedListCommandDurability,
        listRevision: ProductStateListRevision
    ) -> ProductStateNamedListCommandExecution {
        ProductStateNamedListCommandExecution(
            outcome: outcome,
            diagnostic: diagnostic(
                command: command,
                operation: operation,
                listID: listID,
                authoritativeEntry: authoritativeEntry,
                outcome: outcomeKind,
                failure: failure,
                durability: durability,
                listRevisionBefore: listRevision.value,
                listRevisionAfter: listRevision.value
            )
        )
    }

    private func rejectedExecution(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID,
        outcome: ProductStateNamedListCommandOutcome,
        failure: ProductStateNamedListCommandFailureClassification,
        durability: ProductStateNamedListCommandDurability = .notAttempted
    ) -> ProductStateNamedListCommandExecution {
        ProductStateNamedListCommandExecution(
            outcome: outcome,
            diagnostic: diagnostic(
                command: command,
                operation: operation,
                listID: listID,
                authoritativeEntry: nil,
                outcome: outcomeKind(for: outcome),
                failure: failure,
                durability: durability
            )
        )
    }

    private func diagnostic(
        command: ProductStateCommand,
        operation: ProductStateNamedListCommandOperation,
        listID: ProductStateListID,
        authoritativeEntry: ProductStateListEntryIdentity?,
        outcome: ProductStateNamedListCommandOutcomeKind,
        failure: ProductStateNamedListCommandFailureClassification? = nil,
        durability: ProductStateNamedListCommandDurability,
        summary: ProductStateNamedListCommandCommitSummary? = nil,
        listRevisionBefore: UInt64? = nil,
        listRevisionAfter: UInt64? = nil,
        claimsDurableSuccess: Bool = false
    ) -> ProductStateNamedListCommandDiagnostic {
        let requestedEntry = entryIdentity(for: command)
        return ProductStateNamedListCommandDiagnostic(
            commandID: command.id.rawValue,
            listID: listID.rawValue,
            requestedEntryID: requestedEntry?.id.rawValue,
            authoritativeEntryID: authoritativeEntry?.id.rawValue,
            productID: requestedEntry?.productID.rawValue,
            operation: operation,
            outcome: outcome,
            failure: failure,
            durability: durability,
            listRevisionBefore:
                summary?.listRevisionBefore.value ?? listRevisionBefore,
            listRevisionAfter:
                summary?.listRevisionAfter.value ?? listRevisionAfter,
            historyEventCount: summary?.historyEventIDs.count ?? 0,
            claimsDurableSuccess: claimsDurableSuccess
        )
    }

    private func durability(
        for disposition: ProductStateTransactionDisposition
    ) -> ProductStateNamedListCommandDurability {
        switch disposition {
        case .committed: .committed
        case .reconciledCommitted: .reconciledCommitted
        case .noCommitRequired: .noCommitRequired
        case .rolledBack: .rolledBack
        case .outcomeUnknown: .outcomeUnknown
        }
    }

    private func failure(
        for conflict: ProductStateCommandConflict
    ) -> ProductStateNamedListCommandFailureClassification {
        switch conflict {
        case .staleRevision: .staleRevision
        case .activeSession: .activeSession
        case .removedProduct: .removedProduct
        case .reopenRequired: .reopenRequired
        case .unresolvedMigration: .unresolvedMigration
        case .ambiguousIdentity, .existingNeededEntry: .ambiguousIdentity
        }
    }

    private func failure(
        for disposition: ProductStateTransactionDisposition
    ) -> ProductStateNamedListCommandFailureClassification {
        switch disposition {
        case .committed, .reconciledCommitted, .noCommitRequired:
            .durableAuthorityUnavailable
        case let .rolledBack(reason):
            switch reason {
            case .saveFailed: .saveFailed
            case .stagedStateMismatch: .stagedStateMismatch
            case .finalInvariantFailure: .finalInvariantFailure
            case .reconciliationFailed: .reconciliationFailed
            case .commitOutcomeUnknown: .outcomeUnknown
            case .preparedResultRejected: .invalidRequest
            }
        case .outcomeUnknown:
            .outcomeUnknown
        }
    }

    private func outcomeKind(
        for outcome: ProductStateNamedListCommandOutcome
    ) -> ProductStateNamedListCommandOutcomeKind {
        switch outcome {
        case .listCreated: .listCreated
        case .listRenamed: .listRenamed
        case .entryAdded: .entryAdded
        case .existingNeeded: .existingNeeded
        case .reopenRequired: .reopenRequired
        case .entryUpdated: .entryUpdated
        case .entryResolved: .entryResolved
        case .entryReopened: .entryReopened
        case .entryRemoved: .entryRemoved
        case .noOp: .noOp
        case .conflict: .conflict
        case .validationFailure: .validationFailure
        case .unavailable: .unavailable
        }
    }

    private var zeroListID: ProductStateListID {
        ProductStateListID(
            rawValue: UUID(uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ))
        )
    }
}
