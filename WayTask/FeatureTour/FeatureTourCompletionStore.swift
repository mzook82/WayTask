import Foundation

protocol FeatureTourCompletionStoring {
    var hasCompletedFeatureTour: Bool { get }
    func markFeatureTourCompleted()
}

struct UserDefaultsFeatureTourCompletionStore: FeatureTourCompletionStoring {
    static let completionKey = "waytask.featureTourCompleted.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompletedFeatureTour: Bool {
        userDefaults.bool(forKey: Self.completionKey)
    }

    func markFeatureTourCompleted() {
        userDefaults.set(true, forKey: Self.completionKey)
    }
}
