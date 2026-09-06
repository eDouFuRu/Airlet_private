// Custom changes for 工位充电岛. Geometry is independent of AppKit and SwiftUI.
import Foundation
import CoreGraphics

struct NotchHitRegion: Equatable {
    var triggerRect: CGRect
    var visibleFrame: CGRect
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// AppKit screen coordinates, including screens whose origin is not zero.
    /// The physical camera exclusion area is exactly between the two auxiliary areas.
    static func triggerRect(
        screenFrame: CGRect,
        safeTop: CGFloat,
        leftAuxiliaryWidth: CGFloat?,
        rightAuxiliaryWidth: CGFloat?,
        fallbackSize: CGSize = CGSize(width: 120, height: 29)
    ) -> CGRect {
        if safeTop > 0,
           let left = leftAuxiliaryWidth, let right = rightAuxiliaryWidth,
           left >= 0, right >= 0, left + right < screenFrame.width {
            return CGRect(
                x: screenFrame.minX + left,
                y: screenFrame.maxY - safeTop,
                width: screenFrame.width - left - right,
                height: safeTop
            )
        }
        let width = min(max(1, fallbackSize.width), screenFrame.width)
        let height = min(max(1, fallbackSize.height), screenFrame.height)
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height,
                      width: width, height: height)
    }

    func containsTrigger(_ point: CGPoint) -> Bool {
        Self.containsIncludingEdges(triggerRect, point)
    }

    /// Same quadratic contour as the upstream NotchShape, with AppKit's Y axis flipped.
    /// The top outer corners are concave and are not rectangular hit targets.
    func containsVisible(_ point: CGPoint) -> Bool {
        guard visibleFrame.width > 0, visibleFrame.height > 0,
              Self.containsIncludingEdges(visibleFrame, point) else { return false }
        let local = CGPoint(x: point.x - visibleFrame.minX, y: visibleFrame.maxY - point.y)
        return Self.outline(size: visibleFrame.size, topRadius: topRadius,
                            bottomRadius: bottomRadius).contains(local)
    }

    func containsExpandedHover(_ point: CGPoint) -> Bool {
        containsTrigger(point) || containsVisible(point)
    }

    static func outline(size: CGSize, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let width = max(0, size.width), height = max(0, size.height)
        let top = min(max(0, topRadius), min(width / 2, height))
        let bottom = min(max(0, bottomRadius), min(max(0, width / 2 - top), max(0, height - top)))
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: top, y: top), control: CGPoint(x: top, y: 0))
        path.addLine(to: CGPoint(x: top, y: height - bottom))
        path.addQuadCurve(to: CGPoint(x: top + bottom, y: height),
                          control: CGPoint(x: top, y: height))
        path.addLine(to: CGPoint(x: width - top - bottom, y: height))
        path.addQuadCurve(to: CGPoint(x: width - top, y: height - bottom),
                          control: CGPoint(x: width - top, y: height))
        path.addLine(to: CGPoint(x: width - top, y: top))
        path.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: width - top, y: 0))
        path.closeSubpath()
        return path
    }

    private static func containsIncludingEdges(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
