import Foundation

/// File-backed store for the focus session log: `…/Application Support/boringNotch/Pomodoro/sessions.json`.
///
/// Mirrors `ShelfPersistenceService`: pretty-printed JSON, iso8601 dates, atomic writes and a
/// per-record fallback decode so one corrupted entry can never blank the whole history.
/// On top of the session array it carries the `openRun` slot — the serialized machine state
/// of a session that is still running or paused, which is how a pomodoro survives an app
/// relaunch. Pure Foundation so it is unit-testable with a temporary directory.
final class PomodoroSessionStore {
    struct File: Codable {
        var sessions: [PomodoroSessionRecord] = []
        var openRun: PomodoroRunState?
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let fm = FileManager.default
        let targetDirectory: URL
        if let directory {
            targetDirectory = directory
        } else {
            let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
            targetDirectory = support.appendingPathComponent("boringNotch", isDirectory: true)
                .appendingPathComponent("Pomodoro", isDirectory: true)
        }
        try? fm.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        fileURL = targetDirectory.appendingPathComponent("sessions.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Loads the whole file. If the container itself fails to decode, the session array is
    /// recovered record-by-record and a broken `openRun` is dropped (a lost live session is
    /// preferable to losing the user's entire history).
    func load() -> File {
        guard let data = try? Data(contentsOf: fileURL) else { return File() }
        if let file = try? decoder.decode(File.self, from: data) { return file }
        return File(sessions: recoverSessions(from: data), openRun: nil)
    }

    private func recoverSessions(from data: Data) -> [PomodoroSessionRecord] {
        guard let container = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSessions = container["sessions"] as? [[String: Any]] else { return [] }
        return rawSessions.compactMap { raw in
            guard let recordData = try? JSONSerialization.data(withJSONObject: raw),
                  let record = try? decoder.decode(PomodoroSessionRecord.self, from: recordData) else {
                return nil
            }
            return record
        }
    }

    /// Atomically persists the session log plus the optional live-run state. Callers must
    /// save *before* publishing state changes to the UI.
    func save(_ file: File) {
        do {
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PomodoroSessionStore: failed to save sessions: \(error.localizedDescription)")
        }
    }
}
