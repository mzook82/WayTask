import Foundation

enum ProductSource: String, Codable, Sendable {
    case manual
    case barcode
    case camera
    case ai
    case discover

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .barcode:
            return "Barcode"
        case .camera:
            return "Camera"
        case .ai:
            return "AI"
        case .discover:
            return "Discover"
        }
    }
}
