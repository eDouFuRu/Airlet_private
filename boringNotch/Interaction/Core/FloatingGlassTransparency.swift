import Foundation

/// The upper half clears the centre of the lens without weakening its optical
/// edge. Foreground content never shares these opacity values.
struct FloatingGlassTransparency: Equatable, Sendable {
    static let original = 0.5

    let backingOpacity: Double
    let veilOpacity: Double
    let nativeGlassCenterOpacity: Double
    let legacyMaterialOpacity: Double

    init(_ requestedValue: Double) {
        let value = requestedValue.isFinite
            ? min(1, max(0, requestedValue)) : Self.original
        let clearProgress = max(0, (value - Self.original) / (1 - Self.original))
        backingOpacity = value >= Self.original
            ? 0 : (Self.original - value) * 1.7
        veilOpacity = value <= Self.original
            ? 0.03 + 0.24 * (1 - value) : 0.15 * (1 - clearProgress)
        nativeGlassCenterOpacity = 1 - 0.65 * clearProgress
        legacyMaterialOpacity = 1 - 0.88 * clearProgress
    }
}

/// Keep the native material at full strength in a feathered inner band. Scaling
/// this band down with the capsule prevents its two edges covering the centre.
struct FloatingGlassLensMetrics: Equatable, Sendable {
    let edgeWidth: Double
    let featherRadius: Double

    init(height: Double) {
        let height = height.isFinite ? max(0, height) : 0
        edgeWidth = min(24, height * 0.18)
        featherRadius = edgeWidth * 0.4
    }
}
