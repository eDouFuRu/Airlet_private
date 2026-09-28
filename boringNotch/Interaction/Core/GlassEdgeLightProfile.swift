import Foundation

/// Ambient light on the two sides of a glass edge. Values are linearized
/// luminance in 0...1, sampled from the desktop with Airlet's windows excluded.
struct GlassEdgeLightPair: Equatable, Sendable {
    let outside: Double
    let inside: Double
}

/// Eight positions clockwise from the top: top, top-right, right, bottom-right,
/// bottom, bottom-left, left, top-left. The same order is used by the rim shader.
struct GlassEdgeLightProfile: Equatable, Sendable {
    static let neutral = GlassEdgeLightProfile(levels: Array(repeating: 0.5, count: 8))

    let levels: [Double]

    private init(levels: [Double]) { self.levels = levels }

    init(pairs: [GlassEdgeLightPair]) {
        guard pairs.count == 8 else { self = .neutral; return }
        levels = pairs.map { pair in
            let outside = Self.clamp(pair.outside)
            let inside = Self.clamp(pair.inside)
            // A bright exterior against a dark interior concentrates light;
            // the opposite edge darkens. Ambient luminance contributes gently,
            // so a uniform white or black desktop does not invent a moving glint.
            return Self.clamp(0.45 + 0.34 * (outside - inside)
                              + 0.2 * (outside - 0.5))
        }
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
}
