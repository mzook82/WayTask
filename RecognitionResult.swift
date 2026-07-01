import Foundation

enum RecognitionInputSource: String, Codable, Sendable {
    case cameraCapture
    case photoLibrary
    case barcode
}

enum RecognitionResultStatus: String, Codable, Sendable {
    case recognized
    case noMatch
    case unavailable
    case failed
}

struct RecognitionResult: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let status: RecognitionResultStatus
    let candidates: [ProductCandidate]
    let message: String
    let inputSource: RecognitionInputSource
    let createdAt: Date

    init(
        id: UUID = UUID(),
        status: RecognitionResultStatus,
        candidates: [ProductCandidate] = [],
        message: String,
        inputSource: RecognitionInputSource,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.status = status
        self.candidates = candidates
        self.message = message
        self.inputSource = inputSource
        self.createdAt = createdAt
    }

    var bestCandidate: ProductCandidate? {
        candidates.max { lhs, rhs in
            (lhs.confidence ?? 0) < (rhs.confidence ?? 0)
        }
    }

    var hasCandidates: Bool {
        !candidates.isEmpty
    }
}
