import SwiftUI

/// The card shows a confirmed system reading. No toggle is run by appearing,
/// refreshing, opening Settings, or adding the card to the user's layout.
struct SystemToolBluetoothTile: View {
    @ObservedObject private var control = SystemBluetoothControl.shared

    private var authorizationText: String {
        if control.isRequestingAccess { return L("Waiting for a Bluetooth permission decision in macOS.") }
        let key: String
        switch control.authorization {
        case .notDetermined: key = "Bluetooth access has not been requested for this app."
        case .denied: key = "Bluetooth access is denied for this app."
        case .restricted: key = "Bluetooth access is restricted for this app."
        case .allowed: key = "Bluetooth access is allowed for this app."
        case .unknown: key = "Bluetooth access status is not available."
        }
        return L(key)
    }

    var body: some View {
        ExperimentalSystemToggleTile(tool: .bluetooth, enabled: control.enabled,
            isBusy: control.isBusy, unsupported: control.availability == .unsupported,
            errorKey: control.errorKey,
            helpKey: "Experimental Bluetooth control. Turning Bluetooth off disconnects Bluetooth devices.") {
                Task { @MainActor in
                    if control.availability == .unsupported {
                        _ = await SystemToolActions.shared.openControlSettings(.bluetooth)
                    } else if control.errorKey != nil || control.enabled == nil {
                        await control.refresh()
                    } else { await control.toggle() }
                }
            }
            .contextMenu {
                Text(verbatim: authorizationText)
                if let error = control.errorKey { Text(L(error)) }
                if control.authorization == .notDetermined {
                    Button(L("Request Bluetooth access")) { control.requestAccess() }
                        .disabled(control.isRequestingAccess)
                }
                Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                    .disabled(control.isBusy)
                Button(L("Open Bluetooth settings")) {
                    Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.bluetooth) }
                }
            }
            .task { await control.refresh() }
    }
}

struct SystemToolNightShiftTile: View {
    @ObservedObject private var control = SystemNightShiftControl.shared
    private var unsupported: Bool {
        control.availability == .unsupportedABI || control.availability == .unsupportedHardware
    }

    var body: some View {
        ExperimentalSystemToggleTile(tool: .nightShift, enabled: control.enabled,
            isBusy: control.isBusy, unsupported: unsupported, errorKey: control.errorKey,
            helpKey: "Experimental Night Shift control. Toggles Night Shift without changing its schedule or color temperature.") {
                Task { @MainActor in
                    if unsupported {
                        _ = await SystemToolActions.shared.openControlSettings(.displays)
                    } else if control.errorKey != nil || control.enabled == nil {
                        await control.refresh()
                    } else { await control.toggle() }
                }
            }
            .task { await control.refresh() }
    }
}

struct SystemToolTrueToneTile: View {
    @ObservedObject private var control = SystemTrueToneControl.shared

    var body: some View {
        ExperimentalSystemToggleTile(tool: .trueTone, enabled: control.enabled,
            isBusy: control.isBusy, unsupported: control.availability == .unsupportedABI,
            errorKey: control.errorKey,
            helpKey: "Experimental True Tone control. Available only when macOS confirms support.") {
                Task { @MainActor in
                    if control.availability == .unsupportedABI {
                        _ = await SystemToolActions.shared.openControlSettings(.displays)
                    } else if control.errorKey != nil || control.enabled == nil {
                        await control.refresh()
                    } else { await control.toggle() }
                }
            }
            .task { await control.refresh() }
    }
}

private struct ExperimentalSystemToggleTile: View {
    let tool: SystemToolID
    let enabled: Bool?
    let isBusy: Bool
    let unsupported: Bool
    let errorKey: String?
    let helpKey: String
    let action: () -> Void

    private var status: String {
        if isBusy { return L("Reading hardware…") }
        if unsupported { return L("Unsupported · Open Settings") }
        if errorKey != nil { return L("Unavailable · Retry") }
        guard let enabled else { return L("Reading hardware…") }
        return L(enabled ? "On" : "Off") + " · " + L("Experimental")
    }

    var body: some View {
        let definition = SystemToolCatalog.tool(tool)
        Button(action: action) {
            SystemToolStateLabel(tool: definition, status: status, hasError: errorKey != nil)
        }
        .buttonStyle(.plain).disabled(isBusy)
        .accessibilityLabel(L(definition.titleKey)).accessibilityValue(status)
        .help(L(errorKey ?? helpKey))
    }
}

struct SystemToolInputSourceTile: View {
    @ObservedObject private var control = SystemInputSourceControl.shared
    private func sourceLabel(_ item: InputSourceMenuItem) -> String {
        guard let parent = item.parentName, parent != item.displayName else { return item.displayName }
        return item.displayName + " · " + parent
    }
    private var status: String {
        if control.isBusy { return L("Reading input sources…") }
        if control.errorKey != nil { return L("Unavailable · Retry") }
        return control.currentName ?? L("Choose Input Source")
    }

    var body: some View {
        Menu {
            if let error = control.errorKey { Text(L(error)) }
            ForEach(control.sources) { item in
                Button {
                    Task { @MainActor in await control.select(id: item.id) }
                } label: {
                    HStack {
                        if item.id == control.selectedID { Image(systemName: "checkmark") }
                        Text(verbatim: sourceLabel(item))
                    }
                }
                .accessibilityLabel(sourceLabel(item))
                .disabled(control.isBusy)
            }
            Divider()
            Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                .disabled(control.isBusy)
            Button(L("Open keyboard settings")) {
                Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.keyboard) }
            }
        } label: {
            SystemToolStateLabel(tool: SystemToolCatalog.tool(.inputSources), status: status,
                                 hasError: control.errorKey != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel(L("Input Sources")).accessibilityValue(status)
        .help(L(control.errorKey ?? "Choose an enabled keyboard input source."))
        .task { await control.refresh() }
    }
}

struct SystemToolAudioOutputTile: View {
    @ObservedObject private var control = SystemAudioOutputControl.shared

    private var status: String {
        if control.isBusy { return L("Reading audio outputs…") }
        if control.errorKey != nil { return L("Unavailable · Retry") }
        return control.currentName ?? L("Choose Audio Output")
    }

    var body: some View {
        Menu {
            if let error = control.errorKey { Text(L(error)) }
            ForEach(control.devices) { device in
                Button {
                    Task { @MainActor in await control.select(id: device.id) }
                } label: {
                    HStack {
                        if device.id == control.selectedID { Image(systemName: "checkmark") }
                        Text(verbatim: device.displayName)
                    }
                }
                .disabled(control.isBusy || !control.canSelect)
            }
            Divider()
            Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                .disabled(control.isBusy)
            Button(L("Open sound settings")) {
                Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.sound) }
            }
        } label: {
            SystemToolStateLabel(tool: SystemToolCatalog.tool(.sound), status: status,
                                 hasError: control.errorKey != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel(L("Sound & Audio Output")).accessibilityValue(status)
        .help(L(control.errorKey ?? "Choose an available audio output. Each device keeps its own volume; system alert output stays unchanged."))
        .task { await control.refresh() }
    }
}

struct SystemToolDisplayModeTile: View {
    @ObservedObject private var control = SystemDisplayModeControl.shared

    private var status: String {
        if control.isBusy { return L("Reading display modes…") }
        if control.errorKey != nil { return L("Unavailable · Retry") }
        if control.displays.count == 1, let display = control.displays.first,
           let mode = display.modes.first(where: { $0.id == display.currentModeID }) {
            return mode.resolutionLabel
        }
        return String(format: L("%d displays"), control.displays.count)
    }

    private func modeLabel(_ mode: DisplayModeOption) -> String {
        [mode.resolutionLabel, mode.isHiDPI ? "HiDPI" : nil,
         mode.refreshRateLabel ?? L("System Default")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Menu {
            Text(L("Display changes last while the island is running. macOS restores the previous mode when the app quits."))
            if let error = control.errorKey { Text(L(error)) }
            ForEach(control.displays) { display in
                Menu(display.isBuiltIn ? L("Built-in Display") : String(format: L("Display %d"), display.ordinal)) {
                    if display.isMirrored {
                        Text(L("Changing this mirrored display may also change the other displays in its mirror group."))
                    }
                    ForEach(display.modes) { mode in
                        Button {
                            Task { @MainActor in await control.select(displayID: display.id, mode: mode) }
                        } label: {
                            HStack {
                                if mode.id == display.currentModeID { Image(systemName: "checkmark") }
                                Text(verbatim: modeLabel(mode))
                            }
                        }
                        .accessibilityLabel(modeLabel(mode))
                        .disabled(control.isBusy)
                    }
                }
            }
            Divider()
            Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                .disabled(control.isBusy)
            Button(L("Open display settings")) {
                Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.displays) }
            }
        } label: {
            SystemToolStateLabel(tool: SystemToolCatalog.tool(.display), status: status,
                                 hasError: control.errorKey != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel(L("Display")).accessibilityValue(status)
        .help(L(control.errorKey ?? "Display changes last while the island is running. macOS restores the previous mode when the app quits."))
        .task { await control.refresh() }
    }
}

struct SystemToolVPNTile: View {
    @ObservedObject private var control = SystemVPNControl.shared

    private var status: String {
        if control.isBusy { return L("Updating VPN connections…") }
        if control.errorKey != nil { return L("Unavailable · Retry") }
        if control.services.count == 1, let service = control.services.first { return L(service.status.labelKey) }
        if control.services.isEmpty { return L("No controllable VPN found") }
        return String(format: L("%d VPN connections"), control.services.count)
    }

    var body: some View {
        Menu {
            Text(L("Controls configured VPNs listed by macOS. Some third-party clients must be operated in their own apps."))
            if let error = control.errorKey { Text(L(error)) }
            if control.services.isEmpty { Text(L("No controllable VPN found")) }
            ForEach(control.services) { service in
                Menu(service.displayName + " · " + L(service.status.labelKey)) {
                    Button(L(service.status == .connected ? "Disconnect VPN" : "Connect VPN")) {
                        Task { @MainActor in
                            await control.setConnected(id: service.id, connected: service.status != .connected)
                        }
                    }
                    .disabled(control.isBusy || !service.canToggle)
                }
            }
            Divider()
            Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                .disabled(control.isBusy)
            Button(L("Open VPN settings")) {
                Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.vpn) }
            }
        } label: {
            SystemToolStateLabel(tool: SystemToolCatalog.tool(.vpn), status: status,
                                 hasError: control.errorKey != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel(L("VPN")).accessibilityValue(status)
        .help(L(control.errorKey ?? "Controls configured VPNs listed by macOS. Some third-party clients must be operated in their own apps."))
        .task { await control.monitorWhileVisible() }
    }
}

struct SystemToolAccessibilityDisplayTile: View {
    let feature: AccessibilityDisplayFeature
    @ObservedObject private var control = SystemAccessibilityDisplayControl.shared

    private var tool: SystemToolID { feature == .increaseContrast ? .increaseContrast : .reduceTransparency }
    private var enabled: Bool? { control.states[feature] }
    private var lockedByContrast: Bool {
        feature == .reduceTransparency && enabled == true && control.states[.increaseContrast] == true
    }
    private var status: String {
        if control.isBusy { return L("Reading display accessibility…") }
        if !control.supportedFeatures.contains(feature) { return L("Unsupported · Open Settings") }
        if control.errorKey != nil || enabled == nil { return L("Unavailable · Retry") }
        if lockedByContrast { return L("Required by Increase Contrast") }
        return L(enabled == true ? "On" : "Off") + " · " + L("Experimental")
    }
    private var explanation: String {
        "Experimental display accessibility controls. Increase Contrast also reduces transparency; turn it off first to change transparency."
    }

    var body: some View {
        Button {
            Task { @MainActor in
                if !control.supportedFeatures.contains(feature) {
                    _ = await SystemToolActions.shared.openControlSettings(.displayAccessibility)
                } else if control.errorKey != nil || enabled == nil {
                    await control.refresh()
                } else if let enabled {
                    await control.toggle(feature: feature, expectedEnabled: enabled)
                }
            }
        } label: {
            SystemToolStateLabel(tool: SystemToolCatalog.tool(tool), status: status,
                                 hasError: control.errorKey != nil)
        }
        .buttonStyle(.plain).disabled(control.isBusy || lockedByContrast)
        .accessibilityLabel(L(SystemToolCatalog.tool(tool).titleKey)).accessibilityValue(status)
        .help(L(control.errorKey ?? explanation))
        .contextMenu {
            Text(L(explanation))
            if let error = control.errorKey { Text(L(error)) }
            Button(L("Refresh")) { Task { @MainActor in await control.refresh() } }
                .disabled(control.isBusy)
            Button(L("Open display accessibility settings")) {
                Task { @MainActor in _ = await SystemToolActions.shared.openControlSettings(.displayAccessibility) }
            }
        }
        .task { await control.refresh() }
    }
}

private struct SystemToolStateLabel: View {
    let tool: SystemToolDefinition
    let status: String
    let hasError: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tool.symbol).font(.system(size: 18, weight: .medium)).frame(height: 22)
            Text(L(tool.titleKey)).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(verbatim: status).font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(hasError ? Color.orange : Color.white.opacity(0.6))
        }
        .foregroundStyle(.white.opacity(0.92)).frame(maxWidth: .infinity).frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
