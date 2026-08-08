import Foundation

struct GuestMigrationRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let baseDelayMilliseconds: UInt64

    static let bounded = GuestMigrationRetryPolicy(
        maximumAttempts: 3,
        baseDelayMilliseconds: 250
    )
}

final class SupabaseGuestMigrationTransport:
    GuestMigrationTransport, @unchecked Sendable {
    typealias AccessTokenProvider = @Sendable () async throws -> String

    private let endpointURL: URL
    private let publishableKey: String
    private let session: URLSession
    private let accessToken: AccessTokenProvider
    private let retryPolicy: GuestMigrationRetryPolicy

    init(
        configuration: WayTaskSupabaseConfiguration,
        session: URLSession = .shared,
        retryPolicy: GuestMigrationRetryPolicy = .bounded,
        accessToken: @escaping AccessTokenProvider
    ) throws {
        guard configuration.environment == .staging else {
            throw GuestMigrationFoundationError.activationBlocked(
                configuration.environment == .production
                    ? .productionDenied : .notStaging
            )
        }
        endpointURL = configuration.projectURL
            .appendingPathComponent("functions/v1/initial-migration")
        publishableKey = configuration.publishableKey
        self.session = session
        self.retryPolicy = retryPolicy
        self.accessToken = accessToken
    }

    func begin(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws {
        _ = try await request([
            "operation": "begin",
            "attempt_id": attemptID.uuidString.lowercased(),
            "local_dataset_id": manifest.dataset.localDataSetID.uuidString
                .lowercased(),
            "dataset_fingerprint": manifest.datasetFingerprint,
            "format_version": manifest.dataset.migrationFormatVersion,
            "counts": try jsonObject(manifest.dataset.counts)
        ])
    }

    func upload(
        attemptID: UUID,
        batchID: String,
        plan: GuestMigrationBatchPlan,
        payload: Data
    ) async throws -> GuestMigrationReceipt {
        let response = try await request([
            "operation": "upload",
            "attempt_id": attemptID.uuidString.lowercased(),
            "batch_id": batchID,
            "sequence": plan.sequence,
            "entity_kind": plan.entityKind.rawValue,
            "payload_sha256": plan.payloadSHA256,
            "records": try JSONSerialization.jsonObject(with: payload)
        ])
        return try JSONDecoder().decode(
            GuestMigrationReceipt.self,
            from: response
        )
    }

    func verify(
        attemptID: UUID,
        manifest: GuestMigrationManifest
    ) async throws -> GuestMigrationVerification {
        let response = try await request([
            "operation": "verify",
            "attempt_id": attemptID.uuidString.lowercased()
        ])
        return try JSONDecoder().decode(
            GuestMigrationVerification.self,
            from: response
        )
    }

    func rollback(attemptID: UUID) async throws {
        _ = try await request([
            "operation": "rollback",
            "attempt_id": attemptID.uuidString.lowercased()
        ])
    }

    private func request(_ body: [String: Any]) async throws -> Data {
        let encoded = try JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys]
        )
        guard encoded.count <= 1_100_000 else {
            throw GuestMigrationFoundationError.oversizedBatch
        }

        var lastFailure: GuestMigrationFoundationError = .serviceUnavailable
        for attempt in 0..<retryPolicy.maximumAttempts {
            do {
                let token = try await accessToken()
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "POST"
                request.httpBody = encoded
                request.timeoutInterval = 30
                request.setValue(
                    "application/json",
                    forHTTPHeaderField: "Content-Type"
                )
                request.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
                request.setValue(
                    publishableKey,
                    forHTTPHeaderField: "apikey"
                )
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GuestMigrationFoundationError.serviceUnavailable
                }
                switch http.statusCode {
                case 200..<300:
                    return data.isEmpty ? Data("{}".utf8) : data
                case 401:
                    throw GuestMigrationFoundationError.sessionExpired
                case 403:
                    throw GuestMigrationFoundationError.activationBlocked(
                        .unresolvedSecurityBlocker
                    )
                case 409:
                    throw GuestMigrationFoundationError.accountConflict
                case 400:
                    throw GuestMigrationFoundationError.invalidLocalDataset
                case 422:
                    throw GuestMigrationFoundationError.verificationFailed
                case 413:
                    throw GuestMigrationFoundationError.oversizedBatch
                case 500..<600:
                    lastFailure = .serviceUnavailable
                default:
                    throw GuestMigrationFoundationError.serviceUnavailable
                }
            } catch let error as GuestMigrationFoundationError {
                switch error {
                case .serviceUnavailable, .offline:
                    lastFailure = error
                default:
                    throw error
                }
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost,
                     .internationalRoamingOff:
                    lastFailure = .offline
                default:
                    lastFailure = .serviceUnavailable
                }
            } catch {
                throw GuestMigrationFoundationError.serviceUnavailable
            }
            if attempt + 1 < retryPolicy.maximumAttempts {
                let multiplier = UInt64(1 << attempt)
                try await Task.sleep(
                    nanoseconds: retryPolicy.baseDelayMilliseconds
                        * multiplier * 1_000_000
                )
            }
        }
        throw lastFailure
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(
            with: GuestMigrationCanonicalizer.data(for: value)
        )
    }
}
