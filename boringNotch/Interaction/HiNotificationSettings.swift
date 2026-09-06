import AppKit
import Defaults
import SwiftUI

struct HiNotificationSettings: View {
    @Default(.enableHiNotifications) private var enabled
    @Default(.hiNotificationDetail) private var detailed
    @Default(.hideOriginalHiBanner) private var hideOriginal
    @ObservedObject private var source = HiNotificationManager.shared
    @ObservedObject private var lyrics = LyricsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show hi notifications below the notch", isOn: $enabled)
                Picker("Notification preview", selection: $detailed) {
                    Text("Only indicate a new hi message").tag(false)
                    Text("Show sender and message preview").tag(true)
                }.disabled(!enabled)
                Label(L(source.status.labelKey), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                if source.status == .accessibilityRequired {
                    Button("Request Accessibility") { HUDStateManager.shared.requestPermission() }
                }
                Button("Refresh notification observer") { source.refreshDiagnostics() }
            } header: { Text("hi notifications") }
            footer: {
                Text("Only new desktop banners actually shown by hi can be mirrored. Messages suppressed by Focus, desktop notification settings, or hi itself are not captured.")
            }
            Section {
                Toggle("Try to hide original hi banners (experimental)", isOn: $hideOriginal)
                    .disabled(!enabled || !source.originalBannerHidingSupported)
                Text("Mirror only: original banners are not taken over on this Mac. Notification Center records remain untouched. Hiding will become available only after safe repositioning is verified.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Original system banner") }
            Section {
                Text("Message previews are held briefly in memory and are not saved or logged. Privacy mode controls the island only; macOS controls the original banner preview.")
                Text("Click the island reminder to open its original notification action when available, otherwise open hi. Continuous messages are grouped and the latest message is used.")
            } header: { Text("Privacy and interaction") }
            Section {
                DisclosureGroup("Notification diagnostics") {
                    Text(verbatim: source.diagnosticsSummary)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(verbatim: lyrics.diagnosticsSummary)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(Text(verbatim: L("hi notifications")))
    }
}
