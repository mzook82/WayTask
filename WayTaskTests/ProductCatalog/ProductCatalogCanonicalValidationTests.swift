import Foundation
import XCTest
@testable import WayTask

final class ProductCatalogCanonicalValidationTests: XCTestCase {
    func testSharedTaxonomyLoadsAllApprovedCategoriesAndLegacyMappings()
        throws {
        let taxonomy = try ProductCatalogTaxonomyLoader(
            bundle: Bundle(for: SharedCatalogFixtureBundleToken.self)
        ).load()

        XCTAssertEqual(taxonomy.taxonomyVersion, 1)
        XCTAssertEqual(taxonomy.locale, "he-IL")
        XCTAssertEqual(taxonomy.categories.count, 23)
        XCTAssertEqual(taxonomy.compatibilityMappings.count, 24)
        XCTAssertEqual(
            taxonomy.compatibilityMapping(
                legacyCategoryId: "spices"
            )?.canonicalCategoryId,
            "pantry"
        )
        XCTAssertEqual(
            taxonomy.compatibilityMapping(
                legacyCategoryId: "spices"
            )?.canonicalSubcategoryId,
            "pantry.spices"
        )
        XCTAssertEqual(
            taxonomy.compatibilityMapping(
                legacyCategoryId: "paper_products"
            )?.migrationMode,
            .productReviewRequired
        )
    }

    func testUnknownCanonicalCategoryIsRejected() throws {
        let product = makeProduct(categoryId: "missing_category")

        assertCatalogError(
            products: [product],
            matches: {
                guard case ProductCatalogError.invalidCategoryReference(
                    productID: "product_a",
                    categoryID: "missing_category",
                    sourceFormat: "canonical_v1"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testUnknownCanonicalSubcategoryIsRejected() throws {
        let product = makeProduct(
            categoryId: "pantry",
            subcategoryId: "pantry.missing"
        )

        assertCatalogError(
            products: [product],
            matches: {
                guard case ProductCatalogError.invalidSubcategoryReference(
                    productID: "product_a",
                    subcategoryID: "pantry.missing"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testSubcategoryParentMismatchIsRejected() throws {
        let product = makeProduct(
            categoryId: "household",
            subcategoryId: "pantry.spices"
        )

        assertCatalogError(
            products: [product],
            matches: {
                guard case ProductCatalogError.subcategoryParentMismatch(
                    productID: "product_a",
                    categoryID: "household",
                    subcategoryID: "pantry.spices",
                    expectedParentID: "pantry"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testDuplicateNormalizedCanonicalNamesAreRejected() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "לחם---מלא"
        )
        let second = makeProduct(
            id: "second",
            canonicalName: " לחם מלא "
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.duplicateCanonicalName(
                    normalizedName: "לחמ מלא",
                    productIDs: ["first", "second"]
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testDuplicateNormalizedCanonicalNamesIncludeInactiveProducts()
        throws {
        let first = makeProduct(
            id: "duplicate_active",
            canonicalName: "נייר טואלט"
        )
        let second = makeProduct(
            id: "duplicate_inactive",
            canonicalName: "נייר־טואלט",
            isActive: false
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.duplicateCanonicalName(
                    normalizedName: "נייר טואלט",
                    productIDs: [
                        "duplicate_active",
                        "duplicate_inactive"
                    ]
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testAliasMatchingAnotherCanonicalNameIsRejected() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "מוצר ראשון",
            aliases: ["מוצר שני"]
        )
        let second = makeProduct(
            id: "second",
            canonicalName: "מוצר שני"
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.aliasMatchesCanonicalName(
                    alias: "מוצר שני",
                    aliasProductID: "first",
                    canonicalProductID: "second"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testAliasSharedByActiveProductsIsRejected() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "מוצר ראשון",
            aliases: ["שם משותף"]
        )
        let second = makeProduct(
            id: "second",
            canonicalName: "מוצר שני",
            aliases: ["שם---משותף"]
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.aliasSharedByProducts(
                    normalizedAlias: "שמ משותפ",
                    productIDs: ["first", "second"],
                    aliases: _
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testBrandTermMatchingCanonicalNameIsRejected() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "מוצר ראשון",
            brandTerms: ["מוצר שני"]
        )
        let second = makeProduct(
            id: "second",
            canonicalName: "מוצר שני"
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError
                    .brandTermMatchesCanonicalName(
                        brandTerm: "מוצר שני",
                        brandProductID: "first",
                        canonicalProductID: "second"
                    ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testBrandTermMatchingAliasIsRejected() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "מוצר ראשון",
            brandTerms: ["שם מסחרי"]
        )
        let second = makeProduct(
            id: "second",
            canonicalName: "מוצר שני",
            aliases: ["שם---מסחרי"]
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.brandTermMatchesAlias(
                    brandTerm: "שם מסחרי",
                    brandProductID: "first",
                    aliasProductID: "second"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testReplacementTargetMustExist() throws {
        let retired = makeProduct(
            id: "retired",
            canonicalName: "מוצר ישן",
            isActive: false,
            replacementProductId: "missing",
            deprecatedSinceCatalogVersion: 1
        )

        assertCatalogError(
            products: [retired],
            matches: {
                guard case ProductCatalogError.replacementTargetMissing(
                    productID: "retired",
                    replacementProductID: "missing"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testValidInactiveReplacementIsAcceptedAndFiltered() throws {
        let active = makeProduct(
            id: "survivor",
            canonicalName: "מוצר חדש"
        )
        let retired = makeProduct(
            id: "retired",
            canonicalName: "מוצר ישן",
            isActive: false,
            replacementProductId: "survivor",
            deprecatedSinceCatalogVersion: 1
        )
        let data = try canonicalData(
            products: [active, retired],
            catalogVersion: 2
        )

        let products = try service.loadProducts(data: data)

        XCTAssertEqual(products.map(\.id), ["survivor"])
    }

    func testReplacementLoopsAreRejectedActionably() throws {
        let first = makeProduct(
            id: "first",
            canonicalName: "מוצר ראשון",
            isActive: false,
            replacementProductId: "second",
            deprecatedSinceCatalogVersion: 1
        )
        let second = makeProduct(
            id: "second",
            canonicalName: "מוצר שני",
            isActive: false,
            replacementProductId: "first",
            deprecatedSinceCatalogVersion: 1
        )

        assertCatalogError(
            products: [first, second],
            matches: {
                guard case ProductCatalogError.replacementLoop(
                    productIDs: let ids
                ) = $0 else {
                    return false
                }
                return ids == ["first", "second", "first"]
            }
        )
    }

    func testInvalidStableProductIDIsRejected() throws {
        let product = makeProduct(id: "Invalid-ID")

        assertCatalogError(
            products: [product],
            matches: {
                guard case ProductCatalogError.invalidProductID(
                    "Invalid-ID"
                ) = $0 else {
                    return false
                }
                return true
            }
        )
    }

    private var service: ProductCatalogService {
        ProductCatalogService(
            bundle: Bundle(for: SharedCatalogFixtureBundleToken.self)
        )
    }

    private func assertCatalogError(
        products: [CatalogProduct],
        catalogVersion: Int = 2,
        matches: (ProductCatalogError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try service.loadProducts(
                data: canonicalData(
                    products: products,
                    catalogVersion: catalogVersion
                )
            ),
            file: file,
            line: line
        ) { error in
            guard let catalogError = error as? ProductCatalogError,
                  matches(catalogError) else {
                return XCTFail(
                    "Unexpected error: \(error)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func canonicalData(
        products: [CatalogProduct],
        catalogVersion: Int = 1
    ) throws -> Data {
        try JSONEncoder().encode(
            ValidationCanonicalDocument(
                schemaVersion: 1,
                catalogVersion: catalogVersion,
                taxonomyVersion: 1,
                locale: "he-IL",
                products: products
            )
        )
    }

    private func makeProduct(
        id: String = "product_a",
        canonicalName: String = "מוצר",
        categoryId: String = "pantry",
        subcategoryId: String? = nil,
        aliases: [String] = [],
        brandTerms: [String] = [],
        popularity: Int = 50,
        isActive: Bool = true,
        replacementProductId: String? = nil,
        deprecatedSinceCatalogVersion: Int? = nil
    ) -> CatalogProduct {
        CatalogProduct(
            id: id,
            canonicalName: canonicalName,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            aliases: aliases,
            keywords: [],
            brandTerms: brandTerms,
            popularityScore: popularity,
            isActive: isActive,
            replacementProductId: replacementProductId,
            deprecatedSinceCatalogVersion:
                deprecatedSinceCatalogVersion
        )
    }
}

private struct ValidationCanonicalDocument: Encodable {
    let schemaVersion: Int
    let catalogVersion: Int
    let taxonomyVersion: Int
    let locale: String
    let products: [CatalogProduct]
}

final class SharedCatalogFixtureBundleToken {}
