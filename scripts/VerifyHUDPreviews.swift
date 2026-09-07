// Read-only pixel checks on offline PNGs. No AppKit session or hardware calls.
import CoreGraphics
import Foundation
import ImageIO

@main struct VerifyHUDPreviews {
    static func bitmap(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "HUDPreviewPixels", code: 1)
        }
        return image
    }

    static func pixels(_ image: CGImage, rect: CGRect) throws -> [UInt8] {
        guard let crop = image.cropping(to: rect) else { throw NSError(domain: "HUDPreviewPixels", code: 2) }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw NSError(domain: "HUDPreviewPixels", code: 3)
            }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return bytes
    }

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let geometry = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("geometry.json"))) as! [String: Any]
        let scenarios = geometry["scenarios"] as! [[String: Any]]
        var gapChecks: [[String: Any]] = []
        var iconChecks: [[String: Any]] = []
        var bodyChecks: [[String: Any]] = []
        for scenario in scenarios {
            let name = scenario["name"] as! String
            let gap = scenario["physicalGapWidth"] as! Double
            let width = scenario["width"] as! Double
            let header = scenario["headerHeight"] as! Double
            let rowHeight = scenario["rowHeight"] as! Double
            let image = try bitmap(output.appendingPathComponent(name + ".png"))
            let bytes = try pixels(image, rect: CGRect(x: width - gap, y: 0, width: gap * 2, height: header * 2))
            let occupied = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 2 || bytes[$0 + 1] > 2 || bytes[$0 + 2] > 2 }.count
            gapChecks.append(["name": name, "occupiedCameraGapPixels": occupied, "pass": occupied == 0])
            let inline = name.contains("-inline-")
            let leadingInset: Double = name.contains("-open-") ? 31 : 6
            let iconBytes = try pixels(image, rect: CGRect(
                x: (leadingInset + (inline ? 10 : 16)) * 2,
                y: inline ? 0 : header * 2,
                width: inline ? 36 : 40, height: inline ? header * 2 : rowHeight * 2))
            let iconPixels = stride(from: 0, to: iconBytes.count, by: 4).filter {
                iconBytes[$0] > 2 || iconBytes[$0 + 1] > 2 || iconBytes[$0 + 2] > 2
            }.count
            iconChecks.append(["name": name, "visibleIconPixels": iconPixels, "pass": iconPixels > 0])
        }
        for language in ["en", "zh-Hans"] {
            for kind in ["volume", "brightness", "error", "backlight", "mic"] {
                let inlineName = "\(language)-open-inline-\(kind)"
                let rowName = "\(language)-open-default-\(kind)"
                let a = scenarios.first { $0["name"] as? String == inlineName }!
                let b = scenarios.first { $0["name"] as? String == rowName }!
                let height = a["pageBodyHeight"] as! Double
                let width = (a["width"] as! Double) - 62
                let aRect = CGRect(x: 62, y: (a["pageBodyTop"] as! Double) * 2, width: width * 2, height: height * 2)
                let bRect = CGRect(x: 62, y: (b["pageBodyTop"] as! Double) * 2, width: width * 2, height: height * 2)
                let aPixels = try pixels(bitmap(output.appendingPathComponent(inlineName + ".png")), rect: aRect)
                let bPixels = try pixels(bitmap(output.appendingPathComponent(rowName + ".png")), rect: bRect)
                let equal = aPixels == bPixels
                let differentBytes = zip(aPixels, bPixels).filter { $0 != $1 }.count
                let maximumDifference = zip(aPixels, bPixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
                bodyChecks.append(["language": language, "kind": kind, "bodyHeight": height,
                    "rowMovesBodyBy": (b["pageBodyTop"] as! Double) - (a["pageBodyTop"] as! Double),
                    "bodyPixelsIdentical": equal, "differentBytes": differentBytes,
                    "maximumChannelDifference": maximumDifference, "totalBytes": aPixels.count,
                    // Allow only 3/255 channel rounding between independent
                    // ImageRenderer layers, while retaining the exact result.
                    "bodyPixelsMatchWithinTolerance": maximumDifference <= 3])
            }
        }
        let failures = gapChecks.filter { $0["pass"] as? Bool != true }.count + iconChecks.filter { $0["pass"] as? Bool != true }.count + bodyChecks.filter { $0["bodyPixelsMatchWithinTolerance"] as? Bool != true }.count
        let result: [String: Any] = ["staticOnly": true, "bodyChannelTolerance": 3, "gapChecks": gapChecks, "iconChecks": iconChecks, "bodyChecks": bodyChecks, "failures": failures]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("pixel-checks.json"))
        print("Offline pixel checks: \(gapChecks.count) camera gaps + \(iconChecks.count) visible icons + \(bodyChecks.count) page bodies (3/255 channel tolerance); failures=\(failures)")
        if failures > 0 { throw NSError(domain: "HUDPreviewPixels", code: 4) }
        if CommandLine.arguments.count > 2 {
            let baseline = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            var comparison: [[String: Any]] = []
            for scenario in scenarios where (scenario["name"] as! String).contains("-inline-") {
                let name = scenario["name"] as! String
                let before = try bitmap(baseline.appendingPathComponent(name + ".png"))
                let after = try bitmap(output.appendingPathComponent(name + ".png"))
                guard before.width == after.width, before.height == after.height else {
                    throw NSError(domain: "HUDPreviewPixels", code: 5)
                }
                let full = CGRect(x: 0, y: 0, width: after.width, height: after.height)
                let header = CGRect(x: 0, y: 0, width: Double(after.width),
                                    height: (scenario["headerHeight"] as! Double) * 2)
                let beforePixels = try pixels(before, rect: full)
                let afterPixels = try pixels(after, rect: full)
                let headerIdentical = try pixels(before, rect: header) == pixels(after, rect: header)
                let maximumDifference = zip(beforePixels, afterPixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
                comparison.append(["name": name, "widthPixels": after.width, "heightPixels": after.height,
                    "headerPixelsIdentical": headerIdentical, "fullImagePixelsIdentical": beforePixels == afterPixels,
                    "maximumFullImageChannelDifference": maximumDifference,
                    "pass": headerIdentical && maximumDifference <= 3])
            }
            let report: [String: Any] = ["staticOnly": true, "source": "Production inline HUD and isolated previous HUD source from Git",
                "bodyChannelTolerance": 3, "scenarios": comparison,
                "failures": comparison.filter { $0["pass"] as? Bool != true }.count]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("inline-baseline-pixels.json"))
            guard comparison.allSatisfy({ $0["pass"] as? Bool == true }) else {
                throw NSError(domain: "HUDPreviewPixels", code: 6)
            }
            print("Inline baseline comparison: \(comparison.count) HUD headers pixel-identical; full images within 3/255 channel tolerance")
        }
    }
}
