import SwiftUI

struct OnboardingFlowView: View {
    let pages: [OnboardingPage]
    let onSkip: () -> Void
    let onComplete: () -> Void

    @State private var selectedPageIndex = 0
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 82

    init(
        pages: [OnboardingPage] = OnboardingPage.wayTaskPages,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        precondition(!pages.isEmpty, "Onboarding requires at least one page.")
        self.pages = pages
        self.onSkip = onSkip
        self.onComplete = onComplete
    }

    private var isLastPage: Bool {
        selectedPageIndex == pages.count - 1
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pageView
                pageIndicator
                primaryAction
            }
        }
        .tint(WayTaskDesign.accent)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
    }

    private var topBar: some View {
        HStack {
            Spacer()

            if !isLastPage {
                Button("Skip", action: onSkip)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Closes onboarding and opens WayTask")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var pageView: some View {
        TabView(selection: $selectedPageIndex) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                OnboardingPageView(
                    page: page,
                    symbolSize: symbolSize
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.3), value: selectedPageIndex)
        .accessibilityValue(
            "Page \(selectedPageIndex + 1) of \(pages.count)"
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        index == selectedPageIndex
                            ? WayTaskDesign.accent
                            : Color.secondary.opacity(0.25)
                    )
                    .frame(
                        width: index == selectedPageIndex ? 24 : 8,
                        height: 8
                    )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedPageIndex)
        .accessibilityHidden(true)
        .padding(.bottom, 24)
    }

    private var primaryAction: some View {
        Button {
            if isLastPage {
                onComplete()
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedPageIndex += 1
                }
            }
        } label: {
            Text(isLastPage ? "Get Started" : "Next")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .accessibilityHint(
            isLastPage
                ? "Closes onboarding and opens WayTask"
                : "Shows the next onboarding page"
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let symbolSize: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 28)

                Image(systemName: page.systemImage)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WayTaskDesign.accent)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Text(page.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text(page.subtitle)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingFlowView(
        onSkip: {},
        onComplete: {}
    )
}
