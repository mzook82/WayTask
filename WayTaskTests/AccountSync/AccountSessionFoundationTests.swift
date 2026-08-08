import Foundation
import XCTest
@testable import WayTask

@MainActor
final class AccountSessionFoundationTests: XCTestCase {
    private let dataSetID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let userID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    private let otherUserID = UUID(
        uuidString: "30000000-0000-0000-0000-000000000003"
    )!

    func testGuestIsTheDefaultAndHasOnlyLocalAuthorization() {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)

        XCTAssertEqual(authority.currentSession.state, .guest)
        XCTAssertEqual(
            authority.currentSession.authorization,
            .localDeviceOnly
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
    }

    func testVerifiedIdentityDoesNotSilentlyMigrateGuestData() {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)

        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userID),
            expiresAt: Date().addingTimeInterval(3_600)
        )

        XCTAssertEqual(
            authority.currentSession.state,
            .signedInLocalDataNotBackedUp
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
    }

    func testSigningInIsExplicitAndCancellationPreservesGuestOwnership() {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)

        authority.beginSignIn()
        XCTAssertEqual(authority.currentSession.state, .signingIn)
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )

        authority.cancelSignInPreservingLocalData()
        XCTAssertEqual(authority.currentSession.state, .guest)
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .guestOnly(dataSetID: dataSetID)
        )
    }

    func testMigrationActivePauseErrorAndDeletionTransitionsAreExplicit() {
        let authority = signedInAuthority()

        authority.markInitialMigrationPending()
        XCTAssertEqual(
            authority.currentSession.state,
            .signedInInitialMigrationPending
        )

        XCTAssertTrue(authority.markInitialMigrationCompleted())
        authority.markSynchronizationActive()
        XCTAssertEqual(
            authority.currentSession.state,
            .signedInSynchronizationActive
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .linked(dataSetID: dataSetID, ownerUserID: userID)
        )

        authority.pauseSynchronization(.offline)
        XCTAssertEqual(
            authority.currentSession.state,
            .signedInSynchronizationPaused
        )

        authority.recordRecoverableSyncError(
            WayTaskAccountSyncError(category: .partialSync)
        )
        XCTAssertEqual(authority.currentSession.state, .recoverableSyncError)

        authority.markAccountDeletionPending()
        XCTAssertEqual(
            authority.currentSession.state,
            .accountDeletionPending
        )
    }

    func testSessionExpirationAndSignOutPreserveLocalData() {
        let authority = signedInAuthority()
        authority.markInitialMigrationPending()
        XCTAssertTrue(authority.markInitialMigrationCompleted())
        authority.markSynchronizationActive()

        authority.expireSession()
        XCTAssertEqual(authority.currentSession.state, .sessionExpired)
        XCTAssertEqual(
            authority.currentSession.authorization,
            .localDeviceOnly
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .linked(dataSetID: dataSetID, ownerUserID: userID)
        )

        authority.signOutPreservingLocalData()
        XCTAssertEqual(authority.currentSession.state, .guest)
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .linked(dataSetID: dataSetID, ownerUserID: userID)
        )
    }

    func testLinkedLocalDataCannotBeRetargetedToAnotherAccount() {
        let authority = signedInAuthority()
        authority.markInitialMigrationPending()
        XCTAssertTrue(authority.markInitialMigrationCompleted())
        authority.markSynchronizationActive()
        authority.signOutPreservingLocalData()

        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: otherUserID),
            expiresAt: nil
        )
        authority.markInitialMigrationPending()
        authority.markSynchronizationActive()

        XCTAssertEqual(authority.currentSession.state, .recoverableSyncError)
        XCTAssertEqual(
            authority.currentSession.authorization,
            .ownerScoped(userID: otherUserID)
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .linked(dataSetID: dataSetID, ownerUserID: userID)
        )
    }

    func testLinkedLocalDataCanResumeOnlyForItsExistingOwner() {
        let authority = signedInAuthority()
        authority.markInitialMigrationPending()
        XCTAssertTrue(authority.markInitialMigrationCompleted())
        authority.markSynchronizationActive()
        authority.signOutPreservingLocalData()

        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userID),
            expiresAt: nil
        )

        XCTAssertEqual(
            authority.currentSession.state,
            .signedInSynchronizationPaused
        )
        XCTAssertEqual(
            authority.currentSession.localDataOwnership,
            .linked(dataSetID: dataSetID, ownerUserID: userID)
        )
    }

    func testDisabledCloudProviderNeverMakesNetworkRequest() async {
        let provider = DisabledCloudSyncProvider()

        do {
            try await provider.requestSynchronization()
            XCTFail("Disabled provider must fail closed")
        } catch let error as WayTaskAccountSyncError {
            XCTAssertEqual(error.category, .accountUnavailable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(provider.performedNetworkRequestCount, 0)
        XCTAssertEqual(provider.lifecycleState, .paused(.featureDisabled))
    }

    private func signedInAuthority() -> LocalAccountSessionAuthority {
        let authority = LocalAccountSessionAuthority(dataSetID: dataSetID)
        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: userID),
            expiresAt: nil
        )
        return authority
    }
}
