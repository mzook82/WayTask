import Foundation

// MARK: - T-12 immutable Product History query vocabulary

enum ProductStateHistoryNamedProvenance:
    String, CaseIterable, Codable, Hashable, Sendable {
    case nativeUserCommand
    case nativeSessionFinish
    case legacyMigration
    case retainedLegacyAggregate
    case unsupported
}

enum ProductStateHistoryEventKind:
    String, CaseIterable, Codable, Hashable, Sendable {
    case needAdded
    case needResolved
    case needReopened
    case listMembershipRemoved
    case productRemovedFromLibrary
    case productRestoredToLibrary
    case sessionOutcome
    case unsupported
}

enum ProductStateHistoryContributionDisposition:
    String, Codable, Hashable, Sendable {
    case included
    case duplicateEventIdentity
    case duplicateCausalReplay
    case unsupportedEvidence
}

enum ProductStateHistoryRetentionPolicy:
    String, Codable, Hashable, Sendable {
    /// D-07: local history has no automatic expiry in v1.0.3. A query window
    /// may bound returned rows, but it never deletes or rewrites retained data.
    case retainAllNoAutomaticExpiryV103
}

enum ProductStateHistoryQueryOrder:
    String, Codable, Hashable, Sendable {
    case oldestFirst
    case newestFirst
}

struct ProductStateHistoryQueryRequest: Equatable, Sendable {
    let productID: ProductStateProductID
    let maximumEventCount: Int
    let order: ProductStateHistoryQueryOrder
}

struct ProductStateHistoryEventProjection: Equatable, Sendable {
    let eventID: ProductStateHistoryEventID
    let productID: ProductStateProductID
    let kind: ProductStateHistoryEventKind
    let meaningRawValue: String
    let resolutionReason: ShoppingListResolutionReason?
    let resolutionReasonRawValue: String?
    let sessionOutcome: ShoppingSessionFinalOutcome?
    let sessionOutcomeRawValue: String?
    let sourceListID: ProductStateListID?
    let sourceEntryID: ProductStateListEntryID?
    let sessionID: ProductStateSessionID?
    let sessionLineID: ProductStateSessionLineID?
    let commandID: ProductStateCommandID?
    let provenance: ProductStateHistoryNamedProvenance
    let provenanceRawValue: String
    let occurredAt: Date
    let displaySnapshotID: UUID?
    let contribution: ProductStateHistoryContributionDisposition
}

struct ProductStateHistoryProvenanceCount:
    Equatable, Codable, Sendable {
    let provenance: ProductStateHistoryNamedProvenance
    let count: Int
}

/// Native and migration evidence remain separately countable. No field is a
/// Product/list/Session lifecycle authority.
struct ProductStateHistoryAggregate: Equatable, Sendable {
    let productID: ProductStateProductID
    let nativeUserCommandEventCount: Int
    let nativeSessionFinishEventCount: Int
    let legacyMigrationEventCount: Int
    let needAddedCount: Int
    let needResolvedAlreadyHaveCount: Int
    let needResolvedNoLongerNeededCount: Int
    let needReopenedCount: Int
    let listMembershipRemovedCount: Int
    let productRemovedFromLibraryCount: Int
    let productRestoredToLibraryCount: Int
    let confirmedPurchaseCount: Int
    let sessionAlreadyHaveCount: Int
    let sessionNoLongerNeededCount: Int
    let sessionUnavailableCount: Int
    let sessionSkippedCount: Int
    let sessionCarriedForwardCount: Int
    let duplicateContributionCount: Int
    let unsupportedEvidenceCount: Int
    let firstIncludedEventAt: Date?
    let lastIncludedEventAt: Date?
    let mostRecentNeedAddedAt: Date?

    /// The only native Catalog-personalization signal authorized in T-12.
    /// It represents exact `needAdded` evidence, never purchase.
    var safePersonalizationSignalCount: Int {
        needAddedCount
    }
}

struct ProductStateLegacyHistoryAggregateEvidence: Equatable, Sendable {
    let legacyRecordID: UUID
    let provenProductID: ProductStateProductID?
    let provenance: ProductStateHistoryNamedProvenance
    let observationCount: Int
    let firstObservedAt: Date
    let lastObservedAt: Date
    let averageInterval: TimeInterval?
    let legacyCompletionObservedAt: Date?

    init(
        legacyRecordID: UUID,
        provenProductID: ProductStateProductID?,
        observationCount: Int,
        firstObservedAt: Date,
        lastObservedAt: Date,
        averageInterval: TimeInterval?,
        legacyCompletionObservedAt: Date?
    ) {
        self.legacyRecordID = legacyRecordID
        self.provenProductID = provenProductID
        provenance = .retainedLegacyAggregate
        self.observationCount = observationCount
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.averageInterval = averageInterval
        self.legacyCompletionObservedAt = legacyCompletionObservedAt
    }
}

struct ProductStateProductHistoryProjection: Equatable, Sendable {
    let productID: ProductStateProductID
    let events: [ProductStateHistoryEventProjection]
    let aggregate: ProductStateHistoryAggregate
    let provenanceCounts: [ProductStateHistoryProvenanceCount]
    let retentionPolicy: ProductStateHistoryRetentionPolicy
    let retainedEventCount: Int
    let returnedEventCount: Int
    let omittedEventCount: Int
}

enum ProductStateHistoryQueryOutcomeKind:
    String, Codable, Hashable, Sendable {
    case success
    case invalidRequest
    case unavailable
}

enum ProductStateHistoryQueryFailure:
    String, Codable, Hashable, Sendable {
    case invalidLimit
    case repositoryReadFailed
}

struct ProductStateHistoryQueryDiagnostic:
    Equatable, Codable, Sendable {
    let productID: UUID
    let outcome: ProductStateHistoryQueryOutcomeKind
    let failure: ProductStateHistoryQueryFailure?
    let retentionPolicy: ProductStateHistoryRetentionPolicy
    let retainedEventCount: Int
    let returnedEventCount: Int
    let omittedEventCount: Int
    let duplicateContributionCount: Int
    let unsupportedEvidenceCount: Int
    let provenanceCounts: [ProductStateHistoryProvenanceCount]
}

enum ProductStateHistoryQueryOutcome: Equatable, Sendable {
    case success(
        projection: ProductStateProductHistoryProjection,
        diagnostic: ProductStateHistoryQueryDiagnostic
    )
    case invalidRequest(ProductStateHistoryQueryDiagnostic)
    case unavailable(ProductStateHistoryQueryDiagnostic)
}

@MainActor
protocol ProductStateHistoryQuerying: AnyObject {
    func history(
        _ request: ProductStateHistoryQueryRequest
    ) -> ProductStateHistoryQueryOutcome
}

/// T-12 implements only the Product History slice of TC-06. It maps mutable
/// persistence rows immediately into immutable value projections and exposes
/// no staging, repair, save, deletion, or default-store operation.
@MainActor
final class ProductStateHistoryQueryBoundary: ProductStateHistoryQuerying {
    private let historyRepository: any HistoryRepository
    private let retentionPolicy:
        ProductStateHistoryRetentionPolicy = .retainAllNoAutomaticExpiryV103

    init(historyRepository: any HistoryRepository) {
        self.historyRepository = historyRepository
    }

    func history(
        _ request: ProductStateHistoryQueryRequest
    ) -> ProductStateHistoryQueryOutcome {
        guard request.maximumEventCount > 0 else {
            return .invalidRequest(
                emptyDiagnostic(
                    productID: request.productID,
                    outcome: .invalidRequest,
                    failure: .invalidLimit
                )
            )
        }

        let rows: [WayTaskSchemaV4.ProductHistoryEvent]
        do {
            rows = try historyRepository.historyEvents(
                productID: request.productID.rawValue
            )
        } catch {
            return .unavailable(
                emptyDiagnostic(
                    productID: request.productID,
                    outcome: .unavailable,
                    failure: .repositoryReadFailed
                )
            )
        }

        let snapshots = rows.map(RawEventSnapshot.init).sorted(
            by: canonicalLessThan
        )
        let allEvents = project(
            snapshots,
            requestedProductID: request.productID
        )
        let ordered: [ProductStateHistoryEventProjection]
        switch request.order {
        case .oldestFirst:
            ordered = allEvents
        case .newestFirst:
            ordered = Array(allEvents.reversed())
        }
        let returned = Array(ordered.prefix(request.maximumEventCount))
        let aggregate = makeAggregate(
            productID: request.productID,
            events: allEvents
        )
        let provenanceCounts = makeProvenanceCounts(allEvents)
        let projection = ProductStateProductHistoryProjection(
            productID: request.productID,
            events: returned,
            aggregate: aggregate,
            provenanceCounts: provenanceCounts,
            retentionPolicy: retentionPolicy,
            retainedEventCount: allEvents.count,
            returnedEventCount: returned.count,
            omittedEventCount: allEvents.count - returned.count
        )
        let diagnostic = ProductStateHistoryQueryDiagnostic(
            productID: request.productID.rawValue,
            outcome: .success,
            failure: nil,
            retentionPolicy: retentionPolicy,
            retainedEventCount: allEvents.count,
            returnedEventCount: returned.count,
            omittedEventCount: allEvents.count - returned.count,
            duplicateContributionCount:
                aggregate.duplicateContributionCount,
            unsupportedEvidenceCount: aggregate.unsupportedEvidenceCount,
            provenanceCounts: provenanceCounts
        )
        return .success(projection: projection, diagnostic: diagnostic)
    }

    private func project(
        _ snapshots: [RawEventSnapshot],
        requestedProductID: ProductStateProductID
    ) -> [ProductStateHistoryEventProjection] {
        var seenEventIDs: Set<UUID> = []
        var seenCausalKeys: Set<CausalKey> = []

        return snapshots.map { event in
            let kind = eventKind(event.meaningRawValue)
            let provenance = namedProvenance(event.provenanceRawValue)
            let disposition: ProductStateHistoryContributionDisposition

            if event.productID != requestedProductID.rawValue {
                disposition = .unsupportedEvidence
            } else if seenEventIDs.contains(event.id) {
                disposition = .duplicateEventIdentity
            } else if !isSemanticallySupported(
                event,
                kind: kind,
                provenance: provenance
            ) {
                seenEventIDs.insert(event.id)
                disposition = .unsupportedEvidence
            } else if let key = causalKey(
                event,
                kind: kind,
                provenance: provenance
            ) {
                seenEventIDs.insert(event.id)
                if seenCausalKeys.contains(key) {
                    disposition = .duplicateCausalReplay
                } else {
                    seenCausalKeys.insert(key)
                    disposition = .included
                }
            } else {
                seenEventIDs.insert(event.id)
                disposition = .unsupportedEvidence
            }

            return ProductStateHistoryEventProjection(
                eventID: ProductStateHistoryEventID(rawValue: event.id),
                productID: ProductStateProductID(rawValue: event.productID),
                kind: kind,
                meaningRawValue: event.meaningRawValue,
                resolutionReason: event.resolutionReasonRawValue.flatMap(
                    ShoppingListResolutionReason.init(rawValue:)
                ),
                resolutionReasonRawValue: event.resolutionReasonRawValue,
                sessionOutcome: event.sessionOutcomeRawValue.flatMap(
                    ShoppingSessionFinalOutcome.init(rawValue:)
                ),
                sessionOutcomeRawValue: event.sessionOutcomeRawValue,
                sourceListID: event.sourceListID.map {
                    ProductStateListID(rawValue: $0)
                },
                sourceEntryID: event.sourceEntryID.map {
                    ProductStateListEntryID(rawValue: $0)
                },
                sessionID: event.sessionID.map {
                    ProductStateSessionID(rawValue: $0)
                },
                sessionLineID: event.sessionLineID.map {
                    ProductStateSessionLineID(rawValue: $0)
                },
                commandID: event.commandID.map {
                    ProductStateCommandID(rawValue: $0)
                },
                provenance: provenance,
                provenanceRawValue: event.provenanceRawValue,
                occurredAt: event.occurredAt,
                displaySnapshotID: event.displaySnapshotID,
                contribution: disposition
            )
        }
    }

    private func makeAggregate(
        productID: ProductStateProductID,
        events: [ProductStateHistoryEventProjection]
    ) -> ProductStateHistoryAggregate {
        var nativeUser = 0
        var nativeFinish = 0
        var legacyMigration = 0
        var needAdded = 0
        var resolvedAlreadyHave = 0
        var resolvedNoLongerNeeded = 0
        var reopened = 0
        var membershipRemoved = 0
        var productRemoved = 0
        var productRestored = 0
        var purchased = 0
        var sessionAlreadyHave = 0
        var sessionNoLongerNeeded = 0
        var unavailable = 0
        var skipped = 0
        var carriedForward = 0
        var duplicates = 0
        var unsupported = 0
        var includedDates: [Date] = []
        var needAddedDates: [Date] = []

        for event in events {
            switch event.contribution {
            case .duplicateEventIdentity, .duplicateCausalReplay:
                duplicates += 1
                continue
            case .unsupportedEvidence:
                unsupported += 1
                continue
            case .included:
                break
            }

            includedDates.append(event.occurredAt)
            switch event.provenance {
            case .nativeUserCommand:
                nativeUser += 1
            case .nativeSessionFinish:
                nativeFinish += 1
            case .legacyMigration:
                legacyMigration += 1
                continue
            case .retainedLegacyAggregate, .unsupported:
                unsupported += 1
                continue
            }

            switch event.kind {
            case .needAdded:
                needAdded += 1
                needAddedDates.append(event.occurredAt)
            case .needResolved:
                switch event.resolutionReason {
                case .alreadyHave:
                    resolvedAlreadyHave += 1
                case .noLongerNeeded:
                    resolvedNoLongerNeeded += 1
                case .purchased, .legacyUnknown, .none:
                    unsupported += 1
                }
            case .needReopened:
                reopened += 1
            case .listMembershipRemoved:
                membershipRemoved += 1
            case .productRemovedFromLibrary:
                productRemoved += 1
            case .productRestoredToLibrary:
                productRestored += 1
            case .sessionOutcome:
                switch event.sessionOutcome {
                case .purchased: purchased += 1
                case .alreadyHave: sessionAlreadyHave += 1
                case .noLongerNeeded: sessionNoLongerNeeded += 1
                case .unavailable: unavailable += 1
                case .skipped: skipped += 1
                case .carriedForward: carriedForward += 1
                case .none: unsupported += 1
                }
            case .unsupported:
                unsupported += 1
            }
        }

        return ProductStateHistoryAggregate(
            productID: productID,
            nativeUserCommandEventCount: nativeUser,
            nativeSessionFinishEventCount: nativeFinish,
            legacyMigrationEventCount: legacyMigration,
            needAddedCount: needAdded,
            needResolvedAlreadyHaveCount: resolvedAlreadyHave,
            needResolvedNoLongerNeededCount: resolvedNoLongerNeeded,
            needReopenedCount: reopened,
            listMembershipRemovedCount: membershipRemoved,
            productRemovedFromLibraryCount: productRemoved,
            productRestoredToLibraryCount: productRestored,
            confirmedPurchaseCount: purchased,
            sessionAlreadyHaveCount: sessionAlreadyHave,
            sessionNoLongerNeededCount: sessionNoLongerNeeded,
            sessionUnavailableCount: unavailable,
            sessionSkippedCount: skipped,
            sessionCarriedForwardCount: carriedForward,
            duplicateContributionCount: duplicates,
            unsupportedEvidenceCount: unsupported,
            firstIncludedEventAt: includedDates.min(),
            lastIncludedEventAt: includedDates.max(),
            mostRecentNeedAddedAt: needAddedDates.max()
        )
    }

    private func makeProvenanceCounts(
        _ events: [ProductStateHistoryEventProjection]
    ) -> [ProductStateHistoryProvenanceCount] {
        let grouped = Dictionary(grouping: events, by: \.provenance)
        return ProductStateHistoryNamedProvenance.allCases.compactMap {
            provenance in
            guard let count = grouped[provenance]?.count, count > 0 else {
                return nil
            }
            return ProductStateHistoryProvenanceCount(
                provenance: provenance,
                count: count
            )
        }
    }

    private func isSemanticallySupported(
        _ event: RawEventSnapshot,
        kind: ProductStateHistoryEventKind,
        provenance: ProductStateHistoryNamedProvenance
    ) -> Bool {
        switch provenance {
        case .nativeUserCommand:
            guard event.commandID != nil else { return false }
            switch kind {
            case .needAdded, .needReopened, .listMembershipRemoved,
                 .needResolved:
                guard event.sourceListID != nil,
                      event.sourceEntryID != nil else { return false }
                if kind == .needResolved {
                    return event.resolutionReasonRawValue == "alreadyHave"
                        || event.resolutionReasonRawValue == "noLongerNeeded"
                }
                return true
            case .productRemovedFromLibrary, .productRestoredToLibrary:
                return true
            case .sessionOutcome, .unsupported:
                return false
            }
        case .nativeSessionFinish:
            return kind == .sessionOutcome
                && event.commandID != nil
                && event.sourceListID != nil
                && event.sourceEntryID != nil
                && event.sessionID != nil
                && event.sessionLineID != nil
                && event.sessionOutcomeRawValue.flatMap(
                    ShoppingSessionFinalOutcome.init(rawValue:)
                ) != nil
        case .legacyMigration:
            return true
        case .retainedLegacyAggregate, .unsupported:
            return false
        }
    }

    private func causalKey(
        _ event: RawEventSnapshot,
        kind: ProductStateHistoryEventKind,
        provenance: ProductStateHistoryNamedProvenance
    ) -> CausalKey? {
        switch provenance {
        case .nativeUserCommand:
            guard let commandID = event.commandID else { return nil }
            return CausalKey(
                provenance: provenance,
                productID: event.productID,
                commandID: commandID,
                sessionID: nil,
                sessionLineID: nil,
                kind: kind,
                resolutionReasonRawValue: event.resolutionReasonRawValue,
                sessionOutcomeRawValue: nil,
                sourceListID: event.sourceListID,
                sourceEntryID: event.sourceEntryID,
                legacyEventID: nil
            )
        case .nativeSessionFinish:
            guard let commandID = event.commandID,
                  let sessionID = event.sessionID,
                  let sessionLineID = event.sessionLineID else { return nil }
            return CausalKey(
                provenance: provenance,
                productID: event.productID,
                commandID: commandID,
                sessionID: sessionID,
                sessionLineID: sessionLineID,
                kind: kind,
                resolutionReasonRawValue: event.resolutionReasonRawValue,
                sessionOutcomeRawValue: event.sessionOutcomeRawValue,
                sourceListID: event.sourceListID,
                sourceEntryID: event.sourceEntryID,
                legacyEventID: nil
            )
        case .legacyMigration:
            return CausalKey(
                provenance: provenance,
                productID: event.productID,
                commandID: event.commandID,
                sessionID: event.sessionID,
                sessionLineID: event.sessionLineID,
                kind: kind,
                resolutionReasonRawValue: event.resolutionReasonRawValue,
                sessionOutcomeRawValue: event.sessionOutcomeRawValue,
                sourceListID: event.sourceListID,
                sourceEntryID: event.sourceEntryID,
                legacyEventID: event.id
            )
        case .retainedLegacyAggregate, .unsupported:
            return nil
        }
    }

    private func eventKind(
        _ rawValue: String
    ) -> ProductStateHistoryEventKind {
        switch rawValue {
        case "needAdded": .needAdded
        case "needResolved": .needResolved
        case "needReopened": .needReopened
        case "listMembershipRemoved", "needRemoved":
            .listMembershipRemoved
        case "productRemovedFromLibrary": .productRemovedFromLibrary
        case "productRestoredToLibrary": .productRestoredToLibrary
        case "sessionOutcome": .sessionOutcome
        default: .unsupported
        }
    }

    private func namedProvenance(
        _ rawValue: String
    ) -> ProductStateHistoryNamedProvenance {
        switch rawValue {
        case "userCommand": .nativeUserCommand
        case "sessionFinish": .nativeSessionFinish
        case "legacyMigration": .legacyMigration
        default: .unsupported
        }
    }

    private func emptyDiagnostic(
        productID: ProductStateProductID,
        outcome: ProductStateHistoryQueryOutcomeKind,
        failure: ProductStateHistoryQueryFailure
    ) -> ProductStateHistoryQueryDiagnostic {
        ProductStateHistoryQueryDiagnostic(
            productID: productID.rawValue,
            outcome: outcome,
            failure: failure,
            retentionPolicy: retentionPolicy,
            retainedEventCount: 0,
            returnedEventCount: 0,
            omittedEventCount: 0,
            duplicateContributionCount: 0,
            unsupportedEvidenceCount: 0,
            provenanceCounts: []
        )
    }

    private func canonicalLessThan(
        _ lhs: RawEventSnapshot,
        _ rhs: RawEventSnapshot
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.canonicalTieBreaker < rhs.canonicalTieBreaker
    }

    private struct CausalKey: Hashable {
        let provenance: ProductStateHistoryNamedProvenance
        let productID: UUID
        let commandID: UUID?
        let sessionID: UUID?
        let sessionLineID: UUID?
        let kind: ProductStateHistoryEventKind
        let resolutionReasonRawValue: String?
        let sessionOutcomeRawValue: String?
        let sourceListID: UUID?
        let sourceEntryID: UUID?
        let legacyEventID: UUID?
    }

    private struct RawEventSnapshot {
        let id: UUID
        let productID: UUID
        let meaningRawValue: String
        let resolutionReasonRawValue: String?
        let sessionOutcomeRawValue: String?
        let sourceListID: UUID?
        let sourceEntryID: UUID?
        let sessionID: UUID?
        let sessionLineID: UUID?
        let commandID: UUID?
        let provenanceRawValue: String
        let occurredAt: Date
        let displaySnapshotID: UUID?

        init(_ event: WayTaskSchemaV4.ProductHistoryEvent) {
            id = event.id
            productID = event.productID
            meaningRawValue = event.meaningRawValue
            resolutionReasonRawValue = event.resolutionReasonRawValue
            sessionOutcomeRawValue = event.sessionOutcomeRawValue
            sourceListID = event.sourceListID
            sourceEntryID = event.sourceEntryID
            sessionID = event.sessionID
            sessionLineID = event.sessionLineID
            commandID = event.commandID
            provenanceRawValue = event.provenanceRawValue
            occurredAt = event.occurredAt
            displaySnapshotID = event.displaySnapshotID
        }

        var canonicalTieBreaker: String {
            [
                productID.uuidString,
                meaningRawValue,
                resolutionReasonRawValue ?? "",
                sessionOutcomeRawValue ?? "",
                sourceListID?.uuidString ?? "",
                sourceEntryID?.uuidString ?? "",
                sessionID?.uuidString ?? "",
                sessionLineID?.uuidString ?? "",
                commandID?.uuidString ?? "",
                provenanceRawValue,
                displaySnapshotID?.uuidString ?? ""
            ].joined(separator: "|")
        }
    }
}

// MARK: - T-13 complete read-only projection boundary

enum ProductStateProjectionCachePolicy:
    String, Codable, Hashable, Sendable {
    /// S-02 makes caching optional. T-13 deliberately rebuilds every read so
    /// correctness has no cache dependency and no invalidation side effect.
    case disabledDirectRebuild
}

enum ProductStateProjectionScope: Hashable, Sendable {
    case library(ProductLibraryLifecycle)
    case product(ProductStateProductID)
    case list(ProductStateListID)
    case plan(ProductStatePlanID, ProductStateListID)
    case sessions
    case session(ProductStateSessionID)
    case knowledge(inputFingerprint: String)
    case location(UUID)
    case migration(version: String)
}

enum ProductStateProjectionStaleReason:
    String, CaseIterable, Codable, Hashable, Sendable {
    case expectedListRevisionChanged
    case expectedSessionRevisionChanged
    case sourceIdentityChanged
    case sourceRevisionChanged
    case includedEntriesChanged
    case declaredInputChanged
    case snapshotChanged
    case evidenceExpired
}

enum ProductStateProjectionUnavailableReason:
    String, Codable, Hashable, Sendable {
    case invalidRequest
    case notFound
    case ambiguousAuthority
    case repositoryReadFailed
    case migrationIncomplete
    case invariantFailure
}

enum ProductStateProjectionFreshness: Equatable, Sendable {
    case current
    case stale([ProductStateProjectionStaleReason])
    case unavailable(ProductStateProjectionUnavailableReason)
}

enum ProductStateProjectionProvenance: Equatable, Sendable {
    case targetProductState
    case frozenSessionSnapshot
    case nativeHistoryEvents
    case publishedCatalog(version: String)
    case publishedProductKnowledge(version: String)
    case savedLocationEvidence(version: String)
    case publishedStoreEvidence(version: String)
    case migrationRecovery(version: String)
}

enum ProductStateProjectionOmissionReason:
    String, Codable, Hashable, Sendable {
    case missingProduct
    case ambiguousProduct
    case removedProduct
    case malformedEntryState
    case invalidEntryScope
    case unresolvedSessionLine
    case invalidSessionReference
    case explicitExclusion
    case unprovenLocationLink
    case unsupportedEvidence
}

struct ProductStateProjectionOmission: Equatable, Sendable {
    let reason: ProductStateProjectionOmissionReason
    let productID: ProductStateProductID?
    let listID: ProductStateListID?
    let entryID: ProductStateListEntryID?
    let sessionID: ProductStateSessionID?
    let sessionLineID: ProductStateSessionLineID?
}

struct ProductStateProjectionMetadata: Equatable, Sendable {
    let scope: ProductStateProjectionScope
    let freshness: ProductStateProjectionFreshness
    let listRevision: ProductStateListRevision?
    let sessionRevision: ProductStateSessionRevision?
    let sessionSnapshotID: ProductStateSessionSnapshotID?
    let provenances: [ProductStateProjectionProvenance]
    let omissions: [ProductStateProjectionOmission]
    let cachePolicy: ProductStateProjectionCachePolicy
}

enum ProductStateProjectionOutcome<Value: Equatable>: Equatable {
    case projection(Value)
    case unavailable(ProductStateProjectionMetadata)
}

struct ProductStateProductProjection: Equatable, Sendable {
    let id: ProductStateProductID
    let revision: UInt64
    let libraryLifecycle: ProductLibraryLifecycle
    let libraryRemovedAt: Date?
    let displayName: String
    let brand: String?
    let category: String?
    let barcode: String?
    let catalogID: ProductStateCatalogID?
    let catalogDisplayNameSnapshot: String?
    let catalogDisplayLocaleSnapshot: String?
    let catalogCategoryIDSnapshot: String?
    let catalogCategoryDisplayNameSnapshot: String?
    let catalogIconKeySnapshot: String?
    let catalogSnapshotUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

enum ProductStateMembershipAction:
    String, Codable, Hashable, Sendable {
    case add
    case resolve
    case reopen
    case remove
    case restoreProduct
}

enum ProductStateMembershipState: Equatable, Sendable {
    case absent
    case needed(ProductStateListEntryID)
    case resolved(
        entryID: ProductStateListEntryID,
        reason: ShoppingListResolutionReason?,
        effectiveAt: Date?
    )
    case unresolved(ProductStateListEntryID, rawState: String)
    case ambiguous([ProductStateListEntryID])
}

struct ProductStateMembershipProjection: Equatable, Sendable {
    let productID: ProductStateProductID
    let listID: ProductStateListID
    let listRevision: ProductStateListRevision
    let state: ProductStateMembershipState
    let permittedActions: [ProductStateMembershipAction]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateProductLibraryItem: Equatable, Sendable {
    let product: ProductStateProductProjection
    let membership: ProductStateMembershipProjection?
}

struct ProductStateProductLibraryProjection: Equatable, Sendable {
    let products: [ProductStateProductLibraryItem]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateRemovedProductProjection: Equatable, Sendable {
    let product: ProductStateProductProjection
    let restoreAvailable: Bool
}

struct ProductStateRemovedProductsProjection: Equatable, Sendable {
    let products: [ProductStateRemovedProductProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateListScopeRequest: Equatable, Sendable {
    let listID: ProductStateListID
    let expectedRevision: ProductStateListRevision?
}

struct ProductStateProductLibraryRequest: Equatable, Sendable {
    let membershipScope: ProductStateListScopeRequest?
}

enum ProductStateExactAcquisitionEvidence: Hashable, Sendable {
    case productID(ProductStateProductID)
    case catalogID(ProductStateCatalogID)
    case barcode(String)
}

struct ProductStateAcquisitionMatchRequest: Equatable, Sendable {
    let candidateProductID: ProductStateProductID
    let exactEvidence: [ProductStateExactAcquisitionEvidence]
}

enum ProductStateAcquisitionMatch: Equatable, Sendable {
    case alreadyActive(ProductStateProductProjection)
    case restoreRequired(ProductStateProductProjection)
    case create(ProductStateProductID)
    case ambiguous([ProductStateProductID])
}

struct ProductStateAcquisitionMatchProjection: Equatable, Sendable {
    let match: ProductStateAcquisitionMatch
    let matchedEvidence: [ProductStateExactAcquisitionEvidence]
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateListEntryProjectionState: Equatable, Sendable {
    case needed
    case resolved(
        reason: ShoppingListResolutionReason?,
        reasonRawValue: String?,
        effectiveAt: Date?,
        provenanceRawValue: String?,
        commandID: ProductStateCommandID?,
        sessionID: ProductStateSessionID?,
        sessionLineID: ProductStateSessionLineID?
    )
    case unresolved(rawValue: String)
}

struct ProductStateListEntryProjection: Equatable, Sendable {
    let identity: ProductStateListEntryIdentity
    let state: ProductStateListEntryProjectionState
    let quantity: Double
    let unitRawValue: String?
    let note: String?
    let sortOrder: Double
    let product: ProductStateProductProjection?
    let issues: [ProductStateProjectionOmissionReason]
    let createdAt: Date
    let updatedAt: Date
}

struct ProductStateNamedListProjection: Equatable, Sendable {
    let id: ProductStateListID
    let revision: ProductStateListRevision
    let title: String
    let purposeRawValue: String?
    let neededEntries: [ProductStateListEntryProjection]
    let resolvedEntries: [ProductStateListEntryProjection]
    let unresolvedEntries: [ProductStateListEntryProjection]
    let createdAt: Date
    let updatedAt: Date
    let metadata: ProductStateProjectionMetadata

    var neededEntryIDs: [ProductStateListEntryID] {
        neededEntries.map(\.identity.id)
    }
}

enum ProductStatePlanInputExclusionReason:
    String, Codable, Hashable, Sendable {
    case explicitUserExclusion
    case missingProduct
    case ambiguousProduct
    case removedProduct
    case malformedEntry
}

struct ProductStatePlanInputExclusionProjection: Equatable, Sendable {
    let entry: ProductStateListEntryProjection
    let reason: ProductStatePlanInputExclusionReason
}

struct ProductStatePlanInputRequest: Equatable, Sendable {
    let listScope: ProductStateListScopeRequest
    let declaredInputFingerprint: String
    let explicitlyExcludedEntryIDs: Set<ProductStateListEntryID>
}

struct ProductStatePlanInputProjection: Equatable, Sendable {
    let listID: ProductStateListID
    let revision: ProductStateListRevision
    let eligibleEntries: [ProductStateListEntryProjection]
    let exclusions: [ProductStatePlanInputExclusionProjection]
    let allNeededEntryIDs: [ProductStateListEntryID]
    let declaredInputFingerprint: String
    let metadata: ProductStateProjectionMetadata
}

struct ProductStatePlanStatusRequest: Equatable, Sendable {
    let plan: ProductStateShoppingPlan
    let planInputFingerprint: String
    let currentInput: ProductStatePlanInputProjection
}

struct ProductStatePlanStatusProjection: Equatable, Sendable {
    let planID: ProductStatePlanID
    let sourceListID: ProductStateListID
    let sourceRevision: ProductStateListRevision
    let includedEntryIDs: [ProductStateListEntryID]
    let excludedEntryIDs: [ProductStateListEntryID]
    let status: ShoppingPlanStatus
    let staleReasons: [ShoppingPlanStaleReason]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateActiveSessionCandidateProjection: Equatable, Sendable {
    let sessionID: ProductStateSessionID
    let revision: ProductStateSessionRevision
    let snapshotID: ProductStateSessionSnapshotID
    let sourceListID: ProductStateListID?
    let sourceRevision: ShoppingSessionSourceRevision
    let lifecycle: ShoppingSessionLifecycle
    let migrationCondition: ShoppingSessionMigrationCondition
    let startedAt: Date
}

struct ProductStateActiveSessionLookupProjection: Equatable, Sendable {
    let candidates: [ProductStateActiveSessionCandidateProjection]
    let requiresExplicitSelection: Bool
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateSessionRecordQualification:
    String, Codable, Hashable, Sendable {
    case qualified
    case unresolved
    case invalidReference
}

struct ProductStateSessionStopProjection: Equatable, Sendable {
    let id: ProductStateSessionStopID
    let sortOrder: Int
    let storeReferenceID: String?
    let storeReferenceProvenanceRawValue: String
    let displayNameSnapshot: String
    let latitudeSnapshot: Double?
    let longitudeSnapshot: Double?
    let evidenceAt: Date?
    let isSessionScopedTransient: Bool
    let qualification: ProductStateSessionRecordQualification
}

struct ProductStateSessionLineProjection: Equatable, Sendable {
    let id: ProductStateSessionLineID
    let snapshotID: ProductStateSessionSnapshotID
    let sourceListID: ProductStateListID?
    let sourceEntryID: ProductStateListEntryID?
    let productID: ProductStateProductID?
    let stopID: ProductStateSessionStopID?
    let sortOrder: Int
    let productNameSnapshot: String
    let productBrandSnapshot: String?
    let productCategorySnapshot: String?
    let quantitySnapshot: Double
    let unitSnapshotRawValue: String?
    let noteSnapshot: String?
    let executionState: ShoppingSessionExecutionState?
    let executionStateRawValue: String
    let finalOutcome: ShoppingSessionFinalOutcome?
    let finalOutcomeRawValue: String?
    let legacyDisposition: ShoppingSessionLegacyDisposition?
    let qualification: ProductStateSessionRecordQualification
}

struct ProductStateSessionExceptionProjection: Equatable, Sendable {
    let id: UUID
    let sessionID: ProductStateSessionID?
    let sessionLineID: ProductStateSessionLineID?
    let categoryRawValue: String
    let safeEvidenceDigest: String
    let ordinal: Int
    let occurrenceCount: Int
    let recordedAt: Date
}

struct ProductStateSessionSnapshotRequest: Equatable, Sendable {
    let sessionID: ProductStateSessionID
    let expectedRevision: ProductStateSessionRevision?
}

struct ProductStateSessionSnapshotProjection: Equatable, Sendable {
    let id: ProductStateSessionID
    let revision: ProductStateSessionRevision
    let lifecycle: ShoppingSessionLifecycle?
    let lifecycleRawValue: String
    let migrationCondition: ShoppingSessionMigrationCondition?
    let migrationConditionRawValue: String
    let snapshotID: ProductStateSessionSnapshotID
    let snapshotVersion: Int
    let snapshotGeneration: Int
    let snapshotContentSignature: String
    let sourceListID: ProductStateListID?
    let sourceRevision: ShoppingSessionSourceRevision
    let sourcePlanID: ProductStatePlanID?
    let sourcePlanSignature: String?
    let sourcePlanEvidenceAt: Date?
    let stops: [ProductStateSessionStopProjection]
    let lines: [ProductStateSessionLineProjection]
    let exceptions: [ProductStateSessionExceptionProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateFinishReviewRequest: Equatable, Sendable {
    let session: ProductStateSessionSnapshotRequest
    let proposedOutcomes: [ProductStateSessionLineID:
        ShoppingSessionFinalOutcome]
    let expectedCurrentListRevision: ProductStateListRevision?

    init(
        session: ProductStateSessionSnapshotRequest,
        proposedOutcomes: [ProductStateSessionLineID:
            ShoppingSessionFinalOutcome],
        expectedCurrentListRevision: ProductStateListRevision? = nil
    ) {
        self.session = session
        self.proposedOutcomes = proposedOutcomes
        self.expectedCurrentListRevision = expectedCurrentListRevision
    }
}

enum ProductStateFinishReviewStatus:
    String, Codable, Hashable, Sendable {
    case ready
    case incomplete
    case sourceConflict
    case invalidSession
}

struct ProductStateFinishReviewLineProjection: Equatable, Sendable {
    let line: ProductStateSessionLineProjection
    let proposedOutcome: ShoppingSessionFinalOutcome?
    let isValid: Bool
}

struct ProductStateFinishReviewProjection: Equatable, Sendable {
    let sessionID: ProductStateSessionID
    let sessionRevision: ProductStateSessionRevision
    let lines: [ProductStateFinishReviewLineProjection]
    let missingOutcomeLineIDs: [ProductStateSessionLineID]
    let invalidLineIDs: [ProductStateSessionLineID]
    let status: ProductStateFinishReviewStatus
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateCatalogPublicationStatus:
    Equatable, Sendable {
    case unlinked
    case current
    case redirected(from: ProductStateCatalogID)
    case offlineSnapshot
    case mismatchedEvidence
}

struct ProductStatePublishedCatalogEvidence: Equatable, Sendable {
    let catalogID: ProductStateCatalogID
    let redirectsFrom: [ProductStateCatalogID]
    let displayName: String
    let categoryID: String?
    let categoryDisplayName: String?
    let iconKey: String?
    let locale: String?
    let version: String
}

struct ProductStateCatalogLinkedProductProjection: Equatable, Sendable {
    let product: ProductStateProductProjection
    let status: ProductStateCatalogPublicationStatus
    let displayedName: String
    let displayedCategoryID: String?
    let displayedCategoryName: String?
    let displayedIconKey: String?
    let displayedLocale: String?
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateKnowledgeCandidateInput: Equatable, Sendable {
    let evidenceID: UUID
    let displayNameSnapshot: String
    let confidence: Double
    let provenanceRawValue: String
}

struct ProductStateKnowledgeSearchRequest: Equatable, Sendable {
    /// A caller may provide an already-authoritative Product UUID. Nil means
    /// acquisition browse scope; no candidate is allowed to fabricate one.
    let productID: ProductStateProductID?
    let inputFingerprint: String
    let publicationVersion: String
    let maximumCandidateCount: Int
}

struct ProductStateKnowledgeCandidateProjection: Equatable, Sendable {
    let evidenceID: UUID
    let productID: ProductStateProductID?
    let displayNameSnapshot: String
    let confidence: Double
    let provenanceRawValue: String
}

struct ProductStateKnowledgeSearchProjection: Equatable, Sendable {
    let explicitProductID: ProductStateProductID?
    let candidates: [ProductStateKnowledgeCandidateProjection]
    let omittedCandidateCount: Int
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateShoppingContextOwner: Equatable, Sendable {
    case list(ProductStateListID, ProductStateListRevision)
    case plan(
        ProductStatePlanID,
        ProductStateListID,
        ProductStateListRevision
    )
    case session(
        ProductStateSessionID,
        ProductStateSessionRevision,
        ProductStateSessionSnapshotID
    )
}

struct ProductStateShoppingContextItemProjection: Equatable, Sendable {
    let productID: ProductStateProductID?
    let entryID: ProductStateListEntryID?
    let sessionLineID: ProductStateSessionLineID?
    let displayNameSnapshot: String?
    let isQualified: Bool
}

struct ProductStateMapShoppingContextProjection: Equatable, Sendable {
    let owner: ProductStateShoppingContextOwner
    let items: [ProductStateShoppingContextItemProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateNotificationOpportunityProjection:
    Equatable, Sendable {
    let owner: ProductStateShoppingContextOwner
    let items: [ProductStateShoppingContextItemProjection]
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateNotificationPayloadOwner: Equatable, Sendable {
    case list(ProductStateListID, ProductStateListRevision)
    case plan(
        ProductStatePlanID,
        ProductStateListID,
        ProductStateListRevision
    )
    case session(
        ProductStateSessionID,
        ProductStateSessionRevision,
        ProductStateSessionSnapshotID
    )
}

enum ProductStateNotificationRoute: Equatable, Sendable {
    case namedList(ProductStateListID)
    case session(ProductStateSessionID)
    case safeShopping(ProductStateProjectionStaleReason)
    case suppressed(ProductStateProjectionUnavailableReason)
}

struct ProductStateNotificationRouteProjection: Equatable, Sendable {
    let payloadOwner: ProductStateNotificationPayloadOwner
    let route: ProductStateNotificationRoute
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateSavedLocationLinkAuthority:
    String, Codable, Hashable, Sendable {
    case exactTargetReference
    case legacyEvidenceOnly
    case unproven
}

struct ProductStateSavedLocationLinkInput: Equatable, Sendable {
    let productID: ProductStateProductID?
    let listID: ProductStateListID?
    let entryID: ProductStateListEntryID?
    let authority: ProductStateSavedLocationLinkAuthority
}

struct ProductStateSavedLocationEvidenceInput: Equatable, Sendable {
    let locationID: UUID
    let displayNameSnapshot: String
    let noteSnapshot: String?
    let latitude: Double?
    let longitude: Double?
    let evidenceVersion: String
    let links: [ProductStateSavedLocationLinkInput]
}

struct ProductStateSavedLocationLinkProjection: Equatable, Sendable {
    let productID: ProductStateProductID?
    let listID: ProductStateListID?
    let entryID: ProductStateListEntryID?
    let authority: ProductStateSavedLocationLinkAuthority
    let isAuthoritativeProductStateLink: Bool
}

struct ProductStateSavedLocationEvidenceProjection:
    Equatable, Sendable {
    let locationID: UUID
    let displayNameSnapshot: String
    let noteSnapshot: String?
    let latitude: Double?
    let longitude: Double?
    let links: [ProductStateSavedLocationLinkProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateDiscoveryContextProjection: Equatable, Sendable {
    let owner: ProductStateShoppingContextOwner
    let eligibleProductIDs: [ProductStateProductID]
    let unresolvedItems: [ProductStateShoppingContextItemProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStatePublishedStoreEvidence: Equatable, Sendable {
    let storeID: String
    let coveredProductIDs: Set<ProductStateProductID>
    let confidence: Double
    let evidenceAt: Date
    let publicationVersion: String
}

struct ProductStateStoreRecommendationProjection: Equatable, Sendable {
    let storeID: String
    let estimatedCoveredProductIDs: [ProductStateProductID]
    let uncoveredProductIDs: [ProductStateProductID]
    let confidence: Double
    let evidenceAt: Date
}

struct ProductStateStoreRecommendationsProjection: Equatable, Sendable {
    let owner: ProductStateShoppingContextOwner
    let recommendations: [ProductStateStoreRecommendationProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateMigrationRecoveryInput: Equatable, Sendable {
    let migrationVersion: String
    let semanticMigrationComplete: Bool
    let invariantsValid: Bool
    let exceptionLedger: [ProductStateSessionExceptionProjection]
}

enum ProductStateTargetWriteAvailability:
    String, Codable, Hashable, Sendable {
    case available
    case blockedMigrationIncomplete
    case blockedInvariantFailure
}

struct ProductStateMigrationRecoveryProjection: Equatable, Sendable {
    let migrationVersion: String
    let targetWriteAvailability: ProductStateTargetWriteAvailability
    let sessionCandidates: [ProductStateActiveSessionCandidateProjection]
    let exceptions: [ProductStateSessionExceptionProjection]
    let metadata: ProductStateProjectionMetadata
}

struct ProductStateListParityProjection: Equatable, Sendable {
    let namedList: ProductStateNamedListProjection
    let planInput: ProductStatePlanInputProjection
    let mapContext: ProductStateMapShoppingContextProjection
    let notificationOpportunity:
        ProductStateNotificationOpportunityProjection
}

@MainActor
final class ProductStateQueryBoundary {
    let cachePolicy:
        ProductStateProjectionCachePolicy = .disabledDirectRebuild

    private let products: any ProductRepository
    private let shopping: any ShoppingRepository
    private let sessions: any ShoppingSessionRepository

    init(
        products: any ProductRepository,
        shopping: any ShoppingRepository,
        sessions: any ShoppingSessionRepository
    ) {
        self.products = products
        self.shopping = shopping
        self.sessions = sessions
    }

    convenience init(repositories: ProductStateRepositories) {
        self.init(
            products: repositories.products,
            shopping: repositories.shopping,
            sessions: repositories.sessions
        )
    }

    func productLibrary(
        _ request: ProductStateProductLibraryRequest
    ) -> ProductStateProjectionOutcome<
        ProductStateProductLibraryProjection
    > {
        let listSnapshot: ListSnapshot?
        if let scope = request.membershipScope {
            switch loadList(scope) {
            case let .success(snapshot): listSnapshot = snapshot
            case let .failure(metadata): return .unavailable(metadata)
            }
        } else {
            listSnapshot = nil
        }

        let rows: [WayTaskSchemaV4.Product]
        do {
            rows = try products.products(libraryLifecycle: .active)
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .library(.active),
                    reason: .repositoryReadFailed
                )
            )
        }

        let mapped = uniquelyScopedProducts(rows, lifecycle: .active)
        var items: [ProductStateProductLibraryItem] = []
        var omissions = mapped.omissions
        for product in mapped.products {
            let membership: ProductStateMembershipProjection?
            if let listSnapshot {
                switch membershipProjection(
                    product: product,
                    list: listSnapshot
                ) {
                case let .success(value): membership = value
                case let .failure(value):
                    membership = value
                    omissions.append(contentsOf: value.metadata.omissions)
                }
            } else {
                membership = nil
            }
            items.append(
                ProductStateProductLibraryItem(
                    product: product,
                    membership: membership
                )
            )
        }

        let freshness = listSnapshot?.freshness ?? .current
        let metadata = metadata(
            scope: .library(.active),
            freshness: freshness,
            listRevision: listSnapshot?.revision,
            provenances: [.targetProductState],
            omissions: canonicalOmissions(omissions)
        )
        return .projection(
            ProductStateProductLibraryProjection(
                products: items,
                metadata: metadata
            )
        )
    }

    func removedProducts() -> ProductStateProjectionOutcome<
        ProductStateRemovedProductsProjection
    > {
        let rows: [WayTaskSchemaV4.Product]
        do {
            rows = try products.products(libraryLifecycle: .removed)
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .library(.removed),
                    reason: .repositoryReadFailed
                )
            )
        }
        let mapped = uniquelyScopedProducts(rows, lifecycle: .removed)
        let values = mapped.products.sorted {
            let lhsDate = $0.libraryRemovedAt ?? .distantPast
            let rhsDate = $1.libraryRemovedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return uuidLess($0.id.rawValue, $1.id.rawValue)
        }.map {
            ProductStateRemovedProductProjection(
                product: $0,
                restoreAvailable: true
            )
        }
        let projectionMetadata = metadata(
            scope: .library(.removed),
            freshness: .current,
            provenances: [.targetProductState],
            omissions: canonicalOmissions(mapped.omissions)
        )
        return .projection(
            ProductStateRemovedProductsProjection(
                products: values,
                metadata: projectionMetadata
            )
        )
    }

    func acquisitionMatch(
        _ request: ProductStateAcquisitionMatchRequest
    ) -> ProductStateProjectionOutcome<
        ProductStateAcquisitionMatchProjection
    > {
        var matchedByID: [UUID: WayTaskSchemaV4.Product] = [:]
        var matchedCounts: [UUID: Int] = [:]
        var matchedEvidence: [ProductStateExactAcquisitionEvidence] = []

        do {
            for evidence in canonicalEvidence(request.exactEvidence) {
                let matches: [WayTaskSchemaV4.Product]
                switch evidence {
                case let .productID(id):
                    matches = try products.products(id: id.rawValue)
                case let .catalogID(id):
                    matches = try products.products(
                        catalogProductIDRawValue: id.rawValue
                    )
                case let .barcode(barcode):
                    guard !barcode.isEmpty else {
                        return .unavailable(
                            unavailableMetadata(
                                scope: .product(request.candidateProductID),
                                reason: .invalidRequest
                            )
                        )
                    }
                    matches = try products.products(barcode: barcode)
                }
                let exactMatches = matches.filter { match in
                    switch evidence {
                    case let .productID(id):
                        match.id == id.rawValue
                    case let .catalogID(id):
                        match.catalogProductIDRawValue == id.rawValue
                    case let .barcode(barcode):
                        match.barcode == barcode
                    }
                }
                if !exactMatches.isEmpty {
                    matchedEvidence.append(evidence)
                }
                for match in exactMatches {
                    matchedByID[match.id] = match
                    matchedCounts[match.id, default: 0] += 1
                }
            }
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(request.candidateProductID),
                    reason: .repositoryReadFailed
                )
            )
        }

        let matchedIDs = matchedByID.keys.sorted(by: uuidLess)
        let match: ProductStateAcquisitionMatch
        if matchedCounts.values.contains(where: { $0 > 1 }) {
            match = .ambiguous(
                matchedCounts.filter { $0.value > 1 }.keys.sorted(
                    by: uuidLess
                ).map(ProductStateProductID.init(rawValue:))
            )
        } else if matchedIDs.isEmpty {
            match = .create(request.candidateProductID)
        } else if matchedIDs.count > 1 {
            match = .ambiguous(
                matchedIDs.map(ProductStateProductID.init(rawValue:))
            )
        } else if let row = matchedIDs.first.flatMap({ matchedByID[$0] }),
                  let product = mapProduct(row) {
            switch product.libraryLifecycle {
            case .active: match = .alreadyActive(product)
            case .removed: match = .restoreRequired(product)
            }
        } else {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(request.candidateProductID),
                    reason: .ambiguousAuthority
                )
            )
        }

        let projectionMetadata = metadata(
            scope: .product(request.candidateProductID),
            freshness: .current,
            provenances: [.targetProductState]
        )
        return .projection(
            ProductStateAcquisitionMatchProjection(
                match: match,
                matchedEvidence: matchedEvidence,
                metadata: projectionMetadata
            )
        )
    }

    func namedList(
        _ request: ProductStateListScopeRequest
    ) -> ProductStateProjectionOutcome<ProductStateNamedListProjection> {
        let listSnapshot: ListSnapshot
        switch loadList(request) {
        case let .success(value): listSnapshot = value
        case let .failure(value): return .unavailable(value)
        }

        let rows: [WayTaskSchemaV4.ShoppingListEntry]
        do {
            rows = try shopping.shoppingEntries(
                listID: request.listID.rawValue
            )
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .list(request.listID),
                    reason: .repositoryReadFailed,
                    listRevision: listSnapshot.revision
                )
            )
        }

        var needed: [ProductStateListEntryProjection] = []
        var resolved: [ProductStateListEntryProjection] = []
        var unresolved: [ProductStateListEntryProjection] = []
        var omissions: [ProductStateProjectionOmission] = []

        for row in rows.sorted(by: entryLess) {
            let projected = projectEntry(
                row,
                requiredListID: request.listID
            )
            omissions.append(contentsOf: projected.omissions)
            switch projected.entry.state {
            case .needed: needed.append(projected.entry)
            case .resolved: resolved.append(projected.entry)
            case .unresolved: unresolved.append(projected.entry)
            }
        }

        let projectionMetadata = metadata(
            scope: .list(request.listID),
            freshness: listSnapshot.freshness,
            listRevision: listSnapshot.revision,
            provenances: [.targetProductState],
            omissions: canonicalOmissions(omissions)
        )
        return .projection(
            ProductStateNamedListProjection(
                id: request.listID,
                revision: listSnapshot.revision,
                title: listSnapshot.title,
                purposeRawValue: listSnapshot.purposeRawValue,
                neededEntries: needed,
                resolvedEntries: resolved,
                unresolvedEntries: unresolved,
                createdAt: listSnapshot.createdAt,
                updatedAt: listSnapshot.updatedAt,
                metadata: projectionMetadata
            )
        )
    }

    func membership(
        productID: ProductStateProductID,
        listScope: ProductStateListScopeRequest
    ) -> ProductStateProjectionOutcome<ProductStateMembershipProjection> {
        let productRows: [WayTaskSchemaV4.Product]
        do {
            productRows = try products.products(id: productID.rawValue)
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(productID),
                    reason: .repositoryReadFailed
                )
            )
        }
        guard productRows.count == 1,
              let product = productRows.first.flatMap(mapProduct) else {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(productID),
                    reason: productRows.isEmpty ? .notFound :
                        .ambiguousAuthority
                )
            )
        }

        let listSnapshot: ListSnapshot
        switch loadList(listScope) {
        case let .success(value): listSnapshot = value
        case let .failure(value): return .unavailable(value)
        }
        switch membershipProjection(product: product, list: listSnapshot) {
        case let .success(value), let .failure(value):
            return .projection(value)
        }
    }

    func planInput(
        _ request: ProductStatePlanInputRequest
    ) -> ProductStateProjectionOutcome<ProductStatePlanInputProjection> {
        guard !request.declaredInputFingerprint.isEmpty else {
            return .unavailable(
                unavailableMetadata(
                    scope: .list(request.listScope.listID),
                    reason: .invalidRequest
                )
            )
        }
        let listResult = namedList(request.listScope)
        guard case let .projection(list) = listResult else {
            if case let .unavailable(value) = listResult {
                return .unavailable(value)
            }
            return .unavailable(
                unavailableMetadata(
                    scope: .list(request.listScope.listID),
                    reason: .repositoryReadFailed
                )
            )
        }
        return .projection(makePlanInput(request, list: list))
    }

    func listParity(
        _ request: ProductStatePlanInputRequest
    ) -> ProductStateProjectionOutcome<ProductStateListParityProjection> {
        guard !request.declaredInputFingerprint.isEmpty else {
            return .unavailable(
                unavailableMetadata(
                    scope: .list(request.listScope.listID),
                    reason: .invalidRequest
                )
            )
        }
        let listResult = namedList(request.listScope)
        guard case let .projection(list) = listResult else {
            if case let .unavailable(value) = listResult {
                return .unavailable(value)
            }
            return .unavailable(
                unavailableMetadata(
                    scope: .list(request.listScope.listID),
                    reason: .repositoryReadFailed
                )
            )
        }
        let input = makePlanInput(request, list: list)
        let map = mapContext(list: list)
        let notification = notificationOpportunity(list: list)
        return .projection(
            ProductStateListParityProjection(
                namedList: list,
                planInput: input,
                mapContext: map,
                notificationOpportunity: notification
            )
        )
    }

    func planStatus(
        _ request: ProductStatePlanStatusRequest
    ) -> ProductStatePlanStatusProjection {
        var stale: [ShoppingPlanStaleReason] = []
        if request.plan.sourceListID != request.currentInput.listID {
            stale.append(.sourceRevisionChanged)
        }
        if request.plan.sourceRevision != request.currentInput.revision {
            stale.append(.sourceRevisionChanged)
        }
        let currentEligible = Set(
            request.currentInput.eligibleEntries.map(\.identity.id)
        )
        let planIncluded = Set(
            request.plan.includedEntries.map(\.id)
        )
        if currentEligible != planIncluded {
            stale.append(.includedEntriesChanged)
        }
        if request.planInputFingerprint
            != request.currentInput.declaredInputFingerprint {
            stale.append(.planningInputChanged)
        }
        stale = Array(Set(stale)).sorted { $0.rawValue < $1.rawValue }

        let status: ShoppingPlanStatus
        if let first = stale.first {
            status = .stale(first)
        } else {
            status = request.plan.status
        }
        let freshness: ProductStateProjectionFreshness = stale.isEmpty
            ? request.currentInput.metadata.freshness
            : .stale(stale.map(projectionStaleReason))
        let projectionMetadata = metadata(
            scope: .plan(request.plan.id, request.plan.sourceListID),
            freshness: freshness,
            listRevision: request.currentInput.revision,
            provenances: [.targetProductState],
            omissions: request.currentInput.metadata.omissions
        )
        return ProductStatePlanStatusProjection(
            planID: request.plan.id,
            sourceListID: request.plan.sourceListID,
            sourceRevision: request.plan.sourceRevision,
            includedEntryIDs: request.plan.includedEntries.map(\.id),
            excludedEntryIDs: request.plan.exclusions.map(\.entry.id),
            status: status,
            staleReasons: stale,
            metadata: projectionMetadata
        )
    }

    func activeSessions() -> ProductStateProjectionOutcome<
        ProductStateActiveSessionLookupProjection
    > {
        let active: [WayTaskSchemaV4.ShoppingSession]
        let expired: [WayTaskSchemaV4.ShoppingSession]
        do {
            active = try sessions.shoppingSessions(lifecycle: .active)
            expired = try sessions.shoppingSessions(lifecycle: .expired)
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .sessions,
                    reason: .repositoryReadFailed
                )
            )
        }
        let rows = (active + expired).sorted(by: sessionLess)
        var seen: Set<UUID> = []
        var candidates: [ProductStateActiveSessionCandidateProjection] = []
        var omissions: [ProductStateProjectionOmission] = []
        for row in rows {
            guard seen.insert(row.id).inserted else {
                omissions.append(
                    omission(
                        .invalidSessionReference,
                        sessionID: ProductStateSessionID(rawValue: row.id)
                    )
                )
                continue
            }
            guard let lifecycle = ShoppingSessionLifecycle(
                rawValue: row.lifecycleRawValue
            ), !lifecycle.isTerminal,
            let migration = ShoppingSessionMigrationCondition(
                rawValue: row.migrationConditionRawValue
            ) else {
                omissions.append(
                    omission(
                        .invalidSessionReference,
                        sessionID: ProductStateSessionID(rawValue: row.id)
                    )
                )
                continue
            }
            candidates.append(
                ProductStateActiveSessionCandidateProjection(
                    sessionID: ProductStateSessionID(rawValue: row.id),
                    revision: ProductStateSessionRevision(
                        value: row.revision
                    ),
                    snapshotID: ProductStateSessionSnapshotID(
                        rawValue: row.snapshotID
                    ),
                    sourceListID: row.sourceListID.map(
                        ProductStateListID.init(rawValue:)
                    ),
                    sourceRevision: sourceRevision(row),
                    lifecycle: lifecycle,
                    migrationCondition: migration,
                    startedAt: row.startedAt
                )
            )
        }
        let projectionMetadata = metadata(
            scope: .sessions,
            freshness: .current,
            provenances: [.frozenSessionSnapshot],
            omissions: canonicalOmissions(omissions)
        )
        return .projection(
            ProductStateActiveSessionLookupProjection(
                candidates: candidates,
                requiresExplicitSelection: candidates.count > 1,
                metadata: projectionMetadata
            )
        )
    }

    func sessionSnapshot(
        _ request: ProductStateSessionSnapshotRequest
    ) -> ProductStateProjectionOutcome<
        ProductStateSessionSnapshotProjection
    > {
        let sessionRows: [WayTaskSchemaV4.ShoppingSession]
        do {
            sessionRows = try sessions.shoppingSessions(
                id: request.sessionID.rawValue
            )
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .session(request.sessionID),
                    reason: .repositoryReadFailed
                )
            )
        }
        guard sessionRows.count == 1, let row = sessionRows.first else {
            return .unavailable(
                unavailableMetadata(
                    scope: .session(request.sessionID),
                    reason: sessionRows.isEmpty ? .notFound :
                        .ambiguousAuthority
                )
            )
        }

        let lines: [WayTaskSchemaV4.ShoppingSessionLine]
        let stops: [WayTaskSchemaV4.ShoppingSessionStop]
        let exceptions: [WayTaskSchemaV4.ProductStateMigrationException]
        do {
            lines = try sessions.sessionLines(sessionID: row.id)
            stops = try sessions.sessionStops(sessionID: row.id)
            exceptions = try sessions.migrationExceptions(
                sessionID: row.id
            )
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .session(request.sessionID),
                    reason: .repositoryReadFailed,
                    sessionRevision: ProductStateSessionRevision(
                        value: row.revision
                    )
                )
            )
        }

        let projectedLines = lines.sorted(by: lineLess).map {
            projectSessionLine($0, session: row)
        }
        let projectedStops = stops.sorted(by: stopLess).map {
            projectSessionStop($0, session: row)
        }
        let projectedExceptions = exceptions.sorted(
            by: exceptionLess
        ).map(projectSessionException)
        let omissions = sessionOmissions(
            projectedLines,
            stops: projectedStops,
            sessionID: request.sessionID
        )
        let revision = ProductStateSessionRevision(value: row.revision)
        let freshness: ProductStateProjectionFreshness
        if let expected = request.expectedRevision,
           expected != revision {
            freshness = .stale([.expectedSessionRevisionChanged])
        } else {
            freshness = .current
        }
        let projectionMetadata = metadata(
            scope: .session(request.sessionID),
            freshness: freshness,
            sessionRevision: revision,
            sessionSnapshotID: ProductStateSessionSnapshotID(
                rawValue: row.snapshotID
            ),
            provenances: [.frozenSessionSnapshot],
            omissions: canonicalOmissions(omissions)
        )
        return .projection(
            ProductStateSessionSnapshotProjection(
                id: request.sessionID,
                revision: revision,
                lifecycle: ShoppingSessionLifecycle(
                    rawValue: row.lifecycleRawValue
                ),
                lifecycleRawValue: row.lifecycleRawValue,
                migrationCondition: ShoppingSessionMigrationCondition(
                    rawValue: row.migrationConditionRawValue
                ),
                migrationConditionRawValue: row.migrationConditionRawValue,
                snapshotID: ProductStateSessionSnapshotID(
                    rawValue: row.snapshotID
                ),
                snapshotVersion: row.snapshotVersion,
                snapshotGeneration: row.snapshotGeneration,
                snapshotContentSignature: row.snapshotContentSignature,
                sourceListID: row.sourceListID.map(
                    ProductStateListID.init(rawValue:)
                ),
                sourceRevision: sourceRevision(row),
                sourcePlanID: row.sourcePlanID.map(
                    ProductStatePlanID.init(rawValue:)
                ),
                sourcePlanSignature: row.sourcePlanSignature,
                sourcePlanEvidenceAt: row.sourcePlanEvidenceAt,
                stops: projectedStops,
                lines: projectedLines,
                exceptions: projectedExceptions,
                metadata: projectionMetadata
            )
        )
    }

    func finishReview(
        _ request: ProductStateFinishReviewRequest
    ) -> ProductStateProjectionOutcome<ProductStateFinishReviewProjection> {
        let snapshotResult = sessionSnapshot(request.session)
        guard case let .projection(snapshot) = snapshotResult else {
            if case let .unavailable(value) = snapshotResult {
                return .unavailable(value)
            }
            return .unavailable(
                unavailableMetadata(
                    scope: .session(request.session.sessionID),
                    reason: .repositoryReadFailed
                )
            )
        }

        var reviewLines: [ProductStateFinishReviewLineProjection] = []
        var missing: [ProductStateSessionLineID] = []
        var invalid: [ProductStateSessionLineID] = []
        let knownLineIDs = Set(snapshot.lines.map(\.id))
        for line in snapshot.lines {
            let outcome = request.proposedOutcomes[line.id]
            if outcome == nil { missing.append(line.id) }
            let valid = line.qualification == .qualified
                && line.productID != nil
                && line.sourceEntryID != nil
                && line.legacyDisposition == nil
            if !valid { invalid.append(line.id) }
            reviewLines.append(
                ProductStateFinishReviewLineProjection(
                    line: line,
                    proposedOutcome: outcome,
                    isValid: valid
                )
            )
        }
        if request.proposedOutcomes.keys.contains(where: {
            !knownLineIDs.contains($0)
        }) {
            invalid.append(contentsOf: request.proposedOutcomes.keys.filter {
                !knownLineIDs.contains($0)
            })
        }
        invalid = Array(Set(invalid)).sorted(by: lineIDLess)

        var sourceConflict = false
        var currentListRevision = exactListRevision(snapshot.sourceRevision)
        let historicalRevision = exactListRevision(snapshot.sourceRevision)
        if let listID = snapshot.sourceListID,
           let expectedRevision = request.expectedCurrentListRevision
                ?? historicalRevision {
            switch loadList(
                ProductStateListScopeRequest(
                    listID: listID,
                    expectedRevision: expectedRevision
                )
            ) {
            case let .success(list):
                sourceConflict = list.freshness != .current
                currentListRevision = list.revision
                if !sourceConflict,
                   request.expectedCurrentListRevision != nil {
                    do {
                        for line in snapshot.lines {
                            guard let entryID = line.sourceEntryID,
                                  let productID = line.productID
                            else {
                                sourceConflict = true
                                break
                            }
                            let entries = try shopping.shoppingEntries(
                                id: entryID.rawValue,
                                listID: listID.rawValue
                            ).filter {
                                $0.productID == productID.rawValue
                                    && $0.lifecycleRawValue == "needed"
                            }
                            let productRows = try products.products(
                                id: productID.rawValue
                            ).filter {
                                $0.libraryLifecycleRawValue
                                    == ProductLibraryLifecycle.active.rawValue
                            }
                            if entries.count != 1 || productRows.count != 1 {
                                sourceConflict = true
                                break
                            }
                        }
                    } catch {
                        sourceConflict = true
                    }
                }
            case .failure:
                sourceConflict = true
            }
        } else {
            sourceConflict = true
        }

        let status: ProductStateFinishReviewStatus
        if snapshot.lifecycle != .active {
            status = .invalidSession
        } else if sourceConflict {
            status = .sourceConflict
        } else if !missing.isEmpty || !invalid.isEmpty {
            status = .incomplete
        } else {
            status = .ready
        }
        var freshness = snapshot.metadata.freshness
        if sourceConflict {
            freshness = .stale([.sourceRevisionChanged])
        }
        let projectionMetadata = metadata(
            scope: .session(snapshot.id),
            freshness: freshness,
            listRevision: currentListRevision,
            sessionRevision: snapshot.revision,
            sessionSnapshotID: snapshot.snapshotID,
            provenances: [.frozenSessionSnapshot],
            omissions: snapshot.metadata.omissions
        )
        return .projection(
            ProductStateFinishReviewProjection(
                sessionID: snapshot.id,
                sessionRevision: snapshot.revision,
                lines: reviewLines,
                missingOutcomeLineIDs: missing.sorted(by: lineIDLess),
                invalidLineIDs: invalid,
                status: status,
                metadata: projectionMetadata
            )
        )
    }

    func catalogLinkedProduct(
        productID: ProductStateProductID,
        catalogEvidence: ProductStatePublishedCatalogEvidence?
    ) -> ProductStateProjectionOutcome<
        ProductStateCatalogLinkedProductProjection
    > {
        let rows: [WayTaskSchemaV4.Product]
        do {
            rows = try products.products(id: productID.rawValue)
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(productID),
                    reason: .repositoryReadFailed
                )
            )
        }
        guard rows.count == 1, let product = rows.first.flatMap(mapProduct)
        else {
            return .unavailable(
                unavailableMetadata(
                    scope: .product(productID),
                    reason: rows.isEmpty ? .notFound : .ambiguousAuthority
                )
            )
        }

        let linkedID = product.catalogID
        let status: ProductStateCatalogPublicationStatus
        let name: String
        let categoryID: String?
        let categoryName: String?
        let iconKey: String?
        let locale: String?
        let provenances: [ProductStateProjectionProvenance]

        if linkedID == nil {
            status = .unlinked
            name = product.displayName
            categoryID = product.catalogCategoryIDSnapshot
            categoryName = product.catalogCategoryDisplayNameSnapshot
            iconKey = product.catalogIconKeySnapshot
            locale = product.catalogDisplayLocaleSnapshot
            provenances = [.targetProductState]
        } else if let evidence = catalogEvidence,
                  evidence.catalogID == linkedID {
            status = .current
            name = evidence.displayName
            categoryID = evidence.categoryID
            categoryName = evidence.categoryDisplayName
            iconKey = evidence.iconKey
            locale = evidence.locale
            provenances = [
                .targetProductState,
                .publishedCatalog(version: evidence.version)
            ]
        } else if let evidence = catalogEvidence,
                  let linkedID,
                  evidence.redirectsFrom.contains(linkedID) {
            status = .redirected(from: linkedID)
            name = evidence.displayName
            categoryID = evidence.categoryID
            categoryName = evidence.categoryDisplayName
            iconKey = evidence.iconKey
            locale = evidence.locale
            provenances = [
                .targetProductState,
                .publishedCatalog(version: evidence.version)
            ]
        } else if catalogEvidence == nil {
            status = .offlineSnapshot
            name = product.catalogDisplayNameSnapshot
                ?? product.displayName
            categoryID = product.catalogCategoryIDSnapshot
            categoryName = product.catalogCategoryDisplayNameSnapshot
            iconKey = product.catalogIconKeySnapshot
            locale = product.catalogDisplayLocaleSnapshot
            provenances = [.targetProductState]
        } else {
            status = .mismatchedEvidence
            name = product.catalogDisplayNameSnapshot
                ?? product.displayName
            categoryID = product.catalogCategoryIDSnapshot
            categoryName = product.catalogCategoryDisplayNameSnapshot
            iconKey = product.catalogIconKeySnapshot
            locale = product.catalogDisplayLocaleSnapshot
            provenances = [.targetProductState]
        }

        let freshness: ProductStateProjectionFreshness =
            status == .mismatchedEvidence
            ? .stale([.sourceIdentityChanged]) : .current
        let projectionMetadata = metadata(
            scope: .product(productID),
            freshness: freshness,
            provenances: provenances
        )
        return .projection(
            ProductStateCatalogLinkedProductProjection(
                product: product,
                status: status,
                displayedName: name,
                displayedCategoryID: categoryID,
                displayedCategoryName: categoryName,
                displayedIconKey: iconKey,
                displayedLocale: locale,
                metadata: projectionMetadata
            )
        )
    }

    func knowledgeSearch(
        _ request: ProductStateKnowledgeSearchRequest,
        candidates: [ProductStateKnowledgeCandidateInput]
    ) -> ProductStateProjectionOutcome<
        ProductStateKnowledgeSearchProjection
    > {
        guard request.maximumCandidateCount >= 0,
              !request.inputFingerprint.isEmpty,
              !request.publicationVersion.isEmpty else {
            return .unavailable(
                unavailableMetadata(
                    scope: .knowledge(
                        inputFingerprint: request.inputFingerprint
                    ),
                    reason: .invalidRequest
                )
            )
        }
        let ordered = candidates.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if $0.evidenceID != $1.evidenceID {
                return uuidLess($0.evidenceID, $1.evidenceID)
            }
            if $0.displayNameSnapshot != $1.displayNameSnapshot {
                return $0.displayNameSnapshot < $1.displayNameSnapshot
            }
            return $0.provenanceRawValue < $1.provenanceRawValue
        }
        let bounded = ordered.prefix(request.maximumCandidateCount).map {
            ProductStateKnowledgeCandidateProjection(
                evidenceID: $0.evidenceID,
                productID: request.productID,
                displayNameSnapshot: $0.displayNameSnapshot,
                confidence: $0.confidence,
                provenanceRawValue: $0.provenanceRawValue
            )
        }
        let projectionMetadata = metadata(
            scope: request.productID.map(ProductStateProjectionScope.product)
                ?? .knowledge(inputFingerprint: request.inputFingerprint),
            freshness: .current,
            provenances: [
                .publishedProductKnowledge(
                    version: request.publicationVersion
                )
            ]
        )
        return .projection(
            ProductStateKnowledgeSearchProjection(
                explicitProductID: request.productID,
                candidates: Array(bounded),
                omittedCandidateCount: ordered.count - bounded.count,
                metadata: projectionMetadata
            )
        )
    }

    func mapContext(
        list: ProductStateNamedListProjection
    ) -> ProductStateMapShoppingContextProjection {
        let items = list.neededEntries.map(contextItem)
        return ProductStateMapShoppingContextProjection(
            owner: .list(list.id, list.revision),
            items: items,
            metadata: metadata(
                scope: .list(list.id),
                freshness: list.metadata.freshness,
                listRevision: list.revision,
                provenances: [.targetProductState],
                omissions: list.metadata.omissions
            )
        )
    }

    func mapContext(
        planInput: ProductStatePlanInputProjection,
        status: ProductStatePlanStatusProjection
    ) -> ProductStateMapShoppingContextProjection {
        let items = planInput.eligibleEntries.map(contextItem)
        return ProductStateMapShoppingContextProjection(
            owner: .plan(
                status.planID,
                status.sourceListID,
                status.sourceRevision
            ),
            items: items,
            metadata: metadata(
                scope: .plan(status.planID, status.sourceListID),
                freshness: status.metadata.freshness,
                listRevision: planInput.revision,
                provenances: [.targetProductState],
                omissions: canonicalOmissions(
                    planInput.metadata.omissions
                        + status.metadata.omissions
                )
            )
        )
    }

    func mapContext(
        session: ProductStateSessionSnapshotProjection
    ) -> ProductStateMapShoppingContextProjection {
        let items = session.lines.map(contextItem)
        return ProductStateMapShoppingContextProjection(
            owner: .session(
                session.id,
                session.revision,
                session.snapshotID
            ),
            items: items,
            metadata: metadata(
                scope: .session(session.id),
                freshness: session.metadata.freshness,
                sessionRevision: session.revision,
                sessionSnapshotID: session.snapshotID,
                provenances: [.frozenSessionSnapshot],
                omissions: session.metadata.omissions
            )
        )
    }

    func notificationOpportunity(
        list: ProductStateNamedListProjection
    ) -> ProductStateNotificationOpportunityProjection {
        notificationOpportunity(from: mapContext(list: list))
    }

    func notificationOpportunity(
        planInput: ProductStatePlanInputProjection,
        status: ProductStatePlanStatusProjection
    ) -> ProductStateNotificationOpportunityProjection {
        notificationOpportunity(
            from: mapContext(planInput: planInput, status: status)
        )
    }

    func notificationOpportunity(
        session: ProductStateSessionSnapshotProjection
    ) -> ProductStateNotificationOpportunityProjection {
        notificationOpportunity(from: mapContext(session: session))
    }

    func notificationRoute(
        _ owner: ProductStateNotificationPayloadOwner,
        currentPlanStatus: ProductStatePlanStatusProjection? = nil
    ) -> ProductStateNotificationRouteProjection {
        switch owner {
        case let .list(listID, revision):
            switch loadList(
                ProductStateListScopeRequest(
                    listID: listID,
                    expectedRevision: revision
                )
            ) {
            case let .success(list):
                let route: ProductStateNotificationRoute =
                    list.freshness == .current
                    ? .namedList(listID)
                    : .safeShopping(.sourceRevisionChanged)
                return ProductStateNotificationRouteProjection(
                    payloadOwner: owner,
                    route: route,
                    metadata: metadata(
                        scope: .list(listID),
                        freshness: list.freshness,
                        listRevision: list.revision,
                        provenances: [.targetProductState]
                    )
                )
            case let .failure(value):
                return ProductStateNotificationRouteProjection(
                    payloadOwner: owner,
                    route: .suppressed(.notFound),
                    metadata: value
                )
            }
        case let .plan(planID, listID, revision):
            guard let status = currentPlanStatus,
                  status.planID == planID,
                  status.sourceListID == listID else {
                return ProductStateNotificationRouteProjection(
                    payloadOwner: owner,
                    route: .suppressed(.notFound),
                    metadata: unavailableMetadata(
                        scope: .plan(planID, listID),
                        reason: .notFound,
                        listRevision: revision
                    )
                )
            }
            let isCurrent = status.sourceRevision == revision
                && status.metadata.freshness == .current
                && status.status == .ready
            return ProductStateNotificationRouteProjection(
                payloadOwner: owner,
                route: isCurrent
                    ? .namedList(listID)
                    : .safeShopping(.sourceRevisionChanged),
                metadata: metadata(
                    scope: .plan(planID, listID),
                    freshness: isCurrent
                        ? .current : .stale([.sourceRevisionChanged]),
                    listRevision: status.sourceRevision,
                    provenances: [.targetProductState]
                )
            )
        case let .session(sessionID, revision, snapshotID):
            let result = sessionSnapshot(
                ProductStateSessionSnapshotRequest(
                    sessionID: sessionID,
                    expectedRevision: revision
                )
            )
            guard case let .projection(snapshot) = result else {
                let metadata: ProductStateProjectionMetadata
                if case let .unavailable(value) = result {
                    metadata = value
                } else {
                    metadata = unavailableMetadata(
                        scope: .session(sessionID),
                        reason: .notFound
                    )
                }
                return ProductStateNotificationRouteProjection(
                    payloadOwner: owner,
                    route: .suppressed(.notFound),
                    metadata: metadata
                )
            }
            let isCurrent = snapshot.snapshotID == snapshotID
                && snapshot.revision == revision
                && snapshot.lifecycle == .active
            let staleReason: ProductStateProjectionStaleReason =
                snapshot.snapshotID == snapshotID
                ? .sourceRevisionChanged : .snapshotChanged
            return ProductStateNotificationRouteProjection(
                payloadOwner: owner,
                route: isCurrent
                    ? .session(sessionID)
                    : .safeShopping(staleReason),
                metadata: metadata(
                    scope: .session(sessionID),
                    freshness: isCurrent
                        ? .current : .stale([staleReason]),
                    sessionRevision: snapshot.revision,
                    sessionSnapshotID: snapshot.snapshotID,
                    provenances: [.frozenSessionSnapshot],
                    omissions: snapshot.metadata.omissions
                )
            )
        }
    }

    func savedLocationEvidence(
        _ input: ProductStateSavedLocationEvidenceInput
    ) -> ProductStateProjectionOutcome<
        ProductStateSavedLocationEvidenceProjection
    > {
        let sorted = input.links.sorted(by: locationLinkLess)
        var links: [ProductStateSavedLocationLinkProjection] = []
        do {
            for link in sorted {
                let isExact: Bool
                if link.authority == .exactTargetReference,
                   let productID = link.productID,
                   let listID = link.listID,
                   let entryID = link.entryID {
                    let productRows = try products.products(
                        id: productID.rawValue
                    )
                    let listRows = try shopping.shoppingLists(
                        id: listID.rawValue
                    )
                    let entryRows = try shopping.shoppingEntries(
                        id: entryID.rawValue,
                        listID: listID.rawValue
                    )
                    isExact = productRows.count == 1
                        && productRows.first?.id == productID.rawValue
                        && listRows.count == 1
                        && listRows.first?.id == listID.rawValue
                        && entryRows.count == 1
                        && entryRows.first?.id == entryID.rawValue
                        && entryRows.first?.productID == productID.rawValue
                } else {
                    isExact = false
                }
                links.append(
                    ProductStateSavedLocationLinkProjection(
                        productID: link.productID,
                        listID: link.listID,
                        entryID: link.entryID,
                        authority: link.authority,
                        isAuthoritativeProductStateLink: isExact
                    )
                )
            }
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .location(input.locationID),
                    reason: .repositoryReadFailed
                )
            )
        }
        let omissions = links.filter {
            !$0.isAuthoritativeProductStateLink
        }.map {
            omission(
                .unprovenLocationLink,
                productID: $0.productID,
                listID: $0.listID,
                entryID: $0.entryID
            )
        }
        return .projection(
            ProductStateSavedLocationEvidenceProjection(
                locationID: input.locationID,
                displayNameSnapshot: input.displayNameSnapshot,
                noteSnapshot: input.noteSnapshot,
                latitude: input.latitude,
                longitude: input.longitude,
                links: links,
                metadata: metadata(
                    scope: .location(input.locationID),
                    freshness: .current,
                    provenances: [
                        .savedLocationEvidence(
                            version: input.evidenceVersion
                        )
                    ],
                    omissions: canonicalOmissions(omissions)
                )
            )
        )
    }

    func discoveryContext(
        _ context: ProductStateMapShoppingContextProjection
    ) -> ProductStateDiscoveryContextProjection {
        let eligible = Array(
            Set(context.items.compactMap {
                $0.isQualified ? $0.productID : nil
            })
        ).sorted(by: productIDLess)
        let unresolved = context.items.filter {
            !$0.isQualified || $0.productID == nil
        }
        return ProductStateDiscoveryContextProjection(
            owner: context.owner,
            eligibleProductIDs: eligible,
            unresolvedItems: unresolved,
            metadata: context.metadata
        )
    }

    func storeRecommendations(
        context: ProductStateDiscoveryContextProjection,
        evidence: [ProductStatePublishedStoreEvidence]
    ) -> ProductStateStoreRecommendationsProjection {
        let required = Set(context.eligibleProductIDs)
        let recommendations = evidence.map { value in
            let covered = required.intersection(value.coveredProductIDs)
            let uncovered = required.subtracting(value.coveredProductIDs)
            return ProductStateStoreRecommendationProjection(
                storeID: value.storeID,
                estimatedCoveredProductIDs: covered.sorted(
                    by: productIDLess
                ),
                uncoveredProductIDs: uncovered.sorted(by: productIDLess),
                confidence: value.confidence,
                evidenceAt: value.evidenceAt
            )
        }.sorted {
            if $0.estimatedCoveredProductIDs.count
                != $1.estimatedCoveredProductIDs.count {
                return $0.estimatedCoveredProductIDs.count
                    > $1.estimatedCoveredProductIDs.count
            }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if $0.storeID != $1.storeID {
                return $0.storeID < $1.storeID
            }
            if $0.evidenceAt != $1.evidenceAt {
                return $0.evidenceAt < $1.evidenceAt
            }
            let lhsCoverage = $0.estimatedCoveredProductIDs.map {
                $0.rawValue.uuidString
            }.joined(separator: "|")
            let rhsCoverage = $1.estimatedCoveredProductIDs.map {
                $0.rawValue.uuidString
            }.joined(separator: "|")
            return lhsCoverage < rhsCoverage
        }
        let versions = Array(Set(evidence.map(\.publicationVersion)))
            .sorted()
        let provenances = versions.map {
            ProductStateProjectionProvenance.publishedStoreEvidence(
                version: $0
            )
        }
        return ProductStateStoreRecommendationsProjection(
            owner: context.owner,
            recommendations: recommendations,
            metadata: metadata(
                scope: scope(context.owner),
                freshness: context.metadata.freshness,
                listRevision: context.metadata.listRevision,
                sessionRevision: context.metadata.sessionRevision,
                sessionSnapshotID: context.metadata.sessionSnapshotID,
                provenances: context.metadata.provenances + provenances,
                omissions: context.metadata.omissions
            )
        )
    }

    func migrationRecovery(
        _ input: ProductStateMigrationRecoveryInput
    ) -> ProductStateProjectionOutcome<
        ProductStateMigrationRecoveryProjection
    > {
        let lookupResult = activeSessions()
        guard case let .projection(lookup) = lookupResult else {
            if case let .unavailable(value) = lookupResult {
                return .unavailable(value)
            }
            return .unavailable(
                unavailableMetadata(
                    scope: .migration(version: input.migrationVersion),
                    reason: .repositoryReadFailed
                )
            )
        }

        var exceptions = input.exceptionLedger
        do {
            for candidate in lookup.candidates {
                let rows = try sessions.migrationExceptions(
                    sessionID: candidate.sessionID.rawValue
                )
                exceptions.append(
                    contentsOf: rows.map(projectSessionException)
                )
            }
        } catch {
            return .unavailable(
                unavailableMetadata(
                    scope: .migration(version: input.migrationVersion),
                    reason: .repositoryReadFailed
                )
            )
        }
        exceptions.sort(by: exceptionProjectionLess)

        let availability: ProductStateTargetWriteAvailability
        let freshness: ProductStateProjectionFreshness
        if !input.semanticMigrationComplete {
            availability = .blockedMigrationIncomplete
            freshness = .unavailable(.migrationIncomplete)
        } else if !input.invariantsValid {
            availability = .blockedInvariantFailure
            freshness = .unavailable(.invariantFailure)
        } else {
            availability = .available
            freshness = .current
        }
        let projectionMetadata = metadata(
            scope: .migration(version: input.migrationVersion),
            freshness: freshness,
            provenances: [
                .migrationRecovery(version: input.migrationVersion),
                .frozenSessionSnapshot
            ],
            omissions: lookup.metadata.omissions
        )
        return .projection(
            ProductStateMigrationRecoveryProjection(
                migrationVersion: input.migrationVersion,
                targetWriteAvailability: availability,
                sessionCandidates: lookup.candidates,
                exceptions: exceptions,
                metadata: projectionMetadata
            )
        )
    }

    // MARK: Pure/scoped builders

    private func makePlanInput(
        _ request: ProductStatePlanInputRequest,
        list: ProductStateNamedListProjection
    ) -> ProductStatePlanInputProjection {
        var eligible: [ProductStateListEntryProjection] = []
        var excluded: [ProductStatePlanInputExclusionProjection] = []
        var omissions = list.metadata.omissions

        for entry in list.neededEntries {
            let reason: ProductStatePlanInputExclusionReason?
            if request.explicitlyExcludedEntryIDs.contains(
                entry.identity.id
            ) {
                reason = .explicitUserExclusion
            } else if entry.issues.contains(.missingProduct) {
                reason = .missingProduct
            } else if entry.issues.contains(.ambiguousProduct) {
                reason = .ambiguousProduct
            } else if entry.issues.contains(.removedProduct) {
                reason = .removedProduct
            } else if !entry.issues.isEmpty || entry.product == nil {
                reason = .malformedEntry
            } else {
                reason = nil
            }

            if let reason {
                excluded.append(
                    ProductStatePlanInputExclusionProjection(
                        entry: entry,
                        reason: reason
                    )
                )
                omissions.append(
                    omission(
                        reason == .explicitUserExclusion
                            ? .explicitExclusion : .unsupportedEvidence,
                        productID: entry.identity.productID,
                        listID: entry.identity.listID,
                        entryID: entry.identity.id
                    )
                )
            } else {
                eligible.append(entry)
            }
        }
        return ProductStatePlanInputProjection(
            listID: list.id,
            revision: list.revision,
            eligibleEntries: eligible,
            exclusions: excluded,
            allNeededEntryIDs: list.neededEntryIDs,
            declaredInputFingerprint: request.declaredInputFingerprint,
            metadata: metadata(
                scope: .list(list.id),
                freshness: list.metadata.freshness,
                listRevision: list.revision,
                provenances: [.targetProductState],
                omissions: canonicalOmissions(omissions)
            )
        )
    }

    private func notificationOpportunity(
        from context: ProductStateMapShoppingContextProjection
    ) -> ProductStateNotificationOpportunityProjection {
        ProductStateNotificationOpportunityProjection(
            owner: context.owner,
            items: context.items,
            metadata: context.metadata
        )
    }

    private func contextItem(
        _ entry: ProductStateListEntryProjection
    ) -> ProductStateShoppingContextItemProjection {
        ProductStateShoppingContextItemProjection(
            productID: entry.identity.productID,
            entryID: entry.identity.id,
            sessionLineID: nil,
            displayNameSnapshot: entry.product?.displayName,
            isQualified: entry.product != nil && entry.issues.isEmpty
        )
    }

    private func contextItem(
        _ line: ProductStateSessionLineProjection
    ) -> ProductStateShoppingContextItemProjection {
        ProductStateShoppingContextItemProjection(
            productID: line.productID,
            entryID: line.sourceEntryID,
            sessionLineID: line.id,
            displayNameSnapshot: line.productNameSnapshot,
            isQualified: line.qualification == .qualified
        )
    }

    // MARK: Repository mapping

    private func loadList(
        _ request: ProductStateListScopeRequest
    ) -> ListLoad {
        let rows: [WayTaskSchemaV4.ShoppingList]
        do {
            rows = try shopping.shoppingLists(id: request.listID.rawValue)
        } catch {
            return .failure(
                unavailableMetadata(
                    scope: .list(request.listID),
                    reason: .repositoryReadFailed
                )
            )
        }
        guard rows.count == 1, let row = rows.first else {
            return .failure(
                unavailableMetadata(
                    scope: .list(request.listID),
                    reason: rows.isEmpty ? .notFound : .ambiguousAuthority
                )
            )
        }
        let revision = ProductStateListRevision(value: row.revision)
        let freshness: ProductStateProjectionFreshness
        if let expected = request.expectedRevision, expected != revision {
            freshness = .stale([.expectedListRevisionChanged])
        } else {
            freshness = .current
        }
        return .success(
            ListSnapshot(
                id: request.listID,
                revision: revision,
                title: row.title,
                purposeRawValue: row.purposeRawValue,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                freshness: freshness
            )
        )
    }

    private func membershipProjection(
        product: ProductStateProductProjection,
        list: ListSnapshot
    ) -> MembershipBuild {
        let rows: [WayTaskSchemaV4.ShoppingListEntry]
        do {
            rows = try shopping.shoppingEntries(
                listID: list.id.rawValue,
                productID: product.id.rawValue
            )
        } catch {
            let value = ProductStateMembershipProjection(
                productID: product.id,
                listID: list.id,
                listRevision: list.revision,
                state: .absent,
                permittedActions: [],
                metadata: unavailableMetadata(
                    scope: .list(list.id),
                    reason: .repositoryReadFailed,
                    listRevision: list.revision
                )
            )
            return .failure(value)
        }

        let state: ProductStateMembershipState
        let actions: [ProductStateMembershipAction]
        var omissions: [ProductStateProjectionOmission] = []
        if rows.isEmpty {
            state = .absent
            actions = product.libraryLifecycle == .active
                ? [.add] : [.restoreProduct]
        } else if rows.count > 1 {
            let ids = rows.map {
                ProductStateListEntryID(rawValue: $0.id)
            }.sorted(by: entryIDLess)
            state = .ambiguous(ids)
            actions = []
            omissions.append(
                omission(
                    .ambiguousProduct,
                    productID: product.id,
                    listID: list.id
                )
            )
        } else if let row = rows.first {
            let id = ProductStateListEntryID(rawValue: row.id)
            switch row.lifecycleRawValue {
            case "needed":
                state = .needed(id)
                actions = [.resolve, .remove]
            case "resolved":
                state = .resolved(
                    entryID: id,
                    reason: row.resolutionReasonRawValue.flatMap(
                        ShoppingListResolutionReason.init(rawValue:)
                    ),
                    effectiveAt: row.resolutionEffectiveAt
                )
                actions = [.reopen, .remove]
            default:
                state = .unresolved(
                    id,
                    rawState: row.lifecycleRawValue
                )
                actions = []
                omissions.append(
                    omission(
                        .malformedEntryState,
                        productID: product.id,
                        listID: list.id,
                        entryID: id
                    )
                )
            }
        } else {
            state = .absent
            actions = []
        }
        let value = ProductStateMembershipProjection(
            productID: product.id,
            listID: list.id,
            listRevision: list.revision,
            state: state,
            permittedActions: actions,
            metadata: metadata(
                scope: .list(list.id),
                freshness: list.freshness,
                listRevision: list.revision,
                provenances: [.targetProductState],
                omissions: omissions
            )
        )
        return .success(value)
    }

    private func projectEntry(
        _ row: WayTaskSchemaV4.ShoppingListEntry,
        requiredListID: ProductStateListID
    ) -> (
        entry: ProductStateListEntryProjection,
        omissions: [ProductStateProjectionOmission]
    ) {
        let identity = ProductStateListEntryIdentity(
            id: ProductStateListEntryID(rawValue: row.id),
            listID: ProductStateListID(rawValue: row.shoppingListID),
            productID: ProductStateProductID(rawValue: row.productID)
        )
        var issues: [ProductStateProjectionOmissionReason] = []
        if row.shoppingListID != requiredListID.rawValue {
            issues.append(.invalidEntryScope)
        }
        let state: ProductStateListEntryProjectionState
        switch row.lifecycleRawValue {
        case "needed":
            state = .needed
        case "resolved":
            let reason = row.resolutionReasonRawValue.flatMap(
                ShoppingListResolutionReason.init(rawValue:)
            )
            if reason == nil || row.resolutionEffectiveAt == nil
                || row.resolutionProvenanceRawValue == nil {
                issues.append(.malformedEntryState)
            }
            state = .resolved(
                reason: reason,
                reasonRawValue: row.resolutionReasonRawValue,
                effectiveAt: row.resolutionEffectiveAt,
                provenanceRawValue: row.resolutionProvenanceRawValue,
                commandID: row.resolutionCommandID.map(
                    ProductStateCommandID.init(rawValue:)
                ),
                sessionID: row.resolutionSessionID.map(
                    ProductStateSessionID.init(rawValue:)
                ),
                sessionLineID: row.resolutionSessionLineID.map(
                    ProductStateSessionLineID.init(rawValue:)
                )
            )
        default:
            issues.append(.malformedEntryState)
            state = .unresolved(rawValue: row.lifecycleRawValue)
        }

        let productRows: [WayTaskSchemaV4.Product]
        do {
            productRows = try products.products(id: row.productID)
        } catch {
            productRows = []
            issues.append(.missingProduct)
        }
        let product: ProductStateProductProjection?
        if productRows.isEmpty {
            product = nil
            if !issues.contains(.missingProduct) {
                issues.append(.missingProduct)
            }
        } else if productRows.count > 1 {
            product = nil
            issues.append(.ambiguousProduct)
        } else if let mapped = productRows.first.flatMap(mapProduct) {
            product = mapped
            if mapped.libraryLifecycle == .removed {
                issues.append(.removedProduct)
            }
        } else {
            product = nil
            issues.append(.missingProduct)
        }
        issues = Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
        let omissions = issues.map {
            omission(
                $0,
                productID: identity.productID,
                listID: requiredListID,
                entryID: identity.id
            )
        }
        return (
            ProductStateListEntryProjection(
                identity: identity,
                state: state,
                quantity: row.quantity,
                unitRawValue: row.unitRawValue,
                note: row.note,
                sortOrder: row.sortOrder,
                product: product,
                issues: issues,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            ),
            omissions
        )
    }

    private func uniquelyScopedProducts(
        _ rows: [WayTaskSchemaV4.Product],
        lifecycle: ProductLibraryLifecycle
    ) -> (
        products: [ProductStateProductProjection],
        omissions: [ProductStateProjectionOmission]
    ) {
        let grouped = Dictionary(grouping: rows, by: \.id)
        var mapped: [ProductStateProductProjection] = []
        var omissions: [ProductStateProjectionOmission] = []
        for id in grouped.keys.sorted(by: uuidLess) {
            guard let values = grouped[id], values.count == 1,
                  let row = values.first,
                  let product = mapProduct(row),
                  product.libraryLifecycle == lifecycle else {
                omissions.append(
                    omission(
                        .ambiguousProduct,
                        productID: ProductStateProductID(rawValue: id)
                    )
                )
                continue
            }
            mapped.append(product)
        }
        mapped.sort(by: productLess)
        return (mapped, omissions)
    }

    private func mapProduct(
        _ row: WayTaskSchemaV4.Product
    ) -> ProductStateProductProjection? {
        guard let lifecycle = ProductLibraryLifecycle(
            rawValue: row.libraryLifecycleRawValue
        ) else { return nil }
        return ProductStateProductProjection(
            id: ProductStateProductID(rawValue: row.id),
            revision: row.revision,
            libraryLifecycle: lifecycle,
            libraryRemovedAt: row.libraryRemovedAt,
            displayName: row.name,
            brand: row.brand,
            category: row.category,
            barcode: row.barcode,
            catalogID: row.catalogProductIDRawValue.map(
                ProductStateCatalogID.init(rawValue:)
            ),
            catalogDisplayNameSnapshot: row.catalogDisplayNameSnapshot,
            catalogDisplayLocaleSnapshot:
                row.catalogDisplayLocaleSnapshot,
            catalogCategoryIDSnapshot:
                row.catalogCategoryIDSnapshotRawValue,
            catalogCategoryDisplayNameSnapshot:
                row.catalogCategoryDisplayNameSnapshot,
            catalogIconKeySnapshot: row.catalogIconKeySnapshot,
            catalogSnapshotUpdatedAt: row.catalogSnapshotUpdatedAt,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }

    private func projectSessionLine(
        _ line: WayTaskSchemaV4.ShoppingSessionLine,
        session: WayTaskSchemaV4.ShoppingSession
    ) -> ProductStateSessionLineProjection {
        let validReference = line.sessionID == session.id
            && line.snapshotID == session.snapshotID
        let resolvedIdentity = line.sourceListID != nil
            && line.sourceEntryID != nil
            && line.productID != nil
            && line.stopID != nil
        let qualification: ProductStateSessionRecordQualification
        if !validReference {
            qualification = .invalidReference
        } else if !resolvedIdentity
            || line.legacyDispositionRawValue != nil {
            qualification = .unresolved
        } else {
            qualification = .qualified
        }
        return ProductStateSessionLineProjection(
            id: ProductStateSessionLineID(rawValue: line.id),
            snapshotID: ProductStateSessionSnapshotID(
                rawValue: line.snapshotID
            ),
            sourceListID: line.sourceListID.map(
                ProductStateListID.init(rawValue:)
            ),
            sourceEntryID: line.sourceEntryID.map(
                ProductStateListEntryID.init(rawValue:)
            ),
            productID: line.productID.map(
                ProductStateProductID.init(rawValue:)
            ),
            stopID: line.stopID.map(
                ProductStateSessionStopID.init(rawValue:)
            ),
            sortOrder: line.sortOrder,
            productNameSnapshot: line.productNameSnapshot,
            productBrandSnapshot: line.productBrandSnapshot,
            productCategorySnapshot: line.productCategorySnapshot,
            quantitySnapshot: line.quantitySnapshot,
            unitSnapshotRawValue: line.unitSnapshotRawValue,
            noteSnapshot: line.noteSnapshot,
            executionState: ShoppingSessionExecutionState(
                rawValue: line.executionStateRawValue
            ),
            executionStateRawValue: line.executionStateRawValue,
            finalOutcome: line.finalOutcomeRawValue.flatMap(
                ShoppingSessionFinalOutcome.init(rawValue:)
            ),
            finalOutcomeRawValue: line.finalOutcomeRawValue,
            legacyDisposition: line.legacyDispositionRawValue.flatMap(
                ShoppingSessionLegacyDisposition.init(rawValue:)
            ),
            qualification: qualification
        )
    }

    private func projectSessionStop(
        _ stop: WayTaskSchemaV4.ShoppingSessionStop,
        session: WayTaskSchemaV4.ShoppingSession
    ) -> ProductStateSessionStopProjection {
        ProductStateSessionStopProjection(
            id: ProductStateSessionStopID(rawValue: stop.id),
            sortOrder: stop.sortOrder,
            storeReferenceID: stop.storeReferenceIDRawValue,
            storeReferenceProvenanceRawValue:
                stop.storeReferenceProvenanceRawValue,
            displayNameSnapshot: stop.displayNameSnapshot,
            latitudeSnapshot: stop.latitudeSnapshot,
            longitudeSnapshot: stop.longitudeSnapshot,
            evidenceAt: stop.evidenceAt,
            isSessionScopedTransient: stop.isSessionScopedTransient,
            qualification: stop.sessionID == session.id
                && stop.snapshotID == session.snapshotID
                ? .qualified : .invalidReference
        )
    }

    private func projectSessionException(
        _ value: WayTaskSchemaV4.ProductStateMigrationException
    ) -> ProductStateSessionExceptionProjection {
        ProductStateSessionExceptionProjection(
            id: value.id,
            sessionID: value.sessionID.map(
                ProductStateSessionID.init(rawValue:)
            ),
            sessionLineID: value.sessionLineID.map(
                ProductStateSessionLineID.init(rawValue:)
            ),
            categoryRawValue: value.categoryRawValue,
            safeEvidenceDigest: value.safeEvidenceDigest,
            ordinal: value.ordinal,
            occurrenceCount: value.occurrenceCount,
            recordedAt: value.recordedAt
        )
    }

    private func sessionOmissions(
        _ lines: [ProductStateSessionLineProjection],
        stops: [ProductStateSessionStopProjection],
        sessionID: ProductStateSessionID
    ) -> [ProductStateProjectionOmission] {
        let lineOmissions: [ProductStateProjectionOmission] =
            lines.compactMap { line in
            switch line.qualification {
            case .qualified: return nil
            case .unresolved:
                return omission(
                    .unresolvedSessionLine,
                    productID: line.productID,
                    listID: line.sourceListID,
                    entryID: line.sourceEntryID,
                    sessionID: sessionID,
                    sessionLineID: line.id
                )
            case .invalidReference:
                return omission(
                    .invalidSessionReference,
                    productID: line.productID,
                    listID: line.sourceListID,
                    entryID: line.sourceEntryID,
                    sessionID: sessionID,
                    sessionLineID: line.id
                )
            }
        }
        let stopOmissions: [ProductStateProjectionOmission] =
            stops.compactMap { stop in
            stop.qualification == .qualified ? nil : omission(
                .invalidSessionReference,
                sessionID: sessionID
            )
        }
        return lineOmissions + stopOmissions
    }

    // MARK: Deterministic metadata and ordering

    private func metadata(
        scope: ProductStateProjectionScope,
        freshness: ProductStateProjectionFreshness,
        listRevision: ProductStateListRevision? = nil,
        sessionRevision: ProductStateSessionRevision? = nil,
        sessionSnapshotID: ProductStateSessionSnapshotID? = nil,
        provenances: [ProductStateProjectionProvenance] = [],
        omissions: [ProductStateProjectionOmission] = []
    ) -> ProductStateProjectionMetadata {
        ProductStateProjectionMetadata(
            scope: scope,
            freshness: freshness,
            listRevision: listRevision,
            sessionRevision: sessionRevision,
            sessionSnapshotID: sessionSnapshotID,
            provenances: provenances,
            omissions: omissions,
            cachePolicy: cachePolicy
        )
    }

    private func unavailableMetadata(
        scope: ProductStateProjectionScope,
        reason: ProductStateProjectionUnavailableReason,
        listRevision: ProductStateListRevision? = nil,
        sessionRevision: ProductStateSessionRevision? = nil
    ) -> ProductStateProjectionMetadata {
        metadata(
            scope: scope,
            freshness: .unavailable(reason),
            listRevision: listRevision,
            sessionRevision: sessionRevision
        )
    }

    private func omission(
        _ reason: ProductStateProjectionOmissionReason,
        productID: ProductStateProductID? = nil,
        listID: ProductStateListID? = nil,
        entryID: ProductStateListEntryID? = nil,
        sessionID: ProductStateSessionID? = nil,
        sessionLineID: ProductStateSessionLineID? = nil
    ) -> ProductStateProjectionOmission {
        ProductStateProjectionOmission(
            reason: reason,
            productID: productID,
            listID: listID,
            entryID: entryID,
            sessionID: sessionID,
            sessionLineID: sessionLineID
        )
    }

    private func canonicalOmissions(
        _ values: [ProductStateProjectionOmission]
    ) -> [ProductStateProjectionOmission] {
        values.sorted {
            omissionKey($0) < omissionKey($1)
        }
    }

    private func omissionKey(
        _ value: ProductStateProjectionOmission
    ) -> String {
        [
            value.reason.rawValue,
            value.productID?.rawValue.uuidString ?? "",
            value.listID?.rawValue.uuidString ?? "",
            value.entryID?.rawValue.uuidString ?? "",
            value.sessionID?.rawValue.uuidString ?? "",
            value.sessionLineID?.rawValue.uuidString ?? ""
        ].joined(separator: "|")
    }

    private func canonicalEvidence(
        _ values: [ProductStateExactAcquisitionEvidence]
    ) -> [ProductStateExactAcquisitionEvidence] {
        Array(Set(values)).sorted { evidenceKey($0) < evidenceKey($1) }
    }

    private func evidenceKey(
        _ value: ProductStateExactAcquisitionEvidence
    ) -> String {
        switch value {
        case let .productID(id): return "0|\(id.rawValue.uuidString)"
        case let .catalogID(id): return "1|\(id.rawValue)"
        case let .barcode(value): return "2|\(value)"
        }
    }

    private func sourceRevision(
        _ session: WayTaskSchemaV4.ShoppingSession
    ) -> ShoppingSessionSourceRevision {
        guard let value = session.sourceRevision,
              session.sourceRevisionProvenanceRawValue == "exact" else {
            return .legacyUnknown
        }
        return .exact(ProductStateListRevision(value: value))
    }

    private func exactListRevision(
        _ revision: ShoppingSessionSourceRevision
    ) -> ProductStateListRevision? {
        guard case let .exact(value) = revision else { return nil }
        return value
    }

    private func projectionStaleReason(
        _ value: ShoppingPlanStaleReason
    ) -> ProductStateProjectionStaleReason {
        switch value {
        case .sourceRevisionChanged: .sourceRevisionChanged
        case .includedEntriesChanged: .includedEntriesChanged
        case .planningInputChanged: .declaredInputChanged
        case .evidenceExpired: .evidenceExpired
        }
    }

    private func scope(
        _ owner: ProductStateShoppingContextOwner
    ) -> ProductStateProjectionScope {
        switch owner {
        case let .list(id, _): .list(id)
        case let .plan(id, listID, _): .plan(id, listID)
        case let .session(id, _, _): .session(id)
        }
    }

    private func productLess(
        _ lhs: ProductStateProductProjection,
        _ rhs: ProductStateProductProjection
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return uuidLess(lhs.id.rawValue, rhs.id.rawValue)
    }

    private func entryLess(
        _ lhs: WayTaskSchemaV4.ShoppingListEntry,
        _ rhs: WayTaskSchemaV4.ShoppingListEntry
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return entryTieKey(lhs) < entryTieKey(rhs)
    }

    private func sessionLess(
        _ lhs: WayTaskSchemaV4.ShoppingSession,
        _ rhs: WayTaskSchemaV4.ShoppingSession
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return sessionTieKey(lhs) < sessionTieKey(rhs)
    }

    private func lineLess(
        _ lhs: WayTaskSchemaV4.ShoppingSessionLine,
        _ rhs: WayTaskSchemaV4.ShoppingSessionLine
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return lineTieKey(lhs) < lineTieKey(rhs)
    }

    private func stopLess(
        _ lhs: WayTaskSchemaV4.ShoppingSessionStop,
        _ rhs: WayTaskSchemaV4.ShoppingSessionStop
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return stopTieKey(lhs) < stopTieKey(rhs)
    }

    private func exceptionLess(
        _ lhs: WayTaskSchemaV4.ProductStateMigrationException,
        _ rhs: WayTaskSchemaV4.ProductStateMigrationException
    ) -> Bool {
        if lhs.ordinal != rhs.ordinal {
            return lhs.ordinal < rhs.ordinal
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return exceptionTieKey(lhs) < exceptionTieKey(rhs)
    }

    private func exceptionProjectionLess(
        _ lhs: ProductStateSessionExceptionProjection,
        _ rhs: ProductStateSessionExceptionProjection
    ) -> Bool {
        if lhs.ordinal != rhs.ordinal {
            return lhs.ordinal < rhs.ordinal
        }
        if lhs.id != rhs.id { return uuidLess(lhs.id, rhs.id) }
        return exceptionProjectionTieKey(lhs)
            < exceptionProjectionTieKey(rhs)
    }

    private func locationLinkLess(
        _ lhs: ProductStateSavedLocationLinkInput,
        _ rhs: ProductStateSavedLocationLinkInput
    ) -> Bool {
        locationLinkKey(lhs) < locationLinkKey(rhs)
    }

    private func locationLinkKey(
        _ value: ProductStateSavedLocationLinkInput
    ) -> String {
        [
            value.productID?.rawValue.uuidString ?? "",
            value.listID?.rawValue.uuidString ?? "",
            value.entryID?.rawValue.uuidString ?? "",
            value.authority.rawValue
        ].joined(separator: "|")
    }

    private func entryTieKey(
        _ value: WayTaskSchemaV4.ShoppingListEntry
    ) -> String {
        [
            value.shoppingListID.uuidString,
            value.productID.uuidString,
            value.lifecycleRawValue,
            value.resolutionReasonRawValue ?? "",
            value.resolutionEffectiveAt.map(String.init(describing:)) ?? "",
            value.resolutionProvenanceRawValue ?? "",
            value.resolutionCommandID?.uuidString ?? "",
            value.resolutionSessionID?.uuidString ?? "",
            value.resolutionSessionLineID?.uuidString ?? "",
            String(value.quantity),
            value.unitRawValue ?? "",
            value.note ?? "",
            String(value.createdAt.timeIntervalSinceReferenceDate),
            String(value.updatedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func sessionTieKey(
        _ value: WayTaskSchemaV4.ShoppingSession
    ) -> String {
        [
            value.sourceListID?.uuidString ?? "",
            value.sourceRevision.map(String.init) ?? "",
            value.sourceRevisionProvenanceRawValue,
            String(value.revision),
            value.lifecycleRawValue,
            value.migrationConditionRawValue,
            value.snapshotID.uuidString,
            String(value.snapshotVersion),
            String(value.snapshotGeneration),
            value.snapshotContentSignature
        ].joined(separator: "|")
    }

    private func lineTieKey(
        _ value: WayTaskSchemaV4.ShoppingSessionLine
    ) -> String {
        [
            value.sessionID.uuidString,
            value.snapshotID.uuidString,
            value.sourceListID?.uuidString ?? "",
            value.sourceEntryID?.uuidString ?? "",
            value.productID?.uuidString ?? "",
            value.stopID?.uuidString ?? "",
            value.productNameSnapshot,
            value.executionStateRawValue,
            value.finalOutcomeRawValue ?? "",
            value.legacyDispositionRawValue ?? ""
        ].joined(separator: "|")
    }

    private func stopTieKey(
        _ value: WayTaskSchemaV4.ShoppingSessionStop
    ) -> String {
        [
            value.sessionID.uuidString,
            value.snapshotID.uuidString,
            value.storeReferenceIDRawValue ?? "",
            value.storeReferenceProvenanceRawValue,
            value.displayNameSnapshot,
            value.evidenceAt.map(String.init(describing:)) ?? ""
        ].joined(separator: "|")
    }

    private func exceptionTieKey(
        _ value: WayTaskSchemaV4.ProductStateMigrationException
    ) -> String {
        [
            value.sessionID?.uuidString ?? "",
            value.sessionLineID?.uuidString ?? "",
            value.categoryRawValue,
            value.safeEvidenceDigest,
            String(value.occurrenceCount),
            String(value.recordedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func exceptionProjectionTieKey(
        _ value: ProductStateSessionExceptionProjection
    ) -> String {
        [
            value.sessionID?.rawValue.uuidString ?? "",
            value.sessionLineID?.rawValue.uuidString ?? "",
            value.categoryRawValue,
            value.safeEvidenceDigest,
            String(value.occurrenceCount),
            String(value.recordedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private func productIDLess(
        _ lhs: ProductStateProductID,
        _ rhs: ProductStateProductID
    ) -> Bool {
        uuidLess(lhs.rawValue, rhs.rawValue)
    }

    private func entryIDLess(
        _ lhs: ProductStateListEntryID,
        _ rhs: ProductStateListEntryID
    ) -> Bool {
        uuidLess(lhs.rawValue, rhs.rawValue)
    }

    private func lineIDLess(
        _ lhs: ProductStateSessionLineID,
        _ rhs: ProductStateSessionLineID
    ) -> Bool {
        uuidLess(lhs.rawValue, rhs.rawValue)
    }

    private struct ListSnapshot {
        let id: ProductStateListID
        let revision: ProductStateListRevision
        let title: String
        let purposeRawValue: String?
        let createdAt: Date
        let updatedAt: Date
        let freshness: ProductStateProjectionFreshness
    }

    private enum ListLoad {
        case success(ListSnapshot)
        case failure(ProductStateProjectionMetadata)
    }

    private enum MembershipBuild {
        case success(ProductStateMembershipProjection)
        case failure(ProductStateMembershipProjection)
    }
}
