import Foundation
import XCTest
@testable import WayTask

@MainActor
final class SupabaseStagingAuthClientTests: XCTestCase {
    private let userID = UUID(
        uuidString: "40000000-0000-0000-0000-000000000004"
    )!

    override func tearDown() {
        AuthMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAppleOIDCExchangeUsesFixedSupabaseEndpointAndPersistsSession()
        async throws {
        let store = InMemorySecureSessionStore()
        var capturedRequest: URLRequest?
        AuthMockURLProtocol.handler = { [userID] request in
            capturedRequest = request
            return Self.response(
                request: request,
                status: 200,
                json: Self.tokenJSON(userID: userID)
            )
        }
        let client = try makeClient(store: store)

        let session = try await client.signInWithApple(
            identityToken: "apple.identity.token.test-value",
            rawNonce: "cryptographically-random-raw-nonce"
        )

        XCTAssertEqual(session.userID, userID)
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://staging.invalid/auth/v1/token?grant_type=id_token"
        )
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "apikey"),
            "sb_publishable_staging_test_value"
        )
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(capturedRequest.flatMap(Self.bodyData))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(json["provider"], "apple")
        XCTAssertEqual(json["id_token"], "apple.identity.token.test-value")
        XCTAssertEqual(json["nonce"], "cryptographically-random-raw-nonce")
        XCTAssertNotNil(store.data)
    }

    func testRevokedOrMalformedJWTExpiresSessionAndClearsLocalToken() async throws {
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(storedSession(environment: .staging))
        var requestCount = 0
        AuthMockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request: request, status: 401, json: [:])
        }
        let client = try makeClient(store: store)

        let result = try await client.restoreSession()

        XCTAssertEqual(
            result,
            .expired(lastKnownIdentity: UserIdentity(userID: userID))
        )
        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(store.data)
    }

    func testWrongEnvironmentSessionFailsClosedWithoutNetworkRequest()
        async throws {
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(storedSession(environment: .local))
        var requestCount = 0
        AuthMockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request: request, status: 200, json: [:])
        }
        let client = try makeClient(store: store)

        do {
            _ = try await client.restoreSession()
            XCTFail("Wrong-environment session must fail closed")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .invalidConfiguration)
        }

        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(store.data)
    }

    func testWrongProjectOriginFailsClosedWithoutNetworkRequest() async throws {
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(
                environment: .staging,
                projectOrigin: "https://other-project.invalid"
            )
        )
        var requestCount = 0
        AuthMockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request: request, status: 200, json: [:])
        }
        let client = try makeClient(store: store)

        do {
            _ = try await client.restoreSession()
            XCTFail("Wrong-project session must fail closed")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .invalidConfiguration)
        }

        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(store.data)
    }

    func testFreshSessionVerifiesOnceWithoutRefresh() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        let original = storedSession(expiresAt: now.addingTimeInterval(3_600))
        store.data = try JSONEncoder().encode(original)
        var requestCount = 0
        AuthMockURLProtocol.handler = { [userID] request in
            requestCount += 1
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            return Self.response(
                request: request,
                status: 200,
                json: ["id": userID.uuidString]
            )
        }
        let client = try makeClient(store: store, now: { now })

        let result = try await client.restoreSession()

        XCTAssertEqual(result, .restored(original))
        XCTAssertEqual(requestCount, 1)
    }

    func testNearExpirySessionRefreshesOncePersistsRotationAndVerifies()
        async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(30))
        )
        var requestCount = 0
        AuthMockURLProtocol.handler = { [userID] request in
            requestCount += 1
            if request.url?.path == "/auth/v1/token" {
                XCTAssertEqual(
                    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                        .queryItems?.first?.value,
                    "refresh_token"
                )
                return Self.response(
                    request: request,
                    status: 200,
                    json: Self.tokenJSON(
                        userID: userID,
                        accessToken: "rotated-access-token",
                        refreshToken: "rotated-refresh-token",
                        expiresAt: now.addingTimeInterval(3_600)
                    )
                )
            }
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            return Self.response(
                request: request,
                status: 200,
                json: ["id": userID.uuidString]
            )
        }
        let client = try makeClient(store: store, now: { now })

        let result = try await client.restoreSession()
        guard case let .restored(refreshed) = result else {
            return XCTFail("Near-expiry session must refresh")
        }

        XCTAssertEqual(refreshed.accessToken, "rotated-access-token")
        XCTAssertEqual(refreshed.refreshToken, "rotated-refresh-token")
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(
            try JSONDecoder().decode(
                SecureSupabaseSession.self,
                from: XCTUnwrap(store.data)
            ),
            refreshed
        )
    }

    func testExpiredAccessTokenWithValidRefreshTokenRecovers() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(-1))
        )
        var requestCount = 0
        AuthMockURLProtocol.handler = { [userID] request in
            requestCount += 1
            if request.url?.path == "/auth/v1/token" {
                return Self.response(
                    request: request,
                    status: 200,
                    json: Self.tokenJSON(
                        userID: userID,
                        accessToken: "fresh-access-token",
                        refreshToken: "fresh-refresh-token",
                        expiresAt: now.addingTimeInterval(3_600)
                    )
                )
            }
            return Self.response(
                request: request,
                status: 200,
                json: ["id": userID.uuidString]
            )
        }
        let client = try makeClient(store: store, now: { now })

        guard case let .restored(session) = try await client.restoreSession()
        else {
            return XCTFail("Expired access token must recover with valid refresh")
        }

        XCTAssertEqual(session.accessToken, "fresh-access-token")
        XCTAssertEqual(requestCount, 2)
    }

    func testRefreshWhileOfflinePreservesStoredRetryMaterial() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        let originalData = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(30))
        )
        store.data = originalData
        var requestCount = 0
        AuthMockURLProtocol.handler = { _ in
            requestCount += 1
            throw URLError(.notConnectedToInternet)
        }
        let client = try makeClient(store: store, now: { now })

        let result = try await client.restoreSession()

        XCTAssertEqual(
            result,
            .offline(lastKnownIdentity: UserIdentity(userID: userID))
        )
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(store.data, originalData)
    }

    func testDeniedRefreshExpiresSessionWithoutRetryStorm() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(30))
        )
        var requestCount = 0
        AuthMockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request: request, status: 401, json: [:])
        }
        let client = try makeClient(store: store, now: { now })

        let result = try await client.restoreSession()

        XCTAssertEqual(
            result,
            .expired(lastKnownIdentity: UserIdentity(userID: userID))
        )
        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(store.data)
    }

    func testStaleAccessTokenRefreshesOnceThenVerifies() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(3_600))
        )
        var requestCount = 0
        AuthMockURLProtocol.handler = { [userID] request in
            requestCount += 1
            switch requestCount {
            case 1:
                XCTAssertEqual(request.url?.path, "/auth/v1/user")
                return Self.response(request: request, status: 401, json: [:])
            case 2:
                XCTAssertEqual(request.url?.path, "/auth/v1/token")
                return Self.response(
                    request: request,
                    status: 200,
                    json: Self.tokenJSON(
                        userID: userID,
                        accessToken: "refreshed-access-token",
                        refreshToken: "refreshed-refresh-token",
                        expiresAt: now.addingTimeInterval(3_600)
                    )
                )
            default:
                XCTAssertEqual(request.url?.path, "/auth/v1/user")
                return Self.response(
                    request: request,
                    status: 200,
                    json: ["id": userID.uuidString]
                )
            }
        }
        let client = try makeClient(store: store, now: { now })

        guard case let .restored(session) = try await client.restoreSession()
        else {
            return XCTFail("Stale access token must use one refresh recovery")
        }

        XCTAssertEqual(session.accessToken, "refreshed-access-token")
        XCTAssertEqual(requestCount, 3)
    }

    func testStaleAccessThenOfflineRefreshPreservesStoredRetryMaterial()
        async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        let originalData = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(3_600))
        )
        store.data = originalData
        var requestCount = 0
        AuthMockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                XCTAssertEqual(request.url?.path, "/auth/v1/user")
                return Self.response(request: request, status: 401, json: [:])
            }
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            throw URLError(.notConnectedToInternet)
        }
        let client = try makeClient(store: store, now: { now })

        let result = try await client.restoreSession()

        XCTAssertEqual(
            result,
            .offline(lastKnownIdentity: UserIdentity(userID: userID))
        )
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(store.data, originalData)
    }

    func testZeroUserIDTokenResponseIsRejectedAndNotPersisted() async throws {
        let store = InMemorySecureSessionStore()
        AuthMockURLProtocol.handler = { request in
            Self.response(
                request: request,
                status: 200,
                json: Self.tokenJSON(
                    userID: UUID(
                        uuidString: "00000000-0000-0000-0000-000000000000"
                    )!
                )
            )
        }
        let client = try makeClient(store: store)

        do {
            _ = try await client.signInWithApple(
                identityToken: "apple-id-token",
                rawNonce: "raw-nonce"
            )
            XCTFail("Zero user UUID must fail closed")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        XCTAssertNil(store.data)
    }

    func testVerifiedSubjectMismatchFailsClosedAndClearsSession() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(3_600))
        )
        AuthMockURLProtocol.handler = { request in
            Self.response(
                request: request,
                status: 200,
                json: ["id": UUID().uuidString]
            )
        }
        let client = try makeClient(store: store, now: { now })

        do {
            _ = try await client.restoreSession()
            XCTFail("Verified subject mismatch must fail closed")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        XCTAssertNil(store.data)
    }

    func testRefreshSubjectMismatchFailsClosedAndClearsSession() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = InMemorySecureSessionStore()
        store.data = try JSONEncoder().encode(
            storedSession(expiresAt: now.addingTimeInterval(30))
        )
        AuthMockURLProtocol.handler = { request in
            Self.response(
                request: request,
                status: 200,
                json: Self.tokenJSON(
                    userID: UUID(),
                    expiresAt: now.addingTimeInterval(3_600)
                )
            )
        }
        let client = try makeClient(store: store, now: { now })

        do {
            _ = try await client.restoreSession()
            XCTFail("Refresh subject mismatch must fail closed")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }

        XCTAssertNil(store.data)
    }

    func testProtectedRequestUnauthorizedClearsSessionAndRequiresReauth()
        async throws {
        let store = InMemorySecureSessionStore()
        let session = storedSession(environment: .staging)
        store.data = try JSONEncoder().encode(session)
        AuthMockURLProtocol.handler = { request in
            Self.response(request: request, status: 401, json: [:])
        }
        let client = try makeClient(store: store)

        do {
            try await client.saveDisplayName(
                "Safe Name",
                locale: "he-IL",
                session: session
            )
            XCTFail("Unauthorized protected request must require reauth")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .sessionExpired)
        }

        XCTAssertNil(store.data)
    }

    func testProtectedRequestForbiddenKeepsValidSession() async throws {
        let store = InMemorySecureSessionStore()
        let session = storedSession(environment: .staging)
        store.data = try JSONEncoder().encode(session)
        AuthMockURLProtocol.handler = { request in
            Self.response(request: request, status: 403, json: [:])
        }
        let client = try makeClient(store: store)

        do {
            try await client.saveDisplayName(
                "Safe Name",
                locale: "he-IL",
                session: session
            )
            XCTFail("RLS denial must remain permission denied")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .permissionDenied)
        }

        XCTAssertNotNil(store.data)
    }

    func testProfileTextIsEncodedAsJSONDataNotURLOrSQLSyntax() async throws {
        let store = InMemorySecureSessionStore()
        var capturedRequest: URLRequest?
        AuthMockURLProtocol.handler = { request in
            capturedRequest = request
            return Self.response(request: request, status: 204, json: [:])
        }
        let client = try makeClient(store: store)
        let value = "'; DROP TABLE profiles; -- <script>alert(1)</script>"

        try await client.saveDisplayName(
            value,
            locale: "he-IL",
            session: storedSession(environment: .staging)
        )

        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://staging.invalid/rest/v1/profiles?on_conflict=id"
        )
        let body = try XCTUnwrap(capturedRequest.flatMap(Self.bodyData))
        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [[String: Any]]
        )
        XCTAssertEqual(rows.first?["display_name"] as? String, value)
        XCTAssertEqual(
            rows.first?["owner_user_id"] as? String,
            userID.uuidString
        )
    }

    func testProviderErrorBodyNeverEscapesTypedErrorBoundary() async throws {
        let store = InMemorySecureSessionStore()
        AuthMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                response,
                Data("raw SQLSTATE JWT stack provider error".utf8)
            )
        }
        let client = try makeClient(store: store)

        do {
            _ = try await client.signInWithApple(
                identityToken: "apple.identity.token.test-value",
                rawNonce: "raw-nonce"
            )
            XCTFail("Server failure must be mapped")
        } catch let failure as WayTaskAuthenticationFailure {
            XCTAssertEqual(failure, .serviceUnavailable)
            XCTAssertFalse(failure.userFacingMessage.contains("SQLSTATE"))
            XCTAssertFalse(failure.userFacingMessage.contains("JWT"))
        }
    }

    private func makeClient(
        store: InMemorySecureSessionStore,
        now: @escaping () -> Date = Date.init
    ) throws
        -> SupabaseStagingAuthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockURLProtocol.self]
        return try SupabaseStagingAuthClient(
            configuration: WayTaskSupabaseConfiguration(
                environment: .staging,
                projectURL: URL(string: "https://staging.invalid")!,
                publishableKey: "sb_publishable_staging_test_value"
            ),
            sessionStore: store,
            urlSession: URLSession(configuration: configuration),
            now: now
        )
    }

    private func storedSession(
        environment: WayTaskCloudEnvironment = .staging,
        projectOrigin: String? = nil,
        expiresAt: Date = Date().addingTimeInterval(3_600)
    ) -> SecureSupabaseSession {
        SecureSupabaseSession(
            environment: environment,
            projectOrigin: projectOrigin ?? (environment == .staging
                ? "https://staging.invalid"
                : "http://127.0.0.1:54321"),
            userID: userID,
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: expiresAt
        )
    }

    private static func tokenJSON(
        userID: UUID,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        expiresAt: Date = Date().addingTimeInterval(3_600)
    ) -> [String: Any] {
        [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "expires_in": 3_600,
            "expires_at": expiresAt.timeIntervalSince1970,
            "token_type": "bearer",
            "user": ["id": userID.uuidString]
        ]
    }

    private static func response(
        request: URLRequest,
        status: Int,
        json: Any
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (
            response,
            (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        )
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class InMemorySecureSessionStore: SecureSessionStoring {
    var data: Data?

    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() throws { data = nil }
}

private final class AuthMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
