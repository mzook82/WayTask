//
//  ContentView.swift
//  WayTask
//
//  Created by Mordechai Zukerman on 27/06/2026.
//

import CoreLocation
import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var items: [ShoppingItem]
    @Query private var locations: [GeoLocation]
    @Query private var shoppingSessions: [ShoppingSession]
    @Query private var products: [Product]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]

    @AppStorage("waytask.initialShoppingSelectionCompleted.v1") private var initialShoppingSelectionCompleted = false
    @AppStorage("waytask.shoppingWorkflowOnboardingCompleted.v1") private var shoppingWorkflowOnboardingCompleted = false
    @AppStorage("waytask.legacyShoppingReviewCompleted.v1") private var legacyShoppingReviewCompleted = false
    @State private var startupSheet: ShoppingStartupSheet?
    private let shoppingListBackfillService = ShoppingListBackfillService()

    var body: some View {
        TabView(selection: $appStateManager.selectedTab) {
            HomeView()
            .tabItem {
                Label(AppTab.home.title, systemImage: AppTab.home.systemImageName)
            }
            .tag(AppTab.home)

            ProductListView()
                .tabItem {
                    Label(AppTab.products.title, systemImage: AppTab.products.systemImageName)
                }
                .tag(AppTab.products)

            ShoppingWorkspaceView()
                .tabItem {
                    Label(AppTab.shopping.title, systemImage: AppTab.shopping.systemImageName)
                }
                .tag(AppTab.shopping)

            MainMapView()
                .tabItem {
                    Label(AppTab.map.title, systemImage: AppTab.map.systemImageName)
                }
                .tag(AppTab.map)

            WayTaskFoundationPlaceholderView(
                title: "Settings",
                subtitle: "Settings tab foundation is ready. Existing settings logic remains unchanged.",
                systemImage: "gearshape.fill"
            )
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.systemImageName)
            }
            .tag(AppTab.settings)
        }
        .tint(WayTaskDesign.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            ensureShoppingListArchitecture()
            syncShoppingArchitectureState()
            presentShoppingStartupSheetIfNeeded()
            seedDebugStoreIfNeeded()
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
        }
        .onChange(of: legacyShoppingItemSignature) {
            ensureShoppingListArchitecture()
            syncShoppingArchitectureState()
        }
        .onChange(of: shoppingArchitectureSignature) {
            syncShoppingArchitectureState()
            presentShoppingStartupSheetIfNeeded()
        }
        .sheet(item: $startupSheet) { sheet in
            startupSheetContent(sheet)
        }
        .onChange(of: geofenceRefreshSignature) {
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            seedDebugStoreIfNeeded()
            ensureShoppingListArchitecture()
            syncShoppingArchitectureState()
            refreshShoppingGeofences()
            refreshNearbyOpportunities()
            locationManager.checkSmartNearbyDetection(reason: "app active")
        }
    }

    private var legacyShoppingItemSignature: String {
        items
            .map { item in
                [
                    item.id.uuidString,
                    item.name,
                    item.isCompleted ? "1" : "0",
                    item.brand ?? "",
                    item.category ?? "",
                    item.barcode ?? "",
                    String(item.dateAdded.timeIntervalSince1970)
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
    }

    private var shoppingArchitectureSignature: String {
        let productSignature = products
            .map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        let listSignature = shoppingLists
            .map { "\($0.id.uuidString)-\($0.kindRawValue)-\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")

        return "\(productSignature)#\(listSignature)"
    }

    private var weeklyShoppingListID: UUID? {
        shoppingLists.first { $0.kind == .weekly }?.id
    }

    private var weeklyShoppingEntryCount: Int {
        guard let weeklyShoppingListID else {
            return 0
        }

        return shoppingListEntries.filter { $0.shoppingListID == weeklyShoppingListID }.count
    }

    private var weeklyShoppingEntries: [ShoppingListEntry] {
        guard let weeklyShoppingListID else {
            return []
        }

        return shoppingListEntries.filter { $0.shoppingListID == weeklyShoppingListID }
    }

    private func ensureShoppingListArchitecture() {
        do {
            let result = try shoppingListBackfillService.ensureDefaultListsAndBackfill(in: modelContext)
            appStateManager.setCurrentShoppingList(result.weeklyListID)
        } catch {
            assertionFailure("Failed to prepare shopping list architecture: \(error.localizedDescription)")
        }
    }

    private func syncShoppingArchitectureState() {
        let weeklyListID = shoppingLists.first { $0.kind == .weekly }?.id
        appStateManager.setCurrentShoppingList(weeklyListID)
        appStateManager.setCurrentProductLibrary(products)
    }

    private func presentShoppingStartupSheetIfNeeded() {
        guard startupSheet == nil,
              weeklyShoppingListID != nil,
              !products.isEmpty else {
            return
        }

        if !legacyShoppingReviewCompleted, weeklyShoppingEntryCount > 0 {
            startupSheet = .legacyReview
            return
        }

        if !shoppingWorkflowOnboardingCompleted {
            startupSheet = .workflowOnboarding
            return
        }

        if !initialShoppingSelectionCompleted, weeklyShoppingEntryCount == 0 {
            startupSheet = .initialSelection
        }
    }

    @ViewBuilder
    private func startupSheetContent(_ sheet: ShoppingStartupSheet) -> some View {
        switch sheet {
        case .workflowOnboarding:
            ShoppingWorkflowOnboardingSheet(
                onChooseProducts: {
                    shoppingWorkflowOnboardingCompleted = true
                    startupSheet = .initialSelection
                },
                onSkip: {
                    shoppingWorkflowOnboardingCompleted = true
                    initialShoppingSelectionCompleted = true
                    startupSheet = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        case .legacyReview:
            LegacyShoppingReviewSheet(
                entryCount: weeklyShoppingEntryCount,
                onKeep: {
                    completeLegacyReview(selectShopping: true)
                },
                onEdit: {
                    completeLegacyReview(selectShopping: true)
                },
                onStartFresh: {
                    startFreshWeeklyShopping()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        case .initialSelection:
            ProductShoppingSelectionSheet(
                title: "Choose products",
                subtitle: "Products are your permanent library. Shopping contains only products you choose for this trip.",
                preferredShoppingListID: weeklyShoppingListID,
                showsSkipAction: true,
                onComplete: {
                    shoppingWorkflowOnboardingCompleted = true
                    initialShoppingSelectionCompleted = true
                    startupSheet = nil
                    appStateManager.selectedTab = .shopping
                },
                onSkip: {
                    shoppingWorkflowOnboardingCompleted = true
                    initialShoppingSelectionCompleted = true
                    startupSheet = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        }
    }

    private func completeLegacyReview(selectShopping: Bool) {
        legacyShoppingReviewCompleted = true
        shoppingWorkflowOnboardingCompleted = true
        initialShoppingSelectionCompleted = true
        startupSheet = nil

        if selectShopping {
            appStateManager.selectedTab = .shopping
        }
    }

    private func startFreshWeeklyShopping() {
        let entriesToRemove = weeklyShoppingEntries
        let legacyShoppingItemIDs = Set(entriesToRemove.compactMap(\.legacyShoppingItemID))

        for item in items where legacyShoppingItemIDs.contains(item.id) {
            item.isCompleted = true
        }

        for entry in entriesToRemove {
            modelContext.delete(entry)
        }

        do {
            try modelContext.save()
            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
        } catch {
            assertionFailure("Failed to start fresh shopping list: \(error.localizedDescription)")
            return
        }

        completeLegacyReview(selectShopping: true)
    }

    private var geofenceRefreshSignature: String {
        let itemSignature = items
            .filter { !$0.isCompleted }
            .map { item in
                "\(item.id.uuidString)-\(item.name)-\(item.category ?? "")-\(item.isCompleted)"
            }
            .sorted()
            .joined(separator: "|")

        let locationSignature = locations
            .map { location in
                let locationItemSignature = location.shoppingItems
                    .filter { !$0.isCompleted }
                    .map { "\($0.id.uuidString)-\($0.name)" }
                    .sorted()
                    .joined(separator: ",")

                return "\(location.id.uuidString)-\(location.title)-\(location.latitude)-\(location.longitude)-\(location.radius)-\(location.storeCategoryRawValue ?? "")-\(location.addressText ?? "")-\(location.notes ?? "")-\(locationItemSignature)"
            }
            .sorted()
            .joined(separator: "|")

        let sessionSignature = shoppingSessions
            .map { session in
                "\(session.id.uuidString)-\(session.isActive)-\(session.finishedAt?.timeIntervalSince1970 ?? 0)-\(session.collectedItemIDListRawValue)"
            }
            .sorted()
            .joined(separator: "|")

        let coordinateSignature: String
        if let coordinate = locationManager.currentCoordinate {
            let latitudeBucket = Int((coordinate.latitude * 2_000).rounded())
            let longitudeBucket = Int((coordinate.longitude * 2_000).rounded())
            coordinateSignature = "\(latitudeBucket)-\(longitudeBucket)"
        } else {
            coordinateSignature = "no-location"
        }

        return "\(itemSignature)#\(locationSignature)#\(sessionSignature)#\(coordinateSignature)"
    }

    private func refreshShoppingGeofences() {
        locationManager.refreshShoppingGeofences(items: items, savedLocations: locations)
    }

    private func refreshNearbyOpportunities() {
        Task {
            await appStateManager.refreshNearbyOpportunities(
                items: items,
                savedLocations: locations,
                currentCoordinate: locationManager.currentCoordinate
            )
        }
    }

    private func seedDebugStoreIfNeeded() {
        #if DEBUG
        guard DebugSeedStoreService.isEnabled else {
            return
        }

        DebugSeedStoreService().ensureSeedStore(
            near: locationManager.currentCoordinate,
            in: modelContext
        )
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStateManager())
        .environmentObject(LocationManager())
}

private struct WayTaskFoundationPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(spacing: WayTaskDesign.Spacing.xl) {
                    WayTaskNavigationBar(title: title, subtitle: "Foundation")

                    Spacer(minLength: WayTaskDesign.Spacing.lg)

                    WayTaskEmptyState(
                        title: title,
                        message: subtitle,
                        systemImage: systemImage
                    )
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)

                    Spacer(minLength: WayTaskDesign.Spacing.lg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private enum ShoppingStartupSheet: Identifiable {
    case workflowOnboarding
    case legacyReview
    case initialSelection

    var id: String {
        switch self {
        case .workflowOnboarding:
            return "workflowOnboarding"
        case .legacyReview:
            return "legacyReview"
        case .initialSelection:
            return "initialSelection"
        }
    }
}

private struct ShoppingWorkflowOnboardingSheet: View {
    let onChooseProducts: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.lg) {
                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                        Text("How Shopping works")
                            .font(WayTaskDesign.Typography.title)
                            .foregroundStyle(WayTaskDesign.primaryText)

                        Text("Products are your permanent library. Shopping contains only products you choose for this shopping trip. Generate Plan finds the best stores for that list.")
                            .font(WayTaskDesign.Typography.subheadline)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
                        workflowStep("1", title: "Products", message: "Save or scan products once.")
                        workflowStep("2", title: "Choose Products", message: "Pick what you need for Weekly Shopping.")
                        workflowStep("3", title: "Generate Plan", message: "Review store coverage, then open Map or start shopping.")
                    }

                    Spacer(minLength: WayTaskDesign.Spacing.sm)

                    WayTaskPrimaryButton("Choose Products", systemImage: "cart.badge.plus") {
                        onChooseProducts()
                    }

                    WayTaskSecondaryButton("Not Now", systemImage: "xmark") {
                        onSkip()
                    }
                }
                .padding(WayTaskDesign.Spacing.lg)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func workflowStep(_ number: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: WayTaskDesign.Spacing.sm) {
            Text(number)
                .font(WayTaskDesign.Typography.captionStrong)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(WayTaskDesign.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.primaryText)

                Text(message)
                    .font(WayTaskDesign.Typography.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LegacyShoppingReviewSheet: View {
    let entryCount: Int
    let onKeep: () -> Void
    let onEdit: () -> Void
    let onStartFresh: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.lg) {
                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                        Text("WayTask has been updated")
                            .font(WayTaskDesign.Typography.title)
                            .foregroundStyle(WayTaskDesign.primaryText)

                        Text("Products are now separate from Shopping. Your permanent Products were preserved, and Weekly Shopping currently has \(entryCount) \(entryCount == 1 ? "product" : "products").")
                            .font(WayTaskDesign.Typography.subheadline)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                        Label("Keep Current Shopping List preserves the selected products.", systemImage: "checkmark.circle")
                        Label("Edit Shopping List opens Shopping so you can remove or add products.", systemImage: "slider.horizontal.3")
                        Label("Start Fresh clears only Shopping entries. Products stay in your library.", systemImage: "arrow.counterclockwise")
                    }
                    .font(WayTaskDesign.Typography.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)

                    Spacer(minLength: WayTaskDesign.Spacing.sm)

                    WayTaskPrimaryButton("Keep Current Shopping List", systemImage: "checkmark.circle.fill") {
                        onKeep()
                    }

                    WayTaskSecondaryButton("Edit Shopping List", systemImage: "square.and.pencil") {
                        onEdit()
                    }

                    WayTaskSecondaryButton("Start Fresh", systemImage: "arrow.counterclockwise") {
                        onStartFresh()
                    }
                }
                .padding(WayTaskDesign.Spacing.lg)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct ProductShoppingSelectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager

    @Query private var products: [Product]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]

    let title: String
    let subtitle: String
    let preferredShoppingListID: UUID?
    let showsSkipAction: Bool
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var selectedProductIDs: Set<UUID> = []

    private let shoppingListService = ShoppingListService()

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
                    VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
                        Text(title)
                            .font(WayTaskDesign.Typography.title)
                            .foregroundStyle(WayTaskDesign.primaryText)

                        Text(subtitle)
                            .font(WayTaskDesign.Typography.subheadline)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)
                    .padding(.top, WayTaskDesign.Spacing.lg)

                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        WayTaskSecondaryButton("Select All", systemImage: "checkmark.square") {
                            selectAllAvailableProducts()
                        }

                        WayTaskSecondaryButton("Clear All", systemImage: "square") {
                            clearSelectedProducts()
                        }
                    }
                    .padding(.horizontal, WayTaskDesign.Spacing.lg)

                    productSelectionList
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                initializeSelectionIfNeeded()
            }
        }
    }

    private var productSelectionList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: WayTaskDesign.Spacing.sm) {
                ForEach(sortedProducts) { product in
                    productRow(product)
                }
            }
            .padding(.horizontal, WayTaskDesign.Spacing.lg)
            .padding(.bottom, 116)
        }
    }

    private var bottomActions: some View {
        VStack(spacing: WayTaskDesign.Spacing.sm) {
            WayTaskPrimaryButton(
                "Add Selected to Shopping",
                systemImage: "cart.badge.plus",
                isDisabled: selectedAddableProductIDs.isEmpty || selectedShoppingListID == nil
            ) {
                addSelectedProducts()
            }

            WayTaskSecondaryButton(showsSkipAction ? "Skip for Now" : "Done", systemImage: showsSkipAction ? "forward.end" : "checkmark") {
                onSkip()
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

    private func productRow(_ product: Product) -> some View {
        let alreadyInShopping = isProductAlreadyInShopping(product)
        let isSelected = selectedProductIDs.contains(product.id) || alreadyInShopping

        return Button {
            guard !alreadyInShopping else {
                return
            }

            if selectedProductIDs.contains(product.id) {
                selectedProductIDs.remove(product.id)
            } else {
                selectedProductIDs.insert(product.id)
            }
        } label: {
            HStack(spacing: WayTaskDesign.Spacing.sm) {
                WayTaskProductThumbnail(
                    data: product.imageData,
                    url: product.imageURL,
                    size: 52,
                    cornerRadius: WayTaskDesign.Radius.sm
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)

                    Text(product.brand ?? product.category ?? "Product")
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                    .frame(width: 44, height: 44)
            }
            .padding(WayTaskDesign.Spacing.sm)
            .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.md, highlighted: isSelected && !alreadyInShopping)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(productAccessibilityLabel(product, isSelected: isSelected, alreadyInShopping: alreadyInShopping))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    private var selectedShoppingListID: UUID? {
        preferredShoppingListID ??
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

    private var selectedAddableProductIDs: Set<UUID> {
        selectedProductIDs.subtracting(Set(selectedShoppingEntries.map(\.productID)))
    }

    private func initializeSelectionIfNeeded() {
        guard selectedProductIDs.isEmpty else {
            return
        }

        selectedProductIDs = []
    }

    private func selectAllAvailableProducts() {
        let existingProductIDs = Set(selectedShoppingEntries.map(\.productID))
        selectedProductIDs = Set(products.map(\.id)).subtracting(existingProductIDs)
    }

    private func clearSelectedProducts() {
        selectedProductIDs = []
    }

    private func isProductAlreadyInShopping(_ product: Product) -> Bool {
        selectedShoppingEntries.contains { $0.productID == product.id }
    }

    private func addSelectedProducts() {
        guard let selectedShoppingListID else {
            return
        }

        let productIDsToAdd = selectedAddableProductIDs
        guard !productIDsToAdd.isEmpty else {
            onComplete()
            return
        }

        do {
            for product in products where productIDsToAdd.contains(product.id) {
                try shoppingListService.addProductToShopping(
                    product,
                    shoppingListID: selectedShoppingListID,
                    in: modelContext
                )
            }

            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
            onComplete()
        } catch {
            assertionFailure("Failed to add selected products to shopping: \(error.localizedDescription)")
        }
    }

    private func productAccessibilityLabel(_ product: Product, isSelected: Bool, alreadyInShopping: Bool) -> String {
        let status: String
        if alreadyInShopping {
            status = "Already in Shopping"
        } else {
            status = isSelected ? "Selected" : "Not selected"
        }

        return "\(product.name), \(product.brand ?? product.category ?? "Product"), \(status)"
    }
}
