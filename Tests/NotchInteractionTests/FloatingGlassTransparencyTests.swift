import XCTest
@testable import NotchInteractionCore

final class FloatingGlassTransparencyTests: XCTestCase {
    func testMidpointAddsAReadableVeilWithoutAnOpaqueBacking() {
        let levels = FloatingGlassTransparency(FloatingGlassTransparency.original)
        XCTAssertEqual(levels.backingOpacity, 0)
        XCTAssertGreaterThan(levels.veilOpacity, 0)
    }

    func testSliderAdjustsVeilAndBackingWithoutTurningTheLensOff() {
        let solid = FloatingGlassTransparency(0)
        let original = FloatingGlassTransparency(0.5)
        let clear = FloatingGlassTransparency(1)

        XCTAssertGreaterThan(solid.backingOpacity, original.backingOpacity)
        XCTAssertGreaterThan(solid.veilOpacity, original.veilOpacity)
        XCTAssertEqual(clear.backingOpacity, 0)
        XCTAssertGreaterThan(clear.veilOpacity, 0)
        XCTAssertLessThan(clear.veilOpacity, original.veilOpacity)
        XCTAssertLessThan(clear.legacyMaterialOpacity, original.legacyMaterialOpacity)
    }

    func testInvalidSavedValuesCannotProduceInvisibleOrOverfilledShell() {
        XCTAssertEqual(FloatingGlassTransparency(.nan), FloatingGlassTransparency(0.5))
        XCTAssertEqual(FloatingGlassTransparency(-1), FloatingGlassTransparency(0))
        XCTAssertEqual(FloatingGlassTransparency(2), FloatingGlassTransparency(1))
    }
}
