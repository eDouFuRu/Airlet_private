import Foundation

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
