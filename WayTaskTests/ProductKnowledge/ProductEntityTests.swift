import XCTest
@testable import WayTask

final class ProductEntityTests: XCTestCase {
    func testProductEntityStoresOnlyApprovedConceptFields() {
        let entity = ProductEntity(
            id: ProductID("prd_pilot_0001"),
            defaultNameID: ProductNameID("name_prd_pilot_0001_en"),
            primaryCategoryID: ProductCategoryID("dairy"),
            status: .active
        )

        XCTAssertEqual(entity.id.rawValue, "prd_pilot_0001")
        XCTAssertEqual(entity.defaultNameID.rawValue, "name_prd_pilot_0001_en")
        XCTAssertEqual(entity.primaryCategoryID.rawValue, "dairy")
        XCTAssertEqual(entity.status, .active)
    }

    func testOpaqueProductIdentifiersUseStableValueEqualityAndHashing() {
        let first = ProductID("prd_pilot_0001")
        let same = ProductID("prd_pilot_0001")
        let different = ProductID("prd_pilot_0002")

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(Set([first, same, different]).count, 2)
    }

    func testDomainValuesRoundTripThroughCodable() throws {
        let original = ProductEntity(
            id: ProductID("prd_pilot_0001"),
            defaultNameID: ProductNameID("name_prd_pilot_0001_en"),
            primaryCategoryID: ProductCategoryID("dairy"),
            status: .active
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProductEntity.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLocalizedNameAndCategoryRoundTripWithoutUnicodeLoss() throws {
        let name = ProductName(
            id: ProductNameID("name_prd_pilot_0001_he"),
            productID: ProductID("prd_pilot_0001"),
            locale: "he",
            kind: .localizedDisplay,
            value: "חלב",
            isPreferred: true
        )
        let category = ProductCategory(
            id: ProductCategoryID("dairy"),
            names: ProductCategoryNames(
                en: "Dairy & Alternatives",
                he: "מוצרי חלב ותחליפים"
            ),
            iconKey: "product.dairy",
            sortOrder: 0,
            status: .active
        )

        let decodedName = try JSONDecoder().decode(
            ProductName.self,
            from: JSONEncoder().encode(name)
        )
        let decodedCategory = try JSONDecoder().decode(
            ProductCategory.self,
            from: JSONEncoder().encode(category)
        )

        XCTAssertEqual(decodedName, name)
        XCTAssertEqual(decodedCategory, category)
    }
}
