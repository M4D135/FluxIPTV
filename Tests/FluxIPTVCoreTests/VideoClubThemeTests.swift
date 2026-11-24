import XCTest
@testable import FluxIPTVCore

final class VideoClubThemeTests:XCTestCase {
    func testSixThemeRecipesAndThreeDifferentWorlds() {
        XCTAssertEqual(VideoClubTheme.allCases.count,6)
        for theme in VideoClubTheme.allCases {
            let cinema=theme.room(kind:.movie),club=theme.room(kind:.series),tv=theme.room(kind:.live)
            XCTAssertNotEqual(cinema,club);XCTAssertNotEqual(club,tv);XCTAssertNotEqual(cinema,tv)
            XCTAssertEqual(cinema,theme.room(kind:.movie))
            XCTAssertEqual(club,theme.room(kind:.series))
            for mesh in [cinema,club,tv] {
                XCTAssertFalse(mesh.isEmpty);XCTAssertLessThan(mesh.count,3000)
                XCTAssertTrue(mesh.allSatisfy{$0.normal.finite && $0.normal.length>0.99 && $0.color.finite})
                XCTAssertFalse(ProceduralCinema.project(mesh,width:960,height:540).isEmpty)
            }
        }
        for (index,theme) in VideoClubTheme.allCases.enumerated() {
            for other in VideoClubTheme.allCases.dropFirst(index+1) {
                XCTAssertNotEqual(theme.room(kind:.movie),other.room(kind:.movie))
                XCTAssertNotEqual(theme.room(kind:.live),other.room(kind:.live))
            }
        }
    }
    func testProviderMetadataAndTrailerWithoutGuessing() {
        let metadata=XtreamClient.details(["plot":"Résumé", "director":"Réalisatrice", "cast":"Interprète", "youtube_trailer":"dQw4w9WgXcQ"])
        XCTAssertEqual(metadata.synopsis,"Résumé")
        XCTAssertEqual(metadata.director,"Réalisatrice")
        XCTAssertEqual(metadata.trailerURL?.host,"www.youtube.com")
        XCTAssertNil(XtreamClient.details(["trailer":"file:///tmp/secret"]).trailerURL)
        XCTAssertNil(XtreamClient.details(["trailer":"not a link"]).trailerURL)
        let fallback=IPTVDetails(genre:"Drame",director:"Autre")
        XCTAssertEqual(metadata.fillingMissing(from:fallback).director,"Réalisatrice")
        XCTAssertEqual(metadata.fillingMissing(from:fallback).genre,"Drame")
    }
}
