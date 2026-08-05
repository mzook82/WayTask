import Combine
import Foundation
import SwiftData

enum WayTaskProductStateCutoverError: Error, LocalizedError {
    case incompleteRuntimeDirectory
    case foreignStagingDirectory
    case migrationFoundation(WayTaskMigrationFailureClassification)
    case productListMigration(WayTaskMigrationFailureClassification)
    case sessionHistoryMigration(WayTaskMigrationFailureClassification)
    case candidateCleanupFailed
    case promotionFailed
    case targetStoreInvalid

    var errorDescription: String? {
        switch self {
        case .incompleteRuntimeDirectory:
            "The Product State runtime directory is incomplete."
        case .foreignStagingDirectory:
            "An unowned Product State staging directory exists."
        case let .migrationFoundation(reason):
            "Product State migration foundation failed: \(reason.rawValue)."
        case let .productListMigration(reason):
            "Product and List migration failed: \(reason.rawValue)."
        case let .sessionHistoryMigration(reason):
            "Session and history migration failed: \(reason.rawValue)."
        case .candidateCleanupFailed:
            "The owned Product State migration candidate could not be cleaned."
        case .promotionFailed:
            "The validated Product State runtime could not be promoted."
        case .targetStoreInvalid:
            "The Product State runtime failed invariant validation."
        }
    }
}

struct WayTaskProductStateCutoverRecord: Codable, Equatable {
    static let formatVersion = 1

    let formatVersion: Int
    let authority: String
    let schemaVersion: Int
    let sourceKind: String
    let sourceFingerprint: String?
    let semanticFingerprint: String?
    let semanticDigest: String?
    let productCount: Int
    let listCount: Int
    let entryCount: Int
    let sessionCount: Int
    let historyEventCount: Int
    let compatibilityLegacyReadCount: UInt64
    let compatibilityLegacyWriteCount: UInt64
}

struct WayTaskProductStateRuntimeBootstrapResult {
    let modelContainer: ModelContainer
    let record: WayTaskProductStateCutoverRecord
    let runtimeStoreURL: URL
}

@MainActor
final class ProductStateRuntimeLaunchState: ObservableObject {
    let runtime: ProductStateRuntime?
    let failureMessage: String?

    convenience init() {
        self.init(bootstrap: .live())
    }

    init(bootstrap: WayTaskProductStateRuntimeBootstrap) {
        do {
            let result = try bootstrap.start()
            runtime = ProductStateRuntime(
                modelContainer: result.modelContainer,
                cutoverRecord: result.record
            )
            failureMessage = nil
        } catch {
            runtime = nil
            failureMessage = (error as? LocalizedError)?.errorDescription
                ?? "Product State is unavailable."
        }
    }
}

/// T-21's single fail-closed release boundary.
///
/// The shipped V3 store and sidecars remain protected and byte-unchanged. A
/// separately validated V4 store is promoted as one owned directory, and all
/// subsequent launches open only that V4 runtime. Missing markers, foreign
/// staging data, migration failure, cleanup failure, or invariant failure
/// blocks the application instead of reopening V3 or creating a substitute.
@MainActor
struct WayTaskProductStateRuntimeBootstrap {
    static let ownerFilename = ".wt033a-t21-owner.json"
    static let recordFilename = "runtime-cutover.json"
    static let storeFilename = "product-state-v4.store"

    let sourceStoreURL: URL
    let runtimeRootURL: URL
    let candidateRootURL: URL
    let stagingRootURL: URL
    let attemptSeed: UUID

    init(
        sourceStoreURL: URL,
        runtimeRootURL: URL,
        candidateRootURL: URL,
        stagingRootURL: URL,
        attemptSeed: UUID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000021"
        )!
    ) {
        self.sourceStoreURL = sourceStoreURL.standardizedFileURL
        self.runtimeRootURL = runtimeRootURL.standardizedFileURL
        self.candidateRootURL = candidateRootURL.standardizedFileURL
        self.stagingRootURL = stagingRootURL.standardizedFileURL
        self.attemptSeed = attemptSeed
    }

    static func live() -> Self {
        let source = WayTaskModelContainer.defaultStoreURL.standardizedFileURL
        let parent = source.deletingLastPathComponent()
        return Self(
            sourceStoreURL: source,
            runtimeRootURL: parent.appendingPathComponent(
                "WayTaskProductStateRuntime",
                isDirectory: true
            ),
            candidateRootURL: parent.appendingPathComponent(
                "WayTaskProductStateMigrationCandidates",
                isDirectory: true
            ),
            stagingRootURL: parent.appendingPathComponent(
                "WayTaskProductStateRuntime.staging",
                isDirectory: true
            )
        )
    }

    func start() throws -> WayTaskProductStateRuntimeBootstrapResult {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: runtimeRootURL.path) {
            guard !fileManager.fileExists(atPath: stagingRootURL.path) else {
                try removeOwnedStaging()
                return try openPromotedRuntime()
            }
            return try openPromotedRuntime()
        }

        if fileManager.fileExists(atPath: stagingRootURL.path) {
            try removeOwnedStaging()
        }
        try fileManager.createDirectory(
            at: candidateRootURL,
            withIntermediateDirectories: true
        )

        guard fileManager.fileExists(atPath: sourceStoreURL.path) else {
            return try createNewInstallRuntime()
        }
        return try migrateAndPromote()
    }

    private func openPromotedRuntime() throws
        -> WayTaskProductStateRuntimeBootstrapResult {
        let ownerURL = runtimeRootURL.appendingPathComponent(
            Self.ownerFilename
        )
        let recordURL = runtimeRootURL.appendingPathComponent(
            Self.recordFilename
        )
        let storeURL = runtimeRootURL.appendingPathComponent(
            Self.storeFilename
        )
        guard FileManager.default.fileExists(atPath: ownerURL.path),
              FileManager.default.fileExists(atPath: recordURL.path),
              FileManager.default.fileExists(atPath: storeURL.path),
              try Data(contentsOf: ownerURL) == ownerData()
        else {
            throw WayTaskProductStateCutoverError.incompleteRuntimeDirectory
        }
        let record = try JSONDecoder().decode(
            WayTaskProductStateCutoverRecord.self,
            from: Data(contentsOf: recordURL)
        )
        guard record.formatVersion == WayTaskProductStateCutoverRecord
            .formatVersion,
              record.authority == "product-state",
              record.schemaVersion == 4,
              record.compatibilityLegacyReadCount == 0,
              record.compatibilityLegacyWriteCount == 0
        else {
            throw WayTaskProductStateCutoverError.incompleteRuntimeDirectory
        }
        let container = try makeRuntimeContainer(storeURL: storeURL)
        try validateRuntimeStore(container, expected: nil)
        return WayTaskProductStateRuntimeBootstrapResult(
            modelContainer: container,
            record: record,
            runtimeStoreURL: storeURL
        )
    }

    private func createNewInstallRuntime() throws
        -> WayTaskProductStateRuntimeBootstrapResult {
        try createOwnedStaging()
        let storeURL = stagingRootURL.appendingPathComponent(
            Self.storeFilename
        )
        _ = try makeRuntimeContainer(storeURL: storeURL)
        let record = WayTaskProductStateCutoverRecord(
            formatVersion: WayTaskProductStateCutoverRecord.formatVersion,
            authority: "product-state",
            schemaVersion: 4,
            sourceKind: "new-install",
            sourceFingerprint: nil,
            semanticFingerprint: nil,
            semanticDigest: nil,
            productCount: 0,
            listCount: 0,
            entryCount: 0,
            sessionCount: 0,
            historyEventCount: 0,
            compatibilityLegacyReadCount: 0,
            compatibilityLegacyWriteCount: 0
        )
        try write(record: record, at: stagingRootURL)
        try validateRuntimeStore(
            makeRuntimeContainer(storeURL: storeURL),
            expected: record
        )
        try promoteStaging()
        return try openPromotedRuntime()
    }

    private func migrateAndPromote() throws
        -> WayTaskProductStateRuntimeBootstrapResult {
        let migration = WayTaskProductStateMigration()
        let foundation: WayTaskMigrationCandidateReceipt
        switch migration.prepareCandidate(
            WayTaskMigrationRequest(
                sourceStoreURL: sourceStoreURL,
                candidateRootURL: candidateRootURL,
                attemptSeed: attemptSeed
            )
        ) {
        case let .candidateReady(receipt):
            foundation = receipt
        case let .failed(failure):
            throw WayTaskProductStateCutoverError.migrationFoundation(
                failure.classification
            )
        }

        let productList: WayTaskProductListSemanticReceipt
        switch migration.migrateProductListSemantics(foundation) {
        case let .complete(receipt):
            productList = receipt
        case let .failed(failure):
            throw WayTaskProductStateCutoverError.productListMigration(
                failure.classification
            )
        }

        let complete: WayTaskSessionHistoryArchiveMigrationReceipt
        switch migration.migrateSessionHistoryArchiveSemantics(productList) {
        case let .complete(receipt):
            complete = receipt
        case let .failed(failure):
            throw WayTaskProductStateCutoverError.sessionHistoryMigration(
                failure.classification
            )
        }

        try createOwnedStaging()
        let stagedStoreURL = stagingRootURL.appendingPathComponent(
            Self.storeFilename
        )
        try copyStore(
            from: complete.targetStoreURL,
            to: stagedStoreURL
        )
        let target = complete.targetValidation
        let record = WayTaskProductStateCutoverRecord(
            formatVersion: WayTaskProductStateCutoverRecord.formatVersion,
            authority: "product-state",
            schemaVersion: 4,
            sourceKind: "protected-v3-migration",
            sourceFingerprint: foundation.sourceFingerprint.rawValue,
            semanticFingerprint: complete.targetFingerprint.rawValue,
            semanticDigest: complete.semanticDigest.rawValue,
            productCount: target.productListBase.products.count,
            listCount: target.productListBase.lists.count
                + target.archiveLists.count,
            entryCount: target.productListBase.entries.count
                + target.archiveEntries.count,
            sessionCount: target.sessions.count,
            historyEventCount: target.historyEvents.count,
            compatibilityLegacyReadCount: 0,
            compatibilityLegacyWriteCount: 0
        )
        try write(record: record, at: stagingRootURL)
        try validateRuntimeStore(
            makeRuntimeContainer(storeURL: stagedStoreURL),
            expected: record
        )
        let cleanup = migration.cleanupOwnedCandidate(foundation)
        guard cleanup.succeeded, !cleanup.sourceWasAccessed else {
            try? removeOwnedStaging()
            throw WayTaskProductStateCutoverError.candidateCleanupFailed
        }
        try promoteStaging()
        return try openPromotedRuntime()
    }

    private func createOwnedStaging() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: stagingRootURL.path) else {
            throw WayTaskProductStateCutoverError.foreignStagingDirectory
        }
        try fileManager.createDirectory(
            at: stagingRootURL,
            withIntermediateDirectories: false
        )
        try ownerData().write(
            to: stagingRootURL.appendingPathComponent(Self.ownerFilename),
            options: [.atomic]
        )
    }

    private func removeOwnedStaging() throws {
        let marker = stagingRootURL.appendingPathComponent(Self.ownerFilename)
        guard FileManager.default.fileExists(atPath: marker.path),
              try Data(contentsOf: marker) == ownerData()
        else {
            throw WayTaskProductStateCutoverError.foreignStagingDirectory
        }
        try FileManager.default.removeItem(at: stagingRootURL)
    }

    private func promoteStaging() throws {
        guard !FileManager.default.fileExists(atPath: runtimeRootURL.path)
        else {
            throw WayTaskProductStateCutoverError.promotionFailed
        }
        do {
            try FileManager.default.moveItem(
                at: stagingRootURL,
                to: runtimeRootURL
            )
        } catch {
            throw WayTaskProductStateCutoverError.promotionFailed
        }
    }

    private func copyStore(from source: URL, to destination: URL) throws {
        let inventory = try WayTaskProtectedStoreInspector.inspect(
            storeURL: source
        )
        for component in inventory.components {
            let suffix: String
            switch component.role {
            case .database: suffix = ""
            case .writeAheadLog: suffix = "-wal"
            case .sharedMemory: suffix = "-shm"
            case .rollbackJournal: suffix = "-journal"
            }
            try FileManager.default.copyItem(
                at: component.url,
                to: URL(fileURLWithPath: destination.path + suffix)
            )
        }
        let copied = try WayTaskProtectedStoreInspector.inspect(
            storeURL: destination
        )
        guard copied.fingerprint == inventory.fingerprint else {
            throw WayTaskProductStateCutoverError.targetStoreInvalid
        }
    }

    private func write(
        record: WayTaskProductStateCutoverRecord,
        at root: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(
            to: root.appendingPathComponent(Self.recordFilename),
            options: [.atomic]
        )
    }

    private func makeRuntimeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
        let configuration = ModelConfiguration(
            "WT033A-T21-Product-State-Runtime",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func validateRuntimeStore(
        _ container: ModelContainer,
        expected: WayTaskProductStateCutoverRecord?
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let products = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>()
        )
        let lists = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
        )
        let entries = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
        )
        let sessions = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
        )
        let sessionLines = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingSessionLine>()
        )
        let sessionStops = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingSessionStop>()
        )
        let history = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
        )
        let productIDs = Set(products.map(\.id))
        let listIDs = Set(lists.map(\.id))
        let editableListIDs = Set(lists.filter {
            ![ShoppingListKind.completed.rawValue,
              ShoppingListKind.recent.rawValue].contains($0.purposeRawValue)
        }.map(\.id))
        let entryIDs = Set(entries.map(\.id))
        let sessionsByID = Dictionary(grouping: sessions, by: \.id)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
        let stopsByID = Dictionary(grouping: sessionStops, by: \.id)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
        let recordedCountsMatch = expected.map {
            $0.productCount == products.count &&
                $0.listCount == lists.count &&
                $0.entryCount == entries.count &&
                $0.sessionCount == sessions.count &&
                $0.historyEventCount == history.count
        } ?? true
        guard recordedCountsMatch,
              productIDs.count == products.count,
              listIDs.count == lists.count,
              Set(entries.map(\.id)).count == entries.count,
              Set(sessions.map(\.id)).count == sessions.count,
              Set(sessionLines.map(\.id)).count == sessionLines.count,
              Set(sessionStops.map(\.id)).count == sessionStops.count,
              Set(history.map(\.id)).count == history.count,
              products.allSatisfy({ product in
                  guard product.revision > 0,
                        let lifecycle = ProductLibraryLifecycle(
                            rawValue: product.libraryLifecycleRawValue
                        ) else { return false }
                  switch lifecycle {
                  case .active: return product.libraryRemovedAt == nil
                  case .removed: return product.libraryRemovedAt != nil
                  }
              }),
              lists.allSatisfy({ $0.revision > 0 }),
              entries.allSatisfy({ entry in
                  guard entry.quantity.isFinite,
                        entry.quantity > 0,
                        entry.sortOrder.isFinite,
                        listIDs.contains(entry.shoppingListID),
                        !editableListIDs.contains(entry.shoppingListID) ||
                            productIDs.contains(entry.productID)
                  else { return false }
                  switch entry.lifecycleRawValue {
                  case "needed":
                      return entry.resolutionReasonRawValue == nil &&
                        entry.resolutionEffectiveAt == nil &&
                        entry.resolutionProvenanceRawValue == nil
                  case "resolved":
                      return ShoppingListResolutionReason(
                          rawValue: entry.resolutionReasonRawValue ?? ""
                      ) != nil &&
                        entry.resolutionEffectiveAt != nil &&
                        !(entry.resolutionProvenanceRawValue ?? "").isEmpty
                  default:
                      return false
                  }
              }),
              sessions.allSatisfy({ session in
                  guard session.revision > 0,
                        ShoppingSessionLifecycle(
                            rawValue: session.lifecycleRawValue
                        ) != nil,
                        ShoppingSessionMigrationCondition(
                            rawValue: session.migrationConditionRawValue
                        ) != nil,
                        session.snapshotVersion > 0,
                        session.snapshotGeneration > 0,
                        !session.snapshotContentSignature.isEmpty,
                        session.expirationPolicyVersion > 0,
                        ["exact", "legacyUnknown"].contains(
                            session.sourceRevisionProvenanceRawValue
                        )
                  else { return false }
                  if let sourceListID = session.sourceListID,
                     !listIDs.contains(sourceListID) { return false }
                  if session.sourceRevisionProvenanceRawValue == "exact" {
                      return session.sourceListID != nil &&
                        (session.sourceRevision ?? 0) > 0
                  }
                  return true
              }),
              sessionStops.allSatisfy({ stop in
                  guard let session = sessionsByID[stop.sessionID],
                        stop.snapshotID == session.snapshotID,
                        stop.sortOrder >= 0,
                        !stop.storeReferenceProvenanceRawValue.isEmpty
                  else { return false }
                  switch (stop.latitudeSnapshot, stop.longitudeSnapshot) {
                  case (nil, nil): return true
                  case let (.some(latitude), .some(longitude)):
                      return latitude.isFinite && longitude.isFinite &&
                        (-90...90).contains(latitude) &&
                        (-180...180).contains(longitude)
                  default: return false
                  }
              }),
              sessionLines.allSatisfy({ line in
                  guard let session = sessionsByID[line.sessionID],
                        line.snapshotID == session.snapshotID,
                        line.snapshotVersion == session.snapshotVersion,
                        line.sortOrder >= 0,
                        line.quantitySnapshot.isFinite,
                        line.quantitySnapshot > 0,
                        ShoppingSessionExecutionState(
                            rawValue: line.executionStateRawValue
                        ) != nil,
                        line.sourceListID.map(listIDs.contains) ?? true,
                        line.sourceEntryID.map(entryIDs.contains) ?? true,
                        line.productID.map(productIDs.contains) ?? true
                  else { return false }
                  guard let stopID = line.stopID else { return true }
                  return stopsByID[stopID]?.sessionID == line.sessionID
              }),
              history.allSatisfy({ productIDs.contains($0.productID) })
        else {
            throw WayTaskProductStateCutoverError.targetStoreInvalid
        }
    }

    private func ownerData() -> Data {
        Data("WT-033A|T-21|product-state-runtime|v1".utf8)
    }
}

@MainActor
final class ProductStateRuntime: ObservableObject {
    let modelContainer: ModelContainer
    let cutoverRecord: WayTaskProductStateCutoverRecord
    let repositories: ProductStateRepositories
    let transactionCoordinator: ProductStateTransactionCoordinator
    let productCommands: ProductStateProductCommandAuthority
    let listCommands: ProductStateNamedListCommandAuthority
    let queries: ProductStateQueryBoundary
    let sessionCommands: ProductStateShoppingSessionCommandAuthority
    let sessions: ProductStateShoppingSessionService
    let notificationPlanner = ProductStateNotificationPlanner()
    let monitoringCoordinator = ProductStateLocationMonitoringCoordinator()

    let compatibilityCounters = ProductStateCompatibilityAccessCounters(
        targetReadCount: 0,
        outputEmissionCount: 0,
        legacyReadCount: 0,
        legacyWriteCount: 0,
        reverseSynchronizationCount: 0
    )

    @Published private(set) var namedLists: [
        ProductStateProjectionOutcome<ProductStateNamedListProjection>
    ] = []
    @Published private(set) var homeState = ProductHomeConsumerState.idle
    @Published private(set) var shoppingState =
        ShoppingWorkspaceProjectionConsumerState.idle
    @Published private(set) var mapState =
        ProductStateMapProjectionConsumerState.idle
    @Published private(set) var activeSessions:
        ProductStateProjectionOutcome<
            ProductStateActiveSessionLookupProjection
        >?
    @Published private(set) var notificationPlan:
        ProductStateNotificationPlanProjection?
    @Published private(set) var monitoringPlan:
        ProductStateMonitoringCoordinationProjection?
    @Published private(set) var selectedListID: ProductStateListID?
    @Published private(set) var lastMutationMessage: String?

    init(
        modelContainer: ModelContainer,
        cutoverRecord: WayTaskProductStateCutoverRecord
    ) {
        self.modelContainer = modelContainer
        self.cutoverRecord = cutoverRecord
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let repositories = ProductStateRepositories(modelContext: context)
        self.repositories = repositories
        let transaction = ProductStateTransactionCoordinator(
            modelContext: context
        )
        transactionCoordinator = transaction
        productCommands = ProductStateProductCommandAuthority(
            repositories: repositories,
            transactionCoordinator: transaction,
            writeState: .writableTarget
        )
        listCommands = ProductStateNamedListCommandAuthority(
            repositories: repositories,
            transactionCoordinator: transaction,
            writeState: .writableTarget
        )
        let queries = ProductStateQueryBoundary(repositories: repositories)
        self.queries = queries
        let sessionCommands = ProductStateShoppingSessionCommandAuthority(
            repositories: repositories,
            transactionCoordinator: transaction,
            writeState: .writableTarget
        )
        self.sessionCommands = sessionCommands
        sessions = ProductStateShoppingSessionService(
            queries: queries,
            commands: sessionCommands
        )
        refresh()
    }

    func selectList(_ listID: ProductStateListID?) {
        selectedListID = listID
        refresh()
    }

    func refresh() {
        namedLists = queries.namedLists().filter { outcome in
            guard case let .projection(list) = outcome else { return true }
            return ![ShoppingListKind.completed.rawValue,
                     ShoppingListKind.recent.rawValue,
                     "deleted"]
                .contains(list.purposeRawValue)
        }
        let library = queries.productLibrary(
            ProductStateProductLibraryRequest(membershipScope: nil)
        )
        let removed = queries.removedProducts()
        let libraryState = ProductLibraryPresentationConsumer.make(
            library: library,
            removedProducts: removed,
            listScope: nil,
            catalog: [:]
        )
        let home = ProductHomePresentationConsumer.make(
            library: libraryState,
            namedLists: namedLists,
            planStatus: ShoppingPlanConsumerBoundary.emptyConsumerStatus(),
            acquisition: .idle
        )
        homeState = ProductHomeConsumerState(
            library: libraryState,
            chooser: .idle,
            home: home,
            acquisition: .idle
        )

        if let selectedListID,
           let selected = namedLists.first(where: {
               guard case let .projection(list) = $0 else { return false }
               return list.id == selectedListID
           }) {
            shoppingState = ShoppingWorkspaceProjectionConsumer.make(
                namedList: selected,
                planStatus:
                    ShoppingPlanConsumerBoundary.emptyConsumerStatus()
            )
            buildMap(from: selected)
        } else {
            if selectedListID != nil { self.selectedListID = nil }
            shoppingState = .idle
            mapState = .idle
        }

        activeSessions = sessions.activeSessions()
        buildReminderPlans()
    }

    @discardableResult
    func createList(title: String) -> ProductStateListID? {
        let id = ProductStateListID(rawValue: UUID())
        let result = listCommands.createNamedList(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: nil,
                effectiveAt: Date(),
                intent: .createNamedList(
                    CreateNamedListCommand(
                        listID: id,
                        title: title,
                        purposeRawValue: "shopping"
                    )
                )
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "List created" : "List was not created"
        if result.claimsDurableSuccess { selectedListID = id }
        refresh()
        return result.claimsDurableSuccess ? id : nil
    }

    @discardableResult
    func renameList(
        _ list: ProductStateNamedListProjection,
        title: String
    ) -> Bool {
        let result = listCommands.renameNamedList(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .renameNamedList(
                    RenameNamedListCommand(
                        listID: list.id,
                        title: title
                    )
                )
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "List renamed" : "List was not renamed"
        refresh()
        return result.claimsDurableSuccess
    }

    /// Deletes a user-visible list through a revisioned logical archive. The
    /// retained row keeps session/history references valid; list entries and
    /// product records are not rewritten or removed.
    @discardableResult
    func deleteList(_ list: ProductStateNamedListProjection) -> Bool {
        let fallbackID: ProductStateListID? = namedLists.compactMap {
            outcome -> ProductStateListID? in
            guard case let .projection(candidate) = outcome,
                  candidate.id != list.id
            else { return nil }
            return candidate.id
        }.first
        let wasSelected = selectedListID == list.id
        let result = listCommands.deleteNamedList(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .deleteNamedList(
                    DeleteNamedListCommand(
                        listID: list.id,
                        confirmed: true
                    )
                )
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "List deleted" : "List was not deleted"
        if result.claimsDurableSuccess, wasSelected {
            selectedListID = fallbackID
        }
        refresh()
        return result.claimsDurableSuccess
    }

    @discardableResult
    func acquireProduct(name: String) -> Bool {
        let result = productCommands.acquire(
            ProductStateProductAcquisitionRequest(
                commandID: ProductStateCommandID(rawValue: UUID()),
                productID: ProductStateProductID(rawValue: UUID()),
                effectiveAt: Date(),
                reviewed: true,
                name: name,
                sourceRawValue: ProductSource.manual.rawValue
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "Product added" : "Product was not added"
        refresh()
        return result.claimsDurableSuccess
    }

    func addProduct(
        _ productID: ProductStateProductID,
        to list: ProductStateNamedListProjection
    ) {
        let identity = ProductStateListEntryIdentity(
            id: ProductStateListEntryID(rawValue: UUID()),
            listID: list.id,
            productID: productID
        )
        let result = listCommands.addEntry(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .addProductToList(
                    AddProductToListCommand(
                        entry: identity,
                        historyEventID: ProductStateHistoryEventID(
                            rawValue: UUID()
                        ),
                        quantity: 1,
                        unitRawValue: nil,
                        note: nil,
                        sortOrder: nextSortOrder(in: list)
                    )
                )
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "Product added to List" : "List was not changed"
        refresh()
    }

    @discardableResult
    func perform(
        _ action: ShoppingWorkspaceListAction,
        row: ShoppingWorkspaceProjectionRow,
        list: ProductStateNamedListProjection
    ) -> Bool {
        let commandID = ProductStateCommandID(rawValue: UUID())
        let historyID = ProductStateHistoryEventID(rawValue: UUID())
        let command: ProductStateCommand
        switch action {
        case let .updateQuantity(quantity):
            command = ProductStateCommand(
                id: commandID,
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .updateListEntry(
                    UpdateListEntryCommand(
                        entry: row.entry.identity,
                        quantity: quantity,
                        unitRawValue: row.entry.unitRawValue,
                        note: row.entry.note,
                        sortOrder: row.entry.sortOrder
                    )
                )
            )
        case let .resolve(reason):
            command = ProductStateCommand(
                id: commandID,
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .resolveListNeed(
                    ResolveListNeedCommand(
                        entry: row.entry.identity,
                        historyEventID: historyID,
                        reason: reason
                    )
                )
            )
        case .reopen:
            command = ProductStateCommand(
                id: commandID,
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .reopenListNeed(
                    ReopenListNeedCommand(
                        entry: row.entry.identity,
                        historyEventID: historyID
                    )
                )
            )
        case .remove:
            command = ProductStateCommand(
                id: commandID,
                expectedRevision: expectedRevision(for: list),
                effectiveAt: Date(),
                intent: .removeProductFromNamedList(
                    RemoveProductFromNamedListCommand(
                        entry: row.entry.identity,
                        historyEventID: historyID
                    )
                )
            )
        }
        let result: ProductStateNamedListCommandExecution
        switch action {
        case .updateQuantity: result = listCommands.updateEntry(command)
        case .resolve: result = listCommands.resolveEntry(command)
        case .reopen: result = listCommands.reopenEntry(command)
        case .remove: result = listCommands.removeEntry(command)
        }
        lastMutationMessage = result.claimsDurableSuccess
            ? "List updated" : "List was not changed"
        refresh()
        return result.claimsDurableSuccess
    }

    @discardableResult
    func increaseQuantity(
        of entry: ProductStateListEntryProjection,
        in list: ProductStateNamedListProjection
    ) -> Bool {
        guard let currentList = projectedList(id: list.id),
              var currentEntry = allEntries(in: currentList).first(where: {
                  $0.identity.id == entry.identity.id
              }) else {
            lastMutationMessage = "The existing product is no longer available"
            return false
        }

        if case .resolved = currentEntry.state {
            guard perform(
                .reopen,
                row: ShoppingWorkspaceProjectionRow(entry: currentEntry),
                list: currentList
            ),
            let reopenedList = projectedList(id: list.id),
            let reopenedEntry = reopenedList.neededEntries.first(where: {
                $0.identity.id == entry.identity.id
            }) else {
                return false
            }
            currentEntry = reopenedEntry
        }

        guard case .needed = currentEntry.state,
              let latestList = projectedList(id: list.id) else {
            lastMutationMessage = "The existing product cannot be updated"
            return false
        }

        let updatedQuantity = min(currentEntry.quantity + 1, 99)
        guard updatedQuantity > currentEntry.quantity else {
            lastMutationMessage = "Quantity is already at the maximum"
            return false
        }
        return perform(
            .updateQuantity(updatedQuantity),
            row: ShoppingWorkspaceProjectionRow(entry: currentEntry),
            list: latestList
        )
    }

    func restore(_ product: ProductStateProductProjection) {
        let result = productCommands.restoreToLibrary(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: ProductStateExpectedRevision(
                    revision: ProductStateRevision(
                        scope: .product(product.id),
                        value: product.revision
                    )
                ),
                effectiveAt: Date(),
                intent: .restoreProductToLibrary(
                    RestoreProductToLibraryCommand(
                        productID: product.id,
                        historyEventID: ProductStateHistoryEventID(
                            rawValue: UUID()
                        ),
                        confirmed: true
                    )
                )
            )
        )
        lastMutationMessage = result.claimsDurableSuccess
            ? "Product restored" : "Product was not restored"
        refresh()
    }

    private func buildMap(
        from selected:
            ProductStateProjectionOutcome<ProductStateNamedListProjection>
    ) {
        guard case let .projection(list) = selected else {
            mapState = .idle
            return
        }
        let mapContext = queries.mapContext(list: list)
        let discovery = queries.discoveryContext(mapContext)
        let recommendations = queries.storeRecommendations(
            context: discovery,
            evidence: [],
            emptyEvidencePublicationVersion:
                "wt033a-t21-empty-store-snapshot-v1"
        )
        mapState = ProductStateMapProjectionConsumer.make(
            shopping: shoppingState,
            mapContext: .projection(mapContext),
            discovery: .projection(discovery),
            recommendations: .projection(recommendations),
            stores: [],
            coverages: [],
            savedLocations: []
        )
    }

    private func buildReminderPlans() {
        notificationPlan = nil
        monitoringPlan = nil
        guard case let .projection(lookup) = activeSessions,
              lookup.candidates.count == 1,
              let candidate = lookup.candidates.first,
              case let .projection(snapshot) = sessions.snapshot(
                  ProductStateSessionSnapshotRequest(
                      sessionID: candidate.sessionID,
                      expectedRevision: candidate.revision
                  )
              )
        else { return }
        let opportunity = queries.notificationOpportunity(session: snapshot)
        let recoveryID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000021"
        )!
        let desired = notificationPlanner.makeProjection(
            session: snapshot,
            opportunity: opportunity,
            intent: .disabled(snapshot.id),
            capabilities: ProductStateReminderCapabilityProjection(
                notificationAuthorization: .notDetermined,
                locationAuthorization: .notDetermined,
                preciseLocationAvailable: false,
                regionMonitoringAvailable: false,
                backgroundRefreshAvailable: false,
                durableAuthorityAvailable: true
            ),
            policy: ProductStateReminderRegionPolicy(
                maximumRegionCount: 12,
                approvedFutureStopCount: 11,
                radiusMeters: 200,
                cooldown: ProductStateReminderRegionPolicy.requiredCooldown
            ),
            cause: .recovery(
                ProductStateReminderRecoveryInput(
                    recoveryID: recoveryID,
                    sessionID: snapshot.id,
                    revision: snapshot.revision,
                    snapshotID: snapshot.snapshotID,
                    durableAuthorityAvailable: true
                )
            )
        )
        notificationPlan = desired
        monitoringPlan = monitoringCoordinator.coordinate(
            desired: desired,
            ledger: [],
            platform: ProductStateManagedReminderPlatformSnapshot(
                geofenceIdentifiers: [],
                pendingNotificationIdentifiers: [],
                deliveredNotificationIdentifiers: []
            )
        )
    }

    private func expectedRevision(
        for list: ProductStateNamedListProjection
    ) -> ProductStateExpectedRevision {
        ProductStateExpectedRevision(
            revision: ProductStateRevision(
                scope: .list(list.id),
                value: list.revision.value
            )
        )
    }

    private func nextSortOrder(
        in list: ProductStateNamedListProjection
    ) -> Double {
        let values = (list.neededEntries + list.resolvedEntries +
            list.unresolvedEntries).map(\.sortOrder)
        return (values.max() ?? -1) + 1
    }

    private func projectedList(
        id: ProductStateListID
    ) -> ProductStateNamedListProjection? {
        namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
        .first { $0.id == id }
    }

    private func allEntries(
        in list: ProductStateNamedListProjection
    ) -> [ProductStateListEntryProjection] {
        list.neededEntries + list.resolvedEntries + list.unresolvedEntries
    }
}
