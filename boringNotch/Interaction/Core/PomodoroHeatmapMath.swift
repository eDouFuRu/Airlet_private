import Foundation

/// Scrolling edits a draft. Only explicit confirmation changes the displayed week.
struct PomodoroWeekSelection {
    private(set) var selectedWeekStart: Date?
    private(set) var isPicking = false
    var draftWeekStart: Date?

    mutating func begin(currentWeekStart: Date) {
        draftWeekStart = selectedWeekStart ?? currentWeekStart
        isPicking = true
    }

    mutating func confirm(currentWeekStart: Date) {
        guard isPicking, let draftWeekStart else { return }
        selectedWeekStart = draftWeekStart == currentWeekStart ? nil : draftWeekStart
        isPicking = false
        self.draftWeekStart = nil
    }

    mutating func returnToCurrentWeek() {
        selectedWeekStart = nil
        draftWeekStart = nil
        isPicking = false
    }
}

/// An sRGB color expressed as plain numbers so heatmap math stays testable without AppKit.
public struct PomodoroRGB: Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: Int) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255,
                  g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255)
    }

    public static let neutral = PomodoroRGB(r: 1, g: 1, b: 1)
}

public enum PomodoroHeatmapPalette: String, Codable, CaseIterable {
    case tomatoRed
    case tangerine
    case forestGreen
    case oceanBlue
    case grapePurple

    public var baseRGB: PomodoroRGB {
        switch self {
        case .tomatoRed: return PomodoroRGB(hex: 0xE5533C)
        case .tangerine: return PomodoroRGB(hex: 0xF08C2E)
        case .forestGreen: return PomodoroRGB(hex: 0x3E9B4F)
        case .oceanBlue: return PomodoroRGB(hex: 0x3D7DD8)
        case .grapePurple: return PomodoroRGB(hex: 0x8A63C9)
        }
    }

    /// Localization key for the settings picker.
    public var nameKey: String {
        switch self {
        case .tomatoRed: return "Tomato red"
        case .tangerine: return "Tangerine"
        case .forestGreen: return "Forest green"
        case .oceanBlue: return "Ocean blue"
        case .grapePurple: return "Grape purple"
        }
    }
}

/// Monday-anchored week math and the GitHub-style intensity ramp.
///
/// The week start is computed from the weekday component directly rather than through
/// `Calendar.dateInterval(of: .weekOfYear, …)`, which follows the user's `firstWeekday`
/// setting and would shift the grid on locales whose weeks start on Sunday.
public enum PomodoroHeatmapMath {
    /// Durations bounding each intensity level, in seconds. Index `i` holds the *upper*
    /// bound of level `i` (exclusive); the last entry is open-ended.
    public static let levelUpperBounds: [Double] = [0, 30 * 60, 60 * 60, 2 * 60 * 60]

    /// Alphas for levels 1…4 on top of the palette base. Level 0 is a fixed neutral chip.
    public static let levelAlphas: [Double] = [0.35, 0.55, 0.78, 1.0]
    public static let neutralAlpha = 0.14

    // MARK: - Week math

    /// Midnight of the Monday containing `date`.
    public static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        // weekday: 1 = Sunday … 7 = Saturday. Shift so Monday maps to 0.
        let mondayOffset = (calendar.component(.weekday, from: dayStart) + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: dayStart) ?? dayStart
    }

    /// The `[start, start + 7 days)` interval of the week containing `date`.
    public static func weekInterval(containing date: Date,
                                    calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = startOfWeek(date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    /// Weeks back from the current one offered by the week picker (current week included).
    public static let weekPickerHistory = 12

    // MARK: - Aggregation

    /// Focused seconds per weekday, Monday-first, for the week starting at `weekStart`.
    /// A session is attributed to the day it *started*; a session crossing midnight is
    /// never split, so it lands wholly on its start day.
    public static func dailyTotals(sessions: [PomodoroSessionRecord], weekStart: Date,
                                   calendar: Calendar = .current) -> [Double] {
        var totals = [Double](repeating: 0, count: 7)
        for session in sessions {
            let dayStart = calendar.startOfDay(for: session.startedAt)
            guard let bucket = calendar.dateComponents([.day], from: weekStart, to: dayStart).day,
                  (0..<7).contains(bucket) else { continue }
            totals[bucket] += max(0, session.elapsedSeconds)
        }
        return totals
    }

    public static func intensityLevel(seconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        // Skip the level-0 bound; it only exists to give the zero case a home.
        for (level, bound) in levelUpperBounds.enumerated() where level > 0 && seconds <= bound {
            return level
        }
        return levelUpperBounds.count
    }

    /// Level 0 renders as a fixed neutral chip; levels 1…4 tint the palette base by alpha.
    public static func color(forLevel level: Int,
                             palette: PomodoroHeatmapPalette) -> (rgb: PomodoroRGB, alpha: Double) {
        guard (1...levelAlphas.count).contains(level) else {
            return (PomodoroRGB.neutral, neutralAlpha)
        }
        return (palette.baseRGB, levelAlphas[level - 1])
    }
}

/// Calendar-based display buckets; records remain attributed to their start date.
enum PomodoroStatsPeriod: String, CaseIterable {
    case week, month, year
    var titleKey: String { switch self { case .week: return "周"; case .month: return "月"; case .year: return "年" } }
    var component: Calendar.Component { self == .year ? .year : .month }

    func start(containing date: Date, calendar: Calendar = .current) -> Date {
        if self == .week {
            let midnight = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: midnight), to: midnight) ?? midnight
        }
        return calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func dates(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let first = start(containing: date, calendar: calendar)
        let count = self == .week ? 7 : self == .year ? 12 : (calendar.range(of: .day, in: .month, for: first)?.count ?? 0)
        return (0..<count).compactMap { calendar.date(byAdding: self == .year ? .month : .day, value: $0, to: first) }
    }

    func totals(sessions: [PomodoroSessionRecord], containing date: Date, calendar: Calendar = .current) -> [Double] {
        let buckets = dates(containing: date, calendar: calendar)
        guard let first = buckets.first, let last = buckets.last,
              let end = calendar.date(byAdding: self == .year ? .month : .day, value: 1, to: last) else { return [] }
        var result = Array(repeating: 0.0, count: buckets.count)
        for record in sessions where record.startedAt >= first && record.startedAt < end {
            let index = self == .year ? calendar.dateComponents([.month], from: first, to: record.startedAt).month : calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: record.startedAt)).day
            if let index, result.indices.contains(index), record.elapsedSeconds.isFinite {
                result[index] += max(0, record.elapsedSeconds)
            }
        }
        return result
    }

    static func ratios(_ totals: [Double]) -> [Double] {
        let clean = totals.map { $0.isFinite ? max(0, $0) : 0 }
        guard let maximum = clean.max(), maximum > 0 else { return clean.map { _ in 0 } }
        return clean.map { $0 / maximum }
    }
}
