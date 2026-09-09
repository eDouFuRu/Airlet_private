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
            ("com.openai.codex", "ChatGPT / Codex", ["ChatGPT", "Codex"]),
            ("com.tencent.xinWeChat", "WeChat", ["WeChat", "微信"]),
            // Kept on purpose: `osascript -e 'display notification …'` posts a real banner as this
            // app, which is the only way to self-test the whole capture path without a second person.
            ("com.apple.ScriptEditor2", "Script Editor", ["Script Editor", "脚本编辑器"])
        ]
        let running = NSWorkspace.shared.runningApplications.map {
            AppNotificationNameFilter.RunningApplication(bundleID: $0.bundleIdentifier,
                                                         bundlePath: $0.bundleURL?.path,
                                                         localizedName: $0.localizedName)
        }
        return specifications.map { id, name, aliases in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let bundle = Bundle(url: url), bundle.bundleIdentifier == id else {
                return Self(id: id, name: name, applicationURL: nil, attributedNames: [])
            }
            var names = aliases
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = bundle.object(forInfoDictionaryKey: key) as? String { names.insert(value) }
            }
            names = AppNotificationNameFilter.attributableNames(candidates: names, sourceBundleID: id,
                                                                sourceBundlePath: url.path, running: running)
            return Self(id: id, name: name, applicationURL: url, attributedNames: names)
        }
    }
}
