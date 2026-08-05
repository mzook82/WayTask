import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ShoppingUXFinalizationTests: XCTestCase {
    func testProgressUsesResolvedQuantityAndClampsInvalidInput() {
        let empty = ShoppingListProgressPresentation(
            neededQuantities: [],
            resolvedQuantities: []
        )
        XCTAssertEqual(empty.fraction, 0)
        XCTAssertEqual(empty.percentage, 0)
        XCTAssertEqual(empty.summary, "0 of 0 completed")

        let partial = ShoppingListProgressPresentation(
            neededQuantities: [2],
            resolvedQuantities: [3]
        )
        XCTAssertEqual(partial.fraction, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(partial.percentage, 60)
        XCTAssertEqual(partial.summary, "3 of 5 completed")

        let safe = ShoppingListProgressPresentation(
            neededQuantities: [-2, .nan, .infinity],
            resolvedQuantities: [1]
        )
        XCTAssertEqual(safe.fraction, 1)
        XCTAssertEqual(safe.percentage, 100)
        XCTAssertEqual(safe.summary, "1 of 1 completed")
    }

    func testRuntimeRenameDeleteSelectionAndRecoveryPreserveProducts()
        throws {
        let runtime = try makeRuntime()
        let firstID = try XCTUnwrap(runtime.createList(title: "First"))
        let secondID = try XCTUnwrap(runtime.createList(title: "Second"))
        XCTAssertEqual(runtime.selectedListID, secondID)

        XCTAssertTrue(runtime.acquireProduct(name: "Milk"))
        let product = try XCTUnwrap(activeProducts(runtime).first)
        var second = try XCTUnwrap(
            projectedLists(runtime).first { $0.id == secondID }
        )
        runtime.addProduct(product.id, to: second)
        second = try XCTUnwrap(
            projectedLists(runtime).first { $0.id == secondID }
        )
        XCTAssertEqual(second.neededEntries.count, 1)

        XCTAssertTrue(runtime.renameList(second, title: "Renamed"))
        second = try XCTUnwrap(
            projectedLists(runtime).first { $0.id == secondID }
        )
        XCTAssertEqual(second.title, "Renamed")

        let first = try XCTUnwrap(
            projectedLists(runtime).first { $0.id == firstID }
        )
        XCTAssertTrue(runtime.deleteList(first))
        XCTAssertEqual(runtime.selectedListID, secondID)
        XCTAssertEqual(projectedLists(runtime).map(\.id), [secondID])

        XCTAssertTrue(runtime.deleteList(second))
        XCTAssertNil(runtime.selectedListID)
        XCTAssertTrue(projectedLists(runtime).isEmpty)
        XCTAssertEqual(activeProducts(runtime).map(\.id), [product.id])

        let recoveredID = try XCTUnwrap(
            runtime.createList(title: "Recovered")
        )
        XCTAssertEqual(runtime.selectedListID, recoveredID)
        XCTAssertEqual(projectedLists(runtime).map(\.id), [recoveredID])

        let verification = ModelContext(runtime.modelContainer)
        XCTAssertEqual(
            try verification.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.Product>()
            ),
            1
        )
        XCTAssertEqual(
            try verification.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
            ),
            3,
            "Deleted lists remain logically archived for durable references"
        )
        XCTAssertEqual(
            try verification.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            ),
            1
        )
    }

    func testProductionActionsAndEmptyStatesHaveDistinctResponsibilities()
        throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WayTask/ProductionRuntimePresentation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("as a Custom Product")
        )
        XCTAssertTrue(source.contains("Add Product from Catalog"))
        XCTAssertTrue(source.contains("Create Shopping List"))
        XCTAssertTrue(
            source.contains("Add Product to Selected Shopping List")
        )
        XCTAssertTrue(source.contains("Delete Shopping List?"))
        XCTAssertTrue(source.contains("No Shopping Lists"))
        XCTAssertTrue(source.contains("No Products Yet"))
        XCTAssertTrue(source.contains("Select a Shopping List"))
        XCTAssertTrue(source.contains("presentPendingProductChooser"))
    }

    private func makeRuntime() throws -> ProductStateRuntime {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT-030-\(UUID().uuidString)",
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
            cutoverRecord: WayTaskProductStateCutoverRecord(
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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
