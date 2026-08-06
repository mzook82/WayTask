import Foundation

/// Stable, non-destructive normalization for product knowledge comparisons.
///
/// Display values are never replaced with this projection. The same authority
/// is used by search, catalog validation, duplicate evidence, and acquisition
/// identity adapters so those paths cannot drift into different equivalence
/// rules.
nonisolated struct ProductKnowledgeNormalizedText: Equatable, Sendable {
    let value: String
    let tokens: [String]
}

nonisolated enum ProductKnowledgeNormalizer {
    private static let defaultLocale = Locale(identifier: "en_US_POSIX")
    private static let separator = UnicodeScalar(0x20)!
    private static let quoteScalars: Set<UnicodeScalar> = [
        "'", "\"", "`", "´", "‘", "’", "‚", "‛", "“", "”", "„", "‟", "׳", "״"
    ]

    static func searchText(
        _ input: String,
        localeIdentifier: String? = nil
    ) -> ProductKnowledgeNormalizedText {
        let locale = localeIdentifier.flatMap { identifier -> Locale? in
            let trimmed = identifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return trimmed.isEmpty ? nil : Locale(identifier: trimmed)
        } ?? defaultLocale
        let lowercased = input
            .decomposedStringWithCompatibilityMapping
            .lowercased(with: locale)
        var output = String.UnicodeScalarView()
        var separatorPending = false

        for scalar in lowercased.unicodeScalars {
            if quoteScalars.contains(scalar) {
                continue
            }

            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            case .uppercaseLetter,
                 .lowercaseLetter,
                 .titlecaseLetter,
                 .modifierLetter,
                 .otherLetter,
                 .decimalNumber:
                if separatorPending, !output.isEmpty {
                    output.append(separator)
                }
                output.append(normalizedHebrewFinalLetter(scalar))
                separatorPending = false
            default:
                if !output.isEmpty {
                    separatorPending = true
                }
            }
        }

        let value = String(output)
        return ProductKnowledgeNormalizedText(
            value: value,
            tokens: value.split(separator: " ").map(String.init)
        )
    }

    /// GTIN/barcode comparison accepts common visual separators but rejects
    /// other punctuation. Non-numeric provider identifiers are trimmed and
    /// case-folded without being treated as GTINs.
    static func barcode(_ input: String?) -> String? {
        guard let input else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let scalars = trimmed.unicodeScalars
        let digits = scalars.filter(CharacterSet.decimalDigits.contains)
        let ignorable = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "-–—")
        )
        if scalars.allSatisfy({
            CharacterSet.decimalDigits.contains($0) || ignorable.contains($0)
        }) {
            let value = String(String.UnicodeScalarView(digits))
            return value.isEmpty ? nil : value
        }

        let normalized = searchText(trimmed).value
        return normalized.isEmpty ? nil : normalized
    }

    static func localeIdentifier(_ input: String) -> String? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else { return nil }

        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = parts.first,
              (2...3).contains(language.count),
              language.unicodeScalars.allSatisfy(isASCIILetter),
              parts.dropFirst().allSatisfy({ part in
                  (2...8).contains(part.count)
                      && part.unicodeScalars.allSatisfy {
                          isASCIILetter($0) || isASCIIDigit($0)
                      }
              }) else {
            return nil
        }

        return parts.enumerated().map { index, part in
            index == 0 ? part.lowercased() : String(part)
        }.joined(separator: "-")
    }

    private static func normalizedHebrewFinalLetter(
        _ scalar: UnicodeScalar
    ) -> UnicodeScalar {
        switch scalar.value {
        case 0x05DA: UnicodeScalar(0x05DB)!
        case 0x05DD: UnicodeScalar(0x05DE)!
        case 0x05DF: UnicodeScalar(0x05E0)!
        case 0x05E3: UnicodeScalar(0x05E4)!
        case 0x05E5: UnicodeScalar(0x05E6)!
        default: scalar
        }
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
    }
}

// Compatibility spelling retained for existing callers. All behavior delegates
// to ProductKnowledgeNormalizer; it is not a second normalization policy.
typealias ProductSearchNormalizedText = ProductKnowledgeNormalizedText

nonisolated enum ProductSearchNormalizer {
    static func normalize(
        _ input: String,
        localeIdentifier: String? = nil
    ) -> ProductSearchNormalizedText {
        ProductKnowledgeNormalizer.searchText(
            input,
            localeIdentifier: localeIdentifier
        )
    }

    static func normalizeBarcode(_ input: String?) -> String? {
        ProductKnowledgeNormalizer.barcode(input)
    }
}
