import Foundation

/// Pomodoro domain types and the wall-clock-authoritative reducer.
///
/// Pure logic: no AppKit, SwiftUI or timer dependencies. Callers drive every event with
/// an explicit `now` and persist the resulting state *before* publishing it to the UI, so
/// a late tick can only delay what is displayed, never when a session settles.
public enum PomodoroSessionCore {
    /// Classic default so the picker lands on a usable pomodoro out of the box.
    public static let defaultDurationSeconds = 25 * 60
    /// Shortest configurable countdown; below this the start button stays disabled.
    public static let minimumCountdownSeconds = 60
    public static let maximumHour = 12
    public static let maximumMinute = 59

    // MARK: - Queries

    /// Total focused seconds, counting the live segment since `lastResumedAt`.
    public static func elapsed(_ state: PomodoroRunState, now: Date) -> Double {
        state.accumulatedSeconds + (state.lastResumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// Seconds left on a countdown, or `nil` for count-up sessions.
    public static func remainingSeconds(_ state: PomodoroRunState, now: Date) -> Double? {
        guard state.mode == .countdown, let planned = validPlanned(state) else { return nil }
        return max(0, Double(planned) - elapsed(state, now: now))
    }

    /// The wall-clock instant a running countdown settles at. Only meaningful while running.
    public static func deadline(_ state: PomodoroRunState) -> Date? {
        guard state.mode == .countdown, state.phase == .running, let resumedAt = state.lastResumedAt,
              let planned = validPlanned(state) else { return nil }
        return resumedAt.addingTimeInterval(Double(planned) - state.accumulatedSeconds)
    }

    /// `mm:ss`, promoted to `h:mm:ss` from one hour up.
    public static func clockText(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let (hours, remainder) = total.quotientAndRemainder(dividingBy: 3600)
        let (minutes, secs) = remainder.quotientAndRemainder(dividingBy: 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Configuration (idle only)

    public static func selectMode(_ mode: PomodoroMode, state: inout PomodoroRunState) -> Bool {
        guard state.phase == .idle else { return false }
        state.mode = mode
        return true
    }

    public static func setDuration(seconds: Int, state: inout PomodoroRunState) -> Bool {
        guard state.phase == .idle, seconds >= 0,
              seconds <= maximumHour * 3600 + maximumMinute * 60 else { return false }
        state.plannedSeconds = seconds
        return true
    }

    public static func setTopic(_ topic: String, state: inout PomodoroRunState) -> Bool {
        guard state.phase == .idle else { return false }
        state.topic = topic
        return true
    }

    /// A start is legal with any selected mode; a countdown additionally needs its minimum.
    public static func canStart(_ state: PomodoroRunState) -> Bool {
        guard state.phase == .idle, state.mode != nil else { return false }
        if state.mode == .countdown { return (validPlanned(state) ?? 0) >= minimumCountdownSeconds }
        return true
    }

    // MARK: - Session events

    @discardableResult
    public static func start(_ state: inout PomodoroRunState, now: Date) -> Bool {
        guard canStart(state) else { return false }
        state.phase = .running
        state.sessionID = UUID()
        state.startedAt = now
        state.accumulatedSeconds = 0
        state.lastResumedAt = now
        return true
    }

    @discardableResult
    public static func pause(_ state: inout PomodoroRunState, now: Date) -> Bool {
        guard state.phase == .running, let resumedAt = state.lastResumedAt else { return false }
        state.accumulatedSeconds += now.timeIntervalSince(resumedAt)
        state.lastResumedAt = nil
        state.phase = .paused
        return true
    }

    @discardableResult
    public static func resume(_ state: inout PomodoroRunState, now: Date) -> Bool {
        guard state.phase == .paused, state.startedAt != nil else { return false }
        state.lastResumedAt = now
        state.phase = .running
        return true
    }

    /// Manual end: records what was actually focused, then resets to a prefilled idle state.
    public static func end(_ state: inout PomodoroRunState, now: Date) -> PomodoroSessionRecord? {
        guard state.phase == .running || state.phase == .paused, let id = state.sessionID,
              let startedAt = state.startedAt, let mode = state.mode else { return nil }
        let record = PomodoroSessionRecord(id: id, topic: normalizedTopic(state), mode: mode,
                                           plannedSeconds: state.mode == .countdown ? state.plannedSeconds : nil,
                                           startedAt: startedAt, endedAt: now,
                                           elapsedSeconds: elapsed(state, now: now))
        resetToIdlePrefilled(&state)
        return record
    }

    /// Countdown expiry. `endedAt` is the *deadline*, not the moment a late tick noticed,
    /// so settlement timing never depends on display timing.
    public static func naturalCompleteIfDue(_ state: inout PomodoroRunState, now: Date) -> PomodoroSessionRecord? {
        guard let deadline = deadline(state), now >= deadline,
              let id = state.sessionID, let startedAt = state.startedAt, let mode = state.mode,
              let planned = validPlanned(state) else { return nil }
        let record = PomodoroSessionRecord(id: id, topic: normalizedTopic(state), mode: mode,
                                           plannedSeconds: planned, startedAt: startedAt,
                                           endedAt: deadline, elapsedSeconds: Double(planned))
        resetToIdlePrefilled(&state)
        return record
    }

    /// Pre-start abandonment: nothing was focused, so nothing is recorded. Keeps the topic,
    /// clears the mode selection and restores the default duration.
    @discardableResult
    public static func cancel(_ state: inout PomodoroRunState) -> Bool {
        guard state.phase == .idle else { return false }
        state.mode = nil
        state.plannedSeconds = defaultDurationSeconds
        state.sessionID = nil
        state.startedAt = nil
        state.accumulatedSeconds = 0
        state.lastResumedAt = nil
        return true
    }

    // MARK: - Internals

    private static func validPlanned(_ state: PomodoroRunState) -> Int? {
        guard state.mode == .countdown, state.plannedSeconds > 0 else { return nil }
        return state.plannedSeconds
    }

    private static func normalizedTopic(_ state: PomodoroRunState) -> String? {
        let trimmed = state.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// End and natural completion both land here: config stays so the next session starts
    /// prefilled, while every session-specific field is cleared.
    private static func resetToIdlePrefilled(_ state: inout PomodoroRunState) {
        state.phase = .idle
        state.sessionID = nil
        state.startedAt = nil
        state.accumulatedSeconds = 0
        state.lastResumedAt = nil
    }
}

public enum PomodoroMode: String, Codable, CaseIterable {
    case countdown
    case countup
}

public enum PomodoroPhase: Equatable, Codable {
    case idle
    case running
    case paused
}

/// Full machine state, including the idle-stage configuration. Codable so the whole run
/// survives an app relaunch via the store's `openRun` slot.
public struct PomodoroRunState: Codable, Equatable {
    public var phase: PomodoroPhase = .idle
    public var mode: PomodoroMode?
    public var plannedSeconds: Int = PomodoroSessionCore.defaultDurationSeconds
    public var topic: String = ""
    public var sessionID: UUID?
    public var startedAt: Date?
    public var accumulatedSeconds: Double = 0
    public var lastResumedAt: Date?

    public init() {}
}

/// One settled focus session. Future fields must be added as optionals so older files
/// keep decoding (the Shelf persistence lesson).
public struct PomodoroSessionRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public var topic: String?
    public var mode: PomodoroMode
    public var plannedSeconds: Int?
    public let startedAt: Date
    public var endedAt: Date?
    public var elapsedSeconds: Double

    public init(id: UUID = UUID(), topic: String? = nil, mode: PomodoroMode,
                plannedSeconds: Int? = nil, startedAt: Date, endedAt: Date? = nil,
                elapsedSeconds: Double = 0) {
        self.id = id
        self.topic = topic
        self.mode = mode
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
    }
}
