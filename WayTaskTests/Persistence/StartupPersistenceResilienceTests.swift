import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class StartupPersistenceResilienceTests: XCTestCase {
    func testRecoverableStoreOpenFailureQuarantinesRecreatesAndSendsSentryDiagnostics()
        throws
    {
        var sentryDiagnostics:
            [WayTaskStartupPersistenceDiagnostic] = []
        let sentry = SentryReportingService(
            sdkStartAction: { _ in true },
            startupPersistenceCaptureAction: {
                sentryDiagnostics.append($0)
            }
        )
        XCTAssertEqual(
            sentry.startIfConfigured(
                infoDictionary: validInfoDictionary,
                bundleIdentifier: "h.WayTask",
                deviceMetadata: SentryDeviceMetadata(
                    model: "iPhone-test",
                    osVersion: "26.5"
                ),
                isDebugBuild: false
            ),
            .enabled
        )

        let recoveredContainer = try makeInMemoryContainer()
        var openAttempts = 0
        var repairAttempts = 0
        var developerAssertions: [String] = []
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO)
        )
        let openError = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_110,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                openAttempts += 1
                if openAttempts == 1 {
                    throw openError
                }
                return recoveredContainer
            },
            openInMemoryStore: {
                XCTFail("Persistent recovery should succeed")
                return try self.makeInMemoryContainer()
            },
            repairStore: { container in
                repairAttempts += 1
                let context = ModelContext(container)
                return try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(in: context)
                    .repairActionCount
            },
            quarantineStore: { 3 },
            reportDiagnostic: {
                sentry.captureStartupPersistence($0)
            },
            developerAssertion: {
                developerAssertions.append($0)
            }
        )

        let result = try bootstrap.start()

        XCTAssertEqual(
            result.mode,
            .recreatedPersistentStore
        )
        XCTAssertEqual(openAttempts, 2)
        XCTAssertEqual(repairAttempts, 1)
        XCTAssertEqual(developerAssertions.count, 1)
        XCTAssertEqual(sentryDiagnostics.count, 2)
        XCTAssertEqual(
            sentryDiagnostics[0],
            WayTaskStartupPersistenceDiagnostic(
                stage: .openStore,
                outcome: .failed,
                error: openError
            )
        )
        XCTAssertEqual(
            sentryDiagnostics[1],
            WayTaskStartupPersistenceDiagnostic(
                stage: .recreatePersistentStore,
                outcome: .recovered,
                quarantinedComponentCount: 3
            )
        )
    }

    func testPersistentRecoveryFailureFallsBackToSafeInMemoryStore()
        throws
    {
        enum TestFailure: Error {
            case open
            case recreate
        }

        let fallbackContainer = try makeInMemoryContainer()
        var openAttempts = 0
        var diagnostics:
            [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                openAttempts += 1
                if openAttempts == 1 {
                    throw TestFailure.open
                }
                throw TestFailure.recreate
            },
            openInMemoryStore: {
                fallbackContainer
            },
            repairStore: { container in
                let context = ModelContext(container)
                return try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(in: context)
                    .repairActionCount
            },
            quarantineStore: { 1 },
            reportDiagnostic: {
                diagnostics.append($0)
            },
            developerAssertion: { _ in }
        )

        let result = try bootstrap.start()

        XCTAssertEqual(result.mode, .inMemoryFallback)
        XCTAssertEqual(
            diagnostics.map(\.outcome),
            [.failed, .failed, .degraded]
        )
        XCTAssertEqual(
            diagnostics.map(\.stage),
            [
                .openStore,
                .recreatePersistentStore,
                .inMemoryFallback
            ]
        )
    }

    func testSuccessfulRowRepairSendsOneDiagnosticAndRepeatedStartupIsQuiet()
        throws
    {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(
            Product(
                name: "Legacy milk",
                catalogProductIDRawValue: "prd_pilot_0001"
            )
        )
        try context.save()

        var diagnostics:
            [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: { container },
            openInMemoryStore: {
                XCTFail("Fallback should not be used")
                return try self.makeInMemoryContainer()
            },
            repairStore: { container in
                let context = ModelContext(container)
                return try ShoppingListBackfillService()
                    .ensureDefaultListsAndBackfill(in: context)
                    .repairActionCount
            },
            quarantineStore: {
                XCTFail("Quarantine should not be used")
                return 0
            },
            reportDiagnostic: {
                diagnostics.append($0)
            },
            developerAssertion: { _ in }
        )

        XCTAssertEqual(try bootstrap.start().mode, .persistent)
        XCTAssertEqual(try bootstrap.start().mode, .persistent)

        XCTAssertEqual(
            diagnostics,
            [
                WayTaskStartupPersistenceDiagnostic(
                    stage: .startupRepair,
                    outcome: .recovered,
                    repairActionCount: 4
                )
            ]
        )
    }

    func testQuarantineMovesWholeStoreOnceAndRepeatedRecoveryIsIdempotent()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WT029B2-Quarantine-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent(
            "default.store"
        )
        let componentURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
        for (index, url) in componentURLs.enumerated() {
            try Data([UInt8(index)]).write(to: url)
        }
        let quarantineRoot = directory.appendingPathComponent(
            "Quarantine",
            isDirectory: true
        )
        let quarantine = WayTaskStoreQuarantine(
            storeURL: storeURL,
            quarantineRootURL: quarantineRoot,
            clock: {
                Date(timeIntervalSince1970: 1_900_000_000)
            },
            identifierFactory: {
                UUID(
                    uuidString:
                        "10000000-0000-0000-0000-000000000001"
                )!
            }
        )

        XCTAssertEqual(try quarantine.quarantine(), 3)
        XCTAssertEqual(try quarantine.quarantine(), 0)
        XCTAssertTrue(
            componentURLs.allSatisfy {
                !FileManager.default.fileExists(atPath: $0.path)
            }
        )

        let quarantineDirectories = try FileManager.default
            .contentsOfDirectory(
                at: quarantineRoot,
                includingPropertiesForKeys: nil
            )
        XCTAssertEqual(quarantineDirectories.count, 1)
        let quarantinedNames = Set(
            try FileManager.default.contentsOfDirectory(
                at: quarantineDirectories[0],
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent)
        )
        XCTAssertEqual(
            quarantinedNames,
            Set(componentURLs.map(\.lastPathComponent))
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try WayTaskModelContainer.makeInMemory()
    }

    private var validInfoDictionary: [String: Any] {
        [
            "SENTRY_DSN":
                "https://public@example.ingest.invalid/123",
            "CFBundleShortVersionString": "1.0.2",
            "CFBundleVersion": "4"
        ]
    }
}
