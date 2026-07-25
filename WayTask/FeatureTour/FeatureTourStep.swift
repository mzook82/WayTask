import Foundation

enum FeatureTourStepID: String, CaseIterable {
    case productsAdd
    case productAutocomplete
    case cameraCapture
    case mapFollowUser
    case storeNavigation
    case storesWorkspace
    case settingsReplay
}

enum FeatureTourSurface: Hashable {
    case products
    case productEntry
    case camera
    case map
    case shopping
    case settings
}

enum FeatureTourTargetID: String, Hashable {
    case productsBottomAddButton
    case addProductNameField
    case cameraShutterButton
    case mapFollowLocationButton
    case mapNavigateButton
    case shoppingRecommendedStoreCard
    case settingsFeatureTourRow
}

struct FeatureTourStep: Identifiable, Equatable {
    let id: FeatureTourStepID
    let title: String
    let message: String
    let destinationTab: AppTab
    let surface: FeatureTourSurface
    let target: FeatureTourTargetID
    let missingTargetMessage: String

    static let wayTaskSteps: [FeatureTourStep] = [
        FeatureTourStep(
            id: .productsAdd,
            title: "Add a product",
            message: "Open manual product entry from the Products tab.",
            destinationTab: .products,
            surface: .products,
            target: .productsBottomAddButton,
            missingTargetMessage:
                "The Add button is not visible yet. You can continue safely."
        ),
        FeatureTourStep(
            id: .productAutocomplete,
            title: "Search the catalog",
            message: "Type a product name here to see canonical catalog suggestions.",
            destinationTab: .products,
            surface: .productEntry,
            target: .addProductNameField,
            missingTargetMessage:
                "The product-name field is not visible yet. You can continue safely."
        ),
        FeatureTourStep(
            id: .cameraCapture,
            title: "Scan a product",
            message: "Use the capture control to recognize a product with the camera.",
            destinationTab: .home,
            surface: .camera,
            target: .cameraShutterButton,
            missingTargetMessage:
                "The camera capture button is not available right now. You can continue safely."
        ),
        FeatureTourStep(
            id: .mapFollowUser,
            title: "Follow your location",
            message: "Center the map on your current location at any time.",
            destinationTab: .map,
            surface: .map,
            target: .mapFollowLocationButton,
            missingTargetMessage:
                "The follow-location button is not visible yet. You can continue safely."
        ),
        FeatureTourStep(
            id: .storeNavigation,
            title: "Navigate to a store",
            message: "Select a live store to open directions. If none is available, WayTask keeps this step safe and lets you continue.",
            destinationTab: .map,
            surface: .map,
            target: .mapNavigateButton,
            missingTargetMessage:
                "Navigation appears after selecting a store."
        ),
        FeatureTourStep(
            id: .storesWorkspace,
            title: "Review recommended stores",
            message: "Shopping groups your list and shows recommended stores when a plan is available.",
            destinationTab: .shopping,
            surface: .shopping,
            target: .shoppingRecommendedStoreCard,
            missingTargetMessage:
                "Recommended stores appear after a shopping plan is available."
        ),
        FeatureTourStep(
            id: .settingsReplay,
            title: "Replay the tour anytime",
            message: "Use View Feature Tour in Settings whenever you want another walkthrough.",
            destinationTab: .settings,
            surface: .settings,
            target: .settingsFeatureTourRow,
            missingTargetMessage:
                "View Feature Tour is not visible yet. You can continue safely."
        )
    ]
}

enum FeatureTourTargetResolver {
    static func target(
        for step: FeatureTourStep,
        availableTargets: Set<FeatureTourTargetID>
    ) -> FeatureTourTargetID? {
        availableTargets.contains(step.target) ? step.target : nil
    }
}
