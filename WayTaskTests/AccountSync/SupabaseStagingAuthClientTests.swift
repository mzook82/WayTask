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

    private func makeClient(store: InMemorySecureSessionStore) throws
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
            urlSession: URLSession(configuration: configuration)
        )
    }

    private func storedSession(
        environment: WayTaskCloudEnvironment
    ) -> SecureSupabaseSession {
        SecureSupabaseSession(
            environment: environment,
            projectOrigin: environment == .staging
                ? "https://staging.invalid"
                : "http://127.0.0.1:54321",
            userID: userID,
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    private static func tokenJSON(userID: UUID) -> [String: Any] {
        [
            "access_token": "test-access-token",
            "refresh_token": "test-refresh-token",
            "expires_in": 3_600,
            "expires_at": Date().addingTimeInterval(3_600).timeIntervalSince1970,
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
