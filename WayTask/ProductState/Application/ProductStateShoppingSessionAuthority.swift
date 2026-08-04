import CryptoKit
import Foundation

// MARK: - T-19 immutable command inputs

enum ProductStateSessionCommandWriteState: Equatable, Sendable {
    case writableTarget
    case migrationIncomplete
    case nonDurable
}

struct ProductStateSessionStopInput: Equatable, Sendable {
    let id: ProductStateSessionStopID
    let sortOrder: Int
    let storeReferenceIDRawValue: String?
    let storeReferenceProvenanceRawValue: String
    let displayNameSnapshot: String
    let latitude: Double
    let longitude: Double
    let evidenceAt: Date
    let isSessionScopedTransient: Bool
}

struct ProductStateSessionLineInput: Equatable, Sendable {
    let id: ProductStateSessionLineID
    let sourceEntry: ProductStateListEntryIdentity
    let stopID: ProductStateSessionStopID
    let sortOrder: Int
    let globalProductConceptIDRawValue: String?
}

struct ProductStateSessionStartInput: Equatable, Sendable {
    let command: ProductStateCommand
    let plan: ProductStateShoppingPlan
    let planFingerprint: String
    let planEvidenceAt: Date
    let confirmedStaleEvidenceAt: Date?
    let snapshotID: ProductStateSessionSnapshotID
    let stops: [ProductStateSessionStopInput]
    let lines: [ProductStateSessionLineInput]
}

struct ProductStateSessionFinishInput: Equatable, Sendable {
    let command: ProductStateCommand
    let expectedListRevision: ProductStateListRevision
}

struct ProductStateExpireSessionCommand: Hashable, Sendable {
    let id: ProductStateCommandID
    let sessionID: ProductStateSessionID
    let expectedRevision: ProductStateSessionRevision
    let effectiveAt: Date
}

enum ProductStateSessionStopActivity: String, CaseIterable, Sendable {
    case selected
    case completed
    case skipped
    case externalNavigationStarted
}

struct ProductStateSessionStopActivityCommand: Hashable, Sendable {
    let id: ProductStateCommandID
    let sessionID: ProductStateSessionID
    let expectedRevision: ProductStateSessionRevision
    let stopID: ProductStateSessionStopID
    let activity: ProductStateSessionStopActivity
    let effectiveAt: Date
}

// MARK: - Bounded outcomes

enum ProductStateSessionPlanFreshness: Equatable, Sendable {
    case fresh
    case staleConfirmed(evidenceAt: Date)
}

enum ProductStateSessionConflict: Equatable, Sendable {
    case staleSessionRevision(
        expected: ProductStateSessionRevision,
        actual: ProductStateSessionRevision
    )
    case staleListRevision(
        expected: ProductStateListRevision,
        actual: ProductStateListRevision
    )
    case nonTerminalSessions([ProductStateSessionID])
    case duplicateSessionIdentity(ProductStateSessionID)
    case wrongLifecycle(
        expected: [ShoppingSessionLifecycle],
        actual: ShoppingSessionLifecycle
    )
    case expirationRequired(ProductStateSessionRevision)
    case foreignSessionOwner
    case sourceEntryChanged(ProductStateListEntryID)
    case transactionConflict
}

enum ProductStateSessionInvalidReason: Equatable, Sendable {
    case commandShape([ProductStateCommandShapeViolationCode])
    case wrongCommand
    case invalidIdentity
    case invalidPlan
    case planIdentityMismatch
    case planEvidenceInFuture
    case planEvidenceExpired
    case stalePlanConfirmationRequired(Date)
    case invalidSnapshot
    case invalidStops
    case invalidLineAssignments
    case invalidSourceEntries
    case invalidSessionAuthority
    case invalidMigrationCondition
    case invalidFinishOutcomes
    case expirationNotDue
    case invalidTransitionTime
}

enum ProductStateSessionUnavailableReason: Equatable, Sendable {
    case durableAuthorityUnavailable
    case migrationIncomplete
    case repositoryReadFailed
    case sessionNotFound(ProductStateSessionID)
    case listNotFound(ProductStateListID)
    case productNotFound(ProductStateProductID)
    case entryNotFound(ProductStateListEntryID)
    case lineNotFound(ProductStateSessionLineID)
    case transactionOutcomeUnknown
}

struct ProductStateSessionCommandSummary: Equatable, Sendable {
    let commandID: ProductStateCommandID
    let sessionID: ProductStateSessionID
    let sourceListID: ProductStateListID?
    let sourceRevision: ShoppingSessionSourceRevision
    let sourcePlanID: ProductStatePlanID?
    let sourcePlanFingerprint: String?
    let snapshotID: ProductStateSessionSnapshotID
    let snapshotContentSignature: String
    let lifecycle: ShoppingSessionLifecycle
    let revisionBefore: ProductStateSessionRevision
    let revisionAfter: ProductStateSessionRevision
    let lineIDs: [ProductStateSessionLineID]
    let stopIDs: [ProductStateSessionStopID]
    let historyEventIDs: [ProductStateHistoryEventID]
    let affectedListRevision: ProductStateAffectedListRevision?
    let receipt: ProductStateCommandReceipt
}

struct ProductStateSessionStateValue: Equatable, Sendable {
    let sessionID: ProductStateSessionID
    let sourceListID: ProductStateListID?
    let sourceRevision: ShoppingSessionSourceRevision
    let sourcePlanID: ProductStatePlanID?
    let sourcePlanFingerprint: String?
    let snapshotID: ProductStateSessionSnapshotID
    let lifecycle: ShoppingSessionLifecycle
    let migrationCondition: ShoppingSessionMigrationCondition
    let revision: ProductStateSessionRevision
    let lineIDs: [ProductStateSessionLineID]
    let stopIDs: [ProductStateSessionStopID]
}

enum ProductStateSessionCommandOutcome: Equatable, Sendable {
    case started(ProductStateSessionCommandSummary, ProductStateSessionPlanFreshness)
    case lineCollected(ProductStateSessionCommandSummary, ProductStateSessionLineID)
    case lineCollectionUndone(ProductStateSessionCommandSummary, ProductStateSessionLineID)
    case stopActivityRecorded(
        ProductStateSessionCommandSummary,
        ProductStateSessionStopID,
        ProductStateSessionStopActivity
    )
    case finishReviewReady(ProductStateSessionStateValue, ProductStateSessionLineID)
    case expired(ProductStateSessionCommandSummary)
    case resumed(ProductStateSessionCommandSummary)
    case completed(ProductStateSessionCommandSummary)
    case cancelled(ProductStateSessionCommandSummary)
    case noOp(ProductStateSessionStateValue)
    case terminal(ProductStateSessionStateValue)
    case conflict(ProductStateSessionConflict)
    case invalid(ProductStateSessionInvalidReason)
    case unavailable(ProductStateSessionUnavailableReason)
}

struct ProductStateSessionCommandExecution: Equatable, Sendable {
    let outcome: ProductStateSessionCommandOutcome

    var claimsDurableSuccess: Bool {
        switch outcome {
        case .started, .lineCollected, .lineCollectionUndone,
             .stopActivityRecorded, .expired, .resumed, .completed, .cancelled:
            true
        case .finishReviewReady, .noOp, .terminal, .conflict, .invalid,
             .unavailable:
            false
        }
    }
}

// MARK: - Sole inactive target Session mutation authority

/// T-19 owns the normalized Shopping Session write boundary. It is deliberately
/// not composed into startup or any presentation consumer; T-21 owns runtime
/// activation. Every durable mutation is staged through the committed
/// repositories and completed by the one T-05 transaction coordinator.
@MainActor
final class ProductStateShoppingSessionCommandAuthority {
    typealias TransactionCommit = (
        ProductStatePreparedCommandResult
    ) -> ProductStateTransactionResult

    static let inactivityInterval: TimeInterval = 12 * 60 * 60
    static let maximumActivationInterval: TimeInterval = 72 * 60 * 60
    static let freshPlanInterval: TimeInterval = 24 * 60 * 60
    static let maximumPlanInterval: TimeInterval = 7 * 24 * 60 * 60

    private let repositories: ProductStateRepositories
    private let commitPrepared: TransactionCommit
    private let writeState: ProductStateSessionCommandWriteState
    private let shapeValidator = ProductStateCommandShapeValidator()

    init(
        repositories: ProductStateRepositories,
        transactionCoordinator: ProductStateTransactionCoordinator,
        writeState: ProductStateSessionCommandWriteState
    ) {
        self.repositories = repositories
        commitPrepared = { transactionCoordinator.commit($0) }
        self.writeState = writeState
    }

    init(
        repositories: ProductStateRepositories,
        writeState: ProductStateSessionCommandWriteState,
        commitPrepared: @escaping TransactionCommit
    ) {
        self.repositories = repositories
        self.writeState = writeState
        self.commitPrepared = commitPrepared
    }

    func start(
        _ input: ProductStateSessionStartInput
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        let shape = shapeValidator.validate(input.command)
        guard shape.isEmpty else {
            return execution(.invalid(.commandShape(shape)))
        }
        guard case let .startSession(command) = input.command.intent else {
            return execution(.invalid(.wrongCommand))
        }

        let validated: ValidatedStart
        do {
            switch try validateStart(input, command: command) {
            case let .success(value): validated = value
            case let .failure(outcome): return execution(outcome)
            }
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }

        let effect = ProductStateStagedEffect.sessionInserted(
            id: command.sessionID,
            revision: 1,
            snapshotID: input.snapshotID,
            snapshotContentSignature: validated.signature,
            lineIDs: validated.lines.map { ProductStateSessionLineID(rawValue: $0.id) },
            stopIDs: validated.stops.map { ProductStateSessionStopID(rawValue: $0.id) }
        )

        if validated.isRetry {
            return finishCommit(
                commandID: input.command.id,
                effects: [effect],
                success: { receipt in
                    .started(
                        self.summary(
                            commandID: input.command.id,
                            session: validated.session,
                            revisionBefore: 0,
                            receipt: receipt
                        ),
                        validated.freshness
                    )
                },
                retryConflict: .duplicateSessionIdentity(command.sessionID)
            )
        }

        repositories.sessions.stageInsertion(of: validated.session)
        return finishCommit(
            commandID: input.command.id,
            effects: [effect],
            success: { receipt in
                .started(
                    self.summary(
                        commandID: input.command.id,
                        session: validated.session,
                        revisionBefore: 0,
                        receipt: receipt
                    ),
                    validated.freshness
                )
            }
        )
    }

    func collect(
        _ command: ProductStateCommand
    ) -> ProductStateSessionCommandExecution {
        changeExecutionState(command, target: .collected)
    }

    func undoCollection(
        _ command: ProductStateCommand
    ) -> ProductStateSessionCommandExecution {
        changeExecutionState(command, target: .remaining)
    }

    func recordStopActivity(
        _ command: ProductStateSessionStopActivityCommand
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        guard valid(command.id.rawValue), valid(command.sessionID.rawValue),
              valid(command.stopID.rawValue),
              command.expectedRevision.value > 0,
              command.effectiveAt.timeIntervalSince1970.isFinite
        else { return execution(.invalid(.invalidIdentity)) }
        do {
            if let conflict = try multipleCandidateConflict() {
                return execution(conflict)
            }
            guard let session = try exactSession(command.sessionID) else {
                return execution(.unavailable(.sessionNotFound(command.sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            guard state.lifecycle == .active else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: [.active], actual: state.lifecycle
                    )))
            }
            guard allowsActiveMutation(session, state: state) else {
                return execution(.invalid(.invalidMigrationCondition))
            }
            guard try exactStop(command.stopID, in: session) != nil else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            let effect = ProductStateStagedEffect.sessionActivityRecorded(
                sessionID: command.sessionID,
                stopID: command.stopID,
                beforeRevision: command.expectedRevision.value,
                afterRevision: command.expectedRevision.value + 1,
                activityRawValue: command.activity.rawValue,
                lastActivityAt: command.effectiveAt
            )
            if state.revision.value == command.expectedRevision.value + 1,
               session.lastActivityAt == command.effectiveAt {
                return finishCommit(
                    commandID: command.id,
                    effects: [effect],
                    success: { receipt in
                        .stopActivityRecorded(
                            self.summary(
                                commandID: command.id,
                                session: session,
                                revisionBefore: command.expectedRevision.value,
                                receipt: receipt
                            ),
                            command.stopID,
                            command.activity
                        )
                    },
                    retryConflict: .staleSessionRevision(
                        expected: command.expectedRevision,
                        actual: state.revision
                    )
                )
            }
            guard state.revision == command.expectedRevision else {
                return execution(.conflict(.staleSessionRevision(
                    expected: command.expectedRevision,
                    actual: state.revision
                )))
            }
            guard command.effectiveAt >= session.lastActivityAt else {
                return execution(.invalid(.invalidTransitionTime))
            }
            if isExpirationDue(session, at: command.effectiveAt) {
                return execution(.conflict(.expirationRequired(state.revision)))
            }
            let before = session.revision
            session.revision = before + 1
            session.lastActivityAt = command.effectiveAt
            return finishCommit(
                commandID: command.id,
                effects: [effect],
                success: { receipt in
                    .stopActivityRecorded(
                        self.summary(
                            commandID: command.id,
                            session: session,
                            revisionBefore: before,
                            receipt: receipt
                        ),
                        command.stopID,
                        command.activity
                    )
                }
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }

    /// Outcome drafting is intentionally read-only. The authoritative outcomes
    /// are supplied together only by the confirmed Finish command.
    func prepareFinishOutcome(
        _ command: ProductStateCommand
    ) -> ProductStateSessionCommandExecution {
        let shape = shapeValidator.validate(command)
        guard shape.isEmpty else {
            return execution(.invalid(.commandShape(shape)))
        }
        guard case let .prepareFinishOutcome(value) = command.intent,
              let expected = expectedSessionRevision(command)
        else { return execution(.invalid(.wrongCommand)) }
        do {
            guard let session = try exactSession(value.sessionID) else {
                return execution(.unavailable(.sessionNotFound(value.sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            guard state.revision == expected else {
                return execution(.conflict(.staleSessionRevision(
                    expected: expected,
                    actual: state.revision
                )))
            }
            guard state.lifecycle == .active else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: [.active], actual: state.lifecycle
                    )))
            }
            guard finishListID(session, state: state) != nil else {
                return execution(.invalid(.invalidMigrationCondition))
            }
            guard try exactLine(value.lineID, in: session) != nil else {
                return execution(.unavailable(.lineNotFound(value.lineID)))
            }
            return execution(.finishReviewReady(state, value.lineID))
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }

    func expire(
        _ command: ProductStateExpireSessionCommand
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        guard valid(command.id.rawValue), valid(command.sessionID.rawValue),
              command.expectedRevision.value > 0,
              command.effectiveAt.timeIntervalSince1970.isFinite
        else { return execution(.invalid(.invalidIdentity)) }
        do {
            if let conflict = try multipleCandidateConflict() {
                return execution(conflict)
            }
            guard let session = try exactSession(command.sessionID) else {
                return execution(.unavailable(.sessionNotFound(command.sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            if state.lifecycle == .expired,
               state.revision.value == command.expectedRevision.value + 1 {
                let effect = ProductStateStagedEffect.sessionLifecycleChanged(
                    id: command.sessionID,
                    beforeRevision: command.expectedRevision.value,
                    afterRevision: state.revision.value,
                    beforeLifecycle: .active,
                    afterLifecycle: .expired,
                    transitionedAt: command.effectiveAt
                )
                return finishCommit(
                    commandID: command.id,
                    effects: [effect],
                    success: { receipt in
                        .expired(self.summary(
                            commandID: command.id,
                            session: session,
                            revisionBefore: command.expectedRevision.value,
                            receipt: receipt
                        ))
                    },
                    retryConflict: .staleSessionRevision(
                        expected: command.expectedRevision,
                        actual: state.revision
                    )
                )
            }
            guard state.revision == command.expectedRevision else {
                return execution(.conflict(.staleSessionRevision(
                    expected: command.expectedRevision,
                    actual: state.revision
                )))
            }
            guard state.lifecycle == .active else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: [.active], actual: state.lifecycle
                    )))
            }
            guard let boundary = expirationBoundary(session),
                  command.effectiveAt >= boundary.date
            else { return execution(.invalid(.expirationNotDue)) }

            let before = session.revision
            session.lifecycleRawValue = ShoppingSessionLifecycle.expired.rawValue
            session.revision = before + 1
            session.expiredAt = command.effectiveAt
            session.expirationReasonRawValue = boundary.reason
            let effect = ProductStateStagedEffect.sessionLifecycleChanged(
                id: command.sessionID,
                beforeRevision: before,
                afterRevision: before + 1,
                beforeLifecycle: .active,
                afterLifecycle: .expired,
                transitionedAt: command.effectiveAt
            )
            return finishCommit(
                commandID: command.id,
                effects: [effect],
                success: { receipt in
                    .expired(self.summary(
                        commandID: command.id,
                        session: session,
                        revisionBefore: before,
                        receipt: receipt
                    ))
                }
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }

    func resume(
        _ command: ProductStateCommand
    ) -> ProductStateSessionCommandExecution {
        lifecycleCommand(
            command,
            operation: .resume,
            allowed: [.expired],
            target: .active
        )
    }

    func abandon(
        _ command: ProductStateCommand
    ) -> ProductStateSessionCommandExecution {
        lifecycleCommand(
            command,
            operation: .abandon,
            allowed: [.active, .expired],
            target: .abandoned
        )
    }

    func finish(
        _ input: ProductStateSessionFinishInput
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        let shape = shapeValidator.validate(input.command)
        guard shape.isEmpty else {
            return execution(.invalid(.commandShape(shape)))
        }
        guard case let .finishSession(command) = input.command.intent,
              let expected = expectedSessionRevision(input.command)
        else { return execution(.invalid(.wrongCommand)) }

        do {
            if let conflict = try multipleCandidateConflict() {
                return execution(conflict)
            }
            guard let session = try exactSession(command.sessionID) else {
                return execution(.unavailable(.sessionNotFound(command.sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }

            if state.lifecycle == .finished,
               state.revision.value == expected.value + 1 {
                return retryFinish(
                    input,
                    command: command,
                    session: session,
                    state: state,
                    expected: expected
                )
            }
            guard state.revision == expected else {
                return execution(.conflict(.staleSessionRevision(
                    expected: expected,
                    actual: state.revision
                )))
            }
            guard state.lifecycle == .active else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: [.active], actual: state.lifecycle
                    )))
            }
            guard input.command.effectiveAt >= session.lastActivityAt else {
                return execution(.invalid(.invalidTransitionTime))
            }
            if isExpirationDue(session, at: input.command.effectiveAt) {
                return execution(.conflict(.expirationRequired(state.revision)))
            }
            guard let listID = finishListID(session, state: state) else {
                return execution(.invalid(.invalidMigrationCondition))
            }
            guard let list = try exactList(listID) else {
                return execution(.unavailable(.listNotFound(listID)))
            }
            guard list.revision == input.expectedListRevision.value else {
                return execution(.conflict(.staleListRevision(
                    expected: input.expectedListRevision,
                    actual: ProductStateListRevision(value: list.revision)
                )))
            }

            let validated: ValidatedFinish
            switch try validateFinish(
                command,
                session: session,
                list: list
            ) {
            case let .success(value): validated = value
            case let .failure(outcome): return execution(outcome)
            }

            let beforeSession = session.revision
            let beforeList = list.revision
            let afterSession = beforeSession + 1
            let afterList = beforeList + 1
            for item in validated.lines {
                item.line.finalOutcomeRawValue = item.outcome.rawValue
                item.line.finalOutcomeAt = input.command.effectiveAt
                item.line.finalOutcomeCommandID = input.command.id.rawValue
            }
            for item in validated.resolutions {
                item.entry.lifecycleRawValue = "resolved"
                item.entry.resolutionReasonRawValue = item.reason.rawValue
                item.entry.resolutionEffectiveAt = input.command.effectiveAt
                item.entry.resolutionProvenanceRawValue = "sessionFinish"
                item.entry.resolutionCommandID = input.command.id.rawValue
                item.entry.resolutionSessionID = session.id
                item.entry.resolutionSessionLineID = item.lineID.rawValue
                item.entry.updatedAt = input.command.effectiveAt
            }
            list.revision = afterList
            list.updatedAt = input.command.effectiveAt
            session.lifecycleRawValue = ShoppingSessionLifecycle.finished.rawValue
            session.revision = afterSession
            session.endedAt = input.command.effectiveAt

            let events = validated.lines.map { item in
                historyEvent(
                    commandID: input.command.id,
                    session: session,
                    line: item.line,
                    outcome: item.outcome,
                    occurredAt: input.command.effectiveAt
                )
            }
            events.forEach { repositories.history.stageInsertion(of: $0) }
            let finishEffect = ProductStateStagedEffect.sessionFinished(
                id: command.sessionID,
                beforeRevision: beforeSession,
                afterRevision: afterSession,
                listID: listID,
                listBeforeRevision: beforeList,
                listAfterRevision: afterList,
                lineOutcomes: validated.lines.map {
                    ProductStateSessionLineOutcomeEffect(
                        lineID: ProductStateSessionLineID(rawValue: $0.line.id),
                        outcome: $0.outcome
                    )
                },
                resolvedEntries: validated.resolutions.map {
                    ProductStateSessionEntryResolutionEffect(
                        identity: $0.identity,
                        reason: $0.reason
                    )
                },
                finishedAt: input.command.effectiveAt
            )
            let effects = [finishEffect] + events.map {
                ProductStateStagedEffect.historyEventInserted(
                    ProductStateHistoryEventID(rawValue: $0.id)
                )
            }
            return finishCommit(
                commandID: input.command.id,
                effects: effects,
                success: { receipt in
                    .completed(self.summary(
                        commandID: input.command.id,
                        session: session,
                        revisionBefore: beforeSession,
                        receipt: receipt,
                        affectedListRevision: ProductStateAffectedListRevision(
                            listID: listID,
                            before: ProductStateListRevision(value: beforeList),
                            after: ProductStateListRevision(value: afterList)
                        )
                    ))
                }
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }
}

// MARK: - Validation and mutation helpers

private extension ProductStateShoppingSessionCommandAuthority {
    enum Validation<Value> {
        case success(Value)
        case failure(ProductStateSessionCommandOutcome)
    }

    struct ValidatedStart {
        let session: WayTaskSchemaV4.ShoppingSession
        let lines: [WayTaskSchemaV4.ShoppingSessionLine]
        let stops: [WayTaskSchemaV4.ShoppingSessionStop]
        let signature: String
        let freshness: ProductStateSessionPlanFreshness
        let isRetry: Bool
    }

    struct ValidatedFinishLine {
        let line: WayTaskSchemaV4.ShoppingSessionLine
        let outcome: ShoppingSessionFinalOutcome
    }

    struct ValidatedResolution {
        let entry: WayTaskSchemaV4.ShoppingListEntry
        let identity: ProductStateListEntryIdentity
        let lineID: ProductStateSessionLineID
        let reason: ShoppingListResolutionReason
    }

    struct ValidatedFinish {
        let lines: [ValidatedFinishLine]
        let resolutions: [ValidatedResolution]
    }

    struct ExactSource {
        let listID: ProductStateListID
        let revision: ProductStateListRevision
        let planID: ProductStatePlanID
        let planFingerprint: String
    }

    struct AuthoritySource {
        let listID: ProductStateListID?
        let revision: ShoppingSessionSourceRevision
        let planID: ProductStatePlanID?
        let planFingerprint: String?
    }

    enum LifecycleOperation {
        case resume
        case abandon
    }

    func validateStart(
        _ input: ProductStateSessionStartInput,
        command: StartSessionCommand
    ) throws -> Validation<ValidatedStart> {
        guard valid(input.snapshotID.rawValue),
              valid(input.plan.id.rawValue),
              !input.planFingerprint.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              input.planEvidenceAt.timeIntervalSince1970.isFinite
        else { return .failure(.invalid(.invalidIdentity)) }
        guard input.plan.sourceListID == command.listID,
              input.plan.sourceRevision == command.sourceRevision,
              input.plan.includedEntries == command.entries
        else { return .failure(.invalid(.planIdentityMismatch)) }
        guard input.plan.status == .ready else {
            return .failure(.invalid(.invalidPlan))
        }
        let age = input.command.effectiveAt.timeIntervalSince(
            input.planEvidenceAt
        )
        guard age >= 0 else {
            return .failure(.invalid(.planEvidenceInFuture))
        }
        guard age <= Self.maximumPlanInterval else {
            return .failure(.invalid(.planEvidenceExpired))
        }
        let freshness: ProductStateSessionPlanFreshness
        if age > Self.freshPlanInterval {
            guard input.confirmedStaleEvidenceAt == input.planEvidenceAt else {
                return .failure(.invalid(
                    .stalePlanConfirmationRequired(input.planEvidenceAt)
                ))
            }
            freshness = .staleConfirmed(evidenceAt: input.planEvidenceAt)
        } else {
            freshness = .fresh
        }

        let active = try repositories.sessions.shoppingSessions(lifecycle: .active)
        let expired = try repositories.sessions.shoppingSessions(lifecycle: .expired)
        let candidates = (active + expired).sorted(by: sessionLess)
        guard candidates.count <= 1 else {
            return .failure(.conflict(.nonTerminalSessions(
                candidates.map { ProductStateSessionID(rawValue: $0.id) }
            )))
        }
        if let existing = candidates.first {
            guard existing.id == command.sessionID.rawValue else {
                return .failure(.conflict(.nonTerminalSessions([
                    ProductStateSessionID(rawValue: existing.id)
                ])))
            }
            let existingLines = try repositories.sessions.sessionLines(
                sessionID: existing.id
            )
            let existingStops = try repositories.sessions.sessionStops(
                sessionID: existing.id
            )
            guard retryStartMatches(
                input,
                command: command,
                session: existing,
                lines: existingLines,
                stops: existingStops
            )
            else {
                return .failure(.conflict(
                    .duplicateSessionIdentity(command.sessionID)
                ))
            }
            return .success(ValidatedStart(
                session: existing,
                lines: existingLines.sorted(by: lineLess),
                stops: existingStops.sorted(by: stopLess),
                signature: existing.snapshotContentSignature,
                freshness: freshness,
                isRetry: true
            ))
        }

        let sameID = try repositories.sessions.shoppingSessions(
            id: command.sessionID.rawValue
        )
        guard sameID.isEmpty else {
            return .failure(.conflict(.duplicateSessionIdentity(command.sessionID)))
        }
        guard let list = try exactList(command.listID) else {
            return .failure(.unavailable(.listNotFound(command.listID)))
        }
        guard list.revision == command.sourceRevision.value else {
            return .failure(.conflict(.staleListRevision(
                expected: command.sourceRevision,
                actual: ProductStateListRevision(value: list.revision)
            )))
        }
        let built = try buildSnapshot(input, command: command, list: list)
        guard case let .success(snapshot) = built else {
            if case let .failure(outcome) = built { return .failure(outcome) }
            return .failure(.invalid(.invalidSnapshot))
        }
        return .success(ValidatedStart(
            session: snapshot.session,
            lines: snapshot.lines,
            stops: snapshot.stops,
            signature: snapshot.signature,
            freshness: freshness,
            isRetry: false
        ))
    }

    func retryStartMatches(
        _ input: ProductStateSessionStartInput,
        command: StartSessionCommand,
        session: WayTaskSchemaV4.ShoppingSession,
        lines: [WayTaskSchemaV4.ShoppingSessionLine],
        stops: [WayTaskSchemaV4.ShoppingSessionStop]
    ) -> Bool {
        let orderedLines = lines.sorted(by: lineLess)
        let orderedStops = stops.sorted(by: stopLess)
        let inputLines = input.lines.sorted(by: lineInputLess)
        let inputStops = input.stops.sorted(by: stopInputLess)
        guard session.revision == 1,
              session.lifecycleRawValue == ShoppingSessionLifecycle.active.rawValue,
              session.migrationConditionRawValue
                == ShoppingSessionMigrationCondition.native.rawValue,
              session.sourceListID == command.listID.rawValue,
              session.sourceRevision == command.sourceRevision.value,
              session.sourceRevisionProvenanceRawValue == "exact",
              session.sourcePlanID == input.plan.id.rawValue,
              session.sourcePlanSignature == input.planFingerprint,
              session.sourcePlanEvidenceAt == input.planEvidenceAt,
              session.snapshotID == input.snapshotID.rawValue,
              session.snapshotVersion == 1,
              session.snapshotGeneration == 1,
              session.startedAt == input.command.effectiveAt,
              orderedLines.count == inputLines.count,
              orderedStops.count == inputStops.count
        else { return false }

        let linesMatch = zip(orderedLines, inputLines).allSatisfy { stored, value in
            stored.id == value.id.rawValue
                && stored.sessionID == command.sessionID.rawValue
                && stored.snapshotID == input.snapshotID.rawValue
                && stored.sourceListID == value.sourceEntry.listID.rawValue
                && stored.sourceEntryID == value.sourceEntry.id.rawValue
                && stored.productID == value.sourceEntry.productID.rawValue
                && stored.stopID == value.stopID.rawValue
                && stored.sortOrder == value.sortOrder
                && stored.globalProductConceptIDRawValue
                    == value.globalProductConceptIDRawValue
        }
        let stopsMatch = zip(orderedStops, inputStops).allSatisfy { stored, value in
            stored.id == value.id.rawValue
                && stored.sessionID == command.sessionID.rawValue
                && stored.snapshotID == input.snapshotID.rawValue
                && stored.sortOrder == value.sortOrder
                && stored.storeReferenceIDRawValue == value.storeReferenceIDRawValue
                && stored.storeReferenceProvenanceRawValue
                    == value.storeReferenceProvenanceRawValue
                && stored.displayNameSnapshot == value.displayNameSnapshot
                && stored.latitudeSnapshot == value.latitude
                && stored.longitudeSnapshot == value.longitude
                && stored.evidenceAt == value.evidenceAt
                && stored.isSessionScopedTransient
                    == value.isSessionScopedTransient
        }
        let expectedSignature = snapshotSignature(
            command: command,
            snapshotID: input.snapshotID,
            plan: input.plan,
            fingerprint: input.planFingerprint,
            evidenceAt: input.planEvidenceAt,
            stops: orderedStops,
            lines: orderedLines
        )
        return linesMatch && stopsMatch
            && session.snapshotContentSignature == expectedSignature
    }

    typealias BuiltSnapshot = (
        session: WayTaskSchemaV4.ShoppingSession,
        lines: [WayTaskSchemaV4.ShoppingSessionLine],
        stops: [WayTaskSchemaV4.ShoppingSessionStop],
        signature: String
    )

    func buildSnapshot(
        _ input: ProductStateSessionStartInput,
        command: StartSessionCommand,
        list: WayTaskSchemaV4.ShoppingList
    ) throws -> Validation<BuiltSnapshot> {
        let orderedStops = input.stops.sorted(by: stopInputLess)
        guard !orderedStops.isEmpty,
              Set(orderedStops.map(\.id)).count == orderedStops.count,
              Set(orderedStops.map(\.sortOrder)).count == orderedStops.count,
              orderedStops.allSatisfy(validStop),
              orderedStops.allSatisfy({
                  $0.evidenceAt <= input.command.effectiveAt
              })
        else { return .failure(.invalid(.invalidStops)) }
        let orderedLines = input.lines.sorted(by: lineInputLess)
        guard !orderedLines.isEmpty,
              orderedLines.count == command.entries.count,
              Set(orderedLines.map(\.id)).count == orderedLines.count,
              Set(orderedLines.map(\.sortOrder)).count == orderedLines.count,
              orderedLines.map(\.sourceEntry) == command.entries,
              orderedLines.allSatisfy({
                  Set(orderedStops.map(\.id)).contains($0.stopID)
              })
        else { return .failure(.invalid(.invalidLineAssignments)) }

        let stopModels = orderedStops.map { stop in
            WayTaskSchemaV4.ShoppingSessionStop(
                id: stop.id.rawValue,
                sessionID: command.sessionID.rawValue,
                snapshotID: input.snapshotID.rawValue,
                sortOrder: stop.sortOrder,
                storeReferenceIDRawValue: stop.storeReferenceIDRawValue,
                storeReferenceProvenanceRawValue:
                    stop.storeReferenceProvenanceRawValue,
                displayNameSnapshot: stop.displayNameSnapshot,
                latitudeSnapshot: stop.latitude,
                longitudeSnapshot: stop.longitude,
                evidenceAt: stop.evidenceAt,
                isSessionScopedTransient: stop.isSessionScopedTransient
            )
        }
        let stopByID = Dictionary(uniqueKeysWithValues: stopModels.map {
            ($0.id, $0)
        })
        var validatedLines: [(
            input: ProductStateSessionLineInput,
            entry: WayTaskSchemaV4.ShoppingListEntry,
            product: WayTaskSchemaV4.Product,
            stop: WayTaskSchemaV4.ShoppingSessionStop
        )] = []
        for line in orderedLines {
            let entryRows = try repositories.shopping.shoppingEntries(
                id: line.sourceEntry.id.rawValue,
                listID: command.listID.rawValue
            ).filter { $0.productID == line.sourceEntry.productID.rawValue }
            guard entryRows.count == 1, let entry = entryRows.first else {
                return .failure(.unavailable(.entryNotFound(line.sourceEntry.id)))
            }
            guard entry.lifecycleRawValue == "needed",
                  entry.shoppingListID == command.listID.rawValue,
                  entry.productID == line.sourceEntry.productID.rawValue
            else { return .failure(.invalid(.invalidSourceEntries)) }
            let products = try repositories.products.products(
                id: line.sourceEntry.productID.rawValue
            )
            guard products.count == 1, let product = products.first else {
                return .failure(.unavailable(
                    .productNotFound(line.sourceEntry.productID)
                ))
            }
            guard product.libraryLifecycleRawValue
                    == ProductLibraryLifecycle.active.rawValue,
                  let stop = stopByID[line.stopID.rawValue]
            else { return .failure(.invalid(.invalidSourceEntries)) }
            validatedLines.append((line, entry, product, stop))
        }
        let lineModels = validatedLines.map { value in
            WayTaskSchemaV4.ShoppingSessionLine(
                id: value.input.id.rawValue,
                sessionID: command.sessionID.rawValue,
                snapshotID: input.snapshotID.rawValue,
                snapshotVersion: 1,
                snapshotProvenanceRawValue: "nativeStart",
                sourceListID: command.listID.rawValue,
                sourceEntryID: value.entry.id,
                productID: value.product.id,
                globalProductConceptIDRawValue:
                    value.input.globalProductConceptIDRawValue,
                stopID: value.stop.id,
                sortOrder: value.input.sortOrder,
                productNameSnapshot: value.product.name,
                productBrandSnapshot: value.product.brand,
                productCategorySnapshot: value.product.category,
                quantitySnapshot: value.entry.quantity,
                unitSnapshotRawValue: value.entry.unitRawValue,
                noteSnapshot: value.entry.note,
                executionStateRawValue:
                    ShoppingSessionExecutionState.remaining.rawValue,
                sourceEntry: value.entry,
                product: value.product,
                stop: value.stop
            )
        }
        let signature = snapshotSignature(
            command: command,
            snapshotID: input.snapshotID,
            plan: input.plan,
            fingerprint: input.planFingerprint,
            evidenceAt: input.planEvidenceAt,
            stops: stopModels,
            lines: lineModels
        )
        let session = WayTaskSchemaV4.ShoppingSession(
            id: command.sessionID.rawValue,
            sourceListID: command.listID.rawValue,
            sourceRevision: command.sourceRevision.value,
            sourceRevisionProvenanceRawValue: "exact",
            revision: 1,
            lifecycleRawValue: ShoppingSessionLifecycle.active.rawValue,
            migrationConditionRawValue:
                ShoppingSessionMigrationCondition.native.rawValue,
            snapshotID: input.snapshotID.rawValue,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: signature,
            sourcePlanID: input.plan.id.rawValue,
            sourcePlanSignature: input.planFingerprint,
            sourcePlanEvidenceAt: input.planEvidenceAt,
            startedAt: input.command.effectiveAt,
            activationStartedAt: input.command.effectiveAt,
            lastActivityAt: input.command.effectiveAt,
            expirationPolicyVersion: 1,
            sourceList: list,
            lines: lineModels,
            stops: stopModels
        )
        return .success((session, lineModels, stopModels, signature))
    }

    func changeExecutionState(
        _ command: ProductStateCommand,
        target: ShoppingSessionExecutionState
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        let shape = shapeValidator.validate(command)
        guard shape.isEmpty else {
            return execution(.invalid(.commandShape(shape)))
        }
        let value: SessionLineCommand
        switch target {
        case .collected:
            guard case let .markLineCollected(input) = command.intent else {
                return execution(.invalid(.wrongCommand))
            }
            value = input
        case .remaining:
            guard case let .undoLineCollection(input) = command.intent else {
                return execution(.invalid(.wrongCommand))
            }
            value = input
        }
        guard let expected = expectedSessionRevision(command) else {
            return execution(.invalid(.wrongCommand))
        }
        do {
            if let conflict = try multipleCandidateConflict() {
                return execution(conflict)
            }
            guard let session = try exactSession(value.sessionID) else {
                return execution(.unavailable(.sessionNotFound(value.sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            guard state.lifecycle == .active else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: [.active], actual: state.lifecycle
                    )))
            }
            guard allowsActiveMutation(session, state: state) else {
                return execution(.invalid(.invalidMigrationCondition))
            }
            guard command.effectiveAt >= session.lastActivityAt else {
                return execution(.invalid(.invalidTransitionTime))
            }
            if isExpirationDue(session, at: command.effectiveAt) {
                return execution(.conflict(.expirationRequired(state.revision)))
            }
            guard let line = try exactLine(value.lineID, in: session) else {
                return execution(.unavailable(.lineNotFound(value.lineID)))
            }
            let current = ShoppingSessionExecutionState(
                rawValue: line.executionStateRawValue
            )
            guard let current else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            if state.revision.value == expected.value + 1, current == target {
                let effect = ProductStateStagedEffect.sessionLineExecutionChanged(
                    sessionID: value.sessionID,
                    lineID: value.lineID,
                    beforeRevision: expected.value,
                    afterRevision: state.revision.value,
                    executionState: target,
                    executionChangedAt: command.effectiveAt
                )
                return finishCommit(
                    commandID: command.id,
                    effects: [effect],
                    success: { receipt in
                        let summary = self.summary(
                            commandID: command.id,
                            session: session,
                            revisionBefore: expected.value,
                            receipt: receipt
                        )
                        return target == .collected
                            ? .lineCollected(summary, value.lineID)
                            : .lineCollectionUndone(summary, value.lineID)
                    },
                    retryConflict: .staleSessionRevision(
                        expected: expected, actual: state.revision
                    )
                )
            }
            guard state.revision == expected else {
                return execution(.conflict(.staleSessionRevision(
                    expected: expected, actual: state.revision
                )))
            }
            if current == target { return execution(.noOp(state)) }

            let before = session.revision
            line.executionStateRawValue = target.rawValue
            line.executionChangedAt = command.effectiveAt
            session.revision = before + 1
            session.lastActivityAt = command.effectiveAt
            let effect = ProductStateStagedEffect.sessionLineExecutionChanged(
                sessionID: value.sessionID,
                lineID: value.lineID,
                beforeRevision: before,
                afterRevision: before + 1,
                executionState: target,
                executionChangedAt: command.effectiveAt
            )
            return finishCommit(
                commandID: command.id,
                effects: [effect],
                success: { receipt in
                    let summary = self.summary(
                        commandID: command.id,
                        session: session,
                        revisionBefore: before,
                        receipt: receipt
                    )
                    return target == .collected
                        ? .lineCollected(summary, value.lineID)
                        : .lineCollectionUndone(summary, value.lineID)
                }
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }

    func lifecycleCommand(
        _ command: ProductStateCommand,
        operation: LifecycleOperation,
        allowed: [ShoppingSessionLifecycle],
        target: ShoppingSessionLifecycle
    ) -> ProductStateSessionCommandExecution {
        if let blocked = blockedExecution() { return blocked }
        let shape = shapeValidator.validate(command)
        guard shape.isEmpty else {
            return execution(.invalid(.commandShape(shape)))
        }
        let sessionID: ProductStateSessionID
        switch (command.intent, operation) {
        case let (.resumeSession(value), .resume): sessionID = value.sessionID
        case let (.abandonSession(value), .abandon): sessionID = value.sessionID
        default: return execution(.invalid(.wrongCommand))
        }
        guard let expected = expectedSessionRevision(command) else {
            return execution(.invalid(.wrongCommand))
        }
        do {
            if operation == .resume,
               let conflict = try multipleCandidateConflict() {
                return execution(conflict)
            }
            guard let session = try exactSession(sessionID) else {
                return execution(.unavailable(.sessionNotFound(sessionID)))
            }
            guard let state = stateValue(session) else {
                return execution(.invalid(.invalidSessionAuthority))
            }
            if state.lifecycle == target,
               state.revision.value == expected.value + 1 {
                let beforeLifecycle: ShoppingSessionLifecycle =
                    operation == .resume
                        ? .expired
                        : (session.expiredAt == nil ? .active : .expired)
                let effect = ProductStateStagedEffect.sessionLifecycleChanged(
                    id: sessionID,
                    beforeRevision: expected.value,
                    afterRevision: state.revision.value,
                    beforeLifecycle: beforeLifecycle,
                    afterLifecycle: target,
                    transitionedAt: command.effectiveAt
                )
                return finishCommit(
                    commandID: command.id,
                    effects: [effect],
                    success: { receipt in
                        let value = self.summary(
                            commandID: command.id,
                            session: session,
                            revisionBefore: expected.value,
                            receipt: receipt
                        )
                        return operation == .resume
                            ? .resumed(value) : .cancelled(value)
                    },
                    retryConflict: .staleSessionRevision(
                        expected: expected, actual: state.revision
                    )
                )
            }
            guard state.revision == expected else {
                return execution(.conflict(.staleSessionRevision(
                    expected: expected, actual: state.revision
                )))
            }
            guard allowed.contains(state.lifecycle) else {
                return state.lifecycle.isTerminal
                    ? execution(.terminal(state))
                    : execution(.conflict(.wrongLifecycle(
                        expected: allowed, actual: state.lifecycle
                    )))
            }
            if operation == .resume {
                let minimumResumeTime = session.expiredAt
                    ?? session.lastActivityAt
                guard command.effectiveAt >= minimumResumeTime else {
                    return execution(.invalid(.invalidTransitionTime))
                }
                if state.migrationCondition == .native
                    || state.migrationCondition == .legacyMapped {
                    guard let listID = state.sourceListID else {
                        return execution(.invalid(.invalidSessionAuthority))
                    }
                    guard let list = try exactList(listID) else {
                        return execution(.unavailable(.listNotFound(listID)))
                    }
                    if let invalid = try protectedEntryFailure(
                        session: session,
                        list: list
                    ) {
                        return execution(invalid)
                    }
                }
            } else {
                let minimumAbandonTime = max(
                    session.lastActivityAt,
                    session.expiredAt ?? session.lastActivityAt
                )
                guard command.effectiveAt >= minimumAbandonTime else {
                    return execution(.invalid(.invalidTransitionTime))
                }
            }

            let before = session.revision
            let previous = state.lifecycle
            session.lifecycleRawValue = target.rawValue
            session.revision = before + 1
            if operation == .resume {
                session.activationStartedAt = command.effectiveAt
                session.lastActivityAt = command.effectiveAt
                session.expiredAt = nil
                session.expirationReasonRawValue = nil
                session.endedAt = nil
            } else {
                session.endedAt = command.effectiveAt
            }
            let effect = ProductStateStagedEffect.sessionLifecycleChanged(
                id: sessionID,
                beforeRevision: before,
                afterRevision: before + 1,
                beforeLifecycle: previous,
                afterLifecycle: target,
                transitionedAt: command.effectiveAt
            )
            return finishCommit(
                commandID: command.id,
                effects: [effect],
                success: { receipt in
                    let value = self.summary(
                        commandID: command.id,
                        session: session,
                        revisionBefore: before,
                        receipt: receipt
                    )
                    return operation == .resume
                        ? .resumed(value) : .cancelled(value)
                }
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }

    func validateFinish(
        _ command: FinishSessionCommand,
        session: WayTaskSchemaV4.ShoppingSession,
        list: WayTaskSchemaV4.ShoppingList
    ) throws -> Validation<ValidatedFinish> {
        let lines = try repositories.sessions.sessionLines(sessionID: session.id)
            .sorted(by: lineLess)
        guard !lines.isEmpty,
              lines.count == command.outcomes.count,
              Set(lines.map(\.id)).count == lines.count,
              Set(command.outcomes.map(\.lineID)).count == command.outcomes.count,
              Set(lines.map(\.id)) == Set(command.outcomes.map(\.lineID.rawValue)),
              lines.allSatisfy({
                  $0.snapshotID == session.snapshotID
                      && $0.sourceListID == list.id
                      && $0.sourceEntryID != nil
                      && $0.productID != nil
                      && $0.legacyDispositionRawValue == nil
                      && $0.finalOutcomeRawValue == nil
                      && $0.finalOutcomeCommandID == nil
              })
        else { return .failure(.invalid(.invalidFinishOutcomes)) }
        let outcomes = Dictionary(uniqueKeysWithValues: command.outcomes.map {
            ($0.lineID.rawValue, $0.outcome)
        })
        var validatedLines: [ValidatedFinishLine] = []
        var resolutions: [ValidatedResolution] = []
        for line in lines {
            guard let outcome = outcomes[line.id],
                  let entryID = line.sourceEntryID,
                  let productID = line.productID
            else { return .failure(.invalid(.invalidFinishOutcomes)) }
            let entries = try repositories.shopping.shoppingEntries(
                id: entryID,
                listID: list.id
            ).filter { $0.productID == productID }
            guard entries.count == 1, let entry = entries.first else {
                return .failure(.unavailable(.entryNotFound(
                    ProductStateListEntryID(rawValue: entryID)
                )))
            }
            guard entry.lifecycleRawValue == "needed" else {
                return .failure(.conflict(.sourceEntryChanged(
                    ProductStateListEntryID(rawValue: entryID)
                )))
            }
            let products = try repositories.products.products(id: productID)
            guard products.count == 1,
                  products[0].libraryLifecycleRawValue
                    == ProductLibraryLifecycle.active.rawValue
            else { return .failure(.unavailable(.productNotFound(
                ProductStateProductID(rawValue: productID)
            ))) }
            validatedLines.append(ValidatedFinishLine(
                line: line, outcome: outcome
            ))
            if let reason = resolutionReason(outcome) {
                resolutions.append(ValidatedResolution(
                    entry: entry,
                    identity: ProductStateListEntryIdentity(
                        id: ProductStateListEntryID(rawValue: entryID),
                        listID: ProductStateListID(rawValue: list.id),
                        productID: ProductStateProductID(rawValue: productID)
                    ),
                    lineID: ProductStateSessionLineID(rawValue: line.id),
                    reason: reason
                ))
            }
        }
        return .success(ValidatedFinish(
            lines: validatedLines,
            resolutions: resolutions
        ))
    }

    func protectedEntryFailure(
        session: WayTaskSchemaV4.ShoppingSession,
        list: WayTaskSchemaV4.ShoppingList
    ) throws -> ProductStateSessionCommandOutcome? {
        let lines = try repositories.sessions.sessionLines(sessionID: session.id)
        for line in lines.sorted(by: lineLess) {
            guard let entryID = line.sourceEntryID,
                  let productID = line.productID,
                  line.sourceListID == list.id
            else { return .invalid(.invalidSessionAuthority) }
            let entries = try repositories.shopping.shoppingEntries(
                id: entryID,
                listID: list.id
            ).filter { $0.productID == productID }
            guard entries.count == 1, let entry = entries.first else {
                return .unavailable(.entryNotFound(
                    ProductStateListEntryID(rawValue: entryID)
                ))
            }
            guard entry.lifecycleRawValue == "needed" else {
                return .conflict(.sourceEntryChanged(
                    ProductStateListEntryID(rawValue: entryID)
                ))
            }
            let products = try repositories.products.products(id: productID)
            guard products.count == 1,
                  products[0].libraryLifecycleRawValue
                    == ProductLibraryLifecycle.active.rawValue
            else {
                return .unavailable(.productNotFound(
                    ProductStateProductID(rawValue: productID)
                ))
            }
        }
        return nil
    }

    func retryFinish(
        _ input: ProductStateSessionFinishInput,
        command: FinishSessionCommand,
        session: WayTaskSchemaV4.ShoppingSession,
        state: ProductStateSessionStateValue,
        expected: ProductStateSessionRevision
    ) -> ProductStateSessionCommandExecution {
        do {
            guard let listID = finishListID(session, state: state),
                  let list = try exactList(listID),
                  list.revision == input.expectedListRevision.value + 1
            else {
                return execution(.terminal(state))
            }
            let lines = try repositories.sessions.sessionLines(sessionID: session.id)
                .sorted(by: lineLess)
            let outcomes = Dictionary(uniqueKeysWithValues: command.outcomes.map {
                ($0.lineID.rawValue, $0.outcome)
            })
            guard lines.count == command.outcomes.count,
                  lines.allSatisfy({ line in
                      line.finalOutcomeRawValue == outcomes[line.id]?.rawValue
                          && line.finalOutcomeCommandID == input.command.id.rawValue
                  })
            else { return execution(.terminal(state)) }
            var resolved: [ProductStateSessionEntryResolutionEffect] = []
            for line in lines {
                guard let outcome = outcomes[line.id],
                      let entryID = line.sourceEntryID,
                      let productID = line.productID
                else { return execution(.terminal(state)) }
                if let reason = resolutionReason(outcome) {
                    resolved.append(ProductStateSessionEntryResolutionEffect(
                        identity: ProductStateListEntryIdentity(
                            id: ProductStateListEntryID(rawValue: entryID),
                            listID: listID,
                            productID: ProductStateProductID(rawValue: productID)
                        ),
                        reason: reason
                    ))
                }
            }
            let historyIDs = lines.map {
                ProductStateHistoryEventID(rawValue: historyEventUUID(
                    commandID: input.command.id,
                    sessionID: command.sessionID,
                    lineID: ProductStateSessionLineID(rawValue: $0.id),
                    outcome: outcomes[$0.id]!
                ))
            }
            let effect = ProductStateStagedEffect.sessionFinished(
                id: command.sessionID,
                beforeRevision: expected.value,
                afterRevision: state.revision.value,
                listID: listID,
                listBeforeRevision: input.expectedListRevision.value,
                listAfterRevision: list.revision,
                lineOutcomes: lines.map {
                    ProductStateSessionLineOutcomeEffect(
                        lineID: ProductStateSessionLineID(rawValue: $0.id),
                        outcome: outcomes[$0.id]!
                    )
                },
                resolvedEntries: resolved,
                finishedAt: input.command.effectiveAt
            )
            return finishCommit(
                commandID: input.command.id,
                effects: [effect] + historyIDs.map {
                    ProductStateStagedEffect.historyEventInserted($0)
                },
                success: { receipt in
                    .completed(self.summary(
                        commandID: input.command.id,
                        session: session,
                        revisionBefore: expected.value,
                        receipt: receipt,
                        affectedListRevision: ProductStateAffectedListRevision(
                            listID: listID,
                            before: input.expectedListRevision,
                            after: ProductStateListRevision(value: list.revision)
                        )
                    ))
                },
                retryConflict: .transactionConflict
            )
        } catch {
            return execution(.unavailable(.repositoryReadFailed))
        }
    }
}

// MARK: - Exact persistence mapping and deterministic evidence

private extension ProductStateShoppingSessionCommandAuthority {
    func exactSession(
        _ id: ProductStateSessionID
    ) throws -> WayTaskSchemaV4.ShoppingSession? {
        let rows = try repositories.sessions.shoppingSessions(id: id.rawValue)
        guard rows.count <= 1 else { return nil }
        return rows.first
    }

    func exactList(
        _ id: ProductStateListID
    ) throws -> WayTaskSchemaV4.ShoppingList? {
        let rows = try repositories.shopping.shoppingLists(id: id.rawValue)
        guard rows.count <= 1 else { return nil }
        return rows.first
    }

    func exactLine(
        _ id: ProductStateSessionLineID,
        in session: WayTaskSchemaV4.ShoppingSession
    ) throws -> WayTaskSchemaV4.ShoppingSessionLine? {
        let rows = try repositories.sessions.sessionLines(sessionID: session.id)
            .filter { $0.id == id.rawValue }
        guard rows.count <= 1 else { return nil }
        return rows.first
    }

    func exactStop(
        _ id: ProductStateSessionStopID,
        in session: WayTaskSchemaV4.ShoppingSession
    ) throws -> WayTaskSchemaV4.ShoppingSessionStop? {
        let rows = try repositories.sessions.sessionStops(sessionID: session.id)
            .filter { $0.id == id.rawValue }
        guard rows.count <= 1 else { return nil }
        return rows.first
    }

    func exactSource(
        _ session: WayTaskSchemaV4.ShoppingSession
    ) -> ExactSource? {
        guard session.sourceRevisionProvenanceRawValue == "exact",
              let listID = session.sourceListID,
              let revision = session.sourceRevision,
              revision > 0,
              let planID = session.sourcePlanID,
              let fingerprint = session.sourcePlanSignature,
              !fingerprint.isEmpty
        else { return nil }
        return ExactSource(
            listID: ProductStateListID(rawValue: listID),
            revision: ProductStateListRevision(value: revision),
            planID: ProductStatePlanID(rawValue: planID),
            planFingerprint: fingerprint
        )
    }

    func authoritySource(
        _ session: WayTaskSchemaV4.ShoppingSession,
        migrationCondition: ShoppingSessionMigrationCondition
    ) -> AuthoritySource? {
        let listID = session.sourceListID.map(ProductStateListID.init(rawValue:))
        let revision: ShoppingSessionSourceRevision
        switch session.sourceRevisionProvenanceRawValue {
        case "exact":
            guard listID != nil, let value = session.sourceRevision, value > 0 else {
                return nil
            }
            revision = .exact(ProductStateListRevision(value: value))
        case "legacyUnknown":
            guard session.sourceRevision == nil else { return nil }
            revision = .legacyUnknown
        default:
            return nil
        }

        let planID = session.sourcePlanID.map(ProductStatePlanID.init(rawValue:))
        let fingerprint = session.sourcePlanSignature
        guard (planID == nil) == (fingerprint == nil),
              fingerprint?.isEmpty != true
        else { return nil }
        if migrationCondition == .native {
            guard case .exact = revision, listID != nil,
                  planID != nil, fingerprint != nil
            else { return nil }
        }
        return AuthoritySource(
            listID: listID,
            revision: revision,
            planID: planID,
            planFingerprint: fingerprint
        )
    }

    func stateValue(
        _ session: WayTaskSchemaV4.ShoppingSession
    ) -> ProductStateSessionStateValue? {
        guard let lifecycle = ShoppingSessionLifecycle(
                rawValue: session.lifecycleRawValue
              ),
              let migrationCondition = ShoppingSessionMigrationCondition(
                rawValue: session.migrationConditionRawValue
              ),
              let source = authoritySource(
                session,
                migrationCondition: migrationCondition
              ),
              session.snapshotVersion == 1,
              session.snapshotGeneration == 1,
              !session.snapshotContentSignature.isEmpty
        else { return nil }
        let lines: [WayTaskSchemaV4.ShoppingSessionLine]
        let stops: [WayTaskSchemaV4.ShoppingSessionStop]
        do {
            lines = try repositories.sessions.sessionLines(sessionID: session.id)
            stops = try repositories.sessions.sessionStops(sessionID: session.id)
        } catch { return nil }
        let stopIDs = Set(stops.map(\.id))
        guard session.revision > 0,
              session.startedAt.timeIntervalSince1970.isFinite,
              session.activationStartedAt.timeIntervalSince1970.isFinite,
              session.lastActivityAt.timeIntervalSince1970.isFinite,
              session.activationStartedAt >= session.startedAt,
              session.lastActivityAt >= session.activationStartedAt,
              !lines.isEmpty,
              Set(lines.map(\.id)).count == lines.count,
              stopIDs.count == stops.count,
              stops.allSatisfy({
                  $0.sessionID == session.id
                      && $0.snapshotID == session.snapshotID
              }),
              lines.allSatisfy({
                  $0.sessionID == session.id
                      && $0.snapshotID == session.snapshotID
                      && ShoppingSessionExecutionState(
                        rawValue: $0.executionStateRawValue
                      ) != nil
                      && ($0.stopID == nil
                        || $0.stopID.map(stopIDs.contains) == true)
              })
        else { return nil }
        if migrationCondition == .native {
            guard !stops.isEmpty,
                  let listID = source.listID,
                  lines.allSatisfy({
                      $0.sourceListID == listID.rawValue
                          && $0.sourceEntryID != nil
                          && $0.productID != nil
                          && $0.stopID.map(stopIDs.contains) == true
                  })
            else { return nil }
        } else if migrationCondition == .legacyMapped {
            guard let listID = source.listID,
                  lines.allSatisfy({
                      $0.sourceListID == listID.rawValue
                          && $0.sourceEntryID != nil
                          && $0.productID != nil
                          && $0.legacyDispositionRawValue == nil
                  })
            else { return nil }
        }
        return ProductStateSessionStateValue(
            sessionID: ProductStateSessionID(rawValue: session.id),
            sourceListID: source.listID,
            sourceRevision: source.revision,
            sourcePlanID: source.planID,
            sourcePlanFingerprint: source.planFingerprint,
            snapshotID: ProductStateSessionSnapshotID(rawValue: session.snapshotID),
            lifecycle: lifecycle,
            migrationCondition: migrationCondition,
            revision: ProductStateSessionRevision(value: session.revision),
            lineIDs: lines.sorted(by: lineLess).map {
                ProductStateSessionLineID(rawValue: $0.id)
            },
            stopIDs: stops.sorted(by: stopLess).map {
                ProductStateSessionStopID(rawValue: $0.id)
            }
        )
    }

    func summary(
        commandID: ProductStateCommandID,
        session: WayTaskSchemaV4.ShoppingSession,
        revisionBefore: UInt64,
        receipt: ProductStateCommandReceipt,
        affectedListRevision: ProductStateAffectedListRevision? = nil
    ) -> ProductStateSessionCommandSummary {
        let state = stateValue(session)!
        return ProductStateSessionCommandSummary(
            commandID: commandID,
            sessionID: state.sessionID,
            sourceListID: state.sourceListID,
            sourceRevision: state.sourceRevision,
            sourcePlanID: state.sourcePlanID,
            sourcePlanFingerprint: state.sourcePlanFingerprint,
            snapshotID: state.snapshotID,
            snapshotContentSignature: session.snapshotContentSignature,
            lifecycle: state.lifecycle,
            revisionBefore: ProductStateSessionRevision(value: revisionBefore),
            revisionAfter: state.revision,
            lineIDs: state.lineIDs,
            stopIDs: state.stopIDs,
            historyEventIDs: receipt.effects.historyEventIDs,
            affectedListRevision: affectedListRevision,
            receipt: receipt
        )
    }

    func finishCommit(
        commandID: ProductStateCommandID,
        effects: [ProductStateStagedEffect],
        success: (ProductStateCommandReceipt) -> ProductStateSessionCommandOutcome,
        retryConflict: ProductStateSessionConflict = .transactionConflict
    ) -> ProductStateSessionCommandExecution {
        let result = commitPrepared(.staged(
            commandID: commandID,
            effects: effects
        ))
        guard result.claimsDurableSuccess,
              case let .committed(receipt) = result.commandResult
        else {
            switch result.disposition {
            case .rolledBack(.stagedStateMismatch):
                return execution(.conflict(retryConflict))
            case .outcomeUnknown:
                return execution(.unavailable(.transactionOutcomeUnknown))
            default:
                return execution(.unavailable(.durableAuthorityUnavailable))
            }
        }
        return execution(success(receipt))
    }

    func multipleCandidateConflict(
    ) throws -> ProductStateSessionCommandOutcome? {
        let rows = try repositories.sessions.shoppingSessions(lifecycle: .active)
            + repositories.sessions.shoppingSessions(lifecycle: .expired)
        let ids = rows.map { ProductStateSessionID(rawValue: $0.id) }
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        guard ids.count > 1 else { return nil }
        return .conflict(.nonTerminalSessions(ids))
    }

    func allowsActiveMutation(
        _ session: WayTaskSchemaV4.ShoppingSession,
        state: ProductStateSessionStateValue
    ) -> Bool {
        switch state.migrationCondition {
        case .native, .legacyMapped:
            true
        case .legacyIncomplete, .legacyUnresolved:
            session.activationStartedAt > session.startedAt
        }
    }

    func finishListID(
        _ session: WayTaskSchemaV4.ShoppingSession,
        state: ProductStateSessionStateValue
    ) -> ProductStateListID? {
        switch state.migrationCondition {
        case .native:
            exactSource(session)?.listID
        case .legacyMapped:
            state.sourceListID
        case .legacyIncomplete, .legacyUnresolved:
            nil
        }
    }

    func blockedExecution() -> ProductStateSessionCommandExecution? {
        switch writeState {
        case .writableTarget: nil
        case .migrationIncomplete:
            execution(.unavailable(.migrationIncomplete))
        case .nonDurable:
            execution(.unavailable(.durableAuthorityUnavailable))
        }
    }

    func expectedSessionRevision(
        _ command: ProductStateCommand
    ) -> ProductStateSessionRevision? {
        guard let expected = command.expectedRevision,
              case let .session(id) = expected.revision.scope,
              expected.revision.value > 0
        else { return nil }
        let scopeID: ProductStateSessionID
        switch command.scope {
        case let .session(id): scopeID = id
        case let .sessionLine(sessionID, _): scopeID = sessionID
        default: return nil
        }
        guard id == scopeID else { return nil }
        return ProductStateSessionRevision(value: expected.revision.value)
    }

    func expirationBoundary(
        _ session: WayTaskSchemaV4.ShoppingSession
    ) -> (date: Date, reason: String)? {
        guard session.lifecycleRawValue
                == ShoppingSessionLifecycle.active.rawValue else { return nil }
        let inactivity = session.lastActivityAt.addingTimeInterval(
            Self.inactivityInterval
        )
        let maximum = session.activationStartedAt.addingTimeInterval(
            Self.maximumActivationInterval
        )
        return inactivity <= maximum
            ? (inactivity, "inactivity")
            : (maximum, "maximumAuthority")
    }

    func isExpirationDue(
        _ session: WayTaskSchemaV4.ShoppingSession,
        at date: Date
    ) -> Bool {
        expirationBoundary(session).map { date >= $0.date } ?? false
    }

    func resolutionReason(
        _ outcome: ShoppingSessionFinalOutcome
    ) -> ShoppingListResolutionReason? {
        switch outcome {
        case .purchased: .purchased
        case .alreadyHave: .alreadyHave
        case .noLongerNeeded: .noLongerNeeded
        case .unavailable, .skipped, .carriedForward: nil
        }
    }

    func historyEvent(
        commandID: ProductStateCommandID,
        session: WayTaskSchemaV4.ShoppingSession,
        line: WayTaskSchemaV4.ShoppingSessionLine,
        outcome: ShoppingSessionFinalOutcome,
        occurredAt: Date
    ) -> WayTaskSchemaV4.ProductHistoryEvent {
        let lineID = ProductStateSessionLineID(rawValue: line.id)
        return WayTaskSchemaV4.ProductHistoryEvent(
            id: historyEventUUID(
                commandID: commandID,
                sessionID: ProductStateSessionID(rawValue: session.id),
                lineID: lineID,
                outcome: outcome
            ),
            productID: line.productID!,
            meaningRawValue: "sessionOutcome",
            resolutionReasonRawValue: resolutionReason(outcome)?.rawValue,
            sessionOutcomeRawValue: outcome.rawValue,
            sourceListID: line.sourceListID,
            sourceEntryID: line.sourceEntryID,
            sessionID: session.id,
            sessionLineID: line.id,
            commandID: commandID.rawValue,
            provenanceRawValue: "sessionFinish",
            occurredAt: occurredAt,
            displaySnapshotID: session.snapshotID,
            product: line.product
        )
    }

    func historyEventUUID(
        commandID: ProductStateCommandID,
        sessionID: ProductStateSessionID,
        lineID: ProductStateSessionLineID,
        outcome: ShoppingSessionFinalOutcome
    ) -> UUID {
        deterministicUUID(
            "finish|\(commandID.rawValue.uuidString.lowercased())|" +
            "\(sessionID.rawValue.uuidString.lowercased())|" +
            "\(lineID.rawValue.uuidString.lowercased())|\(outcome.rawValue)"
        )
    }

    func snapshotSignature(
        command: StartSessionCommand,
        snapshotID: ProductStateSessionSnapshotID,
        plan: ProductStateShoppingPlan,
        fingerprint: String,
        evidenceAt: Date,
        stops: [WayTaskSchemaV4.ShoppingSessionStop],
        lines: [WayTaskSchemaV4.ShoppingSessionLine]
    ) -> String {
        var fields = [
            "session:\(command.sessionID.rawValue.uuidString.lowercased())",
            "snapshot:\(snapshotID.rawValue.uuidString.lowercased())",
            "version:1", "generation:1",
            "list:\(command.listID.rawValue.uuidString.lowercased())",
            "revision:\(command.sourceRevision.value)",
            "plan:\(plan.id.rawValue.uuidString.lowercased())",
            "plan-signature:\(fingerprint)",
            "evidence:\(canonicalDate(evidenceAt))"
        ]
        fields.append(contentsOf: stops.sorted(by: stopLess).map { stop in
            [
                "stop", stop.id.uuidString.lowercased(),
                String(stop.sortOrder),
                stop.storeReferenceIDRawValue ?? "",
                stop.storeReferenceProvenanceRawValue,
                stop.displayNameSnapshot,
                canonicalDouble(stop.latitudeSnapshot!),
                canonicalDouble(stop.longitudeSnapshot!),
                canonicalDate(stop.evidenceAt!),
                stop.isSessionScopedTransient ? "transient" : "stable"
            ].joined(separator: "|")
        })
        fields.append(contentsOf: lines.sorted(by: lineLess).map { line in
            [
                "line", line.id.uuidString.lowercased(),
                String(line.sortOrder),
                line.sourceListID!.uuidString.lowercased(),
                line.sourceEntryID!.uuidString.lowercased(),
                line.productID!.uuidString.lowercased(),
                line.globalProductConceptIDRawValue ?? "",
                line.stopID!.uuidString.lowercased(),
                line.productNameSnapshot,
                line.productBrandSnapshot ?? "",
                line.productCategorySnapshot ?? "",
                canonicalDouble(line.quantitySnapshot),
                line.unitSnapshotRawValue ?? "",
                line.noteSnapshot ?? ""
            ].joined(separator: "|")
        })
        return sha256(fields.joined(separator: "\n"))
    }

    func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func deterministicUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func canonicalDate(_ value: Date) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"),
               value.timeIntervalSince1970)
    }

    func canonicalDouble(_ value: Double) -> String {
        String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    func validStop(_ stop: ProductStateSessionStopInput) -> Bool {
        valid(stop.id.rawValue)
            && stop.sortOrder >= 0
            && !stop.storeReferenceProvenanceRawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !stop.displayNameSnapshot.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && stop.latitude.isFinite && (-90...90).contains(stop.latitude)
            && stop.longitude.isFinite && (-180...180).contains(stop.longitude)
            && stop.evidenceAt.timeIntervalSince1970.isFinite
            && (!stop.isSessionScopedTransient
                ? !(stop.storeReferenceIDRawValue ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                : true)
    }

    func valid(_ id: UUID) -> Bool {
        id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    func execution(
        _ outcome: ProductStateSessionCommandOutcome
    ) -> ProductStateSessionCommandExecution {
        ProductStateSessionCommandExecution(outcome: outcome)
    }

    func sessionLess(
        _ lhs: WayTaskSchemaV4.ShoppingSession,
        _ rhs: WayTaskSchemaV4.ShoppingSession
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func lineLess(
        _ lhs: WayTaskSchemaV4.ShoppingSessionLine,
        _ rhs: WayTaskSchemaV4.ShoppingSessionLine
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func stopLess(
        _ lhs: WayTaskSchemaV4.ShoppingSessionStop,
        _ rhs: WayTaskSchemaV4.ShoppingSessionStop
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func lineInputLess(
        _ lhs: ProductStateSessionLineInput,
        _ rhs: ProductStateSessionLineInput
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    func stopInputLess(
        _ lhs: ProductStateSessionStopInput,
        _ rhs: ProductStateSessionStopInput
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}
