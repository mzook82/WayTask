import XCTest
@testable import WayTask

final class ProductionRuntimePresentationIntegrationTests: XCTestCase {
    func testProductionRootRestoresEveryAuthorizedSurface() throws {
        let presentation = try source("WayTask/ProductionRuntimePresentation.swift")
        let app = try source("WayTask/WayTaskApp.swift")

        XCTAssertTrue(app.contains("WayTaskProductionRuntimeView()"))
        XCTAssertTrue(presentation.contains("WayTaskProductionHomeView("))
        XCTAssertTrue(presentation.contains("WayTaskProductionProductsView("))
        XCTAssertTrue(presentation.contains("CameraView {"))
        XCTAssertTrue(presentation.contains("WayTaskProductionShoppingView("))
        XCTAssertTrue(presentation.contains("WayTaskProductionMapView("))
    }

    func testProductPresentationIsInteractiveAndUsesTargetCommands() throws {
        let presentation = try source("WayTask/ProductionRuntimePresentation.swift")

        XCTAssertTrue(presentation.contains("NavigationLink(value: row.id)"))
        XCTAssertTrue(presentation.contains(".editProduct("))
        XCTAssertTrue(presentation.contains(".removeProductFromLibrary("))
        XCTAssertTrue(presentation.contains("runtime.restore(product)"))
        XCTAssertTrue(presentation.contains("runtime.addProduct(product.id, to: list)"))
        XCTAssertTrue(presentation.contains("AddProductAutocompleteViewModel"))
        XCTAssertTrue(presentation.contains("confirmTargetAcquisition("))
        XCTAssertTrue(presentation.contains("confirmTargetRestore("))
        XCTAssertTrue(presentation.contains("Restore Product?"))
    }

    func testCameraUsesOnlyReviewedTargetAcquisition() throws {
        let camera = try source("CameraView.swift")

        XCTAssertTrue(camera.contains("prepareTargetAcquisitionConfirmation("))
        XCTAssertTrue(camera.contains("using: runtime.productCommands"))
        XCTAssertTrue(camera.contains("runtime.refresh()"))
        XCTAssertTrue(camera.contains("Restore Product?"))
        XCTAssertTrue(
            camera.contains(
                "productID: ProductStateProductID(rawValue: UUID())"
            )
        )
        XCTAssertFalse(camera.contains("@Environment(\\.modelContext)"))
        XCTAssertFalse(camera.contains("ShoppingListService()"))
        XCTAssertFalse(camera.contains("ProductKnowledgeService()"))
        XCTAssertFalse(camera.contains("appStateManager.shoppingListDidChange"))
    }

    func testMapRestoresProductionMapKitMarkersCardsAndBottomSheet() throws {
        let presentation = try source("WayTask/ProductionRuntimePresentation.swift")

        XCTAssertTrue(presentation.contains("WayTaskMapView("))
        XCTAssertTrue(presentation.contains("Text(\"Shopping Mission\")"))
        XCTAssertTrue(presentation.contains("Create New List"))
        XCTAssertFalse(presentation.contains("MapFilterBar("))
        XCTAssertTrue(presentation.contains("MapBottomSheet("))
        XCTAssertTrue(presentation.contains("StoreResolutionEngine.shared"))
        XCTAssertTrue(presentation.contains("MapProduct("))
        XCTAssertTrue(presentation.contains("storeCards"))
        XCTAssertTrue(presentation.contains("openInMaps("))
    }

    func testProductionPresentationDoesNotOwnPersistenceOrExposeAuthorityMetadata()
        throws {
        let presentation = try source("WayTask/ProductionRuntimePresentation.swift")
        let forbidden = [
            "@Query",
            "ModelContext",
            "modelContext",
            "ProductStateCompatibilityAdapter",
            "compatibilityCounters",
            "cutoverRecord",
            "Text(\"Revision",
            "Text(\"List revision",
            "snapshotID",
            "sessionSnapshotID",
            "BetaDiagnosticsView",
            ".save("
        ]

        for value in forbidden {
            XCTAssertFalse(
                presentation.contains(value),
                "Unexpected presentation authority or metadata: \(value)"
            )
        }
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
