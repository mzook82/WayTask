import Foundation
import XCTest
@testable import WayTask

@MainActor
final class OnboardingFoundationTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingFoundationTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testWayTaskOnboardingDefinesTheApprovedFivePages() {
        let pages = OnboardingPage.wayTaskPages

        XCTAssertEqual(pages.count, 5)
        XCTAssertEqual(Set(pages.map(\.id)).count, 5)
        XCTAssertEqual(
            pages.map(\.title),
            [
                "Welcome to WayTask",
                "AI Camera",
                "Shopping List",
                "Smart Store Alerts",
                "You're Ready"
            ]
        )
        XCTAssertEqual(
            pages.map(\.subtitle),
            [
                "Your smart shopping companion.",
                "Use AI or your camera to recognize products, or add them manually.",
                "Build your product list before you need to shop.",
                "WayTask notifies you when you are near stores that sell products from your list.",
                "Start exploring WayTask."
            ]
        )
    }

    func testFirstLaunchPresentsAndCompletionPersistsForLaterLaunches() {
        let store = UserDefaultsOnboardingCompletionStore(
            userDefaults: userDefaults
        )
        let firstLaunch = OnboardingCoordinator(completionStore: store)

        XCTAssertTrue(firstLaunch.isPresented)
        XCTAssertFalse(store.hasCompletedOnboarding)

        firstLaunch.complete()

        XCTAssertFalse(firstLaunch.isPresented)
        XCTAssertTrue(store.hasCompletedOnboarding)

        let subsequentLaunch = OnboardingCoordinator(
            completionStore: store
        )
        XCTAssertFalse(subsequentLaunch.isPresented)
    }

    func testInterruptedFirstLaunchDoesNotMarkOnboardingComplete() {
        let store = UserDefaultsOnboardingCompletionStore(
            userDefaults: userDefaults
        )
        let coordinator = OnboardingCoordinator(completionStore: store)

        coordinator.dismissWithoutCompleting()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(
            OnboardingCoordinator(completionStore: store).isPresented
        )
    }

    func testCompletedOnboardingCanBePresentedAgainWithoutResettingState() {
        let store = UserDefaultsOnboardingCompletionStore(
            userDefaults: userDefaults
        )
        store.markOnboardingCompleted()
        let coordinator = OnboardingCoordinator(completionStore: store)

        XCTAssertFalse(coordinator.isPresented)

        coordinator.present()
        XCTAssertTrue(coordinator.isPresented)

        coordinator.complete()
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(
            OnboardingCoordinator(completionStore: store).isPresented
        )
    }
}
