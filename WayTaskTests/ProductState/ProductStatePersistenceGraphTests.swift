import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStatePersistenceGraphTests: XCTestCase {
    func testTargetSchemaIsRegisteredButCurrentContainerRemainsV3() {
        let current = WayTaskModelContainer.currentSchema
        let target = WayTaskModelContainer.inactiveTargetProductStateSchema

        XCTAssertEqual(
            Set(current.entities.map(\.name)),
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
        XCTAssertEqual(
            Set(target.entities.map(\.name)),
            [
                "GeoLocation",
                "ShoppingItem",
                "Product",
                "ShoppingList",
                "ShoppingListEntry",
                "ProductHistory",
                "ProductHistoryEvent",
                "ProductKnowledge",
                "ShoppingSession",
                "ShoppingSessionLine",
                "ShoppingSessionStop",
                "ProductStateMigrationException"
            ]
        )
        XCTAssertEqual(
            WayTaskSchemaV4.versionIdentifier,
            Schema.Version(4, 0, 0)
        )
        XCTAssertEqual(WayTaskSchemaV4.models.count, 12)
        XCTAssertEqual(WayTaskSchemaMigrationPlan.schemas.count, 3)
        XCTAssertEqual(WayTaskSchemaMigrationPlan.stages.count, 2)
        XCTAssertFalse(
            WayTaskSchemaMigrationPlan.schemas.contains {
                ObjectIdentifier($0) == ObjectIdentifier(WayTaskSchemaV4.self)
            }
        )
    }

    func testTargetSchemaContainsRequiredAttributesAndRelationships() throws {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema

        try assertEntity(
            WayTaskSchemaV4.Product.self,
            in: schema,
            attributes: [
                "id", "revision", "libraryLifecycleRawValue",
                "libraryRemovedAt", "name", "imageData", "brand",
                "category", "barcode", "imageURLString", "sourceRawValue",
                "catalogProductIDRawValue", "catalogDisplayNameSnapshot",
                "catalogDisplayLocaleSnapshot",
                "catalogCategoryIDSnapshotRawValue",
                "catalogCategoryDisplayNameSnapshot",
                "catalogIconKeySnapshot", "catalogSnapshotUpdatedAt",
                "createdAt", "updatedAt"
            ]
        )
        try assertEntity(
            WayTaskSchemaV4.ShoppingList.self,
            in: schema,
            attributes: [
                "id", "revision", "title", "purposeRawValue", "createdAt",
                "updatedAt"
            ],
            relationships: ["entries"]
        )
        try assertEntity(
            WayTaskSchemaV4.ShoppingListEntry.self,
            in: schema,
            attributes: [
                "id", "shoppingListID", "productID", "lifecycleRawValue",
                "resolutionReasonRawValue", "resolutionEffectiveAt",
                "resolutionProvenanceRawValue", "resolutionCommandID",
                "resolutionSessionID", "resolutionSessionLineID", "quantity",
                "unitRawValue", "note", "sortOrder", "createdAt", "updatedAt"
            ],
            relationships: ["product"]
        )
        try assertEntity(
            WayTaskSchemaV4.ProductHistoryEvent.self,
            in: schema,
            attributes: [
                "id", "productID", "meaningRawValue",
                "resolutionReasonRawValue", "sessionOutcomeRawValue",
                "sourceListID", "sourceEntryID", "sessionID", "sessionLineID",
                "commandID", "provenanceRawValue", "occurredAt",
                "displaySnapshotID"
            ],
            relationships: ["product"]
        )
        try assertEntity(
            WayTaskSchemaV4.ShoppingSession.self,
            in: schema,
            attributes: [
                "id", "sourceListID", "sourceRevision",
                "sourceRevisionProvenanceRawValue", "revision",
                "lifecycleRawValue", "migrationConditionRawValue",
                "snapshotID", "snapshotVersion", "snapshotGeneration",
                "snapshotContentSignature", "sourcePlanID",
                "sourcePlanSignature", "sourcePlanEvidenceAt", "startedAt",
                "activationStartedAt", "lastActivityAt", "expiredAt",
                "endedAt", "expirationReasonRawValue",
                "expirationPolicyVersion"
            ],
            relationships: [
                "sourceList", "lines", "stops", "migrationExceptions"
            ]
        )
        try assertEntity(
            WayTaskSchemaV4.ShoppingSessionLine.self,
            in: schema,
            attributes: [
                "id", "sessionID", "snapshotID", "snapshotVersion",
                "snapshotProvenanceRawValue", "sourceListID", "sourceEntryID",
                "productID", "globalProductConceptIDRawValue", "stopID",
                "sortOrder", "productNameSnapshot", "productBrandSnapshot",
                "productCategorySnapshot", "quantitySnapshot",
                "unitSnapshotRawValue", "noteSnapshot",
                "executionStateRawValue", "executionChangedAt",
                "finalOutcomeRawValue", "finalOutcomeAt",
                "finalOutcomeCommandID", "legacyDispositionRawValue"
            ],
            relationships: ["sourceEntry", "product", "stop"]
        )
        try assertEntity(
            WayTaskSchemaV4.ShoppingSessionStop.self,
            in: schema,
            attributes: [
                "id", "sessionID", "snapshotID", "sortOrder",
                "storeReferenceIDRawValue",
                "storeReferenceProvenanceRawValue", "displayNameSnapshot",
                "latitudeSnapshot", "longitudeSnapshot", "evidenceAt",
                "isSessionScopedTransient"
            ]
        )
        try assertEntity(
            WayTaskSchemaV4.ProductStateMigrationException.self,
            in: schema,
            attributes: [
                "id", "sessionID", "sessionLineID", "categoryRawValue",
                "safeEvidenceDigest", "ordinal", "occurrenceCount",
                "recordedAt"
            ]
        )
    }

    func testProductLibraryListEntryAndHistoryGraphRoundTrips() throws {
        let container = try makeTargetContainer()
        let context = ModelContext(container)
        let productID = uuid(1)
        let listID = uuid(2)
        let entryID = uuid(3)
        let commandID = uuid(4)
        let lineID = uuid(5)
        let sessionID = uuid(6)
        let now = date(100)
        let product = WayTaskSchemaV4.Product(
            id: productID,
            revision: 7,
            libraryLifecycleRawValue: ProductLibraryLifecycle.removed.rawValue,
            libraryRemovedAt: now,
            name: "Fixture Product",
            sourceRawValue: ProductSource.manual.rawValue,
            catalogProductIDRawValue: "catalog.fixture",
            catalogDisplayNameSnapshot: "Fixture Product",
            catalogDisplayLocaleSnapshot: "en",
            createdAt: date(1),
            updatedAt: now
        )
        let entry = WayTaskSchemaV4.ShoppingListEntry(
            id: entryID,
            shoppingListID: listID,
            productID: productID,
            lifecycleRawValue: "resolved",
            resolutionReasonRawValue:
                ShoppingListResolutionReason.purchased.rawValue,
            resolutionEffectiveAt: now,
            resolutionProvenanceRawValue: "sessionFinish",
            resolutionCommandID: commandID,
            resolutionSessionID: sessionID,
            resolutionSessionLineID: lineID,
            quantity: 2,
            unitRawValue: "count",
            note: "Frozen note",
            sortOrder: 1,
            createdAt: date(2),
            updatedAt: now,
            product: product
        )
        let list = WayTaskSchemaV4.ShoppingList(
            id: listID,
            revision: 11,
            title: "Named List",
            purposeRawValue: "shopping",
            createdAt: date(1),
            updatedAt: now,
            entries: [entry]
        )
        let history = WayTaskSchemaV4.ProductHistoryEvent(
            id: uuid(7),
            productID: productID,
            meaningRawValue: "sessionOutcome",
            resolutionReasonRawValue:
                ShoppingListResolutionReason.purchased.rawValue,
            sessionOutcomeRawValue:
                ShoppingSessionFinalOutcome.purchased.rawValue,
            sourceListID: listID,
            sourceEntryID: entryID,
            sessionID: sessionID,
            sessionLineID: lineID,
            commandID: commandID,
            provenanceRawValue: "sessionFinish",
            occurredAt: now,
            displaySnapshotID: uuid(8),
            product: product
        )

        context.insert(product)
        context.insert(list)
        context.insert(history)
        try context.save()

        let products = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>()
        )
        let lists = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
        )
        let entries = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
        )
        let events = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
        )

        XCTAssertEqual(products.map(\.id), [productID])
        XCTAssertEqual(products.first?.revision, 7)
        XCTAssertEqual(
            products.first?.libraryLifecycleRawValue,
            ProductLibraryLifecycle.removed.rawValue
        )
        XCTAssertEqual(lists.first?.revision, 11)
        XCTAssertEqual(lists.first?.entries.map(\.id), [entryID])
        XCTAssertEqual(entries.first?.product?.id, productID)
        XCTAssertEqual(
            entries.first?.resolutionReasonRawValue,
            ShoppingListResolutionReason.purchased.rawValue
        )
        XCTAssertEqual(events.first?.productID, productID)
        XCTAssertEqual(events.first?.product?.id, productID)
        XCTAssertEqual(events.first?.commandID, commandID)
    }

    func testNativeSessionSnapshotRelationshipsAndOutcomesRoundTrip() throws {
        let container = try makeTargetContainer()
        let context = ModelContext(container)
        let productID = uuid(20)
        let listID = uuid(21)
        let entryID = uuid(22)
        let sessionID = uuid(23)
        let snapshotID = uuid(24)
        let stopID = uuid(25)
        let lineID = uuid(26)
        let planID = uuid(27)
        let now = date(200)
        let product = WayTaskSchemaV4.Product(
            id: productID,
            revision: 1,
            libraryLifecycleRawValue: ProductLibraryLifecycle.active.rawValue,
            name: "Snapshot Product",
            sourceRawValue: ProductSource.manual.rawValue,
            createdAt: date(1),
            updatedAt: date(1)
        )
        let entry = WayTaskSchemaV4.ShoppingListEntry(
            id: entryID,
            shoppingListID: listID,
            productID: productID,
            lifecycleRawValue: "needed",
            quantity: 3,
            sortOrder: 0,
            createdAt: date(2),
            updatedAt: date(2),
            product: product
        )
        let list = WayTaskSchemaV4.ShoppingList(
            id: listID,
            revision: 9,
            title: "Session Source",
            createdAt: date(1),
            updatedAt: date(2),
            entries: [entry]
        )
        let stop = WayTaskSchemaV4.ShoppingSessionStop(
            id: stopID,
            sessionID: sessionID,
            snapshotID: snapshotID,
            sortOrder: 0,
            storeReferenceIDRawValue: "store.fixture",
            storeReferenceProvenanceRawValue: "planSnapshot",
            displayNameSnapshot: "Fixture Store",
            latitudeSnapshot: 31.7683,
            longitudeSnapshot: 35.2137,
            evidenceAt: date(150),
            isSessionScopedTransient: false
        )
        let line = WayTaskSchemaV4.ShoppingSessionLine(
            id: lineID,
            sessionID: sessionID,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "nativeStart",
            sourceListID: listID,
            sourceEntryID: entryID,
            productID: productID,
            globalProductConceptIDRawValue: "concept.fixture",
            stopID: stopID,
            sortOrder: 0,
            productNameSnapshot: "Snapshot Product",
            productBrandSnapshot: "Fixture Brand",
            productCategorySnapshot: "Fixture Category",
            quantitySnapshot: 3,
            unitSnapshotRawValue: "count",
            noteSnapshot: "Offline note",
            executionStateRawValue:
                ShoppingSessionExecutionState.collected.rawValue,
            executionChangedAt: date(180),
            finalOutcomeRawValue:
                ShoppingSessionFinalOutcome.carriedForward.rawValue,
            finalOutcomeAt: now,
            finalOutcomeCommandID: uuid(28),
            sourceEntry: entry,
            product: product,
            stop: stop
        )
        let session = WayTaskSchemaV4.ShoppingSession(
            id: sessionID,
            sourceListID: listID,
            sourceRevision: 9,
            sourceRevisionProvenanceRawValue: "exact",
            revision: 4,
            lifecycleRawValue: ShoppingSessionLifecycle.finished.rawValue,
            migrationConditionRawValue:
                ShoppingSessionMigrationCondition.native.rawValue,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "sha256:fixture",
            sourcePlanID: planID,
            sourcePlanSignature: "plan:fixture",
            sourcePlanEvidenceAt: date(150),
            startedAt: date(160),
            activationStartedAt: date(160),
            lastActivityAt: date(180),
            endedAt: now,
            expirationPolicyVersion: 1,
            sourceList: list,
            lines: [line],
            stops: [stop]
        )

        context.insert(product)
        context.insert(list)
        context.insert(session)
        try context.save()

        let stored = try XCTUnwrap(
            try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
            ).first
        )
        XCTAssertEqual(stored.id, sessionID)
        XCTAssertEqual(stored.sourceList?.id, listID)
        XCTAssertEqual(stored.sourceRevision, 9)
        XCTAssertEqual(stored.revision, 4)
        XCTAssertEqual(stored.snapshotID, snapshotID)
        XCTAssertEqual(stored.sourcePlanID, planID)
        XCTAssertEqual(stored.stops.map(\.id), [stopID])
        XCTAssertEqual(stored.lines.map(\.id), [lineID])
        XCTAssertEqual(stored.lines.first?.sourceEntry?.id, entryID)
        XCTAssertEqual(stored.lines.first?.product?.id, productID)
        XCTAssertEqual(stored.lines.first?.stop?.id, stopID)
        XCTAssertEqual(
            stored.lines.first?.executionStateRawValue,
            ShoppingSessionExecutionState.collected.rawValue
        )
        XCTAssertEqual(
            stored.lines.first?.finalOutcomeRawValue,
            ShoppingSessionFinalOutcome.carriedForward.rawValue
        )
        XCTAssertNil(stored.lines.first?.legacyDispositionRawValue)
    }

    func testLegacyIncompleteSessionCanPreserveUnresolvedEvidence() throws {
        let container = try makeTargetContainer()
        let context = ModelContext(container)
        let sessionID = uuid(40)
        let lineID = uuid(41)
        let snapshotID = uuid(42)
        let unresolvedLine = WayTaskSchemaV4.ShoppingSessionLine(
            id: lineID,
            sessionID: sessionID,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "legacyIncomplete",
            sortOrder: 0,
            productNameSnapshot: "Legacy item unavailable",
            quantitySnapshot: 1,
            executionStateRawValue:
                ShoppingSessionExecutionState.collected.rawValue,
            legacyDispositionRawValue:
                ShoppingSessionLegacyDisposition.legacyUnknown.rawValue
        )
        let exception = WayTaskSchemaV4.ProductStateMigrationException(
            id: uuid(43),
            sessionID: sessionID,
            sessionLineID: lineID,
            categoryRawValue: "unresolvedLineIdentity",
            safeEvidenceDigest: "sha256:safe-fixture",
            ordinal: 1,
            occurrenceCount: 1,
            recordedAt: date(300)
        )
        let session = WayTaskSchemaV4.ShoppingSession(
            id: sessionID,
            sourceListID: uuid(44),
            sourceRevision: nil,
            sourceRevisionProvenanceRawValue: "legacyUnknown",
            revision: 1,
            lifecycleRawValue: ShoppingSessionLifecycle.finished.rawValue,
            migrationConditionRawValue:
                ShoppingSessionMigrationCondition.legacyIncomplete.rawValue,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "legacy:incomplete",
            startedAt: date(250),
            activationStartedAt: date(250),
            lastActivityAt: date(250),
            endedAt: date(260),
            expirationPolicyVersion: 1,
            lines: [unresolvedLine],
            migrationExceptions: [exception]
        )

        context.insert(session)
        try context.save()

        let stored = try XCTUnwrap(
            try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
            ).first
        )
        XCTAssertNil(stored.sourceRevision)
        XCTAssertEqual(
            stored.sourceRevisionProvenanceRawValue,
            "legacyUnknown"
        )
        XCTAssertEqual(
            stored.migrationConditionRawValue,
            ShoppingSessionMigrationCondition.legacyIncomplete.rawValue
        )
        XCTAssertNil(stored.lines.first?.sourceEntryID)
        XCTAssertNil(stored.lines.first?.productID)
        XCTAssertNil(stored.lines.first?.finalOutcomeRawValue)
        XCTAssertEqual(
            stored.lines.first?.legacyDispositionRawValue,
            ShoppingSessionLegacyDisposition.legacyUnknown.rawValue
        )
        XCTAssertEqual(
            stored.migrationExceptions.first?.categoryRawValue,
            "unresolvedLineIdentity"
        )
    }

    func testPersistenceVocabularyMatchesApprovedDomainRawValues() {
        XCTAssertEqual(
            Set(ProductLibraryLifecycle.allCases.map(\.rawValue)),
            ["active", "removed"]
        )
        XCTAssertEqual(
            Set(ShoppingListResolutionReason.allCases.map(\.rawValue)),
            ["purchased", "alreadyHave", "noLongerNeeded", "legacyUnknown"]
        )
        XCTAssertEqual(
            Set(ShoppingSessionLifecycle.allCases.map(\.rawValue)),
            ["active", "expired", "finished", "abandoned"]
        )
        XCTAssertEqual(
            Set(ShoppingSessionExecutionState.allCases.map(\.rawValue)),
            ["remaining", "collected"]
        )
        XCTAssertEqual(
            Set(ShoppingSessionFinalOutcome.allCases.map(\.rawValue)),
            [
                "purchased", "alreadyHave", "noLongerNeeded", "unavailable",
                "skipped", "carriedForward"
            ]
        )
        XCTAssertFalse(
            ShoppingSessionFinalOutcome.allCases.map(\.rawValue).contains(
                ShoppingSessionLegacyDisposition.legacyUnknown.rawValue
            )
        )
        XCTAssertEqual(
            Set(ShoppingSessionMigrationCondition.allCases.map(\.rawValue)),
            [
                "native", "legacyMapped", "legacyIncomplete",
                "legacyUnresolved"
            ]
        )
    }

    private func makeTargetContainer() throws -> ModelContainer {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T02",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func assertEntity<T: PersistentModel>(
        _ type: T.Type,
        in schema: Schema,
        attributes: Set<String>,
        relationships: Set<String> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let entity = try XCTUnwrap(
            schema.entity(for: type),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(entity.attributesByName.keys),
            attributes,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(entity.relationshipsByName.keys),
            relationships,
            file: file,
            line: line
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }
}
