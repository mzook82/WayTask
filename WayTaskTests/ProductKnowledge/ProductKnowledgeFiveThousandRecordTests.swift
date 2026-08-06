import Foundation
import XCTest
@testable import WayTask

final class ProductKnowledgeFiveThousandRecordTests: XCTestCase {
    /// Broad regression budgets intentionally leave headroom for shared CI and
    /// simulator variance. The measured values are printed for release evidence.
    func testFiveThousandRecordDecodeIndexAndSearchBudgets() async throws {
        let encoded = try ProductKnowledgeScalabilityFixture.makeEncodedCatalog()
        let clock = ContinuousClock()

        let decodeStarted = clock.now
        let decoded = try JSONDecoder().decode(
            ProductKnowledgeCatalog.self,
            from: encoded
        )
        let snapshot = decoded.makeSnapshot()
        let decodeDuration = decodeStarted.duration(to: clock.now)

        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(snapshot: snapshot)
        )
        let indexStarted = clock.now
        await search.prepare()
        let indexDuration = indexStarted.duration(to: clock.now)
        let statistics = await search.indexStatistics()

        let queryStarted = clock.now
        var queryDurations: [Duration] = []
        for index in 0..<100 {
            let number = String(format: "%04d", index * 37 % 5_000)
            let started = clock.now
            _ = await search.suggestions(
                matching: "Scalable Product \(number)",
                locale: "en"
            )
            queryDurations.append(started.duration(to: clock.now))
        }
        let queryBatchDuration = queryStarted.duration(to: clock.now)

        let exact = await search.suggestions(
            matching: "Scalable Product 0420",
            locale: "en"
        )
        let prefix = await search.suggestions(
            matching: "Scalable Product 04",
            locale: "en"
        )
        let alias = await search.suggestions(
            matching: "Fixture Alias 0420",
            locale: "en"
        )
        let missing = await search.suggestions(
            matching: "not present anywhere",
            locale: "en"
        )

        XCTAssertEqual(decoded.products.count, 5_000)
        XCTAssertEqual(decoded.names.count, 20_000)
        XCTAssertEqual(statistics.productCount, 5_000)
        XCTAssertEqual(statistics.searchableNameCount, 20_000)
        XCTAssertEqual(exact.first?.productID, ProductID("fixture_product_0420"))
        XCTAssertEqual(exact.first?.matchTier, .exactCanonical)
        XCTAssertEqual(prefix.first?.productID, ProductID("fixture_product_0400"))
        XCTAssertEqual(alias.first?.productID, ProductID("fixture_product_0420"))
        XCTAssertEqual(alias.first?.matchTier, .exactAlias)
        XCTAssertTrue(missing.isEmpty)
        XCTAssertLessThan(decodeDuration, .seconds(3))
        XCTAssertLessThan(indexDuration, .seconds(5))
        XCTAssertLessThan(queryBatchDuration, .seconds(3))
        XCTAssertLessThan(
            statistics.estimatedIndexedUTF8Bytes,
            100 * 1024 * 1024
        )

        let metrics = "WT031A_METRICS " + [
            "encodedBytes=\(encoded.count)",
            "decodeMs=\(milliseconds(decodeDuration))",
            "indexMs=\(milliseconds(indexDuration))",
            "query100Ms=\(milliseconds(queryBatchDuration))",
            "maxQueryMs=\(queryDurations.map(milliseconds).max() ?? 0)",
            "indexedUTF8LowerBound=\(statistics.estimatedIndexedUTF8Bytes)",
            "prefixKeys=\(statistics.prefixKeyCount)",
            "tokenPrefixKeys=\(statistics.tokenPrefixKeyCount)",
            "trigramKeys=\(statistics.trigramKeyCount)"
        ].joined(separator: " ")
        print(metrics)
        XCTContext.runActivity(named: metrics) { _ in }
    }

    func testRapidConsecutiveQueriesRemainStableAndDeduplicated() async {
        let snapshot = ProductKnowledgeScalabilityFixture.makeCatalog()
            .makeSnapshot()
        let search = ProductKnowledgeSearch(
            repository: InMemoryProductKnowledgeRepository(snapshot: snapshot)
        )

        let resultSets = await withTaskGroup(
            of: [ProductSearchResult].self,
            returning: [[ProductSearchResult]].self
        ) { group in
            for index in 0..<64 {
                group.addTask {
                    let number = String(format: "%04d", index)
                    return await search.suggestions(
                        matching: "Search Token \(number)",
                        locale: "en"
                    )
                }
            }
            var values: [[ProductSearchResult]] = []
            for await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(resultSets.count, 64)
        XCTAssertTrue(resultSets.allSatisfy { results in
            results.count == Set(results.map(\.productID)).count
                && results.first?.matchTier == .exactAlias
        })
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
