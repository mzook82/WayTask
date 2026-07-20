import SwiftUI

struct BuyingOptionsSheet: View {
    let options: [BuyingOption]
    let tripCoverages: [StoreCoverage]
    let activeTripItems: [ShoppingItem]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onViewOnMap: (BuyingOption) -> Void
    let onViewTripOnMap: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        if shouldShowShoppingTripSection {
                            if let bestTripCoverage {
                                ShoppingTripCoverageCard(
                                    coverage: bestTripCoverage,
                                    activeTripItems: activeTripItems,
                                    onViewTripOnMap: onViewTripOnMap
                                )
                            } else {
                                ShoppingTripUnavailableCard()
                            }
                        }

                        if options.isEmpty {
                            emptyState
                        } else {
                            ForEach(options) { option in
                                BuyingOptionCard(
                                    option: option,
                                    isBestMatch: option.id == bestMatchOptionID,
                                    onViewOnMap: {
                                        onViewOnMap(option)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .tint(WayTaskDesign.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onRefresh) {
                        if isRefreshing {
                            ProgressView()
                                .tint(WayTaskDesign.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .tint(WayTaskDesign.accent)
                    .accessibilityLabel("Refresh Suggested Places")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var shouldShowShoppingTripSection: Bool {
        !activeTripItems.isEmpty
    }

    private var bestTripCoverage: StoreCoverage? {
        tripCoverages.first
    }

    private var bestMatchOptionID: UUID? {
        options
            .filter(\.isActionableOnMap)
            .max { lhs, rhs in
                (lhs.ranking?.score ?? 0) < (rhs.ranking?.score ?? 0)
            }?
            .id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buying Options")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WayTaskDesign.primaryText)

            Text("Choose how you want to continue with this item.")
                .font(.subheadline)
                .foregroundStyle(WayTaskDesign.secondaryText)
        }
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(WayTaskDesign.tertiaryText)

            Text("No suitable stores found")
                .font(.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text("WayTask could not resolve a realistic store type for this item.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WayTaskDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .wayTaskCard()
    }
}

private struct ShoppingTripUnavailableCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.walk.motion")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 44, height: 44)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Shopping Trip")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WayTaskDesign.accent)

                Text("Recommended stores will appear when WayTask can estimate products from your shopping list.")
                    .font(.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(WayTaskDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingTripCoverageCard: View {
    let coverage: StoreCoverage
    let activeTripItems: [ShoppingItem]
    let onViewTripOnMap: () -> Void

    var body: some View {
        WayTaskRecommendationCard(
            recommendationTitle: recommendationTitle,
            storeName: coverage.store.title,
            likelyItemNames: coverage.matchedItems.map(\.name),
            otherItemNames: otherItemNames,
            totalItemCount: activeTripItems.count,
            distanceText: distanceText,
            isHighlighted: true,
            actionTitle: "View Trip on Map",
            action: onViewTripOnMap
        )
    }

    private var distanceText: String? {
        guard let distance = coverage.distance else {
            return nil
        }

        if distance >= 1000 {
            return String(format: "%.1f km away", distance / 1000)
        }

        return "\(max(Int(distance), 1)) m away"
    }

    private var otherItemNames: [String] {
        let likelyItemIDs = Set(coverage.matchedItems.map(\.id))
        return activeTripItems.filter { !likelyItemIDs.contains($0.id) }.map(\.name)
    }

    private var recommendationTitle: String {
        switch coverage.group {
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
}

private struct FlexibleItemList: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
            }

            VStack(alignment: .leading, spacing: 6) {
                chips
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(items.prefix(4), id: \.self) { item in
            Text(item)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WayTaskDesign.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

private struct BuyingOptionCard: View {
    let option: BuyingOption
    let isBestMatch: Bool
    let onViewOnMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                optionIcon

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            badges
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            badges
                        }
                    }

                    Text(option.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)

                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                if !option.storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(option.storeName, systemImage: "storefront")
                        .lineLimit(1)
                }

                if !option.distanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(option.distanceText, systemImage: "location")
                        .lineLimit(1)
                }

                if let priceText = option.priceText {
                    Label(priceText, systemImage: "tag")
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WayTaskDesign.secondaryText)

            if !presentationReasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(presentationReasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Availability is estimated.")
                    Text("Some items may require another store.")
                }
            }
            .font(.caption)
            .foregroundStyle(WayTaskDesign.secondaryText)

            if option.isActionableOnMap {
                Button(action: onViewOnMap) {
                    Label("View on Map", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 48, cornerRadius: 16, shadow: true))
            } else {
                Label("Coming Soon", systemImage: "clock")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WayTaskDesign.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(WayTaskDesign.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
                    }
            }
        }
        .padding(16)
        .background(isBestMatch ? WayTaskDesign.accent.opacity(0.08) : WayTaskDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isBestMatch ? WayTaskDesign.accent.opacity(0.34) : WayTaskDesign.surfaceBorder, lineWidth: 1)
        }
    }

    private var optionIcon: some View {
        Image(systemName: option.iconName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(WayTaskDesign.accent)
            .frame(width: 44, height: 44)
            .background(WayTaskDesign.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var badges: some View {
        Text(optionBadgeTitle)
            .font(.caption2.weight(.bold))
            .foregroundStyle(option.isActionableOnMap ? .white : WayTaskDesign.secondaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(option.isActionableOnMap ? WayTaskDesign.accent.opacity(isBestMatch ? 0.72 : 1) : WayTaskDesign.surfaceElevated)
            .clipShape(Capsule())

    }

    private var optionBadgeTitle: String {
        switch option.optionType {
        case .nearbyStore:
            return "Recommended Store"
        case .suggestedStore:
            return "Recommended Store"
        case .onlineStore:
            return "Online Coming Soon"
        case .futurePriceComparison:
            return "Price Later"
        }
    }

    private var presentationReasons: [String] {
        option.recommendationReasons.filter { reason in
            !reason.hasPrefix("Covers ") &&
                reason.range(of: "match", options: .caseInsensitive) == nil
        }
    }
}

private extension BuyingOption {
    var isActionableOnMap: Bool {
        switch optionType {
        case .nearbyStore, .suggestedStore:
            return true
        case .onlineStore, .futurePriceComparison:
            return false
        }
    }

    var iconName: String {
        switch optionType {
        case .nearbyStore:
            return "mappin.and.ellipse"
        case .suggestedStore:
            return "storefront"
        case .onlineStore:
            return "globe"
        case .futurePriceComparison:
            return "tag"
        }
    }
}
