import CryptoKit
import Foundation

// MARK: - T-20 exact reminder identities

struct ProductStateNotificationID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateGeofenceID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateNotificationTriggerID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateNotificationEventID: Hashable, Sendable {
    let rawValue: UUID
}

struct ProductStateStoreID: Hashable, Sendable {
    let rawValue: String
}

struct ProductStateReminderRegistrationID: Hashable, Sendable {
    let rawValue: UUID
}

// MARK: - Inactive capability and policy inputs

enum ProductStateNotificationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

enum ProductStateLocationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always
}

struct ProductStateReminderCapabilityProjection: Equatable, Sendable {
    let notificationAuthorization: ProductStateNotificationAuthorization
    let locationAuthorization: ProductStateLocationAuthorization
    let preciseLocationAvailable: Bool
    let regionMonitoringAvailable: Bool
    let backgroundRefreshAvailable: Bool
    let durableAuthorityAvailable: Bool
}

struct ProductStateReminderRegionPolicy: Equatable, Sendable {
    static let requiredCooldown: TimeInterval = 2 * 60 * 60

    let maximumRegionCount: Int
    let approvedFutureStopCount: Int
    let radiusMeters: Double
    let cooldown: TimeInterval

    var isValid: Bool {
        (1...12).contains(maximumRegionCount)
            && (0..<maximumRegionCount).contains(approvedFutureStopCount)
            && (150...250).contains(radiusMeters)
            && radiusMeters.isFinite
            && cooldown == Self.requiredCooldown
    }
}

enum ProductStateReminderIntent: Equatable, Sendable {
    case disabled(ProductStateSessionID)
    case enabled(
        sessionID: ProductStateSessionID,
        currentStopID: ProductStateSessionStopID
    )
}

struct ProductStateReminderRecoveryInput: Equatable, Sendable {
    let recoveryID: UUID
    let sessionID: ProductStateSessionID
    let revision: ProductStateSessionRevision
    let snapshotID: ProductStateSessionSnapshotID
    let durableAuthorityAvailable: Bool
}

enum ProductStateReminderPlanningCause: Equatable, Sendable {
    case postCommit(ProductStateCommandReceipt)
    case recovery(ProductStateReminderRecoveryInput)
}

// MARK: - Immutable desired registration projection

enum ProductStateReminderIneligibilityReason: Equatable, Sendable {
    case explicitIntentDisabled
    case sessionNotActive(ShoppingSessionLifecycle?)
    case notificationPermissionUnavailable(
        ProductStateNotificationAuthorization
    )
    case backgroundLocationUnavailable(ProductStateLocationAuthorization)
    case preciseLocationUnavailable
    case regionMonitoringUnavailable
    case backgroundRefreshUnavailable
    case durableAuthorityUnavailable
    case noRemainingLines
}

enum ProductStateReminderInvalidReason: Equatable, Sendable {
    case invalidPolicy
    case staleSessionProjection
    case staleOpportunityProjection
    case ownerMismatch
    case intentOwnerMismatch
    case postCommitRevisionMissing(ProductStateCommandID)
    case recoveryOwnerMismatch(UUID)
    case missingExactListOwner
    case missingExactPlanOwner
    case invalidPlanSignature
    case invalidStopOrder
    case duplicateStopIdentity(ProductStateSessionStopID)
    case currentStopNotFound(ProductStateSessionStopID)
    case invalidStop(ProductStateSessionStopID)
    case missingStoreIdentity(ProductStateSessionStopID)
    case invalidCoordinate(ProductStateSessionStopID)
    case duplicateLineIdentity(ProductStateSessionLineID)
    case duplicateEntryIdentity(ProductStateListEntryID)
    case duplicateProductIdentity(ProductStateProductID)
    case invalidLineOrder(ProductStateSessionStopID)
    case unresolvedLine(ProductStateSessionLineID)
    case invalidLineState(ProductStateSessionLineID)
    case lineOwnerMismatch(ProductStateSessionLineID)
    case lineStopNotFound(ProductStateSessionLineID)
    case unresolvedOpportunityItem
    case duplicateOpportunityLine(ProductStateSessionLineID)
    case opportunityMismatch(ProductStateSessionLineID)
}

enum ProductStateReminderPlanState: Equatable, Sendable {
    case eligible
    case ineligible(ProductStateReminderIneligibilityReason)
    case invalid(ProductStateReminderInvalidReason)
}

struct ProductStateNotificationOpaquePayload: Equatable, Sendable {
    static let version = 1

    let registrationID: ProductStateReminderRegistrationID
    let notificationID: ProductStateNotificationID
    let geofenceID: ProductStateGeofenceID
    let triggerID: ProductStateNotificationTriggerID
    let sessionID: ProductStateSessionID
    let sessionRevision: ProductStateSessionRevision
    let sessionSnapshotID: ProductStateSessionSnapshotID
    let listID: ProductStateListID
    let listRevision: ProductStateListRevision
    let planID: ProductStatePlanID
    let stopID: ProductStateSessionStopID
    let storeID: ProductStateStoreID

    var owner: ProductStateNotificationPayloadOwner {
        .session(sessionID, sessionRevision, sessionSnapshotID)
    }
}

struct ProductStateReminderRegistrationProjection: Equatable, Sendable {
    let payload: ProductStateNotificationOpaquePayload
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let lineIDs: [ProductStateSessionLineID]
    let entryIDs: [ProductStateListEntryID]
    let productIDs: [ProductStateProductID]
    let stopOrdinal: Int
    let remainingLineCount: Int
    let sourceReceipt: ProductStateCommandReceipt?
    let recoveryID: UUID?

    var sourceCommandID: ProductStateCommandID? {
        sourceReceipt?.commandID
    }
}

enum ProductStateReminderStopOmissionReason: Equatable, Sendable {
    case beforeCurrentStop
    case noRemainingLines
    case outsideApprovedRegionBudget
}

struct ProductStateReminderStopOmissionProjection: Equatable, Sendable {
    let stopID: ProductStateSessionStopID
    let reason: ProductStateReminderStopOmissionReason
}

struct ProductStateNotificationPlanProjection: Equatable, Sendable {
    let owner: ProductStateNotificationPayloadOwner
    let state: ProductStateReminderPlanState
    let registrations: [ProductStateReminderRegistrationProjection]
    let stopOmissions: [ProductStateReminderStopOmissionProjection]
    let policy: ProductStateReminderRegionPolicy

    var omittedStopIDs: [ProductStateSessionStopID] {
        stopOmissions.map(\.stopID)
    }
}

// MARK: - Deterministic planning

struct ProductStateNotificationPlanner {
    func makeProjection(
        session: ProductStateSessionSnapshotProjection,
        opportunity: ProductStateNotificationOpportunityProjection,
        intent: ProductStateReminderIntent,
        capabilities: ProductStateReminderCapabilityProjection,
        policy: ProductStateReminderRegionPolicy,
        cause: ProductStateReminderPlanningCause
    ) -> ProductStateNotificationPlanProjection {
        let owner = ProductStateNotificationPayloadOwner.session(
            session.id, session.revision, session.snapshotID
        )
        func result(
            _ state: ProductStateReminderPlanState,
            registrations: [ProductStateReminderRegistrationProjection] = [],
            omissions: [ProductStateReminderStopOmissionProjection] = []
        ) -> ProductStateNotificationPlanProjection {
            ProductStateNotificationPlanProjection(
                owner: owner,
                state: state,
                registrations: registrations,
                stopOmissions: omissions,
                policy: policy
            )
        }

        guard policy.isValid else { return result(.invalid(.invalidPolicy)) }
        guard session.metadata.freshness == .current,
              session.metadata.sessionRevision == session.revision,
              session.metadata.sessionSnapshotID == session.snapshotID else {
            return result(.invalid(.staleSessionProjection))
        }
        guard opportunity.metadata.freshness == .current,
              opportunity.metadata.sessionRevision == session.revision,
              opportunity.metadata.sessionSnapshotID == session.snapshotID else {
            return result(.invalid(.staleOpportunityProjection))
        }
        guard opportunity.owner == .session(
            session.id, session.revision, session.snapshotID
        ) else { return result(.invalid(.ownerMismatch)) }

        let currentStopID: ProductStateSessionStopID
        switch intent {
        case let .disabled(sessionID):
            guard sessionID == session.id else {
                return result(.invalid(.intentOwnerMismatch))
            }
            return result(.ineligible(.explicitIntentDisabled))
        case let .enabled(sessionID, stopID):
            guard sessionID == session.id else {
                return result(.invalid(.intentOwnerMismatch))
            }
            currentStopID = stopID
        }

        guard session.lifecycle == .active else {
            return result(.ineligible(.sessionNotActive(session.lifecycle)))
        }
        if let reason = capabilityReason(capabilities) {
            return result(.ineligible(reason))
        }

        let listID: ProductStateListID
        let listRevision: ProductStateListRevision
        guard let exactListID = session.sourceListID,
              case let .exact(exactRevision) = session.sourceRevision else {
            return result(.invalid(.missingExactListOwner))
        }
        listID = exactListID
        listRevision = exactRevision
        guard let planID = session.sourcePlanID else {
            return result(.invalid(.missingExactPlanOwner))
        }
        guard let planSignature = session.sourcePlanSignature,
              !planSignature.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return result(.invalid(.invalidPlanSignature))
        }

        let source: (ProductStateCommandReceipt?, UUID?)
        switch cause {
        case let .postCommit(receipt):
            let exactEffect = receipt.effects.revisionChanges.contains {
                $0.after.scope == .session(session.id)
                    && $0.after.value == session.revision.value
            }
            guard exactEffect else {
                return result(.invalid(
                    .postCommitRevisionMissing(receipt.commandID)
                ))
            }
            source = (receipt, nil)
        case let .recovery(recovery):
            guard recovery.durableAuthorityAvailable else {
                return result(.ineligible(.durableAuthorityUnavailable))
            }
            guard recovery.sessionID == session.id,
                  recovery.revision == session.revision,
                  recovery.snapshotID == session.snapshotID else {
                return result(.invalid(
                    .recoveryOwnerMismatch(recovery.recoveryID)
                ))
            }
            source = (nil, recovery.recoveryID)
        }

        let stops = session.stops
        guard Set(stops.map(\.id)).count == stops.count else {
            let duplicate = firstDuplicate(stops.map(\.id))!
            return result(.invalid(.duplicateStopIdentity(duplicate)))
        }
        guard stops.map(\.id) == stops.sorted(by: canonicalStopOrder).map(\.id)
        else { return result(.invalid(.invalidStopOrder)) }
        guard let currentIndex = stops.firstIndex(where: {
            $0.id == currentStopID
        }) else {
            return result(.invalid(.currentStopNotFound(currentStopID)))
        }

        let lines = session.lines
        guard Set(lines.map(\.id)).count == lines.count else {
            let duplicate = firstDuplicate(lines.map(\.id))!
            return result(.invalid(.duplicateLineIdentity(duplicate)))
        }
        let entryIDs = lines.compactMap(\.sourceEntryID)
        if let duplicate = firstDuplicate(entryIDs) {
            return result(.invalid(.duplicateEntryIdentity(duplicate)))
        }
        let productIDs = lines.compactMap(\.productID)
        if let duplicate = firstDuplicate(productIDs) {
            return result(.invalid(.duplicateProductIdentity(duplicate)))
        }
        var itemsByLine = [
            ProductStateSessionLineID:
                ProductStateShoppingContextItemProjection
        ]()
        for item in opportunity.items {
            guard let lineID = item.sessionLineID else {
                return result(.invalid(.unresolvedOpportunityItem))
            }
            guard itemsByLine[lineID] == nil else {
                return result(.invalid(.duplicateOpportunityLine(lineID)))
            }
            itemsByLine[lineID] = item
        }
        guard opportunity.items.compactMap(\.sessionLineID) == lines.map(\.id)
        else {
            let first = lines.first?.id
                ?? opportunity.items.compactMap(\.sessionLineID).first
            guard let first else {
                return result(.invalid(.unresolvedOpportunityItem))
            }
            return result(.invalid(.opportunityMismatch(first)))
        }

        for line in lines {
            guard line.qualification == .qualified,
                  let productID = line.productID,
                  let entryID = line.sourceEntryID,
                  let stopID = line.stopID else {
                return result(.invalid(.unresolvedLine(line.id)))
            }
            guard line.sourceListID == listID else {
                return result(.invalid(.lineOwnerMismatch(line.id)))
            }
            guard line.executionState != nil,
                  line.finalOutcome == nil else {
                return result(.invalid(.invalidLineState(line.id)))
            }
            guard stops.contains(where: { $0.id == stopID }) else {
                return result(.invalid(.lineStopNotFound(line.id)))
            }
            guard let item = itemsByLine[line.id], item.isQualified,
                  item.productID == productID,
                  item.entryID == entryID else {
                return result(.invalid(.opportunityMismatch(line.id)))
            }
        }
        guard itemsByLine.count == lines.count else {
            let extra = itemsByLine.keys.first { lineID in
                !lines.contains(where: { $0.id == lineID })
            }
            guard let extra else {
                return result(.invalid(.unresolvedOpportunityItem))
            }
            return result(.invalid(.opportunityMismatch(extra)))
        }

        for stop in stops {
            let stopLines = lines.filter { $0.stopID == stop.id }
            guard stopLines.map(\.id) == stopLines.sorted(
                by: canonicalLineOrder
            ).map(\.id) else {
                return result(.invalid(.invalidLineOrder(stop.id)))
            }
            let hasRemainingLines = stopLines.contains {
                $0.executionState == .remaining
            }
            let storeID = stop.storeReferenceID?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let validLatitude = stop.latitudeSnapshot.map {
                $0.isFinite && (-90...90).contains($0)
            } == true
            let validLongitude = stop.longitudeSnapshot.map {
                $0.isFinite && (-180...180).contains($0)
            } == true
            guard !hasRemainingLines || stop.qualification == .qualified else {
                return result(.invalid(.invalidStop(stop.id)))
            }
            guard !hasRemainingLines || storeID?.isEmpty == false else {
                return result(.invalid(.missingStoreIdentity(stop.id)))
            }
            guard !hasRemainingLines || (validLatitude && validLongitude) else {
                return result(.invalid(.invalidCoordinate(stop.id)))
            }
        }

        let futureLimit = min(
            policy.approvedFutureStopCount,
            policy.maximumRegionCount - 1
        )
        let currentStop = stops[currentIndex]
        let futureStopsWithRemainingLines = stops
            .dropFirst(currentIndex + 1)
            .filter { stop in
                lines.contains {
                    $0.stopID == stop.id
                        && $0.executionState == .remaining
                        && $0.finalOutcome == nil
                }
            }
        let considered = [currentStop] + Array(
            futureStopsWithRemainingLines.prefix(futureLimit)
        )
        let consideredIDs = Set(considered.map(\.id))
        var registrations: [ProductStateReminderRegistrationProjection] = []

        for (ordinal, stop) in considered.enumerated() {
            let stopLines = lines.filter { $0.stopID == stop.id }
            let remaining = stopLines.filter {
                $0.executionState == .remaining && $0.finalOutcome == nil
            }
            guard !remaining.isEmpty else { continue }
            guard let rawStoreID = stop.storeReferenceID?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), let latitude = stop.latitudeSnapshot,
              let longitude = stop.longitudeSnapshot,
              !rawStoreID.isEmpty else {
                return result(.invalid(.invalidStop(stop.id)))
            }

            let seed = [
                session.id.rawValue.uuidString,
                String(session.revision.value),
                session.snapshotID.rawValue.uuidString,
                listID.rawValue.uuidString,
                String(listRevision.value),
                planID.rawValue.uuidString,
                planSignature,
                stop.id.rawValue.uuidString,
                rawStoreID
            ]
            let registrationID = ProductStateReminderRegistrationID(
                rawValue: deterministicUUID(kind: "registration", seed: seed)
            )
            let payload = ProductStateNotificationOpaquePayload(
                registrationID: registrationID,
                notificationID: ProductStateNotificationID(
                    rawValue: deterministicUUID(
                        kind: "notification", seed: seed
                    )
                ),
                geofenceID: ProductStateGeofenceID(
                    rawValue: deterministicUUID(kind: "geofence", seed: seed)
                ),
                triggerID: ProductStateNotificationTriggerID(
                    rawValue: deterministicUUID(kind: "trigger", seed: seed)
                ),
                sessionID: session.id,
                sessionRevision: session.revision,
                sessionSnapshotID: session.snapshotID,
                listID: listID,
                listRevision: listRevision,
                planID: planID,
                stopID: stop.id,
                storeID: ProductStateStoreID(rawValue: rawStoreID)
            )
            registrations.append(ProductStateReminderRegistrationProjection(
                payload: payload,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: policy.radiusMeters,
                lineIDs: remaining.map(\.id),
                entryIDs: remaining.compactMap(\.sourceEntryID),
                productIDs: remaining.compactMap(\.productID),
                stopOrdinal: ordinal,
                remainingLineCount: remaining.count,
                sourceReceipt: source.0,
                recoveryID: source.1
            ))
        }
        let omissions = stops.enumerated().compactMap { index, stop in
            let hasRemainingLines = lines.contains {
                $0.stopID == stop.id
                    && $0.executionState == .remaining
                    && $0.finalOutcome == nil
            }
            let reason: ProductStateReminderStopOmissionReason?
            if index < currentIndex {
                reason = .beforeCurrentStop
            } else if !hasRemainingLines {
                reason = .noRemainingLines
            } else if !consideredIDs.contains(stop.id) {
                reason = .outsideApprovedRegionBudget
            } else {
                reason = nil
            }
            return reason.map {
                ProductStateReminderStopOmissionProjection(
                    stopID: stop.id,
                    reason: $0
                )
            }
        }
        guard !registrations.isEmpty else {
            return result(
                .ineligible(.noRemainingLines),
                omissions: omissions
            )
        }
        return result(
            .eligible,
            registrations: registrations,
            omissions: omissions
        )
    }

    private func capabilityReason(
        _ value: ProductStateReminderCapabilityProjection
    ) -> ProductStateReminderIneligibilityReason? {
        guard value.durableAuthorityAvailable else {
            return .durableAuthorityUnavailable
        }
        guard value.notificationAuthorization == .authorized
                || value.notificationAuthorization == .provisional else {
            return .notificationPermissionUnavailable(
                value.notificationAuthorization
            )
        }
        guard value.locationAuthorization == .always else {
            return .backgroundLocationUnavailable(value.locationAuthorization)
        }
        guard value.preciseLocationAvailable else {
            return .preciseLocationUnavailable
        }
        guard value.regionMonitoringAvailable else {
            return .regionMonitoringUnavailable
        }
        guard value.backgroundRefreshAvailable else {
            return .backgroundRefreshUnavailable
        }
        return nil
    }

    private func canonicalStopOrder(
        _ lhs: ProductStateSessionStopProjection,
        _ rhs: ProductStateSessionStopProjection
    ) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            : lhs.sortOrder < rhs.sortOrder
    }

    private func canonicalLineOrder(
        _ lhs: ProductStateSessionLineProjection,
        _ rhs: ProductStateSessionLineProjection
    ) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            : lhs.sortOrder < rhs.sortOrder
    }

    private func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen = Set<Value>()
        return values.first { !seen.insert($0).inserted }
    }

    private func deterministicUUID(kind: String, seed: [String]) -> UUID {
        var input = Data(kind.utf8)
        for value in seed {
            let data = Data(value.utf8)
            var size = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &size) { input.append(contentsOf: $0) }
            input.append(data)
        }
        var bytes = Array(SHA256.hash(data: input).prefix(16))
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

// MARK: - Registration ledger and post-commit reconciliation

enum ProductStateReminderRegistrationLifecycle: Equatable, Sendable {
    case desired
    case registering(attemptID: UUID)
    case registered
    case failed(code: String)
    case removing(attemptID: UUID)
    case removed
    case suppressed(reason: String)
}

enum ProductStateNotificationDeliveryLifecycle: Equatable, Sendable {
    case idle
    case scheduling(attemptID: UUID, eventID: ProductStateNotificationEventID)
    case scheduled(
        eventID: ProductStateNotificationEventID,
        lastSuccessfulAt: Date
    )
    case failed(code: String)
    case unknown(attemptID: UUID, eventID: ProductStateNotificationEventID)
}

struct ProductStateReminderLedgerEntry: Equatable, Sendable {
    let payload: ProductStateNotificationOpaquePayload
    let registrationLifecycle: ProductStateReminderRegistrationLifecycle
    let deliveryLifecycle: ProductStateNotificationDeliveryLifecycle
}

struct ProductStateReminderReconciliationInput: Equatable, Sendable {
    let desired: ProductStateNotificationPlanProjection
    let ledger: [ProductStateReminderLedgerEntry]
    let actualGeofenceIDs: Set<ProductStateGeofenceID>
    let actualPendingNotificationIDs: Set<ProductStateNotificationID>
    let actualDeliveredNotificationIDs: Set<ProductStateNotificationID>
}

enum ProductStateReminderReconciliationAction: Equatable, Sendable {
    case register(ProductStateReminderRegistrationProjection)
    case disarm(ProductStateGeofenceID)
    case cancelPending(ProductStateNotificationID)
    case removeDelivered(ProductStateNotificationID)
    case recordProjectionRemoved(ProductStateReminderRegistrationID)
    case invalidateNotificationNavigation(
        ProductStateNotificationPayloadOwner
    )
    case recordActualRegistration(ProductStateGeofenceID)
    case recordMissingRegistration(ProductStateGeofenceID)
    case retryUnknownRegistration(ProductStateGeofenceID)
}

enum ProductStateReminderReconciliationIssue: Equatable, Sendable {
    case duplicateLedgerRegistration(ProductStateReminderRegistrationID)
}

struct ProductStateReminderDiagnosticProjection: Equatable, Sendable {
    let desiredRegistrationCount: Int
    let ledgerRegistrationCount: Int
    let actualRegistrationCount: Int
    let reconciliationActionCount: Int
    let hasLedgerConflict: Bool
}

struct ProductStateReminderReconciliationProjection: Equatable, Sendable {
    let owner: ProductStateNotificationPayloadOwner
    let actions: [ProductStateReminderReconciliationAction]
    let desiredGeofenceIDs: [ProductStateGeofenceID]
    let actualGeofenceIDs: [ProductStateGeofenceID]
    let issues: [ProductStateReminderReconciliationIssue]
    let diagnostics: ProductStateReminderDiagnosticProjection
}

struct ProductStatePostCommitReconciler {
    func reconcile(
        _ input: ProductStateReminderReconciliationInput
    ) -> ProductStateReminderReconciliationProjection {
        let registrations = input.desired.state == .eligible
            ? input.desired.registrations : []
        let desiredByID = Dictionary(uniqueKeysWithValues: registrations.map {
            ($0.payload.geofenceID, $0)
        })
        let orderedDesiredIDs = registrations.map(\.payload.geofenceID)
        let desiredIDs = Set(desiredByID.keys)
        var ledgerByID = [
            ProductStateGeofenceID: ProductStateReminderLedgerEntry
        ]()
        var duplicateLedgerIDs = Set<ProductStateGeofenceID>()
        for entry in input.ledger.sorted(by: ledgerOrder) {
            let id = entry.payload.geofenceID
            guard !duplicateLedgerIDs.contains(id) else { continue }
            if ledgerByID[id] != nil {
                ledgerByID.removeValue(forKey: id)
                duplicateLedgerIDs.insert(id)
            } else {
                ledgerByID[id] = entry
            }
        }
        let issues = duplicateLedgerIDs.sorted(by: geofenceOrder).map { id in
            ProductStateReminderReconciliationIssue
                .duplicateLedgerRegistration(
                    input.ledger.first {
                        $0.payload.geofenceID == id
                    }!.payload.registrationID
                )
        }
        var actions: [ProductStateReminderReconciliationAction] = []

        for geofenceID in input.actualGeofenceIDs.subtracting(desiredIDs)
            .sorted(by: geofenceOrder) {
            actions.append(.disarm(geofenceID))
        }
        for notificationID in input.actualPendingNotificationIDs.filter({
            notificationID in
                !registrations.contains {
                    $0.payload.notificationID == notificationID
                }
            }).sorted(by: notificationOrder) {
            actions.append(.cancelPending(notificationID))
        }
        for notificationID in input.actualDeliveredNotificationIDs.filter({
            notificationID in
                !registrations.contains {
                    $0.payload.notificationID == notificationID
                }
            }).sorted(by: notificationOrder) {
            actions.append(.removeDelivered(notificationID))
        }

        var invalidatedOwners: [ProductStateNotificationPayloadOwner] = []
        for entry in input.ledger.sorted(by: ledgerOrder)
        where !desiredIDs.contains(entry.payload.geofenceID) {
            if entry.registrationLifecycle != .removed {
                actions.append(.recordProjectionRemoved(
                    entry.payload.registrationID
                ))
            }
            let owner = entry.payload.owner
            if !invalidatedOwners.contains(owner) {
                invalidatedOwners.append(owner)
            }
        }
        for owner in invalidatedOwners.sorted(by: ownerOrder) {
            actions.append(.invalidateNotificationNavigation(owner))
        }

        for geofenceID in orderedDesiredIDs {
            let isActual = input.actualGeofenceIDs.contains(geofenceID)
            let ledger = ledgerByID[geofenceID]
            if isActual {
                if ledger?.registrationLifecycle != .registered {
                    actions.append(.recordActualRegistration(geofenceID))
                }
                continue
            }
            switch ledger?.registrationLifecycle {
            case .registering, .removing:
                actions.append(.retryUnknownRegistration(geofenceID))
            case .registered:
                actions.append(.recordMissingRegistration(geofenceID))
                if let desired = desiredByID[geofenceID] {
                    actions.append(.register(desired))
                }
            default:
                if let desired = desiredByID[geofenceID] {
                    actions.append(.register(desired))
                }
            }
        }

        return ProductStateReminderReconciliationProjection(
            owner: input.desired.owner,
            actions: actions,
            desiredGeofenceIDs: orderedDesiredIDs,
            actualGeofenceIDs: input.actualGeofenceIDs.sorted(
                by: geofenceOrder
            ),
            issues: issues,
            diagnostics: ProductStateReminderDiagnosticProjection(
                desiredRegistrationCount: registrations.count,
                ledgerRegistrationCount: input.ledger.count,
                actualRegistrationCount: input.actualGeofenceIDs.count,
                reconciliationActionCount: actions.count,
                hasLedgerConflict: !issues.isEmpty
            )
        )
    }

    private func ledgerOrder(
        _ lhs: ProductStateReminderLedgerEntry,
        _ rhs: ProductStateReminderLedgerEntry
    ) -> Bool {
        lhs.payload.registrationID.rawValue.uuidString
            < rhs.payload.registrationID.rawValue.uuidString
    }

    private func ownerOrder(
        _ lhs: ProductStateNotificationPayloadOwner,
        _ rhs: ProductStateNotificationPayloadOwner
    ) -> Bool {
        ownerKey(lhs) < ownerKey(rhs)
    }

    private func ownerKey(
        _ owner: ProductStateNotificationPayloadOwner
    ) -> String {
        switch owner {
        case let .list(listID, revision):
            return "list:\(listID.rawValue.uuidString):\(revision.value)"
        case let .plan(planID, listID, revision):
            return "plan:\(planID.rawValue.uuidString):" +
                "\(listID.rawValue.uuidString):\(revision.value)"
        case let .session(sessionID, revision, snapshotID):
            return "session:\(sessionID.rawValue.uuidString):" +
                "\(revision.value):\(snapshotID.rawValue.uuidString)"
        }
    }

    private func geofenceOrder(
        _ lhs: ProductStateGeofenceID,
        _ rhs: ProductStateGeofenceID
    ) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    private func notificationOrder(
        _ lhs: ProductStateNotificationID,
        _ rhs: ProductStateNotificationID
    ) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }
}

// MARK: - Event validation and scheduling-result intents

struct ProductStateGeofenceEvent: Equatable, Sendable {
    let geofenceID: ProductStateGeofenceID
    let triggerID: ProductStateNotificationTriggerID
    let eventID: ProductStateNotificationEventID
    let occurredAt: Date
}

enum ProductStateNotificationSemanticContent: Equatable, Sendable {
    case remainingLinesAtSessionStop(count: Int)
}

struct ProductStateNotificationDeliveryProjection: Equatable, Sendable {
    let notificationID: ProductStateNotificationID
    let triggerID: ProductStateNotificationTriggerID
    let eventID: ProductStateNotificationEventID
    let owner: ProductStateNotificationPayloadOwner
    let sessionID: ProductStateSessionID
    let stopID: ProductStateSessionStopID
    let storeID: ProductStateStoreID
    let lineIDs: [ProductStateSessionLineID]
    let entryIDs: [ProductStateListEntryID]
    let productIDs: [ProductStateProductID]
    let content: ProductStateNotificationSemanticContent
}

enum ProductStateNotificationEventOutcome: Equatable, Sendable {
    case schedule(ProductStateNotificationDeliveryProjection)
    case cooldown(until: Date)
    case duplicateInFlight
    case duplicateSucceeded
    case stale(ProductStateProjectionStaleReason)
    case suppressed(ProductStateProjectionUnavailableReason)
    case invalid
}

/// Successful-delivery authority is keyed by Session and stop, not by a
/// revisioned registration. This prevents a Session revision change from
/// bypassing the binding two-hour cooldown.
struct ProductStateReminderCooldownProjection: Equatable, Sendable {
    let sessionID: ProductStateSessionID
    let stopID: ProductStateSessionStopID
    let lastSuccessfulAt: Date
}

struct ProductStateNotificationTriggerEvaluator {
    func evaluate(
        event: ProductStateGeofenceEvent,
        desired: ProductStateNotificationPlanProjection,
        ledger: ProductStateReminderLedgerEntry?,
        route: ProductStateNotificationRouteProjection,
        cooldown: ProductStateReminderCooldownProjection?
    ) -> ProductStateNotificationEventOutcome {
        guard desired.state == .eligible,
              let registration = desired.registrations.first(where: {
                $0.payload.geofenceID == event.geofenceID
              }),
              registration.payload.triggerID == event.triggerID,
              ledger?.payload == registration.payload,
              ledger?.registrationLifecycle == .registered,
              route.payloadOwner == registration.payload.owner else {
            return .invalid
        }
        switch route.route {
        case let .safeShopping(reason): return .stale(reason)
        case let .suppressed(reason): return .suppressed(reason)
        case let .session(sessionID):
            guard sessionID == registration.payload.sessionID else {
                return .invalid
            }
        case .namedList:
            return .invalid
        }
        if let cooldown {
            guard cooldown.sessionID == registration.payload.sessionID,
                  cooldown.stopID == registration.payload.stopID else {
                return .invalid
            }
        }
        var lastSuccessfulAt = cooldown?.lastSuccessfulAt
        switch ledger?.deliveryLifecycle {
        case .scheduling, .unknown:
            return .duplicateInFlight
        case let .scheduled(eventID, ledgerSuccessfulAt):
            guard eventID != event.eventID else {
                return .duplicateSucceeded
            }
            if lastSuccessfulAt.map({ $0 < ledgerSuccessfulAt }) != false {
                lastSuccessfulAt = ledgerSuccessfulAt
            }
        default:
            break
        }
        if let lastSuccessfulAt {
            let next = lastSuccessfulAt.addingTimeInterval(
                ProductStateReminderRegionPolicy.requiredCooldown
            )
            guard event.occurredAt >= next else {
                return .cooldown(until: next)
            }
        }
        return .schedule(ProductStateNotificationDeliveryProjection(
            notificationID: registration.payload.notificationID,
            triggerID: registration.payload.triggerID,
            eventID: event.eventID,
            owner: registration.payload.owner,
            sessionID: registration.payload.sessionID,
            stopID: registration.payload.stopID,
            storeID: registration.payload.storeID,
            lineIDs: registration.lineIDs,
            entryIDs: registration.entryIDs,
            productIDs: registration.productIDs,
            content: .remainingLinesAtSessionStop(
                count: registration.remainingLineCount
            )
        ))
    }
}

enum ProductStateNotificationSchedulingResult: Equatable, Sendable {
    case succeeded(at: Date)
    case failed(code: String)
    case unknown(attemptID: UUID)
}

enum ProductStateNotificationLedgerIntent: Equatable, Sendable {
    case recordSuccessfulSchedule(
        ProductStateNotificationID,
        eventID: ProductStateNotificationEventID,
        sessionID: ProductStateSessionID,
        stopID: ProductStateSessionStopID,
        successfulAt: Date
    )
    case recordRetryableFailure(
        ProductStateNotificationID,
        eventID: ProductStateNotificationEventID,
        code: String
    )
    case recordUnknownResult(
        ProductStateNotificationID,
        eventID: ProductStateNotificationEventID,
        attemptID: UUID
    )
}

struct ProductStateNotificationSchedulingResultProjector {
    func project(
        delivery: ProductStateNotificationDeliveryProjection,
        result: ProductStateNotificationSchedulingResult
    ) -> ProductStateNotificationLedgerIntent {
        switch result {
        case let .succeeded(at):
            return .recordSuccessfulSchedule(
                delivery.notificationID,
                eventID: delivery.eventID,
                sessionID: delivery.sessionID,
                stopID: delivery.stopID,
                successfulAt: at
            )
        case let .failed(code):
            return .recordRetryableFailure(
                delivery.notificationID,
                eventID: delivery.eventID,
                code: code
            )
        case let .unknown(attemptID):
            return .recordUnknownResult(
                delivery.notificationID,
                eventID: delivery.eventID,
                attemptID: attemptID
            )
        }
    }
}
