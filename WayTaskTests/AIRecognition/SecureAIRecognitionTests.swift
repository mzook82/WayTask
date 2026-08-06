import Foundation
import UIKit
import XCTest
@testable import WayTask

@MainActor
final class SecureAIRecognitionTests: XCTestCase {
    override func tearDown() {
        SecureAIMockURLProtocol.requestHandler = nil
        SecureAIMockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testPolicyDefaultsOffRequiresAccountsAndRejectsProduction() {
        let cloud = WayTaskCloudConfiguration.resolve(values: [
            WayTaskCloudConfiguration.environmentKey: "staging",
            WayTaskCloudConfiguration.projectURLKey: "https://staging.invalid",
            WayTaskCloudConfiguration.publishableKeyKey:
                "sb_publishable_staging_test_value"
        ])

        XCTAssertEqual(
            SecureAIRecognitionPolicy.resolve(
                cloudStatus: cloud,
                flags: .disabled
            ),
            .disabled
        )

        let noAccounts = WayTaskCloudFeatureFlags(
            accountsEnabled: false,
            synchronizationEnabled: false,
            firstMigrationEnabled: false,
            secureAIRecognitionEnabled: true
        )
        XCTAssertEqual(
            SecureAIRecognitionPolicy.resolve(
                cloudStatus: cloud,
                flags: noAccounts
            ),
            .disabled
        )

        let production = WayTaskCloudConfiguration.resolve(values: [
            WayTaskCloudConfiguration.environmentKey: "production",
            WayTaskCloudConfiguration.projectURLKey:
                "https://production.invalid",
            WayTaskCloudConfiguration.publishableKeyKey:
                "sb_publishable_production_test_value"
        ])
        XCTAssertEqual(
            SecureAIRecognitionPolicy.resolve(
                cloudStatus: production,
                flags: enabledFlags
            ),
            .invalid(.productionNotApproved)
        )
    }

    func testDirectGeminiClientFallbackIsPermanentlyDisabled() {
        XCTAssertFalse(SecureAIRecognitionPolicy.directClientFallbackAllowed)
    }

    func testDisabledConfigurationReturnsUnavailableWithoutNetworkOrFakeResult()
        async {
        var networkRequests = 0
        SecureAIMockURLProtocol.requestHandler = { request in
            networkRequests += 1
            return try Self.response(
                request: request,
                statusCode: 500,
                body: Data()
            )
        }
        let service = SecureAIProductRecognitionService(
            session: makeSession(),
            configurationStatus: .disabled,
            accessTokenProvider: { "signed-in-test-token-value" }
        )

        let result = await service.suggestProduct(
            from: syntheticJPEG(),
            barcode: nil
        )

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(networkRequests, 0)
        XCTAssertTrue(result.message.contains("not configured"))
    }

    func testConfiguredProxyRequiresAuthenticationBeforeAnyNetworkRequest()
        async {
        var networkRequests = 0
        SecureAIMockURLProtocol.requestHandler = { request in
            networkRequests += 1
            return try Self.response(
                request: request,
                statusCode: 500,
                body: Data()
            )
        }
        let service = SecureAIProductRecognitionService(
            session: makeSession(),
            configurationStatus: configuredStatus,
            accessTokenProvider: { nil }
        )

        let result = await service.suggestProduct(
            from: syntheticJPEG(),
            barcode: nil
        )

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(networkRequests, 0)
        XCTAssertTrue(result.message.contains("Sign in"))
    }

    func testProxyRequestIsBoundedAndCannotForwardModelEndpointOrPrompt()
        async throws {
        SecureAIMockURLProtocol.requestHandler = { request in
            let requestID = try Self.requestID(from: request)
            let body = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1,
                "requestId": requestID,
                "status": "recognized",
                "messageCode": "review_result",
                "product": [
                    "productName": "Synthetic Test Product",
                    "brand": "Test Brand",
                    "category": "Test Category",
                    "confidence": 0.88,
                    "searchKeywords": ["synthetic", "test"]
                ]
            ])
            return try Self.response(
                request: request,
                statusCode: 200,
                body: body
            )
        }
        let service = SecureAIProductRecognitionService(
            session: makeSession(),
            configurationStatus: configuredStatus,
            accessTokenProvider: { "signed-in-test-token-value" }
        )
        let barcode = BarcodeResult(value: "7290000000000", type: .ean13)

        let result = await service.suggestProduct(
            from: syntheticJPEG(),
            barcode: barcode
        )

        XCTAssertEqual(result.status, .recognized)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.bestCandidate?.name, "Synthetic Test Product")
        XCTAssertEqual(result.bestCandidate?.barcode, barcode.value)

        let request = try XCTUnwrap(SecureAIMockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.host, "staging.invalid")
        XCTAssertEqual(
            request.url?.path,
            "/functions/v1/recognize-product"
        )
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Authorization")?
                .hasPrefix("Bearer ") == true
        )
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertLessThan(body.count, 2_850_001)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["schemaVersion", "requestId", "image", "barcode"])
        )
        XCTAssertNil(object["model"])
        XCTAssertNil(object["prompt"])
        XCTAssertNil(object["endpoint"])
        let image = try XCTUnwrap(object["image"] as? [String: Any])
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(image["imageBase64"] as? String).count,
            2_800_000
        )
    }

    func testOversizedAndUnsupportedImagesFailBeforeNetwork() async {
        var networkRequests = 0
        SecureAIMockURLProtocol.requestHandler = { request in
            networkRequests += 1
            return try Self.response(
                request: request,
                statusCode: 500,
                body: Data()
            )
        }
        let service = SecureAIProductRecognitionService(
            session: makeSession(),
            configurationStatus: configuredStatus,
            accessTokenProvider: { "signed-in-test-token-value" }
        )

        let oversized = await service.suggestProduct(
            from: Data(
                repeating: 0,
                count: SecureAIProductRecognitionService
                    .maximumInputImageBytes + 1
            ),
            barcode: nil
        )
        let unsupported = await service.suggestProduct(
            from: Data([0x00, 0x01, 0x02]),
            barcode: nil
        )

        XCTAssertEqual(oversized.status, .unavailable)
        XCTAssertTrue(oversized.message.contains("too large"))
        XCTAssertTrue(oversized.candidates.isEmpty)
        XCTAssertEqual(unsupported.status, .unavailable)
        XCTAssertTrue(unsupported.message.contains("could not be used"))
        XCTAssertTrue(unsupported.candidates.isEmpty)
        XCTAssertEqual(networkRequests, 0)
    }

    func testServerErrorsUseSafeUserFacingMappings() async {
        let cases: [(Int, String, String?)] = [
            (401, "authentication_required", "Sign in"),
            (403, "permission_denied", "permission was denied"),
            (413, "payload_too_large", "too large"),
            (415, "unsupported_image", "could not be used"),
            (422, "invalid_result", "usable product"),
            (429, "rate_limited", "Too many"),
            (500, "server_error", "could not finish"),
            (503, "service_unavailable", "temporarily unavailable"),
            (504, "timeout", "too long")
        ]

        for (statusCode, errorCode, expectedCopy) in cases {
            SecureAIMockURLProtocol.requestHandler = { request in
                let body = try JSONSerialization.data(withJSONObject: [
                    "error": ["code": errorCode]
                ])
                return try Self.response(
                    request: request,
                    statusCode: statusCode,
                    headers: statusCode == 429
                        ? ["Retry-After": "30"]
                        : [:],
                    body: body
                )
            }
            let service = SecureAIProductRecognitionService(
                session: makeSession(),
                configurationStatus: configuredStatus,
                accessTokenProvider: { "signed-in-test-token-value" }
            )

            let result = await service.suggestProduct(
                from: syntheticJPEG(),
                barcode: nil
            )

            XCTAssertEqual(result.status, .unavailable)
            XCTAssertTrue(result.candidates.isEmpty)
            XCTAssertTrue(
                result.message.contains(expectedCopy ?? ""),
                "Unexpected copy for HTTP \(statusCode): \(result.message)"
            )
            for forbidden in ["HTTP", "JWT", "Supabase", "SQL", "stack"] {
                XCTAssertFalse(result.message.contains(forbidden))
            }
        }
    }

    private var enabledFlags: WayTaskCloudFeatureFlags {
        WayTaskCloudFeatureFlags(
            accountsEnabled: true,
            synchronizationEnabled: false,
            firstMigrationEnabled: false,
            secureAIRecognitionEnabled: true
        )
    }

    private var configuredStatus: SecureAIConfigurationStatus {
        .configured(
            SecureAIProxyConfiguration(
                environment: .staging,
                endpointURL: URL(
                    string:
                        "https://staging.invalid/functions/v1/recognize-product"
                )!,
                publishableKey: "sb_publishable_staging_test_value"
            )
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SecureAIMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func syntheticJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(
                CGRect(origin: .zero, size: CGSize(width: 8, height: 8))
            )
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    private nonisolated static func requestID(
        from request: URLRequest
    ) throws -> String {
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        return try XCTUnwrap(object["requestId"] as? String)
    }

    private nonisolated static func response(
        request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
        return (response, body)
    }
}

private final class SecureAIMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    nonisolated override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    nonisolated override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    nonisolated override func startLoading() {
        var handledRequest = request
        if handledRequest.httpBody == nil,
           let bodyStream = handledRequest.httpBodyStream {
            bodyStream.open()
            defer { bodyStream.close() }

            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while bodyStream.hasBytesAvailable {
                let count = bodyStream.read(
                    &buffer,
                    maxLength: buffer.count
                )
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            handledRequest.httpBody = body
        }

        Self.lastRequest = handledRequest
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        do {
            let (response, data) = try handler(handledRequest)
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

    nonisolated override func stopLoading() {}
}
