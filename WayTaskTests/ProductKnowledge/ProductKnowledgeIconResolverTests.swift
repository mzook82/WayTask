import UIKit
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
            let systemName = ProductKnowledgeIconResolver.systemName(for: key)
            XCTAssertFalse(
                systemName.isEmpty,
                "Missing icon mapping for \(key)"
            )
            XCTAssertNotNil(
                UIImage(systemName: systemName),
                "Invalid system icon \(systemName) for \(key)"
            )
            XCTAssertNotEqual(
                systemName,
                ProductKnowledgeIconResolver.fallbackSystemName,
                "Resolved catalog icon \(key) must not use the unresolved fallback"
            )
        }
    }

    func testDeviceQACorrectionsAvoidCakeAndPersonIcons() {
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: "product.bread"),
            "basket.fill"
        )
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(
                for: "product.personalcare"
            ),
            "comb.fill"
        )
        XCTAssertNotEqual(
            ProductKnowledgeIconResolver.systemName(for: "product.bread"),
            "birthday.cake.fill"
        )
        XCTAssertNotEqual(
            ProductKnowledgeIconResolver.systemName(
                for: "product.personalcare"
            ),
            "figure.stand"
        )
    }

    func testCatalogSnapshotUsesSemanticIconThenGenericFallback() {
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(
                forCatalogSnapshot: "product.bread"
            ),
            "basket.fill"
        )
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(
                forCatalogSnapshot: nil
            ),
            ProductKnowledgeIconResolver.fallbackSystemName
        )
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(
                forCatalogSnapshot: "product.future"
            ),
            ProductKnowledgeIconResolver.fallbackSystemName
        )
    }

    @MainActor
    func testChooseProductsThumbnailPreservesPhotoThenCatalogThenGenericFallback() {
        let photoData = Data([0x01, 0x02, 0x03])
        let catalogWithPhoto = Product(
            name: "Bread",
            imageData: photoData,
            catalogProductIDRawValue: "bread_white",
            catalogIconKeySnapshot: "product.bread"
        )
        let catalogWithoutPhoto = Product(
            name: "Bread",
            catalogProductIDRawValue: "bread_white",
            catalogIconKeySnapshot: "product.bread"
        )
        let manualWithoutPhoto = Product(name: "Custom item")

        let photoPresentation = ProductShoppingThumbnailPresentation(
            product: catalogWithPhoto
        )
        XCTAssertEqual(photoPresentation.imageData, photoData)
        XCTAssertEqual(photoPresentation.fallbackSystemName, "basket.fill")

        let catalogPresentation = ProductShoppingThumbnailPresentation(
            product: catalogWithoutPhoto
        )
        XCTAssertNil(catalogPresentation.imageData)
        XCTAssertEqual(catalogPresentation.fallbackSystemName, "basket.fill")

        let manualPresentation = ProductShoppingThumbnailPresentation(
            product: manualWithoutPhoto
        )
        XCTAssertNil(manualPresentation.imageData)
        XCTAssertEqual(
            manualPresentation.fallbackSystemName,
            ProductKnowledgeIconResolver.fallbackSystemName
        )
    }

    func testUnknownSemanticIconUsesGenericFallback() {
        XCTAssertEqual(
            ProductKnowledgeIconResolver.systemName(for: "product.future"),
            ProductKnowledgeIconResolver.fallbackSystemName
        )
    }
}
