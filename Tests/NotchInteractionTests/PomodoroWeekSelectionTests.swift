import XCTest
@testable import NotchInteractionCore

final class PomodoroWeekSelectionTests: XCTestCase {
    private let current = Date(timeIntervalSince1970: 1_800_000_000)

    func testScrollingKeepsPickerOpenAndDoesNotChangeDisplayedWeekUntilConfirmed() {
        var selection = PomodoroWeekSelection()
        selection.begin(currentWeekStart: current)
        for offset in 1...12 {
            selection.draftWeekStart = current.addingTimeInterval(Double(-offset * 7 * 86400))
            XCTAssertTrue(selection.isPicking)
            XCTAssertNil(selection.selectedWeekStart)
        }
        let draft = selection.draftWeekStart
        selection.confirm(currentWeekStart: current)
        XCTAssertEqual(selection.selectedWeekStart, draft)
        XCTAssertFalse(selection.isPicking)
        selection.begin(currentWeekStart: current)
        XCTAssertEqual(selection.draftWeekStart, draft)
    }

    func testReturnToCurrentDiscardsUnconfirmedDraftAndTracksFutureCurrentWeek() {
        var selection = PomodoroWeekSelection()
        selection.begin(currentWeekStart: current)
        selection.draftWeekStart = current.addingTimeInterval(-604800)
        selection.confirm(currentWeekStart: current)
        selection.begin(currentWeekStart: current)
        selection.draftWeekStart = current.addingTimeInterval(-1209600)
        selection.returnToCurrentWeek()
        XCTAssertNil(selection.selectedWeekStart)
        XCTAssertNil(selection.draftWeekStart)
        XCTAssertFalse(selection.isPicking)
        let nextMonday = current.addingTimeInterval(604800)
        selection.begin(currentWeekStart: nextMonday)
        XCTAssertEqual(selection.draftWeekStart, nextMonday)
    }

    func testConfirmCurrentWeekUsesLiveCurrentWeekInsteadOfPinningADate() {
        var selection = PomodoroWeekSelection()
        selection.begin(currentWeekStart: current)
        selection.confirm(currentWeekStart: current)
        XCTAssertNil(selection.selectedWeekStart)
        XCTAssertFalse(selection.isPicking)
    }
}
