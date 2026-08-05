import CoreLocation
import XCTest
@testable import WayTask

@MainActor
final class ShoppingMissionMapUXTests: XCTestCase {
    func testProductionMapUsesCompactMissionHeaderWithoutSearchFilters()
        throws {
        let source = try productionMapSource()

        XCTAssertTrue(source.contains("Text(\"Shopping Mission\")"))
        XCTAssertTrue(source.contains("Create New List"))
        XCTAssertTrue(source.contains("runtime.selectList(list.id)"))
        XCTAssertTrue(source.contains("needed \\(quantity == 1"))
        XCTAssertFalse(source.contains("MapFilterBar("))
        XCTAssertFalse(source.contains("searchText"))
        XCTAssertFalse(source.contains("selectedCategory"))
        XCTAssertFalse(source.contains("shoppingListOnly"))
    }

    func testProductionMapDismissesInputOnMapAndTabTransitions() throws {
        let source = try productionMapSource()

        XCTAssertTrue(source.contains("onClearSelection: clearMapSelection"))
        XCTAssertTrue(source.contains(".onDisappear { dismissKeyboard() }"))
        XCTAssertTrue(source.contains("if tab != .map { dismissKeyboard() }"))
        XCTAssertTrue(source.contains("UIResponder.resignFirstResponder"))
    }

    func testStoreSelectionTogglesAndReconcilesAgainstRecommendations() {
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(
            ShoppingMissionMapSelectionPolicy.toggledSelection(
                current: nil,
                tapped: first
            ),
            first
        )
        XCTAssertNil(
            ShoppingMissionMapSelectionPolicy.toggledSelection(
                current: first,
                tapped: first
            )
        )
        XCTAssertEqual(
            ShoppingMissionMapSelectionPolicy.toggledSelection(
                current: first,
                tapped: second
            ),
            second
        )
        XCTAssertNil(
            ShoppingMissionMapSelectionPolicy.validSelection(
                current: first,
                availableStoreIDs: [second]
            )
        )
    }

    func testMapTapAndRepeatedMarkerTapCanCloseBottomSheet() throws {
        let map = try source("WayTaskMapView.swift")
        let production = try productionMapSource()

        XCTAssertTrue(map.contains("handleMapBackgroundTap"))
        XCTAssertTrue(map.contains("parent.onClearSelection()"))
        XCTAssertTrue(map.contains("mapView.deselectAnnotation"))
        XCTAssertTrue(production.contains("if let store = model.selectedStore"))
        XCTAssertTrue(production.contains("model.clearSelection()"))
    }

    func testProductMatchesAtAStoreDoNotRenderAsDuplicateStoreMarkers() {
        let storeID = UUID()
        let orphanStoreID = UUID()
        let atStore = MapProduct(
            id: UUID(),
            storeID: storeID,
            name: "Bread",
            coordinate: coordinate(latitude: 31.7, longitude: 35.2)
        )
        let orphan = MapProduct(
            id: UUID(),
            storeID: orphanStoreID,
            name: "Milk",
            coordinate: coordinate(latitude: 31.8, longitude: 35.3)
        )

        XCTAssertEqual(
            ShoppingMissionMapMarkerPolicy.renderedProducts(
                storeIDs: [storeID],
                products: [atStore, orphan]
            ),
            [orphan]
        )
    }

    func testPhysicalStoreDuplicatesMergeButUnrelatedBusinessesDoNot() {
        let first = store(
            title: "Fresh Market",
            latitude: 31.70000,
            longitude: 35.20000,
            items: ["Bread"]
        )
        let duplicate = store(
            title: "Fresh Market",
            latitude: 31.70008,
            longitude: 35.20000,
            items: ["Milk"]
        )
        let unrelated = store(
            title: "Central Pharmacy",
            latitude: 31.70000,
            longitude: 35.20000,
            items: ["Medicine"]
        )

        XCTAssertTrue(
            ShoppingMissionStoreIdentityPolicy
                .representsSamePhysicalStore(first, duplicate)
        )
        XCTAssertFalse(
            ShoppingMissionStoreIdentityPolicy
                .representsSamePhysicalStore(first, unrelated)
        )

        let resolved = StoreResolutionEngine().deduplicated([
            first, duplicate, unrelated
        ])
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(
            Set(resolved.first { $0.title == "Fresh Market" }?.itemNames ?? []),
            ["Bread", "Milk"]
        )
    }

    func testSameNamedDistinctLocationsRemainSeparate() {
        let first = store(
            title: "Fresh Market",
            latitude: 31.7000,
            longitude: 35.2000
        )
        let otherBranch = store(
            title: "Fresh Market",
            latitude: 31.7030,
            longitude: 35.2000
        )

        XCTAssertFalse(
            ShoppingMissionStoreIdentityPolicy
                .representsSamePhysicalStore(first, otherBranch)
        )
        XCTAssertEqual(
            StoreResolutionEngine().deduplicated([first, otherBranch]).count,
            2
        )
    }

    func testMapUpdatesMarkersIncrementallyAndAvoidsRoutineCameraJumps()
        throws {
        let map = try source("WayTaskMapView.swift")
        let production = try productionMapSource()

        XCTAssertTrue(map.contains("reconcileAnnotations("))
        XCTAssertFalse(map.contains("removeAnnotations(existingAnnotations)"))
        XCTAssertTrue(map.contains("cameraRequestID"))
        XCTAssertTrue(production.contains("shouldRecenter(on:"))
        XCTAssertTrue(production.contains("publishStores(resolved)"))
        XCTAssertTrue(production.contains("publishProducts(resolvedProducts)"))
    }

    func testNavigationAndProductMatchingRemainConnected() throws {
        let source = try productionMapSource()

        XCTAssertTrue(source.contains("openInMaps("))
        XCTAssertTrue(source.contains("likelyItemNames: store.itemNames"))
        XCTAssertTrue(source.contains("StoreResolutionEngine.shared"))
        XCTAssertTrue(source.contains("sourceListID: listID"))
    }

    private func store(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        items: [String] = []
    ) -> MapStore {
        MapStore(
            id: id,
            locationID: nil,
            title: title,
            coordinate: coordinate(
                latitude: latitude,
                longitude: longitude
            ),
            radius: 180,
            itemNames: items,
            completedItemNames: [],
            isOpen: true,
            rating: nil,
            storeCategories: [.generalStore],
            queryEvidenceCategories: [.generalStore],
            websiteURL: nil,
            sourceType: .appleMaps
        )
    }

    private func coordinate(
        latitude: Double,
        longitude: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    private func productionMapSource() throws -> String {
        let value = try source("WayTask/ProductionRuntimePresentation.swift")
        guard let start = value.range(
            of: "private final class WayTaskProductionMapModel"
        ),
        let end = value.range(
            of: "private extension String",
            range: start.lowerBound..<value.endIndex
        ) else {
            throw NSError(domain: "ShoppingMissionMapUXTests", code: 1)
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
