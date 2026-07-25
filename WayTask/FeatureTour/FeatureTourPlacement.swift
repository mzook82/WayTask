import CoreGraphics
import Foundation

struct FeatureTourSafeAreaInsets: Equatable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    static let zero = FeatureTourSafeAreaInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
}

enum FeatureTourTooltipPlacementKind: Equatable {
    case above
    case below
    case centered
}

struct FeatureTourTooltipPlacement: Equatable {
    let kind: FeatureTourTooltipPlacementKind
    let frame: CGRect
    let safeBounds: CGRect
}

enum FeatureTourPlacementSolver {
    static func placement(
        in containerBounds: CGRect,
        safeAreaInsets: FeatureTourSafeAreaInsets,
        targetFrame: CGRect?,
        tooltipSize: CGSize,
        margin: CGFloat = 16,
        gap: CGFloat = 14
    ) -> FeatureTourTooltipPlacement {
        let safeBounds = insetBounds(
            containerBounds,
            safeAreaInsets: safeAreaInsets,
            margin: margin
        )
        let fittedSize = CGSize(
            width: min(max(tooltipSize.width, 1), safeBounds.width),
            height: min(max(tooltipSize.height, 1), safeBounds.height)
        )

        guard let targetFrame else {
            return FeatureTourTooltipPlacement(
                kind: .centered,
                frame: centeredFrame(
                    size: fittedSize,
                    in: safeBounds
                ),
                safeBounds: safeBounds
            )
        }

        let spaceAbove = max(targetFrame.minY - gap - safeBounds.minY, 0)
        let spaceBelow = max(safeBounds.maxY - targetFrame.maxY - gap, 0)
        let fitsAbove = fittedSize.height <= spaceAbove
        let fitsBelow = fittedSize.height <= spaceBelow
        let horizontalOrigin = clamped(
            targetFrame.midX - fittedSize.width / 2,
            minimum: safeBounds.minX,
            maximum: safeBounds.maxX - fittedSize.width
        )

        if fitsAbove, !fitsBelow || spaceAbove >= spaceBelow {
            return FeatureTourTooltipPlacement(
                kind: .above,
                frame: CGRect(
                    x: horizontalOrigin,
                    y: targetFrame.minY - gap - fittedSize.height,
                    width: fittedSize.width,
                    height: fittedSize.height
                ),
                safeBounds: safeBounds
            )
        }

        if fitsBelow {
            return FeatureTourTooltipPlacement(
                kind: .below,
                frame: CGRect(
                    x: horizontalOrigin,
                    y: targetFrame.maxY + gap,
                    width: fittedSize.width,
                    height: fittedSize.height
                ),
                safeBounds: safeBounds
            )
        }

        let usesAbove = spaceAbove >= spaceBelow
        let availableHeight = usesAbove ? spaceAbove : spaceBelow
        let nonoverlappingSize = CGSize(
            width: fittedSize.width,
            height: min(fittedSize.height, max(availableHeight, 1))
        )

        if usesAbove {
            return FeatureTourTooltipPlacement(
                kind: .above,
                frame: CGRect(
                    x: horizontalOrigin,
                    y: targetFrame.minY -
                        gap -
                        nonoverlappingSize.height,
                    width: nonoverlappingSize.width,
                    height: nonoverlappingSize.height
                ),
                safeBounds: safeBounds
            )
        }

        return FeatureTourTooltipPlacement(
            kind: .below,
            frame: CGRect(
                x: horizontalOrigin,
                y: targetFrame.maxY + gap,
                width: nonoverlappingSize.width,
                height: nonoverlappingSize.height
            ),
            safeBounds: safeBounds
        )
    }

    private static func insetBounds(
        _ bounds: CGRect,
        safeAreaInsets: FeatureTourSafeAreaInsets,
        margin: CGFloat
    ) -> CGRect {
        let minimumX = bounds.minX + safeAreaInsets.leading + margin
        let minimumY = bounds.minY + safeAreaInsets.top + margin
        let maximumX = bounds.maxX - safeAreaInsets.trailing - margin
        let maximumY = bounds.maxY - safeAreaInsets.bottom - margin

        return CGRect(
            x: minimumX,
            y: minimumY,
            width: max(maximumX - minimumX, 1),
            height: max(maximumY - minimumY, 1)
        )
    }

    private static func centeredFrame(
        size: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func clamped(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }
}
