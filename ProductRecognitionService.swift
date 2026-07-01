import Foundation

protocol ProductRecognitionServicing {
    func analyzeProduct(from imageData: Data, inputSource: RecognitionInputSource) async -> RecognitionResult
}

struct ProductRecognitionService: ProductRecognitionServicing {
    func analyzeProduct(from imageData: Data, inputSource: RecognitionInputSource) async -> RecognitionResult {
        RecognitionResult(
            status: .unavailable,
            candidates: [],
            message: "AI recognition is not available yet.",
            inputSource: inputSource
        )
    }
}
