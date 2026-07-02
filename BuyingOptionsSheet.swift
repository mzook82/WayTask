import SwiftUI

struct BuyingOptionsSheet: View {
    let options: [BuyingOption]
    let onViewOnMap: (BuyingOption) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

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

private struct BuyingOptionCard: View {
    let option: BuyingOption
    let isBestMatch: Bool
    let onViewOnMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                optionIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if isBestMatch {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2.weight(.bold))
                                    .baselineOffset(0)

                                Text("Best Match")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(WayTaskDesign.accent)
                            .clipShape(Capsule())
                        }

                        Text(optionBadgeTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(option.isActionableOnMap ? .white : WayTaskDesign.secondaryText)
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
