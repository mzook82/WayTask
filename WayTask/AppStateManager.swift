//
//  Untitled.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import Combine
import CoreLocation
import Foundation
import SwiftUI
import UserNotifications

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case products
    case shopping
    case map
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .products:
            return "Products"
        case .shopping:
            return "Shopping"
        case .map:
            return "Map"
        case .settings:
            return "Settings"
        }
    }

    var systemImageName: String {
        switch self {
        case .home:
            return "house.fill"
        case .products:
            return "shippingbox.fill"
        case .shopping:
            return "list.bullet.rectangle.fill"
        case .map:
            return "map.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct NearbyShoppingOpportunity: Identifiable, Equatable {
    let id: String
    let storeID: UUID?
    let locationID: UUID?
    let title: String
    let itemNames: [String]
    let sourceType: String
    let distanceMeters: CLLocationDistance
    let realityScore: Double
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let detectedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km away", distanceMeters / 1000)
        }

        return "\(max(Int(distanceMeters.rounded()), 1)) m away"
    }

    var itemSummary: String {
        if itemNames.isEmpty {
            return "Recommended Store. Availability is estimated."
        }

        if itemNames.count == 1 {
            return "\(itemNames[0]) is likely here. Availability is estimated."
        }

        let visibleNames = itemNames.prefix(2).joined(separator: ", ")
        let suffix = itemNames.count > 2 ? ", and more" : ""
        return "\(itemNames.count) items are likely here: \(visibleNames)\(suffix). Availability is estimated. Some items may require another store."
    }
}

struct StoreNavigationContext: Equatable {
    let storeID: UUID
    let locationID: UUID?
    let title: String
    let coordinate: CLLocationCoordinate2D?
    let sourceType: DataSourceType
    let matchedShoppingItemIDs: [UUID]
    let matchedItemNames: [String]
    let shoppingListID: UUID?
    let notificationType: String

    static func == (lhs: StoreNavigationContext, rhs: StoreNavigationContext) -> Bool {
        lhs.storeID == rhs.storeID &&
            lhs.locationID == rhs.locationID &&
            lhs.title == rhs.title &&
            lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
            lhs.coordinate?.longitude == rhs.coordinate?.longitude &&
            lhs.sourceType == rhs.sourceType &&
            lhs.matchedShoppingItemIDs == rhs.matchedShoppingItemIDs &&
            lhs.matchedItemNames == rhs.matchedItemNames &&
            lhs.shoppingListID == rhs.shoppingListID &&
            lhs.notificationType == rhs.notificationType
    }
}

// MARK: - T-14 exact Shopping Plan consumer authority

enum ShoppingPlanConsumerReadiness: String, Equatable, Sendable {
    case noUsablePlan
    case generating
    case currentReady
    case stale
    case unavailable
    case invalidOrIncomplete
}

enum ShoppingPlanConsumerAttention: String, Equatable, Sendable {
    case none
    case explicitExclusions
    case unresolvedEntries
    case exclusionsAndUnresolvedEntries
}

enum ShoppingPlanConsumerInvalidReason:
    String, CaseIterable, Equatable, Sendable {
    case invalidScope
    case duplicateEntryIdentity
    case incompleteNeededEntryAccounting
    case invalidEligibleEntry
    case invalidExclusion
    case mismatchedPlanStatus
    case mismatchedDerivedProjection
    case unclassifiedPlanningIntent
}

struct ShoppingPlanConsumerStatus {
    let readiness: ShoppingPlanConsumerReadiness
    let attention: ShoppingPlanConsumerAttention
    let staleReasons: [ShoppingPlanStaleReason]
    let invalidReasons: [ShoppingPlanConsumerInvalidReason]
    let unavailableReason: ProductStateProjectionUnavailableReason?
    let sourceListID: ProductStateListID?
    let sourceRevision: ProductStateListRevision?
    let inputFingerprint: String?
    let includedEntryIDs: [ProductStateListEntryID]
    let explicitlyExcludedEntryIDs: [ProductStateListEntryID]
    let unresolvedEntryIDs: [ProductStateListEntryID]
}

struct ShoppingPlanInputItem {
    let identity: ProductStateListEntryIdentity
    let quantity: Double
    let unitRawValue: String?
    let sortOrder: Double
    let displayName: String
    let brand: String?
    let category: String?
    let catalogID: ProductStateCatalogID?
    let catalogCategoryID: String?
    let productLifecycle: ProductLibraryLifecycle
}

struct ShoppingPlanConsumerExclusion {
    let identity: ProductStateListEntryIdentity
    let reason: ProductStatePlanInputExclusionReason

    var isExplicitUserExclusion: Bool {
        reason == .explicitUserExclusion
    }
}

struct ShoppingPlanInputAuthority {
    let projection: ProductStatePlanInputProjection
    let items: [ShoppingPlanInputItem]
    let exclusions: [ShoppingPlanConsumerExclusion]
    let inputFingerprint: String

    var explicitExclusions: [ShoppingPlanConsumerExclusion] {
        exclusions.filter(\.isExplicitUserExclusion)
    }

    var unresolvedEntries: [ShoppingPlanConsumerExclusion] {
        exclusions.filter { !$0.isExplicitUserExclusion }
    }

    var attention: ShoppingPlanConsumerAttention {
        switch (explicitExclusions.isEmpty, unresolvedEntries.isEmpty) {
        case (true, true): .none
        case (false, true): .explicitExclusions
        case (true, false): .unresolvedEntries
        case (false, false): .exclusionsAndUnresolvedEntries
        }
    }
}

struct ShoppingPlanConsumerPlan {
    let plan: ProductStateShoppingPlan
    let input: ShoppingPlanInputAuthority
    let planStatus: ProductStatePlanStatusProjection
    let status: ShoppingPlanConsumerStatus
    let generatedAt: Date
    let intentClassification: ShoppingPlanIntentClassification
    let storeResolutionIntents: [StoreResolutionIntent]
    let shoppingContext: ShoppingContext
    let decision: DecisionResult
    let tripCoverages: [ShoppingPlanStoreCoverage]
    let buyingOptions: [ShoppingPlanBuyingOption]
    let discoveryContext: ProductStateDiscoveryContextProjection
    let storeRecommendations: ProductStateStoreRecommendationsProjection
}

enum ShoppingPlanInputAuthorityOutcome {
    case success(ShoppingPlanInputAuthority)
    case failure(ShoppingPlanConsumerStatus)
}

enum ShoppingPlanBuildOutcome {
    case success(
        ProductStateShoppingPlan,
        ShoppingPlanInputAuthority,
        ShoppingPlanConsumerStatus
    )
    case failure(ShoppingPlanConsumerStatus)
}

enum ShoppingPlanConsumerBoundary {
    static func emptyConsumerStatus() -> ShoppingPlanConsumerStatus {
        emptyStatus(.noUsablePlan)
    }

    static func invalidStatus(
        input: ProductStatePlanInputProjection,
        reason: ShoppingPlanConsumerInvalidReason
    ) -> ShoppingPlanConsumerStatus {
        status(
            readiness: .invalidOrIncomplete,
            attention: .none,
            input: input,
            invalidReasons: [reason]
        )
    }

    static func includingClassificationUncertainty(
        _ status: ShoppingPlanConsumerStatus,
        classification: ShoppingPlanIntentClassification
    ) -> ShoppingPlanConsumerStatus {
        let classificationIDs = classification.unresolvedItems
            .map(\.identity.id)
        guard !classificationIDs.isEmpty else { return status }
        let unresolved = Array(
            Set(status.unresolvedEntryIDs + classificationIDs)
        ).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        let attention: ShoppingPlanConsumerAttention =
            status.explicitlyExcludedEntryIDs.isEmpty
                ? .unresolvedEntries
                : .exclusionsAndUnresolvedEntries
        let readiness: ShoppingPlanConsumerReadiness
        switch status.readiness {
        case .stale, .unavailable:
            readiness = status.readiness
        default:
            readiness = .invalidOrIncomplete
        }
        return ShoppingPlanConsumerStatus(
            readiness: readiness,
            attention: attention,
            staleReasons: status.staleReasons,
            invalidReasons: Array(
                Set(
                    status.invalidReasons +
                        [.unclassifiedPlanningIntent]
                )
            ).sorted { $0.rawValue < $1.rawValue },
            unavailableReason: status.unavailableReason,
            sourceListID: status.sourceListID,
            sourceRevision: status.sourceRevision,
            inputFingerprint: status.inputFingerprint,
            includedEntryIDs: status.includedEntryIDs,
            explicitlyExcludedEntryIDs:
                status.explicitlyExcludedEntryIDs,
            unresolvedEntryIDs: unresolved
        )
    }

    static func inputAuthority(
        _ input: ProductStatePlanInputProjection
    ) -> ShoppingPlanInputAuthorityOutcome {
        let validation = validate(input)
        let exclusions = input.exclusions.map {
            ShoppingPlanConsumerExclusion(
                identity: $0.entry.identity,
                reason: $0.reason
            )
        }
        let attention = attention(for: exclusions)
        guard validation.isEmpty else {
            return .failure(
                status(
                    readiness: .invalidOrIncomplete,
                    attention: attention,
                    input: input,
                    invalidReasons: validation
                )
            )
        }

        let items = input.eligibleEntries.compactMap { entry in
            entry.product.map { product in
                ShoppingPlanInputItem(
                    identity: entry.identity,
                    quantity: entry.quantity,
                    unitRawValue: entry.unitRawValue,
                    sortOrder: entry.sortOrder,
                    displayName: product.displayName,
                    brand: product.brand,
                    category: product.category,
                    catalogID: product.catalogID,
                    catalogCategoryID:
                        product.catalogCategoryIDSnapshot,
                    productLifecycle: product.libraryLifecycle
                )
            }
        }
        let authority = ShoppingPlanInputAuthority(
            projection: input,
            items: items,
            exclusions: exclusions,
            inputFingerprint: fingerprint(input)
        )
        return .success(authority)
    }

    static func makePlan(
        input: ProductStatePlanInputProjection,
        planStatus: ProductStatePlanStatusProjection,
        generatedAt: Date
    ) -> ShoppingPlanBuildOutcome {
        let authority: ShoppingPlanInputAuthority
        switch inputAuthority(input) {
        case let .success(value):
            authority = value
        case let .failure(value):
            return .failure(value)
        }

        let included = authority.items.map(\.identity)
        let exclusions = authority.exclusions.map {
            ShoppingPlanExclusion(
                entry: $0.identity,
                reason: domainExclusionReason($0.reason)
            )
        }
        let plan = ProductStateShoppingPlan(
            id: planStatus.planID,
            sourceListID: input.listID,
            sourceRevision: input.revision,
            includedEntries: included,
            exclusions: exclusions,
            status: planStatus.status
        )

        let mismatch = statusMismatch(
            plan: plan,
            input: authority,
            planStatus: planStatus
        )
        guard mismatch.isEmpty else {
            return .failure(
                status(
                    readiness: .invalidOrIncomplete,
                    attention: authority.attention,
                    input: input,
                    invalidReasons: mismatch
                )
            )
        }

        let evaluated = evaluate(
            plan: plan,
            storedInput: authority,
            currentInput: input,
            currentPlanStatus: planStatus
        )
        return .success(plan, authority, evaluated)
    }

    static func evaluate(
        publishedPlan: ShoppingPlanConsumerPlan?,
        currentInput: ProductStateProjectionOutcome<
            ProductStatePlanInputProjection
        >?,
        currentPlanStatus: ProductStatePlanStatusProjection?
    ) -> ShoppingPlanConsumerStatus {
        guard let publishedPlan else {
            return emptyStatus(.noUsablePlan)
        }
        guard let currentInput else {
            return emptyStatus(
                .unavailable,
                unavailableReason: .notFound,
                sourceListID: publishedPlan.input.projection.listID,
                sourceRevision: publishedPlan.input.projection.revision,
                fingerprint: publishedPlan.input.inputFingerprint
            )
        }
        switch currentInput {
        case let .unavailable(metadata):
            let reason: ProductStateProjectionUnavailableReason
            if case let .unavailable(value) = metadata.freshness {
                reason = value
            } else {
                reason = .repositoryReadFailed
            }
            return emptyStatus(
                .unavailable,
                unavailableReason: reason,
                sourceListID: publishedPlan.input.projection.listID,
                sourceRevision: publishedPlan.input.projection.revision,
                fingerprint: publishedPlan.input.inputFingerprint
            )
        case let .projection(input):
            guard let currentPlanStatus else {
                return emptyStatus(
                    .unavailable,
                    unavailableReason: .notFound,
                    sourceListID: input.listID,
                    sourceRevision: input.revision,
                    fingerprint: fingerprint(input)
                )
            }
            return evaluate(
                plan: publishedPlan.plan,
                storedInput: publishedPlan.input,
                currentInput: input,
                currentPlanStatus: currentPlanStatus
            )
        }
    }

    static func fingerprint(
        _ input: ProductStatePlanInputProjection
    ) -> String {
        var fields: [String] = [
            "t14-plan-input-v1",
            input.listID.rawValue.uuidString,
            String(input.revision.value),
            input.declaredInputFingerprint
        ]
        fields.append(contentsOf: input.eligibleEntries.flatMap { entry in
            let product = entry.product
            return [
                "included",
                entry.identity.id.rawValue.uuidString,
                entry.identity.productID.rawValue.uuidString,
                String(entry.quantity.bitPattern, radix: 16),
                entry.unitRawValue ?? "",
                String(entry.sortOrder.bitPattern, radix: 16),
                product?.displayName ?? "",
                product?.brand ?? "",
                product?.category ?? "",
                product?.catalogID?.rawValue ?? "",
                product?.catalogCategoryIDSnapshot ?? "",
                product?.libraryLifecycle.rawValue ?? "missing"
            ]
        })
        fields.append(contentsOf: input.exclusions.flatMap {
            [
                "excluded",
                $0.entry.identity.id.rawValue.uuidString,
                $0.entry.identity.productID.rawValue.uuidString,
                $0.reason.rawValue
            ]
        })
        fields.append(contentsOf: input.allNeededEntryIDs.flatMap {
            ["needed", $0.rawValue.uuidString]
        })
        let canonical = fields.map(lengthPrefixed).joined(separator: "|")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "t14-%016llx", hash)
    }

    private static func evaluate(
        plan: ProductStateShoppingPlan,
        storedInput: ShoppingPlanInputAuthority,
        currentInput: ProductStatePlanInputProjection,
        currentPlanStatus: ProductStatePlanStatusProjection
    ) -> ShoppingPlanConsumerStatus {
        let currentAuthority: ShoppingPlanInputAuthority
        switch inputAuthority(currentInput) {
        case let .success(value):
            currentAuthority = value
        case let .failure(value):
            return value
        }

        let mismatch = statusMismatch(
            plan: plan,
            input: currentAuthority,
            planStatus: currentPlanStatus
        )
        guard mismatch.isEmpty else {
            return status(
                readiness: .invalidOrIncomplete,
                attention: currentAuthority.attention,
                input: currentInput,
                fingerprint: currentAuthority.inputFingerprint,
                invalidReasons: mismatch
            )
        }

        var staleReasons = currentPlanStatus.staleReasons
        if plan.sourceListID != currentInput.listID ||
            plan.sourceRevision != currentInput.revision {
            staleReasons.append(.sourceRevisionChanged)
        }
        if plan.includedEntries.map(\.id) !=
            currentAuthority.items.map(\.identity.id) {
            staleReasons.append(.includedEntriesChanged)
        }
        if storedInput.inputFingerprint !=
            currentAuthority.inputFingerprint {
            staleReasons.append(.planningInputChanged)
        }
        if case let .stale(reasons) = currentInput.metadata.freshness {
            staleReasons.append(contentsOf: reasons.map(staleReason))
        }
        if case let .stale(reason) = currentPlanStatus.status {
            staleReasons.append(reason)
        }
        staleReasons = Array(Set(staleReasons)).sorted {
            $0.rawValue < $1.rawValue
        }

        let readiness: ShoppingPlanConsumerReadiness
        if !staleReasons.isEmpty {
            readiness = .stale
        } else if !currentAuthority.unresolvedEntries.isEmpty {
            readiness = .invalidOrIncomplete
        } else if currentAuthority.items.isEmpty {
            readiness = .noUsablePlan
        } else {
            switch currentPlanStatus.status {
            case .ready:
                readiness = .currentReady
            case .generating:
                readiness = .generating
            case .idle:
                readiness = .noUsablePlan
            case .failed:
                readiness = .invalidOrIncomplete
            case .stale:
                readiness = .stale
            }
        }

        return status(
            readiness: readiness,
            attention: currentAuthority.attention,
            input: currentInput,
            fingerprint: currentAuthority.inputFingerprint,
            staleReasons: staleReasons
        )
    }

    private static func validate(
        _ input: ProductStatePlanInputProjection
    ) -> [ShoppingPlanConsumerInvalidReason] {
        var reasons: Set<ShoppingPlanConsumerInvalidReason> = []
        guard input.metadata.scope == .list(input.listID),
              input.metadata.listRevision == input.revision else {
            reasons.insert(.invalidScope)
            return reasons.sorted { $0.rawValue < $1.rawValue }
        }

        let included = input.eligibleEntries.map(\.identity.id)
        let excluded = input.exclusions.map(\.entry.identity.id)
        let needed = input.allNeededEntryIDs
        if Set(included).count != included.count ||
            Set(excluded).count != excluded.count ||
            Set(needed).count != needed.count {
            reasons.insert(.duplicateEntryIdentity)
        }
        if !Set(included).isDisjoint(with: Set(excluded)) ||
            Set(included + excluded) != Set(needed) {
            reasons.insert(.incompleteNeededEntryAccounting)
        }
        if input.eligibleEntries.contains(where: {
            $0.identity.listID != input.listID ||
                $0.product == nil ||
                !$0.issues.isEmpty ||
                $0.product?.libraryLifecycle != .active
        }) {
            reasons.insert(.invalidEligibleEntry)
        }
        if input.exclusions.contains(where: {
            $0.entry.identity.listID != input.listID
        }) {
            reasons.insert(.invalidExclusion)
        }
        return reasons.sorted { $0.rawValue < $1.rawValue }
    }

    private static func statusMismatch(
        plan: ProductStateShoppingPlan,
        input: ShoppingPlanInputAuthority,
        planStatus: ProductStatePlanStatusProjection
    ) -> [ShoppingPlanConsumerInvalidReason] {
        guard planStatus.planID == plan.id,
              planStatus.sourceListID == plan.sourceListID,
              planStatus.sourceRevision == plan.sourceRevision,
              planStatus.includedEntryIDs == plan.includedEntries.map(\.id),
              planStatus.excludedEntryIDs == plan.exclusions.map(\.entry.id),
              planStatus.metadata.scope ==
                .plan(plan.id, plan.sourceListID),
              planStatus.metadata.listRevision == input.projection.revision
        else {
            return [.mismatchedPlanStatus]
        }
        return []
    }

    private static func status(
        readiness: ShoppingPlanConsumerReadiness,
        attention: ShoppingPlanConsumerAttention,
        input: ProductStatePlanInputProjection,
        fingerprint: String? = nil,
        staleReasons: [ShoppingPlanStaleReason] = [],
        invalidReasons: [ShoppingPlanConsumerInvalidReason] = []
    ) -> ShoppingPlanConsumerStatus {
        ShoppingPlanConsumerStatus(
            readiness: readiness,
            attention: attention,
            staleReasons: staleReasons,
            invalidReasons: invalidReasons,
            unavailableReason: nil,
            sourceListID: input.listID,
            sourceRevision: input.revision,
            inputFingerprint: fingerprint ?? self.fingerprint(input),
            includedEntryIDs: input.eligibleEntries.map(\.identity.id),
            explicitlyExcludedEntryIDs: input.exclusions.filter {
                $0.reason == .explicitUserExclusion
            }.map(\.entry.identity.id),
            unresolvedEntryIDs: input.exclusions.filter {
                $0.reason != .explicitUserExclusion
            }.map(\.entry.identity.id)
        )
    }

    private static func emptyStatus(
        _ readiness: ShoppingPlanConsumerReadiness,
        unavailableReason: ProductStateProjectionUnavailableReason? = nil,
        sourceListID: ProductStateListID? = nil,
        sourceRevision: ProductStateListRevision? = nil,
        fingerprint: String? = nil
    ) -> ShoppingPlanConsumerStatus {
        ShoppingPlanConsumerStatus(
            readiness: readiness,
            attention: .none,
            staleReasons: [],
            invalidReasons: [],
            unavailableReason: unavailableReason,
            sourceListID: sourceListID,
            sourceRevision: sourceRevision,
            inputFingerprint: fingerprint,
            includedEntryIDs: [],
            explicitlyExcludedEntryIDs: [],
            unresolvedEntryIDs: []
        )
    }

    private static func attention(
        for exclusions: [ShoppingPlanConsumerExclusion]
    ) -> ShoppingPlanConsumerAttention {
        let explicit = exclusions.contains {
            $0.isExplicitUserExclusion
        }
        let unresolved = exclusions.contains { !$0.isExplicitUserExclusion }
        switch (explicit, unresolved) {
        case (false, false): return .none
        case (true, false): return .explicitExclusions
        case (false, true): return .unresolvedEntries
        case (true, true): return .exclusionsAndUnresolvedEntries
        }
    }

    private static func domainExclusionReason(
        _ reason: ProductStatePlanInputExclusionReason
    ) -> ShoppingPlanExclusionReason {
        switch reason {
        case .explicitUserExclusion: .userExcluded
        case .missingProduct, .ambiguousProduct, .removedProduct:
            .invalidProduct
        case .malformedEntry: .unsupported
        }
    }

    nonisolated private static func staleReason(
        _ reason: ProductStateProjectionStaleReason
    ) -> ShoppingPlanStaleReason {
        switch reason {
        case .expectedListRevisionChanged, .sourceIdentityChanged,
             .sourceRevisionChanged:
            .sourceRevisionChanged
        case .includedEntriesChanged:
            .includedEntriesChanged
        case .evidenceExpired:
            .evidenceExpired
        case .expectedSessionRevisionChanged, .declaredInputChanged,
             .snapshotChanged:
            .planningInputChanged
        }
    }

    nonisolated private static func lengthPrefixed(
        _ value: String
    ) -> String {
        "\(value.utf8.count):\(value)"
    }
}

struct ShoppingPlan: Identifiable {
    let id: UUID
    let request: ShoppingStoreSuggestionRequest
    let items: [ShoppingItem]
    let stores: [MapStore]
    let buyingOptions: [BuyingOption]
    let shoppingTripCoverages: [StoreCoverage]
    let generatedAt: Date
    let contentSignature: String

    init(
        id: UUID = UUID(),
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.items = items.filter { !$0.isCompleted }
        self.stores = stores
        self.buyingOptions = buyingOptions
        self.shoppingTripCoverages = shoppingTripCoverages
        self.generatedAt = generatedAt
        self.contentSignature = ShoppingPlan.makeContentSignature(
            request: request,
            items: self.items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
    }

    var bestCoverage: StoreCoverage? {
        shoppingTripCoverages.first
    }

    private static func makeContentSignature(
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage]
    ) -> String {
        [
            requestSignature(request),
            itemSignature(items),
            storeSignature(stores),
            buyingOptionSignature(buyingOptions),
            coverageSignature(shoppingTripCoverages)
        ].joined(separator: "|")
    }

    private static func requestSignature(_ request: ShoppingStoreSuggestionRequest) -> String {
        [
            request.itemID.uuidString,
            request.itemName,
            request.itemCategory ?? "",
            request.storeCategories.map(\.rawValue).joined(separator: ","),
            request.searchTerms.joined(separator: ","),
            intentProfileSignature(request.intentProfile)
        ].joined(separator: ":")
    }

    private static func intentProfileSignature(_ profile: ProductIntentProfile?) -> String {
        guard let profile else {
            return ""
        }

        return [
            profile.normalizedCategory.rawValue,
            profile.intentGroup.rawValue,
            String(format: "%.2f", profile.confidence),
            profile.evidence.sorted().joined(separator: ","),
            profile.primaryAllowedStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.secondaryAllowedStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.fallbackStoreTypes.map(\.rawValue).sorted().joined(separator: ","),
            profile.excludedStoreTypes.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "/")
    }

    private static func itemSignature(_ items: [ShoppingItem]) -> String {
        items
            .map { item in
                [
                    item.id.uuidString,
                    item.name,
                    item.brand ?? "",
                    item.category ?? "",
                    item.catalogProductIDRawValue ?? "",
                    item.catalogCategoryIDRawValue ?? "",
                    item.catalogSubcategoryIDRawValue ?? "",
                    item.isCompleted ? "1" : "0"
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func storeSignature(_ stores: [MapStore]) -> String {
        stores
            .map { store in
                [
                    store.id.uuidString,
                    store.title,
                    String(format: "%.5f", store.coordinate.latitude),
                    String(format: "%.5f", store.coordinate.longitude),
                    store.itemNames.sorted().joined(separator: ","),
                    store.completedItemNames.sorted().joined(separator: ","),
                    store.storeCategories.map(\.rawValue).sorted().joined(separator: ","),
                    store.sourceType.rawValue
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func buyingOptionSignature(_ buyingOptions: [BuyingOption]) -> String {
        buyingOptions
            .map { option in
                [
                    option.title,
                    option.subtitle,
                    option.optionType.rawValue,
                    option.storeName,
                    option.distanceText,
                    option.source.rawValue,
                    String(format: "%.2f", option.ranking?.score ?? -1),
                    option.confidenceLabel ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: ";")
    }

    private static func coverageSignature(_ coverages: [StoreCoverage]) -> String {
        coverages
            .map { coverage in
                [
                    coverage.id,
                    coverage.store.title,
                    coverage.group.rawValue,
                    coverage.matchedItems.map(\.id.uuidString).sorted().joined(separator: ","),
                    coverage.missingItems.map(\.id.uuidString).sorted().joined(separator: ","),
                    String(format: "%.4f", coverage.coverageScore),
                    String(format: "%.1f", coverage.distance ?? -1),
                    String(format: "%.2f", coverage.ranking.score),
                    String(format: "%.2f", coverage.ranking.confidence)
                ].joined(separator: ":")
            }
            .joined(separator: ";")
    }
}

enum ShoppingPlanGenerationStage: String, CaseIterable, Equatable {
    case preparingList
    case findingStores
    case matchingProducts
    case calculatingCoverage
    case rankingOptions

    var title: String {
        switch self {
        case .preparingList:
            return "Preparing your shopping list"
        case .findingStores:
            return "Finding nearby stores"
        case .matchingProducts:
            return "Estimating products by store"
        case .calculatingCoverage:
            return "Calculating coverage"
        case .rankingOptions:
            return "Ranking recommended stores"
        }
    }
}

enum ShoppingPlanGenerationState: Equatable {
    case idle
    case generating(stage: ShoppingPlanGenerationStage, startedAt: Date)
    case ready(generatedAt: Date)
    case failed(message: String, actionTitle: String?)
    case stale(reason: String)

    var isGenerating: Bool {
        if case .generating = self {
            return true
        }

        return false
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    var stageTitle: String? {
        if case let .generating(stage, _) = self {
            return stage.title
        }

        return nil
    }

    var startedAt: Date? {
        if case let .generating(_, startedAt) = self {
            return startedAt
        }

        return nil
    }
}

final class AppStateManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var selectedTab: AppTab = .home
    @Published var navigationPath = NavigationPath()
    @Published var focusedLocationID: UUID?
    @Published var shoppingListRevision = UUID()
    @Published var recentlyAddedShoppingItemID: UUID?
    @Published private(set) var shoppingPlan: ShoppingPlan?
    @Published private(set) var shoppingPlanState: ShoppingPlanGenerationState = .idle
    @Published private(set) var productStateShoppingPlan:
        ShoppingPlanConsumerPlan?
    @Published private(set) var productStateShoppingPlanStatus =
        ShoppingPlanConsumerBoundary.emptyConsumerStatus()
    @Published private(set) var currentShoppingListID: UUID?
    @Published var selectedShoppingListID: UUID?
    @Published private(set) var currentProductLibraryIDs: [UUID] = []
    @Published var isTripMapMode = false
    @Published private(set) var nearbyOpportunities: [NearbyShoppingOpportunity] = []
    @Published private(set) var storeNavigationContext: StoreNavigationContext?

    private let storeResolutionEngine = StoreResolutionEngine.shared
    private let nearbyIntentMatcher = ShoppingIntentMatcher()
    private let storeRankingService = StoreRankingService()
    private let targetTripService = ShoppingTripService()
    private let targetBuyingOptionsService = BuyingOptionsService()
    private let targetDecisionEngine = DecisionEngine()
    private let nearbyRadius: CLLocationDistance = 350
    private let maxNearbyOpportunities = 8
    private let nearbyDismissCooldown: TimeInterval = 15 * 60
    private let userDefaults = UserDefaults.standard
    private var nearbyRefreshGeneration = 0

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var visibleNearbyOpportunity: NearbyShoppingOpportunity? {
        nearbyOpportunities.first { !isNearbyOpportunityDismissed($0) }
    }

    var storeSuggestionRequest: ShoppingStoreSuggestionRequest? {
        shoppingPlan?.request
    }

    var buyingOptions: [BuyingOption] {
        shoppingPlan?.buyingOptions ?? []
    }

    var shoppingTripCoverages: [StoreCoverage] {
        shoppingPlan?.shoppingTripCoverages ?? []
    }

    @discardableResult
    func publishProductStateShoppingPlan(
        input: ProductStatePlanInputProjection,
        planStatus: ProductStatePlanStatusProjection,
        stores: [MapStore],
        userCoordinate: CLLocationCoordinate2D? = nil,
        discoveryContext: ProductStateDiscoveryContextProjection,
        storeRecommendations:
            ProductStateStoreRecommendationsProjection,
        generatedAt: Date
    ) -> ShoppingPlanConsumerStatus {
        let plan: ProductStateShoppingPlan
        let authority: ShoppingPlanInputAuthority
        var evaluated: ShoppingPlanConsumerStatus
        switch ShoppingPlanConsumerBoundary.makePlan(
            input: input,
            planStatus: planStatus,
            generatedAt: generatedAt
        ) {
        case let .success(valuePlan, valueAuthority, valueStatus):
            plan = valuePlan
            authority = valueAuthority
            evaluated = valueStatus
        case let .failure(status):
            productStateShoppingPlan = nil
            productStateShoppingPlanStatus = status
            return status
        }

        guard derivedProjectionOwnersMatch(
            discoveryContext: discoveryContext,
            storeRecommendations: storeRecommendations,
            authority: authority,
            planStatus: planStatus
        ) else {
            let status = ShoppingPlanConsumerBoundary.invalidStatus(
                input: input,
                reason: .mismatchedDerivedProjection
            )
            productStateShoppingPlan = nil
            productStateShoppingPlanStatus = status
            return status
        }

        let classification = nearbyIntentMatcher.classify(authority)
        evaluated = ShoppingPlanConsumerBoundary
            .includingClassificationUncertainty(
                evaluated,
                classification: classification
            )
        let intents = storeResolutionEngine.intents(
            for: authority,
            classification: classification
        )
        let contextStores = stores.map { store in
            ShoppingContextStore(
                id: store.id,
                name: store.title,
                coordinate: ShoppingCoordinate(store.coordinate),
                matchingItemNames: store.itemNames.sorted(),
                isFavorite: store.isSavedLocation,
                websiteURL: store.websiteURL
            )
        }
        let exactLocation: ShoppingCoordinate?
        if let userCoordinate {
            exactLocation = ShoppingCoordinate(userCoordinate)
        } else {
            exactLocation = nil
        }
        let context = ShoppingContext.exactPlanInput(
            authority,
            nearbyStores: contextStores,
            currentLocation: exactLocation,
            observedAt: generatedAt
        )
        let decision = targetDecisionEngine.evaluate(
            mission: .exploreNearby,
            context: context
        )
        let coverages = targetTripService.coverage(
            for: authority,
            classification: classification,
            stores: stores,
            userCoordinate: userCoordinate
        )
        let options = targetBuyingOptionsService.localOptions(
            for: authority,
            classification: classification,
            intents: intents,
            stores: stores,
            userCoordinate: userCoordinate
        )
        let published = ShoppingPlanConsumerPlan(
            plan: plan,
            input: authority,
            planStatus: planStatus,
            status: evaluated,
            generatedAt: generatedAt,
            intentClassification: classification,
            storeResolutionIntents: intents,
            shoppingContext: context,
            decision: decision,
            tripCoverages: coverages,
            buyingOptions: options,
            discoveryContext: discoveryContext,
            storeRecommendations: storeRecommendations
        )
        productStateShoppingPlan = published
        productStateShoppingPlanStatus = evaluated
        return evaluated
    }

    @discardableResult
    func refreshProductStateShoppingPlanStatus(
        currentInput: ProductStateProjectionOutcome<
            ProductStatePlanInputProjection
        >?,
        currentPlanStatus: ProductStatePlanStatusProjection?
    ) -> ShoppingPlanConsumerStatus {
        var evaluated = ShoppingPlanConsumerBoundary.evaluate(
            publishedPlan: productStateShoppingPlan,
            currentInput: currentInput,
            currentPlanStatus: currentPlanStatus
        )
        if let classification = productStateShoppingPlan?
            .intentClassification {
            evaluated = ShoppingPlanConsumerBoundary
                .includingClassificationUncertainty(
                    evaluated,
                    classification: classification
                )
        }
        productStateShoppingPlanStatus = evaluated
        return evaluated
    }

    func discardProductStateShoppingPlan() {
        productStateShoppingPlan = nil
        productStateShoppingPlanStatus =
            ShoppingPlanConsumerBoundary.emptyConsumerStatus()
    }

    private func derivedProjectionOwnersMatch(
        discoveryContext: ProductStateDiscoveryContextProjection,
        storeRecommendations:
            ProductStateStoreRecommendationsProjection,
        authority: ShoppingPlanInputAuthority,
        planStatus: ProductStatePlanStatusProjection
    ) -> Bool {
        let owner = ProductStateShoppingContextOwner.plan(
            planStatus.planID,
            planStatus.sourceListID,
            planStatus.sourceRevision
        )
        let scope = ProductStateProjectionScope.plan(
            planStatus.planID,
            planStatus.sourceListID
        )
        let productIDs = Array(Set(authority.items.map(
            \.identity.productID
        ))).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        guard discoveryContext.owner == owner,
              discoveryContext.metadata.scope == scope,
              discoveryContext.eligibleProductIDs == productIDs,
              storeRecommendations.owner == owner,
              storeRecommendations.metadata.scope == scope else {
            return false
        }
        return true
    }

    var hasNearbyOpportunityBadge: Bool {
        visibleNearbyOpportunity != nil
    }

    func focusMap(on locationID: UUID) {
        isTripMapMode = false
        selectedTab = .map
        focusedLocationID = locationID
    }

    func shoppingListDidChange(revealing itemID: UUID? = nil) {
        recentlyAddedShoppingItemID = itemID
        shoppingListRevision = UUID()
    }

    func setCurrentShoppingList(_ listID: UUID?) {
        if currentShoppingListID != listID {
            currentShoppingListID = listID
        }

        if selectedShoppingListID == nil {
            selectedShoppingListID = listID
        }
    }

    func setCurrentProductLibrary(_ products: [Product]) {
        let productIDs = products
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        if currentProductLibraryIDs != productIDs {
            currentProductLibraryIDs = productIDs
        }
    }

    func suggestStores(
        for request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem] = [],
        stores: [MapStore] = [],
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        setShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
        isTripMapMode = false
        selectedTab = .map
    }

    func showTripOnMap(
        for request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem] = [],
        stores: [MapStore] = [],
        buyingOptions: [BuyingOption] = [],
        shoppingTripCoverages: [StoreCoverage] = []
    ) {
        navigationPath = NavigationPath()
        setShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
        isTripMapMode = true
        selectedTab = .map
    }

    func setShoppingPlan(
        request: ShoppingStoreSuggestionRequest,
        items: [ShoppingItem],
        stores: [MapStore],
        buyingOptions: [BuyingOption],
        shoppingTripCoverages: [StoreCoverage]
    ) {
        let nextPlan = ShoppingPlan(
            request: request,
            items: items,
            stores: stores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )

        if shoppingPlan?.contentSignature == nextPlan.contentSignature {
            if let shoppingPlan {
                BetaDiagnosticsCenter.shared.plannerSucceeded(plan: shoppingPlan, cacheHit: true)
                SentryReportingService.shared.breadcrumb(
                    .planReady,
                    area: .shopping,
                    operation: .planner,
                    numericContext: [
                        .itemCount: shoppingPlan.items.count,
                        .storeCount: shoppingPlan.stores.count
                    ]
                )
            }
            markShoppingPlanReady(generatedAt: shoppingPlan?.generatedAt ?? Date())
            return
        }

        shoppingPlan = nextPlan
        BetaDiagnosticsCenter.shared.plannerSucceeded(plan: nextPlan, cacheHit: false)
        SentryReportingService.shared.breadcrumb(
            .planReady,
            area: .shopping,
            operation: .planner,
            numericContext: [
                .itemCount: nextPlan.items.count,
                .storeCount: nextPlan.stores.count
            ]
        )
        markShoppingPlanReady(generatedAt: nextPlan.generatedAt)
    }

    func clearShoppingPlan() {
        if shoppingPlan != nil {
            shoppingPlan = nil
        }
        setShoppingPlanState(.idle)
    }

    func beginShoppingPlanGeneration(stage: ShoppingPlanGenerationStage = .preparingList) {
        setShoppingPlanState(.generating(stage: stage, startedAt: Date()))
        BetaDiagnosticsCenter.shared.plannerStarted(stage: stage.title)
        SentryReportingService.shared.breadcrumb(
            .planGenerationStarted,
            area: .shopping,
            operation: .planner
        )
    }

    func updateShoppingPlanGeneration(stage: ShoppingPlanGenerationStage) {
        let startedAt = shoppingPlanState.startedAt ?? Date()
        setShoppingPlanState(.generating(stage: stage, startedAt: startedAt))
        BetaDiagnosticsCenter.shared.plannerStageChanged(stage.title)
    }

    func markShoppingPlanReady(generatedAt: Date = Date()) {
        setShoppingPlanState(.ready(generatedAt: generatedAt))
    }

    func markShoppingPlanFailed(message: String, actionTitle: String? = "Try Again") {
        if shoppingPlan != nil {
            shoppingPlan = nil
        }
        setShoppingPlanState(.failed(message: message, actionTitle: actionTitle))
        BetaDiagnosticsCenter.shared.plannerFailed(reason: message)
        SentryReportingService.shared.breadcrumb(
            .planFailed,
            area: .shopping,
            operation: .planner
        )
    }

    func markShoppingPlanStale(reason: String) {
        if shoppingPlan != nil {
            shoppingPlan = nil
        }
        setShoppingPlanState(.stale(reason: reason))
        BetaDiagnosticsCenter.shared.plannerMarkedStale(reason: reason)
    }

    private func setShoppingPlanState(_ state: ShoppingPlanGenerationState) {
        guard shoppingPlanState != state else {
            return
        }

        shoppingPlanState = state
    }

    func openShoppingNotificationOnMap(_ context: StoreNavigationContext) {
        navigationPath = NavigationPath()
        if let shoppingListID = context.shoppingListID {
            let activeListID = selectedShoppingListID ?? currentShoppingListID
            if let activeListID, activeListID != shoppingListID {
                clearShoppingPlan()
            }
            selectedShoppingListID = shoppingListID
        }
        isTripMapMode = false
        focusedLocationID = context.locationID ?? context.storeID
        storeNavigationContext = context
        selectedTab = .map
    }

    func consumeStoreNavigationContext(storeID: UUID) {
        guard storeNavigationContext?.storeID == storeID else {
            return
        }
        storeNavigationContext = nil
    }

    func dismissNearbyOpportunity(_ opportunity: NearbyShoppingOpportunity) {
        let dismissUntil = Date().addingTimeInterval(nearbyDismissCooldown)
        userDefaults.set(dismissUntil.timeIntervalSince1970, forKey: dismissalKey(for: opportunity))
        objectWillChange.send()
    }

    func openNearbyOpportunityOnMap(_ opportunity: NearbyShoppingOpportunity) {
        let sourceType = DataSourceType(rawValue: opportunity.sourceType) ?? .appleMaps
        let storeID = opportunity.storeID ?? StoreRuntimeIdentity.transientID(
            title: opportunity.title,
            coordinate: opportunity.coordinate,
            sourceType: sourceType
        )
        openShoppingNotificationOnMap(StoreNavigationContext(
            storeID: storeID,
            locationID: opportunity.locationID,
            title: opportunity.title,
            coordinate: opportunity.coordinate,
            sourceType: sourceType,
            matchedShoppingItemIDs: [],
            matchedItemNames: opportunity.itemNames,
            shoppingListID: selectedShoppingListID ?? currentShoppingListID,
            notificationType: "nearbyOpportunity"
        ))
    }

    func refreshNearbyOpportunities(
        items: [ShoppingItem],
        savedLocations: [GeoLocation],
        currentCoordinate: CLLocationCoordinate2D?
    ) async {
        nearbyRefreshGeneration += 1
        let refreshGeneration = nearbyRefreshGeneration

        guard let currentCoordinate else {
            nearbyOpportunities = []
            return
        }

        let activeItems = nearbyIntentMatcher.eligibleItems(
            from: items
        )
        guard !activeItems.isEmpty else {
            nearbyOpportunities = []
            return
        }

        let activeGroups = nearbyIntentMatcher.groupedIntents(for: activeItems)
        ShoppingDiscoveryDebugLogger.logGroups(
            context: "Nearby",
            groups: activeGroups
        )
        let resolvedStores = await storeResolutionEngine.resolve(
            savedLocations: savedLocations,
            items: activeItems,
            around: currentCoordinate
        )

        guard refreshGeneration == nearbyRefreshGeneration else {
            return
        }

        let mapOpportunities = nearbyMapOpportunities(
            from: resolvedStores,
            activeItems: activeItems,
            currentCoordinate: currentCoordinate
        )

        nearbyOpportunities = deduplicatedNearbyOpportunities(mapOpportunities)
            .sorted { lhs, rhs in
                if lhs.realityScore == rhs.realityScore {
                    return lhs.distanceMeters < rhs.distanceMeters
                }

                return lhs.realityScore > rhs.realityScore
            }
            .prefixArray(maxNearbyOpportunities)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        await MainActor.run {
            let storeID = (userInfo["storeID"] as? String).flatMap(UUID.init(uuidString:))
            let locationID = (userInfo["geoLocationID"] as? String).flatMap(UUID.init(uuidString:))
            let title = (userInfo["storeTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let latitude = (userInfo["latitude"] as? String).flatMap(Double.init)
            let longitude = (userInfo["longitude"] as? String).flatMap(Double.init)
            let coordinate: CLLocationCoordinate2D?
            if let latitude, let longitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            } else {
                coordinate = nil
            }
            let sourceRawValue = (userInfo["sourceType"] as? String) ?? (userInfo["storeSourceType"] as? String)
            let sourceType = sourceRawValue.flatMap(DataSourceType.init(rawValue:)) ?? .appleMaps
            let itemIDs = ((userInfo["matchedShoppingItemIDs"] as? String) ?? "")
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
            let itemNames = ((userInfo["matchedItemNames"] as? String) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let listID = (userInfo["shoppingListID"] as? String).flatMap(UUID.init(uuidString:))
            let notificationType = (userInfo["notificationType"] as? String) ?? "shoppingGeofence"

            guard let storeID else {
                BetaDiagnosticsCenter.shared.recordError(
                    category: .notification,
                    message: "Notification deep link rejected",
                    detail: "Missing storeID"
                )
                SentryReportingService.shared.capture(
                    message: .notificationDeepLinkFailed,
                    operation: .notification,
                    category: .integration,
                    area: .map
                )
                SentryReportingService.shared.breadcrumb(
                    .notificationDeepLinkFailed,
                    area: .map,
                    operation: .notification
                )
                return
            }
            BetaDiagnosticsCenter.shared.notificationTapped(
                store: title ?? storeID.uuidString,
                deepLinkStatus: coordinate != nil || locationID != nil ? "Payload accepted" : "Missing coordinate and saved location"
            )
            openShoppingNotificationOnMap(StoreNavigationContext(
                storeID: storeID,
                locationID: locationID,
                title: title ?? "",
                coordinate: coordinate,
                sourceType: sourceType,
                matchedShoppingItemIDs: itemIDs,
                matchedItemNames: itemNames,
                shoppingListID: listID,
                notificationType: notificationType
            ))
            SentryReportingService.shared.breadcrumb(
                .notificationDeepLinkHandled,
                area: .map,
                operation: .notification
            )
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func nearbyMapOpportunities(
        from stores: [MapStore],
        activeItems: [ShoppingItem],
        currentCoordinate: CLLocationCoordinate2D
    ) -> [NearbyShoppingOpportunity] {
        let userLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)

        return stores.compactMap { store in
            let matchingItems = nearbyIntentMatcher.relevantItems(from: activeItems, for: store)
            guard !matchingItems.isEmpty else {
                return nil
            }

            let itemNames = notificationItemNames(from: matchingItems)
            let requestedCategories = matchedStoreCategories(for: matchingItems)
            let request = nearbyRealityRequest(
                itemNames: itemNames,
                categories: requestedCategories,
                fallbackID: store.id
            )
            let groupedStore = MapStore(
                id: store.id,
                locationID: store.locationID,
                title: store.title,
                coordinate: store.coordinate,
                radius: store.radius,
                itemNames: itemNames,
                completedItemNames: store.completedItemNames,
                isOpen: store.isOpen,
                rating: store.rating,
                storeCategories: store.storeCategories,
                queryEvidenceCategories: store.queryEvidenceCategories,
                websiteURL: store.websiteURL,
                sourceType: store.sourceType
            )
            let storeLocation = CLLocation(latitude: store.coordinate.latitude, longitude: store.coordinate.longitude)
            let distance = userLocation.distance(from: storeLocation)

            guard storeRankingService.isRelevant(
                store: groupedStore,
                request: request,
                userCoordinate: currentCoordinate
            ) else {
                return nil
            }

            guard distance <= nearbyRadius else {
                return nil
            }

            let ranking = storeRankingService.score(
                store: groupedStore,
                request: request,
                userCoordinate: currentCoordinate,
                coverage: StoreRealityCoverage(
                    matchedItemCount: matchingItems.count,
                    totalItemCount: matchingItems.count
                )
            )

            return NearbyShoppingOpportunity(
                id: stableOpportunityID(for: store),
                storeID: store.locationID ?? store.id,
                locationID: store.locationID,
                title: store.title,
                itemNames: groupedStore.itemNames,
                sourceType: store.sourceType.rawValue,
                distanceMeters: distance,
                realityScore: ranking.score,
                latitude: store.coordinate.latitude,
                longitude: store.coordinate.longitude,
                detectedAt: Date()
            )
        }
    }

    private func nearbyRealityRequest(
        itemNames: [String],
        categories: [ShoppingStoreCategory],
        fallbackID: UUID
    ) -> ShoppingStoreSuggestionRequest {
        let itemName = itemNames.first ?? "Shopping list"
        return ShoppingStoreSuggestionRequest(
            itemID: fallbackID,
            itemName: itemName,
            itemCategory: nil,
            storeCategories: categories,
            searchTerms: itemNames,
            intentProfile: nil
        )
    }

    private func stableOpportunityID(for store: MapStore) -> String {
        if let locationID = store.locationID {
            return "saved-\(locationID.uuidString)"
        }

        let latitude = Int((store.coordinate.latitude * 100_000).rounded())
        let longitude = Int((store.coordinate.longitude * 100_000).rounded())
        return "\(store.sourceType.rawValue)-\(store.title.lowercased())-\(latitude)-\(longitude)"
    }

    private func matchedStoreCategories(for items: [ShoppingItem]) -> [ShoppingStoreCategory] {
        let categories = items.flatMap { nearbyIntentMatcher.matchStoreCategories(for: $0) }
        let uniqueCategories = Array(Set(categories))
        return uniqueCategories.sorted { $0.displayName < $1.displayName }
    }

    private func notificationItemNames(from items: [ShoppingItem]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()

            guard !name.isEmpty, !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            names.append(name)

            if names.count == 3 {
                break
            }
        }

        return names
    }

    private func deduplicatedNearbyOpportunities(_ opportunities: [NearbyShoppingOpportunity]) -> [NearbyShoppingOpportunity] {
        var result: [NearbyShoppingOpportunity] = []

        for opportunity in opportunities {
            let isDuplicate = result.contains { existing in
                existing.id == opportunity.id ||
                existing.title.localizedCaseInsensitiveCompare(opportunity.title) == .orderedSame ||
                distance(from: existing.coordinate, to: opportunity.coordinate) < 35
            }

            if !isDuplicate {
                result.append(opportunity)
            }
        }

        return result
    }

    private func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func isNearbyOpportunityDismissed(_ opportunity: NearbyShoppingOpportunity) -> Bool {
        let dismissedUntil = userDefaults.double(forKey: dismissalKey(for: opportunity))

        guard dismissedUntil > 0 else {
            return false
        }

        return Date().timeIntervalSince1970 < dismissedUntil
    }

    private func dismissalKey(for opportunity: NearbyShoppingOpportunity) -> String {
        "waytask.nearbyOpportunity.dismissedUntil.\(opportunity.id)"
    }
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}

private extension Array where Element == ShoppingStoreCategory {
    func deduplicated() -> [ShoppingStoreCategory] {
        reduce(into: [ShoppingStoreCategory]()) { result, category in
            if !result.contains(category) {
                result.append(category)
            }
        }
    }
}
