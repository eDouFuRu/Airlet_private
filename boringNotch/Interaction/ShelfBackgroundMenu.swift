import AppKit
import SwiftUI

/// The right-click menu for the shelf's empty space.
///
/// SwiftUI's `.contextMenu` does nothing here: showing it needs the window to take the click
/// as key, and the island deliberately never becomes key. The shelf's per-item menu already
/// works around this with a hand-built `NSMenu` and `popUpContextMenu`; this is the same
/// approach for the background, and it matters most exactly when the shelf is empty — that is
/// when there is no item to right-click and paste is the only thing the user could want.
struct ShelfBackgroundMenu: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BackgroundMenuView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class BackgroundMenuView: NSView {
        /// Left clicks, drags and drops must keep reaching the SwiftUI content underneath;
        /// only the right button is claimed. `hitTest` cannot express "this button only", so
        /// the view stays transparent to hit testing and the right click is picked up from
        /// the window's event stream instead.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }
                MainActor.assumeIsolated { self.present(event) }
                return nil
            }
        }

        deinit { monitor.map(NSEvent.removeMonitor) }

        private var monitor: Any?

        @MainActor private func present(_ event: NSEvent) {
            let menu = NSMenu()
            let paste = NSMenuItem(title: L("Paste"), action: #selector(pasteFromMenu), keyEquivalent: "")
            paste.target = self
            paste.isEnabled = ShelfClipboardActions.clipboardHasStageableContent
            menu.addItem(paste)
            menu.autoenablesItems = false
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func pasteFromMenu() {
            MainActor.assumeIsolated { ShelfClipboardActions.paste() }
        }
    }
}
