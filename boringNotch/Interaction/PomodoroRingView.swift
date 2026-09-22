import SwiftUI

enum PomodoroTheme {
    /// Brand tomato red (#E5533C), shared by the ring, buttons and closed-wing icon.
    static let accent = Color(red: 0.898, green: 0.325, blue: 0.235)
    static let accentRGB = PomodoroRGB(hex: 0xE5533C)
}

extension PomodoroRGB {
    var swiftUIColor: Color { Color(red: r, green: g, blue: b) }
}

/// Apple-Health-style single progress ring: a dim track, a gradient progress arc whose
/// head is bright and tail deep, and a head cap whose shadow falls on the track beneath
/// it to sell the layered look.
///
/// The ring is presentation-only — every frame is derived from values the model already
/// settled and persisted.
struct PomodoroRingView<Center: View>: View {
    /// 0…1 progress, or `nil` for the idle track-only state.
    let fraction: Double?
    let baseRGB: PomodoroRGB
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center

    /// Draws at `diameter` so the head-cap offset can be computed exactly.
    var diameter: CGFloat = 128

    private var radius: CGFloat { (diameter - lineWidth) / 2 }

    private var trackColor: Color { baseRGB.swiftUIColor.opacity(0.22) }
    private var tailColor: Color { baseRGB.swiftUIColor.multiplyBrightness(0.62) }
    private var headColor: Color { baseRGB.swiftUIColor.multiplyBrightness(1.16) }

    /// Point on the ring where the progress arc ends (SwiftUI coordinates, y down).
    private var headOffset: CGSize {
        guard let fraction else { return .zero }
        let clamped = min(max(fraction, 0), 1)
        let radians = (-90.0 + 360.0 * clamped) * Double.pi / 180
        return CGSize(width: radius * CGFloat(cos(radians)), height: radius * CGFloat(sin(radians)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            if let fraction, fraction > 0.001 {
                let clamped = min(max(fraction, 0.0001), 1)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(colors: [tailColor, headColor],
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(-90 + 360 * clamped)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                Circle()
                    .fill(headColor)
                    .frame(width: lineWidth, height: lineWidth)
                    .offset(headOffset)
                    .shadow(color: .black.opacity(0.4), radius: 2.5, x: 0, y: 1.5)
            }

            center()
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 1), value: fraction)
    }
}

private extension Color {
    /// Scales toward white (factor > 1) or black (factor < 1) without leaving sRGB.
    func multiplyBrightness(_ factor: CGFloat) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        func scaled(_ component: CGFloat) -> CGFloat {
            let value = factor >= 1 ? component + (1 - component) * (factor - 1)
                                    : component * factor
            return min(max(value, 0), 1)
        }
        return Color(red: Double(scaled(r)), green: Double(scaled(g)), blue: Double(scaled(b)), opacity: Double(a))
    }
}
