import Foundation
import SwiftData

@Model
final class ShoppingSession {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var isActive: Bool
    var itemIDListRawValue: String
    var collectedItemIDListRawValue: String
    var shoppingListID: UUID?
    var selectedStoreID: UUID?
    var selectedStoreName: String?
    var selectedStoreLatitude: Double?
    var selectedStoreLongitude: Double?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        isActive: Bool = true,
        itemIDs: [UUID] = [],
        collectedItemIDs: [UUID] = [],
        shoppingListID: UUID? = nil,
        selectedStoreID: UUID? = nil,
        selectedStoreName: String? = nil,
        selectedStoreLatitude: Double? = nil,
        selectedStoreLongitude: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isActive = isActive
        self.itemIDListRawValue = Self.encode(itemIDs)
        self.collectedItemIDListRawValue = Self.encode(collectedItemIDs)
        self.shoppingListID = shoppingListID
        self.selectedStoreID = selectedStoreID
        self.selectedStoreName = selectedStoreName
        self.selectedStoreLatitude = selectedStoreLatitude
        self.selectedStoreLongitude = selectedStoreLongitude
    }

    var itemIDs: [UUID] {
        get { Self.decode(itemIDListRawValue) }
        set { itemIDListRawValue = Self.encode(newValue) }
    }

    var collectedItemIDs: [UUID] {
        get { Self.decode(collectedItemIDListRawValue) }
        set { collectedItemIDListRawValue = Self.encode(newValue) }
    }

    var remainingItemCount: Int {
        max(itemIDs.count - collectedItemIDs.count, 0)
    }

    func containsItem(_ item: ShoppingItem) -> Bool {
        itemIDs.contains(item.id)
    }

    func isCollected(_ item: ShoppingItem) -> Bool {
        collectedItemIDs.contains(item.id)
    }

    private static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    private static func decode(_ rawValue: String) -> [UUID] {
        rawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
}

// MARK: - Inactive target Shopping Session persistence models

extension WayTaskSchemaV4 {
    @Model
    final class ShoppingSession {
        var id: UUID
        var sourceListID: UUID
        var sourceRevision: UInt64?
        var sourceRevisionProvenanceRawValue: String
        var revision: UInt64
        var lifecycleRawValue: String
        var migrationConditionRawValue: String
        var snapshotID: UUID
        var snapshotVersion: Int
        var snapshotGeneration: Int
        var snapshotContentSignature: String
        var sourcePlanID: UUID?
        var sourcePlanSignature: String?
        var sourcePlanEvidenceAt: Date?
        var startedAt: Date
        var activationStartedAt: Date
        var lastActivityAt: Date
        var expiredAt: Date?
        var endedAt: Date?
        var expirationReasonRawValue: String?
        var expirationPolicyVersion: Int

        @Relationship(deleteRule: .nullify)
        var sourceList: WayTaskSchemaV4.ShoppingList?

        @Relationship(deleteRule: .cascade)
        var lines: [ShoppingSessionLine]

        @Relationship(deleteRule: .cascade)
        var stops: [ShoppingSessionStop]

        @Relationship(deleteRule: .cascade)
        var migrationExceptions: [ProductStateMigrationException]

        init(
            id: UUID,
            sourceListID: UUID,
            sourceRevision: UInt64?,
            sourceRevisionProvenanceRawValue: String,
            revision: UInt64,
            lifecycleRawValue: String,
            migrationConditionRawValue: String,
            snapshotID: UUID,
            snapshotVersion: Int,
            snapshotGeneration: Int,
            snapshotContentSignature: String,
            sourcePlanID: UUID? = nil,
            sourcePlanSignature: String? = nil,
            sourcePlanEvidenceAt: Date? = nil,
            startedAt: Date,
            activationStartedAt: Date,
            lastActivityAt: Date,
            expiredAt: Date? = nil,
            endedAt: Date? = nil,
            expirationReasonRawValue: String? = nil,
            expirationPolicyVersion: Int,
            sourceList: WayTaskSchemaV4.ShoppingList? = nil,
            lines: [ShoppingSessionLine] = [],
            stops: [ShoppingSessionStop] = [],
            migrationExceptions: [ProductStateMigrationException] = []
        ) {
            self.id = id
            self.sourceListID = sourceListID
            self.sourceRevision = sourceRevision
            self.sourceRevisionProvenanceRawValue =
                sourceRevisionProvenanceRawValue
            self.revision = revision
            self.lifecycleRawValue = lifecycleRawValue
            self.migrationConditionRawValue = migrationConditionRawValue
            self.snapshotID = snapshotID
            self.snapshotVersion = snapshotVersion
            self.snapshotGeneration = snapshotGeneration
            self.snapshotContentSignature = snapshotContentSignature
            self.sourcePlanID = sourcePlanID
            self.sourcePlanSignature = sourcePlanSignature
            self.sourcePlanEvidenceAt = sourcePlanEvidenceAt
            self.startedAt = startedAt
            self.activationStartedAt = activationStartedAt
            self.lastActivityAt = lastActivityAt
            self.expiredAt = expiredAt
            self.endedAt = endedAt
            self.expirationReasonRawValue = expirationReasonRawValue
            self.expirationPolicyVersion = expirationPolicyVersion
            self.sourceList = sourceList
            self.lines = lines
            self.stops = stops
            self.migrationExceptions = migrationExceptions
        }
    }

    @Model
    final class ShoppingSessionLine {
        var id: UUID
        var sessionID: UUID
        var snapshotID: UUID
        var snapshotVersion: Int
        var snapshotProvenanceRawValue: String
        var sourceListID: UUID?
        var sourceEntryID: UUID?
        var productID: UUID?
        var globalProductConceptIDRawValue: String?
        var stopID: UUID?
        var sortOrder: Int
        var productNameSnapshot: String
        var productBrandSnapshot: String?
        var productCategorySnapshot: String?
        var quantitySnapshot: Double
        var unitSnapshotRawValue: String?
        var noteSnapshot: String?
        var executionStateRawValue: String
        var executionChangedAt: Date?
        var finalOutcomeRawValue: String?
        var finalOutcomeAt: Date?
        var finalOutcomeCommandID: UUID?
        var legacyDispositionRawValue: String?

        @Relationship(deleteRule: .nullify)
        var sourceEntry: WayTaskSchemaV4.ShoppingListEntry?

        @Relationship(deleteRule: .nullify)
        var product: WayTaskSchemaV4.Product?

        @Relationship(deleteRule: .nullify)
        var stop: ShoppingSessionStop?

        init(
            id: UUID,
            sessionID: UUID,
            snapshotID: UUID,
            snapshotVersion: Int,
            snapshotProvenanceRawValue: String,
            sourceListID: UUID? = nil,
            sourceEntryID: UUID? = nil,
            productID: UUID? = nil,
            globalProductConceptIDRawValue: String? = nil,
            stopID: UUID? = nil,
            sortOrder: Int,
            productNameSnapshot: String,
            productBrandSnapshot: String? = nil,
            productCategorySnapshot: String? = nil,
            quantitySnapshot: Double,
            unitSnapshotRawValue: String? = nil,
            noteSnapshot: String? = nil,
            executionStateRawValue: String,
            executionChangedAt: Date? = nil,
            finalOutcomeRawValue: String? = nil,
            finalOutcomeAt: Date? = nil,
            finalOutcomeCommandID: UUID? = nil,
            legacyDispositionRawValue: String? = nil,
            sourceEntry: WayTaskSchemaV4.ShoppingListEntry? = nil,
            product: WayTaskSchemaV4.Product? = nil,
            stop: ShoppingSessionStop? = nil
        ) {
            self.id = id
            self.sessionID = sessionID
            self.snapshotID = snapshotID
            self.snapshotVersion = snapshotVersion
            self.snapshotProvenanceRawValue =
                snapshotProvenanceRawValue
            self.sourceListID = sourceListID
            self.sourceEntryID = sourceEntryID
            self.productID = productID
            self.globalProductConceptIDRawValue =
                globalProductConceptIDRawValue
            self.stopID = stopID
            self.sortOrder = sortOrder
            self.productNameSnapshot = productNameSnapshot
            self.productBrandSnapshot = productBrandSnapshot
            self.productCategorySnapshot = productCategorySnapshot
            self.quantitySnapshot = quantitySnapshot
            self.unitSnapshotRawValue = unitSnapshotRawValue
            self.noteSnapshot = noteSnapshot
            self.executionStateRawValue = executionStateRawValue
            self.executionChangedAt = executionChangedAt
            self.finalOutcomeRawValue = finalOutcomeRawValue
            self.finalOutcomeAt = finalOutcomeAt
            self.finalOutcomeCommandID = finalOutcomeCommandID
            self.legacyDispositionRawValue = legacyDispositionRawValue
            self.sourceEntry = sourceEntry
            self.product = product
            self.stop = stop
        }
    }

    @Model
    final class ShoppingSessionStop {
        var id: UUID
        var sessionID: UUID
        var snapshotID: UUID
        var sortOrder: Int
        var storeReferenceIDRawValue: String?
        var storeReferenceProvenanceRawValue: String
        var displayNameSnapshot: String
        var latitudeSnapshot: Double?
        var longitudeSnapshot: Double?
        var evidenceAt: Date?
        var isSessionScopedTransient: Bool

        init(
            id: UUID,
            sessionID: UUID,
            snapshotID: UUID,
            sortOrder: Int,
            storeReferenceIDRawValue: String? = nil,
            storeReferenceProvenanceRawValue: String,
            displayNameSnapshot: String,
            latitudeSnapshot: Double? = nil,
            longitudeSnapshot: Double? = nil,
            evidenceAt: Date? = nil,
            isSessionScopedTransient: Bool
        ) {
            self.id = id
            self.sessionID = sessionID
            self.snapshotID = snapshotID
            self.sortOrder = sortOrder
            self.storeReferenceIDRawValue = storeReferenceIDRawValue
            self.storeReferenceProvenanceRawValue =
                storeReferenceProvenanceRawValue
            self.displayNameSnapshot = displayNameSnapshot
            self.latitudeSnapshot = latitudeSnapshot
            self.longitudeSnapshot = longitudeSnapshot
            self.evidenceAt = evidenceAt
            self.isSessionScopedTransient = isSessionScopedTransient
        }
    }

    @Model
    final class ProductStateMigrationException {
        var id: UUID
        var sessionID: UUID?
        var sessionLineID: UUID?
        var categoryRawValue: String
        var safeEvidenceDigest: String
        var ordinal: Int
        var occurrenceCount: Int
        var recordedAt: Date

        init(
            id: UUID,
            sessionID: UUID? = nil,
            sessionLineID: UUID? = nil,
            categoryRawValue: String,
            safeEvidenceDigest: String,
            ordinal: Int,
            occurrenceCount: Int,
            recordedAt: Date
        ) {
            self.id = id
            self.sessionID = sessionID
            self.sessionLineID = sessionLineID
            self.categoryRawValue = categoryRawValue
            self.safeEvidenceDigest = safeEvidenceDigest
            self.ordinal = ordinal
            self.occurrenceCount = occurrenceCount
            self.recordedAt = recordedAt
        }
    }
}
