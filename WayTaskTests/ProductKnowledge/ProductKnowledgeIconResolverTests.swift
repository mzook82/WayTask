import XCTest
@testable import WayTask

final class ProductKnowledgeIconResolverTests: XCTestCase {
    func testEveryApprovedSemanticIconKeyResolves() {
        let keys = [
            "product.dairy",
            "product.bread",
            "product.fruit",
            "product.meat",
            "product.pantry",
            "product.drink",
            "product.frozen",
            "product.snack",
            "product.household",
            "product.cleaning",
            "product.personalcare",
            "product.pharmacy",
            "product.baby",
            "product.pet",
            "product.generic"
        ]

        for key in keys {
            XCTAssertFalse(
                ProductKnowledgeIconResolver.systemName(for: key).isEmpty,
                "Missing icon mapping for \(key)"
            )
        }
    }

    func testUnknownSemanticIconUsesGenericFallback() {
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: "product.future"),
            ProductKnowledgeIconResolver.fallbackSystemName
        )
    }
}
