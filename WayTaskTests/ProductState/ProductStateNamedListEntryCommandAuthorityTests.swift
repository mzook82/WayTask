import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateNamedListEntryCommandAuthorityTests: XCTestCase {
    func testWriteGateAndOperationGateRejectBeforeRepositoryMutation()
        throws {
        let fixture = try makeFixture("write-gate")
        let create = createListCommand(command: 1, list: 2)

        let incomplete = makeAuthority(
            fixture,
            writeState: .migrationIncomplete
        ).createNamedList(create)
        let nonDurable = makeAuthority(
            fixture,
            writeState: .nonDurable
        ).createNamedList(create)
        let wrongOperation = makeAuthority(fixture).removeEntry(create)

        XCTAssertEqual(incomplete.outcome, .unavailable(.migrationIncomplete))
        XCTAssertEqual(incomplete.diagnostic.failure, .migrationIncomplete)
        XCTAssertEqual(nonDurable.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(nonDurable.diagnostic.failure, .nonDurable)
        XCTAssertEqual(wrongOperation.outcome, .validationFailure)
        XCTAssertFalse(incomplete.claimsDurableSuccess)
        XCTAssertFalse(nonDurable.claimsDurableSuccess)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingList.self, fixture), 0)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testCreateAndRenameNamedListPreserveIdentityAndAdvanceOnce()
        throws {
        let fixture = try makeFixture("create-rename")
        let authority = makeAuthority(fixture)

        let created = authority.createNamedList(
            createListCommand(command: 10, list: 11, title: "  Named  ")
        )
        guard case let .listCreated(createSummary) = created.outcome else {
            return XCTFail("Expected list creation")
        }
        XCTAssertEqual(createSummary.listID, listID(11))
        XCTAssertEqual(createSummary.listRevisionBefore.value, 0)
        XCTAssertEqual(createSummary.listRevisionAfter.value, 1)
        XCTAssertTrue(createSummary.historyEventIDs.isEmpty)
        XCTAssertNil(createSummary.entry)

        let same = authority.createNamedList(
            createListCommand(command: 12, list: 11, title: "Named")
        )
        XCTAssertEqual(
            same.outcome,
            .noOp(
                listID: listID(11),
                entry: nil,
                listRevision: ProductStateListRevision(value: 1)
            )
        )

        let renamed = authority.renameNamedList(
            renameListCommand(command: 13, list: 11, revision: 1, title: "Renamed")
        )
        guard case let .listRenamed(renameSummary) = renamed.outcome else {
            return XCTFail("Expected list rename")
        }
        XCTAssertEqual(renameSummary.listRevisionBefore.value, 1)
        XCTAssertEqual(renameSummary.listRevisionAfter.value, 2)

        let stored = try fetchList(11, fixture)
        XCTAssertEqual(stored.id, uuid(11))
        XCTAssertEqual(stored.title, "Renamed")
        XCTAssertEqual(stored.revision, 2)
        XCTAssertTrue(stored.entries.isEmpty)

        let stale = authority.renameNamedList(
            renameListCommand(command: 14, list: 11, revision: 1, title: "No")
        )
        XCTAssertEqual(stale.outcome, .conflict(.staleRevision))
        XCTAssertEqual(stored.title, "Renamed")
        XCTAssertEqual(stored.revision, 2)
    }

    func testArchivePurposesCannotBecomeMutableNamedLists() throws {
        let fixture = try makeFixture("archive-purpose")
        let authority = makeAuthority(fixture)

        for (offset, purpose) in ["completed", "recent"].enumerated() {
            let result = authority.createNamedList(
                createListCommand(
                    command: 20 + offset,
                    list: 30 + offset,
                    purpose: purpose
                )
            )
            XCTAssertEqual(result.outcome, .validationFailure)
        }
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingList.self, fixture), 0)

        let archive = makeList(40, revision: 1, purpose: "completed")
        fixture.repositories.shopping.stageInsertion(of: archive)
        try fixture.context.save()
        let rename = authority.renameNamedList(
            renameListCommand(command: 41, list: 40, revision: 1, title: "No")
        )
        XCTAssertEqual(rename.outcome, .validationFailure)
        XCTAssertEqual(archive.title, "List 40")
        XCTAssertEqual(archive.revision, 1)
    }

    func testAddEntryCommitsExactIdentityRevisionHistoryAndCompatibility()
        throws {
        let fixture = try makeFixture("add")
        let product = makeProduct(50)
        let list = makeList(51, revision: 4)
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: list)
        try fixture.context.save()

        let authority = makeAuthority(fixture)
        let compatibility = ProductStateCompatibilityAdapter(
            shopping: fixture.repositories.shopping
        )
        let result = ShoppingListService().addTargetEntry(
            addCommand(
                command: 52,
                list: 51,
                product: 50,
                entry: 53,
                history: 54,
                revision: 4,
                quantity: 2.5,
                unit: "kg",
                note: "PRIVATE NOTE",
                order: 7
            ),
            using: authority,
            compatibility: compatibility
        )

        guard case let .entryAdded(summary) = result.command.outcome else {
            return XCTFail("Expected entry addition")
        }
        XCTAssertEqual(summary.entry, identity(entry: 53, list: 51, product: 50))
        XCTAssertEqual(summary.listRevisionBefore.value, 4)
        XCTAssertEqual(summary.listRevisionAfter.value, 5)
        XCTAssertEqual(summary.historyEventIDs, [historyID(54)])
        XCTAssertTrue(result.command.claimsDurableSuccess)
        XCTAssertEqual(
            result.compatibilityOutput,
            ProductStateLegacyEntryCompatibilityOutput(
                listID: uuid(51),
                listRevision: 5,
                entryID: uuid(53),
                productID: uuid(50),
                membership: .presentNeeded,
                legacyEntryIsChecked: false,
                legacyShoppingItemIsCompleted: nil
            )
        )

        let stored = try fetchEntry(53, list: 51, fixture)
        XCTAssertEqual(stored.id, uuid(53))
        XCTAssertEqual(stored.shoppingListID, uuid(51))
        XCTAssertEqual(stored.productID, uuid(50))
        XCTAssertEqual(stored.lifecycleRawValue, "needed")
        XCTAssertEqual(stored.quantity, 2.5)
        XCTAssertEqual(stored.unitRawValue, "kg")
        XCTAssertEqual(stored.note, "PRIVATE NOTE")
        XCTAssertEqual(stored.sortOrder, 7)
        XCTAssertEqual(try fetchList(51, fixture).revision, 5)
        let event = try XCTUnwrap(try historyEvents(fixture).first)
        XCTAssertEqual(event.id, uuid(54))
        XCTAssertEqual(event.productID, uuid(50))
        XCTAssertEqual(event.sourceListID, uuid(51))
        XCTAssertEqual(event.sourceEntryID, uuid(53))
        XCTAssertEqual(event.commandID, uuid(52))
        XCTAssertEqual(event.meaningRawValue, "needAdded")
    }

    func testAddExistingNeededIsDeterministicNoOpWithAuthoritativeEntry()
        throws {
        let fixture = try makeFixture("add-noop")
        let product = makeProduct(60)
        let entry = makeEntry(63, list: 61, product: 60, model: product)
        let list = makeList(61, revision: 8, entries: [entry])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: list)
        try fixture.context.save()

        let execution = makeAuthority(fixture).addEntry(
            addCommand(
                command: 64,
                list: 61,
                product: 60,
                entry: 62,
                history: 65,
                revision: 8
            )
        )

        XCTAssertEqual(
            execution.outcome,
            .existingNeeded(
                identity: identity(entry: 63, list: 61, product: 60),
                listRevision: ProductStateListRevision(value: 8)
            )
        )
        XCTAssertEqual(execution.diagnostic.requestedEntryID, uuid(62))
        XCTAssertEqual(execution.diagnostic.authoritativeEntryID, uuid(63))
        XCTAssertEqual(execution.diagnostic.durability, .noCommitRequired)
        XCTAssertFalse(execution.claimsDurableSuccess)
        XCTAssertEqual(list.revision, 8)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingListEntry.self, fixture), 1)
        XCTAssertTrue(try historyEvents(fixture).isEmpty)
    }

    func testAddResolvedRequiresExplicitReopenAndReopenPreservesEntryUUID()
        throws {
        let fixture = try makeFixture("reopen")
        let product = makeProduct(70)
        let entry = makeEntry(
            73,
            list: 71,
            product: 70,
            model: product,
            lifecycle: "resolved",
            reason: .alreadyHave
        )
        let list = makeList(71, revision: 3, entries: [entry])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: list)
        try fixture.context.save()
        let authority = makeAuthority(fixture)

        let add = authority.addEntry(
            addCommand(
                command: 74,
                list: 71,
                product: 70,
                entry: 72,
                history: 75,
                revision: 3
            )
        )
        XCTAssertEqual(
            add.outcome,
            .reopenRequired(
                identity: identity(entry: 73, list: 71, product: 70),
                listRevision: ProductStateListRevision(value: 3)
            )
        )
        XCTAssertEqual(entry.lifecycleRawValue, "resolved")
        XCTAssertEqual(entry.resolutionReasonRawValue, "alreadyHave")
        XCTAssertEqual(list.revision, 3)
        XCTAssertTrue(try historyEvents(fixture).isEmpty)

        let reopen = authority.reopenEntry(
            reopenCommand(
                command: 76,
                list: 71,
                product: 70,
                entry: 73,
                history: 77,
                revision: 3
            )
        )
        guard case let .entryReopened(summary) = reopen.outcome else {
            return XCTFail("Expected explicit Reopen")
        }
        XCTAssertEqual(summary.entry?.id, entryID(73))
        XCTAssertEqual(summary.listRevisionAfter.value, 4)
        XCTAssertEqual(summary.historyEventIDs, [historyID(77)])
        XCTAssertEqual(entry.id, uuid(73))
        XCTAssertEqual(entry.lifecycleRawValue, "needed")
        XCTAssertNil(entry.resolutionReasonRawValue)
        XCTAssertEqual(list.revision, 4)
        XCTAssertEqual(try historyEvents(fixture).map(\.meaningRawValue), ["needReopened"])
    }

    func testUpdateEntryFieldsAdvancesExactlyOnceAndUnchangedIsNoOp()
        throws {
        let fixture = try seededEntryFixture("update", listRevision: 5)
        let authority = makeAuthority(fixture)

        let updated = authority.updateEntry(
            updateCommand(
                command: 80,
                list: 2,
                product: 1,
                entry: 3,
                revision: 5,
                quantity: 3,
                unit: "box",
                note: "PRIVATE UPDATED NOTE",
                order: 9
            )
        )
        guard case let .entryUpdated(summary) = updated.outcome else {
            return XCTFail("Expected update")
        }
        XCTAssertEqual(summary.listRevisionBefore.value, 5)
        XCTAssertEqual(summary.listRevisionAfter.value, 6)
        XCTAssertTrue(summary.historyEventIDs.isEmpty)
        let entry = try fetchEntry(3, list: 2, fixture)
        XCTAssertEqual(entry.quantity, 3)
        XCTAssertEqual(entry.unitRawValue, "box")
        XCTAssertEqual(entry.note, "PRIVATE UPDATED NOTE")
        XCTAssertEqual(entry.sortOrder, 9)

        let noOp = authority.updateEntry(
            updateCommand(
                command: 81,
                list: 2,
                product: 1,
                entry: 3,
                revision: 6,
                quantity: 3,
                unit: "box",
                note: "PRIVATE UPDATED NOTE",
                order: 9
            )
        )
        XCTAssertEqual(
            noOp.outcome,
            .noOp(
                listID: listID(2),
                entry: identity(entry: 3, list: 2, product: 1),
                listRevision: ProductStateListRevision(value: 6)
            )
        )
        XCTAssertEqual(try fetchList(2, fixture).revision, 6)
        XCTAssertTrue(try historyEvents(fixture).isEmpty)
    }

    func testResolveSupportsOnlyApprovedUserReasonsAndAppendsExactEvent()
        throws {
        for (offset, reason) in [
            ShoppingListResolutionReason.alreadyHave,
            .noLongerNeeded
        ].enumerated() {
            let fixture = try seededEntryFixture(
                "resolve-\(offset)",
                listRevision: 10
            )
            let execution = makeAuthority(fixture).resolveEntry(
                resolveCommand(
                    command: 90 + offset,
                    list: 2,
                    product: 1,
                    entry: 3,
                    history: 100 + offset,
                    revision: 10,
                    reason: reason
                )
            )
            guard case let .entryResolved(summary, storedReason) = execution.outcome else {
                return XCTFail("Expected resolution")
            }
            XCTAssertEqual(storedReason, reason)
            XCTAssertEqual(summary.listRevisionAfter.value, 11)
            XCTAssertEqual(summary.historyEventIDs, [historyID(100 + offset)])
            let entry = try fetchEntry(3, list: 2, fixture)
            XCTAssertEqual(entry.id, uuid(3))
            XCTAssertEqual(entry.lifecycleRawValue, "resolved")
            XCTAssertEqual(entry.resolutionReasonRawValue, reason.rawValue)
            XCTAssertEqual(entry.resolutionEffectiveAt, instant)
            XCTAssertEqual(entry.resolutionProvenanceRawValue, "userCommand")
            XCTAssertEqual(entry.resolutionCommandID, uuid(90 + offset))
            let event = try XCTUnwrap(try historyEvents(fixture).first)
            XCTAssertEqual(event.meaningRawValue, "needResolved")
            XCTAssertEqual(event.resolutionReasonRawValue, reason.rawValue)
        }

        for (offset, reason) in [
            ShoppingListResolutionReason.purchased,
            .legacyUnknown
        ].enumerated() {
            let fixture = try seededEntryFixture(
                "resolve-reject-\(offset)",
                listRevision: 4
            )
            let result = makeAuthority(fixture).resolveEntry(
                resolveCommand(
                    command: 110 + offset,
                    list: 2,
                    product: 1,
                    entry: 3,
                    history: 120 + offset,
                    revision: 4,
                    reason: reason
                )
            )
            XCTAssertEqual(result.outcome, .validationFailure)
            XCTAssertEqual(try fetchEntry(3, list: 2, fixture).lifecycleRawValue, "needed")
            XCTAssertEqual(try fetchList(2, fixture).revision, 4)
            XCTAssertTrue(try historyEvents(fixture).isEmpty)
        }
    }

    func testRemoveAffectsOnlyOneNamedListAndRetryIsAbsentNoOp()
        throws {
        let fixture = try makeFixture("one-list-remove")
        let product = makeProduct(130)
        let firstEntry = makeEntry(133, list: 131, product: 130, model: product)
        let secondEntry = makeEntry(134, list: 132, product: 130, model: product)
        let first = makeList(131, revision: 6, entries: [firstEntry])
        let second = makeList(132, revision: 9, entries: [secondEntry])
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(of: first)
        fixture.repositories.shopping.stageInsertion(of: second)
        try fixture.context.save()
        let authority = makeAuthority(fixture)

        let removed = authority.removeEntry(
            removeCommand(
                command: 135,
                list: 131,
                product: 130,
                entry: 133,
                history: 136,
                revision: 6
            )
        )
        guard case let .entryRemoved(summary) = removed.outcome else {
            return XCTFail("Expected one-list removal")
        }
        XCTAssertEqual(summary.listRevisionAfter.value, 7)
        XCTAssertEqual(summary.historyEventIDs, [historyID(136)])
        XCTAssertTrue(try entries(list: 131, fixture).isEmpty)
        XCTAssertEqual(try entries(list: 132, fixture).map(\.id), [uuid(134)])
        XCTAssertEqual(try fetchList(132, fixture).revision, 9)
        XCTAssertEqual(try fetchProduct(130, fixture).libraryLifecycleRawValue, "active")

        let retry = authority.removeEntry(
            removeCommand(
                command: 137,
                list: 131,
                product: 130,
                entry: 133,
                history: 138,
                revision: 7
            )
        )
        XCTAssertEqual(
            retry.outcome,
            .noOp(
                listID: listID(131),
                entry: identity(entry: 133, list: 131, product: 130),
                listRevision: ProductStateListRevision(value: 7)
            )
        )
        XCTAssertEqual(try historyEvents(fixture).map(\.id), [uuid(136)])
    }

    func testUniquenessRejectsDuplicateRowsAndSerializedRetryCannotDuplicate()
        throws {
        let duplicateFixture = try makeFixture("duplicates")
        let duplicateProduct = makeProduct(140)
        let duplicates = [141, 142].map {
            makeEntry($0, list: 143, product: 140, model: duplicateProduct)
        }
        duplicateFixture.repositories.products.stageInsertion(of: duplicateProduct)
        duplicateFixture.repositories.shopping.stageInsertion(
            of: makeList(143, revision: 2, entries: duplicates)
        )
        try duplicateFixture.context.save()
        let rejected = makeAuthority(duplicateFixture).addEntry(
            addCommand(
                command: 144,
                list: 143,
                product: 140,
                entry: 145,
                history: 146,
                revision: 2
            )
        )
        XCTAssertEqual(rejected.outcome, .conflict(.ambiguousIdentity))
        XCTAssertEqual(try entries(list: 143, duplicateFixture).count, 2)
        XCTAssertTrue(try historyEvents(duplicateFixture).isEmpty)

        let retryFixture = try makeFixture("serialized-retry")
        let product = makeProduct(150)
        retryFixture.repositories.products.stageInsertion(of: product)
        retryFixture.repositories.shopping.stageInsertion(
            of: makeList(151, revision: 1)
        )
        try retryFixture.context.save()
        let authority = makeAuthority(retryFixture)
        let first = authority.addEntry(
            addCommand(
                command: 152,
                list: 151,
                product: 150,
                entry: 153,
                history: 154,
                revision: 1
            )
        )
        guard case .entryAdded = first.outcome else {
            return XCTFail("Expected first serialized add")
        }
        let retry = authority.addEntry(
            addCommand(
                command: 155,
                list: 151,
                product: 150,
                entry: 156,
                history: 157,
                revision: 2
            )
        )
        XCTAssertEqual(
            retry.outcome,
            .existingNeeded(
                identity: identity(entry: 153, list: 151, product: 150),
                listRevision: ProductStateListRevision(value: 2)
            )
        )
        XCTAssertEqual(try entries(list: 151, retryFixture).map(\.id), [uuid(153)])
        XCTAssertEqual(try historyEvents(retryFixture).map(\.id), [uuid(154)])
    }

    func testActiveSessionProtectsCapturedEntryAcrossEveryMutation()
        throws {
        let fixture = try seededEntryFixture("session-protection", listRevision: 4)
        fixture.repositories.sessions.stageInsertion(
            of: makeSession(160, sourceEntry: 3)
        )
        try fixture.context.save()
        let authority = makeAuthority(fixture)

        let results = [
            authority.updateEntry(
                updateCommand(
                    command: 161, list: 2, product: 1, entry: 3,
                    revision: 4, quantity: 2, unit: nil, note: nil, order: 0
                )
            ),
            authority.resolveEntry(
                resolveCommand(
                    command: 162, list: 2, product: 1, entry: 3,
                    history: 163, revision: 4, reason: .alreadyHave
                )
            ),
            authority.reopenEntry(
                reopenCommand(
                    command: 164, list: 2, product: 1, entry: 3,
                    history: 165, revision: 4
                )
            ),
            authority.removeEntry(
                removeCommand(
                    command: 166, list: 2, product: 1, entry: 3,
                    history: 167, revision: 4
                )
            )
        ]
        XCTAssertTrue(results.allSatisfy { $0.outcome == .conflict(.activeSession) })
        XCTAssertEqual(try fetchList(2, fixture).revision, 4)
        XCTAssertEqual(try entries(list: 2, fixture).map(\.id), [uuid(3)])
        XCTAssertEqual(try fetchEntry(3, list: 2, fixture).lifecycleRawValue, "needed")
        XCTAssertTrue(try historyEvents(fixture).isEmpty)
    }

    func testSaveFailuresRollBackListEntryRevisionAndHistoryTogether()
        throws {
        let createFixture = try makeFixture("rollback-create")
        let create = rollbackAuthority(createFixture).createNamedList(
            createListCommand(command: 170, list: 171)
        )
        XCTAssertEqual(create.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(create.diagnostic.failure, .saveFailed)
        XCTAssertEqual(try count(WayTaskSchemaV4.ShoppingList.self, createFixture), 0)

        let addFixture = try makeFixture("rollback-add")
        let product = makeProduct(180)
        addFixture.repositories.products.stageInsertion(of: product)
        addFixture.repositories.shopping.stageInsertion(
            of: makeList(181, revision: 5)
        )
        try addFixture.context.save()
        let add = rollbackAuthority(addFixture).addEntry(
            addCommand(
                command: 182, list: 181, product: 180, entry: 183,
                history: 184, revision: 5
            )
        )
        XCTAssertEqual(add.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(add.diagnostic.failure, .saveFailed)
        XCTAssertEqual(try fetchList(181, addFixture).revision, 5)
        XCTAssertTrue(try entries(list: 181, addFixture).isEmpty)
        XCTAssertTrue(try historyEvents(addFixture).isEmpty)

        let resolveFixture = try seededEntryFixture("rollback-resolve", listRevision: 8)
        let resolve = rollbackAuthority(resolveFixture).resolveEntry(
            resolveCommand(
                command: 190, list: 2, product: 1, entry: 3,
                history: 191, revision: 8, reason: .noLongerNeeded
            )
        )
        XCTAssertEqual(resolve.outcome, .unavailable(.durableAuthorityUnavailable))
        XCTAssertEqual(try fetchList(2, resolveFixture).revision, 8)
        XCTAssertEqual(
            try fetchEntry(3, list: 2, resolveFixture).lifecycleRawValue,
            "needed"
        )
        XCTAssertTrue(try historyEvents(resolveFixture).isEmpty)
    }

    func testCompatibilityIsExactListOneWayDeterministicAndNeverGlobal()
        throws {
        let fixture = try seededEntryFixture("compatibility", listRevision: 3)
        let adapter = ProductStateCompatibilityAdapter(
            shopping: fixture.repositories.shopping
        )
        let authority = makeAuthority(fixture)
        let service = ShoppingListService()

        let resolved = service.resolveTargetEntry(
            resolveCommand(
                command: 200, list: 2, product: 1, entry: 3,
                history: 201, revision: 3, reason: .alreadyHave
            ),
            using: authority,
            compatibility: adapter
        )
        XCTAssertEqual(resolved.compatibilityOutput?.membership, .presentResolved)
        XCTAssertEqual(resolved.compatibilityOutput?.legacyEntryIsChecked, true)
        XCTAssertNil(resolved.compatibilityOutput?.legacyShoppingItemIsCompleted)

        let first = try XCTUnwrap(
            adapter.deriveEntryOutput(from: resolved.command)
        )
        let second = try XCTUnwrap(
            adapter.deriveEntryOutput(from: resolved.command)
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.listID, uuid(2))
        XCTAssertEqual(first.entryID, uuid(3))
        XCTAssertEqual(first.productID, uuid(1))
        XCTAssertEqual(adapter.counters.targetReadCount, 3)
        XCTAssertEqual(adapter.counters.outputEmissionCount, 3)
        XCTAssertEqual(adapter.counters.legacyReadCount, 0)
        XCTAssertEqual(adapter.counters.legacyWriteCount, 0)
        XCTAssertEqual(adapter.counters.reverseSynchronizationCount, 0)

        let removed = service.removeTargetEntry(
            removeCommand(
                command: 202, list: 2, product: 1, entry: 3,
                history: 203, revision: 4
            ),
            using: authority,
            compatibility: adapter
        )
        XCTAssertEqual(removed.compatibilityOutput?.membership, .absent)
        XCTAssertNil(removed.compatibilityOutput?.legacyEntryIsChecked)
        XCTAssertNil(removed.compatibilityOutput?.legacyShoppingItemIsCompleted)
    }

    func testDiagnosticsAreDeterministicBoundedAndPrivacySafe() throws {
        let fixture = try makeFixture("diagnostics")
        let command = createListCommand(
            command: 210,
            list: 211,
            title: "PRIVATE LIST TITLE",
            purpose: "private-purpose"
        )
        let first = makeAuthority(
            fixture,
            writeState: .nonDurable
        ).createNamedList(command)
        let second = makeAuthority(
            fixture,
            writeState: .nonDurable
        ).createNamedList(command)
        XCTAssertEqual(first.diagnostic, second.diagnostic)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(first.diagnostic)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("PRIVATE LIST TITLE"))
        XCTAssertFalse(encoded.contains("private-purpose"))
        XCTAssertFalse(encoded.contains("barcode"))
        XCTAssertLessThan(encoded.utf8.count, 1_024)
        XCTAssertTrue(encoded.contains(uuid(210).uuidString))
        XCTAssertTrue(encoded.contains(uuid(211).uuidString))
    }

    func testEquivalentCleanFixturesProduceIdenticalStateAndOutput()
        throws {
        let first = try deterministicRun("repeat-a")
        let second = try deterministicRun("repeat-b")
        XCTAssertEqual(first.execution, second.execution)
        XCTAssertEqual(first.output, second.output)
        XCTAssertEqual(first.state, second.state)
    }

    func testT11ScopeHasNoListLifecycleStartupReverseSyncOrDefaultStore()
        throws {
        let root = repositoryRoot
        let coordinator = try source(
            "WayTask/ProductState/Application/ProductStateCommandCoordinator.swift",
            root
        )
        let marker = try XCTUnwrap(
            coordinator.range(
                of: "// MARK: - T-11 durable Named List and Entry command authority"
            )
        )
        let t11 = String(coordinator[marker.lowerBound...])
        let compatibility = try source(
            "WayTask/ProductState/Persistence/ProductStateCompatibilityAdapter.swift",
            root
        )
        let service = try source("ShoppingListService.swift", root)
        let startup = try source(
            "WayTask/Persistence/WayTaskStartupPersistence.swift",
            root
        )
        let app = try source("WayTask/WayTaskApp.swift", root)
        let schema = try source("WayTask/Persistence/WayTaskSchema.swift", root)

        XCTAssertTrue(t11.contains("final class ProductStateNamedListCommandAuthority"))
        XCTAssertFalse(t11.contains("removeNamedList"))
        XCTAssertFalse(t11.contains("restoreNamedList"))
        XCTAssertFalse(t11.contains("closeNamedList"))
        XCTAssertFalse(t11.contains("deleteNamedList"))
        XCTAssertFalse(t11.contains("import SwiftData"))
        XCTAssertFalse(t11.contains("ModelContext"))
        XCTAssertFalse(t11.contains("fatalError"))
        XCTAssertFalse(compatibility.contains("ModelContext"))
        XCTAssertFalse(compatibility.contains("ModelContainer"))
        XCTAssertFalse(compatibility.contains("isCompleted ="))
        XCTAssertFalse(compatibility.contains("syncTarget"))
        XCTAssertTrue(compatibility.contains("legacyWriteCount: 0"))
        XCTAssertTrue(service.contains("func createTargetNamedList("))
        XCTAssertTrue(service.contains("func removeTargetEntry("))
        XCTAssertFalse(startup.contains("ProductStateNamedListCommandAuthority"))
        XCTAssertFalse(app.contains("ProductStateNamedListCommandAuthority"))
        XCTAssertTrue(schema.contains("Schema(versionedSchema: WayTaskSchemaV3.self)"))
        XCTAssertFalse(schema.contains("ProductStateNamedListCommandAuthority"))
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
    }

    private struct DeterministicState: Equatable {
        let listRevision: UInt64
        let entryID: UUID
        let lifecycle: String
        let eventIDs: [UUID]
    }

    private struct DeterministicResult {
        let execution: ProductStateNamedListCommandExecution
        let output: ProductStateLegacyEntryCompatibilityOutput?
        let state: DeterministicState
    }

    private let instant = Date(timeIntervalSince1970: 1_780_100_000)

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T11-\(name)-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return Fixture(
            container: container,
            context: context,
            repositories: ProductStateRepositories(modelContext: context)
        )
    }

    private func seededEntryFixture(
        _ name: String,
        listRevision: UInt64
    ) throws -> Fixture {
        let fixture = try makeFixture(name)
        let product = makeProduct(1)
        let entry = makeEntry(3, list: 2, product: 1, model: product)
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(
            of: makeList(2, revision: listRevision, entries: [entry])
        )
        try fixture.context.save()
        return fixture
    }

    private func makeAuthority(
        _ fixture: Fixture,
        writeState: ProductStateNamedListCommandWriteState = .writableTarget
    ) -> ProductStateNamedListCommandAuthority {
        ProductStateNamedListCommandAuthority(
            repositories: fixture.repositories,
            transactionCoordinator: ProductStateTransactionCoordinator(
                modelContext: fixture.context
            ),
            writeState: writeState
        )
    }

    private func rollbackAuthority(
        _ fixture: Fixture
    ) -> ProductStateNamedListCommandAuthority {
        ProductStateNamedListCommandAuthority(
            shopping: fixture.repositories.shopping,
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
                    disposition: .rolledBack(.saveFailed)
                )
            }
        )
    }

    private func createListCommand(
        command: Int,
        list: Int,
        title: String = "List",
        purpose: String? = "shopping"
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: nil,
            effectiveAt: instant,
            intent: .createNamedList(
                CreateNamedListCommand(
                    listID: listID(list),
                    title: title,
                    purposeRawValue: purpose
                )
            )
        )
    }

    private func renameListCommand(
        command: Int,
        list: Int,
        revision: UInt64,
        title: String
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .renameNamedList(
                RenameNamedListCommand(listID: listID(list), title: title)
            )
        )
    }

    private func addCommand(
        command: Int,
        list: Int,
        product: Int,
        entry: Int,
        history: Int,
        revision: UInt64,
        quantity: Double = 1,
        unit: String? = nil,
        note: String? = nil,
        order: Double = 0
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .addProductToList(
                AddProductToListCommand(
                    entry: identity(entry: entry, list: list, product: product),
                    historyEventID: historyID(history),
                    quantity: quantity,
                    unitRawValue: unit,
                    note: note,
                    sortOrder: order
                )
            )
        )
    }

    private func updateCommand(
        command: Int,
        list: Int,
        product: Int,
        entry: Int,
        revision: UInt64,
        quantity: Double,
        unit: String?,
        note: String?,
        order: Double
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .updateListEntry(
                UpdateListEntryCommand(
                    entry: identity(entry: entry, list: list, product: product),
                    quantity: quantity,
                    unitRawValue: unit,
                    note: note,
                    sortOrder: order
                )
            )
        )
    }

    private func resolveCommand(
        command: Int,
        list: Int,
        product: Int,
        entry: Int,
        history: Int,
        revision: UInt64,
        reason: ShoppingListResolutionReason
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .resolveListNeed(
                ResolveListNeedCommand(
                    entry: identity(entry: entry, list: list, product: product),
                    historyEventID: historyID(history),
                    reason: reason
                )
            )
        )
    }

    private func reopenCommand(
        command: Int,
        list: Int,
        product: Int,
        entry: Int,
        history: Int,
        revision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .reopenListNeed(
                ReopenListNeedCommand(
                    entry: identity(entry: entry, list: list, product: product),
                    historyEventID: historyID(history)
                )
            )
        )
    }

    private func removeCommand(
        command: Int,
        list: Int,
        product: Int,
        entry: Int,
        history: Int,
        revision: UInt64
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedListRevision(list, revision),
            effectiveAt: instant,
            intent: .removeProductFromNamedList(
                RemoveProductFromNamedListCommand(
                    entry: identity(entry: entry, list: list, product: product),
                    historyEventID: historyID(history)
                )
            )
        )
    }

    private func expectedListRevision(
        _ list: Int,
        _ revision: UInt64
    ) -> ProductStateExpectedRevision {
        ProductStateExpectedRevision(
            revision: ProductStateRevision(
                scope: .list(listID(list)),
                value: revision
            )
        )
    }

    private func makeProduct(_ value: Int) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: 1,
            libraryLifecycleRawValue: ProductLibraryLifecycle.active.rawValue,
            name: "Synthetic Product \(value)",
            sourceRawValue: ProductSource.manual.rawValue,
            createdAt: instant.addingTimeInterval(-2_000),
            updatedAt: instant.addingTimeInterval(-1_000)
        )
    }

    private func makeList(
        _ value: Int,
        revision: UInt64,
        purpose: String? = "shopping",
        entries: [WayTaskSchemaV4.ShoppingListEntry] = []
    ) -> WayTaskSchemaV4.ShoppingList {
        WayTaskSchemaV4.ShoppingList(
            id: uuid(value),
            revision: revision,
            title: "List \(value)",
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
        model: WayTaskSchemaV4.Product,
        lifecycle: String = "needed",
        reason: ShoppingListResolutionReason? = nil
    ) -> WayTaskSchemaV4.ShoppingListEntry {
        WayTaskSchemaV4.ShoppingListEntry(
            id: uuid(value),
            shoppingListID: uuid(list),
            productID: uuid(product),
            lifecycleRawValue: lifecycle,
            resolutionReasonRawValue: reason?.rawValue,
            resolutionEffectiveAt: reason == nil ? nil : instant.addingTimeInterval(-500),
            resolutionProvenanceRawValue: reason == nil ? nil : "userCommand",
            resolutionCommandID: reason == nil ? nil : uuid(value + 10_000),
            quantity: 1,
            sortOrder: 0,
            createdAt: instant.addingTimeInterval(-1_000),
            updatedAt: instant.addingTimeInterval(-500),
            product: model
        )
    }

    private func makeSession(
        _ value: Int,
        sourceEntry: Int
    ) -> WayTaskSchemaV4.ShoppingSession {
        let sessionID = uuid(value)
        let snapshotID = uuid(value + 1_000)
        let line = WayTaskSchemaV4.ShoppingSessionLine(
            id: uuid(value + 2_000),
            sessionID: sessionID,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "synthetic",
            sourceEntryID: uuid(sourceEntry),
            productID: uuid(1),
            sortOrder: 0,
            productNameSnapshot: "Synthetic",
            quantitySnapshot: 1,
            executionStateRawValue: ShoppingSessionExecutionState.remaining.rawValue
        )
        return WayTaskSchemaV4.ShoppingSession(
            id: sessionID,
            sourceListID: uuid(2),
            sourceRevision: 4,
            sourceRevisionProvenanceRawValue: "synthetic",
            revision: 1,
            lifecycleRawValue: ShoppingSessionLifecycle.active.rawValue,
            migrationConditionRawValue: ShoppingSessionMigrationCondition.native.rawValue,
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "synthetic",
            startedAt: instant.addingTimeInterval(-500),
            activationStartedAt: instant.addingTimeInterval(-500),
            lastActivityAt: instant,
            expirationPolicyVersion: 1,
            lines: [line]
        )
    }

    private func deterministicRun(_ name: String) throws -> DeterministicResult {
        let fixture = try makeFixture(name)
        let product = makeProduct(220)
        fixture.repositories.products.stageInsertion(of: product)
        fixture.repositories.shopping.stageInsertion(
            of: makeList(221, revision: 7)
        )
        try fixture.context.save()
        let authority = makeAuthority(fixture)
        let adapter = ProductStateCompatibilityAdapter(
            shopping: fixture.repositories.shopping
        )
        let result = ShoppingListService().addTargetEntry(
            addCommand(
                command: 222, list: 221, product: 220, entry: 223,
                history: 224, revision: 7
            ),
            using: authority,
            compatibility: adapter
        )
        let entry = try fetchEntry(223, list: 221, fixture)
        return DeterministicResult(
            execution: result.command,
            output: result.compatibilityOutput,
            state: DeterministicState(
                listRevision: try fetchList(221, fixture).revision,
                entryID: entry.id,
                lifecycle: entry.lifecycleRawValue,
                eventIDs: try historyEvents(fixture).map(\.id)
            )
        )
    }

    private func fetchProduct(
        _ value: Int,
        _ fixture: Fixture
    ) throws -> WayTaskSchemaV4.Product {
        let id = uuid(value)
        return try XCTUnwrap(try freshContext(fixture).fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>(
                predicate: #Predicate { $0.id == id }
            )
        ).first)
    }

    private func fetchList(
        _ value: Int,
        _ fixture: Fixture
    ) throws -> WayTaskSchemaV4.ShoppingList {
        let id = uuid(value)
        return try XCTUnwrap(try freshContext(fixture).fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingList>(
                predicate: #Predicate { $0.id == id }
            )
        ).first)
    }

    private func fetchEntry(
        _ value: Int,
        list: Int,
        _ fixture: Fixture
    ) throws -> WayTaskSchemaV4.ShoppingListEntry {
        let id = uuid(value)
        let listID = uuid(list)
        return try XCTUnwrap(try freshContext(fixture).fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>(
                predicate: #Predicate {
                    $0.id == id && $0.shoppingListID == listID
                }
            )
        ).first)
    }

    private func entries(
        list: Int,
        _ fixture: Fixture
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        let listID = uuid(list)
        return try freshContext(fixture).fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>(
                predicate: #Predicate { $0.shoppingListID == listID },
                sortBy: [SortDescriptor(\.id)]
            )
        )
    }

    private func historyEvents(
        _ fixture: Fixture
    ) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        try freshContext(fixture).fetch(
            FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>(
                sortBy: [SortDescriptor(\.id)]
            )
        )
    }

    private func count<T: PersistentModel>(
        _ type: T.Type,
        _ fixture: Fixture
    ) throws -> Int {
        try freshContext(fixture).fetchCount(FetchDescriptor<T>())
    }

    private func freshContext(_ fixture: Fixture) -> ModelContext {
        let context = ModelContext(fixture.container)
        context.autosaveEnabled = false
        return context
    }

    private func source(_ relativePath: String, _ root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func identity(
        entry: Int,
        list: Int,
        product: Int
    ) -> ProductStateListEntryIdentity {
        ProductStateListEntryIdentity(
            id: entryID(entry),
            listID: listID(list),
            productID: productID(product)
        )
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(value))
    }

    private func entryID(_ value: Int) -> ProductStateListEntryID {
        ProductStateListEntryID(rawValue: uuid(value))
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
