import Foundation
import XCTest
@testable import YouTubeKit

final class PublicYouTubePolicyTests: XCTestCase {
    private let id = "TcMBFSGVi1c"

    private func player(status: String = "OK", embed: Bool = true, videoID: String? = nil,
                        streaming: [String: Any]? = nil, live: Bool = false) throws -> Data {
        var object: [String: Any] = [
            "playabilityStatus": ["status": status, "playableInEmbed": embed],
            "videoDetails": ["videoId": videoID ?? id, "isLiveContent": live, "thumbnail": ["thumbnails": []]]
        ]
        object["streamingData"] = streaming
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func format(itag: Int = 18, mime: String = "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
                        url: String = "https://r1.googlevideo.com/videoplayback", drm: [String] = []) -> [String: Any] {
        ["itag": itag, "mimeType": mime, "url": url, "drmFamilies": drm]
    }

    func testPublicResponseIsAccepted() throws {
        try PublicYouTubePolicy.validatePlayerResponse(player(), videoID: id)
    }

    func testEveryNonPublicStatusIsRejected() throws {
        for status in ["LOGIN_REQUIRED", "UNPLAYABLE", "CONTENT_CHECK_REQUIRED", "AGE_CHECK_REQUIRED", "ERROR", "UNKNOWN", ""] {
            XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(status: status), videoID: id), status)
        }
        XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(Data("{}".utf8), videoID: id))
    }

    func testExplicitRestrictionsAreRejectedEvenWhenStatusSaysOK() throws {
        XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(embed: false), videoID: id))
        XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(), videoID: id, ageRestricted: true))
        XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(live: true), videoID: id))
    }

    func testResponseCannotSwitchVideo() throws {
        XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(videoID: "M7lc1UVf-VE"), videoID: id))
    }

    func testProtectedFormatsAndLicensesAreRejected() throws {
        for streaming in [
            ["formats": [format(drm: ["WIDEVINE"])]] as [String: Any],
            ["adaptiveFormats": [format(drm: ["FAIRPLAY"])]] as [String: Any],
            ["licenseInfos": [["drmFamily": "WIDEVINE"]]] as [String: Any]
        ] {
            XCTAssertThrowsError(try PublicYouTubePolicy.validatePlayerResponse(player(streaming: streaming), videoID: id))
        }
    }

    func testStrictIdentifierAndMediaHostValidation() {
        XCTAssertTrue(PublicYouTubePolicy.isVideoID(id))
        for invalid in ["", "short", id + "?", "TcMBFSGVi1é", "TcMBFSGVi/1"] { XCTAssertFalse(PublicYouTubePolicy.isVideoID(invalid)) }
        for valid in ["https://r1---sn-test.googlevideo.com/videoplayback?expire=1", "https://manifest.googlevideo.com/api/manifest/hls_playlist/index.m3u8"] {
            XCTAssertTrue(PublicYouTubePolicy.isMediaURL(URL(string: valid)!))
        }
        for invalid in ["http://r1.googlevideo.com/video", "https://googlevideo.com.evil.test/video", "https://evilgooglevideo.com/video",
                        "https://name:pass@r1.googlevideo.com/video", "https://r1.googlevideo.com:444/video", "file:///video.mp4",
                        "https://www.youtube.com/watch?v=TcMBFSGVi1c", "https://127.0.0.1/video", "https://r1.googlevideo.com/video#fragment"] {
            XCTAssertFalse(PublicYouTubePolicy.isMediaURL(URL(string: invalid)!), invalid)
        }
        XCTAssertFalse(PublicYouTubePolicy.isRequestURL(URL(string: "https://youtube.com.evil.test/watch")!))
        XCTAssertFalse(PublicYouTubePolicy.isRequestURL(URL(string: "https://accounts.google.com/signin")!))
    }

    func testNativeSelectionRequiresClearMuxedSupportedCodecs() throws {
        let formats = [
            format(),
            format(itag: 137, mime: "video/mp4; codecs=\"avc1.640028\""),
            format(itag: 140, mime: "audio/mp4; codecs=\"mp4a.40.2\""),
            format(mime: "video/mp4; codecs=\"vp09.00.10.08, opus\""),
            format(url: "https://outside.example/video.mp4"),
            format(drm: ["WIDEVINE"])
        ]
        let data = try JSONSerialization.data(withJSONObject: formats)
        let decoded = try JSONDecoder().decode([InnerTube.StreamingData.Format].self, from: data)
        let selected = PublicYouTubePolicy.supportedProgressive(decoded)
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0].includesVideoAndAudioTrack)
        XCTAssertEqual(selected[0].itag.itag, 18)
    }

    func testWatchPagePolicyUsesParsedPublicResponse() throws {
        let publicJSON = String(decoding: try player(), as: UTF8.self)
        let restrictedJSON = String(decoding: try player(status: "LOGIN_REQUIRED"), as: UTF8.self)
        for assignment in ["var ytInitialPlayerResponse = ", "window['ytInitialPlayerResponse'] = "] {
            let info = try Extraction.getVideoInfo(fromHTML: assignment + publicJSON + ";")
            try PublicYouTubePolicy.requirePublic(info, videoID: id)
            let restricted = try Extraction.getVideoInfo(fromHTML: assignment + restrictedJSON + ";")
            XCTAssertThrowsError(try PublicYouTubePolicy.requirePublic(restricted, videoID: id))
        }
        XCTAssertTrue(Extraction.isAgeRestricted(watchHTML: "<meta property='og:restrictions:age' content='18+'>"))
    }
}
