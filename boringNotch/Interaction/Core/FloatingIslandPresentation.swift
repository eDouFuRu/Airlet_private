import Foundation

/// A floating island has one compact line, so events replace rather than stack on it.
enum FloatingIslandContent: Equatable, Sendable {
    case hud, power, notification, completion, song, lyric, pomodoro, music, idle

    static func select(hud: Bool, power: Bool, notification: Bool, completion: Bool,
                       song: Bool, lyric: Bool, pomodoro: Bool, music: Bool) -> Self {
        if hud { return .hud }
        if power { return .power }
        if notification { return .notification }
        if completion { return .completion }
        if song { return .song }
        if lyric { return .lyric }
        if pomodoro { return .pomodoro }
        if music { return .music }
        return .idle
    }

    var isTransient: Bool {
        switch self {
        case .hud, .power, .notification, .completion, .song: return true
        case .lyric, .pomodoro, .music, .idle: return false
        }
    }
}

enum FloatingIslandMetrics {
    static func width(textWidth: CGFloat, decorationWidth: CGFloat, minimum: CGFloat = 120,
                      maximum: CGFloat, expandsToFit: Bool = true) -> CGFloat {
        let measured = textWidth.isFinite ? max(0, textWidth) : 0
        let decoration = decorationWidth.isFinite ? max(0, decorationWidth) : 0
        let limit = maximum.isFinite ? max(1, maximum) : 640
        let base = minimum.isFinite ? max(1, minimum) : 120
        let floor = min(limit, base)
        return expandsToFit ? min(limit, max(floor, ceil(measured + decoration))) : floor
    }

    static func fontSize(height: CGFloat) -> CGFloat { min(13, max(1, height - 4)) }
    static func iconSize(height: CGFloat) -> CGFloat { min(22, max(1, height - 4)) }
}
