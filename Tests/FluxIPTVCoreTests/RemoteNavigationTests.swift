import XCTest
@testable import FluxIPTVCore

final class RemoteNavigationTests: XCTestCase {
    func testDirectionalFocusAndUnequalRows() {
        let rows = [["a", "b"], ["c", "d", "e"], [], ["f"]]
        XCTAssertEqual(RemoteNavigation.move(from: "b", action: .down, rows: rows), "d")
        XCTAssertEqual(RemoteNavigation.move(from: "e", action: .down, rows: rows), "f")
        XCTAssertEqual(RemoteNavigation.move(from: "a", action: .left, rows: rows), "a")
        XCTAssertEqual(RemoteNavigation.move(from: "f", action: .down, rows: rows), "f")
        XCTAssertEqual(RemoteNavigation.move(from: "missing", action: .right, rows: rows), "a")
        XCTAssertNil(RemoteNavigation.move(from: nil, action: .down, rows: []))
    }
    func testAluminiumClickpad() {
        XCTAssertEqual(RemoteNavigation.clickpad(dx: 0, dy: 0, seconds: 0.1), .select)
        XCTAssertEqual(RemoteNavigation.clickpad(dx: 0.2, dy: -0.2, seconds: 1), .options)
        XCTAssertEqual(RemoteNavigation.clickpad(dx: 0, dy: -0.9, seconds: 0.1), .up)
        XCTAssertEqual(RemoteNavigation.clickpad(dx: -0.9, dy: 0, seconds: 0.1), .left)
        XCTAssertEqual(RemoteNavigation.clickpad(dx: 0, dy: 0.9, seconds: 0.1), .down)
        XCTAssertEqual(RemoteNavigation.clickpad(dx: 0.9, dy: 0, seconds: 0.1), .right)
        XCTAssertEqual(RemoteAppearance.allCases.count, 2)
    }
    func testTouchDirectionsAndPresses() {
        XCTAssertEqual(RemoteNavigation.touch(dx: 60, dy: 15, seconds: 0.1), .right)
        XCTAssertEqual(RemoteNavigation.touch(dx: -60, dy: 15, seconds: 0.1), .left)
        XCTAssertEqual(RemoteNavigation.touch(dx: 5, dy: -50, seconds: 0.1), .up)
        XCTAssertEqual(RemoteNavigation.touch(dx: 5, dy: 50, seconds: 0.1), .down)
        XCTAssertEqual(RemoteNavigation.touch(dx: 4, dy: 3, seconds: 0.1), .select)
        XCTAssertEqual(RemoteNavigation.touch(dx: 4, dy: 3, seconds: 0.8), .options)
    }
    func testTrackpadAccumulatesWithoutClickOrRepeat() {
        var pad = RemoteScrollNavigation()
        XCTAssertNil(pad.delta(10, 2))
        XCTAssertNil(pad.delta(13, 1))
        XCTAssertEqual(pad.delta(2, 1), .right)
        XCTAssertNil(pad.delta(80, 0))
        XCTAssertNil(pad.delta(-200, 0))
        pad = RemoteScrollNavigation()
        XCTAssertEqual(pad.delta(-1, -30), .up)
    }
    func testTrackpadShortStrokesNeverSelectAndInvalidInputIgnored() {
        var pad = RemoteScrollNavigation()
        XCTAssertNil(pad.delta(.nan, 100))
        XCTAssertNil(pad.delta(5, 6))
        XCTAssertNil(pad.delta(-5, -6))
        XCTAssertEqual(pad.delta(-30, 2), .left)
        pad = RemoteScrollNavigation()
        XCTAssertEqual(pad.delta(1, 25), .down)
    }
}
