import Foundation

protocol OnboardingCompletionStoring {
    var hasCompletedOnboarding: Bool { get }
    func markOnboardingCompleted()
}

struct UserDefaultsOnboardingCompletionStore: OnboardingCompletionStoring {
    static let completionKey = "waytask.firstLaunchOnboardingCompleted.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompletedOnboarding: Bool {
        userDefaults.bool(forKey: Self.completionKey)
    }

    func markOnboardingCompleted() {
        userDefaults.set(true, forKey: Self.completionKey)
    }
}
