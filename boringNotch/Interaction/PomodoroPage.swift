import Defaults
import SwiftUI

/// The 番茄钟 page: topic capsule + mode/duration controls on the left, the progress ring
/// in the middle, and the weekly heatmap on the right. Laid out inside the same expanded
/// footprint as the home and shelf pages.
struct PomodoroPage: View {
    @Environment(\.islandAppearance) private var islandAppearance
    @ObservedObject private var model: PomodoroModel
    @Default(.pomodoroCountdownRingFills) private var countdownRingFills
    @Default(.pomodoroHeatmapPalette) private var paletteOption
    @State private var editingTopic = false
    @State private var statsPeriod: PomodoroStatsPeriod = .week
    @ObservedObject private var visibility = IslandVisibility.shared
    @EnvironmentObject private var island: BoringViewModel

    init(model: PomodoroModel? = nil) {
        self.model = model ?? .shared
    }

    var body: some View {
        // Column widths must fit the header's proposal (visibleWidth − 2×31 ≈ 578): a page
        // wider than that inflates the morphing group and drags the tab bar sideways.
        Group {
            if statsPeriod == .week {
                HStack(alignment: .top, spacing: 12) {
                    leftColumn.frame(width: 196)
                    centerColumn.frame(width: 156)
                    PomodoroStatistics(model: model, period: $statsPeriod).frame(width: 168)
                }
            } else {
                PomodoroStatistics(model: model, period: $statsPeriod)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 4) {
            topicRow.frame(height: 30)
            middleZone.frame(height: 64)
            actionRow.frame(height: 30)
        }
    }

    private var topicRow: some View {
        HStack(spacing: 6) {
            Button {
                editingTopic = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(islandAppearance.primary.opacity(model.topic.isEmpty ? 0.35 : 0.6))
                    Text(model.topic.isEmpty ? L("本次专注主题") : model.topic)
                        .font(.system(size: 12, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(model.topic.isEmpty ? islandAppearance.primary.opacity(0.4) : islandAppearance.primary.opacity(0.9))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 15).fill(islandAppearance.controlFill))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(islandAppearance.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .opacity(model.isBusy ? 0.7 : 1)
            .popover(isPresented: $editingTopic, arrowEdge: .bottom) {
                TopicEditorPopover()
            }
            .notchHoldsOpenWhilePopoverPresented($editingTopic)
            .help(L("本次专注主题"))

            Button {
                SettingsWindowController.shared.showTimerSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(islandAppearance.primary.opacity(0.5))
                    .frame(width: 22, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("番茄钟设置"))
        }
    }

    /// Mode buttons while unselected or in count-up mode; the hour/minute wheels take the
    /// same slot once countdown is chosen (switching back requires 取消, per spec).
    @ViewBuilder
    private var middleZone: some View {
        if model.isBusy {
            VStack(spacing: 3) {
                Text(model.mode == .countup ? L("正计时") : L("倒计时"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(islandAppearance.primary.opacity(0.9))
                Text(busyDurationText)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(islandAppearance.primary.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.mode == .countdown {
            HStack(spacing: 10) {
                PomodoroLoopingWheel(values: Array(0...PomodoroSessionCore.maximumHour),
                                     selection: hourBinding,
                                     format: { String(format: L("%lld h"), $0) }, rowHeight: 20)
                PomodoroLoopingWheel(values: Array(0...PomodoroSessionCore.maximumMinute),
                                     selection: minuteBinding,
                                     format: { String(format: L("%lld m"), $0) }, rowHeight: 20)
            }
            .padding(.vertical, 2)
        } else {
            HStack(spacing: 8) {
                modeButton(.countdown, title: L("倒计时"))
                modeButton(.countup, title: L("正计时"))
            }
        }
    }

    private var busyDurationText: String {
        guard model.mode == .countdown else { return L("不限时长") }
        return String(format: L("%lld h %02lld m"), model.plannedSeconds / 3600,
                      (model.plannedSeconds % 3600) / 60)
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { model.plannedSeconds / 3600 },
                set: { model.setDuration(hours: $0, minutes: model.plannedSeconds % 3600 / 60) })
    }

    private var minuteBinding: Binding<Int> {
        Binding(get: { model.plannedSeconds % 3600 / 60 },
                set: { model.setDuration(hours: model.plannedSeconds / 3600, minutes: $0) })
    }

    private func modeButton(_ mode: PomodoroMode, title: String) -> some View {
        let isSelected = model.mode == mode
        return Button {
            model.selectMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : islandAppearance.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(isSelected ? PomodoroTheme.accent.opacity(0.85) : islandAppearance.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(islandAppearance.primary.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .idle:
                capsuleButton(title: L("开始"), filled: true, enabled: model.canStart) { model.start() }
                capsuleButton(title: L("取消"), filled: false,
                              enabled: model.mode != nil) { model.cancelConfiguration() }
            case .running:
                capsuleButton(title: L("暂停"), filled: true, enabled: true) { model.pause() }
                capsuleButton(title: L("结束"), filled: false, enabled: true) { model.end() }
            case .paused:
                capsuleButton(title: L("继续"), filled: true, enabled: true) { model.resume() }
                capsuleButton(title: L("结束"), filled: false, enabled: true) { model.end() }
            }
        }
    }

    private func capsuleButton(title: String, filled: Bool, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle((filled ? Color.white : islandAppearance.primary).opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(filled ? PomodoroTheme.accent.opacity(enabled ? 0.9 : 0.4)
                                     : islandAppearance.controlFill)
                )
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Center column

    private var centerColumn: some View {
        PomodoroRingView(presentation: model.ringPresentation,
                         baseRGB: paletteOption.core.baseRGB,
                         countdownFills: countdownRingFills,
                         isVisible: visibility.isAvailable && island.notchState == .open,
                         diameter: 128) {
            if model.isBusy {
                Text(model.clockText)
                    .font(.system(size: model.clockText.count > 5 ? 15 : 19, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(islandAppearance.primary.opacity(model.phase == .paused ? 0.45 : 0.95))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
            } else {
                Image("PomodoroTomato")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityLabel(L("番茄钟"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The topic editor lives in a popover because the island window never becomes key and an
/// inline text field could not receive keyboard input (including IME composition).
private struct TopicEditorPopover: View {
    @ObservedObject private var model = PomodoroModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            TextField(L("本次专注主题"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Button(L("清除")) {
                    _ = model.setTopic("")
                    dismiss()
                }
                Spacer()
                Button(L("完成"), action: commit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 250)
        .onAppear {
            draft = model.topic
            focused = true
        }
    }

    private func commit() {
        _ = model.setTopic(draft)
        dismiss()
    }
}
