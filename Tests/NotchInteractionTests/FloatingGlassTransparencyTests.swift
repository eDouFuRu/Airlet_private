import XCTest
@testable import NotchInteractionCore

final class FloatingGlassTransparencyTests: XCTestCase {
    func testMidpointPreservesThePreviouslyShippedClearGlass() {
        let levels = FloatingGlassTransparency(FloatingGlassTransparency.original)
        XCTAssertEqual(levels.glassOpacity, 1)
        XCTAssertEqual(levels.backingOpacity, 0)
        XCTAssertEqual(levels.rimOpacity, 0.4)
    }

    func testSliderCanMoveInBothVisualDirectionsWhileRetainingSomeGlass() {
        let solid = FloatingGlassTransparency(0)
        let original = FloatingGlassTransparency(0.5)
        let clear = FloatingGlassTransparency(1)

        XCTAssertGreaterThan(solid.backingOpacity, original.backingOpacity)
        XCTAssertEqual(solid.glassOpacity, original.glassOpacity)
        XCTAssertEqual(clear.backingOpacity, 0)
        XCTAssertLessThan(clear.glassOpacity, original.glassOpacity)
        XCTAssertGreaterThan(clear.glassOpacity, 0)
    }

    func testInvalidSavedValuesCannotProduceInvisibleOrOverfilledShell() {
        XCTAssertEqual(FloatingGlassTransparency(.nan), FloatingGlassTransparency(0.5))
        XCTAssertEqual(FloatingGlassTransparency(-1), FloatingGlassTransparency(0))
        XCTAssertEqual(FloatingGlassTransparency(2), FloatingGlassTransparency(1))
    }
}
