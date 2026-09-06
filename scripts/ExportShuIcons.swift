import SwiftUI
import AppKit
@main struct ExportShuIcons {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for variant in ["captain", "planting", "roasting"] {
            let folder = root.appendingPathComponent("ShuIcon-\(variant).imageset")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try render(variant: variant, pixels: 512, to: folder.appendingPathComponent("icon.png"))
            let manifest: [String: Any] = ["images": [["idiom": "universal", "filename": "icon.png"]], "info": ["author": "xcode", "version": 1]]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
        }
        let folder = root.appendingPathComponent("AppIcon.appiconset")
        var entries: [[String:String]] = []
        for point in [16, 32, 128, 256, 512] {
            for scale in [1,2] {
                let pixels = point * scale
                let name = "shu-\(pixels).png"
                try render(variant: "captain", pixels: pixels, to: folder.appendingPathComponent(name))
                entries.append(["idiom":"mac", "size":"\(point)x\(point)", "scale":"\(scale)x", "filename":name])
            }
        }
        try JSONSerialization.data(withJSONObject: ["images":entries,"info":["version":1,"author":"xcode"]], options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("Contents.json"))
        let logo = root.appendingPathComponent("logo2.imageset")
        try render(variant:"captain",pixels:512,to:logo.appendingPathComponent("shu-brand.png"))
        try JSONSerialization.data(withJSONObject:["images":[["idiom":"universal","filename":"shu-brand.png"]],"info":["version":1,"author":"xcode"]],options:[.prettyPrinted,.sortedKeys]).write(to:logo.appendingPathComponent("Contents.json"))
    }
    @MainActor static func render(variant: String, pixels: Int, to url: URL) throws {
        let side = CGFloat(pixels)
        let content = CaptainShuIconArtwork(variant:variant).scaleEffect(side/512).frame(width:side,height:side)
        let renderer = ImageRenderer(content:content)
        renderer.scale = 1
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else { throw NSError(domain:"ShuIcon",code:1) }
        try data.write(to:url)
    }
}
