import AppKit

/// Compile together with Interaction/PotatoStatusIcon.swift; writes review assets only.
@main
enum RenderPotatoStatusIcon {
    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? "build/validation/menu-bar-273"
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scale in [1, 2] {
            try render(size: NSSize(width: 19, height: 18), scale: scale,
                       destination: directory.appendingPathComponent("potato-status-\(scale)x.png")) {
                PotatoStatusIcon.image.draw(in: NSRect(x: 0, y: 0, width: 19, height: 18))
            }
        }
        try render(size: NSSize(width: 480, height: 300), scale: 2,
                   destination: directory.appendingPathComponent("potato-status-preview.png")) {
            for (row, dark) in [false, true].enumerated() {
                let y = CGFloat(row) * 100
                NSColor(white: dark ? 0.13 : 0.96, alpha: 1).setFill()
                NSRect(x: 0, y: y, width: 480, height: 100).fill()
                let tint: NSColor = dark ? .white : .black
                let icon = tintedIcon(tint)
                icon.draw(in: NSRect(x: 28, y: y + 42, width: 19, height: 18))
                icon.draw(in: NSRect(x: 165, y: y + 14, width: 76, height: 72))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: tint
                ]
                (dark ? "Dark menu bar" : "Light menu bar").draw(
                    at: NSPoint(x: 280, y: y + 52), withAttributes: attributes)
                "19 x 18 pt / 4x detail".draw(
                    at: NSPoint(x: 280, y: y + 32), withAttributes: attributes)
            }
            NSColor.black.setFill()
            NSRect(x: 0, y: 200, width: 480, height: 100).fill()
            for (column, selected) in [true, false].enumerated() {
                let x = CGFloat(column) * 62 + 24
                if selected {
                    NSColor(white: 0.20, alpha: 1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: 234, width: 44, height: 32),
                                 xRadius: 16, yRadius: 16).fill()
                }
                tintedIcon(selected ? .white : NSColor(white: 0.60, alpha: 1)).draw(
                    in: NSRect(x: x + 12.5, y: 241, width: 19, height: 18))
            }
            "Island tab: selected / inactive".draw(
                at: NSPoint(x: 200, y: 244),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                 .foregroundColor: NSColor.white])
        }
    }

    private static func tintedIcon(_ color: NSColor) -> NSImage {
        NSImage(size: PotatoStatusIcon.image.size, flipped: false) { bounds in
            PotatoStatusIcon.image.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
    }

    private static func render(size: NSSize, scale: Int, destination: URL,
                               draw: () -> Void) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: Int(size.width) * scale,
                                      pixelsHigh: Int(size.height) * scale,
                                      bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
    }
}
