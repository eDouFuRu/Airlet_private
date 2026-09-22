import Defaults
import SwiftUI

/// Right column of the pomodoro page: a GitHub-contribution-style weekly heatmap.
///
/// The header shows the Monday-based week range and doubles as the toggle that morphs the
/// whole panel into a vertical week picker. Below it sit the week's total focus time and
/// seven day squares (Mon–Sun) shaded by that day's total focused time.
struct PomodoroWeeklyHeatmap: View {
    @ObservedObject private var model = PomodoroModel.shared
    @Default(.pomodoroHeatmapPalette) private var paletteOption
    @Environment(\.locale) private var locale
    @State private var pickingWeek = false
    /// `nil` = the current week.
    @State private var selectedWeekStart: Date?

    private var palette: PomodoroHeatmapPalette { paletteOption.core }
    private var calendar: Calendar { Calendar.current }

    private var weekStart: Date {
        selectedWeekStart ?? PomodoroHeatmapMath.startOfWeek(Date(), calendar: calendar)
    }

    private var dailyTotals: [Double] {
        PomodoroHeatmapMath.dailyTotals(sessions: model.allSessions, weekStart: weekStart, calendar: calendar)
    }

    private var weekTotal: Double { dailyTotals.reduce(0, +) }

    var body: some View {
        Group {
            if pickingWeek {
                weekPicker.transition(.opacity)
            } else {
                stats.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.22), value: pickingWeek)
    }

    // MARK: - Stats panel

    private var stats: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.22)) { pickingWeek = true }
            } label: {
                HStack(spacing: 4) {
                    Text(weekRangeText(weekStart))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("选择要查看的周"))

            Text("\(L("本周总计")) \(durationText(weekTotal))")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    dayCell(index)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func dayCell(_ index: Int) -> some View {
        let level = PomodoroHeatmapMath.intensityLevel(seconds: dailyTotals[index])
        let color = PomodoroHeatmapMath.color(forLevel: level, palette: palette)
        return VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.rgb.swiftUIColor.opacity(color.alpha))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .frame(width: 20, height: 20)
            Text(L(weekdayKeys[index]))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(index == todayIndex ? 0.95 : 0.55))
        }
    }

    private var weekdayKeys: [String] {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    }

    private var todayIndex: Int {
        let mondayOffset = (calendar.component(.weekday, from: Date()) + 5) % 7
        return mondayOffset
    }

    // MARK: - Week picker panel

    private var weekPicker: some View {
        VStack(spacing: 6) {
            Text(L("选择要查看的周"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            PomodoroWeekWheel(weekStarts: pickerWeeks, selection: selectedWeek,
                              rangeText: weekRangeText)

            Button {
                selectedWeekStart = nil
                withAnimation(.smooth(duration: 0.22)) { pickingWeek = false }
            } label: {
                Text(L("返回本周"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PomodoroTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var selectedWeek: Binding<Date> {
        Binding(get: { weekStart },
                set: { newValue in
                    selectedWeekStart = newValue
                    withAnimation(.smooth(duration: 0.22)) { pickingWeek = false }
                })
    }

    /// The current week plus up to twelve before it, oldest first.
    private var pickerWeeks: [Date] {
        let current = PomodoroHeatmapMath.startOfWeek(Date(), calendar: calendar)
        return (0...PomodoroHeatmapMath.weekPickerHistory).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -7 * back, to: current)
        }
    }

    // MARK: - Formatting

    private func weekRangeText(_ start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let style = Date.FormatStyle().month().day().locale(locale)
        return "\(start.formatted(style)) - \(end.formatted(style))"
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: L("%lld h %02lld m"), hours, minutes)
    }
}
