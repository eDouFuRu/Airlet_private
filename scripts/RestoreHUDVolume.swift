// Restore only the master volume and mute recorded in hardware-baseline.json.
// Default / --check is read-only. Device writes require the explicit --apply argument.
// No device switching, channel fallback, brightness, private API, permissions or signing.
import Foundation
import CoreAudio

struct RestoreFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

struct Baseline: Decodable {
    struct Reading<T: Decodable>: Decodable { let status: String; let value: T? }
    struct Audio: Decodable {
        struct Master: Decodable {
            let element: UInt32
            let volumeScalar: Reading<Double>
            let mute: Reading<Bool>
        }
        let status: String
        let sameDefaultDeviceAfterRead: Bool
        let deviceUID: Reading<String>
        let master: Master
    }
    let schemaVersion: Int
    let readOnly: Bool
    let audio: Audio

    func target() throws -> (uid: String, volume: Float32, muted: Bool) {
        guard schemaVersion == 1, readOnly, audio.status == "ok", audio.sameDefaultDeviceAfterRead,
              audio.deviceUID.status == "ok", let uid = audio.deviceUID.value, !uid.isEmpty,
              audio.master.element == kAudioObjectPropertyElementMain,
              audio.master.volumeScalar.status == "ok", let volume = audio.master.volumeScalar.value,
              volume.isFinite, (0...1).contains(volume),
              audio.master.mute.status == "ok", let muted = audio.master.mute.value else {
            throw RestoreFailure("Baseline lacks a stable default-device UID, valid master volume or mute; refusing restoration.")
        }
        return (uid, Float32(volume), muted)
    }
}

struct OutputReading {
    let volume: Float32
    let muted: Bool
    var json: [String: Any] { ["volumeScalar": Double(volume), "muted": muted] }
}

func address(_ selector: AudioObjectPropertySelector, global: Bool = false) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: global ? kAudioObjectPropertyScopeGlobal : kAudioObjectPropertyScopeOutput,
          mElement: kAudioObjectPropertyElementMain)
}

func readProperty<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress, initial: T) throws -> T {
    var property = property
    guard AudioObjectHasProperty(id, &property) else { throw RestoreFailure("Required CoreAudio property is unsupported.") }
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0)
    }
    guard status == noErr, size == MemoryLayout<T>.size else {
        throw RestoreFailure("CoreAudio read failed (OSStatus \(status), size \(size)).")
    }
    return value
}

func defaultDevice() throws -> AudioObjectID {
    let id = try readProperty(AudioObjectID(kAudioObjectSystemObject),
                              address(kAudioHardwarePropertyDefaultOutputDevice, global: true), initial: AudioObjectID(0))
    guard id != kAudioObjectUnknown else { throw RestoreFailure("No default output device is visible; no writes performed.") }
    return id
}

func deviceUID(_ id: AudioObjectID) throws -> String {
    let value = try readProperty(id, address(kAudioDevicePropertyDeviceUID, global: true), initial: Optional<CFString>.none)
    guard let value else { throw RestoreFailure("Default output device UID is unavailable.") }
    return value as String
}

func requireSameDefault(_ id: AudioObjectID, uid: String) throws {
    guard try defaultDevice() == id, try deviceUID(id) == uid else {
        throw RestoreFailure("Default output device changed or its UID differs from the baseline; refusing further writes.")
    }
}

func readOutput(_ id: AudioObjectID) throws -> OutputReading {
    let volume = try readProperty(id, address(kAudioDevicePropertyVolumeScalar), initial: Float32(0))
    let mute = try readProperty(id, address(kAudioDevicePropertyMute), initial: UInt32(0))
    guard volume.isFinite, (0...1).contains(volume) else { throw RestoreFailure("Invalid master volume readback.") }
    return OutputReading(volume: volume, muted: mute != 0)
}

func requireSettable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws {
    var property = address(selector)
    var settable: DarwinBoolean = false
    let status = AudioObjectIsPropertySettable(id, &property, &settable)
    guard status == noErr, settable.boolValue else {
        throw RestoreFailure("Baseline master property is not settable (OSStatus \(status)); no fallback is attempted.")
    }
}

// Only this function writes hardware, and it rejects check mode and rechecks default UID.
func writeProperty<T>(_ id: AudioObjectID, uid: String, selector: AudioObjectPropertySelector,
                      value: T, apply: Bool, recordSuccess: () -> Void) throws {
    guard apply else { throw RestoreFailure("Check mode cannot write device properties.") }
    try requireSettable(id, selector)
    try requireSameDefault(id, uid: uid)
    var property = address(selector)
    var value = value
    let status = withUnsafePointer(to: &value) {
        AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
    }
    guard status == noErr else { throw RestoreFailure("CoreAudio write failed (OSStatus \(status)).") }
    // Record a successful write even if the output changes immediately afterward.
    recordSuccess()
    try requireSameDefault(id, uid: uid)
}

func confirmReadback(_ id: AudioObjectID, uid: String,
                     matches: (OutputReading) -> Bool) throws -> OutputReading {
    for attempt in 0..<10 {
        try requireSameDefault(id, uid: uid)
        let actual = try readOutput(id)
        if matches(actual) { return actual }
        if attempt < 9 { Thread.sleep(forTimeInterval: 0.05) }
    }
    throw RestoreFailure("Hardware readback does not match the saved baseline; no success is reported.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let apply = arguments == ["--apply"]
var report: [String: Any] = ["mode": apply ? "apply" : "check", "writesCompleted": [String](), "status": "error"]
var completedWrites: [String] = []
var resultCode: Int32 = 0
do {
    guard arguments.isEmpty || arguments == ["--check"] || apply else {
        throw RestoreFailure("Usage: RestoreHUDVolume.swift [--check|--apply]. No arguments means read-only check.")
    }
    let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/validation/hud25d/hardware-baseline.json")
    report["baselinePath"] = baselineURL.path
    let baseline = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: baselineURL))
    let target = try baseline.target()
    report["targetUID"] = target.uid
    report["target"] = OutputReading(volume: target.volume, muted: target.muted).json
    let id = try defaultDevice()
    report["currentDeviceID"] = id
    report["currentUID"] = try deviceUID(id)
    try requireSameDefault(id, uid: target.uid)
    let before = try readOutput(id)
    report["before"] = before.json
    // Preflight both properties before permitting a partial restoration.
    try requireSettable(id, kAudioDevicePropertyVolumeScalar)
    try requireSettable(id, kAudioDevicePropertyMute)
    try requireSameDefault(id, uid: target.uid)
    if apply {
        // If restoring a muted baseline, mute first. Otherwise restore level before unmuting.
        if target.muted && !before.muted {
            try writeProperty(id, uid: target.uid, selector: kAudioDevicePropertyMute, value: UInt32(1), apply: apply) {
                completedWrites.append("mute")
            }
            _ = try confirmReadback(id, uid: target.uid) { $0.muted }
        }
        if before.volume != target.volume {
            try writeProperty(id, uid: target.uid, selector: kAudioDevicePropertyVolumeScalar, value: target.volume, apply: apply) {
                completedWrites.append("volumeScalar")
            }
            _ = try confirmReadback(id, uid: target.uid) { $0.volume == target.volume }
        }
        let current = try readOutput(id)
        if current.muted != target.muted {
            try writeProperty(id, uid: target.uid, selector: kAudioDevicePropertyMute,
                              value: UInt32(target.muted ? 1 : 0), apply: apply) {
                completedWrites.append("mute")
            }
        }
        let actual = try confirmReadback(id, uid: target.uid) { $0.volume == target.volume && $0.muted == target.muted }
        report["after"] = actual.json
        report["status"] = "restored"
        report["matchesBaselineExactly"] = true
    } else {
        report["status"] = "ready"
        report["matchesBaselineExactly"] = before.volume == target.volume && before.muted == target.muted
    }
} catch {
    report["error"] = String(describing: error)
    resultCode = 1
}
report["writesCompleted"] = completedWrites
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data([0x0a]))
exit(resultCode)
