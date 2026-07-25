import XCTest
@testable import WayTask

@MainActor
final class FeatureTourFoundationTests: XCTestCase {
    func testTooltipPlacementStaysInsideSafeAreaBounds() {
        let placement = FeatureTourPlacementSolver.placement(
            in: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaInsets: FeatureTourSafeAreaInsets(
                top: 59,
                leading: 0,
                bottom: 34,
                trailing: 0
            ),
            targetFrame: CGRect(
                x: 160,
                y: 700,
                width: 70,
                height: 50
            ),
            tooltipSize: CGSize(width: 350, height: 260)
        )

        XCTAssertGreaterThanOrEqual(
            placement.frame.minX,
            placement.safeBounds.minX
        )
        XCTAssertGreaterThanOrEqual(
            placement.frame.minY,
            placement.safeBounds.minY
        )
        XCTAssertLessThanOrEqual(
            placement.frame.maxX,
            placement.safeBounds.maxX
        )
        XCTAssertLessThanOrEqual(
            placement.frame.maxY,
            placement.safeBounds.maxY
        )
    }

    func testTooltipChoosesAboveOrBelowUsingAvailableSpace() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let insets = FeatureTourSafeAreaInsets(
            top: 59,
            leading: 0,
            bottom: 34,
            trailing: 0
        )
        let tooltipSize = CGSize(width: 350, height: 240)

        let belowPlacement = FeatureTourPlacementSolver.placement(
            in: bounds,
            safeAreaInsets: insets,
            targetFrame: CGRect(
                x: 24,
                y: 110,
                width: 342,
                height: 52
            ),
            tooltipSize: tooltipSize
        )
        let abovePlacement = FeatureTourPlacementSolver.placement(
            in: bounds,
            safeAreaInsets: insets,
            targetFrame: CGRect(
                x: 160,
                y: 700,
                width: 70,
                height: 50
            ),
            tooltipSize: tooltipSize
        )

        XCTAssertEqual(belowPlacement.kind, .below)
        XCTAssertEqual(abovePlacement.kind, .above)
    }

    func testMissingTargetUsesCenteredSafePlacement() {
        let placement = FeatureTourPlacementSolver.placement(
            in: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaInsets: FeatureTourSafeAreaInsets(
                top: 59,
                leading: 0,
                bottom: 34,
                trailing: 0
            ),
            targetFrame: nil,
            tooltipSize: CGSize(width: 350, height: 300)
        )

        XCTAssertEqual(placement.kind, .centered)
        XCTAssertEqual(
            placement.frame.midX,
            placement.safeBounds.midX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            placement.frame.midY,
            placement.safeBounds.midY,
            accuracy: 0.001
        )
    }

    func testTooltipNeverOverlapsAcceptedTarget() {
        let target = CGRect(
            x: 145,
            y: 380,
            width: 100,
            height: 84
        )
        let placement = FeatureTourPlacementSolver.placement(
            in: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaInsets: FeatureTourSafeAreaInsets(
                top: 59,
                leading: 0,
                bottom: 34,
                trailing: 0
            ),
            targetFrame: target,
            tooltipSize: CGSize(width: 350, height: 500)
        )

        XCTAssertTrue(placement.frame.intersection(target).isNull)
        XCTAssertNotEqual(placement.kind, .centered)
    }

    func testTourCompletionPersistsSeparately() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )

        coordinator.start()
        coordinator.complete()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(context.store.hasCompletedFeatureTour)
        XCTAssertNotEqual(
            UserDefaultsFeatureTourCompletionStore.completionKey,
            UserDefaultsOnboardingCompletionStore.completionKey
        )
        XCTAssertFalse(
            context.userDefaults.bool(
                forKey: UserDefaultsOnboardingCompletionStore.completionKey
            )
        )

        let nextLaunchCoordinator = FeatureTourCoordinator(
            completionStore: context.store,
            presentOnLaunch: true
        )
        XCTAssertFalse(nextLaunchCoordinator.isPresented)
    }

    func testSkipMarksTourCompleteAndDismissesIt() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()
        coordinator.next()

        coordinator.skip()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(context.store.hasCompletedFeatureTour)
    }

    func testReplayStartsAtFirstStepWithoutResettingCompletion() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()
        coordinator.complete()
        XCTAssertTrue(context.store.hasCompletedFeatureTour)

        coordinator.replay()

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.currentStepIndex, 0)
        XCTAssertEqual(coordinator.currentStep?.id, .productsAdd)
        XCTAssertTrue(context.store.hasCompletedFeatureTour)
    }

    func testSettingsReplayPresentsStepOneAfterRoutingToProducts() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        var selectedTab = AppTab.settings

        coordinator.replay()
        selectedTab = coordinator.navigationDestination ?? selectedTab

        XCTAssertEqual(selectedTab, .products)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.currentStep?.id, .productsAdd)
        XCTAssertTrue(coordinator.presentationState.showsTooltip)
        XCTAssertFalse(coordinator.presentationState.showsHighlight)
    }

    func testPostOnboardingStartPresentsStepOne() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let onboardingCoordinator = OnboardingCoordinator(
            completionStore: UserDefaultsOnboardingCompletionStore(
                userDefaults: context.userDefaults
            )
        )
        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )

        // This is the production completion order: make the shared tour
        // coordinator active before replacing onboarding with ContentView.
        coordinator.start()
        onboardingCoordinator.complete()
        var selectedTab = AppTab.home
        selectedTab = coordinator.navigationDestination ?? selectedTab

        XCTAssertFalse(onboardingCoordinator.isPresented)
        XCTAssertTrue(onboardingCoordinator.hasCompletedOnboarding)
        XCTAssertEqual(selectedTab, .products)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.currentStep?.id, .productsAdd)
        XCTAssertTrue(coordinator.presentationState.showsTooltip)
        XCTAssertFalse(context.store.hasCompletedFeatureTour)
    }

    func testMissingInitialAnchorStillPresentsTooltip() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()

        coordinator.updateTargetCandidate(
            nil,
            for: .productsAdd,
            targetID: .productsBottomAddButton
        )

        XCTAssertEqual(
            coordinator.targetResolutionState,
            .unavailable
        )
        XCTAssertTrue(coordinator.presentationState.showsTooltip)
        XCTAssertFalse(coordinator.presentationState.showsHighlight)
        XCTAssertNil(coordinator.resolvedTargetFrame)
    }

    func testDelayedAnchorUpgradesFallbackToHighlight() async throws {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        let targetFrame = CGRect(
            x: 18,
            y: 730,
            width: 108,
            height: 44
        )
        coordinator.start()

        coordinator.updateTargetCandidate(
            targetFrame,
            for: .productsAdd,
            targetID: .productsBottomAddButton,
            stabilizationDelay: .milliseconds(5)
        )

        XCTAssertEqual(coordinator.targetResolutionState, .resolving)
        XCTAssertTrue(coordinator.presentationState.showsTooltip)
        XCTAssertFalse(coordinator.presentationState.showsHighlight)

        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(coordinator.targetResolutionState, .highlighted)
        XCTAssertEqual(coordinator.resolvedTargetFrame, targetFrame)
        XCTAssertTrue(coordinator.presentationState.showsTooltip)
        XCTAssertTrue(coordinator.presentationState.showsHighlight)
    }

    func testTabChangesDoNotDismissPresentedTour() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()

        var selectedTab = coordinator.navigationDestination ?? .home
        selectedTab = .map
        selectedTab = coordinator.navigationDestination ?? selectedTab

        XCTAssertEqual(selectedTab, .products)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.currentStep?.id, .productsAdd)
        XCTAssertFalse(context.store.hasCompletedFeatureTour)
    }

    func testRoutingAndTargetResolutionDoNotCompleteTour() async throws {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.replay()
        _ = coordinator.navigationDestination
        coordinator.updateTargetCandidate(
            CGRect(x: 18, y: 730, width: 108, height: 44),
            for: .productsAdd,
            targetID: .productsBottomAddButton,
            stabilizationDelay: .milliseconds(5)
        )
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertFalse(coordinator.isShowingCompletion)
        XCTAssertFalse(context.store.hasCompletedFeatureTour)

        coordinator.skip()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(context.store.hasCompletedFeatureTour)
    }

    func testStepOrderingMatchesApprovedInitialTour() {
        XCTAssertEqual(
            FeatureTourStep.wayTaskSteps.map(\.id),
            [
                .productsAdd,
                .productAutocomplete,
                .cameraCapture,
                .mapFollowUser,
                .storeNavigation,
                .storesWorkspace,
                .settingsReplay
            ]
        )
    }

    func testEveryStepDeclaresItsAutomaticTabNavigation() {
        XCTAssertEqual(
            FeatureTourStep.wayTaskSteps.map(\.destinationTab),
            [
                .products,
                .products,
                .home,
                .map,
                .map,
                .shopping,
                .settings
            ]
        )
    }

    func testTargetChangesWithNavigationAndPresentationSteps() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()

        XCTAssertEqual(
            coordinator.currentStep?.target,
            .productsBottomAddButton
        )
        XCTAssertEqual(
            coordinator.currentStep?.destinationTab,
            .products
        )

        coordinator.next()
        XCTAssertEqual(
            coordinator.currentStep?.target,
            .addProductNameField
        )
        XCTAssertEqual(
            coordinator.currentStep?.surface,
            .productEntry
        )

        coordinator.next()
        XCTAssertEqual(
            coordinator.currentStep?.target,
            .cameraShutterButton
        )
        XCTAssertEqual(
            coordinator.currentStep?.destinationTab,
            .home
        )
    }

    func testNavigateMissingTargetHasNoFallbackRectangle() throws {
        let storeStep = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .storeNavigation
            }
        )

        XCTAssertEqual(
            FeatureTourTargetResolver.target(
                for: storeStep,
                availableTargets: []
            ),
            nil
        )
        XCTAssertEqual(
            storeStep.missingTargetMessage,
            "Navigation appears after selecting a store."
        )

        let validation = FeatureTourTargetFrameValidator.validate(
            frame: nil,
            observedTarget: nil,
            expectedTarget: .mapNavigateButton,
            overlayBounds: CGRect(
                x: 0,
                y: 0,
                width: 390,
                height: 844
            ),
            safeAreaInsets: testSafeAreaInsets
        )

        XCTAssertNil(validation.frame)
        XCTAssertEqual(validation.rejection, .missing)
    }

    func testEveryStepUsesOneUniqueSemanticTarget() {
        let targets = FeatureTourStep.wayTaskSteps.map(\.target)

        XCTAssertEqual(targets.count, 7)
        XCTAssertEqual(Set(targets).count, targets.count)
    }

    func testAddStepSelectsProductsBottomActionButton() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .productsAdd
            }
        )

        XCTAssertEqual(step.target, .productsBottomAddButton)
        XCTAssertAccepted(
            frame: CGRect(x: 18, y: 730, width: 108, height: 44),
            target: step.target
        )
        XCTAssertRejected(
            frame: CGRect(x: 20, y: 420, width: 350, height: 160),
            target: step.target,
            as: .tooLarge
        )
    }

    func testSearchStepSelectsOnlyAddProductNameField() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .productAutocomplete
            }
        )

        XCTAssertEqual(step.target, .addProductNameField)
        XCTAssertAccepted(
            frame: CGRect(x: 80, y: 180, width: 290, height: 50),
            target: step.target
        )
    }

    func testCaptureTargetUsesCircularShutterFrame() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .cameraCapture
            }
        )

        XCTAssertEqual(step.target, .cameraShutterButton)
        XCTAssertAccepted(
            frame: CGRect(x: 160, y: 680, width: 70, height: 70),
            target: step.target
        )
        XCTAssertRejected(
            frame: CGRect(x: 30, y: 590, width: 330, height: 150),
            target: step.target,
            as: .tooLarge
        )
        XCTAssertEqual(
            step.target.highlightCornerRadius(
                for: CGRect(x: 0, y: 0, width: 78, height: 78)
            ),
            39
        )
    }

    func testFollowLocationTargetUsesOnlyMapControl() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .mapFollowUser
            }
        )

        XCTAssertEqual(step.target, .mapFollowLocationButton)
        XCTAssertAccepted(
            frame: CGRect(x: 314, y: 650, width: 50, height: 50),
            target: step.target
        )
    }

    func testRecommendedStoresTargetsUsableCardOutsideStatusBar() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .storesWorkspace
            }
        )

        XCTAssertEqual(step.target, .shoppingRecommendedStoreCard)
        XCTAssertAccepted(
            frame: CGRect(x: 20, y: 210, width: 350, height: 260),
            target: step.target
        )
        XCTAssertRejected(
            frame: CGRect(x: 20, y: 20, width: 350, height: 120),
            target: step.target,
            as: .outsideVisibleBounds
        )
        XCTAssertRejected(
            frame: CGRect(x: 0, y: 70, width: 390, height: 650),
            target: step.target,
            as: .tooLarge
        )
    }

    func testSettingsTargetEqualsVisibleFeatureTourRow() throws {
        let step = try XCTUnwrap(
            FeatureTourStep.wayTaskSteps.first {
                $0.id == .settingsReplay
            }
        )

        XCTAssertEqual(step.target, .settingsFeatureTourRow)
        XCTAssertAccepted(
            frame: CGRect(x: 20, y: 380, width: 350, height: 48),
            target: step.target
        )
    }

    func testStaleAndOversizedAnchorsAreRejected() {
        let stale = FeatureTourTargetFrameValidator.validate(
            frame: CGRect(x: 18, y: 730, width: 108, height: 44),
            observedTarget: .mapNavigateButton,
            expectedTarget: .productsBottomAddButton,
            overlayBounds: testOverlayBounds,
            safeAreaInsets: testSafeAreaInsets
        )
        let oversized = FeatureTourTargetFrameValidator.validate(
            frame: CGRect(x: 10, y: 100, width: 370, height: 500),
            observedTarget: .productsBottomAddButton,
            expectedTarget: .productsBottomAddButton,
            overlayBounds: testOverlayBounds,
            safeAreaInsets: testSafeAreaInsets
        )

        XCTAssertNil(stale.frame)
        XCTAssertEqual(stale.rejection, .staleTarget)
        XCTAssertNil(oversized.frame)
        XCTAssertEqual(oversized.rejection, .tooLarge)
    }

    func testCoordinateConversionAcrossSheetAndScrolledRoots() {
        let sheetGlobalBounds = CGRect(
            x: 0,
            y: 96,
            width: 390,
            height: 748
        )
        let sheetLocalField = CGRect(
            x: 20,
            y: 112,
            width: 350,
            height: 50
        )
        let globalField = FeatureTourCoordinateConverter.globalFrame(
            fromOverlayFrame: sheetLocalField,
            overlayGlobalBounds: sheetGlobalBounds
        )

        XCTAssertEqual(
            globalField,
            CGRect(x: 20, y: 208, width: 350, height: 50)
        )
        XCTAssertEqual(
            FeatureTourCoordinateConverter.overlayFrame(
                fromGlobalFrame: globalField,
                overlayGlobalBounds: sheetGlobalBounds
            ),
            sheetLocalField
        )

        let scrolledCardGlobal = CGRect(
            x: 20,
            y: 250,
            width: 350,
            height: 260
        )
        XCTAssertEqual(
            FeatureTourCoordinateConverter.overlayFrame(
                fromGlobalFrame: scrolledCardGlobal,
                overlayGlobalBounds: CGRect(
                    x: 0,
                    y: 59,
                    width: 390,
                    height: 751
                )
            ),
            CGRect(x: 20, y: 191, width: 350, height: 260)
        )
    }

    func testLastStepOpensCompletionScreenBeforePersisting() {
        let context = makeStoreContext()
        defer { context.userDefaults.removePersistentDomain(forName: context.suiteName) }

        let coordinator = FeatureTourCoordinator(
            completionStore: context.store
        )
        coordinator.start()

        for _ in 1..<coordinator.steps.count {
            coordinator.next()
        }

        XCTAssertTrue(coordinator.isLastStep)
        coordinator.next()

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertTrue(coordinator.isShowingCompletion)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(context.store.hasCompletedFeatureTour)
        XCTAssertEqual(
            FeatureTourCompletionCopy.title,
            "You’re all set!"
        )
        XCTAssertEqual(
            FeatureTourCompletionCopy.message,
            "You can replay this tour anytime from Settings."
        )
        XCTAssertEqual(
            FeatureTourCompletionCopy.action,
            "Start Using WayTask"
        )

        coordinator.complete()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertFalse(coordinator.isShowingCompletion)
        XCTAssertTrue(context.store.hasCompletedFeatureTour)
    }

    private func makeStoreContext() -> (
        store: UserDefaultsFeatureTourCompletionStore,
        userDefaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "FeatureTourFoundationTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        return (
            UserDefaultsFeatureTourCompletionStore(
                userDefaults: userDefaults
            ),
            userDefaults,
            suiteName
        )
    }

    private var testOverlayBounds: CGRect {
        CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    private var testSafeAreaInsets: FeatureTourSafeAreaInsets {
        FeatureTourSafeAreaInsets(
            top: 59,
            leading: 0,
            bottom: 34,
            trailing: 0
        )
    }

    private func XCTAssertAccepted(
        frame: CGRect,
        target: FeatureTourTargetID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let validation = FeatureTourTargetFrameValidator.validate(
            frame: frame,
            observedTarget: target,
            expectedTarget: target,
            overlayBounds: testOverlayBounds,
            safeAreaInsets: testSafeAreaInsets
        )

        XCTAssertEqual(validation.frame, frame, file: file, line: line)
        XCTAssertNil(validation.rejection, file: file, line: line)
    }

    private func XCTAssertRejected(
        frame: CGRect,
        target: FeatureTourTargetID,
        as expectedRejection: FeatureTourTargetFrameRejection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let validation = FeatureTourTargetFrameValidator.validate(
            frame: frame,
            observedTarget: target,
            expectedTarget: target,
            overlayBounds: testOverlayBounds,
            safeAreaInsets: testSafeAreaInsets
        )

        XCTAssertNil(validation.frame, file: file, line: line)
        XCTAssertEqual(
            validation.rejection,
            expectedRejection,
            file: file,
            line: line
        )
    }
}
