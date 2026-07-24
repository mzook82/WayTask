import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class CatalogProductPersistenceServiceTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewCatalogProductPersistsExactSnapshotsPhotoAndInjectedTimeInOneSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let imageData = Data([0x01, 0x23, 0x45, 0x67])
        var saveCount = 0
        let service = CatalogProductPersistenceService(
            clock: { self.fixedDate },
            saveContext: {
                saveCount += 1
                try $0.save()
            }
        )
        let request = makeRequest(imageData: imageData)

        let outcome = try service.save(request, in: context)
        let inserted = try insertedProduct(from: outcome)

        XCTAssertEqual(saveCount, 1)
        XCTAssertNotEqual(inserted.id.uuidString, request.productID.rawValue)
        XCTAssertEqual(inserted.name, request.displayNameSnapshot)
        XCTAssertEqual(inserted.category, request.categoryDisplayNameSnapshot)
        XCTAssertEqual(inserted.imageData, imageData)
        XCTAssertEqual(inserted.source, .catalog)
        XCTAssertEqual(inserted.dateAdded, fixedDate)
        XCTAssertEqual(inserted.updatedAt, fixedDate)
        XCTAssertEqual(inserted.catalogProductID, request.productID)
        XCTAssertEqual(inserted.catalogProductIDRawValue, request.productID.rawValue)
        XCTAssertEqual(inserted.catalogDisplayNameSnapshot, request.displayNameSnapshot)
        XCTAssertEqual(inserted.catalogDisplayLocaleSnapshot, request.displayLocaleSnapshot)
        XCTAssertEqual(
            inserted.catalogCategoryIDSnapshotRawValue,
            request.categoryIDSnapshot.rawValue
        )
        XCTAssertEqual(
            inserted.catalogCategoryDisplayNameSnapshot,
            request.categoryDisplayNameSnapshot
        )
        XCTAssertEqual(inserted.catalogIconKeySnapshot, request.iconKeySnapshot)
        XCTAssertEqual(inserted.catalogSnapshotUpdatedAt, fixedDate)
        XCTAssertNil(inserted.brand)
        XCTAssertNil(inserted.barcode)
        XCTAssertNil(inserted.legacyShoppingItemID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShoppingListEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShoppingItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductKnowledge>()).isEmpty)

        let reloadedContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            try reloadedContext.fetch(FetchDescriptor<Product>()).first
        )
        XCTAssertEqual(reloaded.id, inserted.id)
        XCTAssertEqual(reloaded.imageData, imageData)
        XCTAssertEqual(reloaded.catalogProductIDRawValue, request.productID.rawValue)
        XCTAssertEqual(reloaded.catalogDisplayLocaleSnapshot, "he")
        XCTAssertEqual(reloaded.catalogCategoryDisplayNameSnapshot, "מוצרי חלב")
        XCTAssertEqual(reloaded.catalogIconKeySnapshot, "product.dairy")
        XCTAssertEqual(reloaded.catalogSnapshotUpdatedAt, fixedDate)
    }

    func testSearchResultInitializerUsesDisplayLocaleRatherThanMatchLocale() {
        let result = ProductSearchResult(
            productID: ProductID("prd_test"),
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

        let request = CatalogProductSaveRequest(
            searchResult: result,
            imageData: nil
        )

        XCTAssertEqual(request.displayLocaleSnapshot, "en")
        XCTAssertNotEqual(request.displayLocaleSnapshot, result.matchedLocale)
        XCTAssertEqual(request.categoryDisplayNameSnapshot, "Dairy")
        XCTAssertEqual(request.source, .catalog)
    }

    func testSameProductIDReturnsExistingWithoutMutationOrSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var saveCount = 0
        let initialService = CatalogProductPersistenceService(
            clock: { self.fixedDate },
            saveContext: {
                saveCount += 1
                try $0.save()
            }
        )
        let initialRequest = makeRequest(imageData: Data([0xaa]))
        let initial = try insertedProduct(
            from: initialService.save(initialRequest, in: context)
        )
        let originalID = initial.id

        let changedRequest = CatalogProductSaveRequest(
            productID: initialRequest.productID,
            displayNameSnapshot: "Renamed Catalog Value",
            displayLocaleSnapshot: "en",
            categoryIDSnapshot: ProductCategoryID("changed"),
            categoryDisplayNameSnapshot: "Changed Category",
            iconKeySnapshot: "product.changed",
            imageData: Data([0xbb]),
            source: .camera
        )
        let secondService = CatalogProductPersistenceService(
            clock: { self.fixedDate.addingTimeInterval(100) },
            saveContext: {
                saveCount += 1
                try $0.save()
            }
        )

        let outcome = try secondService.save(changedRequest, in: context)
        let existing = try existingProduct(from: outcome)

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(existing.id, originalID)
        XCTAssertEqual(existing.name, initialRequest.displayNameSnapshot)
        XCTAssertEqual(existing.category, initialRequest.categoryDisplayNameSnapshot)
        XCTAssertEqual(existing.imageData, Data([0xaa]))
        XCTAssertEqual(existing.source, .catalog)
        XCTAssertEqual(existing.dateAdded, fixedDate)
        XCTAssertEqual(existing.updatedAt, fixedDate)
        XCTAssertEqual(existing.catalogDisplayNameSnapshot, initialRequest.displayNameSnapshot)
        XCTAssertEqual(existing.catalogDisplayLocaleSnapshot, initialRequest.displayLocaleSnapshot)
        XCTAssertEqual(
            existing.catalogCategoryIDSnapshotRawValue,
            initialRequest.categoryIDSnapshot.rawValue
        )
        XCTAssertEqual(
            existing.catalogCategoryDisplayNameSnapshot,
            initialRequest.categoryDisplayNameSnapshot
        )
        XCTAssertEqual(existing.catalogIconKeySnapshot, initialRequest.iconKeySnapshot)
        XCTAssertEqual(existing.catalogSnapshotUpdatedAt, fixedDate)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 1)
    }

    func testDeduplicationUsesOnlyExactProductID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let manual = Product(name: "חלב", source: .manual)
        context.insert(manual)
        try context.save()
        let service = CatalogProductPersistenceService(clock: { self.fixedDate })

        let first = try insertedProduct(
            from: service.save(makeRequest(productID: "catalog-a"), in: context)
        )
        let second = try insertedProduct(
            from: service.save(makeRequest(productID: "catalog-b"), in: context)
        )

        XCTAssertEqual(first.name, second.name)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.catalogProductID, second.catalogProductID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 3)
        XCTAssertNil(manual.catalogProductIDRawValue)
    }

    func testMultipleExactMatchesFailDeterministicallyWithoutSaving() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        context.insert(
            Product(
                id: firstID,
                name: "First",
                catalogProductIDRawValue: "duplicate"
            )
        )
        context.insert(
            Product(
                id: secondID,
                name: "Second",
                catalogProductIDRawValue: "duplicate"
            )
        )
        try context.save()
        var saveCount = 0
        let service = CatalogProductPersistenceService(
            saveContext: {
                saveCount += 1
                try $0.save()
            }
        )

        XCTAssertThrowsError(
            try service.save(makeRequest(productID: "duplicate"), in: context)
        ) { error in
            guard case CatalogProductPersistenceError.duplicateCatalogIdentity(
                let productID,
                let userProductIDs
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(productID, "duplicate")
            XCTAssertEqual(userProductIDs, [secondID, firstID])
        }
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 2)
    }

    func testSaveFailureRemovesOnlyNewInsertionAndAllowsCleanRetry() throws {
        struct ExpectedFailure: Error {}

        let container = try makeContainer()
        let context = ModelContext(container)
        let unrelated = Product(name: "Unrelated pending product")
        context.insert(unrelated)
        let request = makeRequest(productID: "retry-product")
        var failedSaveCount = 0
        let failingService = CatalogProductPersistenceService(
            clock: { self.fixedDate },
            saveContext: { _ in
                failedSaveCount += 1
                throw ExpectedFailure()
            }
        )

        XCTAssertThrowsError(
            try failingService.save(request, in: context)
        ) { error in
            guard case CatalogProductPersistenceError.saveFailed(
                let productID,
                let underlying
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(productID, "retry-product")
            XCTAssertTrue(underlying is ExpectedFailure)
        }

        XCTAssertEqual(failedSaveCount, 1)
        XCTAssertTrue(
            context.insertedModelsArray.contains {
                ($0 as? Product)?.id == unrelated.id
            }
        )
        XCTAssertFalse(
            context.insertedModelsArray.contains {
                ($0 as? Product)?.catalogProductIDRawValue == "retry-product"
            }
        )

        let retryDate = fixedDate.addingTimeInterval(60)
        var retrySaveCount = 0
        let retryService = CatalogProductPersistenceService(
            clock: { retryDate },
            saveContext: {
                retrySaveCount += 1
                try $0.save()
            }
        )
        let retried = try insertedProduct(
            from: retryService.save(request, in: context)
        )

        XCTAssertEqual(retrySaveCount, 1)
        XCTAssertEqual(retried.catalogSnapshotUpdatedAt, retryDate)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Product>())
                .filter { $0.catalogProductIDRawValue == "retry-product" }
                .count,
            1
        )
    }

    func testInvalidRequestsAndUnsupportedSourcesDoNotInsertOrSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var saveCount = 0
        let service = CatalogProductPersistenceService(
            saveContext: {
                saveCount += 1
                try $0.save()
            }
        )
        let invalid = makeRequest(productID: " invalid ")
        let unsupported = CatalogProductSaveRequest(
            productID: ProductID("valid"),
            displayNameSnapshot: "Name",
            displayLocaleSnapshot: "en",
            categoryIDSnapshot: ProductCategoryID("category"),
            categoryDisplayNameSnapshot: "Category",
            iconKeySnapshot: "product.category",
            imageData: nil,
            source: .manual
        )

        XCTAssertThrowsError(try service.save(invalid, in: context)) { error in
            guard case CatalogProductPersistenceError.invalidField(.productID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try service.save(unsupported, in: context)) { error in
            guard case CatalogProductPersistenceError.unsupportedSource(.manual) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try WayTaskModelContainer.make(configurations: [configuration])
    }

    private func makeRequest(
        productID: String = "prd_pilot_0001",
        imageData: Data? = nil
    ) -> CatalogProductSaveRequest {
        CatalogProductSaveRequest(
            productID: ProductID(productID),
            displayNameSnapshot: "חלב",
            displayLocaleSnapshot: "he",
            categoryIDSnapshot: ProductCategoryID("dairy"),
            categoryDisplayNameSnapshot: "מוצרי חלב",
            iconKeySnapshot: "product.dairy",
            imageData: imageData,
            source: .catalog
        )
    }

    private func insertedProduct(
        from outcome: CatalogProductSaveOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Product {
        guard case .inserted(let product) = outcome else {
            XCTFail("Expected inserted outcome", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return product
    }

    private func existingProduct(
        from outcome: CatalogProductSaveOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Product {
        guard case .alreadyPresent(let product) = outcome else {
            XCTFail("Expected alreadyPresent outcome", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return product
    }
}

private struct UnexpectedOutcome: Error {}
