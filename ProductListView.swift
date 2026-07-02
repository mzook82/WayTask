import MapKit
import PhotosUI
import SwiftData
import SwiftUI

struct ProductListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager

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
    @State private var isShowingBuyingOptions = false
    private let shoppingListService = ShoppingListService()
    private let shoppingIntentMatcher = ShoppingIntentMatcher()
    private let buyingOptionsService = BuyingOptionsService()
    private let shoppingMemoryService = ShoppingMemoryService()
    private let shoppingTripService = ShoppingTripService()
    private let shoppingSessionService = ShoppingSessionService()
    @State private var suggestions: [MKMapItem] = []
    @State private var isSearchingSuggestions = false
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $suggestionItem) { item in
                suggestionSheet(for: item)
            }
            .sheet(isPresented: $isShowingBuyingOptions) {
                BuyingOptionsSheet(
                    options: appStateManager.buyingOptions,
                    tripCoverages: appStateManager.shoppingTripCoverages,
                    activeTripItemCount: activeShoppingItems.count,
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
            .onChange(of: selectedPhotoItem) {
                loadSelectedPhoto()
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
            WayTaskScreenHeader(
                title: "My Lists",
                subtitle: summaryText,
                trailingIcons: ["bell", "gearshape"]
            )
            WayTaskSearchField(placeholder: "Search products...", text: $searchText)
            addProductCard

            if !activeShoppingItems.isEmpty {
                startShoppingCard
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var addProductCard: some View {
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

    private var startShoppingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "cart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 44, height: 44)
                .background(WayTaskDesign.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to shop")
                    .font(.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)

                Text("\(activeShoppingItems.count) active items in your list")
                    .font(.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }

            Spacer(minLength: 8)

            Button {
                startShopping()
            } label: {
                Label("Start Shopping", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(WayTaskPrimaryPillButtonStyle())
        }
        .padding(16)
        .wayTaskCard()
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

    private func memoryIndicators(for item: ShoppingItem) -> [String] {
        guard let history = try? shoppingMemoryService.productHistory(for: item, in: modelContext),
              productHistories.contains(where: { $0.id == history.id }) else {
            return []
        }

        var indicators: [String] = []

        if history.addCount >= 3 {
            indicators.append("Frequently Bought")
        }

        if history.addCount > 1 {
            indicators.append("Added \(history.addCount) times")
        }

        let daysSinceLastAdded = Calendar.current.dateComponents([.day], from: history.lastAddedDate, to: Date()).day ?? 0
        if history.addCount > 1 && indicators.count < 2 && daysSinceLastAdded <= 7 {
            indicators.append("Last added recently")
        }

        return Array(indicators.prefix(2))
    }

    private func findSuggestions(for item: ShoppingItem) {
        let request = shoppingIntentMatcher.suggestionRequest(for: item)
        let buyingOptions = buyingOptionsService.localOptions(for: request)
        let tripCoverages = shoppingTripService.coverage(
            for: activeShoppingItems,
            stores: tripPlanningStores(for: request),
            request: request,
            userCoordinate: nil
        )
        buyingOptionsRequest = request
        appStateManager.storeSuggestionRequest = request
        appStateManager.buyingOptions = buyingOptions
        appStateManager.shoppingTripCoverages = tripCoverages
        isShowingBuyingOptions = true
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

    private func tripPlanningStores(for request: ShoppingStoreSuggestionRequest) -> [MapStore] {
        savedStoresForTripPlanning() + buyingOptionsService.suggestedStores(for: request)
    }

    private func savedStoresForTripPlanning() -> [MapStore] {
        locations.map { location in
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
                websiteURL: nil
            )
        }
    }

    private func assign(_ item: ShoppingItem, to mapItem: MKMapItem) {
        let coordinate = mapItem.placemark.coordinate
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
    let onOpenMap: (GeoLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                WayTaskProductThumbnail(data: item.imageData, size: 72, cornerRadius: 17)

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
        if indicator == "Frequently Bought" {
            return "arrow.triangle.2.circlepath"
        }

        if indicator.hasPrefix("Added") {
            return "plus.circle.fill"
        }

        return "clock.fill"
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

                WayTaskProductThumbnail(data: item.imageData, size: 52, cornerRadius: 14)
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

                if let address = mapItem.placemark.title {
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
