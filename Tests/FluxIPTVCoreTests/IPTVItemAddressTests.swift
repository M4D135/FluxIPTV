import XCTest
@testable import FluxIPTVCore

/// A title keeps its addresses as their text and gives back the URLs it was
/// made with.
final class IPTVItemAddressTests: XCTestCase {
    private func item(_ url: URL?) -> IPTVItem {
        IPTVItem(id: "a", sourceID: UUID(uuidString: "3C9E1F2A-7B4D-4E8A-9F10-2D3C4B5A6E7F")!, name: "A", group: "G",
                 logoURL: url, kind: .series, directURL: url, xtreamStreamID: nil, fileExtension: nil,
                 isSeriesCollection: true, backdropURL: url)
    }

    func testTheAddressesComeBackAsTheURLsGiven() throws {
        let texts = ["http://h.example/a.png", "https://h.example:8443/a/b?c=d&e=%20f", "http://[::1]:80/x.ts",
                     "http://h.example/a%20b.png", "http://h.example/a b.png", "http://h.example/été.jpg",
                     "HTTP://H.EXAMPLE/X.PNG", "http://h.example/x#frag", "http://h.example/?", "http://h.example",
                     "https://h.example/live/user/p%40ss/1.m3u8", "http://h.example/a/./b/../c.png"]
        var urls = try texts.map { try XCTUnwrap(URL(string: $0), $0) }
        urls.append(URL(fileURLWithPath: "/tmp/Flux Fixture/poster été.png"))
        urls.append(URL(fileURLWithPath: "/tmp/Flux Fixture/", isDirectory: true))
        for url in urls {
            let item = item(url)
            XCTAssertEqual(item.logoURL, url, url.absoluteString)
            XCTAssertEqual(item.backdropURL, url, url.absoluteString)
            XCTAssertEqual(item.directURL, url, url.absoluteString)
            XCTAssertEqual(item.logoURL?.isFileURL, url.isFileURL, url.absoluteString)
            // Titles made with equal URLs are equal, and hash alike.
            let again = self.item(URL(string: url.absoluteString))
            XCTAssertEqual(again, item, url.absoluteString)
            XCTAssertEqual(again.hashValue, item.hashValue, url.absoluteString)
        }
        XCTAssertNil(item(nil).logoURL)
        XCTAssertNil(item(nil).directURL)
        XCTAssertNotEqual(item(urls[0]), item(urls[1]))
        // A relative URL comes back absolute, to the same place.
        let relative = try XCTUnwrap(URL(string: "poster.png", relativeTo: URL(string: "http://h.example/images/")))
        XCTAssertEqual(item(relative).logoURL, relative.absoluteURL)
    }
}
