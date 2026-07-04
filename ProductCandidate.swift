import Foundation

enum ProductCandidateSource: String, Codable, Sendable {
    case cameraPhoto
    case photoLibrary
    case barcode
    case ai
    case manual
    case unknown
}

struct ProductCandidate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let brand: String?
    let category: String?
    let confidence: Double?
    let productType: String?
    let flavor: String?
    let packageSize: String?
    let packageType: String?
    let visibleText: String?
    let source: ProductCandidateSource
    let productHints: [String]
    let searchKeywords: [String]
    let imageURL: URL?
    let imageData: Data?
    let barcode: String?

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        category: String? = nil,
        confidence: Double? = nil,
        productType: String? = nil,
        flavor: String? = nil,
        packageSize: String? = nil,
        packageType: String? = nil,
        visibleText: String? = nil,
        source: ProductCandidateSource = .unknown,
        productHints: [String] = [],
        searchKeywords: [String] = [],
        imageURL: URL? = nil,
        imageData: Data? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.confidence = confidence
        self.productType = productType
        self.flavor = flavor
        self.packageSize = packageSize
        self.packageType = packageType
        self.visibleText = visibleText
        self.source = source
        self.productHints = productHints
        self.searchKeywords = searchKeywords
        self.imageURL = imageURL
        self.imageData = imageData
        self.barcode = barcode
    }
}
