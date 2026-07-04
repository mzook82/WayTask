import Foundation

protocol AIProductRecognitionServicing {
    func suggestProduct(from imageData: Data?, barcode: BarcodeResult?) async -> RecognitionResult
}

struct LocalAIProductRecognitionService: AIProductRecognitionServicing {
    func suggestProduct(from imageData: Data?, barcode: BarcodeResult?) async -> RecognitionResult {
        guard imageData != nil else {
            return RecognitionResult(
                status: .unavailable,
                candidates: [],
                message: "AI recognition needs a product photo. Add the details manually.",
                inputSource: .barcode
            )
        }

        return RecognitionResult(
            status: .unavailable,
            candidates: [],
            message: "AI product recognition is not available in this build. Add the details manually.",
            inputSource: .barcode
        )
    }
}
