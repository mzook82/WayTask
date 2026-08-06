import Foundation

enum WayTaskCloudEnvironment: String, CaseIterable, Codable, Sendable {
    case local
    case development
    case staging
    case production
}

struct WayTaskSupabaseConfiguration: Equatable, Sendable {
    let environment: WayTaskCloudEnvironment
    let projectURL: URL
    let publishableKey: String
}

enum WayTaskCloudConfigurationIssue: String, Equatable, Sendable {
    case incompleteConfiguration
    case unknownEnvironment
    case invalidProjectURL
    case insecureRemoteURL
    case nonLocalDevelopmentURL
    case invalidPublishableKey
    case privilegedSecretRejected
}

enum WayTaskCloudConfigurationStatus: Equatable, Sendable {
    case notConfigured
    case configured(WayTaskSupabaseConfiguration)
    case invalid(WayTaskCloudConfigurationIssue)

    var environment: WayTaskCloudEnvironment? {
        guard case let .configured(configuration) = self else {
            return nil
        }
        return configuration.environment
    }

    nonisolated var permitsCloudClientCreation: Bool {
        if case .configured = self { return true }
        return false
    }
}

struct WayTaskCloudFeatureFlags: Equatable, Sendable {
    let accountsEnabled: Bool
    let synchronizationEnabled: Bool
    let firstMigrationEnabled: Bool
    let secureAIRecognitionEnabled: Bool

    nonisolated static let disabled = WayTaskCloudFeatureFlags(
        accountsEnabled: false,
        synchronizationEnabled: false,
        firstMigrationEnabled: false,
        secureAIRecognitionEnabled: false
    )

    nonisolated init(
        accountsEnabled: Bool,
        synchronizationEnabled: Bool,
        firstMigrationEnabled: Bool,
        secureAIRecognitionEnabled: Bool = false
    ) {
        self.accountsEnabled = accountsEnabled
        self.synchronizationEnabled =
            accountsEnabled && synchronizationEnabled
        self.firstMigrationEnabled =
            accountsEnabled && synchronizationEnabled && firstMigrationEnabled
        self.secureAIRecognitionEnabled =
            accountsEnabled && secureAIRecognitionEnabled
    }
}

enum WayTaskCloudConfiguration {
    nonisolated static let environmentKey = "WAYTASK_SUPABASE_ENVIRONMENT"
    nonisolated static let projectURLKey = "WAYTASK_SUPABASE_URL"
    nonisolated static let publishableKeyKey =
        "WAYTASK_SUPABASE_PUBLISHABLE_KEY"
    nonisolated static let accountsFlagKey =
        "WAYTASK_CLOUD_ACCOUNTS_ENABLED"
    nonisolated static let syncFlagKey = "WAYTASK_CLOUD_SYNC_ENABLED"
    nonisolated static let migrationFlagKey =
        "WAYTASK_CLOUD_MIGRATION_ENABLED"
    nonisolated static let secureAIFlagKey =
        "WAYTASK_SECURE_AI_ENABLED"

    nonisolated static func resolve(
        values: [String: String]
    ) -> WayTaskCloudConfigurationStatus {
        let environmentValue = normalized(values[environmentKey])
        let urlValue = normalized(values[projectURLKey])
        let keyValue = normalized(values[publishableKeyKey])

        if environmentValue == nil, urlValue == nil, keyValue == nil {
            return .notConfigured
        }
        guard let environmentValue, let urlValue, let keyValue else {
            return .invalid(.incompleteConfiguration)
        }
        guard let environment = WayTaskCloudEnvironment(
            rawValue: environmentValue.lowercased()
        ) else {
            return .invalid(.unknownEnvironment)
        }
        guard let projectURL = URL(string: urlValue),
              projectURL.user == nil,
              projectURL.password == nil,
              projectURL.query == nil,
              projectURL.fragment == nil,
              let scheme = projectURL.scheme?.lowercased(),
              let host = projectURL.host?.lowercased()
        else {
            return .invalid(.invalidProjectURL)
        }

        switch environment {
        case .local:
            guard ["http", "https"].contains(scheme),
                  ["localhost", "127.0.0.1", "::1"].contains(host)
            else {
                return .invalid(.nonLocalDevelopmentURL)
            }
        case .development, .staging, .production:
            guard scheme == "https" else {
                return .invalid(.insecureRemoteURL)
            }
        }

        guard isStructurallySafeClientKey(keyValue) else {
            return .invalid(.invalidPublishableKey)
        }
        guard !looksLikePrivilegedSecret(keyValue) else {
            return .invalid(.privilegedSecretRejected)
        }

        return .configured(
            WayTaskSupabaseConfiguration(
                environment: environment,
                projectURL: projectURL,
                publishableKey: keyValue
            )
        )
    }

    nonisolated static func resolve(bundle: Bundle = .main)
        -> WayTaskCloudConfigurationStatus {
        resolve(values: stringValues(from: bundle.infoDictionary ?? [:]))
    }

    nonisolated static func featureFlags(
        values: [String: String],
        configurationStatus: WayTaskCloudConfigurationStatus
    ) -> WayTaskCloudFeatureFlags {
        guard configurationStatus.permitsCloudClientCreation else {
            return .disabled
        }
        return WayTaskCloudFeatureFlags(
            accountsEnabled: enabled(values[accountsFlagKey]),
            synchronizationEnabled: enabled(values[syncFlagKey]),
            firstMigrationEnabled: enabled(values[migrationFlagKey]),
            secureAIRecognitionEnabled: enabled(values[secureAIFlagKey])
        )
    }

    nonisolated static func featureFlags(
        bundle: Bundle = .main,
        configurationStatus: WayTaskCloudConfigurationStatus
    ) -> WayTaskCloudFeatureFlags {
        featureFlags(
            values: stringValues(from: bundle.infoDictionary ?? [:]),
            configurationStatus: configurationStatus
        )
    }

    private nonisolated static func stringValues(
        from dictionary: [String: Any]
    ) -> [String: String] {
        dictionary.reduce(into: [:]) { result, element in
            if let value = element.value as? String {
                result[element.key] = value
            }
        }
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        guard let result = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !result.isEmpty, !result.contains("$(") else {
            return nil
        }
        return result
    }

    private nonisolated static func enabled(_ value: String?) -> Bool {
        switch normalized(value)?.lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }

    private nonisolated static func isStructurallySafeClientKey(
        _ value: String
    ) -> Bool {
        guard (16...4096).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                      !CharacterSet.controlCharacters.contains(scalar)
              })
        else {
            return false
        }
        return true
    }

    private nonisolated static func looksLikePrivilegedSecret(
        _ value: String
    ) -> Bool {
        let lowercased = value.lowercased()
        let protectedKeyPrefix = "sb_" + "secret_"
        let protectedRole = "service_" + "role"
        if lowercased.hasPrefix(protectedKeyPrefix) ||
            lowercased.contains(protectedRole) {
            return true
        }

        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let dictionary = object as? [String: Any],
              let role = dictionary["role"] as? String
        else {
            return false
        }
        return role.lowercased() != "anon"
    }

    private nonisolated static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
