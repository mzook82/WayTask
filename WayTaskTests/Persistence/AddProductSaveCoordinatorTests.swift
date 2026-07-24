import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class AddProductSaveCoordinatorTests: XCTestCase {
    func testCatalogSelectionMapsExactSnapshotAndNeverCallsManualSave() throws {
        let context = try makeContext()
        let imageData = Data([0x10, 0x20, 0x30])
        let selectedResult = makeSearchResult()
        let selection = AddProductCatalogSelection(
            result: selectedResult,
            preselectionQuery: "mi"
        )
        let inserted = Product(name: "Inserted")
        var capturedRequest: CatalogProductSaveRequest?
        var catalogSaveCount = 0
        var manualSaveCount = 0
        let coordinator = AddProductSaveCoordinator(
            catalogSave: { request, _ in
                catalogSaveCount += 1
                capturedRequest = request
                return .inserted(inserted)
            },
            manualSave: { _, _, _ in
                manualSaveCount += 1
                throw UnexpectedSavePath()
            }
        )

        let outcome = try coordinator.save(
            selection: .catalog(selection),
            imageData: imageData,
            in: context
        )

        guard case .catalogInserted(let product) = outcome else {
            return XCTFail("Expected catalog inserted outcome")
        }
        XCTAssertEqual(product.id, inserted.id)
        XCTAssertEqual(catalogSaveCount, 1)
        XCTAssertEqual(manualSaveCount, 0)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.productID, selectedResult.productID)
        XCTAssertEqual(request.displayNameSnapshot, selectedResult.displayName)
        XCTAssertEqual(request.displayLocaleSnapshot, selectedResult.displayLocale)
        XCTAssertEqual(request.categoryIDSnapshot, selectedResult.categoryID)
        XCTAssertEqual(
            request.categoryDisplayNameSnapshot,
            selectedResult.categoryDisplayName
        )
        XCTAssertEqual(request.iconKeySnapshot, selectedResult.iconKey)
        XCTAssertEqual(request.imageData, imageData)
        XCTAssertEqual(request.source, .catalog)
    }

    func testCustomSelectionCallsOnlyAuthoritativeManualSave() throws {
        let context = try makeContext()
        let imageData = Data([0xaa, 0xbb])
        let selection = AddProductCustomSelection(
            name: "Custom Need",
            preselectionQuery: "  Custom Need  "
        )
        let inserted = Product(name: selection.name, source: .manual)
        var catalogSaveCount = 0
        var manualSaveCount = 0
        var capturedName: String?
        var capturedImageData: Data?
        let coordinator = AddProductSaveCoordinator(
            catalogSave: { _, _ in
                catalogSaveCount += 1
                throw UnexpectedSavePath()
            },
            manualSave: { name, imageData, _ in
                manualSaveCount += 1
                capturedName = name
                capturedImageData = imageData
                return inserted
            }
        )

        let outcome = try coordinator.save(
            selection: .custom(selection),
            imageData: imageData,
            in: context
        )

        guard case .manualInserted(let product) = outcome else {
            return XCTFail("Expected manual inserted outcome")
        }
        XCTAssertEqual(product.id, inserted.id)
        XCTAssertEqual(catalogSaveCount, 0)
        XCTAssertEqual(manualSaveCount, 1)
        XCTAssertEqual(capturedName, selection.name)
        XCTAssertEqual(capturedImageData, imageData)
    }

    func testAlreadyPresentOutcomeDoesNotCallManualSave() throws {
        let context = try makeContext()
        let existing = Product(
            name: "Saved Milk",
            imageData: Data([0x01]),
            source: .catalog,
            catalogProductIDRawValue: "prd_milk"
        )
        var manualSaveCount = 0
        let coordinator = AddProductSaveCoordinator(
            catalogSave: { _, _ in
                .alreadyPresent(existing)
            },
            manualSave: { _, _, _ in
                manualSaveCount += 1
                throw UnexpectedSavePath()
            }
        )

        let outcome = try coordinator.save(
            selection: .catalog(
                AddProductCatalogSelection(
                    result: makeSearchResult(),
                    preselectionQuery: "mi"
                )
            ),
            imageData: Data([0xff]),
            in: context
        )

        guard case .catalogAlreadyPresent(let product) = outcome else {
            return XCTFail("Expected catalog already-present outcome")
        }
        XCTAssertEqual(product.id, existing.id)
        XCTAssertEqual(product.name, "Saved Milk")
        XCTAssertEqual(product.imageData, Data([0x01]))
        XCTAssertEqual(manualSaveCount, 0)
    }

    func testCatalogFailureNeverFallsBackToManualAndCleanRetryUsesSameSelection() throws {
        struct ExpectedFailure: Error {}

        let context = try makeContext()
        let result = makeSearchResult()
        let selection = AddProductSelection.catalog(
            AddProductCatalogSelection(
                result: result,
                preselectionQuery: "mi"
            )
        )
        let inserted = Product(name: result.displayName)
        var catalogSaveCount = 0
        var manualSaveCount = 0
        var shouldFail = true
        let coordinator = AddProductSaveCoordinator(
            catalogSave: { request, _ in
                catalogSaveCount += 1
                XCTAssertEqual(request.productID, result.productID)
                if shouldFail {
                    shouldFail = false
                    throw ExpectedFailure()
                }
                return .inserted(inserted)
            },
            manualSave: { _, _, _ in
                manualSaveCount += 1
                throw UnexpectedSavePath()
            }
        )

        XCTAssertThrowsError(
            try coordinator.save(
                selection: selection,
                imageData: nil,
                in: context
            )
        ) { error in
            XCTAssertTrue(error is ExpectedFailure)
        }

        let retryOutcome = try coordinator.save(
            selection: selection,
            imageData: nil,
            in: context
        )

        guard case .catalogInserted = retryOutcome else {
            return XCTFail("Expected retry to insert catalog product")
        }
        XCTAssertEqual(catalogSaveCount, 2)
        XCTAssertEqual(manualSaveCount, 0)
    }

    private func makeContext() throws -> ModelContext {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try WayTaskModelContainer.make(
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func makeSearchResult() -> ProductSearchResult {
        ProductSearchResult(
            productID: ProductID("prd_milk"),
            displayName: "Milk",
            displayLocale: "en",
            secondaryName: "חלב",
            categoryID: ProductCategoryID("dairy"),
            categoryDisplayName: "Dairy",
            iconKey: "product.dairy",
            matchedRecordAuthority: .preferredDisplayName,
            matchType: .exact,
            matchedLocale: "he"
        )
    }
}

private struct UnexpectedSavePath: Error {}
