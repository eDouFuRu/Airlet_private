import Defaults
import SwiftUI

/// Shared period selector. The full-page views keep the same shell proposal as the timer.
struct PomodoroStatistics: View {
    @ObservedObject var model: PomodoroModel
    @Binding var period: PomodoroStatsPeriod
    @Default(.pomodoroHeatmapPalette) private var paletteOption
    @Environment(\.locale) private var locale
    @State private var selectedDate = Date()
    @State private var draft: Date?
    @State private var picking = false
    init(model: PomodoroModel, period: Binding<PomodoroStatsPeriod>, selectedDate: Date = Date(), picking: Bool = false) {
        self.model = model
        _period = period
        _selectedDate = State(initialValue: selectedDate)
        _picking = State(initialValue: picking)
        _draft = State(initialValue: picking ? period.wrappedValue.start(containing: selectedDate) : nil)
    }

    private var calendar: Calendar { .current }
    private var date: Date { period == .week ? Date() : selectedDate }
    private var totals: [Double] { period.totals(sessions: model.allSessions, containing: date) }
    private var dates: [Date] { period.dates(containing: date) }
    private var current: Bool { period.start(containing: date) == period.start(containing: Date()) }
    private var label: String {
        switch period {
        case .week: return "本周总计"
        case .month: return current ? "本月总计" : "该月总计"
        case .year: return current ? "本年总计" : "该年总计"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if period == .week {
                HStack {
                    Text(L(label)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                    selector
                }.frame(height: 18)
                PomodoroTotalText(total: totals.reduce(0, +), palette: paletteOption.core)
                    .frame(height: 30)
            } else {
                HStack(spacing: 10) {
                    Button { draft = period.start(containing: date); picking = true } label: {
                        HStack(spacing: 4) {
                            Text(dateTitle(date)).font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }.foregroundStyle(.white.opacity(0.9))
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text(L(label)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    PomodoroTotalText(total: totals.reduce(0, +), palette: paletteOption.core)
                        .frame(maxWidth: 190)
                    selector
                }.frame(height: 30)
            }
            if picking {
                periodPicker
            } else {
                PomodoroBarChart(dates: dates, totals: totals, period: period, palette: paletteOption.core)
                    .id("\(period.rawValue)-\(period.start(containing: date).timeIntervalSince1970)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: period) { _, _ in selectedDate = Date(); picking = false; draft = nil }
    }

    private var selector: some View {
        HStack(spacing: 1) {
            ForEach(PomodoroStatsPeriod.allCases, id: \.self) { item in
                Button { period = item } label: {
                    Text(L(item.titleKey)).font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 18)
                        .foregroundStyle(.white.opacity(period == item ? 1 : 0.45))
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(period == item ? 0.16 : 0)))
                }.buttonStyle(.plain)
                .accessibilityLabel(L(item == .week ? "周视图" : item == .month ? "月视图" : "年视图"))
                .accessibilityAddTraits(period == item ? .isSelected : [])
            }
        }
    }

    private var choices: [Date] {
        let now = period.start(containing: Date())
        let earliest = model.allSessions.map(\.startedAt).min() ?? now
        let fallback = calendar.date(byAdding: period.component, value: period == .month ? -24 : -10, to: now) ?? now
        let first = period.start(containing: min(earliest, fallback))
        let count = calendar.dateComponents([period.component], from: first, to: now).value(for: period.component) ?? 0
        return (0...max(0, count)).compactMap { calendar.date(byAdding: period.component, value: $0, to: first) }
    }

    private var periodPicker: some View {
        HStack(spacing: 18) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(choices, id: \.self) { item in
                        Button { draft = item } label: {
                            Text(dateTitle(item)).font(.system(size: 13, weight: item == draft ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(item == draft ? 1 : 0.4))
                                .frame(maxWidth: .infinity).frame(height: 24)
                        }.buttonStyle(.plain)
                    }
                }.scrollTargetLayout()
            }
            .contentMargins(.vertical, 24, for: .scrollContent)
            .frame(height: 72)
            .scrollPosition(id: $draft, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            HStack(spacing: 12) {
                Button(L(period == .month ? "返回本月" : "返回本年")) { selectedDate = Date(); picking = false }
                Button(L("确认")) { if let draft { selectedDate = draft }; picking = false }
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .foregroundStyle(paletteOption.core.baseRGB.swiftUIColor)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dateTitle(_ date: Date) -> String {
        if period == .year { return date.formatted(.dateTime.year().locale(locale)) }
        return date.formatted(.dateTime.year().month(.wide).locale(locale))
    }
}
