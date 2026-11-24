import XCTest
@testable import FluxIPTVCore

final class CaseCarouselTests: XCTestCase {
    func testFiveObjectWindowAtCatalogueBoundaries() {
        func window(_ index:Int,_ count:Int) -> [Int] {
            (-CaseCarousel.radius...CaseCarousel.radius).compactMap {CaseCarousel.index(from:index,offset:$0,count:count)}
        }
        XCTAssertEqual(window(0,60_000),[0,1,2])
        XCTAssertEqual(window(32_000,60_000),[31_998,31_999,32_000,32_001,32_002])
        XCTAssertEqual(window(59_999,60_000),[59_997,59_998,59_999])
        XCTAssertEqual(window(0,1),[0])
        XCTAssertEqual(window(0,0),[])
        XCTAssertNil(CaseCarousel.index(from:-1,offset:1,count:40))
        XCTAssertNil(CaseCarousel.index(from:2,offset:3,count:40))
        XCTAssertNil(CaseCarousel.index(from:Int.max-1,offset:1,count:Int.max))
        XCTAssertEqual(CaseCarousel.index(from:Int.max-2,offset:1,count:Int.max),Int.max-1)
        XCTAssertNil(CaseCarousel.index(from:0,offset:Int.min,count:40))
    }

    func testFinalClosedCaseShortcuts() {
        for series in [false,true] {
            let primary:CaseFaceLayout.Action = series ? .episodes:.play
            XCTAssertEqual(CaseCarousel.command(for:.up,series:series),primary)
            XCTAssertEqual(CaseCarousel.command(for:.select,series:series),primary)
            XCTAssertEqual(CaseCarousel.command(for:.playPause,series:series),primary)
            XCTAssertEqual(CaseCarousel.command(for:.left,series:series),.previous)
            XCTAssertEqual(CaseCarousel.command(for:.right,series:series),.next)
            XCTAssertEqual(CaseCarousel.command(for:.back,series:series),.close)
            // Down enters the visible action bar; it must never close or play.
            XCTAssertNil(CaseCarousel.command(for:.down,series:series))
            XCTAssertNil(CaseCarousel.command(for:.options,series:series))
        }
    }

    func testResponsiveFramingKeepsLargeCentralPosterAndFourSmallNeighbors() {
        let slope=tan(35*Double.pi/360)
        for editorial in [false,true] {
            for aspect in [16.0/9.0,2.35,1.33,1.0,0.66,0.40] {
                let placements=CaseCarousel.placements(aspect:aspect,editorial:editorial)
                XCTAssertEqual(placements.map(\.offset),[-2,-1,1,2])
                XCTAssertEqual(placements.count,4)
                XCTAssertLessThan(placements[0].scale,placements[1].scale)
                XCTAssertLessThan(placements[1].scale,0.5)
                let distance=CaseCarousel.distance(aspect:aspect,editorial:editorial)
                let fraction=1.5/((distance-0.14)*slope)
                XCTAssertLessThanOrEqual(fraction,0.900001)
                if aspect>=1.33 {XCTAssertGreaterThan(fraction,0.85)}
                for placement in placements {
                    let outer=abs(placement.x)+placement.scale*1.04
                    let front = -placement.depth+placement.scale*0.70
                    XCTAssertLessThanOrEqual(outer/((distance-front)*slope*aspect),0.960001)
                }
            }
            XCTAssertTrue(CaseCarousel.distance(aspect:.nan,editorial:editorial).isFinite)
            let closed=CaseCarousel.distance(aspect:16.0/9.0,editorial:editorial,collector:true)
            let opened=CaseCarousel.distance(aspect:16.0/9.0,editorial:editorial,collector:true,open:true)
            XCTAssertGreaterThan(opened,closed)
            let lidDepth=CaseCarousel.collectorHalfDepth+0.08+1.94*sin(25*Double.pi/180)
            XCTAssertLessThanOrEqual(1.5/((opened-lidDepth)*slope),0.900001)
        }
    }

    func testCollectorHasRealDepthAndBoundedTextures() {
        let movie=ProceduralCase.premiumMesh()
        let collector=ProceduralCase.premiumMesh(halfDepth:Float(CaseCarousel.collectorHalfDepth))
        XCTAssertEqual(movie.count,collector.count)
        let vertices=collector.flatMap(\.vertices)
        let depth=vertices.map(\.position.z).max()!-vertices.map(\.position.z).min()!
        XCTAssertEqual(depth,0.6,accuracy:0.0001)
        for vertex in vertices {
            XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
            XCTAssertEqual(vertex.normal.x*vertex.normal.x+vertex.normal.y*vertex.normal.y+vertex.normal.z*vertex.normal.z,1,accuracy:0.002)
        }
        XCTAssertLessThan(CaseRenderQuality.balanced.collectorTextureBytes,20*1024*1024)
        XCTAssertLessThan(CaseRenderQuality.cinema.collectorTextureBytes,42*1024*1024)
    }

    func testBackMediaAndDescriptionPanelsDoNotOverlap() {
        let page=CGRect(x:0,y:0,width:1,height:1)
        let regions=[CaseBackMediaLayout.frame,CaseBackMediaLayout.trailer,CaseBackMediaLayout.film,CaseBackMediaLayout.descriptionFrame]
        for (index,region) in regions.enumerated() {
            XCTAssertTrue(page.contains(region))
            for other in regions.dropFirst(index+1) {XCTAssertFalse(region.intersects(other))}
        }
        for rect in [CaseBackMediaLayout.descriptionPrevious,CaseBackMediaLayout.descriptionNext,CaseBackMediaLayout.descriptionLink] {
            XCTAssertTrue(CaseBackMediaLayout.descriptionFrame.contains(rect))
        }
        XCTAssertEqual(CaseBackMediaLayout.action(at:CGPoint(x:0.25,y:0.43)),.trailer)
        XCTAssertEqual(CaseBackMediaLayout.action(at:CGPoint(x:0.75,y:0.43)),.play)
        XCTAssertNil(CaseBackMediaLayout.action(at:CGPoint(x:0.5,y:0.8)))
    }
}
