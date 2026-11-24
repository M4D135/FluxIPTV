import XCTest
@testable import FluxIPTVCore

final class CasePadRotationTests: XCTestCase {
    func testIncrementalPreciseScrollingFollowsEachDelta() {
        var g = CasePadRotation(yaw: 0, pitch: 0)
        XCTAssertEqual(g.delta(10, 0).yaw, 13.5, accuracy: 0.001)
        XCTAssertEqual(g.delta(20, 0).yaw, 40.5, accuracy: 0.001)
        XCTAssertEqual(g.delta(40, 0).yaw, 94.5, accuracy: 0.001)
        XCTAssertEqual(g.finish().yaw, 180)
        XCTAssertEqual(CaseFaceLayout.face(yaw: g.finish().yaw, pitch: g.finish().pitch), .details)
    }
    func testReverseFromBackAndKeepFullRotation() {
        var g = CasePadRotation(yaw: 180, pitch: 0)
        _ = g.translation(-75, 0)
        XCTAssertEqual(g.finish().yaw, 0)
        var next = CasePadRotation(yaw: 180, pitch: 0)
        _ = next.translation(75, 0)
        XCTAssertEqual(next.finish().yaw, 360)
    }
    func testVerticalTiltDoesNotChangeFaceAndIsBounded() {
        var g = CasePadRotation(yaw: 180, pitch: 0)
        XCTAssertEqual(g.translation(0, 500).pitch, 75)
        XCTAssertEqual(g.finish(), .init(yaw: 180, pitch: 75))
        XCTAssertEqual(g.translation(0, -500).pitch, -75)
    }
    func testTranslationIsAbsoluteNotRepeated() {
        var g = CasePadRotation(yaw: 0, pitch: 0)
        let first = g.translation(50, 30)
        XCTAssertEqual(g.translation(50, 30), first)
        XCTAssertEqual(first.yaw, 67.5, accuracy: 0.001)
        XCTAssertEqual(first.pitch, 18.6, accuracy: 0.001)
    }
    func testSmallAccidentalHorizontalStrokeDoesNotFlip() {
        var g = CasePadRotation(yaw: 0, pitch: 0)
        _ = g.translation(15, 0)
        XCTAssertEqual(g.finish().yaw, 0)
    }
    func testInvalidDeltasDoNotCorruptPose() {
        var g = CasePadRotation(yaw: 180, pitch: 10)
        XCTAssertEqual(g.delta(.infinity, .nan), g.origin)
        XCTAssertEqual(g.translation(.nan, 12), g.origin)
    }
    func testNoInertiaWithReducedMotion() {
        var g = CasePadRotation(yaw: 0, pitch: 0)
        _ = g.translation(45, 0)
        XCTAssertEqual(g.finish(reduceMotion: true).yaw, 180)
    }
}
