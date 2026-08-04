import Foundation
import XCTest
@testable import WayTask

@MainActor
final class ProductStateNotificationIntegrationTests: XCTestCase {
    func testPlannerPreservesExactIdentityOrderingAndCommittedReceipt() {
        let session = makeSession(stopCount: 4)
        let plan = projection(
            session: session,
            policy: policy(maximum: 3, future: 2)
        )

        XCTAssertEqual(plan.state, .eligible)
        XCTAssertEqual(plan.registrations.count, 3)
        XCTAssertEqual(
            plan.registrations.map(\.payload.stopID),
            [stopID(0), stopID(1), stopID(2)]
        )
        XCTAssertEqual(plan.omittedStopIDs, [stopID(3)])
        XCTAssertEqual(
            plan.stopOmissions.map(\.reason),
            [.outsideApprovedRegionBudget]
        )
        for (index, registration) in plan.registrations.enumerated() {
            XCTAssertEqual(registration.payload.sessionID, sessionID)
            XCTAssertEqual(registration.payload.sessionRevision.value, 7)
            XCTAssertEqual(registration.payload.sessionSnapshotID, snapshotID)
            XCTAssertEqual(registration.payload.listID, listID)
            XCTAssertEqual(registration.payload.listRevision.value, 11)
            XCTAssertEqual(registration.payload.planID, planID)
            XCTAssertEqual(registration.payload.stopID, stopID(index))
            XCTAssertEqual(
                registration.payload.storeID,
                ProductStateStoreID(rawValue: "store-\(index)")
            )
            XCTAssertEqual(registration.lineIDs, [lineID(index)])
            XCTAssertEqual(registration.entryIDs, [entryID(index)])
            XCTAssertEqual(registration.productIDs, [productID(index)])
            XCTAssertEqual(registration.sourceCommandID, commandID)
            XCTAssertEqual(registration.sourceReceipt, receipt())
            XCTAssertNil(registration.recoveryID)
        }

        XCTAssertEqual(
            plan,
            projection(
                session: session,
                policy: policy(maximum: 3, future: 2)
            )
        )
    }

    func testRegionSelectionUsesOnlyExplicitApprovedPolicy() {
        let session = makeSession(stopCount: 3)
        let plan = projection(
            session: session,
            currentStop: 1,
            policy: policy(maximum: 1, future: 0)
        )

        XCTAssertEqual(plan.registrations.map(\.payload.stopID), [stopID(1)])
        XCTAssertEqual(plan.stopOmissions, [
            .init(stopID: stopID(0), reason: .beforeCurrentStop),
            .init(stopID: stopID(2), reason: .outsideApprovedRegionBudget)
        ])

        let skippedCompleted = projection(
            session: makeSession(
                stopCount: 4,
                remainingStops: [0, 2, 3]
            ),
            policy: policy(maximum: 3, future: 2)
        )
        XCTAssertEqual(
            skippedCompleted.registrations.map(\.payload.stopID),
            [stopID(0), stopID(2), stopID(3)]
        )
        XCTAssertEqual(skippedCompleted.stopOmissions, [
            .init(stopID: stopID(1), reason: .noRemainingLines)
        ])
    }

    func testInvalidPolicyFailsClosed() {
        let invalid = policy(maximum: 13, future: 12)
        XCTAssertEqual(
            projection(session: makeSession(), policy: invalid).state,
            .invalid(.invalidPolicy)
        )
        let wrongCooldown = ProductStateReminderRegionPolicy(
            maximumRegionCount: 3,
            approvedFutureStopCount: 2,
            radiusMeters: 200,
            cooldown: 3_600
        )
        XCTAssertEqual(
            projection(session: makeSession(), policy: wrongCooldown).state,
            .invalid(.invalidPolicy)
        )
    }

    func testDisabledIntentAndNoRemainingLinesAreExplicit() {
        let session = makeSession()
        let disabled = ProductStateNotificationPlanner().makeProjection(
            session: session,
            opportunity: opportunity(session),
            intent: .disabled(sessionID),
            capabilities: capabilities,
            policy: policy(),
            cause: .postCommit(receipt())
        )
        XCTAssertEqual(
            disabled.state,
            .ineligible(.explicitIntentDisabled)
        )
        XCTAssertTrue(disabled.registrations.isEmpty)

        let completed = makeSession(remainingStops: [])
        let noRemaining = projection(session: completed)
        XCTAssertEqual(
            noRemaining.state,
            .ineligible(.noRemainingLines)
        )
        XCTAssertEqual(
            noRemaining.stopOmissions.map(\.reason),
            [.noRemainingLines, .noRemainingLines, .noRemainingLines]
        )
    }

    func testCapabilitiesRemainSeparateFromSessionLifecycle() {
        let session = makeSession()
        let cases: [
            (ProductStateReminderCapabilityProjection,
             ProductStateReminderIneligibilityReason)
        ] = [
            (.init(
                notificationAuthorization: .denied,
                locationAuthorization: .always,
                preciseLocationAvailable: true,
                regionMonitoringAvailable: true,
                backgroundRefreshAvailable: true,
                durableAuthorityAvailable: true
            ), .notificationPermissionUnavailable(.denied)),
            (.init(
                notificationAuthorization: .authorized,
                locationAuthorization: .whenInUse,
                preciseLocationAvailable: true,
                regionMonitoringAvailable: true,
                backgroundRefreshAvailable: true,
                durableAuthorityAvailable: true
            ), .backgroundLocationUnavailable(.whenInUse)),
            (.init(
                notificationAuthorization: .authorized,
                locationAuthorization: .always,
                preciseLocationAvailable: false,
                regionMonitoringAvailable: true,
                backgroundRefreshAvailable: true,
                durableAuthorityAvailable: true
            ), .preciseLocationUnavailable),
            (.init(
                notificationAuthorization: .authorized,
                locationAuthorization: .always,
                preciseLocationAvailable: true,
                regionMonitoringAvailable: false,
                backgroundRefreshAvailable: true,
                durableAuthorityAvailable: true
            ), .regionMonitoringUnavailable),
            (.init(
                notificationAuthorization: .authorized,
                locationAuthorization: .always,
                preciseLocationAvailable: true,
                regionMonitoringAvailable: true,
                backgroundRefreshAvailable: false,
                durableAuthorityAvailable: true
            ), .backgroundRefreshUnavailable),
            (.init(
                notificationAuthorization: .authorized,
                locationAuthorization: .always,
                preciseLocationAvailable: true,
                regionMonitoringAvailable: true,
                backgroundRefreshAvailable: true,
                durableAuthorityAvailable: false
            ), .durableAuthorityUnavailable)
        ]
        for (capability, reason) in cases {
            let value = ProductStateNotificationPlanner().makeProjection(
                session: session,
                opportunity: opportunity(session),
                intent: .enabled(
                    sessionID: sessionID,
                    currentStopID: stopID(0)
                ),
                capabilities: capability,
                policy: policy(),
                cause: .postCommit(receipt())
            )
            XCTAssertEqual(value.state, .ineligible(reason))
            XCTAssertEqual(session.lifecycle, .active)
        }
    }

    func testTerminalAndUnavailableLifecycleProduceZeroDesiredRegions() {
        for lifecycle in [
            ShoppingSessionLifecycle.expired,
            .finished,
            .abandoned
        ] {
            let plan = projection(session: makeSession(lifecycle: lifecycle))
            XCTAssertEqual(
                plan.state,
                .ineligible(.sessionNotActive(lifecycle))
            )
            XCTAssertTrue(plan.registrations.isEmpty)
        }
        let unknown = projection(
            session: makeSession(lifecycle: nil, lifecycleRawValue: "future")
        )
        XCTAssertEqual(
            unknown.state,
            .ineligible(.sessionNotActive(nil))
        )
    }

    func testStaleProjectionAndOwnerMismatchFailClosed() {
        let stale = makeSession(freshness: .stale([.snapshotChanged]))
        XCTAssertEqual(
            projection(session: stale).state,
            .invalid(.staleSessionProjection)
        )

        let current = makeSession()
        let staleOpportunity = replacingOpportunity(
            opportunity(current),
            freshness: .stale([.sourceRevisionChanged])
        )
        XCTAssertEqual(
            planner(
                session: current,
                opportunity: staleOpportunity
            ).state,
            .invalid(.staleOpportunityProjection)
        )

        let wrongOwner = replacingOpportunity(
            opportunity(current),
            owner: .session(
                ProductStateSessionID(rawValue: id(999)),
                current.revision,
                current.snapshotID
            )
        )
        XCTAssertEqual(
            planner(session: current, opportunity: wrongOwner).state,
            .invalid(.ownerMismatch)
        )
    }

    func testExactListPlanAndIntentIdentityAreRequired() {
        XCTAssertEqual(
            projection(session: makeSession(hasListOwner: false)).state,
            .invalid(.missingExactListOwner)
        )
        XCTAssertEqual(
            projection(
                session: makeSession(sourceRevision: .legacyUnknown)
            ).state,
            .invalid(.missingExactListOwner)
        )
        XCTAssertEqual(
            projection(session: makeSession(hasPlanOwner: false)).state,
            .invalid(.missingExactPlanOwner)
        )
        XCTAssertEqual(
            projection(session: makeSession(planSignature: " ")).state,
            .invalid(.invalidPlanSignature)
        )

        let session = makeSession()
        let wrongIntent = ProductStateNotificationPlanner().makeProjection(
            session: session,
            opportunity: opportunity(session),
            intent: .enabled(
                sessionID: ProductStateSessionID(rawValue: id(998)),
                currentStopID: stopID(0)
            ),
            capabilities: capabilities,
            policy: policy(),
            cause: .postCommit(receipt())
        )
        XCTAssertEqual(wrongIntent.state, .invalid(.intentOwnerMismatch))
    }

    func testPostCommitAndRecoveryInputsPreserveExactAuthority() {
        let session = makeSession()
        let wrongReceipt = receipt(revision: 6, command: 777)
        XCTAssertEqual(
            planner(
                session: session,
                cause: .postCommit(wrongReceipt)
            ).state,
            .invalid(.postCommitRevisionMissing(
                ProductStateCommandID(rawValue: id(777))
            ))
        )

        let recoveryID = id(778)
        let recovery = ProductStateReminderRecoveryInput(
            recoveryID: recoveryID,
            sessionID: sessionID,
            revision: .init(value: 7),
            snapshotID: snapshotID,
            durableAuthorityAvailable: true
        )
        let recovered = planner(
            session: session,
            cause: .recovery(recovery)
        )
        XCTAssertEqual(recovered.state, .eligible)
        XCTAssertTrue(recovered.registrations.allSatisfy {
            $0.recoveryID == recoveryID && $0.sourceCommandID == nil
        })

        let mismatch = ProductStateReminderRecoveryInput(
            recoveryID: id(779),
            sessionID: sessionID,
            revision: .init(value: 6),
            snapshotID: snapshotID,
            durableAuthorityAvailable: true
        )
        XCTAssertEqual(
            planner(session: session, cause: .recovery(mismatch)).state,
            .invalid(.recoveryOwnerMismatch(id(779)))
        )
        let nondurable = ProductStateReminderRecoveryInput(
            recoveryID: id(780),
            sessionID: sessionID,
            revision: .init(value: 7),
            snapshotID: snapshotID,
            durableAuthorityAvailable: false
        )
        XCTAssertEqual(
            planner(session: session, cause: .recovery(nondurable)).state,
            .ineligible(.durableAuthorityUnavailable)
        )
    }

    func testInvalidStopsLinesAndOpportunityAreNeverSilentlyDiscarded() {
        let unordered = makeSession(stopOrder: [1, 0, 2])
        XCTAssertEqual(
            projection(session: unordered, currentStop: 1).state,
            .invalid(.invalidStopOrder)
        )
        XCTAssertEqual(
            projection(session: makeSession(storeMissingAt: 0)).state,
            .invalid(.missingStoreIdentity(stopID(0)))
        )
        XCTAssertEqual(
            projection(session: makeSession(invalidCoordinateAt: 0)).state,
            .invalid(.invalidCoordinate(stopID(0)))
        )
        XCTAssertEqual(
            projection(session: makeSession(unresolvedLineAt: 0)).state,
            .invalid(.unresolvedLine(lineID(0)))
        )
        XCTAssertEqual(
            projection(session: makeSession(wrongLineOwnerAt: 0)).state,
            .invalid(.lineOwnerMismatch(lineID(0)))
        )
        XCTAssertEqual(
            projection(session: makeSession(invalidLineStateAt: 0)).state,
            .invalid(.invalidLineState(lineID(0)))
        )
        XCTAssertEqual(
            projection(
                session: makeSession(invalidStopQualificationAt: 2),
                policy: policy(maximum: 1, future: 0)
            ).state,
            .invalid(.invalidStop(stopID(2)))
        )

        let session = makeSession()
        let reordered = replacingOpportunity(
            opportunity(session),
            items: Array(opportunity(session).items.reversed())
        )
        XCTAssertEqual(
            planner(session: session, opportunity: reordered).state,
            .invalid(.opportunityMismatch(lineID(0)))
        )
        var duplicated = opportunity(session).items
        duplicated.append(duplicated[0])
        let duplicate = replacingOpportunity(
            opportunity(session),
            items: duplicated
        )
        XCTAssertEqual(
            planner(session: session, opportunity: duplicate).state,
            .invalid(.duplicateOpportunityLine(lineID(0)))
        )
    }

    func testCompactTokensRoundTripAndCarryNoPresentationAuthority() {
        let registration = projection(session: makeSession()).registrations[0]
        let adapter = ProductStateGeofenceNotificationProjectionAdapter()
        let platform = adapter.geofence(registration)
        let token = ProductStateOpaqueReminderToken(
            encoded: platform.identifier
        )

        XCTAssertEqual(token?.kind, .geofence)
        XCTAssertEqual(
            token?.opaqueID,
            registration.payload.geofenceID.rawValue
        )
        XCTAssertLessThan(platform.identifier.count, 48)
        for forbidden in [
            "Product 0", "Store 0", "store-0",
            listID.rawValue.uuidString, "31.5", "35.2"
        ] {
            XCTAssertFalse(platform.identifier.contains(forbidden))
        }
        XCTAssertNil(ProductStateOpaqueReminderToken(encoded: "wt-r2-g-\(id(1))"))
        XCTAssertNil(ProductStateOpaqueReminderToken(encoded: "legacy-payload"))
    }

    func testNotificationPlatformProjectionContainsOnlyOpaqueRoutingValues() {
        let (plan, ledger, route, event) = eventFixture()
        guard case let .schedule(delivery) = evaluator().evaluate(
            event: event,
            desired: plan,
            ledger: ledger,
            route: route,
            cooldown: nil
        ) else { return XCTFail("Expected delivery") }

        let platform = ProductStateGeofenceNotificationProjectionAdapter()
            .notification(delivery)
        XCTAssertEqual(Set(platform.opaqueUserInfo.keys), [
            "waytaskReminderVersion", "waytaskReminderToken"
        ])
        XCTAssertEqual(
            ProductStateOpaqueReminderToken(
                encoded: platform.identifier
            )?.opaqueID,
            delivery.notificationID.rawValue
        )
        let serialized = platform.opaqueUserInfo.description
        for forbidden in [
            "Product", "Store", "store-0", "distance",
            "latitude", "longitude", listID.rawValue.uuidString
        ] {
            XCTAssertFalse(serialized.contains(forbidden))
        }
    }

    func testReconcilerRegistersMissingDesiredProjectionDeterministically() {
        let plan = projection(session: makeSession())
        let input = ProductStateReminderReconciliationInput(
            desired: plan,
            ledger: [],
            actualGeofenceIDs: [],
            actualPendingNotificationIDs: [],
            actualDeliveredNotificationIDs: []
        )
        let first = ProductStatePostCommitReconciler().reconcile(input)
        let second = ProductStatePostCommitReconciler().reconcile(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.actions,
            plan.registrations.map {
                .register($0)
            }
        )
        XCTAssertEqual(first.diagnostics.desiredRegistrationCount, 3)
        XCTAssertEqual(first.diagnostics.reconciliationActionCount, 3)
        XCTAssertFalse(first.diagnostics.hasLedgerConflict)
    }

    func testReconcilerConvergedInputsNeedNoActions() {
        let plan = projection(session: makeSession())
        let ledger = plan.registrations.map {
            ProductStateReminderLedgerEntry(
                payload: $0.payload,
                registrationLifecycle: .registered,
                deliveryLifecycle: .idle
            )
        }
        let output = ProductStatePostCommitReconciler().reconcile(.init(
            desired: plan,
            ledger: ledger,
            actualGeofenceIDs: Set(plan.registrations.map {
                $0.payload.geofenceID
            }),
            actualPendingNotificationIDs: [],
            actualDeliveredNotificationIDs: []
        ))
        XCTAssertTrue(output.actions.isEmpty)
        XCTAssertTrue(output.issues.isEmpty)
    }

    func testReconcilerDisarmsOldRevisionAndInvalidatesItsRoute() {
        let oldPlan = projection(session: makeSession(revision: 6))
        let old = oldPlan.registrations[0]
        let terminal = projection(session: makeSession(lifecycle: .finished))
        let output = ProductStatePostCommitReconciler().reconcile(.init(
            desired: terminal,
            ledger: [.init(
                payload: old.payload,
                registrationLifecycle: .registered,
                deliveryLifecycle: .scheduled(
                    eventID: ProductStateNotificationEventID(
                        rawValue: id(700)
                    ),
                    lastSuccessfulAt: instant
                )
            )],
            actualGeofenceIDs: [old.payload.geofenceID],
            actualPendingNotificationIDs: [old.payload.notificationID],
            actualDeliveredNotificationIDs: [old.payload.notificationID]
        ))

        XCTAssertTrue(output.actions.contains(.disarm(old.payload.geofenceID)))
        XCTAssertTrue(output.actions.contains(
            .cancelPending(old.payload.notificationID)
        ))
        XCTAssertTrue(output.actions.contains(
            .removeDelivered(old.payload.notificationID)
        ))
        XCTAssertTrue(output.actions.contains(
            .recordProjectionRemoved(old.payload.registrationID)
        ))
        XCTAssertTrue(output.actions.contains(
            .invalidateNotificationNavigation(old.payload.owner)
        ))
    }

    func testReconcilerRepairsMissingAndUnknownRegistrationResults() {
        let plan = projection(session: makeSession())
        let missing = plan.registrations[0]
        let unknown = plan.registrations[1]
        let output = ProductStatePostCommitReconciler().reconcile(.init(
            desired: plan,
            ledger: [
                .init(
                    payload: missing.payload,
                    registrationLifecycle: .registered,
                    deliveryLifecycle: .idle
                ),
                .init(
                    payload: unknown.payload,
                    registrationLifecycle: .registering(attemptID: id(701)),
                    deliveryLifecycle: .idle
                )
            ],
            actualGeofenceIDs: [],
            actualPendingNotificationIDs: [],
            actualDeliveredNotificationIDs: []
        ))
        XCTAssertTrue(output.actions.contains(
            .recordMissingRegistration(missing.payload.geofenceID)
        ))
        XCTAssertTrue(output.actions.contains(.register(missing)))
        XCTAssertTrue(output.actions.contains(
            .retryUnknownRegistration(unknown.payload.geofenceID)
        ))
    }

    func testDuplicateLedgerEvidenceIsNamedAndNeverCrashes() {
        let plan = projection(session: makeSession())
        let registration = plan.registrations[0]
        let entry = ProductStateReminderLedgerEntry(
            payload: registration.payload,
            registrationLifecycle: .registered,
            deliveryLifecycle: .idle
        )
        let output = ProductStatePostCommitReconciler().reconcile(.init(
            desired: plan,
            ledger: [entry, entry],
            actualGeofenceIDs: [],
            actualPendingNotificationIDs: [],
            actualDeliveredNotificationIDs: []
        ))
        XCTAssertEqual(output.issues, [
            .duplicateLedgerRegistration(registration.payload.registrationID)
        ])
        XCTAssertTrue(output.diagnostics.hasLedgerConflict)
    }

    func testMonitoringCoordinatorDecodesOnlyTargetOpaqueIdentifiers() {
        let plan = projection(session: makeSession())
        let target = ProductStateGeofenceNotificationProjectionAdapter()
            .geofence(plan.registrations[0]).identifier
        let pending = ProductStateOpaqueReminderToken(
            kind: .notification,
            opaqueID: plan.registrations[0].payload.notificationID.rawValue
        ).encoded
        let output = ProductStateLocationMonitoringCoordinator().coordinate(
            desired: plan,
            ledger: [],
            platform: .init(
                geofenceIdentifiers: ["legacy-region", target],
                pendingNotificationIdentifiers: [pending, "invalid-request"],
                deliveredNotificationIdentifiers: ["invalid-request"]
            )
        )
        XCTAssertEqual(output.invalidGeofenceIdentifiers, ["legacy-region"])
        XCTAssertEqual(output.invalidNotificationIdentifiers, ["invalid-request"])
        XCTAssertEqual(
            output.reconciliation.actualGeofenceIDs,
            [plan.registrations[0].payload.geofenceID]
        )
    }

    func testTriggerEvaluationReturnsExactImmutableDelivery() {
        let (plan, ledger, route, event) = eventFixture()
        let outcome = evaluator().evaluate(
            event: event,
            desired: plan,
            ledger: ledger,
            route: route,
            cooldown: nil
        )
        guard case let .schedule(delivery) = outcome else {
            return XCTFail("Expected exact delivery, got \(outcome)")
        }
        let registration = plan.registrations[0]
        XCTAssertEqual(delivery.notificationID, registration.payload.notificationID)
        XCTAssertEqual(delivery.triggerID, registration.payload.triggerID)
        XCTAssertEqual(delivery.eventID, event.eventID)
        XCTAssertEqual(delivery.owner, registration.payload.owner)
        XCTAssertEqual(delivery.stopID, registration.payload.stopID)
        XCTAssertEqual(delivery.storeID, registration.payload.storeID)
        XCTAssertEqual(delivery.lineIDs, registration.lineIDs)
        XCTAssertEqual(delivery.entryIDs, registration.entryIDs)
        XCTAssertEqual(delivery.productIDs, registration.productIDs)
        XCTAssertEqual(
            delivery.content,
            .remainingLinesAtSessionStop(count: 1)
        )
    }

    func testTriggerValidationSuppressesStaleUnavailableAndMismatchedEvents() {
        let (plan, ledger, route, event) = eventFixture()
        let stale = replacingRoute(route, route: .safeShopping(.snapshotChanged))
        XCTAssertEqual(
            evaluator().evaluate(
                event: event,
                desired: plan,
                ledger: ledger,
                route: stale,
                cooldown: nil
            ),
            .stale(.snapshotChanged)
        )
        let unavailable = replacingRoute(route, route: .suppressed(.notFound))
        XCTAssertEqual(
            evaluator().evaluate(
                event: event,
                desired: plan,
                ledger: ledger,
                route: unavailable,
                cooldown: nil
            ),
            .suppressed(.notFound)
        )
        var wrongEvent = event
        wrongEvent = .init(
            geofenceID: ProductStateGeofenceID(rawValue: id(987)),
            triggerID: event.triggerID,
            eventID: event.eventID,
            occurredAt: event.occurredAt
        )
        XCTAssertEqual(
            evaluator().evaluate(
                event: wrongEvent,
                desired: plan,
                ledger: ledger,
                route: route,
                cooldown: nil
            ),
            .invalid
        )
    }

    func testTriggerCooldownAndIdempotencyNeverMutateLifecycle() {
        let (plan, ledger, route, event) = eventFixture()
        let scheduled = ProductStateReminderLedgerEntry(
            payload: ledger.payload,
            registrationLifecycle: .registered,
            deliveryLifecycle: .scheduled(
                eventID: ProductStateNotificationEventID(rawValue: id(801)),
                lastSuccessfulAt: instant
            )
        )
        let withinCooldown = ProductStateGeofenceEvent(
            geofenceID: event.geofenceID,
            triggerID: event.triggerID,
            eventID: ProductStateNotificationEventID(rawValue: id(802)),
            occurredAt: instant.addingTimeInterval(10)
        )
        XCTAssertEqual(
            evaluator().evaluate(
                event: withinCooldown,
                desired: plan,
                ledger: scheduled,
                route: route,
                cooldown: nil
            ),
            .cooldown(until: instant.addingTimeInterval(policy().cooldown))
        )
        let duplicate = ProductStateGeofenceEvent(
            geofenceID: event.geofenceID,
            triggerID: event.triggerID,
            eventID: ProductStateNotificationEventID(rawValue: id(801)),
            occurredAt: instant.addingTimeInterval(policy().cooldown + 1)
        )
        XCTAssertEqual(
            evaluator().evaluate(
                event: duplicate,
                desired: plan,
                ledger: scheduled,
                route: route,
                cooldown: nil
            ),
            .duplicateSucceeded
        )

        let revisedSession = makeSession(revision: 8)
        let revisedPlan = projection(session: revisedSession)
        let revisedRegistration = revisedPlan.registrations[0]
        let revisedLedger = ProductStateReminderLedgerEntry(
            payload: revisedRegistration.payload,
            registrationLifecycle: .registered,
            deliveryLifecycle: .idle
        )
        let revisedEvent = ProductStateGeofenceEvent(
            geofenceID: revisedRegistration.payload.geofenceID,
            triggerID: revisedRegistration.payload.triggerID,
            eventID: ProductStateNotificationEventID(rawValue: id(803)),
            occurredAt: instant.addingTimeInterval(10)
        )
        XCTAssertEqual(
            evaluator().evaluate(
                event: revisedEvent,
                desired: revisedPlan,
                ledger: revisedLedger,
                route: self.route(revisedRegistration.payload.owner),
                cooldown: .init(
                    sessionID: sessionID,
                    stopID: stopID(0),
                    lastSuccessfulAt: instant
                )
            ),
            .cooldown(until: instant.addingTimeInterval(policy().cooldown))
        )
        XCTAssertEqual(plan.owner, ledger.payload.owner)
    }

    func testSchedulingResultRecordsCooldownOnlyAfterSuccess() {
        let (plan, ledger, route, event) = eventFixture()
        guard case let .schedule(delivery) = evaluator().evaluate(
            event: event,
            desired: plan,
            ledger: ledger,
            route: route,
            cooldown: nil
        ) else { return XCTFail("Expected delivery") }
        let projector = ProductStateNotificationSchedulingResultProjector()
        XCTAssertEqual(
            projector.project(
                delivery: delivery,
                result: .succeeded(at: instant)
            ),
            .recordSuccessfulSchedule(
                delivery.notificationID,
                eventID: delivery.eventID,
                sessionID: delivery.sessionID,
                stopID: delivery.stopID,
                successfulAt: instant
            )
        )
        XCTAssertEqual(
            projector.project(
                delivery: delivery,
                result: .failed(code: "platform-add-failed")
            ),
            .recordRetryableFailure(
                delivery.notificationID,
                eventID: delivery.eventID,
                code: "platform-add-failed"
            )
        )
        let attempt = id(804)
        XCTAssertEqual(
            projector.project(
                delivery: delivery,
                result: .unknown(attemptID: attempt)
            ),
            .recordUnknownResult(
                delivery.notificationID,
                eventID: delivery.eventID,
                attemptID: attempt
            )
        )
    }

    func testTapRoutingRevalidatesExactOwnerAndNeverOpensMap() {
        let plan = projection(session: makeSession())
        let registration = plan.registrations[0]
        let token = ProductStateOpaqueReminderToken(
            kind: .notification,
            opaqueID: registration.payload.notificationID.rawValue
        ).encoded
        let current = route(registration.payload.owner)
        let projector = ProductStateNotificationNavigationIntentProjector()
        XCTAssertEqual(
            projector.project(
                notificationToken: token,
                desired: plan,
                route: current
            ),
            .shoppingSession(sessionID: sessionID, stopID: stopID(0))
        )
        XCTAssertEqual(
            projector.project(
                notificationToken: token,
                desired: plan,
                route: replacingRoute(
                    current,
                    route: .safeShopping(.sourceRevisionChanged)
                )
            ),
            .safeShopping(.sourceRevisionChanged)
        )
        XCTAssertEqual(
            projector.project(
                notificationToken: token,
                desired: plan,
                route: replacingRoute(current, route: .suppressed(.notFound))
            ),
            .suppressed(.notFound)
        )
        XCTAssertEqual(
            projector.project(
                notificationToken: "legacy-payload",
                desired: plan,
                route: current
            ),
            .invalid
        )
    }

    func testT20BoundaryContainsNoPersistenceOrRuntimeActivation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reconciler = try String(
            contentsOf: root.appendingPathComponent(
                "WayTask/ProductState/Infrastructure/" +
                "ProductStatePostCommitReconciler.swift"
            ),
            encoding: .utf8
        )
        for forbidden in [
            "import SwiftData", "ModelContext", ".save(",
            "UNUserNotificationCenter", "CLLocationManager",
            "startMonitoring", "requestAuthorization", "openURL",
            "isQuiet", "case quiet"
        ] {
            XCTAssertFalse(reconciler.contains(forbidden), forbidden)
        }

        let sources = [
            ("GeofenceNotificationService.swift",
             "// MARK: - T-20 inactive Product State platform projections"),
            ("WayTask/LocationManager.swift",
             "// MARK: - T-20 inactive monitoring coordination boundary"),
            ("WayTask/AppStateManager.swift",
             "// MARK: - T-20 inactive exact notification navigation intent")
        ]
        for (path, marker) in sources {
            let source = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            let target = try XCTUnwrap(source.components(
                separatedBy: marker
            ).last)
            for forbidden in [
                ".add(", "startMonitoring(", "requestAuthorization(",
                "requestAlwaysAuthorization(", "ModelContext", ".save(",
                "openShoppingNotificationOnMap("
            ] {
                XCTAssertFalse(target.contains(forbidden), "\(path): \(forbidden)")
            }
        }
    }

    func testPlannerProducesTwelveRegionsWithinBoundedTime() {
        let session = makeSession(stopCount: 12)
        let policy = policy(maximum: 12, future: 11)
        let clock = ContinuousClock()
        let start = clock.now
        let plan = projection(session: session, policy: policy)
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(plan.registrations.count, 12)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    // MARK: - Fixtures

    private let instant = Date(timeIntervalSince1970: 2_000_000_000)
    private var sessionID: ProductStateSessionID {
        ProductStateSessionID(rawValue: id(1))
    }

    private var snapshotID: ProductStateSessionSnapshotID {
        ProductStateSessionSnapshotID(rawValue: id(2))
    }

    private var listID: ProductStateListID {
        ProductStateListID(rawValue: id(3))
    }

    private var planID: ProductStatePlanID {
        ProductStatePlanID(rawValue: id(4))
    }

    private var commandID: ProductStateCommandID {
        ProductStateCommandID(rawValue: id(5))
    }

    private var capabilities: ProductStateReminderCapabilityProjection {
        .init(
            notificationAuthorization: .authorized,
            locationAuthorization: .always,
            preciseLocationAvailable: true,
            regionMonitoringAvailable: true,
            backgroundRefreshAvailable: true,
            durableAuthorityAvailable: true
        )
    }

    private func policy(
        maximum: Int = 3,
        future: Int = 2
    ) -> ProductStateReminderRegionPolicy {
        .init(
            maximumRegionCount: maximum,
            approvedFutureStopCount: future,
            radiusMeters: 200,
            cooldown: ProductStateReminderRegionPolicy.requiredCooldown
        )
    }

    private func projection(
        session: ProductStateSessionSnapshotProjection,
        currentStop: Int = 0,
        policy: ProductStateReminderRegionPolicy? = nil
    ) -> ProductStateNotificationPlanProjection {
        planner(
            session: session,
            intent: .enabled(
                sessionID: sessionID,
                currentStopID: stopID(currentStop)
            ),
            policy: policy ?? self.policy()
        )
    }

    private func planner(
        session: ProductStateSessionSnapshotProjection,
        opportunity: ProductStateNotificationOpportunityProjection? = nil,
        intent: ProductStateReminderIntent? = nil,
        policy: ProductStateReminderRegionPolicy? = nil,
        cause: ProductStateReminderPlanningCause? = nil
    ) -> ProductStateNotificationPlanProjection {
        ProductStateNotificationPlanner().makeProjection(
            session: session,
            opportunity: opportunity ?? self.opportunity(session),
            intent: intent ?? .enabled(
                sessionID: sessionID,
                currentStopID: stopID(0)
            ),
            capabilities: capabilities,
            policy: policy ?? self.policy(),
            cause: cause ?? .postCommit(receipt(revision: session.revision.value))
        )
    }

    private func makeSession(
        stopCount: Int = 3,
        remainingStops: Set<Int>? = nil,
        lifecycle: ShoppingSessionLifecycle? = .active,
        lifecycleRawValue: String = "active",
        revision: UInt64 = 7,
        freshness: ProductStateProjectionFreshness = .current,
        hasListOwner: Bool = true,
        sourceRevision: ShoppingSessionSourceRevision? = nil,
        hasPlanOwner: Bool = true,
        planSignature: String? = "plan-signature-v1",
        stopOrder: [Int]? = nil,
        storeMissingAt: Int? = nil,
        invalidCoordinateAt: Int? = nil,
        unresolvedLineAt: Int? = nil,
        invalidStopQualificationAt: Int? = nil,
        wrongLineOwnerAt: Int? = nil,
        invalidLineStateAt: Int? = nil
    ) -> ProductStateSessionSnapshotProjection {
        let included = remainingStops ?? Set(0..<stopCount)
        let order = stopOrder ?? Array(0..<stopCount)
        let stops = order.map { index in
            ProductStateSessionStopProjection(
                id: stopID(index),
                sortOrder: index,
                storeReferenceID: storeMissingAt == index
                    ? nil : "store-\(index)",
                storeReferenceProvenanceRawValue: "published",
                displayNameSnapshot: "Store \(index)",
                latitudeSnapshot: invalidCoordinateAt == index
                    ? 100 : 31.5 + Double(index) / 100,
                longitudeSnapshot: 35.2 + Double(index) / 100,
                evidenceAt: instant,
                isSessionScopedTransient: false,
                qualification: invalidStopQualificationAt == index
                    ? .unresolved : .qualified
            )
        }
        let lines = (0..<stopCount).map { index in
            ProductStateSessionLineProjection(
                id: lineID(index),
                snapshotID: snapshotID,
                sourceListID: wrongLineOwnerAt == index
                    ? ProductStateListID(rawValue: id(990)) : self.listID,
                sourceEntryID: entryID(index),
                productID: productID(index),
                stopID: stopID(index),
                sortOrder: index,
                productNameSnapshot: "Product \(index)",
                productBrandSnapshot: nil,
                productCategorySnapshot: nil,
                quantitySnapshot: 1,
                unitSnapshotRawValue: nil,
                noteSnapshot: nil,
                executionState: invalidLineStateAt == index
                    ? nil : (included.contains(index) ? .remaining : .collected),
                executionStateRawValue: invalidLineStateAt == index
                    ? "future" : (included.contains(index)
                        ? "remaining" : "collected"),
                finalOutcome: nil,
                finalOutcomeRawValue: nil,
                legacyDisposition: nil,
                qualification: unresolvedLineAt == index
                    ? .unresolved : .qualified
            )
        }
        return ProductStateSessionSnapshotProjection(
            id: sessionID,
            revision: .init(value: revision),
            lifecycle: lifecycle,
            lifecycleRawValue: lifecycle?.rawValue ?? lifecycleRawValue,
            migrationCondition: .native,
            migrationConditionRawValue: "native",
            snapshotID: snapshotID,
            snapshotVersion: 1,
            snapshotGeneration: 1,
            snapshotContentSignature: "snapshot-signature",
            sourceListID: hasListOwner ? self.listID : nil,
            sourceRevision: sourceRevision ?? .exact(.init(value: 11)),
            sourcePlanID: hasPlanOwner ? self.planID : nil,
            sourcePlanSignature: planSignature,
            sourcePlanEvidenceAt: instant,
            stops: stops,
            lines: lines,
            exceptions: [],
            metadata: metadata(revision: revision, freshness: freshness)
        )
    }

    private func opportunity(
        _ session: ProductStateSessionSnapshotProjection
    ) -> ProductStateNotificationOpportunityProjection {
        .init(
            owner: .session(session.id, session.revision, session.snapshotID),
            items: session.lines.map { line in
                .init(
                    productID: line.productID,
                    entryID: line.sourceEntryID,
                    sessionLineID: line.id,
                    displayNameSnapshot: line.productNameSnapshot,
                    isQualified: line.qualification == .qualified
                )
            },
            metadata: metadata(
                revision: session.revision.value,
                freshness: session.metadata.freshness
            )
        )
    }

    private func replacingOpportunity(
        _ value: ProductStateNotificationOpportunityProjection,
        owner: ProductStateShoppingContextOwner? = nil,
        items: [ProductStateShoppingContextItemProjection]? = nil,
        freshness: ProductStateProjectionFreshness? = nil
    ) -> ProductStateNotificationOpportunityProjection {
        return .init(
            owner: owner ?? value.owner,
            items: items ?? value.items,
            metadata: .init(
                scope: value.metadata.scope,
                freshness: freshness ?? value.metadata.freshness,
                listRevision: value.metadata.listRevision,
                sessionRevision: value.metadata.sessionRevision,
                sessionSnapshotID: value.metadata.sessionSnapshotID,
                provenances: value.metadata.provenances,
                omissions: value.metadata.omissions,
                cachePolicy: value.metadata.cachePolicy
            )
        )
    }

    private func metadata(
        revision: UInt64,
        freshness: ProductStateProjectionFreshness
    ) -> ProductStateProjectionMetadata {
        .init(
            scope: .session(sessionID),
            freshness: freshness,
            listRevision: nil,
            sessionRevision: .init(value: revision),
            sessionSnapshotID: snapshotID,
            provenances: [.frozenSessionSnapshot],
            omissions: [],
            cachePolicy: .disabledDirectRebuild
        )
    }

    private func receipt(
        revision: UInt64 = 7,
        command: Int = 5
    ) -> ProductStateCommandReceipt {
        .init(
            commandID: ProductStateCommandID(rawValue: id(command)),
            effects: .init(
                revisionChanges: [.init(
                    before: .init(
                        scope: .session(sessionID),
                        value: revision > 0 ? revision - 1 : 0
                    ),
                    after: .init(
                        scope: .session(sessionID),
                        value: revision
                    )
                )],
                historyEventIDs: []
            )
        )
    }

    private func route(
        _ owner: ProductStateNotificationPayloadOwner
    ) -> ProductStateNotificationRouteProjection {
        .init(
            payloadOwner: owner,
            route: .session(sessionID),
            metadata: metadata(revision: 7, freshness: .current)
        )
    }

    private func replacingRoute(
        _ value: ProductStateNotificationRouteProjection,
        route: ProductStateNotificationRoute
    ) -> ProductStateNotificationRouteProjection {
        .init(
            payloadOwner: value.payloadOwner,
            route: route,
            metadata: value.metadata
        )
    }

    private func eventFixture() -> (
        ProductStateNotificationPlanProjection,
        ProductStateReminderLedgerEntry,
        ProductStateNotificationRouteProjection,
        ProductStateGeofenceEvent
    ) {
        let plan = projection(session: makeSession())
        let registration = plan.registrations[0]
        let ledger = ProductStateReminderLedgerEntry(
            payload: registration.payload,
            registrationLifecycle: .registered,
            deliveryLifecycle: .idle
        )
        let event = ProductStateGeofenceEvent(
            geofenceID: registration.payload.geofenceID,
            triggerID: registration.payload.triggerID,
            eventID: ProductStateNotificationEventID(rawValue: id(800)),
            occurredAt: instant
        )
        return (plan, ledger, route(registration.payload.owner), event)
    }

    private func evaluator() -> ProductStateNotificationTriggerEvaluator {
        ProductStateNotificationTriggerEvaluator()
    }

    private func stopID(_ value: Int) -> ProductStateSessionStopID {
        ProductStateSessionStopID(rawValue: id(100 + value))
    }

    private func lineID(_ value: Int) -> ProductStateSessionLineID {
        ProductStateSessionLineID(rawValue: id(200 + value))
    }

    private func entryID(_ value: Int) -> ProductStateListEntryID {
        ProductStateListEntryID(rawValue: id(300 + value))
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: id(400 + value))
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }
}
