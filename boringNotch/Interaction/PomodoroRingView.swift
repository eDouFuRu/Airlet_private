import SwiftUI

enum PomodoroTheme {
    /// Brand tomato red (#E5533C), shared by the ring, buttons and closed-wing icon.
    static let accent = Color(red: 0.898, green: 0.325, blue: 0.235)
    static let accentRGB = PomodoroRGB(hex: 0xE5533C)
}

extension PomodoroRGB {
    var swiftUIColor: Color { Color(red: r, green: g, blue: b) }
}

/// A single Activity-style ring. Only this Canvas updates at frame cadence; labels and
/// the surrounding island retain their own layout/animation transactions.
struct PomodoroRingView<Center: View>: View {
    let presentation: PomodoroRingPresentation
    let baseRGB: PomodoroRGB
    var countdownFills = true
    var isVisible = true
    var diameter: CGFloat = 128
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool {
        isVisible && !reduceMotion && (presentation.phase == .running || presentation.completedAt != nil)
    }

    var body: some View {
        ZStack {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    drawing(at: timeline.date)
                }
            } else {
                // Model publication supplies the existing second cadence in reduced motion.
                drawing(at: Date())
            }
            center()
        }
        .frame(width: diameter, height: diameter)
    }

    private func drawing(at date: Date) -> some View {
        PomodoroRingCanvas(progress: presentation.progress(at: date, countdownFills: countdownFills), baseRGB: baseRGB,
                           progressOpacity: presentation.opacity(at: date, reduceMotion: reduceMotion),
                           lineWidth: lineWidth)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Also used by the isolated renderer, so visual evidence exercises production drawing.
struct PomodoroRingCanvas: View {
    let progress: Double?
    let baseRGB: PomodoroRGB
    var progressOpacity: Double = 1
    var lineWidth: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let geometry = PomodoroRingGeometry(progress: progress ?? 0,
                                               diameter: diameter, lineWidth: lineWidth)
            let circle = Path(ellipseIn: CGRect(x: center.x - geometry.radius,
                                                y: center.y - geometry.radius,
                                                width: geometry.radius * 2, height: geometry.radius * 2))
            context.stroke(circle, with: .color(baseRGB.swiftUIColor.opacity(0.20)), lineWidth: lineWidth)
            guard let progress, progress > 0, progressOpacity > 0 else { return }
            context.opacity = progressOpacity
            let tail = Color(red: baseRGB.r * 0.68, green: baseRGB.g * 0.68, blue: baseRGB.b * 0.68)
            let head = Color(red: baseRGB.r + (1 - baseRGB.r) * 0.24,
                             green: baseRGB.g + (1 - baseRGB.g) * 0.24,
                             blue: baseRGB.b + (1 - baseRGB.b) * 0.24)
            let start = geometry.point(at: geometry.startAngle, center: center)
            let end = geometry.point(at: geometry.endAngle, center: center)
            func cap(_ point: CGPoint) -> Path {
                Path(ellipseIn: CGRect(x: point.x - lineWidth / 2, y: point.y - lineWidth / 2,
                                       width: lineWidth, height: lineWidth))
            }
            if geometry.sweep > 0 {
                var arc = Path()
                arc.addArc(center: center, radius: geometry.radius,
                           startAngle: .radians(geometry.startAngle), endAngle: .radians(geometry.endAngle),
                           clockwise: false)
                let portion = max(0.000001, geometry.sweep / (2 * .pi))
                let gradient = Gradient(stops: [.init(color: tail, location: 0),
                                                 .init(color: head, location: portion),
                                                 .init(color: head, location: 1)])
                context.stroke(arc, with: .conicGradient(gradient, center: center,
                                                        angle: .radians(geometry.startAngle)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                if geometry.sweep < 2 * .pi { context.fill(cap(start), with: .color(tail)) }
            }
            // Clip the cap's forward shadow to the ring band: depth without a halo.
            if geometry.sweep * geometry.radius > lineWidth {
                context.drawLayer { layer in
                    layer.clip(to: circle.strokedPath(StrokeStyle(lineWidth: lineWidth)))
                    layer.addFilter(.shadow(color: .black.opacity(0.65), radius: 2,
                                            x: -sin(geometry.endAngle) * 3,
                                            y: cos(geometry.endAngle) * 3))
                    layer.fill(cap(end), with: .color(head))
                }
            }
            context.fill(cap(end), with: .color(head))
        }
    }
}
