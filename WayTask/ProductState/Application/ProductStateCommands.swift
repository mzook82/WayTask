import Foundation

// MARK: - S-01 command descriptions

enum ProductStateCommandCategory: String, CaseIterable, Hashable, Sendable {
    case createProduct
    case editProduct
    case removeProductFromLibrary
    case restoreProductToLibrary
    case createNamedList
    case renameNamedList
    case addProductToList
    case updateListEntry
    case resolveListNeed
    case reopenListNeed
    case removeProductFromNamedList
    case generatePlan
    case supersedePlan
    case startSession
    case resumeSession
    case markLineCollected
    case undoLineCollection
    case prepareFinishOutcome
    case finishSession
    case abandonSession
    case createSavedLocation
    case editSavedLocation
    case removeSavedLocation
}

enum ProductStateCommandScope: Hashable, Sendable {
    case product(ProductStateProductID)
    case list(ProductStateListID)
    case entry(ProductStateListEntryIdentity)
    case plan(ProductStatePlanID)
    case session(ProductStateSessionID)
    case sessionLine(
        sessionID: ProductStateSessionID,
        lineID: ProductStateSessionLineID
    )
    case savedLocation(UUID)
}

struct CreateProductCommand: Hashable, Sendable {
    let productID: ProductStateProductID
    let name: String
    let sourceRawValue: String
    let catalogID: ProductStateCatalogID?
}

struct EditProductCommand: Hashable, Sendable {
    let productID: ProductStateProductID
    let name: String
}

struct RemoveProductFromLibraryCommand: Hashable, Sendable {
    let productID: ProductStateProductID
    let historyEventID: ProductStateHistoryEventID
    let confirmed: Bool
}

struct RestoreProductToLibraryCommand: Hashable, Sendable {
    let productID: ProductStateProductID
    let historyEventID: ProductStateHistoryEventID
    let confirmed: Bool
}

struct CreateNamedListCommand: Hashable, Sendable {
    let listID: ProductStateListID
    let title: String
    let purposeRawValue: String?
}

struct RenameNamedListCommand: Hashable, Sendable {
    let listID: ProductStateListID
    let title: String
}

struct AddProductToListCommand: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let historyEventID: ProductStateHistoryEventID
    let quantity: Double
    let unitRawValue: String?
    let note: String?
    let sortOrder: Double
}

struct UpdateListEntryCommand: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let quantity: Double
    let unitRawValue: String?
    let note: String?
    let sortOrder: Double
}

struct ResolveListNeedCommand: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let historyEventID: ProductStateHistoryEventID
    let reason: ShoppingListResolutionReason
}

struct ReopenListNeedCommand: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let historyEventID: ProductStateHistoryEventID
}

struct RemoveProductFromNamedListCommand: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let historyEventID: ProductStateHistoryEventID
}

struct GeneratePlanCommand: Hashable, Sendable {
    let planID: ProductStatePlanID
    let listID: ProductStateListID
    let sourceRevision: ProductStateListRevision
    let entries: [ProductStateListEntryIdentity]
}

struct SupersedePlanCommand: Hashable, Sendable {
    let planID: ProductStatePlanID
}

struct StartSessionCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
    let listID: ProductStateListID
    let sourceRevision: ProductStateListRevision
    let entries: [ProductStateListEntryIdentity]
}

struct SessionCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
}

struct SessionLineCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
    let lineID: ProductStateSessionLineID
}

struct PrepareFinishOutcomeCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
    let lineID: ProductStateSessionLineID
    let outcome: ShoppingSessionFinalOutcome
}

struct FinishSessionLineOutcome: Hashable, Sendable {
    let lineID: ProductStateSessionLineID
    let outcome: ShoppingSessionFinalOutcome
}

struct FinishSessionCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
    let outcomes: [FinishSessionLineOutcome]
    let confirmed: Bool
}

struct AbandonSessionCommand: Hashable, Sendable {
    let sessionID: ProductStateSessionID
    let confirmed: Bool
}

struct CreateSavedLocationCommand: Hashable, Sendable {
    let locationID: UUID
    let title: String
}

struct EditSavedLocationCommand: Hashable, Sendable {
    let locationID: UUID
    let title: String
}

struct RemoveSavedLocationCommand: Hashable, Sendable {
    let locationID: UUID
    let confirmed: Bool
}

enum ProductStateCommandIntent: Hashable, Sendable {
    case createProduct(CreateProductCommand)
    case editProduct(EditProductCommand)
    case removeProductFromLibrary(RemoveProductFromLibraryCommand)
    case restoreProductToLibrary(RestoreProductToLibraryCommand)
    case createNamedList(CreateNamedListCommand)
    case renameNamedList(RenameNamedListCommand)
    case addProductToList(AddProductToListCommand)
    case updateListEntry(UpdateListEntryCommand)
    case resolveListNeed(ResolveListNeedCommand)
    case reopenListNeed(ReopenListNeedCommand)
    case removeProductFromNamedList(RemoveProductFromNamedListCommand)
    case generatePlan(GeneratePlanCommand)
    case supersedePlan(SupersedePlanCommand)
    case startSession(StartSessionCommand)
    case resumeSession(SessionCommand)
    case markLineCollected(SessionLineCommand)
    case undoLineCollection(SessionLineCommand)
    case prepareFinishOutcome(PrepareFinishOutcomeCommand)
    case finishSession(FinishSessionCommand)
    case abandonSession(AbandonSessionCommand)
    case createSavedLocation(CreateSavedLocationCommand)
    case editSavedLocation(EditSavedLocationCommand)
    case removeSavedLocation(RemoveSavedLocationCommand)

    var category: ProductStateCommandCategory {
        switch self {
        case .createProduct: .createProduct
        case .editProduct: .editProduct
        case .removeProductFromLibrary: .removeProductFromLibrary
        case .restoreProductToLibrary: .restoreProductToLibrary
        case .createNamedList: .createNamedList
        case .renameNamedList: .renameNamedList
        case .addProductToList: .addProductToList
        case .updateListEntry: .updateListEntry
        case .resolveListNeed: .resolveListNeed
        case .reopenListNeed: .reopenListNeed
        case .removeProductFromNamedList: .removeProductFromNamedList
        case .generatePlan: .generatePlan
        case .supersedePlan: .supersedePlan
        case .startSession: .startSession
        case .resumeSession: .resumeSession
        case .markLineCollected: .markLineCollected
        case .undoLineCollection: .undoLineCollection
        case .prepareFinishOutcome: .prepareFinishOutcome
        case .finishSession: .finishSession
        case .abandonSession: .abandonSession
        case .createSavedLocation: .createSavedLocation
        case .editSavedLocation: .editSavedLocation
        case .removeSavedLocation: .removeSavedLocation
        }
    }

    var scope: ProductStateCommandScope {
        switch self {
        case let .createProduct(value):
            .product(value.productID)
        case let .editProduct(value):
            .product(value.productID)
        case let .removeProductFromLibrary(value):
            .product(value.productID)
        case let .restoreProductToLibrary(value):
            .product(value.productID)
        case let .createNamedList(value):
            .list(value.listID)
        case let .renameNamedList(value):
            .list(value.listID)
        case let .addProductToList(value):
            .entry(value.entry)
        case let .updateListEntry(value):
            .entry(value.entry)
        case let .resolveListNeed(value):
            .entry(value.entry)
        case let .reopenListNeed(value):
            .entry(value.entry)
        case let .removeProductFromNamedList(value):
            .entry(value.entry)
        case let .generatePlan(value):
            .plan(value.planID)
        case let .supersedePlan(value):
            .plan(value.planID)
        case let .startSession(value):
            .session(value.sessionID)
        case let .resumeSession(value):
            .session(value.sessionID)
        case let .markLineCollected(value):
            .sessionLine(sessionID: value.sessionID, lineID: value.lineID)
        case let .undoLineCollection(value):
            .sessionLine(sessionID: value.sessionID, lineID: value.lineID)
        case let .prepareFinishOutcome(value):
            .sessionLine(sessionID: value.sessionID, lineID: value.lineID)
        case let .finishSession(value):
            .session(value.sessionID)
        case let .abandonSession(value):
            .session(value.sessionID)
        case let .createSavedLocation(value):
            .savedLocation(value.locationID)
        case let .editSavedLocation(value):
            .savedLocation(value.locationID)
        case let .removeSavedLocation(value):
            .savedLocation(value.locationID)
        }
    }
}

struct ProductStateCommand: Hashable, Sendable {
    let id: ProductStateCommandID
    let expectedRevision: ProductStateExpectedRevision?
    let effectiveAt: Date
    let intent: ProductStateCommandIntent

    var category: ProductStateCommandCategory { intent.category }
    var scope: ProductStateCommandScope { intent.scope }
}

// MARK: - Pure command shape validation

enum ProductStateCommandShapeViolationCode:
    String, CaseIterable, Hashable, Sendable {
    case invalidCommandIdentity
    case invalidScopeIdentity
    case missingExpectedRevision
    case unexpectedExpectedRevision
    case invalidExpectedRevision
    case expectedRevisionScopeMismatch
    case sourceRevisionMismatch
    case invalidEffectiveTime
    case invalidName
    case invalidSource
    case invalidEntryValues
    case invalidResolutionReason
    case invalidSourceEntries
    case invalidFinishOutcomes
    case missingConfirmation
    case invalidHistoryEventIdentity
}

struct ProductStateCommandShapeValidator: Sendable {
    func validate(
        _ command: ProductStateCommand
    ) -> [ProductStateCommandShapeViolationCode] {
        var codes = Set<ProductStateCommandShapeViolationCode>()

        if !isValid(command.id.rawValue) {
            codes.insert(.invalidCommandIdentity)
        }
        if !hasValidScope(command.scope) {
            codes.insert(.invalidScopeIdentity)
        }
        if !command.effectiveAt.timeIntervalSince1970.isFinite {
            codes.insert(.invalidEffectiveTime)
        }

        validateExpectedRevision(command, into: &codes)
        validateIntent(command.intent, into: &codes)

        return codes.sorted { $0.rawValue < $1.rawValue }
    }

    private func validateExpectedRevision(
        _ command: ProductStateCommand,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        let requiredScope = expectedRevisionScope(for: command.intent)

        guard let requiredScope else {
            if command.expectedRevision != nil {
                codes.insert(.unexpectedExpectedRevision)
            }
            return
        }

        guard let expected = command.expectedRevision else {
            codes.insert(.missingExpectedRevision)
            return
        }
        if expected.revision.value == 0 {
            codes.insert(.invalidExpectedRevision)
        }
        if expected.revision.scope != requiredScope {
            codes.insert(.expectedRevisionScopeMismatch)
        }

        switch command.intent {
        case let .generatePlan(value):
            if value.sourceRevision.value != expected.revision.value {
                codes.insert(.sourceRevisionMismatch)
            }
        case let .startSession(value):
            if value.sourceRevision.value != expected.revision.value {
                codes.insert(.sourceRevisionMismatch)
            }
        default:
            break
        }
    }

    private func expectedRevisionScope(
        for intent: ProductStateCommandIntent
    ) -> ProductStateRevisionScope? {
        switch intent {
        case let .editProduct(value):
            .product(value.productID)
        case let .removeProductFromLibrary(value):
            .product(value.productID)
        case let .restoreProductToLibrary(value):
            .product(value.productID)
        case let .renameNamedList(value):
            .list(value.listID)
        case let .addProductToList(value):
            .list(value.entry.listID)
        case let .updateListEntry(value):
            .list(value.entry.listID)
        case let .resolveListNeed(value):
            .list(value.entry.listID)
        case let .reopenListNeed(value):
            .list(value.entry.listID)
        case let .removeProductFromNamedList(value):
            .list(value.entry.listID)
        case let .generatePlan(value):
            .list(value.listID)
        case let .startSession(value):
            .list(value.listID)
        case let .resumeSession(value):
            .session(value.sessionID)
        case let .markLineCollected(value):
            .session(value.sessionID)
        case let .undoLineCollection(value):
            .session(value.sessionID)
        case let .prepareFinishOutcome(value):
            .session(value.sessionID)
        case let .finishSession(value):
            .session(value.sessionID)
        case let .abandonSession(value):
            .session(value.sessionID)
        case .createProduct, .createNamedList, .supersedePlan,
             .createSavedLocation, .editSavedLocation, .removeSavedLocation:
            nil
        }
    }

    private func validateIntent(
        _ intent: ProductStateCommandIntent,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        switch intent {
        case let .createProduct(value):
            validateName(value.name, into: &codes)
            if value.sourceRawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                codes.insert(.invalidSource)
            }

        case let .editProduct(value):
            validateName(value.name, into: &codes)

        case let .removeProductFromLibrary(value):
            validateHistory(value.historyEventID, into: &codes)
            if !value.confirmed { codes.insert(.missingConfirmation) }

        case let .restoreProductToLibrary(value):
            validateHistory(value.historyEventID, into: &codes)
            if !value.confirmed { codes.insert(.missingConfirmation) }

        case let .createNamedList(value):
            validateName(value.title, into: &codes)

        case let .renameNamedList(value):
            validateName(value.title, into: &codes)

        case let .addProductToList(value):
            validateHistory(value.historyEventID, into: &codes)
            validateEntryValues(
                quantity: value.quantity,
                sortOrder: value.sortOrder,
                into: &codes
            )

        case let .updateListEntry(value):
            validateEntryValues(
                quantity: value.quantity,
                sortOrder: value.sortOrder,
                into: &codes
            )

        case let .resolveListNeed(value):
            validateHistory(value.historyEventID, into: &codes)
            if value.reason == .purchased || value.reason == .legacyUnknown {
                codes.insert(.invalidResolutionReason)
            }

        case let .reopenListNeed(value):
            validateHistory(value.historyEventID, into: &codes)

        case let .removeProductFromNamedList(value):
            validateHistory(value.historyEventID, into: &codes)

        case let .generatePlan(value):
            validateEntries(
                value.entries,
                listID: value.listID,
                into: &codes
            )

        case .supersedePlan:
            break

        case let .startSession(value):
            validateEntries(
                value.entries,
                listID: value.listID,
                into: &codes
            )

        case .resumeSession, .markLineCollected, .undoLineCollection,
             .prepareFinishOutcome:
            break

        case let .finishSession(value):
            let lineIDs = value.outcomes.map(\.lineID)
            if value.outcomes.isEmpty
                || Set(lineIDs).count != lineIDs.count
                || lineIDs.contains(where: { !isValid($0.rawValue) })
            {
                codes.insert(.invalidFinishOutcomes)
            }
            if !value.confirmed { codes.insert(.missingConfirmation) }

        case let .abandonSession(value):
            if !value.confirmed { codes.insert(.missingConfirmation) }

        case let .createSavedLocation(value):
            validateName(value.title, into: &codes)

        case let .editSavedLocation(value):
            validateName(value.title, into: &codes)

        case let .removeSavedLocation(value):
            if !value.confirmed { codes.insert(.missingConfirmation) }
        }
    }

    private func validateName(
        _ value: String,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            codes.insert(.invalidName)
        }
    }

    private func validateHistory(
        _ id: ProductStateHistoryEventID,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        if !isValid(id.rawValue) {
            codes.insert(.invalidHistoryEventIdentity)
        }
    }

    private func validateEntryValues(
        quantity: Double,
        sortOrder: Double,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        if !quantity.isFinite || quantity <= 0 || !sortOrder.isFinite {
            codes.insert(.invalidEntryValues)
        }
    }

    private func validateEntries(
        _ entries: [ProductStateListEntryIdentity],
        listID: ProductStateListID,
        into codes: inout Set<ProductStateCommandShapeViolationCode>
    ) {
        if entries.isEmpty
            || Set(entries.map(\.id)).count != entries.count
            || entries.contains(where: { $0.listID != listID })
        {
            codes.insert(.invalidSourceEntries)
        }
    }

    private func hasValidScope(_ scope: ProductStateCommandScope) -> Bool {
        switch scope {
        case let .product(id):
            isValid(id.rawValue)
        case let .list(id):
            isValid(id.rawValue)
        case let .entry(identity):
            isValid(identity.id.rawValue)
                && isValid(identity.listID.rawValue)
                && isValid(identity.productID.rawValue)
        case let .plan(id):
            isValid(id.rawValue)
        case let .session(id):
            isValid(id.rawValue)
        case let .sessionLine(sessionID, lineID):
            isValid(sessionID.rawValue) && isValid(lineID.rawValue)
        case let .savedLocation(id):
            isValid(id)
        }
    }

    private func isValid(_ id: UUID) -> Bool {
        id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}

// MARK: - Prepared, explicitly non-durable semantics

enum ProductStateCommandPipelineConflict: Hashable, Sendable {
    case approved(ProductStateCommandConflict)
    case missingTarget(ProductStateCommandScope)
    case duplicateTarget(ProductStateCommandScope)
}

enum ProductStateStagedEffect: Hashable, Sendable {
    case productInserted(id: ProductStateProductID, revision: UInt64)
    case productEdited(
        id: ProductStateProductID,
        beforeRevision: UInt64,
        afterRevision: UInt64
    )
    case productRestored(
        id: ProductStateProductID,
        beforeRevision: UInt64,
        afterRevision: UInt64
    )
    case listInserted(id: ProductStateListID, revision: UInt64)
    case listRenamed(
        id: ProductStateListID,
        beforeRevision: UInt64,
        afterRevision: UInt64
    )
    case entryInserted(
        identity: ProductStateListEntryIdentity,
        listRevision: UInt64
    )
    case entryUpdated(
        identity: ProductStateListEntryIdentity,
        listRevision: UInt64
    )
    case entryResolved(
        identity: ProductStateListEntryIdentity,
        reason: ShoppingListResolutionReason,
        listRevision: UInt64
    )
    case entryReopened(
        identity: ProductStateListEntryIdentity,
        listRevision: UInt64
    )
    case entryDeleted(
        identity: ProductStateListEntryIdentity,
        listRevision: UInt64
    )
    case sessionInserted(
        id: ProductStateSessionID,
        revision: UInt64,
        snapshotID: ProductStateSessionSnapshotID,
        snapshotContentSignature: String,
        lineIDs: [ProductStateSessionLineID],
        stopIDs: [ProductStateSessionStopID]
    )
    case sessionLineExecutionChanged(
        sessionID: ProductStateSessionID,
        lineID: ProductStateSessionLineID,
        beforeRevision: UInt64,
        afterRevision: UInt64,
        executionState: ShoppingSessionExecutionState,
        executionChangedAt: Date
    )
    case sessionActivityRecorded(
        sessionID: ProductStateSessionID,
        stopID: ProductStateSessionStopID,
        beforeRevision: UInt64,
        afterRevision: UInt64,
        activityRawValue: String,
        lastActivityAt: Date
    )
    case sessionLifecycleChanged(
        id: ProductStateSessionID,
        beforeRevision: UInt64,
        afterRevision: UInt64,
        beforeLifecycle: ShoppingSessionLifecycle,
        afterLifecycle: ShoppingSessionLifecycle,
        transitionedAt: Date
    )
    case sessionFinished(
        id: ProductStateSessionID,
        beforeRevision: UInt64,
        afterRevision: UInt64,
        listID: ProductStateListID,
        listBeforeRevision: UInt64,
        listAfterRevision: UInt64,
        lineOutcomes: [ProductStateSessionLineOutcomeEffect],
        resolvedEntries: [ProductStateSessionEntryResolutionEffect],
        finishedAt: Date
    )
    case historyEventInserted(ProductStateHistoryEventID)
}

struct ProductStateSessionLineOutcomeEffect: Hashable, Sendable {
    let lineID: ProductStateSessionLineID
    let outcome: ShoppingSessionFinalOutcome
}

struct ProductStateSessionEntryResolutionEffect: Hashable, Sendable {
    let identity: ProductStateListEntryIdentity
    let reason: ShoppingListResolutionReason
}

struct ProductStatePreparedValidationFailure: Hashable, Sendable {
    let shapeViolations: [ProductStateCommandShapeViolationCode]
    let invariantViolations: [ProductStateInvariantCode]
}

enum ProductStatePreparedCommandResult: Hashable, Sendable {
    case staged(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect]
    )
    case noOp(commandID: ProductStateCommandID)
    case conflict(
        commandID: ProductStateCommandID,
        conflict: ProductStateCommandPipelineConflict
    )
    case validationFailure(
        commandID: ProductStateCommandID,
        failure: ProductStatePreparedValidationFailure
    )
    case unavailable(
        commandID: ProductStateCommandID,
        reason: ProductStateUnavailableReason
    )

    var commandID: ProductStateCommandID {
        switch self {
        case let .staged(commandID, _), let .noOp(commandID),
             let .conflict(commandID, _),
             let .validationFailure(commandID, _),
             let .unavailable(commandID, _):
            commandID
        }
    }

    /// T-04 has no durable-success state. Even `.staged` means only that one
    /// caller-owned repository scope contains prepared, unsaved changes.
    var claimsDurableSuccess: Bool { false }
}
