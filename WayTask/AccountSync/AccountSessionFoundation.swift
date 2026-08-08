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
    case signingIn
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
    case signingIn
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
        case (.signingIn, _):
            return .signingIn
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
    func beginSignIn()
    func cancelSignInPreservingLocalData()
    func acceptVerifiedSession(
        identity: UserIdentity,
        expiresAt: Date?
    )
    func markInitialMigrationPending()
    func markSynchronizationActive()
    func pauseSynchronization(_ reason: SyncPauseReason)
    func recordRecoverableSyncError(_ error: WayTaskAccountSyncError)
    func expireSession()
    func restoreExpiredSession(identity: UserIdentity)
    func markAccountDeletionPending()
    func signOutPreservingLocalData()
}

protocol LocalDataOwnershipPersisting: AnyObject {
    func save(_ ownership: LocalDataOwnershipState) throws
}

@MainActor
final class LocalAccountSessionAuthority: AccountSessionAuthorizing {
    private(set) var currentSession: AccountSessionSnapshot
    private let ownershipPersistence: LocalDataOwnershipPersisting?
    private var authenticationBeforeSignIn: AccountAuthenticationState?

    init(
        dataSetID: UUID = UUID(),
        initialOwnership: LocalDataOwnershipState? = nil,
        ownershipPersistence: LocalDataOwnershipPersisting? = nil
    ) {
        self.ownershipPersistence = ownershipPersistence
        let ownership = initialOwnership ?? .guestOnly(dataSetID: dataSetID)
        currentSession = AccountSessionSnapshot(
            authentication: .guest,
            authorization: .localDeviceOnly,
            synchronization: .localOnly,
            localDataOwnership: ownership
        )
    }

    func beginSignIn() {
        switch currentSession.authentication {
        case .guest, .sessionExpired:
            authenticationBeforeSignIn = currentSession.authentication
            currentSession = AccountSessionSnapshot(
                authentication: .signingIn,
                authorization: .localDeviceOnly,
                synchronization: currentSession.synchronization,
                localDataOwnership: currentSession.localDataOwnership
            )
        case .signingIn, .signedIn, .deletionPending:
            return
        }
    }

    func cancelSignInPreservingLocalData() {
        guard case .signingIn = currentSession.authentication else { return }
        let authentication = authenticationBeforeSignIn ?? .guest
        authenticationBeforeSignIn = nil
        currentSession = AccountSessionSnapshot(
            authentication: authentication,
            authorization: .localDeviceOnly,
            synchronization: synchronizationAfterCancelledSignIn(
                authentication: authentication
            ),
            localDataOwnership: currentSession.localDataOwnership
        )
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
            let pendingOwnership = LocalDataOwnershipState.migrationPending(
                dataSetID: dataSetID,
                targetUserID: identity.userID
            )
            if persist(pendingOwnership) {
                targetOwnership = pendingOwnership
                synchronization = .signedInLocalDataNotBackedUp
            } else {
                targetOwnership = currentSession.localDataOwnership
                synchronization = .recoverableError(
                    WayTaskAccountSyncError(category: .localPersistenceFailure)
                )
            }
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
        authenticationBeforeSignIn = nil
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

    func restoreExpiredSession(identity: UserIdentity) {
        currentSession = AccountSessionSnapshot(
            authentication: .sessionExpired(lastKnownIdentity: identity),
            authorization: .localDeviceOnly,
            synchronization: .paused(.authenticationRequired),
            localDataOwnership: currentSession.localDataOwnership
        )
        authenticationBeforeSignIn = nil
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
        authenticationBeforeSignIn = nil
    }

    private var signedInIdentity: UserIdentity? {
        switch currentSession.authentication {
        case let .signedIn(identity, _), let .deletionPending(identity):
            return identity
        case .guest, .signingIn, .sessionExpired:
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

    private func persist(_ ownership: LocalDataOwnershipState) -> Bool {
        guard let ownershipPersistence else { return true }
        do {
            try ownershipPersistence.save(ownership)
            return true
        } catch {
            return false
        }
    }

    private func synchronizationAfterCancelledSignIn(
        authentication: AccountAuthenticationState
    ) -> SyncLifecycleState {
        if case .sessionExpired = authentication {
            return .paused(.authenticationRequired)
        }
        return .localOnly
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
    let localOwnershipStorageAvailable: Bool

    init(
        configurationStatus: WayTaskCloudConfigurationStatus,
        featureFlags: WayTaskCloudFeatureFlags,
        dataSetID: UUID = UUID(),
        initialOwnership: LocalDataOwnershipState? = nil,
        ownershipPersistence: LocalDataOwnershipPersisting? = nil,
        localOwnershipStorageAvailable: Bool = true
    ) {
        self.configurationStatus = configurationStatus
        self.featureFlags = featureFlags
        self.localOwnershipStorageAvailable = localOwnershipStorageAvailable
        accountSession = LocalAccountSessionAuthority(
            dataSetID: dataSetID,
            initialOwnership: initialOwnership,
            ownershipPersistence: ownershipPersistence
        )
        cloudSync = DisabledCloudSyncProvider()
    }

    static func startup(bundle: Bundle = .main)
        -> WayTaskAccountSyncFoundation {
        let status = WayTaskCloudConfiguration.resolve(bundle: bundle)
        let flags = WayTaskCloudConfiguration.featureFlags(
            bundle: bundle,
            configurationStatus: status
        )
        do {
            let ownershipStore = try ProtectedLocalDataOwnershipStore.live()
            let ownership = try ownershipStore.loadOrCreate()
            return WayTaskAccountSyncFoundation(
                configurationStatus: status,
                featureFlags: flags,
                initialOwnership: ownership,
                ownershipPersistence: ownershipStore
            )
        } catch {
            return WayTaskAccountSyncFoundation(
                configurationStatus: status,
                featureFlags: .disabled,
                localOwnershipStorageAvailable: false
            )
        }
    }
}
