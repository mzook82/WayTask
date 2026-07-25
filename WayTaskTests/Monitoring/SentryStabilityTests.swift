import Sentry
import XCTest
@testable import WayTask

@MainActor
final class SentryStabilityTests: XCTestCase {
    func testInitializationBuildsApprovedDebugAndBetaConfigurations() throws {
        var capturedConfiguration: SentryLaunchConfiguration?
        let service = SentryReportingService(
            sdkStartAction: { configuration in
                capturedConfiguration = configuration
                return true
            }
        )

        let status = service.startIfConfigured(
            infoDictionary: validInfoDictionary,
            bundleIdentifier: "h.WayTask",
            deviceMetadata: testDeviceMetadata,
            isDebugBuild: false
        )
        let releaseConfiguration = try XCTUnwrap(
            capturedConfiguration
        )
        let debugConfiguration = try XCTUnwrap(
            SentryLaunchConfigurationResolver.resolve(
                infoDictionary: validInfoDictionary,
                bundleIdentifier: "h.WayTask",
                deviceMetadata: testDeviceMetadata,
                isDebugBuild: true
            )
        )

        XCTAssertEqual(status, .enabled)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(releaseConfiguration.environment, "beta")
        XCTAssertEqual(
            releaseConfiguration.releaseName,
            "h.WayTask@1.0.2"
        )
        XCTAssertEqual(releaseConfiguration.distribution, "42")
        XCTAssertFalse(
            releaseConfiguration.enablesSDKDebugDiagnostics
        )
        XCTAssertTrue(releaseConfiguration.enablesCrashHandler)
        XCTAssertEqual(
            releaseConfiguration.privacyPolicy,
            .wayTask
        )
        XCTAssertEqual(debugConfiguration.environment, "development")
        XCTAssertTrue(debugConfiguration.enablesSDKDebugDiagnostics)
        XCTAssertTrue(debugConfiguration.enablesCrashHandler)
        XCTAssertFalse(debugConfiguration.privacyPolicy.sendsDefaultPII)
        XCTAssertFalse(
            debugConfiguration.privacyPolicy.attachesScreenshots
        )
        XCTAssertFalse(
            debugConfiguration.privacyPolicy
                .attachesViewHierarchy
        )
        XCTAssertFalse(
            debugConfiguration.privacyPolicy
                .enablesSessionReplay
        )
        XCTAssertFalse(
            debugConfiguration.privacyPolicy
                .enablesPerformanceTracing
        )
    }

    func testMissingConfigurationUsesSafeDisabledFallback() {
        var startWasCalled = false
        let service = SentryReportingService(
            sdkStartAction: { _ in
                startWasCalled = true
                return true
            }
        )

        let emptyStatus = service.startIfConfigured(
            infoDictionary: [
                "SENTRY_DSN": "",
                "CFBundleShortVersionString": "1.0.2",
                "CFBundleVersion": "42"
            ],
            bundleIdentifier: "h.WayTask",
            deviceMetadata: testDeviceMetadata,
            isDebugBuild: true
        )
        let unresolvedStatus = service.startIfConfigured(
            infoDictionary: [
                "SENTRY_DSN": "$(SENTRY_DSN)"
            ],
            bundleIdentifier: "h.WayTask",
            deviceMetadata: testDeviceMetadata,
            isDebugBuild: false
        )

        XCTAssertEqual(emptyStatus, .disabledMissingConfiguration)
        XCTAssertEqual(
            unresolvedStatus,
            .disabledMissingConfiguration
        )
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(startWasCalled)
        XCTAssertFalse(service.captureDebugTestMessage())
        XCTAssertFalse(service.captureDebugHandledError())
        XCTAssertFalse(service.captureDebugNonFatalException())
        XCTAssertFalse(service.isNativeCrashHandlerEnabled)
    }

    func testDiagnosticsControlsAreHiddenFromNormalUsersAndRelease() {
        XCTAssertFalse(
            SentryDiagnosticsAccessPolicy.shouldShowControls(
                developerModeEnabled: false,
                approvedBuild: true
            )
        )
        XCTAssertFalse(
            SentryDiagnosticsAccessPolicy.shouldShowControls(
                developerModeEnabled: true,
                approvedBuild: false
            )
        )
        XCTAssertTrue(
            SentryDiagnosticsAccessPolicy.shouldShowControls(
                developerModeEnabled: true,
                approvedBuild: true
            )
        )
    }

    func testSafeDiagnosticMetadataDropsUserAndSecretFields() throws {
        let configuration = try XCTUnwrap(
            SentryLaunchConfigurationResolver.resolve(
                infoDictionary: validInfoDictionary,
                bundleIdentifier: "h.WayTask",
                deviceMetadata: testDeviceMetadata,
                isDebugBuild: false
            )
        )
        let approvedContext =
            SentryDiagnosticMetadataPolicy.context(
                configuration: configuration,
                eventType: .handledError
            )
        let filtered = SentryDiagnosticMetadataPolicy.filtered(
            approvedContext.merging(
                [
                    "product_name": "private product",
                    "precise_location": "31.0,35.0",
                    "email": "private@example.invalid",
                    "shopping_history": "private history",
                    "authentication_token": "private token",
                    "photo": "private image"
                ],
                uniquingKeysWith: { _, newValue in newValue }
            )
        )

        XCTAssertEqual(
            Set(filtered.keys),
            SentryDiagnosticMetadataPolicy.allowedKeys
        )
        XCTAssertEqual(filtered["app_version"], "1.0.2")
        XCTAssertEqual(filtered["build_number"], "42")
        XCTAssertEqual(filtered["environment"], "beta")
        XCTAssertEqual(filtered["device_model"], "iPhone-test")
        XCTAssertEqual(filtered["os_version"], "26.5")
        XCTAssertEqual(
            filtered["diagnostic_event_type"],
            SentryDiagnosticEventType.handledError.rawValue
        )
        XCTAssertNil(filtered["product_name"])
        XCTAssertNil(filtered["precise_location"])
        XCTAssertNil(filtered["email"])
        XCTAssertNil(filtered["shopping_history"])
        XCTAssertNil(filtered["authentication_token"])
        XCTAssertNil(filtered["photo"])
    }

    func testDiagnosticActionsRouteToDistinctEventTypes() {
        var routedEvents: [SentryDiagnosticEventType] = []
        let service = SentryReportingService(
            sdkStartAction: { _ in true },
            diagnosticCaptureAction: {
                routedEvents.append($0)
            }
        )
        XCTAssertEqual(
            service.startIfConfigured(
                infoDictionary: validInfoDictionary,
                bundleIdentifier: "h.WayTask",
                deviceMetadata: testDeviceMetadata,
                isDebugBuild: true
            ),
            .enabled
        )

        XCTAssertTrue(service.captureDebugTestMessage())
        XCTAssertTrue(service.captureDebugHandledError())
        XCTAssertTrue(service.captureDebugNonFatalException())

        XCTAssertEqual(
            routedEvents,
            [
                .testMessage,
                .handledError,
                .nonFatalException
            ]
        )
    }

    func testNativeCrashHandlerStatusRequiresStartedSDK() {
        let service = SentryReportingService(
            sdkStartAction: { _ in true }
        )

        XCTAssertFalse(service.isNativeCrashHandlerEnabled)
        XCTAssertEqual(service.startupStatus, .notStarted)

        XCTAssertEqual(
            service.startIfConfigured(
                infoDictionary: validInfoDictionary,
                bundleIdentifier: "h.WayTask",
                deviceMetadata: testDeviceMetadata,
                isDebugBuild: true
            ),
            .enabled
        )

        XCTAssertTrue(service.isNativeCrashHandlerEnabled)
        XCTAssertEqual(service.startupStatus, .enabled)
    }

    func testBeforeSendPreservesOrdinaryFatalCrashEvent() throws {
        let event = Event(level: .fatal)
        event.tags = [
            "area": SentryAppArea.home.rawValue,
            "private_tag": "must be removed"
        ]

        let sanitized = try XCTUnwrap(
            SentryReportingService.sanitize(event)
        )

        XCTAssertEqual(sanitized.level, .fatal)
        XCTAssertEqual(
            sanitized.tags?["area"],
            SentryAppArea.home.rawValue
        )
        XCTAssertNil(sanitized.tags?["private_tag"])
    }

    func testMonitoringStartupFailureDoesNotInterruptAppStartup() {
        enum TestStartupFailure: Error {
            case unavailable
        }

        let service = SentryReportingService(
            sdkStartAction: { _ in
                throw TestStartupFailure.unavailable
            }
        )
        var applicationStartupContinued = false

        let status = service.startIfConfigured(
            infoDictionary: validInfoDictionary,
            bundleIdentifier: "h.WayTask",
            deviceMetadata: testDeviceMetadata,
            isDebugBuild: false
        )
        applicationStartupContinued = true

        XCTAssertEqual(status, .failed)
        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(applicationStartupContinued)
    }

    private var validInfoDictionary: [String: Any] {
        [
            "SENTRY_DSN":
                "https://public@example.ingest.invalid/123",
            "CFBundleShortVersionString": "1.0.2",
            "CFBundleVersion": "42"
        ]
    }

    private var testDeviceMetadata: SentryDeviceMetadata {
        SentryDeviceMetadata(
            model: "iPhone-test",
            osVersion: "26.5"
        )
    }
}
