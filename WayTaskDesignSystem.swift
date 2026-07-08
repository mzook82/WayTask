import Foundation
import SwiftUI
import UIKit

struct WayTaskDesign {
    struct Colors {
        static let accent = Color(red: 1.0, green: 0.48, blue: 0.0)
        static let accentRed = Color(red: 1.0, green: 0.27, blue: 0.0)
        static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let warning = Color(red: 1.0, green: 0.60, blue: 0.24)
        static let danger = Color(red: 1.0, green: 0.41, blue: 0.38)
        static let primaryText = Color(red: 0.96, green: 0.96, blue: 0.97)
        static let secondaryText = Color.white.opacity(0.56)
        static let tertiaryText = Color.white.opacity(0.30)
        static let backgroundTop = Color(red: 0.09, green: 0.09, blue: 0.10)
        static let backgroundBottom = Color(red: 0.04, green: 0.04, blue: 0.05)
        static let surface = Color.white.opacity(0.055)
        static let surfaceElevated = Color.white.opacity(0.085)
        static let surfaceStrong = Color.white.opacity(0.12)
        static let surfaceBorder = Color.white.opacity(0.08)
        static let scannerSurface = Color(red: 0.07, green: 0.07, blue: 0.09)
    }

    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.bold)
        static let sectionTitle = Font.title3.weight(.bold)
        static let headline = Font.headline.weight(.bold)
        static let body = Font.body
        static let bodyStrong = Font.body.weight(.semibold)
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let captionStrong = Font.caption.weight(.bold)
        static let metric = Font.system(size: 30, weight: .bold, design: .rounded)
    }

    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    struct Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let sheet: CGFloat = 28
    }

    struct Elevation {
        static let cardShadow = Color.black.opacity(0.20)
        static let cardRadius: CGFloat = 22
        static let cardY: CGFloat = 10
        static let buttonShadow = Colors.accent.opacity(0.36)
        static let buttonRadius: CGFloat = 18
        static let buttonY: CGFloat = 8
    }

    struct Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.16)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.24)
        static let spring = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.86)
    }

    static let accent = Colors.accent
    static let accentRed = Colors.accentRed
    static let primaryText = Colors.primaryText
    static let secondaryText = Colors.secondaryText
    static let tertiaryText = Colors.tertiaryText
    static let surface = Colors.surface
    static let surfaceElevated = Colors.surfaceElevated
    static let surfaceBorder = Colors.surfaceBorder
    static let scannerSurface = Colors.scannerSurface

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Colors.warning, Colors.accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var background: LinearGradient {
        LinearGradient(
            colors: [Colors.backgroundTop, Colors.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum WayTaskHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

struct WayTaskScreenHeader: View {
    let title: String
    let subtitle: String
    var trailingIcons: [String] = []

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                Text(title)
                    .font(WayTaskDesign.Typography.largeTitle)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(WayTaskDesign.Typography.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: WayTaskDesign.Spacing.md)

            HStack(spacing: WayTaskDesign.Spacing.xs) {
                ForEach(trailingIcons, id: \.self) { systemName in
                    WayTaskIconButton(systemName: systemName)
                }
            }
        }
    }
}

struct WayTaskSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WayTaskDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                Text(title)
                    .font(WayTaskDesign.Typography.sectionTitle)
                    .foregroundStyle(WayTaskDesign.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
            }

            Spacer(minLength: WayTaskDesign.Spacing.sm)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(WayTaskDesign.Typography.captionStrong)
                        .foregroundStyle(WayTaskDesign.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WayTaskIconButton: View {
    let systemName: String
    var action: () -> Void = {}

    var body: some View {
        Button {
            WayTaskHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .frame(width: 40, height: 40)
                .background(WayTaskDesign.surface)
                .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous)
                        .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct WayTaskPrimaryButton: View {
    let title: String
    let systemImage: String?
    var isDisabled = false
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button {
            WayTaskHaptics.impact(.soft)
            action()
        } label: {
            buttonLabel
        }
        .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 52, cornerRadius: WayTaskDesign.Radius.md, shadow: true))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var buttonLabel: some View {
        HStack(spacing: WayTaskDesign.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WayTaskSecondaryButton: View {
    let title: String
    let systemImage: String?
    var isDisabled = false
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button {
            WayTaskHaptics.selection()
            action()
        } label: {
            HStack(spacing: WayTaskDesign.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 48, cornerRadius: WayTaskDesign.Radius.md))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct WayTaskSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: WayTaskDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WayTaskDesign.tertiaryText)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .foregroundStyle(WayTaskDesign.primaryText)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                    WayTaskHaptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WayTaskDesign.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(WayTaskDesign.Typography.body)
        .padding(.horizontal, WayTaskDesign.Spacing.md)
        .frame(minHeight: 46)
        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.md)
        .accessibilityLabel(placeholder)
    }
}

struct WayTaskFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            WayTaskHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
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

struct WayTaskBadge: View {
    enum Tone {
        case accent
        case success
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .accent:
                return WayTaskDesign.accent
            case .success:
                return WayTaskDesign.Colors.success
            case .warning:
                return WayTaskDesign.Colors.warning
            case .danger:
                return WayTaskDesign.Colors.danger
            case .neutral:
                return WayTaskDesign.secondaryText
            }
        }
    }

    let title: String
    var systemImage: String?
    var tone: Tone = .accent

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(WayTaskDesign.Typography.captionStrong)
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.14))
        .clipShape(Capsule())
    }
}

struct WayTaskProductThumbnail: View {
    let data: Data?
    var url: URL? = nil
    var size: CGFloat = 64
    var cornerRadius: CGFloat = 15
    var systemName: String = "shippingbox"
    var onRemoteImageLoaded: ((Data) -> Void)? = nil
    @State private var remoteImageData: Data?
    @State private var remoteImageURL: URL?
    @State private var remoteLoadFailedURL: URL?

    var body: some View {
        Group {
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(displayImage == nil && url == nil)
        .task(id: url) {
            await loadRemoteImageIfNeeded()
        }
    }

    private var displayImage: UIImage? {
        if let data, let image = UIImage(data: data) {
            return image
        }

        if let remoteImageData,
           remoteImageURL == url,
           let image = UIImage(data: remoteImageData) {
            return image
        }

        return nil
    }

    private var placeholder: some View {
        ZStack {
            WayTaskDesign.surfaceElevated
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(WayTaskDesign.accent)
        }
    }

    private func loadRemoteImageIfNeeded() async {
        guard data == nil,
              let url,
              remoteImageURL != url,
              remoteLoadFailedURL != url else {
            return
        }

        do {
            let (loadedData, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  UIImage(data: loadedData) != nil else {
                remoteLoadFailedURL = url
                return
            }

            remoteImageData = loadedData
            remoteImageURL = url
            onRemoteImageLoaded?(loadedData)
        } catch {
            remoteLoadFailedURL = url
        }
    }
}

struct WayTaskProductCard: View {
    let title: String
    var subtitle: String?
    var detail: String?
    var imageData: Data?
    var imageURL: URL?
    var badges: [String] = []
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            HStack(alignment: .top, spacing: WayTaskDesign.Spacing.sm) {
                WayTaskProductThumbnail(data: imageData, url: imageURL, size: 64, cornerRadius: WayTaskDesign.Radius.md)

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                    Text(title)
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(WayTaskDesign.Typography.caption.weight(.semibold))
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(1)
                    }

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(WayTaskDesign.Typography.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)
            }

            if !badges.isEmpty || actionTitle != nil {
                HStack(spacing: WayTaskDesign.Spacing.xs) {
                    ForEach(badges.prefix(3), id: \.self) { badge in
                        WayTaskBadge(title: badge, tone: .neutral)
                    }

                    Spacer(minLength: WayTaskDesign.Spacing.xs)

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(WayTaskDesign.Typography.captionStrong)
                            .foregroundStyle(WayTaskDesign.accent)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard()
    }
}

struct WayTaskCompactProductCard: View {
    let title: String
    var subtitle: String?
    var imageData: Data?
    var imageURL: URL?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                WayTaskProductThumbnail(
                    data: imageData,
                    url: imageURL,
                    size: 88,
                    cornerRadius: WayTaskDesign.Radius.md
                )
                .frame(maxWidth: .infinity)

                if let actionSystemImage, let action {
                    Button {
                        WayTaskHaptics.selection()
                        action()
                    } label: {
                        Image(systemName: actionSystemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(WayTaskDesign.accent)
                            .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.xs, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Product action")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WayTaskDesign.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 120)
        .padding(WayTaskDesign.Spacing.sm)
        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.lg)
    }
}

struct WayTaskStoreCard: View {
    let title: String
    var subtitle: String?
    var distanceText: String?
    var coverage: Double?
    var confidenceText: String?
    var isBestMatch = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.md) {
            HStack(alignment: .top, spacing: WayTaskDesign.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: WayTaskDesign.Radius.md, style: .continuous)
                        .fill(isBestMatch ? WayTaskDesign.accentGradient : LinearGradient(colors: [WayTaskDesign.surfaceElevated, WayTaskDesign.surfaceElevated], startPoint: .top, endPoint: .bottom))

                    Image(systemName: "storefront.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isBestMatch ? .white : WayTaskDesign.accent)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                    HStack(spacing: WayTaskDesign.Spacing.xs) {
                        Text(title)
                            .font(WayTaskDesign.Typography.headline)
                            .foregroundStyle(WayTaskDesign.primaryText)
                            .lineLimit(1)

                        if isBestMatch {
                            WayTaskBadge(title: "Best", systemImage: "sparkle", tone: .accent)
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(WayTaskDesign.Typography.caption)
                            .foregroundStyle(WayTaskDesign.secondaryText)
                            .lineLimit(2)
                    }

                    HStack(spacing: WayTaskDesign.Spacing.xs) {
                        if let distanceText {
                            Label(distanceText, systemImage: "location")
                        }

                        if let confidenceText {
                            Label(confidenceText, systemImage: "checkmark.seal")
                        }
                    }
                    .font(WayTaskDesign.Typography.caption.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.secondaryText)
                }

                Spacer(minLength: WayTaskDesign.Spacing.xs)

                if let coverage {
                    WayTaskCoverageRing(progress: coverage, size: 54, lineWidth: 6)
                }
            }

            if let actionTitle, let action {
                WayTaskPrimaryButton(actionTitle, systemImage: "arrow.right", action: action)
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard(highlighted: isBestMatch)
    }
}

struct WayTaskShoppingListCard: View {
    let title: String
    let itemCount: Int
    var completedCount: Int = 0
    var subtitle: String?
    var isActive = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            WayTaskHaptics.selection()
            action?()
        } label: {
            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isActive ? .white : WayTaskDesign.accent)
                        .frame(width: 40, height: 40)
                        .background(isActive ? WayTaskDesign.accent : WayTaskDesign.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sm, style: .continuous))

                    Spacer()

                    WayTaskBadge(title: "\(itemCount)", tone: isActive ? .accent : .neutral)
                }

                VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                    Text(title)
                        .font(WayTaskDesign.Typography.headline)
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(1)

                    Text(subtitle ?? "\(completedCount) of \(max(itemCount, 1)) complete")
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(2)
                }

                WayTaskProgressRing(progress: itemCount == 0 ? 0 : Double(completedCount) / Double(itemCount), size: 36, lineWidth: 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(WayTaskDesign.Spacing.md)
            .wayTaskGlassCard(highlighted: isActive)
        }
        .buttonStyle(.plain)
    }
}

struct WayTaskMetricCard: View {
    let value: String
    let title: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
            }

            Text(value)
                .font(WayTaskDesign.Typography.metric)
                .foregroundStyle(WayTaskDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(WayTaskDesign.Typography.caption)
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard()
    }
}

struct WayTaskCoverageRing: View {
    let progress: Double
    var size: CGFloat = 68
    var lineWidth: CGFloat = 7
    var showsLabel = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(WayTaskDesign.surfaceElevated, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(WayTaskDesign.accentGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(WayTaskDesign.Animation.spring, value: clampedProgress)

            if showsLabel {
                Text("\(Int((clampedProgress * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Coverage \(Int((clampedProgress * 100).rounded())) percent")
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

struct WayTaskProgressRing: View {
    let progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(WayTaskDesign.surfaceElevated, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(WayTaskDesign.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(WayTaskDesign.Animation.standard, value: clampedProgress)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Progress \(Int((clampedProgress * 100).rounded())) percent")
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

struct WayTaskEmptyState: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: WayTaskDesign.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 72, height: 72)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.lg, style: .continuous))

            VStack(spacing: WayTaskDesign.Spacing.xs) {
                Text(title)
                    .font(WayTaskDesign.Typography.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(WayTaskDesign.Typography.subheadline)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                WayTaskSecondaryButton(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(WayTaskDesign.Spacing.xl)
        .wayTaskGlassCard()
    }
}

struct WayTaskLoadingSkeleton: View {
    var lineCount = 3
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.sm) {
            ForEach(0..<lineCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: WayTaskDesign.Radius.xs, style: .continuous)
                    .fill(WayTaskDesign.surfaceElevated)
                    .frame(height: index == 0 ? 22 : 14)
                    .frame(maxWidth: index == lineCount - 1 ? 180 : .infinity, alignment: .leading)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.10), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: isAnimating ? 220 : -220)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.xs, style: .continuous))
            }
        }
        .padding(WayTaskDesign.Spacing.md)
        .wayTaskGlassCard()
        .onAppear {
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
        .accessibilityLabel("Loading")
    }
}

struct WayTaskOfflineState: View {
    var retry: (() -> Void)?

    var body: some View {
        WayTaskEmptyState(
            title: "Connection unavailable",
            message: "WayTask will keep local features available. Online lookup will resume when the connection returns.",
            systemImage: "wifi.slash",
            actionTitle: retry == nil ? nil : "Try Again",
            action: retry
        )
    }
}

struct WayTaskBottomSheet<Content: View>: View {
    let title: String?
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(WayTaskDesign.tertiaryText)
                .frame(width: 42, height: 5)
                .padding(.top, WayTaskDesign.Spacing.sm)
                .padding(.bottom, WayTaskDesign.Spacing.md)

            if title != nil || onClose != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(WayTaskDesign.Typography.headline)
                            .foregroundStyle(WayTaskDesign.primaryText)
                    }

                    Spacer()

                    if let onClose {
                        WayTaskIconButton(systemName: "xmark", action: onClose)
                    }
                }
                .padding(.horizontal, WayTaskDesign.Spacing.md)
                .padding(.bottom, WayTaskDesign.Spacing.sm)
            }

            content()
                .padding(.horizontal, WayTaskDesign.Spacing.md)
                .padding(.bottom, WayTaskDesign.Spacing.md)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WayTaskDesign.Radius.sheet, style: .continuous)
                .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: WayTaskDesign.Elevation.cardShadow, radius: WayTaskDesign.Elevation.cardRadius, y: WayTaskDesign.Elevation.cardY)
    }
}

struct WayTaskFloatingScanButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            WayTaskHaptics.impact(.medium)
            action()
        } label: {
            Image(systemName: "barcode.viewfinder")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(WayTaskDesign.accentGradient)
                .clipShape(Circle())
                .shadow(color: WayTaskDesign.Elevation.buttonShadow, radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan product")
    }
}

struct WayTaskNavigationBar: View {
    let title: String
    var subtitle: String?
    var leadingSystemName: String?
    var trailingSystemName: String?
    var leadingAction: (() -> Void)?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: WayTaskDesign.Spacing.sm) {
            if let leadingSystemName {
                WayTaskIconButton(systemName: leadingSystemName, action: leadingAction ?? {})
            }

            VStack(alignment: .leading, spacing: WayTaskDesign.Spacing.xxs) {
                Text(title)
                    .font(WayTaskDesign.Typography.title)
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(WayTaskDesign.Typography.caption)
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WayTaskDesign.Spacing.sm)

            if let trailingSystemName {
                WayTaskIconButton(systemName: trailingSystemName, action: trailingAction ?? {})
            }
        }
        .padding(.horizontal, WayTaskDesign.Spacing.lg)
        .padding(.vertical, WayTaskDesign.Spacing.sm)
        .background(.ultraThinMaterial)
    }
}

struct WayTaskPrimaryPillButtonStyle: ButtonStyle {
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = WayTaskDesign.Radius.sm
    var shadow: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, WayTaskDesign.Spacing.md)
            .frame(maxWidth: height == nil ? nil : .infinity, alignment: .center)
            .frame(minHeight: height ?? 44, alignment: .center)
            .background {
                WayTaskDesign.accentGradient
                    .opacity(configuration.isPressed ? 0.72 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadow ? WayTaskDesign.Elevation.buttonShadow : .clear, radius: shadow ? WayTaskDesign.Elevation.buttonRadius : 0, y: shadow ? WayTaskDesign.Elevation.buttonY : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(WayTaskDesign.Animation.quick, value: configuration.isPressed)
    }
}

struct WayTaskSecondaryPillButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 36
    var cornerRadius: CGFloat = WayTaskDesign.Radius.sm

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(WayTaskDesign.secondaryText)
            .padding(.horizontal, WayTaskDesign.Spacing.sm)
            .frame(minHeight: minHeight)
            .background(WayTaskDesign.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(WayTaskDesign.Animation.quick, value: configuration.isPressed)
    }
}

struct WayTaskModeTile: View {
    let title: String
    let systemName: String

    var body: some View {
        VStack(spacing: WayTaskDesign.Spacing.xs) {
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
        .wayTaskGlassCard(cornerRadius: WayTaskDesign.Radius.md)
    }
}

private struct WayTaskGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let highlighted: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(highlighted ? WayTaskDesign.accent.opacity(0.10) : WayTaskDesign.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(highlighted ? WayTaskDesign.accent.opacity(0.34) : WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: highlighted ? WayTaskDesign.accent.opacity(0.16) : .clear, radius: highlighted ? 18 : 0, y: highlighted ? 8 : 0)
    }
}

extension View {
    func wayTaskCard(cornerRadius: CGFloat = WayTaskDesign.Radius.lg) -> some View {
        self
            .background(WayTaskDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
    }

    func wayTaskGlassCard(cornerRadius: CGFloat = WayTaskDesign.Radius.lg, highlighted: Bool = false) -> some View {
        modifier(WayTaskGlassCardModifier(cornerRadius: cornerRadius, highlighted: highlighted))
    }
}
