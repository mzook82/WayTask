import CryptoKit
import Foundation
import SQLite3
import SwiftData

// MARK: - Protected store identity

enum WayTaskMigrationSchemaIdentity: String, CaseIterable, Codable, Sendable {
    case v1 = "WayTaskSchemaV1@1.0.0"
    case v2 = "WayTaskSchemaV2@2.0.0"
    case v3 = "WayTaskSchemaV3@3.0.0"
    case v4 = "WayTaskSchemaV4@4.0.0"

    fileprivate var persistentVersionIdentifier: String {
        switch self {
        case .v1:
            return "1.0.0"
        case .v2:
            return "2.0.0"
        case .v3:
            return "3.0.0"
        case .v4:
            return "4.0.0"
        }
    }

    fileprivate static func resolve(
        persistentVersionIdentifier: String
    ) -> WayTaskMigrationSchemaIdentity? {
        allCases.first {
            $0.persistentVersionIdentifier == persistentVersionIdentifier
        }
    }
}

struct WayTaskMigrationFingerprint: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct WayTaskMigrationStageIdentity: Hashable, Codable, Sendable {
    static let foundationVersion = "wt033a.tc13.t06.foundation.v1"

    let sourceSchema: WayTaskMigrationSchemaIdentity
    let candidateSchema: WayTaskMigrationSchemaIdentity
    let rawValue: String

    init(
        sourceSchema: WayTaskMigrationSchemaIdentity,
        candidateSchema: WayTaskMigrationSchemaIdentity = .v3
    ) {
        self.sourceSchema = sourceSchema
        self.candidateSchema = candidateSchema
        rawValue = WayTaskMigrationDigest.hex(
            hashing: Data(
                [
                    Self.foundationVersion,
                    sourceSchema.rawValue,
                    candidateSchema.rawValue
                ].joined(separator: "|").utf8
            )
        )
    }
}

struct WayTaskMigrationAttemptIdentity: Hashable, Codable, Sendable {
    let rawValue: String

    init(
        stageIdentity: WayTaskMigrationStageIdentity,
        sourceFingerprint: WayTaskMigrationFingerprint,
        attemptSeed: UUID
    ) {
        rawValue = WayTaskMigrationDigest.hex(
            hashing: Data(
                [
                    stageIdentity.rawValue,
                    sourceFingerprint.rawValue,
                    attemptSeed.uuidString.lowercased()
                ].joined(separator: "|").utf8
            )
        )
    }
}

enum WayTaskMigrationStoreComponentRole: String, CaseIterable, Codable,
    Sendable
{
    case database
    case writeAheadLog = "write_ahead_log"
    case sharedMemory = "shared_memory"
    case rollbackJournal = "rollback_journal"

    fileprivate var suffix: String {
        switch self {
        case .database:
            return ""
        case .writeAheadLog:
            return "-wal"
        case .sharedMemory:
            return "-shm"
        case .rollbackJournal:
            return "-journal"
        }
    }
}

struct WayTaskMigrationStoreComponent: Equatable, Sendable {
    let role: WayTaskMigrationStoreComponentRole
    let url: URL
    let byteCount: UInt64
    let fingerprint: WayTaskMigrationFingerprint
}

struct WayTaskMigrationStoreInventory: Equatable, Sendable {
    let components: [WayTaskMigrationStoreComponent]
    let totalByteCount: UInt64
    let fingerprint: WayTaskMigrationFingerprint

    var componentRoles: [WayTaskMigrationStoreComponentRole] {
        components.map(\.role)
    }
}

// MARK: - Privacy-safe exception foundation

enum WayTaskMigrationExceptionCategory: String, CaseIterable, Codable,
    Sendable
{
    case unsupportedRecord = "unsupported_record"
    case ambiguousRecord = "ambiguous_record"
    case legacyFlagContradiction = "legacy_flag_contradiction"
    case duplicateMerge = "duplicate_merge"
    case missingProductIdentity = "missing_product_identity"
    case missingListIdentity = "missing_list_identity"
    case ambiguousRelationship = "ambiguous_relationship"
    case tombstoneActiveReference = "tombstone_active_reference"
    case unresolvedSessionLine = "unresolved_session_line"
    case multipleSessionCandidates = "multiple_session_candidates"
    case legacyArchiveUnresolved = "legacy_archive_unresolved"
    case legacyHistoryUnlinked = "legacy_history_unlinked"
    case savedLocationUnresolved = "saved_location_unresolved"
}

struct WayTaskMigrationSafeDigest: Hashable, Codable, Sendable {
    let rawValue: String

    init(hashing evidenceBytes: Data) {
        rawValue = WayTaskMigrationDigest.hex(hashing: evidenceBytes)
    }
}

struct WayTaskMigrationExceptionEntry: Equatable, Codable, Sendable {
    let id: UUID
    let category: WayTaskMigrationExceptionCategory
    let safeEvidenceDigest: WayTaskMigrationSafeDigest
    let ordinal: Int
    fileprivate(set) var occurrenceCount: Int
}

struct WayTaskMigrationExceptionCategoryCount: Equatable, Codable, Sendable {
    let category: WayTaskMigrationExceptionCategory
    let count: Int
}

struct WayTaskMigrationExceptionSummary: Equatable, Codable, Sendable {
    let capacity: Int
    let totalOccurrenceCount: Int
    let recordedEntryCount: Int
    let overflowOccurrenceCount: Int
    let categoryCounts: [WayTaskMigrationExceptionCategoryCount]
    let overflowCategoryCounts: [WayTaskMigrationExceptionCategoryCount]

    static func empty(capacity: Int) -> Self {
        Self(
            capacity: max(capacity, 0),
            totalOccurrenceCount: 0,
            recordedEntryCount: 0,
            overflowOccurrenceCount: 0,
            categoryCounts: [],
            overflowCategoryCounts: []
        )
    }
}

struct WayTaskMigrationExceptionLedger: Equatable, Sendable {
    static let formatVersion = 1

    let capacity: Int
    private(set) var entries: [WayTaskMigrationExceptionEntry] = []
    private var categoryCounts: [WayTaskMigrationExceptionCategory: Int] = [:]
    private var overflowCategoryCounts:
        [WayTaskMigrationExceptionCategory: Int] = [:]
    private(set) var totalOccurrenceCount = 0
    private(set) var overflowOccurrenceCount = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 0)
    }

    mutating func record(
        category: WayTaskMigrationExceptionCategory,
        safeEvidenceDigest: WayTaskMigrationSafeDigest
    ) {
        totalOccurrenceCount += 1
        categoryCounts[category, default: 0] += 1

        if let index = entries.firstIndex(where: {
            $0.category == category &&
                $0.safeEvidenceDigest == safeEvidenceDigest
        }) {
            entries[index].occurrenceCount += 1
            return
        }

        guard entries.count < capacity else {
            overflowOccurrenceCount += 1
            overflowCategoryCounts[category, default: 0] += 1
            return
        }

        let ordinal = totalOccurrenceCount
        entries.append(
            WayTaskMigrationExceptionEntry(
                id: WayTaskMigrationDigest.stableUUID(
                    category: category,
                    digest: safeEvidenceDigest,
                    ordinal: ordinal
                ),
                category: category,
                safeEvidenceDigest: safeEvidenceDigest,
                ordinal: ordinal,
                occurrenceCount: 1
            )
        )
    }

    var summary: WayTaskMigrationExceptionSummary {
        WayTaskMigrationExceptionSummary(
            capacity: capacity,
            totalOccurrenceCount: totalOccurrenceCount,
            recordedEntryCount: entries.count,
            overflowOccurrenceCount: overflowOccurrenceCount,
            categoryCounts: Self.sortedCounts(categoryCounts),
            overflowCategoryCounts: Self.sortedCounts(
                overflowCategoryCounts
            )
        )
    }

    func encodedData() throws -> Data {
        let payload = PersistedLedger(
            formatVersion: Self.formatVersion,
            capacity: capacity,
            totalOccurrenceCount: totalOccurrenceCount,
            overflowOccurrenceCount: overflowOccurrenceCount,
            entries: entries,
            categoryCounts: Self.sortedCounts(categoryCounts),
            overflowCategoryCounts: Self.sortedCounts(
                overflowCategoryCounts
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private static func sortedCounts(
        _ counts: [WayTaskMigrationExceptionCategory: Int]
    ) -> [WayTaskMigrationExceptionCategoryCount] {
        WayTaskMigrationExceptionCategory.allCases.compactMap { category in
            guard let count = counts[category], count > 0 else {
                return nil
            }
            return WayTaskMigrationExceptionCategoryCount(
                category: category,
                count: count
            )
        }
    }

    private struct PersistedLedger: Codable {
        let formatVersion: Int
        let capacity: Int
        let totalOccurrenceCount: Int
        let overflowOccurrenceCount: Int
        let entries: [WayTaskMigrationExceptionEntry]
        let categoryCounts: [WayTaskMigrationExceptionCategoryCount]
        let overflowCategoryCounts:
            [WayTaskMigrationExceptionCategoryCount]
    }
}

// MARK: - Stage result

enum WayTaskMigrationStageStatus: String, Codable, Sendable {
    case candidateCreated = "candidate_created"
    case sourceCopied = "source_copied"
    case physicalMigrationCompleted = "physical_migration_completed"
    case candidateReopened = "candidate_reopened"
    case foundationValidated = "foundation_validated"
    case productListSemanticMigrationComplete =
        "product_list_semantic_migration_complete"
    case failedBeforePromotion = "failed_before_promotion"
}

enum WayTaskMigrationCompletionClassification: String, Codable, Sendable {
    case candidateReadyForSemanticMigration =
        "candidate_ready_for_semantic_migration"
    case productListSemanticMigrationComplete =
        "product_list_semantic_migration_complete"
    case failedBeforePromotion = "failed_before_promotion"
}

enum WayTaskMigrationFailureClassification: String, Codable, Sendable {
    case missingSource = "missing_source"
    case unreadableSource = "unreadable_source"
    case unknownSchemaIdentity = "unknown_schema_identity"
    case unsupportedSchemaIdentity = "unsupported_schema_identity"
    case inconsistentSourceInventory = "inconsistent_source_inventory"
    case candidateOwnershipConflict = "candidate_ownership_conflict"
    case insufficientDestinationSpace = "insufficient_destination_space"
    case candidateCreationFailed = "candidate_creation_failed"
    case physicalMigrationFailed = "physical_migration_failed"
    case candidateReopenFailed = "candidate_reopen_failed"
    case validationFailed = "validation_failed"
    case sourceFingerprintDrift = "source_fingerprint_drift"
    case sourceRevalidationFailed = "source_revalidation_failed"
    case candidateFingerprintMismatch = "candidate_fingerprint_mismatch"
    case exceptionLedgerWriteFailed = "exception_ledger_write_failed"
    case interruptedAttemptCleanupFailed =
        "interrupted_attempt_cleanup_failed"
    case cleanupFailed = "cleanup_failed"
    case semanticCandidateReadFailed = "semantic_candidate_read_failed"
    case semanticNormalizationFailed = "semantic_normalization_failed"
    case semanticTargetCreationFailed = "semantic_target_creation_failed"
    case semanticTargetReopenFailed = "semantic_target_reopen_failed"
    case semanticValidationFailed = "semantic_validation_failed"
    case semanticFingerprintMismatch = "semantic_fingerprint_mismatch"
}

enum WayTaskMigrationRollbackClassification: String, Codable, Sendable {
    case notRequired = "not_required"
    case candidateRemovedSourceVerified =
        "candidate_removed_source_verified"
    case candidateRemovedSourceRevalidationFailed =
        "candidate_removed_source_revalidation_failed"
    case cleanupFailedSourceVerified = "cleanup_failed_source_verified"
    case cleanupFailedSourceRevalidationFailed =
        "cleanup_failed_source_revalidation_failed"
    case sourceFingerprintDrift = "source_fingerprint_drift"
}

struct WayTaskMigrationCandidateValidation: Equatable, Sendable {
    let schemaIdentity: WayTaskMigrationSchemaIdentity
    let recordCounts: [String: Int]
}

struct WayTaskMigrationDiagnostic: Equatable, Sendable {
    let status: WayTaskMigrationStageStatus
    let completion:
        WayTaskMigrationCompletionClassification
    let failure: WayTaskMigrationFailureClassification?
    let sourceSchema: WayTaskMigrationSchemaIdentity?
    let candidateSchema: WayTaskMigrationSchemaIdentity?
    let stageIdentity: String?
    let attemptIdentity: String?
    let sourceFingerprint: String?
    let candidateFingerprint: String?
    let exceptionCount: Int
    let exceptionOverflowCount: Int
}

struct WayTaskMigrationCandidateReceipt: Sendable {
    let sourceSchemaIdentity: WayTaskMigrationSchemaIdentity
    let candidateSchemaIdentity: WayTaskMigrationSchemaIdentity
    let inactiveSemanticTargetSchemaIdentity:
        WayTaskMigrationSchemaIdentity
    let stageIdentity: WayTaskMigrationStageIdentity
    let attemptIdentity: WayTaskMigrationAttemptIdentity
    let sourceInventory: WayTaskMigrationStoreInventory
    let sourceFingerprint: WayTaskMigrationFingerprint
    let candidateFingerprint: WayTaskMigrationFingerprint
    let candidateValidation: WayTaskMigrationCandidateValidation
    let exceptionSummary: WayTaskMigrationExceptionSummary
    let status: WayTaskMigrationStageStatus
    let completion:
        WayTaskMigrationCompletionClassification
    let candidateRootURL: URL
    let candidateAttemptDirectoryURL: URL
    let candidateStoreURL: URL
    let ownedArtifactNames: [String]
    let recoveredInterruptedAttempt: Bool

    var semanticConversionCompleted: Bool { false }
    var promotionAuthorized: Bool { false }

    var diagnostic: WayTaskMigrationDiagnostic {
        WayTaskMigrationDiagnostic(
            status: status,
            completion: completion,
            failure: nil,
            sourceSchema: sourceSchemaIdentity,
            candidateSchema: candidateSchemaIdentity,
            stageIdentity: stageIdentity.rawValue,
            attemptIdentity: attemptIdentity.rawValue,
            sourceFingerprint: sourceFingerprint.rawValue,
            candidateFingerprint: candidateFingerprint.rawValue,
            exceptionCount: exceptionSummary.totalOccurrenceCount,
            exceptionOverflowCount:
                exceptionSummary.overflowOccurrenceCount
        )
    }
}

struct WayTaskMigrationFailure: Sendable {
    let classification: WayTaskMigrationFailureClassification
    let triggeringClassification:
        WayTaskMigrationFailureClassification
    let precedingClassification:
        WayTaskMigrationFailureClassification?
    let rollbackClassification: WayTaskMigrationRollbackClassification
    let stageIdentity: WayTaskMigrationStageIdentity?
    let attemptIdentity: WayTaskMigrationAttemptIdentity?
    let sourceSchemaIdentity: WayTaskMigrationSchemaIdentity?
    let sourceFingerprint: WayTaskMigrationFingerprint?
    let finalSourceFingerprint: WayTaskMigrationFingerprint?
    let sourceBytesVerifiedUnchanged: Bool
    let candidateArtifactsRemain: Bool
    let exceptionSummary: WayTaskMigrationExceptionSummary

    var status: WayTaskMigrationStageStatus { .failedBeforePromotion }
    var completion: WayTaskMigrationCompletionClassification {
        .failedBeforePromotion
    }
    var promotionAuthorized: Bool { false }

    var diagnostic: WayTaskMigrationDiagnostic {
        WayTaskMigrationDiagnostic(
            status: status,
            completion: completion,
            failure: classification,
            sourceSchema: sourceSchemaIdentity,
            candidateSchema: stageIdentity?.candidateSchema,
            stageIdentity: stageIdentity?.rawValue,
            attemptIdentity: attemptIdentity?.rawValue,
            sourceFingerprint: sourceFingerprint?.rawValue,
            candidateFingerprint: nil,
            exceptionCount: exceptionSummary.totalOccurrenceCount,
            exceptionOverflowCount:
                exceptionSummary.overflowOccurrenceCount
        )
    }
}

enum WayTaskMigrationPreparationResult: Sendable {
    case candidateReady(WayTaskMigrationCandidateReceipt)
    case failed(WayTaskMigrationFailure)
}

struct WayTaskMigrationRequest: Sendable {
    let sourceStoreURL: URL
    let candidateRootURL: URL
    let attemptSeed: UUID
    let exceptionLedgerCapacity: Int

    init(
        sourceStoreURL: URL,
        candidateRootURL: URL,
        attemptSeed: UUID,
        exceptionLedgerCapacity: Int = 256
    ) {
        self.sourceStoreURL = sourceStoreURL
        self.candidateRootURL = candidateRootURL
        self.attemptSeed = attemptSeed
        self.exceptionLedgerCapacity = max(exceptionLedgerCapacity, 0)
    }
}

struct WayTaskMigrationCleanupResult: Equatable, Sendable {
    let removedOwnedArtifactCount: Int
    let sourceWasAccessed: Bool
    let succeeded: Bool
}

// MARK: - T-07 Product/list semantic records

struct WayTaskLegacyProductRecord: Equatable, Sendable {
    let sourceRecordID: UUID
    let productID: UUID?
    let legacyShoppingItemID: UUID?
    let name: String
    let imageData: Data?
    let brand: String?
    let category: String?
    let barcode: String?
    let imageURLString: String?
    let sourceRawValue: String
    let productType: String?
    let flavor: String?
    let packageSize: String?
    let packageType: String?
    let visibleText: String?
    let searchKeywordsRawValue: String?
    let catalogProductIDRawValue: String?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshotRawValue: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let removedAt: Date?

    init(
        sourceRecordID: UUID,
        productID: UUID?,
        legacyShoppingItemID: UUID? = nil,
        name: String,
        imageData: Data? = nil,
        brand: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        imageURLString: String? = nil,
        sourceRawValue: String = ProductSource.manual.rawValue,
        productType: String? = nil,
        flavor: String? = nil,
        packageSize: String? = nil,
        packageType: String? = nil,
        visibleText: String? = nil,
        searchKeywordsRawValue: String? = nil,
        catalogProductIDRawValue: String? = nil,
        catalogDisplayNameSnapshot: String? = nil,
        catalogDisplayLocaleSnapshot: String? = nil,
        catalogCategoryIDSnapshotRawValue: String? = nil,
        catalogCategoryDisplayNameSnapshot: String? = nil,
        catalogIconKeySnapshot: String? = nil,
        catalogSnapshotUpdatedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        removedAt: Date? = nil
    ) {
        self.sourceRecordID = sourceRecordID
        self.productID = productID
        self.legacyShoppingItemID = legacyShoppingItemID
        self.name = name
        self.imageData = imageData
        self.brand = brand
        self.category = category
        self.barcode = barcode
        self.imageURLString = imageURLString
        self.sourceRawValue = sourceRawValue
        self.productType = productType
        self.flavor = flavor
        self.packageSize = packageSize
        self.packageType = packageType
        self.visibleText = visibleText
        self.searchKeywordsRawValue = searchKeywordsRawValue
        self.catalogProductIDRawValue = catalogProductIDRawValue
        self.catalogDisplayNameSnapshot = catalogDisplayNameSnapshot
        self.catalogDisplayLocaleSnapshot = catalogDisplayLocaleSnapshot
        self.catalogCategoryIDSnapshotRawValue =
            catalogCategoryIDSnapshotRawValue
        self.catalogCategoryDisplayNameSnapshot =
            catalogCategoryDisplayNameSnapshot
        self.catalogIconKeySnapshot = catalogIconKeySnapshot
        self.catalogSnapshotUpdatedAt = catalogSnapshotUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removedAt = removedAt
    }
}

struct WayTaskLegacyShoppingListRecord: Equatable, Sendable {
    let sourceRecordID: UUID
    let listID: UUID?
    let title: String
    let kindRawValue: String
    let createdAt: Date
    let updatedAt: Date
    let isDefault: Bool
}

struct WayTaskLegacyShoppingEntryRecord: Equatable, Sendable {
    let sourceRecordID: UUID
    let entryID: UUID?
    let listID: UUID?
    let productID: UUID?
    let relationshipProductID: UUID?
    let legacyShoppingItemID: UUID?
    let quantity: Double
    let isChecked: Bool
    let createdAt: Date
    let sortOrder: Double
}

struct WayTaskLegacyCompatibilityRecord: Equatable, Sendable {
    let sourceRecordID: UUID
    let compatibilityID: UUID
    let isCompleted: Bool
}

struct WayTaskLegacyProductListSnapshot: Equatable, Sendable {
    let products: [WayTaskLegacyProductRecord]
    let lists: [WayTaskLegacyShoppingListRecord]
    let entries: [WayTaskLegacyShoppingEntryRecord]
    let compatibilityRecords: [WayTaskLegacyCompatibilityRecord]
}

struct WayTaskMigratedProductRecord: Equatable, Codable, Sendable {
    let id: UUID
    let revision: UInt64
    let libraryLifecycleRawValue: String
    let libraryRemovedAt: Date?
    let name: String
    let imageData: Data?
    let brand: String?
    let category: String?
    let barcode: String?
    let imageURLString: String?
    let sourceRawValue: String
    let catalogProductIDRawValue: String?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshotRawValue: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct WayTaskMigratedShoppingListRecord: Equatable, Codable, Sendable {
    let id: UUID
    let revision: UInt64
    let title: String
    let purposeRawValue: String?
    let createdAt: Date
    let updatedAt: Date
}

struct WayTaskMigratedShoppingEntryRecord: Equatable, Codable, Sendable {
    let id: UUID
    let shoppingListID: UUID
    let productID: UUID
    let lifecycleRawValue: String
    let resolutionReasonRawValue: String?
    let resolutionEffectiveAt: Date?
    let resolutionProvenanceRawValue: String?
    let quantity: Double
    let sortOrder: Double
    let createdAt: Date
    let updatedAt: Date
}

enum WayTaskProductListAliasKind: String, Codable, Sendable {
    case product
    case shoppingList = "shopping_list"
    case shoppingEntry = "shopping_entry"
    case compatibilityEvidence = "compatibility_evidence"
}

struct WayTaskProductListAliasRecord: Equatable, Codable, Sendable {
    let kind: WayTaskProductListAliasKind
    let sourceIdentity: UUID
    let canonicalIdentity: UUID
    let sourceEvidenceDigest: WayTaskMigrationSafeDigest
    let ordinal: Int
}

struct WayTaskProductListSemanticSnapshot: Equatable, Codable, Sendable {
    let products: [WayTaskMigratedProductRecord]
    let lists: [WayTaskMigratedShoppingListRecord]
    let entries: [WayTaskMigratedShoppingEntryRecord]
}

struct WayTaskProductListSemanticPlan: Equatable, Sendable {
    static let initialProductRevision: UInt64 = 1
    static let initialListRevision: UInt64 = 1

    let target: WayTaskProductListSemanticSnapshot
    let aliases: [WayTaskProductListAliasRecord]
    let exceptionFacts: [WayTaskProductListSemanticExceptionFact]
    let deferredArchiveListCount: Int
    let deferredArchiveEntryCount: Int
    let compatibilityEvidenceCount: Int
    let blockingAmbiguityCount: Int
    let semanticDigest: WayTaskMigrationFingerprint
}

struct WayTaskProductListSemanticExceptionFact: Equatable, Sendable {
    let category: WayTaskMigrationExceptionCategory
    let safeEvidenceDigest: WayTaskMigrationSafeDigest
}

struct WayTaskProductListSemanticStageIdentity: Hashable, Codable, Sendable {
    static let version = "wt033a.tc13.t07.product-list.v1"

    let foundationStageIdentity: WayTaskMigrationStageIdentity
    let sourceSchemaIdentity: WayTaskMigrationSchemaIdentity
    let candidateSchemaIdentity: WayTaskMigrationSchemaIdentity
    let rawValue: String

    init(foundationStageIdentity: WayTaskMigrationStageIdentity) {
        self.foundationStageIdentity = foundationStageIdentity
        sourceSchemaIdentity = .v3
        candidateSchemaIdentity = .v4
        rawValue = WayTaskMigrationDigest.hex(
            hashing: Data(
                [
                    Self.version,
                    foundationStageIdentity.rawValue,
                    sourceSchemaIdentity.rawValue,
                    candidateSchemaIdentity.rawValue
                ].joined(separator: "|").utf8
            )
        )
    }
}

struct WayTaskProductListSemanticReceipt: Sendable {
    let foundationReceipt: WayTaskMigrationCandidateReceipt
    let semanticStageIdentity: WayTaskProductListSemanticStageIdentity
    let targetStoreURL: URL
    let targetFingerprint: WayTaskMigrationFingerprint
    let semanticDigest: WayTaskMigrationFingerprint
    let targetValidation: WayTaskProductListSemanticSnapshot
    let aliases: [WayTaskProductListAliasRecord]
    let exceptionSummary: WayTaskMigrationExceptionSummary
    let ownedArtifactNames: [String]
    let status: WayTaskMigrationStageStatus
    let completion: WayTaskMigrationCompletionClassification
    let deferredArchiveListCount: Int
    let deferredArchiveEntryCount: Int
    let compatibilityEvidenceCount: Int

    var semanticConversionCompleted: Bool { true }
    var productListSemanticConversionCompleted: Bool { true }
    var sessionHistoryLocationSemanticConversionCompleted: Bool { false }
    var promotionAuthorized: Bool { false }
    var startupActivationAuthorized: Bool { false }
}

enum WayTaskProductListSemanticMigrationResult: Sendable {
    case complete(WayTaskProductListSemanticReceipt)
    case failed(WayTaskMigrationFailure)
}

enum WayTaskProductListSemanticNormalizer {
    static func normalize(
        _ source: WayTaskLegacyProductListSnapshot,
        recordingTime: Date
    ) throws -> WayTaskProductListSemanticPlan {
        var facts: [WayTaskProductListSemanticExceptionFact] = []
        var pendingAliases: [PendingAlias] = []
        var blockingAmbiguityCount = 0

        let compatibilityGroups = Dictionary(
            grouping: source.compatibilityRecords,
            by: \.compatibilityID
        )
        var compatibilityStates: [UUID: Set<Bool>] = [:]
        for compatibilityID in compatibilityGroups.keys.sorted(by: uuidLess) {
            let rows = compatibilityGroups[compatibilityID]!.sorted {
                uuidLess($0.sourceRecordID, $1.sourceRecordID)
            }
            compatibilityStates[compatibilityID] = Set(rows.map(\.isCompleted))
            if rows.count > 1 {
                for row in rows.dropFirst() {
                    pendingAliases.append(
                        PendingAlias(
                            kind: .compatibilityEvidence,
                            sourceIdentity: row.compatibilityID,
                            canonicalIdentity: rows[0].compatibilityID,
                            evidenceID: row.sourceRecordID
                        )
                    )
                    facts.append(fact(.duplicateMerge, [
                        "compatibility", compatibilityID.uuidString,
                        row.sourceRecordID.uuidString
                    ]))
                }
            }
            if compatibilityStates[compatibilityID]?.count != 1 {
                facts.append(fact(.ambiguousRecord, [
                    "compatibility-state", compatibilityID.uuidString
                ]))
            }
        }

        var validProducts: [WayTaskLegacyProductRecord] = []
        for row in source.products.sorted(by: productSourceLess) {
            guard row.productID != nil else {
                facts.append(fact(.missingProductIdentity, [
                    "product", row.sourceRecordID.uuidString
                ]))
                continue
            }
            validProducts.append(row)
        }

        var migratedProducts: [WayTaskMigratedProductRecord] = []
        let productGroups = Dictionary(
            grouping: validProducts,
            by: { $0.productID! }
        )
        for productID in productGroups.keys.sorted(by: uuidLess) {
            let rows = productGroups[productID]!.sorted(by: productSourceLess)
            let canonical = rows[0]
            if !rows.allSatisfy({ compatibleProductSnapshot($0, canonical) }) {
                blockingAmbiguityCount += 1
                facts.append(fact(.ambiguousRecord, [
                    "product-snapshot", productID.uuidString
                ]))
            }
            if rows.count > 1 {
                for row in rows.dropFirst() {
                    pendingAliases.append(
                        PendingAlias(
                            kind: .product,
                            sourceIdentity: productID,
                            canonicalIdentity: productID,
                            evidenceID: row.sourceRecordID
                        )
                    )
                    facts.append(fact(.duplicateMerge, [
                        "product", productID.uuidString,
                        row.sourceRecordID.uuidString
                    ]))
                }
            }

            let removalDates = rows.compactMap(\.removedAt).sorted()
            if !removalDates.isEmpty && removalDates.count != rows.count {
                facts.append(fact(.ambiguousRecord, [
                    "product-tombstone", productID.uuidString
                ]))
            }
            if rows.contains(where: hasUnrepresentedProductEvidence) {
                facts.append(fact(.unsupportedRecord, [
                    "product-extra-evidence", productID.uuidString
                ]))
            }

            let exactCatalogID: String?
            if let rawValue = canonical.catalogProductIDRawValue {
                let trimmed = rawValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !trimmed.isEmpty && trimmed == rawValue {
                    exactCatalogID = rawValue
                } else {
                    exactCatalogID = nil
                    facts.append(fact(.ambiguousRecord, [
                        "catalog-identity", productID.uuidString
                    ]))
                }
            } else {
                exactCatalogID = nil
            }

            migratedProducts.append(
                WayTaskMigratedProductRecord(
                    id: productID,
                    revision:
                        WayTaskProductListSemanticPlan.initialProductRevision,
                    libraryLifecycleRawValue: removalDates.isEmpty
                        ? ProductLibraryLifecycle.active.rawValue
                        : ProductLibraryLifecycle.removed.rawValue,
                    libraryRemovedAt: removalDates.first,
                    name: canonical.name,
                    imageData: canonical.imageData,
                    brand: canonical.brand,
                    category: canonical.category,
                    barcode: canonical.barcode,
                    imageURLString: canonical.imageURLString,
                    sourceRawValue: canonical.sourceRawValue,
                    catalogProductIDRawValue: exactCatalogID,
                    catalogDisplayNameSnapshot:
                        canonical.catalogDisplayNameSnapshot,
                    catalogDisplayLocaleSnapshot:
                        canonical.catalogDisplayLocaleSnapshot,
                    catalogCategoryIDSnapshotRawValue:
                        canonical.catalogCategoryIDSnapshotRawValue,
                    catalogCategoryDisplayNameSnapshot:
                        canonical.catalogCategoryDisplayNameSnapshot,
                    catalogIconKeySnapshot:
                        canonical.catalogIconKeySnapshot,
                    catalogSnapshotUpdatedAt:
                        canonical.catalogSnapshotUpdatedAt,
                    createdAt: rows.map(\.createdAt).min()!,
                    updatedAt: rows.map(\.updatedAt).max()!
                )
            )
        }

        var validLists: [WayTaskLegacyShoppingListRecord] = []
        for row in source.lists.sorted(by: listSourceLess) {
            guard row.listID != nil else {
                facts.append(fact(.missingListIdentity, [
                    "list", row.sourceRecordID.uuidString
                ]))
                continue
            }
            validLists.append(row)
        }

        var migratedLists: [WayTaskMigratedShoppingListRecord] = []
        var deferredListIDs = Set<UUID>()
        let listGroups = Dictionary(grouping: validLists, by: { $0.listID! })
        for listID in listGroups.keys.sorted(by: uuidLess) {
            let rows = listGroups[listID]!.sorted(by: listSourceLess)
            let canonical = rows[0]
            if !rows.allSatisfy({
                $0.title == canonical.title &&
                    $0.kindRawValue == canonical.kindRawValue
            }) {
                blockingAmbiguityCount += 1
                facts.append(fact(.ambiguousRecord, [
                    "list-snapshot", listID.uuidString
                ]))
            }
            if rows.count > 1 {
                for row in rows.dropFirst() {
                    pendingAliases.append(
                        PendingAlias(
                            kind: .shoppingList,
                            sourceIdentity: listID,
                            canonicalIdentity: listID,
                            evidenceID: row.sourceRecordID
                        )
                    )
                    facts.append(fact(.duplicateMerge, [
                        "list", listID.uuidString,
                        row.sourceRecordID.uuidString
                    ]))
                }
            }

            if canonical.kindRawValue == ShoppingListKind.completed.rawValue ||
                canonical.kindRawValue == ShoppingListKind.recent.rawValue
            {
                deferredListIDs.insert(listID)
                continue
            }
            guard canonical.kindRawValue == ShoppingListKind.weekly.rawValue
            else {
                blockingAmbiguityCount += 1
                facts.append(fact(.unsupportedRecord, [
                    "list-kind", listID.uuidString
                ]))
                continue
            }
            if rows.contains(where: \.isDefault) {
                facts.append(fact(.unsupportedRecord, [
                    "list-default-evidence", listID.uuidString
                ]))
            }
            migratedLists.append(
                WayTaskMigratedShoppingListRecord(
                    id: listID,
                    revision:
                        WayTaskProductListSemanticPlan.initialListRevision,
                    title: canonical.title,
                    purposeRawValue: canonical.kindRawValue,
                    createdAt: rows.map(\.createdAt).min()!,
                    updatedAt: rows.map(\.updatedAt).max()!
                )
            )
        }

        let migratedProductIDs = Set(migratedProducts.map(\.id))
        let migratedListIDs = Set(migratedLists.map(\.id))
        var eligibleEntries: [WayTaskLegacyShoppingEntryRecord] = []
        var deferredArchiveEntryCount = 0
        for row in source.entries.sorted(by: entrySourceLess) {
            if let listID = row.listID, deferredListIDs.contains(listID) {
                deferredArchiveEntryCount += 1
                continue
            }
            guard let entryID = row.entryID else {
                facts.append(fact(.ambiguousRecord, [
                    "entry-identity", row.sourceRecordID.uuidString
                ]))
                continue
            }
            guard let listID = row.listID else {
                facts.append(fact(.missingListIdentity, [
                    "entry", entryID.uuidString
                ]))
                continue
            }
            guard migratedListIDs.contains(listID) else {
                facts.append(fact(.ambiguousRelationship, [
                    "entry-list", entryID.uuidString, listID.uuidString
                ]))
                continue
            }
            guard let productID = row.productID else {
                facts.append(fact(.missingProductIdentity, [
                    "entry", entryID.uuidString
                ]))
                continue
            }
            guard migratedProductIDs.contains(productID) else {
                facts.append(fact(.ambiguousRelationship, [
                    "entry-product", entryID.uuidString,
                    productID.uuidString
                ]))
                continue
            }
            if row.relationshipProductID != productID {
                facts.append(fact(.ambiguousRelationship, [
                    "relationship-repair", entryID.uuidString,
                    productID.uuidString
                ]))
            }
            eligibleEntries.append(row)
        }

        let entryGroups = Dictionary(
            grouping: eligibleEntries,
            by: { EntryGroupKey(listID: $0.listID!, productID: $0.productID!) }
        )
        var migratedEntries: [WayTaskMigratedShoppingEntryRecord] = []
        for key in entryGroups.keys.sorted() {
            let rows = entryGroups[key]!.sorted(by: entrySurvivorLess)
            let canonical = rows[0]
            if rows.count > 1 {
                for row in rows.dropFirst() {
                    pendingAliases.append(
                        PendingAlias(
                            kind: .shoppingEntry,
                            sourceIdentity: row.entryID!,
                            canonicalIdentity: canonical.entryID!,
                            evidenceID: row.sourceRecordID
                        )
                    )
                    facts.append(fact(.duplicateMerge, [
                        "entry", row.entryID!.uuidString,
                        canonical.entryID!.uuidString
                    ]))
                }
            }

            let validQuantities = rows.map(\.quantity).filter {
                $0.isFinite && $0 > 0
            }
            if validQuantities.count != rows.count {
                facts.append(fact(.unsupportedRecord, [
                    "entry-quantity", canonical.entryID!.uuidString
                ]))
            }
            let validSortOrders = rows.map(\.sortOrder).filter(\.isFinite)
            if validSortOrders.count != rows.count {
                facts.append(fact(.unsupportedRecord, [
                    "entry-sort", canonical.entryID!.uuidString
                ]))
            }

            for row in rows where !row.isChecked {
                if let legacyID = row.legacyShoppingItemID,
                   compatibilityStates[legacyID]?.contains(true) == true
                {
                    facts.append(fact(.legacyFlagContradiction, [
                        "flag", row.entryID!.uuidString,
                        legacyID.uuidString
                    ]))
                }
            }

            let isNeeded = rows.contains { !$0.isChecked }
            migratedEntries.append(
                WayTaskMigratedShoppingEntryRecord(
                    id: canonical.entryID!,
                    shoppingListID: key.listID,
                    productID: key.productID,
                    lifecycleRawValue: isNeeded ? "needed" : "resolved",
                    resolutionReasonRawValue: isNeeded
                        ? nil : ShoppingListResolutionReason
                            .legacyUnknown.rawValue,
                    resolutionEffectiveAt: isNeeded ? nil : recordingTime,
                    resolutionProvenanceRawValue: isNeeded
                        ? nil : "legacyMigration",
                    quantity: validQuantities.max() ?? 1,
                    sortOrder: validSortOrders.min() ?? 0,
                    createdAt: rows.map(\.createdAt).min()!,
                    updatedAt: rows.map(\.createdAt).min()!
                )
            )
        }

        let duplicateEntryIdentities = Dictionary(
            grouping: migratedEntries,
            by: \.id
        ).filter { $0.value.count > 1 }
        for entryID in duplicateEntryIdentities.keys.sorted(by: uuidLess) {
            blockingAmbiguityCount += 1
            facts.append(fact(.ambiguousRecord, [
                "entry-id-collision", entryID.uuidString
            ]))
        }

        let productLifecycle = Dictionary(
            uniqueKeysWithValues: migratedProducts.map {
                ($0.id, $0.libraryLifecycleRawValue)
            }
        )
        for entry in migratedEntries
        where productLifecycle[entry.productID] ==
            ProductLibraryLifecycle.removed.rawValue
        {
            facts.append(fact(.tombstoneActiveReference, [
                "entry", entry.id.uuidString, entry.productID.uuidString
            ]))
        }

        migratedProducts.sort { uuidLess($0.id, $1.id) }
        migratedLists.sort { uuidLess($0.id, $1.id) }
        migratedEntries.sort {
            if $0.shoppingListID != $1.shoppingListID {
                return uuidLess($0.shoppingListID, $1.shoppingListID)
            }
            if $0.productID != $1.productID {
                return uuidLess($0.productID, $1.productID)
            }
            return uuidLess($0.id, $1.id)
        }
        facts.sort {
            if $0.category.rawValue != $1.category.rawValue {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.safeEvidenceDigest.rawValue <
                $1.safeEvidenceDigest.rawValue
        }
        pendingAliases.sort()
        let aliases = pendingAliases.enumerated().map { index, alias in
            WayTaskProductListAliasRecord(
                kind: alias.kind,
                sourceIdentity: alias.sourceIdentity,
                canonicalIdentity: alias.canonicalIdentity,
                sourceEvidenceDigest: WayTaskMigrationSafeDigest(
                    hashing: Data(alias.evidenceID.uuidString.lowercased().utf8)
                ),
                ordinal: index + 1
            )
        }
        let target = WayTaskProductListSemanticSnapshot(
            products: migratedProducts,
            lists: migratedLists,
            entries: migratedEntries
        )
        return WayTaskProductListSemanticPlan(
            target: target,
            aliases: aliases,
            exceptionFacts: facts,
            deferredArchiveListCount: deferredListIDs.count,
            deferredArchiveEntryCount: deferredArchiveEntryCount,
            compatibilityEvidenceCount: source.compatibilityRecords.count,
            blockingAmbiguityCount: blockingAmbiguityCount,
            semanticDigest: try semanticDigest(target)
        )
    }

    static func semanticDigest(
        _ snapshot: WayTaskProductListSemanticSnapshot
    ) throws -> WayTaskMigrationFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return WayTaskMigrationFingerprint(
            rawValue: WayTaskMigrationDigest.hex(
                hashing: try encoder.encode(snapshot)
            )
        )
    }

    private static func compatibleProductSnapshot(
        _ lhs: WayTaskLegacyProductRecord,
        _ rhs: WayTaskLegacyProductRecord
    ) -> Bool {
        lhs.name == rhs.name && lhs.imageData == rhs.imageData &&
            lhs.brand == rhs.brand && lhs.category == rhs.category &&
            lhs.barcode == rhs.barcode &&
            lhs.imageURLString == rhs.imageURLString &&
            lhs.sourceRawValue == rhs.sourceRawValue &&
            lhs.catalogProductIDRawValue == rhs.catalogProductIDRawValue &&
            lhs.catalogDisplayNameSnapshot ==
                rhs.catalogDisplayNameSnapshot &&
            lhs.catalogDisplayLocaleSnapshot ==
                rhs.catalogDisplayLocaleSnapshot &&
            lhs.catalogCategoryIDSnapshotRawValue ==
                rhs.catalogCategoryIDSnapshotRawValue &&
            lhs.catalogCategoryDisplayNameSnapshot ==
                rhs.catalogCategoryDisplayNameSnapshot &&
            lhs.catalogIconKeySnapshot == rhs.catalogIconKeySnapshot &&
            lhs.catalogSnapshotUpdatedAt == rhs.catalogSnapshotUpdatedAt
    }

    nonisolated private static func hasUnrepresentedProductEvidence(
        _ row: WayTaskLegacyProductRecord
    ) -> Bool {
        row.productType != nil || row.flavor != nil ||
            row.packageSize != nil || row.packageType != nil ||
            row.visibleText != nil || row.searchKeywordsRawValue != nil
    }

    private static func fact(
        _ category: WayTaskMigrationExceptionCategory,
        _ components: [String]
    ) -> WayTaskProductListSemanticExceptionFact {
        WayTaskProductListSemanticExceptionFact(
            category: category,
            safeEvidenceDigest: WayTaskMigrationSafeDigest(
                hashing: Data(
                    ([category.rawValue] + components)
                        .joined(separator: "|").lowercased().utf8
                )
            )
        )
    }

    nonisolated private static func uuidLess(
        _ lhs: UUID,
        _ rhs: UUID
    ) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    nonisolated private static func productSourceLess(
        _ lhs: WayTaskLegacyProductRecord,
        _ rhs: WayTaskLegacyProductRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
    }

    nonisolated private static func listSourceLess(
        _ lhs: WayTaskLegacyShoppingListRecord,
        _ rhs: WayTaskLegacyShoppingListRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
    }

    nonisolated private static func entrySourceLess(
        _ lhs: WayTaskLegacyShoppingEntryRecord,
        _ rhs: WayTaskLegacyShoppingEntryRecord
    ) -> Bool {
        if lhs.sourceRecordID != rhs.sourceRecordID {
            return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
        }
        return (lhs.entryID?.uuidString ?? "") <
            (rhs.entryID?.uuidString ?? "")
    }

    nonisolated private static func entrySurvivorLess(
        _ lhs: WayTaskLegacyShoppingEntryRecord,
        _ rhs: WayTaskLegacyShoppingEntryRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        if lhs.entryID != rhs.entryID {
            return (lhs.entryID?.uuidString.lowercased() ?? "") <
                (rhs.entryID?.uuidString.lowercased() ?? "")
        }
        return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
    }

    private struct EntryGroupKey: Hashable, Comparable {
        let listID: UUID
        let productID: UUID

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.listID != rhs.listID {
                return uuidLess(lhs.listID, rhs.listID)
            }
            return uuidLess(lhs.productID, rhs.productID)
        }
    }

    private struct PendingAlias: Comparable {
        let kind: WayTaskProductListAliasKind
        let sourceIdentity: UUID
        let canonicalIdentity: UUID
        let evidenceID: UUID

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            if lhs.sourceIdentity != rhs.sourceIdentity {
                return uuidLess(lhs.sourceIdentity, rhs.sourceIdentity)
            }
            if lhs.canonicalIdentity != rhs.canonicalIdentity {
                return uuidLess(lhs.canonicalIdentity, rhs.canonicalIdentity)
            }
            return uuidLess(lhs.evidenceID, rhs.evidenceID)
        }
    }
}

// MARK: - Injected capabilities

@MainActor
struct WayTaskProductStateMigrationDependencies {
    var inspectStore: (URL) throws -> WayTaskMigrationStoreInventory
    var resolveSchemaIdentity:
        (URL) throws -> WayTaskMigrationSchemaIdentity
    var availableDestinationCapacity: (URL) throws -> Int64
    var createDirectory: (URL) throws -> Void
    var copyItem: (URL, URL) throws -> Void
    var writeOwnedArtifact: (Data, URL) throws -> Void
    var removeOwnedDirectory: (URL) throws -> Void
    var fileExists: (URL) -> Bool
    var readOwnedArtifact: (URL) throws -> Data
    var physicalMigrateCandidate: (URL) throws -> Void
    var reopenCandidate:
        (URL) throws -> WayTaskMigrationCandidateValidation
    var validateCandidate:
        (WayTaskMigrationCandidateValidation) throws -> Void
    var enumerateOwnedArtifacts: (URL) throws -> [String]
    var observeFingerprint:
        (URL, WayTaskMigrationFingerprint) -> WayTaskMigrationFingerprint

    static var live: Self {
        Self(
            inspectStore: WayTaskProtectedStoreInspector.inspect,
            resolveSchemaIdentity:
                WayTaskProtectedStoreSchemaReader.resolve,
            availableDestinationCapacity: { url in
                let values = try url.resourceValues(forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey,
                    .volumeAvailableCapacityKey
                ])
                if let important =
                    values.volumeAvailableCapacityForImportantUsage
                {
                    return important
                }
                if let fallback = values.volumeAvailableCapacity {
                    return Int64(fallback)
                }
                return 0
            },
            createDirectory: { url in
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: false
                )
            },
            copyItem: { source, destination in
                try FileManager.default.copyItem(
                    at: source,
                    to: destination
                )
            },
            writeOwnedArtifact: { data, url in
                try data.write(to: url, options: [.atomic])
            },
            removeOwnedDirectory: { url in
                try FileManager.default.removeItem(at: url)
            },
            fileExists: { url in
                FileManager.default.fileExists(atPath: url.path)
            },
            readOwnedArtifact: { url in
                try Data(contentsOf: url, options: [.mappedIfSafe])
            },
            physicalMigrateCandidate:
                WayTaskCandidatePhysicalStoreBoundary.migrate,
            reopenCandidate:
                WayTaskCandidatePhysicalStoreBoundary.reopen,
            validateCandidate:
                WayTaskCandidatePhysicalStoreBoundary.validate,
            enumerateOwnedArtifacts:
                WayTaskCandidateArtifactInventory.enumerate,
            observeFingerprint: { _, fingerprint in fingerprint }
        )
    }
}

@MainActor
struct WayTaskProductListSemanticMigrationDependencies {
    var readPhysicalCandidate:
        (URL) throws -> WayTaskLegacyProductListSnapshot
    var createTargetStore:
        (WayTaskProductListSemanticSnapshot, URL) throws -> Void
    var reopenTargetStore:
        (URL) throws -> WayTaskProductListSemanticSnapshot
    var recordingTime: (WayTaskMigrationAttemptIdentity) -> Date

    static var live: Self {
        Self(
            readPhysicalCandidate:
                WayTaskProductListSemanticStoreBoundary.readPhysicalCandidate,
            createTargetStore:
                WayTaskProductListSemanticStoreBoundary.createTargetStore,
            reopenTargetStore:
                WayTaskProductListSemanticStoreBoundary.reopenTargetStore,
            recordingTime: { attempt in
                let value = UInt64(
                    attempt.rawValue.prefix(12),
                    radix: 16
                ) ?? 0
                return Date(
                    timeIntervalSinceReferenceDate:
                        TimeInterval(value % 1_577_836_800)
                )
            }
        )
    }
}

// MARK: - Semantic migration owner

@MainActor
struct WayTaskProductStateMigration {
    static let ownerMarkerFilename = ".wt033a-tc13-owner.json"
    static let manifestFilename = "migration-manifest.json"
    static let exceptionLedgerFilename = "migration-exceptions.json"
    static let candidateStoreFilename = "candidate.store"
    static let productListTargetStoreFilename =
        "product-list-semantic-v4.store"
    static let productListAliasFilename = "product-list-aliases.json"
    static let productListSummaryFilename =
        "product-list-semantic-summary.json"
    static let attemptDirectoryPrefix = "wt033a-tc13-"

    private let dependencies: WayTaskProductStateMigrationDependencies
    private let semanticDependencies:
        WayTaskProductListSemanticMigrationDependencies

    init() {
        dependencies = .live
        semanticDependencies = .live
    }

    init(dependencies: WayTaskProductStateMigrationDependencies) {
        self.dependencies = dependencies
        semanticDependencies = .live
    }

    init(
        dependencies: WayTaskProductStateMigrationDependencies,
        semanticDependencies:
            WayTaskProductListSemanticMigrationDependencies
    ) {
        self.dependencies = dependencies
        self.semanticDependencies = semanticDependencies
    }

    func prepareCandidate(
        _ request: WayTaskMigrationRequest
    ) -> WayTaskMigrationPreparationResult {
        let sourceURL = request.sourceStoreURL.standardizedFileURL
        let candidateRootURL =
            request.candidateRootURL.standardizedFileURL
        var sourceInventory: WayTaskMigrationStoreInventory?
        var sourceSchema: WayTaskMigrationSchemaIdentity?
        var stageIdentity: WayTaskMigrationStageIdentity?
        var attemptIdentity: WayTaskMigrationAttemptIdentity?
        var attemptDirectoryURL: URL?
        var attemptCreatedByThisInvocation = false
        var recoveredInterruptedAttempt = false
        let ledger = WayTaskMigrationExceptionLedger(
            capacity: request.exceptionLedgerCapacity
        )

        do {
            let initialInventory = try inspectSource(sourceURL)
            sourceInventory = initialInventory

            let resolvedSchema: WayTaskMigrationSchemaIdentity
            do {
                resolvedSchema = try dependencies.resolveSchemaIdentity(
                    sourceURL
                )
            } catch let error as WayTaskProtectedStoreSchemaError {
                switch error {
                case .unknownIdentity:
                    throw ClassifiedFailure(.unknownSchemaIdentity)
                case .unsupportedIdentity:
                    throw ClassifiedFailure(.unsupportedSchemaIdentity)
                case .unreadable:
                    throw ClassifiedFailure(.unreadableSource)
                }
            } catch {
                throw ClassifiedFailure(.unknownSchemaIdentity)
            }

            guard [.v1, .v2, .v3].contains(resolvedSchema) else {
                throw ClassifiedFailure(.unsupportedSchemaIdentity)
            }
            sourceSchema = resolvedSchema

            try verifySource(
                sourceURL,
                expected: initialInventory.fingerprint
            )
            try validateCandidateRoot(
                candidateRootURL,
                sourceStoreURL: sourceURL
            )

            let requiredCapacity = Self.requiredDestinationCapacity(
                sourceByteCount: initialInventory.totalByteCount
            )
            let availableCapacity: Int64
            do {
                availableCapacity = try dependencies
                    .availableDestinationCapacity(candidateRootURL)
            } catch {
                throw ClassifiedFailure(.insufficientDestinationSpace)
            }
            guard availableCapacity >= requiredCapacity else {
                throw ClassifiedFailure(.insufficientDestinationSpace)
            }

            let stage = WayTaskMigrationStageIdentity(
                sourceSchema: resolvedSchema
            )
            stageIdentity = stage
            let attempt = WayTaskMigrationAttemptIdentity(
                stageIdentity: stage,
                sourceFingerprint: initialInventory.fingerprint,
                attemptSeed: request.attemptSeed
            )
            attemptIdentity = attempt
            let attemptURL = candidateRootURL.appendingPathComponent(
                Self.attemptDirectoryPrefix + attempt.rawValue,
                isDirectory: true
            )
            attemptDirectoryURL = attemptURL

            if dependencies.fileExists(attemptURL) {
                guard try ownsAttemptDirectory(
                    attemptURL,
                    candidateRootURL: candidateRootURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt
                ) else {
                    throw ClassifiedFailure(.candidateOwnershipConflict)
                }
                do {
                    try dependencies.removeOwnedDirectory(attemptURL)
                    recoveredInterruptedAttempt = true
                } catch {
                    throw ClassifiedFailure(
                        .interruptedAttemptCleanupFailed
                    )
                }
            }

            do {
                try dependencies.createDirectory(attemptURL)
                attemptCreatedByThisInvocation = true
                try writeOwnerMarker(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt
                )
                try writeManifest(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: nil,
                    status: .candidateCreated,
                    completion: nil,
                    failure: nil,
                    exceptionSummary: ledger.summary
                )
            } catch {
                throw ClassifiedFailure(.candidateCreationFailed)
            }

            let candidateStoreURL = attemptURL.appendingPathComponent(
                Self.candidateStoreFilename
            )
            do {
                for component in initialInventory.components {
                    let destination = Self.componentURL(
                        for: component.role,
                        storeURL: candidateStoreURL
                    )
                    try dependencies.copyItem(component.url, destination)
                }
                let copiedInventory = try dependencies.inspectStore(
                    candidateStoreURL
                )
                guard Self.hasExactCopiedBytes(
                    source: initialInventory,
                    candidate: copiedInventory
                ) else {
                    throw ClassifiedFailure(.candidateCreationFailed)
                }
                try writeManifest(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: nil,
                    status: .sourceCopied,
                    completion: nil,
                    failure: nil,
                    exceptionSummary: ledger.summary
                )
            } catch let failure as ClassifiedFailure {
                throw failure
            } catch {
                throw ClassifiedFailure(.candidateCreationFailed)
            }

            do {
                let ledgerURL = attemptURL.appendingPathComponent(
                    Self.exceptionLedgerFilename
                )
                try dependencies.writeOwnedArtifact(
                    ledger.encodedData(),
                    ledgerURL
                )
            } catch {
                throw ClassifiedFailure(.exceptionLedgerWriteFailed)
            }

            do {
                try dependencies.physicalMigrateCandidate(candidateStoreURL)
                try writeManifest(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: nil,
                    status: .physicalMigrationCompleted,
                    completion: nil,
                    failure: nil,
                    exceptionSummary: ledger.summary
                )
            } catch let failure as ClassifiedFailure {
                throw failure
            } catch {
                throw ClassifiedFailure(.physicalMigrationFailed)
            }

            try verifySource(
                sourceURL,
                expected: initialInventory.fingerprint
            )

            let candidateSchema: WayTaskMigrationSchemaIdentity
            do {
                candidateSchema = try dependencies.resolveSchemaIdentity(
                    candidateStoreURL
                )
            } catch {
                throw ClassifiedFailure(.validationFailed)
            }
            guard candidateSchema == stage.candidateSchema else {
                throw ClassifiedFailure(.validationFailed)
            }

            let validation: WayTaskMigrationCandidateValidation
            do {
                validation = try dependencies.reopenCandidate(
                    candidateStoreURL
                )
                try writeManifest(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: nil,
                    status: .candidateReopened,
                    completion: nil,
                    failure: nil,
                    exceptionSummary: ledger.summary
                )
            } catch {
                throw ClassifiedFailure(.candidateReopenFailed)
            }

            do {
                try dependencies.validateCandidate(validation)
            } catch {
                throw ClassifiedFailure(.validationFailed)
            }

            let firstCandidateFingerprint: WayTaskMigrationFingerprint
            let secondCandidateFingerprint: WayTaskMigrationFingerprint
            do {
                let firstInventory = try dependencies.inspectStore(
                    candidateStoreURL
                )
                firstCandidateFingerprint = dependencies.observeFingerprint(
                    candidateStoreURL,
                    firstInventory.fingerprint
                )
                let secondInventory = try dependencies.inspectStore(
                    candidateStoreURL
                )
                secondCandidateFingerprint = dependencies.observeFingerprint(
                    candidateStoreURL,
                    secondInventory.fingerprint
                )
            } catch {
                throw ClassifiedFailure(.validationFailed)
            }
            guard firstCandidateFingerprint == secondCandidateFingerprint else {
                throw ClassifiedFailure(.candidateFingerprintMismatch)
            }

            try verifySource(
                sourceURL,
                expected: initialInventory.fingerprint
            )

            do {
                try writeManifest(
                    at: attemptURL,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: secondCandidateFingerprint,
                    status: .foundationValidated,
                    completion: .candidateReadyForSemanticMigration,
                    failure: nil,
                    exceptionSummary: ledger.summary
                )
            } catch {
                throw ClassifiedFailure(.validationFailed)
            }

            let ownedArtifactNames: [String]
            do {
                ownedArtifactNames = try dependencies
                    .enumerateOwnedArtifacts(attemptURL)
            } catch {
                throw ClassifiedFailure(.validationFailed)
            }

            return .candidateReady(
                WayTaskMigrationCandidateReceipt(
                    sourceSchemaIdentity: resolvedSchema,
                    candidateSchemaIdentity: candidateSchema,
                    inactiveSemanticTargetSchemaIdentity: .v4,
                    stageIdentity: stage,
                    attemptIdentity: attempt,
                    sourceInventory: initialInventory,
                    sourceFingerprint: initialInventory.fingerprint,
                    candidateFingerprint: secondCandidateFingerprint,
                    candidateValidation: validation,
                    exceptionSummary: ledger.summary,
                    status: .foundationValidated,
                    completion: .candidateReadyForSemanticMigration,
                    candidateRootURL: candidateRootURL,
                    candidateAttemptDirectoryURL: attemptURL,
                    candidateStoreURL: candidateStoreURL,
                    ownedArtifactNames: ownedArtifactNames,
                    recoveredInterruptedAttempt:
                        recoveredInterruptedAttempt
                )
            )
        } catch let failure as ClassifiedFailure {
            return .failed(
                makeFailure(
                    triggering: failure.classification,
                    sourceStoreURL: sourceURL,
                    candidateRootURL: candidateRootURL,
                    sourceInventory: sourceInventory,
                    sourceSchema: sourceSchema,
                    stageIdentity: stageIdentity,
                    attemptIdentity: attemptIdentity,
                    attemptDirectoryURL: attemptDirectoryURL,
                    attemptCreatedByThisInvocation:
                        attemptCreatedByThisInvocation,
                    exceptionSummary: ledger.summary
                )
            )
        } catch {
            return .failed(
                makeFailure(
                    triggering: .validationFailed,
                    sourceStoreURL: sourceURL,
                    candidateRootURL: candidateRootURL,
                    sourceInventory: sourceInventory,
                    sourceSchema: sourceSchema,
                    stageIdentity: stageIdentity,
                    attemptIdentity: attemptIdentity,
                    attemptDirectoryURL: attemptDirectoryURL,
                    attemptCreatedByThisInvocation:
                        attemptCreatedByThisInvocation,
                    exceptionSummary: ledger.summary
                )
            )
        }
    }

    func cleanupOwnedCandidate(
        _ receipt: WayTaskMigrationCandidateReceipt
    ) -> WayTaskMigrationCleanupResult {
        guard (try? ownsAttemptDirectory(
            receipt.candidateAttemptDirectoryURL,
            candidateRootURL: receipt.candidateRootURL,
            stageIdentity: receipt.stageIdentity,
            attemptIdentity: receipt.attemptIdentity
        )) == true else {
            return WayTaskMigrationCleanupResult(
                removedOwnedArtifactCount: 0,
                sourceWasAccessed: false,
                succeeded: false
            )
        }

        let count = (try? dependencies.enumerateOwnedArtifacts(
            receipt.candidateAttemptDirectoryURL
        ).count) ?? 0
        do {
            try dependencies.removeOwnedDirectory(
                receipt.candidateAttemptDirectoryURL
            )
            return WayTaskMigrationCleanupResult(
                removedOwnedArtifactCount: count,
                sourceWasAccessed: false,
                succeeded: true
            )
        } catch {
            return WayTaskMigrationCleanupResult(
                removedOwnedArtifactCount: 0,
                sourceWasAccessed: false,
                succeeded: false
            )
        }
    }

    private func inspectSource(
        _ sourceURL: URL
    ) throws -> WayTaskMigrationStoreInventory {
        do {
            return try dependencies.inspectStore(sourceURL)
        } catch let error as WayTaskProtectedStoreInspectionError {
            switch error {
            case .missingDatabase:
                throw ClassifiedFailure(.missingSource)
            case .unreadableComponent:
                throw ClassifiedFailure(.unreadableSource)
            case .invalidComponent, .unknownSidecar,
                    .inconsistentSidecars, .componentChangedDuringRead:
                throw ClassifiedFailure(.inconsistentSourceInventory)
            }
        } catch {
            throw ClassifiedFailure(.unreadableSource)
        }
    }

    private func verifySource(
        _ sourceURL: URL,
        expected: WayTaskMigrationFingerprint
    ) throws {
        let current: WayTaskMigrationStoreInventory
        do {
            current = try dependencies.inspectStore(sourceURL)
        } catch {
            throw ClassifiedFailure(.sourceRevalidationFailed)
        }
        let observed = dependencies.observeFingerprint(
            sourceURL,
            current.fingerprint
        )
        guard observed == expected else {
            throw ClassifiedFailure(.sourceFingerprintDrift)
        }
    }

    private func validateCandidateRoot(
        _ candidateRootURL: URL,
        sourceStoreURL: URL
    ) throws {
        guard candidateRootURL.isFileURL,
              sourceStoreURL.isFileURL,
              candidateRootURL != sourceStoreURL.deletingLastPathComponent(),
              !Self.path(candidateRootURL, contains: sourceStoreURL),
              !Self.path(sourceStoreURL, contains: candidateRootURL)
        else {
            throw ClassifiedFailure(.candidateOwnershipConflict)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidateRootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ClassifiedFailure(.candidateCreationFailed)
        }
    }

    private func ownsAttemptDirectory(
        _ attemptURL: URL,
        candidateRootURL: URL,
        stageIdentity: WayTaskMigrationStageIdentity,
        attemptIdentity: WayTaskMigrationAttemptIdentity
    ) throws -> Bool {
        let expectedURL = candidateRootURL.appendingPathComponent(
            Self.attemptDirectoryPrefix + attemptIdentity.rawValue,
            isDirectory: true
        ).standardizedFileURL
        guard attemptURL.standardizedFileURL == expectedURL else {
            return false
        }
        let markerURL = attemptURL.appendingPathComponent(
            Self.ownerMarkerFilename
        )
        let data = try dependencies.readOwnedArtifact(markerURL)
        let marker = try JSONDecoder().decode(OwnerMarker.self, from: data)
        return marker.formatVersion == 1 &&
            marker.stageIdentity == stageIdentity.rawValue &&
            marker.attemptIdentity == attemptIdentity.rawValue
    }

    private func writeOwnerMarker(
        at attemptURL: URL,
        stageIdentity: WayTaskMigrationStageIdentity,
        attemptIdentity: WayTaskMigrationAttemptIdentity
    ) throws {
        let marker = OwnerMarker(
            formatVersion: 1,
            stageIdentity: stageIdentity.rawValue,
            attemptIdentity: attemptIdentity.rawValue
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dependencies.writeOwnedArtifact(
            encoder.encode(marker),
            attemptURL.appendingPathComponent(Self.ownerMarkerFilename)
        )
    }

    private func writeManifest(
        at attemptURL: URL,
        stageIdentity: WayTaskMigrationStageIdentity,
        attemptIdentity: WayTaskMigrationAttemptIdentity,
        sourceFingerprint: WayTaskMigrationFingerprint,
        candidateFingerprint: WayTaskMigrationFingerprint?,
        status: WayTaskMigrationStageStatus,
        completion: WayTaskMigrationCompletionClassification?,
        failure: WayTaskMigrationFailureClassification?,
        exceptionSummary: WayTaskMigrationExceptionSummary,
        semanticStageIdentity: String? = nil,
        semanticTargetFingerprint: String? = nil,
        semanticDigest: String? = nil
    ) throws {
        let manifest = CandidateManifest(
            formatVersion: 1,
            foundationVersion:
                WayTaskMigrationStageIdentity.foundationVersion,
            sourceSchemaIdentity: stageIdentity.sourceSchema.rawValue,
            candidateSchemaIdentity: stageIdentity.candidateSchema.rawValue,
            inactiveSemanticTargetSchemaIdentity:
                WayTaskMigrationSchemaIdentity.v4.rawValue,
            stageIdentity: stageIdentity.rawValue,
            attemptIdentity: attemptIdentity.rawValue,
            sourceFingerprint: sourceFingerprint.rawValue,
            candidateFingerprint: candidateFingerprint?.rawValue,
            status: status,
            completion: completion,
            failure: failure,
            exceptionSummary: exceptionSummary,
            semanticStageIdentity: semanticStageIdentity,
            semanticTargetFingerprint: semanticTargetFingerprint,
            semanticDigest: semanticDigest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dependencies.writeOwnedArtifact(
            encoder.encode(manifest),
            attemptURL.appendingPathComponent(Self.manifestFilename)
        )
    }

    private func makeFailure(
        triggering: WayTaskMigrationFailureClassification,
        sourceStoreURL: URL,
        candidateRootURL: URL,
        sourceInventory: WayTaskMigrationStoreInventory?,
        sourceSchema: WayTaskMigrationSchemaIdentity?,
        stageIdentity: WayTaskMigrationStageIdentity?,
        attemptIdentity: WayTaskMigrationAttemptIdentity?,
        attemptDirectoryURL: URL?,
        attemptCreatedByThisInvocation: Bool,
        exceptionSummary: WayTaskMigrationExceptionSummary
    ) -> WayTaskMigrationFailure {
        var cleanupSucceeded = true
        var cleanupWasRequired = false

        if let attemptDirectoryURL,
           dependencies.fileExists(attemptDirectoryURL)
        {
            cleanupWasRequired = true
            let ownsDirectory: Bool
            if attemptCreatedByThisInvocation {
                ownsDirectory = Self.isExpectedAttemptPath(
                    attemptDirectoryURL,
                    candidateRootURL: candidateRootURL,
                    attemptIdentity: attemptIdentity
                )
            } else if let stageIdentity, let attemptIdentity {
                ownsDirectory = (try? ownsAttemptDirectory(
                    attemptDirectoryURL,
                    candidateRootURL: candidateRootURL,
                    stageIdentity: stageIdentity,
                    attemptIdentity: attemptIdentity
                )) == true
            } else {
                ownsDirectory = false
            }

            if ownsDirectory {
                do {
                    try dependencies.removeOwnedDirectory(
                        attemptDirectoryURL
                    )
                } catch {
                    cleanupSucceeded = false
                }
            } else {
                cleanupSucceeded = false
            }
        }

        var finalSourceFingerprint: WayTaskMigrationFingerprint?
        var sourceUnchanged = false
        var sourceRevalidationSucceeded = sourceInventory == nil
        if let sourceInventory {
            do {
                let finalInventory = try dependencies.inspectStore(
                    sourceStoreURL
                )
                let observed = dependencies.observeFingerprint(
                    sourceStoreURL,
                    finalInventory.fingerprint
                )
                finalSourceFingerprint = observed
                sourceRevalidationSucceeded = true
                sourceUnchanged = observed == sourceInventory.fingerprint
            } catch {
                sourceRevalidationSucceeded = false
            }
        }

        let terminalClassification:
            WayTaskMigrationFailureClassification
        let precedingClassification:
            WayTaskMigrationFailureClassification?
        if sourceInventory != nil && sourceRevalidationSucceeded &&
            !sourceUnchanged
        {
            terminalClassification = .sourceFingerprintDrift
            precedingClassification = triggering == .sourceFingerprintDrift
                ? nil : triggering
        } else if sourceInventory != nil && !sourceRevalidationSucceeded {
            terminalClassification = .sourceRevalidationFailed
            precedingClassification = triggering == .sourceRevalidationFailed
                ? nil : triggering
        } else if cleanupWasRequired && !cleanupSucceeded {
            terminalClassification = .cleanupFailed
            precedingClassification = triggering
        } else {
            terminalClassification = triggering
            precedingClassification = nil
        }

        let rollbackClassification:
            WayTaskMigrationRollbackClassification
        if sourceInventory != nil && sourceRevalidationSucceeded &&
            !sourceUnchanged
        {
            rollbackClassification = .sourceFingerprintDrift
        } else if cleanupWasRequired && !cleanupSucceeded {
            rollbackClassification = sourceRevalidationSucceeded
                ? .cleanupFailedSourceVerified
                : .cleanupFailedSourceRevalidationFailed
        } else if cleanupWasRequired {
            rollbackClassification = sourceRevalidationSucceeded
                ? .candidateRemovedSourceVerified
                : .candidateRemovedSourceRevalidationFailed
        } else {
            rollbackClassification = .notRequired
        }

        return WayTaskMigrationFailure(
            classification: terminalClassification,
            triggeringClassification: triggering,
            precedingClassification: precedingClassification,
            rollbackClassification: rollbackClassification,
            stageIdentity: stageIdentity,
            attemptIdentity: attemptIdentity,
            sourceSchemaIdentity: sourceSchema,
            sourceFingerprint: sourceInventory?.fingerprint,
            finalSourceFingerprint: finalSourceFingerprint,
            sourceBytesVerifiedUnchanged: sourceUnchanged,
            candidateArtifactsRemain: cleanupWasRequired && !cleanupSucceeded,
            exceptionSummary: exceptionSummary
        )
    }

    private static func requiredDestinationCapacity(
        sourceByteCount: UInt64
    ) -> Int64 {
        let minimum: UInt64 = 4 * 1_024 * 1_024
        let multiplied: UInt64
        if sourceByteCount > UInt64.max / 3 {
            multiplied = UInt64.max
        } else {
            multiplied = sourceByteCount * 3
        }
        let required = max(minimum, multiplied)
        return required > UInt64(Int64.max)
            ? Int64.max
            : Int64(required)
    }

    private static func hasExactCopiedBytes(
        source: WayTaskMigrationStoreInventory,
        candidate: WayTaskMigrationStoreInventory
    ) -> Bool {
        guard source.fingerprint == candidate.fingerprint,
              source.components.count == candidate.components.count
        else {
            return false
        }
        return zip(source.components, candidate.components).allSatisfy {
            sourceComponent, candidateComponent in
            sourceComponent.role == candidateComponent.role &&
                sourceComponent.byteCount == candidateComponent.byteCount &&
                sourceComponent.fingerprint ==
                    candidateComponent.fingerprint
        }
    }

    private static func componentURL(
        for role: WayTaskMigrationStoreComponentRole,
        storeURL: URL
    ) -> URL {
        guard role != .database else { return storeURL }
        return URL(fileURLWithPath: storeURL.path + role.suffix)
    }

    private static func path(_ directory: URL, contains file: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        return filePath == directoryPath ||
            filePath.hasPrefix(directoryPath + "/")
    }

    private static func isExpectedAttemptPath(
        _ attemptURL: URL,
        candidateRootURL: URL,
        attemptIdentity: WayTaskMigrationAttemptIdentity?
    ) -> Bool {
        guard let attemptIdentity else { return false }
        return attemptURL.standardizedFileURL == candidateRootURL
            .appendingPathComponent(
                attemptDirectoryPrefix + attemptIdentity.rawValue,
                isDirectory: true
            ).standardizedFileURL
    }

    private struct OwnerMarker: Codable {
        let formatVersion: Int
        let stageIdentity: String
        let attemptIdentity: String
    }

    private struct CandidateManifest: Codable {
        let formatVersion: Int
        let foundationVersion: String
        let sourceSchemaIdentity: String
        let candidateSchemaIdentity: String
        let inactiveSemanticTargetSchemaIdentity: String
        let stageIdentity: String
        let attemptIdentity: String
        let sourceFingerprint: String
        let candidateFingerprint: String?
        let status: WayTaskMigrationStageStatus
        let completion: WayTaskMigrationCompletionClassification?
        let failure: WayTaskMigrationFailureClassification?
        let exceptionSummary: WayTaskMigrationExceptionSummary
        let semanticStageIdentity: String?
        let semanticTargetFingerprint: String?
        let semanticDigest: String?
    }

    private struct ClassifiedFailure: Error {
        let classification: WayTaskMigrationFailureClassification

        init(_ classification: WayTaskMigrationFailureClassification) {
            self.classification = classification
        }
    }
}

// MARK: - T-07 Product/list semantic candidate stage

extension WayTaskProductStateMigration {
    func migrateProductListSemantics(
        _ receipt: WayTaskMigrationCandidateReceipt
    ) -> WayTaskProductListSemanticMigrationResult {
        let sourceURL = receipt.sourceInventory.components.first {
            $0.role == .database
        }?.url
        var ledger = WayTaskMigrationExceptionLedger(
            capacity: receipt.exceptionSummary.capacity
        )

        func fail(
            _ classification: WayTaskMigrationFailureClassification
        ) -> WayTaskProductListSemanticMigrationResult {
            guard let sourceURL else {
                return .failed(
                    WayTaskMigrationFailure(
                        classification: classification,
                        triggeringClassification: classification,
                        precedingClassification: nil,
                        rollbackClassification: .notRequired,
                        stageIdentity: receipt.stageIdentity,
                        attemptIdentity: receipt.attemptIdentity,
                        sourceSchemaIdentity:
                            receipt.sourceSchemaIdentity,
                        sourceFingerprint: receipt.sourceFingerprint,
                        finalSourceFingerprint: nil,
                        sourceBytesVerifiedUnchanged: false,
                        candidateArtifactsRemain: true,
                        exceptionSummary: ledger.summary
                    )
                )
            }
            return .failed(
                makeFailure(
                    triggering: classification,
                    sourceStoreURL: sourceURL,
                    candidateRootURL: receipt.candidateRootURL,
                    sourceInventory: receipt.sourceInventory,
                    sourceSchema: receipt.sourceSchemaIdentity,
                    stageIdentity: receipt.stageIdentity,
                    attemptIdentity: receipt.attemptIdentity,
                    attemptDirectoryURL:
                        receipt.candidateAttemptDirectoryURL,
                    attemptCreatedByThisInvocation: false,
                    exceptionSummary: ledger.summary
                )
            )
        }

        guard receipt.status == .foundationValidated,
              receipt.completion == .candidateReadyForSemanticMigration,
              receipt.candidateSchemaIdentity == .v3,
              receipt.inactiveSemanticTargetSchemaIdentity == .v4,
              sourceURL != nil,
              (try? ownsAttemptDirectory(
                  receipt.candidateAttemptDirectoryURL,
                  candidateRootURL: receipt.candidateRootURL,
                  stageIdentity: receipt.stageIdentity,
                  attemptIdentity: receipt.attemptIdentity
              )) == true
        else {
            return fail(.candidateOwnershipConflict)
        }

        do {
            try verifySource(
                sourceURL!,
                expected: receipt.sourceFingerprint
            )
        } catch let error as ClassifiedFailure {
            return fail(error.classification)
        } catch {
            return fail(.sourceRevalidationFailed)
        }

        let physicalCandidateInventory: WayTaskMigrationStoreInventory
        do {
            physicalCandidateInventory = try dependencies.inspectStore(
                receipt.candidateStoreURL
            )
        } catch {
            return fail(.semanticCandidateReadFailed)
        }
        guard physicalCandidateInventory.fingerprint ==
            receipt.candidateFingerprint
        else {
            return fail(.candidateFingerprintMismatch)
        }

        let sourceSnapshot: WayTaskLegacyProductListSnapshot
        do {
            sourceSnapshot = try semanticDependencies
                .readPhysicalCandidate(receipt.candidateStoreURL)
        } catch {
            return fail(.semanticCandidateReadFailed)
        }

        let plan: WayTaskProductListSemanticPlan
        do {
            plan = try WayTaskProductListSemanticNormalizer.normalize(
                sourceSnapshot,
                recordingTime: semanticDependencies.recordingTime(
                    receipt.attemptIdentity
                )
            )
        } catch {
            return fail(.semanticNormalizationFailed)
        }

        for fact in plan.exceptionFacts {
            ledger.record(
                category: fact.category,
                safeEvidenceDigest: fact.safeEvidenceDigest
            )
        }
        do {
            try dependencies.writeOwnedArtifact(
                ledger.encodedData(),
                receipt.candidateAttemptDirectoryURL.appendingPathComponent(
                    Self.exceptionLedgerFilename
                )
            )
        } catch {
            return fail(.exceptionLedgerWriteFailed)
        }
        guard plan.blockingAmbiguityCount == 0 else {
            return fail(.semanticNormalizationFailed)
        }

        let targetStoreURL = receipt.candidateAttemptDirectoryURL
            .appendingPathComponent(Self.productListTargetStoreFilename)
        guard !dependencies.fileExists(targetStoreURL) else {
            return fail(.semanticTargetCreationFailed)
        }
        do {
            try semanticDependencies.createTargetStore(
                plan.target,
                targetStoreURL
            )
        } catch {
            return fail(.semanticTargetCreationFailed)
        }

        do {
            _ = try dependencies.inspectStore(targetStoreURL)
        } catch {
            return fail(.semanticTargetCreationFailed)
        }

        let reopened: WayTaskProductListSemanticSnapshot
        do {
            reopened = try semanticDependencies.reopenTargetStore(
                targetStoreURL
            )
        } catch {
            return fail(.semanticTargetReopenFailed)
        }
        let reopenedDigest: WayTaskMigrationFingerprint
        do {
            reopenedDigest = try WayTaskProductListSemanticNormalizer
                .semanticDigest(reopened)
        } catch {
            return fail(.semanticValidationFailed)
        }
        guard reopened == plan.target,
              reopenedDigest == plan.semanticDigest,
              Set(reopened.products.map(\.id)).count ==
                reopened.products.count,
              Set(reopened.lists.map(\.id)).count == reopened.lists.count,
              Set(reopened.entries.map(\.id)).count ==
                reopened.entries.count,
              Set(reopened.entries.map {
                  "\($0.shoppingListID.uuidString)|\($0.productID.uuidString)"
              }).count == reopened.entries.count,
              reopened.entries.allSatisfy({ entry in
                  reopened.products.contains { $0.id == entry.productID } &&
                      reopened.lists.contains {
                          $0.id == entry.shoppingListID
                      }
              }),
              reopened.lists.allSatisfy({
                  $0.revision ==
                      WayTaskProductListSemanticPlan.initialListRevision
              })
        else {
            return fail(.semanticValidationFailed)
        }

        let secondTargetInventory: WayTaskMigrationStoreInventory
        do {
            secondTargetInventory = try dependencies.inspectStore(
                targetStoreURL
            )
        } catch {
            return fail(.semanticTargetReopenFailed)
        }
        let stableTargetInventory: WayTaskMigrationStoreInventory
        do {
            stableTargetInventory = try dependencies.inspectStore(
                targetStoreURL
            )
        } catch {
            return fail(.semanticTargetReopenFailed)
        }
        guard secondTargetInventory.fingerprint ==
            stableTargetInventory.fingerprint
        else {
            return fail(.semanticFingerprintMismatch)
        }

        let semanticStage = WayTaskProductListSemanticStageIdentity(
            foundationStageIdentity: receipt.stageIdentity
        )
        do {
            try writeAliases(
                plan.aliases,
                at: receipt.candidateAttemptDirectoryURL
                    .appendingPathComponent(Self.productListAliasFilename)
            )
            try writeSemanticSummary(
                plan: plan,
                ledger: ledger,
                stageIdentity: semanticStage,
                attemptIdentity: receipt.attemptIdentity,
                targetFingerprint: stableTargetInventory.fingerprint,
                at: receipt.candidateAttemptDirectoryURL
                    .appendingPathComponent(Self.productListSummaryFilename)
            )
            try writeManifest(
                at: receipt.candidateAttemptDirectoryURL,
                stageIdentity: receipt.stageIdentity,
                attemptIdentity: receipt.attemptIdentity,
                sourceFingerprint: receipt.sourceFingerprint,
                candidateFingerprint: receipt.candidateFingerprint,
                status: .productListSemanticMigrationComplete,
                completion: .productListSemanticMigrationComplete,
                failure: nil,
                exceptionSummary: ledger.summary,
                semanticStageIdentity: semanticStage.rawValue,
                semanticTargetFingerprint:
                    stableTargetInventory.fingerprint.rawValue,
                semanticDigest: plan.semanticDigest.rawValue
            )
            try verifySource(
                sourceURL!,
                expected: receipt.sourceFingerprint
            )
        } catch let error as ClassifiedFailure {
            return fail(error.classification)
        } catch {
            return fail(.semanticValidationFailed)
        }

        let ownedArtifactNames: [String]
        do {
            ownedArtifactNames = try dependencies.enumerateOwnedArtifacts(
                receipt.candidateAttemptDirectoryURL
            )
        } catch {
            return fail(.semanticValidationFailed)
        }

        return .complete(
            WayTaskProductListSemanticReceipt(
                foundationReceipt: receipt,
                semanticStageIdentity: semanticStage,
                targetStoreURL: targetStoreURL,
                targetFingerprint: stableTargetInventory.fingerprint,
                semanticDigest: plan.semanticDigest,
                targetValidation: reopened,
                aliases: plan.aliases,
                exceptionSummary: ledger.summary,
                ownedArtifactNames: ownedArtifactNames,
                status: .productListSemanticMigrationComplete,
                completion: .productListSemanticMigrationComplete,
                deferredArchiveListCount: plan.deferredArchiveListCount,
                deferredArchiveEntryCount:
                    plan.deferredArchiveEntryCount,
                compatibilityEvidenceCount:
                    plan.compatibilityEvidenceCount
            )
        )
    }

    private func writeAliases(
        _ aliases: [WayTaskProductListAliasRecord],
        at url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dependencies.writeOwnedArtifact(
            encoder.encode(AliasArtifact(formatVersion: 1, aliases: aliases)),
            url
        )
    }

    private func writeSemanticSummary(
        plan: WayTaskProductListSemanticPlan,
        ledger: WayTaskMigrationExceptionLedger,
        stageIdentity: WayTaskProductListSemanticStageIdentity,
        attemptIdentity: WayTaskMigrationAttemptIdentity,
        targetFingerprint: WayTaskMigrationFingerprint,
        at url: URL
    ) throws {
        let artifact = SemanticSummaryArtifact(
            formatVersion: 1,
            semanticStageIdentity: stageIdentity.rawValue,
            attemptIdentity: attemptIdentity.rawValue,
            semanticDigest: plan.semanticDigest.rawValue,
            targetFingerprint: targetFingerprint.rawValue,
            productCount: plan.target.products.count,
            listCount: plan.target.lists.count,
            entryCount: plan.target.entries.count,
            aliasCount: plan.aliases.count,
            exceptionCount: ledger.summary.totalOccurrenceCount,
            exceptionOverflowCount: ledger.summary.overflowOccurrenceCount,
            deferredArchiveListCount: plan.deferredArchiveListCount,
            deferredArchiveEntryCount: plan.deferredArchiveEntryCount,
            compatibilityEvidenceCount: plan.compatibilityEvidenceCount,
            productListSemanticMigrationComplete: true,
            sessionHistoryLocationSemanticMigrationComplete: false,
            promotionAuthorized: false,
            startupActivationAuthorized: false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dependencies.writeOwnedArtifact(try encoder.encode(artifact), url)
    }

    private struct AliasArtifact: Codable {
        let formatVersion: Int
        let aliases: [WayTaskProductListAliasRecord]
    }

    private struct SemanticSummaryArtifact: Codable {
        let formatVersion: Int
        let semanticStageIdentity: String
        let attemptIdentity: String
        let semanticDigest: String
        let targetFingerprint: String
        let productCount: Int
        let listCount: Int
        let entryCount: Int
        let aliasCount: Int
        let exceptionCount: Int
        let exceptionOverflowCount: Int
        let deferredArchiveListCount: Int
        let deferredArchiveEntryCount: Int
        let compatibilityEvidenceCount: Int
        let productListSemanticMigrationComplete: Bool
        let sessionHistoryLocationSemanticMigrationComplete: Bool
        let promotionAuthorized: Bool
        let startupActivationAuthorized: Bool
    }
}

// MARK: - Read-only source inspection

enum WayTaskProtectedStoreInspectionError: Error {
    case missingDatabase
    case unreadableComponent
    case invalidComponent
    case unknownSidecar
    case inconsistentSidecars
    case componentChangedDuringRead
}

private enum WayTaskProtectedStoreInspector {
    static func inspect(
        storeURL: URL
    ) throws -> WayTaskMigrationStoreInventory {
        let fileManager = FileManager.default
        let standardizedStoreURL = storeURL.standardizedFileURL
        guard standardizedStoreURL.isFileURL else {
            throw WayTaskProtectedStoreInspectionError.invalidComponent
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: standardizedStoreURL.path,
            isDirectory: &isDirectory
        ) else {
            throw WayTaskProtectedStoreInspectionError.missingDatabase
        }
        guard !isDirectory.boolValue else {
            throw WayTaskProtectedStoreInspectionError.invalidComponent
        }

        let parentURL = standardizedStoreURL.deletingLastPathComponent()
        let storeName = standardizedStoreURL.lastPathComponent
        let knownNames = Set(
            WayTaskMigrationStoreComponentRole.allCases.map {
                storeName + $0.suffix
            }
        )
        let siblingNames: [String]
        do {
            siblingNames = try fileManager.contentsOfDirectory(
                atPath: parentURL.path
            )
        } catch {
            throw WayTaskProtectedStoreInspectionError.unreadableComponent
        }
        if siblingNames.contains(where: {
            $0.hasPrefix(storeName + "-") && !knownNames.contains($0)
        }) {
            throw WayTaskProtectedStoreInspectionError.unknownSidecar
        }

        let existingRoles = WayTaskMigrationStoreComponentRole.allCases
            .filter { role in
                let url = componentURL(for: role, storeURL: standardizedStoreURL)
                return fileManager.fileExists(atPath: url.path)
            }
        let roleSet = Set(existingRoles)
        let hasWAL = roleSet.contains(.writeAheadLog)
        let hasSHM = roleSet.contains(.sharedMemory)
        let hasJournal = roleSet.contains(.rollbackJournal)
        guard hasWAL == hasSHM,
              !(hasJournal && (hasWAL || hasSHM))
        else {
            throw WayTaskProtectedStoreInspectionError.inconsistentSidecars
        }

        var components: [WayTaskMigrationStoreComponent] = []
        var totalByteCount: UInt64 = 0
        for role in existingRoles {
            let url = componentURL(for: role, storeURL: standardizedStoreURL)
            let component = try inspectComponent(role: role, url: url)
            if UInt64.max - totalByteCount < component.byteCount {
                throw WayTaskProtectedStoreInspectionError.invalidComponent
            }
            totalByteCount += component.byteCount
            components.append(component)
        }

        let aggregate = aggregateFingerprint(components)
        return WayTaskMigrationStoreInventory(
            components: components,
            totalByteCount: totalByteCount,
            fingerprint: aggregate
        )
    }

    private static func inspectComponent(
        role: WayTaskMigrationStoreComponentRole,
        url: URL
    ) throws -> WayTaskMigrationStoreComponent {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw WayTaskProtectedStoreInspectionError.unreadableComponent
        }

        let before: [FileAttributeKey: Any]
        do {
            before = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw WayTaskProtectedStoreInspectionError.unreadableComponent
        }
        guard before[.type] as? FileAttributeType == .typeRegular,
              let sizeNumber = before[.size] as? NSNumber
        else {
            throw WayTaskProtectedStoreInspectionError.invalidComponent
        }
        let byteCount = sizeNumber.uint64Value
        if role == .database && byteCount == 0 {
            throw WayTaskProtectedStoreInspectionError.invalidComponent
        }

        let fingerprint: WayTaskMigrationFingerprint
        do {
            fingerprint = try fingerprintFile(url)
        } catch {
            throw WayTaskProtectedStoreInspectionError.unreadableComponent
        }

        let after: [FileAttributeKey: Any]
        do {
            after = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw WayTaskProtectedStoreInspectionError.unreadableComponent
        }
        guard (after[.size] as? NSNumber)?.uint64Value == byteCount,
              (before[.modificationDate] as? Date) ==
                (after[.modificationDate] as? Date)
        else {
            throw WayTaskProtectedStoreInspectionError
                .componentChangedDuringRead
        }

        return WayTaskMigrationStoreComponent(
            role: role,
            url: url,
            byteCount: byteCount,
            fingerprint: fingerprint
        )
    }

    private static func fingerprintFile(
        _ url: URL
    ) throws -> WayTaskMigrationFingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return WayTaskMigrationFingerprint(
            rawValue: WayTaskMigrationDigest.hex(hasher.finalize())
        )
    }

    private static func aggregateFingerprint(
        _ components: [WayTaskMigrationStoreComponent]
    ) -> WayTaskMigrationFingerprint {
        let canonical = components.map {
            [
                $0.role.rawValue,
                String($0.byteCount),
                $0.fingerprint.rawValue
            ].joined(separator: ":")
        }.joined(separator: "|")
        return WayTaskMigrationFingerprint(
            rawValue: WayTaskMigrationDigest.hex(
                hashing: Data(canonical.utf8)
            )
        )
    }

    private static func componentURL(
        for role: WayTaskMigrationStoreComponentRole,
        storeURL: URL
    ) -> URL {
        guard role != .database else { return storeURL }
        return URL(fileURLWithPath: storeURL.path + role.suffix)
    }
}

enum WayTaskProtectedStoreSchemaError: Error {
    case unknownIdentity
    case unsupportedIdentity
    case unreadable
}

private enum WayTaskProtectedStoreSchemaReader {
    private static let versionIdentifiersKey =
        "NSStoreModelVersionIdentifiers"

    static func resolve(
        storeURL: URL
    ) throws -> WayTaskMigrationSchemaIdentity {
        var components = URLComponents(
            url: storeURL.standardizedFileURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "mode", value: "ro"),
            URLQueryItem(name: "immutable", value: "1")
        ]
        guard let uri = components?.string else {
            throw WayTaskProtectedStoreSchemaError.unreadable
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            uri,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw WayTaskProtectedStoreSchemaError.unreadable
        }
        defer { sqlite3_close(database) }
        guard sqlite3_db_readonly(database, "main") == 1 else {
            throw WayTaskProtectedStoreSchemaError.unreadable
        }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            database,
            "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
            -1,
            &statement,
            nil
        )
        guard prepareResult == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, 0)
        else {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }

        let byteCount = Int(sqlite3_column_bytes(statement, 0))
        guard byteCount > 0 else {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        let data = Data(bytes: bytes, count: byteCount)
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        guard let metadata = propertyList as? [String: Any],
              let rawIdentifiers = metadata[versionIdentifiersKey]
        else {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }

        let identifiers: [String]
        if let values = rawIdentifiers as? [String] {
            identifiers = values
        } else if let values = rawIdentifiers as? Set<String> {
            identifiers = values.sorted()
        } else if let value = rawIdentifiers as? String {
            identifiers = [value]
        } else {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        let normalized = Array(Set(identifiers)).sorted()
        guard normalized.count == 1,
              let identifier = normalized.first
        else {
            throw WayTaskProtectedStoreSchemaError.unknownIdentity
        }
        guard let identity = WayTaskMigrationSchemaIdentity.resolve(
            persistentVersionIdentifier: identifier
        ) else {
            throw WayTaskProtectedStoreSchemaError.unsupportedIdentity
        }
        return identity
    }
}

// MARK: - Candidate-only physical boundary

@MainActor
private enum WayTaskProductListSemanticStoreBoundary {
    static func readPhysicalCandidate(
        storeURL: URL
    ) throws -> WayTaskLegacyProductListSnapshot {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-T07-Physical-Candidate-Read",
                schema: schema,
                url: storeURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan:
                    WayTaskProtectedCandidatePhysicalMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let products = try context.fetch(FetchDescriptor<Product>()).map {
                product in
                WayTaskLegacyProductRecord(
                    sourceRecordID: product.id,
                    productID: product.id,
                    legacyShoppingItemID: product.legacyShoppingItemID,
                    name: product.name,
                    imageData: product.imageData,
                    brand: product.brand,
                    category: product.category,
                    barcode: product.barcode,
                    imageURLString: product.imageURLString,
                    sourceRawValue: product.sourceRawValue,
                    productType: product.productType,
                    flavor: product.flavor,
                    packageSize: product.packageSize,
                    packageType: product.packageType,
                    visibleText: product.visibleText,
                    searchKeywordsRawValue: product.searchKeywordsRawValue,
                    catalogProductIDRawValue:
                        product.catalogProductIDRawValue,
                    catalogDisplayNameSnapshot:
                        product.catalogDisplayNameSnapshot,
                    catalogDisplayLocaleSnapshot:
                        product.catalogDisplayLocaleSnapshot,
                    catalogCategoryIDSnapshotRawValue:
                        product.catalogCategoryIDSnapshotRawValue,
                    catalogCategoryDisplayNameSnapshot:
                        product.catalogCategoryDisplayNameSnapshot,
                    catalogIconKeySnapshot:
                        product.catalogIconKeySnapshot,
                    catalogSnapshotUpdatedAt:
                        product.catalogSnapshotUpdatedAt,
                    createdAt: product.dateAdded,
                    updatedAt: product.updatedAt,
                    removedAt: product.deletedAt
                )
            }
            let lists = try context.fetch(
                FetchDescriptor<ShoppingList>()
            ).map { list in
                WayTaskLegacyShoppingListRecord(
                    sourceRecordID: list.id,
                    listID: list.id,
                    title: list.title,
                    kindRawValue: list.kindRawValue,
                    createdAt: list.createdAt,
                    updatedAt: list.updatedAt,
                    isDefault: list.isDefault
                )
            }
            let entries = try context.fetch(
                FetchDescriptor<ShoppingListEntry>()
            ).map { entry in
                WayTaskLegacyShoppingEntryRecord(
                    sourceRecordID: entry.id,
                    entryID: entry.id,
                    listID: entry.shoppingListID,
                    productID: entry.productID,
                    relationshipProductID: entry.product?.id,
                    legacyShoppingItemID: entry.legacyShoppingItemID,
                    quantity: entry.quantity,
                    isChecked: entry.isChecked,
                    createdAt: entry.createdAt,
                    sortOrder: entry.sortOrder
                )
            }
            let compatibilityRecords = try context.fetch(
                FetchDescriptor<ShoppingItem>()
            ).map { item in
                WayTaskLegacyCompatibilityRecord(
                    sourceRecordID: item.id,
                    compatibilityID: item.id,
                    isCompleted: item.isCompleted
                )
            }
            return WayTaskLegacyProductListSnapshot(
                products: products,
                lists: lists,
                entries: entries,
                compatibilityRecords: compatibilityRecords
            )
        }
    }

    static func createTargetStore(
        snapshot: WayTaskProductListSemanticSnapshot,
        storeURL: URL
    ) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
            let configuration = ModelConfiguration(
                "WT033A-T07-Inactive-V4-Target",
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
            context.autosaveEnabled = false
            var productsByID: [UUID: WayTaskSchemaV4.Product] = [:]
            for record in snapshot.products {
                let product = WayTaskSchemaV4.Product(
                    id: record.id,
                    revision: record.revision,
                    libraryLifecycleRawValue:
                        record.libraryLifecycleRawValue,
                    libraryRemovedAt: record.libraryRemovedAt,
                    name: record.name,
                    imageData: record.imageData,
                    brand: record.brand,
                    category: record.category,
                    barcode: record.barcode,
                    imageURLString: record.imageURLString,
                    sourceRawValue: record.sourceRawValue,
                    catalogProductIDRawValue:
                        record.catalogProductIDRawValue,
                    catalogDisplayNameSnapshot:
                        record.catalogDisplayNameSnapshot,
                    catalogDisplayLocaleSnapshot:
                        record.catalogDisplayLocaleSnapshot,
                    catalogCategoryIDSnapshotRawValue:
                        record.catalogCategoryIDSnapshotRawValue,
                    catalogCategoryDisplayNameSnapshot:
                        record.catalogCategoryDisplayNameSnapshot,
                    catalogIconKeySnapshot:
                        record.catalogIconKeySnapshot,
                    catalogSnapshotUpdatedAt:
                        record.catalogSnapshotUpdatedAt,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                context.insert(product)
                productsByID[record.id] = product
            }

            let entriesByList = Dictionary(
                grouping: snapshot.entries,
                by: \.shoppingListID
            )
            for record in snapshot.lists {
                let entries = try (entriesByList[record.id] ?? []).map {
                    entry -> WayTaskSchemaV4.ShoppingListEntry in
                    guard let product = productsByID[entry.productID] else {
                        throw StoreError.invalidRelationship
                    }
                    return WayTaskSchemaV4.ShoppingListEntry(
                        id: entry.id,
                        shoppingListID: entry.shoppingListID,
                        productID: entry.productID,
                        lifecycleRawValue: entry.lifecycleRawValue,
                        resolutionReasonRawValue:
                            entry.resolutionReasonRawValue,
                        resolutionEffectiveAt:
                            entry.resolutionEffectiveAt,
                        resolutionProvenanceRawValue:
                            entry.resolutionProvenanceRawValue,
                        quantity: entry.quantity,
                        sortOrder: entry.sortOrder,
                        createdAt: entry.createdAt,
                        updatedAt: entry.updatedAt,
                        product: product
                    )
                }
                let list = WayTaskSchemaV4.ShoppingList(
                    id: record.id,
                    revision: record.revision,
                    title: record.title,
                    purposeRawValue: record.purposeRawValue,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    entries: entries
                )
                context.insert(list)
            }
            try context.save()
        }
    }

    static func reopenTargetStore(
        storeURL: URL
    ) throws -> WayTaskProductListSemanticSnapshot {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
            let configuration = ModelConfiguration(
                "WT033A-T07-Inactive-V4-Reopen",
                schema: schema,
                url: storeURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var products = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.Product>()
            ).map { product in
                WayTaskMigratedProductRecord(
                    id: product.id,
                    revision: product.revision,
                    libraryLifecycleRawValue:
                        product.libraryLifecycleRawValue,
                    libraryRemovedAt: product.libraryRemovedAt,
                    name: product.name,
                    imageData: product.imageData,
                    brand: product.brand,
                    category: product.category,
                    barcode: product.barcode,
                    imageURLString: product.imageURLString,
                    sourceRawValue: product.sourceRawValue,
                    catalogProductIDRawValue:
                        product.catalogProductIDRawValue,
                    catalogDisplayNameSnapshot:
                        product.catalogDisplayNameSnapshot,
                    catalogDisplayLocaleSnapshot:
                        product.catalogDisplayLocaleSnapshot,
                    catalogCategoryIDSnapshotRawValue:
                        product.catalogCategoryIDSnapshotRawValue,
                    catalogCategoryDisplayNameSnapshot:
                        product.catalogCategoryDisplayNameSnapshot,
                    catalogIconKeySnapshot:
                        product.catalogIconKeySnapshot,
                    catalogSnapshotUpdatedAt:
                        product.catalogSnapshotUpdatedAt,
                    createdAt: product.createdAt,
                    updatedAt: product.updatedAt
                )
            }
            var lists = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
            ).map { list in
                WayTaskMigratedShoppingListRecord(
                    id: list.id,
                    revision: list.revision,
                    title: list.title,
                    purposeRawValue: list.purposeRawValue,
                    createdAt: list.createdAt,
                    updatedAt: list.updatedAt
                )
            }
            var entries = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            ).map { entry in
                guard entry.product?.id == entry.productID else {
                    throw StoreError.invalidRelationship
                }
                return WayTaskMigratedShoppingEntryRecord(
                    id: entry.id,
                    shoppingListID: entry.shoppingListID,
                    productID: entry.productID,
                    lifecycleRawValue: entry.lifecycleRawValue,
                    resolutionReasonRawValue:
                        entry.resolutionReasonRawValue,
                    resolutionEffectiveAt: entry.resolutionEffectiveAt,
                    resolutionProvenanceRawValue:
                        entry.resolutionProvenanceRawValue,
                    quantity: entry.quantity,
                    sortOrder: entry.sortOrder,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            }
            products.sort { uuidLess($0.id, $1.id) }
            lists.sort { uuidLess($0.id, $1.id) }
            entries.sort {
                if $0.shoppingListID != $1.shoppingListID {
                    return uuidLess($0.shoppingListID, $1.shoppingListID)
                }
                if $0.productID != $1.productID {
                    return uuidLess($0.productID, $1.productID)
                }
                return uuidLess($0.id, $1.id)
            }
            return WayTaskProductListSemanticSnapshot(
                products: products,
                lists: lists,
                entries: entries
            )
        }
    }

    private static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    private enum StoreError: Error {
        case invalidRelationship
    }
}

private enum WayTaskCandidatePhysicalStoreBoundary {
    private static let expectedCountKeys: Set<String> = [
        "GeoLocation",
        "ShoppingItem",
        "Product",
        "ShoppingList",
        "ShoppingListEntry",
        "ProductHistory",
        "ProductKnowledge",
        "ShoppingSession"
    ]

    static func migrate(storeURL: URL) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-TC13-PhysicalCandidate",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan:
                    WayTaskProtectedCandidatePhysicalMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            _ = try context.fetchCount(FetchDescriptor<Product>())
        }
    }

    static func reopen(
        storeURL: URL
    ) throws -> WayTaskMigrationCandidateValidation {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-TC13-ReopenCandidate",
                schema: schema,
                url: storeURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan:
                    WayTaskProtectedCandidatePhysicalMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let counts: [String: Int] = [
                "GeoLocation": try context.fetchCount(
                    FetchDescriptor<GeoLocation>()
                ),
                "ShoppingItem": try context.fetchCount(
                    FetchDescriptor<ShoppingItem>()
                ),
                "Product": try context.fetchCount(
                    FetchDescriptor<Product>()
                ),
                "ShoppingList": try context.fetchCount(
                    FetchDescriptor<ShoppingList>()
                ),
                "ShoppingListEntry": try context.fetchCount(
                    FetchDescriptor<ShoppingListEntry>()
                ),
                "ProductHistory": try context.fetchCount(
                    FetchDescriptor<ProductHistory>()
                ),
                "ProductKnowledge": try context.fetchCount(
                    FetchDescriptor<ProductKnowledge>()
                ),
                "ShoppingSession": try context.fetchCount(
                    FetchDescriptor<ShoppingSession>()
                )
            ]
            return WayTaskMigrationCandidateValidation(
                schemaIdentity: .v3,
                recordCounts: counts
            )
        }
    }

    static func validate(
        _ validation: WayTaskMigrationCandidateValidation
    ) throws {
        guard validation.schemaIdentity == .v3,
              Set(validation.recordCounts.keys) == expectedCountKeys,
              validation.recordCounts.values.allSatisfy({ $0 >= 0 })
        else {
            throw CandidateValidationError.invalidPhysicalBoundary
        }
    }

    private enum CandidateValidationError: Error {
        case invalidPhysicalBoundary
    }
}

private enum WayTaskCandidateArtifactInventory {
    static func enumerate(rootURL: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }
        var names: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey
            ])
            guard values.isRegularFile == true else { continue }
            let rootPath = rootURL.standardizedFileURL.path + "/"
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            names.append(String(path.dropFirst(rootPath.count)))
        }
        return Array(Set(names)).sorted()
    }
}

private enum WayTaskMigrationDigest {
    static func hex(hashing data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func hex<D: Sequence>(_ digest: D) -> String
    where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func stableUUID(
        category: WayTaskMigrationExceptionCategory,
        digest: WayTaskMigrationSafeDigest,
        ordinal: Int
    ) -> UUID {
        var bytes = Array(
            SHA256.hash(
                data: Data(
                    "\(category.rawValue)|\(digest.rawValue)|\(ordinal)".utf8
                )
            ).prefix(16)
        )
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
