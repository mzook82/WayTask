import CoreLocation
import UserNotifications
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
        XCTAssertTrue(production.contains("publishStores(recommendedStores)"))
        XCTAssertTrue(production.contains("publishProducts(resolvedProducts)"))
    }

    func testProductionRootOwnsNearbyNotificationsAndSharesMapAuthority()
        throws {
        let production = try source(
            "WayTask/ProductionRuntimePresentation.swift"
        )
        let notifications = try source("GeofenceNotificationService.swift")

        XCTAssertTrue(production.contains(
            "@StateObject private var nearbyNotifications"
        ))
        XCTAssertTrue(production.contains(
            "nearbyNotifications.configure("
        ))
        XCTAssertTrue(production.contains(
            "nearbyNotifications.applicationDidBecomeActive()"
        ))
        XCTAssertTrue(production.contains(
            "ShoppingMissionRecommendationAuthority"
        ))
        XCTAssertTrue(notifications.contains(
            "final class ProductionNearbyNotificationCoordinator"
        ))
        XCTAssertTrue(notifications.contains(
            "ShoppingMissionRecommendationAuthority"
        ))
        XCTAssertTrue(notifications.contains(
            "approvedRegionIdentifiers.contains(circular.identifier)"
        ))
        XCTAssertTrue(notifications.contains(
            "waytask.productionNearby.missionSignature.v1"
        ))
        XCTAssertTrue(notifications.contains(
            "case registrationSucceeded"
        ))
        XCTAssertTrue(notifications.contains(
            "case notificationRequestAcceptedDeliveryUnproven"
        ))
    }

    func testNavigationAndProductMatchingRemainConnected() throws {
        let source = try productionMapSource()

        XCTAssertTrue(source.contains("openInMaps("))
        XCTAssertTrue(source.contains("likelyItemNames: store.itemNames"))
        XCTAssertTrue(source.contains("StoreResolutionEngine.shared"))
        XCTAssertTrue(source.contains("sourceListID: listID"))
    }

    func testLocationFreshnessRejectsStaleAndInaccurateAutomaticRecenters()
        throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fresh = location(timestamp: now.addingTimeInterval(-5), accuracy: 25)
        let stale = location(timestamp: now.addingTimeInterval(-3_600), accuracy: 25)
        let inaccurate = location(timestamp: now, accuracy: 900)

        XCTAssertTrue(
            MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
                fresh,
                now: now
            )
        )
        XCTAssertFalse(
            MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
                stale,
                now: now
            )
        )
        XCTAssertFalse(
            MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
                inaccurate,
                now: now
            )
        )
        XCTAssertFalse(
            MapLocationFreshnessPolicy.shouldRefreshAfterActivation(
                inactiveSince: now.addingTimeInterval(-14 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            MapLocationFreshnessPolicy.shouldRefreshAfterActivation(
                inactiveSince: now.addingTimeInterval(-16 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            MapLocationFreshnessPolicy.shouldRefreshAfterActivation(
                inactiveSince: nil,
                now: now
            )
        )
        XCTAssertTrue(
            MapLocationFreshnessPolicy.shouldAutomaticallyFollowAfterActivation(
                inactiveSince: now.addingTimeInterval(-60),
                isUserExploring: false,
                now: now
            )
        )
        XCTAssertFalse(
            MapLocationFreshnessPolicy.shouldAutomaticallyFollowAfterActivation(
                inactiveSince: now.addingTimeInterval(-60),
                isUserExploring: true,
                now: now
            )
        )
        XCTAssertTrue(
            MapLocationFreshnessPolicy.shouldAutomaticallyFollowAfterActivation(
                inactiveSince: now.addingTimeInterval(-16 * 60),
                isUserExploring: true,
                now: now
            )
        )

        let production = try productionMapSource()
        XCTAssertTrue(production.contains("applicationDidBecomeInactive"))
        XCTAssertTrue(production.contains("applicationDidBecomeActive"))
        XCTAssertTrue(production.contains("pendingAutomaticFollow"))
        XCTAssertTrue(production.contains("pendingExplicitFollow"))
        XCTAssertTrue(production.contains("isUserExploring"))
        XCTAssertTrue(production.contains("remainingFreshLocationRetries"))
    }

    func testCompatibilityContractRejectsFashionJewelryAndUnknown() {
        let matcher = ShoppingIntentMatcher()
        let cottage = planItem(1, name: "קוטג׳", categoryID: nil)
        let trashBags = planItem(
            2,
            name: "שקיות אשפה",
            categoryID: nil
        )
        let toxic = store(
            title: "TOXIC FASHION / טוקסיק",
            latitude: 31.7,
            longitude: 35.2
        )
        let jewelry = store(
            title: "שפי תכשיטים",
            latitude: 31.7001,
            longitude: 35.2
        )
        let unknown = store(
            title: "Nearby Place",
            latitude: 31.7002,
            longitude: 35.2
        )

        for item in [cottage, trashBags] {
            XCTAssertEqual(
                matcher.compatibility(of: item, with: toxic).compatibility,
                .incompatible
            )
            XCTAssertEqual(
                matcher.compatibility(of: item, with: jewelry).compatibility,
                .incompatible
            )
            XCTAssertEqual(
                matcher.compatibility(of: item, with: unknown).compatibility,
                .unknown
            )
        }
        for title in ["TOXIC FASHION / טוקסיק", "שפי תכשיטים"] {
            XCTAssertTrue(
                ShoppingStoreCategoryFilter.shouldExclude(
                    storeTitle: title,
                    storeCategories: [.generalStore],
                    for: [.grocery, .supermarket]
                )
            )
        }
    }

    func testLocalizedTaxonomyCoversApprovedRetailTypes() {
        let matcher = ShoppingIntentMatcher()
        let cases: [(ShoppingPlanInputItem, MapStore)] = [
            (planItem(1, name: "קוטג׳", categoryID: "dairy"),
             typedStore("Local Grocery", .grocery)),
            (planItem(2, name: "חלב", categoryID: "dairy"),
             typedStore("Supermarket", .supermarket)),
            (planItem(3, name: "שקיות אשפה", categoryID: "household"),
             typedStore("Home Store", .generalStore)),
            (planItem(4, name: "קפה", categoryID: nil),
             typedStore("Coffee House", .coffeeShop)),
            (planItem(5, name: "לחם", categoryID: "bakery"),
             typedStore("Neighborhood Bakery", .grocery)),
            (planItem(6, name: "Coffee", categoryID: nil),
             typedStore("Coffee House", .coffeeShop)),
            (planItem(7, name: "Milk", categoryID: "dairy"),
             typedStore("Convenience Store", .convenienceStore)),
            (planItem(8, name: "Hazelnut Spread", categoryID: "pantry"),
             typedStore("Local Grocery", .grocery))
        ]

        for (item, store) in cases {
            XCTAssertEqual(
                matcher.compatibility(of: item, with: store).compatibility,
                .plausibleButUnverified,
                "\(item.displayName) × \(store.title)"
            )
        }
        XCTAssertEqual(
            matcher.compatibility(
                of: planItem(9, name: "לחם", categoryID: "bakery"),
                with: typedStore("Footwear Shop", .generalStore)
            ).compatibility,
            .incompatible
        )
        XCTAssertEqual(
            matcher.compatibility(
                of: planItem(10, name: "Medicine", categoryID: "pharmacy"),
                with: typedStore("Central Pharmacy", .pharmacy)
            ).compatibility,
            .plausibleButUnverified
        )
        XCTAssertEqual(
            matcher.compatibility(
                of: planItem(11, name: "שקיות אשפה", categoryID: "household"),
                with: typedStore("Hardware Store", .homeImprovement)
            ).compatibility,
            .plausibleButUnverified
        )
    }

    func testCompleteMissionCoverageOutranksDistanceAndFeedsNotifications() {
        let user = coordinate(latitude: 31.7, longitude: 35.2)
        let items = [
            planItem(1, name: "קוטג׳", categoryID: "dairy"),
            planItem(2, name: "שקיות אשפה", categoryID: "household")
        ]
        let stores = [
            typedStore("TOXIC FASHION", .generalStore, latitude: 31.70005),
            typedStore("שפי תכשיטים", .generalStore, latitude: 31.70008),
            typedStore("Hardware Store", .homeImprovement, latitude: 31.702),
            typedStore("Trusted Supermarket", .supermarket, latitude: 31.708)
        ]

        let recommendations = ShoppingMissionRecommendationAuthority
            .recommendations(
                stores: stores,
                items: items,
                userCoordinate: user
            )

        XCTAssertEqual(recommendations.first?.store.title, "Trusted Supermarket")
        XCTAssertEqual(
            recommendations.first?.store.itemNames,
            ["קוטג׳", "שקיות אשפה"]
        )
        XCTAssertFalse(recommendations.contains {
            $0.store.title.contains("FASHION") || $0.store.title.contains("תכשיטים")
        })

        // The notification coordinator consumes this same authority; there
        // is no second product/store matcher that can re-admit these stores.
        let geofenceEligibleStoreIDs = Set(recommendations.map(\.store.id))
        XCTAssertFalse(geofenceEligibleStoreIDs.contains(stores[0].id))
        XCTAssertFalse(geofenceEligibleStoreIDs.contains(stores[1].id))
    }

    func testNotificationCooldownAndDiagnosticStatesAreDistinct() {
        let suite = "WT-MAP-R1-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = GeofenceNotificationService(
            userDefaults: defaults,
            cooldown: 3_600
        )
        let candidate = ShoppingGeofenceCandidate(
            id: UUID(),
            locationID: nil,
            title: "Trusted Supermarket",
            coordinate: coordinate(latitude: 31.7, longitude: 35.2),
            radius: 180,
            itemNames: ["קוטג׳"],
            itemIDs: [UUID()],
            shoppingListID: UUID(),
            sourceType: DataSourceType.appleMaps.rawValue,
            distanceMeters: 100,
            notificationType: "shoppingGeofence"
        )
        let identifier = ShoppingGeofencePayload(candidate: candidate).identifier
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        guard case .request = service.notificationRequestOutcome(
            for: identifier,
            now: now
        ) else { return XCTFail("First notification should be accepted") }
        guard case .request = service.notificationRequestOutcome(
            for: identifier,
            now: now.addingTimeInterval(10)
        ) else {
            return XCTFail("Cooldown must not begin before request acceptance")
        }
        service.recordNotificationRequestAccepted(
            for: identifier,
            now: now
        )
        guard case let .suppressed(reason) = service.notificationRequestOutcome(
            for: identifier,
            now: now.addingTimeInterval(30)
        ) else { return XCTFail("Cooldown should suppress the duplicate") }
        XCTAssertEqual(reason, .cooldown)
        XCTAssertNotEqual(
            ProductionNearbyNotificationDiagnosticState.registrationSucceeded(1),
            .notificationRequestAcceptedDeliveryUnproven
        )
        XCTAssertNotEqual(
            ProductionNearbyNotificationDiagnosticState.permissionMissing(
                notification: "Denied",
                location: "When In Use"
            ),
            .noEligibleStores
        )
        XCTAssertNotEqual(
            ProductionNearbyNotificationDiagnosticState.osMonitoringLimit,
            .notificationSuppressedByCooldown
        )
    }

    private func store(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        items: [String] = [],
        categories: [ShoppingStoreCategory] = [.generalStore]
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
            storeCategories: categories,
            queryEvidenceCategories: categories,
            websiteURL: nil,
            sourceType: .appleMaps
        )
    }

    private func typedStore(
        _ title: String,
        _ category: ShoppingStoreCategory,
        latitude: Double = 31.7,
        longitude: Double = 35.2
    ) -> MapStore {
        store(
            title: title,
            latitude: latitude,
            longitude: longitude,
            categories: [category]
        )
    }

    private func planItem(
        _ value: UInt8,
        name: String,
        categoryID: String?
    ) -> ShoppingPlanInputItem {
        let listID = ProductStateListID(rawValue: id(200))
        return ShoppingPlanInputItem(
            identity: ProductStateListEntryIdentity(
                id: ProductStateListEntryID(rawValue: id(value)),
                listID: listID,
                productID: ProductStateProductID(rawValue: id(value &+ 50))
            ),
            quantity: 1,
            unitRawValue: nil,
            sortOrder: Double(value),
            displayName: name,
            brand: nil,
            category: nil,
            catalogID: nil,
            catalogCategoryID: categoryID,
            productLifecycle: .active
        )
    }

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }

    private func location(
        timestamp: Date,
        accuracy: CLLocationAccuracy
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate(latitude: 31.7, longitude: 35.2),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: accuracy,
            timestamp: timestamp
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
