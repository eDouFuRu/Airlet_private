import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Reads only a small strip around one island, with every Airlet window
/// excluded. The image stays in memory just long enough to reduce it to eight
/// luminance pairs; no screenshot, pixel buffer, or app content is retained.
@MainActor
final class FloatingGlassBackdropSampler {
    private let filter: SCContentFilter
    private let screenSize: CGSize

    private init(filter: SCContentFilter, screenSize: CGSize) {
        self.filter = filter
        self.screenSize = screenSize
    }

    static func make(screen: NSScreen) async -> FloatingGlassBackdropSampler? {
        guard CGPreflightScreenCaptureAccess(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                return nil
            }
            let ownApps = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            guard !ownApps.isEmpty else { return nil }
            let filter = SCContentFilter(display: display,
                                         excludingApplications: ownApps,
                                         exceptingWindows: [])
            return FloatingGlassBackdropSampler(filter: filter, screenSize: screen.frame.size)
        } catch {
            return nil
        }
    }

    func sample(size: CGSize, topInset: CGFloat, cornerRadius: CGFloat) async -> GlassEdgeLightProfile? {
        guard size.width > 0, size.height > 0 else { return nil }
        let width = min(size.width, screenSize.width)
        let height = min(size.height, screenSize.height)
        let left = (screenSize.width - width) / 2
        let top = max(0, topInset)
        let margin: CGFloat = 12
        let sourceX = max(0, left - margin)
        let sourceWidth = min(screenSize.width - sourceX, width + 2 * margin)
        let sourceHeight = min(screenSize.height, top + height + margin)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let source = CGRect(x: sourceX, y: 0, width: sourceWidth, height: sourceHeight)
        let outputWidth = min(320, max(96, Int(sourceWidth * 0.75)))
        let outputHeight = max(24, Int((sourceHeight / sourceWidth * CGFloat(outputWidth)).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = outputWidth
        configuration.height = outputHeight
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.showsCursor = false
        configuration.capturesAudio = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            guard let bitmap = LuminanceBitmap(image: image) else { return nil }
            let radius = min(max(1, cornerRadius), min(width, height) / 2)
            let diagonal = radius * (1 - 1 / sqrt(2))
            let positions: [(CGPoint, CGVector)] = [
                (CGPoint(x: left + width / 2, y: top), CGVector(dx: 0, dy: -1)),
                (CGPoint(x: left + width - diagonal, y: top + diagonal),
                 CGVector(dx: 0.7071, dy: -0.7071)),
                (CGPoint(x: left + width, y: top + height / 2), CGVector(dx: 1, dy: 0)),
                (CGPoint(x: left + width - diagonal, y: top + height - diagonal),
                 CGVector(dx: 0.7071, dy: 0.7071)),
                (CGPoint(x: left + width / 2, y: top + height), CGVector(dx: 0, dy: 1)),
                (CGPoint(x: left + diagonal, y: top + height - diagonal),
                 CGVector(dx: -0.7071, dy: 0.7071)),
                (CGPoint(x: left, y: top + height / 2), CGVector(dx: -1, dy: 0)),
                (CGPoint(x: left + diagonal, y: top + diagonal),
                 CGVector(dx: -0.7071, dy: -0.7071))
            ]
            let reach: CGFloat = min(8, max(3, height / 3))
            let pairs = positions.map { edge, normal in
                let outside = CGPoint(x: edge.x + normal.dx * reach,
                                      y: edge.y + normal.dy * reach)
                let inside = CGPoint(x: edge.x - normal.dx * reach,
                                     y: edge.y - normal.dy * reach)
                return GlassEdgeLightPair(outside: bitmap.luminance(at: outside, source: source),
                                          inside: bitmap.luminance(at: inside, source: source))
            }
            return GlassEdgeLightProfile(pairs: pairs)
        } catch {
            return nil
        }
    }
}

private struct LuminanceBitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage) {
        let pixelWidth = image.width
        let pixelHeight = image.height
        guard pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 1024, pixelHeight <= 1024 else { return nil }
        var storage = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let rendered = storage.withUnsafeMutableBytes { raw -> Bool in
            guard let address = raw.baseAddress,
                  let context = CGContext(data: address, width: pixelWidth, height: pixelHeight,
                                          bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard rendered else { return nil }
        width = pixelWidth
        height = pixelHeight
        pixels = storage
    }

    func luminance(at point: CGPoint, source: CGRect) -> Double {
        let x = min(width - 1, max(0, Int((point.x - source.minX) / source.width * CGFloat(width))))
        let y = min(height - 1, max(0, Int((point.y - source.minY) / source.height * CGFloat(height))))
        var total = 0.0
        var count = 0.0
        for row in max(0, y - 1)...min(height - 1, y + 1) {
            for column in max(0, x - 1)...min(width - 1, x + 1) {
                let index = (row * width + column) * 4
                let red = Self.linearChannel(pixels[index])
                let green = Self.linearChannel(pixels[index + 1])
                let blue = Self.linearChannel(pixels[index + 2])
                total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
                count += 1
            }
        }
        return total / count
    }

    private static func linearChannel(_ byte: UInt8) -> Double {
        let value = Double(byte) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
