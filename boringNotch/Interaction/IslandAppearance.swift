import AppKit
import SwiftUI

/// Shared contrast choices for an attached black notch and a floating glass island.
/// Child pages inherit this value from the shell rather than choosing a material.
struct IslandAppearance {
    let isFloating: Bool
    let colorScheme: ColorScheme

    var primary: Color { isFloating && colorScheme == .light ? .black : .white }
    var secondary: Color { primary.opacity(0.65) }
    var tertiary: Color { primary.opacity(0.4) }
    var controlFill: Color { primary.opacity(isFloating ? 0.07 : 0.08) }
    var border: Color { primary.opacity(isFloating ? 0.14 : 0.12) }
    var track: Color { primary.opacity(0.2) }
    var popoverFill: Color {
        isFloating ? Color(nsColor: .windowBackgroundColor) : Color(white: 0.15)
    }

    /// Album artwork can be nearly white; lifting its brightness is only suitable
    /// for the old black surface. Preserve its hue while darkening light-mode ink.
    func artworkTint(_ color: Color, minimumBrightness: CGFloat = 0.6) -> Color {
        guard isFloating && colorScheme == .light else {
            return color.ensureMinimumBrightness(factor: minimumBrightness)
        }
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return primary }
        let peak = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        let scale = peak > 0.5 ? 0.5 / peak : 1
        return Color(red: rgb.redComponent * scale,
                     green: rgb.greenComponent * scale,
                     blue: rgb.blueComponent * scale,
                     opacity: rgb.alphaComponent)
    }
}

private struct IslandAppearanceKey: EnvironmentKey {
    static let defaultValue = IslandAppearance(isFloating: false, colorScheme: .dark)
}

extension EnvironmentValues {
    var islandAppearance: IslandAppearance {
        get { self[IslandAppearanceKey.self] }
        set { self[IslandAppearanceKey.self] = newValue }
    }
}
