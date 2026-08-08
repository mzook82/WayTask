import Foundation
import XCTest
@testable import WayTask

final class IdentityProfileValidationTests: XCTestCase {
    func testAdversarialStringsAreAcceptedAsLiteralDisplayNameData() throws {
        let accepted = [
            "DROP TABLE shopping_lists;",
            "' OR '1'='1",
            "\"; DELETE FROM profiles; --",
            "<script>alert(1)</script>",
            "<img src=x onerror=alert(1)>",
            "👻",
            "👨‍👩‍👧‍👦",
            "נועה לוי",
            "ليان أحمد",
            "José Álvarez",
            "王小明"
        ]

        for value in accepted {
            XCTAssertEqual(
                try IdentityProfileValidationContract
                    .normalizeDisplayName(value),
                value
            )
        }
    }

    func testUnicodeAndWhitespaceAreNormalizedWithoutDestroyingContent() throws {
        XCTAssertEqual(
            try IdentityProfileValidationContract
                .normalizeDisplayName("  Ada    Lovelace  "),
            "Ada Lovelace"
        )
        XCTAssertEqual(
            try IdentityProfileValidationContract
                .normalizeDisplayName("Jose\u{0301}"),
            "José"
        )
        XCTAssertEqual(
            try IdentityProfileValidationContract
                .normalizeDisplayName("שירה   أحمد"),
            "שירה أحمد"
        )
    }

    func testInvisibleBidiAndControlCharactersProduceTypedErrors() {
        assertRejected("A\u{200B}B", reason: .invisibleCharacter)
        assertRejected("A\u{202E}B", reason: .bidirectionalControl)
        assertRejected("A\nB", reason: .controlCharacter)
        assertRejected("A\tB", reason: .controlCharacter)
        assertRejected("A\u{0007}B", reason: .controlCharacter)
        assertRejected("A\0B", reason: .controlCharacter)
    }

    func testEmptyWhitespaceAndExtremeLengthProduceTypedErrors() throws {
        assertRejected("", reason: .empty)
        assertRejected("     ", reason: .empty)
        XCTAssertNoThrow(
            try IdentityProfileValidationContract.normalizeDisplayName(
                String(repeating: "א", count: 80)
            )
        )
        assertRejected(
            String(repeating: "א", count: 81),
            reason: .tooLong
        )
        assertRejected(
            String(repeating: "👨‍👩‍👧‍👦", count: 12),
            reason: .tooLong
        )
    }

    func testEmojiJoinerAndArabicNonJoinerPolicyIsExplicitlyAllowed() throws {
        XCTAssertEqual(
            try IdentityProfileValidationContract
                .normalizeDisplayName("👨‍👩‍👧‍👦"),
            "👨‍👩‍👧‍👦"
        )
        XCTAssertEqual(
            try IdentityProfileValidationContract
                .normalizeDisplayName("می\u{200C}خواهم"),
            "می\u{200C}خواهم"
        )
    }

    private func assertRejected(
        _ input: String,
        reason: IdentityProfileValidationReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try IdentityProfileValidationContract.normalizeDisplayName(input),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? IdentityProfileValidationError,
                IdentityProfileValidationError(
                    field: .displayName,
                    reason: reason
                ),
                file: file,
                line: line
            )
        }
    }
}
