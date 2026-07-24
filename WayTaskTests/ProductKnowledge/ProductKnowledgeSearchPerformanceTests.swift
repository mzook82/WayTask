import Foundation
import XCTest
@testable import WayTask

final class ProductKnowledgeSearchPerformanceTests: XCTestCase {
    func testColdSearchPerformanceWith15Products() {
        measureColdSearch(productCount: 15)
    }

    func testWarmSearchPerformanceWith15Products() {
        measureWarmSearch(productCount: 15)
    }

    func testColdSearchPerformanceWith100Products() {
        measureColdSearch(productCount: 100)
    }

    func testWarmSearchPerformanceWith100Products() {
        measureWarmSearch(productCount: 100)
    }

    func testColdSearchPerformanceWith500Products() {
        measureColdSearch(productCount: 500)
    }

    func testWarmSearchPerformanceWith500Products() {
        measureWarmSearch(productCount: 500)
    }

    private func measureColdSearch(productCount: Int) {
        let snapshot = ProductSearchPerformanceFixtureFactory.makeSnapshot(
            productCount: productCount
        )
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            waitForAsyncOperation {
                let repository = InMemoryProductKnowledgeRepository(
                    snapshot: snapshot
                )
                let search = ProductKnowledgeSearch(repository: repository)
                _ = await search.suggestions(
                    matching: "product 0",
                    locale: "en"
                )
            }
        }
    }

    private func measureWarmSearch(productCount: Int) {
        let snapshot = ProductSearchPerformanceFixtureFactory.makeSnapshot(
            productCount: productCount
        )
        let repository = InMemoryProductKnowledgeRepository(snapshot: snapshot)
        let search = ProductKnowledgeSearch(repository: repository)
        waitForAsyncOperation {
            _ = await search.suggestions(matching: "warmup", locale: "en")
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            waitForAsyncOperation {
                _ = await search.suggestions(
                    matching: "product 0",
                    locale: "en"
                )
            }
        }
    }

    private func waitForAsyncOperation(
        _ operation: @escaping @Sendable () async -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .high) {
            await operation()
            semaphore.signal()
        }

        XCTAssertEqual(
            semaphore.wait(timeout: .now() + 5),
            .success,
            "Timed out waiting for measured search",
            file: file,
            line: line
        )
    }
}

nonisolated private enum ProductSearchPerformanceFixtureFactory {
    static func makeSnapshot(productCount: Int) -> ProductKnowledgeSnapshot {
        let category = ProductCategory(
            id: ProductCategoryID("performance"),
            names: ProductCategoryNames(
                en: "Performance",
                he: "ביצועים"
            ),
            iconKey: "product.performance",
            sortOrder: 0,
            status: .active
        )
        var products: [ProductEntity] = []
        var names: [ProductName] = []

        for index in 0..<productCount {
            let number = String(format: "%04d", index)
            let productID = ProductID("performance_\(number)")
            let englishNameID = ProductNameID("name_\(number)_en")

            products.append(
                ProductEntity(
                    id: productID,
                    defaultNameID: englishNameID,
                    primaryCategoryID: category.id,
                    status: .active
                )
            )
            names.append(
                ProductName(
                    id: englishNameID,
                    productID: productID,
                    locale: "en",
                    kind: .canonical,
                    value: "Product \(number)",
                    isPreferred: true
                )
            )
            names.append(
                ProductName(
                    id: ProductNameID("name_\(number)_he"),
                    productID: productID,
                    locale: "he",
                    kind: .localizedDisplay,
                    value: "מוצר \(number)",
                    isPreferred: true
                )
            )
            names.append(
                ProductName(
                    id: ProductNameID("name_\(number)_alias_catalog"),
                    productID: productID,
                    locale: "en",
                    kind: .alias,
                    value: "Catalog Item \(number)",
                    isPreferred: false
                )
            )
            names.append(
                ProductName(
                    id: ProductNameID("name_\(number)_alias_searchable"),
                    productID: productID,
                    locale: "en",
                    kind: .alias,
                    value: "Searchable \(number)",
                    isPreferred: false
                )
            )
        }

        return ProductKnowledgeSnapshot(
            metadata: ProductKnowledgeSnapshotMetadata(
                schemaVersion: 1,
                catalogRevision: 1,
                taxonomyVersion: "1.0",
                expectedProductCount: productCount,
                supportedLocales: ["en", "he"]
            ),
            categories: [category],
            products: products,
            names: names
        )
    }
}
