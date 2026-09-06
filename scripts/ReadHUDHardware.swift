// Read-only hardware baseline for native HUD verification.
// Run with: xcrun swift -module-cache-path /private/tmp/notchisland-hardware-module-cache scripts/ReadHUDHardware.swift
// Only public CoreAudio / IODisplay getters are used. No device setters, private APIs,
// event synthesis, permission prompts, keychain access, or application dependencies.
import Foundation
import CoreAudio
import IOKit
import IOKit.graphics

typealias JSONObject = [String: Any]

func audioAddress(_ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

func failure(_ status: OSStatus, operation: String) -> JSONObject {
    ["status": "error", "operation": operation, "osStatus": Int(status)]
}

func readAudioProperty<T>(_ id: AudioObjectID, address: AudioObjectPropertyAddress,
                          initial: T) -> (T?, JSONObject) {
    var address = address
    guard AudioObjectHasProperty(id, &address) else {
        return (nil, ["status": "unsupported", "reason": "CoreAudio property is not exposed by this device."])
    }
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let result = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard result == noErr else { return (nil, failure(result, operation: "AudioObjectGetPropertyData")) }
    guard size == MemoryLayout<T>.size else {
        return (nil, ["status": "error", "reason": "Unexpected CoreAudio property size.", "bytes": size])
    }
    return (value, ["status": "ok"])
}

func readAudioString(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> JSONObject {
    let (value, status) = readAudioProperty(id, address: audioAddress(selector, scope: kAudioObjectPropertyScopeGlobal),
                                          initial: Optional<CFString>.none)
    guard let wrapped = value, let text = wrapped else { return status }
    return ["status": "ok", "value": text as String]
}

func readVolume(_ id: AudioObjectID, element: UInt32) -> JSONObject {
    let (value, status) = readAudioProperty(id, address: audioAddress(kAudioDevicePropertyVolumeScalar, element: element),
                                          initial: Float32(0))
    guard let value else { return status }
    guard value.isFinite && (0...1).contains(value) else {
        return ["status": "error", "reason": "Volume scalar is not finite or outside 0...1."]
    }
    return ["status": "ok", "value": Double(value)]
}

func readMute(_ id: AudioObjectID, element: UInt32) -> JSONObject {
    let (value, status) = readAudioProperty(id, address: audioAddress(kAudioDevicePropertyMute, element: element),
                                          initial: UInt32(0))
    guard let value else { return status }
    return ["status": "ok", "value": value != 0]
}

func outputChannels(_ id: AudioObjectID) -> (UInt32?, JSONObject) {
    var address = audioAddress(kAudioDevicePropertyStreamConfiguration)
    guard AudioObjectHasProperty(id, &address) else {
        return (nil, ["status": "unsupported", "reason": "Output stream configuration is unavailable."])
    }
    var size: UInt32 = 0
    var result = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    guard result == noErr else { return (nil, failure(result, operation: "AudioObjectGetPropertyDataSize")) }
    let headerSize = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size
    guard size >= headerSize, size <= 1_048_576 else {
        return (nil, ["status": "error", "reason": "Unexpected output stream configuration size.", "bytes": size])
    }
    let allocatedSize = Int(size)
    let storage = UnsafeMutableRawPointer.allocate(byteCount: allocatedSize,
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    result = AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage)
    guard result == noErr else { return (nil, failure(result, operation: "AudioObjectGetPropertyData(streamConfiguration)")) }
    let buffers = storage.assumingMemoryBound(to: AudioBufferList.self)
    let capacity = (allocatedSize - headerSize) / MemoryLayout<AudioBuffer>.size
    guard Int(buffers.pointee.mNumberBuffers) <= capacity else {
        return (nil, ["status": "error", "reason": "Output buffer list exceeds its allocated size."])
    }
    let total = UnsafeMutableAudioBufferListPointer(buffers).reduce(UInt64(0)) { $0 + UInt64($1.mNumberChannels) }
    guard total <= 1024 else {
        return (nil, ["status": "error", "reason": "Output channel count exceeds the bounded baseline probe.", "count": total])
    }
    return (UInt32(total), ["status": "ok", "count": total])
}

func defaultOutputDevice() -> (AudioObjectID?, JSONObject) {
    readAudioProperty(AudioObjectID(kAudioObjectSystemObject),
                      address: audioAddress(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal),
                      initial: AudioObjectID(kAudioObjectUnknown))
}

func audioBaseline() -> JSONObject {
    let (device, status) = defaultOutputDevice()
    guard let device else { return status }
    guard device != kAudioObjectUnknown else {
        return ["status": "unsupported", "reason": "No default output audio device."]
    }
    let (count, channelStatus) = outputChannels(device)
    var channels: [JSONObject] = []
    if let count, count > 0 {
        for element in 1...count {
            channels.append(["element": element, "volumeScalar": readVolume(device, element: element),
                             "mute": readMute(device, element: element)])
        }
    }
    let master: JSONObject = ["element": kAudioObjectPropertyElementMain,
                              "volumeScalar": readVolume(device, element: kAudioObjectPropertyElementMain),
                              "mute": readMute(device, element: kAudioObjectPropertyElementMain)]
    let (deviceAfter, afterStatus) = defaultOutputDevice()
    return ["status": deviceAfter == device ? "ok" : "unstable",
            "defaultOutputDeviceID": device,
            "deviceUID": readAudioString(device, selector: kAudioDevicePropertyDeviceUID),
            "deviceName": readAudioString(device, selector: kAudioObjectPropertyName),
            "channelConfiguration": channelStatus,
            "master": master, "channels": channels,
            "sameDefaultDeviceAfterRead": deviceAfter == device,
            "defaultDeviceRecheck": afterStatus]
}

func displayBaseline() -> JSONObject {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
    guard result == kIOReturnSuccess else {
        return ["status": "unsupported", "method": "IODisplayGetFloatParameter", "ioReturn": Int(result),
                "reason": "The public IODisplay service query is unavailable.", "displays": []]
    }
    defer { IOObjectRelease(iterator) }
    var displays: [JSONObject] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        var entryID: UInt64 = 0
        let entryResult = IORegistryEntryGetRegistryEntryID(service, &entryID)
        var brightness: Float = 0
        let readResult = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        var record: JSONObject = ["status": "unsupported", "ioReturn": Int(readResult)]
        if entryResult == kIOReturnSuccess { record["registryEntryID"] = entryID }
        if readResult == kIOReturnSuccess && brightness.isFinite && (0...1).contains(brightness) {
            record["status"] = "ok"
            record["brightnessScalar"] = Double(brightness)
        } else {
            record["reason"] = "This display does not expose a valid brightness scalar through the public IODisplay API."
        }
        displays.append(record)
    }
    return ["status": displays.contains { $0["status"] as? String == "ok" } ? "ok" : "unsupported",
            "method": "IODisplayGetFloatParameter", "serviceClass": "IODisplayConnect",
            "reason": displays.isEmpty ? "No public IODisplayConnect services were exposed." : "See individual display readings.",
            "displays": displays]
}

let started = Date()
let audio = audioBaseline()
let displays = displayBaseline()
let timestamp = ISO8601DateFormatter()
timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let result: JSONObject = ["schemaVersion": 1, "readOnly": true,
                          "startedAt": timestamp.string(from: started),
                          "finishedAt": timestamp.string(from: Date()),
                          "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                          "audio": audio, "brightness": displays]
do {
    let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data([0x0a]))
} catch {
    FileHandle.standardError.write(Data("Unable to encode hardware baseline: \(error)\n".utf8))
    exit(1)
}
