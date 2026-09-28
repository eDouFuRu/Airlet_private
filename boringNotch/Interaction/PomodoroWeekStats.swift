import SwiftUI

/// Value-driven statistics, shared by the live page and isolated visual fixtures.
struct PomodoroWeekStats: View {
    @Environment(\.islandAppearance) private var islandAppearance
    let weekStart: Date
    let dailyTotals: [Double]
    let palette: PomodoroHeatmapPalette
    var calendar: Calendar = .current
    var today = Date()
    var previewHoveredDay: Int?
    var selectWeek: () -> Void = {}
    @Environment(\.locale) private var locale
    @State private var hoveredDay: Int?

    private var activeDay: Int? { previewHoveredDay ?? hoveredDay }
    private var isCurrentWeek: Bool {
        calendar.isDate(weekStart, inSameDayAs: PomodoroHeatmapMath.startOfWeek(today, calendar: calendar))
    }
    private var total: Int { Int(max(0, dailyTotals.reduce(0, +))) }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            summary
            Spacer(minLength: 8)
            heatmap

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: weekStart) { _, _ in hoveredDay = nil }
        .onDisappear { hoveredDay = nil }
    }

    private var weekHeader: some View {
            Button(action: selectWeek) {
                HStack(spacing: 4) {
                    Text(rangeText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(islandAppearance.primary.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("选择要查看的周"))

    }

    private var summary: some View {
        VStack(spacing: 0) {
            Text(L(isCurrentWeek ? "本周总计" : "该周总计"))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(islandAppearance.primary.opacity(0.55))
                .padding(.top, 7)
            (
                Text("\(total / 3600)").font(.system(size: 24, weight: .semibold, design: .rounded))
                + Text(" \(L("h")) ").font(.system(size: 11, weight: .medium, design: .rounded))
                + Text(String(format: "%02d", total % 3600 / 60)).font(.system(size: 24, weight: .semibold, design: .rounded))
                + Text(" \(L("m"))").font(.system(size: 11, weight: .medium, design: .rounded))
            )
            .monospacedDigit()
            .foregroundStyle(palette.baseRGB.swiftUIColor)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 32)
            .accessibilityLabel("\(L(isCurrentWeek ? "本周总计" : "该周总计")) \(duration(total))")

        }
    }

    private var heatmap: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in dayCell(index) }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if let index = activeDay {
                GeometryReader { proxy in
                    tooltip(index, columnWidth: proxy.size.width)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func tooltip(_ index: Int, columnWidth: CGFloat) -> some View {
        let width: CGFloat = min(156, columnWidth)
        let cellCenter: CGFloat = (columnWidth - 164) / 2 + 10 + CGFloat(index) * 24
        let x: CGFloat = min(max(0, cellCenter - width / 2), max(0, columnWidth - width))
        return VStack(spacing: 3) {
            Text(dateLabel(index)).font(.system(size: 10, weight: .medium))
                .foregroundStyle(islandAppearance.primary.opacity(0.7))
            Text(duration(seconds(index))).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(islandAppearance.primary)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(width: width, height: 42)
        .background(RoundedRectangle(cornerRadius: 8).fill(islandAppearance.popoverFill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(islandAppearance.primary.opacity(0.18), lineWidth: 1))
        .offset(x: x, y: -48)
    }

    private func dayCell(_ index: Int) -> some View {
        let day = date(index)
        let color = PomodoroHeatmapMath.color(forLevel: PomodoroHeatmapMath.intensityLevel(seconds: dailyTotals.indices.contains(index) ? dailyTotals[index] : 0), palette: palette)
        return VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.rgb.swiftUIColor.opacity(color.alpha))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(islandAppearance.primary.opacity(activeDay == index ? 0.85 : 0.1), lineWidth: activeDay == index ? 1 : 0.5))
                .frame(width: 20, height: 20)
            Text(L(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(islandAppearance.primary.opacity(calendar.isDate(day, inSameDayAs: today) ? 0.95 : 0.55))
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredDay = index }
            else if hoveredDay == index { hoveredDay = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dateLabel(index)), \(duration(seconds(index)))")
    }

    private func seconds(_ index: Int) -> Int { dailyTotals.indices.contains(index) ? Int(max(0, dailyTotals[index])) : 0 }
    private func date(_ index: Int) -> Date { calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart }
    private func dateLabel(_ index: Int) -> String {
        date(index).formatted(.dateTime.month().day().weekday(.wide).locale(locale))
    }
    private var rangeText: String {
        let style = Date.FormatStyle().month().day().locale(locale)
        return "\(weekStart.formatted(style)) - \(date(6).formatted(style))"
    }
    private func duration(_ seconds: Int) -> String {
        if seconds == 0 { return L("0 秒") }
        if seconds < 60 { return String(format: L("%lld 秒"), seconds) }
        if seconds < 3600 { return String(format: L("%lld 分 %02lld 秒"), seconds / 60, seconds % 60) }
        return String(format: L("%lld 小时 %02lld 分 %02lld 秒"), seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}

struct PomodoroTotalText: View {
    let total: Double
    let palette: PomodoroHeatmapPalette
    private var seconds: Int { Int(max(0, total)) }
    var body: some View {
        (Text("\(seconds / 3600)").font(.system(size: 24, weight: .semibold, design: .rounded))
         + Text(" \(L("h")) ").font(.system(size: 11, weight: .medium))
         + Text(String(format: "%02d", seconds % 3600 / 60)).font(.system(size: 24, weight: .semibold, design: .rounded))
         + Text(" \(L("m"))").font(.system(size: 11, weight: .medium)))
        .monospacedDigit().foregroundStyle(palette.baseRGB.swiftUIColor)
        .lineLimit(1).minimumScaleFactor(0.65)
    }
}

private struct PomodoroBarFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct PomodoroBarChart: View {
    @Environment(\.islandAppearance) private var islandAppearance
    let dates: [Date]
    let totals: [Double]
    let period: PomodoroStatsPeriod
    let palette: PomodoroHeatmapPalette
    @Environment(\.locale) private var locale
    @State private var frames: [Int: CGRect] = [:]
    @State private var hovered: Int?
    @Namespace private var viewport
    private var ratios: [Double] { PomodoroStatsPeriod.ratios(totals) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cellWidth = width / CGFloat(period == .month ? 21 : max(1, dates.count))
            Group {
                if period == .month {
                    ScrollView(.horizontal, showsIndicators: false) {
                        bars(cellWidth: cellWidth, height: proxy.size.height, viewportWidth: width)
                    }
                    .defaultScrollAnchor(.leading)
                } else {
                    bars(cellWidth: cellWidth, height: proxy.size.height, viewportWidth: width)
                }
            }
            .coordinateSpace(name: viewport)
            .onPreferenceChange(PomodoroBarFrames.self) { newFrames in
                guard period == .month, newFrames != frames else { return }
                if let hovered, frames[hovered] != newFrames[hovered] { self.hovered = nil }
                frames = newFrames
            }
            .overlay(alignment: .topLeading) {
                if let index = hovered, dates.indices.contains(index) {
                    let tooltipWidth = min(width, 165.0)
                    let center = period == .month
                        ? (frames[index]?.midX ?? width / 2)
                        : (CGFloat(index) + 0.5) * cellWidth
                    VStack(spacing: 2) {
                        Text(dateTitle(index)).font(.system(size: 10)).foregroundStyle(islandAppearance.primary.opacity(0.7))
                        Text(duration(index)).font(.system(size: 11, weight: .semibold)).foregroundStyle(islandAppearance.primary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: tooltipWidth, height: 36)
                    .background(RoundedRectangle(cornerRadius: 7).fill(islandAppearance.popoverFill))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(islandAppearance.primary.opacity(0.18)))
                    .offset(x: min(max(0, center - tooltipWidth / 2), max(0, width - tooltipWidth)))
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .onDisappear { hovered = nil }
    }

    private func bars(cellWidth: CGFloat, height: CGFloat, viewportWidth: CGFloat) -> some View {
        let visible = frames.filter { $0.value.maxX > 0.5 && $0.value.minX < viewportWidth - 0.5 }.keys.sorted()
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(dates.indices, id: \.self) { index in
                let ratio = ratios.indices.contains(index) ? ratios[index] : 0
                let edge = period == .month && ((index == visible.first && index != 0) || (index == visible.last && index != dates.count - 1))
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if ratio > 0 {
                            RoundedRectangle(cornerRadius: period == .year ? 4 : 2)
                                .fill(palette.baseRGB.swiftUIColor.opacity(0.22 + 0.78 * ratio))
                                .frame(width: max(1, cellWidth * (period == .year ? 0.55 : 0.68)), height: max(0, height - 17) * ratio)
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(islandAppearance.primary.opacity(hovered == index ? 0.8 : 0), lineWidth: 1))
                        }
                    }.frame(height: max(0, height - 17))
                    Text(label(index)).font(.system(size: 9, design: .rounded).monospacedDigit())
                        .foregroundStyle(islandAppearance.primary.opacity(0.65)).frame(height: 14)
                }
                .frame(width: cellWidth, height: height)
                .opacity(edge ? 0.35 : 1)
                .contentShape(Rectangle())
                .background {
                    if period == .month {
                        GeometryReader { geometry in
                            Color.clear.preference(key: PomodoroBarFrames.self,
                                                   value: [index: geometry.frame(in: .named(viewport))])
                        }
                    }
                }
                .onHover { inside in if inside { hovered = index } else if hovered == index { hovered = nil } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dateTitle(index)), \(duration(index))")
            }
        }
    }

    private func label(_ index: Int) -> String {
        if period == .week { return L(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][index]) }
        return String(Calendar.current.component(period == .year ? .month : .day, from: dates[index]))
    }
    private func dateTitle(_ index: Int) -> String {
        if period == .year { return dates[index].formatted(.dateTime.year().month(.wide).locale(locale)) }
        return dates[index].formatted(.dateTime.month().day().weekday(.wide).locale(locale))
    }
    private func duration(_ index: Int) -> String {
        let seconds = totals.indices.contains(index) ? Int(max(0, totals[index])) : 0
        if seconds == 0 { return L("0 秒") }
        if seconds < 60 { return String(format: L("%lld 秒"), seconds) }
        if seconds < 3600 { return String(format: L("%lld 分 %02lld 秒"), seconds / 60, seconds % 60) }
        return String(format: L("%lld 小时 %02lld 分 %02lld 秒"), seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}
