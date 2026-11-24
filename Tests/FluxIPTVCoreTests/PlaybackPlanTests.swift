import XCTest
@testable import FluxIPTVCore

final class PlaybackPlanTests: XCTestCase {
    private func url(_ path: String) -> URL { URL(string: "https://example.invalid/\(path)")! }
    func testHLSAndMKVUseDifferentPreferredEngines() {
        XCTAssertEqual(PlaybackPlan.attempts(urls: [url("live.m3u8")]).map(\.engine), [.native, .vlc])
        XCTAssertEqual(PlaybackPlan.attempts(urls: [url("episode.mkv")]).map(\.engine), [.vlc, .native])
        XCTAssertEqual(PlaybackPlan.attempts(urls: [url("movie.mp4")], preferred: .vlc).map(\.engine), [.vlc])
    }
    func testDeduplicationAndNoUnsupportedURLs() {
        let stream = url("episode.mkv")
        XCTAssertEqual(PlaybackPlan.attempts(urls: [stream, stream, URL(fileURLWithPath: "/tmp/movie.mkv")]).count, 2)
    }
    func testXtreamEpisodeFallbackAndDirectSource() {
        let direct = url("provider/episode.mkv")
        let episode = IPTVItem(id: "e", sourceID: UUID(), name: "Episode", group: "S1", logoURL: nil, kind: .series, directURL: direct, xtreamStreamID: "456", fileExtension: nil)
        let urls = PlaybackPlan.urls(server: url(""), username: "u", password: "p", item: episode, liveExtension: "m3u8")
        XCTAssertEqual(urls.map(\.path), ["/series/u/p/456.mp4", "/provider/episode.mkv", "/series/u/p/456.mkv"])
    }
}
