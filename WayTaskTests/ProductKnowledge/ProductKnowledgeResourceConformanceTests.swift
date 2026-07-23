import XCTest
@testable import WayTask

final class ProductKnowledgeResourceConformanceTests: XCTestCase {
    func testShippedResourceMatchesApprovedCatalogExactly() throws {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        let expectedConcepts = Self.expectedConcepts

        XCTAssertEqual(snapshot.metadata.schemaVersion, 1)
        XCTAssertEqual(snapshot.metadata.catalogRevision, 1)
        XCTAssertEqual(snapshot.metadata.taxonomyVersion, "1.0")
        XCTAssertEqual(snapshot.metadata.expectedProductCount, 15)
        XCTAssertEqual(snapshot.metadata.supportedLocales, ["en", "he"])
        XCTAssertEqual(snapshot.categories.count, 15)
        XCTAssertEqual(snapshot.products.count, 15)
        XCTAssertEqual(snapshot.names.count, 57)

        XCTAssertEqual(
            snapshot.products.map(\.id.rawValue),
            expectedConcepts.map(\.id)
        )

        let namesByProduct = Dictionary(grouping: snapshot.names, by: \.productID.rawValue)
        for expected in expectedConcepts {
            let product = try XCTUnwrap(
                snapshot.products.first { $0.id.rawValue == expected.id }
            )
            XCTAssertEqual(product.primaryCategoryID.rawValue, expected.categoryID)
            XCTAssertEqual(product.status, .active)

            let names = namesByProduct[expected.id] ?? []
            let english = names.first {
                $0.locale == "en" && $0.kind == .canonical && $0.isPreferred
            }
            let hebrew = names.first {
                $0.locale == "he" && $0.kind == .localizedDisplay && $0.isPreferred
            }
            XCTAssertEqual(english?.value, expected.en)
            XCTAssertEqual(hebrew?.value, expected.he)
            XCTAssertEqual(product.defaultNameID, english?.id)

            let aliases = Set(
                names
                    .filter { $0.kind == .alias && !$0.isPreferred }
                    .map { "\($0.locale):\($0.value)" }
            )
            XCTAssertEqual(aliases, expected.aliases)
        }
    }

    func testShippedTaxonomyMatchesApprovedNamesIconsAndSortOrder() throws {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        let categoriesByID = Dictionary(
            uniqueKeysWithValues: snapshot.categories.map { ($0.id.rawValue, $0) }
        )
        let expectedCategories = Self.expectedCategories

        XCTAssertEqual(
            Set(categoriesByID.keys),
            Set(expectedCategories.map(\.id))
        )
        for expected in expectedCategories {
            let category = try XCTUnwrap(categoriesByID[expected.id])
            XCTAssertEqual(category.names.en, expected.en)
            XCTAssertEqual(category.names.he, expected.he)
            XCTAssertEqual(category.iconKey, expected.iconKey)
            XCTAssertEqual(category.sortOrder, expected.sortOrder)
            XCTAssertEqual(category.status.rawValue, expected.status)
        }
        XCTAssertEqual(categoriesByID["uncategorized"]?.iconKey, "product.generic")
    }

    func testShippedPilotHasApprovedCoverageAndNoUncategorizedAssignment() throws {
        let snapshot = try BundledProductKnowledgeLoader(bundle: .main).load()
        let representedCategories = Set(
            snapshot.products.map(\.primaryCategoryID.rawValue)
        )

        XCTAssertEqual(representedCategories.count, 11)
        XCTAssertFalse(representedCategories.contains("uncategorized"))
        XCTAssertEqual(
            Set(Self.expectedCategories.map(\.id))
                .subtracting(representedCategories),
            ["meat_fish", "snacks", "pharmacy", "uncategorized"]
        )
    }

    func testShippedResourceIsBundledAndWithinRevisionOneSizeLimit() throws {
        let resourceURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: BundledProductKnowledgeLoader.resourceName,
                withExtension: BundledProductKnowledgeLoader.resourceExtension
            )
        )
        let data = try Data(contentsOf: resourceURL)

        XCTAssertLessThanOrEqual(
            data.count,
            ProductKnowledgeCatalogValidator.maximumRevisionOneByteCount
        )
        XCTAssertNoThrow(try ProductKnowledgeCatalogValidator().validateRawShape(data))
    }
}

private extension ProductKnowledgeResourceConformanceTests {
    struct ExpectedConcept {
        let id: String
        let en: String
        let he: String
        let categoryID: String
        let aliases: Set<String>
    }

    struct ExpectedCategory {
        let id: String
        let en: String
        let he: String
        let iconKey: String
        let sortOrder: Int
        let status: String
    }

    static let expectedCategories: [ExpectedCategory] = [
        ExpectedCategory(
            id: "dairy",
            en: "Dairy & Alternatives",
            he: "מוצרי חלב ותחליפים",
            iconKey: "product.dairy",
            sortOrder: 0,
            status: "active"
        ),
        ExpectedCategory(
            id: "bakery",
            en: "Bakery",
            he: "מאפייה",
            iconKey: "product.bread",
            sortOrder: 1,
            status: "active"
        ),
        ExpectedCategory(
            id: "fruits_vegetables",
            en: "Fruits & Vegetables",
            he: "פירות וירקות",
            iconKey: "product.fruit",
            sortOrder: 2,
            status: "active"
        ),
        ExpectedCategory(
            id: "meat_fish",
            en: "Meat, Fish & Alternatives",
            he: "בשר, דגים ותחליפים",
            iconKey: "product.meat",
            sortOrder: 3,
            status: "active"
        ),
        ExpectedCategory(
            id: "pantry",
            en: "Pantry",
            he: "מזווה",
            iconKey: "product.pantry",
            sortOrder: 4,
            status: "active"
        ),
        ExpectedCategory(
            id: "drinks",
            en: "Drinks",
            he: "משקאות",
            iconKey: "product.drink",
            sortOrder: 5,
            status: "active"
        ),
        ExpectedCategory(
            id: "frozen",
            en: "Frozen",
            he: "קפואים",
            iconKey: "product.frozen",
            sortOrder: 6,
            status: "active"
        ),
        ExpectedCategory(
            id: "snacks",
            en: "Snacks & Sweets",
            he: "חטיפים ומתוקים",
            iconKey: "product.snack",
            sortOrder: 7,
            status: "active"
        ),
        ExpectedCategory(
            id: "household",
            en: "Household",
            he: "מוצרי בית",
            iconKey: "product.household",
            sortOrder: 8,
            status: "active"
        ),
        ExpectedCategory(
            id: "cleaning",
            en: "Cleaning",
            he: "ניקיון",
            iconKey: "product.cleaning",
            sortOrder: 9,
            status: "active"
        ),
        ExpectedCategory(
            id: "personal_care",
            en: "Personal Care",
            he: "טיפוח אישי",
            iconKey: "product.personalcare",
            sortOrder: 10,
            status: "active"
        ),
        ExpectedCategory(
            id: "pharmacy",
            en: "Pharmacy & Health",
            he: "פארם ובריאות",
            iconKey: "product.pharmacy",
            sortOrder: 11,
            status: "active"
        ),
        ExpectedCategory(
            id: "baby",
            en: "Baby",
            he: "תינוקות",
            iconKey: "product.baby",
            sortOrder: 12,
            status: "active"
        ),
        ExpectedCategory(
            id: "pets",
            en: "Pets",
            he: "בעלי חיים",
            iconKey: "product.pet",
            sortOrder: 13,
            status: "active"
        ),
        ExpectedCategory(
            id: "uncategorized",
            en: "Uncategorized",
            he: "ללא קטגוריה",
            iconKey: "product.generic",
            sortOrder: 14,
            status: "active"
        )
    ]

    static let expectedConcepts: [ExpectedConcept] = [
        ExpectedConcept(
            id: "prd_pilot_0001",
            en: "Milk",
            he: "חלב",
            categoryID: "dairy",
            aliases: ["he:חלב פרה", "en:Cow's Milk"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0002",
            en: "Bread",
            he: "לחם",
            categoryID: "bakery",
            aliases: ["he:כיכר לחם", "en:Loaf of Bread"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0003",
            en: "Eggs",
            he: "ביצים",
            categoryID: "dairy",
            aliases: ["he:ביצי תרנגולת", "en:Chicken Eggs"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0004",
            en: "Rice",
            he: "אורז",
            categoryID: "pantry",
            aliases: []
        ),
        ExpectedConcept(
            id: "prd_pilot_0005",
            en: "Apple",
            he: "תפוח",
            categoryID: "fruits_vegetables",
            aliases: ["he:תפוח עץ"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0006",
            en: "Tomato",
            he: "עגבנייה",
            categoryID: "fruits_vegetables",
            aliases: ["he:עגבניה"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0007",
            en: "Water",
            he: "מים",
            categoryID: "drinks",
            aliases: ["he:מי שתייה", "en:Drinking Water"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0008",
            en: "Coffee",
            he: "קפה",
            categoryID: "drinks",
            aliases: []
        ),
        ExpectedConcept(
            id: "prd_pilot_0009",
            en: "Shampoo",
            he: "שמפו",
            categoryID: "personal_care",
            aliases: ["he:שמפו לשיער", "en:Hair Shampoo"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0010",
            en: "Toothpaste",
            he: "משחת שיניים",
            categoryID: "personal_care",
            aliases: ["he:משחה לשיניים", "en:Tooth Paste"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0011",
            en: "Dog Food",
            he: "מזון לכלבים",
            categoryID: "pets",
            aliases: ["he:אוכל לכלבים", "en:Canine Food"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0012",
            en: "Baby Wipes",
            he: "מגבונים לתינוקות",
            categoryID: "baby",
            aliases: [
                "he:מגבונים לתינוק",
                "he:מגבוני תינוקות",
                "en:Infant Wipes"
            ]
        ),
        ExpectedConcept(
            id: "prd_pilot_0013",
            en: "Dish Soap",
            he: "נוזל כלים",
            categoryID: "cleaning",
            aliases: [
                "he:סבון כלים",
                "he:נוזל לשטיפת כלים",
                "en:Dishwashing Liquid",
                "en:Washing-Up Liquid"
            ]
        ),
        ExpectedConcept(
            id: "prd_pilot_0014",
            en: "Paper Towels",
            he: "מגבות נייר",
            categoryID: "household",
            aliases: ["he:נייר סופג", "en:Kitchen Paper"]
        ),
        ExpectedConcept(
            id: "prd_pilot_0015",
            en: "Frozen Vegetables",
            he: "ירקות קפואים",
            categoryID: "frozen",
            aliases: ["he:ירקות מוקפאים", "en:Frozen Veg"]
        )
    ]
}
