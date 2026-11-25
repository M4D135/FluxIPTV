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

    func testExternalVariantsUseTheSameValidatedCandidatesAsNativePlayback() {
        let primary = url("episode.mp4"), direct = url("direct.mkv"), fallback = url("fallback.mkv")
        let supplied = [URL(fileURLWithPath: "/tmp/movie.mkv"), primary, primary,
                        URL(string: "https://user:password@example.invalid/movie.mp4")!,
                        direct, fallback, url("unused.mov")]
        let candidates = PlaybackPlan.candidateURLs(supplied)
        let variants = PlaybackPlan.variants(urls: supplied)
        XCTAssertEqual(candidates, [primary, direct, fallback])
        XCTAssertEqual(PlaybackPlan.attempts(urls: supplied, preferred: .native).map(\.url), candidates)
        XCTAssertEqual(variants.map(\.id), [0, 1, 2])
        XCTAssertEqual(variants.map(\.title), ["Adresse 1 · MP4", "Adresse 2 · MKV", "Adresse 3 · MKV"])
        XCTAssertEqual(candidates[variants[1].id], direct)
    }

    func testVariantLabelsNeverExposeArbitraryURLComponents() {
        let sensitive = URL(string: "https://private-token.example/username/password/video.secret?token=private-token")!
        XCTAssertEqual(PlaybackPlan.variantTitle(url: sensitive, index: 0), "Adresse 1 · format non indiqué")
        let known = URL(string: "https://private-token.example/username/password/video.MKV?token=private-token")!
        XCTAssertEqual(PlaybackPlan.variantTitle(url: known, index: 1), "Adresse 2 · MKV")
        XCTAssertEqual(PlaybackPlan.variantTitle(url: url("live.m3u8"), index: 2), "Adresse 3 · HLS")
    }
}
