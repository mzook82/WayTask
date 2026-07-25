import Combine
import CoreGraphics
import Foundation

enum FeatureTourTargetResolutionState: Equatable {
    case unavailable
    case resolving
    case highlighted
}

struct FeatureTourPresentationState: Equatable {
    let stepID: FeatureTourStepID?
    let targetResolutionState: FeatureTourTargetResolutionState
    let targetFrame: CGRect?

    var showsTooltip: Bool {
        stepID != nil
    }

    var showsHighlight: Bool {
        targetResolutionState == .highlighted && targetFrame != nil
    }
}

@MainActor
final class FeatureTourCoordinator: ObservableObject {
    @Published private(set) var isPresented: Bool
    @Published private(set) var currentStepIndex: Int
    @Published private(set) var isShowingCompletion: Bool
    @Published private(set) var targetResolutionState:
        FeatureTourTargetResolutionState
    @Published private(set) var resolvedTargetFrame: CGRect?

    let steps: [FeatureTourStep]

    private let completionStore: any FeatureTourCompletionStoring
    private var targetResolutionTask: Task<Void, Never>?

    init(
        completionStore: any FeatureTourCompletionStoring,
        steps: [FeatureTourStep],
        presentOnLaunch: Bool = false
    ) {
        precondition(!steps.isEmpty, "A feature tour requires at least one step.")
        self.completionStore = completionStore
        self.steps = steps
        currentStepIndex = 0
        isShowingCompletion = false
        targetResolutionState = .unavailable
        resolvedTargetFrame = nil
        isPresented = presentOnLaunch && !completionStore.hasCompletedFeatureTour
    }

    convenience init(
        completionStore: any FeatureTourCompletionStoring,
        presentOnLaunch: Bool = false
    ) {
        self.init(
            completionStore: completionStore,
            steps: FeatureTourStep.wayTaskSteps,
            presentOnLaunch: presentOnLaunch
        )
    }

    convenience init(presentOnLaunch: Bool = false) {
        self.init(
            completionStore: UserDefaultsFeatureTourCompletionStore(),
            presentOnLaunch: presentOnLaunch
        )
    }

    var currentStep: FeatureTourStep? {
        guard isPresented,
              !isShowingCompletion,
              steps.indices.contains(currentStepIndex) else {
            return nil
        }

        return steps[currentStepIndex]
    }

    var hasCompletedFeatureTour: Bool {
        completionStore.hasCompletedFeatureTour
    }

    var navigationDestination: AppTab? {
        currentStep?.destinationTab
    }

    var presentationState: FeatureTourPresentationState {
        FeatureTourPresentationState(
            stepID: currentStep?.id,
            targetResolutionState: targetResolutionState,
            targetFrame: resolvedTargetFrame
        )
    }

    var isFirstStep: Bool {
        currentStepIndex == steps.startIndex
    }

    var isLastStep: Bool {
        currentStepIndex == steps.index(before: steps.endIndex)
    }

    func start() {
        resetTargetResolution()
        currentStepIndex = 0
        isShowingCompletion = false
        isPresented = true
    }

    func replay() {
        start()
    }

    func next() {
        guard isPresented else {
            return
        }

        if isLastStep {
            resetTargetResolution()
            isShowingCompletion = true
        } else {
            resetTargetResolution()
            currentStepIndex += 1
        }
    }

    func back() {
        guard isPresented,
              !isShowingCompletion,
              !isFirstStep else {
            return
        }

        resetTargetResolution()
        currentStepIndex -= 1
    }

    func skip() {
        resetTargetResolution()
        completionStore.markFeatureTourCompleted()
        isShowingCompletion = false
        isPresented = false
    }

    func complete() {
        resetTargetResolution()
        completionStore.markFeatureTourCompleted()
        isShowingCompletion = false
        isPresented = false
    }

    func updateTargetCandidate(
        _ frame: CGRect?,
        for stepID: FeatureTourStepID,
        targetID: FeatureTourTargetID,
        stabilizationDelay: Duration = .milliseconds(180)
    ) {
        targetResolutionTask?.cancel()
        targetResolutionTask = nil
        resolvedTargetFrame = nil

        guard currentStep?.id == stepID,
              currentStep?.target == targetID,
              let frame else {
            targetResolutionState = .unavailable
            return
        }

        targetResolutionState = .resolving
        targetResolutionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: stabilizationDelay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.currentStep?.id == stepID,
                  self.currentStep?.target == targetID else {
                return
            }

            self.resolvedTargetFrame = frame
            self.targetResolutionState = .highlighted
            self.targetResolutionTask = nil
        }
    }

    private func resetTargetResolution() {
        targetResolutionTask?.cancel()
        targetResolutionTask = nil
        resolvedTargetFrame = nil
        targetResolutionState = .unavailable
    }
}
