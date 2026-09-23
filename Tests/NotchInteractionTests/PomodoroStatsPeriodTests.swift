import XCTest
@testable import NotchInteractionCore

final class PomodoroStatsPeriodTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func record(_ start: Date, _ seconds: Double) -> PomodoroSessionRecord {
        PomodoroSessionRecord(mode: .countup, startedAt: start, endedAt: start.addingTimeInterval(seconds), elapsedSeconds: seconds)
    }
    func testWeekIsSundayThroughSaturdayAcrossYearBoundary() {
        let dates = PomodoroStatsPeriod.week.dates(containing: date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(dates.first, date(2025, 12, 28))
        XCTAssertEqual(dates.last, date(2026, 1, 3))
        XCTAssertEqual(dates.count, 7)
    }
    func testMonthLengthsAndDST() {
        for (year, month, count) in [(2024, 2, 29), (2025, 2, 28), (2026, 9, 30), (2026, 3, 31)] {
            let dates = PomodoroStatsPeriod.month.dates(containing: date(year, month, 12), calendar: calendar)
            XCTAssertEqual(dates.count, count)
            XCTAssertEqual(dates.last, date(year, month, count))
        }
        let totals = PomodoroStatsPeriod.month.totals(sessions: [record(date(2026, 3, 9), 720)], containing: date(2026, 3, 1), calendar: calendar)
        XCTAssertEqual(totals[8], 720)
    }
    func testMonthBoundariesAndCrossMidnightStayOnStartDate() {
        let start = date(2026, 9, 30).addingTimeInterval(23 * 3600)
        let records = [record(start, 7200), record(date(2026, 10, 1), 300), record(date(2026, 8, 31), 900)]
        let totals = PomodoroStatsPeriod.month.totals(sessions: records, containing: date(2026, 9, 1), calendar: calendar)
        XCTAssertEqual(totals.last, 7200)
        XCTAssertEqual(totals.reduce(0, +), 7200)
    }
    func testYearTotalsHaveTwelveMonthsAndExcludeOtherYears() {
        let records = [record(date(2026, 1, 2), 300), record(date(2026, 12, 31), 700), record(date(2025, 12, 31), 600)]
        let totals = PomodoroStatsPeriod.year.totals(sessions: records, containing: date(2026, 6, 1), calendar: calendar)
        XCTAssertEqual(totals.count, 12)
        XCTAssertEqual(totals[0], 300)
        XCTAssertEqual(totals[11], 700)
        XCTAssertEqual(totals.reduce(0, +), 1000)
    }
    func testRelativeScaleAndZeroRecords() {
        XCTAssertEqual(PomodoroStatsPeriod.ratios([0, 300, 600, 1200]), [0, 0.25, 0.5, 1])
        XCTAssertEqual(PomodoroStatsPeriod.ratios([0, 0]), [0, 0])
        XCTAssertEqual(PomodoroStatsPeriod.ratios([-.infinity, .nan, -1]), [0, 0, 0])
    }
}
