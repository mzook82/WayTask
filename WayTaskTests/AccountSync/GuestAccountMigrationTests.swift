import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class GuestAccountMigrationTests: XCTestCase {
    private let userA = UUID(
        uuidString: "10000000-0000-4000-8000-000000000001"
    )!
    private let userB = UUID(
        uuidString: "20000000-0000-4000-8000-000000000002"
    )!
    private let dataSetID = UUID(
        uuidString: "30000000-0000-4000-8000-000000000003"
    )!

    func testCanonicalManifestIsDeterministicAndSeparatesAttemptMetadata()
        throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let builder = GuestMigrationManifestBuilder()

        let first = try builder.build(
            modelContainer: container,
            localDataSetID: dataSetID,
            targetUserID: userA
        )
        let second = try builder.build(
            modelContainer: container,
            localDataSetID: dataSetID,
            targetUserID: userA
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.dataset.counts, GuestMigrationCounts(
            personalProducts: 1,
            shoppingLists: 1,
            shoppingListEntries: 1
        ))
        XCTAssertEqual(first.datasetFingerprint.count, 64)
        XCTAssertEqual(first.batches.map(\.entityKind), [
            .personalProducts, .shoppingLists, .shoppingListEntries
        ])
        let firstID = GuestMigrationCanonicalizer.batchID(
            attemptID: UUID(
                uuidString: "40000000-0000-4000-8000-000000000004"
            )!,
            batch: try XCTUnwrap(first.batches.first)
        )
        let secondID = GuestMigrationCanonicalizer.batchID(
            attemptID: UUID(
                uuidString: "50000000-0000-4000-8000-000000000005"
            )!,
            batch: try XCTUnwrap(first.batches.first)
        )
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(first.datasetFingerprint, second.datasetFingerprint)
    }

    func testManifestPreservesInternationalTextButExcludesPrivateArtifacts()
        throws {
        let container = try makeContainer(fixture: .internationalAndPrivate)
        let manifest = try GuestMigrationManifestBuilder().build(
            modelContainer: container,
            localDataSetID: dataSetID,
            targetUserID: userA
        )

        XCTAssertEqual(manifest.dataset.personalProducts.map(\.displayName), [
            "חלב عربي", "Crème 👻 家庭"
        ])
        XCTAssertEqual(manifest.dataset.shoppingLists.map(\.title), [
            "قائمة أسبوعية", "Localized List"
        ])
        XCTAssertEqual(manifest.dataset.counts, GuestMigrationCounts(
            personalProducts: 2,
            shoppingLists: 2,
            shoppingListEntries: 2
        ))
        XCTAssertEqual(
            manifest.dataset.shoppingListEntries.map(\.resolutionReason),
            [nil, "already_have"]
        )
        XCTAssertTrue(manifest.dataset.excludedCategories.contains(
            .productImages
        ))
        XCTAssertTrue(manifest.dataset.excludedCategories.contains(
            .preciseLocationsAndSavedStores
        ))
        let encoded = String(
            decoding: try GuestMigrationCanonicalizer.data(for: manifest),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("image_data"))
        XCTAssertFalse(encoded.contains("31.7683"))
        XCTAssertFalse(encoded.contains("35.2137"))
    }

    func testEmptyAndLargeBoundedFixturesProduceBoundedOrderedBatches()
        throws {
        let empty = try makeContainer(fixture: .empty)
        let emptyManifest = try GuestMigrationManifestBuilder().build(
            modelContainer: empty,
            localDataSetID: dataSetID,
            targetUserID: userA
        )
        XCTAssertEqual(emptyManifest.dataset.counts.total, 0)
        XCTAssertTrue(emptyManifest.batches.isEmpty)

        let large = try makeContainer(fixture: .products(205))
        let manifest = try GuestMigrationManifestBuilder().build(
            modelContainer: large,
            localDataSetID: dataSetID,
            targetUserID: userA
        )
        XCTAssertEqual(manifest.batches.map(\.recordCount), [100, 100, 5])
        XCTAssertTrue(manifest.batches.allSatisfy {
            $0.payloadByteCount <= 1_048_576
        })
    }

    func testSignInDoesNotBindPreviewConsentUploadOrSync() throws {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)
        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userA),
            expiresAt: nil
        )
        let transport = MigrationTransportSpy()
        let coordinator = makeCoordinator(
            container: try makeContainer(fixture: .oneListOneItem),
            transport: transport
        )
        coordinator.reconcile(session: authority.currentSession)
        _ = try coordinator.makePreview(targetUserID: userA)

        XCTAssertEqual(coordinator.state, .migrationPreviewAvailable)
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
        XCTAssertEqual(transport.networkCallCount, 0)
        XCTAssertEqual(authority.currentSession.synchronization,
                       .signedInLocalDataNotBackedUp)
    }

    func testPreviewChangeInvalidatesConsentBeforeBindingOrUpload() throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let authority = signedInAuthority(userA)
        let transport = MigrationTransportSpy()
        let coordinator = makeCoordinator(
            container: container,
            transport: transport
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        let context = ModelContext(container)
        let product = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WayTaskSchemaV4.Product>()).first
        )
        product.name = "Changed after preview"
        product.updatedAt = product.updatedAt.addingTimeInterval(1)
        try context.save()

        XCTAssertThrowsError(
            try coordinator.consentAndPrepare(
                fingerprint: preview.datasetFingerprint,
                targetUserID: userA,
                activation: passingGate(userA),
                bindAccount: { authority.prepareInitialMigrationBinding() }
            )
        ) { error in
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .previewChanged)
        }
        XCTAssertEqual(transport.networkCallCount, 0)
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .guestOnly(dataSetID: dataSetID))
    }

    func testConsentPermanentlyBindsAAndBIsBlockedAfterSignOut() throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let store = MemoryMigrationLedgerStore()
        let authority = signedInAuthority(userA)
        let coordinator = makeCoordinator(
            container: container,
            store: store,
            transport: MigrationTransportSpy()
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() }
        )
        authority.signOutPreservingLocalData()
        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userB),
            expiresAt: nil
        )
        coordinator.reconcile(session: authority.currentSession)

        XCTAssertEqual(coordinator.state, .migrationConflict)
        XCTAssertThrowsError(
            try coordinator.makePreview(targetUserID: userB)
        ) { error in
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .accountConflict)
        }
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .migrationPending(dataSetID: dataSetID,
                                         targetUserID: userA))

        let relaunched = GuestMigrationCoordinator(
            modelContainer: container,
            localDataSetID: dataSetID,
            ledgerStore: store,
            transport: MigrationTransportSpy()
        )
        XCTAssertEqual(relaunched.boundTargetUserID, userA)
    }

    func testEveryActivationConditionFailsClosedAndProductionAlwaysDenied() {
        let base = passingGate(userA)
        XCTAssertNil(base.blocker())
        XCTAssertEqual(evidence(environment: .production).blocker(),
                       .productionDenied)
        XCTAssertEqual(evidence(environment: .staging,
                                migration: false).blocker(), .featureDisabled)
        XCTAssertEqual(evidence(environment: .staging,
                                schema: 0).blocker(), .unsupportedSchema)
        XCTAssertEqual(evidence(environment: .staging,
                                endpoint: false).blocker(), .endpointUnavailable)
        XCTAssertEqual(evidence(environment: .staging,
                                ab: false).blocker(),
                       .signedSessionIsolationUnproven)
        XCTAssertEqual(evidence(environment: .staging,
                                recovery: false).blocker(),
                       .sessionRecoveryUnproven)
        XCTAssertEqual(evidence(environment: .staging,
                                blockers: false).blocker(),
                       .unresolvedSecurityBlocker)
    }

    func testCurrentRepositoryActivationValuesRemainBlockedEvenIfFlagFlips() {
        let values = [
            GuestMigrationActivationConfiguration.schemaVersionKey: "0",
            GuestMigrationActivationConfiguration.endpointEnabledKey: "NO",
            GuestMigrationActivationConfiguration.signedSessionABGateKey: "NO",
            GuestMigrationActivationConfiguration.sessionRecoveryGateKey: "NO",
            GuestMigrationActivationConfiguration.blockersClearKey: "NO"
        ]
        let evidence = GuestMigrationActivationConfiguration.evidence(
            values: values,
            environment: .staging,
            compiledForInternalStaging: true,
            authenticatedUserID: userA,
            migrationFeatureEnabled: true
        )
        XCTAssertEqual(evidence.blocker(), .unsupportedSchema)
    }

    func testInterruptedLostResponseResumesIdempotentlyWithoutDuplicates()
        async throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let localCounts = try counts(container)
        let authority = signedInAuthority(userA)
        let transport = MigrationTransportSpy()
        transport.failAfterAcceptingSequence = 0
        let coordinator = makeCoordinator(
            container: container,
            transport: transport
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() },
            attemptID: UUID(
                uuidString: "60000000-0000-4000-8000-000000000006"
            )!
        )

        do {
            try await coordinator.execute(
                targetUserID: userA,
                activation: passingGate(userA),
                localOwnership: authority.currentSession.localDataOwnership,
                markCompleted: { authority.markInitialMigrationCompleted() }
            )
            XCTFail("The first accepted response is intentionally lost")
        } catch {
            XCTAssertEqual(coordinator.state, .migrationInterrupted)
            XCTAssertEqual(coordinator.lastError, .serviceUnavailable)
        }
        transport.failAfterAcceptingSequence = nil
        try await coordinator.execute(
            targetUserID: userA,
            activation: passingGate(userA),
            localOwnership: authority.currentSession.localDataOwnership,
            markCompleted: { authority.markInitialMigrationCompleted() }
        )

        XCTAssertEqual(coordinator.state, .migrationCompleted)
        XCTAssertEqual(transport.uniqueAppliedBatchCount, 3)
        XCTAssertEqual(transport.applyAttemptsForSequence[0], 2)
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .linked(dataSetID: dataSetID, ownerUserID: userA))
        XCTAssertEqual(authority.currentSession.synchronization,
                       .paused(.featureDisabled))
        XCTAssertEqual(try counts(container), localCounts)
    }

    func testVerificationFailureCannotClaimCompletionAndLocalDataSurvives()
        async throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let before = try counts(container)
        let authority = signedInAuthority(userA)
        let transport = MigrationTransportSpy()
        transport.verificationIsValid = false
        let coordinator = makeCoordinator(
            container: container,
            transport: transport
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() }
        )

        do {
            try await coordinator.execute(
                targetUserID: userA,
                activation: passingGate(userA),
                localOwnership: authority.currentSession.localDataOwnership,
                markCompleted: { authority.markInitialMigrationCompleted() }
            )
            XCTFail("Invalid verification must not complete")
        } catch {
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .verificationFailed)
        }
        XCTAssertEqual(coordinator.state, .migrationRollbackRequired)
        XCTAssertEqual(try counts(container), before)
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .migrationPending(dataSetID: dataSetID,
                                         targetUserID: userA))

        try await coordinator.rollbackBeforeCompletion(
            targetUserID: userA,
            activation: passingGate(userA),
            localOwnership: authority.currentSession.localDataOwnership
        )
        XCTAssertEqual(coordinator.state, .migrationConsentRequired)
        XCTAssertEqual(transport.rollbackCount, 1)
        XCTAssertEqual(coordinator.boundTargetUserID, userA)
        XCTAssertEqual(try counts(container), before)
    }

    func testCancelBeforeUploadRevokesConsentButKeepsImmutableBinding()
        throws {
        let authority = signedInAuthority(userA)
        let coordinator = makeCoordinator(
            container: try makeContainer(fixture: .oneListOneItem),
            transport: MigrationTransportSpy()
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() }
        )
        try coordinator.cancelBeforeUpload()

        XCTAssertEqual(coordinator.state, .migrationConsentRequired)
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .migrationPending(dataSetID: dataSetID,
                                         targetUserID: userA))
    }

    func testForgedAuthenticatedTargetIsRejectedBeforeNetwork() throws {
        let authority = signedInAuthority(userA)
        let transport = MigrationTransportSpy()
        let coordinator = makeCoordinator(
            container: try makeContainer(fixture: .oneListOneItem),
            transport: transport
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        XCTAssertThrowsError(
            try coordinator.consentAndPrepare(
                fingerprint: preview.datasetFingerprint,
                targetUserID: userA,
                activation: passingGate(userB),
                bindAccount: { authority.prepareInitialMigrationBinding() }
            )
        ) { error in
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .accountConflict)
        }
        XCTAssertEqual(transport.networkCallCount, 0)
    }

    func testResumeRejectsLedgerSidecarAccountMismatchBeforeNetwork()
        async throws {
        let authority = signedInAuthority(userA)
        let transport = MigrationTransportSpy()
        let coordinator = makeCoordinator(
            container: try makeContainer(fixture: .oneListOneItem),
            transport: transport
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() }
        )

        do {
            try await coordinator.execute(
                targetUserID: userA,
                activation: passingGate(userA),
                localOwnership: .migrationPending(
                    dataSetID: dataSetID,
                    targetUserID: userB
                ),
                markCompleted: { authority.markInitialMigrationCompleted() }
            )
            XCTFail("The ledger and ownership sidecar must agree")
        } catch {
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .accountConflict)
        }
        XCTAssertEqual(coordinator.state, .migrationConflict)
        XCTAssertEqual(transport.networkCallCount, 0)
        XCTAssertEqual(authority.currentSession.localDataOwnership,
                       .migrationPending(dataSetID: dataSetID,
                                         targetUserID: userA))
    }

    func testUnsupportedUnitAndMalformedLocalDataFailClosed() throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let context = ModelContext(container)
        let entry = try XCTUnwrap(
            try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            ).first
        )
        entry.unitRawValue = "truckload"
        try context.save()

        XCTAssertThrowsError(
            try GuestMigrationManifestBuilder().build(
                modelContainer: container,
                localDataSetID: dataSetID,
                targetUserID: userA
            )
        ) { error in
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .unsupportedLocalValue)
        }
    }

    func testProtectedLedgerRoundTripsWithMode0600() throws {
        let container = try makeContainer(fixture: .oneListOneItem)
        let memory = MemoryMigrationLedgerStore()
        let authority = signedInAuthority(userA)
        let coordinator = makeCoordinator(
            container: container,
            store: memory,
            transport: MigrationTransportSpy()
        )
        let preview = try coordinator.makePreview(targetUserID: userA)
        try coordinator.consentAndPrepare(
            fingerprint: preview.datasetFingerprint,
            targetUserID: userA,
            activation: passingGate(userA),
            bindAccount: { authority.prepareInitialMigrationBinding() }
        )
        let ledger = try XCTUnwrap(memory.value)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WT032C-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("migration.ledger")
        let protected = ProtectedGuestMigrationLedgerStore(fileURL: url)

        try protected.save(ledger)
        try protected.save(ledger)

        XCTAssertEqual(try protected.load(), ledger)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let permissions = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
    }

    func testTransportMapsSafeServerValidationAndVerificationCategories()
        async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MigrationMockURLProtocol.self]
        let urlSession = URLSession(configuration: sessionConfiguration)
        let transport = try SupabaseGuestMigrationTransport(
            configuration: WayTaskSupabaseConfiguration(
                environment: .staging,
                projectURL: URL(string: "https://staging.invalid")!,
                publishableKey: "client-safe-test-key"
            ),
            session: urlSession,
            retryPolicy: GuestMigrationRetryPolicy(
                maximumAttempts: 1,
                baseDelayMilliseconds: 0
            ),
            accessToken: { "synthetic-access-token" }
        )

        MigrationMockURLProtocol.statusCode = 400
        do {
            try await transport.rollback(attemptID: UUID())
            XCTFail("Validation rejection must be typed")
        } catch {
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .invalidLocalDataset)
        }

        MigrationMockURLProtocol.statusCode = 422
        do {
            try await transport.rollback(attemptID: UUID())
            XCTFail("Verification rejection must require recovery")
        } catch {
            XCTAssertEqual(error as? GuestMigrationFoundationError,
                           .verificationFailed)
        }
    }

    private func makeCoordinator(
        container: ModelContainer,
        transport: MigrationTransportSpy
    ) -> GuestMigrationCoordinator {
        makeCoordinator(
            container: container,
            store: MemoryMigrationLedgerStore(),
            transport: transport
        )
    }

    private func makeCoordinator(
        container: ModelContainer,
        store: MemoryMigrationLedgerStore,
        transport: MigrationTransportSpy
    ) -> GuestMigrationCoordinator {
        GuestMigrationCoordinator(
            modelContainer: container,
            localDataSetID: dataSetID,
            ledgerStore: store,
            transport: transport
        )
    }

    private func signedInAuthority(
        _ userID: UUID
    ) -> LocalAccountSessionAuthority {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)
        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userID),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        return authority
    }

    private func passingGate(_ userID: UUID)
        -> GuestMigrationActivationEvidence {
        evidence(environment: .staging, userID: userID)
    }

    private func evidence(
        environment: WayTaskCloudEnvironment,
        userID: UUID? = nil,
        migration: Bool = true,
        schema: Int = 1,
        endpoint: Bool = true,
        ab: Bool = true,
        recovery: Bool = true,
        blockers: Bool = true
    ) -> GuestMigrationActivationEvidence {
        GuestMigrationActivationEvidence(
            environment: environment,
            compiledForInternalStaging: true,
            authenticatedUserID: userID ?? userA,
            migrationFeatureEnabled: migration,
            schemaVersion: schema,
            endpointConfigured: endpoint,
            signedSessionABGatePassed: ab,
            sessionRecoveryGatePassed: recovery,
            securityBlockersClear: blockers
        )
    }

    private enum Fixture {
        case empty
        case oneListOneItem
        case internationalAndPrivate
        case products(Int)
    }

    private func makeContainer(fixture: Fixture) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        func addProduct(index: Int, name: String) -> WayTaskSchemaV4.Product {
            let product = WayTaskSchemaV4.Product(
                id: deterministicUUID(index + 1),
                revision: 1,
                libraryLifecycleRawValue: "active",
                name: name,
                imageData: fixtureHasPrivateData ? Data("private-photo".utf8) : nil,
                brand: "Synthetic Brand",
                category: "Synthetic Category",
                barcode: String(format: "123456%06d", index),
                imageURLString: fixtureHasPrivateData
                    ? "https://private.invalid/photo.jpg" : nil,
                sourceRawValue: ProductSource.manual.rawValue,
                catalogProductIDRawValue: "synthetic.product.\(index)",
                catalogDisplayNameSnapshot: "Rebuildable Catalog Snapshot",
                createdAt: timestamp,
                updatedAt: timestamp
            )
            context.insert(product)
            return product
        }

        switch fixture {
        case .empty:
            break
        case .oneListOneItem:
            let product = addProduct(index: 0, name: "Synthetic Milk")
            addListAndEntry(
                context: context,
                product: product,
                title: "Synthetic Weekly",
                timestamp: timestamp
            )
        case .internationalAndPrivate:
            let first = addProduct(index: 0, name: "חלב عربي")
            let second = addProduct(index: 1, name: "Crème 👻 家庭")
            addListAndEntry(
                context: context,
                product: first,
                title: "قائمة أسبوعية",
                timestamp: timestamp,
                index: 0
            )
            addListAndEntry(
                context: context,
                product: second,
                title: "Localized List",
                timestamp: timestamp,
                index: 1,
                resolved: true
            )
            context.insert(GeoLocation(
                title: "Private synthetic store",
                latitude: 31.7683,
                longitude: 35.2137
            ))
        case let .products(count):
            for index in 0..<count {
                _ = addProduct(index: index, name: "Synthetic Product \(index)")
            }
        }
        try context.save()
        return container
    }

    private var fixtureHasPrivateData: Bool {
        // Images are safe synthetic fixtures; the scanner must exclude them in
        // every case where present.
        true
    }

    private func addListAndEntry(
        context: ModelContext,
        product: WayTaskSchemaV4.Product,
        title: String,
        timestamp: Date,
        index: Int = 0,
        resolved: Bool = false
    ) {
        let listID = deterministicUUID(10_000 + index)
        let list = WayTaskSchemaV4.ShoppingList(
            id: listID,
            revision: 1,
            title: title,
            purposeRawValue: "shopping",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let entry = WayTaskSchemaV4.ShoppingListEntry(
            id: deterministicUUID(20_000 + index),
            shoppingListID: listID,
            productID: product.id,
            lifecycleRawValue: "needed",
            quantity: 2,
            unitRawValue: "count",
            note: "Synthetic note",
            sortOrder: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            product: product
        )
        if resolved {
            entry.lifecycleRawValue = "resolved"
            entry.resolutionReasonRawValue = "alreadyHave"
            entry.resolutionEffectiveAt = timestamp
            entry.resolutionProvenanceRawValue = "userCommand"
            entry.resolutionCommandID = deterministicUUID(30_000 + index)
        }
        list.entries.append(entry)
        context.insert(list)
        context.insert(entry)
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-4000-8000-%012d", value
        ))!
    }

    private func counts(_ container: ModelContainer) throws
        -> GuestMigrationCounts {
        let context = ModelContext(container)
        return GuestMigrationCounts(
            personalProducts: try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.Product>()
            ),
            shoppingLists: try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
            ),
            shoppingListEntries: try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            )
        )
    }
}

private final class MemoryMigrationLedgerStore:
    GuestMigrationLedgerPersisting {
    var value: GuestMigrationLedger?

    func load() throws -> GuestMigrationLedger? { value }
    func save(_ ledger: GuestMigrationLedger) throws { value = ledger }
    func clear() throws { value = nil }
}

private final class MigrationTransportSpy:
    GuestMigrationTransport, @unchecked Sendable {
    var failAfterAcceptingSequence: Int?
    var verificationIsValid = true
    private(set) var beginCount = 0
    private(set) var rollbackCount = 0
    private(set) var applyAttemptsForSequence: [Int: Int] = [:]
    private var receipts: [String: GuestMigrationReceipt] = [:]
    private var manifest: GuestMigrationManifest?

    var uniqueAppliedBatchCount: Int { receipts.count }
    var networkCallCount: Int {
        beginCount + applyAttemptsForSequence.values.reduce(0, +)
            + rollbackCount
    }

    func begin(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws {
        beginCount += 1
        self.manifest = manifest
    }

    func upload(
        attemptID: UUID,
        batchID: String,
        plan: GuestMigrationBatchPlan,
        payload: Data
    ) async throws -> GuestMigrationReceipt {
        applyAttemptsForSequence[plan.sequence, default: 0] += 1
        let receipt = receipts[batchID] ?? GuestMigrationReceipt(
            batchID: batchID,
            sequence: plan.sequence,
            payloadSHA256: plan.payloadSHA256,
            recordCount: plan.recordCount
        )
        receipts[batchID] = receipt
        if failAfterAcceptingSequence == plan.sequence,
           applyAttemptsForSequence[plan.sequence] == 1 {
            throw GuestMigrationFoundationError.serviceUnavailable
        }
        return receipt
    }

    func verify(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws -> GuestMigrationVerification {
        GuestMigrationVerification(
            targetUserID: manifest.dataset.targetUserID,
            datasetFingerprint: verificationIsValid
                ? manifest.datasetFingerprint : String(repeating: "0", count: 64),
            counts: manifest.dataset.counts,
            acknowledgedBatchIDs: receipts.values
                .sorted { $0.sequence < $1.sequence }
                .map(\.batchID),
            parentChildIntegrityVerified: verificationIsValid,
            excludedDataAbsent: verificationIsValid
        )
    }

    func rollback(attemptID: UUID) async throws {
        rollbackCount += 1
        receipts.removeAll()
    }
}

private final class MigrationMockURLProtocol: URLProtocol,
    @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
