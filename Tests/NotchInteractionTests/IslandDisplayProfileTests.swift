import XCTest
@testable import NotchInteractionCore

final class IslandDisplayProfileTests: XCTestCase {
    private let screen = CGRect(x: -1_600, y: -200, width: 1_600, height: 1_000)

    private func floating(width: CGFloat = 1_600, menu: CGFloat = 24) -> IslandDisplayProfile {
        IslandDisplayProfile(screenWidth: width, safeTop: 0, cameraWidth: 200,
                             nativeClosedHeight: 32, menuBarHeight: menu)
    }

    func testFloatingCapsuleFitsMenuBarWithThreePointMargins() {
        for height: CGFloat in [22, 24, 28, 32, 37] {
            let profile = floating(menu: height)
            let rect = profile.compactFrame(in: screen)
            XCTAssertTrue(profile.isFloating)
            XCTAssertEqual(profile.contour, .floating)
            XCTAssertEqual(rect.midX, screen.midX)
            XCTAssertEqual(rect.width, 120)
            XCTAssertEqual(screen.maxY - rect.maxY, 3)
            XCTAssertEqual(rect.minY - (screen.maxY - height), 3)
            XCTAssertEqual(profile.cameraExclusionWidth, 0)
            XCTAssertEqual(profile.expandedHeaderHeight, 36)
        }
    }

    func testSizesAreInDisplayPointsAndDoNotDependOnBackingScale() {
        let profile = floating(width: 1_920, menu: 24)
        let pointFrame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        for scale: CGFloat in [1, 1.5, 2] {
            let pixelFrame = pointFrame.applying(CGAffineTransform(scaleX: scale, y: scale))
            let restored = pixelFrame.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            XCTAssertEqual(profile.compactFrame(in: restored), profile.compactFrame(in: pointFrame))
        }
    }

    func testWidthCapReservesScreenMargins() {
        XCTAssertEqual(floating().maximumWidth, 640)
        XCTAssertEqual(floating(width: 600).maximumWidth, 552)
        XCTAssertEqual(floating(width: 140).compactBaseWidth, 92)
        XCTAssertEqual(floating(width: 140).compactFrame(in: CGRect(x: 0, y: 0, width: 140, height: 500)).minX, 24)
    }

    func testChosenFloatingWidthIsScreenClampedAndDoesNotChangeNotchGeometry() {
        let wide = IslandDisplayProfile(screenWidth: 1_600, safeTop: 0, cameraWidth: 200,
                                        nativeClosedHeight: 32, menuBarHeight: 24, floatingBaseWidth: 310)
        XCTAssertEqual(wide.compactBaseWidth, 310)
        XCTAssertEqual(wide.compactFrame(in: screen).midX, screen.midX)
        let visible = wide.compactFrame(in: screen)
        XCTAssertEqual(wide.floatingTrigger(in: screen, visibleFrame: visible, cornerRadius: 9,
                                            expanded: false, surfaceVisible: true).frame.width, 310)
        XCTAssertEqual(wide.floatingTrigger(in: screen, visibleFrame: visible, cornerRadius: 9,
                                            expanded: false, surfaceVisible: false).frame.width, 120)
        let narrow = IslandDisplayProfile(screenWidth: 280, safeTop: 0, cameraWidth: 200,
                                          nativeClosedHeight: 32, menuBarHeight: 24, floatingBaseWidth: 500)
        XCTAssertEqual(narrow.compactBaseWidth, 232)
        let notched = IslandDisplayProfile(screenWidth: 1_600, safeTop: 37, cameraWidth: 200,
                                           nativeClosedHeight: 32, menuBarHeight: 24, floatingBaseWidth: 500)
        XCTAssertEqual(notched.compactBaseWidth, 200)
        XCTAssertEqual(notched.cameraExclusionWidth, 200)
    }

    func testNativeCameraGeometryAndHeaderStayAttached() {
        let profile = IslandDisplayProfile(screenWidth: 1_728, safeTop: 37, cameraWidth: 185,
                                           nativeClosedHeight: 32, menuBarHeight: 37)
        XCTAssertFalse(profile.isFloating)
        XCTAssertEqual(profile.contour, .notch)
        XCTAssertEqual(profile.topInset, 0)
        XCTAssertEqual(profile.cameraExclusionWidth, 185)
        XCTAssertEqual(profile.compactSize, CGSize(width: 185, height: 32))
        XCTAssertEqual(profile.expandedHeaderHeight, 37)
    }

    func testMenuBarHeightCacheUsesScreenLocalLastMeasurementThenSystemFallback() {
        var cache = IslandMenuBarHeightCache()
        XCTAssertEqual(cache.height(for: "external", measured: 0, systemHeight: 22), 22)
        XCTAssertEqual(cache.height(for: "internal", measured: 37, systemHeight: 22), 37)
        XCTAssertEqual(cache.height(for: "external", measured: 24, systemHeight: 22), 24)
        XCTAssertEqual(cache.height(for: "internal", measured: 0, systemHeight: 22), 37)
        XCTAssertEqual(cache.height(for: "external", measured: .nan, systemHeight: 22), 24)
        XCTAssertEqual(cache.height(for: "external", measured: 900, systemHeight: 22), 24)
        XCTAssertEqual(cache.height(for: "new", measured: 0, systemHeight: .nan), 24)
    }

    func testFloatingWakeTargetExpandsOnlyWhileTheClosedSurfaceIsVisible() {
        let profile = floating()
        let visible = NotchHitRegion.presentationFrame(carrierFrame: screen,
                                                       size: CGSize(width: 420, height: 18), topInset: 3)
        for expanded in [false, true] {
            for visibleSurface in [false, true] {
                let trigger = profile.floatingTrigger(in: screen, visibleFrame: visible,
                                                       cornerRadius: 9, expanded: expanded,
                                                       surfaceVisible: visibleSurface)
                XCTAssertEqual(trigger.frame.width, visibleSurface && !expanded ? 420 : 120)
                let region = NotchHitRegion(triggerRect: trigger.frame, visibleFrame: visible,
                                            topRadius: 9, bottomRadius: 9, contour: .floating,
                                            triggerCornerRadius: trigger.cornerRadius)
                XCTAssertTrue(region.containsTrigger(CGPoint(x: trigger.frame.midX, y: trigger.frame.midY)))
                XCTAssertFalse(region.containsTrigger(CGPoint(x: trigger.frame.minX + 0.1, y: trigger.frame.maxY - 0.1)))
                XCTAssertFalse(region.containsTrigger(CGPoint(x: trigger.frame.midX, y: screen.maxY - 1)))
            }
        }
    }

    func testFloatingPresentationHitContourTracksAnimatedSizeAndTopInset() {
        for size in [CGSize(width: 120, height: 18), CGSize(width: 370, height: 95), CGSize(width: 640, height: 240)] {
            let radius = min(24, size.height / 2)
            let frame = NotchHitRegion.presentationFrame(carrierFrame: screen, size: size, topInset: 3)
            let region = NotchHitRegion(triggerRect: floating().compactFrame(in: screen), visibleFrame: frame,
                                        topRadius: radius, bottomRadius: radius, contour: .floating)
            let drawn = NotchHitRegion.outline(size: size, topRadius: radius, bottomRadius: radius, contour: .floating)
            for x in stride(from: CGFloat(1), through: size.width, by: 7) {
                for y in stride(from: CGFloat(1), through: size.height, by: 7) {
                    let local = CGPoint(x: x, y: y)
                    XCTAssertEqual(region.containsVisible(CGPoint(x: frame.minX + x, y: frame.maxY - y)), drawn.contains(local))
                }
            }
            XCTAssertFalse(region.containsVisible(CGPoint(x: frame.midX, y: screen.maxY - 1)))
            let button = NotchAccessoryControl.rect(visibleFrame: frame, slot: .collapse)
            XCTAssertEqual(screen.maxY - button.midY, 3 + size.height * 0.25)
        }
    }

    func testCollapsingPanelCannotReopenFromItsOutgoingContent() {
        let profile = floating()
        let point = CGPoint(x: screen.midX + 90, y: screen.maxY - 12)
        for delay: TimeInterval in [0, 0.15] {
            var machine = NotchHoverStateMachine(openDelay: delay)
            for height: CGFloat in [180, 120, 60, 24] {
                let visible = NotchHitRegion.presentationFrame(carrierFrame: screen,
                    size: CGSize(width: 420, height: height), topInset: 3)
                let trigger = profile.floatingTrigger(in: screen, visibleFrame: visible,
                    cornerRadius: min(24, height / 2), expanded: false, surfaceVisible: true)
                let region = NotchHitRegion(triggerRect: trigger.frame, visibleFrame: visible,
                    topRadius: 24, bottomRadius: 24, contour: .floating,
                    triggerCornerRadius: trigger.cornerRadius)
                XCTAssertTrue(region.containsVisible(point))
                XCTAssertFalse(region.containsTrigger(point))
                XCTAssertNil(machine.update(enabled: true, expanded: false,
                    inTrigger: region.containsTrigger(point), inVisibleContent: true,
                    holdsOpen: false, now: Double(180 - height)))
                XCTAssertNil(machine.pending)
            }
        }
    }

    func testReturningToBaseCapsuleDuringCollapseRequiresANewDwell() {
        let profile = floating()
        let visible = NotchHitRegion.presentationFrame(carrierFrame: screen,
            size: CGSize(width: 420, height: 140), topInset: 3)
        let trigger = profile.floatingTrigger(in: screen, visibleFrame: visible,
            cornerRadius: 24, expanded: false, surfaceVisible: true)
        let region = NotchHitRegion(triggerRect: trigger.frame, visibleFrame: visible,
            topRadius: 24, bottomRadius: 24, contour: .floating,
            triggerCornerRadius: trigger.cornerRadius)
        let point = CGPoint(x: screen.midX, y: trigger.frame.midY)
        var machine = NotchHoverStateMachine(openDelay: 0.15)
        XCTAssertNil(machine.update(enabled: true, expanded: true, inTrigger: false,
            inVisibleContent: false, holdsOpen: false, now: 0))
        XCTAssertEqual(machine.update(enabled: true, expanded: true, inTrigger: false,
            inVisibleContent: false, holdsOpen: false, now: 0.11), .close)
        XCTAssertNil(machine.update(enabled: true, expanded: false,
            inTrigger: region.containsTrigger(point), inVisibleContent: true,
            holdsOpen: false, now: 0.12))
        XCTAssertEqual(machine.pending?.deadline ?? -1, 0.27, accuracy: 0.0001)
        XCTAssertEqual(machine.update(enabled: true, expanded: false,
            inTrigger: region.containsTrigger(point), inVisibleContent: true,
            holdsOpen: false, now: 0.271), .open)
    }

    func testCompactBriefClickAreaUsesActualHeight() {
        let frame = floating().compactFrame(in: screen)
        let brief = BriefInteractionRegion.rowRect(visibleRect: frame, rowTopInset: 0, height: 18)
        XCTAssertEqual(brief, frame)
        XCTAssertFalse(brief.contains(CGPoint(x: frame.midX, y: frame.minY - 1)))
    }
}
