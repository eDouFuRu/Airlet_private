import Foundation

/// Opacity controls the backing and a light veil, never the native clear lens.
/// The clear material avoids the dark regular-glass sheet seen over full-screen
/// apps while keeping the optical edge visible at the transparent end.
struct FloatingGlassTransparency: Equatable, Sendable {
    static let original = 0.5

    let backingOpacity: Double
    let veilOpacity: Double
    let legacyMaterialOpacity: Double

    init(_ requestedValue: Double) {
        let value = requestedValue.isFinite
            ? min(1, max(0, requestedValue)) : Self.original
        backingOpacity = value >= Self.original
            ? 0 : (Self.original - value) * 1.7
        veilOpacity = 0.03 + 0.24 * (1 - value)
        legacyMaterialOpacity = value <= Self.original
            ? 1 : 1 - (value - Self.original) * 1.5
    }
}
