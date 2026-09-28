import SwiftUI

/// The compact HUD has no camera gap and never adds a second row.
struct FloatingSystemHUD: View {
    @Environment(\.islandAppearance) private var appearance
    let state: SystemHUDState
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.symbolName)
                .frame(width: FloatingIslandMetrics.iconSize(height: height))
            Text(L(state.titleKey)).lineLimit(1).fixedSize()
            if let error = state.error {
                Text(L(error)).foregroundStyle(.orange).lineLimit(1)
            } else if state.activeKind == .mic {
                Text(L(state.value == 0 ? "muted" : "unmuted"))
                    .lineLimit(1)
            } else {
                GeometryReader { geometry in
                    Capsule().fill(appearance.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(appearance.primary)
                                .frame(width: geometry.size.width * state.value)
                        }
                }
                .frame(minWidth: 40, idealWidth: 100, maxWidth: 140)
                .frame(height: min(5, max(2, height / 4)))
                Text("\(Int((state.value * 100).rounded()))%")
                    .monospacedDigit().fixedSize()
            }
        }
        .font(.system(size: FloatingIslandMetrics.fontSize(height: height), weight: .medium))
        .foregroundStyle(appearance.primary)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }
}
