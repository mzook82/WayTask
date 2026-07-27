import Foundation
import Sentry
import UIKit

enum SentryBuildConfiguration {
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct SentryDeviceMetadata: Equatable {
    let model: String
    let osVersion: String

    static var current: SentryDeviceMetadata {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: 1
            ) {
                String(cString: $0)
            }
        }

        return SentryDeviceMetadata(
            model: model.isEmpty ? UIDevice.current.model : model,
            osVersion: UIDevice.current.systemVersion
        )
    }
}

struct SentryPrivacyPolicy: Equatable {
    let sendsDefaultPII: Bool
    let attachesScreenshots: Bool
    let attachesViewHierarchy: Bool
    let enablesSessionReplay: Bool
    let enablesPerformanceTracing: Bool
    let enablesNetworkTracking: Bool
    let enablesAutomaticBreadcrumbs: Bool

    static let wayTask = SentryPrivacyPolicy(
        sendsDefaultPII: false,
        attachesScreenshots: false,
        attachesViewHierarchy: false,
        enablesSessionReplay: false,
        enablesPerformanceTracing: false,
        enablesNetworkTracking: false,
        enablesAutomaticBreadcrumbs: false
    )
}

struct SentryLaunchConfiguration: Equatable {
    let dsn: String
    let environment: String
    let releaseName: String
    let distribution: String
    let appVersion: String
    let buildNumber: String
    let deviceMetadata: SentryDeviceMetadata
    let enablesSDKDebugDiagnostics: Bool
    let enablesCrashHandler: Bool
    let privacyPolicy: SentryPrivacyPolicy
}

enum SentryStartupStatus: Equatable {
    case notStarted
    case enabled
    case disabledMissingConfiguration
    case failed
}

enum SentryLaunchConfigurationResolver {
    static func resolve(
        infoDictionary: [String: Any],
        bundleIdentifier: String?,
        deviceMetadata: SentryDeviceMetadata,
        isDebugBuild: Bool
    ) -> SentryLaunchConfiguration? {
        guard let dsn = validDSN(
            infoDictionary["SENTRY_DSN"] as? String
        ) else {
            return nil
        }

        let appVersion = nonEmptyString(
            infoDictionary["CFBundleShortVersionString"]
        ) ?? "0"
        let buildNumber = nonEmptyString(
            infoDictionary["CFBundleVersion"]
        ) ?? "0"
        let identifier = nonEmptyString(bundleIdentifier)
            ?? "unknown.bundle"

        return SentryLaunchConfiguration(
            dsn: dsn,
            environment: isDebugBuild ? "development" : "beta",
            releaseName: "\(identifier)@\(appVersion)",
            distribution: buildNumber,
            appVersion: appVersion,
            buildNumber: buildNumber,
            deviceMetadata: deviceMetadata,
            enablesSDKDebugDiagnostics: isDebugBuild,
            enablesCrashHandler: true,
            privacyPolicy: .wayTask
        )
    }

    private static func validDSN(_ value: String?) -> String? {
        guard let trimmedValue = nonEmptyString(value),
              !trimmedValue.contains("$("),
              let components = URLComponents(string: trimmedValue),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user?.isEmpty == false,
              components.path.split(separator: "/").last?.isEmpty
                == false else {
            return nil
        }

        return trimmedValue
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

enum SentryDiagnosticEventType: String, CaseIterable {
    case testMessage = "test_message"
    case handledError = "handled_error"
    case nonFatalException = "non_fatal_exception"
}

enum SentryDiagnosticMetadataPolicy {
    static let contextKey = "waytask_diagnostic"
    static let allowedKeys: Set<String> = [
        "app_version",
        "build_number",
        "environment",
        "device_model",
        "os_version",
        "diagnostic_event_type"
    ]

    static func filtered(
        _ values: [String: String]
    ) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            guard allowedKeys.contains(entry.key) else {
                return
            }

            let value = entry.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty else {
                return
            }
            result[entry.key] = value
        }
    }

    static func context(
        configuration: SentryLaunchConfiguration,
        eventType: SentryDiagnosticEventType
    ) -> [String: String] {
        filtered(
            [
                "app_version": configuration.appVersion,
                "build_number": configuration.buildNumber,
                "environment": configuration.environment,
                "device_model": configuration.deviceMetadata.model,
                "os_version": configuration.deviceMetadata.osVersion,
                "diagnostic_event_type": eventType.rawValue
            ]
        )
    }
}

enum SentryDiagnosticsAccessPolicy {
    static func shouldShowControls(
        developerModeEnabled: Bool,
        approvedBuild: Bool = SentryBuildConfiguration.isDebug
    ) -> Bool {
        developerModeEnabled && approvedBuild
    }
}

enum SentryAppArea: String {
    case home = "Home"
    case products = "Products"
    case shopping = "Shopping"
    case map = "Map"
    case settings = "Settings"
    case camera = "Camera"
}

enum SentryOperation: String {
    case planner
    case storeDiscovery = "store_discovery"
    case notification
    case geofence
    case recognition
    case persistence
    case diagnostics
}

enum SentryIssueCategory: String {
    case integration
    case operational
    case persistence
    case test
}

enum SentryNumericContext: String {
    case itemCount = "item_count"
    case storeCount = "store_count"
    case planningDurationBucket = "planning_duration_bucket"
    case discoveryResultCount = "discovery_result_count"
}

enum SentrySafeMessage: String, CaseIterable {
    case debugTestMessage = "WayTask DEBUG test message"
    case debugHandledError = "WayTask DEBUG handled error"
    case debugNonFatalException =
        "WayTask DEBUG non-fatal exception"
    case plannerTimedOut = "Planner timed out"
    case storeDiscoveryFailed = "Store discovery failed"
    case notificationAuthorizationFailed = "Notification authorization failed"
    case notificationSchedulingFailed = "Notification scheduling failed"
    case notificationDeepLinkFailed = "Notification deep link failed"
    case geofenceMonitoringFailed = "Geofence monitoring failed"
    case recognitionProviderFailed = "Product recognition provider failed"
    case persistenceFailed = "Local persistence failed"
    case productKnowledgeUnavailable = "Product suggestions unavailable"
    case startupPersistenceFailed =
        "Startup persistence initialization failed"
    case startupPersistenceRecovered =
        "Startup persistence recovered"
    case startupPersistenceDegraded =
        "Startup persistence is using temporary storage"
    case startupPersistenceUnrecoverable =
        "Startup persistence is unrecoverable"
}

enum SentryStartupPersistenceMetadataPolicy {
    static let contextKey = "waytask_startup_persistence"
    static let allowedKeys: Set<String> = [
        "stage",
        "outcome",
        "schema_version",
        "error_domain",
        "error_code",
        "underlying_error_domain",
        "underlying_error_code",
        "quarantined_component_count",
        "repair_action_count"
    ]

    static func context(
        for diagnostic: WayTaskStartupPersistenceDiagnostic
    ) -> [String: Any] {
        var context: [String: Any] = [
            "stage": diagnostic.stage.rawValue,
            "outcome": diagnostic.outcome.rawValue,
            "schema_version": "3.0.0",
            "quarantined_component_count":
                min(
                    max(
                        diagnostic.quarantinedComponentCount,
                        0
                    ),
                    10
                ),
            "repair_action_count":
                min(max(diagnostic.repairActionCount, 0), 10_000)
        ]
        if let errorDomain = diagnostic.errorDomain {
            context["error_domain"] = errorDomain
        }
        if let errorCode = diagnostic.errorCode {
            context["error_code"] = errorCode
        }
        if let underlyingErrorDomain =
            diagnostic.underlyingErrorDomain
        {
            context["underlying_error_domain"] =
                underlyingErrorDomain
        }
        if let underlyingErrorCode =
            diagnostic.underlyingErrorCode
        {
            context["underlying_error_code"] =
                underlyingErrorCode
        }
        return context
    }
}

enum SentryWorkflowBreadcrumb: String {
    case appLaunched = "app_launched"
    case recognitionStarted = "recognition_started"
    case recognitionCompleted = "recognition_completed"
    case recognitionFailed = "recognition_failed"
    case planGenerationStarted = "plan_generation_started"
    case planReady = "plan_ready"
    case planFailed = "plan_failed"
    case mapOpened = "map_opened"
    case notificationDeepLinkHandled = "notification_deep_link_handled"
    case notificationDeepLinkFailed = "notification_deep_link_failed"
    case shoppingSessionStarted = "shopping_session_started"
    case shoppingSessionCompleted = "shopping_session_completed"
}

/// The only WayTask type that imports Sentry. All public inputs are constrained to privacy-safe enums
/// and aggregate numbers so callers cannot accidentally attach product, store, location, or user data.
final class SentryReportingService {
    static let shared = SentryReportingService()

    typealias SDKStartAction = @MainActor (
        SentryLaunchConfiguration
    ) throws -> Bool
    typealias DiagnosticCaptureAction = @MainActor (
        SentryDiagnosticEventType
    ) -> Void
    typealias StartupPersistenceCaptureAction = @MainActor (
        WayTaskStartupPersistenceDiagnostic
    ) -> Void

    private static let breadcrumbCategory = "waytask.workflow"
    private static let contextKey = "waytask"
    private static let allowedSafeMessages = Set(SentrySafeMessage.allCases.map(\.rawValue))
    private static let maximumContextValue = 1_000_000_000

    private(set) var isEnabled = false
    private(set) var startupStatus: SentryStartupStatus = .notStarted

    private let sdkStartAction: SDKStartAction
    private let diagnosticCaptureAction: DiagnosticCaptureAction?
    private let startupPersistenceCaptureAction:
        StartupPersistenceCaptureAction?
    private let usesLiveSDK: Bool
    private var activeConfiguration: SentryLaunchConfiguration?

    init(
        sdkStartAction: SDKStartAction? = nil,
        diagnosticCaptureAction: DiagnosticCaptureAction? = nil,
        startupPersistenceCaptureAction:
            StartupPersistenceCaptureAction? = nil
    ) {
        if let sdkStartAction {
            self.sdkStartAction = sdkStartAction
        } else {
            self.sdkStartAction = { @MainActor configuration in
                Self.startSDK(configuration: configuration)
            }
        }
        self.diagnosticCaptureAction = diagnosticCaptureAction
        self.startupPersistenceCaptureAction =
            startupPersistenceCaptureAction
        usesLiveSDK = sdkStartAction == nil
    }

    @discardableResult
    func startIfConfigured(
        bundle: Bundle = .main
    ) -> SentryStartupStatus {
        startIfConfigured(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier,
            deviceMetadata: .current,
            isDebugBuild: SentryBuildConfiguration.isDebug
        )
    }

    @discardableResult
    func startIfConfigured(
        infoDictionary: [String: Any],
        bundleIdentifier: String?,
        deviceMetadata: SentryDeviceMetadata,
        isDebugBuild: Bool
    ) -> SentryStartupStatus {
        guard !isEnabled else {
            startupStatus = .enabled
            return startupStatus
        }

        guard let configuration =
                SentryLaunchConfigurationResolver.resolve(
                    infoDictionary: infoDictionary,
                    bundleIdentifier: bundleIdentifier,
                    deviceMetadata: deviceMetadata,
                    isDebugBuild: isDebugBuild
                ) else {
            activeConfiguration = nil
            startupStatus = .disabledMissingConfiguration
            return startupStatus
        }

        do {
            isEnabled = try sdkStartAction(configuration)
        } catch {
            isEnabled = false
        }

        guard isEnabled else {
            activeConfiguration = nil
            startupStatus = .failed
            return startupStatus
        }

        activeConfiguration = configuration
        startupStatus = .enabled
        if usesLiveSDK {
            breadcrumb(.appLaunched, area: .home)
        }
        return startupStatus
    }

    private static func startSDK(
        configuration: SentryLaunchConfiguration
    ) -> Bool {
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.enableCrashHandler =
                configuration.enablesCrashHandler
            options.debug =
                configuration.enablesSDKDebugDiagnostics
            if configuration.enablesSDKDebugDiagnostics {
                options.diagnosticLevel = .warning
            }
            options.environment = configuration.environment

            options.releaseName = configuration.releaseName
            options.dist = configuration.distribution
            options.sendDefaultPii =
                configuration.privacyPolicy.sendsDefaultPII
            options.attachScreenshot =
                configuration.privacyPolicy.attachesScreenshots
            options.attachViewHierarchy =
                configuration.privacyPolicy.attachesViewHierarchy
            options.reportAccessibilityIdentifier = false
            options.sessionReplay.sessionSampleRate =
                configuration.privacyPolicy.enablesSessionReplay
                ? 1 : 0
            options.sessionReplay.onErrorSampleRate =
                configuration.privacyPolicy.enablesSessionReplay
                ? 1 : 0

            options.tracesSampleRate =
                configuration.privacyPolicy
                    .enablesPerformanceTracing ? 1 : 0
            options.enableAutoPerformanceTracing =
                configuration.privacyPolicy
                    .enablesPerformanceTracing
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enableNetworkTracking =
                configuration.privacyPolicy.enablesNetworkTracking
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableDataSwizzling = false
            options.enableCoreDataTracing = false
            options.enableTimeToFullDisplayTracing = false
            options.configureProfiling = nil

            options.enableSwizzling = false
            options.enableAutoBreadcrumbTracking =
                configuration.privacyPolicy
                    .enablesAutomaticBreadcrumbs
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.enableReportNonFullyBlockingAppHangs = false
            options.enableLogs = false
            options.enableMetricKit = false
            options.enableMetricKitRawPayload = false
            options.maxBreadcrumbs = 40

            options.beforeSend = { event in
                Self.sanitize(event)
            }
        }

        return SentrySDK.isEnabled
    }

    func setCurrentArea(_ area: SentryAppArea) {
        guard isEnabled else { return }

        SentrySDK.configureScope { scope in
            scope.setTag(value: area.rawValue, key: "area")
            scope.setUser(nil)
            scope.clearAttachments()
        }
    }

    func capture(
        error: Error,
        message: SentrySafeMessage,
        operation: SentryOperation,
        category: SentryIssueCategory,
        area: SentryAppArea,
        numericContext: [SentryNumericContext: Int] = [:]
    ) {
        guard isEnabled else { return }

        let originalError = error as NSError
        let sanitizedError = NSError(
            domain: "WayTask.\(operation.rawValue)",
            code: originalError.code,
            userInfo: [NSLocalizedDescriptionKey: message.rawValue]
        )

        SentrySDK.capture(error: sanitizedError) { scope in
            Self.configure(
                scope,
                operation: operation,
                category: category,
                area: area,
                numericContext: numericContext
            )
        }
    }

    func capture(
        message: SentrySafeMessage,
        operation: SentryOperation,
        category: SentryIssueCategory,
        area: SentryAppArea,
        numericContext: [SentryNumericContext: Int] = [:]
    ) {
        guard isEnabled else { return }

        SentrySDK.capture(message: message.rawValue) { scope in
            Self.configure(
                scope,
                operation: operation,
                category: category,
                area: area,
                numericContext: numericContext
            )
        }
    }

    func captureStartupPersistence(
        _ diagnostic: WayTaskStartupPersistenceDiagnostic
    ) {
        guard isEnabled else { return }

        if let startupPersistenceCaptureAction {
            startupPersistenceCaptureAction(diagnostic)
            return
        }

        let message: SentrySafeMessage
        switch diagnostic.outcome {
        case .failed:
            message = .startupPersistenceFailed
        case .recovered:
            message = .startupPersistenceRecovered
        case .degraded:
            message = .startupPersistenceDegraded
        case .fatal:
            message = .startupPersistenceUnrecoverable
        }

        let error = NSError(
            domain: "WayTask.startup.persistence",
            code: diagnostic.errorCode ?? 0,
            userInfo: [
                NSLocalizedDescriptionKey: message.rawValue
            ]
        )
        SentrySDK.capture(error: error) { scope in
            Self.configure(
                scope,
                operation: .persistence,
                category: .persistence,
                area: .home,
                numericContext: [:]
            )
            scope.setTag(
                value: diagnostic.stage.rawValue,
                key: "startup_stage"
            )
            scope.setTag(
                value: diagnostic.outcome.rawValue,
                key: "startup_outcome"
            )
            scope.setContext(
                value:
                    SentryStartupPersistenceMetadataPolicy
                        .context(for: diagnostic),
                key:
                    SentryStartupPersistenceMetadataPolicy
                        .contextKey
            )
        }
    }

    func breadcrumb(
        _ workflow: SentryWorkflowBreadcrumb,
        area: SentryAppArea,
        operation: SentryOperation? = nil,
        numericContext: [SentryNumericContext: Int] = [:]
    ) {
        guard isEnabled else { return }

        let breadcrumb = Breadcrumb(level: .info, category: Self.breadcrumbCategory)
        breadcrumb.type = "navigation"
        breadcrumb.message = workflow.rawValue

        var data: [String: Any] = ["area": area.rawValue]
        if let operation {
            data["operation"] = operation.rawValue
        }
        for (key, value) in Self.sanitizedNumericContext(numericContext) {
            data[key] = value
        }
        breadcrumb.data = data
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    #if DEBUG
    var isNativeCrashHandlerEnabled: Bool {
        isEnabled &&
            startupStatus == .enabled &&
            activeConfiguration?.enablesCrashHandler == true
    }

    @discardableResult
    func captureDebugTestMessage() -> Bool {
        captureDebugDiagnostic(.testMessage)
    }

    @discardableResult
    func captureDebugHandledError() -> Bool {
        captureDebugDiagnostic(.handledError)
    }

    @discardableResult
    func captureDebugNonFatalException() -> Bool {
        captureDebugDiagnostic(.nonFatalException)
    }

    private func captureDebugDiagnostic(
        _ eventType: SentryDiagnosticEventType
    ) -> Bool {
        guard isEnabled,
              let configuration = activeConfiguration else {
            return false
        }

        if let diagnosticCaptureAction {
            diagnosticCaptureAction(eventType)
            return true
        }

        switch eventType {
        case .testMessage:
            SentrySDK.capture(
                message: SentrySafeMessage.debugTestMessage.rawValue
            ) { scope in
                Self.configureDiagnostic(
                    scope,
                    eventType: eventType,
                    configuration: configuration
                )
            }
            requestDebugFlush()
        case .handledError:
            let error = NSError(
                domain: "WayTask.diagnostics",
                code: 1_001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        SentrySafeMessage.debugHandledError.rawValue
                ]
            )
            SentrySDK.capture(error: error) { scope in
                Self.configureDiagnostic(
                    scope,
                    eventType: eventType,
                    configuration: configuration
                )
            }
            requestDebugFlush()
        case .nonFatalException:
            let exception = NSException(
                name: NSExceptionName(
                    "WayTaskDiagnosticException"
                ),
                reason:
                    SentrySafeMessage.debugNonFatalException.rawValue,
                userInfo: nil
            )
            SentrySDK.capture(exception: exception) { scope in
                Self.configureDiagnostic(
                    scope,
                    eventType: eventType,
                    configuration: configuration
                )
            }
            requestDebugFlush()
        }

        return true
    }

    private func requestDebugFlush() {
        DispatchQueue.global(qos: .utility).async {
            SentrySDK.flush(timeout: 2)
        }
    }
    #endif

    private static func configure(
        _ scope: Scope,
        operation: SentryOperation,
        category: SentryIssueCategory,
        area: SentryAppArea,
        numericContext: [SentryNumericContext: Int]
    ) {
        scope.setUser(nil)
        scope.clearAttachments()
        scope.setTag(value: operation.rawValue, key: "operation")
        scope.setTag(value: category.rawValue, key: "category")
        scope.setTag(value: area.rawValue, key: "area")

        var context: [String: Any] = [
            "operation": operation.rawValue,
            "category": category.rawValue,
            "area": area.rawValue
        ]
        for (key, value) in sanitizedNumericContext(numericContext) {
            context[key] = value
        }
        scope.setContext(value: context, key: contextKey)
    }

    private static func configureDiagnostic(
        _ scope: Scope,
        eventType: SentryDiagnosticEventType,
        configuration: SentryLaunchConfiguration
    ) {
        configure(
            scope,
            operation: .diagnostics,
            category: .test,
            area: .settings,
            numericContext: [:]
        )
        scope.setTag(
            value: eventType.rawValue,
            key: "diagnostic_event_type"
        )
        scope.setContext(
            value: SentryDiagnosticMetadataPolicy.context(
                configuration: configuration,
                eventType: eventType
            ),
            key: SentryDiagnosticMetadataPolicy.contextKey
        )
    }

    private static func sanitizedNumericContext(_ values: [SentryNumericContext: Int]) -> [String: Int] {
        values.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = min(max(entry.value, 0), maximumContextValue)
        }
    }

    static func sanitize(_ event: Event) -> Event? {
        event.user = nil
        event.request = nil
        event.serverName = nil
        event.transaction = nil
        event.extra = nil
        event.error = nil
        event.modules = nil
        event.fingerprint = nil
        event.logger = "waytask"

        event.tags = event.tags?.filter { key, _ in
            key == "area" ||
                key == "operation" ||
                key == "category" ||
                key == "diagnostic_event_type" ||
                key == "startup_stage" ||
                key == "startup_outcome"
        }

        if let message = event.message?.formatted,
           !allowedSafeMessages.contains(message) {
            event.message = SentryMessage(formatted: "WayTask crash or error")
        }
        event.message?.params = nil
        event.message?.message = nil

        event.exceptions?.forEach { exception in
            exception.value = "Sanitized error"
        }

        event.breadcrumbs = event.breadcrumbs?.filter { breadcrumb in
            breadcrumb.category == breadcrumbCategory
        }
        event.breadcrumbs?.forEach { breadcrumb in
            breadcrumb.data = breadcrumb.data?.filter { key, _ in
                key == "area" ||
                    key == "operation" ||
                    SentryNumericContext(rawValue: key) != nil
            }
        }

        event.context = sanitizedContexts(event.context)
        return event
    }

    private static func sanitizedContexts(
        _ contexts: [String: [String: Any]]?
    ) -> [String: [String: Any]]? {
        guard let contexts else { return nil }

        let allowedFields: [String: Set<String>] = [
            "app": ["app_identifier", "app_name", "app_version", "app_build", "build_type"],
            "device": ["family", "model", "model_id", "arch", "simulator"],
            "os": ["name", "version", "build"],
            contextKey: [
                "area",
                "operation",
                "category",
                SentryNumericContext.itemCount.rawValue,
                SentryNumericContext.storeCount.rawValue,
                SentryNumericContext.planningDurationBucket.rawValue,
                SentryNumericContext.discoveryResultCount.rawValue
            ],
            SentryDiagnosticMetadataPolicy.contextKey:
                SentryDiagnosticMetadataPolicy.allowedKeys,
            SentryStartupPersistenceMetadataPolicy.contextKey:
                SentryStartupPersistenceMetadataPolicy.allowedKeys
        ]

        return contexts.reduce(into: [:]) { result, entry in
            guard let fields = allowedFields[entry.key] else { return }
            let filtered = entry.value.filter { fields.contains($0.key) }
            if !filtered.isEmpty {
                result[entry.key] = filtered
            }
        }
    }
}
