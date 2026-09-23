import Defaults
import SwiftUI

struct PomodoroSettings: View {
    @Default(.showPomodoroTimerOnClosed) private var showOnClosed
    @Default(.pomodoroHeatmapPalette) private var paletteOption

    @Default(.pomodoroCountdownRingFills) private var countdownRingFills

    var body: some View {
        Form {
            Section {
                Picker("圆环方向", selection: $countdownRingFills) {
                    Text("从空到满").tag(true)
                    Text("从满到空").tag(false)
                }
                Text("仅影响倒计时圆环，正计时仍每小时累积一圈。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("倒计时圆环")
            }

            Section {
                Picker("热力图配色", selection: $paletteOption) {
                    ForEach(PomodoroHeatmapPaletteOption.allCases, id: \.self) { option in
                        Text(L(option.core.nameKey)).tag(option)
                    }
                }
                PalettePreview(palette: paletteOption.core)
                Text("热力图按当日专注总时长由浅到深着色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("专注热力图")
            }

            Section {
                Defaults.Toggle(key: .showPomodoroTimerOnClosed) {
                    Text("闭合时显示番茄钟计时")
                }
            } header: {
                Text("小岛")
            }
        }
        .navigationTitle(Text(verbatim: L("番茄钟")))
    }
}

/// A live preview of the five intensity chips for the chosen palette.
private struct PalettePreview: View {
    let palette: PomodoroHeatmapPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0...4, id: \.self) { level in
                let color = PomodoroHeatmapMath.color(forLevel: level, palette: palette)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.rgb.swiftUIColor.opacity(color.alpha))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                    )
                    .frame(width: 22, height: 18)
            }
            Spacer()
        }
    }
}
