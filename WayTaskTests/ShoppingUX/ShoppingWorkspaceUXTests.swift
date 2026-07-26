import XCTest
@testable import WayTask

@MainActor
final class ShoppingWorkspaceUXTests: XCTestCase {
    func testShoppingPlanPresentationIsInline() {
        XCTAssertEqual(
            ShoppingWorkspacePresentationPolicy.shoppingPlanMode,
            .inline
        )
        XCTAssertEqual(
            ShoppingWorkspacePresentationPolicy
                .inlinePlanAccessibilityIdentifier,
            "shopping-plan-inline"
        )
    }

    func testRecommendedStoreExpandsByDefaultWithoutBeingSelected() {
        let recommendedID = UUID()
        let alternateID = UUID()
        var state = ShoppingStoreAccordionState(
            recommendedStoreID: nil,
            selectedStoreID: nil,
            expandedStoreID: nil
        )

        state.synchronize(
            storeIDs: [recommendedID, alternateID]
        )

        XCTAssertEqual(
            state.recommendedStoreID,
            recommendedID
        )
        XCTAssertNil(state.selectedStoreID)
        XCTAssertEqual(state.expandedStoreID, recommendedID)
    }

    func testExpandingStoreDoesNotSelectItAndOnlyOneIsExpanded() {
        let recommendedID = UUID()
        let alternateID = UUID()
        var state = ShoppingStoreAccordionState(
            recommendedStoreID: recommendedID,
            selectedStoreID: nil,
            expandedStoreID: recommendedID
        )

        state.toggleExpansion(for: alternateID)

        XCTAssertNil(state.selectedStoreID)
        XCTAssertEqual(state.expandedStoreID, alternateID)
        XCTAssertNotEqual(
            state.expandedStoreID,
            recommendedID
        )
    }

    func testSelectingAnotherStoreCollapsesPreviouslyExpandedCard() {
        let recommendedID = UUID()
        let alternateID = UUID()
        var state = ShoppingStoreAccordionState(
            recommendedStoreID: recommendedID,
            selectedStoreID: recommendedID,
            expandedStoreID: recommendedID
        )

        state.select(storeID: alternateID)

        XCTAssertEqual(state.recommendedStoreID, recommendedID)
        XCTAssertEqual(state.selectedStoreID, alternateID)
        XCTAssertEqual(state.expandedStoreID, alternateID)
    }

    func testLongHebrewProductNameRemainsCompleteAndAllowsTwoLines() {
        let longName = "לחם מחיטה מלאה"
        let presentation = WayTaskProductLabelPresentation(
            itemNames: [longName]
        )

        XCTAssertEqual(presentation.visibleNames, [longName])
        XCTAssertEqual(
            WayTaskProductLabelPresentation.maximumLineCount,
            2
        )
        XCTAssertEqual(presentation.additionalCount, 0)
    }

    func testManyProductLabelsUsePlusNMore() {
        let names = [
            "לחם מחיטה מלאה",
            "חלב",
            "ביצים",
            "גבינה",
            "עגבניות"
        ]
        let presentation = WayTaskProductLabelPresentation(
            itemNames: names
        )

        XCTAssertEqual(
            presentation.visibleNames,
            Array(names.prefix(3))
        )
        XCTAssertEqual(presentation.additionalCount, 2)
    }
}
