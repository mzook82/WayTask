import Foundation

enum ProductCandidateSource: String, Codable, Sendable {
    case cameraPhoto
    case photoLibrary
    case barcode
    case manual
    case unknown
}

struct ProductCandidate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let brand: String?
    let category: String?
    let confidence: Double?
    let source: ProductCandidateSource
    let productHints: [String]

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        category: String? = nil,
        confidence: Double? = nil,
        source: ProductCandidateSource = .unknown,
        productHints: [String] = []
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.confidence = confidence
        self.source = source
        self.productHints = productHints
    }
}
