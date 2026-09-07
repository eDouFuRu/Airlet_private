import AppKit
import Defaults

extension Defaults.Keys {
    // hi keeps its existing independent keys; new applications are opt-in and private.
    static let enabledAppNotificationSources = Key<[String: Bool]>("enabledAppNotificationSources", default: [:])
    static let detailedAppNotificationSources = Key<[String: Bool]>("detailedAppNotificationSources", default: [:])
}

struct AppNotificationSourceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let applicationURL: URL?
    let attributedNames: Set<String>
    var isInstalled: Bool { applicationURL != nil }

    /// IDs and names are confirmed against the installed app bundle before observation.
    /// This Mac's ChatGPT app also hosts Codex, under com.openai.codex.
    @MainActor static func discover() -> [Self] {
        let specifications: [(String, String, Set<String>)] = [
            (HiNotificationSourceEvidence.hiBundleID, "hi", ["hi"]),
            ("com.xingin.valos", "ValOS", ["ValOS"]),
            ("com.coral.desktop", "Lobi", ["Lobi"]),
            ("com.openai.codex", "ChatGPT / Codex", ["ChatGPT", "Codex"])
        ]
        let running = NSWorkspace.shared.runningApplications
        return specifications.map { id, name, aliases in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let bundle = Bundle(url: url), bundle.bundleIdentifier == id else {
                return Self(id: id, name: name, applicationURL: nil, attributedNames: [])
            }
            var names = aliases
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = bundle.object(forInfoDictionaryKey: key) as? String { names.insert(value) }
            }
            // Reject a currently ambiguous app name rather than borrowing another app's banner.
            names = names.filter { candidate in
                !running.contains {
                    $0.bundleIdentifier != id && $0.bundleIdentifier != "com.apple.notificationcenterui"
                    && $0.localizedName?.caseInsensitiveCompare(candidate) == .orderedSame
                }
            }
            return Self(id: id, name: name, applicationURL: url, attributedNames: names)
        }
    }
}
