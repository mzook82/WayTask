import Foundation

struct ProductRecognitionResult: Equatable {
    let name: String
}

protocol ProductRecognitionServicing {
    func recognizeProduct(from imageData: Data) async throws -> ProductRecognitionResult?
}

struct ProductRecognitionService: ProductRecognitionServicing {
    func recognizeProduct(from imageData: Data) async throws -> ProductRecognitionResult? {
        nil
    }
}
