import Foundation

// MARK: - Stable identities

struct ProductStateProductID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateCatalogID: Hashable, Sendable {
    let rawValue: String
}

struct ProductStateListID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateListEntryID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateListEntryIdentity: Hashable, Sendable {
    let id: ProductStateListEntryID
    let listID: ProductStateListID
    let productID: ProductStateProductID
}

struct ProductStatePlanID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateSessionID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateSessionSnapshotID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateSessionStopID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateSessionLineID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateHistoryEventID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateCommandID: Hashable, Sendable {
    let rawValue: UUID
}

// MARK: - Product and Product Library

enum ProductLibraryLifecycle: String, CaseIterable, Hashable, Sendable {
    case active
    case removed
}

enum ProductLibraryAction: String, CaseIterable, Hashable, Sendable {
    case removeFromLibrary
    case restoreToLibrary
}

struct ProductStateProductSnapshot: Hashable, Sendable {
    let id: ProductStateProductID
    let catalogID: ProductStateCatalogID?
    let libraryLifecycle: ProductLibraryLifecycle
}

// MARK: - Shopping Lists and entries

struct ProductStateListRevision: Hashable, Comparable, Sendable {
    let value: UInt64

    static func < (
        lhs: ProductStateListRevision,
        rhs: ProductStateListRevision
    ) -> Bool {
        lhs.value < rhs.value
    }
}

enum ShoppingListResolutionReason: String, CaseIterable, Hashable, Sendable {
    case purchased
    case alreadyHave
    case noLongerNeeded
    case legacyUnknown
}

enum ShoppingListResolutionProvenance: Hashable, Sendable {
    case userCommand(ProductStateCommandID)
    case sessionFinish(
        commandID: ProductStateCommandID,
        sessionID: ProductStateSessionID,
        lineID: ProductStateSessionLineID
    )
    case legacyMigration
}

struct ShoppingListResolution: Hashable, Sendable {
    let reason: ShoppingListResolutionReason
    let effectiveAt: Date
    let provenance: ShoppingListResolutionProvenance
}

enum ShoppingListEntryLifecycle: Hashable, Sendable {
    case needed
    case resolved(ShoppingListResolution)
}

struct ProductStateListEntrySnapshot: Hashable, Sendable {
    let identity: ProductStateListEntryIdentity
    let lifecycle: ShoppingListEntryLifecycle
}

struct ProductStateShoppingListSnapshot: Equatable, Sendable {
    let id: ProductStateListID
    let revision: ProductStateListRevision
    let entries: [ProductStateListEntrySnapshot]

    func entries(for productID: ProductStateProductID)
        -> [ProductStateListEntrySnapshot]
    {
        entries.filter { $0.identity.productID == productID }
    }

    func contains(productID: ProductStateProductID) -> Bool {
        !entries(for: productID).isEmpty
    }
}

struct ProductStateListMembershipKey: Hashable, Sendable {
    let listID: ProductStateListID
    let productID: ProductStateProductID
}

enum ShoppingListEntryAction: String, CaseIterable, Hashable, Sendable {
    case resolve
    case reopen
}

// MARK: - Shopping Plans

enum ShoppingPlanExclusionReason: String, CaseIterable, Hashable, Sendable {
    case notNeeded
    case invalidProduct
    case unsupported
    case userExcluded
}

struct ShoppingPlanExclusion: Hashable, Sendable {
    let entry: ProductStateListEntryIdentity
    let reason: ShoppingPlanExclusionReason
}

struct ProductStateFailureCode: Hashable, Sendable {
    let rawValue: String
}

enum ShoppingPlanStaleReason: String, CaseIterable, Hashable, Sendable {
    case sourceRevisionChanged
    case includedEntriesChanged
    case planningInputChanged
    case evidenceExpired
}

enum ShoppingPlanStatus: Hashable, Sendable {
    case idle
    case generating
    case ready
    case failed(ProductStateFailureCode)
    case stale(ShoppingPlanStaleReason)
}

struct ProductStateShoppingPlan: Equatable, Sendable {
    let id: ProductStatePlanID
    let sourceListID: ProductStateListID
    let sourceRevision: ProductStateListRevision
    let includedEntries: [ProductStateListEntryIdentity]
    let exclusions: [ShoppingPlanExclusion]
    let status: ShoppingPlanStatus
}

// MARK: - Shopping Sessions

struct ProductStateSessionRevision: Hashable, Comparable, Sendable {
    let value: UInt64

    static func < (
        lhs: ProductStateSessionRevision,
        rhs: ProductStateSessionRevision
    ) -> Bool {
        lhs.value < rhs.value
    }
}

enum ShoppingSessionLifecycle: String, CaseIterable, Hashable, Sendable {
    case active
    case expired
    case finished
    case abandoned

    var isTerminal: Bool {
        self == .finished || self == .abandoned
    }
}

enum ShoppingSessionExecutionState: String, CaseIterable, Hashable, Sendable {
    case remaining
    case collected
}

enum ShoppingSessionFinalOutcome: String, CaseIterable, Hashable, Sendable {
    case purchased
    case alreadyHave
    case noLongerNeeded
    case unavailable
    case skipped
    case carriedForward
}

enum ShoppingSessionLegacyDisposition: String, CaseIterable, Hashable, Sendable {
    case legacyUnknown
}

enum ShoppingSessionMigrationCondition: String, CaseIterable, Hashable, Sendable {
    case native
    case legacyMapped
    case legacyIncomplete
    case legacyUnresolved
}

enum ShoppingSessionSourceRevision: Hashable, Sendable {
    case exact(ProductStateListRevision)
    case legacyUnknown
}

struct ShoppingSessionLineSnapshot: Hashable, Sendable {
    let id: ProductStateSessionLineID
    let snapshotID: ProductStateSessionSnapshotID
    let sourceEntry: ProductStateListEntryIdentity
    let productID: ProductStateProductID
    let stopID: ProductStateSessionStopID
}

struct ShoppingSessionLine: Hashable, Sendable {
    let snapshot: ShoppingSessionLineSnapshot
    var executionState: ShoppingSessionExecutionState
    var finalOutcome: ShoppingSessionFinalOutcome?
    var legacyDisposition: ShoppingSessionLegacyDisposition?
}

struct ProductStateShoppingSession: Equatable, Sendable {
    let id: ProductStateSessionID
    let snapshotID: ProductStateSessionSnapshotID
    let sourceListID: ProductStateListID
    let sourceRevision: ShoppingSessionSourceRevision
    let stopIDs: [ProductStateSessionStopID]
    let migrationCondition: ShoppingSessionMigrationCondition
    var lifecycle: ShoppingSessionLifecycle
    var revision: ProductStateSessionRevision
    var lines: [ShoppingSessionLine]
}

enum ShoppingSessionAction: Hashable, Sendable {
    case collect(ProductStateSessionLineID)
    case undo(ProductStateSessionLineID)
    case expire
    case resume
    case finish
    case abandon
    case recover
}

struct ShoppingSessionSemanticEffects: Equatable, Sendable {
    let resolvedEntries: [ProductStateListEntryIdentity]
    let historyMeanings: [ProductHistoryEventMeaning]

    static let none = ShoppingSessionSemanticEffects(
        resolvedEntries: [],
        historyMeanings: []
    )
}

// MARK: - Product History

enum ProductHistoryEventMeaning: Hashable, Sendable {
    case needAdded
    case needResolved(ShoppingListResolutionReason)
    case needReopened
    case listMembershipRemoved
    case productRemovedFromLibrary
    case productRestoredToLibrary
    case sessionOutcome(ShoppingSessionFinalOutcome)
}

enum ProductHistoryEventProvenance: Hashable, Sendable {
    case userCommand(ProductStateCommandID)
    case sessionFinish(
        commandID: ProductStateCommandID,
        sessionID: ProductStateSessionID,
        lineID: ProductStateSessionLineID
    )
    case legacyMigration
}

struct ProductStateHistoryEvent: Hashable, Sendable {
    let id: ProductStateHistoryEventID
    let productID: ProductStateProductID
    let meaning: ProductHistoryEventMeaning
    let provenance: ProductHistoryEventProvenance
    let occurredAt: Date
}

// MARK: - Commands and revisions

enum ProductStateRevisionScope: Hashable, Sendable {
    case product(ProductStateProductID)
    case list(ProductStateListID)
    case session(ProductStateSessionID)
    case history(ProductStateProductID)
}

struct ProductStateRevision: Hashable, Sendable {
    let scope: ProductStateRevisionScope
    let value: UInt64
}

struct ProductStateExpectedRevision: Hashable, Sendable {
    let revision: ProductStateRevision
}

struct ProductStateRevisionChange: Hashable, Sendable {
    let before: ProductStateRevision
    let after: ProductStateRevision
}

struct ProductStateCommandEffects: Hashable, Sendable {
    let revisionChanges: [ProductStateRevisionChange]
    let historyEventIDs: [ProductStateHistoryEventID]

    static let none = ProductStateCommandEffects(
        revisionChanges: [],
        historyEventIDs: []
    )
}

struct ProductStateCommandReceipt: Hashable, Sendable {
    let commandID: ProductStateCommandID
    let effects: ProductStateCommandEffects
}

enum ProductStateCommandConflict: String, CaseIterable, Hashable, Sendable {
    case staleRevision
    case existingNeededEntry
    case reopenRequired
    case activeSession
    case removedProduct
    case ambiguousIdentity
    case unresolvedMigration
}

enum ProductStateUnavailableReason: String, CaseIterable, Hashable, Sendable {
    case durableAuthorityUnavailable
    case migrationIncomplete
    case unsupportedOperation
}

enum ProductStateCommandResult: Equatable, Sendable {
    case committed(ProductStateCommandReceipt)
    case noOp(ProductStateCommandReceipt)
    case conflict(
        commandID: ProductStateCommandID,
        conflict: ProductStateCommandConflict
    )
    case validationFailure(
        commandID: ProductStateCommandID,
        violations: [ProductStateInvariantViolation]
    )
    case unavailable(
        commandID: ProductStateCommandID,
        reason: ProductStateUnavailableReason
    )

    var commandID: ProductStateCommandID {
        switch self {
        case let .committed(receipt), let .noOp(receipt):
            receipt.commandID
        case let .conflict(commandID, _),
             let .validationFailure(commandID, _),
             let .unavailable(commandID, _):
            commandID
        }
    }
}
