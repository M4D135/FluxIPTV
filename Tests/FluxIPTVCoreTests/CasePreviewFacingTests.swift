import Foundation
import XCTest
@testable import FluxIPTVCore

final class CasePreviewFacingTests: XCTestCase {
    func testRotationAcrossTheEdgeProducesOnePauseAndOneResume() {
        var facing = CasePreviewFacing()
        let samples: [Double] = [-1, -0.03, 0.01, 0.059, 0.061, 0.02, 0.001, -0.001, 0.02, 0.059, 0.07]
        let visible = samples.map { facing.update(backFacing: $0) }
        XCTAssertEqual(visible, [false, false, false, false, true, true, true, false, false, false, true])
        XCTAssertTrue(facing.isBackFacing)
    }

    func testThresholdsAndInvalidSamplesCannotLeaveAnInvisibleTrailerPlaying() {
        var facing = CasePreviewFacing()
        XCTAssertFalse(facing.isBackFacing)
        XCTAssertFalse(facing.update(backFacing: Double(0.06).nextDown))
        XCTAssertTrue(facing.update(backFacing: 0.06))
        XCTAssertTrue(facing.update(backFacing: 0.03))
        XCTAssertFalse(facing.update(backFacing: 0))
        XCTAssertFalse(facing.update(backFacing: 0.03))
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertTrue(facing.update(backFacing: 1))
            XCTAssertFalse(facing.update(backFacing: invalid))
            XCTAssertFalse(facing.update(backFacing: 0.03))
        }
    }

    func testNormalsFromEitherRotationAxisAndMultipleTurnsSelectThePhysicalFace() {
        // Independent rotation fixtures with a centered camera: the local
        // back normal starts at -Z. Double flips show the front again.
        let poses: [(yaw: Double, pitch: Double, back: Bool)] = [
            (0, 0, false), (180, 0, true), (-180, 0, true),
            (0, 180, true), (0, -180, true), (180, 180, false),
            (180, 75, true), (180, -75, true), (0, 75, false),
            (540, 720, true), (-540, -720, true),
            (1_080, -720, false), (-720, 540, true),
            (540, -540, false)
        ]
        for pose in poses {
            let dot = -cos(pose.yaw * .pi / 180) * cos(pose.pitch * .pi / 180)
            var facing = CasePreviewFacing()
            XCTAssertEqual(facing.update(backFacing: dot), pose.back,
                           "yaw=\(pose.yaw), pitch=\(pose.pitch)")
        }
    }

    func testIntermediateRenderedSamplesRemainPausedUntilTheBackIsVisible() {
        var facing = CasePreviewFacing()
        // The eventual pose is a full turn to the back, but these are the
        // intermediate normals supplied by the renderer during that motion.
        let renderedSamples: [Double] = [-1, -0.7, -0.2, 0, 0.02, 0.05, 0.2, 0.7, 1]
        XCTAssertEqual(renderedSamples.map { facing.update(backFacing: $0) },
                       [false, false, false, false, false, false, true, true, true])
    }
}
