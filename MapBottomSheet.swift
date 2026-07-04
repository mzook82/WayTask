import SwiftUI

struct MapBottomSheet: View {
    let store: MapStore?
    let distanceText: String
    let canOpenItems: Bool
    let onNavigate: () -> Void
    let onWebsite: () -> Void
    let onOpenItems: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.32))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            if let store {
                storeContent(store)
            } else {
                emptyContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store?.id)
    }

    private func storeContent(_ store: MapStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(WayTaskDesign.accentGradient)

                    Image(systemName: "storefront.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        statusPill(isOpen: store.isOpen)
                        Label(distanceText, systemImage: "location")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let rating = store.rating {
                            Label(String(format: "%.1f rating", rating), systemImage: "star.fill")
                        }

                        if store.isSavedLocation {
                            Label("Saved by you", systemImage: "bookmark.fill")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Matching items")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if store.itemNames.isEmpty {
                    Text("No active shopping list items for this place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    FlowItems(items: Array(store.itemNames.prefix(5)))
                }
            }

            HStack(spacing: 10) {
                Button(action: onNavigate) {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 48, cornerRadius: 16, shadow: true))

                Button(action: onOpenItems) {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 48, cornerRadius: 16))
                .disabled(!canOpenItems)
                .opacity(canOpenItems ? 1 : 0.45)
                .accessibilityLabel(canOpenItems ? "Open items" : "Items are available only for saved locations")

                if store.websiteURL != nil {
                    Button(action: onWebsite) {
                        Image(systemName: "safari.fill")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 48, cornerRadius: 16))
                    .accessibilityLabel("Open website")
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var emptyContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 44, height: 44)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Select a nearby place")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Stores with matching shopping items appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func statusPill(isOpen: Bool?) -> some View {
        Text(statusText(isOpen))
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor(isOpen))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(isOpen).opacity(0.14))
            .clipShape(Capsule())
    }

    private func statusText(_ isOpen: Bool?) -> String {
        switch isOpen {
        case true:
            return "Open"
        case false:
            return "Closed"
        case nil:
            return "Hours unavailable"
        }
    }

    private func statusColor(_ isOpen: Bool?) -> Color {
        switch isOpen {
        case true:
            return .green
        case false:
            return .red
        case nil:
            return .secondary
        }
    }
}

private struct FlowItems: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }
}
