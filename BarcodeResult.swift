import Foundation

enum BarcodeType: String, Codable, Sendable {
    case ean13
    case ean8
    case upcA
    case upcE
    case qr
    case unknown

    var displayName: String {
        switch self {
        case .ean13:
            return "EAN-13"
        case .ean8:
            return "EAN-8"
        case .upcA:
            return "UPC-A"
        case .upcE:
            return "UPC-E"
        case .qr:
            return "QR"
        case .unknown:
            return "Barcode"
        }
    }
}

struct BarcodeResult: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let value: String
    let type: BarcodeType
    let scannedAt: Date
    let confidence: Double?

    init(
        id: UUID = UUID(),
        value: String,
        type: BarcodeType,
        scannedAt: Date = Date(),
        confidence: Double? = nil
    ) {
        self.id = id
        self.value = value
        self.type = type
        self.scannedAt = scannedAt
        self.confidence = confidence
    }
}
