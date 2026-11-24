import XCTest
@testable import FluxIPTVCore
final class CinemaLinksTests: XCTestCase {
    func testCleanProviderTitles() {
        XCTAssertEqual(CinemaLinks.title("FR - Breaking Bad - S01E01"),"Breaking Bad")
        XCTAssertEqual(CinemaLinks.title("[VF] [4K] Le Fabuleux Destin d’Amélie Poulain [UHD]"),"Le Fabuleux Destin d’Amélie Poulain")
        XCTAssertEqual(CinemaLinks.title("It"),"It")
        XCTAssertEqual(CinemaLinks.title("2012"),"2012")
    }
    func testAllocineUsesIndexedFichesAndEncodedTitle() throws {
        let url=try XCTUnwrap(CinemaLinks.url(for:.allocine,name:"FR - L'été & l'hiver",year:"2024",series:false))
        let c=try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false))
        XCTAssertEqual(c.host,"www.google.com")
        XCTAssertEqual(c.queryItems?.first(where:{$0.name=="q"})?.value,"site:allocine.fr/film/ L'été & l'hiver 2024")
        let series=try XCTUnwrap(CinemaLinks.url(for:.allocine,name:"FR - Breaking Bad - S01E01",year:"2008",series:true))
        XCTAssertEqual(URLComponents(url:series,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"site:allocine.fr/series/ Breaking Bad 2008")
    }
    func testWikipediaQuery() throws {
        let url=try XCTUnwrap(CinemaLinks.url(for:.wikipedia,name:"FR - Le Bureau des légendes",year:nil,series:true))
        XCTAssertEqual(URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"Le Bureau des légendes")
    }
}
