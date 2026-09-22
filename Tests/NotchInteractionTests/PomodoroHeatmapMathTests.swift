import XCTest
@testable import NotchInteractionCore

final class PomodoroHeatmapMathTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-21 is a Monday; 9月21 - 9月27 is the example week from the requirements.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func session(_ year: Int, _ month: Int, _ day: Int, _ hour: Int,
                         seconds: Double, mode: PomodoroMode = .countdown) -> PomodoroSessionRecord {
        PomodoroSessionRecord(mode: mode, startedAt: date(year, month, day, hour),
                              endedAt: date(year, month, day, hour).addingTimeInterval(seconds),
                              elapsedSeconds: seconds)
    }

    // MARK: - Monday-anchored weeks

    func testStartOfWeekMapsEveryWeekdayToItsMonday() {
        let monday = date(2026, 9, 21, 0, 0)
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
            XCTAssertEqual(PomodoroHeatmapMath.startOfWeek(day, calendar: calendar), monday,
                           "day \(offset) of the week must anchor to Monday")
        }
    }

    func testStartOfWeekRollsSundayBackAndMondayForward() {
        XCTAssertEqual(PomodoroHeatmapMath.startOfWeek(date(2026, 9, 20), calendar: calendar), date(2026, 9, 14, 0, 0),
                       "Sunday belongs to the week that started the Monday before")
        XCTAssertEqual(PomodoroHeatmapMath.startOfWeek(date(2026, 9, 27), calendar: calendar), date(2026, 9, 21, 0, 0))
        XCTAssertEqual(PomodoroHeatmapMath.startOfWeek(date(2026, 9, 28), calendar: calendar), date(2026, 9, 28, 0, 0),
                       "a Monday anchors to itself")
    }

    func testStartOfWeekIsDayStartEvenForEarlyMorning() {
        let earlyMonday = date(2026, 9, 21, 0, 7)
        XCTAssertEqual(PomodoroHeatmapMath.startOfWeek(earlyMonday, calendar: calendar),
                       date(2026, 9, 21, 0, 0))
    }

    func testWeekIntervalSpansSevenDays() {
        let interval = PomodoroHeatmapMath.weekInterval(containing: date(2026, 9, 23), calendar: calendar)
        XCTAssertEqual(interval.start, date(2026, 9, 21, 0, 0))
        XCTAssertEqual(interval.end, date(2026, 9, 28, 0, 0))
    }

    // MARK: - Daily aggregation

    func testDailyTotalsBucketAndAccumulate() {
        let weekStart = date(2026, 9, 21, 0, 0)
        let sessions = [
            session(2026, 9, 21, 9, seconds: 1_800),           // Monday 30m
            session(2026, 9, 22, 10, seconds: 1_200),          // Tuesday 20m
            session(2026, 9, 22, 15, seconds: 900),            // Tuesday +15m
            session(2026, 9, 14, 8, seconds: 3_600),           // previous week, excluded
            session(2026, 9, 28, 8, seconds: 3_600),           // next week, excluded
        ]
        let totals = PomodoroHeatmapMath.dailyTotals(sessions: sessions, weekStart: weekStart, calendar: calendar)
        XCTAssertEqual(totals[0], 1_800, accuracy: 0.001)
        XCTAssertEqual(totals[1], 2_100, accuracy: 0.001)
        XCTAssertEqual(totals[2...6].map { $0 }, [0, 0, 0, 0, 0])
    }

    func testSessionCrossingMidnightAttributesToStartDay() {
        let weekStart = date(2026, 9, 21, 0, 0)
        // Starts Saturday 23:00 and runs an hour past midnight.
        let lateStart = PomodoroSessionRecord(mode: .countup, startedAt: date(2026, 9, 26, 23, 0),
                                              endedAt: date(2026, 9, 27, 0, 0), elapsedSeconds: 3_600)
        let totals = PomodoroHeatmapMath.dailyTotals(sessions: [lateStart], weekStart: weekStart, calendar: calendar)
        XCTAssertEqual(totals[5], 3_600, accuracy: 0.001, "Saturday absorbs the whole session")
        XCTAssertEqual(totals[6], 0, accuracy: 0.001)
    }

    func testCountupSessionsCountTowardTheHeatmap() {
        let weekStart = date(2026, 9, 21, 0, 0)
        let totals = PomodoroHeatmapMath.dailyTotals(
            sessions: [session(2026, 9, 25, 14, seconds: 720, mode: .countup)],
            weekStart: weekStart, calendar: calendar)
        XCTAssertEqual(totals[4], 720, accuracy: 0.001)
    }

    // MARK: - Intensity levels

    func testIntensityLevelBoundaries() {
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 0), 0)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: -1), 0)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 0.5), 1)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 1_800), 1, "≤30m is level 1")
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 1_801), 2)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 3_600), 2, "≤1h is level 2")
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 3_601), 3)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 7_200), 3, "≤2h is level 3")
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 7_201), 4)
        XCTAssertEqual(PomodoroHeatmapMath.intensityLevel(seconds: 100_000), 4)
    }

    // MARK: - Palette colors

    func testLevelZeroIsFixedNeutral() {
        for palette in PomodoroHeatmapPalette.allCases {
            let color = PomodoroHeatmapMath.color(forLevel: 0, palette: palette)
            XCTAssertEqual(color.rgb, PomodoroRGB.neutral)
            XCTAssertEqual(color.alpha, PomodoroHeatmapMath.neutralAlpha, accuracy: 0.0001)
        }
    }

    func testLevelsOneThroughFourRampAlphaOnTheBaseColor() {
        let base = PomodoroHeatmapPalette.tomatoRed.baseRGB
        let expectedAlphas: [Double] = [0.35, 0.55, 0.78, 1.0]
        for (index, expected) in expectedAlphas.enumerated() {
            let color = PomodoroHeatmapMath.color(forLevel: index + 1, palette: .tomatoRed)
            XCTAssertEqual(color.rgb, base)
            XCTAssertEqual(color.alpha, expected, accuracy: 0.0001)
        }
    }

    func testPalettesAreDistinctAndCovered() {
        XCTAssertEqual(PomodoroHeatmapPalette.allCases.count, 5)
        let bases = Set(PomodoroHeatmapPalette.allCases.map { $0.baseRGB })
        XCTAssertEqual(bases.count, 5, "every preset needs its own base color")
        for palette in PomodoroHeatmapPalette.allCases {
            XCTAssertFalse(palette.nameKey.isEmpty)
        }
    }

    func testWeekPickerHistoryCoversTwelvePastWeeks() {
        XCTAssertEqual(PomodoroHeatmapMath.weekPickerHistory, 12)
    }
}
