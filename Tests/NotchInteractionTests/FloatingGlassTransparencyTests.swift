import XCTest
@testable import NotchInteractionCore

final class FloatingGlassTransparencyTests: XCTestCase {
    func testMidpointAddsAReadableVeilWithoutAnOpaqueBacking() {
        let levels = FloatingGlassTransparency(FloatingGlassTransparency.original)
        XCTAssertEqual(levels.backingOpacity, 0)
        XCTAssertEqual(levels.veilOpacity, 0.15, accuracy: 0.0001)
        XCTAssertEqual(levels.nativeGlassCenterOpacity, 1)
    }

    func testClearestSettingPreservesAcceptedCentreTransparencyWithoutAddedHaze() {
        let solid = FloatingGlassTransparency(0)
        let original = FloatingGlassTransparency(0.5)
        let clear = FloatingGlassTransparency(1)

        XCTAssertGreaterThan(solid.backingOpacity, original.backingOpacity)
        XCTAssertGreaterThan(solid.veilOpacity, original.veilOpacity)
        XCTAssertEqual(clear.backingOpacity, 0)
        XCTAssertEqual(clear.veilOpacity, 0)
        XCTAssertLessThan(clear.veilOpacity, original.veilOpacity)
        XCTAssertEqual(clear.nativeGlassCenterOpacity, 0.35, accuracy: 0.0001)
        XCTAssertGreaterThan(clear.legacyMaterialOpacity, 0)
        XCTAssertLessThan(clear.legacyMaterialOpacity, original.legacyMaterialOpacity)
    }

    func testIncreasingTransparencyNeverAddsOpacityOrJumpsAtTheMidpoint() {
        var previous = FloatingGlassTransparency(0)
        for step in 1...100 {
            let current = FloatingGlassTransparency(Double(step) / 100)
            for (before, after) in zip(
                [previous.backingOpacity, previous.veilOpacity, previous.nativeGlassCenterOpacity,
                 previous.legacyMaterialOpacity],
                [current.backingOpacity, current.veilOpacity, current.nativeGlassCenterOpacity,
                 current.legacyMaterialOpacity]) {
                XCTAssertTrue((0...1).contains(after))
                XCTAssertLessThanOrEqual(after, before)
                XCTAssertLessThan(before - after, 0.03)
            }
            previous = current
        }
    }

    func testInvalidSavedValuesCannotProduceInvisibleOrOverfilledShell() {
        XCTAssertEqual(FloatingGlassTransparency(.nan), FloatingGlassTransparency(0.5))
        XCTAssertEqual(FloatingGlassTransparency(-1), FloatingGlassTransparency(0))
        XCTAssertEqual(FloatingGlassTransparency(2), FloatingGlassTransparency(1))
    }

    func testOpticalBandLeavesAClearCentreAtCompactAndExpandedHeights() {
        for height in [16.0, 18, 22, 26, 36, 150, 240, 400] {
            let optics = FloatingGlassLensMetrics(height: height)
            XCTAssertGreaterThan(optics.edgeWidth, 0)
            XCTAssertLessThanOrEqual(optics.edgeWidth, 24)
            // Even the main feather tails must not meet across a small capsule.
            XCTAssertLessThan(2 * (optics.edgeWidth + 3 * optics.featherRadius), height)
        }
        XCTAssertEqual(FloatingGlassLensMetrics(height: 400), FloatingGlassLensMetrics(height: 240))
        XCTAssertEqual(FloatingGlassLensMetrics(height: -.infinity).edgeWidth, 0)
        XCTAssertEqual(FloatingGlassLensMetrics(height: .nan).edgeWidth, 0)
        XCTAssertEqual(FloatingGlassLensMetrics(height: -1).edgeWidth, 0)
    }
}
