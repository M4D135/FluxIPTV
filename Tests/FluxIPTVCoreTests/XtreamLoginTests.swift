import XCTest
@testable import FluxIPTVCore

final class XtreamLoginTests: XCTestCase {
    func testHostPortAndDefaultHTTPS() throws {
        let login = try XtreamLogin(server: "  example.org:8080/proxy/  ", username: " user ", password: " p@ss + ")
        XCTAssertEqual(login.server.absoluteString, "https://example.org:8080/proxy")
        XCTAssertEqual(login.username, "user")
        XCTAssertEqual(login.password, " p@ss + ")
    }

    func testExtractLinkAndStripCredentials() throws {
        let login = try XtreamLogin(server: "http://example.org:8000/sub/get.php?username=user%2B1&password=a%26b%2F%23%3F&output=m3u8#fragment")
        XCTAssertEqual(login.server.absoluteString, "http://example.org:8000/sub")
        XCTAssertEqual(login.username, "user+1")
        XCTAssertEqual(login.password, "a&b/#?")
        XCTAssertNil(login.server.query)
        XCTAssertNil(login.server.fragment)
    }

    func testExplicitCredentialsAndEndpointVariants() throws {
        let login = try XtreamLogin(server: "https://example.org/player_api.php?username=old&password=old", username: "new", password: "fresh")
        XCTAssertEqual(login.server.absoluteString, "https://example.org")
        XCTAssertEqual(login.username, "new")
        XCTAssertEqual(login.password, "fresh")
        let xml = try XtreamLogin(server: "https://example.org/x%20y/xmltv.php?username=u&password=p")
        XCTAssertEqual(xml.server.absoluteString, "https://example.org/x%20y")
    }

    func testRejectIncompleteAndUnsafeInputs() {
        for server in ["", "file:///tmp/test", "https://user:pass@example.org", "https://example.org /broken", "https://"] {
            XCTAssertThrowsError(try XtreamLogin(server: server, username: "user", password: "pass"))
        }
        XCTAssertThrowsError(try XtreamLogin(server: "https://example.org", username: "user"))
        XCTAssertThrowsError(try XtreamLogin(server: "https://example.org/get.php?username=u"))
    }
}
