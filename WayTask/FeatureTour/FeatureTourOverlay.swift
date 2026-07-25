import SwiftUI

private struct FeatureTourTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [FeatureTourTargetID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [FeatureTourTargetID: Anchor<CGRect>],
        nextValue: () -> [FeatureTourTargetID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

private struct FeatureTourTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextSize = nextValue()
        if nextSize != .zero {
            value = nextSize
        }
    }
}

extension View {
    func featureTourTarget(_ target: FeatureTourTargetID) -> some View {
        anchorPreference(
            key: FeatureTourTargetPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [target: anchor]
        }
    }

    func featureTourHost(
        _ coordinator: FeatureTourCoordinator,
        surface: FeatureTourSurface
    ) -> some View {
        modifier(
            FeatureTourHostModifier(
                coordinator: coordinator,
                surface: surface
            )
        )
    }
}

struct FeatureTourReplayButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action, label: label)
            .featureTourTarget(.settingsFeatureTourRow)
    }
}

private struct FeatureTourHostModifier: ViewModifier {
    @ObservedObject var coordinator: FeatureTourCoordinator
    let surface: FeatureTourSurface

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(FeatureTourTargetPreferenceKey.self) {
            anchors in
            GeometryReader { proxy in
                if let step = coordinator.currentStep,
                   step.surface == surface {
                    let overlayBounds = CGRect(
                        origin: .zero,
                        size: proxy.size
                    )
                    let overlayGlobalBounds = proxy.frame(in: .global)
                    let safeAreaInsets = FeatureTourSafeAreaInsets(
                        top: proxy.safeAreaInsets.top,
                        leading: proxy.safeAreaInsets.leading,
                        bottom: proxy.safeAreaInsets.bottom,
                        trailing: proxy.safeAreaInsets.trailing
                    )
                    let availableTargets = Set(anchors.keys)
                    let resolvedTarget = FeatureTourTargetResolver.target(
                        for: step,
                        availableTargets: availableTargets
                    )
                    let resolvedOverlayFrame = resolvedTarget.flatMap { target in
                        anchors[target].map { anchor in
                            let localFrame = proxy[anchor]
                            let globalFrame =
                                FeatureTourCoordinateConverter.globalFrame(
                                    fromOverlayFrame: localFrame,
                                    overlayGlobalBounds: overlayGlobalBounds
                                )
                            return FeatureTourCoordinateConverter.overlayFrame(
                                fromGlobalFrame: globalFrame,
                                overlayGlobalBounds: overlayGlobalBounds
                            )
                        }
                    }
                    let validation =
                        FeatureTourTargetFrameValidator.validate(
                            frame: resolvedOverlayFrame,
                            observedTarget: resolvedTarget,
                            expectedTarget: step.target,
                            overlayBounds: overlayBounds,
                            safeAreaInsets: safeAreaInsets
                        )

                    FeatureTourTargetResolvingOverlay(
                        coordinator: coordinator,
                        step: step,
                        candidateTargetFrame: validation.frame
                    )
                    .id(step.id)
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct FeatureTourTargetResolvingOverlay: View {
    @ObservedObject var coordinator: FeatureTourCoordinator
    let step: FeatureTourStep
    let candidateTargetFrame: CGRect?

    private var snapshotKey: FeatureTourTargetSnapshotKey {
        FeatureTourTargetSnapshotKey(
            stepID: step.id,
            targetID: step.target,
            frame: candidateTargetFrame
        )
    }

    var body: some View {
        FeatureTourOverlayView(
            coordinator: coordinator,
            step: step,
            targetFrame: coordinator.presentationState.targetFrame
        )
        .transition(.opacity)
        .animation(
            .easeInOut(duration: 0.18),
            value: coordinator.presentationState
        )
        .task(id: snapshotKey) {
            coordinator.updateTargetCandidate(
                candidateTargetFrame,
                for: step.id,
                targetID: step.target
            )
        }
    }
}

private struct FeatureTourOverlayView: View {
    @ObservedObject var coordinator: FeatureTourCoordinator
    let step: FeatureTourStep
    let targetFrame: CGRect?
    @State private var measuredTooltipSize = CGSize.zero
    @State private var isHighlightPulsing = false

    var body: some View {
        GeometryReader { geometry in
            let highlightFrame = targetFrame.map {
                $0.insetBy(
                    dx: -step.target.highlightPadding,
                    dy: -step.target.highlightPadding
                )
            }
            let highlightCornerRadius = highlightFrame.map {
                step.target.highlightCornerRadius(for: $0)
            } ?? 14
            let containerBounds = CGRect(
                origin: .zero,
                size: geometry.size
            )
            let safeAreaInsets = FeatureTourSafeAreaInsets(
                top: geometry.safeAreaInsets.top,
                leading: geometry.safeAreaInsets.leading,
                bottom: geometry.safeAreaInsets.bottom,
                trailing: geometry.safeAreaInsets.trailing
            )
            let safeHeight = max(
                geometry.size.height -
                    geometry.safeAreaInsets.top -
                    geometry.safeAreaInsets.bottom -
                    32,
                1
            )
            let tooltipMaximumWidth = min(
                430,
                max(
                    geometry.size.width -
                        geometry.safeAreaInsets.leading -
                        geometry.safeAreaInsets.trailing -
                        32,
                    1
                )
            )
            let baseTooltipMaximumHeight = min(
                360,
                safeHeight * 0.54
            )
            let sideAwareMaximumHeight = maximumTooltipHeight(
                baseMaximumHeight: baseTooltipMaximumHeight,
                containerBounds: containerBounds,
                safeAreaInsets: safeAreaInsets,
                targetFrame: highlightFrame
            )
            let effectiveTooltipSize = CGSize(
                width: measuredTooltipSize == .zero
                    ? tooltipMaximumWidth
                    : min(measuredTooltipSize.width, tooltipMaximumWidth),
                height: measuredTooltipSize == .zero
                    ? sideAwareMaximumHeight
                    : min(
                        measuredTooltipSize.height,
                        sideAwareMaximumHeight
                    )
            )
            let placement = FeatureTourPlacementSolver.placement(
                in: containerBounds,
                safeAreaInsets: safeAreaInsets,
                targetFrame: highlightFrame,
                tooltipSize: effectiveTooltipSize
            )

            ZStack {
                dimmingLayer(
                    size: geometry.size,
                    highlightFrame: highlightFrame,
                    cornerRadius: highlightCornerRadius
                )

                if let highlightFrame {
                    RoundedRectangle(
                        cornerRadius: highlightCornerRadius,
                        style: .continuous
                    )
                        .stroke(
                            WayTaskDesign.accent.opacity(
                                isHighlightPulsing ? 1 : 0.76
                            ),
                            lineWidth: isHighlightPulsing ? 3.2 : 2.4
                        )
                        .shadow(
                            color: WayTaskDesign.accent.opacity(
                                isHighlightPulsing ? 0.7 : 0.35
                            ),
                            radius: isHighlightPulsing ? 15 : 7
                        )
                        .scaleEffect(isHighlightPulsing ? 1.012 : 1)
                        .frame(
                            width: highlightFrame.width,
                            height: highlightFrame.height
                        )
                        .position(
                            x: highlightFrame.midX,
                            y: highlightFrame.midY
                        )
                        .accessibilityHidden(true)
                }

                FeatureTourTooltip(
                    coordinator: coordinator,
                    step: step,
                    showsUnavailableMessage: targetFrame == nil
                )
                .frame(width: tooltipMaximumWidth)
                .frame(maxHeight: sideAwareMaximumHeight)
                .background {
                    GeometryReader { tooltipGeometry in
                        Color.clear.preference(
                            key: FeatureTourTooltipSizePreferenceKey.self,
                            value: tooltipGeometry.size
                        )
                    }
                }
                .position(
                    x: placement.frame.midX,
                    y: placement.frame.midY
                )
            }
            .onPreferenceChange(
                FeatureTourTooltipSizePreferenceKey.self
            ) { size in
                guard size != .zero, measuredTooltipSize != size else {
                    return
                }

                measuredTooltipSize = size
            }
            .task(id: step.id) {
                isHighlightPulsing = false
                withAnimation(
                    .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: true)
                ) {
                    isHighlightPulsing = true
                }
            }
        }
        .zIndex(10_000)
        .accessibilityAddTraits(.isModal)
    }

    private func dimmingLayer(
        size: CGSize,
        highlightFrame: CGRect?,
        cornerRadius: CGFloat
    ) -> some View {
        Canvas { context, canvasSize in
            var path = Path(
                CGRect(origin: .zero, size: canvasSize)
            )

            if let highlightFrame {
                path.addRoundedRect(
                    in: highlightFrame,
                    cornerSize: CGSize(
                        width: cornerRadius,
                        height: cornerRadius
                    )
                )
            }

            context.fill(
                path,
                with: .color(.black.opacity(0.68)),
                style: FillStyle(eoFill: true)
            )
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func maximumTooltipHeight(
        baseMaximumHeight: CGFloat,
        containerBounds: CGRect,
        safeAreaInsets: FeatureTourSafeAreaInsets,
        targetFrame: CGRect?
    ) -> CGFloat {
        guard let targetFrame else {
            return baseMaximumHeight
        }

        let safeMinimumY = containerBounds.minY +
            safeAreaInsets.top + 16
        let safeMaximumY = containerBounds.maxY -
            safeAreaInsets.bottom - 16
        let availableAbove = max(
            targetFrame.minY - 14 - safeMinimumY,
            0
        )
        let availableBelow = max(
            safeMaximumY - targetFrame.maxY - 14,
            0
        )
        let largestSide = max(availableAbove, availableBelow)

        return max(min(baseMaximumHeight, largestSide), 1)
    }
}

private struct FeatureTourTooltip: View {
    @ObservedObject var coordinator: FeatureTourCoordinator
    let step: FeatureTourStep
    let showsUnavailableMessage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(
                    "Step \(coordinator.currentStepIndex + 1) of \(coordinator.steps.count)"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(WayTaskDesign.accent)

                Spacer(minLength: 8)

                progressDots
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(step.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    Text(step.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    if showsUnavailableMessage {
                        Label(
                            step.missingTargetMessage,
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionButtons
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(coordinator.steps.indices, id: \.self) { index in
                Circle()
                    .fill(
                        index <= coordinator.currentStepIndex
                            ? WayTaskDesign.accent
                            : Color.secondary.opacity(0.28)
                    )
                    .frame(
                        width: index == coordinator.currentStepIndex ? 7 : 5,
                        height: index == coordinator.currentStepIndex ? 7 : 5
                    )
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: coordinator.currentStepIndex
        )
        .accessibilityHidden(true)
    }

    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                backButton
                skipButton
                nextButton
            }

            VStack(spacing: 10) {
                backButton
                skipButton
                nextButton
            }
        }
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                coordinator.back()
            }
        } label: {
            Text("Back")
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(
            coordinator.isFirstStep
                ? Color.secondary.opacity(0.55)
                : WayTaskDesign.accent
        )
        .background(
            coordinator.isFirstStep
                ? Color.secondary.opacity(0.12)
                : WayTaskDesign.accent.opacity(0.12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    coordinator.isFirstStep
                        ? Color.secondary.opacity(0.18)
                        : WayTaskDesign.accent.opacity(0.38),
                    lineWidth: 1
                )
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isFirstStep)
        .accessibilityHint(
            coordinator.isFirstStep
                ? "Already at the first step"
                : "Returns to the previous tour step"
        )
    }

    private var skipButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                coordinator.skip()
            }
        } label: {
            Text("Skip")
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(WayTaskDesign.accent)
        .background(WayTaskDesign.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    WayTaskDesign.accent.opacity(0.38),
                    lineWidth: 1
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ends the feature tour")
    }

    private var nextButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                coordinator.next()
            }
        } label: {
            Text(coordinator.isLastStep ? "Done" : "Next")
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .background(WayTaskDesign.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
        .accessibilityHint(
            coordinator.isLastStep
                ? "Shows the tour completion screen"
                : "Shows the next tour step"
        )
    }
}
