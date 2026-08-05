import SwiftUI

struct ProductStateRuntimeRootView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ProductStateRuntimeHomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label(
                        AppTab.home.title,
                        systemImage: AppTab.home.systemImageName
                    )
                }
                .tag(AppTab.home)

            ProductStateRuntimeLibraryView()
                .tabItem {
                    Label(
                        AppTab.products.title,
                        systemImage: AppTab.products.systemImageName
                    )
                }
                .tag(AppTab.products)

            ProductStateRuntimeShoppingView()
                .tabItem {
                    Label(
                        AppTab.shopping.title,
                        systemImage: AppTab.shopping.systemImageName
                    )
                }
                .tag(AppTab.shopping)

            ProductStateRuntimeMapView()
                .tabItem {
                    Label(
                        AppTab.map.title,
                        systemImage: AppTab.map.systemImageName
                    )
                }
                .tag(AppTab.map)

        }
        .tint(WayTaskDesign.accent)
        .onAppear { runtime.refresh() }
    }
}

private struct ProductStateRuntimeHomeView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.lg) {
                    Text("WayTask")
                        .font(WayTaskDesign.Typography.largeTitle)
                        .foregroundStyle(WayTaskDesign.primaryText)

                    HStack(spacing: WayTaskDesign.Spacing.sm) {
                        metric(
                            value: runtime.homeState.home.productLibraryCount,
                            title: "Products",
                            image: "shippingbox.fill"
                        )
                        metric(
                            value: runtime.homeState.home.namedLists.count,
                            title: "Lists",
                            image: "list.bullet"
                        )
                        metric(
                            value: activeSessionCount,
                            title: "Sessions",
                            image: "figure.walk"
                        )
                    }

                    WayTaskSectionHeader(title: "Shopping lists")
                    if runtime.homeState.home.namedLists.isEmpty {
                        WayTaskEmptyState(
                            title: "No shopping lists",
                            message: "Create a named List in Shopping.",
                            systemImage: "list.bullet.rectangle"
                        ) {
                            selectedTab = .shopping
                        }
                    } else {
                        ForEach(runtime.homeState.home.namedLists) { list in
                            Button {
                                runtime.selectList(list.id)
                                selectedTab = .shopping
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(list.title)
                                            .font(WayTaskDesign.Typography.headline)
                                        Text("\(list.neededCount) needed · \(list.resolvedCount) resolved")
                                            .font(WayTaskDesign.Typography.caption)
                                            .foregroundStyle(WayTaskDesign.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(WayTaskDesign.Spacing.md)
                                .wayTaskGlassCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    WayTaskSectionHeader(title: "Recent products")
                    if runtime.homeState.home.productCards.isEmpty {
                        Text("Products you add appear here.")
                            .foregroundStyle(WayTaskDesign.secondaryText)
                    } else {
                        ForEach(runtime.homeState.home.productCards) { card in
                            Text(card.row.product.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(WayTaskDesign.Spacing.md)
                                .wayTaskGlassCard()
                        }
                    }
                }
                .padding(WayTaskDesign.Spacing.lg)
            }
            .background(WayTaskDesign.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var activeSessionCount: Int {
        guard case let .projection(value) = runtime.activeSessions else {
            return 0
        }
        return value.candidates.count
    }

    private func metric(
        value: Int,
        title: String,
        image: String
    ) -> some View {
        VStack(spacing: WayTaskDesign.Spacing.xs) {
            Image(systemName: image)
                .foregroundStyle(WayTaskDesign.accent)
            Text("\(value)")
                .font(WayTaskDesign.Typography.title)
                .foregroundStyle(WayTaskDesign.primaryText)
            Text(title)
                .font(WayTaskDesign.Typography.caption)
                .foregroundStyle(WayTaskDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard()
    }
}

private struct ProductStateRuntimeLibraryView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @State private var isAddingProduct = false
    @State private var productName = ""

    var body: some View {
        NavigationStack {
            List {
                if let message = runtime.lastMutationMessage {
                    Text(message)
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
                switch runtime.homeState.library {
                case .idle:
                    ProgressView()
                case .unavailable:
                    ContentUnavailableView(
                        "Product State unavailable",
                        systemImage: "exclamationmark.shield"
                    )
                case .invalid:
                    ContentUnavailableView(
                        "Product State invalid",
                        systemImage: "exclamationmark.triangle"
                    )
                case let .available(library):
                    Section("Product library") {
                        ForEach(library.visibleProducts) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.product.displayName)
                                if let subtitle = row.product.brand ??
                                    row.product.category {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if case let .available(removed, _) =
                        library.removedProducts {
                        Section("Removed") {
                            ForEach(removed) { row in
                                HStack {
                                    Text(row.projection.product.displayName)
                                    Spacer()
                                    Button("Restore") {
                                        runtime.restore(
                                            row.projection.product
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WayTaskDesign.background)
            .navigationTitle("Products")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        productName = ""
                        isAddingProduct = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add product")
                }
            }
            .sheet(isPresented: $isAddingProduct) {
                NavigationStack {
                    Form {
                        TextField("Product name", text: $productName)
                    }
                    .navigationTitle("Add Product")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isAddingProduct = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                runtime.acquireProduct(name: productName)
                                isAddingProduct = false
                            }
                            .disabled(
                                productName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct ProductStateRuntimeShoppingView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime
    @State private var isCreatingList = false
    @State private var listTitle = ""
    @State private var isAddingProduct = false

    var body: some View {
        NavigationStack {
            List {
                Section("Named List") {
                    ForEach(projectedLists, id: \.id) { list in
                        Button {
                            runtime.selectList(list.id)
                        } label: {
                            HStack {
                                Text(list.title)
                                Spacer()
                                if runtime.selectedListID == list.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Button("Create named List", systemImage: "plus") {
                        listTitle = ""
                        isCreatingList = true
                    }
                }

                if let list = selectedList {
                    Section("Needed") {
                        if list.neededEntries.isEmpty {
                            Text("No needed entries")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(list.neededEntries, id: \.identity.id) { entry in
                            entryRow(entry, list: list, isResolved: false)
                        }
                    }
                    Section("Resolved") {
                        ForEach(list.resolvedEntries, id: \.identity.id) { entry in
                            entryRow(entry, list: list, isResolved: true)
                        }
                    }
                    Section {
                        Button("Add Product to List", systemImage: "plus") {
                            isAddingProduct = true
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Choose a named List",
                            systemImage: "list.bullet"
                        )
                    }
                }

                sessionSection
            }
            .scrollContentBackground(.hidden)
            .background(WayTaskDesign.background)
            .navigationTitle("Shopping")
            .sheet(isPresented: $isCreatingList) {
                NavigationStack {
                    Form { TextField("List title", text: $listTitle) }
                        .navigationTitle("New List")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isCreatingList = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Create") {
                                    runtime.createList(title: listTitle)
                                    isCreatingList = false
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
            .sheet(isPresented: $isAddingProduct) {
                NavigationStack {
                    List(availableProducts, id: \.id) { product in
                        Button(product.displayName) {
                            guard let list = selectedList else { return }
                            runtime.addProduct(product.id, to: list)
                            isAddingProduct = false
                        }
                    }
                    .navigationTitle("Add Product")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isAddingProduct = false }
                        }
                    }
                }
            }
        }
    }

    private var projectedLists: [ProductStateNamedListProjection] {
        runtime.namedLists.compactMap {
            guard case let .projection(value) = $0 else { return nil }
            return value
        }
    }

    private var selectedList: ProductStateNamedListProjection? {
        projectedLists.first { $0.id == runtime.selectedListID }
    }

    private var availableProducts: [ProductStateProductProjection] {
        guard case let .available(library) = runtime.homeState.library else {
            return []
        }
        let existing = Set(
            (selectedList?.neededEntries ?? []
             + (selectedList?.resolvedEntries ?? []))
                .map(\.identity.productID)
        )
        return library.products.map(\.product).filter {
            !existing.contains($0.id)
        }
    }

    @ViewBuilder
    private func entryRow(
        _ entry: ProductStateListEntryProjection,
        list: ProductStateNamedListProjection,
        isResolved: Bool
    ) -> some View {
        let row = ShoppingWorkspaceProjectionRow(entry: entry)
        HStack {
            VStack(alignment: .leading) {
                Text(entry.product?.displayName ?? "Unavailable Product")
                Text("Quantity \(entry.quantity, format: .number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if isResolved {
                    Button("Reopen") {
                        runtime.perform(.reopen, row: row, list: list)
                    }
                } else {
                    Button("Already have") {
                        runtime.perform(
                            .resolve(.alreadyHave),
                            row: row,
                            list: list
                        )
                    }
                    Button("No longer needed") {
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
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section("Shopping Session") {
            if case let .projection(lookup) = runtime.activeSessions {
                if lookup.candidates.isEmpty {
                    Text("No active Session")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lookup.candidates, id: \.sessionID) { session in
                        VStack(alignment: .leading) {
                            Text("Active Session")
                            Text("Revision \(session.revision.value)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Session authority unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProductStateRuntimeMapView: View {
    @EnvironmentObject private var runtime: ProductStateRuntime

    var body: some View {
        NavigationStack {
            Group {
                switch runtime.mapState.content {
                case .idle:
                    ContentUnavailableView(
                        "Choose a Shopping List",
                        systemImage: "map"
                    )
                case let .available(map), let .stale(map, _):
                    List {
                        Section("Map context") {
                            Text("List revision \(map.listRevision.value)")
                            Text("\(map.markers.count) exact markers")
                            Text("\(map.unresolvedProducts.count) unresolved products")
                        }
                        ForEach(map.visibleMarkers) { marker in
                            VStack(alignment: .leading) {
                                Text(marker.title)
                                Text("Exact Product State marker")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                case .unavailable:
                    ContentUnavailableView(
                        "Map context unavailable",
                        systemImage: "map"
                    )
                case .invalid:
                    ContentUnavailableView(
                        "Map context invalid",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .background(WayTaskDesign.background)
            .navigationTitle("Map")
        }
    }
}
