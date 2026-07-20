import Combine
import CoreLocation
import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var items: [ShoppingItem]
    @Query private var products: [Product]
    @Query private var locations: [GeoLocation]
    @Query private var shoppingSessions: [ShoppingSession]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]

    @State private var isShowingScanner = false
    @State private var cachedPlanRows: [HomePlanRow] = []
    @State private var cachedRecentProductCards: [HomeProductCardData] = []
    @State private var homeNow = Date()

    private let buyingOptionsService = BuyingOptionsService()
    private let intentMatcher = ShoppingIntentMatcher()
    private let shoppingTripPlanningService = ShoppingTripService()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xl) {
                        header
                        shoppingTodayCard
                        shoppingListsSection
                        bestShoppingPlanSection
                        nearbyOpportunitySection
                        recentProductsSection
                        monthlyStatsSection
                    }
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)
                    .padding(.top, WayTaskDesign.Spacing.md)
                    .padding(.bottom, 118)
                }

                WayTaskFloatingScanButton {
                    isShowingScanner = true
                }
                .padding(.trailing, WayTaskDesign.Spacing.lg)
                .padding(.bottom, WayTaskDesign.Spacing.xl)
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isShowingScanner) {
                CameraView {
                    isShowingScanner = false
                }
            }
            .onAppear {
                refreshHomePresentationCache()
            }
            .onReceive(planningTickPublisher) { now in
                homeNow = now
            }
            .onChange(of: appStateManager.shoppingPlan?.id) {
                refreshPlanRowsCache()
            }
            .onChange(of: appStateManager.shoppingPlanState) {
                refreshPlanRowsCache()
            }
            .onChange(of: homeItemPresentationSignature) {
                refreshRecentProductCardsCache()
            }
            .onChange(of: productPresentationSignature) {
                refreshRecentProductCardsCache()
            }
        }
    }

    private var planningTickPublisher: AnyPublisher<Date, Never> {
        guard appStateManager.shoppingPlanState.isGenerating else {
            return Empty<Date, Never>(completeImmediately: false).eraseToAnyPublisher()
        }

        return Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: WayTaskDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                Text(dateLabel)
                    .font(WayTaskDesign.Typography.captionStrong)
                    .foregroundStyle(WayTaskDesign.accent)

                Text("\(greeting), Mordechai")
                    .font(WayTaskDesign.Typography.largeTitle)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: WayTaskDesign.Spacing.sm)

            Button {
                WayTaskHaptics.selection()
                appStateManager.selectedTab = .settings
            } label: {
                Text("M")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(WayTaskDesign.accentGradient)
                    .clipShape(Circle())
                    .shadow(color: WayTaskDesign.Elevation.buttonShadow, radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
            .padding(.top, WayTaskDesign.Spacing.xs)
        }
    }

    private var shoppingTodayCard: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.lg) {
            HStack {
                Text("SHOPPING TODAY")
                    .font(WayTaskDesign.Typography.captionStrong)
                    .foregroundStyle(WayTaskDesign.Colors.warning)

                Spacer()

                if bestCoverage?.store.isOpen == false {
                    WayTaskBadge(title: "Closed", systemImage: "circle.fill", tone: .danger)
                }
            }

            Text("\(homeShoppingItemCount) \(homeShoppingItemCount == 1 ? "item" : "items") to buy")
                .font(WayTaskDesign.Typography.title)
                .foregroundStyle(WayTaskDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let bestCoverage {
                WayTaskRecommendationCard(
                    recommendationTitle: recommendationTitle(for: bestCoverage.group),
                    storeName: bestCoverage.store.title,
                    likelyItemNames: bestCoverage.matchedItems.map(\.name),
                    otherItemNames: [],
                    totalItemCount: homePlanItems.count,
                    distanceText: bestCoverage.distance.map(distanceText(for:)),
                    isHighlighted: true,
                    isEmbedded: true,
                    showsItemDetails: false
                )
            } else {
                homePlanStatusBlock
            }

            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                HStack {
                    Text("Trip progress")
                    Spacer()
                    Text("\(collectedCount) of \(homeShoppingTotalCount) collected")
                }
                .font(WayTaskDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)

                ProgressView(value: tripProgress)
                    .tint(WayTaskDesign.accent)
            }

            WayTaskPrimaryButton(homePrimaryActionTitle, systemImage: homePrimaryActionImage, isDisabled: isHomePrimaryDisabled) {
                handleHomePrimaryAction()
            }
        }
        .padding(WayTaskDesign.Spacing.lg)
        .background {
            LinearGradient(
                colors: [WayTaskDesign.accent.opacity(0.22), WayTaskDesign.accent.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sheet, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: WayTaskDesign.accent.opacity(0.14), radius: 28, y: 16)
    }

    private var shoppingListsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Shopping lists")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WayTaskDesign.Spacing.sm) {
                    ForEach(shoppingListSummaries) { summary in
                        WayTaskShoppingListCard(
                            title: summary.title,
                            itemCount: summary.itemCount,
                            completedCount: summary.completedCount,
                            subtitle: summary.subtitle,
                            isActive: summary.isActive
                        ) {
                            appStateManager.selectedTab = .products
                        }
                        .frame(width: 152)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var bestShoppingPlanSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Recommended stores", actionTitle: "See all") {
                appStateManager.selectedTab = .shopping
            }

            if planRows.isEmpty {
                bestPlanEmptyState
            } else {
                VStack(spacing: WayTaskDesign.Spacing.sm) {
                    ForEach(planRows) { row in
                        WayTaskRecommendationCard(
                            recommendationTitle: row.recommendationTitle,
                            storeName: row.storeName,
                            likelyItemNames: row.likelyItemNames,
                            otherItemNames: [],
                            totalItemCount: row.totalItemCount,
                            distanceText: row.distanceText,
                            isHighlighted: row.isHighlighted,
                            showsItemDetails: false
                        ) {
                            appStateManager.selectedTab = .shopping
                        }
                    }
                }
            }
        }
    }

    private var homePlanStatusBlock: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
            Text(homePlanStatusTitle)
                .font(WayTaskDesign.Typography.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text(homePlanStatusMessage)
                .font(WayTaskDesign.Typography.caption)
                .foregroundStyle(WayTaskDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(homePlanStatusTitle). \(homePlanStatusMessage)")
    }

    private var bestPlanEmptyState: some View {
        WayTaskEmptyState(
            title: homePlanStatusTitle,
            message: homePlanStatusMessage,
            systemImage: "storefront",
            actionTitle: activeItemCount == 0 ? nil : "Open Shopping"
        ) {
            appStateManager.selectedTab = .shopping
        }
    }

    @ViewBuilder
    private var nearbyOpportunitySection: some View {
        if let opportunity = appStateManager.visibleNearbyOpportunity {
            nearbyCard(
                title: opportunity.itemNames.first ?? "Nearby item",
                subtitle: "\(opportunity.title) - \(opportunity.distanceText)",
                primaryActionTitle: "Map",
                primaryAction: { appStateManager.openNearbyOpportunityOnMap(opportunity) },
                dismissAction: { appStateManager.dismissNearbyOpportunity(opportunity) }
            )
        }
    }

    private func nearbyCard(
        title: String,
        subtitle: String,
        primaryActionTitle: String,
        primaryAction: @escaping () -> Void,
        dismissAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: WayTaskDesign.Spacing.md) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 46, height: 46)
                .background(WayTaskDesign.accent.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("NEARBY OPPORTUNITY")
                    .font(WayTaskDesign.Typography.captionStrong)
                    .foregroundStyle(WayTaskDesign.accent)

                Text(title)
                    .font(WayTaskDesign.Typography.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(WayTaskDesign.Typography.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: WayTaskDesign.Spacing.xs)

            Button(primaryActionTitle, action: primaryAction)
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 38, cornerRadius: WayTaskDesign.Radius.sm))

            WayTaskIconButton(systemName: "xmark", action: dismissAction)
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.xl)
    }

    private var recentProductsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Recent products", actionTitle: "See all") {
                appStateManager.selectedTab = .products
            }

            if recentProductCards.isEmpty {
                WayTaskEmptyState(
                    title: "No recent products",
                    message: "Scanned or added products will appear here.",
                    systemImage: "shippingbox"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        ForEach(recentProductCards) { product in
                            WayTaskCompactProductCard(
                                title: product.title,
                                subtitle: product.subtitle,
                                imageData: product.imageData,
                                imageURL: product.imageURL,
                                actionSystemImage: "plus"
                            ) {
                                appStateManager.selectedTab = .products
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "This month")

            HStack(spacing: WayTaskDesign.Spacing.sm) {
                WayTaskMetricCard(value: "\(completedTripsThisMonth)", title: "Trips", systemImage: "figure.walk")
                WayTaskMetricCard(value: "\(itemsAddedThisMonth)", title: "Items", systemImage: "basket.fill")
                WayTaskMetricCard(value: "\(productLibraryCount)", title: "Products", systemImage: "shippingbox.fill")
            }
        }
    }

    private var activeItems: [ShoppingItem] {
        if !shoppingListEntries.isEmpty {
            return selectedShoppingEntries
                .filter { !$0.isChecked }
                .compactMap(legacyItem)
                .filter { !$0.isCompleted }
        }

        return items.filter { !$0.isCompleted }
    }

    private var activeItemCount: Int {
        activeItems.count
    }

    private var homeShoppingItemCount: Int {
        activeSession?.remainingItemCount ?? activeItemCount
    }

    private var homeShoppingTotalCount: Int {
        activeSession?.itemIDs.count ?? activeItemCount
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

    private var tripProgress: Double {
        guard let activeSession, !activeSession.itemIDs.isEmpty else {
            return 0
        }

        return Double(activeSession.collectedItemIDs.count) / Double(activeSession.itemIDs.count)
    }

    private var bestCoverage: StoreCoverage? {
        appStateManager.shoppingPlanState.isReady ? appStateManager.shoppingPlan?.bestCoverage : nil
    }

    private var homePlanItems: [ShoppingItem] {
        appStateManager.shoppingPlan?.items ?? activeItems
    }

    private func recommendationTitle(for group: ShoppingIntentGroup) -> String {
        switch group {
        case .grocery:
            return "Recommended Grocery Store"
        case .electronics:
            return "Recommended Electronics Store"
        case .pet:
            return "Recommended Pet Store"
        case .pharmacy:
            return "Recommended Pharmacy"
        case .other:
            return "Recommended Store"
        }
    }

    private var shoppingListSummaries: [HomeShoppingListSummary] {
        if !shoppingLists.isEmpty {
            let sortedLists = shoppingLists.sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }

                return lhs.createdAt < rhs.createdAt
            }

            return sortedLists.map { list in
                let entries = shoppingListEntries.filter { $0.shoppingListID == list.id }
                let neededCount = entries.filter { !$0.isChecked }.count
                let completedCount = entries.filter(\.isChecked).count

                return HomeShoppingListSummary(
                    id: list.id.uuidString,
                    title: list.title,
                    itemCount: neededCount,
                    completedCount: completedCount,
                    subtitle: neededCount == 0 ? "No open items" : "\(neededCount) open items",
                    isActive: list.id == selectedShoppingListID
                )
            }
        }

        let completed = items.filter(\.isCompleted)
        let recent = items
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(8)

        return [
            HomeShoppingListSummary(
                id: "weekly-shopping",
                title: "Weekly Shopping",
                itemCount: activeItemCount,
                completedCount: collectedCount,
                subtitle: activeItemCount == 0 ? "No open items" : "\(activeItemCount) open items",
                isActive: true
            ),
            HomeShoppingListSummary(
                id: "completed",
                title: "Completed",
                itemCount: completed.count,
                completedCount: completed.count,
                subtitle: "Finished items",
                isActive: false
            ),
            HomeShoppingListSummary(
                id: "recent",
                title: "Recent",
                itemCount: recent.count,
                completedCount: recent.filter(\.isCompleted).count,
                subtitle: "Recently added",
                isActive: false
            )
        ]
    }

    private var planRows: [HomePlanRow] {
        cachedPlanRows
    }

    private var recentProductCards: [HomeProductCardData] {
        cachedRecentProductCards
    }

    private var homePrimaryActionTitle: String {
        if activeSession != nil {
            return "Resume Shopping"
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return "Planning..."
        case .ready:
            return "Start Shopping"
        case .failed:
            return "Open Shopping"
        case .idle, .stale:
            return activeItemCount == 0 ? "Add Products" : "Open Shopping"
        }
    }

    private var homePrimaryActionImage: String? {
        if activeSession != nil {
            return "cart.fill"
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return "hourglass"
        case .ready:
            return "play.fill"
        case .failed:
            return "exclamationmark.triangle"
        case .idle, .stale:
            return activeItemCount == 0 ? "shippingbox.fill" : "list.bullet.rectangle.fill"
        }
    }

    private var isHomePrimaryDisabled: Bool {
        activeSession == nil && appStateManager.shoppingPlanState.isGenerating
    }

    private var homePlanStatusTitle: String {
        switch appStateManager.shoppingPlanState {
        case .generating:
            return "Planning your shopping"
        case .failed:
            return "Plan failed"
        case .stale:
            return "Plan needs updating"
        case .ready:
            return "Plan not ready yet"
        case .idle:
            return "Plan not ready yet"
        }
    }

    private var homePlanStatusMessage: String {
        switch appStateManager.shoppingPlanState {
        case let .generating(_, startedAt):
            let elapsedSeconds = max(Int(homeNow.timeIntervalSince(startedAt)), 0)
            let stage = appStateManager.shoppingPlanState.stageTitle ?? "Preparing your shopping list"
            return "\(elapsedSeconds) seconds elapsed - \(stage)"
        case let .failed(message, _):
            return message
        case let .stale(reason):
            return reason
        case .ready:
            return "Open Shopping to review the latest plan."
        case .idle:
            return activeItemCount == 0 ? "Add shopping items to build a plan." : "Open Shopping to generate a plan from your current list."
        }
    }

    private var homeItemPresentationSignature: String {
        items
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.brand ?? "",
                    $0.category ?? "",
                    String($0.dateAdded.timeIntervalSince1970),
                    $0.isCompleted ? "1" : "0",
                    $0.imageURL?.absoluteString ?? "",
                    String($0.imageData?.count ?? 0)
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private var productPresentationSignature: String {
        products
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.brand ?? "",
                    $0.category ?? "",
                    String($0.dateAdded.timeIntervalSince1970),
                    String($0.updatedAt.timeIntervalSince1970),
                    $0.imageURL?.absoluteString ?? "",
                    String($0.imageData?.count ?? 0)
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ";")
    }

    private func refreshHomePresentationCache() {
        refreshPlanRowsCache()
        refreshRecentProductCardsCache()
    }

    private func refreshPlanRowsCache() {
        guard appStateManager.shoppingPlanState.isReady,
              let plan = appStateManager.shoppingPlan else {
            cachedPlanRows = []
            return
        }

        cachedPlanRows = plan.shoppingTripCoverages.prefix(3).enumerated().map { index, coverage in
            return HomePlanRow(
                id: coverage.id,
                storeName: coverage.store.title,
                recommendationTitle: recommendationTitle(for: coverage.group),
                likelyItemNames: coverage.matchedItems.map(\.name),
                totalItemCount: plan.items.count,
                distanceText: coverage.distance.map(distanceText(for:)),
                isHighlighted: index == 0
            )
        }
    }

    private func refreshRecentProductCardsCache() {
        if !products.isEmpty {
            cachedRecentProductCards = products
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(8)
                .map {
                    HomeProductCardData(
                        id: $0.id,
                        title: $0.name,
                        subtitle: $0.brand ?? $0.category ?? "Product",
                        imageData: $0.imageData,
                        imageURL: $0.imageURL
                    )
                }
            return
        }

        cachedRecentProductCards = items
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(8)
            .map {
                HomeProductCardData(
                    id: $0.id,
                    title: $0.name,
                    subtitle: $0.brand ?? $0.category ?? "Product",
                    imageData: $0.imageData,
                    imageURL: $0.imageURL
                )
            }
    }

    private var completedTripsThisMonth: Int {
        shoppingSessions.filter { session in
            guard let finishedAt = session.finishedAt else {
                return false
            }

            return Calendar.current.isDate(finishedAt, equalTo: Date(), toGranularity: .month)
        }
        .count
    }

    private var itemsAddedThisMonth: Int {
        if !products.isEmpty {
            return products.filter { Calendar.current.isDate($0.dateAdded, equalTo: Date(), toGranularity: .month) }.count
        }

        return items.filter { Calendar.current.isDate($0.dateAdded, equalTo: Date(), toGranularity: .month) }.count
    }

    private var productLibraryCount: Int {
        products.isEmpty ? items.count : products.count
    }

    private var selectedShoppingListID: UUID? {
        appStateManager.selectedShoppingListID ??
            appStateManager.currentShoppingListID ??
            shoppingLists.first { $0.kind == .weekly }?.id
    }

    private var selectedShoppingEntries: [ShoppingListEntry] {
        guard let selectedShoppingListID else {
            return []
        }

        return shoppingListEntries.filter { $0.shoppingListID == selectedShoppingListID }
    }

    private func legacyItem(for entry: ShoppingListEntry) -> ShoppingItem? {
        guard let legacyShoppingItemID = entry.legacyShoppingItemID else {
            return nil
        }

        return items.first { $0.id == legacyShoppingItemID }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var dateLabel: String {
        Date()
            .formatted(.dateTime.weekday(.wide).day().month(.wide))
            .uppercased()
    }

    private func handleHomePrimaryAction() {
        if activeSession != nil {
            appStateManager.selectedTab = .shopping
            return
        }

        if activeItemCount == 0 {
            appStateManager.selectedTab = .products
            return
        }

        appStateManager.selectedTab = .shopping
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

private struct HomeShoppingListSummary: Identifiable {
    let id: String
    let title: String
    let itemCount: Int
    let completedCount: Int
    let subtitle: String
    let isActive: Bool
}

private struct HomePlanRow: Identifiable {
    let id: String
    let storeName: String
    let recommendationTitle: String
    let likelyItemNames: [String]
    let totalItemCount: Int
    let distanceText: String?
    let isHighlighted: Bool
}

private struct HomeProductCardData: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    var imageData: Data?
    var imageURL: URL?
}
