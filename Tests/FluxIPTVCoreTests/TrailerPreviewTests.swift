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

    func testYouTubeFormatsResolveToOneEmbeddedVideoInsteadOfAnExternalPage() throws {
        let expected = try XCTUnwrap(YouTubeTrailer(videoID: "M7lc1UVf-VE"))
        for address in [
            "https://www.youtube.com/watch?v=M7lc1UVf-VE&feature=shared",
            "https://m.youtube.com/watch?feature=share&v=M7lc1UVf-VE",
            "https://music.youtube.com/watch?v=M7lc1UVf-VE",
            "https://youtu.be/M7lc1UVf-VE?si=share-token&t=30",
            "https://www.youtu.be/M7lc1UVf-VE",
            "https://youtube.com/embed/M7lc1UVf-VE?autoplay=1",
            "https://www.youtube-nocookie.com/embed/M7lc1UVf-VE",
            "https://youtube-nocookie.com/embed/M7lc1UVf-VE/",
            "https://www.youtube.com/shorts/M7lc1UVf-VE",
            "https://youtube.com/live/M7lc1UVf-VE?feature=share",
            "http://WWW.YOUTUBE.COM:80/v/M7lc1UVf-VE#fragment"
        ] {
            XCTAssertEqual(TrailerPreviewRoute.resolve(URL(string: address)), .youtube(expected), address)
        }
        XCTAssertEqual(expected.watchURL.absoluteString, "https://www.youtube.com/watch?v=M7lc1UVf-VE")
        XCTAssertEqual(expected.thumbnailURL.absoluteString, "https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg")
    }

    func testYouTubeIdentifiersAreStrictASCIIAndHostNamesCannotImpersonateYouTube() {
        for identifier in ["", "0", "M7lc1UVf-V", "M7lc1UVf-VEE", "M7lc1UVf/VE", "M7lc1UVf Vé", "Ｍ7lc1UVf-VE", "M7lc1UVf-VE\n"] {
            XCTAssertNil(YouTubeTrailer(videoID: identifier), identifier)
        }
        XCTAssertNotNil(YouTubeTrailer(videoID: "aB0_-123456"))
        for address in [
            "https://youtube.com.attacker.test/watch?v=M7lc1UVf-VE",
            "https://notyoutube.com/watch?v=M7lc1UVf-VE",
            "https://youtu.be.attacker.test/M7lc1UVf-VE",
            "https://unrecognized.youtube.com/watch?v=M7lc1UVf-VE",
            "https://www.youtube.com:8443/watch?v=M7lc1UVf-VE",
            "https://www.youtube-nocookie.com/watch?v=M7lc1UVf-VE",
            "https://youtu.be/embed/M7lc1UVf-VE",
            "https://www.youtube.com/watch?v=M7lc1UVf-VE&v=abcdefghijk",
            "https://www.youtube.com/embed/M7lc1UVf-VE/extra"
        ] {
            let url = URL(string: address)!
            XCTAssertNil(YouTubeTrailer(url: url), address)
            XCTAssertEqual(TrailerPreviewRoute.resolve(url), .external(url), address)
        }
    }

    func testUnsupportedWebPagesStayExternalWithoutHandingHTMLToPlayer() {
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
        for address in ["file:///tmp/trailer.mp4", "javascript:alert(1)", "ftp://example.test/trailer.mp4", "/relative.mp4", "https://user:password@www.youtube.com/watch?v=M7lc1UVf-VE", "https://youtube.com@attacker.test/trailer.mp4"] {
            XCTAssertEqual(TrailerPreviewRoute.resolve(URL(string: address)), .unavailable)
        }
    }
}
