import Foundation

protocol DataProvider {
    associatedtype Request
    associatedtype Response

    var sourceType: DataSourceType { get }
    var displayName: String { get }

    func fetch(_ request: Request) async throws -> Response
}

enum DataProviderError: LocalizedError, Equatable {
    case unavailable
    case unsupportedSource(DataSourceType)
    case invalidRequest
    case networkUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This data source is unavailable."
        case .unsupportedSource(let sourceType):
            return "\(sourceType.displayName) is not supported yet."
        case .invalidRequest:
            return "The data request is invalid."
        case .networkUnavailable:
            return "No internet connection."
        case .timeout:
            return "The request timed out."
        }
    }
}
