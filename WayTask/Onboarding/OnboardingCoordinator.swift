import Combine
import Foundation

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var isPresented: Bool

    private let completionStore: any OnboardingCompletionStoring

    init(completionStore: any OnboardingCompletionStoring) {
        self.completionStore = completionStore
        isPresented = !completionStore.hasCompletedOnboarding
    }

    convenience init() {
        self.init(
            completionStore: UserDefaultsOnboardingCompletionStore()
        )
    }

    var hasCompletedOnboarding: Bool {
        completionStore.hasCompletedOnboarding
    }

    func complete() {
        completionStore.markOnboardingCompleted()
        isPresented = false
    }

    func present() {
        isPresented = true
    }

    func dismissWithoutCompleting() {
        isPresented = false
    }
}
