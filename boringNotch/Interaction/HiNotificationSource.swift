import AppKit
import Combine
import Defaults
@preconcurrency import ApplicationServices

enum HiNotificationSourceStatus: String, Equatable {
    case disabled, paused, accessibilityRequired, waitingForNotificationCenter, mirrorOnly, unsupportedStructure

    var labelKey: String {
        switch self {
        case .disabled: return "Hi notifications are off."
        case .paused: return "Hi notifications are paused while the island is unavailable."
        case .accessibilityRequired: return "Accessibility access is required to observe Hi banners."
        case .waitingForNotificationCenter: return "Waiting for Notification Center."
        case .mirrorOnly: return "Observer running; mirrors recognized Hi banners only. Original banners remain visible."
        case .unsupportedStructure: return "This notification layout is not supported. Original banners remain visible."
        }
    }
}

/// Experimental UI observer, not a notification delivery interceptor. No database, private
/// window APIs, notification dismissal, text logging, or automatic permissions prompt.
@MainActor
final class HiNotificationManager: ObservableObject {
    static let shared = HiNotificationManager()
    static let bundleID = HiNotificationSourceEvidence.hiBundleID
    @Published private(set) var current: HiNotificationNotice?
    @Published private(set) var status: HiNotificationSourceStatus = .disabled
    @Published private(set) var diagnosticsSummary = "AX: false · Observer: false · Host: 0 · Windows: 0 · Cards: 0 · Hi: 0 · Delivered: 0 · Result: not_started · Position: unverified"
    /// Deliberately false until a separate native verification establishes safe move/restore.
    let originalBannerHidingSupported = false
    var enabled: Bool { Defaults[.enableHiNotifications] }
    var detailed: Bool { Defaults[.hiNotificationDetail] }
    var originalBannerHidingRequested: Bool { Defaults[.hideOriginalHiBanner] }

    private var state = HiNotificationState()
    private var subscriptions = Set<AnyCancellable>()
    private var observer: AXObserver?
    private var host: AXUIElement?
    private var hostPID: pid_t = 0
    private var generation = 0
    private var started = false
    private var scanTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var cardTracker = HiAXCardTracker()
    private var awaitingBaseline = true
    private var latestAction: ActionReference?
    private var lastWindowCount = 0
    private var lastCardCount = 0
    private var lastHiCount = 0
    private var deliveryCount = 0
    private var lastResult = "not_started"
    private var lastPositionSettable: Bool?
    private var lastKnownFields = Set<String>()
    private var readDeadline: TimeInterval?
    private var readHadFailure = false
    private var diagnosticStructure = HiAXDiagnosticStructure()
    private var diagnosticVisitedElements = Set<CFHashCode>()

    private struct ActionReference {
        let card: AXUIElement
        let window: AXUIElement
        let identity: String
        let fingerprint: String
        let hostPID: pid_t
    }

    private struct Capture {
        let candidate: HiNotificationCandidate
        let fingerprint: String
        let hasPayload: Bool
        let card: AXUIElement
        let window: AXUIElement
        var content: HiAXCardContent {
            HiAXCardContent(cardID: candidate.identity, fingerprint: fingerprint, hasPayload: hasPayload)
        }
    }

    private struct CaptureSnapshot {
        let cards: [Capture]
        let visibleCardIDs: Set<String>
        let complete: Bool
    }

    private init() { start() }

    func start() {
        guard !started else { refresh(); return }
        started = true
        Defaults.publisher(.enableHiNotifications).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        Defaults.publisher(.hiNotificationDetail).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        Defaults.publisher(.hideOriginalHiBanner).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }.store(in: &subscriptions)
        }
        refresh()
    }

    func setApplicationAvailable(_ available: Bool) {
        state.setApplicationAvailable(available)
        if !available { latestAction = nil }
        publish()
        refresh()
    }

    /// Passive permission check. The Settings permission button is owned by the app.
    func refresh() {
        defer { updateDiagnostics() }
        state.setEnabled(enabled)
        state.setDetailed(detailed)
        publish()
        guard enabled else { stopObserving(); status = .disabled; lastResult = "disabled"; return }
        guard state.applicationAvailable else { stopObserving(); status = .paused; lastResult = "unavailable"; return }
        ensureHealthCheck()
        guard AXIsProcessTrusted() else {
            stopObserverOnly()
            state.dismiss(); latestAction = nil; publish()
            status = .accessibilityRequired
            lastResult = "accessibility_required"
            return
        }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            stopObserverOnly()
            state.dismiss(); latestAction = nil; publish()
            status = .waitingForNotificationCenter
            lastResult = "notification_center_absent"
            return
        }
        if observer != nil, process.processIdentifier == hostPID { return }
        stopObserverOnly()
        state.dismiss(); latestAction = nil; publish()
        hostPID = process.processIdentifier
        let application = AXUIElementCreateApplication(hostPID)
        // Bound a wedged system AX server's individual calls; this is a read timeout.
        AXUIElementSetMessagingTimeout(application, 0.05)
        var result: AXObserver?
        guard AXObserverCreate(hostPID, hiNotificationAXCallback, &result) == .success, let result else {
            status = .unsupportedStructure
            lastResult = "observer_creation_failed"
            return
        }
        let registered = [kAXWindowCreatedNotification, kAXCreatedNotification].map {
            AXObserverAddNotification(result, application, $0 as CFString, nil)
        }
        guard registered.contains(.success) else {
            status = .unsupportedStructure; lastResult = "events_not_supported"; return
        }
        // Some OS versions support this app-level callback; a confirmed empty snapshot then
        // retires card identities before the system can reuse the window/element handles.
        AXObserverAddNotification(result, application, kAXUIElementDestroyedNotification as CFString, nil)
        observer = result
        host = application
        // A newly enabled/restored observer must not replay banners already on the screen.
        let baseline = captures(includeDetails: false)
        cardTracker.beginBaseline(baseline.cards.map(\.content), now: ProcessInfo.processInfo.systemUptime)
        awaitingBaseline = !baseline.complete
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
        status = .mirrorOnly
    }

    /// A user-requested native probe exposes only structural counts/capabilities. It neither
    /// publishes a notice nor attempts AX writes, clicks, or notification history access.
    func refreshDiagnostics() {
        refresh()
        if observer != nil { _ = captures(includeDetails: false) }
        updateDiagnostics()
    }

    /// Called only by the shared presentation coordinator; never closes a system notification.
    func dismiss() {
        state.dismiss()
        latestAction = nil
        publish()
    }

    /// Original actions are attempted only while the same, unambiguous live card still exists.
    /// If it expired, opening Hi is the only fallback; no guessed deep links or UI automation.
    func clickLatest() {
        guard enabled, state.applicationAvailable, current != nil else { return }
        var openedOriginal = false
        if AXIsProcessTrusted(), let action = latestAction, action.hostPID == hostPID,
           let live = captures(includeDetails: false).cards.first(where: {
               $0.candidate.identity == action.identity && $0.fingerprint == action.fingerprint
           }),
           CFEqual(live.card, action.card), CFEqual(live.window, action.window),
           actions(of: live.card).contains(kAXPressAction as String) {
            openedOriginal = AXUIElementPerformAction(live.card, kAXPressAction as CFString) == .success
        }
        dismiss()
        if !openedOriginal, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    fileprivate func notificationCenterChanged(_ element: AXUIElement, from sourceObserver: AXObserver, notification: String) {
        guard let observer, CFEqual(observer, sourceObserver), enabled, state.applicationAvailable else { return }
        var pid: pid_t = 0
        if notification != kAXUIElementDestroyedNotification as String {
            guard AXUIElementGetPid(element, &pid) == .success, pid == hostPID else { return }
        }
        scanTask?.cancel()
        let expectedGeneration = generation
        scanTask = Task { @MainActor [weak self] in
            // AX window creation can precede the banner's attributed subtree.
            for delay in [0.1, 0.15, 0.35] {
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
                guard let self, !Task.isCancelled, self.generation == expectedGeneration,
                      self.enabled, self.state.applicationAvailable else { return }
                self.scanNewBanners()
            }
        }
    }

    private func scanNewBanners() {
        guard AXIsProcessTrusted() else { refresh(); return }
        let snapshot = captures(includeDetails: detailed)
        let now = ProcessInfo.processInfo.systemUptime
        guard !awaitingBaseline else {
            cardTracker.beginBaseline(snapshot.cards.map(\.content), now: now)
            awaitingBaseline = !snapshot.complete
            return
        }
        cardTracker.reconcileVisibleCards(snapshot.visibleCardIDs, snapshotComplete: snapshot.complete)
        for capture in snapshot.cards {
            let change = cardTracker.observe(capture.content, now: now)
            let eventID: String
            switch change {
            case .ignored: continue
            case let .new(id):
                eventID = id
                let candidate = HiNotificationCandidate(identity: id, sender: capture.candidate.sender, body: capture.candidate.body)
                guard state.receive(candidate, now: now) else { continue }
                deliveryCount += 1
                status = .mirrorOnly
            case let .update(id):
                eventID = id
                guard state.current?.id == id else { continue }
                state.refreshCurrentContent(HiNotificationCandidate(identity: id, sender: capture.candidate.sender, body: capture.candidate.body))
            }
            if state.current?.id == eventID {
                latestAction = ActionReference(card: capture.card, window: capture.window,
                                              identity: capture.candidate.identity,
                                              fingerprint: capture.fingerprint, hostPID: hostPID)
                publish()
            }
        }
        updateDiagnostics()
    }

    private func captures(includeDetails: Bool) -> CaptureSnapshot {
        guard let host else { return CaptureSnapshot(cards: [], visibleCardIDs: [], complete: false) }
        readDeadline = ProcessInfo.processInfo.systemUptime + 0.2
        readHadFailure = false
        defer { readDeadline = nil }
        let allWindows = elements(host, kAXWindowsAttribute)
        let windows = Array(allWindows.prefix(16))
        if allWindows.count > 16 { readHadFailure = true }
        lastWindowCount = windows.count
        lastCardCount = 0; lastHiCount = 0; lastPositionSettable = nil
        diagnosticStructure = HiAXDiagnosticStructure()
        diagnosticVisitedElements.removeAll(keepingCapacity: true)
        lastKnownFields.removeAll(keepingCapacity: true)
        lastResult = windows.isEmpty ? "no_visible_windows" : "no_recognized_hi_card"
        defer { updateDiagnostics() }
        var focused: CFTypeRef?
        recordReadResult(AXUIElementCopyAttributeValue(host, kAXFocusedWindowAttribute as CFString, &focused))
        var visibleIDs = Set<String>()
        let captured: [Capture] = windows.compactMap { window in
            var nodes: [AXUIElement] = []
            guard collect(window, depth: 0, into: &nodes) else { readHadFailure = true; return nil }
            guard let windowFrame = frame(of: window) else { readHadFailure = true; return nil }
            guard isOnScreen(windowFrame) else { return nil }
            // Keep a baseline while its AX element still exists, even during transient
            // subrole/attribution changes. Never parse an opened Notification Center panel.
            visibleIDs.formUnion(nodes.map { cardIdentity(window: window, card: $0) })
            if let focused, CFEqual(focused, window) {
                lastResult = "focused_window_excluded"
                diagnosticStructure.recordSource(.unparsed)
                return nil
            }
            let allCards = nodes.filter { Self.bannerSubroles.contains(string($0, kAXSubroleAttribute) ?? "") }
            let grouped = nodes.contains { Self.stackSubroles.contains(string($0, kAXSubroleAttribute) ?? "") }
            lastCardCount += allCards.count
            if grouped || allCards.count > 1 { lastResult = "grouped_or_multiple_cards_rejected" }
            if allCards.isEmpty { lastResult = "no_supported_banner_subrole" }
            if allCards.count != 1 || grouped { diagnosticStructure.recordSource(.unparsed) }
            guard allCards.count == 1, !grouped, let card = allCards.first,
                  let frame = frame(of: card), frame.width >= 140, frame.width <= 700,
                  frame.height >= 35, frame.height <= 350, isOnScreen(frame),
                  let description = attributedDescription(card),
                  let appName = HiNotificationSourceEvidence.attributedAppName(description) else {
                if allCards.count == 1 && !grouped { diagnosticStructure.recordSource(.unparsed) }
                return nil
            }
            let evidence = HiNotificationSourceEvidence(appNames: [appName])
            let isHi = evidence.isUnambiguouslyHi(knownDisplayNames: knownHiNames())
            diagnosticStructure.recordSource(isHi ? .hi : .other)
            guard isHi else { return nil }
            lastHiCount += 1
            lastResult = "recognized_hi_card"
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success {
                lastPositionSettable = settable.boolValue
            }
            var cardNodes: [AXUIElement] = []
            guard collect(card, depth: 0, into: &cardNodes) else { return nil }
            // Hasher is randomized per process. Neither this token nor raw text is logged/saved.
            let identity = cardIdentity(window: window, card: card)
            var digest = Hasher()
            digest.combine(identity)
            var sender: String?
            var bodyParts: [String] = []
            var hasPayload = false
            var seenFields = Set<String>()
            for node in cardNodes where string(node, kAXRoleAttribute) == kAXStaticTextRole as String {
                guard let value = string(node, kAXValueAttribute), !value.isEmpty else { continue }
                let field = (string(node, kAXIdentifierAttribute) ?? "").lowercased()
                guard ["title", "subtitle", "body"].contains(field) else { continue }
                lastKnownFields.insert(field)
                digest.combine(field); digest.combine(value)
                if field == "body", !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasPayload = true }
                guard includeDetails, seenFields.insert(field + "\u{0}" + value).inserted else { continue }
                // No heuristic slicing of arbitrary localized accessibility descriptions.
                // Unknown layouts retain a useful private notice instead of inventing a sender.
                if field == "title" { sender = value }
                else if field == "body" || field == "subtitle" { bodyParts.append(value) }
            }
            return Capture(candidate: HiNotificationCandidate(identity: identity, sender: sender,
                           body: bodyParts.isEmpty ? nil : bodyParts.joined(separator: " ")),
                           fingerprint: String(digest.finalize(), radix: 16),
                           hasPayload: hasPayload,
                           card: card, window: window)
        }
        let complete = !readHadFailure && withinReadBudget
        // Partial AX payloads cannot drive fingerprint changes or original-action validation.
        return CaptureSnapshot(cards: complete ? captured : [], visibleCardIDs: visibleIDs, complete: complete)
    }

    private static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    private static let stackSubroles: Set<String> = ["AXNotificationCenterBannerStack", "AXNotificationCenterAlertStack"]

    private func knownHiNames() -> Set<String> {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID),
              let bundle = Bundle(url: url), bundle.bundleIdentifier == Self.bundleID else { return [] }
        var names = Set(["hi", "Hi", bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                         bundle.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 })
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier != Self.bundleID && $0.bundleIdentifier != "com.apple.notificationcenterui"
        }.compactMap(\.localizedName)
        names = names.filter { name in !others.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        return names
    }

    private func publish() { if current != state.current { current = state.current } }

    private func updateDiagnostics() {
        let position = lastPositionSettable.map { String($0) } ?? "unverified"
        let fields = lastKnownFields.sorted().joined(separator: ",")
        let summary = "AX: \(AXIsProcessTrusted()) · Observer: \(observer != nil) · Host: \(hostPID) · Windows: \(lastWindowCount) · Cards: \(lastCardCount) · Hi: \(lastHiCount) · Delivered: \(deliveryCount) · Result: \(lastResult) · Fields: \(fields) · Position: \(position) (hide unverified) · \(diagnosticStructure.summary)"
        if diagnosticsSummary != summary { diagnosticsSummary = summary }
    }

    private func ensureHealthCheck() {
        guard healthTask == nil else { return }
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self, self.enabled, self.state.applicationAvailable else { return }
                self.refresh()
            }
        }
    }

    private func stopObserving() {
        healthTask?.cancel(); healthTask = nil
        stopObserverOnly()
        latestAction = nil
    }

    private func stopObserverOnly() {
        generation &+= 1
        scanTask?.cancel(); scanTask = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; host = nil; hostPID = 0
        cardTracker.clear()
        awaitingBaseline = true
    }

    private func collect(_ element: AXUIElement, depth: Int, into nodes: inout [AXUIElement]) -> Bool {
        guard depth <= 10, nodes.count < 160, withinReadBudget else { return false }
        nodes.append(element)
        if diagnosticVisitedElements.count < 2560, diagnosticVisitedElements.insert(CFHash(element)).inserted {
            diagnosticStructure.record(role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute))
        }
        for child in elements(element, kAXChildrenAttribute) {
            guard collect(child, depth: depth + 1, into: &nodes) else { return false }
        }
        return true
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard prepareRead(element) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        recordReadResult(result)
        guard result == .success else { return nil }
        return value as? String
    }

    private func attributedDescription(_ element: AXUIElement) -> String? {
        guard prepareRead(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXAttributedDescription" as CFString, &value) == .success,
              let value else { return nil }
        if let text = value as? NSAttributedString { return text.string }
        return value as? String
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard prepareRead(element) else { return [] }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        recordReadResult(result)
        if attribute == kAXWindowsAttribute, result != .success { readHadFailure = true }
        guard result == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func actions(of element: AXUIElement) -> [String] {
        guard prepareRead(element) else { return [] }
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard prepareRead(element) else { return nil }
        var originValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &originValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let originValue, let sizeValue,
              CFGetTypeID(originValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(originValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func isOnScreen(_ frame: CGRect) -> Bool {
        // AX uses global top-left coordinates, unlike AppKit's bottom-left screen frames.
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.contains { screen in
            let axFrame = CGRect(x: screen.frame.minX, y: desktopTop - screen.frame.maxY,
                                 width: screen.frame.width, height: screen.frame.height)
            return axFrame.intersection(frame).width >= frame.width * 0.5 &&
                   axFrame.intersection(frame).height >= frame.height * 0.5
        }
    }

    private var withinReadBudget: Bool {
        guard let readDeadline else { return true }
        return ProcessInfo.processInfo.systemUptime < readDeadline
    }

    private func prepareRead(_ element: AXUIElement) -> Bool {
        guard withinReadBudget else {
            lastResult = "ax_read_budget_exceeded"; readHadFailure = true; return false
        }
        AXUIElementSetMessagingTimeout(element, 0.05)
        return true
    }

    private func recordReadResult(_ result: AXError) {
        if result == .cannotComplete || result == .invalidUIElement || result == .apiDisabled {
            readHadFailure = true
        }
    }

    private func cardIdentity(window: AXUIElement, card: AXUIElement) -> String {
        var hasher = Hasher()
        hasher.combine(hostPID); hasher.combine(CFHash(window)); hasher.combine(CFHash(card))
        return String(hasher.finalize(), radix: 16)
    }
}

private func hiNotificationAXCallback(_ observer: AXObserver, _ element: AXUIElement,
                                      _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    Task { @MainActor in
        HiNotificationManager.shared.notificationCenterChanged(element, from: observer, notification: notification as String)
    }
}
