import Combine
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

private enum WayTaskProductionTab: Hashable {
    case home
    case products
    case camera
    case shopping
    case map

    var title: String {
        switch self {
        case .home: "Home"
        case .products: "Products"
        case .camera: "Camera"
        case .shopping: "Shopping"
        case .map: "Map"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .products: "shippingbox.fill"
        case .camera: "camera.viewfinder"
        case .shopping: "list.bullet.rectangle.fill"
        case .map: "map.fill"
        }
    }
}

/// Production presentation over the completed WT-033A runtime.
///
/// This layer renders target projections and submits target commands. It owns
/// no persistence context, compatibility adapter, migration, or runtime state.
struct WayTaskProductionRuntimeView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: WayTaskProductionTab = .home
    @State private var notificationStoreID: UUID?
    @StateObject private var nearbyNotifications =
        ProductionNearbyNotificationCoordinator()

    private let searchAvailability: ProductKnowledgeSearchAvailability

    /// Catalog decoding and index ownership live outside SwiftUI body
    /// evaluation. The immutable search service is shared across root-view
    /// reconstruction and prewarmed off the main interaction path.
    private static let productionSearchAvailability =
        ProductionProductKnowledgeFactory.makeSearchAvailability()

    init() {
        searchAvailability = Self.productionSearchAvailability
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WayTaskProductionHomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label(
                        WayTaskProductionTab.home.title,
                        systemImage: WayTaskProductionTab.home.systemImage
                    )
                }
                .tag(WayTaskProductionTab.home)

            WayTaskProductionProductsView(
                selectedTab: $selectedTab,
                searchAvailability: searchAvailability
            )
            .tabItem {
                Label(
                    WayTaskProductionTab.products.title,
                    systemImage: WayTaskProductionTab.products.systemImage
                )
            }
            .tag(WayTaskProductionTab.products)

            CameraView {
                selectedTab = .products
            }
            .tabItem {
                Label(
                    WayTaskProductionTab.camera.title,
                    systemImage: WayTaskProductionTab.camera.systemImage
                )
            }
            .tag(WayTaskProductionTab.camera)

            WayTaskProductionShoppingView(
                selectedTab: $selectedTab,
                searchAvailability: searchAvailability
            )
                .tabItem {
                    Label(
                        WayTaskProductionTab.shopping.title,
                        systemImage: WayTaskProductionTab.shopping.systemImage
                    )
                }
                .tag(WayTaskProductionTab.shopping)

            WayTaskProductionMapView(
                selectedTab: $selectedTab,
                notificationStoreID: notificationStoreID
            )
                .tabItem {
                    Label(
                        WayTaskProductionTab.map.title,
                        systemImage: WayTaskProductionTab.map.systemImage
                    )
                }
                .tag(WayTaskProductionTab.map)
        }
        .tint(WayTaskDesign.accent)
        .preferredColorScheme(.dark)
        .onAppear { runtime.refresh() }
        .task(id: nearbyMissionSignature) {
            nearbyNotifications.configure(
                list: selectedList,
                activate: scenePhase == .active
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                nearbyNotifications.applicationDidBecomeActive()
            }
        }
        .onReceive(
            nearbyNotifications.$pendingDeepLink.compactMap { $0 }
        ) { destination in
            if let listID = destination.shoppingListID {
                runtime.selectList(ProductStateListID(rawValue: listID))
            }
            notificationStoreID = nil
            selectedTab = .map
            DispatchQueue.main.async {
                notificationStoreID = destination.storeID
            }
            nearbyNotifications.consumeDeepLink()
        }
    }

    private var selectedList: ProductStateNamedListProjection? {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
        .first { $0.id == runtime.selectedListID }
    }

    private var nearbyMissionSignature: String {
        guard let selectedList else { return "no-selected-list" }
        return [
            selectedList.id.rawValue.uuidString,
            String(selectedList.revision.value),
            selectedList.neededEntries.map {
                [
                    $0.identity.id.rawValue.uuidString,
                    $0.product?.displayName ?? "",
                    $0.product?.catalogCategoryIDSnapshot ?? ""
                ].joined(separator: "=")
            }.joined(separator: "|")
        ].joined(separator: ":")
    }
}

// MARK: - Home

private struct WayTaskProductionHomeView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @EnvironmentObject private var account: StagingAccountController
    @Binding var selectedTab: WayTaskProductionTab
    @State private var isShowingStagingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WayTaskDesign.Spacing.lg) {
                    WayTaskScreenHeader(
                        title: "WayTask",
                        subtitle: "Your products and shopping, together"
                    )

                    heroCard
                    if account.internalStagingUIEnabled {
                        stagingAccountCard
                    }
                    quickActions
                    shoppingLists
                    recentProducts
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(WayTaskDesign.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProductStateProductID.self) { id in
                WayTaskProductionProductDetailView(productID: id)
            }
            .sheet(isPresented: $isShowingStagingAccount) {
                StagingAccountView()
                    .environmentObject(account)
            }
        }
    }

    private var stagingAccountCard: some View {
        Button {
            isShowingStagingAccount = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: account.snapshot.state == .guest
                    ? "person.crop.circle.badge.plus"
                    : "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(WayTaskDesign.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Staging Account")
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                    Text(stagingAccountSummary)
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }
            .padding(16)
            .wayTaskGlassCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("staging-account-entry")
    }

    private var stagingAccountSummary: String {
        switch account.snapshot.state {
        case .guest: "Guest · local data only"
        case .signingIn: "Signing in…"
        case .sessionExpired: "Session expired · local data preserved"
        case .recoverableSyncError: "Ownership protected · review required"
        case .signedInLocalDataNotBackedUp,
                .signedInInitialMigrationPending,
                .signedInSynchronizationPaused:
            "Signed in · migration not performed"
        case .signedInSynchronizationActive:
            "Signed in · sync remains unavailable"
        case .accountDeletionPending:
            "Account unavailable · local data preserved"
        }
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(WayTaskDesign.accentGradient)
                Image(systemName: "basket.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("Ready when you are")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                Text(homeSummary)
                    .font(.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .wayTaskGlassCard()
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Add Product", icon: "plus.circle.fill", tab: .products)
            quickAction("Scan", icon: "camera.viewfinder", tab: .camera)
            quickAction("Nearby", icon: "map.fill", tab: .map)
        }
    }

    private func quickAction(
        _ title: String,
        icon: String,
        tab: WayTaskProductionTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .wayTaskCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private var shoppingLists: some View {
        VStack(alignment: .leading, spacing: 12) {
            WayTaskSectionHeader(title: "Shopping Lists", actionTitle: "Open") {
                selectedTab = .shopping
            }

            if runtime.homeState.home.namedLists.isEmpty {
                WayTaskEmptyState(
                    title: "No shopping lists",
                    message: "Create a list and start planning your next trip.",
                    systemImage: "list.bullet.rectangle",
                    actionTitle: "Open Shopping"
                ) {
                    selectedTab = .shopping
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(runtime.homeState.home.namedLists) { list in
                            Button {
                                runtime.selectList(list.id)
                                selectedTab = .shopping
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: "list.bullet.rectangle.fill")
                                        .font(.title2)
                                        .foregroundStyle(WayTaskDesign.accent)
                                    Text(list.title)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(WayTaskDesign.primaryText)
                                        .lineLimit(1)
                                    Text("\(list.neededCount) needed · \(list.resolvedCount) resolved")
                                        .font(.caption)
                                        .foregroundStyle(WayTaskDesign.secondaryText)
                                }
                                .frame(width: 190, alignment: .leading)
                                .padding(16)
                                .wayTaskGlassCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var recentProducts: some View {
        VStack(alignment: .leading, spacing: 12) {
            WayTaskSectionHeader(title: "Products", actionTitle: "See all") {
                selectedTab = .products
            }

            if runtime.homeState.home.productCards.isEmpty {
                Text("Products you add will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .wayTaskCard()
            } else {
                ForEach(runtime.homeState.home.productCards.prefix(4)) { card in
                    NavigationLink(value: card.id) {
                        WayTaskProductionProductRow(product: card.row.product)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var homeSummary: String {
        let products = runtime.homeState.home.productLibraryCount
        let lists = runtime.homeState.home.namedLists.count
        return "\(products) products across \(lists) shopping \(lists == 1 ? "list" : "lists")"
    }
}

// MARK: - Products

private struct WayTaskProductionProductsView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Binding var selectedTab: WayTaskProductionTab
    let searchAvailability: ProductKnowledgeSearchAvailability

    @State private var searchText = ""
    @State private var isAddingCatalogProduct = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if visibleProducts.isEmpty {
                        WayTaskEmptyState(
                            title: searchText.isEmpty
                                ? "No products yet" : "No matching products",
                            message: searchText.isEmpty
                                ? "Add from the catalog or scan a product with the Camera."
                                : "Try another product name or category.",
                            systemImage: "shippingbox",
                            actionTitle: searchText.isEmpty
                                ? "Add from Catalog" : "Clear Search"
                        ) {
                            if searchText.isEmpty {
                                isAddingCatalogProduct = true
                            }
                            else { searchText = "" }
                        }
                    } else {
                        ForEach(visibleProducts) { row in
                            NavigationLink(value: row.id) {
                                WayTaskProductionProductRow(product: row.product)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !removedProducts.isEmpty {
                        WayTaskSectionHeader(title: "Removed Products")
                            .padding(.top, 8)
                        ForEach(removedProducts) { row in
                            NavigationLink(value: row.id) {
                                WayTaskProductionProductRow(
                                    product: row.projection.product,
                                    isRemoved: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(WayTaskDesign.background.ignoresSafeArea())
            .navigationTitle("Products")
            .searchable(text: $searchText, prompt: "Search products")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        isAddingCatalogProduct = true
                    } label: {
                        Label("Add from Catalog", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        WayTaskPrimaryPillButtonStyle(
                            height: 46,
                            cornerRadius: 15,
                            shadow: true
                        )
                    )
                    .accessibilityLabel("Add Product from Catalog")

                    Button {
                        selectedTab = .camera
                    } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        WayTaskSecondaryPillButtonStyle(
                            minHeight: 46,
                            cornerRadius: 15
                        )
                    )

                    Button {
                        selectedTab = .shopping
                    } label: {
                        Label("Shopping", systemImage: "list.bullet.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        WayTaskSecondaryPillButtonStyle(
                            minHeight: 46,
                            cornerRadius: 15
                        )
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $isAddingCatalogProduct) {
                WayTaskProductionAddProductView(
                    searchAvailability: searchAvailability,
                    isPresented: $isAddingCatalogProduct
                )
            }
            .navigationDestination(for: ProductStateProductID.self) { id in
                WayTaskProductionProductDetailView(productID: id)
            }
        }
    }

    private var visibleProducts: [ProductLibraryPresentationRow] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.products }
        return library.products.filter { row in
            [
                row.product.displayName,
                row.product.brand,
                row.product.category,
                row.product.catalogCategoryDisplayNameSnapshot
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var removedProducts: [RemovedProductPresentationRow] {
        guard case let .available(library) = runtime.homeState.library,
              case let .available(products, _) = library.removedProducts
        else { return [] }
        return products
    }
}

private struct WayTaskProductionProductRow: View {
    let product: ProductStateProductProjection
    var isRemoved = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(WayTaskDesign.accent.opacity(0.14))
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(1)
                }
                if isRemoved {
                    Label("Removed", systemImage: "archivebox.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WayTaskDesign.tertiaryText)
        }
        .padding(14)
        .wayTaskCard(cornerRadius: 18)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        ProductKnowledgeIconResolver.systemName(for: product)
    }

    private var subtitle: String? {
        [product.brand, product.category ?? product.catalogCategoryDisplayNameSnapshot]
            .compactMap { value in
                guard let value,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return value
            }
            .joined(separator: " · ")
            .nonempty
    }
}

private struct WayTaskProductionProductDetailView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    let productID: ProductStateProductID

    @State private var isEditing = false
    @State private var editedName = ""
    @State private var isChoosingList = false
    @State private var statusMessage: String?
    @State private var confirmsRemoval = false

    var body: some View {
        Group {
            if let product {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        productHero(product)
                        detailCard(product)
                        actionCard(product)
                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WayTaskDesign.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .wayTaskCard(cornerRadius: 16)
                        }
                    }
                    .padding(18)
                }
                .background(WayTaskDesign.background.ignoresSafeArea())
                .navigationTitle(product.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $isEditing) {
                    editSheet(product)
                }
                .sheet(isPresented: $isChoosingList) {
                    listSelectionSheet(product)
                }
                .confirmationDialog(
                    "Remove from Product Library?",
                    isPresented: $confirmsRemoval,
                    titleVisibility: .visible
                ) {
                    Button("Remove Product", role: .destructive) {
                        remove(product)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("The Product stays recoverable in Removed Products.")
                }
            } else {
                ContentUnavailableView(
                    "Product unavailable",
                    systemImage: "shippingbox"
                )
            }
        }
    }

    private func productHero(_ product: ProductStateProductProjection) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(WayTaskDesign.accentGradient)
                Image(
                    systemName: ProductKnowledgeIconResolver.systemName(
                        for: product
                    )
                )
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
            }
            .frame(width: 104, height: 104)

            Text(product.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(WayTaskDesign.primaryText)
                .multilineTextAlignment(.center)

            if product.libraryLifecycle == .removed {
                Text("Removed from Product Library")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func detailCard(_ product: ProductStateProductProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WayTaskSectionHeader(title: "Product Details")
            detailLine("Brand", value: product.brand)
            detailLine(
                "Category",
                value: product.category
                    ?? product.catalogCategoryDisplayNameSnapshot
            )
            detailLine("Barcode", value: product.barcode)
        }
        .padding(16)
        .wayTaskCard(cornerRadius: 20)
    }

    private func actionCard(_ product: ProductStateProductProjection) -> some View {
        VStack(spacing: 10) {
            if product.libraryLifecycle == .active {
                Button {
                    editedName = product.displayName
                    isEditing = true
                } label: {
                    Label("Edit Product", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    WayTaskPrimaryPillButtonStyle(
                        height: 48,
                        cornerRadius: 16,
                        shadow: true
                    )
                )

                Button {
                    isChoosingList = true
                } label: {
                    Label("Add to Shopping List", systemImage: "list.bullet.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    WayTaskSecondaryPillButtonStyle(
                        minHeight: 48,
                        cornerRadius: 16
                    )
                )

                Button(role: .destructive) {
                    confirmsRemoval = true
                } label: {
                    Label("Remove from Library", systemImage: "archivebox")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    WayTaskSecondaryPillButtonStyle(
                        minHeight: 48,
                        cornerRadius: 16
                    )
                )
            } else {
                Button {
                    runtime.restore(product)
                    statusMessage = "Product restored"
                } label: {
                    Label("Restore Product", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    WayTaskPrimaryPillButtonStyle(
                        height: 48,
                        cornerRadius: 16,
                        shadow: true
                    )
                )
            }
        }
        .padding(16)
        .wayTaskCard(cornerRadius: 20)
    }

    @ViewBuilder
    private func detailLine(_ label: String, value: String?) -> some View {
        if let value,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                Spacer()
                Text(value)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
        }
    }

    private func editSheet(_ product: ProductStateProductProjection) -> some View {
        NavigationStack {
            Form {
                TextField("Product name", text: $editedName)
            }
            .navigationTitle("Edit Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { edit(product) }
                        .disabled(
                            editedName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                }
            }
        }
    }

    private func listSelectionSheet(_ product: ProductStateProductProjection) -> some View {
        NavigationStack {
            List(projectedLists, id: \.id) { list in
                Button {
                    runtime.addProduct(product.id, to: list)
                    statusMessage = "Added to \(list.title)"
                    isChoosingList = false
                } label: {
                    Label(list.title, systemImage: "list.bullet.rectangle")
                }
                .disabled(listContains(product.id, list: list))
            }
            .navigationTitle("Choose a List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isChoosingList = false }
                }
            }
        }
    }

    private func edit(_ product: ProductStateProductProjection) {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let execution = runtime.productCommands.edit(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: ProductStateExpectedRevision(
                    revision: ProductStateRevision(
                        scope: .product(product.id),
                        value: product.revision
                    )
                ),
                effectiveAt: Date(),
                intent: .editProduct(
                    EditProductCommand(productID: product.id, name: name)
                )
            )
        )
        statusMessage = execution.claimsDurableSuccess
            ? "Product updated" : "Product could not be updated"
        if execution.claimsDurableSuccess { isEditing = false }
        runtime.refresh()
    }

    private func remove(_ product: ProductStateProductProjection) {
        let expectations: [ProductStateListRevisionExpectation] =
            projectedLists.compactMap { list in
            guard listContains(product.id, list: list) else { return nil }
            return ProductStateListRevisionExpectation(
                listID: list.id,
                revision: list.revision
            )
        }
        let execution = runtime.productCommands.removeFromLibrary(
            ProductStateCommand(
                id: ProductStateCommandID(rawValue: UUID()),
                expectedRevision: ProductStateExpectedRevision(
                    revision: ProductStateRevision(
                        scope: .product(product.id),
                        value: product.revision
                    )
                ),
                effectiveAt: Date(),
                intent: .removeProductFromLibrary(
                    RemoveProductFromLibraryCommand(
                        productID: product.id,
                        historyEventID: ProductStateHistoryEventID(
                            rawValue: UUID()
                        ),
                        confirmed: true
                    )
                )
            ),
            expectedAffectedListRevisions: expectations
        )
        statusMessage = execution.claimsDurableSuccess
            ? "Product moved to Removed Products"
            : "Product could not be removed"
        runtime.refresh()
    }

    private var product: ProductStateProductProjection? {
        if case let .available(library) = runtime.homeState.library {
            if let active = library.products.first(where: { $0.id == productID }) {
                return active.product
            }
            if case let .available(removed, _) = library.removedProducts {
                return removed.first(where: { $0.id == productID })?
                    .projection.product
            }
        }
        return nil
    }

    private var projectedLists: [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
    }

    private func listContains(
        _ productID: ProductStateProductID,
        list: ProductStateNamedListProjection
    ) -> Bool {
        (list.neededEntries + list.resolvedEntries + list.unresolvedEntries)
            .contains { $0.identity.productID == productID }
    }
}

private struct WayTaskProductionCreateCustomProductView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Binding var isPresented: Bool
    let destinationListTitle: String?
    let onConfirm: ((String, Data?) -> Void)?

    @State private var name: String
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?

    init(
        isPresented: Binding<Bool>,
        initialName: String = "",
        destinationListTitle: String? = nil,
        onConfirm: ((String, Data?) -> Void)? = nil
    ) {
        _isPresented = isPresented
        _name = State(initialValue: initialName)
        self.destinationListTitle = destinationListTitle
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if let destinationListTitle {
                        Text(
                            "Creating this custom product also adds it to \(destinationListTitle)."
                        )
                    } else {
                        Text("The custom product will be saved to Products.")
                    }
                }
                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            imageData == nil ? "Add Photo" : "Change Photo",
                            systemImage: "photo"
                        )
                    }

                    if let imageData,
                       let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Custom Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if let onConfirm {
                            isPresented = false
                            DispatchQueue.main.async {
                                onConfirm(trimmed, imageData)
                            }
                        } else if runtime.acquireProduct(name: trimmed) {
                            isPresented = false
                        } else {
                            errorMessage = "The custom product could not be created."
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
            .onChange(of: selectedPhoto) {
                Task {
                    imageData = try? await selectedPhoto?
                        .loadTransferable(type: Data.self)
                }
            }
        }
    }
}

private enum WayTaskProductAddDestination: Equatable {
    case productLibrary
    case shoppingList(id: ProductStateListID, title: String)

    var listTitle: String? {
        guard case let .shoppingList(_, title) = self else { return nil }
        return title
    }
}

private struct WayTaskPendingListDuplicate {
    let candidate: ProductStateProductProjection
    let existingEntry: ProductStateListEntryProjection
    let list: ProductStateNamedListProjection
    let match: ShoppingListDuplicateMatch
}

private struct WayTaskProductionAddProductView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Environment(\.locale) private var locale
    @Binding var isPresented: Bool
    let destination: WayTaskProductAddDestination
    let onCompleted: (() -> Void)?
    let onFeedback: ((String) -> Void)?

    @StateObject private var autocomplete: AddProductAutocompleteViewModel
    @State private var query = ""
    @State private var imageData: Data?
    @State private var errorMessage: String?
    @State private var pendingRestore: ProductAcquisitionResult?
    @State private var isCreatingCustomProduct = false
    @State private var pendingCustomName = ""
    @State private var pendingDuplicate: WayTaskPendingListDuplicate?

    init(
        searchAvailability: ProductKnowledgeSearchAvailability,
        isPresented: Binding<Bool>,
        destination: WayTaskProductAddDestination = .productLibrary,
        onCompleted: (() -> Void)? = nil,
        onFeedback: ((String) -> Void)? = nil
    ) {
        _autocomplete = StateObject(
            wrappedValue: AddProductAutocompleteViewModel(
                searchAvailability: searchAvailability
            )
        )
        _isPresented = isPresented
        self.destination = destination
        self.onCompleted = onCompleted
        self.onFeedback = onFeedback
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WayTaskScreenHeader(
                        title: "Add Product",
                        subtitle: destination.listTitle.map {
                            "Search products for \($0)"
                        } ?? "Search products in the catalog"
                    )

                    nameCard
                    suggestionContent

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        save()
                    } label: {
                        if autocomplete.isSavingProduct {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Add Product", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(
                        WayTaskPrimaryPillButtonStyle(
                            height: 50,
                            cornerRadius: 16,
                            shadow: true
                        )
                    )
                    .disabled(!autocomplete.canConfirmProduct)
                    .opacity(autocomplete.canConfirmProduct ? 1 : 0.45)
                }
                .padding(18)
            }
            .background(WayTaskDesign.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .onChange(of: query) { _, value in
                query = autocomplete.acceptTextFieldEdit(
                    value,
                    localeIdentifier: locale.identifier
                )
            }
            .alert(
                "Restore Product?",
                isPresented: restoreConfirmationPresented,
                presenting: pendingRestore
            ) { result in
                Button("Cancel", role: .cancel) {
                    cancelRestore()
                }
                Button("Restore") {
                    confirmRestore(result)
                }
            } message: { _ in
                Text(
                    "This product was removed earlier. Restore it to Products?"
                )
            }
            .sheet(isPresented: $isCreatingCustomProduct) {
                WayTaskProductionCreateCustomProductView(
                    isPresented: $isCreatingCustomProduct,
                    initialName: pendingCustomName,
                    destinationListTitle: destination.listTitle
                ) { confirmedName, confirmedImageData in
                    confirmCustomProduct(
                        named: confirmedName,
                        imageData: confirmedImageData
                    )
                }
            }
            .confirmationDialog(
                duplicateDialogTitle,
                isPresented: duplicateConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingDuplicate
            ) { duplicate in
                Button("Increase Quantity") {
                    increaseExistingQuantity(duplicate)
                }
                if !duplicate.match.isExactProductIdentity {
                    Button("Add as Separate Product") {
                        addAsSeparateProduct(duplicate)
                    }
                }
                Button("Cancel", role: .cancel) {
                    cancelListAddition(duplicate)
                }
            } message: { duplicate in
                Text(duplicateDialogMessage(duplicate))
            }
        }
    }

    private var restoreConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingRestore != nil },
            set: { isPresented in
                if !isPresented { pendingRestore = nil }
            }
        )
    }

    private var duplicateConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDuplicate != nil },
            set: { if !$0 { pendingDuplicate = nil } }
        )
    }

    private var duplicateDialogTitle: String {
        guard let pendingDuplicate else { return "Product Already Added" }
        return pendingDuplicate.match.isExactProductIdentity
            ? "Product Already in List"
            : "Possible Duplicate"
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ProductAutocompleteCopy.productNameFieldLabel(
                localeIdentifier: locale.identifier
            ))
            .font(.caption.weight(.bold))
            .foregroundStyle(WayTaskDesign.secondaryText)

            if let selected = autocomplete.selectedFieldValue {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(WayTaskDesign.accent)
                    Text(selected)
                        .font(.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                    Spacer()
                    Button("Change") { changeSelection() }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                TextField(
                    ProductAutocompleteCopy.productNamePlaceholder(
                        localeIdentifier: locale.identifier
                    ),
                    text: $query
                )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .padding(12)
                    .background(WayTaskDesign.surfaceElevated)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
        }
        .padding(16)
        .wayTaskCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var suggestionContent: some View {
        let slots = autocomplete.presentationSlots
        if slots.isActive {
            VStack(spacing: 10) {
                if slots.showsResults {
                    ForEach(autocomplete.results.prefix(10)) { result in
                        Button {
                            if autocomplete.selectCatalogProduct(
                                result,
                                preselectionQuery: query
                            ) {
                                query = result.displayName
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: ProductKnowledgeIconResolver
                                        .systemName(for: result.iconKey)
                                )
                                .foregroundStyle(WayTaskDesign.accent)
                                .frame(width: 38, height: 38)
                                .background(WayTaskDesign.accent.opacity(0.12))
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 11,
                                        style: .continuous
                                    )
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WayTaskDesign.primaryText)
                                    Text(result.categoryDisplayName)
                                        .font(.caption)
                                        .foregroundStyle(WayTaskDesign.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(WayTaskDesign.surfaceElevated)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }

                if let customName = slots.customActionName {
                    Button {
                        pendingCustomName = customName
                        imageData = nil
                        isCreatingCustomProduct = true
                    } label: {
                        Label(
                            "Create “\(customName)” as a Custom Product",
                            systemImage: "plus.circle.fill"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .wayTaskCard(cornerRadius: 14)
                }

                switch slots.statusContent {
                case .searching:
                    Label("Searching products…", systemImage: "magnifyingglass")
                        .foregroundStyle(WayTaskDesign.secondaryText)
                case .noMatch:
                    Text(
                        slots.customActionName == nil
                            ? "No suitable catalog match yet. Keep typing to make the product name more specific."
                            : "No catalog match. You can create a custom product below."
                    )
                        .foregroundStyle(WayTaskDesign.secondaryText)
                case .unavailable:
                    Text("Catalog suggestions are unavailable. Try again later.")
                        .foregroundStyle(WayTaskDesign.secondaryText)
                case .hidden:
                    EmptyView()
                }
            }
            .font(.subheadline)
        }
    }

    private func changeSelection() {
        if autocomplete.selectedCatalogProduct != nil {
            query = autocomplete.changeCatalogSelection(
                localeIdentifier: locale.identifier
            ) ?? query
        } else {
            imageData = nil
            query = autocomplete.changeCustomProductSelection(
                localeIdentifier: locale.identifier
            ) ?? query
        }
    }

    private func confirmCustomProduct(named name: String, imageData: Data?) {
        guard let selection = autocomplete.selectCustomProduct(named: name)
        else {
            errorMessage = "The custom product could not be prepared."
            return
        }
        self.imageData = imageData
        query = selection.name
        save()
    }

    private func save() {
        guard autocomplete.beginSavingProduct() != nil else { return }
        guard let confirmation = autocomplete
            .prepareTargetAcquisitionConfirmation(
                productID: ProductStateProductID(rawValue: UUID()),
                commandID: ProductStateCommandID(rawValue: UUID()),
                effectiveAt: Date(),
                imageData: imageData,
                confirmed: true
            )
        else {
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "Choose a catalog suggestion or confirm a custom product."
            return
        }

        let result = autocomplete.confirmTargetAcquisition(
            confirmation,
            using: runtime.productCommands
        )
        switch result.outcome {
        case let .created(productID, _),
             let .alreadyActive(productID, _):
            runtime.refresh()
            completeAcquisition(productID: productID)
        case .restoreRequired:
            pendingRestore = result
        case .ambiguity, .validationFailure, .unavailable:
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "The product could not be added."
        }
    }

    private func cancelRestore() {
        pendingRestore = nil
        autocomplete.finishSavingProductAfterFailure()
        errorMessage = "The product remains removed."
    }

    private func confirmRestore(_ result: ProductAcquisitionResult) {
        pendingRestore = nil
        guard let restore = autocomplete.prepareTargetRestoreConfirmation(
            for: result,
            commandID: ProductStateCommandID(rawValue: UUID()),
            historyEventID: ProductStateHistoryEventID(rawValue: UUID()),
            effectiveAt: Date(),
            confirmed: true
        ) else {
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "This product could not be restored."
            return
        }
        let restored = autocomplete.confirmTargetRestore(
            restore,
            using: runtime.productCommands
        )
        switch restored.outcome {
        case let .restored(productID, _),
             let .alreadyActive(productID, _):
            runtime.refresh()
            completeAcquisition(productID: productID)
        case .ambiguity, .conflict, .validationFailure, .unavailable:
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "The product could not be restored."
        }
    }

    private func completeAcquisition(productID: ProductStateProductID) {
        guard case let .shoppingList(listID, _) = destination else {
            finishPresentation()
            return
        }
        guard let list = projectedLists.first(where: { $0.id == listID }) else {
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "Select or create a shopping list before adding a product."
            return
        }
        guard let candidate = activeProducts.first(where: {
            $0.id == productID
        }) else {
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "The product was saved, but it could not be added to the list."
            return
        }

        prepareListAddition(candidate, to: list)
    }

    private func prepareListAddition(
        _ candidate: ProductStateProductProjection,
        to list: ProductStateNamedListProjection
    ) {
        let entries = allEntries(in: list)
        guard let match = ShoppingListDuplicatePolicy.match(
            candidate: candidate,
            entries: entries
        ) else {
            runtime.addProduct(candidate.id, to: list)
            finishPresentation()
            return
        }
        guard let existingEntry = entries.first(where: {
            $0.identity.id == match.existingEntryID
        }) else {
            errorMessage = "The possible duplicate could not be reviewed."
            return
        }
        pendingDuplicate = WayTaskPendingListDuplicate(
            candidate: candidate,
            existingEntry: existingEntry,
            list: list,
            match: match
        )
    }

    private func increaseExistingQuantity(
        _ duplicate: WayTaskPendingListDuplicate
    ) {
        pendingDuplicate = nil
        let updated = runtime.increaseQuantity(
            of: duplicate.existingEntry,
            in: duplicate.list
        )
        guard updated else {
            autocomplete.finishSavingProductAfterFailure()
            errorMessage = "The existing quantity could not be increased."
            return
        }
        onFeedback?(
            "\(duplicate.candidate.displayName) is already in \(duplicate.list.title). Its quantity was increased."
        )
        finishPresentation()
    }

    private func addAsSeparateProduct(
        _ duplicate: WayTaskPendingListDuplicate
    ) {
        pendingDuplicate = nil
        runtime.addProduct(duplicate.candidate.id, to: duplicate.list)
        finishPresentation()
    }

    private func cancelListAddition(
        _ duplicate: WayTaskPendingListDuplicate
    ) {
        pendingDuplicate = nil
        onFeedback?(
            "No new row was added to \(duplicate.list.title)."
        )
        finishPresentation()
    }

    private func duplicateDialogMessage(
        _ duplicate: WayTaskPendingListDuplicate
    ) -> String {
        if duplicate.match.isExactProductIdentity {
            return "\(duplicate.candidate.displayName) is already in \(duplicate.list.title). Increase its quantity instead?"
        }
        let existingName = duplicate.existingEntry.product?.displayName
            ?? "an existing product"
        return "\(duplicate.candidate.displayName) may match \(existingName) in \(duplicate.list.title). Choose whether to increase the existing quantity or add a separate product."
    }

    private func finishPresentation() {
        isPresented = false
        DispatchQueue.main.async {
            onCompleted?()
        }
    }

    private var projectedLists: [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
    }

    private var activeProducts: [ProductStateProductProjection] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        return library.products.map(\.product)
    }

    private func allEntries(
        in list: ProductStateNamedListProjection
    ) -> [ProductStateListEntryProjection] {
        list.neededEntries + list.resolvedEntries + list.unresolvedEntries
    }
}

// MARK: - Shopping

struct ShoppingListProgressPresentation: Equatable {
    let resolvedQuantity: Double
    let totalQuantity: Double

    init(neededQuantities: [Double], resolvedQuantities: [Double]) {
        let needed = Self.validQuantitySum(neededQuantities)
        let resolved = Self.validQuantitySum(resolvedQuantities)
        resolvedQuantity = resolved
        totalQuantity = needed + resolved
    }

    var fraction: Double {
        guard totalQuantity > 0 else { return 0 }
        return min(max(resolvedQuantity / totalQuantity, 0), 1)
    }

    var percentage: Int {
        min(max(Int((fraction * 100).rounded()), 0), 100)
    }

    var summary: String {
        "\(Self.quantityText(resolvedQuantity)) of "
            + "\(Self.quantityText(totalQuantity)) completed"
    }

    private static func validQuantitySum(_ values: [Double]) -> Double {
        values.reduce(into: 0) { total, value in
            guard value.isFinite, value > 0 else { return }
            total += value
        }
    }

    private static func quantityText(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return value.formatted(
            .number.precision(.fractionLength(0...2))
        )
    }
}

private struct WayTaskProductionShoppingView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Binding var selectedTab: WayTaskProductionTab
    let searchAvailability: ProductKnowledgeSearchAvailability

    @State private var isCreatingList = false
    @State private var listTitle = ""
    @State private var isChoosingProduct = false
    @State private var isSearchingCatalog = false
    @State private var searchText = ""
    @State private var pendingProductChooserListID: ProductStateListID?
    @State private var renamingListID: ProductStateListID?
    @State private var renamedListTitle = ""
    @State private var deletingListID: ProductStateListID?
    @State private var pendingDuplicate: WayTaskPendingListDuplicate?
    @State private var feedbackMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    listPicker

                    if projectedLists.isEmpty {
                        WayTaskEmptyState(
                            title: "No Shopping Lists",
                            message: "Create a shopping list to start planning products.",
                            systemImage: "list.bullet.rectangle",
                            actionTitle: "Create Shopping List"
                        ) {
                            beginCreatingList()
                        }
                    } else if let list = selectedList {
                        shoppingSummary(list)
                        if isEmpty(list) {
                            WayTaskEmptyState(
                                title: "No Products Yet",
                                message: "Add the first product to \(list.title).",
                                systemImage: "cart.badge.plus",
                                actionTitle: "Add Product"
                            ) {
                                isChoosingProduct = true
                            }
                        } else {
                            entriesSection(
                                title: "Needed",
                                entries: list.neededEntries,
                                list: list,
                                resolved: false
                            )
                            if !list.resolvedEntries.isEmpty {
                                entriesSection(
                                    title: "Resolved",
                                    entries: list.resolvedEntries,
                                    list: list,
                                    resolved: true
                                )
                            }
                        }
                        sessionCard
                    } else {
                        WayTaskEmptyState(
                            title: "Select a Shopping List",
                            message: "Choose one of your lists above, or create another list.",
                            systemImage: "list.bullet.rectangle",
                            actionTitle: "Create Shopping List"
                        ) {
                            beginCreatingList()
                        }
                    }
                }
                .padding(16)
            }
            .background(WayTaskDesign.background.ignoresSafeArea())
            .navigationTitle("Shopping")
            .searchable(text: $searchText, prompt: "Search this list")
            .safeAreaInset(edge: .bottom) {
                if let selectedList {
                    selectedListActions(selectedList)
                } else {
                    noSelectedListActions
                }
            }
            .sheet(
                isPresented: $isCreatingList,
                onDismiss: presentPendingProductChooser
            ) { createListSheet }
            .sheet(
                isPresented: $isChoosingProduct,
                onDismiss: resetProductChooserPresentation
            ) { productChooserSheet }
            .sheet(isPresented: renameSheetPresented) { renameListSheet }
            .confirmationDialog(
                "Delete Shopping List?",
                isPresented: deleteConfirmationPresented,
                titleVisibility: .visible,
                presenting: deletingList
            ) { list in
                Button("Delete \(list.title)", role: .destructive) {
                    runtime.deleteList(list)
                    deletingListID = nil
                }
                Button("Cancel", role: .cancel) {
                    deletingListID = nil
                }
            } message: { list in
                Text(
                    "This removes \(list.title) from Shopping. Your Product Library is not changed."
                )
            }
            .alert(
                "Shopping List Updated",
                isPresented: feedbackPresented
            ) {
                Button("OK", role: .cancel) { feedbackMessage = nil }
            } message: {
                Text(feedbackMessage ?? "The shopping list was updated.")
            }
        }
    }

    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    shoppingListsTitle
                    Spacer(minLength: 4)
                    newListButton(expands: false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    shoppingListsTitle
                    newListButton(expands: true)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(projectedLists, id: \.id) { list in
                        HStack(spacing: 4) {
                            Button {
                                runtime.selectList(list.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "list.bullet")
                                    Text(list.title)
                                        .lineLimit(1)
                                    if runtime.selectedListID == list.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    runtime.selectedListID == list.id
                                        ? .white : WayTaskDesign.secondaryText
                                )
                                .padding(.leading, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select Shopping List \(list.title)")

                            Menu {
                                Button("Rename", systemImage: "pencil") {
                                    beginRenaming(list)
                                }
                                Button(
                                    "Delete",
                                    systemImage: "trash",
                                    role: .destructive
                                ) {
                                    deletingListID = list.id
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.subheadline.weight(.bold))
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 10)
                            }
                            .accessibilityLabel("Manage Shopping List \(list.title)")
                        }
                        .foregroundStyle(
                            runtime.selectedListID == list.id
                                ? .white : WayTaskDesign.secondaryText
                        )
                        .background(
                            runtime.selectedListID == list.id
                                ? WayTaskDesign.accent
                                : WayTaskDesign.surface
                        )
                        .clipShape(Capsule())
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var shoppingListsTitle: some View {
        Text("Shopping Lists")
            .font(WayTaskDesign.Typography.sectionTitle)
            .foregroundStyle(WayTaskDesign.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
    }

    private func newListButton(expands: Bool) -> some View {
        Button {
            beginCreatingList()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
                Text("New List")
                    .lineLimit(expands ? 2 : 1)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WayTaskDesign.accent)
            .frame(
                maxWidth: expands ? .infinity : nil,
                alignment: .leading
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(WayTaskDesign.accent.opacity(0.14))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(WayTaskDesign.accent.opacity(0.42), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !expands, vertical: true)
        .accessibilityIdentifier("shopping-new-list-button")
        .accessibilityLabel("Create Shopping List")
        .accessibilityHint("Opens the new shopping list form")
    }

    private func shoppingSummary(
        _ list: ProductStateNamedListProjection
    ) -> some View {
        let progress = progressPresentation(for: list)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(list.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                Text(progress.summary)
                    .font(.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                Text("Progress for this shopping list")
                    .font(.caption)
                    .foregroundStyle(WayTaskDesign.tertiaryText)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        WayTaskDesign.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(progress.percentage)%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
            }
            .frame(width: 58, height: 58)
            .accessibilityLabel(
                "Shopping list progress, \(progress.percentage) percent, \(progress.summary)"
            )
        }
        .padding(18)
        .wayTaskGlassCard()
    }

    private func entriesSection(
        title: String,
        entries: [ProductStateListEntryProjection],
        list: ProductStateNamedListProjection,
        resolved: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WayTaskSectionHeader(title: title)
            if entries.isEmpty {
                Text("No \(title.lowercased()) products")
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .wayTaskCard(cornerRadius: 18)
            } else {
                ForEach(filtered(entries), id: \.identity.id) { entry in
                    shoppingRow(entry, list: list, resolved: resolved)
                }
            }
        }
    }

    private func shoppingRow(
        _ entry: ProductStateListEntryProjection,
        list: ProductStateNamedListProjection,
        resolved: Bool
    ) -> some View {
        let row = ShoppingWorkspaceProjectionRow(entry: entry)
        return HStack(spacing: 12) {
            Button {
                if resolved {
                    runtime.perform(.reopen, row: row, list: list)
                } else {
                    runtime.perform(
                        .resolve(.alreadyHave),
                        row: row,
                        list: list
                    )
                }
            } label: {
                Image(systemName: resolved ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        resolved ? WayTaskDesign.accent : WayTaskDesign.secondaryText
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(resolved ? "Reopen" : "Mark as already have")

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WayTaskDesign.accent.opacity(0.12))
                Image(
                    systemName: entry.product.map {
                        ProductKnowledgeIconResolver.systemName(for: $0)
                    } ?? ProductKnowledgeIconResolver.fallbackSystemName
                )
                .foregroundStyle(WayTaskDesign.accent)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.product?.displayName ?? "Product unavailable")
                    .font(.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .strikethrough(resolved)
                Text(resolved ? row.stateTitle : quantityText(entry.quantity))
                    .font(.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }

            Spacer(minLength: 8)

            if !resolved {
                Stepper(
                    "Quantity",
                    value: Binding(
                        get: { entry.quantity },
                        set: { quantity in
                            runtime.perform(
                                .updateQuantity(max(quantity, 1)),
                                row: row,
                                list: list
                            )
                        }
                    ),
                    in: 1...99
                )
                .labelsHidden()
            }

            Menu {
                if resolved {
                    Button("Reopen") {
                        runtime.perform(.reopen, row: row, list: list)
                    }
                } else {
                    Button("Already Have") {
                        runtime.perform(
                            .resolve(.alreadyHave),
                            row: row,
                            list: list
                        )
                    }
                    Button("No Longer Needed") {
                        runtime.perform(
                            .resolve(.noLongerNeeded),
                            row: row,
                            list: list
                        )
                    }
                }
                Button("Remove", role: .destructive) {
                    runtime.perform(.remove, row: row, list: list)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(14)
        .wayTaskCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private var sessionCard: some View {
        Group {
            if case let .projection(lookup) = runtime.activeSessions,
               !lookup.candidates.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.title2)
                        .foregroundStyle(WayTaskDesign.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shopping Session in progress")
                            .font(.headline)
                        Text("Your active trip is ready to continue.")
                            .font(.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                    }
                    Spacer()
                }
                .padding(16)
                .wayTaskGlassCard()
            }
        }
    }

    private func selectedListActions(
        _ list: ProductStateNamedListProjection
    ) -> some View {
        let neededQuantity = list.neededEntries.reduce(0) {
            $0 + max($1.quantity, 0)
        }
        return HStack(spacing: 10) {
            Button {
                isChoosingProduct = true
            } label: {
                contextualActionLabel(
                    title: "Add Product",
                    context: "to \(list.title)",
                    systemImage: "plus.circle.fill"
                )
            }
            .buttonStyle(
                WayTaskPrimaryPillButtonStyle(
                    height: 58,
                    cornerRadius: 16,
                    shadow: true
                )
            )
            .accessibilityLabel("Add Product to \(list.title)")
            .accessibilityHint(
                "Add Product to Selected Shopping List"
            )

            Button {
                selectedTab = .map
            } label: {
                contextualActionLabel(
                    title: "Find Stores",
                    context: neededQuantity > 0
                        ? "for \(list.title)"
                        : "Add products first",
                    systemImage: "map.fill"
                )
            }
            .buttonStyle(
                WayTaskSecondaryPillButtonStyle(
                    minHeight: 58,
                    cornerRadius: 16
                )
            )
            .disabled(neededQuantity <= 0)
            .opacity(neededQuantity > 0 ? 1 : 0.55)
            .accessibilityLabel("Find Stores for \(list.title)")
            .accessibilityHint(
                neededQuantity > 0
                    ? "Opens Map for \(quantityText(neededQuantity)) needed in \(list.title)"
                    : "Add products to \(list.title) before finding stores"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func contextualActionLabel(
        title: String,
        context: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(context)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var noSelectedListActions: some View {
        HStack(spacing: 10) {
            if !projectedLists.isEmpty {
                Menu {
                    ForEach(projectedLists, id: \.id) { list in
                        Button(list.title) {
                            runtime.selectList(list.id)
                        }
                    }
                    Divider()
                    Button("New List", systemImage: "plus") {
                        beginCreatingList()
                    }
                } label: {
                    contextualActionLabel(
                        title: "Select or Create",
                        context: "a Shopping List",
                        systemImage: "list.bullet"
                    )
                }
                .buttonStyle(
                    WayTaskPrimaryPillButtonStyle(
                        height: 58,
                        cornerRadius: 16,
                        shadow: true
                    )
                )
                .accessibilityLabel("Select or Create a Shopping List")
            } else {
                Button {
                    beginCreatingList()
                } label: {
                    contextualActionLabel(
                        title: "Create List",
                        context: "to add products",
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(
                    WayTaskPrimaryPillButtonStyle(
                        height: 58,
                        cornerRadius: 16,
                        shadow: true
                    )
                )
                .accessibilityLabel("Create Shopping List")
            }

            Button { } label: {
                contextualActionLabel(
                    title: "Find Stores",
                    context: projectedLists.isEmpty
                        ? "Create a list first"
                        : "Select a list first",
                    systemImage: "map.fill"
                )
            }
            .buttonStyle(
                WayTaskSecondaryPillButtonStyle(
                    minHeight: 58,
                    cornerRadius: 16
                )
            )
            .disabled(true)
            .opacity(0.55)
            .accessibilityLabel("Find Stores unavailable")
            .accessibilityHint(
                projectedLists.isEmpty
                    ? "Create a shopping list before finding stores"
                    : "Select a shopping list before finding stores"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var createListSheet: some View {
        NavigationStack {
            Form { TextField("List name", text: $listTitle) }
                .navigationTitle("New Shopping List")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            pendingProductChooserListID = nil
                            isCreatingList = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            if let id = runtime.createList(title: listTitle) {
                                pendingProductChooserListID = id
                                isCreatingList = false
                            }
                        }
                        .disabled(
                            listTitle.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }
        }
    }

    private var renameListSheet: some View {
        NavigationStack {
            Form { TextField("List name", text: $renamedListTitle) }
                .navigationTitle("Rename Shopping List")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renamingListID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let renamingList else { return }
                            if runtime.renameList(
                                renamingList,
                                title: renamedListTitle
                            ) {
                                renamingListID = nil
                            }
                        }
                        .disabled(
                            renamedListTitle.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }
        }
    }

    private var productChooserSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isSearchingCatalog = true
                    } label: {
                        Label(
                            "Search Catalog or Create Custom",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .accessibilityLabel(
                        "Search Catalog or Create a Custom Product"
                    )
                } header: {
                    Text("More Products")
                }

                if availableProducts.isEmpty {
                    WayTaskEmptyState(
                        title: "No Products in Your Library",
                        message: "Search the catalog, create a custom product, or scan one first.",
                        systemImage: "shippingbox",
                        actionTitle: "Search Catalog"
                    ) {
                        isSearchingCatalog = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(availableProducts, id: \.id) { product in
                            Button {
                                guard let list = selectedList else { return }
                                prepareProductSelection(product, for: list)
                            } label: {
                                WayTaskProductionProductRow(product: product)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Your Products")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WayTaskDesign.background)
            .navigationTitle("Add Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isChoosingProduct = false }
                }
            }
            .sheet(isPresented: $isSearchingCatalog) {
                if let list = selectedList {
                    WayTaskProductionAddProductView(
                        searchAvailability: searchAvailability,
                        isPresented: $isSearchingCatalog,
                        destination: .shoppingList(
                            id: list.id,
                            title: list.title
                        ),
                        onCompleted: {
                            isSearchingCatalog = false
                            isChoosingProduct = false
                        },
                        onFeedback: { message in
                            feedbackMessage = message
                        }
                    )
                }
            }
            .confirmationDialog(
                chooserDuplicateDialogTitle,
                isPresented: chooserDuplicateConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingDuplicate
            ) { duplicate in
                Button("Increase Quantity") {
                    increaseExistingQuantity(duplicate)
                }
                if !duplicate.match.isExactProductIdentity {
                    Button("Add as Separate Product") {
                        addAsSeparateProduct(duplicate)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDuplicate = nil
                }
            } message: { duplicate in
                Text(chooserDuplicateDialogMessage(duplicate))
            }
        }
    }

    private var projectedLists: [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
    }

    private var selectedList: ProductStateNamedListProjection? {
        projectedLists.first { $0.id == runtime.selectedListID }
    }

    private var renamingList: ProductStateNamedListProjection? {
        projectedLists.first { $0.id == renamingListID }
    }

    private var deletingList: ProductStateNamedListProjection? {
        projectedLists.first { $0.id == deletingListID }
    }

    private var renameSheetPresented: Binding<Bool> {
        Binding(
            get: { renamingList != nil },
            set: { if !$0 { renamingListID = nil } }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deletingList != nil },
            set: { if !$0 { deletingListID = nil } }
        )
    }

    private var chooserDuplicateConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDuplicate != nil },
            set: { if !$0 { pendingDuplicate = nil } }
        )
    }

    private var feedbackPresented: Binding<Bool> {
        Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil } }
        )
    }

    private var chooserDuplicateDialogTitle: String {
        guard let pendingDuplicate else { return "Product Already Added" }
        return pendingDuplicate.match.isExactProductIdentity
            ? "Product Already in List"
            : "Possible Duplicate"
    }

    private var availableProducts: [ProductStateProductProjection] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        return library.products.map(\.product)
    }

    private func prepareProductSelection(
        _ product: ProductStateProductProjection,
        for list: ProductStateNamedListProjection
    ) {
        let entries = allEntries(in: list)
        guard let match = ShoppingListDuplicatePolicy.match(
            candidate: product,
            entries: entries
        ) else {
            runtime.addProduct(product.id, to: list)
            isChoosingProduct = false
            return
        }
        guard let existingEntry = entries.first(where: {
            $0.identity.id == match.existingEntryID
        }) else { return }
        pendingDuplicate = WayTaskPendingListDuplicate(
            candidate: product,
            existingEntry: existingEntry,
            list: list,
            match: match
        )
    }

    private func increaseExistingQuantity(
        _ duplicate: WayTaskPendingListDuplicate
    ) {
        pendingDuplicate = nil
        guard runtime.increaseQuantity(
            of: duplicate.existingEntry,
            in: duplicate.list
        ) else {
            feedbackMessage = "The existing quantity could not be increased."
            return
        }
        isChoosingProduct = false
        feedbackMessage =
            "\(duplicate.candidate.displayName) is already in \(duplicate.list.title). Its quantity was increased."
    }

    private func addAsSeparateProduct(
        _ duplicate: WayTaskPendingListDuplicate
    ) {
        pendingDuplicate = nil
        runtime.addProduct(duplicate.candidate.id, to: duplicate.list)
        isChoosingProduct = false
    }

    private func chooserDuplicateDialogMessage(
        _ duplicate: WayTaskPendingListDuplicate
    ) -> String {
        if duplicate.match.isExactProductIdentity {
            return "\(duplicate.candidate.displayName) is already in \(duplicate.list.title). Increase its quantity instead?"
        }
        let existingName = duplicate.existingEntry.product?.displayName
            ?? "an existing product"
        return "\(duplicate.candidate.displayName) may match \(existingName) in \(duplicate.list.title). Choose whether to increase the existing quantity or add a separate product."
    }

    private func allEntries(
        in list: ProductStateNamedListProjection
    ) -> [ProductStateListEntryProjection] {
        list.neededEntries + list.resolvedEntries + list.unresolvedEntries
    }

    private func filtered(
        _ entries: [ProductStateListEntryProjection]
    ) -> [ProductStateListEntryProjection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.product?.displayName.localizedCaseInsensitiveContains(query)
                == true
        }
    }

    private func progressPresentation(
        for list: ProductStateNamedListProjection
    ) -> ShoppingListProgressPresentation {
        ShoppingListProgressPresentation(
            neededQuantities: list.neededEntries.map(\.quantity),
            resolvedQuantities: list.resolvedEntries.map(\.quantity)
        )
    }

    private func isEmpty(_ list: ProductStateNamedListProjection) -> Bool {
        list.neededEntries.isEmpty
            && list.resolvedEntries.isEmpty
            && list.unresolvedEntries.isEmpty
    }

    private func beginCreatingList() {
        listTitle = ""
        pendingProductChooserListID = nil
        isCreatingList = true
    }

    private func beginRenaming(_ list: ProductStateNamedListProjection) {
        renamedListTitle = list.title
        renamingListID = list.id
    }

    private func presentPendingProductChooser() {
        guard let listID = pendingProductChooserListID else { return }
        pendingProductChooserListID = nil
        guard runtime.selectedListID == listID,
              selectedList?.id == listID,
              !isChoosingProduct
        else { return }
        DispatchQueue.main.async {
            isChoosingProduct = true
        }
    }

    private func resetProductChooserPresentation() {
        isSearchingCatalog = false
        pendingDuplicate = nil
    }

    private func quantityText(_ value: Double) -> String {
        if value.rounded() == value { return "Quantity \(Int(value))" }
        return "Quantity \(value.formatted(.number.precision(.fractionLength(1))))"
    }
}

// MARK: - Map

private struct WayTaskProductionMapCameraRequest {
    let id: Int
    let region: MKCoordinateRegion
    let animated: Bool
}

@MainActor
private final class WayTaskProductionMapModel:
    NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var stores: [MapStore] = []
    @Published private(set) var products: [MapProduct] = []
    @Published private(set) var selectedStoreID: UUID?
    @Published private(set) var cameraRequest:
        WayTaskProductionMapCameraRequest?
    @Published private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private let resolutionEngine = StoreResolutionEngine.shared
    private let intentMatcher = ShoppingIntentMatcher()
    private var coordinate: CLLocationCoordinate2D?
    private var lastLocation: CLLocation?
    private var entries: [ProductStateListEntryProjection] = []
    private var listID: ProductStateListID?
    private var listRevision: ProductStateListRevision?
    private var searchTask: Task<Void, Never>?
    private var selectionCameraTask: Task<Void, Never>?
    private var lastSignature: String?
    private var visibleRegion: MKCoordinateRegion?
    private var lastDiscoveryCoordinate: CLLocationCoordinate2D?
    private var inactiveSince: Date?
    private var pendingAutomaticFollow = true
    private var pendingExplicitFollow = false
    private var isUserExploring = false
    private var pendingFocusedStoreID: UUID?
    private var remainingFreshLocationRetries = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var selectedStore: MapStore? {
        guard let selectedStoreID else { return nil }
        return stores.first { $0.id == selectedStoreID }
    }

    var visibleStores: [MapStore] {
        stores
    }

    var visibleProducts: [MapProduct] {
        products
    }

    var cameraTarget: MKCoordinateRegion? {
        cameraRequest?.region
    }

    var cameraRequestID: Int {
        cameraRequest?.id ?? 0
    }

    var cameraShouldAnimate: Bool {
        cameraRequest?.animated ?? true
    }

    func start(
        list: ProductStateNamedListProjection?,
        entries: [ProductStateListEntryProjection]
    ) {
        let nextListID = list?.id
        let missionChanged = listID != nextListID
        self.listID = nextListID
        listRevision = list?.revision
        self.entries = entries
        if missionChanged {
            resetMissionPresentation()
        }
        requestFreshLocation()
        discover(force: false)
    }

    func receiveUserLocation(_ location: CLLocation, now: Date = Date()) {
        guard MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
            location,
            now: now
        ) else { return }
        let coordinate = location.coordinate
        let movement = self.coordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ))
        }
        lastLocation = location
        let shouldRecenter = pendingExplicitFollow
            || (pendingAutomaticFollow && !isUserExploring)
        if movement != nil,
           (movement ?? 0) < 10,
           !shouldRecenter { return }
        self.coordinate = coordinate
        if shouldRecenter {
            centerCameraOnUser(animated: true)
            pendingExplicitFollow = false
            pendingAutomaticFollow = false
        }
        if movement == nil {
            discover(force: false)
        } else if distance(
            from: lastDiscoveryCoordinate,
            to: coordinate
        ) >= 250 {
            discover(force: false)
        }
    }

    func followUser() {
        isUserExploring = false
        pendingExplicitFollow = true
        if let lastLocation,
           MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
               lastLocation
           ) {
            centerCameraOnUser(animated: true)
        }
        requestFreshLocation()
    }

    func userDidExploreMap() {
        isUserExploring = true
        pendingAutomaticFollow = false
        pendingExplicitFollow = false
    }

    func applicationDidBecomeInactive(now: Date = Date()) {
        if inactiveSince == nil { inactiveSince = now }
    }

    func applicationDidBecomeActive(now: Date = Date()) {
        let meaningfulReturn = MapLocationFreshnessPolicy
            .shouldRefreshAfterActivation(
                inactiveSince: inactiveSince,
                now: now
            )
        if MapLocationFreshnessPolicy
            .shouldAutomaticallyFollowAfterActivation(
                inactiveSince: inactiveSince,
                isUserExploring: isUserExploring,
                now: now
            ) {
            pendingAutomaticFollow = true
        }
        if meaningfulReturn {
            isUserExploring = false
            coordinate = nil
            lastLocation = nil
        }
        inactiveSince = nil
        requestFreshLocation()
    }

    private func centerCameraOnUser(animated: Bool) {
        guard let coordinate else { return }
        selectionCameraTask?.cancel()
        selectionCameraTask = nil
        requestCamera(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: 0.018,
                longitudeDelta: 0.018
            )
        ), animated: animated)
    }

    func selectStore(_ id: UUID) {
        selectionCameraTask?.cancel()
        selectionCameraTask = nil
        let nextSelection = ShoppingMissionMapSelectionPolicy
            .toggledSelection(current: selectedStoreID, tapped: id)
        publishSelection(nextSelection)
        guard let nextSelection,
              let store = stores.first(where: { $0.id == nextSelection }),
              shouldRecenter(on: store.coordinate)
        else { return }
        let region = MKCoordinateRegion(
            center: store.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: 0.008,
                longitudeDelta: 0.008
            )
        )
        selectionCameraTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled,
                  let self,
                  self.selectedStoreID == nextSelection
            else { return }
            self.requestCamera(region, animated: true)
            self.selectionCameraTask = nil
        }
    }

    func clearSelection() {
        selectionCameraTask?.cancel()
        selectionCameraTask = nil
        publishSelection(nil)
    }

    func focusNotificationStore(_ id: UUID) {
        pendingFocusedStoreID = id
        applyPendingNotificationFocus()
    }

    func prepareForMissionChange() {
        resetMissionPresentation()
    }

    func receiveVisibleRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
    }

    func refresh() {
        requestFreshLocation()
        guard let lastLocation,
              MapLocationFreshnessPolicy.isUsableForAutomaticRecenter(
                  lastLocation
              ) else { return }
        discover(force: true)
    }

    func distanceText(for store: MapStore?) -> String {
        guard let store, let coordinate else { return "Nearby" }
        let distance = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ).distance(from: CLLocation(
            latitude: store.coordinate.latitude,
            longitude: store.coordinate.longitude
        ))
        if distance >= 1_000 {
            return String(format: "%.1f km away", distance / 1_000)
        }
        return "\(max(Int(distance.rounded()), 1)) m away"
    }

    func locationContext(for store: MapStore) -> String {
        let distance = distanceText(for: store)
        let sameNameStores = stores.filter {
            ShoppingMissionStoreIdentityPolicy.hasSameVisibleName($0, store)
        }
        guard sameNameStores.count > 1 else { return distance }
        guard let coordinate else {
            let ordered = sameNameStores.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
            let number = (ordered.firstIndex { $0.id == store.id } ?? 0) + 1
            return "\(distance) · location \(number)"
        }
        let relativeDirection = direction(
            from: coordinate,
            to: store.coordinate
        )
        return "\(distance) · \(relativeDirection)"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            requestFreshLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let value = locations.last(where: {
            MapLocationFreshnessPolicy.isUsableForAutomaticRecenter($0)
        }) else {
            _ = retryFreshLocationIfNeeded()
            return
        }
        remainingFreshLocationRetries = 0
        receiveUserLocation(value)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        publishLoading(false)
    }

    private func discover(force: Bool) {
        guard let coordinate,
              let listID,
              let listRevision else {
            publishStores([])
            publishProducts([])
            publishSelection(nil)
            return
        }
        let neededItems = ShoppingMissionProductStateAdapter.neededItems(
            from: entries
        )
        guard !neededItems.isEmpty else {
            publishStores([])
            publishProducts([])
            publishSelection(nil)
            return
        }
        let signature = [
            listID.rawValue.uuidString,
            coordinateSignature(coordinate),
            neededItems.map {
                [
                    $0.identity.productID.rawValue.uuidString,
                    $0.displayName,
                    $0.catalogCategoryID ?? ""
                ].joined(separator: "=")
            }.sorted().joined(separator: "|")
        ].joined(separator: ":")
        if !force, signature == lastSignature { return }
        lastSignature = signature
        lastDiscoveryCoordinate = coordinate
        searchTask?.cancel()
        publishLoading(true)
        let intents = intentMatcher.resolutionIntents(
            for: neededItems,
            sourceListID: listID,
            sourceRevision: listRevision
        )
        guard !intents.isEmpty else {
            publishStores([])
            publishProducts([])
            publishSelection(nil)
            publishLoading(false)
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await resolutionEngine.resolve(
                savedStores: [],
                intents: intents,
                around: coordinate,
                forceRefresh: force
            )
            guard !Task.isCancelled else { return }
            let recommendations = ShoppingMissionRecommendationAuthority
                .recommendations(
                    stores: resolved,
                    items: neededItems,
                    userCoordinate: coordinate
                )
            let recommendedStores = recommendations.map(\.store)
            publishStores(recommendedStores)
            let resolvedProducts = makeProductMarkers(
                stores: recommendedStores,
                items: neededItems
            )
            publishProducts(resolvedProducts)
            publishSelection(
                ShoppingMissionMapSelectionPolicy.validSelection(
                    current: selectedStoreID,
                    availableStoreIDs: Set(recommendedStores.map(\.id))
                )
            )
            publishLoading(false)
            searchTask = nil
        }
    }

    private func requestCamera(
        _ region: MKCoordinateRegion,
        animated: Bool
    ) {
        cameraRequest = WayTaskProductionMapCameraRequest(
            id: (cameraRequest?.id ?? 0) &+ 1,
            region: region,
            animated: animated
        )
    }

    private func requestFreshLocation() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        guard status == .authorizedAlways
                || status == .authorizedWhenInUse
        else { return }
        remainingFreshLocationRetries = 2
        locationManager.requestLocation()
    }

    private func retryFreshLocationIfNeeded() -> Bool {
        guard remainingFreshLocationRetries > 0 else { return false }
        remainingFreshLocationRetries -= 1
        locationManager.requestLocation()
        return true
    }

    private func resetMissionPresentation() {
        searchTask?.cancel()
        searchTask = nil
        selectionCameraTask?.cancel()
        selectionCameraTask = nil
        lastSignature = nil
        lastDiscoveryCoordinate = nil
        publishSelection(nil)
        publishStores([])
        publishProducts([])
        publishLoading(false)
    }

    private func publishStores(_ proposed: [MapStore]) {
        guard ShoppingMissionMapPublicationPolicy.shouldPublish(
            current: stores,
            proposed: proposed
        ) else { return }
        stores = proposed
        applyPendingNotificationFocus()
    }

    private func publishProducts(_ proposed: [MapProduct]) {
        guard ShoppingMissionMapPublicationPolicy.shouldPublish(
            current: products,
            proposed: proposed
        ) else { return }
        products = proposed
    }

    private func publishSelection(_ proposed: UUID?) {
        guard selectedStoreID != proposed else { return }
        selectedStoreID = proposed
    }

    private func publishLoading(_ proposed: Bool) {
        guard isLoading != proposed else { return }
        isLoading = proposed
    }

    private func applyPendingNotificationFocus() {
        guard let pendingFocusedStoreID,
              let store = stores.first(where: {
                  $0.id == pendingFocusedStoreID
              }) else { return }
        self.pendingFocusedStoreID = nil
        publishSelection(store.id)
        requestCamera(MKCoordinateRegion(
            center: store.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: 0.008,
                longitudeDelta: 0.008
            )
        ), animated: true)
        BetaDiagnosticsCenter.shared.notificationBottomSheetOpened(
            store: store.title
        )
    }

    private func distance(
        from origin: CLLocationCoordinate2D?,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        guard let origin else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            ))
    }

    private func shouldRecenter(
        on coordinate: CLLocationCoordinate2D
    ) -> Bool {
        guard let visibleRegion else { return true }
        let latitudeLimit = visibleRegion.span.latitudeDelta * 0.38
        let longitudeLimit = visibleRegion.span.longitudeDelta * 0.38
        return abs(coordinate.latitude - visibleRegion.center.latitude)
                > latitudeLimit
            || abs(coordinate.longitude - visibleRegion.center.longitude)
                > longitudeLimit
    }

    private func coordinateSignature(
        _ coordinate: CLLocationCoordinate2D
    ) -> String {
        let latitudeBucket = Int((coordinate.latitude * 500).rounded())
        let longitudeBucket = Int((coordinate.longitude * 500).rounded())
        return "\(latitudeBucket),\(longitudeBucket)"
    }

    private func direction(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> String {
        let latitude = destination.latitude - origin.latitude
        let longitude = destination.longitude - origin.longitude
        if abs(latitude) > abs(longitude) * 1.5 {
            return latitude >= 0 ? "north" : "south"
        }
        if abs(longitude) > abs(latitude) * 1.5 {
            return longitude >= 0 ? "east" : "west"
        }
        switch (latitude >= 0, longitude >= 0) {
        case (true, true): return "north-east"
        case (true, false): return "north-west"
        case (false, true): return "south-east"
        case (false, false): return "south-west"
        }
    }

    private func makeProductMarkers(
        stores: [MapStore],
        items: [ShoppingPlanInputItem]
    ) -> [MapProduct] {
        var placed = Set<ProductStateProductID>()
        var markers: [MapProduct] = []
        for store in stores {
            for item in items {
                let productID = item.identity.productID
                guard !placed.contains(productID),
                      store.itemNames.contains(where: {
                          $0.localizedCaseInsensitiveCompare(
                              item.displayName
                          ) == .orderedSame
                      }) else { continue }
                placed.insert(productID)
                markers.append(
                    MapProduct(
                        id: productID.rawValue,
                        storeID: store.id,
                        name: item.displayName,
                        coordinate: store.coordinate
                    )
                )
            }
        }
        return markers
    }
}

private struct WayTaskProductionMapView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: WayTaskProductionTab
    let notificationStoreID: UUID?
    @StateObject private var model = WayTaskProductionMapModel()
    @State private var isCreatingList = false
    @State private var newListTitle = ""
    @FocusState private var isListTitleFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskMapView(
                    stores: model.visibleStores,
                    products: model.visibleProducts,
                    cameraTarget: model.cameraTarget,
                    cameraRequestID: model.cameraRequestID,
                    cameraShouldAnimate: model.cameraShouldAnimate,
                    onSelectStore: model.selectStore,
                    onClearSelection: clearMapSelection,
                    onMapRegionChanged: model.receiveVisibleRegion,
                    onUserLocationChanged: { _ in },
                    onUserLocationReceived: {
                        model.receiveUserLocation($0)
                    },
                    onUserMapInteraction: model.userDidExploreMap
                )
                .equatable()
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    missionHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            mapControl(
                                icon: "location.fill",
                                label: "Follow current location",
                                action: model.followUser
                            )
                            mapControl(
                                icon: "arrow.clockwise",
                                label: "Refresh nearby stores",
                                action: model.refresh
                            )
                        }
                        .padding(.trailing, 14)
                        .padding(.top, 12)
                    }

                    Spacer()

                    if model.isLoading {
                        Label("Finding nearby stores…", systemImage: "location.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 8)
                    }

                    if !model.visibleStores.isEmpty { storeCards }

                    selectedStoreSheet
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: mapInputSignature) {
                model.start(
                    list: selectedList,
                    entries: selectedList.map {
                        $0.neededEntries + $0.resolvedEntries
                            + $0.unresolvedEntries
                    } ?? []
                )
                if let notificationStoreID {
                    model.focusNotificationStore(notificationStoreID)
                }
            }
            .sheet(
                isPresented: $isCreatingList,
                onDismiss: resetCreateListPresentation
            ) {
                createListSheet
            }
            .onChange(of: selectedTab) { _, tab in
                if tab != .map { dismissKeyboard() }
            }
            .onChange(of: notificationStoreID) { _, id in
                if let id { model.focusNotificationStore(id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.applicationDidBecomeActive()
                } else {
                    model.applicationDidBecomeInactive()
                }
            }
            .onDisappear { dismissKeyboard() }
        }
    }

    @ViewBuilder
    private var selectedStoreSheet: some View {
        Group {
            if let store = model.selectedStore {
                MapBottomSheet(
                    store: store,
                    distanceText: model.locationContext(for: store),
                    likelyItemNames: store.itemNames,
                    otherItemNames: [],
                    canOpenItems: selectedList != nil,
                    animatesStoreChanges: false,
                    onNavigate: navigate,
                    onWebsite: openWebsite,
                    onOpenItems: { selectedTab = .shopping }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: 0.2),
            value: model.selectedStoreID != nil
        )
    }

    private var missionHeader: some View {
        Menu {
            if projectedLists.isEmpty {
                Button("No Shopping Lists") { }
                    .disabled(true)
            } else {
                ForEach(projectedLists, id: \.id) { list in
                    Button {
                        dismissKeyboard()
                        guard list.id != selectedList?.id else { return }
                        model.prepareForMissionChange()
                        runtime.selectList(list.id)
                    } label: {
                        if list.id == selectedList?.id {
                            Label(list.title, systemImage: "checkmark")
                        } else {
                            Text(list.title)
                        }
                    }
                }
            }

            Divider()

            Button {
                beginCreatingList()
            } label: {
                Label("Create New List", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(WayTaskDesign.accentGradient)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shopping Mission")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WayTaskDesign.accent)
                        .textCase(.uppercase)

                    HStack(spacing: 5) {
                        Text(selectedList?.title ?? "Select a Shopping List")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Text(missionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
            .clipShape(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(missionAccessibilityLabel)
        .accessibilityHint(
            "Opens the shopping list selector for this map mission"
        )
    }

    private var storeCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.visibleStores) { store in
                    Button {
                        model.selectStore(store.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "storefront.fill")
                                .foregroundStyle(WayTaskDesign.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.title)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                                Text(model.locationContext(for: store))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    model.selectedStoreID == store.id
                                        ? WayTaskDesign.accent
                                        : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
        .padding(.bottom, 8)
    }

    private func mapControl(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(WayTaskDesign.accentGradient)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func navigate() {
        guard let store = model.selectedStore else { return }
        let item = MKMapItem(
            location: CLLocation(
                latitude: store.coordinate.latitude,
                longitude: store.coordinate.longitude
            ),
            address: nil
        )
        item.name = store.title
        item.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }

    private func openWebsite() {
        guard let url = model.selectedStore?.websiteURL else { return }
        openURL(url)
    }

    private func clearMapSelection() {
        dismissKeyboard()
        model.clearSelection()
    }

    private func beginCreatingList() {
        dismissKeyboard()
        newListTitle = ""
        isCreatingList = true
        DispatchQueue.main.async { isListTitleFocused = true }
    }

    private func resetCreateListPresentation() {
        isListTitleFocused = false
        newListTitle = ""
        dismissKeyboard()
    }

    private var createListSheet: some View {
        NavigationStack {
            Form {
                TextField("List name", text: $newListTitle)
                    .focused($isListTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(createMissionList)
            }
            .navigationTitle("New Shopping List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isListTitleFocused = false
                        isCreatingList = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createMissionList)
                        .disabled(trimmedNewListTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createMissionList() {
        let title = trimmedNewListTitle
        guard !title.isEmpty else { return }
        isListTitleFocused = false
        if runtime.createList(title: title) != nil {
            model.prepareForMissionChange()
            isCreatingList = false
        }
    }

    private var selectedList: ProductStateNamedListProjection? {
        projectedLists.first { $0.id == runtime.selectedListID }
    }

    private var projectedLists: [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(list) = $0 else { return nil }
            return list
        }
    }

    private var missionSummary: String {
        guard let selectedList else {
            return projectedLists.isEmpty
                ? "Create a list to find stores"
                : "Choose the list for this map"
        }
        let quantity = selectedList.neededEntries.reduce(0) {
            $0 + $1.quantity
        }
        guard quantity > 0 else { return "No needed items" }
        let formatted = quantity.rounded() == quantity
            ? String(Int(quantity))
            : quantity.formatted(
                .number.precision(.fractionLength(1))
            )
        return "\(formatted) needed \(quantity == 1 ? "item" : "items")"
    }

    private var missionAccessibilityLabel: String {
        guard let selectedList else {
            return "Shopping Mission, no shopping list selected"
        }
        return "Shopping Mission, \(selectedList.title), \(missionSummary)"
    }

    private var trimmedNewListTitle: String {
        newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissKeyboard() {
        isListTitleFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var mapInputSignature: String {
        guard let selectedList else { return "none" }
        return [
            selectedList.id.rawValue.uuidString,
            String(selectedList.revision.value),
            selectedList.neededEntries
                .map(\.identity.id.rawValue.uuidString)
                .joined(separator: ",")
        ].joined(separator: ":")
    }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
