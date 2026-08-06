import Foundation

struct UserIdentity: Equatable, Hashable, Sendable {
    let userID: UUID
    let providerSubject: String?

    init(userID: UUID, providerSubject: String? = nil) {
        self.userID = userID
        self.providerSubject = providerSubject
    }
}

enum AccountAuthenticationState: Equatable, Sendable {
    case guest
    case signedIn(identity: UserIdentity, expiresAt: Date?)
    case sessionExpired(lastKnownIdentity: UserIdentity)
    case deletionPending(identity: UserIdentity)
}

enum AccountAuthorizationState: Equatable, Sendable {
    case localDeviceOnly
    case ownerScoped(userID: UUID)
    case unavailable
}

enum LocalDataOwnershipState: Equatable, Sendable {
    case guestOnly(dataSetID: UUID)
    case migrationPending(dataSetID: UUID, targetUserID: UUID)
    case linked(dataSetID: UUID, ownerUserID: UUID)
}

enum SyncPauseReason: String, Equatable, Sendable {
    case featureDisabled
    case offline
    case userRequested
    case authenticationRequired
    case serviceUnavailable
}

enum SyncLifecycleState: Equatable, Sendable {
    case localOnly
    case signedInLocalDataNotBackedUp
    case initialMigrationPending
    case active
    case paused(SyncPauseReason)
    case recoverableError(WayTaskAccountSyncError)
    case accountDeletionPending
}

enum AccountSessionState: Equatable, Sendable {
    case guest
    case signedInLocalDataNotBackedUp
    case signedInInitialMigrationPending
    case signedInSynchronizationActive
    case signedInSynchronizationPaused
    case sessionExpired
    case recoverableSyncError
    case accountDeletionPending
}

struct AccountSessionSnapshot: Equatable, Sendable {
    let authentication: AccountAuthenticationState
    let authorization: AccountAuthorizationState
    let synchronization: SyncLifecycleState
    let localDataOwnership: LocalDataOwnershipState

    var state: AccountSessionState {
        switch (authentication, synchronization) {
        case (.guest, _):
            return .guest
        case (.sessionExpired, _):
            return .sessionExpired
        case (.deletionPending, _), (_, .accountDeletionPending):
            return .accountDeletionPending
        case (_, .signedInLocalDataNotBackedUp), (_, .localOnly):
            return .signedInLocalDataNotBackedUp
        case (_, .initialMigrationPending):
            return .signedInInitialMigrationPending
        case (_, .active):
            return .signedInSynchronizationActive
        case (_, .paused):
            return .signedInSynchronizationPaused
        case (_, .recoverableError):
            return .recoverableSyncError
        }
    }

    static func guest(dataSetID: UUID) -> AccountSessionSnapshot {
        AccountSessionSnapshot(
            authentication: .guest,
            authorization: .localDeviceOnly,
            synchronization: .localOnly,
            localDataOwnership: .guestOnly(dataSetID: dataSetID)
        )
    }
}

@MainActor
protocol AccountSessionProviding: AnyObject {
    var currentSession: AccountSessionSnapshot { get }
}

@MainActor
protocol AccountSessionAuthorizing: AccountSessionProviding {
    func acceptVerifiedSession(
        identity: UserIdentity,
        expiresAt: Date?
    )
    func markInitialMigrationPending()
    func markSynchronizationActive()
    func pauseSynchronization(_ reason: SyncPauseReason)
    func recordRecoverableSyncError(_ error: WayTaskAccountSyncError)
    func expireSession()
    func markAccountDeletionPending()
    func signOutPreservingLocalData()
}

@MainActor
final class LocalAccountSessionAuthority: AccountSessionAuthorizing {
    private(set) var currentSession: AccountSessionSnapshot

    init(dataSetID: UUID = UUID()) {
        currentSession = .guest(dataSetID: dataSetID)
    }

    func acceptVerifiedSession(
        identity: UserIdentity,
        expiresAt: Date?
    ) {
        let dataSetID = currentDataSetID
        let targetOwnership: LocalDataOwnershipState
        let synchronization: SyncLifecycleState

        switch currentSession.localDataOwnership {
        case .guestOnly:
            targetOwnership = .migrationPending(
                dataSetID: dataSetID,
                targetUserID: identity.userID
            )
            synchronization = .signedInLocalDataNotBackedUp
        case let .migrationPending(_, targetUserID):
            targetOwnership = currentSession.localDataOwnership
            synchronization = targetUserID == identity.userID
                ? .initialMigrationPending
                : .recoverableError(
                    WayTaskAccountSyncError(category: .permissionDenied)
                )
        case let .linked(_, ownerUserID):
            targetOwnership = currentSession.localDataOwnership
            synchronization = ownerUserID == identity.userID
                ? .paused(.featureDisabled)
                : .recoverableError(
                    WayTaskAccountSyncError(category: .permissionDenied)
                )
        }

        currentSession = AccountSessionSnapshot(
            authentication: .signedIn(
                identity: identity,
                expiresAt: expiresAt
            ),
            authorization: .ownerScoped(userID: identity.userID),
            synchronization: synchronization,
            localDataOwnership: targetOwnership
        )
    }

    func markInitialMigrationPending() {
        guard let identity = signedInIdentity,
              case let .migrationPending(_, targetUserID) =
                currentSession.localDataOwnership,
              targetUserID == identity.userID
        else {
            return
        }
        currentSession = AccountSessionSnapshot(
            authentication: currentSession.authentication,
            authorization: .ownerScoped(userID: identity.userID),
            synchronization: .initialMigrationPending,
            localDataOwnership: .migrationPending(
                dataSetID: currentDataSetID,
                targetUserID: identity.userID
            )
        )
    }

    func markSynchronizationActive() {
        guard let identity = signedInIdentity,
              localDataCanSynchronize(for: identity.userID)
        else {
            return
        }
        currentSession = AccountSessionSnapshot(
            authentication: currentSession.authentication,
            authorization: .ownerScoped(userID: identity.userID),
            synchronization: .active,
            localDataOwnership: .linked(
                dataSetID: currentDataSetID,
                ownerUserID: identity.userID
            )
        )
    }

    func pauseSynchronization(_ reason: SyncPauseReason) {
        guard let identity = signedInIdentity else { return }
        currentSession = AccountSessionSnapshot(
            authentication: currentSession.authentication,
            authorization: .ownerScoped(userID: identity.userID),
            synchronization: .paused(reason),
            localDataOwnership: currentSession.localDataOwnership
        )
    }

    func recordRecoverableSyncError(_ error: WayTaskAccountSyncError) {
        guard signedInIdentity != nil, error.retryEligibility != .none else {
            return
        }
        currentSession = AccountSessionSnapshot(
            authentication: currentSession.authentication,
            authorization: currentSession.authorization,
            synchronization: .recoverableError(error),
            localDataOwnership: currentSession.localDataOwnership
        )
    }

    func expireSession() {
        guard let identity = signedInIdentity else { return }
        currentSession = AccountSessionSnapshot(
            authentication: .sessionExpired(lastKnownIdentity: identity),
            authorization: .localDeviceOnly,
            synchronization: .paused(.authenticationRequired),
            localDataOwnership: currentSession.localDataOwnership
        )
    }

    func markAccountDeletionPending() {
        guard let identity = signedInIdentity else { return }
        currentSession = AccountSessionSnapshot(
            authentication: .deletionPending(identity: identity),
            authorization: .ownerScoped(userID: identity.userID),
            synchronization: .accountDeletionPending,
            localDataOwnership: currentSession.localDataOwnership
        )
    }

    func signOutPreservingLocalData() {
        currentSession = AccountSessionSnapshot(
            authentication: .guest,
            authorization: .localDeviceOnly,
            synchronization: .localOnly,
            localDataOwnership: currentSession.localDataOwnership
        )
    }

    private var signedInIdentity: UserIdentity? {
        switch currentSession.authentication {
        case let .signedIn(identity, _), let .deletionPending(identity):
            return identity
        case .guest, .sessionExpired:
            return nil
        }
    }

    private var currentDataSetID: UUID {
        switch currentSession.localDataOwnership {
        case let .guestOnly(dataSetID),
             let .migrationPending(dataSetID, _),
             let .linked(dataSetID, _):
            return dataSetID
        }
    }

    private func localDataCanSynchronize(for userID: UUID) -> Bool {
        switch currentSession.localDataOwnership {
        case .guestOnly:
            return false
        case let .migrationPending(_, targetUserID):
            return targetUserID == userID
        case let .linked(_, ownerUserID):
            return ownerUserID == userID
        }
    }
}

struct SyncConfiguration: Equatable, Sendable {
    let environment: WayTaskCloudEnvironment
    let maximumBatchRecordCount: Int
    let maximumBatchPayloadBytes: Int

    static func version1(environment: WayTaskCloudEnvironment)
        -> SyncConfiguration {
        SyncConfiguration(
            environment: environment,
            maximumBatchRecordCount: 500,
            maximumBatchPayloadBytes: 1_048_576
        )
    }
}

@MainActor
protocol CloudSyncProviding: AnyObject {
    var lifecycleState: SyncLifecycleState { get }
    var performedNetworkRequestCount: Int { get }

    func requestSynchronization() async throws
    func pause(_ reason: SyncPauseReason)
}

@MainActor
final class DisabledCloudSyncProvider: CloudSyncProviding {
    private(set) var lifecycleState: SyncLifecycleState = .localOnly
    private(set) var performedNetworkRequestCount = 0

    func requestSynchronization() async throws {
        lifecycleState = .paused(.featureDisabled)
        throw WayTaskAccountSyncError(category: .accountUnavailable)
    }

    func pause(_ reason: SyncPauseReason) {
        lifecycleState = .paused(reason)
    }
}

@MainActor
final class WayTaskAccountSyncFoundation {
    let configurationStatus: WayTaskCloudConfigurationStatus
    let featureFlags: WayTaskCloudFeatureFlags
    let accountSession: LocalAccountSessionAuthority
    let cloudSync: DisabledCloudSyncProvider

    init(
        configurationStatus: WayTaskCloudConfigurationStatus,
        featureFlags: WayTaskCloudFeatureFlags,
        dataSetID: UUID = UUID()
    ) {
        self.configurationStatus = configurationStatus
        self.featureFlags = featureFlags
        accountSession = LocalAccountSessionAuthority(dataSetID: dataSetID)
        cloudSync = DisabledCloudSyncProvider()
    }

    static func startup(bundle: Bundle = .main)
        -> WayTaskAccountSyncFoundation {
        let status = WayTaskCloudConfiguration.resolve(bundle: bundle)
        let flags = WayTaskCloudConfiguration.featureFlags(
            bundle: bundle,
            configurationStatus: status
        )
        return WayTaskAccountSyncFoundation(
            configurationStatus: status,
            featureFlags: flags
        )
    }
}
