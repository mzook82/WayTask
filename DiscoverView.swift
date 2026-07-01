import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appStateManager: AppStateManager
    @StateObject private var viewModel = DiscoverViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        WayTaskScreenHeader(
                            title: "Discover",
                            subtitle: "Nearby shopping context and local opportunities",
                            trailingIcons: ["slider.horizontal.3"]
                        )
                        .padding(.top, 8)

                        ForEach(DiscoverCategory.allCases) { category in
                            discoverSection(category)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "Discover",
                isPresented: Binding(
                    get: { viewModel.statusMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.statusMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.statusMessage = nil
                }
            } message: {
                Text(viewModel.statusMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func discoverSection(_ category: DiscoverCategory) -> some View {
        let items = viewModel.items(for: category)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.rawValue)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)

                Spacer()

                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WayTaskDesign.tertiaryText)
            }

            if items.isEmpty {
                emptySectionCard
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        discoverCard(item)
                    }
                }
            }
        }
    }

    private var emptySectionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 42, height: 42)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("More context will appear here as WayTask learns from lists, location, and stores.")
                .font(.subheadline)
                .foregroundStyle(WayTaskDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .wayTaskCard(cornerRadius: 18)
    }

    private func discoverCard(_ item: DiscoverItem) -> some View {
        Button {
            viewModel.handleSelection(item, appStateManager: appStateManager)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(item.canOpenMap ? AnyShapeStyle(WayTaskDesign.accentGradient) : AnyShapeStyle(WayTaskDesign.surfaceElevated))

                    Image(systemName: item.systemImageName ?? "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(item.canOpenMap ? .white : WayTaskDesign.accent)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WayTaskDesign.primaryText)
                            .lineLimit(1)

                        if let distance = item.distance {
                            Text(distance)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WayTaskDesign.accent)
                                .lineLimit(1)
                        }
                    }

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)

                    Label(item.relevanceReason, systemImage: sourceIcon(for: item.sourceType))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.tertiaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: item.canOpenMap ? "map.fill" : "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.tertiaryText)
            }
            .padding(14)
            .wayTaskCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private func sourceIcon(for sourceType: DiscoverSourceType) -> String {
        switch sourceType {
        case .localSample:
            return "shippingbox"
        case .shoppingContext:
            return "checklist"
        case .savedStore:
            return "storefront"
        case .futureRecommendation:
            return "sparkles"
        }
    }
}
