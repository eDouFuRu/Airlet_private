import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private var catalog: [String: Any] = [:]
private var language = "zh-Hans"
func L(_ key: String) -> String {
    let entry = catalog[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    let locale = localizations?[language] as? [String: Any]
    return ((locale?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
}

@main @MainActor
struct RenderPomodoro {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
        catalog = json["strings"] as! [String: Any]
        let progress = [0.0, 0.0001, 0.125, 0.5, 0.98, 1, 1.02, 1.25, 2.5]
        let rings = VStack(spacing: 12) {
            ForEach(PomodoroHeatmapPalette.allCases, id: \.self) { palette in
                HStack(spacing: 12) {
                    ForEach(progress, id: \.self) { value in
                        VStack {
                            PomodoroRingCanvas(progress: value, baseRGB: palette.baseRGB).frame(width: 128, height: 128)
                            Text(String(format: "%.4g", value)).font(.system(size: 10)).foregroundStyle(.white)
                        }
                    }
                }
            }
        }.padding(16).background(.black)
        try render(rings, output.appendingPathComponent("rings.png"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!
        for locale in ["zh-Hans", "en"] {
            language = locale
            let sheet = VStack(spacing: 18) {
                HStack(spacing: 16) {
                    stats(monday, calendar, totals: [0, 125, 1800, 4500, 7400, 0, 0], hover: nil)
                    stats(monday, calendar, totals: [0, 125, 1800, 4500, 7400, 0, 0], hover: 0)
                    stats(monday, calendar, totals: [360000, 180000, 9000, 0, 0, 0, 0], hover: nil)
                    stats(monday.addingTimeInterval(-7 * 86400), calendar, totals: [0, 0, 0, 0, 0, 0, 0], hover: nil)
                }
                HStack(spacing: 16) {
                    ForEach(0..<7, id: \.self) { index in
                        stats(monday, calendar, totals: [0, 125, 1800, 4500, 7400, 0, 0], hover: index)
                    }
                }
            }.padding(16).background(.black).environment(\.locale, Locale(identifier: locale))
            try render(sheet, output.appendingPathComponent("stats-\(locale).png"))
        }
        // Deterministic accelerated samples, taken from the exact production Canvas.
        let frames = output.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        for frame in 0..<181 {
            let value = Double(frame) / 180 * 2.25
            let image = ZStack {
                PomodoroRingCanvas(progress: value, baseRGB: PomodoroHeatmapPalette.tomatoRed.baseRGB)
                Text(String(format: "%.2f", value)).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(.white)
            }.frame(width: 128, height: 128).padding(12).background(.black)
            try render(image, frames.appendingPathComponent(String(format: "%03d.png", frame)))
        }
        print("Rendered production rings, bilingual stats, all hover positions and 181 accelerated frames.")
        fflush(stdout)
        try modelChecks(output: output, scratch: URL(fileURLWithPath: CommandLine.arguments[3]))
    }

    static func stats(_ monday: Date, _ calendar: Calendar, totals: [Double], hover: Int?) -> some View {
        PomodoroWeekStats(weekStart: monday, dailyTotals: totals, palette: .grapePurple,
                          calendar: calendar, today: calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!,
                          previewHoveredDay: hover)
            .frame(width: 168, height: 136).background(.black)
    }

    static func render<V: View>(_ view: V, _ url: URL) throws {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "PomodoroPreview", code: 1)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "PomodoroPreview", code: 2) }
    }

    static func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func modelChecks(output: URL, scratch: URL) throws {
        let store = PomodoroSessionStore(directory: scratch.appendingPathComponent("test-sessions"))
        let model = PomodoroModel(store: store)
        model.selectMode(.countdown)
        model.setDuration(seconds: 60)
        model.start()
        let id = model.ringPresentation.sessionID
        spin(1.2)
        precondition(model.remainingSeconds < 60, "Real model ticker must publish")
        model.pause()
        let paused = model.ringPresentation.progress(at: Date())!
        spin(1.2)
        precondition(model.ringPresentation.progress(at: Date())! == paused)
        precondition(store.load().openRun?.phase == .paused)
        model.resume()
        precondition(model.ringPresentation.sessionID == id)
        print("Real 60-second model session running; pause/persistence already verified.")
        fflush(stdout)
        spin(60)
        precondition(model.phase == .idle && model.justCompleted)
        precondition(store.load().sessions.count == 1 && store.load().openRun == nil)
        precondition(store.load().sessions[0].elapsedSeconds == 60)
        model.start()
        precondition(!model.justCompleted && model.completionPresentedAt == nil)
        precondition(model.ringPresentation.progress(at: Date())! < 0.01)
        spin(3.3)
        precondition(model.phase == .running && model.ringPresentation.sessionID != id)
        model.end()
        precondition(model.ringPresentation.progress(at: Date()) == nil)
        // Restore a synthetic overdue session to verify feedback expiration independently.
        var state = PomodoroRunState()
        _ = PomodoroSessionCore.selectMode(.countdown, state: &state)
        _ = PomodoroSessionCore.setDuration(seconds: 60, state: &state)
        _ = PomodoroSessionCore.start(&state, now: Date().addingTimeInterval(-61))
        store.save(.init(sessions: [], openRun: state))
        let restored = PomodoroModel(store: store)
        precondition(restored.justCompleted && restored.phase == .idle)
        spin(3.4)
        precondition(!restored.justCompleted && restored.completionPresentedAt == nil)
        let summary: [String: Any] = ["realCountdownSeconds": 60, "ticker": "passed", "pauseResume": "passed",
            "completionPersistence": "passed", "newSessionClearsCompletion": "passed", "restoredCompletionFadeCleanup": "passed",
            "productionDataReadOrWritten": false, "nativeIslandHoverVerified": false]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted]).write(to: output.appendingPathComponent("model-checks.json"))
        print("Model lifecycle checks passed, using temporary sessions only.")
    }
}
