import Foundation

struct OpenFoodFactsProvider: ProductDataProvider {
    let sourceType: DataSourceType = .publicDatabase
    let displayName = "Open Food Facts"

    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://world.openfoodfacts.org")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func products(for request: ProductDataRequest) async throws -> [ProductCandidate] {
        guard let barcode = request.barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidBarcode(barcode) else {
            throw DataProviderError.invalidRequest
        }

        let url = try productURL(for: barcode)
        var urlRequest = URLRequest(url: url, timeoutInterval: 12)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("WayTask iOS - Product lookup", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw DataProviderError.unavailable
            }

            let decodedResponse = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
            guard decodedResponse.status == 1,
                  let product = decodedResponse.product else {
                return []
            }

            guard let name = product.resolvedName else {
                return []
            }

            let imageData = try await loadImageData(from: product.imageURL)
            return [
                ProductCandidate(
                    name: name,
                    brand: product.resolvedBrand,
                    category: product.resolvedCategory,
                    confidence: nil,
                    source: .barcode,
                    productHints: product.productHints,
                    imageURL: product.imageURL,
                    imageData: imageData,
                    barcode: barcode
                )
            ]
        } catch let error as DataProviderError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw DataProviderError.networkUnavailable
            case .timedOut:
                throw DataProviderError.timeout
            default:
                throw DataProviderError.unavailable
            }
        } catch {
            throw DataProviderError.unavailable
        }
    }

    private func productURL(for barcode: String) throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v2/product/\(barcode).json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "product_name,product_name_en,generic_name,brands,categories,image_url")
        ]

        guard let url = components?.url else {
            throw DataProviderError.invalidRequest
        }

        return url
    }

    private func isValidBarcode(_ barcode: String) -> Bool {
        let allowedCharacters = CharacterSet.decimalDigits
        return barcode.count >= 6
            && barcode.count <= 18
            && barcode.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    private func loadImageData(from url: URL?) async throws -> Data? {
        guard let url else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

private struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let productNameEnglish: String?
    let genericName: String?
    let brands: String?
    let categories: String?
    let imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEnglish = "product_name_en"
        case genericName = "generic_name"
        case brands
        case categories
        case imageURL = "image_url"
    }

    var resolvedName: String? {
        [productName, productNameEnglish, genericName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var resolvedBrand: String? {
        brands?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var resolvedCategory: String? {
        categories?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var productHints: [String] {
        [resolvedBrand, resolvedCategory]
            .compactMap { $0 }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
