// Offline helper. Compiling this file does not process an image.
// Execute only after the user has approved local image editing.
import Foundation
import Vision
import CoreImage
import ImageIO

@main
struct ShuForegroundMask {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw Failure("Usage: ShuForegroundMask <source.png> <mask.png>")
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        guard source != output else { throw Failure("The source cannot be overwritten.") }
        guard #available(macOS 14.0, *) else { throw Failure("Foreground masks require macOS 14 or later.") }

        let handler = VNImageRequestHandler(url: source, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw Failure("Vision found no foreground instance in \(source.lastPathComponent).")
        }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        try context.writePNGRepresentation(of: image, to: output,
                                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        print("Vision mask: \(observation.allInstances.count) foreground instance(s), \(output.path)")
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
