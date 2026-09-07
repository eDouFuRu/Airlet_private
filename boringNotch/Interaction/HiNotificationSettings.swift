import AppKit
import Defaults
import SwiftUI

/// Source-specific switches share the same observer and the existing brief-prompt queue.
struct HiNotificationSettings: View {
    @Default(.hideOriginalHiBanner) private var hideOriginal
    @ObservedObject private var source = HiNotificationManager.shared

    var body: some View {
        Form {
            Section {
                Text(L("Mirror desktop notifications from the apps you choose. Task completion is shown only when the source app actually posts a notification; task state is never guessed."))
                    .foregroundStyle(.secondary)
                Label(L(source.status.labelKey), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                if source.status == .accessibilityRequired {
                    Button(L("Request Accessibility")) { HUDStateManager.shared.requestPermission() }
                }
                Button(L("Refresh notification observer")) { source.refreshDiagnostics() }
            } header: { Text(L("App notifications")) }

            ForEach(source.sources) { app in
                Section {
                    Toggle(isOn: Binding(get: { source.isEnabled(app.id) },
                                         set: { source.setEnabled($0, for: app.id) })) {
                        HStack(spacing: 8) {
                            if let icon = source.icon(for: app.id) {
                                Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24)
                            }
                            Text(verbatim: app.name)
                        }
                    }
                    .accessibilityLabel(app.name)
                    .disabled(!app.isInstalled)
                    Picker(L("Notification preview"), selection: Binding(get: { source.isDetailed(app.id) },
                                                                           set: { source.setDetailed($0, for: app.id) })) {
                        Text(L("Only indicate a new notification")).tag(false)
                        Text(L("Show title and notification preview")).tag(true)
                    }.disabled(!app.isInstalled || !source.isEnabled(app.id))
                    Label(L(source.status(for: app).labelKey), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(verbatim: app.name) }
            }

            Section {
                Text(L("This Mac's ChatGPT and Codex share one installed application, so they use one notification switch."))
                Text(L("Only desktop banners actually posted by each app can be mirrored. Focus, disabled banners, and app-specific notification settings may prevent delivery."))
                Text(L("Click the island reminder to use the original notification action when available, otherwise open its source app. Bursts from the same app show the latest notification and a count."))
            } header: { Text(L("Delivery and interaction")) }

            Section {
                Toggle(L("Try to hide original hi banners (experimental)"), isOn: $hideOriginal)
                    .disabled(!source.isEnabled(HiNotificationManager.bundleID) || !source.originalBannerHidingSupported)
                Text(L("Mirror only: original banners are not taken over on this Mac. Notification Center records remain untouched. Hiding will become available only after safe repositioning is verified."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(L("Original system banner")) }

            Section {
                Text(L("Message previews are held briefly in memory and are not saved or logged. Privacy mode controls the island only; macOS controls the original banner preview."))
                DisclosureGroup(L("Notification diagnostics")) {
                    Text(L("Observer diagnostics may read notification content for recognition and deduplication, but never display or save it here."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: source.diagnosticsSummary)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button(L("Inspect notification structure (no text)")) { source.refreshStructureDiagnostics() }
                    Text(L("This diagnostic reads roles, supported attribute names, window sizes, and observer status only. It does not read notification titles, previews, or identifier values."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: source.structureDiagnosticsSummary)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button(L(source.isSamplingStructure ? "Stop structure sampling" : "Sample notification structure for 30 seconds")) {
                        if source.isSamplingStructure { source.stopStructureSampling() }
                        else { source.startStructureSampling() }
                    }
                    Text(L("Captures structure changes for up to 30 seconds without reading notification text. Start sampling before a real notification arrives."))
                        .font(.caption).foregroundStyle(.secondary)
                    if !source.structureSamplesSummary.isEmpty {
                        Text(verbatim: source.structureSamplesSummary)
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            } header: { Text(L("Privacy and interaction")) }
        }
        .navigationTitle(Text(verbatim: L("App notifications")))
    }
}
