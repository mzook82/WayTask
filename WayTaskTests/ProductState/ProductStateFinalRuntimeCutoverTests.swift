import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateFinalRuntimeCutoverTests: XCTestCase {
    func testNewInstallActivatesOnlyV4AndTargetWritesSurviveRelaunch()
        throws {
        let fixture = try makeBootstrapFixture("new-install")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = try fixture.bootstrap.start()
        XCTAssertEqual(first.record.authority, "product-state")
        XCTAssertEqual(first.record.schemaVersion, 4)
        XCTAssertEqual(first.record.sourceKind, "new-install")
        XCTAssertEqual(first.record.compatibilityLegacyReadCount, 0)
        XCTAssertEqual(first.record.compatibilityLegacyWriteCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.source.path)
        )

        let runtime = ProductStateRuntime(
            modelContainer: first.modelContainer,
            cutoverRecord: first.record
        )
        runtime.createList(title: "Synthetic Exact List")
        runtime.acquireProduct(name: "Synthetic Exact Product")

        let list = try projectedLists(runtime).onlyElement()
        let product = try activeProducts(runtime).onlyElement()
        runtime.addProduct(product.id, to: list)
        let writtenList = try projectedLists(runtime).onlyElement()

        XCTAssertEqual(writtenList.id, list.id)
        XCTAssertEqual(writtenList.neededEntries.count, 1)
        XCTAssertEqual(
            writtenList.neededEntries[0].identity.productID,
            product.id
        )
        XCTAssertEqual(runtime.compatibilityCounters.legacyReadCount, 0)
        XCTAssertEqual(runtime.compatibilityCounters.legacyWriteCount, 0)

        // The cutover record describes the promoted input. Legitimate target
        // writes must not turn those original counts into a relaunch lock.
        let reopened = try fixture.bootstrap.start()
        let relaunched = ProductStateRuntime(
            modelContainer: reopened.modelContainer,
            cutoverRecord: reopened.record
        )
        let relaunchedList = try projectedLists(relaunched).onlyElement()
        let relaunchedProduct = try activeProducts(relaunched).onlyElement()
        XCTAssertEqual(relaunchedList.id, list.id)
        XCTAssertEqual(relaunchedProduct.id, product.id)
        XCTAssertEqual(
            relaunchedList.neededEntries[0].identity.id,
            writtenList.neededEntries[0].identity.id
        )
        XCTAssertEqual(reopened.runtimeStoreURL, first.runtimeStoreURL)
        XCTAssertEqual(relaunched.compatibilityCounters.legacyReadCount, 0)
        XCTAssertEqual(relaunched.compatibilityCounters.legacyWriteCount, 0)
    }

    func testExactListSelectionActivatesShoppingAndMapWithoutFallback()
        throws {
        let fixture = try makeBootstrapFixture("routing")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let started = try fixture.bootstrap.start()
        let runtime = ProductStateRuntime(
            modelContainer: started.modelContainer,
            cutoverRecord: started.record
        )
        runtime.createList(title: "First Synthetic List")
        runtime.createList(title: "Second Synthetic List")
        let lists = projectedLists(runtime)
        XCTAssertEqual(lists.count, 2)

        runtime.selectList(nil)
        XCTAssertNil(runtime.selectedListID)
        guard case .idle = runtime.shoppingState.content else {
            return XCTFail("Shopping must remain idle without exact List scope")
        }
        guard case .idle = runtime.mapState.content else {
            return XCTFail("Map must remain idle without exact List scope")
        }

        runtime.selectList(lists[0].id)
        XCTAssertEqual(runtime.selectedListID, lists[0].id)
        guard case let .available(shopping) = runtime.shoppingState.content
        else {
            return XCTFail("Expected target Shopping consumer")
        }
        XCTAssertEqual(shopping.listID, lists[0].id)
        switch runtime.mapState.content {
        case let .available(map), let .stale(map, _):
            XCTAssertEqual(map.listID, lists[0].id)
            XCTAssertEqual(map.listRevision, lists[0].revision)
        default:
            XCTFail("Expected target Map consumer: \(runtime.mapState.content)")
        }

        runtime.selectList(lists[1].id)
        XCTAssertEqual(runtime.selectedListID, lists[1].id)
        switch runtime.mapState.content {
        case let .available(map), let .stale(map, _):
            XCTAssertEqual(map.listID, lists[1].id)
            XCTAssertEqual(map.listRevision, lists[1].revision)
        default:
            XCTFail("Expected refreshed Map mission: \(runtime.mapState.content)")
        }

        runtime.selectList(
            ProductStateListID(rawValue: uuid(9_999))
        )
        XCTAssertNil(runtime.selectedListID)
        guard case .idle = runtime.shoppingState.content else {
            return XCTFail("A missing List must never select another List")
        }
        guard case .idle = runtime.mapState.content else {
            return XCTFail("A missing List must never supply Map fallback")
        }
    }

    func testTargetListLifecyclePreservesProductListAndEntryIdentity()
        throws {
        let fixture = try makeBootstrapFixture("lifecycle")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let started = try fixture.bootstrap.start()
        let runtime = ProductStateRuntime(
            modelContainer: started.modelContainer,
            cutoverRecord: started.record
        )
        runtime.createList(title: "Lifecycle List")
        runtime.acquireProduct(name: "Lifecycle Product")
        let product = try activeProducts(runtime).onlyElement()
        runtime.addProduct(product.id, to: try projectedLists(runtime).onlyElement())

        let needed = try projectedLists(runtime).onlyElement()
        let entry = try needed.neededEntries.onlyElement()
        let entryIdentity = entry.identity
        let neededRevision = needed.revision.value
        runtime.perform(
            .resolve(.alreadyHave),
            row: ShoppingWorkspaceProjectionRow(entry: entry),
            list: needed
        )

        let resolved = try projectedLists(runtime).onlyElement()
        XCTAssertEqual(resolved.id, needed.id)
        XCTAssertEqual(resolved.revision.value, neededRevision + 1)
        XCTAssertEqual(
            try resolved.resolvedEntries.onlyElement().identity,
            entryIdentity
        )
        let resolvedEntry = try resolved.resolvedEntries.onlyElement()
        runtime.perform(
            .reopen,
            row: ShoppingWorkspaceProjectionRow(entry: resolvedEntry),
            list: resolved
        )

        let reopened = try projectedLists(runtime).onlyElement()
        XCTAssertEqual(reopened.id, needed.id)
        XCTAssertEqual(reopened.revision.value, neededRevision + 2)
        XCTAssertEqual(
            try reopened.neededEntries.onlyElement().identity,
            entryIdentity
        )
        XCTAssertEqual(
            try activeProducts(runtime).onlyElement().id,
            product.id
        )
        XCTAssertEqual(runtime.compatibilityCounters.legacyReadCount, 0)
        XCTAssertEqual(runtime.compatibilityCounters.legacyWriteCount, 0)
    }

    func testProtectedV3CutoverPreservesSourceAndExactIdentities()
        throws {
        let fixture = try makeBootstrapFixture("protected-v3")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try makeProtectedV3Store(
            builder: fixture.builder,
            source: fixture.source
        )
        let before = try WayTaskProtectedStoreInspector.inspect(
            storeURL: fixture.source
        )

        let started = try fixture.bootstrap.start()

        let after = try WayTaskProtectedStoreInspector.inspect(
            storeURL: fixture.source
        )
        XCTAssertEqual(after.fingerprint, before.fingerprint)
        XCTAssertEqual(started.record.sourceKind, "protected-v3-migration")
        XCTAssertEqual(
            started.record.sourceFingerprint,
            before.fingerprint.rawValue
        )
        XCTAssertEqual(started.record.productCount, 1)
        XCTAssertEqual(started.record.listCount, 1)
        XCTAssertEqual(started.record.entryCount, 1)
        XCTAssertEqual(started.record.sessionCount, 0)
        XCTAssertEqual(started.record.historyEventCount, 0)
        XCTAssertNotNil(started.record.semanticFingerprint)
        XCTAssertNotNil(started.record.semanticDigest)

        let runtime = ProductStateRuntime(
            modelContainer: started.modelContainer,
            cutoverRecord: started.record
        )
        let product = try activeProducts(runtime).onlyElement()
        let list = try projectedLists(runtime).onlyElement()
        let migratedEntry = try list.resolvedEntries.onlyElement()
        XCTAssertEqual(product.id.rawValue, uuid(101))
        XCTAssertEqual(list.id.rawValue, uuid(102))
        XCTAssertEqual(migratedEntry.identity.id.rawValue, uuid(103))
        XCTAssertEqual(migratedEntry.identity.productID, product.id)
        XCTAssertEqual(migratedEntry.identity.listID, list.id)
        XCTAssertEqual(runtime.compatibilityCounters.legacyReadCount, 0)
        XCTAssertEqual(runtime.compatibilityCounters.legacyWriteCount, 0)

        _ = try fixture.bootstrap.start()
        let afterRelaunch = try WayTaskProtectedStoreInspector.inspect(
            storeURL: fixture.source
        )
        XCTAssertEqual(afterRelaunch.fingerprint, before.fingerprint)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: fixture.candidates,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testSessionNotificationAndGeofencePlanningUseExactTargetAuthority()
        throws {
        let fixture = try makeBootstrapFixture("session-planning")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let started = try fixture.bootstrap.start()
        let runtime = ProductStateRuntime(
            modelContainer: started.modelContainer,
            cutoverRecord: started.record
        )
        runtime.createList(title: "Session List")
        runtime.acquireProduct(name: "Session Product")
        let product = try activeProducts(runtime).onlyElement()
        runtime.addProduct(product.id, to: try projectedLists(runtime).onlyElement())
        let list = try projectedLists(runtime).onlyElement()
        let entry = try list.neededEntries.onlyElement()
        let sessionID = ProductStateSessionID(rawValue: uuid(601))
        let snapshotID = ProductStateSessionSnapshotID(rawValue: uuid(602))
        let planID = ProductStatePlanID(rawValue: uuid(603))
        let stopID = ProductStateSessionStopID(rawValue: uuid(604))
        let lineID = ProductStateSessionLineID(rawValue: uuid(605))
        let effectiveAt = date(600)
        let plan = ProductStateShoppingPlan(
            id: planID,
            sourceListID: list.id,
            sourceRevision: list.revision,
            includedEntries: [entry.identity],
            exclusions: [],
            status: .ready
        )
        let execution = runtime.sessions.start(
            ProductStateSessionStartInput(
                command: ProductStateCommand(
                    id: ProductStateCommandID(rawValue: uuid(606)),
                    expectedRevision: ProductStateExpectedRevision(
                        revision: ProductStateRevision(
                            scope: .list(list.id),
                            value: list.revision.value
                        )
                    ),
                    effectiveAt: effectiveAt,
                    intent: .startSession(
                        StartSessionCommand(
                            sessionID: sessionID,
                            listID: list.id,
                            sourceRevision: list.revision,
                            entries: [entry.identity]
                        )
                    )
                ),
                plan: plan,
                planFingerprint: "t21-runtime-plan-v1",
                planEvidenceAt: effectiveAt.addingTimeInterval(-60 * 60),
                confirmedStaleEvidenceAt: nil,
                snapshotID: snapshotID,
                stops: [
                    ProductStateSessionStopInput(
                        id: stopID,
                        sortOrder: 0,
                        storeReferenceIDRawValue: "store-t21-runtime",
                        storeReferenceProvenanceRawValue: "publishedStore",
                        displayNameSnapshot: "Synthetic Store",
                        latitude: 31.7,
                        longitude: 35.2,
                        evidenceAt: effectiveAt.addingTimeInterval(-60 * 60),
                        isSessionScopedTransient: false
                    )
                ],
                lines: [
                    ProductStateSessionLineInput(
                        id: lineID,
                        sourceEntry: entry.identity,
                        stopID: stopID,
                        sortOrder: 0,
                        globalProductConceptIDRawValue: "concept-t21-runtime"
                    )
                ]
            )
        )
        guard case let .started(summary, .fresh) = execution.outcome else {
            return XCTFail("Expected target Session Start: \(execution.outcome)")
        }
        XCTAssertEqual(summary.sessionID, sessionID)
        XCTAssertEqual(summary.sourceListID, list.id)
        XCTAssertEqual(summary.sourceRevision, .exact(list.revision))
        XCTAssertEqual(summary.sourcePlanID, planID)
        XCTAssertEqual(summary.snapshotID, snapshotID)

        runtime.refresh()
        guard case let .projection(active) = runtime.activeSessions else {
            return XCTFail("Expected active target Session projection")
        }
        XCTAssertEqual(active.candidates.map(\.sessionID), [sessionID])
        let notification = try XCTUnwrap(runtime.notificationPlan)
        XCTAssertEqual(
            notification.owner,
            .session(sessionID, .init(value: 1), snapshotID)
        )
        XCTAssertEqual(
            notification.state,
            .ineligible(.explicitIntentDisabled)
        )
        XCTAssertTrue(notification.registrations.isEmpty)
        let monitoring = try XCTUnwrap(runtime.monitoringPlan)
        XCTAssertEqual(monitoring.reconciliation.owner, notification.owner)
        XCTAssertTrue(monitoring.reconciliation.actions.isEmpty)
        XCTAssertTrue(monitoring.reconciliation.desiredGeofenceIDs.isEmpty)
        XCTAssertEqual(runtime.compatibilityCounters.legacyReadCount, 0)
        XCTAssertEqual(runtime.compatibilityCounters.legacyWriteCount, 0)
    }

    func testIncompleteAndForeignRuntimeStateFailClosed() throws {
        let incomplete = try makeBootstrapFixture("incomplete")
        defer { try? FileManager.default.removeItem(at: incomplete.root) }
        try FileManager.default.createDirectory(
            at: incomplete.runtime,
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(try incomplete.bootstrap.start()) { error in
            guard case WayTaskProductStateCutoverError
                .incompleteRuntimeDirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: incomplete.source.path)
        )

        let foreign = try makeBootstrapFixture("foreign-staging")
        defer { try? FileManager.default.removeItem(at: foreign.root) }
        try FileManager.default.createDirectory(
            at: foreign.staging,
            withIntermediateDirectories: true
        )
        try Data("foreign".utf8).write(
            to: foreign.staging.appendingPathComponent("foreign.data")
        )
        XCTAssertThrowsError(try foreign.bootstrap.start()) { error in
            guard case WayTaskProductStateCutoverError
                .foreignStagingDirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: foreign.staging.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: foreign.runtime.path)
        )
    }

    func testInvalidPromotedTargetBlocksWithoutLegacyOrEmptySubstitution()
        throws {
        let fixture = try makeBootstrapFixture("invalid-target")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let started = try fixture.bootstrap.start()
        let context = ModelContext(started.modelContainer)
        context.autosaveEnabled = false
        context.insert(
            WayTaskSchemaV4.Product(
                id: uuid(701),
                revision: 0,
                libraryLifecycleRawValue:
                    ProductLibraryLifecycle.active.rawValue,
                name: "Invalid Synthetic Product",
                sourceRawValue: ProductSource.manual.rawValue,
                createdAt: date(701),
                updatedAt: date(701)
            )
        )
        try context.save()

        XCTAssertThrowsError(try fixture.bootstrap.start()) { error in
            guard case WayTaskProductStateCutoverError.targetStoreInvalid =
                    error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.runtime.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.source.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.staging.path)
        )
    }

    func testReleaseRootHasZeroLegacyRuntimeRoutesAndNoPhysicalDeletion()
        throws {
        let root = repositoryRoot()
        let app = try source("WayTask/WayTaskApp.swift", root: root)
        let runtime = try source(
            "WayTask/ProductState/Runtime/ProductStateRuntime.swift",
            root: root
        )
        let view = try source(
            "WayTask/ProductState/Runtime/ProductStateRuntimeView.swift",
            root: root
        )

        XCTAssertTrue(app.contains("ProductStateRuntimeLaunchState"))
        XCTAssertTrue(app.contains("WayTaskProductionRuntimeView"))
        for forbidden in [
            "WayTaskStartupPersistenceBootstrap", "ContentView(",
            "AppStateManager()", "LocationManager()",
            "allowsLegacyV3ApplicationContent"
        ] {
            XCTAssertFalse(app.contains(forbidden), forbidden)
        }
        for forbidden in [
            "ProductStateCompatibilityAdapter", "WayTaskStartupPersistence",
            "WayTaskModelContainer.make", "Schema(versionedSchema: WayTaskSchemaV3",
            "ShoppingItem", "legacyRead(", "legacyWrite("
        ] {
            XCTAssertFalse(runtime.contains(forbidden), forbidden)
        }
        for forbidden in [
            "@Query", "ModelContext", ".save()", "ShoppingItem",
            "isChecked", "isCompleted"
        ] {
            XCTAssertFalse(view.contains(forbidden), forbidden)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "WayTask/ProductState/Persistence/" +
                        "ProductStateCompatibilityAdapter.swift"
                ).path
            )
        )
    }

    private func makeBootstrapFixture(_ name: String) throws
        -> BootstrapFixture {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "WT033A-T21-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let sourceRoot = root.appendingPathComponent(
            "protected-source",
            isDirectory: true
        )
        let builderRoot = root.appendingPathComponent(
            "synthetic-builder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: builderRoot,
            withIntermediateDirectories: false
        )
        let source = sourceRoot.appendingPathComponent("protected.store")
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let candidates = root.appendingPathComponent(
            "candidates",
            isDirectory: true
        )
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        return BootstrapFixture(
            root: root,
            source: source,
            builder: builderRoot.appendingPathComponent("builder.store"),
            runtime: runtime,
            candidates: candidates,
            staging: staging,
            bootstrap: WayTaskProductStateRuntimeBootstrap(
                sourceStoreURL: source,
                runtimeRootURL: runtime,
                candidateRootURL: candidates,
                stagingRootURL: staging
            )
        )
    }

    private func makeProtectedV3Store(builder: URL, source: URL) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-T21-Protected-V3",
                schema: schema,
                url: builder,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let item = ShoppingItem(
                id: uuid(100),
                name: "Synthetic Protected Item",
                isCompleted: false,
                barcode: "0000000000100"
            )
            let product = Product(
                id: uuid(101),
                legacyShoppingItemID: item.id,
                name: "Synthetic Protected Product",
                barcode: item.barcode,
                dateAdded: date(1),
                updatedAt: date(2)
            )
            let list = ShoppingList(
                id: uuid(102),
                title: "Synthetic Protected List",
                kind: .weekly,
                createdAt: date(3),
                updatedAt: date(4),
                isDefault: false
            )
            let entry = ShoppingListEntry(
                id: uuid(103),
                shoppingListID: list.id,
                product: product,
                legacyShoppingItemID: item.id,
                quantity: 2,
                isChecked: true,
                createdAt: date(5),
                sortOrder: 1
            )
            context.insert(item)
            context.insert(product)
            context.insert(list)
            context.insert(entry)
            try context.save()
        }
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let component = URL(fileURLWithPath: builder.path + suffix)
            guard FileManager.default.fileExists(atPath: component.path) else {
                continue
            }
            try FileManager.default.copyItem(
                at: component,
                to: URL(fileURLWithPath: source.path + suffix)
            )
        }
    }

    private func projectedLists(
        _ runtime: ProductStateRuntime
    ) -> [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(value) = $0 else { return nil }
            return value
        }
    }

    private func activeProducts(
        _ runtime: ProductStateRuntime
    ) -> [ProductStateProductProjection] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        return library.products.map(\.product)
    }

    private func source(_ path: String, root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        Date(timeIntervalSince1970: 1_900_000_000 + offset)
    }
}

private struct BootstrapFixture {
    let root: URL
    let source: URL
    let builder: URL
    let runtime: URL
    let candidates: URL
    let staging: URL
    let bootstrap: WayTaskProductStateRuntimeBootstrap
}

private enum FinalRuntimeTestError: Error {
    case expectedOneElement(Int)
}

private extension Array {
    func onlyElement() throws -> Element {
        guard count == 1, let first else {
            throw FinalRuntimeTestError.expectedOneElement(count)
        }
        return first
    }
}
