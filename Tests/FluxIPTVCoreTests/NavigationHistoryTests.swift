import XCTest
@testable import FluxIPTVCore

final class NavigationHistoryTests: XCTestCase {
    func testBackWalksThroughThePreviousScreensDownToHome() {
        var history = FluxNavigationHistory<FluxDockItem>()
        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(history.previous(from: .live))
        XCTAssertNil(history.leave(.live))

        history.visit(.live)
        history.visit(.movie)
        history.visit(.settings)
        XCTAssertEqual(history.places, [.live, .movie, .settings])
        XCTAssertEqual(history.previous(from: .settings), .movie)
        XCTAssertEqual(history.places, [.live, .movie, .settings])

        XCTAssertEqual(history.leave(.settings), .movie)
        XCTAssertEqual(history.leave(.movie), .live)
        XCTAssertNil(history.leave(.live))
        XCTAssertTrue(history.isEmpty)
    }

    func testAScreenOpenedAgainMovesToTheEndSoBackNeverLoops() {
        var history = FluxNavigationHistory<FluxDockItem>()
        for _ in 0..<50 {
            history.visit(.live)
            history.visit(.movie)
        }
        history.visit(.live)
        XCTAssertEqual(history.places, [.movie, .live])
        history.visit(.live)
        XCTAssertEqual(history.places, [.movie, .live])

        var steps = 0
        var current: FluxDockItem? = .live
        while let screen = current {
            current = history.leave(screen)
            steps += 1
            XCTAssertLessThanOrEqual(steps, FluxDockItem.allCases.count)
        }
        XCTAssertEqual(steps, 2)
    }

    func testLeavingAScreenThatWasNeverRecordedStillReturnsToThePreviousOne() {
        var history = FluxNavigationHistory<FluxDockItem>()
        history.visit(.series)
        XCTAssertEqual(history.previous(from: .favorites), .series)
        XCTAssertEqual(history.leave(.favorites), .series)
        XCTAssertEqual(history.places, [.series])

        history.visit(.settings)
        history.reset()
        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(history.leave(.settings))
    }
}
