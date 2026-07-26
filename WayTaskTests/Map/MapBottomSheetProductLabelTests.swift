import XCTest
@testable import WayTask

@MainActor
final class MapBottomSheetProductLabelTests: XCTestCase {
    func testExactHebrewMapProductNameRemainsCompleteAndAllowsTwoLines() {
        let productName = "לחם מחיטה מלאה"
        let presentation = MapStoreProductLabelPresentation(
            itemNames: [productName]
        )

        XCTAssertEqual(presentation.visibleNames, [productName])
        XCTAssertEqual(
            presentation.visibleNames.first,
            "לחם מחיטה מלאה"
        )
        XCTAssertEqual(
            MapStoreProductLabelPresentation.maximumLineCount,
            2
        )
        XCTAssertEqual(presentation.additionalCount, 0)
    }

    func testMapProductLimitUsesPlusNWithoutTruncatingVisibleNames() {
        let names = [
            "לחם מחיטה מלאה",
            "חלב 3%",
            "ביצים",
            "גבינה",
            "עגבניות"
        ]
        let presentation = MapStoreProductLabelPresentation(
            itemNames: names
        )

        XCTAssertEqual(
            presentation.visibleNames,
            Array(
                names.prefix(
                    MapStoreProductLabelPresentation
                        .maximumVisibleCount
                )
            )
        )
        XCTAssertEqual(presentation.additionalCount, 2)
        XCTAssertEqual(
            presentation.visibleNames.first,
            "לחם מחיטה מלאה"
        )
    }
}
