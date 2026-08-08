import CryptoKit
import Foundation
import SwiftData

enum GuestMigrationState: String, Codable, Equatable, Sendable {
    case guestLocal
    case authenticatedLocalUnlinked
    case migrationPreviewAvailable
    case migrationConsentRequired
    case migrationPreparing
    case migrationUploading
    case migrationVerifying
    case migrationInterrupted
    case migrationRecoverable
    case migrationCompleted
    case migrationConflict
    case migrationRollbackRequired
    case migrationBlocked
}

enum GuestMigrationEntityKind: String, Codable, CaseIterable, Sendable {
    case personalProducts = "personal_products"
    case shoppingLists = "shopping_lists"
    case shoppingListEntries = "shopping_list_entries"

    var dependencyRank: Int {
        switch self {
        case .personalProducts: 0
        case .shoppingLists: 1
        case .shoppingListEntries: 2
        }
    }
}

enum GuestMigrationExcludedCategory: String, Codable, CaseIterable, Sendable {
    case productImages = "product_images_and_remote_image_urls"
    case recognitionPayloads = "recognition_payloads"
    case shoppingSessionsAndHistory = "shopping_sessions_and_history"
    case preciseLocationsAndSavedStores = "precise_locations_and_saved_stores"
    case notificationAndGeofenceState = "notification_and_geofence_state"
    case legacyProductKnowledge = "legacy_product_knowledge"
    case legacyAndImportedRecords = "legacy_and_unsupported_records"
    case serverDerivedData = "server_derived_and_rebuildable_data"
    case catalogDisplaySnapshots = "catalog_display_snapshots"
}

struct GuestMigrationCounts: Codable, Equatable, Sendable {
    let personalProducts: Int
    let shoppingLists: Int
    let shoppingListEntries: Int

    var total: Int { personalProducts + shoppingLists + shoppingListEntries }

    enum CodingKeys: String, CodingKey {
        case personalProducts = "personal_products"
        case shoppingLists = "shopping_lists"
        case shoppingListEntries = "shopping_list_entries"
    }
}

struct GuestMigrationProduct: Codable, Equatable, Sendable {
    let id: UUID
    let revision: UInt64
    let displayName: String
    let brand: String?
    let category: String?
    let barcode: String?
    let source: String
    let catalogProductID: String?
    let libraryLifecycle: String
    let removedAtMilliseconds: Int64?
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case id, revision, brand, category, barcode, source
        case displayName = "display_name"
        case catalogProductID = "catalog_product_id"
        case libraryLifecycle = "library_lifecycle"
        case removedAtMilliseconds = "removed_at_milliseconds"
        case createdAtMilliseconds = "created_at_milliseconds"
        case updatedAtMilliseconds = "updated_at_milliseconds"
    }
}

struct GuestMigrationList: Codable, Equatable, Sendable {
    let id: UUID
    let revision: UInt64
    let title: String
    let purpose: String
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case id, revision, title, purpose
        case createdAtMilliseconds = "created_at_milliseconds"
        case updatedAtMilliseconds = "updated_at_milliseconds"
    }
}

struct GuestMigrationEntry: Codable, Equatable, Sendable {
    let id: UUID
    let shoppingListID: UUID
    let personalProductID: UUID
    let quantity: Double
    let unit: String?
    let note: String?
    let lifecycle: String
    let resolutionReason: String?
    let resolutionEffectiveAtMilliseconds: Int64?
    let resolutionProvenance: String?
    let resolutionCommandID: UUID?
    let sortOrder: Double
    let revision: UInt64
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case id, quantity, unit, note, lifecycle, revision
        case shoppingListID = "shopping_list_id"
        case personalProductID = "personal_product_id"
        case resolutionReason = "resolution_reason"
        case resolutionEffectiveAtMilliseconds =
            "resolution_effective_at_milliseconds"
        case resolutionProvenance = "resolution_provenance"
        case resolutionCommandID = "resolution_command_id"
        case sortOrder = "sort_order"
        case createdAtMilliseconds = "created_at_milliseconds"
        case updatedAtMilliseconds = "updated_at_milliseconds"
    }
}

struct GuestMigrationCanonicalDataset: Codable, Equatable, Sendable {
    static let formatVersion = 1
    static let productStateSchemaVersion = "4.0.0"

    let migrationFormatVersion: Int
    let productStateSchemaVersion: String
    let targetUserID: UUID
    let localDataSetID: UUID
    let counts: GuestMigrationCounts
    let includedCategories: [String]
    let excludedCategories: [GuestMigrationExcludedCategory]
    let personalProducts: [GuestMigrationProduct]
    let shoppingLists: [GuestMigrationList]
    let shoppingListEntries: [GuestMigrationEntry]

    enum CodingKeys: String, CodingKey {
        case migrationFormatVersion = "migration_format_version"
        case productStateSchemaVersion = "product_state_schema_version"
        case targetUserID = "target_user_id"
        case localDataSetID = "local_dataset_id"
        case counts
        case includedCategories = "included_categories"
        case excludedCategories = "excluded_categories"
        case personalProducts = "personal_products"
        case shoppingLists = "shopping_lists"
        case shoppingListEntries = "shopping_list_entries"
    }
}

struct GuestMigrationBatchPlan: Codable, Equatable, Sendable {
    let sequence: Int
    let entityKind: GuestMigrationEntityKind
    let recordCount: Int
    let payloadByteCount: Int
    let payloadSHA256: String

    enum CodingKeys: String, CodingKey {
        case sequence
        case entityKind = "entity_kind"
        case recordCount = "record_count"
        case payloadByteCount = "payload_byte_count"
        case payloadSHA256 = "payload_sha256"
    }
}

struct GuestMigrationManifest: Codable, Equatable, Sendable {
    let dataset: GuestMigrationCanonicalDataset
    let datasetFingerprint: String
    let batches: [GuestMigrationBatchPlan]

    enum CodingKeys: String, CodingKey {
        case dataset
        case datasetFingerprint = "dataset_fingerprint"
        case batches
    }
}

struct GuestMigrationExecution: Codable, Equatable, Sendable {
    let attemptID: UUID
    let targetUserID: UUID
    let datasetFingerprint: String
    let consentedFingerprint: String?
    let acknowledgedBatchIDs: [String]
    let retryCount: Int
    let state: GuestMigrationState
}

enum GuestMigrationFoundationError: Error, Equatable, Sendable {
    case notAuthenticated
    case accountConflict
    case invalidLocalDataset
    case unsupportedLocalValue
    case previewChanged
    case consentRequired
    case activationBlocked(GuestMigrationActivationBlocker)
    case batchOrderViolation
    case oversizedBatch
    case receiptMismatch
    case verificationFailed
    case localPersistenceFailure
    case offline
    case sessionExpired
    case serviceUnavailable

    var userMessage: String {
        switch self {
        case .notAuthenticated, .sessionExpired:
            "Sign in again. Your data remains on this device."
        case .accountConflict:
            "This device dataset is already reserved for another account."
        case .previewChanged:
            "Your local data changed. Review a new preview before continuing."
        case .consentRequired:
            "Review and confirm the migration before it can start."
        case .offline:
            "Migration is paused while offline. Your local data is unchanged."
        case .serviceUnavailable:
            "Migration is temporarily unavailable. You can safely try again."
        case .activationBlocked:
            "Migration is not enabled for this build."
        default:
            "Migration stopped safely. Your local data is unchanged."
        }
    }
}

enum GuestMigrationActivationBlocker: String, Codable, Equatable, Sendable {
    case notStaging
    case productionDenied
    case notAuthenticated
    case featureDisabled
    case unsupportedSchema
    case endpointUnavailable
    case signedSessionIsolationUnproven
    case sessionRecoveryUnproven
    case unresolvedSecurityBlocker
}

struct GuestMigrationActivationEvidence: Equatable, Sendable {
    static let approvedSchemaVersion = 1

    let environment: WayTaskCloudEnvironment?
    let compiledForInternalStaging: Bool
    let authenticatedUserID: UUID?
    let migrationFeatureEnabled: Bool
    let schemaVersion: Int
    let endpointConfigured: Bool
    let signedSessionABGatePassed: Bool
    let sessionRecoveryGatePassed: Bool
    let securityBlockersClear: Bool

    func blocker() -> GuestMigrationActivationBlocker? {
        if environment == .production { return .productionDenied }
        guard environment == .staging, compiledForInternalStaging else {
            return .notStaging
        }
        guard authenticatedUserID != nil else { return .notAuthenticated }
        guard migrationFeatureEnabled else { return .featureDisabled }
        guard schemaVersion == Self.approvedSchemaVersion else {
            return .unsupportedSchema
        }
        guard endpointConfigured else { return .endpointUnavailable }
        guard signedSessionABGatePassed else {
            return .signedSessionIsolationUnproven
        }
        guard sessionRecoveryGatePassed else {
            return .sessionRecoveryUnproven
        }
        guard securityBlockersClear else { return .unresolvedSecurityBlocker }
        return nil
    }
}

enum GuestMigrationCanonicalizer {
    static func data<T: Encodable>(for value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(for: value))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func batchID(
        attemptID: UUID,
        batch: GuestMigrationBatchPlan
    ) -> String {
        let source = [
            attemptID.uuidString.lowercased(),
            String(batch.sequence),
            batch.entityKind.rawValue,
            batch.payloadSHA256
        ].joined(separator: "|")
        return SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
struct GuestMigrationManifestBuilder {
    private let validator = WayTaskCloudFieldValidator()

    func build(
        modelContainer: ModelContainer,
        localDataSetID: UUID,
        targetUserID: UUID
    ) throws -> GuestMigrationManifest {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let products = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.Product>()
        )
        let allLists = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
        )
        let allEntries = try context.fetch(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
        )

        let lists = allLists.filter { list in
            !["recent", "completed", "deleted"].contains(
                list.purposeRawValue
            )
        }
        let listIDs = Set(lists.map(\.id))
        let entries = allEntries.filter { listIDs.contains($0.shoppingListID) }
        let productIDs = Set(products.map(\.id))

        guard Set(products.map(\.id)).count == products.count,
              Set(lists.map(\.id)).count == lists.count,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ productIDs.contains($0.productID) })
        else { throw GuestMigrationFoundationError.invalidLocalDataset }

        let productRecords = try products.map(product).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let listRecords = try lists.map(list).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let entryRecords = try entries.map(entry).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let counts = GuestMigrationCounts(
            personalProducts: productRecords.count,
            shoppingLists: listRecords.count,
            shoppingListEntries: entryRecords.count
        )
        let dataset = GuestMigrationCanonicalDataset(
            migrationFormatVersion:
                GuestMigrationCanonicalDataset.formatVersion,
            productStateSchemaVersion:
                GuestMigrationCanonicalDataset.productStateSchemaVersion,
            targetUserID: targetUserID,
            localDataSetID: localDataSetID,
            counts: counts,
            includedCategories: GuestMigrationEntityKind.allCases
                .map(\.rawValue),
            excludedCategories: GuestMigrationExcludedCategory.allCases,
            personalProducts: productRecords,
            shoppingLists: listRecords,
            shoppingListEntries: entryRecords
        )
        return GuestMigrationManifest(
            dataset: dataset,
            datasetFingerprint: try GuestMigrationCanonicalizer.sha256(dataset),
            batches: try makeBatches(
                products: productRecords,
                lists: listRecords,
                entries: entryRecords
            )
        )
    }

    private func product(
        _ value: WayTaskSchemaV4.Product
    ) throws -> GuestMigrationProduct {
        let name = canonicalText(value.name)
        try validator.validateProductDisplayName(name)
        try validateOptionalText(value.brand, maximum: 160)
        try validateOptionalText(value.category, maximum: 160)
        try validator.validateBarcode(value.barcode)
        guard ProductSource(rawValue: value.sourceRawValue) != nil,
              ProductLibraryLifecycle(rawValue:
                value.libraryLifecycleRawValue) != nil,
              value.revision > 0,
              value.updatedAt >= value.createdAt,
              (value.libraryLifecycleRawValue == "removed") ==
                (value.libraryRemovedAt != nil)
        else { throw GuestMigrationFoundationError.unsupportedLocalValue }
        try validateCatalogID(value.catalogProductIDRawValue)
        return GuestMigrationProduct(
            id: value.id,
            revision: value.revision,
            displayName: name,
            brand: canonicalOptionalText(value.brand),
            category: canonicalOptionalText(value.category),
            barcode: value.barcode,
            source: value.sourceRawValue,
            catalogProductID: value.catalogProductIDRawValue,
            libraryLifecycle: value.libraryLifecycleRawValue,
            removedAtMilliseconds: milliseconds(value.libraryRemovedAt),
            createdAtMilliseconds: milliseconds(value.createdAt),
            updatedAtMilliseconds: milliseconds(value.updatedAt)
        )
    }

    private func list(
        _ value: WayTaskSchemaV4.ShoppingList
    ) throws -> GuestMigrationList {
        let title = canonicalText(value.title)
        try validator.validateListName(title)
        guard value.revision > 0, value.updatedAt >= value.createdAt else {
            throw GuestMigrationFoundationError.unsupportedLocalValue
        }
        let purpose: String
        switch value.purposeRawValue {
        case nil, "shopping": purpose = "shopping"
        case "weekly": purpose = "weekly"
        default: purpose = "custom"
        }
        return GuestMigrationList(
            id: value.id,
            revision: value.revision,
            title: title,
            purpose: purpose,
            createdAtMilliseconds: milliseconds(value.createdAt),
            updatedAtMilliseconds: milliseconds(value.updatedAt)
        )
    }

    private func entry(
        _ value: WayTaskSchemaV4.ShoppingListEntry
    ) throws -> GuestMigrationEntry {
        try validator.validateQuantity(value.quantity)
        try validator.validateNote(value.note)
        guard value.sortOrder.isFinite,
              (-1_000_000_000...1_000_000_000).contains(value.sortOrder),
              value.updatedAt >= value.createdAt,
              ["needed", "resolved"].contains(value.lifecycleRawValue),
              value.unitRawValue.map({
                  ["count", "kg", "g", "l", "ml", "package"].contains($0)
              }) ?? true
        else { throw GuestMigrationFoundationError.unsupportedLocalValue }

        let reason = try resolutionReason(value.resolutionReasonRawValue)
        let provenance = try resolutionProvenance(
            value.resolutionProvenanceRawValue
        )
        if value.lifecycleRawValue == "needed" {
            guard reason == nil,
                  value.resolutionEffectiveAt == nil,
                  provenance == nil,
                  value.resolutionCommandID == nil,
                  value.resolutionSessionID == nil,
                  value.resolutionSessionLineID == nil
            else { throw GuestMigrationFoundationError.invalidLocalDataset }
        } else if reason == nil || value.resolutionEffectiveAt == nil ||
                    provenance == nil {
            throw GuestMigrationFoundationError.invalidLocalDataset
        }
        return GuestMigrationEntry(
            id: value.id,
            shoppingListID: value.shoppingListID,
            personalProductID: value.productID,
            quantity: value.quantity,
            unit: value.unitRawValue,
            note: canonicalOptionalText(value.note),
            lifecycle: value.lifecycleRawValue,
            resolutionReason: reason,
            resolutionEffectiveAtMilliseconds:
                milliseconds(value.resolutionEffectiveAt),
            resolutionProvenance: provenance,
            resolutionCommandID: value.resolutionCommandID,
            sortOrder: value.sortOrder,
            revision: 1,
            createdAtMilliseconds: milliseconds(value.createdAt),
            updatedAtMilliseconds: milliseconds(value.updatedAt)
        )
    }

    private func makeBatches(
        products: [GuestMigrationProduct],
        lists: [GuestMigrationList],
        entries: [GuestMigrationEntry]
    ) throws -> [GuestMigrationBatchPlan] {
        var result: [GuestMigrationBatchPlan] = []
        var sequence = 0
        try appendBatches(
            records: products,
            kind: .personalProducts,
            sequence: &sequence,
            result: &result
        )
        try appendBatches(
            records: lists,
            kind: .shoppingLists,
            sequence: &sequence,
            result: &result
        )
        try appendBatches(
            records: entries,
            kind: .shoppingListEntries,
            sequence: &sequence,
            result: &result
        )
        return result
    }

    private func appendBatches<T: Encodable>(
        records: [T],
        kind: GuestMigrationEntityKind,
        sequence: inout Int,
        result: inout [GuestMigrationBatchPlan]
    ) throws {
        for chunk in records.chunked(maximumCount: 100) {
            let payload = try GuestMigrationCanonicalizer.data(for: chunk)
            try validator.validateBatch(
                recordCount: chunk.count,
                payloadBytes: payload.count
            )
            result.append(
                GuestMigrationBatchPlan(
                    sequence: sequence,
                    entityKind: kind,
                    recordCount: chunk.count,
                    payloadByteCount: payload.count,
                    payloadSHA256: SHA256.hash(data: payload)
                        .map { String(format: "%02x", $0) }
                        .joined()
                )
            )
            sequence += 1
        }
    }

    private func resolutionReason(_ value: String?) throws -> String? {
        switch value {
        case nil: return nil
        case "purchased": return "purchased"
        case "alreadyHave": return "already_have"
        case "noLongerNeeded": return "no_longer_needed"
        case "legacyUnknown": return "legacy_unknown"
        default: throw GuestMigrationFoundationError.unsupportedLocalValue
        }
    }

    private func resolutionProvenance(_ value: String?) throws -> String? {
        switch value {
        case nil: return nil
        case "userCommand": return "user_command"
        case "sessionFinish": return "session_finish"
        case "legacyMigration": return "legacy_migration"
        default: throw GuestMigrationFoundationError.unsupportedLocalValue
        }
    }

    private func validateOptionalText(
        _ value: String?,
        maximum: Int
    ) throws {
        guard let value else { return }
        let normalized = canonicalText(value)
        guard !normalized.isEmpty, normalized.count <= maximum else {
            throw GuestMigrationFoundationError.unsupportedLocalValue
        }
        try validator.validateDescription(normalized)
    }

    private func validateCatalogID(_ value: String?) throws {
        guard let value else { return }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"
        )
        guard (1...128).contains(value.count),
              value.unicodeScalars.allSatisfy(allowed.contains),
              value.first?.isLetter == true || value.first?.isNumber == true
        else { throw GuestMigrationFoundationError.unsupportedLocalValue }
    }

    private func canonicalText(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
    }

    private func canonicalOptionalText(_ value: String?) -> String? {
        value.map(canonicalText)
    }

    private func milliseconds(_ value: Date) -> Int64 {
        Int64((value.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private func milliseconds(_ value: Date?) -> Int64? {
        value.map(milliseconds)
    }

}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: maximumCount).map { start in
            Array(self[start..<Swift.min(start + maximumCount, count)])
        }
    }
}
