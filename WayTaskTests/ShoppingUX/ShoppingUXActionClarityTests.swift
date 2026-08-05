import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ShoppingUXActionClarityTests: XCTestCase {
    func testProductsRemovesToolbarPlusAndKeepsBottomCatalogActions()
        throws {
        let products = try productionSourceSection(
            from: "private struct WayTaskProductionProductsView",
            to: "private struct WayTaskProductionProductRow"
        )

        XCTAssertFalse(products.contains(".primaryAction"))
        XCTAssertFalse(products.contains("isCreatingCustomProduct"))
        XCTAssertTrue(products.contains("Add from Catalog"))
        XCTAssertTrue(products.contains("Label(\"Scan\""))
        XCTAssertTrue(products.contains("Label(\"Shopping\""))
        XCTAssertTrue(products.contains("isAddingCatalogProduct = true"))
    }

    func testCustomCreationIsOfferedOnlyForMeaningfulCompletedNoMatch() {
        XCTAssertNil(
            CatalogCustomCreationPolicy.offeredName(
                for: "",
                searchCompletedWithoutMatch: true
            )
        )
        XCTAssertNil(
            CatalogCustomCreationPolicy.offeredName(
                for: "x",
                searchCompletedWithoutMatch: true
            )
        )
        XCTAssertNil(
            CatalogCustomCreationPolicy.offeredName(
                for: "Whole Wheat Bread",
                searchCompletedWithoutMatch: false
            )
        )
        XCTAssertEqual(
            CatalogCustomCreationPolicy.offeredName(
                for: "  Whole Wheat Bread  ",
                searchCompletedWithoutMatch: true
            ),
            "Whole Wheat Bread"
        )
    }

    func testCustomProductConfirmationPreservesPrefilledQuery() {
        let viewModel = AddProductAutocompleteViewModel(
            searchAvailability: .unavailable
        )
        viewModel.updateQuery(
            "Whole Wheat Bread",
            localeIdentifier: "en"
        )

        let selection = viewModel.selectCustomProduct(
            named: "Whole Wheat Bread"
        )

        XCTAssertEqual(selection?.name, "Whole Wheat Bread")
        XCTAssertEqual(selection?.preselectionQuery, "Whole Wheat Bread")
        XCTAssertEqual(viewModel.selectedFieldValue, "Whole Wheat Bread")
    }

    func testContextualCustomFormAndDestinationRulesAreExplicit() throws {
        let source = try productionSource()

        XCTAssertTrue(
            source.contains(
                "Create “\\(customName)” as a Custom Product"
            )
        )
        XCTAssertTrue(source.contains("initialName: pendingCustomName"))
        XCTAssertTrue(source.contains("autocomplete.phase == .noMatch"))
        XCTAssertTrue(
            source.contains(
                "Creating this custom product also adds it to"
            )
        )
        XCTAssertTrue(
            source.contains(
                "The custom product will be saved to Products."
            )
        )
    }

    func testShoppingActionsExposeListAndMapContext() throws {
        let source = try productionSource()

        XCTAssertTrue(source.contains("Text(\"New List\")"))
        XCTAssertTrue(source.contains("shopping-new-list-button"))
        XCTAssertTrue(source.contains("context: \"to \\(list.title)\""))
        XCTAssertTrue(source.contains("title: \"Find Stores\""))
        XCTAssertTrue(source.contains("\"for \\(list.title)\""))
        XCTAssertTrue(source.contains("\"Add products first\""))
        XCTAssertTrue(source.contains("Select or Create a Shopping List"))
        XCTAssertTrue(source.contains(".disabled(neededQuantity <= 0)"))
    }

    func testNoSelectedListCannotOpenProductAddition() throws {
        let source = try productionSource()

        XCTAssertTrue(source.contains("if let selectedList {"))
        XCTAssertTrue(source.contains("selectedListActions(selectedList)"))
        XCTAssertTrue(source.contains("noSelectedListActions"))
        XCTAssertTrue(
            source.contains(
                "Select or create a shopping list before adding a product."
            )
        )
    }

    func testExactIdentityDoesNotCreateSecondRowAndCanIncreaseQuantity()
        throws {
        let runtime = try makeRuntime()
        _ = try XCTUnwrap(runtime.createList(title: "Weekly Shopping"))
        XCTAssertTrue(runtime.acquireProduct(name: "Milk"))
        let product = try XCTUnwrap(activeProducts(runtime).first)
        var list = try XCTUnwrap(projectedLists(runtime).first)

        runtime.addProduct(product.id, to: list)
        list = try XCTUnwrap(projectedLists(runtime).first)
        let entry = try XCTUnwrap(list.neededEntries.first)
        let match = ShoppingListDuplicatePolicy.match(
            candidate: product,
            entries: list.neededEntries
        )

        XCTAssertEqual(match?.evidence, .exactProductIdentity)
        XCTAssertTrue(runtime.increaseQuantity(of: entry, in: list))

        list = try XCTUnwrap(projectedLists(runtime).first)
        XCTAssertEqual(list.neededEntries.count, 1)
        XCTAssertEqual(list.neededEntries.first?.quantity, 2)

        runtime.addProduct(product.id, to: list)
        list = try XCTUnwrap(projectedLists(runtime).first)
        XCTAssertEqual(list.neededEntries.count, 1)
    }

    func testNormalizedNameDuplicateRequiresDecisionAndIsNotExact() {
        let existing = product(
            id: UUID(),
            name: "Whole-Wheat Bread",
            category: "Bakery"
        )
        let candidate = product(
            id: UUID(),
            name: "whole wheat bread",
            category: nil
        )
        let entry = listEntry(product: existing)

        let match = ShoppingListDuplicatePolicy.match(
            candidate: candidate,
            entries: [entry]
        )

        XCTAssertEqual(match?.evidence, .normalizedDisplayName)
        XCTAssertEqual(match?.isExactProductIdentity, false)
    }

    func testCatalogAndBarcodeEvidenceDetectPossibleDifferentIdentity() {
        let catalogID = ProductStateCatalogID(rawValue: "bread_whole_wheat")
        let existing = product(
            id: UUID(),
            name: "Whole Wheat Loaf",
            barcode: "0123456789",
            catalogID: catalogID
        )
        let catalogCandidate = product(
            id: UUID(),
            name: "100% Whole Wheat Bread",
            catalogID: catalogID
        )
        let barcodeCandidate = product(
            id: UUID(),
            name: "Bread",
            barcode: "0123456789"
        )
        let entries = [listEntry(product: existing)]

        XCTAssertEqual(
            ShoppingListDuplicatePolicy.match(
                candidate: catalogCandidate,
                entries: entries
            )?.evidence,
            .matchingCatalogIdentity
        )
        XCTAssertEqual(
            ShoppingListDuplicatePolicy.match(
                candidate: barcodeCandidate,
                entries: entries
            )?.evidence,
            .matchingBarcode
        )
    }

    func testConflictingVariantEvidenceAllowsSeparateProducts() {
        let existing = product(
            id: UUID(),
            name: "Sparkling Water",
            brand: "Brand A",
            barcode: "111"
        )
        let differentBrand = product(
            id: UUID(),
            name: "Sparkling Water",
            brand: "Brand B",
            barcode: "222"
        )

        XCTAssertNil(
            ShoppingListDuplicatePolicy.match(
                candidate: differentBrand,
                entries: [listEntry(product: existing)]
            )
        )
    }

    func testEquivalentBreadUsesOneIconDespiteCategorySnapshotDrift() {
        let catalog = product(
            id: UUID(),
            name: "Whole-Wheat Bread",
            category: "Bakery",
            categoryID: "bakery",
            semanticKey: "product.bread"
        )
        let scanned = product(
            id: UUID(),
            name: "whole wheat bread",
            category: "Dairy",
            categoryID: "dairy",
            semanticKey: "product.dairy"
        )

        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: catalog),
            "basket.fill"
        )
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: scanned),
            ProductKnowledgeIconResolver.systemName(for: catalog)
        )
    }

    func testExistingProductAndListRecordsRemainReadable() throws {
        let runtime = try makeRuntime()
        let listID = try XCTUnwrap(runtime.createList(title: "Persisted"))
        XCTAssertTrue(runtime.acquireProduct(name: "Persisted Product"))
        let product = try XCTUnwrap(activeProducts(runtime).first)
        let list = try XCTUnwrap(projectedLists(runtime).first)
        runtime.addProduct(product.id, to: list)

        let reloaded = ProductStateRuntime(
            modelContainer: runtime.modelContainer,
            cutoverRecord: testCutoverRecord
        )

        XCTAssertEqual(projectedLists(reloaded).map(\.id), [listID])
        XCTAssertEqual(activeProducts(reloaded).map(\.id), [product.id])
        XCTAssertEqual(
            projectedLists(reloaded).first?.neededEntries.count,
            1
        )
    }

    private func product(
        id: UUID,
        name: String,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        catalogID: ProductStateCatalogID? = nil,
        categoryID: String? = nil,
        semanticKey: String? = nil
    ) -> ProductStateProductProjection {
        ProductStateProductProjection(
            id: ProductStateProductID(rawValue: id),
            revision: 0,
            libraryLifecycle: .active,
            libraryRemovedAt: nil,
            displayName: name,
            brand: brand,
            category: category,
            barcode: barcode,
            catalogID: catalogID,
            catalogDisplayNameSnapshot: nil,
            catalogDisplayLocaleSnapshot: nil,
            catalogCategoryIDSnapshot: categoryID,
            catalogCategoryDisplayNameSnapshot: category,
            catalogIconKeySnapshot: semanticKey,
            catalogSnapshotUpdatedAt: nil,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func listEntry(
        product: ProductStateProductProjection
    ) -> ProductStateListEntryProjection {
        ProductStateListEntryProjection(
            identity: ProductStateListEntryIdentity(
                id: ProductStateListEntryID(rawValue: UUID()),
                listID: ProductStateListID(rawValue: UUID()),
                productID: product.id
            ),
            state: .needed,
            quantity: 1,
            unitRawValue: nil,
            note: nil,
            sortOrder: 0,
            product: product,
            issues: [],
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func makeRuntime() throws -> ProductStateRuntime {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT-030A-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ProductStateRuntime(
            modelContainer: container,
            cutoverRecord: testCutoverRecord
        )
    }

    private var testCutoverRecord: WayTaskProductStateCutoverRecord {
        WayTaskProductStateCutoverRecord(
            formatVersion: WayTaskProductStateCutoverRecord.formatVersion,
            authority: "product-state",
            schemaVersion: 4,
            sourceKind: "test",
            sourceFingerprint: nil,
            semanticFingerprint: nil,
            semanticDigest: nil,
            productCount: 0,
            listCount: 0,
            entryCount: 0,
            sessionCount: 0,
            historyEventCount: 0,
            compatibilityLegacyReadCount: 0,
            compatibilityLegacyWriteCount: 0
        )
    }

    private func projectedLists(
        _ runtime: ProductStateRuntime
    ) -> [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
    }

    private func activeProducts(
        _ runtime: ProductStateRuntime
    ) -> [ProductStateProductProjection] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        return library.products.map(\.product)
    }

    private func productionSource() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WayTask/ProductionRuntimePresentation.swift"
            ),
            encoding: .utf8
        )
    }

    private func productionSourceSection(
        from start: String,
        to end: String
    ) throws -> String {
        let source = try productionSource()
        let startIndex = try XCTUnwrap(source.range(of: start)?.lowerBound)
        let endIndex = try XCTUnwrap(
            source.range(of: end, range: startIndex..<source.endIndex)?
                .lowerBound
        )
        return String(source[startIndex..<endIndex])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
