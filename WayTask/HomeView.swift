import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager

    @Query private var items: [ShoppingItem]
    @Query private var shoppingSessions: [ShoppingSession]

    @State private var isShowingScanner = false
    @State private var isSampleNearbyHidden = false

    private let shoppingSessionService = ShoppingSessionService()

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
        }
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

            HStack(spacing: WayTaskDesign.Spacing.xs) {
                WayTaskIconButton(systemName: "barcode.viewfinder") {
                    isShowingScanner = true
                }

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
            }
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

                WayTaskBadge(title: bestStoreOpenLabel, systemImage: "circle.fill", tone: bestStoreOpenTone)
            }

            Text("\(displayItemCount) \(displayItemCount == 1 ? "item" : "items") to buy")
                .font(WayTaskDesign.Typography.title)
                .foregroundStyle(WayTaskDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            HStack(alignment: .center, spacing: WayTaskDesign.Spacing.md) {
                WayTaskCoverageRing(progress: bestCoverageProgress, size: 70, lineWidth: 7)

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
                    Text("\(bestStoreName) - best store")
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    HStack(spacing: WayTaskDesign.Spacing.xs) {
                        WayTaskBadge(title: bestStoreTimeText, systemImage: "clock", tone: .neutral)
                        WayTaskBadge(title: bestStoreDistanceText, systemImage: "location", tone: .neutral)
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                HStack {
                    Text("Trip progress")
                    Spacer()
                    Text("\(collectedCount) of \(max(activeItemCount, collectedCount)) collected")
                }
                .font(WayTaskDesign.Typography.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)

                ProgressView(value: tripProgress)
                    .tint(WayTaskDesign.accent)
            }

            WayTaskPrimaryButton("Start Shopping", systemImage: "play.fill") {
                startShopping()
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
            WayTaskSectionHeader(title: "Best shopping plan", actionTitle: "See all") {
                appStateManager.selectedTab = .shopping
            }

            VStack(spacing: WayTaskDesign.Spacing.sm) {
                ForEach(planRows) { row in
                    WayTaskStoreCard(
                        title: row.storeName,
                        subtitle: row.subtitle,
                        distanceText: row.distanceText,
                        coverage: row.coverage,
                        confidenceText: row.confidenceText,
                        isBestMatch: row.isBestMatch
                    ) {
                        appStateManager.selectedTab = .shopping
                    }
                }
            }
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
        } else if !isSampleNearbyHidden {
            nearbyCard(
                title: "Coffee",
                subtitle: "AM:PM Express - 300 m",
                primaryActionTitle: "Add",
                primaryAction: { appStateManager.selectedTab = .products },
                dismissAction: { isSampleNearbyHidden = true }
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

    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "This month")

            HStack(spacing: WayTaskDesign.Spacing.sm) {
                WayTaskMetricCard(value: "\(completedTripsThisMonth)", title: "Trips", systemImage: "figure.walk")
                WayTaskMetricCard(value: "\(itemsAddedThisMonth)", title: "Items", systemImage: "basket.fill")
                WayTaskMetricCard(value: "\(items.count)", title: "Products", systemImage: "shippingbox.fill")
            }
        }
    }

    private var activeItems: [ShoppingItem] {
        items.filter { !$0.isCompleted }
    }

    private var activeItemCount: Int {
        activeItems.count
    }

    private var displayItemCount: Int {
        activeItemCount == 0 ? 7 : activeItemCount
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
        appStateManager.shoppingTripCoverages.first
    }

    private var bestCoverageProgress: Double {
        bestCoverage?.coverageScore ?? 0.72
    }

    private var bestStoreName: String {
        bestCoverage?.store.title ?? appStateManager.buyingOptions.first?.storeName ?? "Rami Levy"
    }

    private var bestStoreDistanceText: String {
        if let distance = bestCoverage?.distance {
            return distanceText(for: distance)
        }

        if let distance = appStateManager.buyingOptions.first?.distanceText, !distance.isEmpty {
            return distance
        }

        return "2.2 km"
    }

    private var bestStoreTimeText: String {
        if let bestCoverage {
            return "\(max(bestCoverage.matchedItemCount * 3, 4)) min"
        }

        return "15 min"
    }

    private var bestStoreOpenLabel: String {
        bestCoverage?.store.isOpen == false ? "Closed" : "Open now"
    }

    private var bestStoreOpenTone: WayTaskBadge.Tone {
        bestCoverage?.store.isOpen == false ? .danger : .success
    }

    private var shoppingListSummaries: [HomeShoppingListSummary] {
        let completed = items.filter(\.isCompleted)
        let recent = items
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(8)

        return [
            HomeShoppingListSummary(
                title: "Weekly Shopping",
                itemCount: max(activeItemCount, displayItemCount),
                completedCount: collectedCount,
                subtitle: activeItemCount == 0 ? "Sample v1.0 list" : "\(activeItemCount) open items",
                isActive: true
            ),
            HomeShoppingListSummary(
                title: "Completed",
                itemCount: completed.count,
                completedCount: completed.count,
                subtitle: "Finished items",
                isActive: false
            ),
            HomeShoppingListSummary(
                title: "Recent",
                itemCount: recent.count,
                completedCount: recent.filter(\.isCompleted).count,
                subtitle: "Recently added",
                isActive: false
            )
        ]
    }

    private var planRows: [HomePlanRow] {
        let realRows = appStateManager.shoppingTripCoverages.prefix(3).enumerated().map { index, coverage in
            HomePlanRow(
                storeName: coverage.store.title,
                subtitle: "\(coverage.matchedItemCount)/\(coverage.matchedItemCount + coverage.missingItemCount) items - \(coverage.group.displayName)",
                distanceText: coverage.distance.map(distanceText(for:)),
                coverage: coverage.coverageScore,
                confidenceText: coverage.ranking.confidenceLabel,
                isBestMatch: index == 0
            )
        }

        if !realRows.isEmpty {
            return realRows
        }

        return [
            HomePlanRow(storeName: "Rami Levy", subtitle: "5/7 items - Supermarket", distanceText: "2.2 km", coverage: 0.72, confidenceText: "High confidence", isBestMatch: true),
            HomePlanRow(storeName: "Shufersal Deal", subtitle: "3/7 items - Supermarket", distanceText: "1.4 km", coverage: 0.48, confidenceText: "Good match", isBestMatch: false),
            HomePlanRow(storeName: "AM:PM Express", subtitle: "2/7 items - Convenience", distanceText: "600 m", coverage: 0.22, confidenceText: "Possible match", isBestMatch: false)
        ]
    }

    private var recentProductCards: [HomeProductCardData] {
        let realProducts = items
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(8)
            .map {
                HomeProductCardData(
                    title: $0.name,
                    subtitle: $0.brand ?? $0.category ?? "Product",
                    imageData: $0.imageData,
                    imageURL: $0.imageURL
                )
            }

        if !realProducts.isEmpty {
            return Array(realProducts)
        }

        return [
            HomeProductCardData(title: "Milk", subtitle: "Tnuva"),
            HomeProductCardData(title: "Coffee", subtitle: "Elite"),
            HomeProductCardData(title: "Protein Shake", subtitle: "Optimum"),
            HomeProductCardData(title: "USB-C Cable", subtitle: "Anker")
        ]
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
        items.filter { Calendar.current.isDate($0.dateAdded, equalTo: Date(), toGranularity: .month) }.count
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

    private func startShopping() {
        guard !activeItems.isEmpty else {
            appStateManager.selectedTab = .products
            return
        }

        do {
            try shoppingSessionService.startShopping(with: activeItems, in: modelContext)
            appStateManager.selectedTab = .products
        } catch {
            assertionFailure("Failed to start shopping session: \(error.localizedDescription)")
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
    let id = UUID()
    let title: String
    let itemCount: Int
    let completedCount: Int
    let subtitle: String
    let isActive: Bool
}

private struct HomePlanRow: Identifiable {
    let id = UUID()
    let storeName: String
    let subtitle: String
    let distanceText: String?
    let coverage: Double
    let confidenceText: String
    let isBestMatch: Bool
}

private struct HomeProductCardData: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    var imageData: Data?
    var imageURL: URL?
}
