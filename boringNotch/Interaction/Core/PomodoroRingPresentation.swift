import Foundation
import CoreGraphics

/// Read-only presentation anchors. Sampling never advances or settles the session machine.
struct PomodoroRingPresentation: Equatable {
    var sessionID: UUID?
    var phase: PomodoroPhase
    var mode: PomodoroMode?
    var plannedSeconds: Int
    var accumulatedSeconds: Double
    var lastResumedAt: Date?
    var completedAt: Date?

    init(state: PomodoroRunState, completedAt: Date? = nil) {
        sessionID = state.sessionID
        phase = state.phase
        mode = state.mode
        plannedSeconds = state.plannedSeconds
        accumulatedSeconds = state.accumulatedSeconds
        lastResumedAt = state.lastResumedAt
        self.completedAt = completedAt
    }

    func progress(at date: Date, countdownFills: Bool = true) -> Double? {
        guard phase != .idle else { return completedAt == nil ? nil : (countdownFills ? 1 : 0) }
        let live = phase == .running ? lastResumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0 : 0
        let elapsed = max(0, accumulatedSeconds + live)
        switch mode {
        case .countdown:
            guard plannedSeconds > 0 else { return nil }
            let fraction = min(1, elapsed / Double(plannedSeconds))
            return countdownFills ? fraction : 1 - fraction
        case .countup: return elapsed / 3600
        case nil: return nil
        }
    }

    func opacity(at date: Date, reduceMotion: Bool) -> Double {
        guard phase == .idle, let completedAt else { return 1 }
        let age = date.timeIntervalSince(completedAt)
        if reduceMotion { return age < 3 ? 1 : 0 }
        return min(1, max(0, 1 - (age - 3) / 0.2))
    }
}

/// One circular coordinate system for the track, sweep, gradient and end caps.
struct PomodoroRingGeometry {
    let radius: Double
    let startAngle: Double
    let endAngle: Double
    let sweep: Double

    init(progress: Double, diameter: Double = 128, lineWidth: Double = 14) {
        let progress = progress.isFinite ? max(0, progress) : 0
        radius = max(0, (diameter - lineWidth) / 2)
        endAngle = -.pi / 2 + progress * 2 * .pi
        sweep = min(1, progress) * 2 * .pi
        startAngle = endAngle - sweep
    }

    func point(at angle: Double, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
