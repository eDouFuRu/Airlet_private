import CoreGraphics
import Foundation

enum IslandContour: Equatable, Sendable {
    case notch
    case floating
}

/// Screen-local geometry. A camera exclusion is independent of the width of the shell.
struct IslandDisplayProfile: Equatable, Sendable {
    let isFloating: Bool
    let topInset: CGFloat
    let compactHeight: CGFloat
    let compactBaseWidth: CGFloat
    let maximumWidth: CGFloat
    let cameraExclusionWidth: CGFloat
    let expandedHeaderHeight: CGFloat

    var contour: IslandContour { isFloating ? .floating : .notch }
    var compactSize: CGSize { CGSize(width: compactBaseWidth, height: compactHeight) }

    init(screenWidth: CGFloat, safeTop: CGFloat, cameraWidth: CGFloat,
         nativeClosedHeight: CGFloat, menuBarHeight: CGFloat) {
        isFloating = !safeTop.isFinite || safeTop <= 0
        maximumWidth = min(640, max(1, screenWidth.isFinite ? screenWidth - 48 : 640))
        topInset = isFloating ? 3 : 0
        if isFloating {
            let menuHeight = menuBarHeight.isFinite && menuBarHeight > 6 ? menuBarHeight : 24
            compactHeight = max(1, menuHeight - 6)
            compactBaseWidth = min(120, maximumWidth)
            cameraExclusionWidth = 0
            expandedHeaderHeight = 36
        } else {
            compactHeight = min(60, max(24, nativeClosedHeight.isFinite ? nativeClosedHeight : safeTop))
            compactBaseWidth = max(1, cameraWidth.isFinite ? cameraWidth : 120)
            cameraExclusionWidth = compactBaseWidth
            expandedHeaderHeight = max(24, compactHeight, safeTop)
        }
    }

    func compactFrame(in screenFrame: CGRect) -> CGRect {
        NotchHitRegion.presentationFrame(carrierFrame: screenFrame, size: compactSize, topInset: topInset)
    }

    func floatingTrigger(in screenFrame: CGRect, visibleFrame: CGRect, cornerRadius: CGFloat,
                         expanded: Bool, surfaceVisible: Bool) -> (frame: CGRect, cornerRadius: CGFloat) {
        // Closing changes the model immediately while the large presentation still
        // occupies the desktop. That outgoing panel must not become a new open target.
        let isCompact = visibleFrame.height <= compactHeight + 0.5
        if surfaceVisible && !expanded && isCompact { return (visibleFrame, cornerRadius) }
        return (compactFrame(in: screenFrame), compactHeight / 2)
    }
}

/// A hidden menu bar reports zero reservation; remember measurements independently
/// for every display so changing the primary monitor cannot alter another island.
struct IslandMenuBarHeightCache {
    private var heights: [String: CGFloat] = [:]

    mutating func height(for screenID: String, measured: CGFloat, systemHeight: CGFloat) -> CGFloat {
        if measured.isFinite, measured > 6, measured <= 80 {
            heights[screenID] = measured
            return measured
        }
        return heights[screenID]
            ?? (systemHeight.isFinite && systemHeight > 6 ? systemHeight : 24)
    }
}

/// Auto-hide changes only drawing and input routing, never application availability.
enum IslandSurfaceVisibility {
    static func shouldShow(isFloating: Bool, autoHide: Bool, expanded: Bool,
                           pointerInside: Bool, transient: Bool, available: Bool) -> Bool {
        available && (!isFloating || !autoHide || expanded || pointerInside || transient)
    }
}
