import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateProductCommandAuthorityTests: XCTestCase {
    func testWriteGateRejectsIncompleteAndNonDurableTargetBeforeMutation()
        throws {
        let fixture = try makeFixture("write-gate")
        let request = acquisition(command: 1, product: 2, name: "Synthetic")

        let incomplete = makeAuthority(
            fixture,
            writeState: .migrationIncomplete
        ).acquire(request)
        let nonDurable = makeAuthority(
            fixture,
            writeState: .nonDurable
        ).acquire(request)

        XCTAssertEqual(incomplete.outcome, .unavailable(.migrationIncomplete))
        XCTAssertEqual(incomplete.diagnostic.failure, .migrationIncomplete)
        XCTAssertEqual(nonDurable.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(nonDurable.diagnostic.failure, .nonDurable)
        XCTAssertFalse(incomplete.claimsDurableSuccess)
        XCTAssertFalse(nonDurable.claimsDurableSuccess)
        XCTAssertTrue(try fixture.repositories.products.products(id: uuid(2)).isEmpty)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testManualAcquisitionCommitsOneProductWithStableIdentityAndRevision()
        throws {
        let fixture = try makeFixture("manual-acquire")
        let request = acquisition(
            command: 10,
            product: 11,
            name: "  Synthetic Product  ",
            imageData: Data([0x01, 0x02])
        )

        let execution = makeAuthority(fixture).acquire(request)

        guard case let .created(summary) = execution.outcome else {
            return XCTFail("Expected durable create")
        }
        XCTAssertEqual(summary.productID, productID(11))
        XCTAssertEqual(summary.productRevisionBefore, 0)
        XCTAssertEqual(summary.productRevisionAfter, 1)
        XCTAssertTrue(summary.affectedLists.isEmpty)
        XCTAssertTrue(summary.historyEventIDs.isEmpty)
        XCTAssertEqual(summary.durability, .committed)
        XCTAssertTrue(execution.claimsDurableSuccess)

        let stored = try fetchProduct(in: fixture.container, id: 11)
        XCTAssertEqual(stored.id, uuid(11))
        XCTAssertEqual(stored.revision, 1)
        XCTAssertEqual(stored.name, "Synthetic Product")
        XCTAssertEqual(stored.imageData, Data([0x01, 0x02]))
        XCTAssertEqual(stored.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertNil(stored.libraryRemovedAt)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingList.self, in: fixture.container), 0)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: fixture.container), 0)
    }

    func testCatalogAcquisitionPreservesExactIdentityAndReviewedSnapshots()
        throws {
        let fixture = try makeFixture("catalog-acquire")
        let request = ProductStateProductAcquisitionRequest(
            commandID: commandID(20),
            productID: productID(21),
            effectiveAt: instant,
            reviewed: true,
            name: "Synthetic Catalog Display",
            imageData: Data([0xaa]),
            category: "Synthetic Category",
            sourceRawValue: ProductSource.catalog.rawValue,
            catalogID: ProductStateCatalogID(rawValue: "catalog.synthetic.exact"),
            catalogDisplayNameSnapshot: "Synthetic Catalog Display",
            catalogDisplayLocaleSnapshot: "en",
            catalogCategoryIDSnapshotRawValue: "category.synthetic",
            catalogCategoryDisplayNameSnapshot: "Synthetic Category",
            catalogIconKeySnapshot: "product.synthetic",
            catalogSnapshotUpdatedAt: instant
        )

        let execution = makeAuthority(fixture).acquire(request)

        guard case .created = execution.outcome else {
            return XCTFail("Expected catalog create")
        }
        let stored = try fetchProduct(in: fixture.container, id: 21)
        XCTAssertEqual(stored.id, uuid(21))
        XCTAssertEqual(stored.catalogProductIDRawValue, "catalog.synthetic.exact")
        XCTAssertEqual(stored.catalogDisplayNameSnapshot, "Synthetic Catalog Display")
        XCTAssertEqual(stored.catalogDisplayLocaleSnapshot, "en")
        XCTAssertEqual(stored.catalogCategoryIDSnapshotRawValue, "category.synthetic")
        XCTAssertEqual(stored.catalogCategoryDisplayNameSnapshot, "Synthetic Category")
        XCTAssertEqual(stored.catalogIconKeySnapshot, "product.synthetic")
        XCTAssertEqual(stored.catalogSnapshotUpdatedAt, instant)
    }

    func testExactAcquisitionEvidenceReturnsAlreadyActiveOrRestoreRequired()
        throws {
        let fixture = try makeFixture("acquire-classification")
        let active = makeProduct(
            30,
            revision: 4,
            catalogID: "catalog.synthetic.same"
        )
        let removed = makeProduct(
            31,
            revision: 7,
            lifecycle: .removed,
            barcode: "000111222",
            removedAt: instant.addingTimeInterval(-100)
        )
        fixture.repositories.products.stageInsertion(of: active)
        fixture.repositories.products.stageInsertion(of: removed)
        try fixture.context.save()

        let catalogRequest = ProductStateProductAcquisitionRequest(
            commandID: commandID(32),
            productID: productID(33),
            effectiveAt: instant,
            reviewed: true,
            name: "Different Display",
            sourceRawValue: ProductSource.catalog.rawValue,
            catalogID: ProductStateCatalogID(rawValue: "catalog.synthetic.same")
        )
        let activeResult = makeAuthority(fixture).acquire(catalogRequest)
        XCTAssertEqual(
            activeResult.outcome,
            .alreadyActive(productID: productID(30), revision: 4)
        )
        XCTAssertFalse(activeResult.claimsDurableSuccess)

        let candidate = ProductCandidate(
            id: uuid(34),
            name: "Private Synthetic Scan",
            source: .barcode,
            barcode: "000111222"
        )
        let removedResult = ShoppingListService().acquireTargetProduct(
            candidate,
            fallbackImageData: nil,
            productID: productID(35),
            commandID: commandID(36),
            effectiveAt: instant,
            reviewed: true,
            using: makeAuthority(fixture)
        )
        XCTAssertEqual(
            removedResult.outcome,
            .restoreRequired(productID: productID(31), revision: 7)
        )
        XCTAssertEqual(removedResult.diagnostic.failure, .removedProduct)
        XCTAssertEqual(removed.libraryLifecycleRawValue, ProductLibraryLifecycle.removed.rawValue)
        XCTAssertNotNil(removed.libraryRemovedAt)
        XCTAssertEqual(try count(WayTaskSchemaV4.Product.self, in: fixture.container), 2)
    }

    func testAcquisitionRejectsAmbiguousExactIdentityButNeverNameMatches()
        throws {
        let fixture = try makeFixture("acquire-identity")
        let first = makeProduct(40, revision: 1, name: "Same Name", catalogID: "duplicate.exact")
        let second = makeProduct(41, revision: 1, name: "Other", catalogID: "duplicate.exact")
        fixture.repositories.products.stageInsertion(of: first)
        fixture.repositories.products.stageInsertion(of: second)
        try fixture.context.save()

        let ambiguous = ProductStateProductAcquisitionRequest(
            commandID: commandID(42),
            productID: productID(43),
            effectiveAt: instant,
            reviewed: true,
            name: "Unrelated Private Name",
            sourceRawValue: ProductSource.catalog.rawValue,
            catalogID: ProductStateCatalogID(rawValue: "duplicate.exact")
        )
        let rejected = makeAuthority(fixture).acquire(ambiguous)
        XCTAssertEqual(rejected.outcome, .conflict(.ambiguousIdentity))
        XCTAssertEqual(rejected.diagnostic.failure, .ambiguousIdentity)
        XCTAssertFalse(rejected.claimsDurableSuccess)

        let nameOnly = acquisition(
            command: 44,
            product: 45,
            name: "Same Name"
        )
        let created = makeAuthority(fixture).acquire(nameOnly)
        guard case .created = created.outcome else {
            return XCTFail("Name equality must not establish identity")
        }
        XCTAssertEqual(try count(WayTaskSchemaV4.Product.self, in: fixture.container), 3)
    }

    func testEditCommitsOneRevisionAndPreservesUUIDTombstoneAndCatalogEvidence()
        throws {
        let fixture = try makeFixture("edit")
        let stored = makeProduct(
            50,
            revision: 9,
            name: "Before",
            catalogID: "catalog.edit"
        )
        stored.catalogDisplayNameSnapshot = "Immutable Snapshot"
        stored.barcode = "998877"
        fixture.repositories.products.stageInsertion(of: stored)
        try fixture.context.save()

        let execution = makeAuthority(fixture).edit(
            editCommand(command: 51, product: 50, revision: 9, name: "After")
        )

        guard case let .edited(summary) = execution.outcome else {
            return XCTFail("Expected durable edit")
        }
        XCTAssertEqual(summary.productID, productID(50))
        XCTAssertEqual(summary.productRevisionBefore, 9)
        XCTAssertEqual(summary.productRevisionAfter, 10)
        XCTAssertTrue(summary.affectedLists.isEmpty)
        XCTAssertTrue(summary.historyEventIDs.isEmpty)
        let reloaded = try fetchProduct(in: fixture.container, id: 50)
        XCTAssertEqual(reloaded.id, uuid(50))
        XCTAssertEqual(reloaded.name, "After")
        XCTAssertEqual(reloaded.revision, 10)
        XCTAssertEqual(reloaded.catalogProductIDRawValue, "catalog.edit")
        XCTAssertEqual(reloaded.catalogDisplayNameSnapshot, "Immutable Snapshot")
        XCTAssertEqual(reloaded.barcode, "998877")
        XCTAssertNil(reloaded.libraryRemovedAt)
    }

    func testEditRejectsStaleRevisionAndRemovedProductWithoutMutation()
        throws {
        let fixture = try makeFixture("edit-boundaries")
        let active = makeProduct(52, revision: 4, name: "Active Before")
        let removedAt = instant.addingTimeInterval(-200)
        let removed = makeProduct(
            53,
            revision: 6,
            lifecycle: .removed,
            name: "Removed Before",
            removedAt: removedAt
        )
        fixture.repositories.products.stageInsertion(of: active)
        fixture.repositories.products.stageInsertion(of: removed)
        try fixture.context.save()

        let stale = makeAuthority(fixture).edit(
            editCommand(command: 54, product: 52, revision: 3, name: "No")
        )
        XCTAssertEqual(stale.outcome, .conflict(.staleRevision))

        let tombstone = makeAuthority(fixture).edit(
            editCommand(command: 55, product: 53, revision: 6, name: "No")
        )
        XCTAssertEqual(tombstone.outcome, .conflict(.removedProduct))
        XCTAssertEqual(active.name, "Active Before")
        XCTAssertEqual(active.revision, 4)
        XCTAssertEqual(removed.name, "Removed Before")
        XCTAssertEqual(removed.revision, 6)
        XCTAssertEqual(removed.libraryRemovedAt, removedAt)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testAcquisitionAndEditSaveFailuresRollbackAndNeverClaimSuccess()
        throws {
        let acquisitionFixture = try makeFixture("acquire-rollback")
        let acquisitionResult = rollbackAuthority(
            acquisitionFixture,
            failure: .saveFailed
        ).acquire(
            acquisition(command: 56, product: 57, name: "Rolled Back")
        )
        XCTAssertEqual(
            acquisitionResult.outcome,
            .unavailable(.durableAuthorityUnavailable)
        )
        XCTAssertEqual(acquisitionResult.diagnostic.failure, .saveFailed)
        XCTAssertFalse(acquisitionResult.claimsDurableSuccess)
        XCTAssertEqual(
            try count(
                WayTaskSchemaV4.Product.self,
                in: acquisitionFixture.container
            ),
            0
        )

        let editFixture = try makeFixture("edit-rollback")
        let product = makeProduct(58, revision: 2, name: "Before Rollback")
        editFixture.repositories.products.stageInsertion(of: product)
        try editFixture.context.save()
        let editResult = rollbackAuthority(editFixture, failure: .saveFailed)
            .edit(
                editCommand(
                    command: 59,
                    product: 58,
                    revision: 2,
                    name: "After Rollback"
                )
            )
        XCTAssertEqual(
            editResult.outcome,
            .unavailable(.durableAuthorityUnavailable)
        )
        XCTAssertEqual(editResult.diagnostic.failure, .saveFailed)
        XCTAssertFalse(editResult.claimsDurableSuccess)
        let reloaded = try fetchProduct(in: editFixture.container, id: 58)
        XCTAssertEqual(reloaded.name, "Before Rollback")
        XCTAssertEqual(reloaded.revision, 2)
    }

    func testRemovalAtomicallyTombstonesProductRemovesEveryEditableMembershipAndAppendsEvent()
        throws {
        let fixture = try makeFixture("remove-all-lists")
        let product = makeProduct(60, revision: 5, name: "Synthetic Private")
        let first = makeList(61, revision: 3, purpose: "shopping", entries: [
            makeEntry(71, list: 61, product: 60, productModel: product)
        ])
        let second = makeList(62, revision: 8, purpose: nil, entries: [
            makeEntry(72, list: 62, product: 60, productModel: product)
        ])
        let archive = makeList(63, revision: 4, purpose: ShoppingListKind.completed.rawValue, entries: [
            makeEntry(73, list: 63, product: 60, productModel: product)
        ])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: second)
        fixture.repositories.shopping.stageInsertion(of: archive)
        fixture.repositories.shopping.stageInsertion(of: first)
        try fixture.context.save()

        let execution = makeAuthority(fixture).removeFromLibrary(
            removeCommand(command: 64, product: 60, history: 65, revision: 5),
            expectedAffectedListRevisions: [
                listExpectation(62, revision: 8),
                listExpectation(61, revision: 3)
            ]
        )

        guard case let .removed(summary) = execution.outcome else {
            return XCTFail("Expected durable removal, got \(execution.outcome)")
        }
        XCTAssertEqual(summary.productRevisionBefore, 5)
        XCTAssertEqual(summary.productRevisionAfter, 6)
        XCTAssertEqual(summary.affectedLists, [
            ProductStateAffectedListRevision(
                listID: listID(61),
                before: ProductStateListRevision(value: 3),
                after: ProductStateListRevision(value: 4)
            ),
            ProductStateAffectedListRevision(
                listID: listID(62),
                before: ProductStateListRevision(value: 8),
                after: ProductStateListRevision(value: 9)
            )
        ])
        XCTAssertEqual(summary.historyEventIDs, [historyID(65)])
        XCTAssertTrue(execution.claimsDurableSuccess)

        let verification = makeContext(fixture.container)
        let removedProductID = uuid(60)
        let removed = try XCTUnwrap(try verification.fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>(
                predicate: #Predicate { $0.id == removedProductID }
            )
        ).first)
        XCTAssertEqual(removed.libraryLifecycleRawValue, ProductLibraryLifecycle.removed.rawValue)
        XCTAssertEqual(removed.libraryRemovedAt, instant)
        XCTAssertEqual(removed.revision, 6)
        let entries = try verification.fetch(FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>())
        XCTAssertEqual(entries.map(\.id), [uuid(73)])
        let lists = try verification.fetch(FetchDescriptor<WayTaskSchemaV4.ShoppingList>())
        let revisions = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.revision) })
        XCTAssertEqual(revisions[uuid(61)], 4)
        XCTAssertEqual(revisions[uuid(62)], 9)
        XCTAssertEqual(revisions[uuid(63)], 4)
        let event = try XCTUnwrap(try verification.fetch(
            FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
        ).first)
        XCTAssertEqual(event.id, uuid(65))
        XCTAssertEqual(event.productID, uuid(60))
        XCTAssertEqual(event.commandID, uuid(64))
        XCTAssertEqual(event.meaningRawValue, "productRemovedFromLibrary")
        XCTAssertEqual(event.provenanceRawValue, "userCommand")
    }

    func testRemovalRequiresExactListImpactSummaryAndRejectsStaleRevision()
        throws {
        let fixture = try makeFixture("remove-impact")
        let product = makeProduct(80, revision: 2)
        let list = makeList(81, revision: 6, entries: [
            makeEntry(82, list: 81, product: 80, productModel: product)
        ])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: list)
        try fixture.context.save()
        let command = removeCommand(command: 83, product: 80, history: 84, revision: 2)

        let missing = makeAuthority(fixture).removeFromLibrary(
            command,
            expectedAffectedListRevisions: []
        )
        XCTAssertEqual(missing.outcome, .validationFailure)
        XCTAssertFalse(missing.claimsDurableSuccess)

        let extra = makeAuthority(fixture).removeFromLibrary(
            command,
            expectedAffectedListRevisions: [
                listExpectation(81, revision: 6),
                listExpectation(85, revision: 1)
            ]
        )
        XCTAssertEqual(extra.outcome, .validationFailure)

        let stale = makeAuthority(fixture).removeFromLibrary(
            command,
            expectedAffectedListRevisions: [listExpectation(81, revision: 5)]
        )
        XCTAssertEqual(stale.outcome, .conflict(.staleRevision))
        XCTAssertEqual(product.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertNil(product.libraryRemovedAt)
        XCTAssertEqual(product.revision, 2)
        XCTAssertEqual(list.revision, 6)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingListEntry.self, in: fixture.container), 1)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: fixture.container), 0)
    }

    func testActiveAndExpiredSessionEvidenceBlocksRemovalAtomically()
        throws {
        let active = try makeFixture("active-session")
        let activeProduct = makeProduct(90, revision: 1)
        active.repositories.products.stageInsertion(of: activeProduct)
        active.repositories.sessions.stageInsertion(
            of: makeSession(91, lifecycle: .active, product: 90)
        )
        try active.context.save()

        let activeResult = makeAuthority(active).removeFromLibrary(
            removeCommand(command: 92, product: 90, history: 93, revision: 1),
            expectedAffectedListRevisions: []
        )
        XCTAssertEqual(activeResult.outcome, .conflict(.activeSession))
        XCTAssertEqual(activeProduct.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: active.container), 0)

        let expired = try makeFixture("expired-session")
        let expiredProduct = makeProduct(94, revision: 3)
        let entry = makeEntry(95, list: 96, product: 94, productModel: expiredProduct)
        let list = makeList(96, revision: 2, entries: [entry])
        expired.repositories.products.stageInsertion(of: expiredProduct)
        expired.repositories.shopping.stageInsertion(of: list)
        expired.repositories.sessions.stageInsertion(
            of: makeSession(97, lifecycle: .expired, sourceEntry: 95)
        )
        try expired.context.save()

        let expiredResult = makeAuthority(expired).removeFromLibrary(
            removeCommand(command: 98, product: 94, history: 99, revision: 3),
            expectedAffectedListRevisions: [listExpectation(96, revision: 2)]
        )
        XCTAssertEqual(expiredResult.outcome, .conflict(.activeSession))
        XCTAssertEqual(expiredProduct.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertEqual(list.revision, 2)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingListEntry.self, in: expired.container), 1)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: expired.container), 0)
    }

    func testRemovalSaveFailureRollsBackProductListsEntriesAndHistory()
        throws {
        let fixture = try makeFixture("remove-rollback")
        let product = makeProduct(100, revision: 4)
        let list = makeList(101, revision: 7, entries: [
            makeEntry(102, list: 101, product: 100, productModel: product)
        ])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: list)
        try fixture.context.save()
        let authority = rollbackAuthority(fixture, failure: .saveFailed)

        let execution = authority.removeFromLibrary(
            removeCommand(command: 103, product: 100, history: 104, revision: 4),
            expectedAffectedListRevisions: [listExpectation(101, revision: 7)]
        )

        XCTAssertEqual(execution.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(execution.diagnostic.failure, .saveFailed)
        XCTAssertEqual(execution.diagnostic.durability, .rolledBack)
        XCTAssertFalse(execution.claimsDurableSuccess)
        let verification = makeContext(fixture.container)
        let reloaded = try XCTUnwrap(try verification.fetch(FetchDescriptor<WayTaskSchemaV4.Product>()).first)
        XCTAssertEqual(reloaded.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertNil(reloaded.libraryRemovedAt)
        XCTAssertEqual(reloaded.revision, 4)
        XCTAssertEqual(try verification.fetch(FetchDescriptor<WayTaskSchemaV4.ShoppingList>()).first?.revision, 7)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()), 1)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()), 0)
    }

    func testExplicitRestorePreservesIdentityFieldsHistoryAndCreatesNoList()
        throws {
        let fixture = try makeFixture("restore")
        let product = makeProduct(
            110,
            revision: 12,
            lifecycle: .removed,
            name: "Private Preserved",
            barcode: "123-private",
            catalogID: "catalog.restore",
            removedAt: instant.addingTimeInterval(-500)
        )
        product.brand = "Preserved Brand"
        product.catalogDisplayNameSnapshot = "Preserved Snapshot"
        let priorEvent = makeHistoryEvent(111, product: 110, meaning: "priorEvidence", command: 112)
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.history.stageInsertion(of: priorEvent)
        try fixture.context.save()

        let execution = makeAuthority(fixture).restoreToLibrary(
            restoreCommand(command: 113, product: 110, history: 114, revision: 12)
        )

        guard case let .restored(summary) = execution.outcome else {
            return XCTFail("Expected durable restore")
        }
        XCTAssertEqual(summary.productID, productID(110))
        XCTAssertEqual(summary.productRevisionBefore, 12)
        XCTAssertEqual(summary.productRevisionAfter, 13)
        XCTAssertTrue(summary.affectedLists.isEmpty)
        XCTAssertEqual(summary.historyEventIDs, [historyID(114)])
        let reloaded = try fetchProduct(in: fixture.container, id: 110)
        XCTAssertEqual(reloaded.id, uuid(110))
        XCTAssertEqual(reloaded.libraryLifecycleRawValue, ProductLibraryLifecycle.active.rawValue)
        XCTAssertNil(reloaded.libraryRemovedAt)
        XCTAssertEqual(reloaded.revision, 13)
        XCTAssertEqual(reloaded.name, "Private Preserved")
        XCTAssertEqual(reloaded.brand, "Preserved Brand")
        XCTAssertEqual(reloaded.barcode, "123-private")
        XCTAssertEqual(reloaded.catalogProductIDRawValue, "catalog.restore")
        XCTAssertEqual(reloaded.catalogDisplayNameSnapshot, "Preserved Snapshot")
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingList.self, in: fixture.container), 0)
        let events = try makeContext(fixture.container).fetch(FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>())
        XCTAssertEqual(Set(events.map(\.id)), [uuid(111), uuid(114)])
    }

    func testRestoreIsNoOpForActiveAndRejectsRemovedStateWithoutTombstone()
        throws {
        let fixture = try makeFixture("restore-boundaries")
        let active = makeProduct(120, revision: 3)
        let malformed = makeProduct(
            121,
            revision: 5,
            lifecycle: .removed,
            removedAt: nil
        )
        fixture.repositories.products.stageInsertion(of: active)
        fixture.repositories.products.stageInsertion(of: malformed)
        try fixture.context.save()

        let activeResult = makeAuthority(fixture).restoreToLibrary(
            restoreCommand(command: 122, product: 120, history: 123, revision: 3)
        )
        XCTAssertEqual(
            activeResult.outcome,
            .alreadyActive(productID: productID(120), revision: 3)
        )
        XCTAssertFalse(activeResult.claimsDurableSuccess)

        let malformedResult = makeAuthority(fixture).restoreToLibrary(
            restoreCommand(command: 124, product: 121, history: 125, revision: 5)
        )
        XCTAssertEqual(malformedResult.outcome, .validationFailure)
        XCTAssertEqual(malformed.libraryLifecycleRawValue, ProductLibraryLifecycle.removed.rawValue)
        XCTAssertNil(malformed.libraryRemovedAt)
        XCTAssertEqual(malformed.revision, 5)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: fixture.container), 0)
    }

    func testRestoreSaveFailureRetainsTombstoneAndDoesNotAppendEvent()
        throws {
        let fixture = try makeFixture("restore-rollback")
        let removedAt = instant.addingTimeInterval(-1_000)
        let product = makeProduct(
            130,
            revision: 8,
            lifecycle: .removed,
            removedAt: removedAt
        )
        fixture.repositories.products.stageInsertion(of: product)
        try fixture.context.save()

        let execution = rollbackAuthority(fixture, failure: .saveFailed)
            .restoreToLibrary(
                restoreCommand(command: 131, product: 130, history: 132, revision: 8)
            )

        XCTAssertEqual(execution.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(execution.diagnostic.failure, .saveFailed)
        let reloaded = try fetchProduct(in: fixture.container, id: 130)
        XCTAssertEqual(reloaded.libraryLifecycleRawValue, ProductLibraryLifecycle.removed.rawValue)
        XCTAssertEqual(reloaded.libraryRemovedAt, removedAt)
        XCTAssertEqual(reloaded.revision, 8)
        XCTAssertEqual(try count(WayTaskSchemaV4.ProductHistoryEvent.self, in: fixture.container), 0)
    }

    func testDiagnosticsAreDeterministicBoundedAndPrivacySafe() throws {
        let fixture = try makeFixture("diagnostics")
        let privateValues = [
            "SECRET PRODUCT NAME",
            "SECRET-BARCODE-729",
            "SECRET CATALOG DISPLAY",
            "SECRET NOTE",
            "31.7683,35.2137"
        ]
        let request = ProductStateProductAcquisitionRequest(
            commandID: commandID(140),
            productID: productID(141),
            effectiveAt: instant,
            reviewed: true,
            name: privateValues[0],
            brand: "SECRET BRAND",
            category: "SECRET CATEGORY",
            barcode: privateValues[1],
            sourceRawValue: ProductSource.barcode.rawValue,
            catalogDisplayNameSnapshot: privateValues[2]
        )
        let first = makeAuthority(fixture, writeState: .nonDurable).acquire(request)
        let second = makeAuthority(fixture, writeState: .nonDurable).acquire(request)
        XCTAssertEqual(first.diagnostic, second.diagnostic)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let firstData = try encoder.encode(first.diagnostic)
        let secondData = try encoder.encode(second.diagnostic)
        XCTAssertEqual(firstData, secondData)
        let encoded = try XCTUnwrap(String(data: firstData, encoding: .utf8))
        for privateValue in privateValues + ["SECRET BRAND", "SECRET CATEGORY"] {
            XCTAssertFalse(encoded.contains(privateValue))
        }
        XCTAssertLessThan(encoded.utf8.count, 1_024)
        XCTAssertTrue(encoded.contains(uuid(140).uuidString))
        XCTAssertTrue(encoded.contains(uuid(141).uuidString))
    }

    func testTargetAdaptersRouteCatalogAndCustomAcquisitionThroughAuthority()
        throws {
        let fixture = try makeFixture("target-adapters")
        let authority = makeAuthority(fixture)
        let catalogRequest = CatalogProductSaveRequest(
            productID: ProductID("milk_3_percent"),
            displayNameSnapshot: "Synthetic Milk",
            displayLocaleSnapshot: "en",
            categoryIDSnapshot: ProductCategoryID("dairy"),
            categoryDisplayNameSnapshot: "Synthetic Dairy",
            iconKeySnapshot: "product.dairy",
            imageData: Data([0x42]),
            source: .catalog
        )

        let catalog = try CatalogProductPersistenceService().acquireTargetProduct(
            catalogRequest,
            productID: productID(150),
            commandID: commandID(151),
            effectiveAt: instant,
            reviewed: true,
            using: authority
        )
        guard case .created = catalog.outcome else {
            return XCTFail("Expected catalog adapter creation")
        }
        let catalogProduct = try fetchProduct(in: fixture.container, id: 150)
        XCTAssertEqual(catalogProduct.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(catalogProduct.catalogDisplayNameSnapshot, "Synthetic Milk")

        let custom = try AddProductSaveCoordinator().acquireTargetProduct(
            selection: .custom(
                AddProductCustomSelection(
                    name: "Synthetic Custom",
                    preselectionQuery: "Synthetic Custom"
                )
            ),
            imageData: Data([0x43]),
            productID: productID(152),
            commandID: commandID(153),
            effectiveAt: instant,
            reviewed: true,
            using: authority
        )
        guard case .created = custom.outcome else {
            return XCTFail("Expected custom adapter creation")
        }
        let customProduct = try fetchProduct(in: fixture.container, id: 152)
        XCTAssertEqual(customProduct.name, "Synthetic Custom")
        XCTAssertEqual(customProduct.sourceRawValue, ProductSource.manual.rawValue)
        XCTAssertEqual(customProduct.imageData, Data([0x43]))
        XCTAssertEqual(try count(WayTaskSchemaV4.Product.self, in: fixture.container), 2)
    }

    func testEquivalentCleanFixturesProduceIdenticalCommandResultsAndState()
        throws {
        let first = try runDeterministicFixture("determinism-a")
        let second = try runDeterministicFixture("determinism-b")

        XCTAssertEqual(first.execution, second.execution)
        XCTAssertEqual(first.state, second.state)
    }

    func testT10SourcesDoNotActivateV4StartupOrBypassCommandAuthority()
        throws {
        let root = repositoryRoot
        let coordinator = try source("WayTask/ProductState/Application/ProductStateCommandCoordinator.swift", root: root)
        let schema = try source("WayTask/Persistence/WayTaskSchema.swift", root: root)
        let startup = try source("WayTask/Persistence/WayTaskStartupPersistence.swift", root: root)
        let app = try source("WayTask/WayTaskApp.swift", root: root)
        let content = try source("WayTask/ContentView.swift", root: root)
        let adapters = try [
            "ShoppingListService.swift",
            "WayTask/Persistence/AddProductSaveCoordinator.swift",
            "WayTask/Persistence/CatalogProductPersistenceService.swift"
        ].map { try source($0, root: root) }.joined(separator: "\n")

        XCTAssertTrue(coordinator.contains("final class ProductStateProductCommandAuthority"))
        XCTAssertFalse(coordinator.contains("import SwiftData"))
        XCTAssertFalse(coordinator.contains("ModelContext("))
        XCTAssertFalse(coordinator.contains("fatalError"))
        XCTAssertTrue(schema.contains("Schema(versionedSchema: WayTaskSchemaV3.self)"))
        XCTAssertFalse(startup.contains("ProductStateProductCommandAuthority"))
        XCTAssertFalse(app.contains("ProductStateProductCommandAuthority"))
        XCTAssertFalse(content.contains("ProductStateProductCommandAuthority"))
        XCTAssertEqual(adapters.components(separatedBy: "func acquireTargetProduct(").count - 1, 3)
        XCTAssertEqual(adapters.components(separatedBy: "func removeFromTargetLibrary(").count - 1, 1)
        XCTAssertFalse(adapters.contains("fatalError"))
    }

    // MARK: Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
    }

    private struct DeterministicState: Equatable {
        let id: UUID
        let revision: UInt64
        let lifecycle: String
        let name: String
    }

    private struct DeterministicResult {
        let execution: ProductStateProductCommandExecution
        let state: DeterministicState
    }

    private let instant = Date(timeIntervalSince1970: 1_780_000_000)

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T10-\(name)-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = makeContext(container)
        return Fixture(
            container: container,
            context: context,
            repositories: ProductStateRepositories(modelContext: context)
        )
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeAuthority(
        _ fixture: Fixture,
        writeState: ProductStateProductCommandWriteState = .writableTarget
    ) -> ProductStateProductCommandAuthority {
        ProductStateProductCommandAuthority(
            repositories: fixture.repositories,
            transactionCoordinator: ProductStateTransactionCoordinator(
                modelContext: fixture.context
            ),
            writeState: writeState
        )
    }

    private func rollbackAuthority(
        _ fixture: Fixture,
        failure: ProductStateTransactionFailure
    ) -> ProductStateProductCommandAuthority {
        ProductStateProductCommandAuthority(
            products: fixture.repositories.products,
            coordinator: ProductStateCommandCoordinator(
                repositories: fixture.repositories
            ),
            writeState: .writableTarget,
            commitPrepared: { prepared in
                fixture.context.rollback()
                return ProductStateTransactionResult(
                    commandResult: .unavailable(
                        commandID: prepared.commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    preparedResult: prepared,
                    disposition: .rolledBack(failure)
                )
            }
        )
    }

    private func acquisition(
        command: Int,
        product: Int,
        name: String,
        imageData: Data? = nil
    ) -> ProductStateProductAcquisitionRequest {
        ProductStateProductAcquisitionRequest(
            commandID: commandID(command),
            productID: productID(product),
            effectiveAt: instant,
            reviewed: true,
            name: name,
            imageData: imageData,
            sourceRawValue: ProductSource.manual.rawValue
        )
    }

    private func editCommand(
        command: Int,
        product: Int,
        revision: UInt64,
        name: String
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedProductRevision(product, revision: revision),
            effectiveAt: instant,
            intent: .editProduct(
                EditProductCommand(productID: productID(product), name: name)
            )
        )
    }

    private func removeCommand(
        command: Int,
        product: Int,
        history: Int,
        revision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedProductRevision(product, revision: revision),
            effectiveAt: instant,
            intent: .removeProductFromLibrary(
                RemoveProductFromLibraryCommand(
                    productID: productID(product),
                    historyEventID: historyID(history),
                    confirmed: true
                )
            )
        )
    }

    private func restoreCommand(
        command: Int,
        product: Int,
        history: Int,
        revision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedProductRevision(product, revision: revision),
            effectiveAt: instant,
            intent: .restoreProductToLibrary(
                RestoreProductToLibraryCommand(
                    productID: productID(product),
                    historyEventID: historyID(history),
                    confirmed: true
                )
            )
        )
    }

    private func expectedProductRevision(
        _ product: Int,
        revision: UInt64
    ) -> ProductStateExpectedRevision {
        ProductStateExpectedRevision(
            revision: ProductStateRevision(
                scope: .product(productID(product)),
                value: revision
            )
        )
    }

    private func listExpectation(
        _ list: Int,
        revision: UInt64
    ) -> ProductStateListRevisionExpectation {
        ProductStateListRevisionExpectation(
            listID: listID(list),
            revision: ProductStateListRevision(value: revision)
        )
    }

    private func makeProduct(
        _ value: Int,
        revision: UInt64,
        lifecycle: ProductLibraryLifecycle = .active,
        name: String = "Synthetic Product",
        barcode: String? = nil,
        catalogID: String? = nil,
        removedAt: Date? = nil
    ) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: revision,
            libraryLifecycleRawValue: lifecycle.rawValue,
            libraryRemovedAt: removedAt,
            name: name,
            barcode: barcode,
            sourceRawValue: ProductSource.manual.rawValue,
            catalogProductIDRawValue: catalogID,
            createdAt: instant.addingTimeInterval(-2_000),
            updatedAt: instant.addingTimeInterval(-1_000)
        )
    }

    private func makeList(
        _ value: Int,
        revision: UInt64,
        purpose: String? = "shopping",
        entries: [WayTaskSchemaV4.ShoppingListEntry]
    ) -> WayTaskSchemaV4.ShoppingList {
        WayTaskSchemaV4.ShoppingList(
            id: uuid(value),
            revision: revision,
            title: "Synthetic List \(value)",
            purposeRawValue: purpose,
            createdAt: instant.addingTimeInterval(-2_000),
            updatedAt: instant.addingTimeInterval(-1_000),
            entries: entries
        )
    }

    private func makeEntry(
        _ value: Int,
        list: Int,
        product: Int,
        productModel: WayTaskSchemaV4.Product
    ) -> WayTaskSchemaV4.ShoppingListEntry {
        WayTaskSchemaV4.ShoppingListEntry(
            id: uuid(value),
            shoppingListID: uuid(list),
            productID: uuid(product),
            lifecycleRawValue: "needed",
            quantity: 1,
            sortOrder: Double(value),
            createdAt: instant.addingTimeInterval(-1_000),
            updatedAt: instant.addingTimeInterval(-1_000),
            product: productModel
        )
    }

    private func makeHistoryEvent(
        _ value: Int,
        product: Int,
        meaning: String,
        command: Int
    ) -> WayTaskSchemaV4.ProductHistoryEvent {
        WayTaskSchemaV4.ProductHistoryEvent(
            id: uuid(value),
            productID: uuid(product),
            meaningRawValue: meaning,
            commandID: uuid(command),
            provenanceRawValue: "userCommand",
            occurredAt: instant.addingTimeInterval(-100)
        )
    }

    private func makeSession(
        _ value: Int,
        lifecycle: ShoppingSessionLifecycle,
        product: Int? = nil,
        sourceEntry: Int? = nil
    ) -> WayTaskSchemaV4.ShoppingSession {
        let sessionID = uuid(value)
        let snapshotID = uuid(value + 1_000)
        let line = WayTaskSchemaV4.ShoppingSessionLine(
            id: uuid(value + 2_000),
            sessionID: sessionID,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "synthetic",
            sourceEntryID: sourceEntry.map(uuid),
            productID: product.map(uuid),
            sortOrder: 0,
            productNameSnapshot: "Synthetic Session Snapshot",
            quantitySnapshot: 1,
            executionStateRawValue: ShoppingSessionExecutionState.remaining.rawValue
        )
        return WayTaskSchemaV4.ShoppingSession(
            id: sessionID,
            sourceListID: nil,
            sourceRevision: nil,
            sourceRevisionProvenanceRawValue: "synthetic",
            revision: 1,
            lifecycleRawValue: lifecycle.rawValue,
            migrationConditionRawValue: ShoppingSessionMigrationCondition.native.rawValue,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "synthetic:\(value)",
            startedAt: instant.addingTimeInterval(-500),
            activationStartedAt: instant.addingTimeInterval(-500),
            lastActivityAt: instant.addingTimeInterval(-100),
            expiredAt: lifecycle == .expired ? instant.addingTimeInterval(-50) : nil,
            expirationPolicyVersion: 1,
            lines: [line]
        )
    }

    private func fetchProduct(
        in container: ModelContainer,
        id value: Int
    ) throws -> WayTaskSchemaV4.Product {
        let context = makeContext(container)
        let id = uuid(value)
        return try XCTUnwrap(try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>(
                predicate: #Predicate { $0.id == id }
            )
        ).first)
    }

    private func count<T: PersistentModel>(
        _ type: T.Type,
        in container: ModelContainer
    ) throws -> Int {
        try makeContext(container).fetchCount(FetchDescriptor<T>())
    }

    private func runDeterministicFixture(
        _ name: String
    ) throws -> DeterministicResult {
        let fixture = try makeFixture(name)
        let execution = makeAuthority(fixture).acquire(
            acquisition(command: 160, product: 161, name: "Equivalent Synthetic")
        )
        let stored = try fetchProduct(in: fixture.container, id: 161)
        return DeterministicResult(
            execution: execution,
            state: DeterministicState(
                id: stored.id,
                revision: stored.revision,
                lifecycle: stored.libraryLifecycleRawValue,
                name: stored.name
            )
        )
    }

    private func source(_ relativePath: String, root: URL? = nil) throws -> String {
        try String(
            contentsOf: (root ?? repositoryRoot).appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(value))
    }

    private func commandID(_ value: Int) -> ProductStateCommandID {
        ProductStateCommandID(rawValue: uuid(value))
    }

    private func historyID(_ value: Int) -> ProductStateHistoryEventID {
        ProductStateHistoryEventID(rawValue: uuid(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
