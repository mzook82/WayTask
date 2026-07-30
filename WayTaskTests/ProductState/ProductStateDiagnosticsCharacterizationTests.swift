import Foundation
import Sentry
import SwiftData
import XCTest
@testable import WayTask

// These tests record shipped diagnostic and privacy behavior only. Passing
// assertions involving a KD identifier document current legacy behavior; they
// do not approve that behavior or implement the cited WT-032A decisions.

@MainActor
final class ProductStateDiagnosticsCharacterizationTests: XCTestCase {
    // Current behavior: CB-13. Known legacy defect: KD-03.
    // WT-032A target decisions cited: D-34, D-35, D-36, D-37.
    func testCurrentStartupDiagnosticSuccessSequence()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13"],
            knownDefectIDs: ["KD-03"],
            decisionIDs: ["D-34", "D-35", "D-36", "D-37"]
        )

        let container = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e07-success-sequence")
        var sequence: [String] = []
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []

        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                sequence.append("open_store")
                return container
            },
            openInMemoryStore: {
                XCTFail("Current successful startup must not fall back")
                return container
            },
            repairStore: { _ in
                sequence.append("startup_repair")
                return 2
            },
            quarantineStore: {
                XCTFail("Current successful startup must not quarantine")
                return 0
            },
            reportDiagnostic: { diagnostic in
                diagnostics.append(diagnostic)
                sequence.append(
                    "report:\(diagnostic.stage.rawValue):"
                        + diagnostic.outcome.rawValue
                )
            },
            developerAssertion: { _ in
                XCTFail(
                    "Current successful startup must not assert"
                )
            }
        )

        let result = try bootstrap.start()
        sequence.append("complete:persistent")

        XCTAssertEqual(result.mode, .persistent)
        XCTAssertEqual(
            sequence,
            [
                "open_store",
                "startup_repair",
                "report:startup_repair:recovered",
                "complete:persistent"
            ]
        )
        XCTAssertEqual(
            diagnostics,
            [
                WayTaskStartupPersistenceDiagnostic(
                    stage: .startupRepair,
                    outcome: .recovered,
                    repairActionCount: 2
                )
            ]
        )

        let metadata = SentryStartupPersistenceMetadataPolicy
            .context(for: try XCTUnwrap(diagnostics.first))
        assertStartupMetadataAllowlist(metadata)
        XCTAssertEqual(metadata["stage"] as? String, "startup_repair")
        XCTAssertEqual(metadata["outcome"] as? String, "recovered")
        XCTAssertEqual(metadata["schema_version"] as? String, "3.0.0")
        XCTAssertEqual(metadata["repair_action_count"] as? Int, 2)
        XCTAssertEqual(
            metadata["quarantined_component_count"] as? Int,
            0
        )

        // Current clean startup is quiet when repair reports no work.
        var quietSequence: [String] = []
        let quietBootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                quietSequence.append("open_store")
                return container
            },
            openInMemoryStore: {
                XCTFail("Current clean startup must not fall back")
                return container
            },
            repairStore: { _ in
                quietSequence.append("startup_repair")
                return 0
            },
            quarantineStore: {
                XCTFail("Current clean startup must not quarantine")
                return 0
            },
            reportDiagnostic: { _ in
                XCTFail(
                    "Current zero-action startup emits no diagnostic"
                )
            },
            developerAssertion: { _ in
                XCTFail("Current clean startup must not assert")
            }
        )
        XCTAssertEqual(try quietBootstrap.start().mode, .persistent)
        quietSequence.append("complete:persistent")
        XCTAssertEqual(
            quietSequence,
            [
                "open_store",
                "startup_repair",
                "complete:persistent"
            ]
        )
    }

    // Current behavior: CB-13, CB-16. Known legacy defect: KD-03.
    // WT-032A target decisions cited: D-34, D-35, D-36, D-37.
    func testCurrentStartupDiagnosticRecoverySequence()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-16"],
            knownDefectIDs: ["KD-03"],
            decisionIDs: ["D-34", "D-35", "D-36", "D-37"]
        )

        let recoveredContainer = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e07-recovery-sequence")
        let initialError = NSError(
            domain: "SYNTHETIC_STARTUP_OPEN_ERROR",
            code: 7
        )
        var openAttempts = 0
        var sequence: [String] = []
        var diagnostics: [WayTaskStartupPersistenceDiagnostic] = []

        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                openAttempts += 1
                sequence.append("open_store_\(openAttempts)")
                if openAttempts == 1 {
                    throw initialError
                }
                return recoveredContainer
            },
            openInMemoryStore: {
                XCTFail(
                    "Successful persistent recovery must not fall back"
                )
                return recoveredContainer
            },
            repairStore: { _ in
                sequence.append("startup_repair")
                return 2
            },
            quarantineStore: {
                sequence.append("quarantine_store")
                return 3
            },
            reportDiagnostic: { diagnostic in
                diagnostics.append(diagnostic)
                sequence.append(
                    "report:\(diagnostic.stage.rawValue):"
                        + diagnostic.outcome.rawValue
                )
            },
            developerAssertion: { _ in
                sequence.append("developer_assertion")
            }
        )

        let result = try bootstrap.start()
        sequence.append("complete:recreated_persistent_store")

        XCTAssertEqual(result.mode, .recreatedPersistentStore)
        XCTAssertEqual(
            sequence,
            [
                "open_store_1",
                "report:open_store:failed",
                "developer_assertion",
                "quarantine_store",
                "open_store_2",
                "startup_repair",
                "report:recreate_persistent_store:recovered",
                "complete:recreated_persistent_store"
            ]
        )
        XCTAssertEqual(
            diagnostics.map(\.stage),
            [.openStore, .recreatePersistentStore]
        )
        XCTAssertEqual(
            diagnostics.map(\.outcome),
            [.failed, .recovered]
        )
        XCTAssertEqual(
            diagnostics[1].quarantinedComponentCount,
            3
        )
        XCTAssertEqual(diagnostics[1].repairActionCount, 2)

        let recoveredMetadata =
            SentryStartupPersistenceMetadataPolicy.context(
                for: diagnostics[1]
            )
        assertStartupMetadataAllowlist(recoveredMetadata)
        XCTAssertEqual(
            recoveredMetadata[
                "quarantined_component_count"
            ] as? Int,
            3
        )
        XCTAssertEqual(
            recoveredMetadata["repair_action_count"] as? Int,
            2
        )

        // Current failed recreation reports failure before the degraded
        // in-memory outcome. This is characterization, not approval of a
        // future recovery architecture.
        let fallbackContainer = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e07-fallback-sequence")
        let recreateError = NSError(
            domain: "SYNTHETIC_RECREATE_ERROR",
            code: 8
        )
        var fallbackOpenAttempts = 0
        var fallbackDiagnostics:
            [WayTaskStartupPersistenceDiagnostic] = []
        let fallbackBootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: {
                fallbackOpenAttempts += 1
                if fallbackOpenAttempts == 1 {
                    throw initialError
                }
                throw recreateError
            },
            openInMemoryStore: { fallbackContainer },
            repairStore: { _ in 1 },
            quarantineStore: { 4 },
            reportDiagnostic: {
                fallbackDiagnostics.append($0)
            },
            developerAssertion: { _ in }
        )

        XCTAssertEqual(
            try fallbackBootstrap.start().mode,
            .inMemoryFallback
        )
        XCTAssertEqual(
            fallbackDiagnostics.map(\.stage),
            [
                .openStore,
                .recreatePersistentStore,
                .inMemoryFallback
            ]
        )
        XCTAssertEqual(
            fallbackDiagnostics.map(\.outcome),
            [.failed, .failed, .degraded]
        )
        XCTAssertEqual(
            fallbackDiagnostics.map(\.quarantinedComponentCount),
            [0, 4, 4]
        )
        XCTAssertEqual(
            fallbackDiagnostics.map(\.repairActionCount),
            [0, 0, 1]
        )
        for diagnostic in fallbackDiagnostics {
            assertStartupMetadataAllowlist(
                SentryStartupPersistenceMetadataPolicy.context(
                    for: diagnostic
                )
            )
        }
    }

    // Current behavior: CB-13, CB-16. Known legacy defects: KD-03,
    // KD-12.
    // WT-032A target decisions cited: D-20-D-23, D-34-D-37.
    func testCurrentStartupDiagnosticMetadataUsesAllowlist()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-16"],
            knownDefectIDs: ["KD-03", "KD-12"],
            decisionIDs: [
                "D-20", "D-21", "D-22", "D-23",
                "D-34", "D-35", "D-36", "D-37"
            ]
        )

        let underlyingError = NSError(
            domain: "SYNTHETIC_UNDERLYING_ERROR",
            code: 9
        )
        let startupError = NSError(
            domain: "SYNTHETIC ERROR/DOMAIN",
            code: 10,
            userInfo: [NSUnderlyingErrorKey: underlyingError]
        )
        let diagnostic = WayTaskStartupPersistenceDiagnostic(
            stage: .openStore,
            outcome: .failed,
            error: startupError,
            quarantinedComponentCount: 99,
            repairActionCount: 20_001
        )
        let approved =
            SentryStartupPersistenceMetadataPolicy.context(
                for: diagnostic
            )

        XCTAssertEqual(
            Set(approved.keys),
            SentryStartupPersistenceMetadataPolicy.allowedKeys
        )
        XCTAssertEqual(
            diagnostic.errorDomain,
            "SYNTHETIC_ERROR_DOMAIN"
        )
        XCTAssertEqual(
            diagnostic.underlyingErrorDomain,
            "SYNTHETIC_UNDERLYING_ERROR"
        )
        XCTAssertEqual(
            approved["quarantined_component_count"] as? Int,
            10
        )
        XCTAssertEqual(
            approved["repair_action_count"] as? Int,
            10_000
        )

        let forbiddenMetadata: [String: Any] = [
            "product_name": privateSentinels.productName,
            "notes": privateSentinels.notes,
            "barcode": privateSentinels.barcode,
            "image": privateSentinels.image,
            "latitude": privateSentinels.coordinates,
            "longitude": privateSentinels.coordinates,
            "credentials": privateSentinels.credentials,
            "user_identifier": privateSentinels.userIdentifier,
            "account_identifier": privateSentinels.accountIdentifier,
            "token": privateSentinels.token
        ]
        let event = Event(level: .error)
        event.tags = [
            "startup_stage": "open_store",
            "startup_outcome": "failed",
            "private_tag": privateSentinels.token
        ]
        event.context = [
            SentryStartupPersistenceMetadataPolicy.contextKey:
                approved.merging(
                    forbiddenMetadata,
                    uniquingKeysWith: { _, injected in injected }
                )
        ]
        event.extra = forbiddenMetadata

        let sanitized = try XCTUnwrap(
            SentryReportingService.sanitize(event)
        )
        XCTAssertNil(sanitized.extra)
        XCTAssertNil(sanitized.tags?["private_tag"])
        let safeContext = try XCTUnwrap(
            sanitized.context?[
                SentryStartupPersistenceMetadataPolicy.contextKey
            ]
        )
        XCTAssertEqual(
            Set(safeContext.keys),
            SentryStartupPersistenceMetadataPolicy.allowedKeys
        )
        for key in forbiddenMetadata.keys {
            XCTAssertNil(safeContext[key])
        }

        let safeData = try JSONSerialization.data(
            withJSONObject: safeContext,
            options: [.sortedKeys]
        )
        let safeText = try XCTUnwrap(
            String(data: safeData, encoding: .utf8)
        )
        for sentinel in privateSentinels.all {
            XCTAssertFalse(safeText.contains(sentinel))
        }
        assertStartupMetadataAllowlist(safeContext)
    }

    // Current behavior: CB-13, CB-16. Known legacy defect: KD-12.
    // WT-032A target decisions cited: D-20-D-23, D-34-D-37.
    func testProductStateAttachmentsExcludePrivateSentinels()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-16"],
            knownDefectIDs: ["KD-12"],
            decisionIDs: [
                "D-20", "D-21", "D-22", "D-23",
                "D-34", "D-35", "D-36", "D-37"
            ]
        )

        let container = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e07-attachment-safety")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let imageBytes = Data(privateSentinels.image.utf8)
        let item = ShoppingItem(
            id: stableID(namespace: 0x0704, index: 1),
            name: privateSentinels.productName,
            imageData: imageBytes,
            barcode: privateSentinels.barcode,
            dateAdded: fixedDate(0),
            source: .manual,
            visibleText: privateSentinels.notes
        )
        let product = Product(
            id: stableID(namespace: 0x0704, index: 2),
            legacyShoppingItemID: item.id,
            name: privateSentinels.productName,
            imageData: imageBytes,
            barcode: privateSentinels.barcode,
            dateAdded: fixedDate(0),
            updatedAt: fixedDate(1),
            source: .manual,
            visibleText: privateSentinels.notes
        )
        let list = ShoppingList(
            id: stableID(namespace: 0x0704, index: 3),
            title: privateSentinels.listTitle,
            kind: .weekly,
            createdAt: fixedDate(0),
            updatedAt: fixedDate(1),
            isDefault: false
        )
        let location = GeoLocation(
            id: stableID(namespace: 0x0704, index: 4),
            title: privateSentinels.storeName,
            latitude: 0,
            longitude: 0,
            radius: 200,
            addressText: privateSentinels.coordinates,
            notes: privateSentinels.notes,
            sourceType: .userGenerated,
            shoppingItems: [item]
        )
        context.insert(item)
        context.insert(product)
        context.insert(list)
        context.insert(location)
        try context.save()

        let first =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e07-attachment-safety",
                    in: context
                )
        let second =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e07-attachment-safety",
                    in: context
                )
        let firstData = try first.canonicalJSONData()
        let secondData = try second.canonicalJSONData()
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            try first.sha256Digest(),
            try second.sha256Digest()
        )

        let attachmentText = try XCTUnwrap(
            String(data: firstData, encoding: .utf8)
        )
        for sentinel in privateSentinels.all {
            XCTAssertFalse(attachmentText.contains(sentinel))
        }
        try assertAttachmentJSONUsesAllowlist(firstData)

        let attachment =
            try ProductStateAttachmentFactory.makeJSONAttachment(
                snapshot: first,
                lifetime: .deleteOnSuccess
            )
        XCTAssertEqual(
            attachment.name,
            "SYNTHETIC_ProductState_e07-attachment-safety"
        )
        XCTAssertEqual(attachment.lifetime, .deleteOnSuccess)
        add(attachment)

        // A forged forbidden field is rejected, and the failure text exposes
        // only the safe case identifier and rejection category.
        let rejected = ProductStateCanonicalSemanticSnapshot(
            formatVersion: 1,
            caseID: "e07-attachment-rejection",
            syntheticData: true,
            records: [
                ProductStateSemanticRecord(
                    entityKind: "Product",
                    stableID: stableID(
                        namespace: 0x0704,
                        index: 5
                    ),
                    fields: [
                        "productName":
                            .string(privateSentinels.productName)
                    ],
                    relationships: [:]
                )
            ],
            entityCounts: ["Product": 1],
            relationshipCounts: [],
            recordTypeSummaries: [
                ProductStateSafeRecordTypeSummary(
                    entityKind: "Product",
                    count: 1
                )
            ]
        )
        XCTAssertThrowsError(
            try ProductStateAttachmentFactory.makeJSONAttachment(
                snapshot: rejected
            )
        ) { error in
            let description =
                (error as? LocalizedError)?.errorDescription
            XCTAssertEqual(
                description,
                "Product State attachment rejected "
                    + "[privacy-allowlist] for "
                    + "e07-attachment-rejection."
            )
            XCTAssertFalse(
                description?.contains(
                    self.privateSentinels.productName
                ) ?? true
            )
        }
    }

    // Current behavior: CB-13, CB-16. Known legacy defects: KD-03,
    // KD-12.
    // WT-032A target decisions cited: D-20-D-23, D-34-D-37.
    func testCharacterizationDoesNotInitializeDiagnosticTransport()
        throws
    {
        assertTraceability(
            currentBehaviorIDs: ["CB-13", "CB-16"],
            knownDefectIDs: ["KD-03", "KD-12"],
            decisionIDs: [
                "D-20", "D-21", "D-22", "D-23",
                "D-34", "D-35", "D-36", "D-37"
            ]
        )

        var sdkStartCount = 0
        var diagnosticCaptureCount = 0
        var startupCaptureCount = 0
        let service = SentryReportingService(
            sdkStartAction: { _ in
                sdkStartCount += 1
                return true
            },
            diagnosticCaptureAction: { _ in
                diagnosticCaptureCount += 1
            },
            startupPersistenceCaptureAction: { _ in
                startupCaptureCount += 1
            }
        )
        XCTAssertEqual(service.startupStatus, .notStarted)
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isNativeCrashHandlerEnabled)

        let container = try ProductStateTestContainerFactory
            .makeInMemoryCurrent(caseID: "e07-no-transport")
        var locallyReported:
            [WayTaskStartupPersistenceDiagnostic] = []
        let bootstrap = WayTaskStartupPersistenceBootstrap(
            openDefaultStore: { container },
            openInMemoryStore: {
                XCTFail("Current success must not fall back")
                return container
            },
            repairStore: { _ in 1 },
            quarantineStore: {
                XCTFail("Current success must not quarantine")
                return 0
            },
            reportDiagnostic: { diagnostic in
                locallyReported.append(diagnostic)
                service.captureStartupPersistence(diagnostic)
            },
            developerAssertion: { _ in
                XCTFail("Current success must not assert")
            }
        )

        XCTAssertEqual(try bootstrap.start().mode, .persistent)
        XCTAssertEqual(locallyReported.count, 1)
        XCTAssertEqual(
            locallyReported.first?.stage,
            .startupRepair
        )
        XCTAssertEqual(
            locallyReported.first?.outcome,
            .recovered
        )

        XCTAssertFalse(service.captureDebugTestMessage())
        XCTAssertFalse(service.captureDebugHandledError())
        XCTAssertFalse(service.captureDebugNonFatalException())
        XCTAssertEqual(service.startupStatus, .notStarted)
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isNativeCrashHandlerEnabled)
        XCTAssertEqual(sdkStartCount, 0)
        XCTAssertEqual(diagnosticCaptureCount, 0)
        XCTAssertEqual(startupCaptureCount, 0)

        // The test uses only the injected local reporter and an in-memory
        // support container. It invokes no app lifecycle, live transport,
        // production logger, or telemetry boundary.
    }

    // MARK: - Privacy and metadata assertions

    private var privateSentinels: PrivateSentinels {
        PrivateSentinels(
            productName: "SYNTHETIC_PRIVATE_PRODUCT_SENTINEL",
            notes: "SYNTHETIC_PRIVATE_NOTES_SENTINEL",
            barcode: "SYNTHETIC_PRIVATE_BARCODE_SENTINEL",
            image: "SYNTHETIC_PRIVATE_IMAGE_SENTINEL",
            coordinates: "SYNTHETIC_PRIVATE_COORDINATE_SENTINEL",
            listTitle: "SYNTHETIC_PRIVATE_LIST_SENTINEL",
            storeName: "SYNTHETIC_PRIVATE_STORE_SENTINEL",
            credentials: "SYNTHETIC_PRIVATE_CREDENTIAL_SENTINEL",
            userIdentifier: "SYNTHETIC_PRIVATE_USER_SENTINEL",
            accountIdentifier: "SYNTHETIC_PRIVATE_ACCOUNT_SENTINEL",
            token: "SYNTHETIC_PRIVATE_TOKEN_SENTINEL"
        )
    }

    private struct PrivateSentinels {
        let productName: String
        let notes: String
        let barcode: String
        let image: String
        let coordinates: String
        let listTitle: String
        let storeName: String
        let credentials: String
        let userIdentifier: String
        let accountIdentifier: String
        let token: String

        var all: [String] {
            [
                productName,
                notes,
                barcode,
                image,
                coordinates,
                listTitle,
                storeName,
                credentials,
                userIdentifier,
                accountIdentifier,
                token
            ]
        }
    }

    private func assertStartupMetadataAllowlist(
        _ metadata: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            Set(metadata.keys).isSubset(
                of: SentryStartupPersistenceMetadataPolicy
                    .allowedKeys
            ),
            file: file,
            line: line
        )
        let forbiddenFragments = [
            "product",
            "name",
            "note",
            "barcode",
            "image",
            "coordinate",
            "latitude",
            "longitude",
            "credential",
            "user",
            "account",
            "token",
            "path"
        ]
        XCTAssertTrue(
            metadata.keys.allSatisfy { key in
                let lowered = key.lowercased()
                return !forbiddenFragments.contains {
                    lowered.contains($0)
                }
            },
            file: file,
            line: line
        )
    }

    private func assertAttachmentJSONUsesAllowlist(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(root.keys),
            [
                "caseID",
                "entityCounts",
                "formatVersion",
                "recordTypeSummaries",
                "records",
                "relationshipCounts",
                "syntheticData"
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(root["syntheticData"] as? Bool, true)
        XCTAssertEqual(
            root["caseID"] as? String,
            "e07-attachment-safety"
        )

        let records = try XCTUnwrap(
            root["records"] as? [[String: Any]],
            file: file,
            line: line
        )
        let allowedRecordKeys: Set<String> = [
            "entityKind", "fields", "relationships", "stableID"
        ]
        let allowedFieldKeys: Set<String> = [
            "catalogSnapshotFieldCount",
            "createdAt",
            "dateAdded",
            "deletedAt",
            "imageData",
            "isCompleted",
            "isDefault",
            "kindRawValue",
            "legacyShoppingItemID",
            "sourceRawValue",
            "sourceTypeRawValue",
            "updatedAt"
        ]
        for record in records {
            XCTAssertEqual(
                Set(record.keys),
                allowedRecordKeys,
                file: file,
                line: line
            )
            let fields = try XCTUnwrap(
                record["fields"] as? [String: Any],
                file: file,
                line: line
            )
            XCTAssertTrue(
                Set(fields.keys).isSubset(of: allowedFieldKeys),
                file: file,
                line: line
            )
        }
    }

    // MARK: - Traceability and deterministic values

    private func assertTraceability(
        currentBehaviorIDs: [String],
        knownDefectIDs: [String],
        decisionIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            currentBehaviorIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(
            knownDefectIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertFalse(
            decisionIDs.isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            currentBehaviorIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "CB-",
                    range: 1...16
                )
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            knownDefectIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "KD-",
                    range: 1...12
                )
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            decisionIDs.allSatisfy {
                validIdentifier(
                    $0,
                    prefix: "D-",
                    range: 1...37
                )
            },
            file: file,
            line: line
        )
    }

    private func validIdentifier(
        _ value: String,
        prefix: String,
        range: ClosedRange<Int>
    ) -> Bool {
        guard value.hasPrefix(prefix) else {
            return false
        }
        let suffix = value.dropFirst(prefix.count)
        guard let number = Int(suffix), range.contains(number) else {
            return false
        }
        return suffix.count == 2
    }

    private func stableID(
        namespace: UInt16,
        index: UInt64
    ) -> UUID {
        ProductStateSyntheticValues.uuid(
            namespace: namespace,
            index: index
        )
    }

    private func fixedDate(_ day: TimeInterval) -> Date {
        ProductStateSyntheticValues.date(
            secondsAfterEpoch: day * 86_400
        )
    }
}
