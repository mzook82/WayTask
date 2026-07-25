import SwiftUI

enum FeatureTourCompletionCopy {
    static let title = "You’re all set!"
    static let message =
        "You can replay this tour anytime from Settings."
    static let action = "Start Using WayTask"
}

struct FeatureTourCompletionView: View {
    let onStart: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 82

    var body: some View {
        ZStack {
            WayTaskDesign.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)

                    Image(systemName: "checkmark.circle.fill")
                        .font(
                            .system(
                                size: symbolSize,
                                weight: .semibold
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WayTaskDesign.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text(FeatureTourCompletionCopy.title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WayTaskDesign.primaryText)

                        Text(FeatureTourCompletionCopy.message)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }

                    Button(
                        FeatureTourCompletionCopy.action,
                        action: onStart
                    )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WayTaskDesign.accentGradient)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        "Closes the feature tour and opens WayTask"
                    )

                    Spacer(minLength: 36)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    FeatureTourCompletionView(onStart: {})
}
