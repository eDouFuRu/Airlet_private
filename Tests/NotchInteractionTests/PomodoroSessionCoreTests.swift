import XCTest
@testable import NotchInteractionCore

final class PomodoroSessionCoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000) // whole seconds only

    private func after(_ seconds: Double) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func makeRunning(mode: PomodoroMode = .countdown, planned: Int = 25 * 60,
                             topic: String = "") -> PomodoroRunState {
        var state = PomodoroRunState()
        state.topic = topic
        XCTAssertTrue(PomodoroSessionCore.selectMode(mode, state: &state))
        if mode == .countdown {
            XCTAssertTrue(PomodoroSessionCore.setDuration(seconds: planned, state: &state))
        }
        XCTAssertTrue(PomodoroSessionCore.start(&state, now: t0))
        return state
    }

    // MARK: - Configuration

    func testStartRequiresSelectedMode() {
        var state = PomodoroRunState()
        XCTAssertFalse(PomodoroSessionCore.canStart(state))
        XCTAssertFalse(PomodoroSessionCore.start(&state, now: t0))
        XCTAssertEqual(state.phase, .idle)
    }

    func testCountdownBelowMinimumCannotStart() {
        var state = PomodoroRunState()
        XCTAssertTrue(PomodoroSessionCore.selectMode(.countdown, state: &state))
        XCTAssertTrue(PomodoroSessionCore.setDuration(seconds: 59, state: &state))
        XCTAssertFalse(PomodoroSessionCore.canStart(state))

        XCTAssertTrue(PomodoroSessionCore.setDuration(seconds: 60, state: &state))
        XCTAssertTrue(PomodoroSessionCore.canStart(state))
    }

    func testCountupNeedsNoMinimumDuration() {
        var state = PomodoroRunState()
        XCTAssertTrue(PomodoroSessionCore.selectMode(.countup, state: &state))
        XCTAssertTrue(PomodoroSessionCore.canStart(state))
    }

    func testSelectModeAndDurationOnlyInIdle() {
        var state = makeRunning()
        XCTAssertFalse(PomodoroSessionCore.selectMode(.countup, state: &state))
        XCTAssertFalse(PomodoroSessionCore.setDuration(seconds: 10, state: &state))
        XCTAssertFalse(PomodoroSessionCore.setTopic("later", state: &state))
        XCTAssertEqual(state.mode, .countdown)
    }

    func testDurationBounds() {
        var state = PomodoroRunState()
        XCTAssertTrue(PomodoroSessionCore.selectMode(.countdown, state: &state))
        XCTAssertFalse(PomodoroSessionCore.setDuration(seconds: -1, state: &state))
        XCTAssertTrue(PomodoroSessionCore.setDuration(seconds: PomodoroSessionCore.maximumHour * 3600
                                                     + PomodoroSessionCore.maximumMinute * 60, state: &state))
        XCTAssertFalse(PomodoroSessionCore.setDuration(seconds: PomodoroSessionCore.maximumHour * 3600
                                                       + PomodoroSessionCore.maximumMinute * 60 + 1, state: &state))
    }

    // MARK: - Elapsed / remaining math

    func testElapsedAccumulatesAcrossPauseResumeCycles() {
        var state = makeRunning()
        XCTAssertEqual(PomodoroSessionCore.elapsed(state, now: after(100)), 100, accuracy: 0.001)

        XCTAssertTrue(PomodoroSessionCore.pause(&state, now: after(100)))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(PomodoroSessionCore.elapsed(state, now: after(500)), 100, accuracy: 0.001)

        XCTAssertTrue(PomodoroSessionCore.resume(&state, now: after(500)))
        XCTAssertEqual(PomodoroSessionCore.elapsed(state, now: after(600)), 200, accuracy: 0.001)

        XCTAssertTrue(PomodoroSessionCore.pause(&state, now: after(600)))
        XCTAssertTrue(PomodoroSessionCore.resume(&state, now: after(1_000)))
        XCTAssertEqual(PomodoroSessionCore.elapsed(state, now: after(1_100)), 300, accuracy: 0.001)
    }

    func testRemainingCountsDownAndNeverGoesNegative() throws {
        let state = makeRunning(planned: 60)
        XCTAssertEqual(try XCTUnwrap(PomodoroSessionCore.remainingSeconds(state, now: after(10))), 50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PomodoroSessionCore.remainingSeconds(state, now: after(120))), 0, accuracy: 0.001)
    }

    func testCountupHasNoRemaining() {
        let state = makeRunning(mode: .countup)
        XCTAssertNil(PomodoroSessionCore.remainingSeconds(state, now: after(10)))
        XCTAssertNil(PomodoroSessionCore.deadline(state))
    }

    func testDeadlineShiftsAfterResume() {
        var state = makeRunning(planned: 600)
        XCTAssertEqual(PomodoroSessionCore.deadline(state), after(600))
        XCTAssertTrue(PomodoroSessionCore.pause(&state, now: after(100)))
        XCTAssertNil(PomodoroSessionCore.deadline(state))
        XCTAssertTrue(PomodoroSessionCore.resume(&state, now: after(1_000)))
        XCTAssertEqual(PomodoroSessionCore.deadline(state), after(1_500))
    }

    // MARK: - Settlement

    func testManualEndRecordsActualElapsed() {
        var state = makeRunning(mode: .countdown, planned: 1_500, topic: "  写周报  ")
        XCTAssertTrue(PomodoroSessionCore.pause(&state, now: after(200)))
        XCTAssertTrue(PomodoroSessionCore.resume(&state, now: after(400)))

        guard let record = PomodoroSessionCore.end(&state, now: after(500)) else {
            return XCTFail("end should settle a running session")
        }
        XCTAssertEqual(record.elapsedSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(record.endedAt, after(500))
        XCTAssertEqual(record.startedAt, t0)
        XCTAssertEqual(record.mode, .countdown)
        XCTAssertEqual(record.plannedSeconds, 1_500)
        XCTAssertEqual(record.topic, "写周报")

        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.mode, .countdown, "end keeps the configuration for the next prefill")
        XCTAssertEqual(state.plannedSeconds, 1_500)
        XCTAssertEqual(state.topic, "  写周报  ")
        XCTAssertNil(state.sessionID)
        XCTAssertNil(state.startedAt)
    }

    func testManualEndOfCountupOmitsPlannedSeconds() {
        var state = makeRunning(mode: .countup)
        guard let record = PomodoroSessionCore.end(&state, now: after(90)) else {
            return XCTFail("end should settle a running session")
        }
        XCTAssertEqual(record.mode, .countup)
        XCTAssertNil(record.plannedSeconds)
        XCTAssertEqual(record.elapsedSeconds, 90, accuracy: 0.001)
    }

    func testEndRejectedWhenIdle() {
        var state = PomodoroRunState()
        XCTAssertNil(PomodoroSessionCore.end(&state, now: t0))
    }

    func testNaturalCompletionUsesDeadlineNotTickTime() {
        var state = makeRunning(planned: 600)
        XCTAssertNil(PomodoroSessionCore.naturalCompleteIfDue(&state, now: after(599.5)),
                     "not due yet")

        guard let record = PomodoroSessionCore.naturalCompleteIfDue(&state, now: after(663)) else {
            return XCTFail("an overdue countdown must settle")
        }
        XCTAssertEqual(record.endedAt, after(600), "endedAt is the wall-clock deadline")
        XCTAssertEqual(record.elapsedSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(record.plannedSeconds, 600)
        XCTAssertEqual(state.phase, .idle)
    }

    func testNaturalCompletionIgnoresPausedAndCountup() {
        var paused = makeRunning(planned: 600)
        XCTAssertTrue(PomodoroSessionCore.pause(&paused, now: after(10)))
        XCTAssertNil(PomodoroSessionCore.naturalCompleteIfDue(&paused, now: after(1_000)))

        var countup = makeRunning(mode: .countup)
        XCTAssertNil(PomodoroSessionCore.naturalCompleteIfDue(&countup, now: after(1_000)))
    }

    func testRestoredOverdueRunningSessionSettles() {
        // The shape PomodoroSessionStore hands back after an app relaunch mid-countdown.
        var restored = makeRunning(planned: 600)
        XCTAssertNotNil(restored.sessionID)
        let settled = PomodoroSessionCore.naturalCompleteIfDue(&restored, now: after(10_000))
        XCTAssertNotNil(settled)
        XCTAssertEqual(settled?.endedAt, after(600))
        XCTAssertEqual(restored.phase, .idle)
    }

    // MARK: - Cancel

    func testCancelOnlyAppliesBeforeStart() {
        var state = PomodoroRunState()
        state.topic = "保留主题"
        XCTAssertTrue(PomodoroSessionCore.selectMode(.countdown, state: &state))
        XCTAssertTrue(PomodoroSessionCore.setDuration(seconds: 3_600, state: &state))

        XCTAssertTrue(PomodoroSessionCore.cancel(&state))
        XCTAssertNil(state.mode, "cancel returns to the unselected mode buttons")
        XCTAssertEqual(state.plannedSeconds, PomodoroSessionCore.defaultDurationSeconds)
        XCTAssertEqual(state.topic, "保留主题", "cancel keeps the topic")
        XCTAssertNil(state.sessionID)

        var running = makeRunning()
        XCTAssertFalse(PomodoroSessionCore.cancel(&running), "a started session can only be ended")
        XCTAssertEqual(running.phase, .running)
    }

    // MARK: - Clock formatting

    func testClockTextFormatsAndPromotesToHours() {
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 0), "0:00")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 59), "0:59")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 59.4), "1:00", "ceil keeps the last second visible")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 3_599), "59:59")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 3_600), "1:00:00")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 3_661), "1:01:01")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: 45_296), "12:34:56")
        XCTAssertEqual(PomodoroSessionCore.clockText(seconds: -5), "0:00")
    }
}
