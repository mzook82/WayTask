import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class WayTaskSchemaMigrationTests: XCTestCase {
    private let fixture = MigrationFixture()

    func testV1SchemaExactlyDescribesTheShippedModelGraph() throws {
        let schema = Schema(versionedSchema: WayTaskSchemaV1.self)

        XCTAssertEqual(
            Set(schema.entities.map(\.name)),
            [
                "GeoLocation",
                "ShoppingItem",
                "Product",
                "ShoppingList",
                "ShoppingListEntry",
                "ProductHistory",
                "ProductKnowledge",
                "ShoppingSession"
            ]
        )

        try assertEntity(
            GeoLocation.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "title": (String.self, false),
                "latitude": (Double.self, false),
                "longitude": (Double.self, false),
                "radius": (Double.self, false),
                "storeCategoryRawValue": (String.self, true),
                "addressText": (String.self, true),
                "notes": (String.self, true),
                "sourceTypeRawValue": (String.self, true)
            ],
            relationships: [
                "shoppingItems": ("ShoppingItem", .cascade, false)
            ]
        )
        try assertEntity(
            ShoppingItem.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "name": (String.self, false),
                "isCompleted": (Bool.self, false),
                "imageData": (Data.self, true),
                "brand": (String.self, true),
                "category": (String.self, true),
                "barcode": (String.self, true),
                "imageURLString": (String.self, true),
                "dateAdded": (Date.self, false),
                "sourceRawValue": (String.self, false),
                "productType": (String.self, true),
                "flavor": (String.self, true),
                "packageSize": (String.self, true),
                "packageType": (String.self, true),
                "visibleText": (String.self, true),
                "searchKeywordsRawValue": (String.self, true)
            ]
        )
        try assertEntity(
            WayTaskSchemaV1.Product.self,
            in: schema,
            expectedName: "Product",
            attributes: [
                "id": (UUID.self, false),
                "legacyShoppingItemID": (UUID.self, true),
                "name": (String.self, false),
                "imageData": (Data.self, true),
                "brand": (String.self, true),
                "category": (String.self, true),
                "barcode": (String.self, true),
                "imageURLString": (String.self, true),
                "dateAdded": (Date.self, false),
                "updatedAt": (Date.self, false),
                "sourceRawValue": (String.self, false),
                "productType": (String.self, true),
                "flavor": (String.self, true),
                "packageSize": (String.self, true),
                "packageType": (String.self, true),
                "visibleText": (String.self, true),
                "searchKeywordsRawValue": (String.self, true)
            ]
        )
        try assertEntity(
            ShoppingList.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "title": (String.self, false),
                "kindRawValue": (String.self, false),
                "createdAt": (Date.self, false),
                "updatedAt": (Date.self, false),
                "isDefault": (Bool.self, false)
            ]
        )
        try assertEntity(
            WayTaskSchemaV1.ShoppingListEntry.self,
            in: schema,
            expectedName: "ShoppingListEntry",
            attributes: [
                "id": (UUID.self, false),
                "shoppingListID": (UUID.self, false),
                "productID": (UUID.self, false),
                "legacyShoppingItemID": (UUID.self, true),
                "quantity": (Double.self, false),
                "isChecked": (Bool.self, false),
                "createdAt": (Date.self, false),
                "sortOrder": (Double.self, false)
            ],
            relationships: [
                "product": ("Product", .nullify, true)
            ]
        )
        try assertEntity(
            ProductHistory.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "productKey": (String.self, false),
                "productName": (String.self, false),
                "barcode": (String.self, true),
                "firstAddedDate": (Date.self, false),
                "lastAddedDate": (Date.self, false),
                "addCount": (Int.self, false),
                "lastSourceRawValue": (String.self, false),
                "averageInterval": (TimeInterval.self, true),
                "lastCompletedDate": (Date.self, true)
            ]
        )
        try assertEntity(
            ProductKnowledge.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "knowledgeKey": (String.self, false),
                "barcode": (String.self, true),
                "productName": (String.self, false),
                "preferredDisplayName": (String.self, true),
                "brand": (String.self, true),
                "category": (String.self, true),
                "productType": (String.self, true),
                "flavor": (String.self, true),
                "packageSize": (String.self, true),
                "thumbnailData": (Data.self, true),
                "imageURLString": (String.self, true),
                "searchKeywordsRawValue": (String.self, true),
                "aiConfidence": (Double.self, true),
                "recognitionSourceRawValue": (String.self, true),
                "dateLearned": (Date.self, false),
                "lastUsed": (Date.self, true),
                "timesUsed": (Int.self, false),
                "updatedAt": (Date.self, false)
            ]
        )
        try assertEntity(
            ShoppingSession.self,
            in: schema,
            attributes: [
                "id": (UUID.self, false),
                "startedAt": (Date.self, false),
                "finishedAt": (Date.self, true),
                "isActive": (Bool.self, false),
                "itemIDListRawValue": (String.self, false),
                "collectedItemIDListRawValue": (String.self, false),
                "shoppingListID": (UUID.self, true),
                "selectedStoreID": (UUID.self, true),
                "selectedStoreName": (String.self, true),
                "selectedStoreLatitude": (Double.self, true),
                "selectedStoreLongitude": (Double.self, true)
            ]
        )
    }

    func testV2IsV1PlusExactlySevenNullableProductAttributes() throws {
        let v1 = Schema(versionedSchema: WayTaskSchemaV1.self)
        let v2 = WayTaskModelContainer.currentSchema
        let catalogFields: Set<String> = [
            "catalogProductIDRawValue",
            "catalogDisplayNameSnapshot",
            "catalogDisplayLocaleSnapshot",
            "catalogCategoryIDSnapshotRawValue",
            "catalogCategoryDisplayNameSnapshot",
            "catalogIconKeySnapshot",
            "catalogSnapshotUpdatedAt"
        ]

        XCTAssertEqual(Set(v1.entities.map(\.name)), Set(v2.entities.map(\.name)))
        for v1Entity in v1.entities {
            let v2Entity = try XCTUnwrap(
                v2.entities.first { $0.name == v1Entity.name }
            )
            let v1AttributeNames = Set(v1Entity.attributesByName.keys)
            let v2AttributeNames = Set(v2Entity.attributesByName.keys)

            if v1Entity.name == "Product" {
                XCTAssertEqual(
                    v2AttributeNames.subtracting(v1AttributeNames),
                    catalogFields
                )
                XCTAssertTrue(
                    catalogFields.allSatisfy {
                        v2Entity.attributesByName[$0]?.isOptional == true
                    }
                )
            } else {
                XCTAssertEqual(v2AttributeNames, v1AttributeNames)
            }

            XCTAssertEqual(
                Set(v2Entity.relationshipsByName.keys),
                Set(v1Entity.relationshipsByName.keys)
            )
        }
    }

    func testFileBackedV1StoreMigratesToV2WithoutDataLossOrCatalogInference() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WT025C-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("WayTask.store")

        try writeV1Fixture(to: storeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            "WT025C",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try WayTaskModelContainer.make(
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let products = try context.fetch(FetchDescriptor<Product>())
        let entries = try context.fetch(FetchDescriptor<ShoppingListEntry>())
        let items = try context.fetch(FetchDescriptor<ShoppingItem>())
        let locations = try context.fetch(FetchDescriptor<GeoLocation>())
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        let histories = try context.fetch(FetchDescriptor<ProductHistory>())
        let knowledge = try context.fetch(FetchDescriptor<ProductKnowledge>())
        let sessions = try context.fetch(FetchDescriptor<ShoppingSession>())

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(knowledge.count, 1)
        XCTAssertEqual(sessions.count, 1)

        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.id, fixture.productID)
        XCTAssertEqual(product.legacyShoppingItemID, fixture.itemID)
        XCTAssertEqual(product.name, "Milk")
        XCTAssertEqual(product.imageData, fixture.productImageData)
        XCTAssertEqual(product.brand, "Fixture Brand")
        XCTAssertEqual(product.category, "Dairy")
        XCTAssertEqual(product.barcode, "729000000001")
        XCTAssertEqual(product.imageURLString, fixture.imageURL.absoluteString)
        XCTAssertEqual(product.dateAdded, fixture.productCreatedAt)
        XCTAssertEqual(product.updatedAt, fixture.productUpdatedAt)
        XCTAssertEqual(product.sourceRawValue, ProductSource.ai.rawValue)
        XCTAssertEqual(product.productType, "Dairy drink")
        XCTAssertEqual(product.flavor, "Whole")
        XCTAssertEqual(product.packageSize, "1 L")
        XCTAssertEqual(product.packageType, "Carton")
        XCTAssertEqual(product.visibleText, "3%")
        XCTAssertEqual(product.searchKeywordsRawValue, "whole\nfresh")
        XCTAssertNil(product.catalogProductIDRawValue)
        XCTAssertNil(product.catalogDisplayNameSnapshot)
        XCTAssertNil(product.catalogDisplayLocaleSnapshot)
        XCTAssertNil(product.catalogCategoryIDSnapshotRawValue)
        XCTAssertNil(product.catalogCategoryDisplayNameSnapshot)
        XCTAssertNil(product.catalogIconKeySnapshot)
        XCTAssertNil(product.catalogSnapshotUpdatedAt)

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, fixture.entryID)
        XCTAssertEqual(entry.shoppingListID, fixture.listID)
        XCTAssertEqual(entry.productID, fixture.productID)
        XCTAssertEqual(entry.legacyShoppingItemID, fixture.itemID)
        XCTAssertEqual(entry.quantity, 2)
        XCTAssertTrue(entry.isChecked)
        XCTAssertEqual(entry.createdAt, fixture.entryCreatedAt)
        XCTAssertEqual(entry.sortOrder, 4)
        XCTAssertEqual(entry.product?.id, fixture.productID)

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, fixture.itemID)
        XCTAssertEqual(item.imageData, fixture.productImageData)
        XCTAssertEqual(item.dateAdded, fixture.productCreatedAt)
        XCTAssertEqual(item.sourceRawValue, ProductSource.ai.rawValue)

        let location = try XCTUnwrap(locations.first)
        XCTAssertEqual(location.id, fixture.locationID)
        XCTAssertEqual(location.shoppingItems.map(\.id), [fixture.itemID])

        let list = try XCTUnwrap(lists.first)
        XCTAssertEqual(list.id, fixture.listID)
        XCTAssertEqual(list.createdAt, fixture.listCreatedAt)
        XCTAssertEqual(list.updatedAt, fixture.listUpdatedAt)

        XCTAssertEqual(histories.first?.id, fixture.historyID)
        XCTAssertEqual(histories.first?.firstAddedDate, fixture.productCreatedAt)
        XCTAssertEqual(histories.first?.lastAddedDate, fixture.productUpdatedAt)
        XCTAssertEqual(histories.first?.lastCompletedDate, fixture.historyCompletedAt)
        XCTAssertEqual(histories.first?.lastSourceRawValue, ProductSource.camera.rawValue)
        XCTAssertEqual(knowledge.first?.id, fixture.knowledgeID)
        XCTAssertEqual(knowledge.first?.thumbnailData, fixture.knowledgeImageData)
        XCTAssertEqual(knowledge.first?.dateLearned, fixture.productCreatedAt)
        XCTAssertEqual(knowledge.first?.lastUsed, fixture.productUpdatedAt)
        XCTAssertEqual(knowledge.first?.updatedAt, fixture.productUpdatedAt)
        XCTAssertEqual(knowledge.first?.recognitionSource, .ai)
        XCTAssertEqual(sessions.first?.id, fixture.sessionID)
        XCTAssertEqual(sessions.first?.itemIDs, [fixture.itemID])
        XCTAssertEqual(sessions.first?.shoppingListID, fixture.listID)
        XCTAssertEqual(sessions.first?.startedAt, fixture.sessionStartedAt)
        XCTAssertEqual(sessions.first?.finishedAt, fixture.sessionFinishedAt)

        let backfill = ShoppingListBackfillService()
        let firstResult = try backfill.ensureDefaultListsAndBackfill(in: context)
        let countsAfterFirst = try persistenceCounts(in: context)
        let secondResult = try backfill.ensureDefaultListsAndBackfill(in: context)
        let countsAfterSecond = try persistenceCounts(in: context)

        XCTAssertEqual(firstResult.weeklyListID, fixture.listID)
        XCTAssertEqual(secondResult.weeklyListID, fixture.listID)
        XCTAssertEqual(countsAfterFirst, countsAfterSecond)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Product>()).first?.id, fixture.productID)
        XCTAssertNil(try context.fetch(FetchDescriptor<Product>()).first?.catalogProductIDRawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }

    private func writeV1Fixture(to storeURL: URL) throws {
        let schema = Schema(versionedSchema: WayTaskSchemaV1.self)
        let configuration = ModelConfiguration(
            "WT025C",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let item = ShoppingItem(
            id: fixture.itemID,
            name: "Milk",
            isCompleted: false,
            imageData: fixture.productImageData,
            brand: "Fixture Brand",
            category: "Dairy",
            barcode: "729000000001",
            imageURL: fixture.imageURL,
            dateAdded: fixture.productCreatedAt,
            source: .ai,
            productType: "Dairy drink",
            flavor: "Whole",
            packageSize: "1 L",
            packageType: "Carton",
            visibleText: "3%",
            searchKeywords: ["whole", "fresh"]
        )
        let location = GeoLocation(
            id: fixture.locationID,
            title: "Fixture Market",
            latitude: 31.7683,
            longitude: 35.2137,
            radius: 175,
            addressText: "Fixture Street",
            notes: "V1",
            sourceType: .userGenerated,
            shoppingItems: [item]
        )
        let product = WayTaskSchemaV1.Product(
            id: fixture.productID,
            legacyShoppingItemID: fixture.itemID,
            name: "Milk",
            imageData: fixture.productImageData,
            brand: "Fixture Brand",
            category: "Dairy",
            barcode: "729000000001",
            imageURLString: fixture.imageURL.absoluteString,
            dateAdded: fixture.productCreatedAt,
            updatedAt: fixture.productUpdatedAt,
            sourceRawValue: ProductSource.ai.rawValue,
            productType: "Dairy drink",
            flavor: "Whole",
            packageSize: "1 L",
            packageType: "Carton",
            visibleText: "3%",
            searchKeywordsRawValue: "whole\nfresh"
        )
        let list = ShoppingList(
            id: fixture.listID,
            title: "Weekly Shopping",
            kind: .weekly,
            createdAt: fixture.listCreatedAt,
            updatedAt: fixture.listUpdatedAt,
            isDefault: true
        )
        let entry = WayTaskSchemaV1.ShoppingListEntry(
            id: fixture.entryID,
            shoppingListID: fixture.listID,
            product: product,
            legacyShoppingItemID: fixture.itemID,
            quantity: 2,
            isChecked: true,
            createdAt: fixture.entryCreatedAt,
            sortOrder: 4
        )
        let history = ProductHistory(
            id: fixture.historyID,
            productKey: "barcode:729000000001",
            productName: "Milk",
            barcode: "729000000001",
            firstAddedDate: fixture.productCreatedAt,
            lastAddedDate: fixture.productUpdatedAt,
            addCount: 3,
            lastSource: .camera,
            averageInterval: 86_400,
            lastCompletedDate: fixture.historyCompletedAt
        )
        let learnedKnowledge = ProductKnowledge(
            id: fixture.knowledgeID,
            knowledgeKey: "barcode:729000000001",
            barcode: "729000000001",
            productName: "Milk",
            preferredDisplayName: "Whole Milk",
            brand: "Fixture Brand",
            category: "Dairy",
            productType: "Dairy drink",
            flavor: "Whole",
            packageSize: "1 L",
            thumbnailData: fixture.knowledgeImageData,
            imageURL: fixture.imageURL,
            searchKeywords: ["milk", "whole"],
            aiConfidence: 0.98,
            recognitionSource: .ai,
            dateLearned: fixture.productCreatedAt,
            lastUsed: fixture.productUpdatedAt,
            timesUsed: 3,
            updatedAt: fixture.productUpdatedAt
        )
        let session = ShoppingSession(
            id: fixture.sessionID,
            startedAt: fixture.sessionStartedAt,
            finishedAt: fixture.sessionFinishedAt,
            isActive: false,
            itemIDs: [fixture.itemID],
            collectedItemIDs: [fixture.itemID],
            shoppingListID: fixture.listID,
            selectedStoreID: fixture.locationID,
            selectedStoreName: "Fixture Market",
            selectedStoreLatitude: 31.7683,
            selectedStoreLongitude: 35.2137
        )

        context.insert(item)
        context.insert(location)
        context.insert(product)
        context.insert(list)
        context.insert(entry)
        context.insert(history)
        context.insert(learnedKnowledge)
        context.insert(session)
        try context.save()
    }

    private func persistenceCounts(in context: ModelContext) throws -> PersistenceCounts {
        PersistenceCounts(
            items: try context.fetchCount(FetchDescriptor<ShoppingItem>()),
            products: try context.fetchCount(FetchDescriptor<Product>()),
            lists: try context.fetchCount(FetchDescriptor<ShoppingList>()),
            entries: try context.fetchCount(FetchDescriptor<ShoppingListEntry>())
        )
    }

    private func assertEntity<T: PersistentModel>(
        _ type: T.Type,
        in schema: Schema,
        expectedName: String? = nil,
        attributes: [String: (type: Any.Type, optional: Bool)],
        relationships: [String: (
            destination: String,
            deleteRule: Schema.Relationship.DeleteRule,
            optional: Bool
        )] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let entity = try XCTUnwrap(schema.entity(for: type), file: file, line: line)
        if let expectedName {
            XCTAssertEqual(entity.name, expectedName, file: file, line: line)
        }
        XCTAssertEqual(
            Set(entity.attributesByName.keys),
            Set(attributes.keys),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(entity.relationshipsByName.keys),
            Set(relationships.keys),
            file: file,
            line: line
        )

        for (name, expected) in attributes {
            let attribute = try XCTUnwrap(
                entity.attributesByName[name],
                file: file,
                line: line
            )
            XCTAssertEqual(attribute.isOptional, expected.optional, file: file, line: line)
            let expectedTypeName = expected.optional
                ? "Swift.Optional<\(String(reflecting: expected.type))>"
                : String(reflecting: expected.type)
            XCTAssertEqual(
                String(reflecting: attribute.valueType),
                expectedTypeName,
                "\(entity.name).\(name)",
                file: file,
                line: line
            )
        }

        for (name, expected) in relationships {
            let relationship = try XCTUnwrap(
                entity.relationshipsByName[name],
                file: file,
                line: line
            )
            XCTAssertEqual(relationship.destination, expected.destination, file: file, line: line)
            XCTAssertEqual(relationship.deleteRule, expected.deleteRule, file: file, line: line)
            XCTAssertEqual(relationship.isOptional, expected.optional, file: file, line: line)
        }
    }
}

private struct MigrationFixture {
    let locationID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let itemID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let productID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let listID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    let entryID = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
    let historyID = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
    let knowledgeID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
    let sessionID = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
    let productImageData = Data([0x00, 0x01, 0x7f, 0x80, 0xfe, 0xff])
    let knowledgeImageData = Data([0x10, 0x20, 0x30, 0x40])
    let imageURL = URL(string: "https://example.test/v1-milk.jpg")!
    let productCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let productUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let listCreatedAt = Date(timeIntervalSince1970: 1_700_000_200)
    let listUpdatedAt = Date(timeIntervalSince1970: 1_700_000_300)
    let entryCreatedAt = Date(timeIntervalSince1970: 1_700_000_400)
    let historyCompletedAt = Date(timeIntervalSince1970: 1_700_000_500)
    let sessionStartedAt = Date(timeIntervalSince1970: 1_700_000_600)
    let sessionFinishedAt = Date(timeIntervalSince1970: 1_700_000_700)
}

private struct PersistenceCounts: Equatable {
    let items: Int
    let products: Int
    let lists: Int
    let entries: Int
}
