import AppKit
import Combine
import SwiftUI

/// Local, fixed-vocabulary counters. No pointer coordinates, tool names,
/// identifiers or clipboard content are retained. No publication during a drag
/// can invalidate the surrounding Form; the final result is published afterward.
@MainActor final class ToolReorderDiagnostics: ObservableObject {
    static let shared = ToolReorderDiagnostics()
    @Published private(set) var summary = ToolReorderEventCounters().summary
    private var counters = ToolReorderEventCounters()

    fileprivate func record(_ event: ToolReorderEvent) {
        counters.record(event)
        if !ToolReorderLocalRuntime.shared.isActive { refresh() }
    }
    func refresh() { summary = "mode=local\n" + counters.summary }
    func reset() { counters = ToolReorderEventCounters(); refresh() }
}

/// The handle owns the ordinary AppKit down/drag/up sequence. Sorting is local to
/// this window, so no OS drag session, pasteboard or cross-app operation is used.
struct NativeToolReorderHandle: NSViewRepresentable {
    let payload: ToolGridDragPayload
    let title: String
    let symbolName: String
    let hint: String

    func makeNSView(context: Context) -> NativeToolReorderHandleView {
        let view = NativeToolReorderHandleView()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NativeToolReorderHandleView, context: Context) {
        view.payload = payload
        view.previewTitle = title
        view.previewSymbol = symbolName
        view.toolTip = hint
        view.setAccessibilityLabel(hint)
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: NativeToolReorderHandleView, coordinator: ()) {
        ToolReorderLocalRuntime.shared.cancel(ifSource: view)
    }
}

/// Pure visual marker for one row/card. Normal clicks always pass through;
/// local hit testing is performed explicitly against bounds AND visibleRect.
struct NativeToolReorderDropTarget: NSViewRepresentable {
    let cornerRadius: CGFloat
    let canDrop: (ToolGridDragPayload) -> Bool
    let performDrop: (ToolGridDragPayload) -> Bool

    func makeNSView(context: Context) -> NativeToolReorderDropView {
        let view = NativeToolReorderDropView()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NativeToolReorderDropView, context: Context) {
        view.cornerRadius = cornerRadius
        view.canDrop = canDrop
        view.performDrop = performDrop
    }
    static func dismantleNSView(_ view: NativeToolReorderDropView, coordinator: ()) {
        view.deactivate()
    }
}

@MainActor private final class ToolReorderLocalRuntime {
    static let shared = ToolReorderLocalRuntime()
    private let destinations = NSHashTable<NativeToolReorderDropView>.weakObjects()
    private weak var source: NativeToolReorderHandleView?
    private weak var sourceWindow: NSWindow?
    private var payload: ToolGridDragPayload?
    private weak var highlighted: NativeToolReorderDropView?
    private var evaluatedTarget = false
    private var preview: ToolReorderPreviewView?
    private var escapeMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    var isActive: Bool { source != nil && sourceWindow != nil && payload != nil }

    func register(_ view: NativeToolReorderDropView) { destinations.add(view) }

    func begin(source: NativeToolReorderHandleView, payload: ToolGridDragPayload, at point: NSPoint) {
        guard let window = source.window, window.isVisible, source.superview != nil else {
            source.cancelPress()
            return
        }
        if isActive { cancel() }
        self.source = source
        sourceWindow = window
        self.payload = payload
        ToolReorderDiagnostics.shared.record(.localBegan)
        let ghost = ToolReorderPreviewView()
        ghost.image = source.makePreview()
        ghost.imageScaling = .scaleNone
        ghost.alphaValue = 0.94
        window.contentView?.addSubview(ghost)
        preview = ghost
        // Local events only. Escape is consumed only while this local drag is
        // active. No global keyboard/mouse monitor or focus change is installed.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.isActive == true else { return event }
            self?.cancel()
            return nil
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
        update(from: source, at: point)
    }

    func update(from source: NativeToolReorderHandleView, at point: NSPoint) {
        guard self.source === source, let window = sourceWindow,
              source.window === window, source.superview != nil,
              window.isVisible, insideContent(point, window: window) else {
            cancel(ifSource: source)
            return
        }
        ToolReorderDiagnostics.shared.record(.localMoved)
        let candidates = candidates(at: point, window: window)
        let target = candidates.count == 1 ? candidates.first : nil
        if !evaluatedTarget || highlighted !== target {
            evaluatedTarget = true
            highlighted?.setTargeted(false)
            highlighted = target
            target?.setTargeted(true)
            ToolReorderDiagnostics.shared.record(target == nil ? .targetRejected : .targetAccepted)
        }
        if let preview, let image = preview.image, let host = window.contentView {
            let local = host.convert(point, from: nil)
            // The ghost stays inside this window and never participates in hit
            // testing. These coordinates are transient rendering state only.
            let x = min(max(host.bounds.minX, local.x + 14), max(host.bounds.minX, host.bounds.maxX - image.size.width))
            let y = min(max(host.bounds.minY, local.y + 18), max(host.bounds.minY, host.bounds.maxY - image.size.height))
            preview.frame = NSRect(origin: NSPoint(x: x, y: y), size: image.size)
        }
    }

    func finish(from source: NativeToolReorderHandleView, at point: NSPoint) {
        guard self.source === source else { source.finishPress(acceptedTargets: 0); return }
        let candidates: [NativeToolReorderDropView]
        if let window = sourceWindow, source.window === window, source.superview != nil,
           window.isVisible, insideContent(point, window: window) {
            candidates = self.candidates(at: point, window: window)
        } else { candidates = [] }
        // Mark the gesture terminal BEFORE store.drop can reorder/remove its
        // source view. Then clear observers/highlight before publishing data.
        let accepted = source.finishPress(acceptedTargets: candidates.count)
        let action = candidates.count == 1 ? candidates.first?.performDrop : nil
        let payload = self.payload
        cleanup()
        if accepted, let action, let payload {
            ToolReorderDiagnostics.shared.record(.dropAttempted)
            let committed = action(payload) // store revalidates UUID and current configuration
            ToolReorderDiagnostics.shared.record(committed ? .dropCommitted : .dropRejected)
            ToolReorderDiagnostics.shared.record(.localFinished)
        } else { ToolReorderDiagnostics.shared.record(.localCancelled) }
    }

    func cancel(ifSource source: NativeToolReorderHandleView) {
        guard self.source === source else { return }
        cancel()
    }
    func cancel() {
        let wasActive = isActive
        source?.cancelPress()
        cleanup()
        if wasActive { ToolReorderDiagnostics.shared.record(.localCancelled) }
    }
    private func cleanup() {
        highlighted?.setTargeted(false)
        highlighted = nil
        evaluatedTarget = false
        preview?.removeFromSuperview()
        preview = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        source = nil
        sourceWindow = nil
        payload = nil
        ToolReorderDiagnostics.shared.refresh()
    }
    private func insideContent(_ point: NSPoint, window: NSWindow) -> Bool {
        guard let host = window.contentView else { return false }
        return host.bounds.contains(host.convert(point, from: nil))
    }
    private func candidates(at point: NSPoint, window: NSWindow) -> [NativeToolReorderDropView] {
        guard let payload else { return [] }
        return destinations.allObjects.filter { view in
            view.window === window && !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0 &&
                ToolReorderTargetGeometry.visibleTarget(bounds: view.bounds, visibleRect: view.visibleRect)
                    .contains(view.convert(point, from: nil)) && view.canDrop(payload)
        }
    }
}

@MainActor private final class ToolReorderPreviewView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

@MainActor final class NativeToolReorderHandleView: NSView {
    fileprivate var payload: ToolGridDragPayload?
    fileprivate var previewTitle = ""
    fileprivate var previewSymbol = "line.3.horizontal"
    private var downPoint: NSPoint?
    private var gesture = ToolReorderLocalGesture()
    private var pressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { ToolReorderLocalRuntime.shared.cancel(ifSource: self) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { ToolReorderLocalRuntime.shared.cancel(ifSource: self) }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func draw(_ dirtyRect: NSRect) {
        let background = pressed ? NSColor.controlAccentColor.withAlphaComponent(0.22)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.09)
        background.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        let icon = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        icon?.draw(in: bounds.insetBy(dx: 6, dy: 6))
    }
    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        gesture.press()
        pressed = true
        needsDisplay = true
        ToolReorderDiagnostics.shared.record(.mouseDown)
    }
    override func mouseDragged(with event: NSEvent) {
        ToolReorderDiagnostics.shared.record(.mouseDragged)
        guard let downPoint, let payload else { return }
        let point = event.locationInWindow
        let wasDragging = gesture.isDragging
        guard gesture.move(distance: hypot(point.x - downPoint.x, point.y - downPoint.y)) else { return }
        if !wasDragging {
            ToolReorderLocalRuntime.shared.begin(source: self, payload: payload, at: point)
        } else { ToolReorderLocalRuntime.shared.update(from: self, at: point) }
    }
    override func mouseUp(with event: NSEvent) {
        if gesture.isDragging {
            ToolReorderLocalRuntime.shared.finish(from: self, at: event.locationInWindow)
        } else {
            if gesture.phase == .pressed { ToolReorderDiagnostics.shared.record(.clickOnly) }
            _ = finishPress(acceptedTargets: 0)
        }
        downPoint = nil
        pressed = false
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { ToolReorderLocalRuntime.shared.cancel(ifSource: self) }
        else { super.keyDown(with: event) }
    }
    fileprivate func cancelPress() {
        gesture.cancel()
        pressed = false
        needsDisplay = true
    }
    @discardableResult fileprivate func finishPress(acceptedTargets: Int) -> Bool {
        let accepted = gesture.finish(acceptedTargets: acceptedTargets)
        pressed = false
        needsDisplay = true
        return accepted
    }
    fileprivate func makePreview() -> NSImage {
        let title = String(previewTitle.prefix(80)) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
        ]
        let size = NSSize(width: min(280, max(100, title.size(withAttributes: attributes).width + 46)), height: 34)
        let symbol = NSImage(systemSymbolName: previewSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
        return NSImage(size: size, flipped: false) { bounds in
            NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).stroke()
            symbol?.draw(in: NSRect(x: 10, y: 9, width: 16, height: 16))
            title.draw(in: NSRect(x: 34, y: 9, width: size.width - 44, height: 17), withAttributes: attributes)
            return true
        }
    }
}

@MainActor final class NativeToolReorderDropView: NSView {
    fileprivate var cornerRadius: CGFloat = 8
    fileprivate var canDrop: (ToolGridDragPayload) -> Bool = { _ in false }
    fileprivate var performDrop: (ToolGridDragPayload) -> Bool = { _ in false }
    private var targeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        setAccessibilityElement(false)
        ToolReorderLocalRuntime.shared.register(self)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    fileprivate func deactivate() {
        setTargeted(false)
        canDrop = { _ in false }
        performDrop = { _ in false }
    }
    fileprivate func setTargeted(_ value: Bool) {
        guard targeted != value else { return }
        targeted = value
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard targeted else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }
}
