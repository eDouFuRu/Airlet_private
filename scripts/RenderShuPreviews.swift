// Static QA harness. Compile with the actual CaptainShuArtwork.swift and
// IslandPage.swift only; these stubs never read or write production persistence.
import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum PreviewLanguage { static var current = "en" }
func L(_ key: String) -> String {
    guard let path = Bundle.main.path(forResource: PreviewLanguage.current, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
}
enum RestSessionPhase { case idle, running, paused, completed }
enum PotatoSessionMode { case rest, focus }
enum PreviewNotchState { case open, closed }
@MainActor final class BoringViewModel: ObservableObject {
    @Published var notchState = PreviewNotchState.open
    func close(force: Bool) {}
}
@MainActor final class NotchPointerCoordinator: ObservableObject {
    func keepExpandedForUserCommand(duration: Double) {}
}
@MainActor final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func showTimerSettings() {}
}
@MainActor final class IslandRestModel: ObservableObject {
    static let shared = IslandRestModel()
    @Published var phase = RestSessionPhase.idle
    @Published var mode = PotatoSessionMode.rest
    @Published var elapsedSeconds = 0.0
    @Published var potatoCount = 0
    @Published var durationMinutes = 1
    var harvestAnimationSourceID: UUID?
    var harvestAnimationID: UUID?
    var harvestAnimationCount = 0
    var remainingSeconds: Int { phase == .completed ? 0 : max(0, Int(ceil(Double(durationMinutes * 60) - elapsedSeconds))) }
    var clockText: String { String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60) }
    var progress: Double { phase == .completed ? 1 : min(1, elapsedSeconds / Double(durationMinutes * 60)) }
    var focusBitesTaken: Int { mode == .focus ? min(6, Int(floor(progress * 6))) : 0 }
    var restCycleProgress: Double { elapsedSeconds.truncatingRemainder(dividingBy: 60) / 60 }
    func mountPage(_ id: UUID) {}
    func unmountPage(_ id: UUID) {}
    func selectMode(_ value: PotatoSessionMode) { mode = value }
    func setDurationMinutes(_ value: Int) { durationMinutes = value }
    func start() {}
    func pause() {}
    func resume() {}
    func cancel() {}
    func consumeFocusReminder() {}
}

@main @MainActor struct RenderShuPreviews {
    struct Scenario {
        var name: String
        var phase: RestSessionPhase = .idle
        var mode: PotatoSessionMode = .rest
        var elapsed: Double = 0
        var stock: Int = 0
        var minutes: Int = 1
    }

    static func png<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "RenderShuPreviews", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned no bitmap for \(url.lastPathComponent)"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "RenderShuPreviews", code: 2)
        }
        record(url)
    }

    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Preview failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/validation/shu/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        outputRoot = output.standardizedFileURL
        func integerArgument(_ name: String, fallback: Int) -> Int {
            guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return fallback }
            return Int(CommandLine.arguments[index + 1]) ?? fallback
        }
        fps = min(30, max(1, integerArgument("--fps", fallback: 20)))
        inventory = max(0, integerArgument("--inventory", fallback: 1))
        reducedMotion = CommandLine.arguments.contains("--reduce-motion")
        if CommandLine.arguments.contains("--motion-only") {
            try motionPreviews(to: output)
            try await finish(to: output)
            return
        }
        if CommandLine.arguments.contains("--handoff-only") {
            PreviewLanguage.current = "zh-Hans"
            try handoffPreviews(to: output)
            try await finish(to: output)
            return
        }
        let scenarios = [
            Scenario(name: "idle-stock0"),
            Scenario(name: "idle-stock1", stock: 1),
            Scenario(name: "idle-stock12", stock: 12),
            Scenario(name: "idle-stock13", stock: 13),
            Scenario(name: "idle-stock999999", stock: 999_999),
            Scenario(name: "rest-25s", phase: .running, elapsed: 25, stock: 1),
            Scenario(name: "rest-45s", phase: .running, elapsed: 45, stock: 1),
            Scenario(name: "rest-paused", phase: .paused, elapsed: 45, stock: 1),
            Scenario(name: "rest-completed", phase: .completed, elapsed: 60, stock: 13),
            Scenario(name: "focus-0bites", phase: .running, mode: .focus, elapsed: 0, stock: 1, minutes: 25),
            Scenario(name: "focus-1bite", phase: .running, mode: .focus, elapsed: 250, stock: 1, minutes: 25),
            Scenario(name: "focus-3bites", phase: .running, mode: .focus, elapsed: 750, stock: 1, minutes: 25),
            Scenario(name: "focus-5bites", phase: .running, mode: .focus, elapsed: 1_250, stock: 1, minutes: 25),
            Scenario(name: "focus-zero-stock", phase: .running, mode: .focus, elapsed: 250, stock: 0, minutes: 25),
            Scenario(name: "focus-reminder", phase: .completed, mode: .focus, elapsed: 1_500, stock: 0, minutes: 25)
        ]
        for language in ["en", "zh-Hans"] {
            PreviewLanguage.current = language
            for item in scenarios {
                let model = IslandRestModel.shared
                model.phase = item.phase
                model.mode = item.mode
                model.elapsedSeconds = item.elapsed
                model.potatoCount = item.stock
                model.durationMinutes = item.minutes
                let content = IslandPage(presentationID: UUID())
                    .environmentObject(BoringViewModel())
                    .environmentObject(NotchPointerCoordinator())
                    .environment(\.locale, Locale(identifier: language))
                    .transaction { $0.disablesAnimations = true }
                    .preferredColorScheme(.dark)
                    .padding(20)
                    .background(Color.black)
                try png(content, to: output.appendingPathComponent("\(language)-\(item.name).png"))
            }
            let sheet = VStack(alignment: .leading, spacing: 16) {
                Text("Actual IslandPage • \(language) • static QA").font(.system(size: 23, weight: .bold))
                Text("Isolated sample data; one static frame. This does not verify native hover or animation.").font(.system(size: 12))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(380)), count: 3), spacing: 15) {
                    ForEach(scenarios.map(\.name), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name).font(.system(size: 12, weight: .semibold))
                            if let source = CGImageSourceCreateWithURL(output.appendingPathComponent("\(language)-\(name).png") as CFURL, nil),
                               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 380)
                            }
                        }
                    }
                }
            }.padding(24).foregroundStyle(.white).background(Color(white: 0.13))
            try png(sheet, to: output.appendingPathComponent("overview-\(language).png"), scale: 1)
        }
        for bites in 0...6 {
            let potato = RoastPotatoView(bites: bites).frame(width: 53, height: 34)
                .padding(24).background(Color.black)
            try png(potato, to: output.appendingPathComponent("potato-\(bites)-bites.png"), scale: 4)
        }
        let biteSheet = HStack(spacing: 18) {
            ForEach(0...6, id: \.self) { bites in
                VStack(spacing: 12) {
                    Text("\(bites) / 6").font(.system(size: 16, weight: .medium))
                    RoastPotatoView(bites: bites).frame(width: 106, height: 68)
                }.frame(width: 106)
            }
        }.padding(24).foregroundStyle(.white).background(Color.black)
        try png(biteSheet, to: output.appendingPathComponent("potato-bites-contactsheet.png"))
        let pausedScene = PotatoGardenScene(activity: .roasting, elapsed: 45, inventory: 13,
                                            isRunning: false, harvestPulse: nil)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .padding(20).background(Color.black)
        try png(pausedScene, to: output.appendingPathComponent("scene-paused-timeline.png"))
        let timelineTimes = [0.0, 3, 6, 9, 12, 17, 23, 26, 30, 31.5, 33, 42, 54, 57, 59.5]
        for time in timelineTimes {
            let scene = PotatoGardenScene(activity: time < 30 ? .planting : .roasting, elapsed: time,
                                          inventory: 1, isRunning: false, harvestPulse: nil,
                                          previewElapsed: time)
                .padding(16).background(Color.black)
            try png(scene, to: output.appendingPathComponent(String(format: "timeline-%04.1fs.png", time)))
        }
        let timelineSheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(356)), count: 3), spacing: 12) {
            ForEach(timelineTimes, id: \.self) { time in
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(format: "%.1fs · %@", time, ShuAnimationTimeline.sample(elapsed: time).stage.rawValue))
                        .font(.system(size: 13, weight: .medium))
                    PotatoGardenScene(activity: time < 30 ? .planting : .roasting, elapsed: time,
                                      inventory: 1, isRunning: false, harvestPulse: nil,
                                      previewElapsed: time)
                }
            }
        }.padding(20).foregroundStyle(.white).background(Color(white: 0.12))
        try png(timelineSheet, to: output.appendingPathComponent("timeline-contactsheet.png"), scale: 1)
        try motionPreviews(to: output)
        try await finish(to: output)
        print("Rendered \(scenarios.count * 2) page snapshots, 4 contact sheets, 7 bite stages, 15 timeline samples and 1 paused-timeline scene in \(output.path)")
    }

    private static func handoffPreviews(to output: URL) throws {
        let inventories = [0, 1, 12, 13]
        let times = [54.0, 55.99, 56.0, 59.95, 60.0]
        func card(_ inventory: Int, _ time: Double) -> some View {
            let afterSettlement = time >= 60
            return VStack(alignment: .leading, spacing: 7) {
                Text(String(format: "%d → %d · %.2fs · stock %d", inventory, inventory + 1, time, inventory + (afterSettlement ? 1 : 0)))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                PotatoGardenScene(activity: afterSettlement ? .idle : .roasting, elapsed: time,
                                  inventory: inventory + (afterSettlement ? 1 : 0), isRunning: false,
                                  harvestPulse: nil, previewElapsed: time)
            }.padding(16).background(Color(white: 0.12))
        }
        for inventory in inventories {
            for time in times {
                try png(card(inventory, time), to: output.appendingPathComponent(String(format: "handoff-stock%d-at%05.2fs.png", inventory, time)))
            }
        }
        let sheet = VStack(alignment: .leading, spacing: 12) {
            Text("Delivery handoff · simulated before/after settlement").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Text("The renderer supplies old/new stock for these static samples; production inventory is unchanged by the artwork.")
                .font(.system(size: 11)).foregroundStyle(.white)
            ForEach(inventories, id: \.self) { inventory in
                HStack(spacing: 0) { ForEach(times, id: \.self) { time in card(inventory, time) } }
            }
        }.padding(16).background(Color(white: 0.12))
        try png(sheet, to: output.appendingPathComponent("handoff-contactsheet.png"), scale: 1)
        print("Rendered \(inventories.count * times.count) delivery handoff frames and one contact sheet; no production state changed")
    }

    private static var generatedFiles = Set<String>()
    private static var outputRoot = URL(fileURLWithPath: "/private/tmp")
    private static var inventory = 1
    private static var reducedMotion = false
    private static var fps = 20

    private static func record(_ url: URL) {
        generatedFiles.insert(String(url.path.dropFirst(outputRoot.path.count + 1)))
    }

    private static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "RenderShuPreviews", code: 6)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "RenderShuPreviews", code: 7) }
        record(url)
    }

    private static func exactScene(_ time: Double, stock: Int? = nil, idle: Bool = false,
                                   armVisibility: ShuPreviewArmVisibility = .both, skyTime: Double? = nil) -> some View {
        let originalStock = stock ?? inventory
        let settled = time >= 60
        return PotatoGardenScene(activity: settled || idle ? .idle : time < 30 ? .planting : .roasting,
                                 elapsed: time, inventory: originalStock + (settled ? 1 : 0),
                                 isRunning: false, harvestPulse: nil, previewElapsed: time, previewReduceMotion: reducedMotion,
                                 previewSkyTime: skyTime ?? time, previewArmVisibility: armVisibility)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .transaction { $0.disablesAnimations = true }
            .background(Color.black)
    }

    private static func bitmap<V: View>(_ view: V, scale: CGFloat = 1) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw NSError(domain: "RenderShuPreviews", code: 8) }
        return image
    }

    private static func crop(_ image: CGImage, center: CGPoint, radius: CGFloat, scale: CGFloat, to url: URL) throws {
        let desired = CGRect(x: (center.x - radius) * scale, y: (center.y - radius) * scale,
                             width: radius * 2 * scale, height: radius * 2 * scale)
        let rect = desired.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else {
            throw NSError(domain: "RenderShuPreviews", code: 9, userInfo: [NSLocalizedDescriptionKey: "Crop is outside the rendered scene"])
        }
        try savePNG(cropped, to: url)
    }

    /// Compare the actual rendered alpha silhouettes, not prop-center distance.
    /// A wrist-local circle restricts the arm layer to the palm/grip neighborhood.
    /// This detects floating sprites; it does not establish a natural-looking grip.
    private static func alphaContact(arm: CGImage, prop: CGImage, wrist: ShuPoint) throws -> [String: Any] {
        let scale = 4.0, radius = 20.0, palmRadius = 8.0
        let desired = CGRect(x: (wrist.x - radius) * scale, y: (wrist.y - radius) * scale,
                             width: radius * 2 * scale, height: radius * 2 * scale)
        let rect = desired.intersection(CGRect(x: 0, y: 0, width: arm.width, height: arm.height)).integral
        guard let armCrop = arm.cropping(to: rect), let propCrop = prop.cropping(to: rect) else {
            throw NSError(domain: "RenderShuPreviews", code: 25)
        }
        let width = armCrop.width, height = armCrop.height
        func mask(_ image: CGImage, palmOnly: Bool) throws -> [Bool] {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { throw NSError(domain: "RenderShuPreviews", code: 26) }
            let cx = wrist.x * scale - rect.minX, cy = wrist.y * scale - rect.minY
            return (0..<(width * height)).map { index in
                let x = Double(index % width) + 0.5, y = Double(index / width) + 0.5
                return bytes[index * 4 + 3] >= 128
                    && (!palmOnly || hypot(x - cx, y - cy) <= palmRadius * scale)
            }
        }
        let hand = try mask(armCrop, palmOnly: true), potato = try mask(propCrop, palmOnly: false)
        let overlap = zip(hand, potato).filter { pair in pair.0 && pair.1 }.count
        func boundary(_ pixels: [Bool]) -> [ShuPoint] {
            (0..<pixels.count).compactMap { index in
                guard pixels[index] else { return nil }
                let x = index % width, y = index / width
                let edge = x == 0 || x == width - 1 || y == 0 || y == height - 1
                guard edge || !pixels[index - 1] || !pixels[index + 1]
                    || !pixels[index - width] || !pixels[index + width] else { return nil }
                return ShuPoint(x: Double(x), y: Double(y))
            }
        }
        let handBoundary = boundary(hand), propBoundary = boundary(potato)
        guard !handBoundary.isEmpty, !propBoundary.isEmpty else {
            throw NSError(domain: "RenderShuPreviews", code: 27,
                          userInfo: [NSLocalizedDescriptionKey: "Missing visible palm or potato in grip alpha audit"])
        }
        var squaredGap = overlap > 0 ? 0.0 : Double.infinity
        if overlap == 0 {
            for a in handBoundary {
                for b in propBoundary {
                    squaredGap = min(squaredGap, (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
                }
            }
        }
        return ["alphaThreshold": 0.5, "renderScale": scale, "palmRadiusPoints": palmRadius,
                "overlapPixels": overlap, "nearestOpaquePixelDistancePoints": sqrt(squaredGap) / scale,
                "silhouettesOverlap": overlap > 0]
    }

    private static func verifyAlphaContactMeasurement() throws {
        func square(x: Double) -> some View {
            Rectangle().fill(.white).frame(width: 10, height: 10).position(x: x, y: 70)
                .frame(width: 324, height: 186)
        }
        let hand = try bitmap(square(x: 100), scale: 4)
        let touching = try alphaContact(arm: hand, prop: bitmap(square(x: 104), scale: 4), wrist: ShuPoint(x: 100, y: 70))
        let separate = try alphaContact(arm: hand, prop: bitmap(square(x: 115), scale: 4), wrist: ShuPoint(x: 100, y: 70))
        // The opaque pixel-center gap is the 5-point geometric gap plus 1/4 pt.
        guard (touching["overlapPixels"] as? Int ?? 0) > 0,
              (touching["nearestOpaquePixelDistancePoints"] as? Double) == 0,
              (separate["overlapPixels"] as? Int) == 0,
              abs((separate["nearestOpaquePixelDistancePoints"] as? Double ?? -1) - 5.25) < 0.001 else {
            throw NSError(domain: "RenderShuPreviews", code: 28,
                          userInfo: [NSLocalizedDescriptionKey: "Alpha-contact measurement failed independent square fixtures"])
        }
    }

    /// Same-time full-scene subtraction measures a hand's visible contribution
    /// after all production foreground layers, including the torso and props.
    private static func visibleHandContribution(withArm: CGImage, withoutArm: CGImage,
                                                wrist: ShuPoint) throws -> [String: Any] {
        let scale = 4.0, radius = 8.0
        let desired = CGRect(x: (wrist.x - radius) * scale, y: (wrist.y - radius) * scale,
                             width: radius * 2 * scale, height: radius * 2 * scale)
        let rect = desired.intersection(CGRect(x: 0, y: 0, width: withArm.width, height: withArm.height)).integral
        guard let shown = withArm.cropping(to: rect), let hidden = withoutArm.cropping(to: rect) else {
            throw NSError(domain: "RenderShuPreviews", code: 29)
        }
        func bytes(_ image: CGImage) throws -> [UInt8] {
            var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let drawn = result.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { throw NSError(domain: "RenderShuPreviews", code: 30) }
            return result
        }
        let a = try bytes(shown), b = try bytes(hidden)
        let cx = wrist.x * scale - rect.minX, cy = wrist.y * scale - rect.minY
        var changed = 0, peakDelta = 0
        for pixel in 0..<(shown.width * shown.height) {
            let x = Double(pixel % shown.width) + 0.5, y = Double(pixel / shown.width) + 0.5
            guard hypot(x - cx, y - cy) <= radius * scale else { continue }
            let delta = (0..<3).map { abs(Int(a[pixel * 4 + $0]) - Int(b[pixel * 4 + $0])) }.max()!
            peakDelta = max(peakDelta, delta)
            if delta >= 8 { changed += 1 }
        }
        return ["wristRadiusPoints": radius, "renderScale": scale, "minimumRGBChannelDelta": 8,
                "visibleChangedPixels": changed, "visibleChangedAreaPointsSquared": Double(changed) / (scale * scale),
                "maximumRGBChannelDelta": peakDelta, "fullyOccluded": changed == 0]
    }

    private static func verifyVisibleHandMeasurement() throws {
        func fixture(hand: Bool, covered: Bool) -> some View {
            ZStack(alignment: .topLeading) {
                Color.black
                if hand { Rectangle().fill(.white).frame(width: 10, height: 10).position(x: 100, y: 70) }
                if covered { Rectangle().fill(.black).frame(width: 12, height: 12).position(x: 100, y: 70) }
            }.frame(width: 324, height: 186)
        }
        let wrist = ShuPoint(x: 100, y: 70)
        let clear = try visibleHandContribution(withArm: bitmap(fixture(hand: true, covered: false), scale: 4),
            withoutArm: bitmap(fixture(hand: false, covered: false), scale: 4), wrist: wrist)
        let covered = try visibleHandContribution(withArm: bitmap(fixture(hand: true, covered: true), scale: 4),
            withoutArm: bitmap(fixture(hand: false, covered: true), scale: 4), wrist: wrist)
        guard (clear["visibleChangedAreaPointsSquared"] as? Double) == 100,
              (covered["visibleChangedPixels"] as? Int) == 0 else {
            throw NSError(domain: "RenderShuPreviews", code: 31,
                          userInfo: [NSLocalizedDescriptionKey: "Visible-hand subtraction failed independent occlusion fixtures"])
        }
    }

    private static func skyMotionAudit(to output: URL) throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                throw NSError(domain: "RenderShuPreviews", code: 32,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        var clock = ShuAmbientClock()
        try require(clock.elapsed(at: 100) == 0, "Unstarted sky clock advanced")
        clock.setRunning(true, at: 100)
        clock.setRunning(true, at: 104)
        try require(clock.elapsed(at: 110) == 10, "Repeated sky start reset the phase")
        clock.setRunning(false, at: 110)
        clock.setRunning(false, at: 200)
        let paused = clock.elapsed(at: 999)
        try require(paused == 10, "Paused/hidden sky time advanced")
        clock.setRunning(true, at: 2_000)
        try require(clock.elapsed(at: 2_004) == 14, "Sky resume counted paused time")
        clock.setRunning(false, at: 2_004)
        try require(clock.elapsed(at: 9_999) == 14, "Stopped sky clock kept advancing")

        var cloudChecks: [[String: Any]] = []
        for index in ShuSkyLayout.clouds.indices {
            let cloud = ShuSkyLayout.clouds[index]
            let positions = (0...1_200).map {
                ShuSkyLayout.cloudPosition(index: index, time: Double($0) / 10)
            }
            let changes = zip(positions, positions.dropFirst()).map { pair in pair.1.x - pair.0.x }
            let movesRight = changes.contains { $0 > 0.001 }, movesLeft = changes.contains { $0 < -0.001 }
            try require(movesRight && movesLeft, "Cloud \(index) did not reverse horizontal direction")
            let initial = positions[0], loopEnd = ShuSkyLayout.cloudPosition(index: index, time: 60)
            try require(hypot(initial.x - loopEnd.x, initial.y - loopEnd.y) < 0.000_01,
                        "Cloud \(index) did not return at the minute-loop endpoint")
            for time in [0.0, 6.5, 30, 59.99, 120] {
                let reduced = ShuSkyLayout.cloudPosition(index: index, time: time, reduceMotion: true)
                try require(reduced == initial, "Reduce Motion cloud \(index) moved")
            }
            cloudChecks.append(["index": index, "movesLeft": movesLeft, "movesRight": movesRight,
                "minimumX": positions.map(\.x).min()!, "maximumX": positions.map(\.x).max()!,
                "periodSeconds": cloud.period, "minuteLoopPositionError": hypot(initial.x - loopEnd.x, initial.y - loopEnd.y)])
        }

        let originalReducedMotion = reducedMotion
        defer { reducedMotion = originalReducedMotion }
        reducedMotion = false
        let start = try bitmap(exactScene(0, idle: true, skyTime: 0), scale: 2)
        let moved = try bitmap(exactScene(0, idle: true, skyTime: 15), scale: 2)
        let loop = try bitmap(exactScene(0, idle: true, skyTime: 60), scale: 2)
        func hash(_ image: CGImage) -> String {
            SHA256.hash(data: image.dataProvider!.data! as Data).map { String(format: "%02x", $0) }.joined()
        }
        try require(hash(start) != hash(moved), "Actual sky view did not move at 15 seconds")
        try require(hash(start) == hash(loop), "Actual sky view did not close the 60-second loop")
        let pausedBefore = try bitmap(exactScene(0, idle: true, skyTime: paused), scale: 2)
        let pausedAfter = try bitmap(exactScene(0, idle: true, skyTime: paused), scale: 2)
        try require(hash(pausedBefore) == hash(pausedAfter), "Paused sky frame was not deterministic")
        for time in [0.0, 15, 30, 45, 60] {
            try png(exactScene(0, idle: true, skyTime: time),
                    to: output.appendingPathComponent(String(format: "sky-idle-%05.2fs-2x.png", time)), scale: 2)
        }
        reducedMotion = true
        let reducedStart = try bitmap(exactScene(0, idle: true, skyTime: 0), scale: 2)
        let reducedLater = try bitmap(exactScene(0, idle: true, skyTime: 41), scale: 2)
        try require(hash(reducedStart) == hash(reducedLater), "Actual Reduce Motion sky changed")
        let result: [String: Any] = ["nativePlayback": false, "clockPauseResumePassed": true,
            "repeatedStartPreservesPhase": true, "pausedElapsedSeconds": paused,
            "actualFrameChangesAt15Seconds": true, "actualFrameClosesMinuteLoop": true,
            "actualPausedFramesEqual": true, "actualReduceMotionFramesEqual": true, "clouds": cloudChecks,
            "lifecycleLimit": "Tests one live scene clock. Closing/removing IslandPage destroys its local clock; reopening may restart cloud phase. Native lifecycle timing is separately reviewed."]
        let url = output.appendingPathComponent("sky-motion-audit.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        record(url)
    }

    private static func contactSheet(_ files: [URL], title: String, to url: URL, width: CGFloat = 324) throws {
        let sheet = VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 18, weight: .bold))
            Text("Deterministic ImageRenderer samples; not native animation playback.").font(.system(size: 11))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width)), count: 3), spacing: 14) {
                ForEach(files, id: \.path) { file in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.deletingPathExtension().lastPathComponent).font(.system(size: 10, design: .monospaced))
                        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                            Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: width)
                        }
                    }
                }
            }
        }.padding(18).foregroundStyle(.white).background(Color(white: 0.12))
        try png(sheet, to: url, scale: 1)
    }

    private static func motionPreviews(to output: URL) throws {
        PreviewLanguage.current = "zh-Hans"
        try png(exactScene(0, idle: true), to: output.appendingPathComponent("idle-00.00s-1x.png"), scale: 1)
        try png(exactScene(0, idle: true), to: output.appendingPathComponent("idle-00.00s-2x.png"), scale: 2)
        let times = [0.0, 0.6, 0.96, 3, 5.99, 6, 6.5, 8, 10, 11.99, 12, 13, 17,
                     22.99, 23, 24.5, 27, 29.99, 30, 31, 31.5, 32.99, 33, 37, 45,
                     50.99, 51, 52, 53.99, 54, 55, 55.8, 55.99, 56, 57, 58.5, 59, 59.95, 60]
        var nativeFiles: [URL] = [], gripFiles: [URL] = [], soilFiles: [URL] = [], walkingFiles: [URL] = []
        var nodes: [[String: Any]] = []
        var contactAudits: [[String: Any]] = []
        var visibilityAudits: [[String: Any]] = []
        for time in times {
            try autoreleasepool {
                let name = String(format: "%05.2fs", time)
                let scene = exactScene(time)
                let native = output.appendingPathComponent("motion-\(name)-1x.png")
                try png(scene, to: native, scale: 1)
                try png(scene, to: output.appendingPathComponent("motion-\(name)-2x.png"), scale: 2)
                nativeFiles.append(native)
                if time >= 60 { return }
                let sample = ShuAnimationTimeline.sample(elapsed: time, inventory: inventory, reduceMotion: reducedMotion)
                let rig = sample.rig
                for (name, pose, roastMix) in [("seed", rig.plantPotato, 0.0),
                    ("potato", rig.potato, min(1, max(0, (sample.cycleTime - 33) / 15)))]
                    where pose.attachment == .hand && pose.opacity > 0.5 && pose.burial < 0.1 {
                    // Use the production views and production mapping. Keeping a
                    // second independent drawing recipe here would miss regressions.
                    let actualArm = ZStack {
                        ShuPuppetLayer(sample: sample, depth: .nearArm)
                        ShuPuppetLayer(sample: sample, depth: .fingers)
                    }
                    let armBitmap = try bitmap(actualArm, scale: 4)
                    let propBitmap = try bitmap(ShuPotatoSprite(pose: pose, roastedMix: roastMix), scale: 4)
                    var audit = try alphaContact(arm: armBitmap, prop: propBitmap, wrist: rig.nearArm.wrist)
                    audit["elapsed"] = time; audit["prop"] = name
                    audit["attachment"] = pose.attachment.rawValue
                    audit["stage"] = sample.stage.rawValue
                    contactAudits.append(audit)
                }
                let image = try bitmap(scene, scale: 4)
                for (side, visibility, wrist) in [("left-far", ShuPreviewArmVisibility.nearOnly, rig.farArm.wrist),
                    ("right-near", ShuPreviewArmVisibility.farOnly, rig.nearArm.wrist)] {
                    let omitted = try bitmap(exactScene(time, armVisibility: visibility), scale: 4)
                    var visibilityAudit = try visibleHandContribution(withArm: image, withoutArm: omitted, wrist: wrist)
                    visibilityAudit["elapsed"] = time; visibilityAudit["side"] = side
                    visibilityAudit["stage"] = sample.stage.rawValue
                    visibilityAudits.append(visibilityAudit)
                }
                let grip = output.appendingPathComponent("grip-\(name)-4x.png")
                try crop(image, center: CGPoint(x: rig.nearArm.wrist.x, y: rig.nearArm.wrist.y), radius: 42, scale: 4, to: grip)
                gripFiles.append(grip)
                if (6...30).contains(time) {
                    let soil = output.appendingPathComponent("soil-\(name)-4x.png")
                    try crop(image, center: CGPoint(x: rig.stations.soil.x, y: rig.stations.soil.y), radius: 36, scale: 4, to: soil)
                    soilFiles.append(soil)
                }
                if (30...33).contains(time) || (51...60).contains(time) {
                    let walking = output.appendingPathComponent("walking-\(name)-4x.png")
                    try crop(image, center: CGPoint(x: rig.actor.foot.x, y: rig.actor.foot.y - 20), radius: 45, scale: 4, to: walking)
                    walkingFiles.append(walking)
                }
                nodes.append(["elapsed": time, "stage": sample.stage.rawValue,
                              "nearWrist": [rig.nearArm.wrist.x, rig.nearArm.wrist.y],
                              "actorFoot": [rig.actor.foot.x, rig.actor.foot.y],
                              "soil": [rig.stations.soil.x, rig.stations.soil.y]])
            }
        }
        try contactSheet(nativeFiles, title: "Motion keyframes at original 324 x 186 pt", to: output.appendingPathComponent("motion-contactsheet.png"))
        try contactSheet(gripFiles, title: "Wrist and tool grip - rendered at 4x", to: output.appendingPathComponent("grip-contactsheet.png"), width: 240)
        try contactSheet(soilFiles, title: "Planting, watering and pull - soil close-ups at 4x", to: output.appendingPathComponent("soil-contactsheet.png"), width: 240)
        try contactSheet(walkingFiles, title: "Foot contact and travel - close-ups at 4x", to: output.appendingPathComponent("walking-contactsheet.png"), width: 240)
        let url = output.appendingPathComponent("motion-keyframes.json")
        try JSONSerialization.data(withJSONObject: ["nativePlayback": false, "scenePoints": [324, 186], "inventory": inventory, "nodes": nodes], options: [.prettyPrinted, .sortedKeys]).write(to: url)
        record(url)
        var armRanges: [[String: Any]] = []
        for near in [true, false] {
            var spans: [Double] = [], widths: [Double] = [], heights: [Double] = []
            for time in stride(from: 0.0, to: 60, by: 0.01) {
                let rig = ShuAnimationTimeline.sample(elapsed: time, inventory: inventory, reduceMotion: reducedMotion).rig
                let arm = near ? rig.nearArm : rig.farArm
                let mapping = ShuArmSpriteLayout.mapping(arm)
                spans.append((arm.wrist - arm.shoulder).length)
                widths.append(mapping.size.width); heights.append(mapping.size.height)
            }
            armRanges.append(["arm": near ? "near" : "far", "minimumSpanPoints": spans.min()!,
                "maximumSpanPoints": spans.max()!, "minimumWidthPoints": widths.min()!,
                "maximumWidthPoints": widths.max()!, "minimumHeightPoints": heights.min()!,
                "maximumHeightPoints": heights.max()!, "widthRatio": widths.max()! / widths.min()!,
                "heightRatio": heights.max()! / heights.min()!])
        }
        let auditURL = output.appendingPathComponent("grip-alpha-audit.json")
        try JSONSerialization.data(withJSONObject: ["nativePlayback": false, "inventory": inventory,
            "reduceMotion": reducedMotion, "contactSamples": contactAudits, "armSpriteRanges": armRanges,
            "method": "Production near-arm/finger and potato SwiftUI views rendered separately at 4x; compare alpha >= 0.5 in an 8-point radius around the wrist. Excludes soil burial and roasting-stick contact. Zero silhouette gap alone does not establish natural grip or motion."],
            options: [.prettyPrinted, .sortedKeys]).write(to: auditURL)
        record(auditURL)
        let idleRig = ShuAnimationTimeline.sample(elapsed: 0, inventory: inventory).rig
        for (side, visibility, wrist) in [("left-far", ShuPreviewArmVisibility.nearOnly, idleRig.farArm.wrist),
            ("right-near", ShuPreviewArmVisibility.farOnly, idleRig.nearArm.wrist)] {
            var audit = try visibleHandContribution(withArm: bitmap(exactScene(0, idle: true), scale: 4),
                withoutArm: bitmap(exactScene(0, idle: true, armVisibility: visibility), scale: 4), wrist: wrist)
            audit["elapsed"] = 0; audit["side"] = side; audit["stage"] = "idle"
            visibilityAudits.append(audit)
        }
        let visibilityURL = output.appendingPathComponent("hands-visibility-audit.json")
        try JSONSerialization.data(withJSONObject: ["nativePlayback": false, "inventory": inventory,
            "reduceMotion": reducedMotion, "samples": visibilityAudits,
            "method": "4x same-time production scene A/B with one entire arm omitted. Count RGB differences >= 8/255 within 8 points of its wrist after every foreground layer. This is visible image contribution, not an inferred skeleton or isolated-arm area. Visual review must still establish a recognizable hand."],
            options: [.prettyPrinted, .sortedKeys]).write(to: visibilityURL)
        record(visibilityURL)
        try handoffPreviews(to: output)
        print("Rendered \(times.count) motion keyframes in 1x/2x plus 4x grip, soil and walking crops")
    }

    private static func finish(to output: URL) async throws {
        try verifyAlphaContactMeasurement()
        try verifyVisibleHandMeasurement()
        try skyMotionAudit(to: output)
        if CommandLine.arguments.contains("--variants") {
            let originalInventory = inventory, originalReduced = reducedMotion
            for stock in [0, 12, 13] {
                inventory = stock
                let directory = output.appendingPathComponent("inventory-\(stock)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try motionPreviews(to: directory)
            }
            inventory = originalInventory
            reducedMotion = true
            let directory = output.appendingPathComponent("reduced-motion", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try motionPreviews(to: directory)
            reducedMotion = originalReduced
        }
        // Cross the asset/geometry boundary: the visible endpoint derived from
        // the actual decoded image must match the pure rig's registered point.
        var registrations: [[String: Any]] = []
        for (asset, limit, expected) in [(Shu25DAsset.hoe, CGSize(width: 22, height: 43), ShuRigLayout.hoeTipLocal),
                                        (.wateringCan, CGSize(width: 36, height: 29), ShuRigLayout.canEmitterLocal)] {
            let size = Shu25DAssets.size(asset, fitting: limit)
            let pivot = Shu25DAssets.pivot(asset)
            let end = asset == .wateringCan ? Shu25DAssets.emitter(asset) : Shu25DAssets.end(asset)
            let actual = ShuPoint(x: size.width * (end.x - pivot.x), y: size.height * (end.y - pivot.y))
            let error = (actual - expected).length
            // NSImage can round PNG density-derived logical dimensions slightly.
            // Keep the tolerance below one hundredth of an original-size pixel.
            guard error < 0.01 else {
                throw NSError(domain: "RenderShuPreviews", code: 13,
                              userInfo: [NSLocalizedDescriptionKey: "Visible \(asset.rawValue) endpoint differs from rig by \(error) points"])
            }
            registrations.append(["asset": asset.rawValue, "spriteEndpoint": [actual.x, actual.y],
                                  "rigEndpoint": [expected.x, expected.y], "errorPoints": error,
                                  "tolerancePoints": 0.01])
        }
        let gif = CommandLine.arguments.contains("--animation")
        let full = CommandLine.arguments.contains("--full-60s")
        let video = CommandLine.arguments.contains("--video")
        if gif || full || video { try await frameSequence(to: output, gif: gif, saveFrames: full, video: video) }
        let summary: [String: Any] = ["nativePlayback": false, "productionUserDefaultsAccess": false,
                                      "inventory": inventory, "reduceMotion": reducedMotion,
                                      "toolRegistrations": registrations,
                                      "files": generatedFiles.sorted(),
                                      "usesLegacyCharacterFallback": !Shu25DAssets.hasPuppet,
                                      "assetAvailability": Dictionary(uniqueKeysWithValues: Shu25DAsset.allCases.map { ($0.rawValue, Shu25DAssets.image($0) != nil) })]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("render-summary.json"))
    }

    private static func frameSequence(to output: URL, gif: Bool, saveFrames: Bool, video: Bool) async throws {
        let frameCount = 60 * fps
        let frameDirectory = output.appendingPathComponent("frames", isDirectory: true)
        if saveFrames { try FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true) }
        let gifURL = output.appendingPathComponent("shu-60s-loop.gif")
        let videoURL = output.appendingPathComponent("shu-60s.mp4")
        var videoWriter: AVAssetWriter?
        var videoInput: AVAssetWriterInput?
        var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        if video {
            if FileManager.default.fileExists(atPath: videoURL.path) { try FileManager.default.removeItem(at: videoURL) }
            let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 324, AVVideoHeightKey: 186,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000,
                                                  AVVideoAllowFrameReorderingKey: false]
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw NSError(domain: "RenderShuPreviews", code: 16) }
            writer.add(input)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 324, kCVPixelBufferHeightKey as String: 186,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "RenderShuPreviews", code: 17) }
            writer.startSession(atSourceTime: .zero)
            videoWriter = writer; videoInput = input; videoAdaptor = adaptor
        }
        let destination: CGImageDestination?
        if gif {
            guard let value = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw NSError(domain: "RenderShuPreviews", code: 10)
            }
            destination = value
            CGImageDestinationSetProperties(value, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        } else { destination = nil }
        var hashes = Set<String>()
        var rows: [[String: Any]] = []
        // Full rendering includes the exact settled endpoint; a looping GIF has
        // only 0 <= t < 60 so its duration is exactly 60 seconds.
        let total = frameCount + (saveFrames || video ? 1 : 0)
        for frame in 0..<total {
            try autoreleasepool {
                let time = Double(frame) / Double(fps)
                let image = try bitmap(exactScene(time))
                guard image.width == 324, image.height == 186, let data = image.dataProvider?.data else {
                    throw NSError(domain: "RenderShuPreviews", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unexpected or missing original-size bitmap at \(time)s"])
                }
                let hash = SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
                hashes.insert(hash)
                if let input = videoInput, let adaptor = videoAdaptor, let writer = videoWriter {
                    // Keep the exact t=60 result for a one-second video post-roll.
                    let videoFrames = frame == frameCount ? frameCount..<(frameCount + fps) : frame..<(frame + 1)
                    for videoFrame in videoFrames {
                    let deadline = Date().addingTimeInterval(10)
                    while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    guard input.isReadyForMoreMediaData, writer.status == .writing, let pool = adaptor.pixelBufferPool else {
                        throw writer.error ?? NSError(domain: "RenderShuPreviews", code: 18)
                    }
                    var pixelBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                          let buffer = pixelBuffer else { throw NSError(domain: "RenderShuPreviews", code: 19) }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 324, height: 186,
                                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                        throw NSError(domain: "RenderShuPreviews", code: 20)
                    }
                    context.setFillColor(CGColor(gray: 0, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: 324, height: 186))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 324, height: 186))
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(videoFrame), timescale: Int32(fps))) else {
                        throw writer.error ?? NSError(domain: "RenderShuPreviews", code: 21)
                    }
                    }
                }
                if let destination, frame < frameCount {
                    CGImageDestinationAddImage(destination, image,
                        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary)
                }
                if saveFrames {
                    try savePNG(image, to: frameDirectory.appendingPathComponent(String(format: "%04d.png", frame)))
                }
                rows.append(["frame": frame, "elapsed": time, "rgbaSHA256": hash,
                             "stage": time >= 60 ? "settled" : ShuAnimationTimeline.sample(elapsed: time, inventory: inventory).stage.rawValue])
            }
            if frame % 100 == 0 { print("Full-minute render: \(frame)/\(total)") }
        }
        if let destination {
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "RenderShuPreviews", code: 12) }
            record(gifURL)
            guard let decoded = CGImageSourceCreateWithURL(gifURL as CFURL, nil),
                  CGImageSourceGetCount(decoded) == frameCount else {
                throw NSError(domain: "RenderShuPreviews", code: 14,
                              userInfo: [NSLocalizedDescriptionKey: "GIF frame count did not survive encoding"])
            }
            for time in [0.0, 8, 31, 52, 55.8, 58.5] {
                let index = min(frameCount - 1, Int(time * Double(fps)))
                guard let frame = CGImageSourceCreateImageAtIndex(decoded, index, nil), frame.width == 324, frame.height == 186 else {
                    throw NSError(domain: "RenderShuPreviews", code: 15)
                }
                try savePNG(frame, to: output.appendingPathComponent(String(format: "gif-decoded-%05.2fs.png", Double(index) / Double(fps))))
            }
        }
        if let input = videoInput, let writer = videoWriter {
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: 61, timescale: 1))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? NSError(domain: "RenderShuPreviews", code: 22) }
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard abs(duration.seconds - 61) < 0.001, tracks.count == 1,
                  let track = tracks.first else { throw NSError(domain: "RenderShuPreviews", code: 23) }
            let size = try await track.load(.naturalSize)
            guard size == CGSize(width: 324, height: 186) else { throw NSError(domain: "RenderShuPreviews", code: 24) }
            // Decode one native-size frame to catch orientation/codec mistakes.
            let decoder = AVAssetImageGenerator(asset: asset)
            decoder.appliesPreferredTrackTransform = true
            decoder.requestedTimeToleranceBefore = .zero
            decoder.requestedTimeToleranceAfter = .zero
            let decoded = try await decoder.image(at: CMTime(value: 8, timescale: 1))
            try savePNG(decoded.image, to: output.appendingPathComponent("mp4-decoded-08.00s.png"))
            record(videoURL)
        }
        let summary: [String: Any] = ["nativePlayback": false, "renderedFrames": total, "fps": fps,
                                      "durationSeconds": 60, "scenePoints": [324, 186], "uniqueRGBABuffers": hashes.count,
                                      "includesSettledEndpoint": saveFrames || video, "inventoryBefore": inventory,
                                      "mp4DurationSeconds": video ? 61 : 0, "mp4EncodedFrames": video ? 61 * fps : 0,
                                      "inventoryAfterEndpoint": inventory + 1, "frames": rows]
        let url = output.appendingPathComponent("full-60s-render.json")
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        record(url)
    }
}
