import AppKit

/// Shared tomato template for the menu bar and the island's navigation tab.
///
/// Prefers the `TomatoGlyph` asset when one is bundled (the user-supplied monochrome
/// artwork); otherwise falls back to the code-drawn placeholder below so the app builds
/// and ships before the final art lands.
enum TomatoStatusIcon {
    static let image: NSImage = {
        if let glyph = NSImage(named: "TomatoGlyph") {
            glyph.isTemplate = true
            return normalized(glyph)
        }
        return drawnPlaceholder
    }()

    /// Menu-bar template images render at roughly 18pt, whatever their source size.
    private static func normalized(_ source: NSImage) -> NSImage {
        let size = NSSize(width: 19, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let aspect = source.size.width / max(source.size.height, 1)
            let target: NSSize
            if aspect >= 1 {
                target = NSSize(width: size.width, height: size.width / aspect)
            } else {
                target = NSSize(width: size.height * aspect, height: size.height)
            }
            source.draw(in: NSRect(x: (size.width - target.width) / 2,
                                   y: (size.height - target.height) / 2,
                                   width: target.width, height: target.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let drawnPlaceholder: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            // Body: a slightly squat ellipse with rounded joins reads as a tomato outline.
            let body = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 1.6, width: 14, height: 12.6))
            body.lineWidth = 1.35
            body.lineJoinStyle = .round
            body.stroke()

            // Stem, then two calyx leaves sweeping out of the stem base.
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 9.5, y: 14.1))
            stem.line(to: NSPoint(x: 9.5, y: 16.5))
            stem.lineWidth = 1.35
            stem.lineCapStyle = .round
            stem.stroke()

            let leaves = NSBezierPath()
            leaves.move(to: NSPoint(x: 9.5, y: 14.3))
            leaves.curve(to: NSPoint(x: 5.9, y: 15.7),
                         controlPoint1: NSPoint(x: 8.1, y: 14.3),
                         controlPoint2: NSPoint(x: 6.9, y: 14.8))
            leaves.move(to: NSPoint(x: 9.5, y: 14.3))
            leaves.curve(to: NSPoint(x: 13.1, y: 15.7),
                         controlPoint1: NSPoint(x: 10.9, y: 14.3),
                         controlPoint2: NSPoint(x: 12.1, y: 14.8))
            leaves.lineWidth = 1.2
            leaves.lineCapStyle = .round
            leaves.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
