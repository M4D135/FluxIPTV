import XCTest
@testable import FluxIPTVCore

final class SessionCredentialCacheTests: XCTestCase {
    func testRepeatedPlaybackUsesOneReadPerSource() throws {
        var cache = SessionCredentialCache<String>()
        let source = UUID(), other = UUID()
        var reads = 0
        for _ in 0..<100 {
            XCTAssertEqual(cache.load(for: source) { reads += 1; return "first" }, "first")
            XCTAssertEqual(cache.cached(for: source), "first")
        }
        XCTAssertEqual(reads, 1)
        XCTAssertNil(cache.cached(for: other))
        XCTAssertEqual(cache.load(for: other) { reads += 1; return "second" }, "second")
        XCTAssertEqual(reads, 2)
    }

    func testReplaceAndRemove() {
        var cache = SessionCredentialCache<String>()
        let source = UUID(), other = UUID()
        cache.store("old", for: source)
        cache.store("keep", for: other)
        cache.store("new", for: source)
        XCTAssertEqual(cache.load(for: source) { XCTFail("Unexpected read"); return "wrong" }, "new")
        cache.remove(for: source)
        XCTAssertNil(cache.cached(for: source))
        XCTAssertEqual(cache.cached(for: other), "keep")
    }

    func testDeniedReadIsNotCached() {
        enum Denied: Error { case access }
        var cache = SessionCredentialCache<String>()
        let source = UUID()
        XCTAssertThrowsError(try cache.load(for: source) { throw Denied.access })
        XCTAssertNil(cache.cached(for: source))
        XCTAssertEqual(cache.load(for: source) { "authorized" }, "authorized")
    }
}
