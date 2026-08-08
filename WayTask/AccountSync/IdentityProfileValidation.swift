import Foundation

enum IdentityProfileField: String, Sendable {
    case displayName
}

enum IdentityProfileValidationReason: String, Sendable {
    case empty
    case tooLong
    case controlCharacter
    case invisibleCharacter
    case bidirectionalControl
}

struct IdentityProfileValidationError: Error, Equatable, Sendable {
    let field: IdentityProfileField
    let reason: IdentityProfileValidationReason

    var userMessage: String {
        switch reason {
        case .empty:
            return "Enter a display name."
        case .tooLong:
            return "Display name must be 80 characters or fewer."
        case .controlCharacter, .invisibleCharacter, .bidirectionalControl:
            return "Display name contains unsupported invisible characters."
        }
    }
}

enum IdentityProfileValidationContract {
    nonisolated static let maximumDisplayNameLength = 80

    // U+200D (ZWJ) and variation selectors remain allowed so composed emoji,
    // including family emoji, are preserved. U+200C remains allowed because it
    // is meaningful orthography in Persian and other Arabic-script languages.
    private nonisolated static let rejectedInvisibleScalars: Set<UInt32> = [
        0x200B, // zero-width space
        0x2060, // word joiner
        0xFEFF  // BOM / zero-width no-break space
    ]

    private nonisolated static let rejectedBidirectionalScalars: Set<UInt32> = [
        0x061C, 0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069
    ]

    nonisolated static func normalizeDisplayName(
        _ input: String
    ) throws -> String {
        let precomposed = input.precomposedStringWithCanonicalMapping
        for scalar in precomposed.unicodeScalars {
            if rejectedInvisibleScalars.contains(scalar.value) {
                throw IdentityProfileValidationError(
                    field: .displayName,
                    reason: .invisibleCharacter
                )
            }
            if rejectedBidirectionalScalars.contains(scalar.value) {
                throw IdentityProfileValidationError(
                    field: .displayName,
                    reason: .bidirectionalControl
                )
            }
            // Foundation includes permitted join controls in its broad control
            // character set. Preserve only the two explicitly documented
            // exceptions after rejecting all prohibited format controls above.
            if scalar.value == 0x200C || scalar.value == 0x200D {
                continue
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                throw IdentityProfileValidationError(
                    field: .displayName,
                    reason: .controlCharacter
                )
            }
        }

        let words = precomposed
            .split(whereSeparator: { character in
                character.unicodeScalars.allSatisfy {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                }
            })
        let normalized = words.map(String.init).joined(separator: " ")
        guard !normalized.isEmpty else {
            throw IdentityProfileValidationError(
                field: .displayName,
                reason: .empty
            )
        }
        // PostgreSQL char_length counts Unicode code points, so use the same
        // boundary here instead of Swift's extended-grapheme count.
        guard normalized.unicodeScalars.count <= maximumDisplayNameLength else {
            throw IdentityProfileValidationError(
                field: .displayName,
                reason: .tooLong
            )
        }
        return normalized
    }
}
