import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateShoppingSessionAuthorityTests: XCTestCase {
    func testStartPersistsExactFrozenIdentityOrderingAndImmutableProjections()
        throws {
        let fixture = try makeFixture("start")
        try seed(fixture, lineCount: 2, listRevision: 5)
        let input = startInput(command: 100, lineCount: 2, listRevision: 5)

        let execution = authority(fixture).start(input)

        guard case let .started(summary, freshness) = execution.outcome else {
            return XCTFail("Expected committed Start, got \(execution.outcome)")
        }
        XCTAssertTrue(execution.claimsDurableSuccess)
        XCTAssertEqual(freshness, .fresh)
        XCTAssertEqual(summary.sessionID, sessionID)
        XCTAssertEqual(summary.sourceListID, listID)
        XCTAssertEqual(summary.sourceRevision, .exact(.init(value: 5)))
        XCTAssertEqual(summary.sourcePlanID, planID)
        XCTAssertEqual(summary.sourcePlanFingerprint, "plan-fingerprint-v1")
        XCTAssertEqual(summary.snapshotID, snapshotID)
        XCTAssertEqual(summary.revisionBefore.value, 0)
        XCTAssertEqual(summary.revisionAfter.value, 1)
        XCTAssertEqual(summary.lineIDs, [lineID(0), lineID(1)])
        XCTAssertEqual(summary.stopIDs, [stopID(0), stopID(1)])
        XCTAssertEqual(summary.snapshotContentSignature.count, 64)

        let session = try fetchSession(fixture)
        XCTAssertEqual(session.lifecycleRawValue, "active")
        XCTAssertEqual(session.migrationConditionRawValue, "native")
        XCTAssertEqual(session.sourceRevisionProvenanceRawValue, "exact")
        XCTAssertEqual(session.snapshotVersion, 1)
        XCTAssertEqual(session.snapshotGeneration, 1)
        XCTAssertEqual(session.sourcePlanID, planID.rawValue)
        XCTAssertEqual(try lines(fixture).map(\.sourceEntryID), [
            entryID(0).rawValue, entryID(1).rawValue
        ])
        XCTAssertEqual(try lines(fixture).map(\.productID), [
            productID(0).rawValue, productID(1).rawValue
        ])
        XCTAssertEqual(try stops(fixture).map(\.storeReferenceIDRawValue), [
            "store-0", "store-1"
        ])

        let queries = ProductStateQueryBoundary(repositories: fixture.repositories)
        guard case let .projection(active) = queries.activeSessions() else {
            return XCTFail("Expected immutable active lookup")
        }
        XCTAssertEqual(active.candidates.map(\.sessionID), [sessionID])
        guard case let .projection(snapshot) = queries.sessionSnapshot(
            ProductStateSessionSnapshotRequest(
                sessionID: sessionID,
                expectedRevision: ProductStateSessionRevision(value: 1)
            )
        ) else { return XCTFail("Expected immutable Session snapshot") }
        XCTAssertEqual(snapshot.lines.map(\.id), [lineID(0), lineID(1)])
        XCTAssertEqual(snapshot.stops.map(\.id), [stopID(0), stopID(1)])
        let map = queries.mapContext(session: snapshot)
        XCTAssertEqual(map.owner, .session(sessionID, .init(value: 1), snapshotID))
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testStartRejectsSilentReuseAndMultipleRecoveryCandidates() throws {
        let fixture = try makeFixture("conflicts")
        try seed(fixture, lineCount: 1, listRevision: 2)
        let exactStart = startInput(command: 110, lineCount: 1, listRevision: 2)
        let first = authority(fixture).start(exactStart)
        guard case .started = first.outcome else {
            return XCTFail("Expected first Start")
        }
        let retryExecution = authority(fixture).start(exactStart)
        guard case let .started(retried, _) = retryExecution.outcome else {
            return XCTFail(
                "Expected same-command Start reconciliation, got " +
                "\(retryExecution.outcome)"
            )
        }
        XCTAssertEqual(retried.revisionAfter.value, 1)
        XCTAssertEqual(try countSessions(fixture), 1)

        let unrelated = authority(fixture).start(startInput(
            command: 111,
            session: id(900),
            snapshot: id(901),
            lineCount: 1,
            listRevision: 2
        ))
        XCTAssertEqual(
            unrelated.outcome,
            .conflict(.nonTerminalSessions([sessionID]))
        )
        XCTAssertEqual(try countSessions(fixture), 1)

        let duplicate = makeNativeSession(
            session: id(902), snapshot: id(903), lifecycle: .expired,
            revision: 2, listRevision: 2
        )
        fixture.repositories.sessions.stageInsertion(of: duplicate)
        try fixture.context.save()
        let multiple = authority(fixture).start(startInput(
            command: 112,
            session: id(904),
            snapshot: id(905),
            lineCount: 1,
            listRevision: 2
        ))
        guard case let .conflict(.nonTerminalSessions(ids)) = multiple.outcome else {
            return XCTFail("Expected explicit multiple-candidate conflict")
        }
        XCTAssertEqual(Set(ids), Set([sessionID, ProductStateSessionID(rawValue: id(902))]))

        guard case .conflict(.nonTerminalSessions) = authority(fixture).collect(
            sessionLineCommand(
                command: 113, revision: 1, line: lineID(0), collect: true
            )
        ).outcome else {
            return XCTFail("Expected multiple candidates to block normal mutation")
        }
        guard case .cancelled = authority(fixture).abandon(
            sessionCommand(command: 114, revision: 1, kind: .abandon)
        ).outcome else {
            return XCTFail("Expected explicit Abandon to resolve one candidate")
        }
    }

    func testStartPlanFreshnessRequiresExactConfirmationAndRejectsInvalidAge()
        throws {
        let fresh = try makeFixture("plan-freshness")
        try seed(fresh, lineCount: 1, listRevision: 1)
        var stale = startInput(command: 120, lineCount: 1, listRevision: 1)
        stale = replacingEvidence(
            stale,
            evidenceAt: instant.addingTimeInterval(-2 * 24 * 60 * 60),
            confirmed: nil
        )
        guard case let .invalid(.stalePlanConfirmationRequired(date)) =
                authority(fresh).start(stale).outcome else {
            return XCTFail("Expected explicit stale confirmation")
        }
        XCTAssertEqual(date, stale.planEvidenceAt)
        XCTAssertEqual(try countSessions(fresh), 0)

        stale = replacingEvidence(
            stale,
            evidenceAt: stale.planEvidenceAt,
            confirmed: stale.planEvidenceAt
        )
        guard case let .started(_, .staleConfirmed(evidenceAt)) =
                authority(fresh).start(stale).outcome else {
            return XCTFail("Expected confirmed stale Start")
        }
        XCTAssertEqual(evidenceAt, stale.planEvidenceAt)

        let future = try makeFixture("plan-future")
        try seed(future, lineCount: 1, listRevision: 1)
        let futureInput = replacingEvidence(
            startInput(command: 121, lineCount: 1, listRevision: 1),
            evidenceAt: instant.addingTimeInterval(1),
            confirmed: nil
        )
        XCTAssertEqual(
            authority(future).start(futureInput).outcome,
            .invalid(.planEvidenceInFuture)
        )

        let expired = try makeFixture("plan-expired")
        try seed(expired, lineCount: 1, listRevision: 1)
        let expiredInput = replacingEvidence(
            startInput(command: 122, lineCount: 1, listRevision: 1),
            evidenceAt: instant.addingTimeInterval(-8 * 24 * 60 * 60),
            confirmed: instant.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        XCTAssertEqual(
            authority(expired).start(expiredInput).outcome,
            .invalid(.planEvidenceExpired)
        )
    }

    func testCollectUndoAndFinishDraftAreExplicitDeterministicAndReadOnly()
        throws {
        let fixture = try startedFixture("progress", lineCount: 1)
        let target = lineID(0)
        let collect = sessionLineCommand(
            command: 130, revision: 1, line: target, collect: true
        )
        XCTAssertEqual(collect.category, .markLineCollected)
        let collectedExecution = authority(fixture).collect(collect)
        guard case let .lineCollected(summary, line) =
                collectedExecution.outcome else {
            return XCTFail("Expected Collect, got \(collectedExecution.outcome)")
        }
        XCTAssertEqual(line, target)
        XCTAssertEqual(summary.revisionAfter.value, 2)
        XCTAssertEqual(try lines(fixture).first?.executionStateRawValue, "collected")
        XCTAssertTrue(try history(fixture).isEmpty)
        XCTAssertEqual(try fetchList(fixture).revision, 4)
        guard case .lineCollected = authority(fixture).collect(collect).outcome else {
            return XCTFail("Expected same-command Collect reconciliation")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 2)

        let sameState = authority(fixture).collect(
            sessionLineCommand(
                command: 131, revision: 2, line: target, collect: true
            )
        )
        guard case let .noOp(state) = sameState.outcome else {
            return XCTFail("Expected deterministic no-op")
        }
        XCTAssertEqual(state.revision.value, 2)

        let draft = finishDraftCommand(command: 132, revision: 2, line: target)
        guard case .finishReviewReady =
                authority(fixture).prepareFinishOutcome(draft).outcome else {
            return XCTFail("Expected read-only Finish draft")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 2)
        XCTAssertNil(try lines(fixture).first?.finalOutcomeRawValue)
        XCTAssertFalse(fixture.context.hasChanges)

        let undo = sessionLineCommand(
            command: 133, revision: 2, line: target, collect: false
        )
        guard case let .lineCollectionUndone(summary, _) =
                authority(fixture).undoCollection(undo).outcome else {
            return XCTFail("Expected Undo")
        }
        XCTAssertEqual(summary.revisionAfter.value, 3)
        XCTAssertEqual(try lines(fixture).first?.executionStateRawValue, "remaining")
        XCTAssertTrue(try history(fixture).isEmpty)
    }

    func testStopActivitiesAreExactIdempotentSessionOnlyMeaningfulActivity()
        throws {
        let fixture = try startedFixture("stop-activity", lineCount: 2)
        let beforeList = try fetchList(fixture).revision
        let first = ProductStateSessionStopActivityCommand(
            id: commandID(134),
            sessionID: sessionID,
            expectedRevision: .init(value: 1),
            stopID: stopID(1),
            activity: .selected,
            effectiveAt: instant.addingTimeInterval(134)
        )
        guard case let .stopActivityRecorded(summary, stop, activity) =
                authority(fixture).recordStopActivity(first).outcome else {
            return XCTFail("Expected exact stop selection activity")
        }
        XCTAssertEqual(stop, stopID(1))
        XCTAssertEqual(activity, .selected)
        XCTAssertEqual(summary.revisionAfter.value, 2)
        guard case .stopActivityRecorded =
                authority(fixture).recordStopActivity(first).outcome else {
            return XCTFail("Expected idempotent activity reconciliation")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 2)

        for (offset, activity) in [
            ProductStateSessionStopActivity.completed,
            .skipped,
            .externalNavigationStarted
        ].enumerated() {
            let revision = UInt64(2 + offset)
            let command = ProductStateSessionStopActivityCommand(
                id: commandID(135 + offset),
                sessionID: sessionID,
                expectedRevision: .init(value: revision),
                stopID: stopID(offset % 2),
                activity: activity,
                effectiveAt: instant.addingTimeInterval(Double(135 + offset))
            )
            guard case let .stopActivityRecorded(value, _, recorded) =
                    authority(fixture).recordStopActivity(command).outcome else {
                return XCTFail("Expected \(activity) activity")
            }
            XCTAssertEqual(recorded, activity)
            XCTAssertEqual(value.revisionAfter.value, revision + 1)
        }

        XCTAssertEqual(try fetchSession(fixture).revision, 5)
        XCTAssertEqual(
            try fetchSession(fixture).lastActivityAt,
            instant.addingTimeInterval(137)
        )
        XCTAssertEqual(try fetchList(fixture).revision, beforeList)
        XCTAssertTrue(try history(fixture).isEmpty)
        XCTAssertTrue(try lines(fixture).allSatisfy {
            $0.executionStateRawValue == "remaining"
                && $0.finalOutcomeRawValue == nil
        })
    }

    func testExpirationAndResumeUseExactBoundariesAndRejectStaleRevision()
        throws {
        let fixture = try startedFixture("expire-resume", lineCount: 1)
        let early = ProductStateExpireSessionCommand(
            id: commandID(140),
            sessionID: sessionID,
            expectedRevision: .init(value: 1),
            effectiveAt: instant.addingTimeInterval(12 * 60 * 60 - 1)
        )
        XCTAssertEqual(
            authority(fixture).expire(early).outcome,
            .invalid(.expirationNotDue)
        )

        let due = ProductStateExpireSessionCommand(
            id: commandID(141),
            sessionID: sessionID,
            expectedRevision: .init(value: 1),
            effectiveAt: instant.addingTimeInterval(12 * 60 * 60)
        )
        guard case let .expired(expired) = authority(fixture).expire(due).outcome else {
            return XCTFail("Expected explicit Expire")
        }
        XCTAssertEqual(expired.revisionAfter.value, 2)
        XCTAssertEqual(try fetchSession(fixture).expirationReasonRawValue, "inactivity")
        guard case .expired = authority(fixture).expire(due).outcome else {
            return XCTFail("Expected same-command Expire reconciliation")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 2)

        let stale = authority(fixture).resume(
            sessionCommand(command: 142, revision: 1, kind: .resume)
        )
        XCTAssertEqual(
            stale.outcome,
            .conflict(.staleSessionRevision(
                expected: .init(value: 1), actual: .init(value: 2)
            ))
        )
        let resumeAt = due.effectiveAt.addingTimeInterval(10)
        guard case let .resumed(resumed) = authority(fixture).resume(
            sessionCommand(
                command: 143, revision: 2, kind: .resume,
                effectiveAt: resumeAt
            )
        ).outcome else { return XCTFail("Expected Resume") }
        XCTAssertEqual(resumed.revisionAfter.value, 3)
        let stored = try fetchSession(fixture)
        XCTAssertEqual(stored.lifecycleRawValue, "active")
        XCTAssertEqual(stored.activationStartedAt, resumeAt)
        XCTAssertEqual(stored.lastActivityAt, resumeAt)
        XCTAssertNil(stored.expiredAt)
        XCTAssertNil(stored.expirationReasonRawValue)
        guard case .resumed = authority(fixture).resume(
            sessionCommand(
                command: 143, revision: 2, kind: .resume,
                effectiveAt: resumeAt
            )
        ).outcome else {
            return XCTFail("Expected same-command Resume reconciliation")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 3)
    }

    func testExpiredFinishReviewAndBackdatedTransitionsFailClosed() throws {
        let fixture = try startedFixture("transition-time", lineCount: 1)
        let backdated = ProductStateCommand(
            id: commandID(144),
            expectedRevision: expectedSessionRevision(1),
            effectiveAt: instant.addingTimeInterval(-1),
            intent: .markLineCollected(.init(
                sessionID: sessionID, lineID: lineID(0)
            ))
        )
        XCTAssertEqual(
            authority(fixture).collect(backdated).outcome,
            .invalid(.invalidTransitionTime)
        )
        XCTAssertEqual(try fetchSession(fixture).revision, 1)

        let expireAt = instant.addingTimeInterval(12 * 60 * 60)
        guard case .expired = authority(fixture).expire(.init(
            id: commandID(145),
            sessionID: sessionID,
            expectedRevision: .init(value: 1),
            effectiveAt: expireAt
        )).outcome else { return XCTFail("Expected Expire") }
        let queries = ProductStateQueryBoundary(repositories: fixture.repositories)
        guard case let .projection(review) = queries.finishReview(.init(
            session: .init(sessionID: sessionID, expectedRevision: .init(value: 2)),
            proposedOutcomes: [lineID(0): .purchased]
        )) else { return XCTFail("Expected bounded Finish review") }
        XCTAssertEqual(review.status, .invalidSession)

        XCTAssertEqual(
            authority(fixture).resume(sessionCommand(
                command: 146,
                revision: 2,
                kind: .resume,
                effectiveAt: expireAt.addingTimeInterval(-1)
            )).outcome,
            .invalid(.invalidTransitionTime)
        )
        XCTAssertEqual(try fetchSession(fixture).lifecycleRawValue, "expired")
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testAbandonRetainsSnapshotProgressAndHasNoListProductOrHistoryEffects()
        throws {
        let fixture = try startedFixture("abandon", lineCount: 2)
        _ = authority(fixture).collect(
            sessionLineCommand(
                command: 150, revision: 1, line: lineID(0), collect: true
            )
        )
        let beforeList = try fetchList(fixture).revision
        let beforeProductIDs = try products(fixture).map(\.id)
        let beforeProductRevisions = try products(fixture).map(\.revision)
        let signature = try fetchSession(fixture).snapshotContentSignature

        let abandonedExecution = authority(fixture).abandon(
            sessionCommand(command: 151, revision: 2, kind: .abandon)
        )
        guard case let .cancelled(summary) = abandonedExecution.outcome else {
            return XCTFail("Expected Abandon, got \(abandonedExecution.outcome)")
        }

        XCTAssertEqual(summary.lifecycle, .abandoned)
        XCTAssertEqual(summary.revisionAfter.value, 3)
        XCTAssertEqual(try fetchSession(fixture).snapshotContentSignature, signature)
        XCTAssertEqual(try lines(fixture).first?.executionStateRawValue, "collected")
        XCTAssertTrue(try lines(fixture).allSatisfy { $0.finalOutcomeRawValue == nil })
        XCTAssertEqual(try fetchList(fixture).revision, beforeList)
        XCTAssertEqual(try products(fixture).map(\.id), beforeProductIDs)
        XCTAssertEqual(
            try products(fixture).map(\.revision), beforeProductRevisions
        )
        XCTAssertTrue(try history(fixture).isEmpty)
        guard case .cancelled = authority(fixture).abandon(
            sessionCommand(command: 151, revision: 2, kind: .abandon)
        ).outcome else {
            return XCTFail("Expected same-command Abandon reconciliation")
        }
        XCTAssertEqual(try fetchSession(fixture).revision, 3)
    }

    func testResumePreservesFrozenRevisionWhileAllowingUncapturedListAdditions()
        throws {
        let fixture = try startedFixture("resume-list-advance", lineCount: 1)
        let due = ProductStateExpireSessionCommand(
            id: commandID(152), sessionID: sessionID,
            expectedRevision: .init(value: 1),
            effectiveAt: instant.addingTimeInterval(12 * 60 * 60)
        )
        guard case .expired = authority(fixture).expire(due).outcome else {
            return XCTFail("Expected Expire")
        }
        let list = try fetchList(fixture)
        list.revision = 5
        list.updatedAt = due.effectiveAt
        try fixture.context.save()

        let resumeAt = due.effectiveAt.addingTimeInterval(1)
        guard case let .resumed(summary) = authority(fixture).resume(
            sessionCommand(
                command: 153, revision: 2, kind: .resume,
                effectiveAt: resumeAt
            )
        ).outcome else {
            return XCTFail("Expected Resume with protected source intact")
        }
        XCTAssertEqual(summary.sourceRevision, .exact(.init(value: 4)))
        XCTAssertEqual(try fetchList(fixture).revision, 5)
        XCTAssertEqual(try fetchSession(fixture).sourceRevision, 4)
        XCTAssertEqual(try fetchSession(fixture).revision, 3)
        let queries = ProductStateQueryBoundary(repositories: fixture.repositories)
        guard case let .projection(review) = queries.finishReview(.init(
            session: .init(
                sessionID: sessionID,
                expectedRevision: .init(value: 3)
            ),
            proposedOutcomes: [lineID(0): .carriedForward],
            expectedCurrentListRevision: .init(value: 5)
        )) else { return XCTFail("Expected current-revision Finish review") }
        XCTAssertEqual(review.status, .ready)
        XCTAssertEqual(review.metadata.listRevision, .init(value: 5))
    }

    func testLegacyMappedRecoveryPreservesUnknownRevisionWithoutFallback()
        throws {
        let fixture = try makeFixture("legacy-mapped")
        try seed(fixture, lineCount: 1, listRevision: 4)
        try insertLegacyMappedSession(fixture)

        let resumeAt = instant.addingTimeInterval(12 * 60 * 60 + 1)
        guard case let .resumed(resumed) = authority(fixture).resume(
            sessionCommand(
                command: 154, revision: 1, kind: .resume,
                effectiveAt: resumeAt
            )
        ).outcome else { return XCTFail("Expected explicit legacy Resume") }
        XCTAssertEqual(resumed.sourceListID, listID)
        XCTAssertEqual(resumed.sourceRevision, .legacyUnknown)
        XCTAssertNil(resumed.sourcePlanID)
        XCTAssertNil(resumed.sourcePlanFingerprint)

        guard case .lineCollected = authority(fixture).collect(
            sessionLineCommand(
                command: 155, revision: 2, line: lineID(0), collect: true,
                effectiveAt: resumeAt.addingTimeInterval(1)
            )
        ).outcome else { return XCTFail("Expected recovered Collect") }
        let queries = ProductStateQueryBoundary(repositories: fixture.repositories)
        guard case let .projection(review) = queries.finishReview(.init(
            session: .init(
                sessionID: sessionID,
                expectedRevision: .init(value: 3)
            ),
            proposedOutcomes: [lineID(0): .purchased],
            expectedCurrentListRevision: .init(value: 4)
        )) else { return XCTFail("Expected mapped Finish review") }
        XCTAssertEqual(review.status, .ready)
        guard case .completed = authority(fixture).finish(.init(
            command: finishCommand(
                command: 156, sessionRevision: 3, outcomes: [.purchased],
                effectiveAt: resumeAt.addingTimeInterval(2)
            ),
            expectedListRevision: .init(value: 4)
        )).outcome else { return XCTFail("Expected exact mapped Finish") }
        XCTAssertEqual(try fetchSession(fixture).lifecycleRawValue, "finished")
        XCTAssertNil(try fetchSession(fixture).sourceRevision)
        XCTAssertEqual(try fetchList(fixture).revision, 5)
        XCTAssertEqual(try history(fixture).count, 1)
    }

    func testFinishMapsAllOutcomesInOneCommitAndPreservesProductIdentity()
        throws {
        let fixture = try startedFixture("finish-all", lineCount: 6)
        let outcomes = ShoppingSessionFinalOutcome.allCases
        let command = finishCommand(
            command: 160, sessionRevision: 1, outcomes: outcomes
        )

        guard case let .completed(summary) = authority(fixture).finish(
            ProductStateSessionFinishInput(
                command: command,
                expectedListRevision: .init(value: 4)
            )
        ).outcome else { return XCTFail("Expected atomic Finish") }

        XCTAssertEqual(summary.lifecycle, .finished)
        XCTAssertEqual(summary.revisionAfter.value, 2)
        XCTAssertEqual(summary.affectedListRevision, .init(
            listID: listID, before: .init(value: 4), after: .init(value: 5)
        ))
        XCTAssertEqual(summary.historyEventIDs.count, 6)
        XCTAssertEqual(try fetchList(fixture).revision, 5)
        XCTAssertEqual(try lines(fixture).map(\.finalOutcomeRawValue), outcomes.map(\.rawValue))
        XCTAssertTrue(try lines(fixture).allSatisfy {
            $0.finalOutcomeCommandID == commandID(160).rawValue
        })
        let storedEntries = try entries(fixture)
        XCTAssertEqual(storedEntries.prefix(3).map(\.lifecycleRawValue), [
            "resolved", "resolved", "resolved"
        ])
        XCTAssertEqual(storedEntries.suffix(3).map(\.lifecycleRawValue), [
            "needed", "needed", "needed"
        ])
        XCTAssertEqual(storedEntries.prefix(3).map(\.resolutionReasonRawValue), [
            "purchased", "alreadyHave", "noLongerNeeded"
        ])
        let events = try history(fixture)
        XCTAssertEqual(events.count, 6)
        XCTAssertEqual(
            events.map(\.sessionOutcomeRawValue),
            outcomes.map { Optional($0.rawValue) }
        )
        XCTAssertTrue(events.allSatisfy {
            $0.sessionID == sessionID.rawValue
                && $0.commandID == commandID(160).rawValue
                && $0.meaningRawValue == "sessionOutcome"
                && $0.provenanceRawValue == "sessionFinish"
        })
        XCTAssertTrue(try products(fixture).allSatisfy {
            $0.libraryLifecycleRawValue == "active" && $0.revision == 1
        })
        let author = commandID(160).rawValue.uuidString
        XCTAssertEqual(try fixture.context.fetchHistory(
            HistoryDescriptor<DefaultHistoryTransaction>()
        ).filter { $0.author == author }.count, 1)
    }

    func testFinishRejectsMissingOutcomesStaleListAndExpiredSession() throws {
        let missing = try startedFixture("finish-missing", lineCount: 2)
        let oneOutcome = finishCommand(
            command: 170, sessionRevision: 1, outcomes: [.purchased]
        )
        XCTAssertEqual(
            authority(missing).finish(.init(
                command: oneOutcome, expectedListRevision: .init(value: 4)
            )).outcome,
            .invalid(.invalidFinishOutcomes)
        )
        XCTAssertEqual(try fetchList(missing).revision, 4)
        XCTAssertTrue(try history(missing).isEmpty)

        let stale = try startedFixture("finish-stale", lineCount: 1)
        let staleResult = authority(stale).finish(.init(
            command: finishCommand(
                command: 171, sessionRevision: 1, outcomes: [.purchased]
            ),
            expectedListRevision: .init(value: 3)
        ))
        XCTAssertEqual(staleResult.outcome, .conflict(.staleListRevision(
            expected: .init(value: 3), actual: .init(value: 4)
        )))

        let expired = try startedFixture("finish-expired", lineCount: 1)
        let late = finishCommand(
            command: 172,
            sessionRevision: 1,
            outcomes: [.purchased],
            effectiveAt: instant.addingTimeInterval(13 * 60 * 60)
        )
        XCTAssertEqual(
            authority(expired).finish(.init(
                command: late, expectedListRevision: .init(value: 4)
            )).outcome,
            .conflict(.expirationRequired(.init(value: 1)))
        )
    }

    func testFinishSameCommandRetryIsIdempotentAndDifferentCommandIsTerminal()
        throws {
        let fixture = try startedFixture("finish-retry", lineCount: 1)
        let command = finishCommand(
            command: 180, sessionRevision: 1, outcomes: [.purchased]
        )
        let input = ProductStateSessionFinishInput(
            command: command,
            expectedListRevision: .init(value: 4)
        )
        guard case .completed = authority(fixture).finish(input).outcome else {
            return XCTFail("Expected first Finish")
        }
        let firstHistoryIDs = try history(fixture).map(\.id)
        guard case let .completed(retry) = authority(fixture).finish(input).outcome else {
            return XCTFail("Expected reconciled same-command Finish")
        }
        XCTAssertEqual(retry.revisionAfter.value, 2)
        XCTAssertEqual(try fetchList(fixture).revision, 5)
        XCTAssertEqual(try history(fixture).map(\.id), firstHistoryIDs)

        let different = finishCommand(
            command: 181, sessionRevision: 1, outcomes: [.purchased]
        )
        guard case let .terminal(state) = authority(fixture).finish(.init(
            command: different,
            expectedListRevision: .init(value: 4)
        )).outcome else { return XCTFail("Expected terminal rejection") }
        XCTAssertEqual(state.lifecycle, .finished)
        XCTAssertEqual(try history(fixture).count, 1)
    }

    func testInjectedFailureRollsBackEntireFinishWithoutPartialEffects()
        throws {
        let fixture = try startedFixture("finish-rollback", lineCount: 2)
        let command = finishCommand(
            command: 190,
            sessionRevision: 1,
            outcomes: [.purchased, .unavailable]
        )
        let rollback = ProductStateShoppingSessionCommandAuthority(
            repositories: fixture.repositories,
            writeState: .writableTarget,
            commitPrepared: { prepared in
                fixture.context.rollback()
                return ProductStateTransactionResult(
                    commandResult: .unavailable(
                        commandID: prepared.commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    preparedResult: prepared,
                    disposition: .rolledBack(.saveFailed)
                )
            }
        )

        XCTAssertEqual(
            rollback.finish(.init(
                command: command, expectedListRevision: .init(value: 4)
            )).outcome,
            .unavailable(.durableAuthorityUnavailable)
        )
        XCTAssertEqual(try fetchSession(fixture).lifecycleRawValue, "active")
        XCTAssertEqual(try fetchSession(fixture).revision, 1)
        XCTAssertEqual(try fetchList(fixture).revision, 4)
        XCTAssertTrue(try lines(fixture).allSatisfy {
            $0.finalOutcomeRawValue == nil && $0.finalOutcomeCommandID == nil
        })
        XCTAssertTrue(try entries(fixture).allSatisfy {
            $0.lifecycleRawValue == "needed"
        })
        XCTAssertTrue(try history(fixture).isEmpty)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testWriteAndMigrationGatesFailClosedBeforeMutation() throws {
        for (name, writeState, expected) in [
            ("memory", ProductStateSessionCommandWriteState.nonDurable,
             ProductStateSessionCommandOutcome.unavailable(.durableAuthorityUnavailable)),
            ("migration", .migrationIncomplete,
             .unavailable(.migrationIncomplete))
        ] {
            let fixture = try makeFixture(name)
            try seed(fixture, lineCount: 1, listRevision: 1)
            let result = authority(fixture, writeState: writeState).start(
                startInput(command: 200, lineCount: 1, listRevision: 1)
            )
            XCTAssertEqual(result.outcome, expected)
            XCTAssertEqual(try countSessions(fixture), 0)
            XCTAssertFalse(fixture.context.hasChanges)
        }
    }

    func testFileBackedRecoveryAndServiceExposeOnlyImmutableExactSessionValues()
        throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WT033A-T19-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Target.store")
        let first = try makeFixture("file-recovery", url: url)
        try seed(first, lineCount: 2, listRevision: 7)
        guard case .started = authority(first).start(
            startInput(command: 210, lineCount: 2, listRevision: 7)
        ).outcome else { return XCTFail("Expected file-backed Start") }

        let recovered = try makeFixture("file-recovery", url: url)
        let recoveredAuthority = authority(recovered)
        let queries = ProductStateQueryBoundary(repositories: recovered.repositories)
        let service = ProductStateShoppingSessionService(
            queries: queries,
            commands: recoveredAuthority
        )
        guard case let .projection(active) = service.activeSessions() else {
            return XCTFail("Expected durable recovery")
        }
        XCTAssertEqual(active.candidates.count, 1)
        XCTAssertEqual(active.candidates.first?.sessionID, sessionID)
        guard case let .projection(map) = service.shoppingAndMapContext(
            ProductStateSessionSnapshotRequest(
                sessionID: sessionID,
                expectedRevision: .init(value: 1)
            )
        ) else { return XCTFail("Expected immutable Shopping/Map context") }
        XCTAssertEqual(map.owner, .session(sessionID, .init(value: 1), snapshotID))
        XCTAssertEqual(map.items.map(\.sessionLineID), [lineID(0), lineID(1)].map(Optional.some))
        XCTAssertFalse(recovered.context.hasChanges)
    }

    func testT19BoundaryRemainsInactiveAndForbiddenSystemsAreAbsent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let authoritySource = try String(contentsOf:
            root.appendingPathComponent(
                "WayTask/ProductState/Application/ProductStateShoppingSessionAuthority.swift"
            ), encoding: .utf8)
        let serviceSource = try String(contentsOf:
            root.appendingPathComponent("ShoppingSessionService.swift"),
            encoding: .utf8)
        let startup = try String(contentsOf:
            root.appendingPathComponent(
                "WayTask/Persistence/WayTaskStartupPersistence.swift"
            ), encoding: .utf8)
        let app = try String(contentsOf:
            root.appendingPathComponent("WayTask/WayTaskApp.swift"),
            encoding: .utf8)

        XCTAssertTrue(authoritySource.contains(
            "final class ProductStateShoppingSessionCommandAuthority"
        ))
        XCTAssertTrue(serviceSource.contains(
            "struct ProductStateShoppingSessionService"
        ))
        for prohibited in [
            "UNUserNotificationCenter", "CLCircularRegion", "Geofence",
            "Notification", "modelContext.save", "ModelContainer("
        ] {
            XCTAssertFalse(authoritySource.contains(prohibited))
        }
        XCTAssertFalse(startup.contains(
            "ProductStateShoppingSessionCommandAuthority"
        ))
        XCTAssertFalse(app.contains(
            "ProductStateShoppingSessionCommandAuthority"
        ))
    }
}

// MARK: - Fixtures

@MainActor
private extension ProductStateShoppingSessionAuthorityTests {
    struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
    }

    enum SessionCommandKind: Equatable { case resume, abandon }

    var instant: Date { Date(timeIntervalSince1970: 1_780_200_000) }
    var listID: ProductStateListID { .init(rawValue: id(10)) }
    var sessionID: ProductStateSessionID { .init(rawValue: id(20)) }
    var snapshotID: ProductStateSessionSnapshotID { .init(rawValue: id(21)) }
    var planID: ProductStatePlanID { .init(rawValue: id(22)) }

    func makeFixture(_ name: String, url: URL? = nil) throws -> Fixture {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                "WT033A-T19-\(name)",
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "WT033A-T19-\(name)-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        let container = try ModelContainer(
            for: schema, configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return Fixture(
            container: container,
            context: context,
            repositories: ProductStateRepositories(modelContext: context)
        )
    }

    func startedFixture(_ name: String, lineCount: Int) throws -> Fixture {
        let fixture = try makeFixture(name)
        try seed(fixture, lineCount: lineCount, listRevision: 4)
        guard case .started = authority(fixture).start(
            startInput(command: 1, lineCount: lineCount, listRevision: 4)
        ).outcome else { throw FixtureError.startFailed }
        return fixture
    }

    func authority(
        _ fixture: Fixture,
        writeState: ProductStateSessionCommandWriteState = .writableTarget
    ) -> ProductStateShoppingSessionCommandAuthority {
        ProductStateShoppingSessionCommandAuthority(
            repositories: fixture.repositories,
            transactionCoordinator: ProductStateTransactionCoordinator(
                modelContext: fixture.context
            ),
            writeState: writeState
        )
    }

    func seed(
        _ fixture: Fixture,
        lineCount: Int,
        listRevision: UInt64
    ) throws {
        var listEntries: [WayTaskSchemaV4.ShoppingListEntry] = []
        for index in 0..<lineCount {
            let product = WayTaskSchemaV4.Product(
                id: productID(index).rawValue,
                revision: 1,
                libraryLifecycleRawValue: "active",
                name: "Product \(index)",
                brand: "Brand \(index)",
                category: "Category",
                sourceRawValue: "manual",
                createdAt: instant.addingTimeInterval(Double(index)),
                updatedAt: instant.addingTimeInterval(Double(index))
            )
            let entry = WayTaskSchemaV4.ShoppingListEntry(
                id: entryID(index).rawValue,
                shoppingListID: listID.rawValue,
                productID: product.id,
                lifecycleRawValue: "needed",
                quantity: Double(index + 1),
                unitRawValue: "unit",
                note: "Note \(index)",
                sortOrder: Double(index),
                createdAt: instant,
                updatedAt: instant,
                product: product
            )
            fixture.repositories.products.stageInsertion(of: product)
            listEntries.append(entry)
        }
        fixture.repositories.shopping.stageInsertion(of:
            WayTaskSchemaV4.ShoppingList(
                id: listID.rawValue,
                revision: listRevision,
                title: "Exact List",
                purposeRawValue: "shopping",
                createdAt: instant,
                updatedAt: instant,
                entries: listEntries
            )
        )
        try fixture.context.save()
    }

    func startInput(
        command: Int,
        session: UUID? = nil,
        snapshot: UUID? = nil,
        lineCount: Int,
        listRevision: UInt64
    ) -> ProductStateSessionStartInput {
        let exactSessionID = ProductStateSessionID(
            rawValue: session ?? sessionID.rawValue
        )
        let exactSnapshotID = ProductStateSessionSnapshotID(
            rawValue: snapshot ?? snapshotID.rawValue
        )
        let identities = (0..<lineCount).map { identity($0) }
        let plan = ProductStateShoppingPlan(
            id: planID,
            sourceListID: listID,
            sourceRevision: .init(value: listRevision),
            includedEntries: identities,
            exclusions: [],
            status: .ready
        )
        return ProductStateSessionStartInput(
            command: ProductStateCommand(
                id: commandID(command),
                expectedRevision: .init(revision: .init(
                    scope: .list(listID), value: listRevision
                )),
                effectiveAt: instant,
                intent: .startSession(StartSessionCommand(
                    sessionID: exactSessionID,
                    listID: listID,
                    sourceRevision: .init(value: listRevision),
                    entries: identities
                ))
            ),
            plan: plan,
            planFingerprint: "plan-fingerprint-v1",
            planEvidenceAt: instant.addingTimeInterval(-60 * 60),
            confirmedStaleEvidenceAt: nil,
            snapshotID: exactSnapshotID,
            stops: (0..<lineCount).map { index in
                ProductStateSessionStopInput(
                    id: stopID(index),
                    sortOrder: index,
                    storeReferenceIDRawValue: "store-\(index)",
                    storeReferenceProvenanceRawValue: "publishedStore",
                    displayNameSnapshot: "Store \(index)",
                    latitude: 31.7 + Double(index) / 100,
                    longitude: 35.2 + Double(index) / 100,
                    evidenceAt: instant.addingTimeInterval(-60 * 60),
                    isSessionScopedTransient: false
                )
            },
            lines: (0..<lineCount).map { index in
                ProductStateSessionLineInput(
                    id: lineID(index),
                    sourceEntry: identity(index),
                    stopID: stopID(index),
                    sortOrder: index,
                    globalProductConceptIDRawValue: "concept-\(index)"
                )
            }
        )
    }

    func replacingEvidence(
        _ input: ProductStateSessionStartInput,
        evidenceAt: Date,
        confirmed: Date?
    ) -> ProductStateSessionStartInput {
        ProductStateSessionStartInput(
            command: input.command,
            plan: input.plan,
            planFingerprint: input.planFingerprint,
            planEvidenceAt: evidenceAt,
            confirmedStaleEvidenceAt: confirmed,
            snapshotID: input.snapshotID,
            stops: input.stops,
            lines: input.lines
        )
    }

    func sessionLineCommand(
        command: Int,
        revision: UInt64,
        line: ProductStateSessionLineID,
        collect: Bool,
        effectiveAt: Date? = nil
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedSessionRevision(revision),
            effectiveAt: effectiveAt
                ?? instant.addingTimeInterval(Double(command)),
            intent: collect
                ? .markLineCollected(.init(sessionID: sessionID, lineID: line))
                : .undoLineCollection(.init(sessionID: sessionID, lineID: line))
        )
    }

    func finishDraftCommand(
        command: Int,
        revision: UInt64,
        line: ProductStateSessionLineID
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedSessionRevision(revision),
            effectiveAt: instant.addingTimeInterval(Double(command)),
            intent: .prepareFinishOutcome(.init(
                sessionID: sessionID, lineID: line, outcome: .purchased
            ))
        )
    }

    func sessionCommand(
        command: Int,
        revision: UInt64,
        kind: SessionCommandKind,
        effectiveAt: Date? = nil
    ) -> ProductStateCommand {
        let intent: ProductStateCommandIntent = kind == .resume
            ? .resumeSession(.init(sessionID: sessionID))
            : .abandonSession(.init(sessionID: sessionID, confirmed: true))
        return ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedSessionRevision(revision),
            effectiveAt: effectiveAt ?? instant.addingTimeInterval(Double(command)),
            intent: intent
        )
    }

    func finishCommand(
        command: Int,
        sessionRevision: UInt64,
        outcomes: [ShoppingSessionFinalOutcome],
        effectiveAt: Date? = nil
    ) -> ProductStateCommand {
        ProductStateCommand(
            id: commandID(command),
            expectedRevision: expectedSessionRevision(sessionRevision),
            effectiveAt: effectiveAt ?? instant.addingTimeInterval(Double(command)),
            intent: .finishSession(.init(
                sessionID: sessionID,
                outcomes: outcomes.enumerated().map {
                    FinishSessionLineOutcome(
                        lineID: lineID($0.offset), outcome: $0.element
                    )
                },
                confirmed: true
            ))
        )
    }

    func expectedSessionRevision(
        _ value: UInt64
    ) -> ProductStateExpectedRevision {
        .init(revision: .init(scope: .session(sessionID), value: value))
    }

    func makeNativeSession(
        session: UUID,
        snapshot: UUID,
        lifecycle: ShoppingSessionLifecycle,
        revision: UInt64,
        listRevision: UInt64
    ) -> WayTaskSchemaV4.ShoppingSession {
        let stop = WayTaskSchemaV4.ShoppingSessionStop(
            id: id(910), sessionID: session, snapshotID: snapshot,
            sortOrder: 0, storeReferenceIDRawValue: "other-store",
            storeReferenceProvenanceRawValue: "publishedStore",
            displayNameSnapshot: "Other Store", latitudeSnapshot: 31.7,
            longitudeSnapshot: 35.2, evidenceAt: instant,
            isSessionScopedTransient: false
        )
        let line = WayTaskSchemaV4.ShoppingSessionLine(
            id: id(911), sessionID: session, snapshotID: snapshot,
            snapshotVersion: 1, snapshotProvenanceRawValue: "nativeStart",
            sourceListID: listID.rawValue, sourceEntryID: entryID(0).rawValue,
            productID: productID(0).rawValue, stopID: stop.id, sortOrder: 0,
            productNameSnapshot: "Product 0", quantitySnapshot: 1,
            executionStateRawValue: "remaining", stop: stop
        )
        return WayTaskSchemaV4.ShoppingSession(
            id: session, sourceListID: listID.rawValue,
            sourceRevision: listRevision,
            sourceRevisionProvenanceRawValue: "exact",
            revision: revision, lifecycleRawValue: lifecycle.rawValue,
            migrationConditionRawValue: "native", snapshotID: snapshot,
            snapshotVersion: 1, snapshotGeneration: 1,
            snapshotContentSignature: "other-signature",
            sourcePlanID: id(912), sourcePlanSignature: "other-plan",
            sourcePlanEvidenceAt: instant, startedAt: instant,
            activationStartedAt: instant, lastActivityAt: instant,
            expirationPolicyVersion: 1, lines: [line], stops: [stop]
        )
    }

    func insertLegacyMappedSession(_ fixture: Fixture) throws {
        let entry = try XCTUnwrap(entries(fixture).first)
        let product = try XCTUnwrap(products(fixture).first)
        let stop = WayTaskSchemaV4.ShoppingSessionStop(
            id: stopID(0).rawValue,
            sessionID: sessionID.rawValue,
            snapshotID: snapshotID.rawValue,
            sortOrder: 0,
            storeReferenceIDRawValue: "legacy-store",
            storeReferenceProvenanceRawValue: "legacySnapshot",
            displayNameSnapshot: "Saved Store",
            latitudeSnapshot: 31.7,
            longitudeSnapshot: 35.2,
            evidenceAt: instant,
            isSessionScopedTransient: true
        )
        let line = WayTaskSchemaV4.ShoppingSessionLine(
            id: lineID(0).rawValue,
            sessionID: sessionID.rawValue,
            snapshotID: snapshotID.rawValue,
            snapshotVersion: 1,
            snapshotProvenanceRawValue: "legacyExact",
            sourceListID: listID.rawValue,
            sourceEntryID: entry.id,
            productID: product.id,
            stopID: stop.id,
            sortOrder: 0,
            productNameSnapshot: product.name,
            productBrandSnapshot: product.brand,
            productCategorySnapshot: product.category,
            quantitySnapshot: entry.quantity,
            unitSnapshotRawValue: entry.unitRawValue,
            noteSnapshot: entry.note,
            executionStateRawValue: "remaining",
            sourceEntry: entry,
            product: product,
            stop: stop
        )
        fixture.repositories.sessions.stageInsertion(of:
            WayTaskSchemaV4.ShoppingSession(
                id: sessionID.rawValue,
                sourceListID: listID.rawValue,
                sourceRevision: nil,
                sourceRevisionProvenanceRawValue: "legacyUnknown",
                revision: 1,
                lifecycleRawValue: "expired",
                migrationConditionRawValue: "legacyMapped",
                snapshotID: snapshotID.rawValue,
                snapshotVersion: 1,
                snapshotGeneration: 1,
                snapshotContentSignature: "legacy-snapshot-signature",
                startedAt: instant,
                activationStartedAt: instant,
                lastActivityAt: instant,
                expiredAt: instant.addingTimeInterval(12 * 60 * 60),
                expirationReasonRawValue: "legacyInactivity",
                expirationPolicyVersion: 1,
                sourceList: try fetchList(fixture),
                lines: [line],
                stops: [stop]
            )
        )
        try fixture.context.save()
    }

    func fetchSession(_ fixture: Fixture) throws -> WayTaskSchemaV4.ShoppingSession {
        try XCTUnwrap(fixture.repositories.sessions.shoppingSessions(
            id: sessionID.rawValue
        ).first)
    }

    func fetchList(_ fixture: Fixture) throws -> WayTaskSchemaV4.ShoppingList {
        try XCTUnwrap(fixture.repositories.shopping.shoppingLists(
            id: listID.rawValue
        ).first)
    }

    func lines(_ fixture: Fixture) throws -> [WayTaskSchemaV4.ShoppingSessionLine] {
        try fixture.repositories.sessions.sessionLines(sessionID: sessionID.rawValue)
    }

    func stops(_ fixture: Fixture) throws -> [WayTaskSchemaV4.ShoppingSessionStop] {
        try fixture.repositories.sessions.sessionStops(sessionID: sessionID.rawValue)
    }

    func entries(_ fixture: Fixture) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        try fixture.repositories.shopping.shoppingEntries(listID: listID.rawValue)
    }

    func products(_ fixture: Fixture) throws -> [WayTaskSchemaV4.Product] {
        try fixture.repositories.products.products(libraryLifecycle: .active)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func history(_ fixture: Fixture) throws -> [WayTaskSchemaV4.ProductHistoryEvent] {
        try (0..<12).flatMap { index in
            try fixture.repositories.history.historyEvents(
                productID: productID(index).rawValue
            )
        }.sorted { $0.sessionLineID!.uuidString < $1.sessionLineID!.uuidString }
    }

    func countSessions(_ fixture: Fixture) throws -> Int {
        try fixture.context.fetchCount(
            FetchDescriptor<WayTaskSchemaV4.ShoppingSession>()
        )
    }

    func identity(_ index: Int) -> ProductStateListEntryIdentity {
        .init(id: entryID(index), listID: listID, productID: productID(index))
    }

    func productID(_ index: Int) -> ProductStateProductID {
        .init(rawValue: id(1000 + index))
    }

    func entryID(_ index: Int) -> ProductStateListEntryID {
        .init(rawValue: id(2000 + index))
    }

    func lineID(_ index: Int) -> ProductStateSessionLineID {
        .init(rawValue: id(3000 + index))
    }

    func stopID(_ index: Int) -> ProductStateSessionStopID {
        .init(rawValue: id(4000 + index))
    }

    func commandID(_ value: Int) -> ProductStateCommandID {
        .init(rawValue: id(5000 + value))
    }

    func id(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d", value
        ))!
    }

    enum FixtureError: Error { case startFailed }
}
