import Foundation
import Sentry

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
    case debugNonFatalTest = "WayTask DEBUG non-fatal test"
    case plannerTimedOut = "Planner timed out"
    case storeDiscoveryFailed = "Store discovery failed"
    case notificationAuthorizationFailed = "Notification authorization failed"
    case notificationSchedulingFailed = "Notification scheduling failed"
    case notificationDeepLinkFailed = "Notification deep link failed"
    case geofenceMonitoringFailed = "Geofence monitoring failed"
    case recognitionProviderFailed = "Product recognition provider failed"
    case persistenceFailed = "Local persistence failed"
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

    private static let breadcrumbCategory = "waytask.workflow"
    private static let contextKey = "waytask"
    private static let allowedSafeMessages = Set(SentrySafeMessage.allCases.map(\.rawValue))
    private static let maximumContextValue = 1_000_000_000

    private(set) var isEnabled = false

    private init() {}

    func startIfConfigured(bundle: Bundle = .main) {
        guard !isEnabled,
              let configuredDSN = Self.validDSN(in: bundle) else {
            return
        }

        let version = Self.nonEmptyBundleValue("CFBundleShortVersionString", in: bundle) ?? "0"
        let build = Self.nonEmptyBundleValue("CFBundleVersion", in: bundle) ?? "0"
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle"

        SentrySDK.start { options in
            options.dsn = configuredDSN
            #if DEBUG
            options.debug = true
            options.diagnosticLevel = .warning
            options.environment = "development"
            #else
            options.debug = false
            options.environment = "beta"
            #endif

            options.releaseName = "\(bundleIdentifier)@\(version)"
            options.dist = build
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.reportAccessibilityIdentifier = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0

            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableDataSwizzling = false
            options.enableCoreDataTracing = false
            options.enableTimeToFullDisplayTracing = false
            options.configureProfiling = nil

            options.enableSwizzling = false
            options.enableAutoBreadcrumbTracking = false
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

        isEnabled = SentrySDK.isEnabled
        breadcrumb(.appLaunched, area: .home)
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
    @discardableResult
    func captureDebugTestEvent() -> Bool {
        guard isEnabled else { return false }

        capture(
            message: .debugNonFatalTest,
            operation: .diagnostics,
            category: .test,
            area: .settings
        )
        DispatchQueue.global(qos: .utility).async {
            SentrySDK.flush(timeout: 2)
        }
        return true
    }

    func crashForDebugValidation() -> Never {
        fatalError("Intentional DEBUG-only Sentry crash validation")
    }
    #endif

    private static func validDSN(in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "SENTRY_DSN") as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$("),
              let components = URLComponents(string: trimmedValue),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user?.isEmpty == false,
              components.path.split(separator: "/").last?.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }

    private static func nonEmptyBundleValue(_ key: String, in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

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

    private static func sanitizedNumericContext(_ values: [SentryNumericContext: Int]) -> [String: Int] {
        values.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = min(max(entry.value, 0), maximumContextValue)
        }
    }

    private static func sanitize(_ event: Event) -> Event? {
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
            key == "area" || key == "operation" || key == "category"
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
            ]
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
