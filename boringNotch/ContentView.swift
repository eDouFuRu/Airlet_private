//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var pointer: NotchPointerCoordinator
    @ObservedObject private var visibility = IslandVisibility.shared
    @ObservedObject private var pomodoro = PomodoroModel.shared
    @ObservedObject private var systemHUD = SystemHUDPresentation.shared
    @ObservedObject private var brief = BriefPresentationCoordinator.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    private var lyricsAppearance = LyricsAppearance()
    @ObservedObject private var hi = HiNotificationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Default(.autoHideFloatingIsland) private var autoHideFloatingIsland
    @Default(.floatingIslandAutoWidthForLyrics) private var floatingIslandAutoWidthForLyrics
    @Default(.floatingGlassTransparency) private var floatingGlassTransparency
    @Default(.reactiveGlassEdgeLighting) private var reactiveGlassEdgeLighting
    @State private var glassEdgeLight: GlassEdgeLightProfile?
    @State private var presentationID = UUID()
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.idleLeftEmojis) private var idleLeftEmojis
    @Default(.idleRightEmojis) private var idleRightEmojis

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.cornerRadiusScaling) private var cornerRadiusScaling
    @Default(.enableHaptics) private var enableHaptics
    @Default(.enableShadow) private var enableShadow
    @Default(.inlineHUD) private var inlineHUD
    @Default(.hudReplacement) private var hudReplacement
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showPomodoroTimerOnClosed) private var showPomodoroTimerOnClosed
    @Default(.sneakPeekStyles) private var sneakPeekStyles
    @Default(.boringShelf) private var boringShelf

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
        if isFloating { return isOpen ? 24 : profile.compactHeight / 2 }
        return ((vm.notchState == .open) && cornerRadiusScaling)
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && cornerRadiusScaling)
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var closedMediaLayout: ClosedMediaLayout {
        ClosedMediaLayout(notchWidth: vm.closedNotchSize.width,
                          height: vm.effectiveClosedNotchHeight,
                          inlineMetadata: coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                            && sneakPeekStyles == .inline,
                          maximumWidth: openNotchSize.width)
    }

    private var computedChinWidth: CGFloat {
        if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
            return closedMediaLayout.shellWidth
        }
        if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle)
            && showNotHumanFace && !vm.hideOnClosed {
            return vm.closedNotchSize.width + 2 * idleEmojiWingWidth
        }
        return vm.closedNotchSize.width
    }

    private var pomodoroBusy: Bool { pomodoro.phase != .idle }
    private var idleEmojiWingWidth: CGFloat {
        max(IdleEmojiLayout.wingWidth(for: idleLeftEmojis),
            IdleEmojiLayout.wingWidth(for: idleRightEmojis))
    }
    /// Whether the closed shell gives the pomodoro its wings. The header and the width both
    /// read this one value rather than testing `pomodoroBusy` apiece: those are two
    /// hand-written branch chains, and letting them disagree is how a shell ends up 88pt
    /// wider than the thing it was widened for.
    private var showsPomodoroOnClosed: Bool { pomodoroBusy && showPomodoroTimerOnClosed }
    private var isOpen: Bool { vm.notchState == .open }
    private var headerHeight: CGFloat {
        if isFloating { return profile.expandedHeaderHeight }
        return max(24, max(vm.closedNotchSize.height, vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0)?.safeAreaInsets.top } ?? 0))
    }
    private var bottomRadius: CGFloat { isFloating ? topCornerRadius : (isOpen && cornerRadiusScaling ? 24 : 14) }
    private var systemHUDVisible: Bool { visibility.isAvailable && systemHUD.activeKind != nil }
    /// The charging notice rides the HUD chrome so it can appear while the island is open.
    /// It used to live in `closedHeader`, which is only ever used when the island is closed —
    /// so with a pinned page (the shelf) holding the island open, the notice silently expired
    /// against its 3s timer without ever being drawn.
    private var powerNoticeVisible: Bool {
        visibility.isAvailable && showPowerStatusNotifications && hudReplacement
            && coordinator.expandingView.show && coordinator.expandingView.type == .battery
    }
    /// The system HUD wins a tie: a deliberate key press outranks a passive power event.
    private var noticeChromeActive: Bool { systemHUDVisible || powerNoticeVisible }
    private var mediaPromptActive: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let pendingSong = brief.state.songChange.map { now < $0.expiration } ?? false
        return pendingSong
            || (coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music)
            || (coordinator.expandingView.show && coordinator.expandingView.type == .music)
    }
    private var briefSource: BriefPresentationSource {
        brief.state.selection(now: ProcessInfo.processInfo.systemUptime, hudActive: noticeChromeActive,
                              hiEnabled: hi.current != nil,
                              songEnabled: (isFloating || sneakPeekStyles == .standard) && (isFloating || isOpen || !vm.hideOnClosed),
                              lyricAvailable: lyrics.shouldShowNotch && (isFloating || isOpen || !vm.hideOnClosed),
                              mediaPromptActive: mediaPromptActive)
    }
    private var briefVisible: Bool { briefSource.usesBriefRow }
    private var briefHeaderHeight: CGFloat { briefVisible ? headerHeight : max(0, vm.effectiveClosedNotchHeight) }
    private var briefLayout: BriefPresentationLayout {
        BriefPresentationLayout(active: briefVisible, standardHUD: noticeChromeActive && !inlineHUD,
                                expanded: isOpen,
                                baseClosedSize: CGSize(width: baseClosedWidth, height: briefHeaderHeight),
                                baseExpandedHeight: baseExpandedHeight, headerHeight: headerHeight,
                                minimumBriefWidth: briefSource == .hi ? BriefPresentationLayout.noticeMinimumWidth : 0,
                                maximumWidth: isFloating ? profile.maximumWidth : openNotchSize.width,
                                expandedWidth: isFloating ? profile.maximumWidth : openNotchSize.width)
    }
    private var baseExpandedHeight: CGFloat {
        // Derived from the grid's own constants so the island is exactly tall enough for a
        // whole number of rows. A hand-tuned floor here is what previously left a spare
        // half row visible below the third one. Every page — pomodoro included — shares
        // this height; the tools grid derives its own.
        if coordinator.currentView == .tools {
            return max(openNotchSize.height, SystemToolGridMetrics.expandedHeight(headerHeight: headerHeight))
        }
        return max(openNotchSize.height, headerHeight + 156)
    }
    private var baseClosedWidth: CGFloat {
        if isFloating { return profile.compactBaseWidth }
        if vm.hideOnClosed { return vm.closedNotchSize.width }
        if showsPomodoroOnClosed { return vm.closedNotchSize.width + 88 }
        return max(vm.closedNotchSize.width + 12, computedChinWidth)
    }
    private var hudLayout: SystemHUDLayout {
        SystemHUDLayout(active: noticeChromeActive, inline: inlineHUD, expanded: isOpen,
                        notchWidth: profile.cameraExclusionWidth, headerHeight: headerHeight,
                        baseClosedSize: isOpen ? CGSize(width: baseClosedWidth, height: briefHeaderHeight) : briefLayout.size,
                        baseExpandedHeight: baseExpandedHeight + briefLayout.addedHeight,
                        expandedWidth: isFloating ? profile.maximumWidth : openNotchSize.width)
    }
    private var visibleWidth: CGFloat {
        isFloating ? (isOpen ? profile.maximumWidth : floatingCompactWidth) : hudLayout.size.width
    }
    private var visibleHeight: CGFloat {
        isFloating && !isOpen ? profile.compactHeight : hudLayout.size.height
    }
    private var profile: IslandDisplayProfile { vm.displayProfile }
    private var isFloating: Bool { profile.isFloating }
    private var appearance: IslandAppearance {
        IslandAppearance(isFloating: isFloating, colorScheme: colorScheme)
    }
    private var inlineMusicPeek: Bool {
        coordinator.expandingView.show && coordinator.expandingView.type == .music
    }
    private var floatingContent: FloatingIslandContent {
        .select(hud: systemHUDVisible, power: powerNoticeVisible,
                notification: briefSource == .hi, completion: pomodoro.justCompleted,
                song: briefSource == .songChange || inlineMusicPeek,
                lyric: briefSource == .lyric, pomodoro: showsPomodoroOnClosed,
                music: (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled)
    }
    private var surfaceVisible: Bool {
        if !isFloating {
            return visibility.isAvailable && (isOpen || systemHUDVisible || briefVisible || vm.effectiveClosedNotchHeight > 0)
        }
        let requested = IslandSurfaceVisibility.shouldShow(
            isFloating: true, autoHide: autoHideFloatingIsland || vm.hideOnClosed,
            expanded: isOpen, pointerInside: pointer.isPointerOverTrigger,
            transient: floatingContent.isTransient, available: visibility.isAvailable)
        // The reporter samples the actual animated height. Keep painting until the
        // collapse finishes, then fade out; re-entry naturally cancels the fade.
        return requested || (visibility.isAvailable && !pointer.isCompactPresentation)
    }
    private var floatingText: String {
        switch floatingContent {
        case .notification: return hi.current.map { hi.displayText(for: $0) } ?? ""
        case .completion: return L("Pomodoro completed")
        case .song, .music: return musicManager.songTitle + " – " + musicManager.artistName
        case .lyric: return lyrics.displayText
        case .pomodoro: return pomodoro.clockText
        case .power: return L(batteryModel.statusText) + "  \(Int(batteryModel.levelBattery))%"
        case .hud: return L(systemHUD.state.titleKey) + " " + (systemHUD.error.map { L($0) } ?? "")
        case .idle:
            return showNotHumanFace ? (IdleEmojiLayout.normalized(idleLeftEmojis) + " " + IdleEmojiLayout.normalized(idleRightEmojis)).trimmingCharacters(in: .whitespaces) : ""
        }
    }
    private var floatingCompactWidth: CGFloat {
        guard surfaceVisible else { return profile.compactBaseWidth }
        let font = NSFont.systemFont(ofSize: FloatingIslandMetrics.fontSize(height: profile.compactHeight), weight: .medium)
        let measured = (floatingText as NSString).size(withAttributes: [.font: font]).width
        let decorations: CGFloat = floatingContent == .hud ? 188 : floatingContent == .music ? 68 : 52
        let expandsToFit = floatingContent != .lyric || floatingIslandAutoWidthForLyrics
        return FloatingIslandMetrics.width(textWidth: measured, decorationWidth: decorations,
                                           minimum: profile.compactBaseWidth, maximum: profile.maximumWidth,
                                           expandsToFit: expandsToFit)
    }

    private var shellAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: isOpen ? 0.42 : 0.45,
                       dampingFraction: isOpen ? 0.8 : 1.0, blendDuration: 0)
    }

    private var glassLightTaskID: String {
        "\(vm.screenUUID ?? ""):\(isFloating && surfaceVisible && reactiveGlassEdgeLighting):\(isOpen)"
    }

    private func sampleBackdropLight() async {
        guard isFloating, surfaceVisible, reactiveGlassEdgeLighting,
              let screenID = vm.screenUUID,
              let screen = NSScreen.screen(withUUID: screenID),
              let sampler = await FloatingGlassBackdropSampler.make(screen: screen) else {
            glassEdgeLight = nil
            return
        }
        while !Task.isCancelled {
            let size = CGSize(width: visibleWidth, height: visibleHeight)
            let sampled = await sampler.sample(size: size, topInset: profile.topInset,
                                               cornerRadius: topCornerRadius)
            guard !Task.isCancelled else { return }
            glassEdgeLight = sampled
            try? await Task.sleep(for: .seconds(isOpen ? 1 : 4))
        }
    }

    /// Tab swaps are instant: an explicit per-branch identity transition overrides the
    /// scale transition the surrounding page container propagates down. With inherited
    /// or opacity transitions the incoming page still settled ~44pt low with a spring
    /// (layout reflow animated by the shell spring), which read as the page sliding
    /// down from the tab bar. Open/close keeps the container's scale+opacity.
    private var pageSwapTransition: AnyTransition {
        .identity
    }

    /// The shelf is pinned open, so it needs a dismiss control that does not depend on the
    /// pointer leaving. It floats clear of the island rather than sitting on the panel,
    /// where it would cover the rightmost item.
    ///
    /// Drawn here, outside the clipped black shape, and positioned from the same constants
    /// `NotchPointerCoordinator` uses to widen the hit region — the window is otherwise
    /// click-through out here, so the two must agree or the button renders but never
    /// responds.
    private var showsFloatingCollapse: Bool { isOpen && coordinator.currentView == .shelf }

    @ViewBuilder
    private var floatingAccessoryControls: some View {
        if showsFloatingCollapse {
            accessoryButton(slot: .collapse, symbol: "chevron.up", label: L("Collapse the island"),
                            enabled: true) { vm.close(force: true) }
            // Always drawn, dimmed when there is nothing to clear: hiding it would leave the
            // collapse button alone in the upper half and break the symmetry the pair is for.
            accessoryButton(slot: .clearShelf, symbol: "trash", label: L("Clear the shelf"),
                            enabled: !shelf.isEmpty) { shelf.clearAll() }
        }
    }

    private func accessoryButton(slot: NotchAccessorySlot, symbol: String, label: String,
                                 enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(appearance.primary.opacity(enabled ? 0.9 : 0.35))
                .frame(width: NotchAccessoryControl.diameter,
                       height: NotchAccessoryControl.diameter)
                .background {
                    if isFloating {
                        Color.clear.modifier(IslandSurface(isFloating: true,
                            topRadius: NotchAccessoryControl.diameter / 2,
                            bottomRadius: NotchAccessoryControl.diameter / 2,
                            transparency: floatingGlassTransparency))
                    } else { Circle().fill(Color.black.opacity(0.82)) }
                }
                .overlay(Circle().stroke(appearance.border.opacity(enabled ? 1 : 0.5), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // `.overlay(alignment: .top)` aligns the button's *top edge* to the window's top
        // edge, so the y offset must be a top-edge offset; `topEdgeOffset` is the only place
        // that arithmetic lives. Horizontally the overlay *is* centre aligned, so
        // `centerOffsetX` is a centre offset. Two different conventions on purpose.
        .offset(x: NotchAccessoryControl.centerOffsetX(visibleWidth: visibleWidth),
                y: profile.topInset + NotchAccessoryControl.topEdgeOffset(visibleHeight: visibleHeight, slot: slot))
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }

    var body: some View {
        NotchLayout()
            .padding(.horizontal, isOpen ? 31 : 6)
            .padding(.bottom, isOpen ? 12 : 0)
            // Floating glass and its hit reporter share an explicit animated height.
            // Keep the native notch's existing content-driven morph unchanged.
            .frame(width: visibleWidth, height: isFloating ? visibleHeight : nil, alignment: .top)
            .modifier(IslandSurface(isFloating: isFloating, topRadius: topCornerRadius,
                                    bottomRadius: bottomRadius, transparency: floatingGlassTransparency,
                                    edgeLight: glassEdgeLight))
            .shadow(color: enableShadow && (isOpen || pointer.isHoverPreparing)
                    ? .black.opacity(isFloating ? 0.16 : 0.6) : .clear, radius: 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pointer.isHoverPreparing)
            // The animating height proposal, mirroring upstream's
            // `.frame(height: open ? notchSize.height : nil)`: pages are re-laid-out at every
            // intermediate height while the shell spring runs, so the island unfolds around
            // its content instead of revealing it behind a moving clip edge. `.animation(
            // shellAnimation, value:)` below animates the content re-layout this triggers,
            // which is what keeps the closing half of the cycle smooth too.
            .frame(height: !isFloating && isOpen ? visibleHeight : nil, alignment: .top)
            .modifier(NotchPresentationReporter(width: visibleWidth, height: visibleHeight,
                                                topRadius: topCornerRadius, bottomRadius: bottomRadius,
                                                topInset: profile.topInset, contour: profile.contour,
                                                coordinator: pointer))
            .animation(shellAnimation, value: vm.notchState)
            .animation(shellAnimation, value: visibleWidth)
            .animation(shellAnimation, value: visibleHeight)
            .animation(shellAnimation, value: systemHUD.activeKind)
            .padding(.top, profile.topInset)
            .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
            // Overlaid on the full window, not on the island: SwiftUI will not reliably hit
            // test a child that overflows its parent's bounds, and this one sits outside
            // the island by design. The island is centred in the window, so the offsets
            // below are still measured from the island's centre.
            .overlay(alignment: .top) { floatingAccessoryControls }
            .opacity(surfaceVisible ? 1 : 0)
            .animation(isFloating && !reduceMotion ? .easeOut(duration: 0.12) : nil, value: surfaceVisible)
            .accessibilityHidden(!surfaceVisible)
            .environment(\.islandAppearance, appearance)
            .preferredColorScheme(isFloating ? nil : .dark)
            .modifier(IslandLocalization())
            .task(id: glassLightTaskID) { await sampleBackdropLight() }
            .onAppear {
                pointer.setSurfaceVisible(surfaceVisible)
                syncBriefPresentation()
                pointer.setAccessoryControlVisible(showsFloatingCollapse)
            }
            .onChange(of: surfaceVisible) {
                pointer.setSurfaceVisible(surfaceVisible)
                syncBriefPresentation()
            }
            .onChange(of: floatingContent) { syncBriefPresentation() }
            .onChange(of: showsFloatingCollapse) { _, visible in
                pointer.setAccessoryControlVisible(visible)
            }
            .onChange(of: vm.notchState) {
                syncBriefPresentation(); pointer.reevaluate()
                if isOpen && enableHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            }
            .onChange(of: coordinator.currentView) { syncBriefPresentation() }
            .onChange(of: briefSource) { syncBriefPresentation() }
            .onChange(of: mediaPromptActive) { syncBriefPresentation() }
            .onChange(of: lyrics.shouldShowNotch) { syncBriefPresentation() }
            .onChange(of: vm.hideOnClosed) { syncBriefPresentation() }
            .onChange(of: boringShelf) {
                if !boringShelf && coordinator.currentView == .shelf { coordinator.currentView = .home }
            }
            .onChange(of: visibility.isHidden) { syncBriefPresentation() }
            .onChange(of: visibility.screenUnavailable) { syncBriefPresentation() }
            .onChange(of: vm.isBatteryPopoverActive) { pointer.reevaluate() }
            .onChange(of: hudLayout.showsInline) {
                // Replacing the header dismisses its popover and its keep-open claim.
                if hudLayout.showsInline { vm.isBatteryPopoverActive = false }
            }
            .onDisappear {
                lyrics.removeNotchPresentation(sourceID: presentationID)
                brief.setHovered(sourceID: presentationID, hovered: false)
            }
    }

    private func syncBriefPresentation() {
        // Keep the eligible lyric clock alive through a blank intro/interlude,
        // so the next real cue can reveal the row without a metadata event.
        let lyricMayPresent = surfaceVisible && (isFloating || isOpen || !vm.hideOnClosed)
            && !mediaPromptActive && (briefSource == .lyric || briefSource == .none)
        lyrics.setNotchPresentation(sourceID: presentationID, visible: lyricMayPresent)
        let compact = isFloating && !isOpen
        let hasBrief = compact ? floatingContent == .notification : briefVisible
        pointer.configureBriefRow(topInset: surfaceVisible && hasBrief ? (compact ? 0 : briefLayout.rowTopInset) : nil,
                                  interactive: surfaceVisible && briefSource == .hi,
                                  horizontalInset: isOpen ? 31 : 6,
                                  height: compact ? profile.compactHeight : BriefPresentationLayout.rowHeight) { hovered in
            brief.setHovered(sourceID: presentationID, hovered: hovered)
        }
    }

    @ViewBuilder private var briefRow: some View {
        switch briefSource {
        case .hi:
            if let notice = hi.current {
                BriefPromptRow(text: hi.displayText(for: notice), applicationIcon: hi.icon(for: notice),
                               action: { hi.clickLatest() })
            }
        case .songChange:
            BriefPromptRow(text: musicManager.songTitle + " – " + musicManager.artistName,
                           tint: playerColorTinting ? appearance.artworkTint(Color(nsColor: musicManager.avgColor)) : appearance.secondary)
        case .lyric:
            BriefPromptRow(text: lyrics.displayText, symbol: "text.quote", tint: lyricsAppearance.color(in: appearance))
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var floatingCompactRow: some View {
        // Unmount continuously animated text and spectra while dormant. The event
        // managers and their deadlines continue independently of this view.
        if !surfaceVisible {
            Color.clear
        } else {
            switch floatingContent {
            case .hud:
                FloatingSystemHUD(state: systemHUD.state, height: profile.compactHeight)
                    .padding(.horizontal, 4)
            case .notification:
                if let notice = hi.current {
                    BriefPromptRow(text: floatingText, applicationIcon: hi.icon(for: notice),
                                   height: profile.compactHeight, action: { hi.clickLatest() })
                }
            case .power:
                BriefPromptRow(text: floatingText,
                               symbol: batteryModel.isPluggedIn ? "powerplug.fill" : "powerplug",
                               height: profile.compactHeight)
            case .completion:
                BriefPromptRow(text: floatingText, symbol: "checkmark.circle.fill",
                               tint: PomodoroTheme.accent, height: profile.compactHeight)
            case .song:
                BriefPromptRow(text: floatingText, applicationIcon: musicManager.albumArt,
                               tint: playerColorTinting ? appearance.artworkTint(Color(nsColor: musicManager.avgColor)) : appearance.primary,
                               height: profile.compactHeight)
            case .lyric:
                BriefPromptRow(text: floatingText, symbol: "text.quote",
                               tint: lyricsAppearance.color(in: appearance), height: profile.compactHeight)
            case .pomodoro:
                HStack(spacing: 8) {
                    Image(systemName: pomodoro.phase == .paused ? "pause.fill" : "timer")
                        .foregroundStyle(PomodoroTheme.accent)
                    Text(floatingText).monospacedDigit()
                        .foregroundStyle(appearance.primary.opacity(pomodoro.phase == .paused ? 0.6 : 1))
                }
                .font(.system(size: FloatingIslandMetrics.fontSize(height: profile.compactHeight), weight: .medium))
                .frame(maxWidth: .infinity)
            case .music:
                HStack(spacing: 6) {
                    BriefPromptRow(text: floatingText, applicationIcon: musicManager.albumArt,
                                   height: profile.compactHeight)
                    if useMusicVisualizer {
                        AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                            .frame(width: 14, height: min(14, profile.compactHeight - 4))
                    }
                }
                .padding(.trailing, 4)
            case .idle:
                Text(floatingText)
                    .font(.system(size: min(17, FloatingIslandMetrics.iconSize(height: profile.compactHeight))))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                if isFloating && !isOpen {
                    floatingCompactRow.frame(height: profile.compactHeight)
                } else {
                if hudLayout.showsInline {
                    Group {
                        if systemHUDVisible {
                            InlineHUD(state: systemHUD.state, layout: hudLayout)
                        } else {
                            PowerNoticeRow(inline: true, layout: hudLayout)
                        }
                    }
                    .transition(.opacity)
                } else if isOpen {
                    BoringHeader().frame(height: headerHeight)
                } else {
                    closedHeader
                        .frame(height: noticeChromeActive ? headerHeight : briefHeaderHeight)
                }
                if hudLayout.showsRow {
                    Group {
                        if systemHUDVisible {
                            SystemHUDRow(state: systemHUD.state)
                        } else {
                            PowerNoticeRow(inline: false, layout: hudLayout)
                        }
                    }
                    .transition(.opacity)
                } else if briefVisible {
                    briefRow.transition(.opacity)
                }
                }
            }
            .zIndex(2)

            if isOpen {
                // A real VStack container, like upstream: the transition below belongs to
                // THIS view, so it only runs when the island opens/closes. Tab switches
                // swap children *inside* it and get the default crossfade — a Group here
                // would push the scale transition down onto every switch branch, making
                // the incoming page slide down from the tab bar on each tab change.
                VStack(spacing: 0) {
                    switch coordinator.currentView {
                    case .pomodoro:
                        PomodoroPage().transition(pageSwapTransition)
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace).transition(pageSwapTransition)
                    case .shelf:
                        ShelfView().transition(pageSwapTransition)
                    case .tools:
                        SystemToolsPage().transition(pageSwapTransition)
                    }
                }
                .padding(.top, 8)
                // No size frame here on purpose (upstream mounts pages bare): every page
                // stretches to the shell's animating proposal on its own — home via the
                // GeometryReader in its controls column, shelf via its greedy panel shape,
                // tools via the scroll view, pomodoro via its own infinity frame (which is
                // also what keeps a page from dragging the tab bar sideways on tab switch).
                .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35)))
                .zIndex(1)
                .allowsHitTesting(isOpen)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting, onEnter: openShelfForDrag))
    }

    /// Landing on the media page with a file in hand leaves nowhere to drop it, so a drag
    /// always lands on the shelf. This goes through `open(preferredPage:)`, which bypasses
    /// the `openShelfByDefault` branch entirely — the setting keeps governing plain hovering
    /// and needs no companion switch of its own.
    private func openShelfForDrag() {
        guard boringShelf else { return }
        withAnimation(vm.animationLibrary.animation) {
            vm.open(preferredPage: .shelf)
        }
    }

    @ViewBuilder
    private var closedHeader: some View {
        if vm.hideOnClosed {
            Color.clear.frame(width: vm.closedNotchSize.width)
        } else if showsPomodoroOnClosed {
            HStack(spacing: 0) {
                Image(systemName: pomodoro.phase == .paused ? "pause.fill" : "timer")
                    .foregroundStyle(PomodoroTheme.accent).frame(maxWidth: .infinity)
                Color.clear.frame(width: vm.closedNotchSize.width)
                Text(pomodoro.clockText).font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(pomodoro.phase == .paused ? 0.5 : 0.8))
                    .frame(maxWidth: .infinity)
            }
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
                    && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled {
            MusicLiveActivity()
        } else if !coordinator.expandingView.show && !musicManager.isPlaying && musicManager.isPlayerIdle && showNotHumanFace {
            IdleEmojiWings()
        } else {
            Color.clear.frame(width: vm.closedNotchSize.width)
        }
    }

    @ViewBuilder
    func IdleEmojiWings() -> some View {
        HStack(spacing: 0) {
            IdleEmojiWing(characters: IdleEmojiLayout.characters(in: idleLeftEmojis))
                .padding(.trailing, 4)
                .frame(width: idleEmojiWingWidth, alignment: .trailing)
            Color.clear.frame(width: vm.closedNotchSize.width)
                .accessibilityHidden(true)
            IdleEmojiWing(characters: IdleEmojiLayout.characters(in: idleRightEmojis))
                .padding(.leading, 4)
                .frame(width: idleEmojiWingWidth, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        let layout = closedMediaLayout
        HStack(spacing: 0) {
            HStack(spacing: layout.itemSpacing) {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.artworkSize, height: layout.artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                if layout.metadataWidth > 0 {
                    Text(musicManager.songTitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: layout.metadataWidth, alignment: .leading)
                }
            }
            .padding(.horizontal, layout.wingInset)
            .frame(width: layout.wingWidth)

            Color.clear.frame(width: layout.physicalGapWidth)
                .accessibilityHidden(true)

            HStack(spacing: layout.itemSpacing) {
                if layout.metadataWidth > 0 {
                    Text(musicManager.artistName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: layout.metadataWidth, alignment: .trailing)
                }
                Group {
                    if useMusicVisualizer {
                        Rectangle()
                            .fill(coloredSpectrogram
                                  ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                            .frame(width: ClosedMediaLayout.spectrumSize.width,
                                   height: ClosedMediaLayout.spectrumSize.height)
                            .mask {
                                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                    .frame(width: ClosedMediaLayout.spectrumSize.width,
                                           height: ClosedMediaLayout.spectrumSize.height)
                            }
                    } else {
                        LottieAnimationContainer()
                            .frame(width: layout.artworkSize, height: layout.artworkSize)
                    }
                }
                .frame(width: layout.artworkSize, height: layout.artworkSize)
            }
            .padding(.horizontal, layout.wingInset)
            .frame(width: layout.wingWidth)
        }
        .foregroundStyle(coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : .gray)
        .frame(width: layout.contentWidth, height: layout.height)
    }


}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    /// Carrying a file is an unambiguous statement of intent, so it overrides whatever page
    /// hovering alone would have picked. Empty-handed hovering still follows the setting.
    var onEnter: () -> Void = {}

    func dropEntered(info: DropInfo) {
        isTargeted = true
        onEnter()
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}
