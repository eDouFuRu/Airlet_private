import XCTest
@testable import NotchInteractionCore

final class GlassEdgeLightProfileTests: XCTestCase {
    func testLightFollowsBackdropContrastInsteadOfTime() {
        let brightOutside = GlassEdgeLightPair(outside: 1, inside: 0)
        let darkOutside = GlassEdgeLightPair(outside: 0, inside: 1)
        let profile = GlassEdgeLightProfile(pairs: [brightOutside, darkOutside,
                                                     brightOutside, darkOutside,
                                                     brightOutside, darkOutside,
                                                     brightOutside, darkOutside])
        XCTAssertGreaterThan(profile.levels[0], profile.levels[1])
        XCTAssertEqual(profile.levels[0], profile.levels[2])
        XCTAssertEqual(profile.levels[1], profile.levels[3])
    }

    func testUniformBackdropHasNoInventedDirectionalHighlight() {
        for luminance in [0.0, 0.5, 1.0] {
            let profile = GlassEdgeLightProfile(pairs: Array(
                repeating: .init(outside: luminance, inside: luminance), count: 8))
            XCTAssertTrue(profile.levels.allSatisfy { $0 == profile.levels[0] })
        }
    }

    func testMalformedSamplesUseBoundedNeutralFallback() {
        XCTAssertEqual(GlassEdgeLightProfile(pairs: []), .neutral)
        let malformed = GlassEdgeLightProfile(pairs: Array(
            repeating: .init(outside: .nan, inside: .infinity), count: 8))
        XCTAssertTrue(malformed.levels.allSatisfy { (0...1).contains($0) })
    }
}
