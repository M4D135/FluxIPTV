import XCTest
@testable import FluxIPTVCore

final class XtreamClientTests: XCTestCase {
    private let id = UUID(uuidString: "D436229E-3C1A-49E9-B50B-84A67859DF35")!

    func testCategoryAndMovieDecoding() throws {
        let live = [["name": "France Info", "stream_id": 98, "category_id": "7", "stream_icon": "https://example.org/logo.png"]] as [[String: Any]]
        let cats = [["category_id": 7, "category_name": "Informations"]] as [[String: Any]]
        let result = XtreamClient.decodeItems(live, categories: cats, sourceID: id, kind: .live)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].group, "Informations")
        XCTAssertEqual(result[0].xtreamStreamID, "98")
        XCTAssertEqual(result[0].kind, .live)

        let movies = XtreamClient.decodeItems(
            [["name": "Film test", "stream_id": "55", "container_extension": "mkv"]],
            categories: [], sourceID: id, kind: .movie)
        XCTAssertEqual(movies[0].fileExtension, "mkv")
    }

    func testBuildsEncodedPlaybackURL() throws {
        let item = IPTVItem(id: "1", sourceID: id, name: "Canal", group: "Test", logoURL: nil,
                            kind: .live, directURL: nil, xtreamStreamID: "45", fileExtension: nil)
        let server = try XCTUnwrap(URL(string: "https://example.org:8080/sub/"))
        let url = try XCTUnwrap(XtreamClient.streamURL(
            server: server, username: "user name", password: "p/ss", item: item))
        XCTAssertEqual(url.absoluteString, "https://example.org:8080/sub/live/user%20name/p%2Fss/45.m3u8")
    }
    func testSeriesCatalogSeasonsAndPlayback() throws {
        let series = try XCTUnwrap(XtreamClient.decodeItems(
            [["name": "Exemple", "series_id": 99, "category_id": 12]],
            categories: [["category_id": 12, "category_name": "Séries"]], sourceID: id, kind: .series).first)
        XCTAssertTrue(series.isSeriesCollection)
        let server = try XCTUnwrap(URL(string: "https://example.org/sub"))
        XCTAssertNil(XtreamClient.streamURL(server: server, username: "u", password: "p", item: series))
        let episodes: [String: Any] = ["episodes": [
            "2": [["id": "8", "episode_num": 2, "title": "Suite", "container_extension": "mp4"]],
            "1": [["id": "5", "episode_num": 3], ["id": 4, "episode_num": "1", "container_extension": "mkv"]]
        ]]
        let seasons = XtreamClient.decodeSeasons(episodes, series: series)
        XCTAssertEqual(seasons.map(\.number), [1, 2])
        XCTAssertEqual(seasons[0].episodes.map(\.xtreamStreamID), ["4", "5"])
        let episode = seasons[0].episodes[0]
        XCTAssertFalse(episode.isSeriesCollection)
        XCTAssertEqual(XtreamClient.streamURL(server: server, username: "u", password: "p", item: episode)?.absoluteString,
                       "https://example.org/sub/series/u/p/4.mkv")
    }

    func testTrailerMetadataNormalizesYouTubeAndTriesTheNextUsableField() {
        let expected = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
        for firstField in ["", "  ", "0", "null", "not a link", "https://youtube.com/watch?v=123", "https://youtube.com/results?search_query=film"] {
            let details = XtreamClient.details(["trailer_url": firstField, "youtube_trailer": "  M7lc1UVf-VE\n"])
            XCTAssertEqual(details.trailerURL?.absoluteString, expected, firstField)
        }
        XCTAssertEqual(XtreamClient.details(["trailer_url": 0, "youtube_trailer": "M7lc1UVf-VE"]).trailerURL?.absoluteString, expected)
        XCTAssertEqual(XtreamClient.details(["trailer_url": NSNull(), "youtube_trailer": "M7lc1UVf-VE"]).trailerURL?.absoluteString, expected)
        XCTAssertEqual(XtreamClient.details(["youtube_trailer": "https://youtu.be/M7lc1UVf-VE?si=shared"]).trailerURL?.absoluteString, expected)
        XCTAssertEqual(XtreamClient.details(["youtube_trailer": "bad identifier", "trailer": "M7lc1UVf-VE"]).trailerURL?.absoluteString, expected)
    }

    func testPlayableTrailerHasPriorityOverExternalFallbackWithoutLosingDirectStream() {
        let native = "https://cdn.example.test/trailer.mp4?token=example"
        let external = "https://example.test/film/trailer"
        XCTAssertEqual(XtreamClient.details(["trailer_url": native, "youtube_trailer": "M7lc1UVf-VE"]).trailerURL?.absoluteString, native)
        XCTAssertEqual(XtreamClient.details(["trailer_url": external, "youtube_trailer": "M7lc1UVf-VE"]).trailerURL?.absoluteString, "https://www.youtube.com/watch?v=M7lc1UVf-VE")
        XCTAssertEqual(XtreamClient.details(["trailer_url": external, "trailer": native]).trailerURL?.absoluteString, native)
        XCTAssertEqual(XtreamClient.details(["trailer_url": external]).trailerURL?.absoluteString, external)
    }

    func testMissingMalformedOrUnsafeTrailerMetadataDoesNotInventAVideo() {
        XCTAssertNil(XtreamClient.details([:]).trailerURL)
        for value in ["", "0", "null", "123", "not a link", "file:///tmp/trailer.mp4", "javascript:alert(1)", "https://youtube.com/watch?v=123", "https://youtube.com/watch?v=M7lc1UVf-VE&v=abcdefghijk", "https://user:password@youtube.com/watch?v=M7lc1UVf-VE"] {
            XCTAssertNil(XtreamClient.details(["youtube_trailer": value]).trailerURL, value)
        }
    }
}
