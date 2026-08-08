import CryptoKit
import Combine
import Foundation
import SwiftData

struct GuestMigrationReceipt: Codable, Equatable, Sendable {
    let batchID: String
    let sequence: Int
    let payloadSHA256: String
    let recordCount: Int

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case sequence
        case payloadSHA256 = "payload_sha256"
        case recordCount = "record_count"
    }
}

struct GuestMigrationVerification: Codable, Equatable, Sendable {
    let targetUserID: UUID
    let datasetFingerprint: String
    let counts: GuestMigrationCounts
    let acknowledgedBatchIDs: [String]
    let parentChildIntegrityVerified: Bool
    let excludedDataAbsent: Bool

    enum CodingKeys: String, CodingKey {
        case targetUserID = "target_user_id"
        case datasetFingerprint = "dataset_fingerprint"
        case counts
        case acknowledgedBatchIDs = "acknowledged_batch_ids"
        case parentChildIntegrityVerified =
            "parent_child_integrity_verified"
        case excludedDataAbsent = "excluded_data_absent"
    }
}

struct GuestMigrationLedger: Codable, Equatable, Sendable {
    var manifest: GuestMigrationManifest
    var execution: GuestMigrationExecution
    var receipts: [GuestMigrationReceipt]
    var remoteAttemptCreated: Bool
}

protocol GuestMigrationLedgerPersisting: AnyObject {
    func load() throws -> GuestMigrationLedger?
    func save(_ ledger: GuestMigrationLedger) throws
    func clear() throws
}

private final class UnavailableGuestMigrationLedgerStore:
    GuestMigrationLedgerPersisting {
    func load() throws -> GuestMigrationLedger? {
        throw GuestMigrationFoundationError.localPersistenceFailure
    }

    func save(_ ledger: GuestMigrationLedger) throws {
        throw GuestMigrationFoundationError.localPersistenceFailure
    }

    func clear() throws {
        throw GuestMigrationFoundationError.localPersistenceFailure
    }
}

final class ProtectedGuestMigrationLedgerStore:
    GuestMigrationLedgerPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) throws
        -> ProtectedGuestMigrationLedgerStore {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return ProtectedGuestMigrationLedgerStore(
            fileURL: root
                .appendingPathComponent("WayTaskMigration", isDirectory: true)
                .appendingPathComponent("guest-account-v1.ledger"),
            fileManager: fileManager
        )
    }

    func load() throws -> GuestMigrationLedger? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(
            GuestMigrationLedger.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ ledger: GuestMigrationLedger) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let data = try GuestMigrationCanonicalizer.data(for: ledger)
        let temporary = directory.appendingPathComponent(
            ".\(UUID().uuidString).tmp"
        )
        do {
            try data.write(
                to: temporary,
                options: [.atomic, .completeFileProtection]
            )
            try protect(temporary)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: temporary
                )
            } else {
                try fileManager.moveItem(at: temporary, to: fileURL)
            }
            try protect(fileURL)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func protect(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600,
             .protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        guard permissions.map({ $0 & 0o777 }) == 0o600 else {
            throw GuestMigrationFoundationError.localPersistenceFailure
        }
    }
}

protocol GuestMigrationTransport: Sendable {
    func begin(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws
    func upload(
        attemptID: UUID,
        batchID: String,
        plan: GuestMigrationBatchPlan,
        payload: Data
    ) async throws -> GuestMigrationReceipt
    func verify(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws -> GuestMigrationVerification
    func rollback(attemptID: UUID) async throws
}

struct DisabledGuestMigrationTransport: GuestMigrationTransport {
    func begin(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws {
        throw GuestMigrationFoundationError.activationBlocked(.featureDisabled)
    }

    func upload(
        attemptID: UUID,
        batchID: String,
        plan: GuestMigrationBatchPlan,
        payload: Data
    ) async throws -> GuestMigrationReceipt {
        throw GuestMigrationFoundationError.activationBlocked(.featureDisabled)
    }

    func verify(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws -> GuestMigrationVerification {
        throw GuestMigrationFoundationError.activationBlocked(.featureDisabled)
    }

    func rollback(attemptID: UUID) async throws {
        throw GuestMigrationFoundationError.activationBlocked(.featureDisabled)
    }
}

enum GuestMigrationActivationConfiguration {
    static let schemaVersionKey = "WAYTASK_MIGRATION_SCHEMA_VERSION"
    static let endpointEnabledKey = "WAYTASK_MIGRATION_ENDPOINT_ENABLED"
    static let signedSessionABGateKey =
        "WAYTASK_SIGNED_SESSION_AB_GATE_PASSED"
    static let sessionRecoveryGateKey =
        "WAYTASK_SESSION_RECOVERY_GATE_PASSED"
    static let blockersClearKey =
        "WAYTASK_MIGRATION_SECURITY_BLOCKERS_CLEAR"

    static func evidence(
        values: [String: String],
        environment: WayTaskCloudEnvironment?,
        compiledForInternalStaging: Bool,
        authenticatedUserID: UUID?,
        migrationFeatureEnabled: Bool
    ) -> GuestMigrationActivationEvidence {
        GuestMigrationActivationEvidence(
            environment: environment,
            compiledForInternalStaging: compiledForInternalStaging,
            authenticatedUserID: authenticatedUserID,
            migrationFeatureEnabled: migrationFeatureEnabled,
            schemaVersion: Int(normalized(values[schemaVersionKey]) ?? "") ?? 0,
            endpointConfigured: enabled(values[endpointEnabledKey]),
            signedSessionABGatePassed: enabled(values[signedSessionABGateKey]),
            sessionRecoveryGatePassed:
                enabled(values[sessionRecoveryGateKey]),
            securityBlockersClear: enabled(values[blockersClearKey])
        )
    }

    static func evidence(
        bundle: Bundle = .main,
        environment: WayTaskCloudEnvironment?,
        compiledForInternalStaging: Bool,
        authenticatedUserID: UUID?,
        migrationFeatureEnabled: Bool
    ) -> GuestMigrationActivationEvidence {
        var values: [String: String] = [:]
        for (key, value) in bundle.infoDictionary ?? [:] {
            if let value = value as? String { values[key] = value }
        }
        return evidence(
            values: values,
            environment: environment,
            compiledForInternalStaging: compiledForInternalStaging,
            authenticatedUserID: authenticatedUserID,
            migrationFeatureEnabled: migrationFeatureEnabled
        )
    }

    private static func enabled(_ value: String?) -> Bool {
        switch normalized(value)?.lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let result = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !result.isEmpty, !result.contains("$(") else { return nil }
        return result
    }
}

@MainActor
final class GuestMigrationCoordinator: ObservableObject {
    @Published private(set) var state: GuestMigrationState = .guestLocal
    @Published private(set) var preview: GuestMigrationManifest?
    @Published private(set) var lastError: GuestMigrationFoundationError?

    private let modelContainer: ModelContainer
    private let localDataSetID: UUID
    private let ledgerStore: GuestMigrationLedgerPersisting
    private let transport: GuestMigrationTransport
    private let manifestBuilder: GuestMigrationManifestBuilder
    private var ledger: GuestMigrationLedger?

    init(
        modelContainer: ModelContainer,
        localDataSetID: UUID,
        ledgerStore: GuestMigrationLedgerPersisting,
        transport: GuestMigrationTransport
    ) {
        self.modelContainer = modelContainer
        self.localDataSetID = localDataSetID
        self.ledgerStore = ledgerStore
        self.transport = transport
        manifestBuilder = GuestMigrationManifestBuilder()
        do {
            ledger = try ledgerStore.load()
            if let ledger {
                preview = ledger.manifest
                state = ledger.execution.state
            }
        } catch {
            state = .migrationBlocked
            lastError = .localPersistenceFailure
        }
    }

    static func live(
        modelContainer: ModelContainer,
        localDataSetID: UUID,
        transport: GuestMigrationTransport
    ) -> GuestMigrationCoordinator {
        let store: GuestMigrationLedgerPersisting
        do {
            store = try ProtectedGuestMigrationLedgerStore.live()
        } catch {
            store = UnavailableGuestMigrationLedgerStore()
        }
        return GuestMigrationCoordinator(
            modelContainer: modelContainer,
            localDataSetID: localDataSetID,
            ledgerStore: store,
            transport: transport
        )
    }

    func reconcile(session: AccountSessionSnapshot) {
        switch session.authentication {
        case .guest:
            if ledger == nil { state = .guestLocal }
        case let .signedIn(identity, _):
            if let bound = boundTargetUserID, bound != identity.userID {
                state = .migrationConflict
                lastError = .accountConflict
            } else if boundTargetUserID != nil,
                      !ownershipMatches(
                        session.localDataOwnership,
                        targetUserID: identity.userID
                      ) {
                state = .migrationConflict
                lastError = .accountConflict
            } else if ledger == nil {
                if case .guestOnly = session.localDataOwnership {
                    state = .authenticatedLocalUnlinked
                } else {
                    state = .migrationRecoverable
                    lastError = .localPersistenceFailure
                }
            }
        case .sessionExpired:
            if ledger != nil {
                state = .migrationRecoverable
                lastError = .sessionExpired
            }
        case .signingIn, .deletionPending:
            break
        }
    }

    @discardableResult
    func makePreview(targetUserID: UUID) throws -> GuestMigrationManifest {
        do {
            try assertTarget(targetUserID)
            let manifest = try manifestBuilder.build(
                modelContainer: modelContainer,
                localDataSetID: localDataSetID,
                targetUserID: targetUserID
            )
            preview = manifest
            state = .migrationPreviewAvailable
            lastError = nil
            return manifest
        } catch let failure as GuestMigrationFoundationError {
            let failureState: GuestMigrationState = failure == .accountConflict
                ? .migrationConflict : .migrationBlocked
            throw fail(failure, state: failureState)
        } catch {
            throw fail(.invalidLocalDataset, state: .migrationBlocked)
        }
    }

    func requireConsent() {
        guard preview != nil else { return }
        state = .migrationConsentRequired
    }

    func consentAndPrepare(
        fingerprint: String,
        targetUserID: UUID,
        activation: GuestMigrationActivationEvidence,
        bindAccount: () -> Bool,
        attemptID: UUID = UUID()
    ) throws {
        try assertActivation(activation, targetUserID: targetUserID)
        try assertTarget(targetUserID)
        guard let preview, preview.datasetFingerprint == fingerprint else {
            throw fail(.consentRequired, state: .migrationConsentRequired)
        }
        let current = try manifestBuilder.build(
            modelContainer: modelContainer,
            localDataSetID: localDataSetID,
            targetUserID: targetUserID
        )
        guard current.datasetFingerprint == fingerprint else {
            self.preview = current
            throw fail(.previewChanged, state: .migrationPreviewAvailable)
        }
        guard bindAccount() else {
            throw fail(.accountConflict, state: .migrationConflict)
        }
        let execution = GuestMigrationExecution(
            attemptID: attemptID,
            targetUserID: targetUserID,
            datasetFingerprint: fingerprint,
            consentedFingerprint: fingerprint,
            acknowledgedBatchIDs: [],
            retryCount: 0,
            state: .migrationPreparing
        )
        let newLedger = GuestMigrationLedger(
            manifest: current,
            execution: execution,
            receipts: [],
            remoteAttemptCreated: false
        )
        try persist(newLedger)
        state = .migrationPreparing
        lastError = nil
    }

    func execute(
        targetUserID: UUID,
        activation: GuestMigrationActivationEvidence,
        localOwnership: LocalDataOwnershipState,
        markCompleted: () -> Bool
    ) async throws {
        do {
            try await executePrepared(
                targetUserID: targetUserID,
                activation: activation,
                localOwnership: localOwnership,
                markCompleted: markCompleted
            )
        } catch let failure as GuestMigrationFoundationError {
            try? markInterrupted(failure)
            throw failure
        } catch {
            try? markInterrupted(.serviceUnavailable)
            throw GuestMigrationFoundationError.serviceUnavailable
        }
    }

    private func executePrepared(
        targetUserID: UUID,
        activation: GuestMigrationActivationEvidence,
        localOwnership: LocalDataOwnershipState,
        markCompleted: () -> Bool
    ) async throws {
        try assertActivation(activation, targetUserID: targetUserID)
        try assertTarget(targetUserID)
        guard ownershipMatches(
            localOwnership,
            targetUserID: targetUserID
        ) else { throw fail(.accountConflict, state: .migrationConflict) }
        guard var ledger,
              ledger.execution.consentedFingerprint ==
                ledger.manifest.datasetFingerprint
        else { throw fail(.consentRequired, state: .migrationConsentRequired) }

        if !ledger.remoteAttemptCreated {
            let current = try manifestBuilder.build(
                modelContainer: modelContainer,
                localDataSetID: localDataSetID,
                targetUserID: targetUserID
            )
            guard current.datasetFingerprint ==
                    ledger.manifest.datasetFingerprint else {
                preview = current
                throw fail(.previewChanged, state: .migrationPreviewAvailable)
            }
            try await transport.begin(
                attemptID: ledger.execution.attemptID,
                manifest: ledger.manifest
            )
            ledger.remoteAttemptCreated = true
            ledger.execution = replacingExecution(
                ledger.execution,
                state: .migrationUploading
            )
            try persist(ledger)
        }

        state = .migrationUploading
        for batch in ledger.manifest.batches.sorted(by: {
            $0.sequence < $1.sequence
        }) {
            let batchID = GuestMigrationCanonicalizer.batchID(
                attemptID: ledger.execution.attemptID,
                batch: batch
            )
            if ledger.execution.acknowledgedBatchIDs.contains(batchID) {
                continue
            }
            try assertBatchOrder(batch, ledger: ledger)
            let payload = try GuestMigrationPayloadFactory.payload(
                manifest: ledger.manifest,
                batch: batch
            )
            let receipt = try await transport.upload(
                attemptID: ledger.execution.attemptID,
                batchID: batchID,
                plan: batch,
                payload: payload
            )
            guard receipt == GuestMigrationReceipt(
                batchID: batchID,
                sequence: batch.sequence,
                payloadSHA256: batch.payloadSHA256,
                recordCount: batch.recordCount
            ) else { throw fail(.receiptMismatch, state: .migrationConflict) }
            ledger.receipts.append(receipt)
            ledger.execution = replacingExecution(
                ledger.execution,
                acknowledgedBatchIDs:
                    ledger.execution.acknowledgedBatchIDs + [batchID]
            )
            try persist(ledger)
        }

        state = .migrationVerifying
        ledger.execution = replacingExecution(
            ledger.execution,
            state: .migrationVerifying
        )
        try persist(ledger)
        let verification = try await transport.verify(
            attemptID: ledger.execution.attemptID,
            manifest: ledger.manifest
        )
        guard verification.targetUserID == targetUserID,
              verification.datasetFingerprint ==
                ledger.manifest.datasetFingerprint,
              verification.counts == ledger.manifest.dataset.counts,
              Set(verification.acknowledgedBatchIDs) ==
                Set(ledger.execution.acknowledgedBatchIDs),
              verification.parentChildIntegrityVerified,
              verification.excludedDataAbsent
        else { throw fail(.verificationFailed, state: .migrationRollbackRequired) }
        guard markCompleted() else {
            throw fail(.localPersistenceFailure, state: .migrationRecoverable)
        }
        ledger.execution = replacingExecution(
            ledger.execution,
            state: .migrationCompleted
        )
        try persist(ledger)
        state = .migrationCompleted
        lastError = nil
    }

    func cancelBeforeUpload() throws {
        guard var ledger, !ledger.remoteAttemptCreated,
              ledger.receipts.isEmpty else {
            throw fail(.verificationFailed, state: .migrationRollbackRequired)
        }
        ledger.execution = GuestMigrationExecution(
            attemptID: ledger.execution.attemptID,
            targetUserID: ledger.execution.targetUserID,
            datasetFingerprint: ledger.execution.datasetFingerprint,
            consentedFingerprint: nil,
            acknowledgedBatchIDs: [],
            retryCount: ledger.execution.retryCount,
            state: .migrationConsentRequired
        )
        try persist(ledger)
        state = .migrationConsentRequired
    }

    func markInterrupted(_ error: GuestMigrationFoundationError) throws {
        guard var ledger else { return }
        let interruptedState: GuestMigrationState
        switch error {
        case .accountConflict, .receiptMismatch, .batchOrderViolation:
            interruptedState = .migrationConflict
        case .verificationFailed:
            interruptedState = .migrationRollbackRequired
        case .activationBlocked, .localPersistenceFailure,
             .invalidLocalDataset, .unsupportedLocalValue,
             .oversizedBatch:
            interruptedState = .migrationBlocked
        case .previewChanged:
            interruptedState = .migrationPreviewAvailable
        case .consentRequired:
            interruptedState = .migrationConsentRequired
        case .sessionExpired:
            interruptedState = .migrationRecoverable
        case .notAuthenticated, .offline, .serviceUnavailable:
            interruptedState = .migrationInterrupted
        }
        ledger.execution = replacingExecution(
            ledger.execution,
            retryCount: ledger.execution.retryCount + 1,
            state: interruptedState
        )
        try persist(ledger)
        state = ledger.execution.state
        lastError = error
    }

    func rollbackBeforeCompletion(
        targetUserID: UUID,
        activation: GuestMigrationActivationEvidence,
        localOwnership: LocalDataOwnershipState
    ) async throws {
        try assertActivation(activation, targetUserID: targetUserID)
        try assertTarget(targetUserID)
        guard ownershipMatches(
            localOwnership,
            targetUserID: targetUserID
        ) else { throw fail(.accountConflict, state: .migrationConflict) }
        guard var ledger,
              ledger.execution.state != .migrationCompleted else {
            throw fail(.verificationFailed, state: .migrationRollbackRequired)
        }
        if ledger.remoteAttemptCreated {
            try await transport.rollback(attemptID: ledger.execution.attemptID)
        }
        ledger.receipts = []
        ledger.remoteAttemptCreated = false
        ledger.execution = GuestMigrationExecution(
            attemptID: ledger.execution.attemptID,
            targetUserID: ledger.execution.targetUserID,
            datasetFingerprint: ledger.execution.datasetFingerprint,
            consentedFingerprint: nil,
            acknowledgedBatchIDs: [],
            retryCount: ledger.execution.retryCount,
            state: .migrationConsentRequired
        )
        try persist(ledger)
        preview = ledger.manifest
        state = .migrationConsentRequired
        lastError = nil
    }

    var boundTargetUserID: UUID? { ledger?.execution.targetUserID }

    var canCancelBeforeUpload: Bool {
        guard let ledger else { return false }
        return !ledger.remoteAttemptCreated && ledger.receipts.isEmpty &&
            ledger.execution.state != .migrationCompleted
    }

    private func assertActivation(
        _ activation: GuestMigrationActivationEvidence,
        targetUserID: UUID
    ) throws {
        guard activation.authenticatedUserID == targetUserID else {
            throw fail(.accountConflict, state: .migrationConflict)
        }
        if let blocker = activation.blocker() {
            throw fail(
                .activationBlocked(blocker),
                state: .migrationBlocked
            )
        }
    }

    private func assertTarget(_ targetUserID: UUID) throws {
        if let target = boundTargetUserID, target != targetUserID {
            throw fail(.accountConflict, state: .migrationConflict)
        }
    }

    private func ownershipMatches(
        _ ownership: LocalDataOwnershipState,
        targetUserID: UUID
    ) -> Bool {
        switch ownership {
        case .guestOnly:
            return false
        case let .migrationPending(dataSetID, ownerUserID),
             let .linked(dataSetID, ownerUserID):
            return dataSetID == localDataSetID && ownerUserID == targetUserID
        }
    }

    private func assertBatchOrder(
        _ batch: GuestMigrationBatchPlan,
        ledger: GuestMigrationLedger
    ) throws {
        let unfinishedEarlier = ledger.manifest.batches.contains { candidate in
            guard candidate.sequence < batch.sequence else { return false }
            let candidateID = GuestMigrationCanonicalizer.batchID(
                attemptID: ledger.execution.attemptID,
                batch: candidate
            )
            return !ledger.execution.acknowledgedBatchIDs.contains(candidateID)
        }
        guard !unfinishedEarlier else {
            throw fail(.batchOrderViolation, state: .migrationConflict)
        }
    }

    private func persist(_ value: GuestMigrationLedger) throws {
        do {
            try ledgerStore.save(value)
            ledger = value
        } catch {
            throw fail(.localPersistenceFailure, state: .migrationBlocked)
        }
    }

    private func fail(
        _ error: GuestMigrationFoundationError,
        state: GuestMigrationState
    ) -> GuestMigrationFoundationError {
        self.state = state
        lastError = error
        return error
    }

    private func replacingExecution(
        _ value: GuestMigrationExecution,
        acknowledgedBatchIDs: [String]? = nil,
        retryCount: Int? = nil,
        state: GuestMigrationState? = nil
    ) -> GuestMigrationExecution {
        GuestMigrationExecution(
            attemptID: value.attemptID,
            targetUserID: value.targetUserID,
            datasetFingerprint: value.datasetFingerprint,
            consentedFingerprint: value.consentedFingerprint,
            acknowledgedBatchIDs:
                acknowledgedBatchIDs ?? value.acknowledgedBatchIDs,
            retryCount: retryCount ?? value.retryCount,
            state: state ?? value.state
        )
    }
}

enum GuestMigrationPayloadFactory {
    static func payload(
        manifest: GuestMigrationManifest,
        batch: GuestMigrationBatchPlan
    ) throws -> Data {
        let prior = manifest.batches.filter {
            $0.entityKind == batch.entityKind && $0.sequence < batch.sequence
        }.reduce(0) { $0 + $1.recordCount }
        let range = prior..<(prior + batch.recordCount)
        let payload: Data
        switch batch.entityKind {
        case .personalProducts:
            payload = try GuestMigrationCanonicalizer.data(
                for: Array(manifest.dataset.personalProducts[range])
            )
        case .shoppingLists:
            payload = try GuestMigrationCanonicalizer.data(
                for: Array(manifest.dataset.shoppingLists[range])
            )
        case .shoppingListEntries:
            payload = try GuestMigrationCanonicalizer.data(
                for: Array(manifest.dataset.shoppingListEntries[range])
            )
        }
        guard payload.count == batch.payloadByteCount,
              SHA256Digest.hex(payload) == batch.payloadSHA256 else {
            throw GuestMigrationFoundationError.receiptMismatch
        }
        return payload
    }
}

private enum SHA256Digest {
    static func hex(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
