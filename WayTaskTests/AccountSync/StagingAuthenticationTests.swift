import Foundation
import XCTest
@testable import WayTask

@MainActor
final class StagingAuthenticationTests: XCTestCase {
    private let dataSetID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let userA = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    private let userB = UUID(
        uuidString: "30000000-0000-0000-0000-000000000003"
    )!

    func testSecureNonceHashUsesSHA256AndChallengesAreUnique() throws {
        XCTAssertEqual(
            AppleAuthenticationSecurity.sha256("nonce"),
            "78377b525757b494427f89014f97d79928f3938d14eb51e20fb5dec9834eb304"
        )
        let first = try AppleAuthenticationSecurity.makeChallenge()
        let second = try AppleAuthenticationSecurity.makeChallenge()
        XCTAssertNotEqual(first.rawNonce, second.rawNonce)
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertEqual(
            first.hashedNonce,
            AppleAuthenticationSecurity.sha256(first.rawNonce)
        )
    }

    func testCancellationReturnsToGuestWithoutAuthOrOwnershipMutation() async {
        let apple = MockAppleProvider(result: .failure(.cancelled))
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(apple: apple, auth: auth)

        await controller.signInWithApple()

        XCTAssertEqual(controller.snapshot.state, .guest)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
        XCTAssertEqual(auth.signInCount, 0)
        XCTAssertNil(controller.lastFailure)
    }

    func testSignInAuthenticatesButNeverActivatesMigrationOrSync() async {
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(auth: auth)

        await controller.signInWithApple()

        XCTAssertEqual(
            controller.snapshot.state,
            .signedInLocalDataNotBackedUp
        )
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
        XCTAssertEqual(auth.signInCount, 1)
        XCTAssertEqual(auth.profileWriteCount, 0)
    }

    func testStateMismatchFailsBeforeSupabaseExchangeAndPreservesGuest() async {
        let apple = MockAppleProvider(
            result: .success(
                AppleAuthorizationPayload(
                    identityToken: "apple-test-identity-token",
                    returnedState: "attacker-state",
                    suggestedDisplayName: nil
                )
            ),
            echoesChallengeState: false
        )
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(apple: apple, auth: auth)

        await controller.signInWithApple()

        XCTAssertEqual(controller.snapshot.state, .guest)
        XCTAssertEqual(controller.lastFailure, .stateMismatch)
        XCTAssertEqual(auth.signInCount, 0)
    }

    func testSessionRestorationAndExpirationAreExplicit() async {
        let auth = MockSupabaseAuth(userID: userA)
        auth.restoration = .restored(auth.session)
        let controller = makeController(auth: auth)

        await controller.restoreSessionIfNeeded()
        XCTAssertEqual(
            controller.snapshot.state,
            .signedInLocalDataNotBackedUp
        )
        XCTAssertEqual(auth.restoreCount, 1)

        controller.markCurrentSessionExpiredForTesting()
        XCTAssertEqual(controller.snapshot.state, .sessionExpired)
        XCTAssertEqual(controller.lastFailure, .sessionExpired)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
    }

    func testOfflineRestorationPreservesLocalDataAndShowsOffline() async {
        let auth = MockSupabaseAuth(userID: userA)
        auth.restoration = .offline(lastKnownIdentity: UserIdentity(userID: userA))
        let controller = makeController(auth: auth)

        await controller.restoreSessionIfNeeded()

        XCTAssertEqual(controller.snapshot.state, .sessionExpired)
        XCTAssertEqual(controller.lastFailure, .offline)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
    }

    func testSignOutClearsSessionButPreservesPendingOwnership() async {
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(auth: auth)
        await controller.signInWithApple()

        await controller.signOut()

        XCTAssertEqual(controller.snapshot.state, .guest)
        XCTAssertEqual(auth.signOutCount, 1)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
    }

    func testPersistedPendingDatasetCannotBeRetargetedAfterRelaunch() {
        let persistence = OwnershipPersistenceSpy()
        let first = LocalAccountSessionAuthority(
            dataSetID: dataSetID,
            ownershipPersistence: persistence
        )
        first.acceptVerifiedSession(
            identity: UserIdentity(userID: userA),
            expiresAt: nil
        )
        let persisted = persistence.lastSaved
        XCTAssertEqual(
            persisted,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )

        let relaunched = LocalAccountSessionAuthority(
            dataSetID: dataSetID,
            initialOwnership: persisted,
            ownershipPersistence: persistence
        )
        relaunched.acceptVerifiedSession(
            identity: UserIdentity(userID: userB),
            expiresAt: nil
        )

        XCTAssertEqual(relaunched.currentSession.state, .recoverableSyncError)
        XCTAssertEqual(
            relaunched.currentSession.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
    }

    func testMissingConfigurationRestorationMakesZeroCloudRequests() async {
        let auth = MockSupabaseAuth(userID: userA)
        let foundation = WayTaskAccountSyncFoundation(
            configurationStatus: .notConfigured,
            featureFlags: .disabled,
            dataSetID: dataSetID
        )
        let controller = StagingAccountController(
            foundation: foundation,
            appleProvider: MockAppleProvider(),
            authProvider: auth,
            diagnostics: DiagnosticsSpy(),
            internalStagingUIEnabled: true
        )

        await controller.restoreSessionIfNeeded()

        XCTAssertEqual(auth.restoreCount, 0)
        XCTAssertEqual(controller.snapshot.state, .guest)
    }

    func testSecureAIRemainsUnavailableUntilItsIndependentFlagIsEnabled() async {
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(auth: auth, secureAIEnabled: false)
        await controller.signInWithApple()
        XCTAssertNil(controller.secureAIAccessToken())

        let eligible = makeController(auth: auth, secureAIEnabled: true)
        await eligible.signInWithApple()
        XCTAssertEqual(
            eligible.secureAIAccessToken(),
            "supabase-test-access-token"
        )
    }

    func testProfileWriteUsesNormalizedDataOnlyAfterExplicitAction() async {
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(auth: auth)
        await controller.signInWithApple()
        XCTAssertEqual(auth.profileWriteCount, 0)

        await controller.saveDisplayName("  נועה   👻  ")

        XCTAssertEqual(auth.profileWriteCount, 1)
        XCTAssertEqual(auth.lastDisplayName, "נועה 👻")
        XCTAssertEqual(auth.lastProfileOwner, userA)
    }

    func testProtectedRequestRevocationExpiresAccountAndPreservesOwnership()
        async {
        let auth = MockSupabaseAuth(userID: userA)
        let diagnostics = DiagnosticsSpy()
        let controller = makeController(
            auth: auth,
            secureAIEnabled: true,
            diagnostics: diagnostics
        )
        await controller.signInWithApple()
        XCTAssertNotNil(controller.secureAIAccessToken())
        auth.profileWriteFailure = .sessionExpired

        await controller.saveDisplayName("Safe Name")

        XCTAssertEqual(controller.snapshot.state, .sessionExpired)
        XCTAssertEqual(controller.lastFailure, .sessionExpired)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
        XCTAssertNil(controller.secureAIAccessToken())
        XCTAssertTrue(diagnostics.events.contains(.sessionExpired))
    }

    func testPermissionDeniedDoesNotMisclassifyValidSessionAsExpired() async {
        let auth = MockSupabaseAuth(userID: userA)
        let controller = makeController(auth: auth)
        await controller.signInWithApple()
        auth.profileWriteFailure = .permissionDenied

        await controller.saveDisplayName("Safe Name")

        XCTAssertEqual(
            controller.snapshot.state,
            .signedInLocalDataNotBackedUp
        )
        XCTAssertEqual(controller.lastFailure, .permissionDenied)
        XCTAssertEqual(
            controller.snapshot.localDataOwnership,
            .migrationPending(dataSetID: dataSetID, targetUserID: userA)
        )
    }

    private func makeController(
        apple: MockAppleProvider? = nil,
        auth: MockSupabaseAuth,
        secureAIEnabled: Bool = false,
        diagnostics: DiagnosticsSpy = DiagnosticsSpy()
    ) -> StagingAccountController {
        let status = WayTaskCloudConfiguration.resolve(values: [
            WayTaskCloudConfiguration.environmentKey: "staging",
            WayTaskCloudConfiguration.projectURLKey: "https://staging.invalid",
            WayTaskCloudConfiguration.publishableKeyKey:
                "sb_publishable_staging_test_value"
        ])
        let flags = WayTaskCloudFeatureFlags(
            accountsEnabled: true,
            synchronizationEnabled: false,
            firstMigrationEnabled: false,
            secureAIRecognitionEnabled: secureAIEnabled
        )
        return StagingAccountController(
            foundation: WayTaskAccountSyncFoundation(
                configurationStatus: status,
                featureFlags: flags,
                dataSetID: dataSetID
            ),
            appleProvider: apple ?? MockAppleProvider(),
            authProvider: auth,
            diagnostics: diagnostics,
            internalStagingUIEnabled: true
        )
    }
}

@MainActor
private final class MockAppleProvider: AppleAuthorizationProviding {
    private let result: Result<AppleAuthorizationPayload, WayTaskAuthenticationFailure>?
    private let echoesChallengeState: Bool

    init(
        result: Result<AppleAuthorizationPayload, WayTaskAuthenticationFailure>? = nil,
        echoesChallengeState: Bool = true
    ) {
        self.result = result
        self.echoesChallengeState = echoesChallengeState
    }

    func authorize(
        challenge: AppleAuthenticationChallenge
    ) async throws -> AppleAuthorizationPayload {
        if let result {
            let payload = try result.get()
            if echoesChallengeState {
                return AppleAuthorizationPayload(
                    identityToken: payload.identityToken,
                    returnedState: challenge.state,
                    suggestedDisplayName: payload.suggestedDisplayName
                )
            }
            return payload
        }
        return AppleAuthorizationPayload(
            identityToken: "apple-test-identity-token",
            returnedState: challenge.state,
            suggestedDisplayName: nil
        )
    }
}

@MainActor
private final class MockSupabaseAuth: SupabaseAuthenticationProviding {
    let session: SecureSupabaseSession
    var restoration: SessionRestorationResult = .noStoredSession
    private(set) var signInCount = 0
    private(set) var restoreCount = 0
    private(set) var signOutCount = 0
    private(set) var profileWriteCount = 0
    private(set) var lastDisplayName: String?
    private(set) var lastProfileOwner: UUID?
    var profileWriteFailure: WayTaskAuthenticationFailure?

    init(userID: UUID) {
        session = SecureSupabaseSession(
            environment: .staging,
            projectOrigin: "https://staging.invalid",
            userID: userID,
            accessToken: "supabase-test-access-token",
            refreshToken: "supabase-test-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String
    ) async throws -> SecureSupabaseSession {
        signInCount += 1
        return session
    }

    func restoreSession() async throws -> SessionRestorationResult {
        restoreCount += 1
        return restoration
    }

    func signOut(session: SecureSupabaseSession) async throws {
        signOutCount += 1
    }

    func saveDisplayName(
        _ displayName: String,
        locale: String,
        session: SecureSupabaseSession
    ) async throws {
        profileWriteCount += 1
        if let profileWriteFailure { throw profileWriteFailure }
        lastDisplayName = displayName
        lastProfileOwner = session.userID
    }
}

private final class DiagnosticsSpy: AccountAuthDiagnosticsRecording {
    private(set) var events: [AccountAuthDiagnosticEvent] = []

    func record(
        _ event: AccountAuthDiagnosticEvent,
        failure: WayTaskAuthenticationFailure?
    ) {
        events.append(event)
    }
}

private final class OwnershipPersistenceSpy: LocalDataOwnershipPersisting {
    private(set) var lastSaved: LocalDataOwnershipState?

    func save(_ ownership: LocalDataOwnershipState) throws {
        lastSaved = ownership
    }
}
