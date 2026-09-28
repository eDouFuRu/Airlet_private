import SwiftUI

/// Drawing and AppKit hit testing use the very same outline, including during a morph.
struct IslandSurfaceShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var contour: IslandContour

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let path = Path(NotchHitRegion.outline(size: rect.size, topRadius: topRadius,
                                             bottomRadius: bottomRadius, contour: contour))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct IslandSurface: ViewModifier {
    let isFloating: Bool
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = IslandSurfaceShape(topRadius: topRadius, bottomRadius: bottomRadius,
                                       contour: isFloating ? .floating : .notch)
        if isFloating {
            if #available(macOS 26.0, *) {
                // A menu-bar overlay has no app-owned backdrop. The regular variant
                // becomes a nearly opaque white sheet on the desktop and a dark
                // sheet above a full-screen Space. Clear glass keeps the windows
                // behind this transparent panel visible in either context.
                content.clipShape(shape)
                    .glassEffect(.clear, in: shape)
                    .overlay {
                        shape.stroke(.white.opacity(0.4), lineWidth: 0.7)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                    }
            } else {
                content.clipShape(shape).background(.ultraThinMaterial, in: shape)
            }
        } else {
            content.background(.black).clipShape(shape)
                .overlay(alignment: .top) {
                    Rectangle().fill(.black).frame(height: 1).padding(.horizontal, topRadius)
                }
        }
    }
}
