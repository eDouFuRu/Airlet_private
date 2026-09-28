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
    var transparency: Double = FloatingGlassTransparency.original

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        let shape = IslandSurfaceShape(topRadius: topRadius, bottomRadius: bottomRadius,
                                       contour: isFloating ? .floating : .notch)
        if isFloating {
            let levels = FloatingGlassTransparency(reduceTransparency ? 0 : transparency)
            let backing = Color(white: colorScheme == .dark ? 0.2 : 0.97)
            if #available(macOS 26.0, *) {
                // Keep the native glass in its own layer so tuning it never fades
                // lyrics, controls, or the rest of the island's content.
                content.background {
                    backing.opacity(levels.backingOpacity)
                        .clipShape(shape)
                        .overlay {
                            Color.clear.glassEffect(.clear, in: shape)
                                .opacity(levels.glassOpacity)
                        }
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(.white.opacity(levels.rimOpacity), lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
            } else {
                content.background {
                    backing.opacity(levels.backingOpacity)
                        .clipShape(shape)
                        .overlay {
                            Color.clear.background(.ultraThinMaterial, in: shape)
                                .opacity(levels.glassOpacity)
                        }
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
            }
        } else {
            content.background(.black).clipShape(shape)
                .overlay(alignment: .top) {
                    Rectangle().fill(.black).frame(height: 1).padding(.horizontal, topRadius)
                }
        }
    }
}
