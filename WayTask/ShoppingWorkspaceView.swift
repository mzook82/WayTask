import CoreLocation
import SwiftData
import SwiftUI

struct ShoppingWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var items: [ShoppingItem]
    @Query private var locations: [GeoLocation]
    @Query private var shoppingSessions: [ShoppingSession]

    @State private var selectedListID = "weekly"
    @State private var searchText = ""
    @State private var isShowingPlanSheet = false

    private let intentMatcher = ShoppingIntentMatcher()
    private let buyingOptionsService = BuyingOptionsService()
    private let shoppingTripPlanningService = ShoppingTripService()
    private let shoppingSessionService = ShoppingSessionService()

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xl) {
                        header
                        listSelector
                        summaryCard
                        recommendedStoresSection
                        coverageCardsSection
                        groupedProductsSection
                    }
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)
                    .padding(.top, WayTaskDesign.Spacing.md)
                    .padding(.bottom, 118)
                }
            }
            .safeAreaInset(edge: .bottom) {
                startShoppingBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingPlanSheet) {
                planBottomSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private var header: some View {
        WayTaskScreenHeader(
            title: "Shopping",
            subtitle: "\(selectedListTitle) - \(activeItemCount) \(activeItemCount == 1 ? "item" : "items") - \(recommendedStoreCount) stores",
            trailingIcons: ["cart.fill"]
        )
    }

    private var listSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WayTaskDesign.Spacing.xs) {
                ForEach(listChips) { chip in
                    WayTaskFilterChip(title: "\(chip.title) \(chip.count)", isSelected: chip.id == selectedListID) {
                        selectedListID = chip.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
            HStack(alignment: .center, spacing: WayTaskDesign.Spacing.md) {
                WayTaskProgressRing(progress: shoppingProgress, size: 62, lineWidth: 7)

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                    Text("Shopping summary")
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text(summaryText)
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)

                WayTaskBadge(title: "\(recommendedStoreCount) stores", tone: .accent)
            }

            HStack(spacing: WayTaskDesign.Spacing.sm) {
                WayTaskMetricCard(value: "\(activeItemCount)", title: "Open", systemImage: "basket.fill")
                WayTaskMetricCard(value: "\(groupedProductRows.count)", title: "Groups", systemImage: "square.grid.2x2.fill")
                WayTaskMetricCard(value: "\(collectedCount)", title: "Collected", systemImage: "checkmark.circle.fill")
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(highlighted: true)
    }

    private var recommendedStoresSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Recommended stores", subtitle: "Planner preview", actionTitle: recommendedStoreRows.isEmpty ? nil : "Details") {
                isShowingPlanSheet = true
            }

            if let bestStore = recommendedStoreRows.first {
                WayTaskStoreCard(
                    title: bestStore.storeName,
                    subtitle: bestStore.subtitle,
                    distanceText: bestStore.distanceText,
                    coverage: bestStore.coverage,
                    confidenceText: bestStore.confidenceText,
                    isBestMatch: true,
                    actionTitle: "View Plan"
                ) {
                    isShowingPlanSheet = true
                }
            } else {
                WayTaskEmptyState(
                    title: "Plan not ready yet",
                    message: activeItems.isEmpty ? "Add products to generate a shopping plan." : "Generate a plan from your current shopping list.",
                    systemImage: "storefront",
                    actionTitle: activeItems.isEmpty ? nil : "Generate plan",
                    action: generatePlan
                )
            }
        }
    }

    @ViewBuilder
    private var coverageCardsSection: some View {
        let additionalRows = Array(recommendedStoreRows.dropFirst())

        if !additionalRows.isEmpty {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
                WayTaskSectionHeader(title: "Coverage cards")

                VStack(spacing: WayTaskDesign.Spacing.sm) {
                    ForEach(additionalRows) { row in
                        WayTaskStoreCard(
                            title: row.storeName,
                            subtitle: row.subtitle,
                            distanceText: row.distanceText,
                            coverage: row.coverage,
                            confidenceText: row.confidenceText,
                            isBestMatch: false
                        ) {
                            isShowingPlanSheet = true
                        }
                    }
                }
            }
        }
    }

    private var groupedProductsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Your list", subtitle: "Grouped by store intent")

            WayTaskSearchField(placeholder: "Search shopping list", text: $searchText)

            VStack(spacing: WayTaskDesign.Spacing.md) {
                if groupedProductRows.isEmpty {
                    WayTaskEmptyState(
                        title: activeItems.isEmpty ? "No shopping items" : "No matching items",
                        message: activeItems.isEmpty ? "Add products to build your shopping list." : "Clear search to see the current shopping list.",
                        systemImage: activeItems.isEmpty ? "basket" : "magnifyingglass"
                    )
                } else {
                    ForEach(groupedProductRows) { group in
                        groupedProductCard(group)
                    }
                }
            }
        }
    }

    private func groupedProductCard(_ group: ShoppingWorkspaceGroup) -> some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            HStack(spacing: WayTaskDesign.Spacing.xs) {
                Circle()
                    .fill(WayTaskDesign.accent)
                    .frame(width: 8, height: 8)

                Text(group.title)
                    .font(WayTaskDesign.Typography.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)

                Text(group.subtitle)
                    .font(WayTaskDesign.Typography.caption)
                    .foregroundStyle(WayTaskDesign.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: WayTaskDesign.Spacing.xs)

                WayTaskBadge(title: "\(group.items.count) items", tone: .neutral)
            }

            VStack(spacing: 0) {
                ForEach(group.items) { item in
                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        WayTaskProductThumbnail(
                            data: item.imageData,
                            url: item.imageURL,
                            size: 42,
                            cornerRadius: WayTaskDesign.Radius.sm
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                                .foregroundStyle(WayTaskDesign.primaryText)
                                .lineLimit(1)

                            Text(item.subtitle)
                                .font(WayTaskDesign.Typography.caption)
                                .foregroundStyle(WayTaskDesign.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: WayTaskDesign.Spacing.xs)

                        if item.isCompleted {
                            WayTaskBadge(title: "Done", systemImage: "checkmark", tone: .success)
                        }
                    }
                    .padding(.vertical, WayTaskDesign.Spacing.xs)

                    if item.id != group.items.last?.id {
                        Divider()
                            .overlay(WayTaskDesign.surfaceBorder)
                    }
                }
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.xl)
    }

    private var startShoppingBar: some View {
        VStack(spacing: WayTaskDesign.Spacing.sm) {
            HStack(spacing: WayTaskDesign.Spacing.sm) {
                WayTaskSecondaryButton("Map", systemImage: "map.fill") {
                    appStateManager.showTripOnMap(
                        for: appStateManager.storeSuggestionRequest ?? fallbackSuggestionRequest,
                        buyingOptions: appStateManager.buyingOptions,
                        shoppingTripCoverages: appStateManager.shoppingTripCoverages
                    )
                }
                .disabled(!canOpenMapPlan)
                .opacity(canOpenMapPlan ? 1 : 0.45)

                WayTaskPrimaryButton("Start Shopping", systemImage: "play.fill", isDisabled: activeItems.isEmpty) {
                    startShopping()
                }
            }
            .padding(.horizontal, WayTaskDesign.Spacing.lg)
            .padding(.vertical, WayTaskDesign.Spacing.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WayTaskDesign.surfaceBorder)
                    .frame(height: 1)
            }
        }
    }

    private var planBottomSheet: some View {
        WayTaskBottomSheet(title: "Shopping plan") {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
                if recommendedStoreRows.isEmpty {
                    WayTaskEmptyState(
                        title: "Plan not ready yet",
                        message: activeItems.isEmpty ? "Add products to generate a shopping plan." : "Generate a plan from your current shopping list.",
                        systemImage: "storefront",
                        actionTitle: activeItems.isEmpty ? nil : "Generate plan",
                        action: generatePlan
                    )
                } else {
                    ForEach(recommendedStoreRows) { row in
                        HStack(spacing: WayTaskDesign.Spacing.md) {
                            if let coverage = row.coverage {
                                WayTaskCoverageRing(progress: coverage, size: 52, lineWidth: 6)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.storeName)
                                    .font(WayTaskDesign.Typography.headline)
                                    .foregroundStyle(WayTaskDesign.primaryText)
                                    .lineLimit(1)

                                Text(row.subtitle)
                                    .font(WayTaskDesign.Typography.caption)
                                    .foregroundStyle(WayTaskDesign.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer()

                            WayTaskBadge(title: row.confidenceText, tone: row.isBestMatch ? .accent : .neutral)
                        }
                        .padding(WayTaskDesign.Spacing.sm)
                        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.md, highlighted: row.isBestMatch)
                    }

                    WayTaskPrimaryButton("Start Shopping", systemImage: "play.fill", isDisabled: activeItems.isEmpty) {
                        isShowingPlanSheet = false
                        startShopping()
                    }
                }
            }
        }
    }

    private var activeItems: [ShoppingItem] {
        items.filter { !$0.isCompleted }
    }

    private var activeItemCount: Int {
        activeItems.count
    }

    private var filteredActiveItems: [ShoppingItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return activeItems
        }

        return activeItems.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.brand?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var activeSession: ShoppingSession? {
        shoppingSessions
            .filter(\.isActive)
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var collectedCount: Int {
        activeSession?.collectedItemIDs.count ?? 0
    }

    private var shoppingProgress: Double {
        guard let activeSession, !activeSession.itemIDs.isEmpty else {
            return 0
        }

        return Double(activeSession.collectedItemIDs.count) / Double(activeSession.itemIDs.count)
    }

    private var selectedListTitle: String {
        listChips.first { $0.id == selectedListID }?.title ?? "Weekly Shopping"
    }

    private var listChips: [ShoppingWorkspaceListChip] {
        [
            ShoppingWorkspaceListChip(id: "weekly", title: "Weekly", count: activeItemCount),
            ShoppingWorkspaceListChip(id: "open", title: "Open", count: activeItemCount),
            ShoppingWorkspaceListChip(id: "done", title: "Done", count: items.filter(\.isCompleted).count),
            ShoppingWorkspaceListChip(id: "recent", title: "Recent", count: min(items.count, 8))
        ]
    }

    private var recommendedStoreRows: [ShoppingWorkspaceStoreRow] {
        let coverageRows = appStateManager.shoppingTripCoverages.prefix(4).enumerated().map { index, coverage in
            ShoppingWorkspaceStoreRow(
                storeName: coverage.store.title,
                subtitle: "\(coverage.matchedItemCount)/\(coverage.matchedItemCount + coverage.missingItemCount) items - \(coverage.group.displayName)",
                distanceText: coverage.distance.map(distanceText(for:)),
                coverage: coverage.coverageScore,
                confidenceText: coverage.ranking.confidenceLabel,
                isBestMatch: index == 0
            )
        }

        if !coverageRows.isEmpty {
            return coverageRows
        }

        return realBuyingOptionRows
    }

    private var realBuyingOptionRows: [ShoppingWorkspaceStoreRow] {
        appStateManager.buyingOptions
            .filter(\.isDisplayableRealStore)
            .prefix(4)
            .enumerated()
            .map { index, option in
                ShoppingWorkspaceStoreRow(
                    storeName: option.storeName,
                    subtitle: option.subtitle,
                    distanceText: option.distanceText,
                    coverage: option.ranking.map { min(max($0.score / 100, 0), 1) },
                    confidenceText: option.confidenceLabel ?? option.source.displayName,
                    isBestMatch: index == 0
                )
            }
    }

    private var recommendedStoreCount: Int {
        recommendedStoreRows.count
    }

    private var canOpenMapPlan: Bool {
        !activeItems.isEmpty || !appStateManager.shoppingTripCoverages.isEmpty || !realBuyingOptionRows.isEmpty
    }

    private var groupedProductRows: [ShoppingWorkspaceGroup] {
        intentMatcher.groupedIntents(for: filteredActiveItems).map {
            ShoppingWorkspaceGroup(
                title: groupTitle(for: $0.group),
                subtitle: groupSubtitle(for: $0.group),
                items: $0.items.map { ShoppingWorkspaceItemRow(item: $0) }
            )
        }
    }

    private var summaryText: String {
        if activeItemCount == 0 {
            return "No active items yet. The workspace is ready for the next shopping list."
        }

        return "\(activeItemCount) open items grouped into \(groupedProductRows.count) shopping intents."
    }

    private var fallbackSuggestionRequest: ShoppingStoreSuggestionRequest {
        intentMatcher.request(for: activeItems, in: .grocery)
    }

    private func generatePlan() {
        guard !activeItems.isEmpty else {
            return
        }

        let request = appStateManager.storeSuggestionRequest ?? fallbackSuggestionRequest
        let stores = savedStoresForPlanning()
        let userCoordinate = locationManager.currentCoordinate
        let buyingOptions = buyingOptionsService.localOptions(
            for: request,
            shoppingItems: activeItems,
            stores: stores,
            userCoordinate: userCoordinate
        )
        .filter(\.isDisplayableRealStore)
        let shoppingTripCoverages = shoppingTripPlanningService.coverage(
            for: activeItems,
            stores: stores,
            request: request,
            userCoordinate: userCoordinate
        )

        isShowingPlanSheet = false
        appStateManager.showTripOnMap(
            for: request,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: shoppingTripCoverages
        )
    }

    private func startShopping() {
        guard !activeItems.isEmpty else {
            return
        }

        do {
            try shoppingSessionService.startShopping(with: activeItems, in: modelContext)
            appStateManager.selectedTab = .products
        } catch {
            assertionFailure("Failed to start shopping session: \(error.localizedDescription)")
        }
    }

    private func groupTitle(for group: ShoppingIntentGroup) -> String {
        switch group {
        case .grocery:
            return "Grocery items"
        case .electronics:
            return "Electronics items"
        case .pet:
            return "Pet items"
        case .pharmacy:
            return "Health items"
        case .other:
            return "Other items"
        }
    }

    private func groupSubtitle(for group: ShoppingIntentGroup) -> String {
        switch group {
        case .pharmacy:
            return "Health"
        default:
            return group.displayName
        }
    }

    private func savedStoresForPlanning() -> [MapStore] {
        locations.filter { $0.sourceType != .debugSeed }.map { location in
            MapStore(
                id: location.id,
                locationID: location.id,
                title: location.title,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                radius: location.radius,
                itemNames: location.shoppingItems.filter { !$0.isCompleted }.map(\.name),
                completedItemNames: location.shoppingItems.filter(\.isCompleted).map(\.name),
                isOpen: true,
                rating: nil,
                storeCategories: location.storeCategory.map { [$0] } ?? [],
                queryEvidenceCategories: [],
                websiteURL: nil,
                sourceType: location.sourceType
            )
        }
    }

    private func distanceText(for distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }

        return "\(max(Int(distance.rounded()), 1)) m"
    }
}

private extension BuyingOption {
    var isDisplayableRealStore: Bool {
        switch optionType {
        case .nearbyStore, .suggestedStore:
            break
        case .onlineStore, .futurePriceComparison:
            return false
        }

        switch source {
        case .local, .debugSeed:
            return false
        case .appleMaps, .openStreetMap, .retailAPI, .publicDatabase, .aiProvider, .userGenerated:
            return true
        }
    }
}

private struct ShoppingWorkspaceListChip: Identifiable {
    let id: String
    let title: String
    let count: Int
}

private struct ShoppingWorkspaceStoreRow: Identifiable {
    let id = UUID()
    let storeName: String
    let subtitle: String
    let distanceText: String?
    let coverage: Double?
    let confidenceText: String
    let isBestMatch: Bool
}

private struct ShoppingWorkspaceGroup: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let items: [ShoppingWorkspaceItemRow]
}

private struct ShoppingWorkspaceItemRow: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String
    var imageData: Data?
    var imageURL: URL?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        imageData: Data? = nil,
        imageURL: URL? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageData = imageData
        self.imageURL = imageURL
        self.isCompleted = isCompleted
    }

    init(item: ShoppingItem) {
        self.id = item.id
        self.name = item.name
        self.subtitle = item.brand ?? item.category ?? "Shopping item"
        self.imageData = item.imageData
        self.imageURL = item.imageURL
        self.isCompleted = item.isCompleted
    }
}
