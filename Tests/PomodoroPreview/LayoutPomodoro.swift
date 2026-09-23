import AppKit
import Defaults
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private let suiteName = "dev.validation.pomodoro-layout.\(UUID().uuidString)"
private let fixtureDefaults = UserDefaults(suiteName: suiteName)!
private var catalog: [String: Any] = [:]
private var language = "zh-Hans"
func L(_ key: String) -> String {
    let entry = catalog[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    let locale = localizations?[language] as? [String: Any]
    return ((locale?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
}
enum PomodoroHeatmapPaletteOption: String, Defaults.Serializable {
    case grapePurple
    var core: PomodoroHeatmapPalette { .grapePurple }
}
extension Defaults.Keys {
    static let pomodoroCountdownRingFills = Key<Bool>("ringFills", default: true, suite: fixtureDefaults)
    static let pomodoroHeatmapPalette = Key<PomodoroHeatmapPaletteOption>("palette", default: .grapePurple, suite: fixtureDefaults)
    static let enableHaptics = Key<Bool>("haptics", default: false, suite: fixtureDefaults)
}
final class BoringViewModel: ObservableObject {
    enum NotchState { case open, closed }
    @Published var notchState = NotchState.closed // Freeze only the display timeline during sizing.
}
final class IslandVisibility: ObservableObject {
    static let shared = IslandVisibility()
    var isAvailable = true
}
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func showTimerSettings() {}
}

@main @MainActor
struct LayoutPomodoro {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        defer { fixtureDefaults.removePersistentDomain(forName: suiteName) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
        catalog = json["strings"] as! [String: Any]
        let store = PomodoroSessionStore(directory: URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("sessions"))
        let model = PomodoroModel(store: store)
        var evidence: [[String: Any]] = []
        for locale in ["zh-Hans", "en"] {
            language = locale
            for mode in ["unselected", "countdown", "countup", "running", "paused"] {
                if model.isBusy { model.end() }
                model.cancelConfiguration()
                if mode != "unselected" { model.selectMode(mode == "countup" ? .countup : .countdown) }
                if mode == "running" || mode == "paused" { model.start() }
                if mode == "paused" { model.pause() }
                let name = "page-\(mode)-\(locale)"
                let view = PomodoroPage(model: model).environmentObject(BoringViewModel())
                    .environment(\.locale, Locale(identifier: locale))
                evidence.append(try measure(view, width: 578, height: 136, name: name, output: output))
            }
            Defaults[.pomodoroCountdownRingFills] = false
            let draining = PomodoroPage(model: model).environmentObject(BoringViewModel())
                .environment(\.locale, Locale(identifier: locale))
            evidence.append(try measure(draining, width: 578, height: 136, name: "page-draining-\(locale)", output: output))
            Defaults[.pomodoroCountdownRingFills] = true
            for period in [PomodoroStatsPeriod.month, .year] {
                for picking in [false, true] {
                    let statistics = PomodoroStatistics(model: model, period: .constant(period), picking: picking)
                        .environment(\.locale, Locale(identifier: locale))
                    evidence.append(try measure(statistics, width: 550, height: 136,
                        name: "stats-\(period.rawValue)-\(picking ? "picker" : "chart")-\(locale)", output: output))
                }
            }
            for period in PomodoroStatsPeriod.allCases {
                let dates = period.dates(containing: Date())
                let values = dates.indices.map { $0 % 5 == 0 ? 0.0 : Double(($0 * 7) % 13 + 1) * 600 }
                let chart = PomodoroBarChart(dates: dates, totals: values, period: period, palette: .grapePurple)
                    .environment(\.locale, Locale(identifier: locale))
                evidence.append(try measure(chart, width: period == .week ? 168 : 550, height: 80,
                    name: "bars-\(period.rawValue)-\(locale)", output: output))
            }
        }
        if model.isBusy { model.end() }
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted]).write(to: output.appendingPathComponent("sizes.json"))
        print("PASS: 12 page states, 8 period panels and 6 populated charts exactly match their proposed size; no app/shell interaction simulated.")
    }

    static func measure<V: View>(_ view: V, width: Int, height: Int, name: String, output: URL) throws -> [String: Any] {
        let renderer = ImageRenderer(content: view.background(.black).preferredColorScheme(.dark))
        renderer.proposedSize = ProposedViewSize(width: Double(width), height: Double(height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("No image: \(name)") }
        precondition(image.width == width * 2 && image.height == height * 2,
                     "\(name) overflowed proposal: \(image.width)x\(image.height)")
        // Hosting is necessary for ScrollView's onAppear/scrollPosition and lazy rows.
        let host = NSHostingView(rootView: view.frame(width: Double(width), height: Double(height))
            .background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = CGSize(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        window.close()
        return ["name": name, "width": image.width / 2, "height": image.height / 2]
    }
}
