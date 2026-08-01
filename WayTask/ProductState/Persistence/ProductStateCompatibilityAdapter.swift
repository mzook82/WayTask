import Foundation

enum ProductStateLegacyEntryMembership: String, Codable, Sendable {
    case presentNeeded
    case presentResolved
    case absent
}

/// Exact-list compatibility output only. A global legacy completion value is
/// deliberately unavailable because one Product can have independent state in
/// multiple named lists and no list may be selected implicitly.
struct ProductStateLegacyEntryCompatibilityOutput:
    Equatable, Codable, Sendable {
    let listID: UUID
    let listRevision: UInt64
    let entryID: UUID
    let productID: UUID
    let membership: ProductStateLegacyEntryMembership
    let legacyEntryIsChecked: Bool?
    let legacyShoppingItemIsCompleted: Bool?
}

struct ProductStateCompatibilityAccessCounters:
    Equatable, Codable, Sendable {
    let targetReadCount: UInt64
    let outputEmissionCount: UInt64
    let legacyReadCount: UInt64
    let legacyWriteCount: UInt64
    let reverseSynchronizationCount: UInt64
}

/// TC-08 is a bounded, target-to-legacy derivation boundary. It performs no
/// persistence writes and exposes no reverse-synchronization operation.
@MainActor
final class ProductStateCompatibilityAdapter {
    private let shopping: any ShoppingRepository
    private var targetReadCount: UInt64 = 0
    private var outputEmissionCount: UInt64 = 0

    init(shopping: any ShoppingRepository) {
        self.shopping = shopping
    }

    func deriveEntryOutput(
        from execution: ProductStateNamedListCommandExecution
    ) -> ProductStateLegacyEntryCompatibilityOutput? {
        guard let identity = authoritativeIdentity(from: execution),
              isPermittedOutcome(execution.outcome)
        else { return nil }

        targetReadCount &+= 1
        do {
            let lists = try shopping.shoppingLists(
                id: identity.listID.rawValue
            )
            guard lists.count == 1 else { return nil }
            let entries = try shopping.shoppingEntries(
                id: identity.id.rawValue,
                listID: identity.listID.rawValue
            ).filter { $0.productID == identity.productID.rawValue }

            let output: ProductStateLegacyEntryCompatibilityOutput
            if entries.count == 1 {
                let entry = entries[0]
                switch entry.lifecycleRawValue {
                case "needed":
                    output = makeOutput(
                        identity: identity,
                        listRevision: lists[0].revision,
                        membership: .presentNeeded,
                        legacyEntryIsChecked: false
                    )
                case "resolved":
                    output = makeOutput(
                        identity: identity,
                        listRevision: lists[0].revision,
                        membership: .presentResolved,
                        legacyEntryIsChecked: true
                    )
                default:
                    return nil
                }
            } else if entries.isEmpty,
                      execution.diagnostic.operation == .removeEntry {
                output = makeOutput(
                    identity: identity,
                    listRevision: lists[0].revision,
                    membership: .absent,
                    legacyEntryIsChecked: nil
                )
            } else {
                return nil
            }

            outputEmissionCount &+= 1
            return output
        } catch {
            return nil
        }
    }

    var counters: ProductStateCompatibilityAccessCounters {
        ProductStateCompatibilityAccessCounters(
            targetReadCount: targetReadCount,
            outputEmissionCount: outputEmissionCount,
            legacyReadCount: 0,
            legacyWriteCount: 0,
            reverseSynchronizationCount: 0
        )
    }

    private func makeOutput(
        identity: ProductStateListEntryIdentity,
        listRevision: UInt64,
        membership: ProductStateLegacyEntryMembership,
        legacyEntryIsChecked: Bool?
    ) -> ProductStateLegacyEntryCompatibilityOutput {
        ProductStateLegacyEntryCompatibilityOutput(
            listID: identity.listID.rawValue,
            listRevision: listRevision,
            entryID: identity.id.rawValue,
            productID: identity.productID.rawValue,
            membership: membership,
            legacyEntryIsChecked: legacyEntryIsChecked,
            legacyShoppingItemIsCompleted: nil
        )
    }

    private func authoritativeIdentity(
        from execution: ProductStateNamedListCommandExecution
    ) -> ProductStateListEntryIdentity? {
        switch execution.outcome {
        case let .entryAdded(summary),
             let .entryUpdated(summary),
             let .entryResolved(summary, _),
             let .entryReopened(summary),
             let .entryRemoved(summary):
            summary.entry
        case let .existingNeeded(identity, _),
             let .reopenRequired(identity, _):
            identity
        case let .noOp(_, entry, _):
            entry
        case .listCreated, .listRenamed, .conflict,
             .validationFailure, .unavailable:
            nil
        }
    }

    private func isPermittedOutcome(
        _ outcome: ProductStateNamedListCommandOutcome
    ) -> Bool {
        switch outcome {
        case .entryAdded, .existingNeeded, .reopenRequired,
             .entryUpdated, .entryResolved, .entryReopened,
             .entryRemoved, .noOp:
            true
        case .listCreated, .listRenamed, .conflict,
             .validationFailure, .unavailable:
            false
        }
    }
}
