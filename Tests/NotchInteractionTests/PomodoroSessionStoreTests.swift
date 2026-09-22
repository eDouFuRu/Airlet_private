import XCTest
@testable import NotchInteractionCore

final class PomodoroSessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: PomodoroSessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PomodoroStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = PomodoroSessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleRecord(topic: String? = nil, startedAt: Date = Date(timeIntervalSince1970: 1_789_000_000),
                              elapsed: Double = 1_500) -> PomodoroSessionRecord {
        PomodoroSessionRecord(topic: topic, mode: .countdown, plannedSeconds: 1_500,
                              startedAt: startedAt, endedAt: startedAt.addingTimeInterval(elapsed),
                              elapsedSeconds: elapsed)
    }

    func testMissingFileLoadsEmpty() {
        let file = store.load()
        XCTAssertTrue(file.sessions.isEmpty)
        XCTAssertNil(file.openRun)
    }

    func testRoundTripPersistsSessionsAndOpenRun() {
        var openRun = PomodoroRunState()
        openRun.phase = .running
        openRun.mode = .countdown
        openRun.topic = "review PR"
        openRun.sessionID = UUID()
        openRun.startedAt = Date(timeIntervalSince1970: 1_789_000_500)
        openRun.lastResumedAt = Date(timeIntervalSince1970: 1_789_000_510)

        let records = [sampleRecord(topic: "deep work"), sampleRecord(topic: nil)]
        store.save(PomodoroSessionStore.File(sessions: records, openRun: openRun))

        let loaded = store.load()
        XCTAssertEqual(loaded.sessions, records)
        XCTAssertEqual(loaded.openRun, openRun)
    }

    func testSaveOverwritesAtomically() {
        store.save(PomodoroSessionStore.File(sessions: [sampleRecord()], openRun: nil))
        store.save(PomodoroSessionStore.File(sessions: [], openRun: nil))
        XCTAssertTrue(store.load().sessions.isEmpty, "the last save wins in full")
    }

    func testCorruptedContainerRecoversValidRecordsAndDropsOpenRun() throws {
        let valid = sampleRecord(topic: "survivor")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let recordJSON = String(data: try encoder.encode([valid]), encoding: .utf8)!
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespacesAndNewlines))
        // A container whose openRun is garbage and whose second record is malformed.
        let broken = """
        {
          "sessions": [\(recordJSON), { "mode": "countdown", "elapsedSeconds": "not-a-number" }],
          "openRun": { "phase": "running", "mode": 42 }
        }
        """
        try broken.data(using: .utf8)!.write(to: directory.appendingPathComponent("sessions.json"))

        let loaded = store.load()
        XCTAssertEqual(loaded.sessions, [valid], "the valid record survives the fallback decode")
        XCTAssertNil(loaded.openRun, "an unreadable live run is dropped rather than failing the load")
    }

    func testTotalGarbageLoadsEmpty() throws {
        try Data("not json at all".utf8).write(to: directory.appendingPathComponent("sessions.json"))
        let loaded = store.load()
        XCTAssertTrue(loaded.sessions.isEmpty)
        XCTAssertNil(loaded.openRun)
    }
}
