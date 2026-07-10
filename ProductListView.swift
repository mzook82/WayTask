import MapKit
import PhotosUI
import SwiftData
import SwiftUI

struct ProductListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var items: [ShoppingItem]
    @Query private var products: [Product]
    @Query private var locations: [GeoLocation]
    @Query private var productHistories: [ProductHistory]
    @Query private var shoppingSessions: [ShoppingSession]
    @Query private var shoppingLists: [ShoppingList]
    @Query private var shoppingListEntries: [ShoppingListEntry]

    @State private var newItemName = ""
    @State private var selectedLocationID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var suggestionItem: ShoppingItem?
    @State private var buyingOptionsRequest: ShoppingStoreSuggestionRequest?
    @State private var isShowingAddProduct = false
    @State private var isShowingNearbyOpportunities = false
    @State private var isShowingBuyingOptions = false
    @State private var isShowingSettings = false
    @State private var isShowingScanner = false
    private let shoppingListService = ShoppingListService()
    private let shoppingIntentMatcher = ShoppingIntentMatcher()
    private let buyingOptionsService = BuyingOptionsService()
    private let shoppingMemoryService = ShoppingMemoryService()
    private let shoppingTripService = ShoppingTripService()
    private let shoppingSessionService = ShoppingSessionService()
    private let storeSearchService = MapKitStoreSearchService()
    private let storeRankingService = StoreRankingService()
    @State private var suggestions: [MKMapItem] = []
    @State private var isSearchingSuggestions = false
    @State private var isRefreshingBuyingOptions = false
    @State private var suggestionRefreshGeneration = 0
    @State private var searchText = ""
    @State private var selectedFilter: ProductFilter = .all

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    filterBar
                    productList
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddProduct) {
                addProductSheet
            }
            .sheet(isPresented: $isShowingNearbyOpportunities) {
                nearbyOpportunitiesSheet
            }
            .sheet(item: $suggestionItem) { item in
                suggestionSheet(for: item)
            }
            .sheet(isPresented: $isShowingBuyingOptions) {
                BuyingOptionsSheet(
                    options: appStateManager.buyingOptions,
                    tripCoverages: appStateManager.shoppingTripCoverages,
                    activeTripItemCount: activeShoppingItems.count,
                    isRefreshing: isRefreshingBuyingOptions,
                    onRefresh: refreshCurrentBuyingOptions,
                    onViewOnMap: { _ in
                        openBuyingOptionsOnMap()
                    },
                    onViewTripOnMap: {
                        openTripOnMap()
                    },
                    onClose: {
                        isShowingBuyingOptions = false
                    }
                )
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(locationManager)
            }
            .fullScreenCover(isPresented: $isShowingScanner) {
                CameraView {
                    isShowingScanner = false
                }
            }
            .onChange(of: selectedPhotoItem) {
                loadSelectedPhoto()
            }
            .onChange(of: isShowingAddProduct) {
                if !isShowingAddProduct {
                    resetForm()
                }
            }
            .onChange(of: appStateManager.shoppingListRevision) {
                if appStateManager.recentlyAddedShoppingItemID == nil {
                    showAllProducts()
                }
            }
            .onAppear {
                appStateManager.setCurrentProductLibrary(products)
            }
            .onChange(of: productLibrarySignature) {
                appStateManager.setCurrentProductLibrary(products)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Products")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }

                Spacer()

                HStack(spacing: 10) {
                    WayTaskIconButton(systemName: "bell") {
                        isShowingNearbyOpportunities = true
                    }
                    .overlay(alignment: .topTrailing) {
                        if appStateManager.hasNearbyOpportunityBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 9, height: 9)
                                .overlay {
                                    Circle()
                                        .stroke(Color(red: 0.09, green: 0.09, blue: 0.10), lineWidth: 2)
                                }
                                .offset(x: -7, y: 7)
                        }
                    }
                    .accessibilityLabel(appStateManager.hasNearbyOpportunityBadge ? "Nearby opportunities available" : "Nearby opportunities")

                    WayTaskIconButton(systemName: "gearshape") {
                        isShowingSettings = true
                    }
                    .accessibilityLabel("Settings")
                }
            }
            WayTaskSearchField(placeholder: "Search products...", text: $searchText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var addProductSheet: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView {
                    addProductForm
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingAddProduct = false
                    }
                    .tint(WayTaskDesign.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var nearbyOpportunitiesSheet: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                List {
                    if appStateManager.nearbyOpportunities.isEmpty {
                        ContentUnavailableView(
                            "No nearby opportunities",
                            systemImage: "bell",
                            description: Text("WayTask will surface nearby shopping matches here when they are relevant.")
                        )
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(appStateManager.nearbyOpportunities) { opportunity in
                            NearbyOpportunityRow(opportunity: opportunity) {
                                isShowingNearbyOpportunities = false
                                appStateManager.openNearbyOpportunityOnMap(opportunity)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Nearby Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingNearbyOpportunities = false
                    }
                    .tint(WayTaskDesign.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var addProductForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                selectedPhotoPreview

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Product name", text: $newItemName)
                        .textInputAutocapitalization(.words)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text("Saved here first. Add products to Shopping only when you plan to buy them.")
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Label("Photo", systemImage: "camera")
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())

                Button {
                    addItem()
                    isShowingAddProduct = false
                } label: {
                    Label("Add Product", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle())
                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .wayTaskCard()
    }

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button {
                isShowingAddProduct = true
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 44, cornerRadius: 14, shadow: true))

            Button {
                isShowingScanner = true
            } label: {
                Label("Scan", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 44, cornerRadius: 14))
            .accessibilityLabel("Scan Product")

            Button {
                appStateManager.selectedTab = .shopping
            } label: {
                Label("Shopping", systemImage: "list.bullet.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 44, cornerRadius: 14))
            .accessibilityLabel("Open Shopping")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WayTaskDesign.surfaceBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func shoppingSessionContent(for session: ShoppingSession) -> some View {
        let sessionItems = shoppingSessionItems(for: session)
        let collectedCount = sessionItems.filter { session.isCollected($0) }.count
        let totalCount = sessionItems.count
        let remainingCount = max(totalCount - collectedCount, 0)
        let progress = totalCount == 0 ? 0 : Double(collectedCount) / Double(totalCount)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                WayTaskScreenHeader(
                    title: "Shopping Mode",
                    subtitle: "\(remainingCount) remaining • \(collectedCount)/\(totalCount) collected",
                    trailingIcons: ["cart.fill"]
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active shopping session")
                                .font(.headline)
                                .foregroundStyle(WayTaskDesign.primaryText)

                            Text(totalCount == 0 ? "No active items in this session" : "Collect items as you shop")
                                .font(.caption)
                                .foregroundStyle(WayTaskDesign.secondaryText)
                        }

                        Spacer(minLength: 8)

                        Button("Finish") {
                            finishShopping(session)
                        }
                        .buttonStyle(WayTaskSecondaryPillButtonStyle())
                    }

                    ProgressView(value: progress)
                        .tint(WayTaskDesign.accent)
                        .accessibilityLabel("Shopping progress")
                        .accessibilityValue("\(collectedCount) of \(totalCount) items collected")

                    HStack(spacing: 10) {
                        ShoppingSessionMetric(title: "Collected", value: "\(collectedCount)/\(totalCount)", iconName: "checkmark.circle.fill")
                        ShoppingSessionMetric(title: "Remaining", value: "\(remainingCount)", iconName: "list.bullet")
                    }
                }
                .padding(16)
                .wayTaskCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            shoppingSessionList(for: session, items: sessionItems)
        }
    }

    private func shoppingSessionList(for session: ShoppingSession, items sessionItems: [ShoppingItem]) -> some View {
        List {
            if sessionItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(WayTaskDesign.accent)

                    Text("Nothing left to collect")
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    Text("Finish this session when you are done shopping.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .wayTaskCard()
                .listRowInsets(EdgeInsets(top: 42, leading: 20, bottom: 42, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sessionItems) { item in
                    ShoppingSessionItemRow(
                        item: item,
                        isCollected: session.isCollected(item)
                    ) {
                        toggleCollected(item, in: session)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private var selectedPhotoPreview: some View {
        if selectedImageData != nil {
            WayTaskProductThumbnail(data: selectedImageData)
                .accessibilityLabel("Selected product photo")
        } else {
            WayTaskProductThumbnail(data: nil)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProductFilter.allCases) { filter in
                    WayTaskFilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var productList: some View {
        List {
            if let opportunity = appStateManager.visibleNearbyOpportunity {
                nearbyOpportunityBanner(opportunity)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if filteredProducts.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets(top: 42, leading: 20, bottom: 42, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredProducts) { product in
                    ProductRowCard(
                        product: product,
                        isInShopping: isProductInCurrentShoppingList(product),
                        memoryIndicators: memoryIndicators(for: product),
                        onAddToShopping: {
                            addProductToShopping(product)
                        },
                        onRemoveFromShopping: {
                            removeProductFromShopping(product)
                        },
                        onImageSelected: { imageData in
                            replaceImage(for: product, imageData: imageData)
                        },
                        onRemoteImageLoaded: { imageData in
                            cacheRemoteImage(for: product, imageData: imageData)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: deleteFilteredProducts)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .id(appStateManager.shoppingListRevision)
    }

    private func nearbyOpportunityBanner(_ opportunity: NearbyShoppingOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
                    .frame(width: 38, height: 38)
                    .background(WayTaskDesign.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nearby now")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WayTaskDesign.accent)
                        .textCase(.uppercase)

                    Text(opportunity.title)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(1)

                    Text("\(opportunity.itemSummary) \(opportunity.distanceText).")
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    appStateManager.openNearbyOpportunityOnMap(opportunity)
                } label: {
                    Label("View Map", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())

                Button {
                    appStateManager.dismissNearbyOpportunity(opportunity)
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())
            }
        }
        .padding(14)
        .background(WayTaskDesign.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nearby now. \(opportunity.title). \(opportunity.itemSummary) \(opportunity.distanceText).")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "basket")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(WayTaskDesign.tertiaryText)

            Text(products.isEmpty ? "No products yet" : "No matching products")
                .font(.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text(products.isEmpty ? "Scan or add products to build your permanent library." : "Try changing the search or filter.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WayTaskDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .wayTaskCard()
    }

    private func suggestionSheet(for item: ShoppingItem) -> some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                List {
                    if isSearchingSuggestions {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(WayTaskDesign.accent)
                            Text("Searching nearby places")
                                .foregroundStyle(WayTaskDesign.primaryText)
                        }
                        .listRowBackground(Color.clear)
                    } else if suggestions.isEmpty {
                        ContentUnavailableView(
                            "No suggestions found",
                            systemImage: "magnifyingglass",
                            description: Text("Try a more specific product name or add a place manually from the map.")
                        )
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(suggestions, id: \.self) { mapItem in
                            Button {
                                assign(item, to: mapItem)
                                suggestionItem = nil
                            } label: {
                                SuggestionPlaceRow(mapItem: mapItem)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        suggestionItem = nil
                    }
                    .tint(WayTaskDesign.accent)
                }
            }
        }
    }

    private var summaryText: String {
        "\(products.count) library products • \(currentShoppingEntries.count) in Shopping"
    }

    private var activeShoppingItems: [ShoppingItem] {
        currentShoppingEntries
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap(legacyItem)
            .filter { !$0.isCompleted }
    }

    private var productLibrarySignature: String {
        products
            .map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
    }

    private var activeSession: ShoppingSession? {
        shoppingSessions
            .filter(\.isActive)
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var filteredItems: [ShoppingItem] {
        items.filter { item in
            if item.id == appStateManager.recentlyAddedShoppingItemID {
                return true
            }

            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText)

            guard matchesSearch else {
                return false
            }

            switch selectedFilter {
            case .all:
                return true
            case .inShopping:
                return !item.isCompleted
            case .notInShopping:
                return item.isCompleted
            }
        }
    }

    private var filteredProducts: [Product] {
        products
            .filter { product in
                let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    product.name.localizedCaseInsensitiveContains(searchText) ||
                    (product.brand?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (product.category?.localizedCaseInsensitiveContains(searchText) ?? false)

                guard matchesSearch else {
                    return false
                }

                switch selectedFilter {
                case .all:
                    return true
                case .inShopping:
                    return isProductInCurrentShoppingList(product)
                case .notInShopping:
                    return !isProductInCurrentShoppingList(product)
                }
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    private var selectedShoppingListID: UUID? {
        appStateManager.selectedShoppingListID ??
            appStateManager.currentShoppingListID ??
            shoppingLists.first { $0.kind == .weekly }?.id
    }

    private var currentShoppingEntries: [ShoppingListEntry] {
        guard let selectedShoppingListID else {
            return []
        }

        return shoppingListEntries.filter { $0.shoppingListID == selectedShoppingListID }
    }

    private func shoppingSessionItems(for session: ShoppingSession) -> [ShoppingItem] {
        let sessionItemIDs = Set(session.itemIDs)
        return items.filter { sessionItemIDs.contains($0.id) }
    }

    private func startShopping() {
        refreshSharedShoppingPlanForActiveItems()

        do {
            try shoppingSessionService.startShopping(with: activeShoppingItems, in: modelContext)
        } catch {
            assertionFailure("Failed to start shopping session: \(error.localizedDescription)")
        }
    }

    private func refreshSharedShoppingPlanForActiveItems() {
        guard !activeShoppingItems.isEmpty else {
            return
        }

        let request = appStateManager.storeSuggestionRequest ?? shoppingIntentMatcher.request(for: activeShoppingItems, in: .grocery)
        let userCoordinate = locationManager.currentCoordinate
        let candidateStores = suggestionStores(for: request, userCoordinate: userCoordinate)
        let buyingOptions = buyingOptionsService.localOptions(
            for: request,
            shoppingItems: activeShoppingItems,
            stores: candidateStores,
            userCoordinate: userCoordinate
        )
        let tripCoverages = shoppingTripService.coverage(
            for: activeShoppingItems,
            stores: candidateStores,
            request: request,
            userCoordinate: userCoordinate
        )
        appStateManager.setShoppingPlan(
            request: request,
            items: activeShoppingItems,
            stores: candidateStores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: tripCoverages
        )
    }

    private func toggleCollected(_ item: ShoppingItem, in session: ShoppingSession) {
        do {
            if session.isCollected(item) {
                try shoppingSessionService.markItemRemaining(item, in: session, modelContext: modelContext)
            } else {
                try shoppingSessionService.markItemCollected(item, in: session, modelContext: modelContext)
            }
        } catch {
            assertionFailure("Failed to update shopping session item: \(error.localizedDescription)")
        }
    }

    private func finishShopping(_ session: ShoppingSession) {
        do {
            try shoppingSessionService.finishShopping(session, in: modelContext)
        } catch {
            assertionFailure("Failed to finish shopping session: \(error.localizedDescription)")
        }
    }

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        do {
            try shoppingListService.addManualProduct(
                name: name,
                imageData: selectedImageData,
                in: modelContext
            )
            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
            resetForm()
        } catch {
            assertionFailure("Failed to add manual shopping item: \(error.localizedDescription)")
        }
    }

    private func loadSelectedPhoto() {
        Task {
            selectedImageData = try? await selectedPhotoItem?.loadTransferable(type: Data.self)
        }
    }

    private func resetForm() {
        newItemName = ""
        selectedLocationID = nil
        selectedPhotoItem = nil
        selectedImageData = nil
    }

    private func showAllProducts() {
        searchText = ""
        selectedFilter = .all
    }

    private func deleteFilteredProducts(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let product = filteredProducts[index]
            let listIDs = Set(shoppingListEntries.filter { $0.productID == product.id }.map(\.shoppingListID))
            for shoppingListID in listIDs {
                try? shoppingListService.removeProductFromShopping(
                    product,
                    shoppingListID: shoppingListID,
                    in: modelContext
                )
            }
            modelContext.delete(product)
        }
        appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
    }

    private func addProductToShopping(_ product: Product) {
        guard let selectedShoppingListID else {
            return
        }

        do {
            try shoppingListService.addProductToShopping(
                product,
                shoppingListID: selectedShoppingListID,
                in: modelContext
            )
            appStateManager.shoppingListDidChange()
            appStateManager.markShoppingPlanStale(reason: "Shopping list changed. Generate a new plan before viewing stores.")
        } catch {
            assertionFailure("Failed to add product to shopping: \(error.localizedDescription)")
        }
    }

    private func removeProductFromShopping(_ product: Product) {
        guard let selectedShoppingListID else {
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
        } catch {
            assertionFailure("Failed to remove product from shopping: \(error.localizedDescription)")
        }
    }

    private func isProductInCurrentShoppingList(_ product: Product) -> Bool {
        currentShoppingEntries.contains { $0.productID == product.id }
    }

    private func legacyItem(for entry: ShoppingListEntry) -> ShoppingItem? {
        guard let legacyShoppingItemID = entry.legacyShoppingItemID else {
            return nil
        }

        return items.first { $0.id == legacyShoppingItemID }
    }

    private func assignedLocation(for item: ShoppingItem) -> GeoLocation? {
        locations.first { location in
            location.shoppingItems.contains { $0.id == item.id }
        }
    }

    private func remove(_ item: ShoppingItem, from locations: [GeoLocation]) {
        for location in locations {
            location.shoppingItems.removeAll { $0.id == item.id }
        }
    }

    private func replaceImage(for product: Product, imageData: Data?) {
        guard let imageData else {
            return
        }

        product.imageData = imageData
        product.updatedAt = Date()
        syncCompatibilityItems(from: product)
        try? modelContext.save()
        appStateManager.shoppingListDidChange()
    }

    private func cacheRemoteImage(for product: Product, imageData: Data) {
        guard product.imageData == nil else {
            return
        }

        product.imageData = imageData
        product.updatedAt = Date()
        syncCompatibilityItems(from: product)
        try? modelContext.save()
        appStateManager.shoppingListDidChange()
    }

    private func memoryIndicators(for product: Product) -> [String] {
        guard let item = compatibilityItem(for: product) else {
            return []
        }

        guard let history = try? shoppingMemoryService.productHistory(for: item, in: modelContext),
              productHistories.contains(where: { $0.id == history.id }) else {
            return []
        }

        var indicators: [String] = []

        if history.addCount >= 3 {
            indicators.append("Frequent")
        }

        if history.addCount > 1 {
            indicators.append("Added \(history.addCount)x")
        }

        let daysSinceLastAdded = Calendar.current.dateComponents([.day], from: history.lastAddedDate, to: Date()).day ?? 0
        if history.addCount > 1 && indicators.count < 2 && daysSinceLastAdded <= 7 {
            indicators.append("Recent")
        }

        return Array(indicators.prefix(2))
    }

    private func compatibilityItem(for product: Product) -> ShoppingItem? {
        if let legacyShoppingItemID = product.legacyShoppingItemID,
           let item = items.first(where: { $0.id == legacyShoppingItemID }) {
            return item
        }

        if let barcode = product.barcode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !barcode.isEmpty,
           let item = items.first(where: { $0.barcode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == barcode }) {
            return item
        }

        return nil
    }

    private func syncCompatibilityItems(from product: Product) {
        let matchingEntries = shoppingListEntries.filter { $0.productID == product.id }
        let legacyIDs = Set(matchingEntries.compactMap(\.legacyShoppingItemID) + [product.legacyShoppingItemID].compactMap { $0 })

        for item in items where legacyIDs.contains(item.id) {
            item.name = product.name
            item.imageData = product.imageData
            item.brand = product.brand
            item.category = product.category
            item.barcode = product.barcode
            item.imageURLString = product.imageURL?.absoluteString
            item.sourceRawValue = product.source.rawValue
            item.productType = product.productType
            item.flavor = product.flavor
            item.packageSize = product.packageSize
            item.packageType = product.packageType
            item.visibleText = product.visibleText
            item.searchKeywords = product.searchKeywords
        }
    }

    private func findSuggestions(for item: ShoppingItem) {
        let request = shoppingIntentMatcher.suggestionRequest(for: item)
        let groups = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems)
        ShoppingDiscoveryDebugLogger.logGroups(
            context: "Suggest Places / Buying Options",
            groups: groups
        )
        let userCoordinate = locationManager.currentCoordinate
        let candidateStores = suggestionStores(for: request, userCoordinate: userCoordinate)
        auditBuyingOptionsStores(
            phase: "initial",
            stores: candidateStores,
            request: request,
            userCoordinate: userCoordinate,
            fallbackUsed: candidateStores.contains { $0.sourceType == .local }
        )
        let buyingOptions = buyingOptionsService.localOptions(
            for: request,
            shoppingItems: activeShoppingItems,
            stores: candidateStores,
            userCoordinate: userCoordinate
        )
        let tripCoverages = shoppingTripService.coverage(
            for: activeShoppingItems,
            stores: candidateStores,
            request: request,
            userCoordinate: userCoordinate
        )
        buyingOptionsRequest = request
        appStateManager.setShoppingPlan(
            request: request,
            items: activeShoppingItems,
            stores: candidateStores,
            buyingOptions: buyingOptions,
            shoppingTripCoverages: tripCoverages
        )
        isShowingBuyingOptions = true

        if userCoordinate == nil {
            ShoppingDiscoveryDebugLogger.logStoreSearchRequests(
                context: "Suggest Places / Buying Options: no current coordinate",
                groups: groups,
                requests: []
            )
        }
        refreshSuggestionsWithMapKit(for: request)
    }

    private func refreshCurrentBuyingOptions() {
        guard let buyingOptionsRequest else {
            return
        }

        refreshSuggestionsWithMapKit(for: buyingOptionsRequest, forceRefresh: true)
    }

    private func refreshSuggestionsWithMapKit(for request: ShoppingStoreSuggestionRequest, forceRefresh: Bool = false) {
        guard let coordinate = locationManager.currentCoordinate else {
            return
        }

        let groups = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems)
        let discoveryRequests = groupedStoreDiscoveryRequests(fallback: request)
        ShoppingDiscoveryDebugLogger.logStoreSearchRequests(
            context: forceRefresh ? "Buying Options refresh" : "Buying Options MapKit discovery",
            groups: groups,
            requests: discoveryRequests
        )
        suggestionRefreshGeneration += 1
        let refreshGeneration = suggestionRefreshGeneration
        isRefreshingBuyingOptions = true
        Task {
            let discoveredStores = await discoveredStoresByGroup(
                around: coordinate,
                discoveryRequests: discoveryRequests,
                forceRefresh: forceRefresh
            )
            let mergedStores = mergedSuggestionStores(
                savedStores: savedStoresForTripPlanning(),
                discoveredStores: discoveredStores,
                request: request
            )
            auditBuyingOptionsStores(
                phase: forceRefresh ? "mapkit-refresh" : "mapkit",
                stores: mergedStores,
                request: request,
                userCoordinate: coordinate,
                fallbackUsed: mergedStores.contains { $0.sourceType == .local }
            )
            let buyingOptions = buyingOptionsService.localOptions(
                for: request,
                shoppingItems: activeShoppingItems,
                stores: mergedStores,
                userCoordinate: coordinate
            )
            let tripCoverages = shoppingTripService.coverage(
                for: activeShoppingItems,
                stores: mergedStores,
                request: request,
                userCoordinate: coordinate
            )

            guard refreshGeneration == suggestionRefreshGeneration else {
                return
            }

            appStateManager.setShoppingPlan(
                request: request,
                items: activeShoppingItems,
                stores: mergedStores,
                buyingOptions: buyingOptions,
                shoppingTripCoverages: tripCoverages
            )
            isRefreshingBuyingOptions = false
        }
    }

    private func groupedStoreDiscoveryRequests(fallback request: ShoppingStoreSuggestionRequest) -> [(request: ShoppingStoreSuggestionRequest, itemNames: [String])] {
        let groups = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems)
        guard !groups.isEmpty else {
            return [(request, [request.itemName])]
        }

        return groups.map { group in
            (shoppingIntentMatcher.request(for: group), group.itemNames)
        }
    }

    private func discoveredStoresByGroup(
        around coordinate: CLLocationCoordinate2D,
        discoveryRequests: [(request: ShoppingStoreSuggestionRequest, itemNames: [String])],
        forceRefresh: Bool
    ) async -> [MapStore] {
        var discoveredStores: [MapStore] = []

        for discoveryRequest in discoveryRequests {
            let groupStores: [MapStore]
            if forceRefresh {
                groupStores = await storeSearchService.refreshedStores(
                    around: coordinate,
                    shoppingItems: discoveryRequest.itemNames,
                    storeCategories: discoveryRequest.request.storeCategories
                )
            } else {
                groupStores = await storeSearchService.stores(
                    around: coordinate,
                    shoppingItems: discoveryRequest.itemNames,
                    storeCategories: discoveryRequest.request.storeCategories
                )
            }

            discoveredStores.append(contentsOf: groupStores)
        }

        return discoveredStores.deduplicatedStores()
    }

    private func openBuyingOptionsOnMap() {
        guard let buyingOptionsRequest else {
            isShowingBuyingOptions = false
            return
        }

        let groups = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems)
        ShoppingDiscoveryDebugLogger.logGroups(
            context: "Buying Options View Map",
            groups: groups
        )
        isShowingBuyingOptions = false
        appStateManager.suggestStores(
            for: buyingOptionsRequest,
            items: activeShoppingItems,
            stores: appStateManager.shoppingPlan?.stores ?? [],
            buyingOptions: appStateManager.buyingOptions,
            shoppingTripCoverages: appStateManager.shoppingTripCoverages
        )
    }

    private func openTripOnMap() {
        guard let buyingOptionsRequest else {
            isShowingBuyingOptions = false
            return
        }

        let groups = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems)
        ShoppingDiscoveryDebugLogger.logGroups(
            context: "Shopping Trip View Map",
            groups: groups
        )
        isShowingBuyingOptions = false
        appStateManager.showTripOnMap(
            for: buyingOptionsRequest,
            items: activeShoppingItems,
            stores: appStateManager.shoppingPlan?.stores ?? [],
            buyingOptions: appStateManager.buyingOptions,
            shoppingTripCoverages: appStateManager.shoppingTripCoverages
        )
    }

    private func suggestionStores(for request: ShoppingStoreSuggestionRequest, userCoordinate: CLLocationCoordinate2D?) -> [MapStore] {
        let savedStores = savedStoresForTripPlanning()
        let relevantSavedStores = savedStores.map(retagStoreForActiveIntentGroups).filter { store in
            storeMatches(store, request: request, userCoordinate: userCoordinate)
        }

        if !relevantSavedStores.isEmpty {
            return relevantSavedStores
        }

        if userCoordinate != nil {
            return []
        }

        return savedStores
            .map(retagStoreForActiveIntentGroups)
            .filter { storeMatches($0, request: request, userCoordinate: nil) }
    }

    private func mergedSuggestionStores(
        savedStores: [MapStore],
        discoveredStores: [MapStore],
        request: ShoppingStoreSuggestionRequest
    ) -> [MapStore] {
        let retaggedSavedStores = savedStores.map(retagStoreForActiveIntentGroups)
        let retaggedDiscoveredStores = discoveredStores.map(retagStoreForActiveIntentGroups)
        let relevantSavedStores = retaggedSavedStores.filter { storeMatches($0, request: request, userCoordinate: locationManager.currentCoordinate) }
        let baseSavedStores = relevantSavedStores.isEmpty ? retaggedSavedStores : relevantSavedStores
        let appleMapStores = retaggedDiscoveredStores.filter { $0.sourceType == .appleMaps }
        let filteredDiscoveredStores = retaggedDiscoveredStores.filter { store in
            store.sourceType != .local || !hasAppleMapsMatch(for: store, in: appleMapStores)
        }

        return (baseSavedStores + filteredDiscoveredStores)
            .deduplicatedStores()
            .filter { store in
                storeMatches(store, request: request, userCoordinate: locationManager.currentCoordinate)
            }
    }

    private func hasAppleMapsMatch(for store: MapStore, in appleMapStores: [MapStore]) -> Bool {
        appleMapStores.contains { appleStore in
            appleStore.storeCategories.contains { appleCategory in
                store.storeCategories.contains { storeCategory in
                    appleCategory.matches(storeCategory) || storeCategory.matches(appleCategory)
                }
            }
        }
    }

    private func savedStoresForTripPlanning() -> [MapStore] {
        locations.filter(shouldIncludeLocationInRecommendations).map { location in
            let openItems = location.shoppingItems
                .filter { !$0.isCompleted }
                .map(\.name)
            let completedItems = location.shoppingItems
                .filter(\.isCompleted)
                .map(\.name)

            return MapStore(
                id: location.id,
                locationID: location.id,
                title: location.title,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                radius: location.radius,
                itemNames: openItems,
                completedItemNames: completedItems,
                isOpen: true,
                rating: 4.4 + (Double(min(location.shoppingItems.count, 4)) * 0.1),
                storeCategories: location.storeCategory.map { [$0] } ?? [],
                queryEvidenceCategories: [],
                websiteURL: nil,
                sourceType: location.sourceType
            )
        }
    }

    private func storeMatches(_ store: MapStore, request: ShoppingStoreSuggestionRequest, userCoordinate: CLLocationCoordinate2D?) -> Bool {
        guard !store.itemNames.isEmpty else {
            return false
        }

        let groupRequests = shoppingIntentMatcher.groupedIntents(for: activeShoppingItems).map(\.request)
        if !groupRequests.isEmpty {
            return groupRequests.contains { groupRequest in
                storeRankingService.isRelevant(
                    store: store,
                    request: groupRequest,
                    userCoordinate: userCoordinate
                )
            }
        }

        return storeRankingService.isRelevant(
            store: store,
            request: request,
            userCoordinate: userCoordinate
        )
    }

    private func retagStoreForActiveIntentGroups(_ store: MapStore) -> MapStore {
        let relevantItems = shoppingIntentMatcher.relevantItems(from: activeShoppingItems, for: store)
        let itemNames = relevantItems.map(\.name).deduplicatedCaseInsensitive()

        return MapStore(
            id: store.id,
            locationID: store.locationID,
            title: store.title,
            coordinate: store.coordinate,
            radius: store.radius,
            itemNames: itemNames,
            completedItemNames: store.completedItemNames,
            isOpen: store.isOpen,
            rating: store.rating,
            storeCategories: store.storeCategories,
            queryEvidenceCategories: store.queryEvidenceCategories,
            websiteURL: store.websiteURL,
            sourceType: store.sourceType
        )
    }

    private func auditBuyingOptionsStores(
        phase: String,
        stores: [MapStore],
        request: ShoppingStoreSuggestionRequest,
        userCoordinate: CLLocationCoordinate2D?,
        fallbackUsed: Bool
    ) {
        #if DEBUG
        print("[WayTask Store Audit] BuyingOptions phase=\(phase) count=\(stores.count) fallbackUsed=\(fallbackUsed) categories=\(request.storeCategories.map(\.rawValue).joined(separator: ","))")
        for store in stores {
            let distanceText: String
            if let userCoordinate {
                distanceText = "\(Int(distance(from: userCoordinate, to: store.coordinate)))m"
            } else {
                distanceText = "unknown"
            }

            let rejectionReason = ShoppingStoreCategoryFilter.rejectionReason(
                storeTitle: store.title,
                storeCategories: store.storeCategories,
                requestedCategories: request.storeCategories,
                distanceMeters: {
                    guard let userCoordinate else {
                        return nil
                    }

                    return distance(from: userCoordinate, to: store.coordinate)
                }()
            )
            let status = rejectionReason == nil ? "accepted" : "rejected"
            print("[WayTask Store Audit] \(status) name=\"\(store.title)\" source=\(store.sourceType.rawValue) distance=\(distanceText) category=\(store.storeCategories.map(\.rawValue).joined(separator: ",")) reason=\"\(rejectionReason ?? "eligible")\"")
        }
        #endif
    }

    private func distance(from userCoordinate: CLLocationCoordinate2D, to storeCoordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude))
    }

    private func shouldIncludeLocationInRecommendations(_ location: GeoLocation) -> Bool {
        guard location.sourceType == .debugSeed else {
            return true
        }

        #if DEBUG
        return DebugSeedStoreService.isEnabled
        #else
        return false
        #endif
    }

    private func assign(_ item: ShoppingItem, to mapItem: MKMapItem) {
        let coordinate = mapItem.location.coordinate
        let title = mapItem.name ?? item.name
        let location = GeoLocation(
            title: title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: 300.0
        )

        remove(item, from: locations)
        modelContext.insert(location)
        location.shoppingItems.append(item)
        try? modelContext.save()
        appStateManager.focusMap(on: location.id)
    }
}

private enum ProductFilter: String, CaseIterable, Identifiable {
    case all
    case inShopping
    case notInShopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .inShopping:
            return "In Shopping"
        case .notInShopping:
            return "Library Only"
        }
    }
}

private struct ProductRowCard: View {
    @Bindable var product: Product
    let isInShopping: Bool
    let memoryIndicators: [String]
    let onAddToShopping: () -> Void
    let onRemoveFromShopping: () -> Void
    let onImageSelected: (Data?) -> Void
    let onRemoteImageLoaded: (Data) -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                WayTaskProductThumbnail(
                    data: product.imageData,
                    url: product.imageURL,
                    size: 72,
                    cornerRadius: 17,
                    onRemoteImageLoaded: onRemoteImageLoaded
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(product.name)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)

                    if let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
                        Text(brand)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                    }

                    if let productDetails {
                        Text(productDetails)
                            .font(.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Label(isInShopping ? "Already in Shopping" : "Product Library", systemImage: isInShopping ? "cart.badge.checkmark" : "shippingbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isInShopping ? WayTaskDesign.accent : WayTaskDesign.secondaryText)
                        .lineLimit(1)

                    if !memoryIndicators.isEmpty {
                        MemoryIndicatorRow(indicators: memoryIndicators)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isInShopping ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isInShopping ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                    .animation(.spring(), value: isInShopping)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                if isInShopping {
                    Button(action: onRemoveFromShopping) {
                        Label("Remove from Shopping", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WayTaskSecondaryPillButtonStyle())
                    .accessibilityLabel("Remove \(product.name) from Shopping")
                } else {
                    Button(action: onAddToShopping) {
                        Label("Add to Shopping", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WayTaskPrimaryPillButtonStyle())
                    .accessibilityLabel("Add \(product.name) to Shopping")
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .frame(width: 42)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())
                .accessibilityLabel("Change Product Image")
                .onChange(of: selectedPhotoItem) {
                    loadSelectedPhoto()
                }
            }
        }
        .padding(16)
        .wayTaskCard()
    }

    private func loadSelectedPhoto() {
        Task {
            let imageData = try? await selectedPhotoItem?.loadTransferable(type: Data.self)
            onImageSelected(imageData)
            selectedPhotoItem = nil
        }
    }

    private var productDetails: String? {
        let aiDetails = [
            product.productType,
            product.flavor,
            product.packageSize
        ]
        .compactDetails()

        if !aiDetails.isEmpty {
            return aiDetails.prefix(3).joined(separator: " • ")
        }

        let fallbackDetails = [product.category]
            .compactDetails()

        guard !fallbackDetails.isEmpty else {
            return nil
        }

        return fallbackDetails.joined(separator: " • ")
    }
}

private extension Array where Element == String? {
    func compactDetails() -> [String] {
        compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                    result.append(value)
                }
            }
    }
}

private struct MemoryIndicatorRow: View {
    let indicators: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(indicators.prefix(2), id: \.self) { indicator in
                HStack(spacing: 4) {
                    Image(systemName: iconName(for: indicator))
                        .font(.caption2.weight(.bold))

                    Text(indicator)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(WayTaskDesign.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(WayTaskDesign.accent.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shopping memory: \(indicators.prefix(2).joined(separator: ", "))")
    }

    private func iconName(for indicator: String) -> String {
        if indicator == "Frequent" {
            return "arrow.triangle.2.circlepath"
        }

        if indicator.hasPrefix("Added") {
            return "plus.circle.fill"
        }

        return "clock.fill"
    }
}

private struct NearbyOpportunityRow: View {
    let opportunity: NearbyShoppingOpportunity
    let onOpenMap: () -> Void

    var body: some View {
        Button(action: onOpenMap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
                    .frame(width: 40, height: 40)
                    .background(WayTaskDesign.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(opportunity.title)
                            .font(.headline)
                            .foregroundStyle(WayTaskDesign.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(opportunity.distanceText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WayTaskDesign.accent)
                            .lineLimit(1)
                    }

                    Text(opportunity.itemSummary)
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(opportunity.sourceType.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .wayTaskCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(opportunity.title), \(opportunity.distanceText). \(opportunity.itemSummary)")
    }
}

private struct ShoppingSessionMetric: View {
    let title: String
    let value: String
    let iconName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 28, height: 28)
                .background(WayTaskDesign.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WayTaskDesign.surface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ShoppingSessionItemRow: View {
    let item: ShoppingItem
    let isCollected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isCollected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isCollected ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isCollected)

                WayTaskProductThumbnail(data: item.imageData, url: item.imageURL, size: 52, cornerRadius: 14)
                    .opacity(isCollected ? 0.6 : 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .strikethrough(isCollected)
                        .lineLimit(2)

                    if let brand = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
                        Text(brand)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                    }

                    Text(isCollected ? "Collected" : "Remaining")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isCollected ? WayTaskDesign.accent : WayTaskDesign.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .wayTaskCard()
        .opacity(isCollected ? 0.72 : 1)
        .accessibilityLabel("\(item.name), \(isCollected ? "collected" : "remaining")")
    }
}

private struct SuggestionPlaceRow: View {
    let mapItem: MKMapItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 42, height: 42)
                .background(WayTaskDesign.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(mapItem.name ?? "Suggested Place")
                    .font(.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)

                if let address = mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.tertiaryText)
        }
        .padding(14)
        .wayTaskCard()
    }
}

private extension Array where Element == ShoppingStoreCategory {
    func deduplicated() -> [ShoppingStoreCategory] {
        reduce(into: [ShoppingStoreCategory]()) { result, category in
            if !result.contains(category) {
                result.append(category)
            }
        }
    }
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        reduce(into: [String]()) { result, value in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
                result.append(value)
            }
        }
    }
}

private extension Array where Element == MapStore {
    func deduplicatedStores() -> [MapStore] {
        reduce(into: [MapStore]()) { result, store in
            let isDuplicate = result.contains { existingStore in
                existingStore.title.localizedCaseInsensitiveCompare(store.title) == .orderedSame ||
                distance(from: existingStore.coordinate, to: store.coordinate) < 35
            }

            if !isDuplicate {
                result.append(store)
            }
        }
    }

    private func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }
}
