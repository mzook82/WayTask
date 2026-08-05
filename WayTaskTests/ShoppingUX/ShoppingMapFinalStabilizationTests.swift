import CoreLocation
import XCTest
@testable import WayTask

@MainActor
final class ShoppingMapFinalStabilizationTests: XCTestCase {
    func testShoppingNewListActionUsesReadableAdaptiveSectionLayout()
        throws {
        let shopping = try productionSection(
            from: "private struct WayTaskProductionShoppingView",
            to: "// MARK: - Map"
        )

        XCTAssertTrue(shopping.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(shopping.contains("newListButton(expands: false)"))
        XCTAssertTrue(shopping.contains("newListButton(expands: true)"))
        XCTAssertTrue(shopping.contains("Text(\"New List\")"))
        XCTAssertTrue(
            shopping.contains(
                ".accessibilityIdentifier(\"shopping-new-list-button\")"
            )
        )
        XCTAssertFalse(
            shopping.contains("ToolbarItem(placement: .primaryAction)")
        )
    }

    func testShoppingNewListActionPreservesExistingCreationFlow() throws {
        let shopping = try productionSection(
            from: "private struct WayTaskProductionShoppingView",
            to: "// MARK: - Map"
        )

        XCTAssertTrue(shopping.contains("beginCreatingList()"))
        XCTAssertTrue(shopping.contains("isPresented: $isCreatingList"))
        XCTAssertTrue(shopping.contains("runtime.createList(title: listTitle)"))
        XCTAssertTrue(shopping.contains("pendingProductChooserListID = id"))
    }

    func testEquivalentMapArraysDoNotRequirePublication() {
        let storeID = UUID()
        let product = MapProduct(
            id: UUID(),
            storeID: storeID,
            name: "Bread",
            coordinate: CLLocationCoordinate2D(
                latitude: 31.7,
                longitude: 35.2
            )
        )

        XCTAssertFalse(
            ShoppingMissionMapPublicationPolicy.shouldPublish(
                current: [product],
                proposed: [product]
            )
        )
        XCTAssertTrue(
            ShoppingMissionMapPublicationPolicy.shouldPublish(
                current: [product],
                proposed: []
            )
        )
    }

    func testMapModelRoutesStoreAndProductAssignmentsThroughStablePublishers()
        throws {
        let map = try productionSection(
            from: "private final class WayTaskProductionMapModel",
            to: "private struct WayTaskProductionMapView"
        )

        XCTAssertTrue(map.contains("private func publishStores"))
        XCTAssertTrue(map.contains("private func publishProducts"))
        XCTAssertTrue(map.contains("current: stores"))
        XCTAssertTrue(map.contains("current: products"))
        XCTAssertFalse(map.contains("stores = resolved"))
        XCTAssertFalse(map.contains("products = resolvedProducts"))
    }

    func testMapSelectionCoalescesCameraAndSheetAnimations() throws {
        let source = try productionSource()

        XCTAssertTrue(source.contains("selectionCameraTask?.cancel()"))
        XCTAssertTrue(
            source.contains("Task.sleep(for: .milliseconds(260))")
        )
        XCTAssertTrue(source.contains("animatesStoreChanges: false"))
        XCTAssertTrue(
            source.contains("value: model.selectedStoreID != nil")
        )
        XCTAssertFalse(
            source.contains(
                ".spring(response: 0.3, dampingFraction: 0.88)"
            )
        )
    }

    func testMapRepresentableSkipsSelectionOnlyInvalidation() throws {
        let map = try source("WayTaskMapView.swift")
        let production = try productionSection(
            from: "private struct WayTaskProductionMapView",
            to: "private extension String"
        )

        XCTAssertTrue(
            map.contains("struct WayTaskMapView: UIViewRepresentable, Equatable")
        )
        XCTAssertFalse(map.contains("let selectedStoreID"))
        XCTAssertTrue(map.contains("OverlaySignature"))
        XCTAssertTrue(map.contains("cameraShouldAnimate"))
        XCTAssertTrue(production.contains(".equatable()"))
    }

    func testLocationUpdatesAreCoalescedWithoutChangingMissionThreshold()
        throws {
        let map = try productionSection(
            from: "private final class WayTaskProductionMapModel",
            to: "private struct WayTaskProductionMapView"
        )

        XCTAssertTrue(
            map.contains("guard movement == nil || (movement ?? 0) >= 10")
        )
        XCTAssertTrue(map.contains("lastDiscoveryCoordinate"))
        XCTAssertTrue(map.contains(") >= 250"))
        XCTAssertTrue(map.contains("didStartLocationUpdates"))
    }

    private func productionSource() throws -> String {
        try source("WayTask/ProductionRuntimePresentation.swift")
    }

    private func productionSection(
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let value = try productionSource()
        guard let start = value.range(of: startMarker),
              let end = value.range(
                of: endMarker,
                range: start.lowerBound..<value.endIndex
              ) else {
            throw NSError(
                domain: "ShoppingMapFinalStabilizationTests",
                code: 1
            )
        }
        return String(value[start.lowerBound..<end.lowerBound])
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
