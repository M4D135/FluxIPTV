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

    /// As in a web browser, a screen opened twice is two steps: Back retraces
    /// the path that was taken, not a shortened one.
    func testBackRetracesAScreenThatWasOpenedTwice() {
        var history = FluxNavigationHistory<FluxDockItem>()
        history.visit(.live)
        history.visit(.movie)
        history.visit(.live)
        XCTAssertEqual(history.places, [.live, .movie, .live])
        XCTAssertEqual(history.previous(from: .live), .movie)

        XCTAssertEqual(history.leave(.live), .movie)
        // Showing the screen Back returned to is not a new step.
        history.visit(.movie)
        XCTAssertEqual(history.places, [.live, .movie])
        XCTAssertEqual(history.leave(.movie), .live)
        history.visit(.live)
        XCTAssertNil(history.leave(.live))
        XCTAssertTrue(history.isEmpty)
    }

    func testShowingTheScreenOnTopAgainAddsNoStep() {
        var history = FluxNavigationHistory<FluxDockItem>()
        history.visit(.series)
        history.visit(.series)
        history.visit(.series)
        XCTAssertEqual(history.places, [.series])
        XCTAssertNil(history.leave(.series))
    }

    func testALongPendulumForgetsItsOldestStepsAndStillEndsAtHome() {
        var history = FluxNavigationHistory<FluxDockItem>()
        for _ in 0..<200 {
            history.visit(.live)
            history.visit(.movie)
        }
        XCTAssertEqual(history.places.count, FluxNavigationHistory<FluxDockItem>.capacity)
        XCTAssertEqual(history.places.last, .movie)

        var steps = 0
        var current: FluxDockItem? = .movie
        while let screen = current {
            current = history.leave(screen)
            steps += 1
            XCTAssertLessThanOrEqual(steps, FluxNavigationHistory<FluxDockItem>.capacity)
        }
        XCTAssertEqual(steps, FluxNavigationHistory<FluxDockItem>.capacity)
        XCTAssertTrue(history.isEmpty)
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
