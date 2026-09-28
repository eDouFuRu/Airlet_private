import XCTest
@testable import NotchInteractionCore

final class IslandSurfaceVisibilityTests: XCTestCase {
    private func show(floating: Bool = true, autoHide: Bool = true, expanded: Bool = false,
                      pointer: Bool = false, transient: Bool = false, available: Bool = true) -> Bool {
        IslandSurfaceVisibility.shouldShow(isFloating: floating, autoHide: autoHide, expanded: expanded,
                                           pointerInside: pointer, transient: transient, available: available)
    }

    func testAvailabilityAlwaysWinsOverEveryReasonToShow() {
        XCTAssertFalse(show(floating: false, autoHide: false, expanded: true, pointer: true,
                            transient: true, available: false))
    }

    func testNativeAndDisabledAutoHideRemainVisible() {
        XCTAssertTrue(show(floating: false))
        XCTAssertTrue(show(autoHide: false))
        XCTAssertFalse(show())
    }

    func testTransientExpiryReturnsToHiddenUnlessPointerOrExpandedStillNeedsSurface() {
        XCTAssertTrue(show(transient: true))
        XCTAssertFalse(show(transient: false))
        XCTAssertTrue(show(pointer: true, transient: false))
        XCTAssertTrue(show(expanded: true, transient: false))
    }

    func testPointerRevealsWithHoverExpansionDisabled() {
        var machine = NotchHoverStateMachine(openDelay: 0.4, closeDelay: 0.2)
        XCTAssertTrue(show(pointer: true))
        XCTAssertNil(machine.update(enabled: false, expanded: false, inTrigger: true,
                                    inVisibleContent: true, holdsOpen: false, now: 1))
        XCTAssertNil(machine.pending)
    }

    func testEarlyExitCancelsExpansionAndFastReentryStartsFreshDwell() {
        var machine = NotchHoverStateMachine(openDelay: 0.4, closeDelay: 0.2)
        XCTAssertTrue(show(pointer: true))
        XCTAssertNil(machine.update(enabled: true, expanded: false, inTrigger: true,
                                    inVisibleContent: true, holdsOpen: false, now: 0))
        XCTAssertNil(machine.update(enabled: true, expanded: false, inTrigger: false,
                                    inVisibleContent: false, holdsOpen: false, now: 0.2))
        XCTAssertFalse(show())
        XCTAssertNil(machine.pending)
        XCTAssertNil(machine.update(enabled: true, expanded: false, inTrigger: true,
                                    inVisibleContent: true, holdsOpen: false, now: 0.3))
        XCTAssertEqual(machine.pending?.deadline ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(machine.update(enabled: true, expanded: false, inTrigger: true,
                                      inVisibleContent: true, holdsOpen: false, now: 0.701), .open)
    }

    func testZeroDelayOpensImmediatelyAndPinnedPanelStaysVisible() {
        var machine = NotchHoverStateMachine(openDelay: 0, closeDelay: 0)
        XCTAssertEqual(machine.update(enabled: true, expanded: false, inTrigger: true,
                                      inVisibleContent: true, holdsOpen: false, now: 0), .open)
        XCTAssertNil(machine.update(enabled: true, expanded: true, inTrigger: false,
                                    inVisibleContent: false, holdsOpen: true, now: 1))
        XCTAssertTrue(show(expanded: true))
    }

    func testPointerOnOneScreenDoesNotRevealAnotherScreen() {
        XCTAssertTrue(show(pointer: true))
        XCTAssertFalse(show(pointer: false))
    }
}
