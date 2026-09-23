import AppKit
import Foundation

/// App-lifecycle model for the pomodoro timer.
///
/// Mirrors the settlement discipline of the retired rest-session model: every transition
/// is computed by `PomodoroSessionCore` from wall-clock timestamps and **persisted before
/// it is published**, so the 1 Hz display tick can only change what is shown, never when
/// a session settles. A running session survives an app relaunch through the store's
/// `openRun` slot; a countdown that expired while the app was closed settles on restore.
@MainActor
final class PomodoroModel: ObservableObject {
    static let shared = PomodoroModel()

    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var mode: PomodoroMode?
    @Published private(set) var plannedSeconds: Int = PomodoroSessionCore.defaultDurationSeconds
    @Published private(set) var topic: String = ""
    @Published private(set) var remainingSeconds: Int = PomodoroSessionCore.defaultDurationSeconds
    @Published private(set) var elapsedSeconds: Double = 0
    /// Brief full-ring flash after a countdown completes naturally.
    @Published private(set) var justCompleted = false
    @Published private(set) var completionPresentedAt: Date?
    /// A stable copy of Core anchors; frame sampling is entirely presentation-only.
    var ringPresentation: PomodoroRingPresentation {
        PomodoroRingPresentation(state: state, completedAt: completionPresentedAt)
    }

    private let store: PomodoroSessionStore
    private var state = PomodoroRunState()
    private var sessions: [PomodoroSessionRecord] = []
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var completionFlashTask: Task<Void, Never>?

    init(store: PomodoroSessionStore = PomodoroSessionStore()) {
        self.store = store
        restoreFromDisk()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    deinit {
        ticker?.invalidate()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Derived display values

    var isBusy: Bool { phase != .idle }

    var canStart: Bool { PomodoroSessionCore.canStart(state) }

    /// Countdown remaining or count-up elapsed, formatted `mm:ss` / `h:mm:ss`.
    var clockText: String {
        guard isBusy else { return PomodoroSessionCore.clockText(seconds: Double(plannedSeconds)) }
        if mode == .countdown {
            return PomodoroSessionCore.clockText(seconds: Double(remainingSeconds))
        }
        return PomodoroSessionCore.clockText(seconds: elapsedSeconds.rounded(.down))
    }

    var allSessions: [PomodoroSessionRecord] { sessions }

    // MARK: - Configuration (idle only)

    @discardableResult
    func selectMode(_ selected: PomodoroMode) -> Bool {
        guard PomodoroSessionCore.selectMode(selected, state: &state) else { return false }
        syncPublished()
        return true
    }

    @discardableResult
    func setDuration(seconds: Int) -> Bool {
        guard PomodoroSessionCore.setDuration(seconds: seconds, state: &state) else { return false }
        syncPublished()
        return true
    }

    func setDuration(hours: Int, minutes: Int) {
        setDuration(seconds: hours * 3600 + minutes * 60)
    }

    @discardableResult
    func setTopic(_ text: String) -> Bool {
        guard PomodoroSessionCore.setTopic(text, state: &state) else { return false }
        syncPublished()
        return true
    }

    /// Pre-start reset: mode selection clears, duration returns to the default, topic stays.
    @discardableResult
    func cancelConfiguration() -> Bool {
        guard PomodoroSessionCore.cancel(&state) else { return false }
        syncPublished()
        return true
    }

    // MARK: - Session events

    func start() {
        guard PomodoroSessionCore.start(&state, now: Date()) else { return }
        persist(openRun: state)
        completionFlashTask?.cancel()
        completionPresentedAt = nil
        justCompleted = false
        syncPublished()
        syncTicker()
    }

    func pause() {
        guard PomodoroSessionCore.pause(&state, now: Date()) else { return }
        persist(openRun: state)
        syncPublished()
        syncTicker()
    }

    func resume() {
        guard PomodoroSessionCore.resume(&state, now: Date()) else { return }
        persist(openRun: state)
        syncPublished()
        syncTicker()
    }

    func end() {
        guard let record = PomodoroSessionCore.end(&state, now: Date()) else { return }
        sessions.append(record)
        persist(openRun: nil)
        syncPublished()
        syncTicker()
    }

    /// Tick and wake reconciliation. Settlement is wall-clock derived, so a merged or
    /// delayed tick only postpones the visible flip, never the recorded end time.
    func refresh() {
        settleIfDue()
        syncPublished()
        syncTicker()
    }

    // MARK: - Internals

    private func restoreFromDisk() {
        let file = store.load()
        sessions = file.sessions
        guard var restored = file.openRun, restored.phase != .idle else {
            state = PomodoroRunState()
            syncPublished()
            return
        }
        state = restored
        settleIfDue()
        syncPublished()
        syncTicker()
    }

    private func settleIfDue() {
        guard let record = PomodoroSessionCore.naturalCompleteIfDue(&state, now: Date()) else { return }
        sessions.append(record)
        persist(openRun: nil)
        beginCompletionFlash()
    }

    /// Persistence precedes publication: if the process dies right after, the file already
    /// agrees with what was on screen.
    private func persist(openRun: PomodoroRunState?) {
        store.save(PomodoroSessionStore.File(sessions: sessions, openRun: openRun))
    }

    private func syncPublished() {
        if phase != state.phase { phase = state.phase }
        if mode != state.mode { mode = state.mode }
        if plannedSeconds != state.plannedSeconds { plannedSeconds = state.plannedSeconds }
        if topic != state.topic { topic = state.topic }
        let now = Date()
        let remaining = PomodoroSessionCore.remainingSeconds(state, now: now).map { Int($0.rounded(.up)) } ?? 0
        if remainingSeconds != remaining { remainingSeconds = remaining }
        let elapsed = PomodoroSessionCore.elapsed(state, now: now)
        if abs(elapsedSeconds - elapsed) > 0.001 { elapsedSeconds = elapsed }
    }

    private func syncTicker() {
        if state.phase == .running, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if state.phase != .running, ticker != nil {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func beginCompletionFlash() {
        completionFlashTask?.cancel()
        completionPresentedAt = Date()
        justCompleted = true
        completionFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.justCompleted = false
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.completionPresentedAt = nil
        }
    }
}
