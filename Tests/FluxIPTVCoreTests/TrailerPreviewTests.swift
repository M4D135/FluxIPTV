import XCTest
@testable import FluxIPTVCore

final class TrailerPreviewTests: XCTestCase {
    func testOnlyTheRequestedDelaysAreAvailableAndPersistable() throws {
        XCTAssertEqual(TrailerPreviewDelay.allCases.map(\.rawValue), [3, 5, 10])
        XCTAssertNil(TrailerPreviewDelay(rawValue: 0))
        XCTAssertNil(TrailerPreviewDelay(rawValue: 7))
        for delay in TrailerPreviewDelay.allCases {
            XCTAssertEqual(try JSONDecoder().decode(TrailerPreviewDelay.self, from: JSONEncoder().encode(delay)), delay)
        }
        XCTAssertNotEqual(TrailerPreviewDelay.storageKey, TrailerPreviewDelay.automaticKey)
    }

    func testDirectNativeTrailersIncludingQueryStringsAndUppercaseExtensions() {
        for path in ["preview.mp4", "preview.MOV?token=x", "preview.m4v", "master.m3u8?session=x"] {
            let url = URL(string: "https://cdn.example.test/" + path)!
            XCTAssertEqual(TrailerPreviewRoute.resolve(url), .native(url))
        }
    }

    func testWebPagesStayExternalWithoutScrapingOrHandingHTMLToPlayer() {
        for address in [
            "https://www.youtube.com/watch?v=123",
            "https://youtu.be/123",
            "https://www.youtube-nocookie.com/embed/123",
            "https://player.vimeo.com/video/123",
            "https://www.dailymotion.com/video/123",
            "https://example.test/trailer/123",
            "https://youtube.com/preview.mp4"
        ] {
            let url = URL(string: address)!
            XCTAssertEqual(TrailerPreviewRoute.resolve(url), .external(url))
        }
    }

    func testMissingAndNonWebTrailerURLsAreUnavailable() {
        XCTAssertEqual(TrailerPreviewRoute.resolve(nil), .unavailable)
        for address in ["file:///tmp/trailer.mp4", "javascript:alert(1)", "ftp://example.test/trailer.mp4", "/relative.mp4"] {
            XCTAssertEqual(TrailerPreviewRoute.resolve(URL(string: address)), .unavailable)
        }
    }
}
