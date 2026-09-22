import Defaults
import SwiftUI

/// A vertical looping wheel in the spirit of the calendar's `WheelPicker`:
/// `scrollPosition(id:anchor:.center)` + `.viewAligned` snapping + tap-to-select, wrapped
/// around a tripled data set so the wheel never hits an end. When scrolling settles on an
/// outer copy, the position silently re-anchors to the middle copy with animations
/// disabled, making the loop seamless.
struct PomodoroLoopingWheel: View {
    let values: [Int]
    @Binding var selection: Int
    var format: (Int) -> String
    var rowHeight: CGFloat = 24

    private struct Item: Hashable {
        let value: Int
        let copy: Int
    }

    @State private var position: Item?
    @State private var haptics = false

    private var items: [Item] {
        (0..<3).flatMap { copy in values.map { Item(value: $0, copy: copy) } }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    row(item)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: rowHeight * 3)
        .scrollPosition(id: $position, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onScrollPhaseChange { _, phase in
            guard phase == .idle else { return }
            reanchorSilently()
        }
        .onChange(of: position) { _, newItem in
            guard let item = newItem else { return }
            if item.value != selection {
                selection = item.value
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
        }
        .onChange(of: selection) { _, newValue in
            guard position?.value != newValue else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                position = Item(value: newValue, copy: 1)
            }
        }
        .onAppear {
            if position == nil { position = Item(value: selection, copy: 1) }
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.5),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func currentCopy() -> Int {
        position?.copy ?? 1
    }

    private func row(_ item: Item) -> some View {
        let isSelected = item == position
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                position = Item(value: item.value, copy: currentCopy())
            }
        } label: {
            Text(format(item.value))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Jumping from an outer copy back to the middle one must be invisible: no animation,
    /// no haptic, and the value is unchanged so the selection callback stays quiet.
    private func reanchorSilently() {
        guard let item = position, item.copy != 1 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position = Item(value: item.value, copy: 1)
        }
    }
}

/// Flat (non-looping) vertical wheel for picking a past week to inspect. Future weeks
/// have no data, so the list runs oldest → current with no wrap-around.
struct PomodoroWeekWheel: View {
    /// Mondays, oldest first; the last entry is the current week.
    let weekStarts: [Date]
    @Binding var selection: Date
    var rowHeight: CGFloat = 26
    var rangeText: (Date) -> String

    @State private var position: Int?
    @State private var haptics = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(weekStarts.enumerated()), id: \.offset) { index, weekStart in
                    row(index, weekStart)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: rowHeight * 3)
        .scrollPosition(id: $position, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.vertical, rowHeight)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: position) { _, newIndex in
            guard let index = newIndex, weekStarts.indices.contains(index) else { return }
            let weekStart = weekStarts[index]
            if !calendar.isDate(weekStart, inSameDayAs: selection) {
                selection = weekStart
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
        }
        .onAppear {
            if position == nil {
                position = weekStarts.lastIndex { calendar.isDate($0, inSameDayAs: selection) }
            }
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.5),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var calendar: Calendar { Calendar.current }

    private func row(_ index: Int, _ weekStart: Date) -> some View {
        let isSelected = position == index
        let isCurrent = calendar.isDateInToday(weekStart.addingTimeInterval(3 * 86_400))
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { position = index }
        } label: {
            HStack(spacing: 5) {
                Text(rangeText(weekStart))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded).monospacedDigit())
                if isCurrent {
                    Text(L("This week"))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Capsule().fill(PomodoroTheme.accent.opacity(0.85)))
                        .foregroundStyle(.white)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
