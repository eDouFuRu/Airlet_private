import XCTest
@testable import NotchInteractionCore

final class PomodoroRingPresentationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func running(_ mode: PomodoroMode) -> PomodoroRunState {
        var state = PomodoroRunState()
        _ = PomodoroSessionCore.selectMode(mode, state: &state)
        _ = PomodoroSessionCore.start(&state, now: start)
        return state
    }

    func testCountdownFillsAndClampsWithoutSettling() {
        let state = running(.countdown)
        let snapshot = PomodoroRingPresentation(state: state)
        XCTAssertEqual(snapshot.progress(at: start), 0)
        XCTAssertEqual(snapshot.progress(at: start.addingTimeInterval(750)), 0.5)
        XCTAssertEqual(snapshot.progress(at: start.addingTimeInterval(1500)), 1)
        XCTAssertEqual(snapshot.progress(at: start.addingTimeInterval(9000)), 1)
        XCTAssertEqual(state.phase, .running, "Sampling cannot settle a session")
    }

    func testCountdownDrainsAndCountupIgnoresDirection() {
        let snapshot = PomodoroRingPresentation(state: running(.countdown))
        for (seconds, expected) in [(0.0, 1.0), (750, 0.5), (1500, 0), (9000, 0)] {
            XCTAssertEqual(snapshot.progress(at: start.addingTimeInterval(seconds), countdownFills: false), expected)
        }
        let countup = PomodoroRingPresentation(state: running(.countup))
        XCTAssertEqual(countup.progress(at: start.addingTimeInterval(9000), countdownFills: false), 2.5)
    }

    func testDrainingPauseResumeAndCompletionRestart() throws {
        var state = running(.countdown)
        _ = PomodoroSessionCore.pause(&state, now: start.addingTimeInterval(300))
        XCTAssertEqual(PomodoroRingPresentation(state: state).progress(at: start.addingTimeInterval(900), countdownFills: false), 0.8)
        _ = PomodoroSessionCore.resume(&state, now: start.addingTimeInterval(900))
        XCTAssertEqual(try XCTUnwrap(PomodoroRingPresentation(state: state).progress(at: start.addingTimeInterval(1050), countdownFills: false)), 0.7, accuracy: 0.000001)
        let completed = start.addingTimeInterval(2100)
        _ = PomodoroSessionCore.naturalCompleteIfDue(&state, now: completed)
        XCTAssertEqual(PomodoroRingPresentation(state: state, completedAt: completed).progress(at: completed, countdownFills: false), 0)
        _ = PomodoroSessionCore.start(&state, now: completed)
        XCTAssertEqual(PomodoroRingPresentation(state: state, completedAt: completed).progress(at: completed, countdownFills: false), 1)
    }

    func testCountupRetainsContinuousLaps() throws {
        let snapshot = PomodoroRingPresentation(state: running(.countup))
        XCTAssertEqual(snapshot.progress(at: start.addingTimeInterval(9000)), 2.5)
        for boundary in [3600.0, 7200.0, 10800.0] {
            let before = try XCTUnwrap(snapshot.progress(at: start.addingTimeInterval(boundary - 0.01)))
            let after = try XCTUnwrap(snapshot.progress(at: start.addingTimeInterval(boundary + 0.01)))
            XCTAssertGreaterThan(after, before)
            let a = PomodoroRingGeometry(progress: before)
            let b = PomodoroRingGeometry(progress: after)
            XCTAssertEqual(b.endAngle - a.endAngle, 0.02 / 3600 * 2 * .pi, accuracy: 0.000001)
        }
    }

    func testCapsShareTrackRadiusAndSweepNeverExceedsOneVisibleLap() {
        for progress in [0.0, 0.00001, 0.25, 0.5, 0.99999, 1, 1.00001, 2.5, 200] {
            let geometry = PomodoroRingGeometry(progress: progress)
            for angle in [geometry.startAngle, geometry.endAngle] {
                let p = geometry.point(at: angle, center: .zero)
                XCTAssertEqual(hypot(p.x, p.y), 57, accuracy: 0.000001)
            }
            XCTAssertEqual(geometry.sweep, min(progress, 1) * 2 * .pi, accuracy: 0.000001)
        }
    }

    func testPauseFreezesAndResumeDoesNotCountPauseTime() throws {
        var state = running(.countdown)
        _ = PomodoroSessionCore.pause(&state, now: start.addingTimeInterval(300))
        let paused = PomodoroRingPresentation(state: state)
        XCTAssertEqual(paused.progress(at: start.addingTimeInterval(300)), 0.2)
        XCTAssertEqual(paused.progress(at: start.addingTimeInterval(900)), 0.2)
        _ = PomodoroSessionCore.resume(&state, now: start.addingTimeInterval(900))
        let resumed = PomodoroRingPresentation(state: state)
        XCTAssertEqual(resumed.progress(at: start.addingTimeInterval(900)), 0.2)
        XCTAssertEqual(try XCTUnwrap(resumed.progress(at: start.addingTimeInterval(1050))), 0.3, accuracy: 0.000001)
    }

    func testCompletionHoldFadeAndNewSessionIgnorePreviousCompletion() {
        var state = running(.countdown)
        let completed = start.addingTimeInterval(1500)
        _ = PomodoroSessionCore.naturalCompleteIfDue(&state, now: completed)
        let feedback = PomodoroRingPresentation(state: state, completedAt: completed)
        XCTAssertEqual(feedback.progress(at: completed), 1)
        XCTAssertEqual(feedback.opacity(at: completed.addingTimeInterval(2.9), reduceMotion: false), 1)
        XCTAssertEqual(feedback.opacity(at: completed.addingTimeInterval(3.1), reduceMotion: false), 0.5, accuracy: 0.000001)
        XCTAssertEqual(feedback.opacity(at: completed.addingTimeInterval(3.3), reduceMotion: false), 0)
        XCTAssertEqual(feedback.opacity(at: completed.addingTimeInterval(3), reduceMotion: true), 0)
        _ = PomodoroSessionCore.start(&state, now: completed.addingTimeInterval(1))
        let next = PomodoroRingPresentation(state: state, completedAt: completed)
        XCTAssertEqual(next.progress(at: completed.addingTimeInterval(1)), 0)
        XCTAssertEqual(next.opacity(at: completed.addingTimeInterval(4), reduceMotion: false), 1)
    }

    func testIdleAndManualEndHaveNoProgress() {
        var state = running(.countup)
        _ = PomodoroSessionCore.end(&state, now: start.addingTimeInterval(20))
        XCTAssertNil(PomodoroRingPresentation(state: state).progress(at: start))
        XCTAssertNil(PomodoroRingPresentation(state: PomodoroRunState()).progress(at: start))
    }
}
