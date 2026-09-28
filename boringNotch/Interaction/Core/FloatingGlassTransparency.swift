import Foundation

/// The midpoint preserves the original clear-glass appearance. Moving left adds
/// a translucent backing; moving right reduces only the shell's glass strength.
/// Content is intentionally not part of these opacity values.
struct FloatingGlassTransparency: Equatable, Sendable {
    static let original = 0.5

    let glassOpacity: Double
    let backingOpacity: Double
    let rimOpacity: Double

    init(_ requestedValue: Double) {
        let value = requestedValue.isFinite
            ? min(1, max(0, requestedValue)) : Self.original
        glassOpacity = value <= Self.original
            ? 1 : 1 - (value - Self.original) * 1.5
        backingOpacity = value >= Self.original
            ? 0 : (Self.original - value) * 1.7
        rimOpacity = 0.2 + 0.2 * glassOpacity
    }
}
