import XCTest
@testable import FluxIPTVCore

final class M3UParserTests: XCTestCase {
    private let id = UUID(uuidString: "D436229E-3C1A-49E9-B50B-84A67859DF35")!

    func testParsesCategoriesNamesAndLogos() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="demo.one" tvg-name="Info, Monde" tvg-logo="https://cdn.example.org/logo.png" group-title="Actualités",Info HD
        https://video.example.org/live/one.m3u8
        #EXTINF:-1 group-title="Sport",Sport TV
        https://video.example.org/live/two.ts
        """
        let items = M3UParser().parse(text, sourceID: id)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "Info, Monde")
        XCTAssertEqual(items[0].group, "Actualités")
        XCTAssertEqual(items[0].logoURL?.host, "cdn.example.org")
        XCTAssertEqual(items[1].name, "Sport TV")
        XCTAssertEqual(items[1].directURL?.pathExtension, "ts")
    }

    func testHandlesBOMEXTGRPAndDuplicates() {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTGRP:Documentaires\r\n#EXTINF:-1,Docu\r\nhttps://media.example.org/a.m3u8\r\nhttps://media.example.org/a.m3u8"
        let items = M3UParser().parse(text, sourceID: id)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].group, "Documentaires")
    }

    func testRejectsNonHTTPAndInvalidSources() {
        let input = "#EXTINF:-1,Test\nfile:///tmp/secret\nrtsp://localhost/stream\nhttps://example.org/ok.m3u8"
        let items = M3UParser().parse(input, sourceID: id)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "ok.m3u8")
    }

    func testURLValidationAndStableIdentifier() throws {
        XCTAssertThrowsError(try IPTVURL.validated("javascript:alert(1)"))
        XCTAssertThrowsError(try IPTVURL.validated("https://user:password@host.example/test"))
        XCTAssertEqual(StableID.hash("abc"), StableID.hash("abc"))
        XCTAssertNotEqual(StableID.hash("abc"), StableID.hash("abd"))
    }
}
