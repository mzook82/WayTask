import Foundation
import UIKit

// The filename is retained to avoid unnecessary Xcode project churn. This file
// no longer contains a direct Gemini client. All AI traffic crosses the trusted
// server boundary described by SecureAIRecognitionPolicy.

struct SecureAIProxyConfiguration: Equatable, Sendable {
    let environment: WayTaskCloudEnvironment
    let endpointURL: URL
    let publishableKey: String
}

enum SecureAIConfigurationIssue: String, Equatable, Sendable {
    case productionNotApproved
    case invalidProxyURL
}

enum SecureAIConfigurationStatus: Equatable, Sendable {
    case disabled
    case configured(SecureAIProxyConfiguration)
    case invalid(SecureAIConfigurationIssue)
}

enum SecureAIRecognitionPolicy {
    nonisolated static let directClientFallbackAllowed = false
    nonisolated static let functionName = "recognize-product"

    nonisolated static func resolve(
        cloudStatus: WayTaskCloudConfigurationStatus,
        flags: WayTaskCloudFeatureFlags
    ) -> SecureAIConfigurationStatus {
        guard flags.secureAIRecognitionEnabled else {
            return .disabled
        }
        guard case let .configured(cloud) = cloudStatus else {
            return .disabled
        }
        guard cloud.environment == .local || cloud.environment == .staging else {
            return .invalid(.productionNotApproved)
        }

        let endpoint = cloud.projectURL
            .appendingPathComponent("functions", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(functionName, isDirectory: false)
        guard endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil
        else {
            return .invalid(.invalidProxyURL)
        }

        return .configured(
            SecureAIProxyConfiguration(
                environment: cloud.environment,
                endpointURL: endpoint,
                publishableKey: cloud.publishableKey
            )
        )
    }

    nonisolated static func resolve(bundle: Bundle = .main)
        -> SecureAIConfigurationStatus {
        let cloudStatus = WayTaskCloudConfiguration.resolve(bundle: bundle)
        let flags = WayTaskCloudConfiguration.featureFlags(
            bundle: bundle,
            configurationStatus: cloudStatus
        )
        return resolve(cloudStatus: cloudStatus, flags: flags)
    }
}

enum SecureAIRecognitionFailure: Equatable, Sendable {
    case notConfigured
    case offline
    case authenticationRequired
    case permissionDenied
    case rateLimited(retryAfterSeconds: Int?)
    case payloadTooLarge
    case unsupportedImage
    case serviceUnavailable
    case timeout
    case invalidResult
    case recoverableServerError
    case nonRecoverableConfiguration
    case duplicateRequest
    case cancelled

    var userMessage: String {
        switch self {
        case .notConfigured:
            return "Secure AI is not configured. Add the product details manually."
        case .offline:
            return "You’re offline. Your photo stayed on this device. Try again when connected or add the details manually."
        case .authenticationRequired:
            return "Sign in is required for secure AI recognition. Your photo stayed on this device."
        case .permissionDenied:
            return "Secure AI permission was denied. Sign in again or add the details manually."
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                return "Too many recognition requests. Try again in \(retryAfterSeconds) seconds or add the details manually."
            }
            return "Too many recognition requests. Wait a moment, then retry or add the details manually."
        case .payloadTooLarge:
            return "That image is too large for secure recognition. Choose a smaller image or add the details manually."
        case .unsupportedImage:
            return "That image could not be used. Choose a clear JPEG-compatible photo or add the details manually."
        case .serviceUnavailable:
            return "Secure AI is temporarily unavailable. Retry later or add the details manually."
        case .timeout:
            return "Secure AI took too long to respond. Retry or add the details manually."
        case .invalidResult:
            return "Secure AI did not return a usable product. Retake the photo or add the details manually."
        case .recoverableServerError:
            return "Secure AI could not finish this request. Retry later or add the details manually."
        case .nonRecoverableConfiguration:
            return "Secure AI is unavailable in this build. Add the product details manually."
        case .duplicateRequest:
            return "That recognition request was already handled. Retake the photo or start a new request."
        case .cancelled:
            return "Secure AI recognition was cancelled. Your photo stayed on this device."
        }
    }
}

struct SecureAIProductRecognitionService: AIProductRecognitionServicing {
    typealias AccessTokenProvider = () async -> String?

    nonisolated static let maximumInputImageBytes = 12 * 1_024 * 1_024
    nonisolated static let maximumUploadImageBytes = 2 * 1_024 * 1_024
    nonisolated static let maximumResponseBytes = 64 * 1_024
    nonisolated static let requestTimeout: TimeInterval = 20

    private let session: URLSession
    private let configurationStatus: SecureAIConfigurationStatus
    private let accessTokenProvider: AccessTokenProvider

    init(
        session: URLSession = .shared,
        configurationStatus: SecureAIConfigurationStatus =
            SecureAIRecognitionPolicy.resolve(),
        accessTokenProvider: @escaping AccessTokenProvider = {
            StagingAccountController.shared.secureAIAccessToken()
        }
    ) {
        self.session = session
        self.configurationStatus = configurationStatus
        self.accessTokenProvider = accessTokenProvider
    }

    func suggestProduct(
        from imageData: Data?,
        barcode: BarcodeResult?
    ) async -> RecognitionResult {
        let inputSource: RecognitionInputSource = barcode == nil
            ? .cameraCapture
            : .barcode

        let configuration: SecureAIProxyConfiguration
        switch configurationStatus {
        case .disabled:
            return unavailableResult(.notConfigured, inputSource: inputSource)
        case .invalid:
            return unavailableResult(
                .nonRecoverableConfiguration,
                inputSource: inputSource
            )
        case let .configured(value):
            configuration = value
        }

        guard let accessToken = normalizedAccessToken(
            await accessTokenProvider()
        ) else {
            return unavailableResult(
                .authenticationRequired,
                inputSource: inputSource
            )
        }
        guard let imageData else {
            return unavailableResult(
                .unsupportedImage,
                inputSource: inputSource
            )
        }
        guard imageData.count <= Self.maximumInputImageBytes else {
            return unavailableResult(
                .payloadTooLarge,
                inputSource: inputSource
            )
        }

        do {
            let optimizedImage = try optimizedJPEG(from: imageData)
            let requestID = UUID()
            let request = try makeRequest(
                configuration: configuration,
                accessToken: accessToken,
                requestID: requestID,
                imageData: optimizedImage,
                barcode: barcode
            )
            let (data, response) = try await session.data(for: request)
            guard data.count <= Self.maximumResponseBytes else {
                return unavailableResult(
                    .invalidResult,
                    inputSource: inputSource
                )
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                return unavailableResult(
                    .recoverableServerError,
                    inputSource: inputSource
                )
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return unavailableResult(
                    failure(
                        for: httpResponse,
                        responseData: data
                    ),
                    inputSource: inputSource
                )
            }

            let proxyResponse = try JSONDecoder().decode(
                SecureAIProxyResponse.self,
                from: data
            )
            guard proxyResponse.schemaVersion == 1,
                  proxyResponse.requestID == requestID
            else {
                return unavailableResult(
                    .invalidResult,
                    inputSource: inputSource
                )
            }

            switch proxyResponse.status {
            case "no_match":
                return RecognitionResult(
                    status: .noMatch,
                    candidates: [],
                    message: safeMessage(for: proxyResponse.messageCode),
                    inputSource: inputSource
                )
            case "recognized":
                guard let product = proxyResponse.product,
                      let candidate = candidate(
                        from: product,
                        imageData: optimizedImage,
                        barcode: normalizedBarcode(barcode)
                      )
                else {
                    return unavailableResult(
                        .invalidResult,
                        inputSource: inputSource
                    )
                }
                return RecognitionResult(
                    status: .recognized,
                    candidates: [candidate],
                    message: safeMessage(for: proxyResponse.messageCode),
                    inputSource: inputSource
                )
            default:
                return unavailableResult(
                    .invalidResult,
                    inputSource: inputSource
                )
            }
        } catch is CancellationError {
            return unavailableResult(.cancelled, inputSource: inputSource)
        } catch let error as SecureAIClientError {
            switch error {
            case .payloadTooLarge:
                return unavailableResult(
                    .payloadTooLarge,
                    inputSource: inputSource
                )
            case .unsupportedImage:
                return unavailableResult(
                    .unsupportedImage,
                    inputSource: inputSource
                )
            case .invalidRequest:
                return unavailableResult(
                    .nonRecoverableConfiguration,
                    inputSource: inputSource
                )
            }
        } catch let error as URLError {
            let failure: SecureAIRecognitionFailure
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                    .dataNotAllowed, .internationalRoamingOff:
                failure = .offline
            case .timedOut:
                failure = .timeout
            case .cancelled:
                failure = .cancelled
            default:
                failure = .serviceUnavailable
            }
            return unavailableResult(failure, inputSource: inputSource)
        } catch {
            return unavailableResult(
                .invalidResult,
                inputSource: inputSource
            )
        }
    }

    private func makeRequest(
        configuration: SecureAIProxyConfiguration,
        accessToken: String,
        requestID: UUID,
        imageData: Data,
        barcode: BarcodeResult?
    ) throws -> URLRequest {
        let payload = SecureAIProxyRequest(
            schemaVersion: 1,
            requestID: requestID,
            image: SecureAIProxyImage(
                mimeType: "image/jpeg",
                imageBase64: imageData.base64EncodedString()
            ),
            barcode: normalizedBarcode(barcode)
        )
        let body = try JSONEncoder().encode(payload)
        guard body.count <= 2_850_000 else {
            throw SecureAIClientError.payloadTooLarge
        }

        var request = URLRequest(
            url: configuration.endpointURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.requestTimeout
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
        return request
    }

    private func optimizedJPEG(from data: Data) throws -> Data {
        guard let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            throw SecureAIClientError.unsupportedImage
        }

        let maxSide: CGFloat = 1_280
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longestSide)
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        for quality in [0.82, 0.72, 0.62, 0.52, 0.42] as [CGFloat] {
            guard let jpeg = rendered.jpegData(compressionQuality: quality) else {
                continue
            }
            if jpeg.count <= Self.maximumUploadImageBytes {
                return jpeg
            }
        }
        throw SecureAIClientError.payloadTooLarge
    }

    private func normalizedAccessToken(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        (16...8_192).contains(value.utf8.count),
        !value.contains(" "),
        !value.contains("\n"),
        !value.contains("\r") else {
            return nil
        }
        return value
    }

    private func normalizedBarcode(
        _ barcode: BarcodeResult?
    ) -> SecureAIProxyBarcode? {
        guard let barcode,
              barcode.type != .qr,
              (6...32).contains(barcode.value.count),
              barcode.value.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return SecureAIProxyBarcode(
            value: barcode.value,
            type: barcode.type.rawValue
        )
    }

    private func candidate(
        from product: SecureAIProxyProduct,
        imageData: Data,
        barcode: SecureAIProxyBarcode?
    ) -> ProductCandidate? {
        guard let name = bounded(product.productName, maximum: 200) else {
            return nil
        }
        let confidence = min(max(product.confidence, 0), 1)
        let keywords = product.searchKeywords
            .compactMap { bounded($0, maximum: 48) }
            .deduplicatedCaseInsensitive()
            .prefixArray(8)
        let values = [
            name,
            bounded(product.brand, maximum: 160),
            bounded(product.category, maximum: 160),
            bounded(product.productType, maximum: 160),
            bounded(product.flavor, maximum: 160),
            bounded(product.packageSize, maximum: 80),
            bounded(product.packageType, maximum: 80),
            barcode?.value
        ].compactMap { $0 }

        return ProductCandidate(
            name: name,
            brand: bounded(product.brand, maximum: 160),
            category: bounded(product.category, maximum: 160),
            confidence: confidence,
            productType: bounded(product.productType, maximum: 160),
            flavor: bounded(product.flavor, maximum: 160),
            packageSize: bounded(product.packageSize, maximum: 80),
            packageType: bounded(product.packageType, maximum: 80),
            visibleText: bounded(product.visibleText, maximum: 500),
            source: .ai,
            productHints: (values + keywords).deduplicatedCaseInsensitive(),
            searchKeywords: keywords,
            imageData: imageData,
            barcode: barcode?.value
        )
    }

    private func bounded(_ value: String?, maximum: Int) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        !value.isEmpty,
        value.count <= maximum,
        value.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else {
            return nil
        }
        return value
    }

    private func safeMessage(for code: String?) -> String {
        switch code {
        case "review_result":
            return "Secure AI suggested this product. Review it before saving."
        case "retake_single_product":
            return "Retake the photo with one package filling the frame."
        case "retake_clearer_photo":
            return "Retake a clearer front photo of the package."
        case "no_match":
            return "Secure AI could not identify a product. Retake the photo or add the details manually."
        default:
            return "Review the secure AI suggestion before saving."
        }
    }

    private func failure(
        for response: HTTPURLResponse,
        responseData: Data
    ) -> SecureAIRecognitionFailure {
        let code = (try? JSONDecoder().decode(
            SecureAIProxyErrorEnvelope.self,
            from: responseData
        ))?.error.code
        switch response.statusCode {
        case 401:
            return .authenticationRequired
        case 403:
            return .permissionDenied
        case 408, 504:
            return .timeout
        case 409:
            return .duplicateRequest
        case 413:
            return .payloadTooLarge
        case 415:
            return .unsupportedImage
        case 422:
            return .invalidResult
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
            return .rateLimited(retryAfterSeconds: retry)
        case 500:
            return .recoverableServerError
        case 502, 503:
            return code == "not_configured"
                ? .nonRecoverableConfiguration
                : .serviceUnavailable
        default:
            return .recoverableServerError
        }
    }

    private func unavailableResult(
        _ failure: SecureAIRecognitionFailure,
        inputSource: RecognitionInputSource
    ) -> RecognitionResult {
        RecognitionResult(
            status: .unavailable,
            candidates: [],
            message: failure.userMessage,
            inputSource: inputSource
        )
    }
}

private enum SecureAIClientError: Error {
    case payloadTooLarge
    case unsupportedImage
    case invalidRequest
}

private struct SecureAIProxyRequest: Encodable {
    let schemaVersion: Int
    let requestID: UUID
    let image: SecureAIProxyImage
    let barcode: SecureAIProxyBarcode?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID = "requestId"
        case image
        case barcode
    }
}

private struct SecureAIProxyImage: Encodable {
    let mimeType: String
    let imageBase64: String
}

private struct SecureAIProxyBarcode: Codable {
    let value: String
    let type: String
}

private struct SecureAIProxyResponse: Decodable {
    let schemaVersion: Int
    let requestID: UUID
    let status: String
    let product: SecureAIProxyProduct?
    let messageCode: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID = "requestId"
        case status
        case product
        case messageCode
    }
}

private struct SecureAIProxyProduct: Decodable {
    let productName: String
    let brand: String?
    let category: String?
    let productType: String?
    let flavor: String?
    let packageSize: String?
    let packageType: String?
    let visibleText: String?
    let confidence: Double
    let searchKeywords: [String]
}

private struct SecureAIProxyErrorEnvelope: Decodable {
    struct ProxyError: Decodable {
        let code: String
    }

    let error: ProxyError
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    func prefixArray(_ maximum: Int) -> [String] {
        Array(prefix(maximum))
    }
}
