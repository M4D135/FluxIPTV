import XCTest
@testable import FluxIPTVCore

final class ClubInterfaceProfileTests: XCTestCase {
    func testConceptsAreDistinctAndPersistent() throws {
        XCTAssertEqual(Set(ClubInterfaceProfile.allCases.map(\.id)).count,2)
        for profile in ClubInterfaceProfile.allCases {
            XCTAssertEqual(try JSONDecoder().decode(ClubInterfaceProfile.self,from:JSONEncoder().encode(profile)),profile)
        }
        XCTAssertNotEqual(ClubInterfaceProfile.neoVideoClub.arrangement,ClubInterfaceProfile.appleCinema.arrangement)
        XCTAssertFalse(ClubInterfaceProfile.neoVideoClub.isEditorial)
        XCTAssertTrue(ClubInterfaceProfile.appleCinema.isEditorial)
    }
    func testNeighborsNeverWrapOrScan() {
        let first=ClubInterfaceProfile.neighbors(index:0,count:60_000)
        XCTAssertNil(first.previous);XCTAssertEqual(first.next,1)
        let middle=ClubInterfaceProfile.neighbors(index:32_000,count:60_000)
        XCTAssertEqual(middle.previous,31_999);XCTAssertEqual(middle.next,32_001)
        let last=ClubInterfaceProfile.neighbors(index:59_999,count:60_000)
        XCTAssertEqual(last.previous,59_998);XCTAssertNil(last.next)
        let single=ClubInterfaceProfile.neighbors(index:0,count:1)
        XCTAssertNil(single.previous);XCTAssertNil(single.next)
        XCTAssertNil(ClubInterfaceProfile.neighbors(index:0,count:0).next)
    }
    func testConceptStageGeometryIsDeterministicDistinctAndBounded() {
        for theme in VideoClubTheme.allCases {
            let neo=ClubInterfaceProfile.neoVideoClub.stage(theme:theme)
            let apple=ClubInterfaceProfile.appleCinema.stage(theme:theme)
            XCTAssertFalse(neo.isEmpty);XCTAssertFalse(apple.isEmpty)
            XCTAssertLessThanOrEqual(neo.count,3000);XCTAssertLessThanOrEqual(apple.count,1000)
            XCTAssertNotEqual(neo.count,apple.count)
            for profile in ClubInterfaceProfile.allCases {
                let mesh=profile.stage(theme:theme)
                let first=ProceduralCinema.project(mesh,width:960,height:540)
                XCTAssertFalse(first.isEmpty)
                XCTAssertEqual(first,ProceduralCinema.project(profile.stage(theme:theme),width:960,height:540))
                XCTAssertTrue(first.allSatisfy{ $0.depth.isFinite && $0.color.finite })
            }
        }
    }
}

extension ClubInterfaceProfileTests {
    func testFullScreenCaseFramingKeepsWholePosterAndLargeShelfNeighbors() {
        let slope=tan(35*Double.pi/360)
        for profile in ClubInterfaceProfile.allCases {
            for aspect in [16.0/9.0,2.0,1.33,1.0,0.66] {
                let distance=profile.inspectionDistance(aspect:aspect)
                let fraction=1.5/((distance-Double(CasePackageFormat.dvd.halfDepth()))*slope)
                XCTAssertLessThanOrEqual(fraction,0.9600001)
                if aspect >= 1.77 {XCTAssertGreaterThan(fraction,0.90)}
                let neighbors=CaseCarousel.placements(aspect:aspect,editorial:profile.isEditorial)
                XCTAssertTrue(neighbors.allSatisfy{$0.scale>=0.68 && $0.depth>0})
            }
        }
    }
}
