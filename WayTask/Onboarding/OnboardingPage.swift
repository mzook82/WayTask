import Foundation

struct OnboardingPage: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String

    static let wayTaskPages: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            title: "Welcome to WayTask",
            subtitle: "Your smart shopping companion.",
            systemImage: "sparkles"
        ),
        OnboardingPage(
            id: "ai-camera",
            title: "AI Camera",
            subtitle: "Use AI or your camera to recognize products, or add them manually.",
            systemImage: "camera.viewfinder"
        ),
        OnboardingPage(
            id: "shopping-list",
            title: "Shopping List",
            subtitle: "Build your product list before you need to shop.",
            systemImage: "list.bullet.rectangle.fill"
        ),
        OnboardingPage(
            id: "store-alerts",
            title: "Smart Store Alerts",
            subtitle: "WayTask notifies you when you are near stores that sell products from your list.",
            systemImage: "bell.badge.fill"
        ),
        OnboardingPage(
            id: "ready",
            title: "You're Ready",
            subtitle: "Start exploring WayTask.",
            systemImage: "checkmark.circle.fill"
        )
    ]
}
