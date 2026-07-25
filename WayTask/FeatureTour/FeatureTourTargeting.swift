import CoreGraphics
import Foundation

struct FeatureTourTargetFramePolicy: Equatable {
    let minimumSize: CGSize
    let maximumSize: CGSize
    let maximumViewportWidthFraction: CGFloat
    let maximumViewportHeightFraction: CGFloat
    let aspectRatioRange: ClosedRange<CGFloat>?
}

extension FeatureTourTargetID {
    var framePolicy: FeatureTourTargetFramePolicy {
        switch self {
        case .productsBottomAddButton:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 64, height: 36),
                maximumSize: CGSize(width: 220, height: 80),
                maximumViewportWidthFraction: 0.60,
                maximumViewportHeightFraction: 0.15,
                aspectRatioRange: nil
            )
        case .addProductNameField:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 140, height: 40),
                maximumSize: CGSize(width: 620, height: 100),
                maximumViewportWidthFraction: 0.96,
                maximumViewportHeightFraction: 0.18,
                aspectRatioRange: nil
            )
        case .cameraShutterButton:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 56, height: 56),
                maximumSize: CGSize(width: 90, height: 90),
                maximumViewportWidthFraction: 0.25,
                maximumViewportHeightFraction: 0.14,
                aspectRatioRange: 0.84...1.16
            )
        case .mapFollowLocationButton:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 40, height: 40),
                maximumSize: CGSize(width: 80, height: 80),
                maximumViewportWidthFraction: 0.22,
                maximumViewportHeightFraction: 0.13,
                aspectRatioRange: 0.84...1.16
            )
        case .mapNavigateButton:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 80, height: 36),
                maximumSize: CGSize(width: 280, height: 80),
                maximumViewportWidthFraction: 0.72,
                maximumViewportHeightFraction: 0.15,
                aspectRatioRange: nil
            )
        case .shoppingRecommendedStoreCard:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 180, height: 96),
                maximumSize: CGSize(width: 760, height: 620),
                maximumViewportWidthFraction: 0.98,
                maximumViewportHeightFraction: 0.68,
                aspectRatioRange: nil
            )
        case .settingsFeatureTourRow:
            return FeatureTourTargetFramePolicy(
                minimumSize: CGSize(width: 140, height: 36),
                maximumSize: CGSize(width: 760, height: 100),
                maximumViewportWidthFraction: 0.98,
                maximumViewportHeightFraction: 0.18,
                aspectRatioRange: nil
            )
        }
    }

    var highlightPadding: CGFloat {
        switch self {
        case .cameraShutterButton, .mapFollowLocationButton:
            return 4
        case .productsBottomAddButton,
             .addProductNameField,
             .mapNavigateButton,
             .shoppingRecommendedStoreCard,
             .settingsFeatureTourRow:
            return 3
        }
    }

    func highlightCornerRadius(for frame: CGRect) -> CGFloat {
        switch self {
        case .cameraShutterButton, .mapFollowLocationButton:
            return min(frame.width, frame.height) / 2
        case .shoppingRecommendedStoreCard:
            return 22
        case .productsBottomAddButton,
             .addProductNameField,
             .mapNavigateButton,
             .settingsFeatureTourRow:
            return 14
        }
    }
}

enum FeatureTourTargetFrameRejection: Equatable {
    case missing
    case staleTarget
    case nonFinite
    case zeroSized
    case tooSmall
    case tooLarge
    case implausibleShape
    case outsideVisibleBounds
}

struct FeatureTourTargetFrameValidation: Equatable {
    let frame: CGRect?
    let rejection: FeatureTourTargetFrameRejection?

    var isAccepted: Bool {
        frame != nil && rejection == nil
    }
}

enum FeatureTourTargetFrameValidator {
    static func validate(
        frame: CGRect?,
        observedTarget: FeatureTourTargetID?,
        expectedTarget: FeatureTourTargetID,
        overlayBounds: CGRect,
        safeAreaInsets: FeatureTourSafeAreaInsets
    ) -> FeatureTourTargetFrameValidation {
        guard let frame else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .missing
            )
        }
        guard observedTarget == expectedTarget else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .staleTarget
            )
        }

        let standardizedFrame = frame.standardized
        let values = [
            standardizedFrame.minX,
            standardizedFrame.minY,
            standardizedFrame.width,
            standardizedFrame.height
        ]
        guard values.allSatisfy(\.isFinite) else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .nonFinite
            )
        }
        guard standardizedFrame.width > 0,
              standardizedFrame.height > 0 else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .zeroSized
            )
        }

        let policy = expectedTarget.framePolicy
        guard standardizedFrame.width >= policy.minimumSize.width,
              standardizedFrame.height >= policy.minimumSize.height else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .tooSmall
            )
        }

        let maximumWidth = min(
            policy.maximumSize.width,
            overlayBounds.width * policy.maximumViewportWidthFraction
        )
        let maximumHeight = min(
            policy.maximumSize.height,
            overlayBounds.height * policy.maximumViewportHeightFraction
        )
        guard standardizedFrame.width <= maximumWidth,
              standardizedFrame.height <= maximumHeight else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .tooLarge
            )
        }

        if let aspectRatioRange = policy.aspectRatioRange {
            let aspectRatio =
                standardizedFrame.width / standardizedFrame.height
            guard aspectRatioRange.contains(aspectRatio) else {
                return FeatureTourTargetFrameValidation(
                    frame: nil,
                    rejection: .implausibleShape
                )
            }
        }

        let visibleBounds = FeatureTourCoordinateConverter.visibleBounds(
            in: overlayBounds,
            safeAreaInsets: safeAreaInsets
        )
        let targetGuardBounds = visibleBounds.insetBy(dx: 4, dy: 4)
        guard targetGuardBounds.contains(standardizedFrame) else {
            return FeatureTourTargetFrameValidation(
                frame: nil,
                rejection: .outsideVisibleBounds
            )
        }

        return FeatureTourTargetFrameValidation(
            frame: standardizedFrame,
            rejection: nil
        )
    }
}

enum FeatureTourCoordinateConverter {
    static func globalFrame(
        fromOverlayFrame frame: CGRect,
        overlayGlobalBounds: CGRect
    ) -> CGRect {
        frame.offsetBy(
            dx: overlayGlobalBounds.minX,
            dy: overlayGlobalBounds.minY
        )
    }

    static func overlayFrame(
        fromGlobalFrame frame: CGRect,
        overlayGlobalBounds: CGRect
    ) -> CGRect {
        frame.offsetBy(
            dx: -overlayGlobalBounds.minX,
            dy: -overlayGlobalBounds.minY
        )
    }

    static func visibleBounds(
        in overlayBounds: CGRect,
        safeAreaInsets: FeatureTourSafeAreaInsets
    ) -> CGRect {
        CGRect(
            x: overlayBounds.minX + safeAreaInsets.leading,
            y: overlayBounds.minY + safeAreaInsets.top,
            width: max(
                overlayBounds.width -
                    safeAreaInsets.leading -
                    safeAreaInsets.trailing,
                1
            ),
            height: max(
                overlayBounds.height -
                    safeAreaInsets.top -
                    safeAreaInsets.bottom,
                1
            )
        )
    }
}

struct FeatureTourTargetSnapshotKey: Hashable {
    let stepID: FeatureTourStepID
    let targetID: FeatureTourTargetID
    let x: Int?
    let y: Int?
    let width: Int?
    let height: Int?

    init(
        stepID: FeatureTourStepID,
        targetID: FeatureTourTargetID,
        frame: CGRect?
    ) {
        self.stepID = stepID
        self.targetID = targetID
        x = frame.map { Int(($0.minX * 2).rounded()) }
        y = frame.map { Int(($0.minY * 2).rounded()) }
        width = frame.map { Int(($0.width * 2).rounded()) }
        height = frame.map { Int(($0.height * 2).rounded()) }
    }
}
