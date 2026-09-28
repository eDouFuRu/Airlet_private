// Offline QA compiles the real compact HUD, brief row, colors and glass surface.
// Models/settings are isolated; hardware writes abort immediately.
import AppKit
import Defaults
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum SneakContentType { case volume, brightness, backlight, mic, music }
extension Color { static var effectiveAccent: Color { Color(red: 0.96, green: 0.67, blue: 0.30) } }
enum PreviewLanguage { static var current = "en" }
func L(_ text: String) -> String {
    guard let path = Bundle.main.path(forResource: PreviewLanguage.current, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return text }
    return bundle.localizedString(forKey: text, value: text, table: nil)
}
final class BoringViewModel: ObservableObject {
    enum NotchState { case open, closed }
    @Published var notchState = NotchState.closed
}
@MainActor final class VolumeManager {
    static let shared = VolumeManager()
    func setAbsolute(_ value: Float) { fatalError("Offline QA forbids hardware writes") }
}
@MainActor final class BrightnessManager {
    static let shared = BrightnessManager()
    func setAbsolute(value: Float) { fatalError("Offline QA forbids hardware writes") }
}
@MainActor final class KeyboardBacklightManager {
    static let shared = KeyboardBacklightManager()
    func setAbsolute(value: Float) { fatalError("Offline QA forbids hardware writes") }
}
// Compile-time stubs for the separate charging row, which is not rendered here.
final class BatteryStatusViewModel: ObservableObject {
    static let shared = BatteryStatusViewModel()
    var statusText = "Charging"
    var isPluggedIn = true
    var isCharging = true
    var isInLowPowerMode = false
    var levelBattery: Float = 62
}
struct BoringBatteryView: View {
    var batteryWidth: CGFloat
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var isPluggedIn: Bool
    var levelBattery: Float
    var isForNotification: Bool
    var body: some View { EmptyView() }
}

private struct HUDPreviewShell: View {
    let state: SystemHUDState
    let layout: SystemHUDLayout
    let expanded: Bool
    let floating: Bool
    let scheme: ColorScheme
    let language: String
    let scenario: String
    let width: CGFloat
    let height: CGFloat
    let header: CGFloat

    private var appearance: IslandAppearance { .init(isFloating: floating, colorScheme: scheme) }
    var body: some View {
        VStack(spacing: 0) {
            if scenario == "lyrics" || scenario == "notification" {
                BriefPromptRow(text: scenario == "lyrics"
                    ? (language == "en" ? "A gentle breeze carries the melody" : "微风轻轻吹过，歌声慢慢流淌")
                    : (language == "en" ? "Example team · A synthetic preview notification" : "示例项目群 · 这是一条排版测试通知"),
                    symbol: scenario == "lyrics" ? "text.quote" : "message.fill",
                    height: header, scrolls: false)
            } else if floating && !expanded {
                FloatingSystemHUD(state: state, height: header).padding(.horizontal, 10)
            } else {
                InlineHUD(state: state, layout: layout)
                    .padding(.horizontal, expanded ? SystemHUDLayout.openInset : SystemHUDLayout.closedInset)
            }
            if expanded {
                // Deliberately labeled geometry fixture; no claim of page coverage.
                VStack(spacing: 14) {
                    Text(language == "en" ? "Expanded surface fixture" : "展开外壳排版预览")
                        .font(.system(size: 18, weight: .semibold))
                    Text(language == "en" ? "Production HUD and contour · isolated content" : "实际 HUD 与外壳轮廓 · 隔离内容")
                        .font(.system(size: 12)).foregroundStyle(appearance.secondary)
                    HStack(spacing: 12) {
                        ForEach(["timer", "calendar", "folder"], id: \.self) { symbol in
                            Image(systemName: symbol).frame(width: 90, height: 48)
                                .background(appearance.controlFill, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .foregroundStyle(appearance.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        // Native glass is compiled separately below; ImageRenderer cannot
        // capture its WindowServer-backed layer, so content QA uses a backdrop.
        .background(floating ? (scheme == .light ? Color(white: 0.94) : Color(white: 0.12)) : .black)
        .clipShape(IslandSurfaceShape(
            topRadius: floating ? (expanded ? 24 : header / 2) : (expanded ? 19 : 6),
            bottomRadius: floating ? (expanded ? 24 : header / 2) : (expanded ? 24 : 14),
            contour: floating ? .floating : .notch))
        .environment(\.islandAppearance, appearance)
        .environment(\.locale, Locale(identifier: language))
        .preferredColorScheme(scheme)
        .transaction { $0.disablesAnimations = true }
    }
}

@main @MainActor struct RenderHUDPreviews {
    static func png<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws -> CGImage {
        let warmup = ImageRenderer(content: view)
        warmup.scale = scale
        _ = warmup.cgImage
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let bitmap = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "RenderHUDPreviews", code: 1)
        }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "RenderHUDPreviews", code: 2) }
        return bitmap
    }

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var records: [[String: Any]] = []
        for language in ["zh-Hans", "en"] {
            PreviewLanguage.current = language
            for style in ["attached-dark", "glass-light", "glass-dark"] {
                let floating = style != "attached-dark"
                let scheme: ColorScheme = style == "glass-light" ? .light : .dark
                var imageNames: [String] = []
                for expanded in [false, true] {
                    for compactHeight in floating && !expanded ? [CGFloat(18), 24] : [CGFloat(18)] {
                    for scenario in ["volume", "brightness", "error", "backlight", "mic", "lyrics", "notification"] {
                        if !floating && (scenario == "lyrics" || scenario == "notification") { continue }
                        var state = SystemHUDState()
                        state.setApplicationAvailable(true)
                        let kind: SystemHUDKind = scenario == "brightness" || scenario == "error" ? .brightness : scenario == "backlight" ? .backlight : scenario == "mic" ? .mic : .volume
                        state.show(kind: kind, value: scenario == "mic" ? 0 : 0.625,
                            error: scenario == "error" ? "Unable to read brightness after changing it." : nil, now: 0)
                        let header: CGFloat = floating ? (expanded ? 36 : compactHeight) : 32
                        let width: CGFloat = expanded ? 640 : floating ? 320 : 400
                        let height: CGFloat = expanded ? 250 : header
                        let gap: CGFloat = floating ? 0 : 180
                        let layout = SystemHUDLayout(active: true, inline: true, expanded: expanded,
                            notchWidth: gap, headerHeight: header,
                            baseClosedSize: CGSize(width: width, height: header), baseExpandedHeight: height)
                        let vm = BoringViewModel(); vm.notchState = expanded ? .open : .closed
                        let name = "\(language)-\(style)-\(expanded ? "open" : "closed")-\(scenario)" + (floating && !expanded ? "-h\(Int(header))" : "")
                        let view = HUDPreviewShell(state: state, layout: layout, expanded: expanded,
                            floating: floating, scheme: scheme, language: language, scenario: scenario,
                            width: width, height: height, header: header).environmentObject(vm)
                        let bitmap = try png(view, to: output.appendingPathComponent(name + ".png"))
                        precondition(bitmap.width == Int(width * 2) && bitmap.height == Int(height * 2))
                        imageNames.append(name)
                        records.append(["name": name, "width": width, "height": height,
                            "physicalGapWidth": gap, "headerHeight": header,
                            "floating": floating, "expanded": expanded,
                            "colorScheme": scheme == .light ? "light" : "dark", "scenario": scenario,
                            "language": language, "topInset": floating ? 3 : 0])
                    }
                }
                }
                let sheet = VStack(alignment: .leading, spacing: 12) {
                    Text("Production HUD / brief / contour · \(language) · \(style)").font(.system(size: 20, weight: .bold))
                    Text("18 / 24 pt floating capsules · 36 pt expanded headers · isolated static fixtures")
                        .font(.system(size: 12))
                    Text("Deterministic backdrops · materialEvidence=false · native glass not captured")
                        .font(.system(size: 12))
                    LazyVGrid(columns: [GridItem(.fixed(640)), GridItem(.fixed(640))], spacing: 16) {
                        ForEach(imageNames, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(name).font(.system(size: 11))
                                if let source = CGImageSourceCreateWithURL(output.appendingPathComponent(name + ".png") as CFURL, nil),
                                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                                    Image(decorative: image, scale: 2).frame(width: 640)
                                }
                            }
                        }
                    }
                }.padding(24)
                    .foregroundStyle(scheme == .light ? Color.black : Color.white)
                    .background(scheme == .light ? Color(white: 0.9) : Color(white: 0.14))
                _ = try png(sheet, to: output.appendingPathComponent("overview-\(language)-\(style).png"), scale: 1)
            }
        }
        let report: [String: Any] = [
            "staticOnly": true, "hardwareCallsAllowed": false,
            "usesActualHUDComponents": true, "usesActualOutline": true, "nativeGlassVisualVerified": false, "materialEvidence": false, "usesActualContentView": false,
            "scenarios": records,
            "limitations": "ImageRenderer omits native glass layers, so these content snapshots use deterministic backdrops and production outlines. They cannot verify desktop glass refraction, native pointer routing or all application pages. Expanded body uses explicitly labeled geometry fixtures."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("geometry.json"))
        print("Rendered \(records.count) production component states and 6 contact sheets; no hardware calls.")
    }
}
