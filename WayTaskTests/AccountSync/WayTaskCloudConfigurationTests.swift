import Foundation
import XCTest
@testable import WayTask

final class WayTaskCloudConfigurationTests: XCTestCase {
    func testEmptyConfigurationIsSafelyNotConfigured() {
        let status = WayTaskCloudConfiguration.resolve(values: [:])

        XCTAssertEqual(status, .notConfigured)
        XCTAssertFalse(status.permitsCloudClientCreation)
        XCTAssertEqual(
            WayTaskCloudConfiguration.featureFlags(
                values: enabledFlagValues,
                configurationStatus: status
            ),
            .disabled
        )
    }

    func testPartialOrPlaceholderConfigurationFailsClosed() {
        XCTAssertEqual(
            WayTaskCloudConfiguration.resolve(values: [
                WayTaskCloudConfiguration.environmentKey: "staging"
            ]),
            .invalid(.incompleteConfiguration)
        )
        XCTAssertEqual(
            WayTaskCloudConfiguration.resolve(values: [
                WayTaskCloudConfiguration.environmentKey: "$(VALUE)",
                WayTaskCloudConfiguration.projectURLKey: "$(VALUE)",
                WayTaskCloudConfiguration.publishableKeyKey: "$(VALUE)"
            ]),
            .notConfigured
        )
    }

    func testLocalConfigurationRequiresLoopbackHost() {
        XCTAssertEqual(
            resolve(environment: "local", url: "https://example.com"),
            .invalid(.nonLocalDevelopmentURL)
        )

        let status = resolve(
            environment: "local",
            url: "http://127.0.0.1:54321"
        )
        XCTAssertEqual(status.environment, .local)
    }

    func testRemoteConfigurationsRequireTLSAndHaveExplicitEnvironment() {
        XCTAssertEqual(
            resolve(environment: "staging", url: "http://staging.example.com"),
            .invalid(.insecureRemoteURL)
        )
        XCTAssertEqual(
            resolve(environment: "future", url: "https://example.com"),
            .invalid(.unknownEnvironment)
        )
        XCTAssertEqual(
            resolve(environment: "production", url: "https://example.com")
                .environment,
            .production
        )
    }

    func testPrivilegedKeyShapesAreRejected() throws {
        let protectedPrefix = "sb_" + "secret_"
        XCTAssertEqual(
            resolve(
                environment: "staging",
                url: "https://example.com",
                key: protectedPrefix + String(repeating: "x", count: 32)
            ),
            .invalid(.privilegedSecretRejected)
        )

        let protectedRole = "service_" + "role"
        let header = try XCTUnwrap(
            try? JSONSerialization.data(withJSONObject: ["alg": "HS256"])
        )
        let payload = try XCTUnwrap(
            try? JSONSerialization.data(withJSONObject: ["role": protectedRole])
        )
        let jwt = [header, payload, Data("signature".utf8)]
            .map(base64URL)
            .joined(separator: ".")

        XCTAssertEqual(
            resolve(
                environment: "staging",
                url: "https://example.com",
                key: jwt
            ),
            .invalid(.privilegedSecretRejected)
        )
    }

    func testFeatureFlagsAreOrderedAndDefaultOff() {
        let status = resolve(
            environment: "staging",
            url: "https://example.com"
        )
        XCTAssertEqual(
            WayTaskCloudConfiguration.featureFlags(
                values: [:],
                configurationStatus: status
            ),
            .disabled
        )
        XCTAssertEqual(
            WayTaskCloudConfiguration.featureFlags(
                values: [WayTaskCloudConfiguration.syncFlagKey: "YES"],
                configurationStatus: status
            ),
            .disabled
        )

        let flags = WayTaskCloudConfiguration.featureFlags(
            values: enabledFlagValues,
            configurationStatus: status
        )
        XCTAssertTrue(flags.accountsEnabled)
        XCTAssertTrue(flags.synchronizationEnabled)
        XCTAssertTrue(flags.firstMigrationEnabled)
    }

    private var enabledFlagValues: [String: String] {
        [
            WayTaskCloudConfiguration.accountsFlagKey: "YES",
            WayTaskCloudConfiguration.syncFlagKey: "YES",
            WayTaskCloudConfiguration.migrationFlagKey: "YES"
        ]
    }

    private func resolve(
        environment: String,
        url: String,
        key: String = "sb_publishable_local_test_value"
    ) -> WayTaskCloudConfigurationStatus {
        WayTaskCloudConfiguration.resolve(values: [
            WayTaskCloudConfiguration.environmentKey: environment,
            WayTaskCloudConfiguration.projectURLKey: url,
            WayTaskCloudConfiguration.publishableKeyKey: key
        ])
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
