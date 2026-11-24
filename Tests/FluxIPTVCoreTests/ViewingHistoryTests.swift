import XCTest
@testable import FluxIPTVCore
final class ViewingHistoryTests: XCTestCase {
    func testResumeAndCompletion() {
        var h = ViewingHistory()
        h.record(id: "a", seconds: 120, duration: 600)
        XCTAssertEqual(h.resumeSeconds(for: "a"), 120)
        h.record(id: "a", seconds: 590, duration: 600)
        XCTAssertNil(h.resumeSeconds(for: "a"))
    }
    func testInvalidAndPersistence() throws {
        var h = ViewingHistory()
        h.record(id: "a", seconds: .nan, duration: 600)
        XCTAssertTrue(h.entries.isEmpty)
        h.record(id: "a", seconds: 50, duration: 200)
        let copy = try JSONDecoder().decode(ViewingHistory.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(copy.resumeSeconds(for: "a"), 50)
        h.clear(); XCTAssertTrue(h.entries.isEmpty)
    }
}
