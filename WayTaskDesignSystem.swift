import SwiftUI

struct WayTaskDesign {
    static let accent = Color(red: 1.0, green: 0.48, blue: 0.0)
    static let accentRed = Color(red: 1.0, green: 0.27, blue: 0.0)
    static let primaryText = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let secondaryText = Color.white.opacity(0.48)
    static let tertiaryText = Color.white.opacity(0.26)
    static let surface = Color.white.opacity(0.055)
    static let surfaceElevated = Color.white.opacity(0.085)
    static let surfaceBorder = Color.white.opacity(0.08)
    static let scannerSurface = Color(red: 0.07, green: 0.07, blue: 0.09)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentRed],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.09, blue: 0.10),
                Color(red: 0.04, green: 0.04, blue: 0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct WayTaskScreenHeader: View {
    let title: String
    let subtitle: String
    var trailingIcons: [String] = []

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                ForEach(trailingIcons, id: \.self) { systemName in
                    WayTaskIconButton(systemName: systemName)
                }
            }
        }
    }
}

struct WayTaskIconButton: View {
    let systemName: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .frame(width: 40, height: 40)
                .background(WayTaskDesign.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WayTaskSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WayTaskDesign.tertiaryText)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .foregroundStyle(WayTaskDesign.primaryText)
                .submitLabel(.search)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .wayTaskCard(cornerRadius: 14)
        .accessibilityLabel(placeholder)
    }
}

struct WayTaskFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : WayTaskDesign.secondaryText)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(isSelected ? WayTaskDesign.accent : WayTaskDesign.surface)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : WayTaskDesign.surfaceBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WayTaskProductThumbnail: View {
    let data: Data?
    var size: CGFloat = 64
    var cornerRadius: CGFloat = 15
    var systemName: String = "shippingbox"

    var body: some View {
        Group {
            if let data,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    WayTaskDesign.surfaceElevated
                    Image(systemName: systemName)
                        .font(.title2)
                        .foregroundStyle(WayTaskDesign.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(data == nil)
    }
}

struct WayTaskPrimaryPillButtonStyle: ButtonStyle {
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 14
    var shadow: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: height == nil ? nil : .infinity)
            .frame(minHeight: height ?? 44)
            .background {
                WayTaskDesign.accentGradient
                    .opacity(configuration.isPressed ? 0.72 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadow ? WayTaskDesign.accent.opacity(0.36) : .clear, radius: shadow ? 18 : 0, y: shadow ? 8 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct WayTaskSecondaryPillButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 36
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(WayTaskDesign.secondaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: minHeight)
            .background(WayTaskDesign.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
    }
}

struct WayTaskModeTile: View {
    let title: String
    let systemName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .wayTaskCard(cornerRadius: 16)
    }
}

extension View {
    func wayTaskCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(WayTaskDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
    }
}
