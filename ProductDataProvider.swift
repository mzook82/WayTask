import Foundation

struct ProductDataRequest: Sendable {
    let query: String?
    let barcode: String?
    let productHints: [String]
    let imageData: Data?

    init(
        query: String? = nil,
        barcode: String? = nil,
        productHints: [String] = [],
        imageData: Data? = nil
    ) {
        self.query = query
        self.barcode = barcode
        self.productHints = productHints
        self.imageData = imageData
    }
}

protocol ProductDataProvider: DataProvider where Request == ProductDataRequest, Response == [ProductCandidate] {
    func products(for request: ProductDataRequest) async throws -> [ProductCandidate]
}

extension ProductDataProvider {
    func fetch(_ request: ProductDataRequest) async throws -> [ProductCandidate] {
        try await products(for: request)
    }
}
