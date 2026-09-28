import XCTest
@testable import NotchInteractionCore

final class FloatingIslandPresentationTests: XCTestCase {
    func testHardwareFeedbackPreemptsNotificationAndTimerCompletion() {
        XCTAssertEqual(FloatingIslandContent.select(hud: true, power: true, notification: true,
            completion: true, song: true, lyric: true, pomodoro: true, music: true), .hud)
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: true, notification: true,
            completion: true, song: true, lyric: true, pomodoro: true, music: true), .power)
    }

    func testNotificationAndCompletionReplaceOngoingMediaInThatOrder() {
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: false, notification: true,
            completion: true, song: true, lyric: true, pomodoro: true, music: true), .notification)
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: false, notification: false,
            completion: true, song: true, lyric: true, pomodoro: true, music: true), .completion)
    }

    func testOnlyFiniteEventsWakeTheDormantSurface() {
        for source: FloatingIslandContent in [.hud, .power, .notification, .completion, .song] {
            XCTAssertTrue(source.isTransient)
        }
        for source: FloatingIslandContent in [.lyric, .pomodoro, .music, .idle] {
            XCTAssertFalse(IslandSurfaceVisibility.shouldShow(isFloating: true, autoHide: true,
                expanded: false, pointerInside: false, transient: source.isTransient, available: true))
        }
    }

    func testLyricsGiveWayToTimerThenMusicWhenNoCueIsAvailable() {
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: false, notification: false,
            completion: false, song: false, lyric: true, pomodoro: true, music: true), .lyric)
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: false, notification: false,
            completion: false, song: false, lyric: false, pomodoro: true, music: true), .pomodoro)
        XCTAssertEqual(FloatingIslandContent.select(hud: false, power: false, notification: false,
            completion: false, song: false, lyric: false, pomodoro: false, music: true), .music)
    }

    func testLongMessagesGrowHorizontallyWithoutEscapingTheirDisplay() {
        XCTAssertEqual(FloatingIslandMetrics.width(textWidth: 0, decorationWidth: 52, maximum: 640), 120)
        XCTAssertEqual(FloatingIslandMetrics.width(textWidth: 300.2, decorationWidth: 52, maximum: 640), 353)
        XCTAssertEqual(FloatingIslandMetrics.width(textWidth: 1200, decorationWidth: 52, maximum: 640), 640)
        XCTAssertEqual(FloatingIslandMetrics.width(textWidth: 1200, decorationWidth: 52, maximum: 480), 480)
        for height: CGFloat in [16, 18, 22, 26] {
            XCTAssertLessThanOrEqual(FloatingIslandMetrics.iconSize(height: height), height - 4)
            XCTAssertLessThanOrEqual(FloatingIslandMetrics.fontSize(height: height), height - 4)
        }
    }
}
