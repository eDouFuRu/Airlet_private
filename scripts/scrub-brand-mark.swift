// Remove the small white wordmark printed on Captain Shu's red shirt.
//
// The wordmark is located by finding whitish pixels whose nearest non-whitish
// neighbour on both sides of the same row is red fabric; that bounding box is
// padded and then repainted row by row, interpolating the fabric colour between
// the columns just outside the box. Repainting the whole box instead of the
// detected strokes is what makes the antialiased halo disappear as well.
//
// Geometry, canvas size and alpha stay untouched, which is what the 2.5D rig
// depends on: it aligns arms, forearms and fingers to landmarks measured against
// these exact pixel dimensions.
//
// Usage:
//   scrub-brand-mark <input.png> <output.png>
//                    [--roi x,y,w,h] [--preview mask.png] [--detect-only]
//                    [--pad N] [--reach N]

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("scrub-brand-mark: \(message)\n".utf8))
    exit(1)
}

struct Region {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

struct Arguments {
    var input: URL
    var output: URL
    var roi: Region?
    var preview: URL?
    var detectOnly = false
    var audit = false
    var pad = 5
    var reach = 40
}

func parseArguments() -> Arguments {
    var positional: [String] = []
    var roi: Region?
    var preview: URL?
    var detectOnly = false
    var audit = false
    var pad = 5
    var reach = 40
    var index = 1
    let raw = CommandLine.arguments
    while index < raw.count {
        let token = raw[index]
        switch token {
        case "--roi":
            index += 1
            guard index < raw.count else { fail("--roi needs x,y,w,h") }
            let parts = raw[index].split(separator: ",").map { Int($0) }
            guard parts.count == 4, !parts.contains(nil) else { fail("--roi needs four integers") }
            roi = Region(x: parts[0]!, y: parts[1]!, width: parts[2]!, height: parts[3]!)
        case "--preview":
            index += 1
            guard index < raw.count else { fail("--preview needs a path") }
            preview = URL(fileURLWithPath: raw[index])
        case "--detect-only":
            detectOnly = true
        case "--audit":
            audit = true
        case "--pad":
            index += 1
            guard index < raw.count, let value = Int(raw[index]), value >= 0 else { fail("--pad needs a non-negative integer") }
            pad = value
        case "--reach":
            index += 1
            guard index < raw.count, let value = Int(raw[index]), value > 0 else { fail("--reach needs a positive integer") }
            reach = value
        default:
            guard !token.hasPrefix("--") else { fail("unknown flag \(token)") }
            positional.append(token)
        }
        index += 1
    }
    guard positional.count == 2 else { fail("usage: scrub-brand-mark <input.png> <output.png> [flags]") }
    return Arguments(input: URL(fileURLWithPath: positional[0]),
                     output: URL(fileURLWithPath: positional[1]),
                     roi: roi, preview: preview, detectOnly: detectOnly,
                     audit: audit, pad: pad, reach: reach)
}

struct Raster {
    var bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let alphaInfo: CGImageAlphaInfo
    let colorSpace: CGColorSpace

    func offset(_ x: Int, _ y: Int) -> Int { y * bytesPerRow + x * 4 }

    /// Opaque source images carry a padding byte instead of a real alpha channel.
    var carriesAlpha: Bool { alphaInfo == .last || alphaInfo == .premultipliedLast }

    /// Matting left the wordmark's white strokes at alpha 241–254 instead of 255,
    /// so "interior" has to be a threshold. Anything below stays untouched: that
    /// is the antialiased silhouette, not fabric.
    func isOpaque(_ index: Int) -> Bool { carriesAlpha ? bytes[index + 3] >= 235 : true }
}

func loadRaster(_ url: URL) -> Raster {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("cannot decode \(url.path)")
    }
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
          let colorSpace = image.colorSpace, let data = image.dataProvider?.data else {
        fail("\(url.lastPathComponent) is not an 8-bit RGBA image")
    }
    let alphaInfo = image.alphaInfo
    guard alphaInfo == .last || alphaInfo == .premultipliedLast || alphaInfo == .noneSkipLast else {
        fail("\(url.lastPathComponent) has unsupported alpha layout \(alphaInfo.rawValue)")
    }
    let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
    guard byteOrder == .byteOrder32Big || byteOrder.rawValue == 0 else {
        fail("\(url.lastPathComponent) has unsupported byte order")
    }
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRangeMake(0, length), &bytes)
    return Raster(bytes: bytes, width: image.width, height: image.height,
                  bytesPerRow: image.bytesPerRow, alphaInfo: alphaInfo, colorSpace: colorSpace)
}

func writeRaster(_ raster: Raster, to url: URL) {
    let data = CFDataCreate(nil, raster.bytes, raster.bytes.count)!
    guard let provider = CGDataProvider(data: data) else { fail("cannot wrap pixels") }
    let bitmapInfo = CGBitmapInfo(rawValue: raster.alphaInfo.rawValue)
    guard let image = CGImage(width: raster.width, height: raster.height,
                              bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: raster.bytesPerRow, space: raster.colorSpace,
                              bitmapInfo: bitmapInfo, provider: provider,
                              decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
        fail("cannot rebuild image")
    }
    let temporary = url.deletingLastPathComponent()
        .appendingPathComponent("." + url.lastPathComponent + ".tmp")
    guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot create \(temporary.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot encode \(temporary.path)") }
    do {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    } catch {
        fail("cannot write \(url.path): \(error.localizedDescription)")
    }
}

let arguments = parseArguments()
var raster = loadRaster(arguments.input)
let roi = arguments.roi ?? Region(x: 0, y: 0, width: raster.width, height: raster.height)
guard roi.x >= 0, roi.y >= 0, roi.width > 0, roi.height > 0,
      roi.x + roi.width <= raster.width, roi.y + roi.height <= raster.height else {
    fail("--roi falls outside the \(raster.width)x\(raster.height) canvas")
}

func isWhitish(_ index: Int) -> Bool {
    let bytes = raster.bytes
    guard raster.isOpaque(index) else { return false }
    let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
    let low = min(r, min(g, b)), high = max(r, max(g, b))
    return low >= 170 && high - low <= 70
}

func isFabric(_ index: Int) -> Bool {
    let bytes = raster.bytes
    guard raster.isOpaque(index) else { return false }
    let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
    return r >= 130 && r - g >= 55 && r - b >= 55
}

// A wordmark pixel is whitish and enclosed by red fabric on the same row.
var mask = [Bool](repeating: false, count: raster.width * raster.height)
for y in roi.y..<(roi.y + roi.height) {
    for x in roi.x..<(roi.x + roi.width) {
        let index = raster.offset(x, y)
        guard isWhitish(index) else { continue }
        var enclosed = true
        for direction in [-1, 1] {
            var found = false
            var step = 1
            while step <= arguments.reach {
                let probe = x + direction * step
                guard probe >= 0, probe < raster.width else { break }
                let probeIndex = raster.offset(probe, y)
                if isWhitish(probeIndex) { step += 1; continue }
                found = isFabric(probeIndex)
                break
            }
            if !found { enclosed = false; break }
        }
        if enclosed { mask[y * raster.width + x] = true }
    }
}

let detected = mask.filter { $0 }.count
if arguments.audit {
    // Release guard: succeed only when nothing looks like ink on the shirt.
    print("\(arguments.input.lastPathComponent): \(detected) suspicious pixels")
    exit(detected == 0 ? 0 : 1)
}
guard detected > 0 else { fail("no wordmark pixels detected inside the region") }

var minimumX = raster.width, minimumY = raster.height, maximumX = -1, maximumY = -1
for y in 0..<raster.height {
    for x in 0..<raster.width where mask[y * raster.width + x] {
        minimumX = min(minimumX, x); maximumX = max(maximumX, x)
        minimumY = min(minimumY, y); maximumY = max(maximumY, y)
    }
}
print("detected \(detected) wordmark pixels, bounds x=\(minimumX) y=\(minimumY) "
      + "w=\(maximumX - minimumX + 1) h=\(maximumY - minimumY + 1)")

// Grow the detected strokes into their full glyphs. The ink is not always neutral
// white — on some renders it picks up the warm key light — so the test is simply
// "not red fabric": the glyphs spread until they run into the shirt, and the shirt
// is what keeps the flood away from the cream body and the hands.
let patch = Region(x: max(0, minimumX - arguments.pad),
                   y: max(0, minimumY - arguments.pad),
                   width: min(raster.width - 1, maximumX + arguments.pad) - max(0, minimumX - arguments.pad) + 1,
                   height: min(raster.height - 1, maximumY + arguments.pad) - max(0, minimumY - arguments.pad) + 1)
print("patch x=\(patch.x) y=\(patch.y) w=\(patch.width) h=\(patch.height)")

func insidePatch(_ x: Int, _ y: Int) -> Bool {
    x >= patch.x && x < patch.x + patch.width && y >= patch.y && y < patch.y + patch.height
}

var queue: [Int] = []
for y in patch.y..<(patch.y + patch.height) {
    for x in patch.x..<(patch.x + patch.width) where mask[y * raster.width + x] {
        queue.append(y * raster.width + x)
    }
}
var head = 0
while head < queue.count {
    let position = queue[head]
    head += 1
    let x = position % raster.width, y = position / raster.width
    for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx, ny = y + dy
            guard insidePatch(nx, ny), !mask[ny * raster.width + nx] else { continue }
            let index = raster.offset(nx, ny)
            guard raster.isOpaque(index), !isFabric(index) else { continue }
            mask[ny * raster.width + nx] = true
            queue.append(ny * raster.width + nx)
        }
    }
}
print("grown to \(mask.filter { $0 }.count) pixels")

// Swallow the pink halo where each stroke fades into the fabric. Growing into
// fabric is harmless: fabric repainted with interpolated fabric is invisible.
var grown = mask
for y in patch.y..<(patch.y + patch.height) {
    for x in patch.x..<(patch.x + patch.width) where mask[y * raster.width + x] {
        for dy in -3...3 {
            for dx in -3...3 where dx * dx + dy * dy <= 9 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < raster.width, ny >= 0, ny < raster.height else { continue }
                guard raster.isOpaque(raster.offset(nx, ny)) else { continue }
                grown[ny * raster.width + nx] = true
            }
        }
    }
}
mask = grown

if let previewURL = arguments.preview {
    var overlay = raster
    for y in 0..<raster.height {
        for x in 0..<raster.width where mask[y * raster.width + x] {
            let index = raster.offset(x, y)
            overlay.bytes[index] = 0
            overlay.bytes[index + 1] = 255
            overlay.bytes[index + 2] = 0
            if overlay.carriesAlpha { overlay.bytes[index + 3] = 255 }
        }
    }
    writeRaster(overlay, to: previewURL)
    print("preview: \(previewURL.path)")
}

if arguments.detectOnly { exit(0) }

// Fill each masked run by interpolating between the fabric on both sides.
func anchor(row y: Int, from x: Int, direction: Int) -> (Double, Double, Double)? {
    var samples: [(Int, Int, Int)] = []
    var step = 0
    while samples.count < 3, step < arguments.reach {
        let probe = x + direction * step
        guard probe >= 0, probe < raster.width else { break }
        step += 1
        guard !mask[y * raster.width + probe] else { continue }
        let index = raster.offset(probe, y)
        guard isFabric(index) else { continue }
        samples.append((Int(raster.bytes[index]), Int(raster.bytes[index + 1]), Int(raster.bytes[index + 2])))
    }
    guard !samples.isEmpty else { return nil }
    let count = Double(samples.count)
    return (Double(samples.reduce(0) { $0 + $1.0 }) / count,
            Double(samples.reduce(0) { $0 + $1.1 }) / count,
            Double(samples.reduce(0) { $0 + $1.2 }) / count)
}

var filled = 0
var skipped = 0
for y in 0..<raster.height {
    var x = 0
    while x < raster.width {
        guard mask[y * raster.width + x] else { x += 1; continue }
        var end = x
        while end + 1 < raster.width, mask[y * raster.width + end + 1] { end += 1 }
        let left = anchor(row: y, from: x - 1, direction: -1)
        let right = anchor(row: y, from: end + 1, direction: 1)
        if let left, let right {
            let span = Double(end - x + 2)
            for pixel in x...end {
                let t = Double(pixel - x + 1) / span
                let index = raster.offset(pixel, y)
                raster.bytes[index] = UInt8((left.0 + (right.0 - left.0) * t).rounded().clampedByte)
                raster.bytes[index + 1] = UInt8((left.1 + (right.1 - left.1) * t).rounded().clampedByte)
                raster.bytes[index + 2] = UInt8((left.2 + (right.2 - left.2) * t).rounded().clampedByte)
                if raster.carriesAlpha { raster.bytes[index + 3] = 255 }
                filled += 1
            }
        } else if let only = left ?? right {
            for pixel in x...end {
                let index = raster.offset(pixel, y)
                raster.bytes[index] = UInt8(only.0.rounded().clampedByte)
                raster.bytes[index + 1] = UInt8(only.1.rounded().clampedByte)
                raster.bytes[index + 2] = UInt8(only.2.rounded().clampedByte)
                if raster.carriesAlpha { raster.bytes[index + 3] = 255 }
                filled += 1
            }
        } else {
            // No fabric on either side: this run is a bright highlight on the
            // body rather than ink on the shirt. Leave it alone.
            skipped += 1
        }
        x = end + 1
    }
}

extension Double {
    var clampedByte: Double { Swift.min(255, Swift.max(0, self)) }
}

// Row-by-row interpolation leaves faint horizontal banding where neighbouring
// rows disagree; a couple of 3x3 averaging passes over the repainted pixels blend
// it back into the fabric shading.
for _ in 0..<2 {
    let snapshot = raster.bytes
    for y in patch.y..<(patch.y + patch.height) {
        for x in patch.x..<(patch.x + patch.width) where mask[y * raster.width + x] {
            var sums = [0, 0, 0]
            var samples = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < raster.width, ny >= 0, ny < raster.height else { continue }
                    let index = raster.offset(nx, ny)
                    guard raster.isOpaque(index) else { continue }
                    sums[0] += Int(snapshot[index])
                    sums[1] += Int(snapshot[index + 1])
                    sums[2] += Int(snapshot[index + 2])
                    samples += 1
                }
            }
            guard samples > 0 else { continue }
            let index = raster.offset(x, y)
            for channel in 0..<3 {
                raster.bytes[index + channel] = UInt8((Double(sums[channel]) / Double(samples)).rounded().clampedByte)
            }
        }
    }
}

writeRaster(raster, to: arguments.output)
print("filled \(filled) pixels, skipped \(skipped) runs with no fabric alongside "
      + "-> \(arguments.output.path)")
