// This file intentionally imports no framework. It validates value-only
// domain snapshots declared in ProductStateDomain.swift.

enum ProductStateLifecycleAuthority: String, CaseIterable, Hashable, Sendable {
    case productLibrary
    case listMembership
    case entryResolution
    case plan
    case sessionExecution
    case history
}

struct ProductStateAuthorityAudit: Equatable, Sendable {
    let authorityCounts: [ProductStateLifecycleAuthority: Int]
    let hasGlobalProductShoppingState: Bool
    let usesCatalogIdentityAsProductIdentity: Bool
    let hasExternalAuthorityClaim: Bool
    let compatibilityValueIsAuthoritative: Bool

    init(
        authorityCounts: [ProductStateLifecycleAuthority: Int]? = nil,
        hasGlobalProductShoppingState: Bool = false,
        usesCatalogIdentityAsProductIdentity: Bool = false,
        hasExternalAuthorityClaim: Bool = false,
        compatibilityValueIsAuthoritative: Bool = false
    ) {
        self.authorityCounts = authorityCounts ?? Dictionary(
            uniqueKeysWithValues: ProductStateLifecycleAuthority.allCases.map {
                ($0, 1)
            }
        )
        self.hasGlobalProductShoppingState = hasGlobalProductShoppingState
        self.usesCatalogIdentityAsProductIdentity =
            usesCatalogIdentityAsProductIdentity
        self.hasExternalAuthorityClaim = hasExternalAuthorityClaim
        self.compatibilityValueIsAuthoritative =
            compatibilityValueIsAuthoritative
    }
}

struct ProductLibraryTransition: Equatable, Sendable {
    let before: ProductStateProductSnapshot
    let after: ProductStateProductSnapshot
    let action: ProductLibraryAction
    let hasExplicitUserIntent: Bool
}

struct ShoppingListEntryTransition: Equatable, Sendable {
    let before: ProductStateListEntrySnapshot
    let after: ProductStateListEntrySnapshot
    let action: ShoppingListEntryAction
    let commandListID: ProductStateListID
}

struct ShoppingSessionTransition: Equatable, Sendable {
    let before: ProductStateShoppingSession
    let after: ProductStateShoppingSession
    let action: ShoppingSessionAction
    let effects: ShoppingSessionSemanticEffects
}

struct ProductHistoryEventMutation: Equatable, Sendable {
    let before: ProductStateHistoryEvent
    let after: ProductStateHistoryEvent
}

struct ProductStateInvariantInput: Equatable, Sendable {
    let authorityAudit: ProductStateAuthorityAudit
    let productTransitions: [ProductLibraryTransition]
    let lists: [ProductStateShoppingListSnapshot]
    let membershipClaims: [ProductStateListMembershipKey]
    let entryTransitions: [ShoppingListEntryTransition]
    let sessions: [ProductStateShoppingSession]
    let sessionTransitions: [ShoppingSessionTransition]
    let historyEvents: [ProductStateHistoryEvent]
    let historyMutations: [ProductHistoryEventMutation]
    let commandResults: [ProductStateCommandResult]

    init(
        authorityAudit: ProductStateAuthorityAudit = .init(),
        productTransitions: [ProductLibraryTransition] = [],
        lists: [ProductStateShoppingListSnapshot] = [],
        membershipClaims: [ProductStateListMembershipKey] = [],
        entryTransitions: [ShoppingListEntryTransition] = [],
        sessions: [ProductStateShoppingSession] = [],
        sessionTransitions: [ShoppingSessionTransition] = [],
        historyEvents: [ProductStateHistoryEvent] = [],
        historyMutations: [ProductHistoryEventMutation] = [],
        commandResults: [ProductStateCommandResult] = []
    ) {
        self.authorityAudit = authorityAudit
        self.productTransitions = productTransitions
        self.lists = lists
        self.membershipClaims = membershipClaims
        self.entryTransitions = entryTransitions
        self.sessions = sessions
        self.sessionTransitions = sessionTransitions
        self.historyEvents = historyEvents
        self.historyMutations = historyMutations
        self.commandResults = commandResults
    }
}

enum ProductStateInvariantCode: String, CaseIterable, Hashable, Sendable {
    case missingAuthorityForLifecycle
    case multipleAuthoritiesForLifecycle
    case productIdentityChanged
    case catalogIdentitySubstitutedForProduct
    case globalProductShoppingState
    case implicitProductRestore
    case invalidProductLibraryTransition
    case duplicateCurrentListEntry
    case entryMembershipWithoutEntry
    case entryListScopeMismatch
    case crossListMutation
    case reopenChangedEntryIdentity
    case invalidEntryTransition
    case legacyUnknownOutsideMigration
    case purchasedResolutionWithoutFinish
    case multipleNativeNonTerminalSessions
    case nativeSessionMissingStop
    case duplicateSessionLineIdentity
    case invalidSessionLineSnapshot
    case invalidSessionTransition
    case invalidSessionRevision
    case immutableSessionSnapshotChanged
    case collectedTreatedAsPurchased
    case provisionalExecutionHasFinalEffects
    case finishedSessionMissingFinalOutcome
    case nonFinishedSessionHasFinalOutcome
    case nativeSessionHasLegacyDisposition
    case abandonedSessionHasListResolutionMeaning
    case abandonedSessionHasPurchaseHistoryMeaning
    case duplicateHistoryEventIdentity
    case historyEventMutated
    case purchaseHistoryWithoutFinish
    case sessionOutcomeHistoryWithoutFinish
    case noOpCommandHasEffects
    case invalidCommittedRevisionChange
    case duplicateRevisionEffect
    case commandRetryChangedResult
    case duplicateHistoryEffect
    case externalAuthorityClaim
    case compatibilityAuthorityClaim
}

struct ProductStateInvariantViolation: Error, Hashable, Sendable {
    let code: ProductStateInvariantCode
}

struct ProductStateInvariantValidator: Sendable {
    func validate(_ input: ProductStateInvariantInput)
        -> [ProductStateInvariantViolation]
    {
        var codes = Set<ProductStateInvariantCode>()

        validateAuthority(input.authorityAudit, into: &codes)
        validateProducts(input.productTransitions, into: &codes)
        validateLists(
            input.lists,
            membershipClaims: input.membershipClaims,
            transitions: input.entryTransitions,
            into: &codes
        )
        validateSessions(
            input.sessions,
            transitions: input.sessionTransitions,
            into: &codes
        )
        validateHistory(
            input.historyEvents,
            mutations: input.historyMutations,
            into: &codes
        )
        validateCommands(input.commandResults, into: &codes)

        return codes
            .sorted { $0.rawValue < $1.rawValue }
            .map(ProductStateInvariantViolation.init(code:))
    }

    private func validateAuthority(
        _ audit: ProductStateAuthorityAudit,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        if ProductStateLifecycleAuthority.allCases.contains(where: {
            (audit.authorityCounts[$0] ?? 0) < 1
        }) {
            codes.insert(.missingAuthorityForLifecycle)
        }
        if ProductStateLifecycleAuthority.allCases.contains(where: {
            (audit.authorityCounts[$0] ?? 0) > 1
        }) {
            codes.insert(.multipleAuthoritiesForLifecycle)
        }
        if audit.hasGlobalProductShoppingState {
            codes.insert(.globalProductShoppingState)
        }
        if audit.usesCatalogIdentityAsProductIdentity {
            codes.insert(.catalogIdentitySubstitutedForProduct)
        }
        if audit.hasExternalAuthorityClaim {
            codes.insert(.externalAuthorityClaim)
        }
        if audit.compatibilityValueIsAuthoritative {
            codes.insert(.compatibilityAuthorityClaim)
        }
    }

    private func validateProducts(
        _ transitions: [ProductLibraryTransition],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        for transition in transitions {
            if transition.before.id != transition.after.id {
                codes.insert(.productIdentityChanged)
            }

            let stateChange = (
                transition.before.libraryLifecycle,
                transition.after.libraryLifecycle
            )
            switch (stateChange, transition.action) {
            case ((.active, .removed), .removeFromLibrary):
                if !transition.hasExplicitUserIntent {
                    codes.insert(.invalidProductLibraryTransition)
                }
            case ((.removed, .active), .restoreToLibrary):
                if !transition.hasExplicitUserIntent {
                    codes.insert(.implicitProductRestore)
                }
            case ((.removed, .active), _):
                codes.insert(.implicitProductRestore)
            default:
                codes.insert(.invalidProductLibraryTransition)
            }
        }
    }

    private func validateLists(
        _ lists: [ProductStateShoppingListSnapshot],
        membershipClaims: [ProductStateListMembershipKey],
        transitions: [ShoppingListEntryTransition],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        var entriesByMembership: [
            ProductStateListMembershipKey: [ProductStateListEntrySnapshot]
        ] = [:]

        for list in lists {
            for entry in list.entries {
                if entry.identity.listID != list.id {
                    codes.insert(.entryListScopeMismatch)
                }
                let key = ProductStateListMembershipKey(
                    listID: entry.identity.listID,
                    productID: entry.identity.productID
                )
                entriesByMembership[key, default: []].append(entry)
                validateResolution(entry.lifecycle, into: &codes)
            }
        }

        if entriesByMembership.values.contains(where: { $0.count > 1 }) {
            codes.insert(.duplicateCurrentListEntry)
        }

        for claim in membershipClaims
        where entriesByMembership[claim]?.count != 1 {
            codes.insert(.entryMembershipWithoutEntry)
        }

        for transition in transitions {
            validateResolution(transition.before.lifecycle, into: &codes)
            validateResolution(transition.after.lifecycle, into: &codes)

            let beforeIdentity = transition.before.identity
            let afterIdentity = transition.after.identity
            if beforeIdentity.listID != transition.commandListID
                || afterIdentity.listID != transition.commandListID
            {
                codes.insert(.crossListMutation)
            }

            switch transition.action {
            case .resolve:
                guard case .needed = transition.before.lifecycle,
                      case .resolved = transition.after.lifecycle,
                      beforeIdentity == afterIdentity
                else {
                    codes.insert(.invalidEntryTransition)
                    continue
                }
                validateResolution(transition.after.lifecycle, into: &codes)

            case .reopen:
                if beforeIdentity != afterIdentity {
                    codes.insert(.reopenChangedEntryIdentity)
                }
                guard case .resolved = transition.before.lifecycle,
                      case .needed = transition.after.lifecycle,
                      beforeIdentity == afterIdentity
                else {
                    codes.insert(.invalidEntryTransition)
                    continue
                }
            }
        }
    }

    private func validateResolution(
        _ lifecycle: ShoppingListEntryLifecycle,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        guard case let .resolved(resolution) = lifecycle else { return }

        if resolution.reason == .legacyUnknown,
           resolution.provenance != .legacyMigration
        {
            codes.insert(.legacyUnknownOutsideMigration)
        }

        if resolution.reason == .purchased {
            guard case .sessionFinish = resolution.provenance else {
                codes.insert(.purchasedResolutionWithoutFinish)
                return
            }
        }
    }

    private func validateSessions(
        _ sessions: [ProductStateShoppingSession],
        transitions: [ShoppingSessionTransition],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        let nativeNonTerminalCount = sessions.filter {
            $0.migrationCondition == .native && !$0.lifecycle.isTerminal
        }.count
        if nativeNonTerminalCount > 1 {
            codes.insert(.multipleNativeNonTerminalSessions)
        }

        for session in sessions {
            validateSession(session, into: &codes)
        }
        for transition in transitions {
            validateSessionTransition(transition, into: &codes)
        }
    }

    private func validateSession(
        _ session: ProductStateShoppingSession,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        if session.migrationCondition == .native {
            if session.stopIDs.isEmpty {
                codes.insert(.nativeSessionMissingStop)
            }
            if case .legacyUnknown = session.sourceRevision {
                codes.insert(.legacyUnknownOutsideMigration)
            }
        }

        if Set(session.stopIDs).count != session.stopIDs.count {
            codes.insert(.invalidSessionLineSnapshot)
        }

        let lineIDs = session.lines.map(\.snapshot.id)
        if Set(lineIDs).count != lineIDs.count {
            codes.insert(.duplicateSessionLineIdentity)
        }

        for line in session.lines {
            if line.snapshot.snapshotID != session.snapshotID
                || line.snapshot.sourceEntry.listID != session.sourceListID
                || line.snapshot.productID != line.snapshot.sourceEntry.productID
                || !session.stopIDs.contains(line.snapshot.stopID)
            {
                codes.insert(.invalidSessionLineSnapshot)
            }

            if session.migrationCondition == .native,
               line.legacyDisposition != nil
            {
                codes.insert(.nativeSessionHasLegacyDisposition)
            }
        }

        if session.migrationCondition == .native {
            if session.lifecycle == .finished {
                if session.lines.contains(where: { $0.finalOutcome == nil }) {
                    codes.insert(.finishedSessionMissingFinalOutcome)
                }
            } else if session.lines.contains(where: {
                $0.finalOutcome != nil
            }) {
                codes.insert(.nonFinishedSessionHasFinalOutcome)
            }
        }
    }

    private func validateSessionTransition(
        _ transition: ShoppingSessionTransition,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        let before = transition.before
        let after = transition.after

        if before.id != after.id {
            codes.insert(.invalidSessionTransition)
        }

        if before.snapshotID != after.snapshotID
            || before.sourceListID != after.sourceListID
            || before.sourceRevision != after.sourceRevision
            || before.stopIDs != after.stopIDs
            || before.migrationCondition != after.migrationCondition
            || before.lines.map(\.snapshot) != after.lines.map(\.snapshot)
        {
            codes.insert(.immutableSessionSnapshotChanged)
        }

        let shouldAdvanceRevision = transition.action != .recover
        if shouldAdvanceRevision {
            if before.revision.value == UInt64.max
                || after.revision.value != before.revision.value + 1
            {
                codes.insert(.invalidSessionRevision)
            }
        } else if after.revision != before.revision {
            codes.insert(.invalidSessionRevision)
        }

        switch transition.action {
        case let .collect(lineID):
            validateCollectionChange(
                from: .remaining,
                to: .collected,
                lineID: lineID,
                transition: transition,
                into: &codes
            )
            if transition.effects.historyMeanings.contains(where: {
                $0 == .sessionOutcome(.purchased)
            }) || transition.effects.resolvedEntries.isEmpty == false {
                codes.insert(.collectedTreatedAsPurchased)
            }
            if transition.effects != .none {
                codes.insert(.provisionalExecutionHasFinalEffects)
            }

        case let .undo(lineID):
            validateCollectionChange(
                from: .collected,
                to: .remaining,
                lineID: lineID,
                transition: transition,
                into: &codes
            )
            if transition.effects != .none {
                codes.insert(.provisionalExecutionHasFinalEffects)
                codes.insert(.invalidSessionTransition)
            }

        case .expire:
            if before.lifecycle != .active
                || after.lifecycle != .expired
                || before.lines != after.lines
                || transition.effects != .none
            {
                codes.insert(.invalidSessionTransition)
            }

        case .resume:
            if before.lifecycle != .expired
                || after.lifecycle != .active
                || before.lines != after.lines
                || transition.effects != .none
            {
                codes.insert(.invalidSessionTransition)
            }

        case .finish:
            if before.lifecycle != .active || after.lifecycle != .finished {
                codes.insert(.invalidSessionTransition)
            }
            validateSession(after, into: &codes)

        case .abandon:
            if !(before.lifecycle == .active || before.lifecycle == .expired)
                || after.lifecycle != .abandoned
                || before.lines != after.lines
            {
                codes.insert(.invalidSessionTransition)
            }
            if !transition.effects.resolvedEntries.isEmpty {
                codes.insert(.abandonedSessionHasListResolutionMeaning)
            }
            if !transition.effects.historyMeanings.isEmpty {
                codes.insert(.abandonedSessionHasPurchaseHistoryMeaning)
            }

        case .recover:
            if before != after || transition.effects != .none {
                codes.insert(.invalidSessionTransition)
            }
        }
    }

    private func validateCollectionChange(
        from expectedBefore: ShoppingSessionExecutionState,
        to expectedAfter: ShoppingSessionExecutionState,
        lineID: ProductStateSessionLineID,
        transition: ShoppingSessionTransition,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        guard transition.before.lifecycle == .active,
              transition.after.lifecycle == .active,
              transition.before.lines.count == transition.after.lines.count
        else {
            codes.insert(.invalidSessionTransition)
            return
        }

        var changedLineCount = 0
        for beforeLine in transition.before.lines {
            guard let afterLine = transition.after.lines.first(where: {
                $0.snapshot.id == beforeLine.snapshot.id
            }) else {
                codes.insert(.invalidSessionTransition)
                return
            }

            if beforeLine.snapshot.id == lineID {
                changedLineCount += 1
                if beforeLine.executionState != expectedBefore
                    || afterLine.executionState != expectedAfter
                    || beforeLine.finalOutcome != nil
                    || afterLine.finalOutcome != nil
                    || beforeLine.legacyDisposition
                        != afterLine.legacyDisposition
                {
                    codes.insert(.invalidSessionTransition)
                }
            } else if beforeLine != afterLine {
                codes.insert(.invalidSessionTransition)
            }
        }

        if changedLineCount != 1 {
            codes.insert(.invalidSessionTransition)
        }
    }

    private func validateHistory(
        _ events: [ProductStateHistoryEvent],
        mutations: [ProductHistoryEventMutation],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        let eventIDs = events.map(\.id)
        if Set(eventIDs).count != eventIDs.count {
            codes.insert(.duplicateHistoryEventIdentity)
        }

        for event in events {
            switch event.meaning {
            case .needResolved(.purchased):
                guard case .sessionFinish = event.provenance else {
                    codes.insert(.purchaseHistoryWithoutFinish)
                    continue
                }
            case .needResolved(.legacyUnknown):
                if event.provenance != .legacyMigration {
                    codes.insert(.legacyUnknownOutsideMigration)
                }
            case .sessionOutcome:
                guard case .sessionFinish = event.provenance else {
                    codes.insert(.sessionOutcomeHistoryWithoutFinish)
                    continue
                }
            default:
                break
            }
        }

        for mutation in mutations
        where mutation.before.id == mutation.after.id
            && mutation.before != mutation.after
        {
            codes.insert(.historyEventMutated)
        }
    }

    private func validateCommands(
        _ results: [ProductStateCommandResult],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        var resultsByCommand: [
            ProductStateCommandID: [ProductStateCommandResult]
        ] = [:]
        var historyOwners: [
            ProductStateHistoryEventID: ProductStateCommandID
        ] = [:]

        for result in results {
            resultsByCommand[result.commandID, default: []].append(result)

            switch result {
            case let .committed(receipt):
                validateCommittedEffects(receipt.effects, into: &codes)
                validateHistoryEffects(
                    receipt.effects.historyEventIDs,
                    commandID: receipt.commandID,
                    owners: &historyOwners,
                    into: &codes
                )

            case let .noOp(receipt):
                if receipt.effects != .none {
                    codes.insert(.noOpCommandHasEffects)
                }

            case .conflict, .validationFailure, .unavailable:
                break
            }
        }

        for commandResults in resultsByCommand.values {
            guard let first = commandResults.first else { continue }
            if commandResults.dropFirst().contains(where: { $0 != first }) {
                codes.insert(.commandRetryChangedResult)
            }
        }
    }

    private func validateCommittedEffects(
        _ effects: ProductStateCommandEffects,
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        let revisionScopes = effects.revisionChanges.map(\.before.scope)
        if Set(revisionScopes).count != revisionScopes.count {
            codes.insert(.duplicateRevisionEffect)
        }

        for change in effects.revisionChanges {
            if change.before.scope != change.after.scope
                || change.before.value == UInt64.max
                || change.after.value != change.before.value + 1
            {
                codes.insert(.invalidCommittedRevisionChange)
            }
        }

        if Set(effects.historyEventIDs).count != effects.historyEventIDs.count {
            codes.insert(.duplicateHistoryEffect)
        }
    }

    private func validateHistoryEffects(
        _ eventIDs: [ProductStateHistoryEventID],
        commandID: ProductStateCommandID,
        owners: inout [ProductStateHistoryEventID: ProductStateCommandID],
        into codes: inout Set<ProductStateInvariantCode>
    ) {
        for eventID in eventIDs {
            if let owner = owners[eventID], owner != commandID {
                codes.insert(.duplicateHistoryEffect)
            } else {
                owners[eventID] = commandID
            }
        }
    }
}
