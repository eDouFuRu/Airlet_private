// Custom changes for 工位充电岛. Uses monotonic time supplied by the caller.
import Foundation

struct NotchHoverStateMachine {
    enum Action: Equatable { case open, close }
    struct Pending: Equatable {
        let action: Action
        let deadline: TimeInterval
    }

    let openDelay: TimeInterval
    let closeDelay: TimeInterval
    private(set) var pending: Pending?

    init(openDelay: TimeInterval = 0.150, closeDelay: TimeInterval = 0.100) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
    }

    mutating func cancel() { pending = nil }

    /// Repeated movement within one region does not restart its dwell timer.
    mutating func update(enabled: Bool, expanded: Bool, inTrigger: Bool,
                         inVisibleContent: Bool, holdsOpen: Bool, now: TimeInterval) -> Action? {
        guard enabled else { cancel(); return nil }
        let desired: Action?
        if expanded {
            desired = (inTrigger || inVisibleContent || holdsOpen) ? nil : .close
        } else {
            // A visible media wing or a drag entering its region cannot open the island.
            desired = inTrigger ? .open : nil
        }
        guard let desired else { cancel(); return nil }
        if pending?.action != desired {
            pending = Pending(action: desired, deadline: now + (desired == .open ? openDelay : closeDelay))
        }
        if let pending, now >= pending.deadline {
            self.pending = nil
            return desired
        }
        return nil
    }
}
