import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class WayTaskProductStateMigrationFoundationTests: XCTestCase {
    private let attemptSeed = UUID(
        uuidString: "06060606-0000-0000-0000-000000000006"
    )!

    func testStageAndAttemptIdentityAreDeterministicAndSchemaExact() {
        let sourceFingerprint = WayTaskMigrationFingerprint(
            rawValue: String(repeating: "a", count: 64)
        )
        for sourceSchema in [
            WayTaskMigrationSchemaIdentity.v1,
            .v2,
            .v3
        ] {
            let firstStage = WayTaskMigrationStageIdentity(
                sourceSchema: sourceSchema
            )
            let secondStage = WayTaskMigrationStageIdentity(
                sourceSchema: sourceSchema
            )
            let firstAttempt = WayTaskMigrationAttemptIdentity(
                stageIdentity: firstStage,
                sourceFingerprint: sourceFingerprint,
                attemptSeed: attemptSeed
            )
            let secondAttempt = WayTaskMigrationAttemptIdentity(
                stageIdentity: secondStage,
                sourceFingerprint: sourceFingerprint,
                attemptSeed: attemptSeed
            )

            XCTAssertEqual(firstStage, secondStage)
            XCTAssertEqual(firstStage.sourceSchema, sourceSchema)
            XCTAssertEqual(firstStage.candidateSchema, .v3)
            XCTAssertEqual(firstStage.rawValue.count, 64)
            XCTAssertEqual(firstAttempt, secondAttempt)
            XCTAssertEqual(firstAttempt.rawValue.count, 64)
        }

        XCTAssertNotEqual(
            WayTaskMigrationStageIdentity(sourceSchema: .v1),
            WayTaskMigrationStageIdentity(sourceSchema: .v2)
        )
    }

    func testSourceInventoryIncludesExactStoreWALAndSHMSidecars() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let walURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-shm")
        try Data([0x57, 0x41, 0x4c]).write(to: walURL)
        try Data([0x53, 0x48, 0x4d]).write(to: shmURL)

        var dependencies = WayTaskProductStateMigrationDependencies.live
        dependencies.physicalMigrateCandidate = { _ in }
        dependencies.reopenCandidate = { _ in Self.validCandidateSnapshot() }
        let result = WayTaskProductStateMigration(
            dependencies: dependencies
        ).prepareCandidate(fixture.request(seed: attemptSeed))
        let receipt = try unwrapReceipt(result)
        defer {
            _ = WayTaskProductStateMigration(
                dependencies: dependencies
            ).cleanupOwnedCandidate(receipt)
        }

        XCTAssertEqual(
            receipt.sourceInventory.componentRoles,
            [.database, .writeAheadLog, .sharedMemory]
        )
        XCTAssertEqual(receipt.sourceInventory.components[1].byteCount, 3)
        XCTAssertEqual(receipt.sourceInventory.components[2].byteCount, 3)
        XCTAssertTrue(
            receipt.ownedArtifactNames.contains("candidate.store-wal")
        )
        XCTAssertTrue(
            receipt.ownedArtifactNames.contains("candidate.store-shm")
        )
    }

    func testSourceFingerprintIsStableAndChangesWithAnySidecarByte() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let walURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-shm")
        try Data([0x01]).write(to: walURL)
        try Data([0x02]).write(to: shmURL)
        let inspect = WayTaskProductStateMigrationDependencies.live.inspectStore

        let first = try inspect(fixture.sourceStoreURL)
        let second = try inspect(fixture.sourceStoreURL)
        XCTAssertEqual(first.fingerprint, second.fingerprint)

        try Data([0x03]).write(to: shmURL)
        let changed = try inspect(fixture.sourceStoreURL)
        XCTAssertNotEqual(first.fingerprint, changed.fingerprint)
    }

    func testCandidateLocationIsIsolatedOwnedAndNeverDefault() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let migration = WayTaskProductStateMigration()
        let receipt = try unwrapReceipt(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        defer { _ = migration.cleanupOwnedCandidate(receipt) }

        XCTAssertEqual(
            receipt.candidateAttemptDirectoryURL
                .deletingLastPathComponent().standardizedFileURL,
            fixture.candidateRootURL.standardizedFileURL
        )
        XCTAssertTrue(
            receipt.candidateAttemptDirectoryURL.lastPathComponent
                .hasPrefix(WayTaskProductStateMigration.attemptDirectoryPrefix)
        )
        XCTAssertEqual(
            receipt.candidateStoreURL.lastPathComponent,
            WayTaskProductStateMigration.candidateStoreFilename
        )
        XCTAssertNotEqual(
            receipt.candidateStoreURL.standardizedFileURL,
            fixture.sourceStoreURL.standardizedFileURL
        )
        XCTAssertNotEqual(
            receipt.candidateStoreURL.standardizedFileURL,
            ModelConfiguration().url.standardizedFileURL
        )
        XCTAssertTrue(
            receipt.ownedArtifactNames.contains(
                WayTaskProductStateMigration.ownerMarkerFilename
            )
        )
        XCTAssertFalse(receipt.promotionAuthorized)
    }

    func testV1CandidatePhysicallyMigratesToV3AndReopens() throws {
        try assertPhysicalMigration(from: .v1)
    }

    func testV2CandidatePhysicallyMigratesToV3AndReopens() throws {
        try assertPhysicalMigration(from: .v2)
    }

    func testV3CandidatePhysicallyMigratesToV3AndReopens() throws {
        try assertPhysicalMigration(from: .v3)
    }

    func testCandidateFingerprintIsStableAfterValidatedReopen() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let migration = WayTaskProductStateMigration()
        let receipt = try unwrapReceipt(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        defer { _ = migration.cleanupOwnedCandidate(receipt) }

        let inspected = try WayTaskProductStateMigrationDependencies.live
            .inspectStore(receipt.candidateStoreURL)
        XCTAssertEqual(receipt.candidateFingerprint, inspected.fingerprint)
        XCTAssertEqual(receipt.status, .foundationValidated)
        XCTAssertEqual(
            receipt.completion,
            .candidateReadyForSemanticMigration
        )
    }

    func testExceptionCategoriesAreDeterministicBoundedAndPreserveOverflow()
        throws
    {
        var ledger = WayTaskMigrationExceptionLedger(capacity: 2)
        let first = WayTaskMigrationSafeDigest(
            hashing: Data("synthetic-id-1".utf8)
        )
        let second = WayTaskMigrationSafeDigest(
            hashing: Data("synthetic-id-2".utf8)
        )
        let third = WayTaskMigrationSafeDigest(
            hashing: Data("synthetic-id-3".utf8)
        )

        ledger.record(category: .ambiguousRecord, safeEvidenceDigest: first)
        ledger.record(category: .unsupportedRecord, safeEvidenceDigest: second)
        ledger.record(category: .ambiguousRecord, safeEvidenceDigest: first)
        ledger.record(category: .unresolvedSessionLine, safeEvidenceDigest: third)

        XCTAssertEqual(ledger.entries.map(\.ordinal), [1, 2])
        XCTAssertEqual(ledger.entries[0].occurrenceCount, 2)
        XCTAssertEqual(ledger.summary.totalOccurrenceCount, 4)
        XCTAssertEqual(ledger.summary.recordedEntryCount, 2)
        XCTAssertEqual(ledger.summary.overflowOccurrenceCount, 1)
        XCTAssertEqual(
            ledger.summary.overflowCategoryCounts,
            [
                WayTaskMigrationExceptionCategoryCount(
                    category: .unresolvedSessionLine,
                    count: 1
                )
            ]
        )

        var repeated = WayTaskMigrationExceptionLedger(capacity: 2)
        repeated.record(category: .ambiguousRecord, safeEvidenceDigest: first)
        repeated.record(category: .unsupportedRecord, safeEvidenceDigest: second)
        repeated.record(category: .ambiguousRecord, safeEvidenceDigest: first)
        repeated.record(category: .unresolvedSessionLine, safeEvidenceDigest: third)
        XCTAssertEqual(ledger, repeated)
        XCTAssertEqual(
            try ledger.encodedData(),
            try repeated.encodedData()
        )
        XCTAssertEqual(
            Set(WayTaskMigrationExceptionCategory.allCases.map(\.rawValue))
                .count,
            WayTaskMigrationExceptionCategory.allCases.count
        )
    }

    func testSourceAndSidecarBytesRemainUnchangedOnSuccessAndFailure()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let walURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: fixture.sourceStoreURL.path + "-shm")
        try Data([0x10, 0x11]).write(to: walURL)
        try Data([0x20, 0x21]).write(to: shmURL)
        let before = try snapshotStoreComponents(fixture.sourceStoreURL)

        var successDependencies =
            WayTaskProductStateMigrationDependencies.live
        successDependencies.physicalMigrateCandidate = { _ in }
        successDependencies.reopenCandidate = { _ in
            Self.validCandidateSnapshot()
        }
        let successMigration = WayTaskProductStateMigration(
            dependencies: successDependencies
        )
        let receipt = try unwrapReceipt(
            successMigration.prepareCandidate(
                fixture.request(seed: attemptSeed)
            )
        )
        XCTAssertEqual(before, try snapshotStoreComponents(fixture.sourceStoreURL))
        _ = successMigration.cleanupOwnedCandidate(receipt)

        var failureDependencies = successDependencies
        failureDependencies.physicalMigrateCandidate = { _ in
            throw SyntheticFailure.injected
        }
        let failure = try unwrapFailure(
            WayTaskProductStateMigration(
                dependencies: failureDependencies
            ).prepareCandidate(
                fixture.request(
                    seed: UUID(
                        uuidString: "06060606-0000-0000-0000-000000000099"
                    )!
                )
            )
        )
        XCTAssertEqual(failure.classification, .physicalMigrationFailed)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
        XCTAssertEqual(before, try snapshotStoreComponents(fixture.sourceStoreURL))
    }

    func testMissingUnreadableUnknownAndInconsistentSourceFailClosed()
        throws
    {
        let root = try makeEmptyRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source/missing.store")
        let candidateRoot = root.appendingPathComponent("candidates")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidateRoot,
            withIntermediateDirectories: true
        )
        let missingRequest = WayTaskMigrationRequest(
            sourceStoreURL: source,
            candidateRootURL: candidateRoot,
            attemptSeed: attemptSeed
        )
        XCTAssertEqual(
            try unwrapFailure(
                WayTaskProductStateMigration().prepareCandidate(missingRequest)
            ).classification,
            .missingSource
        )

        try Data([0x01]).write(to: source)
        var unreadableDependencies =
            WayTaskProductStateMigrationDependencies.live
        unreadableDependencies.inspectStore = { url in
            if url.standardizedFileURL == source.standardizedFileURL {
                throw WayTaskProtectedStoreInspectionError.unreadableComponent
            }
            return try WayTaskProductStateMigrationDependencies.live
                .inspectStore(url)
        }
        XCTAssertEqual(
            try unwrapFailure(
                WayTaskProductStateMigration(
                    dependencies: unreadableDependencies
                ).prepareCandidate(missingRequest)
            ).classification,
            .unreadableSource
        )

        var unknownDependencies =
            WayTaskProductStateMigrationDependencies.live
        unknownDependencies.resolveSchemaIdentity = { _ in
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        XCTAssertEqual(
            try unwrapFailure(
                WayTaskProductStateMigration(
                    dependencies: unknownDependencies
                ).prepareCandidate(missingRequest)
            ).classification,
            .unknownSchemaIdentity
        )

        var unsupportedDependencies =
            WayTaskProductStateMigrationDependencies.live
        unsupportedDependencies.resolveSchemaIdentity = { _ in
            throw WayTaskProtectedStoreSchemaError.unsupportedIdentity
        }
        XCTAssertEqual(
            try unwrapFailure(
                WayTaskProductStateMigration(
                    dependencies: unsupportedDependencies
                ).prepareCandidate(missingRequest)
            ).classification,
            .unsupportedSchemaIdentity
        )

        try Data([0x02]).write(
            to: URL(fileURLWithPath: source.path + "-wal")
        )
        XCTAssertEqual(
            try unwrapFailure(
                WayTaskProductStateMigration().prepareCandidate(missingRequest)
            ).classification,
            .inconsistentSourceInventory
        )
    }

    func testInsufficientSpaceAndCandidateCreationFailureOccurBeforeCopy()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let sourceBefore = try snapshotStoreComponents(fixture.sourceStoreURL)

        var noSpace = WayTaskProductStateMigrationDependencies.live
        noSpace.availableDestinationCapacity = { _ in 0 }
        let noSpaceFailure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: noSpace)
                .prepareCandidate(fixture.request(seed: attemptSeed))
        )
        XCTAssertEqual(
            noSpaceFailure.classification,
            .insufficientDestinationSpace
        )
        XCTAssertTrue(noSpaceFailure.sourceBytesVerifiedUnchanged)

        var createFailure = WayTaskProductStateMigrationDependencies.live
        createFailure.createDirectory = { _ in
            throw SyntheticFailure.injected
        }
        let failedCreate = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: createFailure)
                .prepareCandidate(
                    fixture.request(
                        seed: UUID(
                            uuidString:
                                "06060606-0000-0000-0000-000000000010"
                        )!
                    )
                )
        )
        XCTAssertEqual(failedCreate.classification, .candidateCreationFailed)
        XCTAssertFalse(failedCreate.candidateArtifactsRemain)
        XCTAssertEqual(sourceBefore, try snapshotStoreComponents(fixture.sourceStoreURL))
    }

    func testPhysicalReopenAndValidationFailuresNeverRetainCandidate()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }

        var physical = WayTaskProductStateMigrationDependencies.live
        physical.physicalMigrateCandidate = { _ in
            throw SyntheticFailure.injected
        }
        try assertInjectedFailure(
            fixture: fixture,
            dependencies: physical,
            seedByte: 11,
            expected: .physicalMigrationFailed
        )

        var reopen = WayTaskProductStateMigrationDependencies.live
        reopen.reopenCandidate = { _ in throw SyntheticFailure.injected }
        try assertInjectedFailure(
            fixture: fixture,
            dependencies: reopen,
            seedByte: 12,
            expected: .candidateReopenFailed
        )

        var validation = WayTaskProductStateMigrationDependencies.live
        validation.validateCandidate = { _ in throw SyntheticFailure.injected }
        try assertInjectedFailure(
            fixture: fixture,
            dependencies: validation,
            seedByte: 13,
            expected: .validationFailed
        )
    }

    func testSourceDriftAndCandidateFingerprintMismatchFailBeforePromotion()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }

        var sourceObservationCount = 0
        var sourceDrift = WayTaskProductStateMigrationDependencies.live
        sourceDrift.observeFingerprint = { url, fingerprint in
            guard url.standardizedFileURL ==
                    fixture.sourceStoreURL.standardizedFileURL
            else { return fingerprint }
            sourceObservationCount += 1
            guard sourceObservationCount >= 2 else { return fingerprint }
            return WayTaskMigrationFingerprint(
                rawValue: String(repeating: "d", count: 64)
            )
        }
        let sourceFailure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: sourceDrift)
                .prepareCandidate(fixture.request(seed: attemptSeed))
        )
        XCTAssertEqual(sourceFailure.classification, .sourceFingerprintDrift)
        XCTAssertFalse(sourceFailure.promotionAuthorized)

        var candidateObservationCount = 0
        var candidateMismatch = WayTaskProductStateMigrationDependencies.live
        candidateMismatch.observeFingerprint = { url, fingerprint in
            guard url.lastPathComponent ==
                    WayTaskProductStateMigration.candidateStoreFilename
            else { return fingerprint }
            candidateObservationCount += 1
            guard candidateObservationCount == 2 else { return fingerprint }
            return WayTaskMigrationFingerprint(
                rawValue: String(repeating: "c", count: 64)
            )
        }
        let candidateFailure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: candidateMismatch)
                .prepareCandidate(
                    fixture.request(
                        seed: UUID(
                            uuidString:
                                "06060606-0000-0000-0000-000000000014"
                        )!
                    )
                )
        )
        XCTAssertEqual(
            candidateFailure.classification,
            .candidateFingerprintMismatch
        )
        XCTAssertFalse(candidateFailure.candidateArtifactsRemain)
        XCTAssertFalse(candidateFailure.promotionAuthorized)
    }

    func testExceptionLedgerWriteFailureIsClassifiedAndCleaned() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        var dependencies = WayTaskProductStateMigrationDependencies.live
        let liveWrite = dependencies.writeOwnedArtifact
        dependencies.writeOwnedArtifact = { data, url in
            if url.lastPathComponent ==
                WayTaskProductStateMigration.exceptionLedgerFilename
            {
                throw SyntheticFailure.injected
            }
            try liveWrite(data, url)
        }

        let failure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: dependencies)
                .prepareCandidate(fixture.request(seed: attemptSeed))
        )
        XCTAssertEqual(
            failure.classification,
            .exceptionLedgerWriteFailed
        )
        XCTAssertFalse(failure.candidateArtifactsRemain)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
    }

    func testInterruptedOwnedAttemptIsCleanedAndRestartedDeterministically()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let migration = WayTaskProductStateMigration()
        let request = fixture.request(seed: attemptSeed)
        let first = try unwrapReceipt(migration.prepareCandidate(request))
        let firstAttempt = first.attemptIdentity
        let firstStage = first.stageIdentity

        let second = try unwrapReceipt(migration.prepareCandidate(request))
        defer { _ = migration.cleanupOwnedCandidate(second) }
        XCTAssertTrue(second.recoveredInterruptedAttempt)
        XCTAssertEqual(second.attemptIdentity, firstAttempt)
        XCTAssertEqual(second.stageIdentity, firstStage)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: second.candidateStoreURL.path
            )
        )
    }

    func testCleanupDeletesOnlyOwnedAttemptArtifacts() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let neighborURL = fixture.candidateRootURL.appendingPathComponent(
            "not-owned.txt"
        )
        try Data("retain".utf8).write(to: neighborURL)
        let migration = WayTaskProductStateMigration()
        let receipt = try unwrapReceipt(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )

        let cleanup = migration.cleanupOwnedCandidate(receipt)
        XCTAssertTrue(cleanup.succeeded)
        XCTAssertGreaterThan(cleanup.removedOwnedArtifactCount, 0)
        XCTAssertFalse(cleanup.sourceWasAccessed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: receipt.candidateAttemptDirectoryURL.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighborURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.sourceStoreURL.path
            )
        )
    }

    func testCleanupFailureHasTerminalClassificationAndNeverTouchesSource()
        throws
    {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let before = try snapshotStoreComponents(fixture.sourceStoreURL)
        var dependencies = WayTaskProductStateMigrationDependencies.live
        dependencies.physicalMigrateCandidate = { _ in
            throw SyntheticFailure.injected
        }
        dependencies.removeOwnedDirectory = { _ in
            throw SyntheticFailure.injected
        }
        let failure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: dependencies)
                .prepareCandidate(fixture.request(seed: attemptSeed))
        )

        XCTAssertEqual(failure.classification, .cleanupFailed)
        XCTAssertEqual(
            failure.triggeringClassification,
            .physicalMigrationFailed
        )
        XCTAssertTrue(failure.candidateArtifactsRemain)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
        XCTAssertEqual(before, try snapshotStoreComponents(fixture.sourceStoreURL))
    }

    func testDiagnosticsAndCandidateArtifactsArePrivacySafe() throws {
        let fixture = try makeFixture(schema: .v3)
        defer { fixture.remove() }
        let migration = WayTaskProductStateMigration()
        let receipt = try unwrapReceipt(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        defer { _ = migration.cleanupOwnedCandidate(receipt) }

        let forbidden = [
            Fixture.privateName,
            Fixture.privateBarcode,
            Fixture.privateNote,
            Fixture.privateCoordinate
        ]
        let manifest = try String(
            contentsOf: receipt.candidateAttemptDirectoryURL
                .appendingPathComponent(
                    WayTaskProductStateMigration.manifestFilename
                ),
            encoding: .utf8
        )
        let ledger = try String(
            contentsOf: receipt.candidateAttemptDirectoryURL
                .appendingPathComponent(
                    WayTaskProductStateMigration.exceptionLedgerFilename
                ),
            encoding: .utf8
        )
        let diagnostic = String(describing: receipt.diagnostic)
        for value in forbidden {
            XCTAssertFalse(manifest.contains(value))
            XCTAssertFalse(ledger.contains(value))
            XCTAssertFalse(diagnostic.contains(value))
        }
        XCTAssertEqual(receipt.exceptionSummary.totalOccurrenceCount, 0)
    }

    func testFoundationRemainsIsolatedBehindSingleT21RuntimeCutover()
        throws
    {
        let root = repositoryRoot()
        let migrationURL = root.appendingPathComponent(
            "WayTask/Persistence/WayTaskProductStateMigration.swift"
        )
        let schemaURL = root.appendingPathComponent(
            "WayTask/Persistence/WayTaskSchema.swift"
        )
        let migrationSource = try String(
            contentsOf: migrationURL,
            encoding: .utf8
        )
        let schemaSource = try String(contentsOf: schemaURL, encoding: .utf8)

        for forbidden in [
            "replacePersistentStore",
            "destroyPersistentStore",
            "FileManager.default.moveItem(",
            "WayTaskStartupPersistence",
            "WayTaskApp",
            "ContentView",
            "import SwiftUI",
            "import MapKit",
            "import CoreLocation",
            "import UserNotifications",
            "import Network",
            "import Sentry",
            "URLSession"
        ] {
            XCTAssertFalse(migrationSource.contains(forbidden), forbidden)
        }
        XCTAssertFalse(
            schemaSource.contains(
                "WayTaskSchemaV3.self,\n            WayTaskSchemaV4.self"
            )
        )
        XCTAssertTrue(
            migrationSource.contains("var semanticConversionCompleted: Bool { false }")
        )
        XCTAssertTrue(
            migrationSource.contains("var promotionAuthorized: Bool { false }")
        )

        let productionRoot = root.appendingPathComponent("WayTask")
        let enumerator = FileManager.default.enumerator(
            at: productionRoot,
            includingPropertiesForKeys: nil
        )
        var callers: [String] = []
        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.pathExtension == "swift",
                  candidate != migrationURL
            else { continue }
            let source = try String(contentsOf: candidate, encoding: .utf8)
            if source.contains("WayTaskProductStateMigration(") {
                callers.append(candidate.path)
            }
        }
        XCTAssertEqual(
            callers.sorted(),
            [
                root.appendingPathComponent(
                    "WayTask/ProductState/Runtime/ProductStateRuntime.swift"
                ).path
            ]
        )
    }

    func testEquivalentCleanCopiesProduceRepeatableFoundationIdentity()
        throws
    {
        let base = try makeFixture(schema: .v3)
        defer { base.remove() }
        let second = try makeEmptyFixtureRoot()
        defer { second.remove() }
        try copyStoreComponents(
            from: base.sourceStoreURL,
            to: second.sourceStoreURL
        )

        let firstMigration = WayTaskProductStateMigration()
        let secondMigration = WayTaskProductStateMigration()
        let first = try unwrapReceipt(
            firstMigration.prepareCandidate(base.request(seed: attemptSeed))
        )
        defer { _ = firstMigration.cleanupOwnedCandidate(first) }
        let secondReceipt = try unwrapReceipt(
            secondMigration.prepareCandidate(
                second.request(seed: attemptSeed)
            )
        )
        defer { _ = secondMigration.cleanupOwnedCandidate(secondReceipt) }

        XCTAssertEqual(first.sourceFingerprint, secondReceipt.sourceFingerprint)
        XCTAssertEqual(first.stageIdentity, secondReceipt.stageIdentity)
        XCTAssertEqual(first.attemptIdentity, secondReceipt.attemptIdentity)
        XCTAssertEqual(first.candidateSchemaIdentity, secondReceipt.candidateSchemaIdentity)
        XCTAssertEqual(first.candidateValidation, secondReceipt.candidateValidation)
        XCTAssertEqual(first.candidateFingerprint, secondReceipt.candidateFingerprint)
        XCTAssertEqual(first.exceptionSummary, secondReceipt.exceptionSummary)
        XCTAssertEqual(first.status, secondReceipt.status)
        XCTAssertEqual(first.completion, secondReceipt.completion)
    }

    // MARK: - Focused assertions

    private func assertPhysicalMigration(
        from sourceSchema: WayTaskMigrationSchemaIdentity
    ) throws {
        let fixture = try makeFixture(schema: sourceSchema)
        defer { fixture.remove() }
        let before = try snapshotStoreComponents(fixture.sourceStoreURL)
        let migration = WayTaskProductStateMigration()
        let receipt = try unwrapReceipt(
            migration.prepareCandidate(fixture.request(seed: attemptSeed))
        )
        defer { _ = migration.cleanupOwnedCandidate(receipt) }

        XCTAssertEqual(receipt.sourceSchemaIdentity, sourceSchema)
        XCTAssertEqual(receipt.candidateSchemaIdentity, .v3)
        XCTAssertEqual(receipt.inactiveSemanticTargetSchemaIdentity, .v4)
        XCTAssertEqual(receipt.candidateValidation.recordCounts["Product"], 1)
        XCTAssertEqual(
            receipt.candidateValidation.recordCounts["ShoppingList"],
            1
        )
        XCTAssertEqual(
            receipt.candidateValidation.recordCounts["ShoppingListEntry"],
            1
        )
        XCTAssertFalse(receipt.semanticConversionCompleted)
        XCTAssertFalse(receipt.promotionAuthorized)
        XCTAssertEqual(before, try snapshotStoreComponents(fixture.sourceStoreURL))

        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-T06-Test-Reopen",
                schema: schema,
                url: receipt.candidateStoreURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan:
                    WayTaskProtectedCandidatePhysicalMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let product = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Product>()).first
            )
            let entry = try XCTUnwrap(
                try context.fetch(FetchDescriptor<ShoppingListEntry>()).first
            )
            XCTAssertEqual(product.id, Fixture.productID)
            XCTAssertEqual(product.name, Fixture.privateName)
            XCTAssertEqual(product.barcode, Fixture.privateBarcode)
            XCTAssertEqual(entry.id, Fixture.entryID)
            XCTAssertEqual(entry.productID, Fixture.productID)
            XCTAssertEqual(entry.isChecked, sourceSchema != .v3)
            XCTAssertNil(product.deletedAt)
        }
    }

    private func assertInjectedFailure(
        fixture: Fixture,
        dependencies: WayTaskProductStateMigrationDependencies,
        seedByte: UInt8,
        expected: WayTaskMigrationFailureClassification
    ) throws {
        let seed = UUID(uuid: (
            0x06, 0x06, 0x06, 0x06,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, seedByte
        ))
        let failure = try unwrapFailure(
            WayTaskProductStateMigration(dependencies: dependencies)
                .prepareCandidate(fixture.request(seed: seed))
        )
        XCTAssertEqual(failure.classification, expected)
        XCTAssertFalse(failure.candidateArtifactsRemain)
        XCTAssertFalse(failure.promotionAuthorized)
        XCTAssertTrue(failure.sourceBytesVerifiedUnchanged)
    }

    // MARK: - Synthetic fixtures

    private struct Fixture {
        static let productID = UUID(
            uuidString: "16000000-0000-0000-0000-000000000001"
        )!
        static let itemID = UUID(
            uuidString: "16000000-0000-0000-0000-000000000002"
        )!
        static let listID = UUID(
            uuidString: "16000000-0000-0000-0000-000000000003"
        )!
        static let entryID = UUID(
            uuidString: "16000000-0000-0000-0000-000000000004"
        )!
        static let privateName = "SYNTHETIC_PRIVATE_PRODUCT"
        static let privateBarcode = "SYNTHETIC_PRIVATE_BARCODE"
        static let privateNote = "SYNTHETIC_PRIVATE_NOTE"
        static let privateCoordinate = "31.123456"

        let rootURL: URL
        let sourceStoreURL: URL
        let candidateRootURL: URL

        func request(seed: UUID) -> WayTaskMigrationRequest {
            WayTaskMigrationRequest(
                sourceStoreURL: sourceStoreURL,
                candidateRootURL: candidateRootURL,
                attemptSeed: seed,
                exceptionLedgerCapacity: 3
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func makeFixture(
        schema: WayTaskMigrationSchemaIdentity
    ) throws -> Fixture {
        let fixture = try makeEmptyFixtureRoot()
        let builderDirectory = fixture.rootURL.appendingPathComponent(
            "synthetic-builder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: builderDirectory,
            withIntermediateDirectories: false
        )
        let builderStoreURL = builderDirectory.appendingPathComponent(
            "builder.store"
        )
        try writeSyntheticFixture(schema: schema, to: builderStoreURL)
        try copyStoreComponents(
            from: builderStoreURL,
            to: fixture.sourceStoreURL
        )
        try FileManager.default.removeItem(at: builderDirectory)
        return fixture
    }

    private func makeEmptyFixtureRoot() throws -> Fixture {
        let root = try makeEmptyRoot()
        let sourceDirectory = root.appendingPathComponent(
            "protected-source",
            isDirectory: true
        )
        let candidateRoot = root.appendingPathComponent(
            "task-owned-candidates",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidateRoot,
            withIntermediateDirectories: true
        )
        return Fixture(
            rootURL: root,
            sourceStoreURL: sourceDirectory.appendingPathComponent(
                "WayTask.store"
            ),
            candidateRootURL: candidateRoot
        )
    }

    private func makeEmptyRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT033A-T06-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        return root
    }

    private func writeSyntheticFixture(
        schema identity: WayTaskMigrationSchemaIdentity,
        to storeURL: URL
    ) throws {
        switch identity {
        case .v1:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV1.self)
                let container = try makeFixtureContainer(
                    schema: schema,
                    storeURL: storeURL
                )
                let context = ModelContext(container)
                let item = ShoppingItem(
                    id: Fixture.itemID,
                    name: Fixture.privateName,
                    barcode: Fixture.privateBarcode
                )
                let product = WayTaskSchemaV1.Product(
                    id: Fixture.productID,
                    legacyShoppingItemID: Fixture.itemID,
                    name: Fixture.privateName,
                    imageData: nil,
                    brand: nil,
                    category: nil,
                    barcode: Fixture.privateBarcode,
                    imageURLString: nil,
                    dateAdded: Date(timeIntervalSince1970: 1_700_006_001),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_002),
                    sourceRawValue: ProductSource.manual.rawValue
                )
                let list = ShoppingList(
                    id: Fixture.listID,
                    title: "Synthetic List",
                    kind: .weekly,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_003),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_004),
                    isDefault: true
                )
                let entry = WayTaskSchemaV1.ShoppingListEntry(
                    id: Fixture.entryID,
                    shoppingListID: Fixture.listID,
                    product: product,
                    legacyShoppingItemID: Fixture.itemID,
                    quantity: 2,
                    isChecked: true,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_005),
                    sortOrder: 1
                )
                context.insert(item)
                context.insert(product)
                context.insert(list)
                context.insert(entry)
                try context.save()
            }
        case .v2:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV2.self)
                let container = try makeFixtureContainer(
                    schema: schema,
                    storeURL: storeURL
                )
                let context = ModelContext(container)
                let item = ShoppingItem(
                    id: Fixture.itemID,
                    name: Fixture.privateName,
                    barcode: Fixture.privateBarcode
                )
                let product = WayTaskSchemaV2.Product(
                    id: Fixture.productID,
                    legacyShoppingItemID: Fixture.itemID,
                    name: Fixture.privateName,
                    barcode: Fixture.privateBarcode,
                    dateAdded: Date(timeIntervalSince1970: 1_700_006_001),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_002),
                    catalogProductIDRawValue: "synthetic.catalog.id"
                )
                let list = ShoppingList(
                    id: Fixture.listID,
                    title: "Synthetic List",
                    kind: .weekly,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_003),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_004),
                    isDefault: true
                )
                let entry = WayTaskSchemaV2.ShoppingListEntry(
                    id: Fixture.entryID,
                    shoppingListID: Fixture.listID,
                    product: product,
                    legacyShoppingItemID: Fixture.itemID,
                    quantity: 2,
                    isChecked: true,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_005),
                    sortOrder: 1
                )
                context.insert(item)
                context.insert(product)
                context.insert(list)
                context.insert(entry)
                try context.save()
            }
        case .v3:
            try autoreleasepool {
                let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
                let container = try makeFixtureContainer(
                    schema: schema,
                    storeURL: storeURL
                )
                let context = ModelContext(container)
                let item = ShoppingItem(
                    id: Fixture.itemID,
                    name: Fixture.privateName,
                    barcode: Fixture.privateBarcode
                )
                let product = Product(
                    id: Fixture.productID,
                    legacyShoppingItemID: Fixture.itemID,
                    name: Fixture.privateName,
                    barcode: Fixture.privateBarcode,
                    dateAdded: Date(timeIntervalSince1970: 1_700_006_001),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_002)
                )
                let list = ShoppingList(
                    id: Fixture.listID,
                    title: "Synthetic List",
                    kind: .weekly,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_003),
                    updatedAt: Date(timeIntervalSince1970: 1_700_006_004),
                    isDefault: true
                )
                let entry = ShoppingListEntry(
                    id: Fixture.entryID,
                    shoppingListID: Fixture.listID,
                    product: product,
                    legacyShoppingItemID: Fixture.itemID,
                    quantity: 2,
                    isChecked: false,
                    createdAt: Date(timeIntervalSince1970: 1_700_006_005),
                    sortOrder: 1
                )
                context.insert(item)
                context.insert(product)
                context.insert(list)
                context.insert(entry)
                try context.save()
            }
        case .v4:
            XCTFail("T-06 fixtures must not create a V4 source")
        }
    }

    private func makeFixtureContainer(
        schema: Schema,
        storeURL: URL
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "WT033A-T06-Synthetic-Source",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private static func validCandidateSnapshot()
        -> WayTaskMigrationCandidateValidation
    {
        WayTaskMigrationCandidateValidation(
            schemaIdentity: .v3,
            recordCounts: [
                "GeoLocation": 0,
                "ShoppingItem": 1,
                "Product": 1,
                "ShoppingList": 1,
                "ShoppingListEntry": 1,
                "ProductHistory": 0,
                "ProductKnowledge": 0,
                "ShoppingSession": 0
            ]
        )
    }

    private func snapshotStoreComponents(
        _ storeURL: URL
    ) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            result[suffix.isEmpty ? "database" : suffix] = try Data(
                contentsOf: url
            )
        }
        return result
    }

    private func copyStoreComponents(
        from sourceStoreURL: URL,
        to destinationStoreURL: URL
    ) throws {
        let inventory = try WayTaskProductStateMigrationDependencies.live
            .inspectStore(sourceStoreURL)
        for component in inventory.components {
            let suffix: String
            switch component.role {
            case .database:
                suffix = ""
            case .writeAheadLog:
                suffix = "-wal"
            case .sharedMemory:
                suffix = "-shm"
            case .rollbackJournal:
                suffix = "-journal"
            }
            try FileManager.default.copyItem(
                at: component.url,
                to: URL(fileURLWithPath: destinationStoreURL.path + suffix)
            )
        }
    }

    private func unwrapReceipt(
        _ result: WayTaskMigrationPreparationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WayTaskMigrationCandidateReceipt {
        switch result {
        case .candidateReady(let receipt):
            return receipt
        case .failed(let failure):
            XCTFail(
                "Expected candidate, got \(failure.classification.rawValue) / " +
                    "\(failure.triggeringClassification.rawValue)",
                file: file,
                line: line
            )
            throw SyntheticFailure.injected
        }
    }

    private func unwrapFailure(
        _ result: WayTaskMigrationPreparationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WayTaskMigrationFailure {
        switch result {
        case .candidateReady:
            XCTFail("Expected failure", file: file, line: line)
            throw SyntheticFailure.injected
        case .failed(let failure):
            return failure
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum SyntheticFailure: Error {
        case injected
    }
}
