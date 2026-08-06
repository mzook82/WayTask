import Foundation
import XCTest
@testable import WayTask

final class AccountSyncErrorAndValidationTests: XCTestCase {
    func testEveryErrorCategoryHasSafeCompleteUXMetadata() {
        XCTAssertEqual(WayTaskAccountSyncErrorCategory.allCases.count, 15)
        XCTAssertEqual(WayTaskAccountSyncDiagnosticCode.allCases.count, 15)

        for category in WayTaskAccountSyncErrorCategory.allCases {
            let error = WayTaskAccountSyncError(category: category)
            XCTAssertFalse(error.userFacingTitle.isEmpty, category.rawValue)
            XCTAssertFalse(
                error.userFacingExplanation.isEmpty,
                category.rawValue
            )
            XCTAssertFalse(error.recommendedAction.isEmpty, category.rawValue)
            XCTAssertTrue(error.diagnosticCode.rawValue.hasPrefix("WTAS-"))
            XCTAssertFalse(
                error.userFacingExplanation.localizedCaseInsensitiveContains(
                    "postgres"
                )
            )
            XCTAssertFalse(
                error.userFacingExplanation.localizedCaseInsensitiveContains(
                    "jwt"
                )
            )
            XCTAssertFalse(
                error.userFacingExplanation.localizedCaseInsensitiveContains(
                    "sqlstate"
                )
            )
        }
    }

    func testApprovedOfflinePermissionRateAndServerMessages() {
        XCTAssertEqual(
            WayTaskAccountSyncError(category: .offline).userFacingExplanation,
            "Your changes are saved on this device. Sync will continue when you are back online."
        )
        XCTAssertEqual(
            WayTaskAccountSyncError(category: .permissionDenied)
                .userFacingExplanation,
            "We could not access this information. Sign in again or contact support if the problem continues."
        )
        XCTAssertEqual(
            WayTaskAccountSyncError(category: .rateLimited)
                .userFacingExplanation,
            "Too many attempts were made. Please wait a few minutes and try again."
        )
        XCTAssertEqual(
            WayTaskAccountSyncError(category: .serviceUnavailable)
                .userFacingExplanation,
            "WayTask could not sync right now. Your local information has not been lost."
        )
    }

    func testTextValidationPreservesHebrewApostrophesEmojiAndPunctuation() throws {
        let validator = WayTaskCloudFieldValidator()

        XCTAssertNoThrow(try validator.validateListName("קניות ליום ו׳ 🛒"))
        XCTAssertNoThrow(
            try validator.validateProductDisplayName("O'Brien's — חלב 3% 😊")
        )
        XCTAssertNoThrow(
            try validator.validateNote("שורה ראשונה\nשורה שנייה: 'בדיקה'.")
        )
    }

    func testTextAndQuantityBoundsRejectMalformedValues() {
        let validator = WayTaskCloudFieldValidator()

        XCTAssertThrowsError(try validator.validateListName("   "))
        XCTAssertThrowsError(
            try validator.validateProductDisplayName(
                String(repeating: "א", count: 201)
            )
        )
        XCTAssertThrowsError(try validator.validateListName("ok\u{0007}"))
        XCTAssertThrowsError(try validator.validateQuantity(.infinity))
        XCTAssertThrowsError(try validator.validateQuantity(0))
        XCTAssertNoThrow(try validator.validateQuantity(999_999.999))
    }

    func testLocaleURLBarcodeImageAndBatchContracts() throws {
        let validator = WayTaskCloudFieldValidator()

        XCTAssertNoThrow(try validator.validateLocale("he-IL"))
        XCTAssertThrowsError(try validator.validateLocale("not-a-locale"))
        XCTAssertNoThrow(
            try validator.validateWebURL(URL(string: "https://example.com/store"))
        )
        XCTAssertThrowsError(
            try validator.validateWebURL(URL(string: "file:///private/item"))
        )
        XCTAssertNoThrow(try validator.validateBarcode("7290000000000"))
        XCTAssertThrowsError(try validator.validateBarcode("ABC-123"))
        XCTAssertNoThrow(
            try validator.validateImageMetadata(
                WayTaskImageMetadata(
                    mimeType: "image/jpeg",
                    byteCount: 500_000,
                    pixelWidth: 2_000,
                    pixelHeight: 2_000
                )
            )
        )
        XCTAssertThrowsError(
            try validator.validateImageMetadata(
                WayTaskImageMetadata(
                    mimeType: "image/svg+xml",
                    byteCount: 500,
                    pixelWidth: 100,
                    pixelHeight: 100
                )
            )
        )
        XCTAssertNoThrow(
            try validator.validateBatch(recordCount: 500, payloadBytes: 1_048_576)
        )
        XCTAssertThrowsError(
            try validator.validateBatch(recordCount: 501, payloadBytes: 1)
        )
    }
}
