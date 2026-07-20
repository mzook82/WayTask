import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ShoppingWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var items: [ShoppingItem]
    @Query private var locations: [GeoLocation]
    @Query private var shoppingSessions: [ShoppingSession]
    @Query private var products: [Product]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]

    @State private var selectedListID = ""
    @State private var searchText = ""
    @State private var isShowingPlanSheet = false
    @State private var isShowingProductChooser = false
    @State private var selectedStoreID: UUID?
    @State private var shoppingFlowErrorMessage = ""
    @State private var isShowingShoppingFlowError = false
    @State private var cachedRecommendedStoreRows: [ShoppingWorkspaceStoreRow] = []
    @State private var cachedGroupedProductRows: [ShoppingWorkspaceGroup] = []
    @State private var planningElapsedSeconds = 0
    @State private var planningTimerTask: Task<Void, Never>?

    private let intentMatcher = ShoppingIntentMatcher()
    private let buyingOptionsService = BuyingOptionsService()
    private let shoppingTripPlanningService = ShoppingTripService()
    private let shoppingSessionService = ShoppingSessionService()
    private let shoppingListService = ShoppingListService()
    private let storeResolutionEngine = StoreResolutionEngine.shared
    private let planningTimeoutSeconds: TimeInterval = 30

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                if let activeSession {
                    activeShoppingContent(for: activeSession)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xl) {
                            header
                            listSelector
                            chooseProductsPanel
                            recommendedStoresSection
                            coverageCardsSection
                            groupedProductsSection
                        }
                        .padding(.horizontal, WayTaskDesign.Spacing.lg)
                        .padding(.top, WayTaskDesign.Spacing.md)
                        .padding(.bottom, 118)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let activeSession {
                    activeShoppingBar(for: activeSession)
                } else {
                    startShoppingBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingPlanSheet) {
                planBottomSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $isShowingProductChooser) {
                ProductShoppingSelectionSheet(
                    title: "Choose products",
                    subtitle: "Add products from your permanent library to the selected shopping list.",
                    preferredShoppingListID: selectedShoppingListID,
                    showsSkipAction: false,
                    onComplete: {
                        isShowingProductChooser = false
                        refreshShoppingPresentationCache()
                    },
                    onSkip: {
                        isShowingProductChooser = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Shopping", isPresented: $isShowingShoppingFlowError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shoppingFlowErrorMessage)
            }
            .onAppear {
                syncSelectedListIfNeeded()
                refreshShoppingPresentationCache()
            }
            .onChange(of: appStateManager.shoppingPlan?.id) {
                selectedStoreID = nil
                refreshRecommendedStoreRowsCache()
            }
            .onChange(of: appStateManager.shoppingPlanState) { _, state in
                handlePlanStateChange(state)
                refreshRecommendedStoreRowsCache()
            }
            .onChange(of: shoppingWorkspaceItemPresentationSignature) {
                refreshGroupedProductRowsCache()
            }
            .onChange(of: searchText) {
                refreshGroupedProductRowsCache()
            }
            .onChange(of: selectedListID) {
                refreshShoppingPresentationCache()
            }
            .onChange(of: shoppingListEntrySignature) {
                syncSelectedListIfNeeded()
                refreshShoppingPresentationCache()
            }
            .onChange(of: shoppingListSignature) {
                syncSelectedListIfNeeded()
                refreshShoppingPresentationCache()
            }
        }
        .onDisappear {
            stopPlanningTimer()
        }
    }

    private func activeShoppingContent(for session: ShoppingSession) -> some View {
        let sessionItems = shoppingSessionItems(for: session)
        let sessionItemIDs = Set(session.itemIDs)
        let collectedCount = session.collectedItemIDs.filter { sessionItemIDs.contains($0) }.count
        let totalCount = session.itemIDs.count
        let remainingCount = max(totalCount - collectedCount, 0)
        let progress = totalCount == 0 ? 0 : Double(collectedCount) / Double(totalCount)

        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xl) {
                WayTaskScreenHeader(
                    title: "Shopping Mode",
                    subtitle: "\(remainingCount) remaining - \(collectedCount)/\(totalCount) collected",
                    trailingIcons: ["cart.fill"]
                )

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
                    HStack(alignment: .center, spacing: WayTaskDesign.Spacing.md) {
                        WayTaskProgressRing(progress: progress, size: 62, lineWidth: 7)

                        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                            Text("Active shopping session")
                                .font(WayTaskDesign.Typography.headline)
                                .foregroundStyle(WayTaskDesign.primaryText)

                            Text(totalCount == 0 ? "No session products are available on this device." : "Collect products as you shop.")
                                .font(WayTaskDesign.Typography.caption)
                                .foregroundStyle(WayTaskDesign.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: WayTaskDesign.Spacing.xs)
                    }

                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        WayTaskMetricCard(value: "\(collectedCount)", title: "Collected", systemImage: "checkmark.circle.fill")
                        WayTaskMetricCard(value: "\(remainingCount)", title: "Remaining", systemImage: "list.bullet")
                        WayTaskMetricCard(value: "\(totalCount)", title: "Total", systemImage: "basket.fill")
                    }
                }
                .padding(WayTaskDesign.Spacing.md)
                .wayTaskGlassCard(highlighted: true)

                activeSessionStoreCard(for: session)
                activeSessionItemsSection(for: session, items: sessionItems)
            }
            .padding(.horizontal, WayTaskDesign.Spacing.lg)
            .padding(.top, WayTaskDesign.Spacing.md)
            .padding(.bottom, 118)
        }
    }

    private func activeSessionStoreCard(for session: ShoppingSession) -> some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Selected store")

            HStack(alignment: .top, spacing: WayTaskDesign.Spacing.md) {
                Image(systemName: "storefront.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
                    .frame(width: 48, height: 48)
                    .background(WayTaskDesign.accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.selectedStoreName ?? "Store unavailable")
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text(canNavigate(to: session) ? "Ready to open turn-by-turn directions in Apple Maps." : "Navigation is unavailable for this session. You can still collect products and finish normally.")
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)
            }
            .padding(WayTaskDesign.Spacing.md)
            .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.lg)
        }
    }

    private func activeSessionItemsSection(for session: ShoppingSession, items sessionItems: [ShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Shopping list", subtitle: "Tap a product to collect or undo")

            if sessionItems.isEmpty {
                WayTaskEmptyState(
                    title: "No session products available",
                    message: "The saved session can still be finished, but its products are no longer available on this device.",
                    systemImage: "basket"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(sessionItems) { item in
                        let isCollected = session.isCollected(item)

                        Button {
                            toggleCollected(item, in: session)
                        } label: {
                            HStack(spacing: WayTaskDesign.Spacing.sm) {
                                Image(systemName: isCollected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(isCollected ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                                    .frame(width: 44, height: 44)

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
                                        .strikethrough(isCollected)
                                        .lineLimit(1)

                                    Text(isCollected ? "Collected" : (item.brand ?? item.category ?? "Ready to collect"))
                                        .font(WayTaskDesign.Typography.caption)
                                        .foregroundStyle(WayTaskDesign.tertiaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: WayTaskDesign.Spacing.xs)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, WayTaskDesign.Spacing.xs)
                            .opacity(isCollected ? 0.58 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isCollected ? "Mark \(item.name) remaining" : "Mark \(item.name) collected")
                        .accessibilityValue(isCollected ? "Collected" : "Remaining")

                        if item.id != sessionItems.last?.id {
                            Divider()
                                .overlay(WayTaskDesign.surfaceBorder)
                        }
                    }
                }
                .padding(.horizontal, WayTaskDesign.Spacing.md)
                .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.xl)
            }
        }
    }

    private func activeShoppingBar(for session: ShoppingSession) -> some View {
        HStack(spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSecondaryButton("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill", isDisabled: !canNavigate(to: session)) {
                navigateToSelectedStore(for: session)
            }

            WayTaskPrimaryButton("Finish Shopping", systemImage: "checkmark.circle.fill") {
                finishShopping(session)
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

    private var header: some View {
        WayTaskScreenHeader(
            title: "Shopping",
            subtitle: "\(selectedListTitle) - \(displayItemCount) \(displayItemCount == 1 ? "item" : "items") - \(recommendedStoreCount) stores",
            trailingIcons: ["cart.fill"]
        )
    }

    private var listSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WayTaskDesign.Spacing.xs) {
                ForEach(listChips) { chip in
                    WayTaskFilterChip(title: "\(chip.title) \(chip.count)", isSelected: chip.id == selectedListID) {
                        selectedListID = chip.id
                        appStateManager.selectedShoppingListID = UUID(uuidString: chip.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var chooseProductsPanel: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
            HStack(alignment: .top, spacing: WayTaskDesign.Spacing.md) {
                Image(systemName: "cart.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
                    .frame(width: 44, height: 44)
                    .background(WayTaskDesign.accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose products")
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text("Products stay in your library. Shopping contains only what you choose for this trip.")
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)
            }

            WayTaskPrimaryButton("Choose Products", systemImage: "cart.badge.plus") {
                isShowingProductChooser = true
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(highlighted: workspaceItems.isEmpty)
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
                WayTaskMetricCard(value: "\(displayItemCount)", title: "Open", systemImage: "basket.fill")
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

            switch appStateManager.shoppingPlanState {
            case .generating:
                planningStatusCard
            case let .failed(message, actionTitle):
                WayTaskEmptyState(
                    title: "Plan failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: actionTitle,
                    action: actionTitle == nil ? nil : { handlePlanFailureAction(actionTitle) }
                )
            case .ready where recommendedStoreRows.first != nil:
                if let recommendedStore = recommendedStoreRows.first {
                    WayTaskRecommendationCard(
                        recommendationTitle: recommendedStore.recommendationTitle,
                        storeName: recommendedStore.storeName,
                        likelyItemNames: recommendedStore.likelyItemNames,
                        otherItemNames: recommendedStore.otherItemNames,
                        totalItemCount: recommendedStore.totalItemCount,
                        hasProductCoverageEstimate: recommendedStore.hasProductCoverageEstimate,
                        distanceText: recommendedStore.distanceText,
                        isHighlighted: recommendedStore.isPrimaryRecommendation,
                        isSelected: isStoreSelected(recommendedStore),
                        actionTitle: isStoreSelected(recommendedStore) ? "Selected Store" : "Select Store"
                    ) {
                        selectStore(recommendedStore)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WayTaskDesign.Radius.xl, style: .continuous)
                            .stroke(isStoreSelected(recommendedStore) ? WayTaskDesign.accent : Color.clear, lineWidth: 2)
                    }
                }
            default:
                planNotReadyState
            }
        }
    }

    private var planningStatusCard: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
            HStack(spacing: WayTaskDesign.Spacing.sm) {
                ProgressView()
                    .tint(WayTaskDesign.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Planning your shopping...")
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text("\(planningElapsedSeconds) seconds elapsed")
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)
            }

            Text(appStateManager.shoppingPlanState.stageTitle ?? ShoppingPlanGenerationStage.preparingList.title)
                .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(highlighted: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Planning your shopping. \(planningElapsedSeconds) seconds elapsed. \(appStateManager.shoppingPlanState.stageTitle ?? ShoppingPlanGenerationStage.preparingList.title).")
    }

    private var planNotReadyState: some View {
        WayTaskEmptyState(
            title: planNotReadyTitle,
            message: planNotReadyMessage,
            systemImage: "storefront",
            actionTitle: planNotReadyActionTitle,
            action: planNotReadyActionTitle == nil ? nil : {
                generateShoppingPlan()
                isShowingPlanSheet = true
            }
        )
    }

    private var planNotReadyTitle: String {
        switch appStateManager.shoppingPlanState {
        case .stale:
            return "Plan needs updating"
        default:
            return "Plan not ready yet"
        }
    }

    private var planNotReadyMessage: String {
        switch appStateManager.shoppingPlanState {
        case let .stale(reason):
            return reason
        default:
            return activeItems.isEmpty ? "Add products to generate a shopping plan." : "Generate a plan from your current shopping list."
        }
    }

    private var planNotReadyActionTitle: String? {
        activeItems.isEmpty ? nil : "Generate plan"
    }


    @ViewBuilder
    private var coverageCardsSection: some View {
        let additionalRows = Array(recommendedStoreRows.dropFirst())

        if !additionalRows.isEmpty {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
                WayTaskSectionHeader(title: "Other recommended stores")

                VStack(spacing: WayTaskDesign.Spacing.sm) {
                    ForEach(additionalRows) { row in
                        WayTaskRecommendationCard(
                            recommendationTitle: row.recommendationTitle,
                            storeName: row.storeName,
                            likelyItemNames: row.likelyItemNames,
                            otherItemNames: row.otherItemNames,
                            totalItemCount: row.totalItemCount,
                            hasProductCoverageEstimate: row.hasProductCoverageEstimate,
                            distanceText: row.distanceText,
                            isHighlighted: row.isPrimaryRecommendation,
                            isSelected: isStoreSelected(row),
                            actionTitle: isStoreSelected(row) ? "Selected Store" : "Select Store"
                        ) {
                            selectStore(row)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: WayTaskDesign.Radius.xl, style: .continuous)
                                .stroke(isStoreSelected(row) ? WayTaskDesign.accent : Color.clear, lineWidth: 2)
                        }
                    }
                }
            }
        }
    }

    private var groupedProductsSection: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            WayTaskSectionHeader(title: "Your list", subtitle: "Grouped by store intent", actionTitle: "Choose products") {
                isShowingProductChooser = true
            }

            WayTaskSearchField(placeholder: "Search shopping list", text: $searchText)

            VStack(spacing: WayTaskDesign.Spacing.md) {
                if groupedProductRows.isEmpty {
                    WayTaskEmptyState(
                        title: workspaceItems.isEmpty ? "No products selected" : "No matching items",
                        message: workspaceItems.isEmpty ? "Choose products to begin planning your shopping trip." : "Clear search to see the current shopping list.",
                        systemImage: workspaceItems.isEmpty ? "basket" : "magnifyingglass",
                        actionTitle: workspaceItems.isEmpty ? "Choose products" : nil,
                        action: workspaceItems.isEmpty ? { isShowingProductChooser = true } : nil
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
                    HStack(alignment: .top, spacing: WayTaskDesign.Spacing.sm) {
                        Button {
                            toggleEntryChecked(item)
                        } label: {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(item.isChecked ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isChecked ? "Mark \(item.name) needed" : "Mark \(item.name) checked")
                        .accessibilityValue(item.isChecked ? "Checked" : "Needed")

                        WayTaskProductThumbnail(
                            data: item.imageData,
                            url: item.imageURL,
                            size: 42,
                            cornerRadius: WayTaskDesign.Radius.sm
                        )

                        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                                    .foregroundStyle(WayTaskDesign.primaryText)
                                    .strikethrough(item.isChecked)
                                    .lineLimit(2)

                                Text(item.subtitle)
                                    .font(WayTaskDesign.Typography.caption)
                                    .foregroundStyle(WayTaskDesign.tertiaryText)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 4) {
                                Button {
                                    adjustQuantity(for: item, delta: -1)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .disabled(item.quantity <= 1)
                                .opacity(item.quantity <= 1 ? 0.35 : 1)
                                .accessibilityLabel("Decrease \(item.name) quantity to \(quantityText(max(1, item.quantity - 1)))")

                                Text(quantityText(item.quantity))
                                    .font(WayTaskDesign.Typography.captionStrong)
                                    .foregroundStyle(WayTaskDesign.secondaryText)
                                    .frame(minWidth: 24)

                                Button {
                                    adjustQuantity(for: item, delta: 1)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Increase \(item.name) quantity to \(quantityText(item.quantity + 1))")

                                Spacer(minLength: WayTaskDesign.Spacing.xs)

                                Button {
                                    removeEntry(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(WayTaskDesign.Colors.danger)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(item.name) from Shopping")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, WayTaskDesign.Spacing.xs)
                    .opacity(item.isChecked ? 0.58 : 1)

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
                WayTaskPrimaryButton(bottomPrimaryTitle, systemImage: bottomPrimarySystemImage, isDisabled: isBottomPrimaryDisabled) {
                    handleBottomPrimaryAction()
                }

                if canViewMapPlan {
                    WayTaskSecondaryButton("View Map", systemImage: "map.fill") {
                        openPlanOnMap()
                    }
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
                switch appStateManager.shoppingPlanState {
                case .generating:
                    planningStatusCard
                case let .failed(message, actionTitle):
                    WayTaskEmptyState(
                        title: "Plan failed",
                        message: message,
                        systemImage: "exclamationmark.triangle",
                        actionTitle: actionTitle,
                        action: actionTitle == nil ? nil : { handlePlanFailureAction(actionTitle) }
                    )
                case .ready where !recommendedStoreRows.isEmpty:
                    ForEach(recommendedStoreRows) { row in
                        WayTaskRecommendationCard(
                            recommendationTitle: row.recommendationTitle,
                            storeName: row.storeName,
                            likelyItemNames: row.likelyItemNames,
                            otherItemNames: row.otherItemNames,
                            totalItemCount: row.totalItemCount,
                            hasProductCoverageEstimate: row.hasProductCoverageEstimate,
                            distanceText: row.distanceText,
                            isHighlighted: row.isPrimaryRecommendation,
                            isSelected: isStoreSelected(row),
                            actionTitle: isStoreSelected(row) ? "Selected Store" : "Select Store"
                        ) {
                            selectStore(row)
                        }
                    }

                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        WayTaskSecondaryButton("View Map", systemImage: "map.fill") {
                            isShowingPlanSheet = false
                            openPlanOnMap()
                        }

                        WayTaskPrimaryButton("Start Shopping", systemImage: "play.fill", isDisabled: !canStartShopping) {
                            isShowingPlanSheet = false
                            startShopping()
                        }
                    }
                default:
                    planNotReadyState
                }
            }
        }
    }

    private var activeItems: [ShoppingItem] {
        selectedShoppingListItems(includeChecked: false)
    }

    private var activeItemCount: Int {
        activeItems.count
    }

    private var workspaceItems: [ShoppingItem] {
        selectedShoppingListItems(includeChecked: true)
    }

    private var displayItemCount: Int {
        workspaceItems.count
    }

    private var filteredActiveItems: [ShoppingItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return workspaceItems
        }

        return workspaceItems.filter {
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
        let sortedLists = shoppingLists.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }

            return lhs.createdAt < rhs.createdAt
        }

        return sortedLists.map { list in
            ShoppingWorkspaceListChip(
                id: list.id.uuidString,
                title: list.title,
                count: shoppingListEntries.filter { $0.shoppingListID == list.id && !$0.isChecked }.count
            )
        }
    }

    private var recommendedStoreRows: [ShoppingWorkspaceStoreRow] {
        cachedRecommendedStoreRows
    }

    private var realBuyingOptionRows: [ShoppingWorkspaceStoreRow] {
        guard let plan = appStateManager.shoppingPlan else {
            return []
        }

        var seenStoreIDs = Set<UUID>()
        let matchedOptions = appStateManager.buyingOptions
            .filter(\.isDisplayableRealStore)
            .compactMap { option -> (option: BuyingOption, store: MapStore)? in
                let store = plan.stores.first {
                    $0.sourceType == option.source &&
                        $0.title.localizedCaseInsensitiveCompare(option.storeName) == .orderedSame
                } ?? plan.stores.first {
                    $0.title.localizedCaseInsensitiveCompare(option.storeName) == .orderedSame
                }

                guard let store, seenStoreIDs.insert(store.id).inserted else {
                    return nil
                }

                return (option, store)
            }
            .prefix(4)

        return matchedOptions
            .enumerated()
            .map { index, match in
                ShoppingWorkspaceStoreRow(
                    id: "option-\(match.option.source.rawValue)-\(match.option.optionType.rawValue)-\(match.store.id.uuidString)",
                    storeID: match.store.id,
                    storeName: match.option.storeName,
                    recommendationTitle: "Recommended Store",
                    likelyItemNames: [],
                    otherItemNames: plan.items.map(\.name),
                    totalItemCount: plan.items.count,
                    hasProductCoverageEstimate: false,
                    distanceText: match.option.distanceText,
                    isPrimaryRecommendation: index == 0
                )
            }
    }

    private var recommendedStoreCount: Int {
        recommendedStoreRows.count
    }

    private var canOpenMapPlan: Bool {
        !activeItems.isEmpty || !appStateManager.shoppingTripCoverages.isEmpty || !recommendedStoreRows.isEmpty
    }

    private var canViewMapPlan: Bool {
        appStateManager.shoppingPlanState.isReady && isCurrentShoppingPlanForActiveItems && !recommendedStoreRows.isEmpty
    }

    private var canStartShopping: Bool {
        selectedShoppingListID != nil && selectedStore != nil && !activeItems.isEmpty && canViewMapPlan
    }

    private var selectedStore: MapStore? {
        guard let selectedStoreID,
              let plan = appStateManager.shoppingPlan else {
            return nil
        }

        return plan.stores.first { $0.id == selectedStoreID }
    }

    private var bottomPrimaryTitle: String {
        if activeItems.isEmpty {
            return "Choose Products"
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return planningElapsedSeconds > 0 ? "Planning... \(planningElapsedSeconds)s" : "Planning..."
        case .ready:
            return "Start Shopping"
        case .failed:
            return "Try Again"
        case .idle, .stale:
            return "Generate Plan"
        }
    }

    private var bottomPrimarySystemImage: String? {
        if activeItems.isEmpty {
            return "cart.badge.plus"
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return "hourglass"
        case .ready:
            return "play.fill"
        case .failed:
            return "arrow.clockwise"
        case .idle, .stale:
            return "wand.and.stars"
        }
    }

    private var isBottomPrimaryDisabled: Bool {
        if activeItems.isEmpty {
            return false
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return true
        case .ready:
            return !canStartShopping
        case .failed:
            return false
        case .idle, .stale:
            return false
        }
    }

    private var groupedProductRows: [ShoppingWorkspaceGroup] {
        cachedGroupedProductRows
    }

    private var shoppingWorkspaceItemPresentationSignature: String {
        workspaceItems
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

    private func refreshShoppingPresentationCache() {
        refreshRecommendedStoreRowsCache()
        refreshGroupedProductRowsCache()
    }

    private func refreshRecommendedStoreRowsCache() {
        guard isCurrentShoppingPlanForActiveItems else {
            updateRecommendedStoreRows([])
            return
        }

        var seenStoreIDs = Set<UUID>()
        let uniqueCoverages = appStateManager.shoppingTripCoverages.compactMap { coverage -> StoreCoverage? in
            guard seenStoreIDs.insert(coverage.store.id).inserted else {
                return nil
            }

            return coverage
        }
        .prefix(4)

        let coverageRows = uniqueCoverages.enumerated().map { index, coverage in
            let planItems = appStateManager.shoppingPlan?.items ?? activeItems
            let likelyItemIDs = Set(coverage.matchedItems.map(\.id))

            return ShoppingWorkspaceStoreRow(
                id: "coverage-\(coverage.id)",
                storeID: coverage.store.id,
                storeName: coverage.store.title,
                recommendationTitle: recommendationTitle(for: coverage.group),
                likelyItemNames: coverage.matchedItems.map(\.name),
                otherItemNames: planItems.filter { !likelyItemIDs.contains($0.id) }.map(\.name),
                totalItemCount: planItems.count,
                hasProductCoverageEstimate: true,
                distanceText: coverage.distance.map(distanceText(for:)),
                isPrimaryRecommendation: index == 0
            )
        }

        if !coverageRows.isEmpty {
            updateRecommendedStoreRows(coverageRows)
            return
        }

        updateRecommendedStoreRows(realBuyingOptionRows)
    }

    private func updateRecommendedStoreRows(_ rows: [ShoppingWorkspaceStoreRow]) {
        cachedRecommendedStoreRows = rows

        if let selectedStoreID,
           rows.contains(where: { $0.storeID == selectedStoreID }) {
            return
        }

        selectedStoreID = rows.first?.storeID
    }

    private func isStoreSelected(_ row: ShoppingWorkspaceStoreRow) -> Bool {
        row.storeID == selectedStoreID
    }

    private func selectStore(_ row: ShoppingWorkspaceStoreRow) {
        selectedStoreID = row.storeID
        WayTaskHaptics.selection()
    }

    private var isCurrentShoppingPlanForActiveItems: Bool {
        guard let planItems = appStateManager.shoppingPlan?.items else {
            return false
        }

        return Set(planItems.map(\.id)) == Set(activeItems.map(\.id))
    }

    private func refreshGroupedProductRowsCache() {
        let groupedItems = Dictionary(grouping: filteredActiveItems) { item in
            intentMatcher.intentGroup(for: item)
        }
        let entriesByLegacyItemID = selectedShoppingEntries.reduce(into: [UUID: ShoppingListEntry]()) { result, entry in
            if let legacyShoppingItemID = entry.legacyShoppingItemID {
                result[legacyShoppingItemID] = entry
            }
        }

        cachedGroupedProductRows = ShoppingIntentGroup.allCases.compactMap { group in
            guard let items = groupedItems[group] else {
                return nil
            }

            return ShoppingWorkspaceGroup(
                id: group,
                title: groupTitle(for: group),
                subtitle: groupSubtitle(for: group),
                items: items.compactMap { item in
                    entriesByLegacyItemID[item.id].map { entry in
                        ShoppingWorkspaceItemRow(item: item, entry: entry)
                    }
                }
            )
        }
        .filter { !$0.items.isEmpty }
    }

    private var summaryText: String {
        if displayItemCount == 0 {
            return "No active items yet. The workspace is ready for the next shopping list."
        }

        return "\(displayItemCount) open items grouped into \(groupedProductRows.count) shopping intents."
    }

    private var fallbackSuggestionRequest: ShoppingStoreSuggestionRequest {
        intentMatcher.request(for: activeItems, in: .grocery)
    }

    private var selectedShoppingListID: UUID? {
        UUID(uuidString: selectedListID) ??
            appStateManager.selectedShoppingListID ??
            appStateManager.currentShoppingListID ??
            shoppingLists.first { $0.kind == .weekly }?.id
    }

    private func selectedShoppingListItems(includeChecked: Bool) -> [ShoppingItem] {
        guard let selectedShoppingListID else {
            return []
        }

        let itemsByID = items.reduce(into: [UUID: ShoppingItem]()) { result, item in
            result[item.id] = item
        }

        return shoppingListEntries
            .filter { $0.shoppingListID == selectedShoppingListID && (includeChecked || !$0.isChecked) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap { entry in
                guard let legacyShoppingItemID = entry.legacyShoppingItemID else {
                    return nil
                }

                return itemsByID[legacyShoppingItemID]
            }
    }

    private var hasSelectedShoppingListEntries: Bool {
        guard let selectedShoppingListID else {
            return false
        }

        return shoppingListEntries.contains { $0.shoppingListID == selectedShoppingListID }
    }

    private var shoppingListEntrySignature: String {
        shoppingListEntries
            .map { entry in
                [
                    entry.id.uuidString,
                    entry.shoppingListID.uuidString,
                    entry.productID.uuidString,
                    entry.legacyShoppingItemID?.uuidString ?? "",
                    entry.isChecked ? "1" : "0",
                    String(format: "%.2f", entry.quantity),
                    String(format: "%.2f", entry.sortOrder)
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
    }

    private var shoppingListSignature: String {
        shoppingLists
            .map { "\($0.id.uuidString)-\($0.title)-\($0.kindRawValue)-\($0.isDefault)" }
            .sorted()
            .joined(separator: "|")
    }

    private func syncSelectedListIfNeeded() {
        guard selectedListID.isEmpty || UUID(uuidString: selectedListID) == nil else {
            return
        }

        if let selectedShoppingListID {
            selectedListID = selectedShoppingListID.uuidString
            appStateManager.selectedShoppingListID = selectedShoppingListID
        }
    }

    private func handleBottomPrimaryAction() {
        guard !activeItems.isEmpty else {
            isShowingProductChooser = true
            return
        }

        switch appStateManager.shoppingPlanState {
        case .generating:
            return
        case .ready:
            startShopping()
        case .failed, .idle, .stale:
            generateShoppingPlan()
            isShowingPlanSheet = true
        }
    }

    private func handlePlanFailureAction(_ actionTitle: String?) {
        switch actionTitle {
        case "Enable Location":
            locationManager.requestWhenInUseAuthorization()
        case "Review Products", "Add products":
            appStateManager.selectedTab = .products
        default:
            generateShoppingPlan()
        }
    }

    private func generateShoppingPlan() {
        guard !appStateManager.shoppingPlanState.isGenerating else {
            return
        }

        guard selectedShoppingListID != nil else {
            failShoppingPlan(
                message: "Choose a shopping list before generating a plan.",
                actionTitle: "Review Products"
            )
            return
        }

        let planningItems = activeItems
        guard !planningItems.isEmpty else {
            failShoppingPlan(
                message: "Add at least one needed product before generating a plan.",
                actionTitle: "Add products"
            )
            return
        }

        appStateManager.beginShoppingPlanGeneration(stage: .preparingList)
        startPlanningTimer()

        Task { @MainActor in
            let startedAt = Date()

            await Task.yield()
            guard !failIfPlanningTimedOut(since: startedAt) else { return }

            appStateManager.updateShoppingPlanGeneration(stage: .findingStores)
            let request = intentMatcher.request(for: planningItems, in: .grocery)
            let userCoordinate = locationManager.currentCoordinate
            let stores = await storeResolutionEngine.resolve(
                savedLocations: locations,
                items: planningItems,
                around: userCoordinate,
                fallback: request
            )
            guard !stores.isEmpty else {
                let hasLocation = locationManager.currentCoordinate != nil
                failShoppingPlan(
                    message: hasLocation ? "No eligible stores were found for this list." : "Location is unavailable, so WayTask cannot find nearby stores for this plan.",
                    actionTitle: hasLocation ? "Try Again" : "Enable Location"
                )
                return
            }
            guard !failIfPlanningTimedOut(since: startedAt) else { return }

            appStateManager.updateShoppingPlanGeneration(stage: .matchingProducts)
            await Task.yield()
            guard !failIfPlanningTimedOut(since: startedAt) else { return }

            appStateManager.updateShoppingPlanGeneration(stage: .calculatingCoverage)
            let buyingOptions = buyingOptionsService.localOptions(
                for: request,
                shoppingItems: planningItems,
                stores: stores,
                userCoordinate: userCoordinate
            )
            .filter(\.isDisplayableRealStore)
            let shoppingTripCoverages = shoppingTripPlanningService.coverage(
                for: planningItems,
                stores: stores,
                request: request,
                userCoordinate: userCoordinate
            )
            guard !failIfPlanningTimedOut(since: startedAt) else { return }

            appStateManager.updateShoppingPlanGeneration(stage: .rankingOptions)
            guard !buyingOptions.isEmpty || !shoppingTripCoverages.isEmpty else {
                failShoppingPlan(
                    message: "No recommended stores were found for the products in this list.",
                    actionTitle: "Review Products"
                )
                return
            }

            appStateManager.setShoppingPlan(
                request: request,
                items: planningItems,
                stores: stores,
                buyingOptions: buyingOptions,
                shoppingTripCoverages: shoppingTripCoverages
            )
            refreshRecommendedStoreRowsCache()
            isShowingPlanSheet = true
        }
    }

    private func failShoppingPlan(message: String, actionTitle: String?) {
        appStateManager.markShoppingPlanFailed(message: message, actionTitle: actionTitle)
        stopPlanningTimer()
        isShowingPlanSheet = true
    }

    private func failIfPlanningTimedOut(since startedAt: Date) -> Bool {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > planningTimeoutSeconds else {
            return false
        }

        SentryReportingService.shared.capture(
            message: .plannerTimedOut,
            operation: .planner,
            category: .operational,
            area: .shopping,
            numericContext: [
                .itemCount: activeItems.count,
                .planningDurationBucket: Int(elapsed / 5) * 5
            ]
        )
        failShoppingPlan(
            message: "Planning timed out before a usable store plan was created.",
            actionTitle: "Try Again"
        )
        return true
    }

    private func handlePlanStateChange(_ state: ShoppingPlanGenerationState) {
        if state.isGenerating {
            startPlanningTimer()
        } else {
            stopPlanningTimer()
        }
    }

    private func startPlanningTimer() {
        guard planningTimerTask == nil else {
            return
        }

        planningElapsedSeconds = 0
        planningTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    planningElapsedSeconds += 1
                }
            }
        }
    }

    private func stopPlanningTimer() {
        planningTimerTask?.cancel()
        planningTimerTask = nil
    }

    private func openPlanOnMap() {
        guard canViewMapPlan,
              let plan = appStateManager.shoppingPlan else {
            return
        }

        appStateManager.showTripOnMap(
            for: plan.request,
            items: plan.items,
            stores: plan.stores,
            buyingOptions: plan.buyingOptions,
            shoppingTripCoverages: plan.shoppingTripCoverages
        )
    }

    private func startShopping() {
        guard let shoppingListID = selectedShoppingListID else {
            showShoppingFlowError("Choose a shopping list before starting.")
            return
        }

        guard let selectedStore else {
            showShoppingFlowError("Choose a recommended store before starting.")
            return
        }

        guard canStartShopping else {
            showShoppingFlowError("The shopping plan is no longer current. Generate the plan again before starting.")
            return
        }

        do {
            try shoppingSessionService.startShopping(
                with: activeItems,
                shoppingListID: shoppingListID,
                selectedStore: selectedStore,
                in: modelContext
            )
            isShowingPlanSheet = false
        } catch {
            showShoppingFlowError("WayTask could not start shopping. \(error.localizedDescription)")
        }
    }

    private func shoppingSessionItems(for session: ShoppingSession) -> [ShoppingItem] {
        let itemsByID = items.reduce(into: [UUID: ShoppingItem]()) { result, item in
            result[item.id] = item
        }

        return session.itemIDs.compactMap { itemsByID[$0] }
    }

    private func toggleCollected(_ item: ShoppingItem, in session: ShoppingSession) {
        do {
            if session.isCollected(item) {
                try shoppingSessionService.markItemRemaining(item, in: session, modelContext: modelContext)
            } else {
                try shoppingSessionService.markItemCollected(item, in: session, modelContext: modelContext)
            }
        } catch {
            showShoppingFlowError("WayTask could not update this product. \(error.localizedDescription)")
        }
    }

    private func finishShopping(_ session: ShoppingSession) {
        do {
            try shoppingSessionService.finishShopping(session, in: modelContext)
            isShowingPlanSheet = false
            selectedStoreID = nil
            appStateManager.clearShoppingPlan()
            refreshShoppingPresentationCache()
        } catch {
            showShoppingFlowError("WayTask could not finish this shopping session. \(error.localizedDescription)")
        }
    }

    private func canNavigate(to session: ShoppingSession) -> Bool {
        guard session.selectedStoreID != nil,
              let storeName = session.selectedStoreName,
              !storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let latitude = session.selectedStoreLatitude,
              let longitude = session.selectedStoreLongitude else {
            return false
        }

        return CLLocationCoordinate2DIsValid(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    private func navigateToSelectedStore(for session: ShoppingSession) {
        guard canNavigate(to: session),
              let storeName = session.selectedStoreName,
              let latitude = session.selectedStoreLatitude,
              let longitude = session.selectedStoreLongitude else {
            showShoppingFlowError("Navigation is unavailable because this session does not include a selected store location.")
            return
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = storeName

        let didOpen = mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
        if !didOpen {
            showShoppingFlowError("Apple Maps could not open directions to \(storeName). Please try again.")
        }
    }

    private func showShoppingFlowError(_ message: String) {
        shoppingFlowErrorMessage = message
        isShowingShoppingFlowError = true
    }

    private var selectedShoppingEntries: [ShoppingListEntry] {
        guard let selectedShoppingListID else {
            return []
        }

        return shoppingListEntries.filter { $0.shoppingListID == selectedShoppingListID }
    }

    private func toggleEntryChecked(_ row: ShoppingWorkspaceItemRow) {
        guard let entry = shoppingListEntries.first(where: { $0.id == row.entryID }) else {
            return
        }

        entry.isChecked.toggle()
        if let legacyShoppingItemID = entry.legacyShoppingItemID,
           let item = items.first(where: { $0.id == legacyShoppingItemID }) {
            item.isCompleted = entry.isChecked
        }
        saveShoppingEntryChange()
    }

    private func adjustQuantity(for row: ShoppingWorkspaceItemRow, delta: Double) {
        guard let entry = shoppingListEntries.first(where: { $0.id == row.entryID }) else {
            return
        }

        entry.quantity = max(1, entry.quantity + delta)
        saveShoppingEntryChange()
    }

    private func removeEntry(_ row: ShoppingWorkspaceItemRow) {
        guard let selectedShoppingListID,
              let product = products.first(where: { $0.id == row.productID }) else {
            return
        }

        do {
            try shoppingListService.removeProductFromShopping(
                product,
                shoppingListID: selectedShoppingListID,
                in: modelContext
            )
            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
            refreshShoppingPresentationCache()
        } catch {
            assertionFailure("Failed to remove product from shopping: \(error.localizedDescription)")
        }
    }

    private func saveShoppingEntryChange() {
        do {
            try modelContext.save()
            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
            refreshShoppingPresentationCache()
        } catch {
            assertionFailure("Failed to update shopping list entry: \(error.localizedDescription)")
        }
    }

    private func quantityText(_ quantity: Double) -> String {
        if quantity.rounded() == quantity {
            return "x\(Int(quantity))"
        }

        return "x\(String(format: "%.1f", quantity))"
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
    let id: String
    let storeID: UUID
    let storeName: String
    let recommendationTitle: String
    let likelyItemNames: [String]
    let otherItemNames: [String]
    let totalItemCount: Int
    let hasProductCoverageEstimate: Bool
    let distanceText: String?
    let isPrimaryRecommendation: Bool
}

private struct ShoppingWorkspaceGroup: Identifiable {
    let id: ShoppingIntentGroup
    let title: String
    let subtitle: String
    let items: [ShoppingWorkspaceItemRow]
}

private struct ShoppingWorkspaceItemRow: Identifiable {
    let id: UUID
    let entryID: UUID
    let productID: UUID
    let name: String
    let subtitle: String
    var imageData: Data?
    var imageURL: URL?
    var isChecked: Bool
    var quantity: Double

    init(
        id: UUID,
        entryID: UUID,
        productID: UUID,
        name: String,
        subtitle: String,
        imageData: Data? = nil,
        imageURL: URL? = nil,
        isChecked: Bool = false,
        quantity: Double = 1
    ) {
        self.id = id
        self.entryID = entryID
        self.productID = productID
        self.name = name
        self.subtitle = subtitle
        self.imageData = imageData
        self.imageURL = imageURL
        self.isChecked = isChecked
        self.quantity = quantity
    }

    init(item: ShoppingItem, entry: ShoppingListEntry) {
        self.id = item.id
        self.entryID = entry.id
        self.productID = entry.productID
        self.name = item.name
        self.subtitle = item.brand ?? item.category ?? "Shopping item"
        self.imageData = item.imageData
        self.imageURL = item.imageURL
        self.isChecked = entry.isChecked
        self.quantity = entry.quantity
    }
}
