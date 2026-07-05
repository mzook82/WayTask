import MapKit
import PhotosUI
import SwiftData
import SwiftUI

struct ProductListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager
    @EnvironmentObject private var locationManager: LocationManager

    @Query private var items: [ShoppingItem]
    @Query private var locations: [GeoLocation]
    @Query private var productHistories: [ProductHistory]
    @Query private var shoppingSessions: [ShoppingSession]

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
                    if let activeSession {
                        shoppingSessionContent(for: activeSession)
                    } else {
                        header
                        filterBar
                        productList
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if activeSession == nil {
                    bottomActionBar
                }
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
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Lists")
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

                    Picker("Place", selection: $selectedLocationID) {
                        Text("No place yet").tag(Optional<UUID>.none)

                        ForEach(locations) { location in
                            Text(location.title).tag(Optional(location.id))
                        }
                    }
                    .tint(WayTaskDesign.accent)
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
                startShopping()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 44, cornerRadius: 14))
            .disabled(activeShoppingItems.isEmpty)
            .opacity(activeShoppingItems.isEmpty ? 0.42 : 1)
            .accessibilityLabel("Start Shopping")
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

            if filteredItems.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets(top: 42, leading: 20, bottom: 42, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredItems) { item in
                    ProductRowCard(
                        item: item,
                        location: assignedLocation(for: item),
                        memoryIndicators: memoryIndicators(for: item),
                        onToggle: {
                            withAnimation(.spring()) {
                                item.isCompleted.toggle()
                            }
                        },
                        onSuggest: {
                            findSuggestions(for: item)
                        },
                        onImageSelected: { imageData in
                            replaceImage(for: item, imageData: imageData)
                        },
                        onRemoteImageLoaded: { imageData in
                            cacheRemoteImage(for: item, imageData: imageData)
                        },
                        onOpenMap: { location in
                            appStateManager.focusMap(on: location.id)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: deleteFilteredItems)
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

            Text(items.isEmpty ? "No products yet" : "No matching products")
                .font(.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text(items.isEmpty ? "Add products here first, then connect them to nearby places." : "Try changing the search or filter.")
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
        let openCount = items.filter { !$0.isCompleted }.count
        let assignedCount = items.filter { assignedLocation(for: $0) != nil }.count
        return "\(items.count) items • \(openCount) open • \(assignedCount) placed"
    }

    private var activeShoppingItems: [ShoppingItem] {
        items.filter { !$0.isCompleted }
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
            case .open:
                return !item.isCompleted
            case .placed:
                return assignedLocation(for: item) != nil
            case .done:
                return item.isCompleted
            }
        }
    }

    private func shoppingSessionItems(for session: ShoppingSession) -> [ShoppingItem] {
        let sessionItemIDs = Set(session.itemIDs)
        return items.filter { sessionItemIDs.contains($0.id) }
    }

    private func startShopping() {
        do {
            try shoppingSessionService.startShopping(with: activeShoppingItems, in: modelContext)
        } catch {
            assertionFailure("Failed to start shopping session: \(error.localizedDescription)")
        }
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

        let location = selectedLocationID.flatMap { locationID in
            locations.first { $0.id == locationID }
        }

        do {
            try shoppingListService.addManualItem(
                name: name,
                imageData: selectedImageData,
                location: location,
                in: modelContext
            )
            appStateManager.shoppingListDidChange()
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

    private func deleteFilteredItems(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let item = filteredItems[index]
            remove(item, from: locations)
            modelContext.delete(item)
        }
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

    private func replaceImage(for item: ShoppingItem, imageData: Data?) {
        guard let imageData else {
            return
        }

        item.imageData = imageData
        try? modelContext.save()
        _ = try? ProductKnowledgeService().learn(from: item, in: modelContext)
        appStateManager.shoppingListDidChange(revealing: item.id)
    }

    private func cacheRemoteImage(for item: ShoppingItem, imageData: Data) {
        guard item.imageData == nil else {
            return
        }

        item.imageData = imageData
        try? modelContext.save()
        _ = try? ProductKnowledgeService().learn(from: item, in: modelContext)
    }

    private func memoryIndicators(for item: ShoppingItem) -> [String] {
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

    private func findSuggestions(for item: ShoppingItem) {
        let request = fullListSuggestionRequest(for: item)
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
        appStateManager.storeSuggestionRequest = request
        appStateManager.buyingOptions = buyingOptions
        appStateManager.shoppingTripCoverages = tripCoverages
        isShowingBuyingOptions = true

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

        let shoppingItemNames = activeShoppingItems.map(\.name)
        suggestionRefreshGeneration += 1
        let refreshGeneration = suggestionRefreshGeneration
        isRefreshingBuyingOptions = true
        Task {
            let discoveredStores: [MapStore]
            if forceRefresh {
                discoveredStores = await storeSearchService.refreshedStores(
                    around: coordinate,
                    shoppingItems: shoppingItemNames,
                    storeCategories: request.storeCategories
                )
            } else {
                discoveredStores = await storeSearchService.stores(
                    around: coordinate,
                    shoppingItems: shoppingItemNames,
                    storeCategories: request.storeCategories
                )
            }
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

            appStateManager.buyingOptions = buyingOptions
            appStateManager.shoppingTripCoverages = tripCoverages
            isRefreshingBuyingOptions = false
        }
    }

    private func fullListSuggestionRequest(for selectedItem: ShoppingItem) -> ShoppingStoreSuggestionRequest {
        let selectedRequest = shoppingIntentMatcher.suggestionRequest(for: selectedItem)
        let listRequests = activeShoppingItems.map { shoppingIntentMatcher.suggestionRequest(for: $0) }
        let categories = listRequests
            .flatMap(\.storeCategories)
            .deduplicated()
        let searchTerms = listRequests
            .flatMap(\.searchTerms)
            .deduplicatedCaseInsensitive()

        return ShoppingStoreSuggestionRequest(
            itemID: selectedRequest.itemID,
            itemName: selectedRequest.itemName,
            itemCategory: selectedRequest.itemCategory,
            storeCategories: categories.isEmpty ? selectedRequest.storeCategories : categories,
            searchTerms: searchTerms.isEmpty ? selectedRequest.searchTerms : searchTerms
        )
    }

    private func openBuyingOptionsOnMap() {
        guard let buyingOptionsRequest else {
            isShowingBuyingOptions = false
            return
        }

        isShowingBuyingOptions = false
        appStateManager.suggestStores(
            for: buyingOptionsRequest,
            buyingOptions: appStateManager.buyingOptions,
            shoppingTripCoverages: appStateManager.shoppingTripCoverages
        )
    }

    private func openTripOnMap() {
        guard let buyingOptionsRequest else {
            isShowingBuyingOptions = false
            return
        }

        isShowingBuyingOptions = false
        appStateManager.showTripOnMap(
            for: buyingOptionsRequest,
            buyingOptions: appStateManager.buyingOptions,
            shoppingTripCoverages: appStateManager.shoppingTripCoverages
        )
    }

    private func suggestionStores(for request: ShoppingStoreSuggestionRequest, userCoordinate: CLLocationCoordinate2D?) -> [MapStore] {
        let savedStores = savedStoresForTripPlanning()
        let relevantSavedStores = savedStores.filter { store in
            storeMatches(store, request: request, userCoordinate: userCoordinate)
        }

        if !relevantSavedStores.isEmpty {
            return relevantSavedStores
        }

        if userCoordinate != nil {
            return []
        }

        return savedStores.filter { storeMatches($0, request: request, userCoordinate: nil) }
    }

    private func mergedSuggestionStores(
        savedStores: [MapStore],
        discoveredStores: [MapStore],
        request: ShoppingStoreSuggestionRequest
    ) -> [MapStore] {
        let relevantSavedStores = savedStores.filter { storeMatches($0, request: request, userCoordinate: locationManager.currentCoordinate) }
        let baseSavedStores = relevantSavedStores.isEmpty ? savedStores : relevantSavedStores
        let shouldDropFallback = !relevantSavedStores.isEmpty || discoveredStores.contains { $0.sourceType == .appleMaps }
        let filteredDiscoveredStores = shouldDropFallback
            ? discoveredStores.filter { $0.sourceType != .local }
            : discoveredStores

        return (baseSavedStores + filteredDiscoveredStores)
            .deduplicatedStores()
            .filter { store in
                storeMatches(store, request: request, userCoordinate: locationManager.currentCoordinate)
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
                websiteURL: nil,
                sourceType: location.sourceType
            )
        }
    }

    private func storeMatches(_ store: MapStore, request: ShoppingStoreSuggestionRequest, userCoordinate: CLLocationCoordinate2D?) -> Bool {
        let storeDistance: CLLocationDistance?
        if let userCoordinate {
            storeDistance = distance(from: userCoordinate, to: store.coordinate)
        } else {
            storeDistance = nil
        }
        guard ShoppingStoreCategoryFilter.isEligible(
            storeTitle: store.title,
            storeCategories: store.storeCategories,
            requestedCategories: request.storeCategories,
            distanceMeters: storeDistance
        ) else {
            return false
        }

        let matchesItem = store.itemNames.contains { itemName in
            itemName.localizedCaseInsensitiveContains(request.itemName) ||
            request.itemName.localizedCaseInsensitiveContains(itemName)
        }
        let matchesCategory = store.storeCategories.contains { storeCategory in
            request.storeCategories.contains { requestCategory in
                storeCategory.matches(requestCategory)
            }
        }
        let matchesTitle = request.storeCategories.contains { category in
            store.title.localizedCaseInsensitiveContains(category.sampleStoreName) ||
            store.title.localizedCaseInsensitiveContains(category.storeFormTitle)
        }
        let genericRequestCanUseSavedCategory = request.storeCategories.contains(.generalStore) && store.isSavedLocation && !store.storeCategories.isEmpty

        return matchesItem || matchesCategory || matchesTitle || genericRequestCanUseSavedCategory
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
    case open
    case placed
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .open:
            return "Open"
        case .placed:
            return "Placed"
        case .done:
            return "Done"
        }
    }
}

private struct ProductRowCard: View {
    @Bindable var item: ShoppingItem
    let location: GeoLocation?
    let memoryIndicators: [String]
    let onToggle: () -> Void
    let onSuggest: () -> Void
    let onImageSelected: (Data?) -> Void
    let onRemoteImageLoaded: (Data) -> Void
    let onOpenMap: (GeoLocation) -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                WayTaskProductThumbnail(
                    data: item.imageData,
                    url: item.imageURL,
                    size: 72,
                    cornerRadius: 17,
                    onRemoteImageLoaded: onRemoteImageLoaded
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)

                    if let brand = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
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

                    if let location {
                        Label(location.title, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                    } else {
                        Label("No place selected", systemImage: "mappin.slash")
                            .font(.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                    }

                    if !memoryIndicators.isEmpty {
                        MemoryIndicatorRow(indicators: memoryIndicators)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(item.isCompleted ? WayTaskDesign.accent : WayTaskDesign.tertiaryText)
                        .animation(.spring(), value: item.isCompleted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "Mark product incomplete" : "Mark product complete")
            }
            .opacity(item.isCompleted ? 0.58 : 1)

            HStack(spacing: 10) {
                Button(action: onSuggest) {
                    Label("Suggest Places", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: location == nil ? .infinity : nil)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .frame(width: 42)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle())
                .accessibilityLabel("Change Product Image")
                .onChange(of: selectedPhotoItem) {
                    loadSelectedPhoto()
                }

                if let location {
                    Button {
                        onOpenMap(location)
                    } label: {
                        Label("Map", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WayTaskSecondaryPillButtonStyle())
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
            item.productType,
            item.flavor,
            item.packageSize
        ]
        .compactDetails()

        if !aiDetails.isEmpty {
            return aiDetails.prefix(3).joined(separator: " • ")
        }

        let fallbackDetails = [item.category]
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
