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
    case invalidSessionToken = "invalid_session_token"
    case duplicateSessionToken = "duplicate_session_token"
    case foreignCollectedToken = "foreign_collected_token"
    case missingSessionSourceList = "missing_session_source_list"
    case ambiguousSessionItem = "ambiguous_session_item"
    case sessionLifecycleContradiction =
        "session_lifecycle_contradiction"
    case invalidSessionStore = "invalid_session_store"
    case sessionExceptionOverflow = "session_exception_overflow"
}

struct WayTaskMigrationSafeDigest: Hashable, Codable, Sendable {
    let rawValue: String

    init(hashing evidenceBytes: Data) {
        rawValue = WayTaskMigrationDigest.hex(hashing: evidenceBytes)
    }

    init(keyed evidenceBytes: Data, keyBytes: Data) {
        let authentication = HMAC<SHA256>.authenticationCode(
            for: evidenceBytes,
            using: SymmetricKey(data: keyBytes)
        )
        rawValue = WayTaskMigrationDigest.hex(authentication)
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

    init(encodedData: Data) throws {
        let payload = try JSONDecoder().decode(
            PersistedLedger.self,
            from: encodedData
        )
        guard payload.formatVersion == Self.formatVersion,
              payload.capacity >= 0,
              payload.totalOccurrenceCount >= 0,
              payload.overflowOccurrenceCount >= 0,
              payload.entries.count <= payload.capacity,
              payload.entries.allSatisfy({ entry in
                  entry.ordinal > 0 && entry.occurrenceCount > 0 &&
                      entry.id == WayTaskMigrationDigest.stableUUID(
                          category: entry.category,
                          digest: entry.safeEvidenceDigest,
                          ordinal: entry.ordinal
                      )
              }),
              Set(payload.entries.map {
                  "\($0.category.rawValue)|\($0.safeEvidenceDigest.rawValue)"
              }).count == payload.entries.count
        else {
            throw LedgerDecodingError.invalidPayload
        }
        let categoryCounts = try Self.decodedCounts(payload.categoryCounts)
        let overflowCounts = try Self.decodedCounts(
            payload.overflowCategoryCounts
        )
        guard categoryCounts.values.reduce(0, +) ==
                payload.totalOccurrenceCount,
              overflowCounts.values.reduce(0, +) ==
                payload.overflowOccurrenceCount
        else {
            throw LedgerDecodingError.invalidPayload
        }
        capacity = payload.capacity
        entries = payload.entries
        self.categoryCounts = categoryCounts
        overflowCategoryCounts = overflowCounts
        totalOccurrenceCount = payload.totalOccurrenceCount
        overflowOccurrenceCount = payload.overflowOccurrenceCount
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

    var persistedEntries: [WayTaskMigrationExceptionEntry] { entries }

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

    private static func decodedCounts(
        _ values: [WayTaskMigrationExceptionCategoryCount]
    ) throws -> [WayTaskMigrationExceptionCategory: Int] {
        var result: [WayTaskMigrationExceptionCategory: Int] = [:]
        for value in values {
            guard value.count > 0, result[value.category] == nil else {
                throw LedgerDecodingError.invalidPayload
            }
            result[value.category] = value.count
        }
        return result
    }

    private enum LedgerDecodingError: Error {
        case invalidPayload
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
    case sessionHistoryArchiveLocationSemanticMigrationComplete =
        "session_history_archive_location_semantic_migration_complete"
    case failedBeforePromotion = "failed_before_promotion"
}

enum WayTaskMigrationCompletionClassification: String, Codable, Sendable {
    case candidateReadyForSemanticMigration =
        "candidate_ready_for_semantic_migration"
    case productListSemanticMigrationComplete =
        "product_list_semantic_migration_complete"
    case sessionHistoryArchiveLocationSemanticMigrationComplete =
        "session_history_archive_location_semantic_migration_complete"
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
    case sessionHistoryCandidateReadFailed =
        "session_history_candidate_read_failed"
    case sessionHistoryNormalizationFailed =
        "session_history_normalization_failed"
    case sessionHistoryTargetWriteFailed =
        "session_history_target_write_failed"
    case sessionHistoryTargetReopenFailed =
        "session_history_target_reopen_failed"
    case sessionHistoryValidationFailed =
        "session_history_validation_failed"
    case sessionHistoryFingerprintMismatch =
        "session_history_fingerprint_mismatch"
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

// MARK: - T-08 Session/history/archive/location semantic records

struct WayTaskLegacySessionRecord: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date?
    let isActive: Bool
    let itemIDListRawValue: String
    let collectedItemIDListRawValue: String
    let shoppingListID: UUID?
    let selectedStoreID: UUID?
    let selectedStoreName: String?
    let selectedStoreLatitude: Double?
    let selectedStoreLongitude: Double?
}

struct WayTaskLegacyHistoryAggregateRecord: Equatable, Codable, Sendable {
    let id: UUID
    let productKey: String
    let productName: String
    let barcode: String?
    let firstAddedDate: Date
    let lastAddedDate: Date
    let addCount: Int
    let lastSourceRawValue: String
    let averageInterval: TimeInterval?
    let lastCompletedDate: Date?
}

struct WayTaskLegacyCompatibilityEvidenceRecord: Equatable, Codable, Sendable {
    let id: UUID
    let name: String
    let isCompleted: Bool
    let imageData: Data?
    let brand: String?
    let category: String?
    let barcode: String?
    let imageURLString: String?
    let dateAdded: Date
    let sourceRawValue: String
    let productType: String?
    let flavor: String?
    let packageSize: String?
    let packageType: String?
    let visibleText: String?
    let searchKeywordsRawValue: String?
}

struct WayTaskLegacySavedLocationRecord: Equatable, Codable, Sendable {
    let id: UUID
    let title: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let storeCategoryRawValue: String?
    let addressText: String?
    let notes: String?
    let sourceTypeRawValue: String?
    let shoppingItemIDs: [UUID]
}

struct WayTaskSessionHistoryArchiveSourceSnapshot: Equatable, Sendable {
    let productList: WayTaskLegacyProductListSnapshot
    let sessions: [WayTaskLegacySessionRecord]
    let historyAggregates: [WayTaskLegacyHistoryAggregateRecord]
    let compatibilityItems: [WayTaskLegacyCompatibilityEvidenceRecord]
    let savedLocations: [WayTaskLegacySavedLocationRecord]
}

struct WayTaskMigratedSessionExceptionRecord: Equatable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID?
    let sessionLineID: UUID?
    let categoryRawValue: String
    let safeEvidenceDigest: String
    let ordinal: Int
    let occurrenceCount: Int
    let recordedAt: Date
    let sourceCollectionRawValue: String?
    let sourceOrdinals: [Int]
    let sourceByteLength: Int?
    let normalizedTokenID: UUID?
}

struct WayTaskSessionExceptionEvidenceArtifact: Equatable, Codable, Sendable {
    let formatVersion: Int
    let records: [WayTaskMigratedSessionExceptionRecord]
}

struct WayTaskMigratedSessionStopRecord: Equatable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let snapshotID: UUID
    let sortOrder: Int
    let storeReferenceIDRawValue: String?
    let storeReferenceProvenanceRawValue: String
    let displayNameSnapshot: String
    let latitudeSnapshot: Double?
    let longitudeSnapshot: Double?
    let evidenceAt: Date?
    let isSessionScopedTransient: Bool
}

struct WayTaskMigratedSessionLineRecord: Equatable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let snapshotID: UUID
    let snapshotVersion: Int
    let snapshotProvenanceRawValue: String
    let sourceListID: UUID?
    let sourceEntryID: UUID?
    let productID: UUID?
    let globalProductConceptIDRawValue: String?
    let stopID: UUID?
    let sortOrder: Int
    let productNameSnapshot: String
    let productBrandSnapshot: String?
    let productCategorySnapshot: String?
    let quantitySnapshot: Double
    let unitSnapshotRawValue: String?
    let noteSnapshot: String?
    let executionStateRawValue: String
    let executionChangedAt: Date?
    let finalOutcomeRawValue: String?
    let finalOutcomeAt: Date?
    let finalOutcomeCommandID: UUID?
    let legacyDispositionRawValue: String?
}

struct WayTaskMigratedSessionRecord: Equatable, Codable, Sendable {
    let id: UUID
    let sourceListID: UUID?
    let sourceRevision: UInt64?
    let sourceRevisionProvenanceRawValue: String
    let revision: UInt64
    let lifecycleRawValue: String
    let migrationConditionRawValue: String
    let snapshotID: UUID
    let snapshotVersion: Int
    let snapshotGeneration: Int
    let snapshotContentSignature: String
    let sourcePlanID: UUID?
    let sourcePlanSignature: String?
    let sourcePlanEvidenceAt: Date?
    let startedAt: Date
    let activationStartedAt: Date
    let lastActivityAt: Date
    let expiredAt: Date?
    let endedAt: Date?
    let expirationReasonRawValue: String?
    let expirationPolicyVersion: Int
    let lines: [WayTaskMigratedSessionLineRecord]
    let stops: [WayTaskMigratedSessionStopRecord]
    let exceptions: [WayTaskMigratedSessionExceptionRecord]
}

struct WayTaskSessionHistoryArchiveSemanticSnapshot: Equatable, Codable,
    Sendable
{
    let productListBase: WayTaskProductListSemanticSnapshot
    let sessions: [WayTaskMigratedSessionRecord]
    let historyAggregates: [WayTaskLegacyHistoryAggregateRecord]
    let historyEvents: [UUID]
    let archiveLists: [WayTaskMigratedShoppingListRecord]
    let archiveEntries: [WayTaskMigratedShoppingEntryRecord]
    let compatibilityItems: [WayTaskLegacyCompatibilityEvidenceRecord]
    let savedLocations: [WayTaskLegacySavedLocationRecord]
    let globalExceptions: [WayTaskMigratedSessionExceptionRecord]
}

struct WayTaskSessionHistoryArchiveExceptionFact: Equatable, Sendable {
    let sessionID: UUID?
    let sessionLineID: UUID?
    let category: WayTaskMigrationExceptionCategory
    let safeEvidenceDigest: WayTaskMigrationSafeDigest
    let sourceCollectionRawValue: String?
    let sourceOrdinal: Int?
    let sourceByteLength: Int?
    let normalizedTokenID: UUID?
}

struct WayTaskSessionHistoryArchiveSemanticPlan: Equatable, Sendable {
    static let initialSessionRevision: UInt64 = 1
    static let snapshotVersion = 1
    static let snapshotGeneration = 1
    static let expirationPolicyVersion = 1
    static let perSessionExceptionCapacity = 100

    let target: WayTaskSessionHistoryArchiveSemanticSnapshot
    let exceptionFacts: [WayTaskSessionHistoryArchiveExceptionFact]
    let blockingAmbiguityCount: Int
    let semanticDigest: WayTaskMigrationFingerprint
}

struct WayTaskSessionHistoryArchiveStageIdentity: Hashable, Codable, Sendable {
    static let version =
        "wt033a.tc13.t08.session-history-archive-location.v1"

    let productListStageIdentity: WayTaskProductListSemanticStageIdentity
    let sourceSchemaIdentity: WayTaskMigrationSchemaIdentity
    let candidateSchemaIdentity: WayTaskMigrationSchemaIdentity
    let rawValue: String

    init(productListReceipt: WayTaskProductListSemanticReceipt) {
        productListStageIdentity = productListReceipt.semanticStageIdentity
        sourceSchemaIdentity = .v3
        candidateSchemaIdentity = .v4
        rawValue = WayTaskMigrationDigest.hex(
            hashing: Data(
                [
                    Self.version,
                    productListReceipt.semanticStageIdentity.rawValue,
                    productListReceipt.semanticDigest.rawValue,
                    sourceSchemaIdentity.rawValue,
                    candidateSchemaIdentity.rawValue
                ].joined(separator: "|").utf8
            )
        )
    }
}

struct WayTaskSessionHistoryArchiveMigrationReceipt: Sendable {
    let productListReceipt: WayTaskProductListSemanticReceipt
    let semanticStageIdentity: WayTaskSessionHistoryArchiveStageIdentity
    let targetStoreURL: URL
    let targetFingerprint: WayTaskMigrationFingerprint
    let semanticDigest: WayTaskMigrationFingerprint
    let targetValidation: WayTaskSessionHistoryArchiveSemanticSnapshot
    let exceptionSummary: WayTaskMigrationExceptionSummary
    let ownedArtifactNames: [String]
    let status: WayTaskMigrationStageStatus
    let completion: WayTaskMigrationCompletionClassification

    var semanticConversionCompleted: Bool { true }
    var productListSemanticConversionCompleted: Bool { true }
    var sessionHistoryLocationSemanticConversionCompleted: Bool { true }
    var promotionAuthorized: Bool { false }
    var startupActivationAuthorized: Bool { false }
}

enum WayTaskSessionHistoryArchiveMigrationResult: Sendable {
    case complete(WayTaskSessionHistoryArchiveMigrationReceipt)
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

enum WayTaskSessionHistoryArchiveSemanticNormalizer {
    static func normalize(
        _ source: WayTaskSessionHistoryArchiveSourceSnapshot,
        productListTarget: WayTaskProductListSemanticSnapshot,
        aliases: [WayTaskProductListAliasRecord],
        recordingTime: Date,
        digestKey: Data
    ) throws -> WayTaskSessionHistoryArchiveSemanticPlan {
        var facts: [WayTaskSessionHistoryArchiveExceptionFact] = []
        var blockingAmbiguityCount = 0

        let productByID = Dictionary(
            uniqueKeysWithValues: productListTarget.products.map { ($0.id, $0) }
        )
        let currentListIDs = Set(productListTarget.lists.map(\.id))
        let targetEntryByID = Dictionary(
            uniqueKeysWithValues: productListTarget.entries.map { ($0.id, $0) }
        )
        var entryAliases: [UUID: UUID] = [:]
        for alias in aliases where alias.kind == .shoppingEntry {
            if let existing = entryAliases[alias.sourceIdentity],
               existing != alias.canonicalIdentity
            {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .ambiguousSessionItem,
                        components: [
                            "entry-alias", alias.sourceIdentity.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
            } else {
                entryAliases[alias.sourceIdentity] = alias.canonicalIdentity
            }
        }

        let archiveKinds = Set([
            ShoppingListKind.completed.rawValue,
            ShoppingListKind.recent.rawValue
        ])
        var archiveLists: [WayTaskMigratedShoppingListRecord] = []
        var archiveListIDs = Set<UUID>()
        let archiveSourceLists = source.productList.lists.filter {
            archiveKinds.contains($0.kindRawValue)
        }
        let archiveGroups = Dictionary(
            grouping: archiveSourceLists.compactMap { row in
                row.listID.map { ($0, row) }
            },
            by: { $0.0 }
        )
        for row in archiveSourceLists where row.listID == nil {
            blockingAmbiguityCount += 1
            facts.append(
                fact(
                    .legacyArchiveUnresolved,
                    components: ["archive-list", row.sourceRecordID.uuidString],
                    digestKey: digestKey
                )
            )
        }
        for listID in archiveGroups.keys.sorted(by: uuidLess) {
            let rows = archiveGroups[listID]!.map(\.1).sorted(by: listLess)
            let canonical = rows[0]
            guard rows.allSatisfy({
                $0.title == canonical.title &&
                    $0.kindRawValue == canonical.kindRawValue
            }), !currentListIDs.contains(listID) else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .legacyArchiveUnresolved,
                        components: ["archive-list-collision", listID.uuidString],
                        digestKey: digestKey
                    )
                )
                continue
            }
            archiveListIDs.insert(listID)
            archiveLists.append(
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

        var archiveEntries: [WayTaskMigratedShoppingEntryRecord] = []
        var archiveEntryIDs = Set<UUID>()
        for row in source.productList.entries.sorted(by: entryLess) {
            guard let listID = row.listID,
                  archiveListIDs.contains(listID)
            else { continue }
            guard let entryID = row.entryID, let productID = row.productID else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .legacyArchiveUnresolved,
                        components: [
                            "archive-entry", row.sourceRecordID.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
                continue
            }
            guard archiveEntryIDs.insert(entryID).inserted,
                  targetEntryByID[entryID] == nil
            else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .legacyArchiveUnresolved,
                        components: [
                            "archive-entry-collision", entryID.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
                continue
            }
            if productByID[productID] == nil {
                facts.append(
                    fact(
                        .legacyArchiveUnresolved,
                        components: [
                            "archive-product", entryID.uuidString,
                            productID.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
            }
            let isNeeded = !row.isChecked
            archiveEntries.append(
                WayTaskMigratedShoppingEntryRecord(
                    id: entryID,
                    shoppingListID: listID,
                    productID: productID,
                    lifecycleRawValue: isNeeded ? "needed" : "resolved",
                    resolutionReasonRawValue: isNeeded
                        ? nil : ShoppingListResolutionReason
                            .legacyUnknown.rawValue,
                    resolutionEffectiveAt: isNeeded ? nil : recordingTime,
                    resolutionProvenanceRawValue: isNeeded
                        ? nil : "legacyMigration",
                    quantity: validQuantity(row.quantity),
                    sortOrder: row.sortOrder.isFinite ? row.sortOrder : 0,
                    createdAt: row.createdAt,
                    updatedAt: row.createdAt
                )
            )
        }

        var historyIDs = Set<UUID>()
        var historyAggregates: [WayTaskLegacyHistoryAggregateRecord] = []
        for history in source.historyAggregates.sorted(by: {
            uuidLess($0.id, $1.id)
        }) {
            guard historyIDs.insert(history.id).inserted else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .legacyHistoryUnlinked,
                        components: ["history-collision", history.id.uuidString],
                        digestKey: digestKey
                    )
                )
                continue
            }
            historyAggregates.append(history)
            facts.append(
                fact(
                    .legacyHistoryUnlinked,
                    components: ["legacy-aggregate", history.id.uuidString],
                    digestKey: digestKey
                )
            )
        }

        var compatibilityIDs = Set<UUID>()
        var compatibilityItems: [WayTaskLegacyCompatibilityEvidenceRecord] = []
        for item in source.compatibilityItems.sorted(by: {
            uuidLess($0.id, $1.id)
        }) {
            guard compatibilityIDs.insert(item.id).inserted else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .ambiguousRecord,
                        components: [
                            "compatibility-collision", item.id.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
                continue
            }
            compatibilityItems.append(item)
        }
        let itemByID = Dictionary(
            uniqueKeysWithValues: compatibilityItems.map { ($0.id, $0) }
        )
        var productIDsByCompatibilityID: [UUID: Set<UUID>] = [:]
        for product in source.productList.products {
            guard let compatibilityID = product.legacyShoppingItemID,
                  let productID = product.productID
            else { continue }
            productIDsByCompatibilityID[compatibilityID, default: []]
                .insert(productID)
        }

        var locationIDs = Set<UUID>()
        var savedLocations: [WayTaskLegacySavedLocationRecord] = []
        for location in source.savedLocations.sorted(by: {
            uuidLess($0.id, $1.id)
        }) {
            guard locationIDs.insert(location.id).inserted else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .savedLocationUnresolved,
                        components: [
                            "location-collision", location.id.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
                continue
            }
            let itemIDs = Array(Set(location.shoppingItemIDs)).sorted(
                by: uuidLess
            )
            if itemIDs.count != location.shoppingItemIDs.count {
                facts.append(
                    fact(
                        .savedLocationUnresolved,
                        components: [
                            "location-duplicate-edge", location.id.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
            }
            for itemID in itemIDs {
                if itemByID[itemID] == nil ||
                    productIDsByCompatibilityID[itemID]?.count != 1
                {
                    facts.append(
                        fact(
                            .savedLocationUnresolved,
                            components: [
                                "location-item", location.id.uuidString,
                                itemID.uuidString
                            ],
                            digestKey: digestKey
                        )
                    )
                }
            }
            savedLocations.append(
                WayTaskLegacySavedLocationRecord(
                    id: location.id,
                    title: location.title,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    radius: location.radius,
                    storeCategoryRawValue: location.storeCategoryRawValue,
                    addressText: location.addressText,
                    notes: location.notes,
                    sourceTypeRawValue: location.sourceTypeRawValue,
                    shoppingItemIDs: itemIDs
                )
            )
        }

        let legacyEntries = source.productList.entries
        var sessions: [WayTaskMigratedSessionRecord] = []
        var sessionIDs = Set<UUID>()
        for session in source.sessions.sorted(by: {
            uuidLess($0.id, $1.id)
        }) {
            guard sessionIDs.insert(session.id).inserted else {
                blockingAmbiguityCount += 1
                facts.append(
                    fact(
                        .ambiguousRecord,
                        sessionID: session.id,
                        components: ["session-collision", session.id.uuidString],
                        digestKey: digestKey
                    )
                )
                continue
            }
            sessions.append(
                migrateSession(
                    session,
                    legacyEntries: legacyEntries,
                    itemByID: itemByID,
                    targetEntryByID: targetEntryByID,
                    productByID: productByID,
                    entryAliases: entryAliases,
                    recordingTime: recordingTime,
                    digestKey: digestKey,
                    facts: &facts
                )
            )
        }

        let activeClaims = source.sessions.filter(\.isActive)
        if activeClaims.count > 1 {
            for session in activeClaims.sorted(by: {
                uuidLess($0.id, $1.id)
            }) {
                facts.append(
                    fact(
                        .multipleSessionCandidates,
                        sessionID: session.id,
                        components: [
                            "active-candidate", session.id.uuidString,
                            String(activeClaims.count)
                        ],
                        digestKey: digestKey
                    )
                )
            }
        }

        let projection = projectExceptions(
            facts,
            recordingTime: recordingTime,
            digestKey: digestKey
        )
        facts.append(contentsOf: projection.overflowFacts)
        sessions = sessions.map { session in
            attaching(
                projection.sessionRecords[session.id] ?? [],
                to: session
            )
        }

        archiveLists.sort { uuidLess($0.id, $1.id) }
        archiveEntries.sort(by: migratedEntryLess)
        sessions.sort { uuidLess($0.id, $1.id) }
        facts.sort(by: factLess)
        let target = WayTaskSessionHistoryArchiveSemanticSnapshot(
            productListBase: productListTarget,
            sessions: sessions,
            historyAggregates: historyAggregates,
            historyEvents: [],
            archiveLists: archiveLists,
            archiveEntries: archiveEntries,
            compatibilityItems: compatibilityItems,
            savedLocations: savedLocations,
            globalExceptions: projection.globalRecords
        )
        return WayTaskSessionHistoryArchiveSemanticPlan(
            target: target,
            exceptionFacts: facts,
            blockingAmbiguityCount: blockingAmbiguityCount,
            semanticDigest: try semanticDigest(target)
        )
    }

    static func semanticDigest(
        _ snapshot: WayTaskSessionHistoryArchiveSemanticSnapshot
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

    private static func migrateSession(
        _ source: WayTaskLegacySessionRecord,
        legacyEntries: [WayTaskLegacyShoppingEntryRecord],
        itemByID: [UUID: WayTaskLegacyCompatibilityEvidenceRecord],
        targetEntryByID: [UUID: WayTaskMigratedShoppingEntryRecord],
        productByID: [UUID: WayTaskMigratedProductRecord],
        entryAliases: [UUID: UUID],
        recordingTime: Date,
        digestKey: Data,
        facts: inout [WayTaskSessionHistoryArchiveExceptionFact]
    ) -> WayTaskMigratedSessionRecord {
        let snapshotID = stableUUID(
            "session-snapshot",
            [source.id.uuidString]
        )
        let parsedItems = parseTokens(
            source.itemIDListRawValue,
            collection: "item_ids",
            sessionID: source.id,
            digestKey: digestKey,
            facts: &facts
        )
        let parsedCollected = parseTokens(
            source.collectedItemIDListRawValue,
            collection: "collected_item_ids",
            sessionID: source.id,
            digestKey: digestKey,
            facts: &facts
        )

        let collectedUUIDs = Set(parsedCollected.compactMap(\.normalizedID))
        let collectedInvalidDigests = Set(
            parsedCollected.filter { $0.normalizedID == nil }
                .map(\.groupingDigest)
        )
        let itemUUIDs = Set(parsedItems.compactMap(\.normalizedID))
        var seenCollectedTokens: [String: ParsedToken] = [:]
        var startedCollectedDuplicateGroups = Set<String>()
        for token in parsedCollected {
            let collectedKey = token.normalizedID?.uuidString.lowercased() ??
                token.groupingDigest.rawValue
            if let first = seenCollectedTokens[collectedKey] {
                if startedCollectedDuplicateGroups.insert(collectedKey).inserted {
                    facts.append(
                        duplicateTokenFact(
                            first,
                            sessionID: source.id
                        )
                    )
                }
                facts.append(
                    duplicateTokenFact(
                        token,
                        sessionID: source.id
                    )
                )
            } else {
                seenCollectedTokens[collectedKey] = token
            }
            if let tokenID = token.normalizedID,
               !itemUUIDs.contains(tokenID)
            {
                facts.append(
                    tokenFact(
                        .foreignCollectedToken,
                        token: token,
                        sessionID: source.id
                    )
                )
            }
        }

        var stops: [WayTaskMigratedSessionStopRecord] = []
        let hasStoreEvidence = source.selectedStoreID != nil ||
            source.selectedStoreName != nil ||
            source.selectedStoreLatitude != nil ||
            source.selectedStoreLongitude != nil
        if hasStoreEvidence {
            let coordinatesAreValid = validCoordinates(
                latitude: source.selectedStoreLatitude,
                longitude: source.selectedStoreLongitude
            )
            if !coordinatesAreValid {
                facts.append(
                    fact(
                        .invalidSessionStore,
                        sessionID: source.id,
                        components: ["store-coordinate", source.id.uuidString],
                        digestKey: digestKey
                    )
                )
            }
            stops.append(
                WayTaskMigratedSessionStopRecord(
                    id: stableUUID("session-stop", [source.id.uuidString]),
                    sessionID: source.id,
                    snapshotID: snapshotID,
                    sortOrder: 0,
                    storeReferenceIDRawValue:
                        source.selectedStoreID?.uuidString.lowercased(),
                    storeReferenceProvenanceRawValue:
                        source.selectedStoreID == nil
                            ? "legacyTransient" : "legacyExact",
                    displayNameSnapshot: source.selectedStoreName ?? "",
                    latitudeSnapshot: coordinatesAreValid
                        ? source.selectedStoreLatitude : nil,
                    longitudeSnapshot: coordinatesAreValid
                        ? source.selectedStoreLongitude : nil,
                    evidenceAt: nil,
                    isSessionScopedTransient: source.selectedStoreID == nil
                )
            )
        } else {
            facts.append(
                fact(
                    .invalidSessionStore,
                    sessionID: source.id,
                    components: ["missing-store", source.id.uuidString],
                    digestKey: digestKey
                )
            )
        }

        if source.shoppingListID == nil {
            facts.append(
                fact(
                    .missingSessionSourceList,
                    sessionID: source.id,
                    components: ["source-list", source.id.uuidString],
                    digestKey: digestKey
                )
            )
        }

        var lines: [WayTaskMigratedSessionLineRecord] = []
        var seenLineTokens: [String: ParsedToken] = [:]
        var startedItemDuplicateGroups = Set<String>()
        var hasUnresolvedLine = false
        for token in parsedItems {
            let lineKey = token.normalizedID?.uuidString.lowercased() ??
                token.groupingDigest.rawValue
            if let first = seenLineTokens[lineKey] {
                if startedItemDuplicateGroups.insert(lineKey).inserted {
                    facts.append(
                        duplicateTokenFact(
                            first,
                            sessionID: source.id
                        )
                    )
                }
                facts.append(
                    duplicateTokenFact(
                        token,
                        sessionID: source.id
                    )
                )
                continue
            }
            seenLineTokens[lineKey] = token
            let lineID = stableUUID(
                "session-line",
                [source.id.uuidString, lineKey]
            )
            let item = token.normalizedID.flatMap { itemByID[$0] }
            let sourceEntries: [WayTaskLegacyShoppingEntryRecord]
            if let tokenID = token.normalizedID,
               let listID = source.shoppingListID
            {
                sourceEntries = legacyEntries.filter {
                    $0.legacyShoppingItemID == tokenID && $0.listID == listID
                }
            } else {
                sourceEntries = []
            }
            let canonicalEntryIDs: Set<UUID> = Set(
                sourceEntries.compactMap { entry -> UUID? in
                guard let entryID = entry.entryID else { return nil }
                return entryAliases[entryID] ?? entryID
                }
            )
            let targetEntries = canonicalEntryIDs.compactMap {
                targetEntryByID[$0]
            }.filter { $0.shoppingListID == source.shoppingListID }
            let exactEntry = targetEntries.count == 1
                ? targetEntries[0] : nil
            if exactEntry == nil || item == nil {
                hasUnresolvedLine = true
                facts.append(
                    tokenFact(
                        targetEntries.count > 1
                            ? .ambiguousSessionItem : .unresolvedSessionLine,
                        token: token,
                        sessionID: source.id,
                        sessionLineID: lineID
                    )
                )
            }
            let isCollected: Bool
            if let tokenID = token.normalizedID {
                isCollected = collectedUUIDs.contains(tokenID)
            } else {
                isCollected = collectedInvalidDigests.contains(
                    token.groupingDigest
                )
            }
            let productID = exactEntry?.productID
            if let productID,
               productByID[productID]?.libraryLifecycleRawValue ==
                    ProductLibraryLifecycle.removed.rawValue,
               source.isActive || source.finishedAt == nil
            {
                facts.append(
                    fact(
                        .tombstoneActiveReference,
                        sessionID: source.id,
                        sessionLineID: lineID,
                        components: [
                            "session-product", source.id.uuidString,
                            lineID.uuidString, productID.uuidString
                        ],
                        digestKey: digestKey
                    )
                )
            }
            let sortOrder = safeSortOrder(
                exactEntry?.sortOrder,
                fallback: token.ordinal - 1
            )
            lines.append(
                WayTaskMigratedSessionLineRecord(
                    id: lineID,
                    sessionID: source.id,
                    snapshotID: snapshotID,
                    snapshotVersion:
                        WayTaskSessionHistoryArchiveSemanticPlan
                            .snapshotVersion,
                    snapshotProvenanceRawValue: exactEntry == nil
                        ? "legacyUnresolved" : "legacyExact",
                    sourceListID: source.shoppingListID,
                    sourceEntryID: exactEntry?.id,
                    productID: productID,
                    globalProductConceptIDRawValue: nil,
                    stopID: stops.first?.id,
                    sortOrder: sortOrder,
                    productNameSnapshot: item?.name ?? "",
                    productBrandSnapshot: item?.brand,
                    productCategorySnapshot: item?.category,
                    quantitySnapshot: validQuantity(
                        exactEntry?.quantity ?? 1
                    ),
                    unitSnapshotRawValue: nil,
                    noteSnapshot: nil,
                    executionStateRawValue: isCollected
                        ? ShoppingSessionExecutionState.collected.rawValue
                        : ShoppingSessionExecutionState.remaining.rawValue,
                    executionChangedAt: nil,
                    finalOutcomeRawValue: nil,
                    finalOutcomeAt: nil,
                    finalOutcomeCommandID: nil,
                    legacyDispositionRawValue:
                        !source.isActive && source.finishedAt != nil
                            ? ShoppingSessionLegacyDisposition
                                .legacyUnknown.rawValue : nil
                )
            )
        }
        lines.sort { $0.sortOrder == $1.sortOrder
            ? uuidLess($0.id, $1.id) : $0.sortOrder < $1.sortOrder }

        var lifecycle: String
        var migrationCondition: String
        var expiredAt: Date?
        var expirationReason: String?
        if source.isActive && source.finishedAt != nil {
            lifecycle = ShoppingSessionLifecycle.active.rawValue
            migrationCondition =
                ShoppingSessionMigrationCondition.legacyUnresolved.rawValue
            facts.append(
                fact(
                    .sessionLifecycleContradiction,
                    sessionID: source.id,
                    components: ["active-finished", source.id.uuidString],
                    digestKey: digestKey
                )
            )
        } else if source.isActive {
            let inactivityBoundary = source.startedAt.addingTimeInterval(
                12 * 60 * 60
            )
            let maximumBoundary = source.startedAt.addingTimeInterval(
                72 * 60 * 60
            )
            let dueBoundary = min(inactivityBoundary, maximumBoundary)
            if recordingTime >= dueBoundary {
                lifecycle = ShoppingSessionLifecycle.expired.rawValue
                expiredAt = dueBoundary
                expirationReason = "legacyInactivity"
            } else {
                lifecycle = ShoppingSessionLifecycle.active.rawValue
            }
            migrationCondition = hasUnresolvedLine ||
                source.shoppingListID == nil
                    ? ShoppingSessionMigrationCondition
                        .legacyUnresolved.rawValue
                    : ShoppingSessionMigrationCondition.legacyMapped.rawValue
        } else if source.finishedAt != nil {
            lifecycle = ShoppingSessionLifecycle.finished.rawValue
            migrationCondition =
                ShoppingSessionMigrationCondition.legacyIncomplete.rawValue
        } else {
            lifecycle = "legacyInactive"
            migrationCondition =
                ShoppingSessionMigrationCondition.legacyUnresolved.rawValue
            facts.append(
                fact(
                    .sessionLifecycleContradiction,
                    sessionID: source.id,
                    components: ["inactive-unterminated", source.id.uuidString],
                    digestKey: digestKey
                )
            )
        }

        let signaturePayload = [
            source.id.uuidString.lowercased(),
            source.shoppingListID?.uuidString.lowercased() ?? "missing",
            parsedItems.map(\.digest.rawValue).joined(separator: ","),
            parsedCollected.map(\.digest.rawValue).joined(separator: ","),
            lifecycle,
            migrationCondition
        ].joined(separator: "|")
        return WayTaskMigratedSessionRecord(
            id: source.id,
            sourceListID: source.shoppingListID,
            sourceRevision: nil,
            sourceRevisionProvenanceRawValue: "legacyUnknown",
            revision:
                WayTaskSessionHistoryArchiveSemanticPlan.initialSessionRevision,
            lifecycleRawValue: lifecycle,
            migrationConditionRawValue: migrationCondition,
            snapshotID: snapshotID,
            snapshotVersion:
                WayTaskSessionHistoryArchiveSemanticPlan.snapshotVersion,
            snapshotGeneration:
                WayTaskSessionHistoryArchiveSemanticPlan.snapshotGeneration,
            snapshotContentSignature: WayTaskMigrationDigest.hex(
                hashing: Data(signaturePayload.utf8)
            ),
            sourcePlanID: nil,
            sourcePlanSignature: nil,
            sourcePlanEvidenceAt: nil,
            startedAt: source.startedAt,
            activationStartedAt: source.startedAt,
            lastActivityAt: source.startedAt,
            expiredAt: expiredAt,
            endedAt: source.finishedAt,
            expirationReasonRawValue: expirationReason,
            expirationPolicyVersion:
                WayTaskSessionHistoryArchiveSemanticPlan
                    .expirationPolicyVersion,
            lines: lines,
            stops: stops,
            exceptions: []
        )
    }

    private static func parseTokens(
        _ rawValue: String,
        collection: String,
        sessionID: UUID,
        digestKey: Data,
        facts: inout [WayTaskSessionHistoryArchiveExceptionFact]
    ) -> [ParsedToken] {
        guard !rawValue.isEmpty else { return [] }
        let values = rawValue.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        return values.enumerated().map { index, value in
            let raw = String(value)
            let normalizedID: UUID?
            if !raw.isEmpty,
               raw == raw.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                normalizedID = UUID(uuidString: raw)
            } else {
                normalizedID = nil
            }
            let digest = WayTaskMigrationSafeDigest(
                keyed: Data(
                    [
                        sessionID.uuidString.lowercased(), collection,
                        String(index + 1), raw
                    ].joined(separator: "|").utf8
                ),
                keyBytes: digestKey
            )
            let groupingDigest = WayTaskMigrationSafeDigest(
                keyed: Data(
                    [sessionID.uuidString.lowercased(), raw]
                        .joined(separator: "|").utf8
                ),
                keyBytes: digestKey
            )
            let token = ParsedToken(
                ordinal: index + 1,
                byteLength: raw.lengthOfBytes(using: .utf8),
                collection: collection,
                normalizedID: normalizedID,
                digest: digest,
                groupingDigest: groupingDigest
            )
            if normalizedID == nil {
                facts.append(
                    tokenFact(
                        .invalidSessionToken,
                        token: token,
                        sessionID: sessionID
                    )
                )
            }
            return token
        }
    }

    private static func projectExceptions(
        _ facts: [WayTaskSessionHistoryArchiveExceptionFact],
        recordingTime: Date,
        digestKey: Data
    ) -> ExceptionProjection {
        let grouped = Dictionary(grouping: facts, by: ExceptionGroupKey.init)
        let groups = grouped.keys.sorted()
        var bySession: [UUID: [ExceptionGroupKey]] = [:]
        var global: [ExceptionGroupKey] = []
        for key in groups {
            if let sessionID = key.sessionID {
                bySession[sessionID, default: []].append(key)
            } else {
                global.append(key)
            }
        }
        var sessionRecords: [UUID: [WayTaskMigratedSessionExceptionRecord]] = [:]
        var overflowFacts: [WayTaskSessionHistoryArchiveExceptionFact] = []
        for sessionID in bySession.keys.sorted(by: uuidLess) {
            let values = bySession[sessionID]!
            let retained = values.prefix(
                WayTaskSessionHistoryArchiveSemanticPlan
                    .perSessionExceptionCapacity
            )
            var records = retained.enumerated().map { index, key in
                exceptionRecord(
                    key,
                    facts: grouped[key]!,
                    ordinal: index + 1,
                    recordingTime: recordingTime
                )
            }
            let overflow = values.dropFirst(
                WayTaskSessionHistoryArchiveSemanticPlan
                    .perSessionExceptionCapacity
            ).reduce(0) { $0 + grouped[$1]!.count }
            if overflow > 0 {
                let digest = WayTaskMigrationSafeDigest(
                    keyed: Data(
                        [
                            "session-overflow", sessionID.uuidString,
                            String(overflow)
                        ].joined(separator: "|").utf8
                    ),
                    keyBytes: digestKey
                )
                records.append(
                    WayTaskMigratedSessionExceptionRecord(
                        id: stableUUID(
                            "session-exception-overflow",
                            [sessionID.uuidString, digest.rawValue]
                        ),
                        sessionID: sessionID,
                        sessionLineID: nil,
                        categoryRawValue:
                            WayTaskMigrationExceptionCategory
                                .sessionExceptionOverflow.rawValue,
                        safeEvidenceDigest: digest.rawValue,
                        ordinal:
                            WayTaskSessionHistoryArchiveSemanticPlan
                                .perSessionExceptionCapacity + 1,
                        occurrenceCount: overflow,
                        recordedAt: recordingTime,
                        sourceCollectionRawValue: nil,
                        sourceOrdinals: [],
                        sourceByteLength: nil,
                        normalizedTokenID: nil
                    )
                )
                for _ in 0..<overflow {
                    overflowFacts.append(
                        WayTaskSessionHistoryArchiveExceptionFact(
                            sessionID: sessionID,
                            sessionLineID: nil,
                            category: .sessionExceptionOverflow,
                            safeEvidenceDigest: digest,
                            sourceCollectionRawValue: nil,
                            sourceOrdinal: nil,
                            sourceByteLength: nil,
                            normalizedTokenID: nil
                        )
                    )
                }
            }
            sessionRecords[sessionID] = records
        }
        let globalRecords = global.enumerated().map { index, key in
            exceptionRecord(
                key,
                facts: grouped[key]!,
                ordinal: index + 1,
                recordingTime: recordingTime
            )
        }
        return ExceptionProjection(
            sessionRecords: sessionRecords,
            globalRecords: globalRecords,
            overflowFacts: overflowFacts
        )
    }

    private static func exceptionRecord(
        _ key: ExceptionGroupKey,
        facts: [WayTaskSessionHistoryArchiveExceptionFact],
        ordinal: Int,
        recordingTime: Date
    ) -> WayTaskMigratedSessionExceptionRecord {
        let ordinals = facts.compactMap(\.sourceOrdinal).sorted()
        return WayTaskMigratedSessionExceptionRecord(
            id: stableUUID(
                "migration-exception",
                [
                    key.sessionID?.uuidString ?? "global",
                    key.category.rawValue,
                    key.digest.rawValue,
                    String(ordinal)
                ]
            ),
            sessionID: key.sessionID,
            sessionLineID: key.sessionLineID,
            categoryRawValue: key.category.rawValue,
            safeEvidenceDigest: key.digest.rawValue,
            ordinal: ordinal,
            occurrenceCount: facts.count,
            recordedAt: recordingTime,
            sourceCollectionRawValue: key.sourceCollectionRawValue,
            sourceOrdinals: ordinals,
            sourceByteLength: key.sourceByteLength,
            normalizedTokenID: key.normalizedTokenID
        )
    }

    private static func attaching(
        _ exceptions: [WayTaskMigratedSessionExceptionRecord],
        to session: WayTaskMigratedSessionRecord
    ) -> WayTaskMigratedSessionRecord {
        WayTaskMigratedSessionRecord(
            id: session.id,
            sourceListID: session.sourceListID,
            sourceRevision: session.sourceRevision,
            sourceRevisionProvenanceRawValue:
                session.sourceRevisionProvenanceRawValue,
            revision: session.revision,
            lifecycleRawValue: session.lifecycleRawValue,
            migrationConditionRawValue: session.migrationConditionRawValue,
            snapshotID: session.snapshotID,
            snapshotVersion: session.snapshotVersion,
            snapshotGeneration: session.snapshotGeneration,
            snapshotContentSignature: session.snapshotContentSignature,
            sourcePlanID: session.sourcePlanID,
            sourcePlanSignature: session.sourcePlanSignature,
            sourcePlanEvidenceAt: session.sourcePlanEvidenceAt,
            startedAt: session.startedAt,
            activationStartedAt: session.activationStartedAt,
            lastActivityAt: session.lastActivityAt,
            expiredAt: session.expiredAt,
            endedAt: session.endedAt,
            expirationReasonRawValue: session.expirationReasonRawValue,
            expirationPolicyVersion: session.expirationPolicyVersion,
            lines: session.lines,
            stops: session.stops,
            exceptions: exceptions
        )
    }

    private static func fact(
        _ category: WayTaskMigrationExceptionCategory,
        sessionID: UUID? = nil,
        sessionLineID: UUID? = nil,
        components: [String],
        digestKey: Data
    ) -> WayTaskSessionHistoryArchiveExceptionFact {
        WayTaskSessionHistoryArchiveExceptionFact(
            sessionID: sessionID,
            sessionLineID: sessionLineID,
            category: category,
            safeEvidenceDigest: WayTaskMigrationSafeDigest(
                keyed: Data(
                    ([category.rawValue] + components)
                        .joined(separator: "|").lowercased().utf8
                ),
                keyBytes: digestKey
            ),
            sourceCollectionRawValue: nil,
            sourceOrdinal: nil,
            sourceByteLength: nil,
            normalizedTokenID: nil
        )
    }

    private static func tokenFact(
        _ category: WayTaskMigrationExceptionCategory,
        token: ParsedToken,
        sessionID: UUID,
        sessionLineID: UUID? = nil
    ) -> WayTaskSessionHistoryArchiveExceptionFact {
        WayTaskSessionHistoryArchiveExceptionFact(
            sessionID: sessionID,
            sessionLineID: sessionLineID,
            category: category,
            safeEvidenceDigest: token.digest,
            sourceCollectionRawValue: token.collection,
            sourceOrdinal: token.ordinal,
            sourceByteLength: token.byteLength,
            normalizedTokenID: token.normalizedID
        )
    }

    private static func duplicateTokenFact(
        _ token: ParsedToken,
        sessionID: UUID
    ) -> WayTaskSessionHistoryArchiveExceptionFact {
        WayTaskSessionHistoryArchiveExceptionFact(
            sessionID: sessionID,
            sessionLineID: nil,
            category: .duplicateSessionToken,
            safeEvidenceDigest: token.groupingDigest,
            sourceCollectionRawValue: token.collection,
            sourceOrdinal: token.ordinal,
            sourceByteLength: token.byteLength,
            normalizedTokenID: token.normalizedID
        )
    }

    private static func stableUUID(
        _ namespace: String,
        _ components: [String]
    ) -> UUID {
        var bytes = Array(
            SHA256.hash(
                data: Data(
                    ([namespace] + components)
                        .joined(separator: "|").lowercased().utf8
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

    nonisolated private static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    nonisolated private static func listLess(
        _ lhs: WayTaskLegacyShoppingListRecord,
        _ rhs: WayTaskLegacyShoppingListRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
    }

    nonisolated private static func entryLess(
        _ lhs: WayTaskLegacyShoppingEntryRecord,
        _ rhs: WayTaskLegacyShoppingEntryRecord
    ) -> Bool {
        if lhs.sourceRecordID != rhs.sourceRecordID {
            return uuidLess(lhs.sourceRecordID, rhs.sourceRecordID)
        }
        return (lhs.entryID?.uuidString ?? "") <
            (rhs.entryID?.uuidString ?? "")
    }

    nonisolated private static func migratedEntryLess(
        _ lhs: WayTaskMigratedShoppingEntryRecord,
        _ rhs: WayTaskMigratedShoppingEntryRecord
    ) -> Bool {
        if lhs.shoppingListID != rhs.shoppingListID {
            return uuidLess(lhs.shoppingListID, rhs.shoppingListID)
        }
        if lhs.productID != rhs.productID {
            return uuidLess(lhs.productID, rhs.productID)
        }
        return uuidLess(lhs.id, rhs.id)
    }

    nonisolated private static func factLess(
        _ lhs: WayTaskSessionHistoryArchiveExceptionFact,
        _ rhs: WayTaskSessionHistoryArchiveExceptionFact
    ) -> Bool {
        if lhs.sessionID != rhs.sessionID {
            return (lhs.sessionID?.uuidString.lowercased() ?? "") <
                (rhs.sessionID?.uuidString.lowercased() ?? "")
        }
        if lhs.category.rawValue != rhs.category.rawValue {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        if lhs.sourceCollectionRawValue != rhs.sourceCollectionRawValue {
            return (lhs.sourceCollectionRawValue ?? "") <
                (rhs.sourceCollectionRawValue ?? "")
        }
        if lhs.sourceOrdinal != rhs.sourceOrdinal {
            return (lhs.sourceOrdinal ?? 0) < (rhs.sourceOrdinal ?? 0)
        }
        return lhs.safeEvidenceDigest.rawValue <
            rhs.safeEvidenceDigest.rawValue
    }

    private static func validQuantity(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 1
    }

    private static func safeSortOrder(
        _ value: Double?,
        fallback: Int
    ) -> Int {
        guard let value, value.isFinite,
              value >= Double(Int.min), value <= Double(Int.max)
        else { return fallback }
        return Int(value.rounded(.towardZero))
    }

    private static func validCoordinates(
        latitude: Double?,
        longitude: Double?
    ) -> Bool {
        guard let latitude, let longitude,
              latitude.isFinite, longitude.isFinite
        else { return false }
        return (-90...90).contains(latitude) &&
            (-180...180).contains(longitude)
    }

    private struct ParsedToken {
        let ordinal: Int
        let byteLength: Int
        let collection: String
        let normalizedID: UUID?
        let digest: WayTaskMigrationSafeDigest
        let groupingDigest: WayTaskMigrationSafeDigest
    }

    private struct ExceptionGroupKey: Hashable, Comparable {
        let sessionID: UUID?
        let sessionLineID: UUID?
        let category: WayTaskMigrationExceptionCategory
        let digest: WayTaskMigrationSafeDigest
        let sourceCollectionRawValue: String?
        let sourceByteLength: Int?
        let normalizedTokenID: UUID?

        nonisolated init(
            _ fact: WayTaskSessionHistoryArchiveExceptionFact
        ) {
            sessionID = fact.sessionID
            sessionLineID = fact.sessionLineID
            category = fact.category
            digest = fact.safeEvidenceDigest
            sourceCollectionRawValue = fact.sourceCollectionRawValue
            sourceByteLength = fact.sourceByteLength
            normalizedTokenID = fact.normalizedTokenID
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            let left = [
                lhs.sessionID?.uuidString.lowercased() ?? "",
                lhs.sessionLineID?.uuidString.lowercased() ?? "",
                lhs.category.rawValue,
                lhs.sourceCollectionRawValue ?? "",
                lhs.normalizedTokenID?.uuidString.lowercased() ?? "",
                String(lhs.sourceByteLength ?? -1),
                lhs.digest.rawValue
            ].joined(separator: "|")
            let right = [
                rhs.sessionID?.uuidString.lowercased() ?? "",
                rhs.sessionLineID?.uuidString.lowercased() ?? "",
                rhs.category.rawValue,
                rhs.sourceCollectionRawValue ?? "",
                rhs.normalizedTokenID?.uuidString.lowercased() ?? "",
                String(rhs.sourceByteLength ?? -1),
                rhs.digest.rawValue
            ].joined(separator: "|")
            return left < right
        }
    }

    private struct ExceptionProjection {
        let sessionRecords:
            [UUID: [WayTaskMigratedSessionExceptionRecord]]
        let globalRecords: [WayTaskMigratedSessionExceptionRecord]
        let overflowFacts: [WayTaskSessionHistoryArchiveExceptionFact]
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

@MainActor
struct WayTaskSessionHistoryArchiveMigrationDependencies {
    var readPhysicalCandidate:
        (URL) throws -> WayTaskSessionHistoryArchiveSourceSnapshot
    var extendTargetStore:
        (WayTaskSessionHistoryArchiveSemanticSnapshot, URL) throws -> Void
    var reopenTargetStore:
        (URL) throws -> WayTaskSessionHistoryArchiveSemanticSnapshot
    var recordingTime: (WayTaskMigrationAttemptIdentity) -> Date

    static var live: Self {
        Self(
            readPhysicalCandidate:
                WayTaskSessionHistoryArchiveStoreBoundary.readPhysicalCandidate,
            extendTargetStore:
                WayTaskSessionHistoryArchiveStoreBoundary.extendTargetStore,
            reopenTargetStore:
                WayTaskSessionHistoryArchiveStoreBoundary.reopenTargetStore,
            recordingTime: { attempt in
                let value = UInt64(
                    attempt.rawValue.suffix(12),
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
    static let sessionHistoryArchiveSummaryFilename =
        "session-history-archive-location-summary.json"
    static let sessionExceptionEvidenceFilename =
        "session-migration-exception-evidence.json"
    static let attemptDirectoryPrefix = "wt033a-tc13-"

    private let dependencies: WayTaskProductStateMigrationDependencies
    private let semanticDependencies:
        WayTaskProductListSemanticMigrationDependencies
    private let sessionHistoryDependencies:
        WayTaskSessionHistoryArchiveMigrationDependencies

    init() {
        dependencies = .live
        semanticDependencies = .live
        sessionHistoryDependencies = .live
    }

    init(dependencies: WayTaskProductStateMigrationDependencies) {
        self.dependencies = dependencies
        semanticDependencies = .live
        sessionHistoryDependencies = .live
    }

    init(
        dependencies: WayTaskProductStateMigrationDependencies,
        semanticDependencies:
            WayTaskProductListSemanticMigrationDependencies
    ) {
        self.dependencies = dependencies
        self.semanticDependencies = semanticDependencies
        sessionHistoryDependencies = .live
    }

    init(
        dependencies: WayTaskProductStateMigrationDependencies,
        semanticDependencies:
            WayTaskProductListSemanticMigrationDependencies,
        sessionHistoryDependencies:
            WayTaskSessionHistoryArchiveMigrationDependencies
    ) {
        self.dependencies = dependencies
        self.semanticDependencies = semanticDependencies
        self.sessionHistoryDependencies = sessionHistoryDependencies
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
        semanticDigest: String? = nil,
        sessionHistoryArchiveStageIdentity: String? = nil,
        completeSemanticTargetFingerprint: String? = nil,
        completeSemanticDigest: String? = nil
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
            semanticDigest: semanticDigest,
            sessionHistoryArchiveStageIdentity:
                sessionHistoryArchiveStageIdentity,
            completeSemanticTargetFingerprint:
                completeSemanticTargetFingerprint,
            completeSemanticDigest: completeSemanticDigest
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
        let sessionHistoryArchiveStageIdentity: String?
        let completeSemanticTargetFingerprint: String?
        let completeSemanticDigest: String?
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

// MARK: - T-08 Session/history/archive/location candidate stage

extension WayTaskProductStateMigration {
    func migrateSessionHistoryArchiveSemantics(
        _ receipt: WayTaskProductListSemanticReceipt
    ) -> WayTaskSessionHistoryArchiveMigrationResult {
        let foundation = receipt.foundationReceipt
        let sourceURL = foundation.sourceInventory.components.first {
            $0.role == .database
        }?.url
        var ledger: WayTaskMigrationExceptionLedger
        var ledgerReadFailed = false
        do {
            ledger = try WayTaskMigrationExceptionLedger(
                encodedData: dependencies.readOwnedArtifact(
                    foundation.candidateAttemptDirectoryURL
                        .appendingPathComponent(Self.exceptionLedgerFilename)
                )
            )
        } catch {
            ledgerReadFailed = true
            ledger = WayTaskMigrationExceptionLedger(
                capacity: receipt.exceptionSummary.capacity
            )
        }

        func fail(
            _ classification: WayTaskMigrationFailureClassification
        ) -> WayTaskSessionHistoryArchiveMigrationResult {
            guard let sourceURL else {
                return .failed(
                    WayTaskMigrationFailure(
                        classification: classification,
                        triggeringClassification: classification,
                        precedingClassification: nil,
                        rollbackClassification: .notRequired,
                        stageIdentity: foundation.stageIdentity,
                        attemptIdentity: foundation.attemptIdentity,
                        sourceSchemaIdentity:
                            foundation.sourceSchemaIdentity,
                        sourceFingerprint: foundation.sourceFingerprint,
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
                    candidateRootURL: foundation.candidateRootURL,
                    sourceInventory: foundation.sourceInventory,
                    sourceSchema: foundation.sourceSchemaIdentity,
                    stageIdentity: foundation.stageIdentity,
                    attemptIdentity: foundation.attemptIdentity,
                    attemptDirectoryURL:
                        foundation.candidateAttemptDirectoryURL,
                    attemptCreatedByThisInvocation: false,
                    exceptionSummary: ledger.summary
                )
            )
        }

        guard receipt.status == .productListSemanticMigrationComplete,
              receipt.completion == .productListSemanticMigrationComplete,
              receipt.productListSemanticConversionCompleted,
              !receipt.sessionHistoryLocationSemanticConversionCompleted,
              !receipt.promotionAuthorized,
              !receipt.startupActivationAuthorized,
              sourceURL != nil,
              (try? ownsAttemptDirectory(
                  foundation.candidateAttemptDirectoryURL,
                  candidateRootURL: foundation.candidateRootURL,
                  stageIdentity: foundation.stageIdentity,
                  attemptIdentity: foundation.attemptIdentity
              )) == true
        else {
            return fail(.candidateOwnershipConflict)
        }
        guard !ledgerReadFailed,
              ledger.summary == receipt.exceptionSummary
        else {
            return fail(.exceptionLedgerWriteFailed)
        }

        do {
            try verifySource(sourceURL!, expected: foundation.sourceFingerprint)
        } catch let error as ClassifiedFailure {
            return fail(error.classification)
        } catch {
            return fail(.sourceRevalidationFailed)
        }

        do {
            let physicalInventory = try dependencies.inspectStore(
                foundation.candidateStoreURL
            )
            guard physicalInventory.fingerprint ==
                    foundation.candidateFingerprint
            else { return fail(.candidateFingerprintMismatch) }
            let semanticInventory = try dependencies.inspectStore(
                receipt.targetStoreURL
            )
            guard semanticInventory.fingerprint == receipt.targetFingerprint
            else { return fail(.semanticFingerprintMismatch) }
        } catch {
            return fail(.sessionHistoryCandidateReadFailed)
        }

        let sourceSnapshot: WayTaskSessionHistoryArchiveSourceSnapshot
        do {
            sourceSnapshot = try sessionHistoryDependencies
                .readPhysicalCandidate(foundation.candidateStoreURL)
        } catch {
            return fail(.sessionHistoryCandidateReadFailed)
        }

        let recordingTime = sessionHistoryDependencies.recordingTime(
            foundation.attemptIdentity
        )
        let plan: WayTaskSessionHistoryArchiveSemanticPlan
        do {
            plan = try WayTaskSessionHistoryArchiveSemanticNormalizer.normalize(
                sourceSnapshot,
                productListTarget: receipt.targetValidation,
                aliases: receipt.aliases,
                recordingTime: recordingTime,
                digestKey: Data(foundation.attemptIdentity.rawValue.utf8)
            )
        } catch {
            return fail(.sessionHistoryNormalizationFailed)
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
                foundation.candidateAttemptDirectoryURL
                    .appendingPathComponent(Self.exceptionLedgerFilename)
            )
        } catch {
            return fail(.exceptionLedgerWriteFailed)
        }
        guard plan.blockingAmbiguityCount == 0 else {
            return fail(.sessionHistoryNormalizationFailed)
        }

        do {
            let records = plan.target.sessions.flatMap { $0.exceptions } +
                plan.target.globalExceptions
            let artifact = WayTaskSessionExceptionEvidenceArtifact(
                formatVersion: 1,
                records: records.sorted { $0.id.uuidString < $1.id.uuidString }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try dependencies.writeOwnedArtifact(
                encoder.encode(artifact),
                foundation.candidateAttemptDirectoryURL
                    .appendingPathComponent(
                        Self.sessionExceptionEvidenceFilename
                    )
            )
        } catch {
            return fail(.exceptionLedgerWriteFailed)
        }

        do {
            try sessionHistoryDependencies.extendTargetStore(
                plan.target,
                receipt.targetStoreURL
            )
        } catch {
            return fail(.sessionHistoryTargetWriteFailed)
        }

        let reopened: WayTaskSessionHistoryArchiveSemanticSnapshot
        do {
            reopened = try sessionHistoryDependencies.reopenTargetStore(
                receipt.targetStoreURL
            )
        } catch {
            return fail(.sessionHistoryTargetReopenFailed)
        }
        let reopenedDigest: WayTaskMigrationFingerprint
        do {
            reopenedDigest = try
                WayTaskSessionHistoryArchiveSemanticNormalizer.semanticDigest(
                    reopened
                )
        } catch {
            return fail(.sessionHistoryValidationFailed)
        }
        guard reopened == plan.target,
              reopenedDigest == plan.semanticDigest,
              Set(reopened.sessions.map(\.id)).count ==
                reopened.sessions.count,
              Set(reopened.sessions.flatMap { $0.lines }.map(\.id)).count ==
                reopened.sessions.flatMap({ $0.lines }).count,
              Set(reopened.sessions.flatMap { $0.stops }.map(\.id)).count ==
                reopened.sessions.flatMap({ $0.stops }).count,
              reopened.sessions.allSatisfy({ session in
                  session.revision ==
                    WayTaskSessionHistoryArchiveSemanticPlan
                        .initialSessionRevision &&
                  session.lines.allSatisfy { $0.sessionID == session.id } &&
                  session.stops.allSatisfy { $0.sessionID == session.id } &&
                  session.exceptions.allSatisfy {
                      $0.sessionID == session.id
                  }
              }),
              Set(reopened.historyAggregates.map(\.id)).count ==
                reopened.historyAggregates.count,
              reopened.historyEvents.isEmpty,
              Set(reopened.archiveLists.map(\.id)).count ==
                reopened.archiveLists.count,
              Set(reopened.archiveEntries.map(\.id)).count ==
                reopened.archiveEntries.count,
              reopened.archiveEntries.allSatisfy({ entry in
                  reopened.archiveLists.contains {
                      $0.id == entry.shoppingListID
                  }
              }),
              Set(reopened.compatibilityItems.map(\.id)).count ==
                reopened.compatibilityItems.count,
              Set(reopened.savedLocations.map(\.id)).count ==
                reopened.savedLocations.count
        else {
            return fail(.sessionHistoryValidationFailed)
        }

        let secondInventory: WayTaskMigrationStoreInventory
        let stableInventory: WayTaskMigrationStoreInventory
        do {
            secondInventory = try dependencies.inspectStore(
                receipt.targetStoreURL
            )
            stableInventory = try dependencies.inspectStore(
                receipt.targetStoreURL
            )
        } catch {
            return fail(.sessionHistoryTargetReopenFailed)
        }
        guard secondInventory.fingerprint == stableInventory.fingerprint else {
            return fail(.sessionHistoryFingerprintMismatch)
        }

        let stage = WayTaskSessionHistoryArchiveStageIdentity(
            productListReceipt: receipt
        )
        do {
            try writeSessionHistoryArchiveSummary(
                plan: plan,
                ledger: ledger,
                stageIdentity: stage,
                attemptIdentity: foundation.attemptIdentity,
                targetFingerprint: stableInventory.fingerprint,
                at: foundation.candidateAttemptDirectoryURL
                    .appendingPathComponent(
                        Self.sessionHistoryArchiveSummaryFilename
                    )
            )
            try writeManifest(
                at: foundation.candidateAttemptDirectoryURL,
                stageIdentity: foundation.stageIdentity,
                attemptIdentity: foundation.attemptIdentity,
                sourceFingerprint: foundation.sourceFingerprint,
                candidateFingerprint: foundation.candidateFingerprint,
                status:
                    .sessionHistoryArchiveLocationSemanticMigrationComplete,
                completion:
                    .sessionHistoryArchiveLocationSemanticMigrationComplete,
                failure: nil,
                exceptionSummary: ledger.summary,
                semanticStageIdentity: receipt.semanticStageIdentity.rawValue,
                semanticTargetFingerprint: receipt.targetFingerprint.rawValue,
                semanticDigest: receipt.semanticDigest.rawValue,
                sessionHistoryArchiveStageIdentity: stage.rawValue,
                completeSemanticTargetFingerprint:
                    stableInventory.fingerprint.rawValue,
                completeSemanticDigest: plan.semanticDigest.rawValue
            )
            try verifySource(sourceURL!, expected: foundation.sourceFingerprint)
        } catch let error as ClassifiedFailure {
            return fail(error.classification)
        } catch {
            return fail(.sessionHistoryValidationFailed)
        }

        let ownedArtifactNames: [String]
        do {
            ownedArtifactNames = try dependencies.enumerateOwnedArtifacts(
                foundation.candidateAttemptDirectoryURL
            )
        } catch {
            return fail(.sessionHistoryValidationFailed)
        }
        return .complete(
            WayTaskSessionHistoryArchiveMigrationReceipt(
                productListReceipt: receipt,
                semanticStageIdentity: stage,
                targetStoreURL: receipt.targetStoreURL,
                targetFingerprint: stableInventory.fingerprint,
                semanticDigest: plan.semanticDigest,
                targetValidation: reopened,
                exceptionSummary: ledger.summary,
                ownedArtifactNames: ownedArtifactNames,
                status:
                    .sessionHistoryArchiveLocationSemanticMigrationComplete,
                completion:
                    .sessionHistoryArchiveLocationSemanticMigrationComplete
            )
        )
    }

    private func writeSessionHistoryArchiveSummary(
        plan: WayTaskSessionHistoryArchiveSemanticPlan,
        ledger: WayTaskMigrationExceptionLedger,
        stageIdentity: WayTaskSessionHistoryArchiveStageIdentity,
        attemptIdentity: WayTaskMigrationAttemptIdentity,
        targetFingerprint: WayTaskMigrationFingerprint,
        at url: URL
    ) throws {
        let artifact = SessionHistoryArchiveSummaryArtifact(
            formatVersion: 1,
            semanticStageIdentity: stageIdentity.rawValue,
            attemptIdentity: attemptIdentity.rawValue,
            semanticDigest: plan.semanticDigest.rawValue,
            targetFingerprint: targetFingerprint.rawValue,
            sessionCount: plan.target.sessions.count,
            sessionLineCount: plan.target.sessions.flatMap { $0.lines }.count,
            sessionStopCount: plan.target.sessions.flatMap { $0.stops }.count,
            legacyHistoryAggregateCount:
                plan.target.historyAggregates.count,
            targetHistoryEventCount: plan.target.historyEvents.count,
            archiveListCount: plan.target.archiveLists.count,
            archiveEntryCount: plan.target.archiveEntries.count,
            savedLocationCount: plan.target.savedLocations.count,
            compatibilityEvidenceCount:
                plan.target.compatibilityItems.count,
            exceptionCount: ledger.summary.totalOccurrenceCount,
            exceptionOverflowCount: ledger.summary.overflowOccurrenceCount,
            productListSemanticMigrationComplete: true,
            sessionHistoryLocationSemanticMigrationComplete: true,
            promotionAuthorized: false,
            startupActivationAuthorized: false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try dependencies.writeOwnedArtifact(try encoder.encode(artifact), url)
    }

    private struct SessionHistoryArchiveSummaryArtifact: Codable {
        let formatVersion: Int
        let semanticStageIdentity: String
        let attemptIdentity: String
        let semanticDigest: String
        let targetFingerprint: String
        let sessionCount: Int
        let sessionLineCount: Int
        let sessionStopCount: Int
        let legacyHistoryAggregateCount: Int
        let targetHistoryEventCount: Int
        let archiveListCount: Int
        let archiveEntryCount: Int
        let savedLocationCount: Int
        let compatibilityEvidenceCount: Int
        let exceptionCount: Int
        let exceptionOverflowCount: Int
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
            let archiveKinds = Set([
                ShoppingListKind.completed.rawValue,
                ShoppingListKind.recent.rawValue
            ])
            let archiveListIDs = Set(lists.filter {
                guard let purpose = $0.purposeRawValue else { return false }
                return archiveKinds.contains(purpose)
            }.map(\.id))
            var entries = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            ).map { entry in
                let relationshipID = entry.product?.id
                guard archiveListIDs.contains(entry.shoppingListID)
                    ? relationshipID == nil || relationshipID == entry.productID
                    : relationshipID == entry.productID
                else {
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

@MainActor
private enum WayTaskSessionHistoryArchiveStoreBoundary {
    static func readPhysicalCandidate(
        storeURL: URL
    ) throws -> WayTaskSessionHistoryArchiveSourceSnapshot {
        let productList = try WayTaskProductListSemanticStoreBoundary
            .readPhysicalCandidate(storeURL: storeURL)
        return try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV3.self)
            let configuration = ModelConfiguration(
                "WT033A-T08-Physical-Candidate-Read",
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
            let sessions = try context.fetch(
                FetchDescriptor<ShoppingSession>()
            ).map { session in
                WayTaskLegacySessionRecord(
                    id: session.id,
                    startedAt: session.startedAt,
                    finishedAt: session.finishedAt,
                    isActive: session.isActive,
                    itemIDListRawValue: session.itemIDListRawValue,
                    collectedItemIDListRawValue:
                        session.collectedItemIDListRawValue,
                    shoppingListID: session.shoppingListID,
                    selectedStoreID: session.selectedStoreID,
                    selectedStoreName: session.selectedStoreName,
                    selectedStoreLatitude:
                        session.selectedStoreLatitude,
                    selectedStoreLongitude:
                        session.selectedStoreLongitude
                )
            }
            let histories = try context.fetch(
                FetchDescriptor<ProductHistory>()
            ).map { history in
                WayTaskLegacyHistoryAggregateRecord(
                    id: history.id,
                    productKey: history.productKey,
                    productName: history.productName,
                    barcode: history.barcode,
                    firstAddedDate: history.firstAddedDate,
                    lastAddedDate: history.lastAddedDate,
                    addCount: history.addCount,
                    lastSourceRawValue: history.lastSourceRawValue,
                    averageInterval: history.averageInterval,
                    lastCompletedDate: history.lastCompletedDate
                )
            }
            let items = try context.fetch(
                FetchDescriptor<ShoppingItem>()
            ).map { item in
                WayTaskLegacyCompatibilityEvidenceRecord(
                    id: item.id,
                    name: item.name,
                    isCompleted: item.isCompleted,
                    imageData: item.imageData,
                    brand: item.brand,
                    category: item.category,
                    barcode: item.barcode,
                    imageURLString: item.imageURLString,
                    dateAdded: item.dateAdded,
                    sourceRawValue: item.sourceRawValue,
                    productType: item.productType,
                    flavor: item.flavor,
                    packageSize: item.packageSize,
                    packageType: item.packageType,
                    visibleText: item.visibleText,
                    searchKeywordsRawValue: item.searchKeywordsRawValue
                )
            }
            let locations = try context.fetch(
                FetchDescriptor<GeoLocation>()
            ).map { location in
                WayTaskLegacySavedLocationRecord(
                    id: location.id,
                    title: location.title,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    radius: location.radius,
                    storeCategoryRawValue:
                        location.storeCategoryRawValue,
                    addressText: location.addressText,
                    notes: location.notes,
                    sourceTypeRawValue: location.sourceTypeRawValue,
                    shoppingItemIDs: location.shoppingItems.map(\.id)
                )
            }
            return WayTaskSessionHistoryArchiveSourceSnapshot(
                productList: productList,
                sessions: sessions,
                historyAggregates: histories,
                compatibilityItems: items,
                savedLocations: locations
            )
        }
    }

    static func extendTargetStore(
        snapshot: WayTaskSessionHistoryArchiveSemanticSnapshot,
        storeURL: URL
    ) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
            let configuration = ModelConfiguration(
                "WT033A-T08-Inactive-V4-Target",
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
            guard try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
            ) == 0,
            try context.fetchCount(FetchDescriptor<ProductHistory>()) == 0,
            try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 0,
            try context.fetchCount(FetchDescriptor<GeoLocation>()) == 0,
            try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
            ) == 0,
            try context.fetchCount(
                FetchDescriptor<WayTaskSchemaV4.ProductStateMigrationException>()
            ) == 0
            else { throw StoreError.targetAlreadyContainsT08Data }

            let products = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.Product>()
            )
            let productsByID = Dictionary(
                uniqueKeysWithValues: products.map { ($0.id, $0) }
            )
            let currentLists = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
            )
            var listsByID = Dictionary(
                uniqueKeysWithValues: currentLists.map { ($0.id, $0) }
            )
            let currentEntries = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
            )
            var entriesByID = Dictionary(
                uniqueKeysWithValues: currentEntries.map { ($0.id, $0) }
            )

            var compatibilityItemsByID: [UUID: ShoppingItem] = [:]
            for record in snapshot.compatibilityItems {
                let item = ShoppingItem(
                    id: record.id,
                    name: record.name,
                    isCompleted: record.isCompleted,
                    imageData: record.imageData,
                    brand: record.brand,
                    category: record.category,
                    barcode: record.barcode,
                    imageURL: record.imageURLString.flatMap(URL.init(string:)),
                    dateAdded: record.dateAdded,
                    source: ProductSource(rawValue: record.sourceRawValue) ??
                        .manual,
                    productType: record.productType,
                    flavor: record.flavor,
                    packageSize: record.packageSize,
                    packageType: record.packageType,
                    visibleText: record.visibleText
                )
                item.imageURLString = record.imageURLString
                item.sourceRawValue = record.sourceRawValue
                item.searchKeywordsRawValue = record.searchKeywordsRawValue
                context.insert(item)
                compatibilityItemsByID[record.id] = item
            }

            for record in snapshot.savedLocations {
                let location = GeoLocation(
                    id: record.id,
                    title: record.title,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    radius: record.radius,
                    storeCategory: record.storeCategoryRawValue.flatMap(
                        ShoppingStoreCategory.init(rawValue:)
                    ),
                    addressText: record.addressText,
                    notes: record.notes,
                    sourceType: record.sourceTypeRawValue.flatMap(
                        DataSourceType.init(rawValue:)
                    ) ?? .userGenerated,
                    shoppingItems: record.shoppingItemIDs.compactMap {
                        compatibilityItemsByID[$0]
                    }
                )
                location.storeCategoryRawValue = record.storeCategoryRawValue
                location.sourceTypeRawValue = record.sourceTypeRawValue
                context.insert(location)
            }

            for record in snapshot.historyAggregates {
                let history = ProductHistory(
                    id: record.id,
                    productKey: record.productKey,
                    productName: record.productName,
                    barcode: record.barcode,
                    firstAddedDate: record.firstAddedDate,
                    lastAddedDate: record.lastAddedDate,
                    addCount: record.addCount,
                    lastSource:
                        ProductSource(rawValue: record.lastSourceRawValue) ??
                            .manual,
                    averageInterval: record.averageInterval,
                    lastCompletedDate: record.lastCompletedDate
                )
                history.lastSourceRawValue = record.lastSourceRawValue
                context.insert(history)
            }

            let archiveEntriesByList = Dictionary(
                grouping: snapshot.archiveEntries,
                by: \.shoppingListID
            )
            for record in snapshot.archiveLists {
                let entries = (archiveEntriesByList[record.id] ?? []).map {
                    entry in
                    WayTaskSchemaV4.ShoppingListEntry(
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
                        product: productsByID[entry.productID]
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
                listsByID[record.id] = list
                for entry in entries { entriesByID[entry.id] = entry }
            }

            for record in snapshot.sessions {
                let stops = record.stops.map { stop in
                    WayTaskSchemaV4.ShoppingSessionStop(
                        id: stop.id,
                        sessionID: stop.sessionID,
                        snapshotID: stop.snapshotID,
                        sortOrder: stop.sortOrder,
                        storeReferenceIDRawValue:
                            stop.storeReferenceIDRawValue,
                        storeReferenceProvenanceRawValue:
                            stop.storeReferenceProvenanceRawValue,
                        displayNameSnapshot: stop.displayNameSnapshot,
                        latitudeSnapshot: stop.latitudeSnapshot,
                        longitudeSnapshot: stop.longitudeSnapshot,
                        evidenceAt: stop.evidenceAt,
                        isSessionScopedTransient:
                            stop.isSessionScopedTransient
                    )
                }
                let stopsByID = Dictionary(
                    uniqueKeysWithValues: stops.map { ($0.id, $0) }
                )
                let lines = record.lines.map { line in
                    WayTaskSchemaV4.ShoppingSessionLine(
                        id: line.id,
                        sessionID: line.sessionID,
                        snapshotID: line.snapshotID,
                        snapshotVersion: line.snapshotVersion,
                        snapshotProvenanceRawValue:
                            line.snapshotProvenanceRawValue,
                        sourceListID: line.sourceListID,
                        sourceEntryID: line.sourceEntryID,
                        productID: line.productID,
                        globalProductConceptIDRawValue:
                            line.globalProductConceptIDRawValue,
                        stopID: line.stopID,
                        sortOrder: line.sortOrder,
                        productNameSnapshot: line.productNameSnapshot,
                        productBrandSnapshot: line.productBrandSnapshot,
                        productCategorySnapshot:
                            line.productCategorySnapshot,
                        quantitySnapshot: line.quantitySnapshot,
                        unitSnapshotRawValue: line.unitSnapshotRawValue,
                        noteSnapshot: line.noteSnapshot,
                        executionStateRawValue:
                            line.executionStateRawValue,
                        executionChangedAt: line.executionChangedAt,
                        finalOutcomeRawValue: line.finalOutcomeRawValue,
                        finalOutcomeAt: line.finalOutcomeAt,
                        finalOutcomeCommandID: line.finalOutcomeCommandID,
                        legacyDispositionRawValue:
                            line.legacyDispositionRawValue,
                        sourceEntry: line.sourceEntryID.flatMap {
                            entriesByID[$0]
                        },
                        product: line.productID.flatMap { productsByID[$0] },
                        stop: line.stopID.flatMap { stopsByID[$0] }
                    )
                }
                let exceptions = record.exceptions.map {
                    makeException($0)
                }
                let session = WayTaskSchemaV4.ShoppingSession(
                    id: record.id,
                    sourceListID: record.sourceListID,
                    sourceRevision: record.sourceRevision,
                    sourceRevisionProvenanceRawValue:
                        record.sourceRevisionProvenanceRawValue,
                    revision: record.revision,
                    lifecycleRawValue: record.lifecycleRawValue,
                    migrationConditionRawValue:
                        record.migrationConditionRawValue,
                    snapshotID: record.snapshotID,
                    snapshotVersion: record.snapshotVersion,
                    snapshotGeneration: record.snapshotGeneration,
                    snapshotContentSignature:
                        record.snapshotContentSignature,
                    sourcePlanID: record.sourcePlanID,
                    sourcePlanSignature: record.sourcePlanSignature,
                    sourcePlanEvidenceAt: record.sourcePlanEvidenceAt,
                    startedAt: record.startedAt,
                    activationStartedAt: record.activationStartedAt,
                    lastActivityAt: record.lastActivityAt,
                    expiredAt: record.expiredAt,
                    endedAt: record.endedAt,
                    expirationReasonRawValue:
                        record.expirationReasonRawValue,
                    expirationPolicyVersion:
                        record.expirationPolicyVersion,
                    sourceList: record.sourceListID.flatMap { listsByID[$0] },
                    lines: lines,
                    stops: stops,
                    migrationExceptions: exceptions
                )
                context.insert(session)
            }
            for record in snapshot.globalExceptions {
                context.insert(makeException(record))
            }
            try context.save()
        }
    }

    static func reopenTargetStore(
        storeURL: URL
    ) throws -> WayTaskSessionHistoryArchiveSemanticSnapshot {
        let completeProductList = try WayTaskProductListSemanticStoreBoundary
            .reopenTargetStore(storeURL: storeURL)
        let archiveKinds = Set([
            ShoppingListKind.completed.rawValue,
            ShoppingListKind.recent.rawValue
        ])
        let archiveListIDs = Set(
            completeProductList.lists.filter {
                guard let purpose = $0.purposeRawValue else { return false }
                return archiveKinds.contains(purpose)
            }.map(\.id)
        )
        let productListBase = WayTaskProductListSemanticSnapshot(
            products: completeProductList.products,
            lists: completeProductList.lists.filter {
                !archiveListIDs.contains($0.id)
            },
            entries: completeProductList.entries.filter {
                !archiveListIDs.contains($0.shoppingListID)
            }
        )
        let archiveLists = completeProductList.lists.filter {
            archiveListIDs.contains($0.id)
        }
        let archiveEntries = completeProductList.entries.filter {
            archiveListIDs.contains($0.shoppingListID)
        }
        let evidenceURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(
                WayTaskProductStateMigration.sessionExceptionEvidenceFilename
            )
        let evidenceArtifact = try JSONDecoder().decode(
            WayTaskSessionExceptionEvidenceArtifact.self,
            from: Data(contentsOf: evidenceURL, options: [.mappedIfSafe])
        )
        guard evidenceArtifact.formatVersion == 1,
              Set(evidenceArtifact.records.map(\.id)).count ==
                evidenceArtifact.records.count
        else { throw StoreError.invalidExceptionEvidence }
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: evidenceArtifact.records.map { ($0.id, $0) }
        )

        return try autoreleasepool {
            let schema = Schema(versionedSchema: WayTaskSchemaV4.self)
            let configuration = ModelConfiguration(
                "WT033A-T08-Inactive-V4-Reopen",
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
            var histories = try context.fetch(
                FetchDescriptor<ProductHistory>()
            ).map { history in
                WayTaskLegacyHistoryAggregateRecord(
                    id: history.id,
                    productKey: history.productKey,
                    productName: history.productName,
                    barcode: history.barcode,
                    firstAddedDate: history.firstAddedDate,
                    lastAddedDate: history.lastAddedDate,
                    addCount: history.addCount,
                    lastSourceRawValue: history.lastSourceRawValue,
                    averageInterval: history.averageInterval,
                    lastCompletedDate: history.lastCompletedDate
                )
            }
            var items = try context.fetch(
                FetchDescriptor<ShoppingItem>()
            ).map { item in
                WayTaskLegacyCompatibilityEvidenceRecord(
                    id: item.id,
                    name: item.name,
                    isCompleted: item.isCompleted,
                    imageData: item.imageData,
                    brand: item.brand,
                    category: item.category,
                    barcode: item.barcode,
                    imageURLString: item.imageURLString,
                    dateAdded: item.dateAdded,
                    sourceRawValue: item.sourceRawValue,
                    productType: item.productType,
                    flavor: item.flavor,
                    packageSize: item.packageSize,
                    packageType: item.packageType,
                    visibleText: item.visibleText,
                    searchKeywordsRawValue: item.searchKeywordsRawValue
                )
            }
            var locations = try context.fetch(
                FetchDescriptor<GeoLocation>()
            ).map { location in
                WayTaskLegacySavedLocationRecord(
                    id: location.id,
                    title: location.title,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    radius: location.radius,
                    storeCategoryRawValue:
                        location.storeCategoryRawValue,
                    addressText: location.addressText,
                    notes: location.notes,
                    sourceTypeRawValue: location.sourceTypeRawValue,
                    shoppingItemIDs: location.shoppingItems.map(\.id)
                        .sorted(by: uuidLess)
                )
            }
            let historyEvents = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
            ).map(\.id).sorted(by: uuidLess)
            var sessions = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
            ).map { session in
                let lines = session.lines.map { line in
                    WayTaskMigratedSessionLineRecord(
                        id: line.id,
                        sessionID: line.sessionID,
                        snapshotID: line.snapshotID,
                        snapshotVersion: line.snapshotVersion,
                        snapshotProvenanceRawValue:
                            line.snapshotProvenanceRawValue,
                        sourceListID: line.sourceListID,
                        sourceEntryID: line.sourceEntryID,
                        productID: line.productID,
                        globalProductConceptIDRawValue:
                            line.globalProductConceptIDRawValue,
                        stopID: line.stopID,
                        sortOrder: line.sortOrder,
                        productNameSnapshot: line.productNameSnapshot,
                        productBrandSnapshot: line.productBrandSnapshot,
                        productCategorySnapshot:
                            line.productCategorySnapshot,
                        quantitySnapshot: line.quantitySnapshot,
                        unitSnapshotRawValue: line.unitSnapshotRawValue,
                        noteSnapshot: line.noteSnapshot,
                        executionStateRawValue:
                            line.executionStateRawValue,
                        executionChangedAt: line.executionChangedAt,
                        finalOutcomeRawValue: line.finalOutcomeRawValue,
                        finalOutcomeAt: line.finalOutcomeAt,
                        finalOutcomeCommandID: line.finalOutcomeCommandID,
                        legacyDispositionRawValue:
                            line.legacyDispositionRawValue
                    )
                }.sorted(by: lineLess)
                let stops = session.stops.map { stop in
                    WayTaskMigratedSessionStopRecord(
                        id: stop.id,
                        sessionID: stop.sessionID,
                        snapshotID: stop.snapshotID,
                        sortOrder: stop.sortOrder,
                        storeReferenceIDRawValue:
                            stop.storeReferenceIDRawValue,
                        storeReferenceProvenanceRawValue:
                            stop.storeReferenceProvenanceRawValue,
                        displayNameSnapshot: stop.displayNameSnapshot,
                        latitudeSnapshot: stop.latitudeSnapshot,
                        longitudeSnapshot: stop.longitudeSnapshot,
                        evidenceAt: stop.evidenceAt,
                        isSessionScopedTransient:
                            stop.isSessionScopedTransient
                    )
                }.sorted(by: stopLess)
                let exceptions = session.migrationExceptions.map {
                    projectException($0, evidenceByID: evidenceByID)
                }.sorted { $0.ordinal < $1.ordinal }
                return WayTaskMigratedSessionRecord(
                    id: session.id,
                    sourceListID: session.sourceListID,
                    sourceRevision: session.sourceRevision,
                    sourceRevisionProvenanceRawValue:
                        session.sourceRevisionProvenanceRawValue,
                    revision: session.revision,
                    lifecycleRawValue: session.lifecycleRawValue,
                    migrationConditionRawValue:
                        session.migrationConditionRawValue,
                    snapshotID: session.snapshotID,
                    snapshotVersion: session.snapshotVersion,
                    snapshotGeneration: session.snapshotGeneration,
                    snapshotContentSignature:
                        session.snapshotContentSignature,
                    sourcePlanID: session.sourcePlanID,
                    sourcePlanSignature: session.sourcePlanSignature,
                    sourcePlanEvidenceAt: session.sourcePlanEvidenceAt,
                    startedAt: session.startedAt,
                    activationStartedAt: session.activationStartedAt,
                    lastActivityAt: session.lastActivityAt,
                    expiredAt: session.expiredAt,
                    endedAt: session.endedAt,
                    expirationReasonRawValue:
                        session.expirationReasonRawValue,
                    expirationPolicyVersion:
                        session.expirationPolicyVersion,
                    lines: lines,
                    stops: stops,
                    exceptions: exceptions
                )
            }
            var globalExceptions = try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.ProductStateMigrationException>()
            ).filter { $0.sessionID == nil }.map {
                projectException($0, evidenceByID: evidenceByID)
            }.sorted {
                if $0.categoryRawValue != $1.categoryRawValue {
                    return $0.categoryRawValue < $1.categoryRawValue
                }
                return $0.safeEvidenceDigest < $1.safeEvidenceDigest
            }
            histories.sort { uuidLess($0.id, $1.id) }
            items.sort { uuidLess($0.id, $1.id) }
            locations.sort { uuidLess($0.id, $1.id) }
            sessions.sort { uuidLess($0.id, $1.id) }
            globalExceptions.sort { $0.ordinal < $1.ordinal }
            return WayTaskSessionHistoryArchiveSemanticSnapshot(
                productListBase: productListBase,
                sessions: sessions,
                historyAggregates: histories,
                historyEvents: historyEvents,
                archiveLists: archiveLists,
                archiveEntries: archiveEntries,
                compatibilityItems: items,
                savedLocations: locations,
                globalExceptions: globalExceptions
            )
        }
    }

    private static func makeException(
        _ record: WayTaskMigratedSessionExceptionRecord
    ) -> WayTaskSchemaV4.ProductStateMigrationException {
        WayTaskSchemaV4.ProductStateMigrationException(
            id: record.id,
            sessionID: record.sessionID,
            sessionLineID: record.sessionLineID,
            categoryRawValue: record.categoryRawValue,
            safeEvidenceDigest: record.safeEvidenceDigest,
            ordinal: record.ordinal,
            occurrenceCount: record.occurrenceCount,
            recordedAt: record.recordedAt
        )
    }

    private static func projectException(
        _ exception: WayTaskSchemaV4.ProductStateMigrationException,
        evidenceByID: [UUID: WayTaskMigratedSessionExceptionRecord]
    ) -> WayTaskMigratedSessionExceptionRecord {
        let evidence = evidenceByID[exception.id]
        return WayTaskMigratedSessionExceptionRecord(
            id: exception.id,
            sessionID: exception.sessionID,
            sessionLineID: exception.sessionLineID,
            categoryRawValue: exception.categoryRawValue,
            safeEvidenceDigest: exception.safeEvidenceDigest,
            ordinal: exception.ordinal,
            occurrenceCount: exception.occurrenceCount,
            recordedAt: exception.recordedAt,
            sourceCollectionRawValue: evidence?.sourceCollectionRawValue,
            sourceOrdinals: evidence?.sourceOrdinals ?? [],
            sourceByteLength: evidence?.sourceByteLength,
            normalizedTokenID: evidence?.normalizedTokenID
        )
    }

    nonisolated private static func uuidLess(
        _ lhs: UUID,
        _ rhs: UUID
    ) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    nonisolated private static func lineLess(
        _ lhs: WayTaskMigratedSessionLineRecord,
        _ rhs: WayTaskMigratedSessionLineRecord
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return uuidLess(lhs.id, rhs.id)
    }

    nonisolated private static func stopLess(
        _ lhs: WayTaskMigratedSessionStopRecord,
        _ rhs: WayTaskMigratedSessionStopRecord
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return uuidLess(lhs.id, rhs.id)
    }

    private enum StoreError: Error {
        case targetAlreadyContainsT08Data
        case invalidExceptionEvidence
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
