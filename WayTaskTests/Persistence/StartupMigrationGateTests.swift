import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class StartupMigrationGateTests: XCTestCase {
    private let gate = WayTaskStartupMigrationGate()

    func test01RequiredStartupStatesAreExactAndStable() {
        XCTAssertEqual(
            WayTaskStartupMigrationState.allCases.map(\.rawValue),
            [
                "startup_ready",
                "migration_required",
                "migration_running",
                "migration_interrupted",
                "migration_failed",
                "recovery_required",
                "degraded_mode",
                "migration_succeeded"
            ]
        )
    }

    func test02TargetInactivePersistentV3IsStartupReadyOnly() {
        let decision = gate.evaluate(
            persistenceMode: .persistent,
            trace: .targetInactive
        )

        XCTAssertEqual(decision.state, .startupReady)
        XCTAssertEqual(decision.durabilityMode, .persistentV3)
        XCTAssertTrue(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test03MigrationRequiredBlocksAllApplicationAndTargetAccess() {
        let decision = evaluate(.migrationRequired)

        XCTAssertEqual(decision.state, .migrationRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .migrationIncomplete
        )
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test04MigrationRunningIsExplicitAndBlocked() {
        let decision = evaluate(.migrationRunning)

        XCTAssertEqual(decision.state, .migrationRunning)
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test05VerifiedInterruptedAttemptRequiresSafeRetry() {
        let decision = evaluate(
            .migrationInterrupted(verifiedRecovery())
        )

        XCTAssertEqual(decision.state, .migrationInterrupted)
        XCTAssertTrue(decision.diagnostic.protectedOriginalVerified)
        XCTAssertTrue(decision.diagnostic.rollbackVerified)
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test06InterruptedAttemptWithoutRollbackRequiresRecovery() {
        let decision = evaluate(
            .migrationInterrupted(
                WayTaskStartupMigrationRecoveryEvidence(
                    protectedOriginalVerified: true,
                    rollbackVerified: false,
                    candidateArtifactsRemain: true
                )
            )
        )

        XCTAssertEqual(decision.state, .recoveryRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .rollbackUnverified
        )
        assertTargetRemainsInactive(decision)
    }

    func test07FailedMigrationWithVerifiedRollbackIsDeterministic() {
        let decision = evaluate(
            .migrationFailed(
                .migrationValidationFailed,
                verifiedRecovery()
            )
        )

        XCTAssertEqual(decision.state, .migrationFailed)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .migrationValidationFailed
        )
        XCTAssertTrue(decision.diagnostic.rollbackVerified)
        assertTargetRemainsInactive(decision)
    }

    func test07InsufficientSpaceFailureRemainsClassifiedAndBlocked() {
        let decision = evaluate(
            .migrationFailed(
                .insufficientDestinationSpace,
                verifiedRecovery()
            )
        )

        XCTAssertEqual(decision.state, .migrationFailed)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .insufficientDestinationSpace
        )
        assertTargetRemainsInactive(decision)
    }

    func test08FailedMigrationWithoutProtectedOriginalRequiresRecovery() {
        let decision = evaluate(
            .migrationFailed(
                .candidateReopenFailed,
                WayTaskStartupMigrationRecoveryEvidence(
                    protectedOriginalVerified: false,
                    rollbackVerified: true,
                    candidateArtifactsRemain: false
                )
            )
        )

        XCTAssertEqual(decision.state, .recoveryRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .protectedOriginalUnavailable
        )
        assertTargetRemainsInactive(decision)
    }

    func test09ExplicitRecoveryStateNeverFallsBackImplicitly() {
        let decision = evaluate(
            .recoveryRequired(.recoveryDecisionRequired)
        )

        XCTAssertEqual(decision.state, .recoveryRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .recoveryDecisionRequired
        )
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test09SuccessfulRecoveryReopensV3OnlyAfterVerifiedRollback()
        throws
    {
        let container = try makeInMemoryContainer()
        var defaultOpenCount = 0
        var repairCount = 0
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                defaultOpenCount += 1
                return container
            },
            openInMemoryStore: {
                XCTFail("Verified recovery should reopen persistent V3")
                return container
            },
            repairStore: { _ in
                repairCount += 1
                return 0
            },
            quarantineStore: {
                XCTFail("Verified recovery must not quarantine again")
                return 0
            },
            reportDiagnostic: { diagnostics.append($0) },
            developerAssertion: { _ in },
            migrationTraceProvider: {
                .recoveryCompleted(self.verifiedRecovery())
            }
        )

        let result = try bootstrap.start()

        XCTAssertEqual(result.mode, .persistent)
        XCTAssertEqual(result.migrationGateDecision.state, .startupReady)
        XCTAssertEqual(defaultOpenCount, 1)
        XCTAssertEqual(repairCount, 1)
        XCTAssertEqual(diagnostics.map(\.stage), [.migrationRecovery])
        XCTAssertEqual(diagnostics.map(\.outcome), [.recovered])
        XCTAssertTrue(
            result.migrationGateDecision
                .allowsLegacyV3ApplicationContent
        )
        assertTargetRemainsInactive(result.migrationGateDecision)
    }

    func test10InMemoryModeIsDegradedAndNeverDurableSuccess() {
        let decision = gate.evaluate(
            persistenceMode: .inMemoryFallback,
            trace: .targetInactive
        )

        XCTAssertEqual(decision.state, .degradedMode)
        XCTAssertEqual(decision.durabilityMode, .inMemoryBlocked)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .inMemoryIsNotDurable
        )
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test11RecreatedEmptyStoreRequiresRecoveryInsteadOfSuccess() {
        let decision = gate.evaluate(
            persistenceMode: .recreatedPersistentStore,
            trace: .targetInactive
        )

        XCTAssertEqual(decision.state, .recoveryRequired)
        XCTAssertEqual(decision.durabilityMode, .recreatedStoreBlocked)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .recreatedStoreRequiresRecovery
        )
        assertTargetRemainsInactive(decision)
    }

    func test12VerifiedCompletionProducesPrePromotionSuccessOnly() {
        let decision = evaluate(
            .migrationCompleted(validCompletion())
        )

        XCTAssertEqual(decision.state, .migrationSucceeded)
        XCTAssertTrue(decision.diagnostic.migrationCompletionVerified)
        XCTAssertTrue(decision.diagnostic.candidateIntegrityVerified)
        XCTAssertTrue(decision.diagnostic.fingerprintsVerified)
        XCTAssertTrue(decision.diagnostic.candidateReopenVerified)
        XCTAssertTrue(decision.diagnostic.protectedOriginalVerified)
        XCTAssertTrue(decision.diagnostic.rollbackVerified)
        XCTAssertFalse(decision.allowsLegacyV3ApplicationContent)
        assertTargetRemainsInactive(decision)
    }

    func test13IncompleteCompletionEvidenceReturnsMigrationRequired() {
        let decision = evaluate(
            .migrationCompleted(validCompletion(migrationComplete: false))
        )

        XCTAssertEqual(decision.state, .migrationRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .migrationIncomplete
        )
        assertTargetRemainsInactive(decision)
    }

    func test14IntegrityFingerprintAndReopenFailuresRemainDistinct() {
        let integrity = evaluate(
            .migrationCompleted(
                validCompletion(candidateIntegrityVerified: false)
            )
        )
        XCTAssertEqual(integrity.state, .migrationFailed)
        XCTAssertEqual(
            integrity.diagnostic.failureClassification,
            .candidateIntegrityFailed
        )

        let fingerprint = evaluate(
            .migrationCompleted(
                validCompletion(candidateFingerprintVerified: false)
            )
        )
        XCTAssertEqual(fingerprint.state, .migrationFailed)
        XCTAssertEqual(
            fingerprint.diagnostic.failureClassification,
            .fingerprintMismatch
        )

        let reopen = evaluate(
            .migrationCompleted(
                validCompletion(candidateReopenVerified: false)
            )
        )
        XCTAssertEqual(reopen.state, .migrationFailed)
        XCTAssertEqual(
            reopen.diagnostic.failureClassification,
            .candidateReopenFailed
        )
    }

    func test15RecoveryCandidatesBlockSuccessWithoutDiscardingCounts() {
        let decision = evaluate(
            .migrationCompleted(
                validCompletion(
                    recoveryRequiredCount: 2,
                    exceptionCount: 7,
                    exceptionOverflowCount: 3
                )
            )
        )

        XCTAssertEqual(decision.state, .recoveryRequired)
        XCTAssertEqual(
            decision.diagnostic.failureClassification,
            .recoveryDecisionRequired
        )
        XCTAssertEqual(decision.diagnostic.recoveryRequiredCount, 2)
        XCTAssertEqual(decision.diagnostic.exceptionCount, 7)
        XCTAssertEqual(decision.diagnostic.exceptionOverflowCount, 3)
        assertTargetRemainsInactive(decision)
    }

    func test16PromotionOrTargetActivationEvidenceFailsClosed() {
        let promotion = evaluate(
            .migrationCompleted(
                validCompletion(promotionAuthorized: true)
            )
        )
        XCTAssertEqual(promotion.state, .recoveryRequired)
        XCTAssertEqual(
            promotion.diagnostic.failureClassification,
            .unauthorizedPromotion
        )

        let activation = evaluate(
            .migrationCompleted(
                validCompletion(targetSchemaActivated: true)
            )
        )
        XCTAssertEqual(activation.state, .recoveryRequired)
        XCTAssertEqual(
            activation.diagnostic.failureClassification,
            .unauthorizedTargetActivation
        )
        assertTargetRemainsInactive(promotion)
        assertTargetRemainsInactive(activation)
    }

    func test17DiagnosticsAreBoundedAndContainNoPrivatePayload() throws {
        let privateSentinels = [
            "Private Product", "1234567890123", "Private note",
            "31.778", "credential", "account-id", "raw-store-row"
        ]
        let decision = evaluate(
            .migrationCompleted(
                validCompletion(
                    recoveryRequiredCount: -4,
                    exceptionCount: -9,
                    exceptionOverflowCount: -2,
                    candidateArtifactCount: -7
                )
            )
        )
        let data = try JSONEncoder().encode(decision.diagnostic)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(decision.diagnostic.recoveryRequiredCount, 0)
        XCTAssertEqual(decision.diagnostic.exceptionCount, 0)
        XCTAssertEqual(decision.diagnostic.exceptionOverflowCount, 0)
        XCTAssertEqual(decision.diagnostic.candidateArtifactCount, 0)
        for sentinel in privateSentinels {
            XCTAssertFalse(encoded.contains(sentinel), sentinel)
        }
    }

    func test18ExplicitTraceDoesNotOpenRepairOrQuarantineProtectedV3()
        throws
    {
        let gateContainer = try makeInMemoryContainer()
        var defaultOpenCount = 0
        var repairCount = 0
        var quarantineCount = 0
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                defaultOpenCount += 1
                return gateContainer
            },
            openInMemoryStore: { gateContainer },
            repairStore: { _ in
                repairCount += 1
                return 0
            },
            quarantineStore: {
                quarantineCount += 1
                return 0
            },
            reportDiagnostic: { diagnostics.append($0) },
            developerAssertion: { _ in },
            migrationTraceProvider: { .migrationRequired }
        )

        let result = try bootstrap.start()

        XCTAssertEqual(result.mode, .startupGate)
        XCTAssertEqual(
            result.migrationGateDecision.state,
            .migrationRequired
        )
        XCTAssertEqual(defaultOpenCount, 0)
        XCTAssertEqual(repairCount, 0)
        XCTAssertEqual(quarantineCount, 0)
        XCTAssertEqual(diagnostics.map(\.stage), [.migrationGate])
        XCTAssertEqual(diagnostics.map(\.outcome), [.degraded])
    }

    func test19GatePresentationFailureIsDeterministicAndDoesNotTouchSource() {
        enum SyntheticFailure: Error { case unavailable }
        var defaultOpenCount = 0
        var repairCount = 0
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                defaultOpenCount += 1
                throw SyntheticFailure.unavailable
            },
            openInMemoryStore: { throw SyntheticFailure.unavailable },
            repairStore: { _ in
                repairCount += 1
                return 0
            },
            quarantineStore: {
                XCTFail("Gate failure must not quarantine the source")
                return 0
            },
            reportDiagnostic: { diagnostics.append($0) },
            developerAssertion: { _ in },
            migrationTraceProvider: { .migrationRunning }
        )

        XCTAssertThrowsError(try bootstrap.start()) { error in
            guard case WayTaskStartupPersistenceError
                .migrationGateUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(defaultOpenCount, 0)
        XCTAssertEqual(repairCount, 0)
        XCTAssertEqual(
            diagnostics.map(\.stage),
            [.migrationGate, .migrationGate]
        )
        XCTAssertEqual(diagnostics.map(\.outcome), [.degraded, .fatal])
    }

    func test20NormalBootstrapExposesPersistentStartupReadyDecision()
        throws
    {
        let container = try makeInMemoryContainer()
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: { container },
            openInMemoryStore: { container },
            repairStore: { _ in 0 },
            quarantineStore: { 0 },
            reportDiagnostic: { diagnostics.append($0) },
            developerAssertion: { _ in }
        )

        let result = try bootstrap.start()

        XCTAssertEqual(result.mode, .persistent)
        XCTAssertEqual(result.migrationGateDecision.state, .startupReady)
        XCTAssertTrue(
            result.migrationGateDecision
                .allowsLegacyV3ApplicationContent
        )
        XCTAssertTrue(diagnostics.isEmpty)
        assertTargetRemainsInactive(result.migrationGateDecision)
    }

    func test21RecreatedAndInMemoryBootstrapResultsBlockAppContent()
        throws
    {
        enum SyntheticFailure: Error { case open; case recreate }
        let container = try makeInMemoryContainer()
        var recreateAttempts = 0
        let recreated = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                recreateAttempts += 1
                if recreateAttempts == 1 { throw SyntheticFailure.open }
                return container
            },
            openInMemoryStore: { container },
            repairStore: { _ in 0 },
            quarantineStore: { 1 },
            reportDiagnostic: { _ in },
            developerAssertion: { _ in }
        )
        let recreatedResult = try recreated.start()
        XCTAssertEqual(
            recreatedResult.migrationGateDecision.state,
            .recoveryRequired
        )
        XCTAssertFalse(
            recreatedResult.migrationGateDecision
                .allowsLegacyV3ApplicationContent
        )

        var fallbackAttempts = 0
        let fallback = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                fallbackAttempts += 1
                throw fallbackAttempts == 1
                    ? SyntheticFailure.open : SyntheticFailure.recreate
            },
            openInMemoryStore: { container },
            repairStore: { _ in 0 },
            quarantineStore: { 1 },
            reportDiagnostic: { _ in },
            developerAssertion: { _ in }
        )
        let fallbackResult = try fallback.start()
        XCTAssertEqual(
            fallbackResult.migrationGateDecision.state,
            .degradedMode
        )
        XCTAssertFalse(
            fallbackResult.migrationGateDecision
                .allowsLegacyV3ApplicationContent
        )
    }

    func test22ProductionSourcesHaveNoPromotionV4OrRootBackfill() throws {
        let root = repositoryRoot()
        let startup = try source(
            root.appendingPathComponent(
                "WayTask/Persistence/WayTaskStartupPersistence.swift"
            )
        )
        let app = try source(
            root.appendingPathComponent("WayTask/WayTaskApp.swift")
        )
        let content = try source(
            root.appendingPathComponent("WayTask/ContentView.swift")
        )

        for forbidden in [
            "replacePersistentStore", "destroyPersistentStore",
            "migrateProductListSemantics(",
            "migrateSessionHistoryArchiveSemantics(",
            "WayTaskSchemaV4", "inactiveTargetProductStateSchema"
        ] {
            XCTAssertFalse(startup.contains(forbidden), forbidden)
            XCTAssertFalse(app.contains(forbidden), forbidden)
            XCTAssertFalse(content.contains(forbidden), forbidden)
        }
        XCTAssertFalse(app.contains("fatalError"))
        XCTAssertFalse(content.contains("ShoppingListBackfillService"))
        XCTAssertFalse(content.contains("ensureDefaultListsAndBackfill"))
        XCTAssertFalse(content.contains("shoppingItemCatalogResolver.hydrate"))
        XCTAssertTrue(startup.contains("writableTargetAccessAuthorized: Bool { false }"))
        XCTAssertTrue(startup.contains("candidatePromotionAuthorized: Bool { false }"))
    }

    private func evaluate(
        _ trace: WayTaskStartupMigrationTrace
    ) -> WayTaskStartupMigrationGateDecision {
        gate.evaluate(persistenceMode: .startupGate, trace: trace)
    }

    private func verifiedRecovery()
        -> WayTaskStartupMigrationRecoveryEvidence
    {
        WayTaskStartupMigrationRecoveryEvidence(
            protectedOriginalVerified: true,
            rollbackVerified: true,
            candidateArtifactsRemain: false
        )
    }

    private func validCompletion(
        migrationComplete: Bool = true,
        candidateIntegrityVerified: Bool = true,
        sourceFingerprintVerified: Bool = true,
        candidateFingerprintVerified: Bool = true,
        candidateReopenVerified: Bool = true,
        protectedOriginalVerified: Bool = true,
        rollbackStateVerified: Bool = true,
        recoveryRequiredCount: Int = 0,
        exceptionCount: Int = 0,
        exceptionOverflowCount: Int = 0,
        candidateArtifactCount: Int = 7,
        promotionAuthorized: Bool = false,
        targetSchemaActivated: Bool = false
    ) -> WayTaskStartupMigrationCompletionEvidence {
        WayTaskStartupMigrationCompletionEvidence(
            migrationComplete: migrationComplete,
            candidateIntegrityVerified: candidateIntegrityVerified,
            sourceFingerprintVerified: sourceFingerprintVerified,
            candidateFingerprintVerified: candidateFingerprintVerified,
            candidateReopenVerified: candidateReopenVerified,
            protectedOriginalVerified: protectedOriginalVerified,
            rollbackStateVerified: rollbackStateVerified,
            recoveryRequiredCount: recoveryRequiredCount,
            exceptionCount: exceptionCount,
            exceptionOverflowCount: exceptionOverflowCount,
            candidateArtifactCount: candidateArtifactCount,
            promotionAuthorized: promotionAuthorized,
            targetSchemaActivated: targetSchemaActivated
        )
    }

    private func assertTargetRemainsInactive(
        _ decision: WayTaskStartupMigrationGateDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            decision.writableTargetAccessAuthorized,
            file: file,
            line: line
        )
        XCTAssertFalse(
            decision.targetUIActivationAuthorized,
            file: file,
            line: line
        )
        XCTAssertFalse(
            decision.candidatePromotionAuthorized,
            file: file,
            line: line
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try WayTaskModelContainer.makeInMemory()
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
