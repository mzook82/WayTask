import Foundation
import SwiftData

enum WayTaskStartupPersistenceStage: String {
    case openStore = "open_store"
    case startupRepair = "startup_repair"
    case quarantineStore = "quarantine_store"
    case recreatePersistentStore = "recreate_persistent_store"
    case inMemoryFallback = "in_memory_fallback"
    case unrecoverable
}

enum WayTaskStartupPersistenceOutcome: String {
    case failed
    case recovered
    case degraded
    case fatal
}

struct WayTaskStartupPersistenceDiagnostic: Equatable {
    let stage: WayTaskStartupPersistenceStage
    let outcome: WayTaskStartupPersistenceOutcome
    let errorDomain: String?
    let errorCode: Int?
    let underlyingErrorDomain: String?
    let underlyingErrorCode: Int?
    let quarantinedComponentCount: Int
    let repairActionCount: Int

    init(
        stage: WayTaskStartupPersistenceStage,
        outcome: WayTaskStartupPersistenceOutcome,
        error: Error? = nil,
        quarantinedComponentCount: Int = 0,
        repairActionCount: Int = 0
    ) {
        self.stage = stage
        self.outcome = outcome
        self.quarantinedComponentCount =
            max(quarantinedComponentCount, 0)
        self.repairActionCount = max(repairActionCount, 0)

        guard let error else {
            errorDomain = nil
            errorCode = nil
            underlyingErrorDomain = nil
            underlyingErrorCode = nil
            return
        }

        let nsError = error as NSError
        errorDomain = Self.sanitizedIdentifier(nsError.domain)
        errorCode = nsError.code

        if let underlyingError =
            nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        {
            underlyingErrorDomain =
                Self.sanitizedIdentifier(underlyingError.domain)
            underlyingErrorCode = underlyingError.code
        } else {
            underlyingErrorDomain = nil
            underlyingErrorCode = nil
        }
    }

    private static func sanitizedIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        let scalars = value.unicodeScalars.prefix(120).map {
            allowed.contains($0) ? Character(String($0)) : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "unknown" : result
    }
}

enum WayTaskStartupPersistenceMode: Equatable {
    case persistent
    case recreatedPersistentStore
    case inMemoryFallback
}

struct WayTaskStartupPersistenceResult {
    let modelContainer: ModelContainer
    let mode: WayTaskStartupPersistenceMode
}

enum WayTaskStartupPersistenceError: LocalizedError {
    case unrecoverable(
        initial: Error,
        persistentRecovery: Error,
        inMemoryFallback: Error
    )

    var errorDescription: String? {
        switch self {
        case .unrecoverable:
            return "WayTask could not initialize persistent or temporary local storage."
        }
    }
}

@MainActor
struct WayTaskStartupPersistenceBootstrap {
    typealias ContainerFactory = () throws -> ModelContainer
    typealias StoreRepair = (ModelContainer) throws -> Int
    typealias StoreQuarantine = () throws -> Int
    typealias DiagnosticReporter =
        (WayTaskStartupPersistenceDiagnostic) -> Void
    typealias DeveloperAssertion = (String) -> Void

    private let openDefaultStore: ContainerFactory
    private let openInMemoryStore: ContainerFactory
    private let repairStore: StoreRepair
    private let quarantineStore: StoreQuarantine
    private let reportDiagnostic: DiagnosticReporter
    private let developerAssertion: DeveloperAssertion

    private struct InitialStoreFailure: Error {
        let stage: WayTaskStartupPersistenceStage
        let underlyingError: Error
    }

    init(
        openDefaultStore: @escaping ContainerFactory,
        openInMemoryStore: @escaping ContainerFactory,
        repairStore: @escaping StoreRepair,
        quarantineStore: @escaping StoreQuarantine,
        reportDiagnostic: @escaping DiagnosticReporter,
        developerAssertion: @escaping DeveloperAssertion
    ) {
        self.openDefaultStore = openDefaultStore
        self.openInMemoryStore = openInMemoryStore
        self.repairStore = repairStore
        self.quarantineStore = quarantineStore
        self.reportDiagnostic = reportDiagnostic
        self.developerAssertion = developerAssertion
    }

    static func live() -> WayTaskStartupPersistenceBootstrap {
        WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                try WayTaskModelContainer.makeDefault()
            },
            openInMemoryStore: {
                try WayTaskModelContainer.makeInMemory()
            },
            repairStore: { container in
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(in: context)
                    .repairActionCount
            },
            quarantineStore: {
                try WayTaskStoreQuarantine(
                    storeURL: WayTaskModelContainer.defaultStoreURL
                ).quarantine()
            },
            reportDiagnostic: { diagnostic in
                SentryReportingService.shared
                    .captureStartupPersistence(diagnostic)
            },
            developerAssertion: { message in
                #if DEBUG
                assertionFailure(message)
                #endif
            }
        )
    }

    func start() throws -> WayTaskStartupPersistenceResult {
        do {
            return try openAndRepairInitialStore()
        } catch let failure as InitialStoreFailure {
            return try recover(
                from: failure.underlyingError,
                stage: failure.stage
            )
        }
    }

    private func openAndRepairInitialStore() throws
        -> WayTaskStartupPersistenceResult
    {
        let initialContainer: ModelContainer
        do {
            initialContainer = try openDefaultStore()
        } catch {
            throw InitialStoreFailure(
                stage: .openStore,
                underlyingError: error
            )
        }

        let repairActionCount: Int
        do {
            repairActionCount = try repairStore(initialContainer)
        } catch {
            throw InitialStoreFailure(
                stage: .startupRepair,
                underlyingError: error
            )
        }
        if repairActionCount > 0 {
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .startupRepair,
                    outcome: .recovered,
                    repairActionCount: repairActionCount
                )
            )
        }
        return WayTaskStartupPersistenceResult(
            modelContainer: initialContainer,
            mode: .persistent
        )
    }

    private func recover(
        from initialError: Error,
        stage: WayTaskStartupPersistenceStage
    ) throws -> WayTaskStartupPersistenceResult {
        reportDiagnostic(
            WayTaskStartupPersistenceDiagnostic(
                stage: stage,
                outcome: .failed,
                error: initialError
            )
        )
        developerAssertion(
            "[WayTask Startup] Recoverable \(stage.rawValue) failure: \(initialError.localizedDescription)"
        )

        var quarantinedComponentCount = 0
        let persistentRecoveryError: Error

        do {
            quarantinedComponentCount = try quarantineStore()
        } catch {
            persistentRecoveryError = error
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .quarantineStore,
                    outcome: .failed,
                    error: error
                )
            )
            return try fallBackToMemory(
                initialError: initialError,
                persistentRecoveryError: persistentRecoveryError,
                quarantinedComponentCount: 0
            )
        }

        do {
            let recoveredContainer = try openDefaultStore()
            let repairActionCount =
                try repairStore(recoveredContainer)
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .recreatePersistentStore,
                    outcome: .recovered,
                    quarantinedComponentCount:
                        quarantinedComponentCount,
                    repairActionCount: repairActionCount
                )
            )
            return WayTaskStartupPersistenceResult(
                modelContainer: recoveredContainer,
                mode: .recreatedPersistentStore
            )
        } catch {
            persistentRecoveryError = error
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .recreatePersistentStore,
                    outcome: .failed,
                    error: error,
                    quarantinedComponentCount:
                        quarantinedComponentCount
                )
            )
            return try fallBackToMemory(
                initialError: initialError,
                persistentRecoveryError: persistentRecoveryError,
                quarantinedComponentCount:
                    quarantinedComponentCount
            )
        }
    }

    private func fallBackToMemory(
        initialError: Error,
        persistentRecoveryError: Error,
        quarantinedComponentCount: Int
    ) throws -> WayTaskStartupPersistenceResult {
        do {
            let fallbackContainer = try openInMemoryStore()
            let repairActionCount =
                try repairStore(fallbackContainer)
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .inMemoryFallback,
                    outcome: .degraded,
                    error: persistentRecoveryError,
                    quarantinedComponentCount:
                        quarantinedComponentCount,
                    repairActionCount: repairActionCount
                )
            )
            return WayTaskStartupPersistenceResult(
                modelContainer: fallbackContainer,
                mode: .inMemoryFallback
            )
        } catch {
            reportDiagnostic(
                WayTaskStartupPersistenceDiagnostic(
                    stage: .unrecoverable,
                    outcome: .fatal,
                    error: error,
                    quarantinedComponentCount:
                        quarantinedComponentCount
                )
            )
            throw WayTaskStartupPersistenceError.unrecoverable(
                initial: initialError,
                persistentRecovery: persistentRecoveryError,
                inMemoryFallback: error
            )
        }
    }
}

struct WayTaskStoreQuarantine {
    typealias Clock = () -> Date
    typealias IdentifierFactory = () -> UUID

    private let storeURL: URL
    private let quarantineRootURL: URL
    private let fileManager: FileManager
    private let clock: Clock
    private let identifierFactory: IdentifierFactory

    init(
        storeURL: URL,
        quarantineRootURL: URL? = nil,
        fileManager: FileManager = .default,
        clock: @escaping Clock = Date.init,
        identifierFactory: @escaping IdentifierFactory = UUID.init
    ) {
        self.storeURL = storeURL
        self.quarantineRootURL = quarantineRootURL ??
            storeURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "WayTask Store Quarantine",
                    isDirectory: true
                )
        self.fileManager = fileManager
        self.clock = clock
        self.identifierFactory = identifierFactory
    }

    @discardableResult
    func quarantine() throws -> Int {
        let components = storeComponentURLs.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !components.isEmpty else {
            return 0
        }

        try fileManager.createDirectory(
            at: quarantineRootURL,
            withIntermediateDirectories: true
        )
        let timestamp = Int(
            clock().timeIntervalSince1970 * 1_000
        )
        let quarantineURL = quarantineRootURL
            .appendingPathComponent(
                "\(timestamp)-\(identifierFactory().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: quarantineURL,
            withIntermediateDirectories: false
        )

        var completedMoves: [(source: URL, destination: URL)] = []
        do {
            for source in components {
                let destination = quarantineURL.appendingPathComponent(
                    source.lastPathComponent,
                    isDirectory: false
                )
                try fileManager.moveItem(
                    at: source,
                    to: destination
                )
                completedMoves.append((source, destination))
            }
            return completedMoves.count
        } catch {
            for move in completedMoves.reversed()
            where fileManager.fileExists(
                atPath: move.destination.path
            ) && !fileManager.fileExists(atPath: move.source.path)
            {
                try? fileManager.moveItem(
                    at: move.destination,
                    to: move.source
                )
            }
            try? fileManager.removeItem(at: quarantineURL)
            throw error
        }
    }

    private var storeComponentURLs: [URL] {
        let name = storeURL.lastPathComponent
        let siblings = (
            try? fileManager.contentsOfDirectory(
                at: storeURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        ) ?? []
        return siblings.filter { url in
            let siblingName = url.lastPathComponent
            return siblingName == name ||
                siblingName.hasPrefix(name + "-") ||
                siblingName.hasPrefix(name + "_") ||
                siblingName.hasPrefix(name + ".")
        }
    }
}
