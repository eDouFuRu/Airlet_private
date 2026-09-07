// Offline QA harness: actual HUD, progress bar, notch shape and IslandPage views.
// Only models/settings/hardware controls are isolated stubs; no window is shown.
import AppKit
import Defaults
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum SneakContentType { case volume, brightness, backlight, mic, music }
extension Color { static var effectiveAccent: Color { Color(red: 0.96, green: 0.67, blue: 0.30) } }
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

@MainActor private struct HUDPreviewShell: View {
    let state: SystemHUDState
    let layout: SystemHUDLayout
    let expanded: Bool
    let baseExpandedHeight: CGFloat
    let language: String
    let guides: Bool

    var body: some View {
        VStack(spacing: 0) {
            if layout.showsInline {
                InlineHUD(state: state, layout: layout)
            } else {
                // The default HUD leaves the page header in place. This header
                // is a geometry fixture; the HUD row and page below are actual views.
                HStack {
                    Image(systemName: "leaf").foregroundStyle(.green)
                    Spacer(minLength: 0)
                    Color.clear.frame(width: layout.physicalGapWidth)
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape").foregroundStyle(.gray)
                }.padding(.horizontal, 10).frame(height: layout.headerHeight)
            }
            if layout.showsRow { SystemHUDRow(state: state) }
            if expanded {
                IslandPage(presentationID: UUID())
                    .padding(.top, 8)
                    .frame(height: max(0, baseExpandedHeight - layout.headerHeight - 12), alignment: .top)
            }
        }
        .padding(.horizontal, expanded ? 31 : 6)
        .padding(.bottom, expanded ? 12 : 0)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: expanded ? 19 : 6, bottomCornerRadius: expanded ? 24 : 14))
        .overlay(alignment: .top) {
            if guides {
                Rectangle().stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                    .frame(width: layout.physicalGapWidth, height: layout.headerHeight)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.locale, Locale(identifier: language))
        .preferredColorScheme(.dark)
        .transaction { $0.disablesAnimations = true }
    }
}

@main @MainActor struct RenderHUDPreviews {
    static func png<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws -> CGImage {
        // A fresh offline process can rasterize its first use of an SF Symbol
        // before that symbol's font/image finishes loading. Warm the same view,
        // then allow the main run loop to service that read-only asset work.
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
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        let safeTop = screen?.safeAreaInsets.top ?? 0
        let left = screen?.auxiliaryTopLeftArea?.width
        let right = screen?.auxiliaryTopRightArea?.width
        let hasRealNotch = safeTop > 0 && left != nil && right != nil
        let gap: CGFloat = hasRealNotch ? max(0, screen!.frame.width - left! - right!) : 120
        let headerHeight = max(24, hasRealNotch ? safeTop : 32)
        let baseExpandedHeight = max(250, headerHeight + 214)
        let model = IslandRestModel.shared
        model.phase = .idle; model.mode = .rest; model.potatoCount = 3
        model.elapsedSeconds = 0; model.durationMinutes = 1
        var records: [[String: Any]] = []
        var imageNames: [String: [String]] = [:]
        for language in ["zh-Hans", "en"] {
            PreviewLanguage.current = language
            imageNames[language] = []
            for expanded in [false, true] {
                for inline in [true, false] {
                    PreviewHUDDefaults.inlineHUD = inline
                    for scenario in ["volume", "brightness", "error", "backlight", "mic"] {
                        var state = SystemHUDState()
                        state.setApplicationAvailable(true)
                        let kind: SystemHUDKind = scenario == "brightness" || scenario == "error" ? .brightness : scenario == "backlight" ? .backlight : scenario == "mic" ? .mic : .volume
                        state.show(kind: kind, value: scenario == "mic" ? 0 : 0.625,
                                   error: scenario == "error" ? "Unable to read brightness after changing it." : nil, now: 0)
                        let layout = SystemHUDLayout(active: true, inline: inline, expanded: expanded,
                            notchWidth: gap, headerHeight: headerHeight,
                            baseClosedSize: CGSize(width: gap + 88, height: headerHeight),
                            baseExpandedHeight: baseExpandedHeight)
                        let vm = BoringViewModel(); vm.notchState = expanded ? .open : .closed
                        let name = "\(language)-\(expanded ? "open" : "closed")-\(inline ? "inline" : "default")-\(scenario)"
                        let view = HUDPreviewShell(state: state, layout: layout, expanded: expanded,
                            baseExpandedHeight: baseExpandedHeight, language: language, guides: false)
                            .environmentObject(vm).environmentObject(NotchPointerCoordinator())
                        _ = try png(view, to: output.appendingPathComponent(name + ".png"))
                        imageNames[language]!.append(name)
                        records.append(["name": name, "width": layout.size.width, "height": layout.size.height,
                            "physicalGapWidth": gap, "headerHeight": headerHeight,
                            "rowHeight": SystemHUDLayout.rowHeight,
                            "pageBodyHeight": expanded ? baseExpandedHeight - headerHeight - 12 : 0,
                            "pageBodyTop": expanded ? headerHeight + (inline ? 0 : SystemHUDLayout.rowHeight) : 0])
                        if scenario == "volume" {
                            let guided = HUDPreviewShell(state: state, layout: layout, expanded: expanded,
                                baseExpandedHeight: baseExpandedHeight, language: language, guides: true)
                                .environmentObject(vm).environmentObject(NotchPointerCoordinator())
                                .padding(.bottom, 16).background(Color(white: 0.19))
                            _ = try png(guided, to: output.appendingPathComponent(name + "-camera-guide.png"))
                        }
                    }
                }
            }
            let comparisonVM = BoringViewModel()
            comparisonVM.notchState = .closed
            let rowWidth: CGFloat = 320
            let comparison = HStack(alignment: .top, spacing: 16) {
                ForEach(["volume", "brightness", "lyrics"], id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(kind) · \(Int(kind == "lyrics" ? BriefPresentationLayout.rowHeight : SystemHUDLayout.rowHeight)) pt")
                            .font(.system(size: 13, weight: .medium))
                        VStack(spacing: 0) {
                            Color.clear.frame(height: headerHeight)
                            if kind == "lyrics" {
                                BriefPromptRow(text: language == "en" ? "A gentle breeze carries the melody" : "微风轻轻吹过，歌声慢慢流淌",
                                               symbol: "text.quote", scrolls: false)
                            } else {
                                SystemHUDRow(state: Self.comparisonState(kind: kind))
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(width: rowWidth)
                        .background(.black)
                        .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
                    }
                }
            }
            .padding(20)
            .foregroundStyle(.white)
            .background(Color(white: 0.14))
            .environmentObject(comparisonVM)
            .environment(\.locale, Locale(identifier: language))
            .preferredColorScheme(.dark)
            .transaction { $0.disablesAnimations = true }
            _ = try png(comparison, to: output.appendingPathComponent("compact-rows-\(language).png"))
            let sheet = VStack(alignment: .leading, spacing: 16) {
                Text("Production HUD components · \(language) · static QA").font(.system(size: 22, weight: .bold))
                Text("Actual camera gap \(gap, specifier: "%.1f") pt · header \(headerHeight, specifier: "%.1f") pt · models and hardware isolated")
                    .font(.system(size: 12))
                LazyVGrid(columns: [GridItem(.fixed(640)), GridItem(.fixed(640))], spacing: 18) {
                    ForEach(imageNames[language]!, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(name).font(.system(size: 12, weight: .medium))
                            if let source = CGImageSourceCreateWithURL(output.appendingPathComponent(name + ".png") as CFURL, nil),
                               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                                Image(decorative: image, scale: 2).frame(width: 640, alignment: .center)
                            }
                        }
                    }
                }
            }.padding(24).foregroundStyle(.white).background(Color(white: 0.14))
            _ = try png(sheet, to: output.appendingPathComponent("overview-\(language).png"), scale: 1)
        }
        let report: [String: Any] = [
            "staticOnly": true, "hardwareCallsAllowed": false, "usesActualIslandPage": true,
            "usesActualHUDComponents": true, "usesActualContentView": false,
            "screenName": screen?.localizedName ?? "No screen", "hasRealNotch": hasRealNotch,
            "screenWidth": screen?.frame.width ?? 0, "safeAreaTop": safeTop,
            "auxiliaryLeftWidth": left ?? 0, "auxiliaryRightWidth": right ?? 0,
            "physicalGapWidth": gap, "scenarios": records,
            "limitations": "ImageRenderer frames, isolated settings/models, representative default header. Does not test actual keys, event taps, hardware writes, hover, focus, native windows or animation."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("geometry.json"))
        print("Rendered \(records.count) HUD states, 8 camera guides and 2 contact sheets. Gap=\(gap), safeTop=\(safeTop), realNotch=\(hasRealNotch)")
    }

    private static func comparisonState(kind: String) -> SystemHUDState {
        var state = SystemHUDState()
        state.setApplicationAvailable(true)
        state.show(kind: kind == "brightness" ? .brightness : .volume, value: 0.625, now: 0)
        return state
    }
}
