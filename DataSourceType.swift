import Foundation

enum DataSourceType: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case appleMaps
    case openStreetMap
    case retailAPI
    case publicDatabase
    case aiProvider
    case userGenerated

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .appleMaps:
            return "Apple Maps"
        case .openStreetMap:
            return "OpenStreetMap"
        case .retailAPI:
            return "Retail API"
        case .publicDatabase:
            return "Public Database"
        case .aiProvider:
            return "AI Provider"
        case .userGenerated:
            return "User Generated"
        }
    }
}
