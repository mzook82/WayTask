import Foundation

enum WayTaskCloudField: String, Sendable {
    case listName
    case productDisplayName
    case note
    case description
    case quantity
    case locale
    case webURL
    case barcode
    case imageMetadata
    case batchRecordCount
    case payloadSize
    case timestamp
}

struct WayTaskCloudValidationIssue: Error, Equatable, Sendable {
    let field: WayTaskCloudField
    let reason: String
}

struct WayTaskImageMetadata: Equatable, Sendable {
    let mimeType: String
    let byteCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
}

enum WayTaskCloudValidationContract {
    static let listNameLength = 1...120
    static let productNameLength = 1...200
    static let noteMaximumLength = 2_000
    static let descriptionMaximumLength = 4_000
    static let quantityRange = 0.001...999_999.999
    static let maximumBatchRecordCount = 500
    static let maximumPayloadBytes = 1_048_576
    static let maximumImageBytes = 10 * 1_048_576
    static let maximumImageDimension = 12_000
    static let allowedLocales: Set<String> = [
        "he", "he-IL", "en", "en-US", "ar", "ar-IL"
    ]
    static let allowedImageMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/webp"
    ]
}

struct WayTaskCloudFieldValidator {
    func validateListName(_ value: String) throws {
        try validateText(
            value,
            field: .listName,
            allowedLength: WayTaskCloudValidationContract.listNameLength,
            allowsNewlines: false
        )
    }

    func validateProductDisplayName(_ value: String) throws {
        try validateText(
            value,
            field: .productDisplayName,
            allowedLength: WayTaskCloudValidationContract.productNameLength,
            allowsNewlines: false
        )
    }

    func validateNote(_ value: String?) throws {
        guard let value else { return }
        try validateText(
            value,
            field: .note,
            allowedLength: 0...WayTaskCloudValidationContract.noteMaximumLength,
            allowsNewlines: true
        )
    }

    func validateDescription(_ value: String?) throws {
        guard let value else { return }
        try validateText(
            value,
            field: .description,
            allowedLength: 0...WayTaskCloudValidationContract.descriptionMaximumLength,
            allowsNewlines: true
        )
    }

    func validateQuantity(_ value: Double) throws {
        guard value.isFinite,
              WayTaskCloudValidationContract.quantityRange.contains(value)
        else {
            throw issue(.quantity, "must be finite and within the safe range")
        }
    }

    func validateLocale(_ value: String) throws {
        guard WayTaskCloudValidationContract.allowedLocales.contains(value) else {
            throw issue(.locale, "is not in the supported locale allowlist")
        }
    }

    func validateWebURL(_ value: URL?) throws {
        guard let value else { return }
        guard ["http", "https"].contains(value.scheme?.lowercased() ?? ""),
              value.host != nil,
              value.absoluteString.utf8.count <= 2_048,
              value.user == nil,
              value.password == nil
        else {
            throw issue(.webURL, "must be an HTTP(S) URL without credentials")
        }
    }

    func validateBarcode(_ value: String?) throws {
        guard let value else { return }
        guard (6...32).contains(value.count),
              value.allSatisfy(\.isNumber),
              value.unicodeScalars.allSatisfy({ $0.isASCII })
        else {
            throw issue(.barcode, "must contain 6 to 32 ASCII digits")
        }
    }

    func validateImageMetadata(_ value: WayTaskImageMetadata?) throws {
        guard let value else { return }
        guard WayTaskCloudValidationContract.allowedImageMIMETypes
            .contains(value.mimeType),
              (1...WayTaskCloudValidationContract.maximumImageBytes)
                .contains(value.byteCount),
              (1...WayTaskCloudValidationContract.maximumImageDimension)
                .contains(value.pixelWidth),
              (1...WayTaskCloudValidationContract.maximumImageDimension)
                .contains(value.pixelHeight)
        else {
            throw issue(.imageMetadata, "is outside the approved image limits")
        }
    }

    func validateBatch(recordCount: Int, payloadBytes: Int) throws {
        guard (1...WayTaskCloudValidationContract.maximumBatchRecordCount)
            .contains(recordCount) else {
            throw issue(.batchRecordCount, "exceeds the maximum batch size")
        }
        guard (1...WayTaskCloudValidationContract.maximumPayloadBytes)
            .contains(payloadBytes) else {
            throw issue(.payloadSize, "exceeds the maximum payload size")
        }
    }

    func validateTimestamp(_ value: Date, now: Date = Date()) throws {
        guard value <= now.addingTimeInterval(300) else {
            throw issue(.timestamp, "is too far in the future")
        }
    }

    private func validateText(
        _ value: String,
        field: WayTaskCloudField,
        allowedLength: ClosedRange<Int>,
        allowsNewlines: Bool
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowedLength.contains(trimmed.count) else {
            throw issue(field, "is outside the approved length")
        }
        let forbidden = value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else {
                return false
            }
            if allowsNewlines,
               ["\n", "\r", "\t"].contains(Character(String(scalar))) {
                return false
            }
            return true
        }
        guard !forbidden else {
            throw issue(field, "contains unsupported control characters")
        }
    }

    private func issue(
        _ field: WayTaskCloudField,
        _ reason: String
    ) -> WayTaskCloudValidationIssue {
        WayTaskCloudValidationIssue(field: field, reason: reason)
    }
}
