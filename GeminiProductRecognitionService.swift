import Foundation
import UIKit

struct GeminiProductRecognitionService: AIProductRecognitionServicing {
    private let session: URLSession
    private let apiKeyProvider: () -> String?
    private let modelName: String
    private let endpointBaseURL: URL

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = GeminiAPIKeyProvider.apiKey,
        modelName: String = "gemini-2.5-flash",
        endpointBaseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.modelName = modelName
        self.endpointBaseURL = endpointBaseURL
    }

    func suggestProduct(from imageData: Data?, barcode: BarcodeResult?) async -> RecognitionResult {
        let isConfigured = apiKeyProvider() != nil
        #if DEBUG
        print("[WayTask Gemini] Gemini key configured: \(isConfigured)")
        #endif

        guard let apiKey = apiKeyProvider() else {
            return unavailableResult(
                message: "AI recognition is not configured yet. Add the product details manually."
            )
        }

        guard let imageData else {
            return unavailableResult(
                message: "AI recognition needs a product photo. Add the product details manually."
            )
        }

        do {
            let startDate = Date()
            let optimizedImage = try optimizeImageData(imageData)
            let request = try makeRequest(
                apiKey: apiKey,
                barcode: barcode,
                imageData: optimizedImage.data
            )

            #if DEBUG
            print("[WayTask Gemini] Gemini call started")
            #endif

            #if DEBUG
            print("[WayTask Gemini] Resized image: \(Int(optimizedImage.size.width))x\(Int(optimizedImage.size.height)) | upload: \(optimizedImage.data.count) bytes")
            #endif

            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(startDate)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                print("[WayTask Gemini] Provider unavailable. Response time: \(String(format: "%.2f", elapsed))s")
                #endif
                return unavailableResult(message: "AI recognition is unavailable right now. Add the details manually.")
            }

            let geminiResponse = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
            let text = geminiResponse.candidates
                .flatMap { $0.content.parts }
                .compactMap(\.text)
                .joined(separator: "\n")

            guard let suggestion = try decodeSuggestion(from: text),
                  let productName = suggestion.productName?.trimmedNonEmpty else {
                #if DEBUG
                print("[WayTask Gemini] No usable product suggestion. Response time: \(String(format: "%.2f", elapsed))s")
                #endif
                return unavailableResult(message: "AI could not identify this product confidently. Add the details manually.")
            }

            let confidence = min(max(suggestion.confidence ?? 0, 0), 1)
            let searchKeywords = normalizedSearchKeywords(from: suggestion.searchKeywords)
            let candidate = ProductCandidate(
                name: productName,
                brand: suggestion.brand?.trimmedNonEmpty,
                category: suggestion.category?.trimmedNonEmpty,
                confidence: confidence,
                source: .ai,
                productHints: ([
                    productName,
                    suggestion.brand?.trimmedNonEmpty,
                    suggestion.category?.trimmedNonEmpty,
                    barcode?.value,
                    suggestion.description?.trimmedNonEmpty
                ].compactMap { $0 } + searchKeywords).deduplicatedCaseInsensitive(),
                searchKeywords: searchKeywords,
                imageData: optimizedImage.data,
                barcode: barcode?.value
            )

            #if DEBUG
            print("[WayTask Gemini] Gemini call succeeded | response time: \(String(format: "%.2f", elapsed))s | confidence: \(confidence)")
            #endif

            return RecognitionResult(
                status: .recognized,
                candidates: [candidate],
                message: suggestion.description?.trimmedNonEmpty ?? "AI suggested this product. Review before adding.",
                inputSource: .barcode
            )
        } catch is CancellationError {
            return unavailableResult(message: "AI recognition was cancelled.")
        } catch {
            #if DEBUG
            print("[WayTask Gemini] Gemini call failed | fallback reason: \(error.localizedDescription)")
            #endif
            return unavailableResult(message: "AI recognition failed. Add the details manually.")
        }
    }

    private func makeRequest(apiKey: String, barcode: BarcodeResult?, imageData: Data) throws -> URLRequest {
        var components = URLComponents(
            url: endpointBaseURL.appendingPathComponent("models/\(modelName):generateContent"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw GeminiRecognitionError.invalidRequest
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GeminiGenerateContentRequest(
                contents: [
                    GeminiContent(parts: [
                        GeminiPart(text: prompt(for: barcode)),
                        GeminiPart(inlineData: GeminiInlineData(
                            mimeType: "image/jpeg",
                            data: imageData.base64EncodedString()
                        ))
                    ])
                ],
                generationConfig: GeminiGenerationConfig(responseMimeType: "application/json")
            )
        )
        return request
    }

    private func prompt(for barcode: BarcodeResult?) -> String {
        let barcodeContext = barcode.map { "The scanned barcode is \($0.value) (\($0.type.displayName))." } ?? "No barcode is available for this image."

        return """
        Identify the commercial product visible in this packaging image. \(barcodeContext) Use visible packaging only. Avoid guessing. If the product, brand, or category is not clearly visible, leave that field empty and use low confidence. Return 3 to 8 useful searchKeywords that describe the product, category, and shopping intent for future store matching. Do not include random guesses, private data, or user-specific data. Return ONLY structured JSON with this exact shape:
        {
          "productName": "",
          "brand": "",
          "category": "",
          "confidence": 0.0,
          "description": "",
          "searchKeywords": []
        }
        """
    }

    private func optimizeImageData(_ data: Data) throws -> OptimizedImage {
        guard let image = UIImage(data: data) else {
            throw GeminiRecognitionError.invalidImage
        }

        let maxSide: CGFloat = 1280
        let originalSize = image.size
        let longestSide = max(originalSize.width, originalSize.height)
        let scale = longestSide > maxSide ? maxSide / longestSide : 1
        let targetSize = CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let qualities: [CGFloat] = [0.82, 0.72, 0.62]
        for quality in qualities {
            if let jpegData = resizedImage.jpegData(compressionQuality: quality) {
                return OptimizedImage(data: jpegData, size: targetSize)
            }
        }

        guard let fallbackData = image.jpegData(compressionQuality: 0.72) else {
            throw GeminiRecognitionError.invalidImage
        }

        #if DEBUG
        print("[WayTask Gemini] Image resize failed. Falling back to recompressed original.")
        #endif
        return OptimizedImage(data: fallbackData, size: originalSize)
    }

    private func normalizedSearchKeywords(from keywords: [String]?) -> [String] {
        (keywords ?? [])
            .compactMap { $0.trimmedNonEmpty }
            .filter { $0.count <= 48 }
            .deduplicatedCaseInsensitive()
            .prefixArray(8)
    }

    private func decodeSuggestion(from text: String) throws -> GeminiProductSuggestion? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(GeminiProductSuggestion.self, from: data)
    }

    private func unavailableResult(message: String) -> RecognitionResult {
        RecognitionResult(
            status: .unavailable,
            candidates: [],
            message: message,
            inputSource: .barcode
        )
    }
}

struct GeminiAPIKeyProvider {
    nonisolated static func apiKey() -> String? {
        if let key = SecretsManager.geminiAPIKey {
            return key
        }

        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        if let key = SecretsManager.normalizedKey(bundleValue) {
            return key
        }

        return SecretsManager.normalizedKey(ProcessInfo.processInfo.environment["GEMINI_API_KEY"])
    }
}

private enum GeminiRecognitionError: Error {
    case invalidImage
    case invalidRequest
}

private struct OptimizedImage {
    let data: Data
    let size: CGSize
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(inlineData: GeminiInlineData) {
        self.text = nil
        self.inlineData = inlineData
    }
}

private struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct GeminiGenerationConfig: Encodable {
    let responseMimeType: String

    enum CodingKeys: String, CodingKey {
        case responseMimeType = "response_mime_type"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiResponseCandidate]
}

private struct GeminiResponseCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}

private struct GeminiProductSuggestion: Decodable {
    let productName: String?
    let brand: String?
    let category: String?
    let confidence: Double?
    let description: String?
    let searchKeywords: [String]?
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(value)
        }

        return result
    }

    func prefixArray(_ maxLength: Int) -> [String] {
        Array(prefix(maxLength))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
