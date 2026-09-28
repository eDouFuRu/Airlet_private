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
    var edgeLight: GlassEdgeLightProfile? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        let shape = IslandSurfaceShape(topRadius: topRadius, bottomRadius: bottomRadius,
                                       contour: isFloating ? .floating : .notch)
        if isFloating {
            let levels = FloatingGlassTransparency(reduceTransparency ? 0 : transparency)
            let backing = Color(white: colorScheme == .dark ? 0.2 : 0.97)
            if #available(macOS 26.0, *) {
                content.background {
                    FloatingGlassLens(shape: shape, levels: levels, backing: backing,
                                      reduceTransparency: reduceTransparency)
                }
                .clipShape(shape)
                .overlay {
                    if !reduceTransparency {
                        FloatingGlassRim(shape: shape, profile: edgeLight ?? .neutral)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: edgeLight)
                    }
                }
            } else {
                content.background {
                    backing.opacity(levels.backingOpacity)
                        .clipShape(shape)
                        .overlay {
                            Color.clear.background(.ultraThinMaterial, in: shape)
                                .opacity(levels.legacyMaterialOpacity)
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

/// The system glass supplies the live backdrop. These optical layers add the
/// bright inner bevel and backdrop-responsive rim that a clear floating window
/// otherwise loses over a light or nearly uniform desktop. None is a hit area.
@available(macOS 26.0, *)
private struct FloatingGlassLens: View {
    let shape: IslandSurfaceShape
    let levels: FloatingGlassTransparency
    let backing: Color
    let reduceTransparency: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backing.opacity(reduceTransparency ? 1 : levels.backingOpacity)
                .clipShape(shape)

            if !reduceTransparency {
                Color.clear.glassEffect(.clear, in: shape)

                shape.fill(backing.opacity(levels.veilOpacity))
                    .clipShape(shape)

                // The wide, soft band reads as light gathered inside a thick
                // lens, while the sharp edge defines its physical boundary.
                shape.stroke(
                    LinearGradient(colors: [
                        .white.opacity(colorScheme == .dark ? 0.24 : 0.42),
                        .cyan.opacity(0.13),
                        .clear,
                        .blue.opacity(0.09),
                        .white.opacity(0.16)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 9
                )
                .blur(radius: 5)
                .clipShape(shape)

                shape.fill(
                    LinearGradient(colors: [
                        .white.opacity(colorScheme == .dark ? 0.09 : 0.17),
                        .clear,
                        .black.opacity(colorScheme == .dark ? 0.06 : 0.035)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(shape)

            }
        }
        .allowsHitTesting(false)
    }
}

/// This sits outside the surface clip so the light can spill into the
/// transparent carrier window. Its outline is still the hit region's outline.
@available(macOS 26.0, *)
private struct FloatingGlassRim: View {
    let shape: IslandSurfaceShape
    let profile: GlassEdgeLightProfile

    @Environment(\.colorScheme) private var colorScheme

    private func gradient(dark: Bool) -> AngularGradient {
        let levels = profile.levels
        let stops = (0...8).map { index -> Gradient.Stop in
            let level = levels[index % 8]
            // Dark surroundings should not carry a conspicuous white outline;
            // a local bright-to-dark transition can still produce a vivid glint.
            let opacity = dark ? max(0.06, (0.65 - level) * 0.65)
                               : max(0.05, (level - 0.25) * 1.4)
            return .init(color: dark ? .black.opacity(opacity) : .white.opacity(opacity),
                         location: Double(index) / 8)
        }
        return AngularGradient(stops: stops, center: .center,
                               startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    var body: some View {
        ZStack {
            shape.stroke(gradient(dark: true), lineWidth: 3)
                .blur(radius: 2)
            shape.stroke(gradient(dark: false), lineWidth: 1.7)
                .shadow(color: .white.opacity(colorScheme == .dark ? 0.24 : 0.38), radius: 3)
        }
        .allowsHitTesting(false)
    }
}
