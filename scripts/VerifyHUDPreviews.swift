// Read-only dimension and camera-gap checks on the isolated component snapshots.
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
        var checks: [[String: Any]] = []
        for scenario in scenarios {
            let name = scenario["name"] as! String
            let width = scenario["width"] as! Double
            let height = scenario["height"] as! Double
            let header = scenario["headerHeight"] as! Double
            let floating = scenario["floating"] as! Bool
            let expanded = scenario["expanded"] as! Bool
            let image = try bitmap(output.appendingPathComponent(name + ".png"))
            let dimensions = image.width == Int(width * 2) && image.height == Int(height * 2)
            var record: [String: Any] = ["name": name, "dimensionsMatch": dimensions]
            var pass = dimensions
            if floating {
                let validGeometry = (expanded ? header == 36 : [18.0, 24.0].contains(header))
                    && (scenario["physicalGapWidth"] as! Double) == 0
                    && (scenario["topInset"] as! Double) == 3
                    && (expanded || height == header)
                let bytes = try pixels(image, rect: CGRect(x: 24, y: 0, width: (width - 24) * 2, height: header * 2))
                let light = scenario["colorScheme"] as! String == "light"
                let ink = stride(from: 0, to: bytes.count, by: 4).filter { i in
                    guard bytes[i + 3] > 160 else { return false }
                    let luminance = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
                    return light ? luminance < 140 : luminance > 160
                }.count
                record["expectedCompactOrExpandedHeader"] = validGeometry
                record["contrastingHeaderPixels"] = ink
                pass = pass && validGeometry && ink > 20
            } else {
                let gap = scenario["physicalGapWidth"] as! Double
                let bytes = try pixels(image, rect: CGRect(x: width - gap, y: 0, width: gap * 2, height: header * 2))
                let occupied = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 2 || bytes[$0 + 1] > 2 || bytes[$0 + 2] > 2 }.count
                record["occupiedCameraGapPixels"] = occupied
                pass = pass && occupied == 0
            }
            record["pass"] = pass
            checks.append(record)
        }
        let failures = checks.filter { $0["pass"] as? Bool != true }.count
        let result: [String: Any] = ["staticOnly": true, "checks": checks, "failures": failures,
            "limitations": "Dimensions, reserved camera pixels and contrasting ink only; no live native glass or full page interaction claim."]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("pixel-checks.json"))
        print("Offline pixel checks: \(checks.count) component snapshots; failures=\(failures)")
        if failures > 0 { throw NSError(domain: "HUDPreviewPixels", code: 4) }
    }
}
