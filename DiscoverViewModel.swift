import Combine
import Foundation

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var items: [DiscoverItem] = []
    @Published var statusMessage: String?

    private let decisionEngine: DecisionEngineServicing
    private var context: ShoppingContext

    init() {
        self.context = Self.makeSampleContext()
        self.decisionEngine = DecisionEngine()
        reload()
    }

    init(
        context: ShoppingContext,
        decisionEngine: DecisionEngineServicing
    ) {
        self.context = context
        self.decisionEngine = decisionEngine
        reload()
    }

    func reload() {
        let decision = decisionEngine.evaluate(mission: .exploreNearby, context: context)
        var nextItems = sampleItems(from: context)

        if decision.outcome == .shoppingListItemsNearby {
            nextItems.append(contentsOf: context.nearbyStores.prefix(2).map(makeListItem))
        }

        items = nextItems
    }

    func items(for category: DiscoverCategory) -> [DiscoverItem] {
        items.filter { $0.category == category }
    }

    func handleSelection(_ item: DiscoverItem, appStateManager: AppStateManager) {
        guard item.canOpenMap else {
            statusMessage = "More personalized recommendations are coming soon."
            return
        }

        appStateManager.selectedTab = .map
        if let relatedStoreID = item.relatedStoreID {
            appStateManager.focusedLocationID = relatedStoreID
        }
    }

    private func sampleItems(from context: ShoppingContext) -> [DiscoverItem] {
        [
            DiscoverItem(
                title: "Nearby essentials",
                subtitle: "Local places that may fit a quick shopping trip.",
                category: .nearbyToday,
                distance: "Nearby",
                systemImageName: "location.circle.fill",
                relevanceReason: "Suggested from nearby shopping context.",
                sourceType: .localSample,
                canOpenMap: true
            ),
            DiscoverItem(
                title: "Complete your list",
                subtitle: listSubtitle(from: context),
                category: .basedOnYourList,
                distance: context.hasNearbyStores ? "Near stores" : nil,
                systemImageName: "checklist.checked",
                relevanceReason: "Uses active shopping list context only. No AI recommendation is used.",
                sourceType: .shoppingContext,
                relatedStoreID: context.nearbyStores.first?.id,
                canOpenMap: context.hasNearbyStores
            ),
            DiscoverItem(
                title: "Household restock ideas",
                subtitle: "Personal picks will improve as your shopping context grows.",
                category: .forYou,
                distance: nil,
                systemImageName: "house.fill",
                relevanceReason: "More personalized recommendations are coming soon.",
                sourceType: .localSample
            ),
            DiscoverItem(
                title: "New places around you",
                subtitle: "Fresh nearby places will appear here as discovery expands.",
                category: .newAroundYou,
                distance: "Soon",
                systemImageName: "sparkle.magnifyingglass",
                relevanceReason: "More nearby discovery options are coming soon.",
                sourceType: .futureRecommendation,
                canOpenMap: true
            )
        ]
    }

    private func makeListItem(from store: ShoppingContextStore) -> DiscoverItem {
        DiscoverItem(
            title: store.name,
            subtitle: store.matchingItemNames.isEmpty
                ? "Nearby store from shopping context."
                : "Matches: \(store.matchingItemNames.joined(separator: ", "))",
            category: .basedOnYourList,
            distance: "Nearby",
            systemImageName: "storefront.fill",
            relevanceReason: "Suggested from matching shopping list items.",
            sourceType: .shoppingContext,
            relatedStoreID: store.id,
            canOpenMap: true
        )
    }

    private func listSubtitle(from context: ShoppingContext) -> String {
        let activeItems = context.activeShoppingListItems
            .filter { !$0.isCompleted }
            .map(\.name)

        guard !activeItems.isEmpty else {
            return "Add list items to improve Discover results."
        }

        return "Looking for: \(activeItems.prefix(3).joined(separator: ", "))"
    }

    private static func makeSampleContext() -> ShoppingContext {
        let storeID = UUID(uuidString: "20000000-0000-0000-0000-000000000001") ?? UUID()

        return ShoppingContext(
            currentLocation: nil,
            activeShoppingListItems: [
                ShoppingContextItem(name: "Milk"),
                ShoppingContextItem(name: "Bread"),
                ShoppingContextItem(name: "Cleaning spray")
            ],
            nearbyStores: [
                ShoppingContextStore(
                    id: storeID,
                    name: "Local Market",
                    coordinate: nil,
                    matchingItemNames: ["Milk", "Bread"],
                    isFavorite: false,
                    websiteURL: nil
                )
            ],
            selectedInterests: ["Groceries", "Household"],
            timeOfDay: Date(),
            dayOfWeek: Calendar.current.component(.weekday, from: Date()),
            recentSearches: [],
            favoriteStores: [],
            availableProductHints: ["pantry", "weekly essentials"]
        )
    }
}
