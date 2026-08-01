import Foundation
import SwiftData

enum WayTaskStartupPersistenceStage: String {
    case openStore = "open_store"
    case startupRepair = "startup_repair"
    case quarantineStore = "quarantine_store"
    case recreatePersistentStore = "recreate_persistent_store"
    case inMemoryFallback = "in_memory_fallback"
    case migrationGate = "migration_gate"
    case migrationValidation = "migration_validation"
    case migrationRecovery = "migration_recovery"
    case migrationComplete = "migration_complete"
    case unrecoverable
}

enum WayTaskStartupPersistenceOutcome: String {
    case failed
    case recovered
    case degraded
    case fatal
}

struct WayTaskStartupPersistenceDiagnostic: Equatable {
    let stage: WayTaskStartupPersistenceStage
    let outcome: WayTaskStartupPersistenceOutcome
    let errorDomain: String?
    let errorCode: Int?
    let underlyingErrorDomain: String?
    let underlyingErrorCode: Int?
    let quarantinedComponentCount: Int
    let repairActionCount: Int

    init(
        stage: WayTaskStartupPersistenceStage,
        outcome: WayTaskStartupPersistenceOutcome,
        error: Error? = nil,
        quarantinedComponentCount: Int = 0,
        repairActionCount: Int = 0
    ) {
        self.stage = stage
        self.outcome = outcome
        self.quarantinedComponentCount =
            max(quarantinedComponentCount, 0)
        self.repairActionCount = max(repairActionCount, 0)

        guard let error else {
            errorDomain = nil
            errorCode = nil
            underlyingErrorDomain = nil
            underlyingErrorCode = nil
            return
        }

        let nsError = error as NSError
        errorDomain = Self.sanitizedIdentifier(nsError.domain)
        errorCode = nsError.code

        if let underlyingError =
            nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        {
            underlyingErrorDomain =
                Self.sanitizedIdentifier(underlyingError.domain)
            underlyingErrorCode = underlyingError.code
        } else {
            underlyingErrorDomain = nil
            underlyingErrorCode = nil
        }
    }

    private static func sanitizedIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        let scalars = value.unicodeScalars.prefix(120).map {
            allowed.contains($0) ? Character(String($0)) : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "unknown" : result
    }
}

enum WayTaskStartupPersistenceMode: Equatable {
    case persistent
    case recreatedPersistentStore
    case inMemoryFallback
    case startupGate
}

struct WayTaskStartupPersistenceResult {
    let modelContainer: ModelContainer
    let mode: WayTaskStartupPersistenceMode
    let migrationGateDecision: WayTaskStartupMigrationGateDecision
}

enum WayTaskStartupPersistenceError: LocalizedError {
    case migrationGateUnavailable(Error)
    case unrecoverable(
        initial: Error,
        persistentRecovery: Error,
        inMemoryFallback: Error
    )

    var errorDescription: String? {
        switch self {
        case .migrationGateUnavailable:
            return "WayTask could not initialize the isolated startup gate."
        case .unrecoverable:
            return "WayTask could not initialize persistent or temporary local storage."
        }
    }
}

// MARK: - T-09 pre-promotion startup migration gate

enum WayTaskStartupMigrationState: String, CaseIterable, Codable, Sendable {
    case startupReady = "startup_ready"
    case migrationRequired = "migration_required"
    case migrationRunning = "migration_running"
    case migrationInterrupted = "migration_interrupted"
    case migrationFailed = "migration_failed"
    case recoveryRequired = "recovery_required"
    case degradedMode = "degraded_mode"
    case migrationSucceeded = "migration_succeeded"
}

enum WayTaskStartupDurabilityMode: String, Codable, Sendable {
    case persistentV3 = "persistent_v3"
    case protectedStoreNotOpened = "protected_store_not_opened"
    case recreatedStoreBlocked = "recreated_store_blocked"
    case inMemoryBlocked = "in_memory_blocked"
    case unavailable = "unavailable"
}

enum WayTaskStartupMigrationFailureClassification: String, Codable,
    Sendable
{
    case migrationIncomplete = "migration_incomplete"
    case candidateIntegrityFailed = "candidate_integrity_failed"
    case fingerprintMismatch = "fingerprint_mismatch"
    case candidateReopenFailed = "candidate_reopen_failed"
    case migrationValidationFailed = "migration_validation_failed"
    case insufficientDestinationSpace = "insufficient_destination_space"
    case protectedOriginalUnavailable = "protected_original_unavailable"
    case rollbackUnverified = "rollback_unverified"
    case recreatedStoreRequiresRecovery =
        "recreated_store_requires_recovery"
    case inMemoryIsNotDurable = "in_memory_is_not_durable"
    case recoveryDecisionRequired = "recovery_decision_required"
    case unauthorizedPromotion = "unauthorized_promotion"
    case unauthorizedTargetActivation = "unauthorized_target_activation"
    case gatePresentationUnavailable = "gate_presentation_unavailable"
}

struct WayTaskStartupMigrationRecoveryEvidence: Equatable, Sendable {
    let protectedOriginalVerified: Bool
    let rollbackVerified: Bool
    let candidateArtifactsRemain: Bool
}

struct WayTaskStartupMigrationCompletionEvidence: Equatable, Sendable {
    let migrationComplete: Bool
    let candidateIntegrityVerified: Bool
    let sourceFingerprintVerified: Bool
    let candidateFingerprintVerified: Bool
    let candidateReopenVerified: Bool
    let protectedOriginalVerified: Bool
    let rollbackStateVerified: Bool
    let recoveryRequiredCount: Int
    let exceptionCount: Int
    let exceptionOverflowCount: Int
    let candidateArtifactCount: Int
    let promotionAuthorized: Bool
    let targetSchemaActivated: Bool

    init(
        migrationComplete: Bool,
        candidateIntegrityVerified: Bool,
        sourceFingerprintVerified: Bool,
        candidateFingerprintVerified: Bool,
        candidateReopenVerified: Bool,
        protectedOriginalVerified: Bool,
        rollbackStateVerified: Bool,
        recoveryRequiredCount: Int,
        exceptionCount: Int,
        exceptionOverflowCount: Int,
        candidateArtifactCount: Int,
        promotionAuthorized: Bool = false,
        targetSchemaActivated: Bool = false
    ) {
        self.migrationComplete = migrationComplete
        self.candidateIntegrityVerified = candidateIntegrityVerified
        self.sourceFingerprintVerified = sourceFingerprintVerified
        self.candidateFingerprintVerified = candidateFingerprintVerified
        self.candidateReopenVerified = candidateReopenVerified
        self.protectedOriginalVerified = protectedOriginalVerified
        self.rollbackStateVerified = rollbackStateVerified
        self.recoveryRequiredCount = max(recoveryRequiredCount, 0)
        self.exceptionCount = max(exceptionCount, 0)
        self.exceptionOverflowCount = max(exceptionOverflowCount, 0)
        self.candidateArtifactCount = max(candidateArtifactCount, 0)
        self.promotionAuthorized = promotionAuthorized
        self.targetSchemaActivated = targetSchemaActivated
    }
}

enum WayTaskStartupMigrationTrace: Equatable, Sendable {
    case targetInactive
    case migrationRequired
    case migrationRunning
    case migrationInterrupted(WayTaskStartupMigrationRecoveryEvidence)
    case migrationFailed(
        WayTaskStartupMigrationFailureClassification,
        WayTaskStartupMigrationRecoveryEvidence
    )
    case recoveryRequired(WayTaskStartupMigrationFailureClassification)
    case recoveryCompleted(WayTaskStartupMigrationRecoveryEvidence)
    case migrationCompleted(WayTaskStartupMigrationCompletionEvidence)

    var isExplicitTargetTrace: Bool {
        self != .targetInactive
    }
}

struct WayTaskStartupMigrationGateDiagnostic: Equatable, Codable, Sendable {
    let state: WayTaskStartupMigrationState
    let durabilityMode: WayTaskStartupDurabilityMode
    let failureClassification:
        WayTaskStartupMigrationFailureClassification?
    let migrationCompletionVerified: Bool
    let candidateIntegrityVerified: Bool
    let fingerprintsVerified: Bool
    let candidateReopenVerified: Bool
    let protectedOriginalVerified: Bool
    let rollbackVerified: Bool
    let recoveryRequiredCount: Int
    let exceptionCount: Int
    let exceptionOverflowCount: Int
    let candidateArtifactCount: Int
}

struct WayTaskStartupMigrationGateDecision: Equatable, Sendable {
    let diagnostic: WayTaskStartupMigrationGateDiagnostic

    var state: WayTaskStartupMigrationState { diagnostic.state }
    var durabilityMode: WayTaskStartupDurabilityMode {
        diagnostic.durabilityMode
    }

    var allowsLegacyV3ApplicationContent: Bool {
        state == .startupReady && durabilityMode == .persistentV3
    }

    // T-09 is deliberately pre-promotion. A later cutover must add a separate
    // authorization after every consumer and writer has converted together.
    var writableTargetAccessAuthorized: Bool { false }
    var targetUIActivationAuthorized: Bool { false }
    var candidatePromotionAuthorized: Bool { false }
}

struct WayTaskStartupMigrationGate {
    func evaluate(
        persistenceMode: WayTaskStartupPersistenceMode,
        trace: WayTaskStartupMigrationTrace
    ) -> WayTaskStartupMigrationGateDecision {
        switch persistenceMode {
        case .recreatedPersistentStore:
            return decision(
                state: .recoveryRequired,
                durability: .recreatedStoreBlocked,
                failure: .recreatedStoreRequiresRecovery
            )
        case .inMemoryFallback:
            return decision(
                state: .degradedMode,
                durability: .inMemoryBlocked,
                failure: .inMemoryIsNotDurable
            )
        case .persistent, .startupGate:
            break
        }

        let durability: WayTaskStartupDurabilityMode =
            persistenceMode == .persistent
                ? .persistentV3 : .protectedStoreNotOpened

        switch trace {
        case .targetInactive:
            return decision(
                state: .startupReady,
                durability: durability
            )
        case .migrationRequired:
            return decision(
                state: .migrationRequired,
                durability: durability,
                failure: .migrationIncomplete
            )
        case .migrationRunning:
            return decision(
                state: .migrationRunning,
                durability: durability
            )
        case .migrationInterrupted(let recovery):
            guard recovery.protectedOriginalVerified else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .protectedOriginalUnavailable,
                    recovery: recovery
                )
            }
            guard recovery.rollbackVerified else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .rollbackUnverified,
                    recovery: recovery
                )
            }
            return decision(
                state: .migrationInterrupted,
                durability: durability,
                failure: .migrationIncomplete,
                recovery: recovery
            )
        case .migrationFailed(let failure, let recovery):
            guard recovery.protectedOriginalVerified else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .protectedOriginalUnavailable,
                    recovery: recovery
                )
            }
            guard recovery.rollbackVerified else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .rollbackUnverified,
                    recovery: recovery
                )
            }
            return decision(
                state: .migrationFailed,
                durability: durability,
                failure: failure,
                recovery: recovery
            )
        case .recoveryRequired(let failure):
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: failure
            )
        case .recoveryCompleted(let recovery):
            guard recovery.protectedOriginalVerified else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .protectedOriginalUnavailable,
                    recovery: recovery
                )
            }
            guard recovery.rollbackVerified,
                  !recovery.candidateArtifactsRemain else {
                return decision(
                    state: .recoveryRequired,
                    durability: durability,
                    failure: .rollbackUnverified,
                    recovery: recovery
                )
            }
            return decision(
                state: .startupReady,
                durability: durability,
                recovery: recovery
            )
        case .migrationCompleted(let evidence):
            return completedDecision(
                evidence,
                durability: durability
            )
        }
    }

    func unavailableDecision() -> WayTaskStartupMigrationGateDecision {
        decision(
            state: .degradedMode,
            durability: .unavailable,
            failure: .gatePresentationUnavailable
        )
    }

    private func completedDecision(
        _ evidence: WayTaskStartupMigrationCompletionEvidence,
        durability: WayTaskStartupDurabilityMode
    ) -> WayTaskStartupMigrationGateDecision {
        if evidence.promotionAuthorized {
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: .unauthorizedPromotion,
                completion: evidence
            )
        }
        if evidence.targetSchemaActivated {
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: .unauthorizedTargetActivation,
                completion: evidence
            )
        }
        guard evidence.protectedOriginalVerified else {
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: .protectedOriginalUnavailable,
                completion: evidence
            )
        }
        guard evidence.rollbackStateVerified else {
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: .rollbackUnverified,
                completion: evidence
            )
        }
        guard evidence.migrationComplete else {
            return decision(
                state: .migrationRequired,
                durability: durability,
                failure: .migrationIncomplete,
                completion: evidence
            )
        }
        guard evidence.candidateIntegrityVerified else {
            return decision(
                state: .migrationFailed,
                durability: durability,
                failure: .candidateIntegrityFailed,
                completion: evidence
            )
        }
        guard evidence.sourceFingerprintVerified,
              evidence.candidateFingerprintVerified else {
            return decision(
                state: .migrationFailed,
                durability: durability,
                failure: .fingerprintMismatch,
                completion: evidence
            )
        }
        guard evidence.candidateReopenVerified else {
            return decision(
                state: .migrationFailed,
                durability: durability,
                failure: .candidateReopenFailed,
                completion: evidence
            )
        }
        guard evidence.recoveryRequiredCount == 0 else {
            return decision(
                state: .recoveryRequired,
                durability: durability,
                failure: .recoveryDecisionRequired,
                completion: evidence
            )
        }
        return decision(
            state: .migrationSucceeded,
            durability: durability,
            completion: evidence
        )
    }

    private func decision(
        state: WayTaskStartupMigrationState,
        durability: WayTaskStartupDurabilityMode,
        failure: WayTaskStartupMigrationFailureClassification? = nil,
        recovery: WayTaskStartupMigrationRecoveryEvidence? = nil,
        completion: WayTaskStartupMigrationCompletionEvidence? = nil
    ) -> WayTaskStartupMigrationGateDecision {
        WayTaskStartupMigrationGateDecision(
            diagnostic: WayTaskStartupMigrationGateDiagnostic(
                state: state,
                durabilityMode: durability,
                failureClassification: failure,
                migrationCompletionVerified:
                    completion?.migrationComplete ?? false,
                candidateIntegrityVerified:
                    completion?.candidateIntegrityVerified ?? false,
                fingerprintsVerified:
                    (completion?.sourceFingerprintVerified ?? false) &&
                        (completion?.candidateFingerprintVerified ?? false),
                candidateReopenVerified:
                    completion?.candidateReopenVerified ?? false,
                protectedOriginalVerified:
                    completion?.protectedOriginalVerified ??
                        recovery?.protectedOriginalVerified ?? false,
                rollbackVerified:
                    completion?.rollbackStateVerified ??
                        recovery?.rollbackVerified ?? false,
                recoveryRequiredCount:
                    completion?.recoveryRequiredCount ?? 0,
                exceptionCount: completion?.exceptionCount ?? 0,
                exceptionOverflowCount:
                    completion?.exceptionOverflowCount ?? 0,
                candidateArtifactCount:
                    completion?.candidateArtifactCount ?? 0
            )
        )
    }
}

@MainActor
struct WayTaskStartupPersistenceBootstrap {
    typealias ContainerFactory = () throws -> ModelContainer
    typealias StoreRepair = (ModelContainer) throws -> Int
    typealias StoreQuarantine = () throws -> Int
    typealias DiagnosticReporter =
        (WayTaskStartupPersistenceDiagnostic) -> Void
    typealias DeveloperAssertion = (String) -> Void
    typealias MigrationTraceProvider = () -> WayTaskStartupMigrationTrace

    private let openDefaultStore: ContainerFactory
    private let openInMemoryStore: ContainerFactory
    private let repairStore: StoreRepair
    private let quarantineStore: StoreQuarantine
    private let reportDiagnostic: DiagnosticReporter
    private let developerAssertion: DeveloperAssertion
    private let migrationTraceProvider: MigrationTraceProvider
    private let migrationGate = WayTaskStartupMigrationGate()

    private struct InitialStoreFailure: Error {
        let stage: WayTaskStartupPersistenceStage
        let underlyingError: Error
    }

    init(
        openDefaultStore: @escaping ContainerFactory,
        openInMemoryStore: @escaping ContainerFactory,
        repairStore: @escaping StoreRepair,
        quarantineStore: @escaping StoreQuarantine,
        reportDiagnostic: @escaping DiagnosticReporter,
        developerAssertion: @escaping DeveloperAssertion,
        migrationTraceProvider: @escaping MigrationTraceProvider = {
            .targetInactive
        }
    ) {
        self.openDefaultStore = openDefaultStore
        self.openInMemoryStore = openInMemoryStore
        self.repairStore = repairStore
        self.quarantineStore = quarantineStore
        self.reportDiagnostic = reportDiagnostic
        self.developerAssertion = developerAssertion
        self.migrationTraceProvider = migrationTraceProvider
    }

    static func live() -> WayTaskStartupPersistenceBootstrap {
        WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                try WayTaskModelContainer.makeDefault()
            },
            openInMemoryStore: {
                try WayTaskModelContainer.makeInMemory()
            },
            repairStore: { container in
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(in: context)
                    .repairActionCount
            },
            quarantineStore: {
                try WayTaskStoreQuarantine(
                    storeURL: WayTaskModelContainer.defaultStoreURL
                ).quarantine()
            },
            reportDiagnostic: { diagnostic in
                SentryReportingService.shared
                    .captureStartupPersistence(diagnostic)
            },
            developerAssertion: { message in
                #if DEBUG
                assertionFailure(message)
                #endif
            }
        )
    }

    func start() throws -> WayTaskStartupPersistenceResult {
        let migrationTrace = migrationTraceProvider()
        if migrationTrace.isExplicitTargetTrace {
            if case .recoveryCompleted = migrationTrace {
                let decision = migrationGate.evaluate(
                    persistenceMode: .persistent,
                    trace: migrationTrace
                )
                if decision.allowsLegacyV3ApplicationContent {
                    reportDiagnostic(
                        WayTaskStartupPersistenceDiagnostic(
                            stage: .migrationRecovery,
                            outcome: .recovered
                        )
                    )
                    return try openAndRepairInitialStore()
                }
            }
            return try startMigrationGateOnly(trace: migrationTrace)
        }
        do {
            return try openAndRepairInitialStore()
        } catch let failure as InitialStoreFailure {
            return try recover(
                from: failure.underlyingError,
                stage: failure.stage
            )
        }
    }

    private func openAndRepairInitialStore() throws
        -> WayTaskStartupPersistenceResult
    {
        let initialContainer: ModelContainer
        do {
            initialContainer = try openDefaultStore()
        } catch {
            throw InitialStoreFailure(
                stage: .openStore,
                underlyingError: error
            )
        }

        let repairActionCount: Int
        do {
            repairActionCount = try repairStore(initialContainer)
        } catch {
            throw InitialStoreFailure(
                stage: .startupRepair,
                underlyingError: error
            )
        }
        if repairActionCount > 0 {
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .startupRepair,
                    outcome: .recovered,
                    repairActionCount: repairActionCount
                )
            )
        }
        return WayTaskStartupPersistenceResult(
            modelContainer: initialContainer,
            mode: .persistent,
            migrationGateDecision: migrationGate.evaluate(
                persistenceMode: .persistent,
                trace: .targetInactive
            )
        )
    }

    private func recover(
        from initialError: Error,
        stage: WayTaskStartupPersistenceStage
    ) throws -> WayTaskStartupPersistenceResult {
        reportDiagnostic(
            WayTaskStartupPersistenceDiagnostic(
                stage: stage,
                outcome: .failed,
                error: initialError
            )
        )
        developerAssertion(
            "[WayTask Startup] Recoverable \(stage.rawValue) failure: \(initialError.localizedDescription)"
        )

        var quarantinedComponentCount = 0
        let persistentRecoveryError: Error

        do {
            quarantinedComponentCount = try quarantineStore()
        } catch {
            persistentRecoveryError = error
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .quarantineStore,
                    outcome: .failed,
                    error: error
                )
            )
            return try fallBackToMemory(
                initialError: initialError,
                persistentRecoveryError: persistentRecoveryError,
                quarantinedComponentCount: 0
            )
        }

        do {
            let recoveredContainer = try openDefaultStore()
            let repairActionCount =
                try repairStore(recoveredContainer)
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .recreatePersistentStore,
                    outcome: .recovered,
                    quarantinedComponentCount:
                        quarantinedComponentCount,
                    repairActionCount: repairActionCount
                )
            )
            return WayTaskStartupPersistenceResult(
                modelContainer: recoveredContainer,
                mode: .recreatedPersistentStore,
                migrationGateDecision: migrationGate.evaluate(
                    persistenceMode: .recreatedPersistentStore,
                    trace: .targetInactive
                )
            )
        } catch {
            persistentRecoveryError = error
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .recreatePersistentStore,
                    outcome: .failed,
                    error: error,
                    quarantinedComponentCount:
                        quarantinedComponentCount
                )
            )
            return try fallBackToMemory(
                initialError: initialError,
                persistentRecoveryError: persistentRecoveryError,
                quarantinedComponentCount:
                    quarantinedComponentCount
            )
        }
    }

    private func fallBackToMemory(
        initialError: Error,
        persistentRecoveryError: Error,
        quarantinedComponentCount: Int
    ) throws -> WayTaskStartupPersistenceResult {
        do {
            let fallbackContainer = try openInMemoryStore()
            let repairActionCount =
                try repairStore(fallbackContainer)
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .inMemoryFallback,
                    outcome: .degraded,
                    error: persistentRecoveryError,
                    quarantinedComponentCount:
                        quarantinedComponentCount,
                    repairActionCount: repairActionCount
                )
            )
            return WayTaskStartupPersistenceResult(
                modelContainer: fallbackContainer,
                mode: .inMemoryFallback,
                migrationGateDecision: migrationGate.evaluate(
                    persistenceMode: .inMemoryFallback,
                    trace: .targetInactive
                )
            )
        } catch {
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .unrecoverable,
                    outcome: .fatal,
                    error: error,
                    quarantinedComponentCount:
                        quarantinedComponentCount
                )
            )
            throw WayTaskStartupPersistenceError.unrecoverable(
                initial: initialError,
                persistentRecovery: persistentRecoveryError,
                inMemoryFallback: error
            )
        }
    }

    private func startMigrationGateOnly(
        trace: WayTaskStartupMigrationTrace
    ) throws -> WayTaskStartupPersistenceResult {
        let decision = migrationGate.evaluate(
            persistenceMode: .startupGate,
            trace: trace
        )
        reportDiagnostic(decision.persistenceDiagnostic)
        do {
            return WayTaskStartupPersistenceResult(
                modelContainer: try openInMemoryStore(),
                mode: .startupGate,
                migrationGateDecision: decision
            )
        } catch {
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .migrationGate,
                    outcome: .fatal,
                    error: error
                )
            )
            throw WayTaskStartupPersistenceError
                .migrationGateUnavailable(error)
        }
    }
}

private extension WayTaskStartupMigrationGateDecision {
    var persistenceDiagnostic: WayTaskStartupPersistenceDiagnostic {
        let stage: WayTaskStartupPersistenceStage
        let outcome: WayTaskStartupPersistenceOutcome
        switch state {
        case .startupReady:
            stage = .migrationGate
            outcome = .recovered
        case .migrationRequired, .migrationRunning:
            stage = .migrationGate
            outcome = .degraded
        case .migrationInterrupted, .recoveryRequired:
            stage = .migrationRecovery
            outcome = .degraded
        case .migrationFailed:
            stage = .migrationValidation
            outcome = .failed
        case .degradedMode:
            stage = .migrationGate
            outcome = .degraded
        case .migrationSucceeded:
            stage = .migrationComplete
            outcome = .recovered
        }
        return WayTaskStartupPersistenceDiagnostic(
            stage: stage,
            outcome: outcome
        )
    }
}

struct WayTaskStoreQuarantine {
    typealias Clock = () -> Date
    typealias IdentifierFactory = () -> UUID

    private let storeURL: URL
    private let quarantineRootURL: URL
    private let fileManager: FileManager
    private let clock: Clock
    private let identifierFactory: IdentifierFactory

    init(
        storeURL: URL,
        quarantineRootURL: URL? = nil,
        fileManager: FileManager = .default,
        clock: @escaping Clock = Date.init,
        identifierFactory: @escaping IdentifierFactory = UUID.init
    ) {
        self.storeURL = storeURL
        self.quarantineRootURL = quarantineRootURL ??
            storeURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "WayTask Store Quarantine",
                    isDirectory: true
                )
        self.fileManager = fileManager
        self.clock = clock
        self.identifierFactory = identifierFactory
    }

    @discardableResult
    func quarantine() throws -> Int {
        let components = storeComponentURLs.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !components.isEmpty else {
            return 0
        }

        try fileManager.createDirectory(
            at: quarantineRootURL,
            withIntermediateDirectories: true
        )
        let timestamp = Int(
            clock().timeIntervalSince1970 * 1_000
        )
        let quarantineURL = quarantineRootURL
            .appendingPathComponent(
                "\(timestamp)-\(identifierFactory().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: quarantineURL,
            withIntermediateDirectories: false
        )

        var completedMoves: [(source: URL, destination: URL)] = []
        do {
            for source in components {
                let destination = quarantineURL.appendingPathComponent(
                    source.lastPathComponent,
                    isDirectory: false
                )
                try fileManager.moveItem(
                    at: source,
                    to: destination
                )
                completedMoves.append((source, destination))
            }
            return completedMoves.count
        } catch {
            for move in completedMoves.reversed()
            where fileManager.fileExists(
                atPath: move.destination.path
            ) && !fileManager.fileExists(atPath: move.source.path)
            {
                try? fileManager.moveItem(
                    at: move.destination,
                    to: move.source
                )
            }
            try? fileManager.removeItem(at: quarantineURL)
            throw error
        }
    }

    private var storeComponentURLs: [URL] {
        let name = storeURL.lastPathComponent
        let siblings = (
            try? fileManager.contentsOfDirectory(
                at: storeURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        ) ?? []
        return siblings.filter { url in
            let siblingName = url.lastPathComponent
            return siblingName == name ||
                siblingName.hasPrefix(name + "-") ||
                siblingName.hasPrefix(name + "_") ||
                siblingName.hasPrefix(name + ".")
        }
    }
}
