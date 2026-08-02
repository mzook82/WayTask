import CoreLocation
import XCTest
@testable import WayTask

@MainActor
final class ProductStateShoppingPlanConsumerConversionTests:
    XCTestCase {
    func testExactT13PipelinePublishesCurrentReadyPlanWithOneAuthority() {
        let fixture = makeFixture(products: [1, 2])
        let derived = makeDerived(fixture)
        let manager = AppStateManager()

        let result = manager.publishProductStateShoppingPlan(
            input: fixture.input,
            planStatus: derived.status,
            stores: stores(),
            discoveryContext: derived.discovery,
            storeRecommendations: derived.recommendations,
            generatedAt: date(500)
        )

        XCTAssertEqual(result.readiness, .currentReady)
        XCTAssertEqual(result.attention, .none)
        XCTAssertEqual(result.sourceListID, listID(100))
        XCTAssertEqual(result.sourceRevision, revision(7))
        XCTAssertEqual(
            result.includedEntryIDs,
            [entryID(11), entryID(12)]
        )
        let plan = try! XCTUnwrap(manager.productStateShoppingPlan)
        XCTAssertEqual(plan.plan.sourceListID, listID(100))
        XCTAssertEqual(plan.plan.sourceRevision, revision(7))
        XCTAssertEqual(
            plan.plan.includedEntries.map(\.id),
            result.includedEntryIDs
        )
        XCTAssertEqual(
            plan.shoppingContext.inputFingerprint,
            result.inputFingerprint
        )
        XCTAssertEqual(
            plan.decision.relatedProductIDs,
            [uuid(1), uuid(2)]
        )
        XCTAssertEqual(plan.discoveryContext.owner, derived.owner)
        XCTAssertEqual(plan.storeRecommendations.owner, derived.owner)
        XCTAssertNil(manager.shoppingPlan)
        XCTAssertEqual(manager.shoppingPlanState, .idle)
        XCTAssertEqual(fixture.repository.mutationCallCount, 0)
    }

    func testExplicitExclusionRemainsNamedAndPlanCanBeCurrent() {
        let fixture = makeFixture(
            products: [1, 2],
            explicitlyExcluded: [2]
        )
        let derived = makeDerived(fixture)
        let manager = AppStateManager()

        let result = publish(manager, fixture, derived)

        XCTAssertEqual(result.readiness, .currentReady)
        XCTAssertEqual(result.attention, .explicitExclusions)
        XCTAssertEqual(result.includedEntryIDs, [entryID(11)])
        XCTAssertEqual(
            result.explicitlyExcludedEntryIDs,
            [entryID(12)]
        )
        XCTAssertTrue(result.unresolvedEntryIDs.isEmpty)
        let plan = try! XCTUnwrap(manager.productStateShoppingPlan)
        XCTAssertEqual(plan.plan.exclusions.count, 1)
        XCTAssertEqual(plan.plan.exclusions[0].reason, .userExcluded)
        XCTAssertEqual(
            plan.shoppingContext.explicitExclusions.map(\.entryID),
            [uuid(12)]
        )
        XCTAssertEqual(
            plan.storeResolutionIntents.first?
                .explicitlyExcludedEntryIDs,
            [entryID(12)]
        )
        XCTAssertTrue(plan.tripCoverages.allSatisfy {
            $0.namedExclusions.map(\.reason) ==
                [.explicitUserExclusion]
        })
        XCTAssertTrue(plan.buyingOptions.allSatisfy {
            $0.namedExclusions.map(\.reason) ==
                [.explicitUserExclusion]
        })
    }

    func testMissingProductIsUnresolvedAndNeverSilentlyDropped() {
        let fixture = makeFixture(
            products: [1, 2],
            omittedProducts: [2]
        )
        let derived = makeDerived(fixture)
        let manager = AppStateManager()

        let result = publish(manager, fixture, derived)

        XCTAssertEqual(result.readiness, .invalidOrIncomplete)
        XCTAssertEqual(result.attention, .unresolvedEntries)
        XCTAssertEqual(result.includedEntryIDs, [entryID(11)])
        XCTAssertEqual(result.unresolvedEntryIDs, [entryID(12)])
        let plan = try! XCTUnwrap(manager.productStateShoppingPlan)
        XCTAssertEqual(
            plan.input.unresolvedEntries.map(\.reason),
            [.missingProduct]
        )
        XCTAssertEqual(
            Set(result.includedEntryIDs + result.unresolvedEntryIDs),
            Set(fixture.input.allNeededEntryIDs)
        )
    }

    func testUnclassifiedEligibleEntryRemainsIncludedAndExplained() {
        let fixture = makeFixture(products: [1, 3])
        let derived = makeDerived(fixture)
        let manager = AppStateManager()

        let result = publish(manager, fixture, derived)

        XCTAssertEqual(result.readiness, .invalidOrIncomplete)
        XCTAssertEqual(result.attention, .unresolvedEntries)
        XCTAssertEqual(
            result.invalidReasons,
            [.unclassifiedPlanningIntent]
        )
        XCTAssertEqual(result.includedEntryIDs, [entryID(11), entryID(13)])
        XCTAssertEqual(result.unresolvedEntryIDs, [entryID(13)])
        let plan = try! XCTUnwrap(manager.productStateShoppingPlan)
        XCTAssertEqual(
            plan.intentClassification.unresolvedItems
                .map(\.identity.id),
            [entryID(13)]
        )
        XCTAssertEqual(
            plan.intentClassification.accountedEntryIDs,
            fixture.input.eligibleEntries.map(\.identity.id).sorted(
                by: entryLess
            )
        )
    }

    func testEmptyExactListHasNoUsablePlanWithoutDefaultSelection() {
        let fixture = makeFixture(products: [])
        let derived = makeDerived(fixture)
        let manager = AppStateManager()

        let result = publish(manager, fixture, derived)

        XCTAssertEqual(result.readiness, .noUsablePlan)
        XCTAssertEqual(result.sourceListID, listID(100))
        XCTAssertEqual(result.sourceRevision, revision(7))
        XCTAssertTrue(result.includedEntryIDs.isEmpty)
        XCTAssertTrue(
            manager.productStateShoppingPlan?
                .storeResolutionIntents.isEmpty == true
        )
    }

    func testQuantityChangeStalesPlanThroughCanonicalFingerprint() {
        let initial = makeFixture(products: [1, 2])
        let derived = makeDerived(initial)
        let manager = AppStateManager()
        _ = publish(manager, initial, derived)
        let changed = makeFixture(
            products: [1, 2],
            quantities: [1: 2]
        )
        let t13Status = changed.boundary.planStatus(
            ProductStatePlanStatusRequest(
                plan: manager.productStateShoppingPlan!.plan,
                planInputFingerprint:
                    initial.input.declaredInputFingerprint,
                currentInput: changed.input
            )
        )

        XCTAssertEqual(t13Status.status, .ready)
        let result = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .projection(changed.input),
            currentPlanStatus: t13Status
        )
        XCTAssertEqual(result.readiness, .stale)
        XCTAssertTrue(result.staleReasons.contains(.planningInputChanged))
        XCTAssertNotEqual(
            result.inputFingerprint,
            manager.productStateShoppingPlan?.input.inputFingerprint
        )
    }

    func testExclusionSetChangeStalesPlanAndKeepsAccounting() {
        let initial = makeFixture(products: [1, 2])
        let derived = makeDerived(initial)
        let manager = AppStateManager()
        _ = publish(manager, initial, derived)
        let changed = makeFixture(
            products: [1, 2],
            explicitlyExcluded: [2]
        )
        let status = changed.boundary.planStatus(
            ProductStatePlanStatusRequest(
                plan: manager.productStateShoppingPlan!.plan,
                planInputFingerprint:
                    initial.input.declaredInputFingerprint,
                currentInput: changed.input
            )
        )

        let result = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .projection(changed.input),
            currentPlanStatus: status
        )
        XCTAssertEqual(result.readiness, .stale)
        XCTAssertTrue(result.staleReasons.contains(.includedEntriesChanged))
        XCTAssertTrue(result.staleReasons.contains(.planningInputChanged))
        XCTAssertEqual(result.explicitlyExcludedEntryIDs, [entryID(12)])
    }

    func testListIdentityAndRevisionAreBothRequiredForCurrentness() {
        let initial = makeFixture(products: [1, 2])
        let derived = makeDerived(initial)
        let manager = AppStateManager()
        _ = publish(manager, initial, derived)
        let changed = makeFixture(
            list: 101,
            revisionValue: 8,
            products: [1, 2]
        )
        let status = changed.boundary.planStatus(
            ProductStatePlanStatusRequest(
                plan: manager.productStateShoppingPlan!.plan,
                planInputFingerprint:
                    initial.input.declaredInputFingerprint,
                currentInput: changed.input
            )
        )

        let result = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .projection(changed.input),
            currentPlanStatus: status
        )
        XCTAssertEqual(result.readiness, .stale)
        XCTAssertTrue(result.staleReasons.contains(.sourceRevisionChanged))
        XCTAssertNotEqual(result.sourceListID, initial.input.listID)
    }

    func testUnrelatedLibraryOnlyChangeDoesNotCreateFalseStaleness() {
        let initial = makeFixture(products: [1, 2], extraProductRevision: 1)
        let derived = makeDerived(initial)
        let manager = AppStateManager()
        _ = publish(manager, initial, derived)
        let changed = makeFixture(products: [1, 2], extraProductRevision: 99)
        let status = changed.boundary.planStatus(
            ProductStatePlanStatusRequest(
                plan: manager.productStateShoppingPlan!.plan,
                planInputFingerprint:
                    initial.input.declaredInputFingerprint,
                currentInput: changed.input
            )
        )

        let result = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .projection(changed.input),
            currentPlanStatus: status
        )
        XCTAssertEqual(result.readiness, .currentReady)
        XCTAssertTrue(result.staleReasons.isEmpty)
        XCTAssertEqual(
            initial.repository.requestedProductIDs.sorted(),
            [uuid(1), uuid(2)]
        )
        XCTAssertEqual(
            changed.repository.requestedProductIDs.sorted(),
            [uuid(1), uuid(2)]
        )
    }

    func testUnavailableCurrentInputIsExplicitAndRetainsOwner() {
        let fixture = makeFixture(products: [1])
        let derived = makeDerived(fixture)
        let manager = AppStateManager()
        _ = publish(manager, fixture, derived)
        let unavailable = ProductStateProjectionMetadata(
            scope: .list(listID(100)),
            freshness: .unavailable(.repositoryReadFailed),
            listRevision: nil,
            sessionRevision: nil,
            sessionSnapshotID: nil,
            provenances: [],
            omissions: [],
            cachePolicy: .disabledDirectRebuild
        )

        let result = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .unavailable(unavailable),
            currentPlanStatus: nil
        )
        XCTAssertEqual(result.readiness, .unavailable)
        XCTAssertEqual(result.unavailableReason, .repositoryReadFailed)
        XCTAssertEqual(result.sourceListID, listID(100))
        XCTAssertNotNil(manager.productStateShoppingPlan)
    }

    func testIncompleteAccountingIsRejectedBeforePipelineUse() {
        let fixture = makeFixture(products: [1, 2])
        let input = ProductStatePlanInputProjection(
            listID: fixture.input.listID,
            revision: fixture.input.revision,
            eligibleEntries: fixture.input.eligibleEntries,
            exclusions: fixture.input.exclusions,
            allNeededEntryIDs: [entryID(11)],
            declaredInputFingerprint:
                fixture.input.declaredInputFingerprint,
            metadata: fixture.input.metadata
        )

        guard case let .failure(status) =
            ShoppingPlanConsumerBoundary.inputAuthority(input) else {
            return XCTFail("Expected incomplete accounting rejection")
        }
        XCTAssertEqual(status.readiness, .invalidOrIncomplete)
        XCTAssertTrue(
            status.invalidReasons.contains(
                .incompleteNeededEntryAccounting
            )
        )
    }

    func testStoreIntentsPreserveScopeExclusionsAndUncertainty() {
        let fixture = makeFixture(
            products: [1, 2, 3],
            explicitlyExcluded: [2]
        )
        let authority = unwrapAuthority(fixture.input)
        let classification = ShoppingIntentMatcher().classify(authority)
        let engine = StoreResolutionEngine(
            searchService: MapKitStoreSearchService()
        )
        let intents = engine.intents(
            for: authority,
            classification: classification
        )

        XCTAssertEqual(intents.count, 1)
        XCTAssertEqual(intents[0].sourceListID, listID(100))
        XCTAssertEqual(intents[0].sourceRevision, revision(7))
        XCTAssertEqual(
            intents[0].inputFingerprint,
            authority.inputFingerprint
        )
        XCTAssertEqual(intents[0].entryIDs, [entryID(11)])
        XCTAssertEqual(
            intents[0].explicitlyExcludedEntryIDs,
            [entryID(12)]
        )
        XCTAssertEqual(intents[0].unresolvedEntryIDs, [entryID(13)])
        XCTAssertEqual(
            intents[0].namedExclusions.map(\.reason),
            [.explicitUserExclusion]
        )
        XCTAssertEqual(
            intents[0].classificationUnresolvedEntryIDs,
            [entryID(13)]
        )
    }

    func testTripAndBuyingOptionsAreDeterministicEstimatedInputs() {
        let fixture = makeFixture(products: [1, 2])
        let authority = unwrapAuthority(fixture.input)
        let classification = ShoppingIntentMatcher().classify(authority)
        let engine = StoreResolutionEngine(
            searchService: MapKitStoreSearchService()
        )
        let intents = engine.intents(
            for: authority,
            classification: classification
        )
        let orderedStores = stores()
        let reversedStores = Array(orderedStores.reversed())
        let trip = ShoppingTripService()
        let firstCoverage = trip.coverage(
            for: authority,
            classification: classification,
            stores: orderedStores
        )
        let secondCoverage = trip.coverage(
            for: authority,
            classification: classification,
            stores: reversedStores
        )
        let buying = BuyingOptionsService()
        let firstOptions = buying.localOptions(
            for: authority,
            classification: classification,
            intents: intents,
            stores: orderedStores,
            userCoordinate: nil
        )
        let secondOptions = buying.localOptions(
            for: authority,
            classification: classification,
            intents: intents,
            stores: reversedStores,
            userCoordinate: nil
        )

        XCTAssertEqual(
            firstCoverage.map { "\($0.store.id.uuidString)|\($0.group.rawValue)" },
            secondCoverage.map { "\($0.store.id.uuidString)|\($0.group.rawValue)" }
        )
        XCTAssertEqual(
            firstOptions.map { "\($0.store.id.uuidString)|\($0.group.rawValue)" },
            secondOptions.map { "\($0.store.id.uuidString)|\($0.group.rawValue)" }
        )
        XCTAssertTrue(firstCoverage.allSatisfy {
            $0.availabilityClaim == .estimatedOnly
        })
        XCTAssertTrue(firstOptions.allSatisfy {
            $0.availabilityClaim == .estimatedOnly
        })
        XCTAssertEqual(
            Set(firstCoverage.flatMap(\.matchedEntryIDs)),
            Set(fixture.input.eligibleEntries.map(\.identity.id))
        )
    }

    func testExactShoppingContextDoesNotConsultCompletionFlag() {
        let exact = ShoppingContext(
            authority: .exactPlanInput,
            sourceListID: uuid(100),
            sourceListRevision: 7,
            inputFingerprint: "t14-safe",
            activeShoppingListItems: [
                ShoppingContextItem(
                    id: uuid(11),
                    name: "Snapshot",
                    isCompleted: true,
                    entryID: uuid(11),
                    productID: uuid(1),
                    quantity: 1
                )
            ],
            nearbyStores: [
                ShoppingContextStore(
                    id: uuid(801),
                    name: "Store",
                    matchingItemNames: ["Snapshot"]
                )
            ]
        )

        XCTAssertTrue(exact.hasActiveShoppingItems)
        let decision = DecisionEngine().evaluate(
            mission: .exploreNearby,
            context: exact
        )
        XCTAssertEqual(decision.outcome, .shoppingListItemsNearby)
        XCTAssertEqual(decision.relatedItemIDs, [uuid(11)])
        XCTAssertEqual(decision.relatedProductIDs, [uuid(1)])
        XCTAssertTrue(decision.message.contains("not verified"))
    }

    func testDiscoverConsumesExactContextAndRetainsDecisionIdentity() {
        let fixture = makeFixture(products: [1])
        let authority = unwrapAuthority(fixture.input)
        let context = ShoppingContext.exactPlanInput(
            authority,
            nearbyStores: [
                ShoppingContextStore(
                    id: uuid(801),
                    name: "Store",
                    matchingItemNames: ["Milk"]
                )
            ],
            observedAt: date(500)
        )
        let viewModel = DiscoverViewModel(
            context: context,
            decisionEngine: DecisionEngine()
        )

        XCTAssertEqual(
            viewModel.latestDecision?.sourceListID,
            uuid(100)
        )
        XCTAssertEqual(
            viewModel.latestDecision?.sourceListRevision,
            7
        )
        XCTAssertEqual(
            viewModel.latestDecision?.relatedProductIDs,
            [uuid(1)]
        )
        XCTAssertFalse(
            viewModel.items(for: .basedOnYourList).isEmpty
        )
    }

    func testMismatchedDiscoveryOwnerIsRejected() {
        let fixture = makeFixture(products: [1])
        let derived = makeDerived(fixture)
        let wrongDiscovery = ProductStateDiscoveryContextProjection(
            owner: .list(listID(100), revision(7)),
            eligibleProductIDs: derived.discovery.eligibleProductIDs,
            unresolvedItems: [],
            metadata: ProductStateProjectionMetadata(
                scope: .list(listID(100)),
                freshness: .current,
                listRevision: revision(7),
                sessionRevision: nil,
                sessionSnapshotID: nil,
                provenances: [.targetProductState],
                omissions: [],
                cachePolicy: .disabledDirectRebuild
            )
        )
        let manager = AppStateManager()

        let result = manager.publishProductStateShoppingPlan(
            input: fixture.input,
            planStatus: derived.status,
            stores: stores(),
            discoveryContext: wrongDiscovery,
            storeRecommendations: derived.recommendations,
            generatedAt: date(500)
        )
        XCTAssertEqual(result.readiness, .invalidOrIncomplete)
        XCTAssertEqual(
            result.invalidReasons,
            [.mismatchedDerivedProjection]
        )
        XCTAssertNil(manager.productStateShoppingPlan)
    }

    func testPlanStatusMustMatchEntriesAndExclusionsNotOnlyListUUID() {
        let fixture = makeFixture(products: [1, 2])
        let derived = makeDerived(fixture)
        let badStatus = ProductStatePlanStatusProjection(
            planID: derived.status.planID,
            sourceListID: fixture.input.listID,
            sourceRevision: fixture.input.revision,
            includedEntryIDs: [entryID(11)],
            excludedEntryIDs: [entryID(12)],
            status: .ready,
            staleReasons: [],
            metadata: derived.status.metadata
        )

        guard case let .failure(status) =
            ShoppingPlanConsumerBoundary.makePlan(
                input: fixture.input,
                planStatus: badStatus,
                generatedAt: date(500)
            ) else {
            return XCTFail("Expected exact status mismatch")
        }
        XCTAssertEqual(status.readiness, .invalidOrIncomplete)
        XCTAssertEqual(status.invalidReasons, [.mismatchedPlanStatus])

        let manager = AppStateManager()
        _ = publish(manager, fixture, derived)
        let refreshed = manager.refreshProductStateShoppingPlanStatus(
            currentInput: .projection(fixture.input),
            currentPlanStatus: badStatus
        )
        XCTAssertEqual(refreshed.readiness, .invalidOrIncomplete)
        XCTAssertEqual(
            refreshed.invalidReasons,
            [.mismatchedPlanStatus]
        )
    }

    func testFingerprintIsDeterministicPrivateAndDependencySensitive() {
        let initial = makeFixture(products: [1, 2])
        let same = makeFixture(products: [1, 2])
        let quantity = makeFixture(
            products: [1, 2],
            quantities: [1: 2]
        )
        let excluded = makeFixture(
            products: [1, 2],
            explicitlyExcluded: [2]
        )
        let first = ShoppingPlanConsumerBoundary.fingerprint(initial.input)

        XCTAssertEqual(
            first,
            ShoppingPlanConsumerBoundary.fingerprint(same.input)
        )
        XCTAssertNotEqual(
            first,
            ShoppingPlanConsumerBoundary.fingerprint(quantity.input)
        )
        XCTAssertNotEqual(
            first,
            ShoppingPlanConsumerBoundary.fingerprint(excluded.input)
        )
        XCTAssertFalse(first.contains("Milk"))
        XCTAssertFalse(first.contains("USB"))
        XCTAssertTrue(first.hasPrefix("t14-"))
    }

    func testFingerprintPerformanceQualification() {
        let fixture = makeFixture(products: [1, 2, 4])
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1_000 {
                _ = ShoppingPlanConsumerBoundary.fingerprint(fixture.input)
            }
        }
    }
}

// MARK: - Exact T-13 fixture pipeline

@MainActor
private struct T14Fixture {
    let repository: T14Repository
    let boundary: ProductStateQueryBoundary
    let input: ProductStatePlanInputProjection
}

@MainActor
private struct T14Derived {
    let status: ProductStatePlanStatusProjection
    let discovery: ProductStateDiscoveryContextProjection
    let recommendations: ProductStateStoreRecommendationsProjection

    var owner: ProductStateShoppingContextOwner {
        discovery.owner
    }
}

@MainActor
private func makeFixture(
    list listValue: Int = 100,
    revisionValue: UInt64 = 7,
    products productValues: [Int],
    quantities: [Int: Double] = [:],
    explicitlyExcluded: Set<Int> = [],
    omittedProducts: Set<Int> = [],
    extraProductRevision: UInt64 = 1
) -> T14Fixture {
    let targetProducts = productValues.compactMap { value in
        omittedProducts.contains(value) ? nil : product(value)
    }
    let extra = product(999, revisionValue: extraProductRevision)
    let repository = T14Repository(
        products: targetProducts + [extra],
        lists: [list(listValue, revisionValue)],
        entries: productValues.map {
            entry(
                10 + $0,
                list: listValue,
                product: $0,
                quantity: quantities[$0] ?? 1,
                order: Double($0)
            )
        }
    )
    let boundary = ProductStateQueryBoundary(
        products: repository,
        shopping: repository,
        sessions: repository
    )
    let result = boundary.planInput(
        ProductStatePlanInputRequest(
            listScope: ProductStateListScopeRequest(
                listID: listID(listValue),
                expectedRevision: revision(revisionValue)
            ),
            declaredInputFingerprint: "catalog-v1|store-evidence-v1",
            explicitlyExcludedEntryIDs: Set(
                explicitlyExcluded.map { entryID(10 + $0) }
            )
        )
    )
    guard case let .projection(input) = result else {
        fatalError("T-14 fixture must produce an exact T-13 Plan Input")
    }
    return T14Fixture(
        repository: repository,
        boundary: boundary,
        input: input
    )
}

@MainActor
private func makeDerived(_ fixture: T14Fixture) -> T14Derived {
    let input = fixture.input
    let plan = ProductStateShoppingPlan(
        id: planID(900),
        sourceListID: input.listID,
        sourceRevision: input.revision,
        includedEntries: input.eligibleEntries.map(\.identity),
        exclusions: input.exclusions.map {
            ShoppingPlanExclusion(
                entry: $0.entry.identity,
                reason: $0.reason == .explicitUserExclusion
                    ? .userExcluded : .invalidProduct
            )
        },
        status: .ready
    )
    let status = fixture.boundary.planStatus(
        ProductStatePlanStatusRequest(
            plan: plan,
            planInputFingerprint: input.declaredInputFingerprint,
            currentInput: input
        )
    )
    let map = fixture.boundary.mapContext(
        planInput: input,
        status: status
    )
    let discovery = fixture.boundary.discoveryContext(map)
    let recommendations = fixture.boundary.storeRecommendations(
        context: discovery,
        evidence: [
            ProductStatePublishedStoreEvidence(
                storeID: uuid(801).uuidString,
                coveredProductIDs: Set(discovery.eligibleProductIDs),
                confidence: 0.75,
                evidenceAt: date(400),
                publicationVersion: "store-evidence-v1"
            )
        ]
    )
    return T14Derived(
        status: status,
        discovery: discovery,
        recommendations: recommendations
    )
}

@MainActor
private func publish(
    _ manager: AppStateManager,
    _ fixture: T14Fixture,
    _ derived: T14Derived
) -> ShoppingPlanConsumerStatus {
    manager.publishProductStateShoppingPlan(
        input: fixture.input,
        planStatus: derived.status,
        stores: stores(),
        discoveryContext: derived.discovery,
        storeRecommendations: derived.recommendations,
        generatedAt: date(500)
    )
}

@MainActor
private func unwrapAuthority(
    _ input: ProductStatePlanInputProjection
) -> ShoppingPlanInputAuthority {
    guard case let .success(authority) =
        ShoppingPlanConsumerBoundary.inputAuthority(input) else {
        fatalError("Expected valid T-14 input authority")
    }
    return authority
}

@MainActor
private final class T14Repository:
    ProductRepository, ShoppingRepository, ShoppingSessionRepository {
    let products: [WayTaskSchemaV4.Product]
    let lists: [WayTaskSchemaV4.ShoppingList]
    let entries: [WayTaskSchemaV4.ShoppingListEntry]
    private(set) var mutationCallCount = 0
    private(set) var requestedProductIDs: [UUID] = []

    init(
        products: [WayTaskSchemaV4.Product],
        lists: [WayTaskSchemaV4.ShoppingList],
        entries: [WayTaskSchemaV4.ShoppingListEntry]
    ) {
        self.products = products
        self.lists = lists
        self.entries = entries
    }

    func products(id: UUID) throws -> [WayTaskSchemaV4.Product] {
        requestedProductIDs.append(id)
        return products.filter { $0.id == id }
    }

    func products(
        catalogProductIDRawValue: String
    ) throws -> [WayTaskSchemaV4.Product] {
        products.filter {
            $0.catalogProductIDRawValue == catalogProductIDRawValue
        }
    }

    func products(barcode: String) throws -> [WayTaskSchemaV4.Product] {
        products.filter { $0.barcode == barcode }
    }

    func products(
        libraryLifecycle: ProductLibraryLifecycle
    ) throws -> [WayTaskSchemaV4.Product] {
        products.filter {
            $0.libraryLifecycleRawValue == libraryLifecycle.rawValue
        }
    }

    func stageInsertion(of product: WayTaskSchemaV4.Product) {
        mutationCallCount += 1
    }

    func shoppingLists(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingList] {
        lists.filter { $0.id == id }
    }

    func shoppingEntries(
        id: UUID,
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        entries.filter { $0.id == id && $0.shoppingListID == listID }
    }

    func shoppingEntries(
        listID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        entries.filter { $0.shoppingListID == listID }
    }

    func shoppingEntries(
        listID: UUID,
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        entries.filter {
            $0.shoppingListID == listID && $0.productID == productID
        }
    }

    func shoppingEntries(
        productID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingListEntry] {
        entries.filter { $0.productID == productID }
    }

    func stageInsertion(of list: WayTaskSchemaV4.ShoppingList) {
        mutationCallCount += 1
    }

    func stageInsertion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        mutationCallCount += 1
    }

    func stageDeletion(of list: WayTaskSchemaV4.ShoppingList) {
        mutationCallCount += 1
    }

    func stageDeletion(of entry: WayTaskSchemaV4.ShoppingListEntry) {
        mutationCallCount += 1
    }

    func shoppingSessions(
        id: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSession] { [] }

    func shoppingSessions(
        lifecycle: ShoppingSessionLifecycle
    ) throws -> [WayTaskSchemaV4.ShoppingSession] { [] }

    func sessionLines(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionLine] { [] }

    func sessionStops(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ShoppingSessionStop] { [] }

    func migrationExceptions(
        sessionID: UUID
    ) throws -> [WayTaskSchemaV4.ProductStateMigrationException] { [] }

    func stageInsertion(of session: WayTaskSchemaV4.ShoppingSession) {
        mutationCallCount += 1
    }
}

@MainActor
private func product(
    _ value: Int,
    revisionValue: UInt64 = 1
) -> WayTaskSchemaV4.Product {
    let values: (String, String?, String?)
    switch value {
    case 1: values = ("Milk", "Dairy", "dairy")
    case 2: values = ("USB Cable", "Electronics", "electronics")
    case 3: values = ("Obscure Artifact", nil, nil)
    case 4: values = ("Bread", "Bakery", "bakery")
    default: values = ("Unrelated Product", "Other", "general")
    }
    return WayTaskSchemaV4.Product(
        id: uuid(value),
        revision: revisionValue,
        libraryLifecycleRawValue: ProductLibraryLifecycle.active.rawValue,
        name: values.0,
        brand: nil,
        category: values.1,
        sourceRawValue: "manual",
        catalogProductIDRawValue: values.2.map { "catalog-\($0)" },
        catalogDisplayNameSnapshot: values.0,
        catalogDisplayLocaleSnapshot: "en",
        catalogCategoryIDSnapshotRawValue: values.2,
        catalogCategoryDisplayNameSnapshot: values.1,
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

@MainActor
private func list(
    _ value: Int,
    _ revisionValue: UInt64
) -> WayTaskSchemaV4.ShoppingList {
    WayTaskSchemaV4.ShoppingList(
        id: uuid(value),
        revision: revisionValue,
        title: "Exact List",
        purposeRawValue: "named",
        createdAt: date(1),
        updatedAt: date(2)
    )
}

@MainActor
private func entry(
    _ value: Int,
    list: Int,
    product: Int,
    quantity: Double,
    order: Double
) -> WayTaskSchemaV4.ShoppingListEntry {
    WayTaskSchemaV4.ShoppingListEntry(
        id: uuid(value),
        shoppingListID: uuid(list),
        productID: uuid(product),
        lifecycleRawValue: "needed",
        quantity: quantity,
        unitRawValue: "unit",
        sortOrder: order,
        createdAt: date(value),
        updatedAt: date(value + 1)
    )
}

private func stores() -> [MapStore] {
    [
        MapStore(
            id: uuid(801),
            locationID: nil,
            title: "Grocery Store",
            coordinate: CLLocationCoordinate2D(
                latitude: 31.5,
                longitude: 35.1
            ),
            radius: 180,
            itemNames: ["Milk", "Bread"],
            completedItemNames: [],
            isOpen: true,
            rating: 4.5,
            storeCategories: [.grocery],
            queryEvidenceCategories: [.grocery],
            websiteURL: nil,
            sourceType: .local
        ),
        MapStore(
            id: uuid(802),
            locationID: nil,
            title: "Electronics Store",
            coordinate: CLLocationCoordinate2D(
                latitude: 31.6,
                longitude: 35.2
            ),
            radius: 180,
            itemNames: ["USB Cable"],
            completedItemNames: [],
            isOpen: true,
            rating: 4.5,
            storeCategories: [.electronicsStore],
            queryEvidenceCategories: [.electronicsStore],
            websiteURL: nil,
            sourceType: .local
        )
    ]
}

private func entryLess(
    _ lhs: ProductStateListEntryID,
    _ rhs: ProductStateListEntryID
) -> Bool {
    lhs.rawValue.uuidString < rhs.rawValue.uuidString
}

private func uuid(_ value: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        )
    )!
}

private func date(_ value: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(value))
}

private func productID(_ value: Int) -> ProductStateProductID {
    ProductStateProductID(rawValue: uuid(value))
}

private func listID(_ value: Int) -> ProductStateListID {
    ProductStateListID(rawValue: uuid(value))
}

private func entryID(_ value: Int) -> ProductStateListEntryID {
    ProductStateListEntryID(rawValue: uuid(value))
}

private func planID(_ value: Int) -> ProductStatePlanID {
    ProductStatePlanID(rawValue: uuid(value))
}

private func revision(_ value: UInt64) -> ProductStateListRevision {
    ProductStateListRevision(value: value)
}
