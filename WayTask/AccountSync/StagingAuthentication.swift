import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import OSLog
import Security
import UIKit

enum WayTaskAuthenticationFailure: Error, Equatable, Sendable {
    case cancelled
    case offline
    case serviceUnavailable
    case invalidConfiguration
    case invalidAppleCredential
    case stateMismatch
    case sessionExpired
    case permissionDenied
    case rateLimited
    case invalidResponse
    case secureStorageUnavailable
    case localOwnershipUnavailable

    var userFacingTitle: String {
        switch self {
        case .cancelled: "Sign in cancelled"
        case .offline: "You’re offline"
        case .serviceUnavailable: "Account service unavailable"
        case .invalidConfiguration: "Staging is not configured"
        case .invalidAppleCredential, .stateMismatch:
            "Sign in could not be verified"
        case .sessionExpired: "Session expired"
        case .permissionDenied: "Account access unavailable"
        case .rateLimited: "Please wait before retrying"
        case .invalidResponse: "Sign in could not be completed"
        case .secureStorageUnavailable: "Secure storage unavailable"
        case .localOwnershipUnavailable: "Local data protection unavailable"
        }
    }

    var userFacingMessage: String {
        switch self {
        case .cancelled:
            "Nothing changed. You can continue as Guest."
        case .offline:
            "Your local data is still available. Connect to the internet and try again."
        case .serviceUnavailable, .invalidResponse:
            "Your local data is safe. Try again later."
        case .invalidConfiguration:
            "This internal build is missing its staging account configuration."
        case .invalidAppleCredential, .stateMismatch:
            "No account changes were made. Try Sign in with Apple again."
        case .sessionExpired:
            "Sign in again to restore account access. Your local data remains on this device."
        case .permissionDenied:
            "Sign in again or contact support if this continues."
        case .rateLimited:
            "Too many attempts were made. Wait a moment, then try again."
        case .secureStorageUnavailable:
            "WayTask could not securely save the session. Guest Mode is still available."
        case .localOwnershipUnavailable:
            "WayTask cannot safely bind this local dataset to an account. Guest Mode remains available."
        }
    }
}

enum AccountAuthDiagnosticEvent: String, Sendable {
    case authStarted = "auth_started"
    case authSucceeded = "auth_succeeded"
    case authCancelled = "auth_cancelled"
    case authFailed = "auth_failed"
    case sessionRestored = "session_restored"
    case sessionExpired = "session_expired"
    case signedOut = "signed_out"
    case migrationPending = "migration_pending"
}

protocol AccountAuthDiagnosticsRecording: AnyObject {
    func record(
        _ event: AccountAuthDiagnosticEvent,
        failure: WayTaskAuthenticationFailure?
    )
}

final class PrivacySafeAccountAuthDiagnostics: AccountAuthDiagnosticsRecording {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WayTask",
        category: "StagingAccount"
    )

    func record(
        _ event: AccountAuthDiagnosticEvent,
        failure: WayTaskAuthenticationFailure? = nil
    ) {
        if let failure {
            logger.notice(
                "\(event.rawValue, privacy: .public) category=\(String(describing: failure), privacy: .public)"
            )
        } else {
            logger.notice("\(event.rawValue, privacy: .public)")
        }
    }
}

struct AppleAuthenticationChallenge: Equatable, Sendable {
    let rawNonce: String
    let hashedNonce: String
    let state: String
}

enum AppleAuthenticationSecurity {
    nonisolated static func makeChallenge() throws
        -> AppleAuthenticationChallenge {
        let nonce = try secureRandomURLSafeString(byteCount: 32)
        return AppleAuthenticationChallenge(
            rawNonce: nonce,
            hashedNonce: sha256(nonce),
            state: try secureRandomURLSafeString(byteCount: 32)
        )
    }

    nonisolated static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated static func securelyMatches(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { result, values in
            result | (values.0 ^ values.1)
        } == 0
    }

    private nonisolated static func secureRandomURLSafeString(
        byteCount: Int
    ) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        ) == errSecSuccess else {
            throw WayTaskAuthenticationFailure.secureStorageUnavailable
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct AppleAuthorizationPayload: Equatable, Sendable {
    let identityToken: String
    let returnedState: String
    let suggestedDisplayName: String?
}

@MainActor
protocol AppleAuthorizationProviding: AnyObject {
    func authorize(
        challenge: AppleAuthenticationChallenge
    ) async throws -> AppleAuthorizationPayload
}

@MainActor
final class NativeAppleAuthorizationProvider: NSObject,
    AppleAuthorizationProviding,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation:
        CheckedContinuation<AppleAuthorizationPayload, Error>?
    private var authorizationController: ASAuthorizationController?

    func authorize(
        challenge: AppleAuthenticationChallenge
    ) async throws -> AppleAuthorizationPayload {
        guard continuation == nil else {
            throw WayTaskAuthenticationFailure.serviceUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = challenge.hashedNonce
            request.state = challenge.state

            let controller = ASAuthorizationController(
                authorizationRequests: [request]
            )
            controller.delegate = self
            controller.presentationContextProvider = self
            self.authorizationController = controller
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
            as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty,
              let state = credential.state,
              !state.isEmpty else {
            finish(throwing: .invalidAppleCredential)
            return
        }

        let suggestedName = credential.fullName.flatMap { components in
            let formatter = PersonNameComponentsFormatter()
            let value = formatter.string(from: components)
            return value.isEmpty ? nil : value
        }
        // Apple email/private-relay values are intentionally left to Supabase
        // Auth. They are not required, displayed, persisted, or logged here.
        finish(
            returning: AppleAuthorizationPayload(
                identityToken: identityToken,
                returnedState: state,
                suggestedDisplayName: suggestedName
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(throwing: .cancelled)
        } else {
            finish(throwing: .invalidAppleCredential)
        }
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        if let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }
        // The provider is invoked from a visible control, so a connected scene
        // is an invariant when the presentation context is requested.
        return ASPresentationAnchor(windowScene: scenes[0])
    }

    private func finish(returning payload: AppleAuthorizationPayload) {
        let continuation = self.continuation
        self.continuation = nil
        authorizationController = nil
        continuation?.resume(returning: payload)
    }

    private func finish(throwing failure: WayTaskAuthenticationFailure) {
        let continuation = self.continuation
        self.continuation = nil
        authorizationController = nil
        continuation?.resume(throwing: failure)
    }
}

struct SecureSupabaseSession: Codable, Equatable, Sendable {
    let environment: WayTaskCloudEnvironment
    let projectOrigin: String
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum SessionRestorationResult: Equatable, Sendable {
    case noStoredSession
    case restored(SecureSupabaseSession)
    case offline(lastKnownIdentity: UserIdentity)
    case expired(lastKnownIdentity: UserIdentity)
}

@MainActor
protocol SupabaseAuthenticationProviding: AnyObject {
    func signInWithApple(
        identityToken: String,
        rawNonce: String
    ) async throws -> SecureSupabaseSession
    func restoreSession() async throws -> SessionRestorationResult
    func signOut(session: SecureSupabaseSession) async throws
    func saveDisplayName(
        _ displayName: String,
        locale: String,
        session: SecureSupabaseSession
    ) async throws
}

final class SupabaseStagingAuthClient: SupabaseAuthenticationProviding,
    @unchecked Sendable {
    private static let zeroUUID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    private let configuration: WayTaskSupabaseConfiguration
    private let sessionStore: SecureSessionStoring
    private let urlSession: URLSession
    private let now: () -> Date
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: WayTaskSupabaseConfiguration,
        sessionStore: SecureSessionStoring = KeychainSessionStore(),
        urlSession: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) throws {
        guard configuration.environment == .local ||
                configuration.environment == .staging else {
            throw WayTaskAuthenticationFailure.invalidConfiguration
        }
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.now = now
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String
    ) async throws -> SecureSupabaseSession {
        guard !identityToken.isEmpty, !rawNonce.isEmpty else {
            throw WayTaskAuthenticationFailure.invalidAppleCredential
        }
        let request = try makeJSONRequest(
            url: endpoint("auth", "v1", "token", query: [
                URLQueryItem(name: "grant_type", value: "id_token")
            ]),
            method: "POST",
            body: AppleTokenExchangeRequest(
                provider: "apple",
                identityToken: identityToken,
                nonce: rawNonce
            ),
            accessToken: nil
        )
        let data = try await send(request, operation: .signIn)
        let response: TokenResponse = try decode(data)
        let session = try makeSession(response)
        try persist(session)
        return session
    }

    func restoreSession() async throws -> SessionRestorationResult {
        guard let data = try sessionStore.read() else {
            return .noStoredSession
        }
        let stored: SecureSupabaseSession
        do {
            stored = try decoder.decode(SecureSupabaseSession.self, from: data)
        } catch {
            try deleteStoredSession()
            throw WayTaskAuthenticationFailure.secureStorageUnavailable
        }
        guard matchesCurrentConfiguration(stored) else {
            try deleteStoredSession()
            throw WayTaskAuthenticationFailure.invalidConfiguration
        }

        let identity = UserIdentity(userID: stored.userID)
        do {
            var candidate = stored
            if candidate.expiresAt <= now().addingTimeInterval(60) {
                candidate = try await refresh(candidate)
            }
            do {
                try await verify(candidate)
            } catch WayTaskAuthenticationFailure.sessionExpired {
                candidate = try await refresh(candidate)
                try await verify(candidate)
            }
            return .restored(candidate)
        } catch let failure as WayTaskAuthenticationFailure {
            switch failure {
            case .offline:
                return .offline(lastKnownIdentity: identity)
            case .sessionExpired:
                try deleteStoredSession()
                return .expired(lastKnownIdentity: identity)
            case .invalidResponse, .invalidConfiguration:
                try deleteStoredSession()
                throw failure
            default:
                throw failure
            }
        }
    }

    func signOut(session: SecureSupabaseSession) async throws {
        var networkFailure: WayTaskAuthenticationFailure?
        do {
            var request = URLRequest(
                url: endpoint("auth", "v1", "logout", query: [
                    URLQueryItem(name: "scope", value: "local")
                ])
            )
            request.httpMethod = "POST"
            addClientHeaders(to: &request, accessToken: session.accessToken)
            _ = try await send(request, operation: .signOut)
        } catch let failure as WayTaskAuthenticationFailure {
            networkFailure = failure
        } catch {
            networkFailure = .serviceUnavailable
        }

        try deleteStoredSession()
        if let networkFailure { throw networkFailure }
    }

    func saveDisplayName(
        _ displayName: String,
        locale: String,
        session: SecureSupabaseSession
    ) async throws {
        guard matchesCurrentConfiguration(session),
              session.expiresAt > now() else {
            throw WayTaskAuthenticationFailure.sessionExpired
        }
        let request = try makeJSONRequest(
            url: endpoint("rest", "v1", "profiles", query: [
                URLQueryItem(name: "on_conflict", value: "id")
            ]),
            method: "POST",
            body: [
                ProfileWrite(
                    id: session.userID,
                    ownerUserID: session.userID,
                    displayName: displayName,
                    locale: locale
                )
            ],
            accessToken: session.accessToken,
            additionalHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        )
        _ = try await send(request, operation: .profileWrite)
    }

    private func refresh(
        _ session: SecureSupabaseSession
    ) async throws -> SecureSupabaseSession {
        let request = try makeJSONRequest(
            url: endpoint("auth", "v1", "token", query: [
                URLQueryItem(name: "grant_type", value: "refresh_token")
            ]),
            method: "POST",
            body: RefreshRequest(refreshToken: session.refreshToken),
            accessToken: nil
        )
        let data = try await send(request, operation: .restore)
        let response: TokenResponse = try decode(data)
        let refreshed = try makeSession(response)
        guard refreshed.userID == session.userID else {
            throw WayTaskAuthenticationFailure.invalidResponse
        }
        try persist(refreshed)
        return refreshed
    }

    private func verify(_ session: SecureSupabaseSession) async throws {
        var request = URLRequest(url: endpoint("auth", "v1", "user"))
        request.httpMethod = "GET"
        addClientHeaders(to: &request, accessToken: session.accessToken)
        let data = try await send(request, operation: .restore)
        let user: AuthUser = try decode(data)
        guard user.id == session.userID else {
            throw WayTaskAuthenticationFailure.invalidResponse
        }
    }

    private func makeSession(_ response: TokenResponse) throws
        -> SecureSupabaseSession {
        guard !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              response.tokenType.lowercased() == "bearer",
              response.user.id != Self.zeroUUID,
              response.accessToken.unicodeScalars.allSatisfy({
                  !CharacterSet.whitespacesAndNewlines.contains($0) &&
                      !CharacterSet.controlCharacters.contains($0)
              }),
              response.refreshToken.unicodeScalars.allSatisfy({
                  !CharacterSet.whitespacesAndNewlines.contains($0) &&
                      !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw WayTaskAuthenticationFailure.invalidResponse
        }
        let expiresAt = response.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? now().addingTimeInterval(TimeInterval(response.expiresIn))
        guard expiresAt > now() else {
            throw WayTaskAuthenticationFailure.sessionExpired
        }
        return SecureSupabaseSession(
            environment: configuration.environment,
            projectOrigin: projectOrigin,
            userID: response.user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAt
        )
    }

    private func persist(_ session: SecureSupabaseSession) throws {
        do {
            try sessionStore.write(try encoder.encode(session))
        } catch {
            throw WayTaskAuthenticationFailure.secureStorageUnavailable
        }
    }

    private func deleteStoredSession() throws {
        do {
            try sessionStore.delete()
        } catch {
            throw WayTaskAuthenticationFailure.secureStorageUnavailable
        }
    }

    private func matchesCurrentConfiguration(
        _ session: SecureSupabaseSession
    ) -> Bool {
        session.environment == configuration.environment &&
            session.projectOrigin == projectOrigin
    }

    private var projectOrigin: String {
        var components = URLComponents(
            url: configuration.projectURL,
            resolvingAgainstBaseURL: false
        )!
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url!.absoluteString
    }

    private func endpoint(
        _ path: String...,
        query: [URLQueryItem] = []
    ) -> URL {
        var url = configuration.projectURL
        for component in path {
            url.appendPathComponent(component, isDirectory: false)
        }
        guard !query.isEmpty else { return url }
        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query
        return components.url!
    }

    private func makeJSONRequest<Body: Encodable>(
        url: URL,
        method: String,
        body: Body,
        accessToken: String?,
        additionalHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = method
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addClientHeaders(to: &request, accessToken: accessToken)
        additionalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    private func addClientHeaders(
        to request: inout URLRequest,
        accessToken: String?
    ) {
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
    }

    private func send(
        _ request: URLRequest,
        operation: NetworkOperation
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw WayTaskAuthenticationFailure.cancelled
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                    .dataNotAllowed, .internationalRoamingOff:
                throw WayTaskAuthenticationFailure.offline
            case .cancelled:
                throw WayTaskAuthenticationFailure.cancelled
            default:
                throw WayTaskAuthenticationFailure.serviceUnavailable
            }
        } catch {
            throw WayTaskAuthenticationFailure.serviceUnavailable
        }
        guard data.count <= 128 * 1_024,
              let http = response as? HTTPURLResponse else {
            throw WayTaskAuthenticationFailure.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            if operation.invalidatesSessionOnUnauthorized {
                try deleteStoredSession()
            }
            throw operation == .signIn
                ? WayTaskAuthenticationFailure.permissionDenied
                : WayTaskAuthenticationFailure.sessionExpired
        case 403:
            throw WayTaskAuthenticationFailure.permissionDenied
        case 429:
            throw WayTaskAuthenticationFailure.rateLimited
        case 400 where operation == .signIn:
            throw WayTaskAuthenticationFailure.invalidAppleCredential
        case 500...599:
            throw WayTaskAuthenticationFailure.serviceUnavailable
        default:
            throw WayTaskAuthenticationFailure.invalidResponse
        }
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw WayTaskAuthenticationFailure.invalidResponse
        }
    }

    private enum NetworkOperation: Equatable {
        case signIn
        case restore
        case signOut
        case profileWrite

        var invalidatesSessionOnUnauthorized: Bool {
            self == .signOut || self == .profileWrite
        }
    }
}

private struct AppleTokenExchangeRequest: Encodable {
    let provider: String
    let identityToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case identityToken = "id_token"
        case nonce
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct ProfileWrite: Encodable {
    let id: UUID
    let ownerUserID: UUID
    let displayName: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case displayName = "display_name"
        case locale
    }
}

private struct AuthUser: Decodable {
    let id: UUID
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Double?
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
        case user
    }
}

@MainActor
final class StagingAccountController: ObservableObject {
    nonisolated static var compiledForInternalStaging: Bool {
        #if STAGING
        true
        #else
        false
        #endif
    }

    static let shared = StagingAccountController.makeLive()

    @Published private(set) var snapshot: AccountSessionSnapshot
    @Published private(set) var lastFailure: WayTaskAuthenticationFailure?
    @Published private(set) var suggestedDisplayName: String?
    @Published private(set) var savedDisplayName: String?
    @Published private(set) var profileValidationError:
        IdentityProfileValidationError?
    @Published private(set) var isRestoring = false

    let configurationStatus: WayTaskCloudConfigurationStatus
    let featureFlags: WayTaskCloudFeatureFlags
    let internalStagingUIEnabled: Bool

    private let authority: LocalAccountSessionAuthority
    private let appleProvider: AppleAuthorizationProviding
    private let authProvider: SupabaseAuthenticationProviding?
    private let diagnostics: AccountAuthDiagnosticsRecording
    private var secureSession: SecureSupabaseSession?
    private var hasAttemptedRestoration = false
    private var expirationTask: Task<Void, Never>?

    init(
        foundation: WayTaskAccountSyncFoundation,
        appleProvider: AppleAuthorizationProviding,
        authProvider: SupabaseAuthenticationProviding?,
        diagnostics: AccountAuthDiagnosticsRecording,
        internalStagingUIEnabled: Bool
    ) {
        authority = foundation.accountSession
        snapshot = foundation.accountSession.currentSession
        configurationStatus = foundation.configurationStatus
        featureFlags = foundation.featureFlags
        self.appleProvider = appleProvider
        self.authProvider = foundation.localOwnershipStorageAvailable
            ? authProvider
            : nil
        self.diagnostics = diagnostics
        self.internalStagingUIEnabled = internalStagingUIEnabled
        if !foundation.localOwnershipStorageAvailable {
            lastFailure = .localOwnershipUnavailable
        }
    }

    static func makeLive() -> StagingAccountController {
        let foundation = WayTaskAccountSyncFoundation.startup()
        let authProvider: SupabaseAuthenticationProviding?
        if compiledForInternalStaging,
           foundation.featureFlags.accountsEnabled,
           case let .configured(configuration) = foundation.configurationStatus,
           foundation.configurationStatus.permitsStagingAuthentication {
            authProvider = try? SupabaseStagingAuthClient(
                configuration: configuration
            )
        } else {
            authProvider = nil
        }
        return StagingAccountController(
            foundation: foundation,
            appleProvider: NativeAppleAuthorizationProvider(),
            authProvider: authProvider,
            diagnostics: PrivacySafeAccountAuthDiagnostics(),
            internalStagingUIEnabled: compiledForInternalStaging
        )
    }

    var canStartAuthentication: Bool {
        internalStagingUIEnabled &&
            featureFlags.accountsEnabled &&
            configurationStatus.permitsStagingAuthentication &&
            authProvider != nil &&
            snapshot.state != .signingIn
    }

    var environmentLabel: String {
        configurationStatus.environment?.rawValue.capitalized ?? "Unavailable"
    }

    func restoreSessionIfNeeded(force: Bool = false) async {
        guard force || !hasAttemptedRestoration else { return }
        hasAttemptedRestoration = true
        guard canUseAuthProvider, let authProvider else { return }

        isRestoring = true
        defer { isRestoring = false }
        do {
            switch try await authProvider.restoreSession() {
            case .noStoredSession:
                return
            case let .restored(session):
                accept(session)
                lastFailure = nil
                diagnostics.record(.sessionRestored, failure: nil)
            case let .offline(identity):
                secureSession = nil
                authority.restoreExpiredSession(identity: identity)
                publishSnapshot()
                lastFailure = .offline
            case let .expired(identity):
                secureSession = nil
                authority.restoreExpiredSession(identity: identity)
                publishSnapshot()
                lastFailure = .sessionExpired
                diagnostics.record(.sessionExpired, failure: .sessionExpired)
            }
        } catch let failure as WayTaskAuthenticationFailure {
            handleAuthenticatedOperationFailure(failure)
        } catch {
            lastFailure = .serviceUnavailable
        }
    }

    func signInWithApple() async {
        guard canUseAuthProvider, let authProvider else {
            lastFailure = configurationStatus.permitsStagingAuthentication
                ? .serviceUnavailable
                : .invalidConfiguration
            return
        }
        authority.beginSignIn()
        publishSnapshot()
        lastFailure = nil
        diagnostics.record(.authStarted, failure: nil)

        do {
            let challenge = try AppleAuthenticationSecurity.makeChallenge()
            let apple = try await appleProvider.authorize(
                challenge: challenge
            )
            guard AppleAuthenticationSecurity.securelyMatches(
                apple.returnedState,
                challenge.state
            ) else {
                throw WayTaskAuthenticationFailure.stateMismatch
            }
            let session = try await authProvider.signInWithApple(
                identityToken: apple.identityToken,
                rawNonce: challenge.rawNonce
            )
            if let value = apple.suggestedDisplayName {
                suggestedDisplayName = try? IdentityProfileValidationContract
                    .normalizeDisplayName(value)
            }
            accept(session)
            diagnostics.record(.authSucceeded, failure: nil)
            diagnostics.record(.migrationPending, failure: nil)
        } catch WayTaskAuthenticationFailure.cancelled {
            authority.cancelSignInPreservingLocalData()
            publishSnapshot()
            lastFailure = nil
            diagnostics.record(.authCancelled, failure: nil)
        } catch let failure as WayTaskAuthenticationFailure {
            authority.cancelSignInPreservingLocalData()
            publishSnapshot()
            lastFailure = failure
            diagnostics.record(.authFailed, failure: failure)
        } catch {
            authority.cancelSignInPreservingLocalData()
            publishSnapshot()
            lastFailure = .serviceUnavailable
            diagnostics.record(.authFailed, failure: .serviceUnavailable)
        }
    }

    func saveDisplayName(_ input: String, locale: String = "he-IL") async {
        guard let secureSession, let authProvider else {
            lastFailure = .sessionExpired
            return
        }
        do {
            let normalized = try IdentityProfileValidationContract
                .normalizeDisplayName(input)
            try await authProvider.saveDisplayName(
                normalized,
                locale: locale,
                session: secureSession
            )
            savedDisplayName = normalized
            suggestedDisplayName = nil
            profileValidationError = nil
            lastFailure = nil
        } catch let validation as IdentityProfileValidationError {
            profileValidationError = validation
            lastFailure = nil
        } catch let failure as WayTaskAuthenticationFailure {
            handleAuthenticatedOperationFailure(failure)
        } catch {
            lastFailure = .serviceUnavailable
        }
    }

    func normalizedDisplayName(
        _ input: String
    ) throws -> String {
        try IdentityProfileValidationContract.normalizeDisplayName(input)
    }

    func signOut() async {
        let session = secureSession
        secureSession = nil
        expirationTask?.cancel()
        expirationTask = nil
        authority.signOutPreservingLocalData()
        publishSnapshot()
        suggestedDisplayName = nil
        savedDisplayName = nil

        if let session, let authProvider {
            do {
                try await authProvider.signOut(session: session)
                lastFailure = nil
            } catch let failure as WayTaskAuthenticationFailure {
                lastFailure = failure
            } catch {
                lastFailure = .serviceUnavailable
            }
        } else {
            lastFailure = nil
        }
        diagnostics.record(.signedOut, failure: lastFailure)
    }

    func secureAIAccessToken() -> String? {
        guard internalStagingUIEnabled,
              featureFlags.secureAIRecognitionEnabled,
              configurationStatus.environment == .staging,
              let secureSession,
              secureSession.expiresAt > Date().addingTimeInterval(30),
              case .signedIn = snapshot.authentication else {
            return nil
        }
        return secureSession.accessToken
    }

    #if DEBUG
    func markCurrentSessionExpiredForTesting() {
        guard let secureSession else { return }
        self.secureSession = nil
        authority.restoreExpiredSession(
            identity: UserIdentity(userID: secureSession.userID)
        )
        publishSnapshot()
        lastFailure = .sessionExpired
        diagnostics.record(.sessionExpired, failure: .sessionExpired)
    }
    #endif

    private var canUseAuthProvider: Bool {
        internalStagingUIEnabled &&
            featureFlags.accountsEnabled &&
            configurationStatus.permitsStagingAuthentication &&
            authProvider != nil
    }

    private func accept(_ session: SecureSupabaseSession) {
        secureSession = session
        authority.acceptVerifiedSession(
            identity: UserIdentity(userID: session.userID),
            expiresAt: session.expiresAt
        )
        publishSnapshot()
        lastFailure = nil
        scheduleExpiration(for: session)
    }

    private func handleAuthenticatedOperationFailure(
        _ failure: WayTaskAuthenticationFailure
    ) {
        switch failure {
        case .sessionExpired, .secureStorageUnavailable,
             .invalidConfiguration, .invalidResponse:
            guard let session = secureSession else {
                lastFailure = failure
                return
            }
            secureSession = nil
            expirationTask?.cancel()
            expirationTask = nil
            suggestedDisplayName = nil
            savedDisplayName = nil
            authority.restoreExpiredSession(
                identity: UserIdentity(userID: session.userID)
            )
            publishSnapshot()
            lastFailure = failure
            diagnostics.record(.sessionExpired, failure: failure)
        default:
            lastFailure = failure
        }
    }

    private func publishSnapshot() {
        snapshot = authority.currentSession
    }

    private func scheduleExpiration(for session: SecureSupabaseSession) {
        expirationTask?.cancel()
        let delay = max(0, session.expiresAt.timeIntervalSinceNow)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(min(delay, 86_400) * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            await self.restoreSessionIfNeeded(force: true)
        }
    }
}
