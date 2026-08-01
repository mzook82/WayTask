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
