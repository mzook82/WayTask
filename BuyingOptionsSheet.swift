import SwiftUI

struct BuyingOptionsSheet: View {
    let options: [BuyingOption]
    let tripCoverages: [StoreCoverage]
    let activeTripItemCount: Int
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
                                    totalItemCount: tripItemCount(for: bestTripCoverage),
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
            }
        }
        .preferredColorScheme(.dark)
    }

    private var shouldShowShoppingTripSection: Bool {
        activeTripItemCount >= 1
    }

    private var bestTripCoverage: StoreCoverage? {
        tripCoverages.first
    }

    private func tripItemCount(for coverage: StoreCoverage) -> Int {
        coverage.matchedItemCount + coverage.missingItemCount
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

            Text("No buying options yet")
                .font(.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text("Try another item or check the map for nearby places.")
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

                Text("Trip suggestions will appear when WayTask finds stores that match your list.")
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
    let totalItemCount: Int
    let onViewTripOnMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.walk.motion")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(WayTaskDesign.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Shopping Trip")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WayTaskDesign.accent)

                    Text(coverage.store.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)

                    Text("Best store for this trip")
                        .font(.subheadline)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }

                Spacer(minLength: 0)

                Text("\(coverage.matchedItemCount)/\(max(totalItemCount, 1))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(WayTaskDesign.accent)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                if let distanceText {
                    Label(distanceText, systemImage: "location")
                }

                Label("Covers \(coverage.matchedItemCount) of \(max(totalItemCount, 1)) list items", systemImage: "checklist")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WayTaskDesign.secondaryText)

            if !coverage.matchedItems.isEmpty {
                itemGroup(title: "Matched", items: coverage.matchedItems, icon: "checkmark.circle.fill")
            }

            if !coverage.missingItems.isEmpty {
                itemGroup(title: "Missing", items: coverage.missingItems, icon: "minus.circle")
            }

            if !coverage.ranking.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coverage.ranking.reasons.prefix(3), id: \.self) { reason in
                        Label(reason, systemImage: "sparkle")
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

            Button(action: onViewTripOnMap) {
                Label("View Trip on Map", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 48, cornerRadius: 16, shadow: true))
        }
        .padding(16)
        .background(WayTaskDesign.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.34), lineWidth: 1)
        }
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

    private func itemGroup(title: String, items: [ShoppingItem], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(WayTaskDesign.secondaryText)

            FlexibleItemList(items: items.map(\.name))
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

            if !option.recommendationReasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(option.recommendationReasons, id: \.self) { reason in
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
        if isBestMatch {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .imageScale(.small)

                Text("Best Match")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WayTaskDesign.accent)
            .clipShape(Capsule())
        }

        Text(optionBadgeTitle)
            .font(.caption2.weight(.bold))
            .foregroundStyle(option.isActionableOnMap ? .white : WayTaskDesign.secondaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(option.isActionableOnMap ? WayTaskDesign.accent.opacity(isBestMatch ? 0.72 : 1) : WayTaskDesign.surfaceElevated)
            .clipShape(Capsule())

        if let confidenceLabel = option.confidenceLabel {
            Text(confidenceLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(1)
        }
    }

    private var optionBadgeTitle: String {
        switch option.optionType {
        case .nearbyStore:
            return "Nearby"
        case .suggestedStore:
            return "Suggested"
        case .onlineStore:
            return "Online Coming Soon"
        case .futurePriceComparison:
            return "Price Later"
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
