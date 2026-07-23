import XCTest
@testable import WayTask

final class ProductKnowledgeCatalogValidatorTests: XCTestCase {
    private let validator = ProductKnowledgeCatalogValidator()

    func testValidCatalogAndRawShapePass() throws {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        let data = try ProductKnowledgeFixtureFactory.makeData(from: catalog)

        XCTAssertNoThrow(try validator.validateRawShape(data))
        XCTAssertNoThrow(try validator.validate(catalog, resourceByteCount: data.count))
    }

    func testUnknownTopLevelAndRecordFieldsAreRejected() throws {
        let data = try ProductKnowledgeFixtureFactory.makeData()
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root["futureField"] = true
        var products = try XCTUnwrap(root["products"] as? [[String: Any]])
        products[0]["brand"] = "Out of scope"
        root["products"] = products
        let invalidData = try JSONSerialization.data(withJSONObject: root)

        assertValidationCode(.unexpectedField) {
            try validator.validateRawShape(invalidData)
        }
    }

    func testMissingRequiredRawFieldIsRejected() throws {
        let data = try ProductKnowledgeFixtureFactory.makeData()
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root.removeValue(forKey: "names")
        let invalidData = try JSONSerialization.data(withJSONObject: root)

        assertValidationCode(.missingField) {
            try validator.validateRawShape(invalidData)
        }
    }

    func testMalformedRecordShapeIsRejected() throws {
        let data = try ProductKnowledgeFixtureFactory.makeData()
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        root["products"] = ["not-a-product-record"]
        let invalidData = try JSONSerialization.data(withJSONObject: root)

        assertValidationCode(.invalidRecordShape) {
            try validator.validateRawShape(invalidData)
        }
    }

    func testEnvelopeRevisionCountLocalesAndSizeAreValidated() {
        assertValidationCode(.invalidCatalogRevision) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(catalogRevision: 0)
            )
        }
        assertValidationCode(.productCountMismatch) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(expectedProductCount: 14)
            )
        }
        assertValidationCode(.unsupportedLocales) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(
                    supportedLocales: ["he", "en"]
                )
            )
        }
        assertValidationCode(.invalidResourceSize) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(),
                resourceByteCount: ProductKnowledgeCatalogValidator.maximumRevisionOneByteCount + 1
            )
        }
    }

    func testUnsupportedSchemaReturnsExactTypedVersionError() {
        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(schemaVersion: 2)
            )
        ) { error in
            XCTAssertEqual(error as? ProductKnowledgeError, .unsupportedSchemaVersion(2))
        }
    }

    func testUnsupportedTaxonomyReturnsExactTypedVersionError() {
        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(taxonomyVersion: "2.0")
            )
        ) { error in
            XCTAssertEqual(error as? ProductKnowledgeError, .unsupportedTaxonomyVersion("2.0"))
        }
    }

    func testInvalidProductCountProducesFocusedViolation() {
        assertValidationCode(.productCountMismatch) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(expectedProductCount: 14)
            )
        }
    }

    func testCategoryCountIdentityAndSortOrderAreValidated() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()

        assertValidationCode(.invalidCategoryCount) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(
                    categories: Array(catalog.categories.dropLast())
                )
            )
        }

        var duplicateCategories = catalog.categories
        duplicateCategories[1] = ProductKnowledgeCategoryRecord(
            id: duplicateCategories[0].id,
            names: duplicateCategories[1].names,
            iconKey: duplicateCategories[1].iconKey,
            sortOrder: duplicateCategories[1].sortOrder,
            status: duplicateCategories[1].status
        )
        assertValidationCode(.duplicateCategoryID) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: duplicateCategories)
            )
        }

        var invalidIDCategories = catalog.categories
        invalidIDCategories[0] = ProductKnowledgeCategoryRecord(
            id: "Dairy!",
            names: invalidIDCategories[0].names,
            iconKey: invalidIDCategories[0].iconKey,
            sortOrder: invalidIDCategories[0].sortOrder,
            status: invalidIDCategories[0].status
        )
        assertValidationCode(.invalidCategoryID) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: invalidIDCategories)
            )
        }

        var duplicateSortCategories = catalog.categories
        let first = duplicateSortCategories[0]
        let second = duplicateSortCategories[1]
        duplicateSortCategories[1] = ProductKnowledgeCategoryRecord(
            id: second.id,
            names: second.names,
            iconKey: second.iconKey,
            sortOrder: first.sortOrder,
            status: second.status
        )
        assertValidationCode(.duplicateCategorySortOrder) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: duplicateSortCategories)
            )
        }
    }

    func testCategoryNamesIconsAndStatusMustMatchTaxonomy() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let category = categories[0]
        categories[0] = ProductKnowledgeCategoryRecord(
            id: category.id,
            names: ProductKnowledgeCategoryNamesRecord(en: "Changed", he: category.names.he),
            iconKey: "product.changed",
            sortOrder: category.sortOrder,
            status: .inactive
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.categoryNameMismatch))
            XCTAssertTrue(codes.contains(.categoryIconMismatch))
            XCTAssertTrue(codes.contains(.invalidCategoryStatus))
        }
    }

    func testCategorySortOrderMismatchProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let category = categories[0]
        categories[0] = ProductKnowledgeCategoryRecord(
            id: category.id,
            names: category.names,
            iconKey: category.iconKey,
            sortOrder: 99,
            status: category.status
        )

        assertValidationCode(.categorySortOrderMismatch) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        }
    }

    func testTaxonomySetMismatchProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let category = categories[14]
        categories[14] = ProductKnowledgeCategoryRecord(
            id: "seasonal",
            names: category.names,
            iconKey: category.iconKey,
            sortOrder: category.sortOrder,
            status: category.status
        )

        assertValidationCode(.taxonomyMismatch) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        }
    }

    func testIncorrectCategoryIconProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let category = categories[0]
        categories[0] = ProductKnowledgeCategoryRecord(
            id: category.id,
            names: category.names,
            iconKey: "product.wrong",
            sortOrder: category.sortOrder,
            status: category.status
        )

        assertValidationCode(.categoryIconMismatch) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        }
    }

    func testInactiveCategoryAndProductProduceFocusedViolations() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let category = categories[0]
        categories[0] = ProductKnowledgeCategoryRecord(
            id: category.id,
            names: category.names,
            iconKey: category.iconKey,
            sortOrder: category.sortOrder,
            status: .inactive
        )
        assertValidationCode(.invalidCategoryStatus) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        }

        var products = catalog.products
        let product = products[0]
        products[0] = ProductKnowledgeProductRecord(
            id: product.id,
            defaultNameID: product.defaultNameID,
            primaryCategoryID: product.primaryCategoryID,
            status: .inactive
        )
        assertValidationCode(.invalidProductStatus) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(
                    products: products,
                    names: catalog.names
                )
            )
        }
    }

    func testProductIdentitySetDuplicatesReferencesAndStatusAreValidated() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var products = catalog.products
        let first = products[0]
        products[1] = ProductKnowledgeProductRecord(
            id: first.id,
            defaultNameID: products[1].defaultNameID,
            primaryCategoryID: "missing_category",
            status: .inactive
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(products: products)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.duplicateProductID))
            XCTAssertTrue(codes.contains(.initialProductSetMismatch))
            XCTAssertTrue(codes.contains(.missingCategoryReference))
            XCTAssertTrue(codes.contains(.invalidProductStatus))
        }
    }

    func testInvalidProductIDProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var products = catalog.products
        let product = products[0]
        products[0] = ProductKnowledgeProductRecord(
            id: "prd_not_approved",
            defaultNameID: product.defaultNameID,
            primaryCategoryID: product.primaryCategoryID,
            status: product.status
        )

        assertValidationCode(.invalidProductID) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(
                    products: products,
                    names: catalog.names
                )
            )
        }
    }

    func testDuplicateProductIDProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var products = catalog.products
        let first = products[0]
        let second = products[1]
        products[1] = ProductKnowledgeProductRecord(
            id: first.id,
            defaultNameID: second.defaultNameID,
            primaryCategoryID: second.primaryCategoryID,
            status: second.status
        )

        assertValidationCode(.duplicateProductID) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(
                    products: products,
                    names: catalog.names
                )
            )
        }
    }

    func testProductCategoryReferenceUsesCategoriesPresentInArtifact() throws {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var categories = catalog.categories
        let dairyIndex = try XCTUnwrap(categories.firstIndex { $0.id == "dairy" })
        let dairy = categories[dairyIndex]
        categories[dairyIndex] = ProductKnowledgeCategoryRecord(
            id: "seasonal",
            names: dairy.names,
            iconKey: dairy.iconKey,
            sortOrder: dairy.sortOrder,
            status: dairy.status
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(categories: categories)
            )
        ) { error in
            let violations = validationViolations(from: error)
            XCTAssertTrue(violations.contains { violation in
                violation.code == .missingCategoryReference
                    && violation.path == "$.products[0].primaryCategoryID"
                    && violation.recordID == "prd_pilot_0001"
            })
        }
    }

    func testDefaultNameMustBePreferredEnglishCanonicalOwnedByProduct() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var products = catalog.products
        let product = products[0]
        products[0] = ProductKnowledgeProductRecord(
            id: product.id,
            defaultNameID: "name_prd_pilot_0002_en",
            primaryCategoryID: product.primaryCategoryID,
            status: product.status
        )

        assertValidationCode(.invalidDefaultNameReference) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(products: products)
            )
        }
    }

    func testNameIDsAndProductReferencesAreValidated() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        let first = names[0]
        let second = names[1]
        names[1] = ProductKnowledgeNameRecord(
            id: first.id,
            productID: "prd_missing",
            locale: second.locale,
            kind: second.kind,
            value: second.value,
            isPreferred: second.isPreferred
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.duplicateNameID))
            XCTAssertTrue(codes.contains(.missingProductReference))
        }
    }

    func testNameValueWhitespaceControlCharactersAndLocaleAreValidated() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        let name = names[0]
        names[0] = ProductKnowledgeNameRecord(
            id: name.id,
            productID: name.productID,
            locale: "fr",
            kind: name.kind,
            value: " English\u{0007} ",
            isPreferred: name.isPreferred
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.invalidNameWhitespace))
            XCTAssertTrue(codes.contains(.disallowedControlCharacter))
            XCTAssertTrue(codes.contains(.unsupportedNameLocale))
        }

        names[0] = ProductKnowledgeNameRecord(
            id: name.id,
            productID: name.productID,
            locale: name.locale,
            kind: name.kind,
            value: " ",
            isPreferred: name.isPreferred
        )
        assertValidationCode(.emptyNameValue) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        }
    }

    func testEmptyAliasProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        names.append(
            ProductKnowledgeNameRecord(
                id: "empty_alias",
                productID: "prd_pilot_0001",
                locale: "en",
                kind: .alias,
                value: "",
                isPreferred: false
            )
        )

        assertValidationCode(.emptyNameValue) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        }
    }

    func testMissingRequiredLocalizationProducesFocusedViolation() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        let names = catalog.names.filter {
            !($0.productID == "prd_pilot_0001" && $0.locale == "he")
        }

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        ) { error in
            XCTAssertTrue(validationViolations(from: error).contains {
                $0.code == .missingPreferredName
                    && $0.recordID == "prd_pilot_0001:he"
            })
        }
    }

    func testPreferredAliasMissingPreferredAndDuplicatePreferredAreValidated() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        let english = names[0]
        names[0] = ProductKnowledgeNameRecord(
            id: english.id,
            productID: english.productID,
            locale: english.locale,
            kind: english.kind,
            value: english.value,
            isPreferred: false
        )
        names.append(
            ProductKnowledgeNameRecord(
                id: "alias_preferred",
                productID: "prd_pilot_0002",
                locale: "en",
                kind: .alias,
                value: "Alternate",
                isPreferred: true
            )
        )
        names.append(
            ProductKnowledgeNameRecord(
                id: "duplicate_preferred",
                productID: "prd_pilot_0003",
                locale: "en",
                kind: .localizedDisplay,
                value: "Second preferred",
                isPreferred: true
            )
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.preferredAlias))
            XCTAssertTrue(codes.contains(.missingPreferredName))
            XCTAssertTrue(codes.contains(.duplicatePreferredName))
        }
    }

    func testAliasCollisionWithCanonicalDisplayAndDuplicateNameRecordsAreRejected() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        let canonical = names[0]
        names.append(
            ProductKnowledgeNameRecord(
                id: "alias_repeat",
                productID: canonical.productID,
                locale: canonical.locale,
                kind: .alias,
                value: canonical.value,
                isPreferred: false
            )
        )
        names.append(
            ProductKnowledgeNameRecord(
                id: "duplicate_tuple",
                productID: canonical.productID,
                locale: canonical.locale,
                kind: canonical.kind,
                value: canonical.value,
                isPreferred: false
            )
        )

        XCTAssertThrowsError(
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        ) { error in
            let codes = ProductKnowledgeFixtureFactory.validationCodes(from: error)
            XCTAssertTrue(codes.contains(.aliasDisplayNameCollision))
            XCTAssertTrue(codes.contains(.duplicateNameRecord))
        }
    }

    func testAliasCollisionWithLocalizedDisplayNameIsRejected() throws {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        let localizedDisplay = try XCTUnwrap(
            catalog.names.first {
                $0.productID == "prd_pilot_0001"
                    && $0.locale == "he"
                    && $0.kind == .localizedDisplay
            }
        )
        var names = catalog.names
        names.append(
            ProductKnowledgeNameRecord(
                id: "localized_display_collision",
                productID: localizedDisplay.productID,
                locale: localizedDisplay.locale,
                kind: .alias,
                value: localizedDisplay.value,
                isPreferred: false
            )
        )

        assertValidationCode(.aliasDisplayNameCollision) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        }
    }

    func testDuplicateNormalizedAliasIsRejected() {
        let catalog = ProductKnowledgeFixtureFactory.makeCatalog()
        var names = catalog.names
        names.append(
            ProductKnowledgeNameRecord(
                id: "alias_case_one",
                productID: "prd_pilot_0001",
                locale: "en",
                kind: .alias,
                value: "Dairy Milk",
                isPreferred: false
            )
        )
        names.append(
            ProductKnowledgeNameRecord(
                id: "alias_case_two",
                productID: "prd_pilot_0001",
                locale: "en",
                kind: .alias,
                value: "dairy milk",
                isPreferred: false
            )
        )

        assertValidationCode(.duplicateNormalizedAlias) {
            try validator.validate(
                ProductKnowledgeFixtureFactory.makeCatalog(names: names)
            )
        }
    }

    private func assertValidationCode(
        _ code: ProductKnowledgeValidationCode,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertTrue(
                ProductKnowledgeFixtureFactory.validationCodes(from: error).contains(code),
                "Expected \(code.rawValue), received \(error)"
            )
        }
    }

    private func validationViolations(
        from error: Error
    ) -> [ProductKnowledgeValidationViolation] {
        guard case ProductKnowledgeError.validationFailed(let violations) = error else {
            return []
        }
        return violations
    }
}
