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

    func testResponsiveFramingKeepsLargeHeldCaseAndContinuousShelf() {
        let slope=tan(35*Double.pi/360)
        for editorial in [false,true] {
            for aspect in [16.0/9.0,2.35,1.33,1.0,0.66,0.40] {
                let placements=CaseCarousel.placements(aspect:aspect,editorial:editorial)
                XCTAssertEqual(placements.map(\.offset),[-2,-1,1,2])
                XCTAssertEqual(placements.count,4)
                XCTAssertLessThan(placements[0].scale,placements[1].scale)
                XCTAssertGreaterThan(placements[1].scale,0.70)
                XCTAssertGreaterThan(placements[0].scale,0.60)
                let spacing=abs(placements[0].x-placements[1].x)
                XCTAssertLessThan(spacing,(placements[0].scale+placements[1].scale)*1.07)
                let distance=CaseCarousel.distance(aspect:aspect,editorial:editorial)
                let fraction=1.5/((distance-Double(CasePackageFormat.dvd.halfDepth()))*slope)
                XCTAssertLessThanOrEqual(fraction,0.960001)
                if aspect>=1.33 {XCTAssertGreaterThan(fraction,0.90)}
                XCTAssertTrue(placements.allSatisfy{$0.depth>0})
            }
            XCTAssertTrue(CaseCarousel.distance(aspect:.nan,editorial:editorial).isFinite)
            let closed=CaseCarousel.distance(aspect:16.0/9.0,editorial:editorial,collector:true)
            let opened=CaseCarousel.distance(aspect:16.0/9.0,editorial:editorial,collector:true,open:true)
            XCTAssertGreaterThan(opened,closed)
            let format=CasePackageFormat.dvd
            let lidDepth=Double(format.halfDepth(collector:true))+0.08+2*Double(format.halfWidth)*abs(sin(CaseCarousel.collectorOpeningAngle * .pi/180))
            XCTAssertLessThanOrEqual(1.5/((opened-lidDepth)*slope),0.920001)
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
        XCTAssertEqual(CaseBackMediaLayout.action(at:CGPoint(x:0.25,y:0.43)),.trailer)
        XCTAssertEqual(CaseBackMediaLayout.action(at:CGPoint(x:0.75,y:0.43)),.play)
        XCTAssertNil(CaseBackMediaLayout.action(at:CGPoint(x:0.5,y:0.8)))
    }

    func testHeldCaseFitsTheFixedCameraThroughoutRotationAndOpening() {
        let slope=tan(35*Double.pi/360)
        for aspect in [2.35,16.0/9.0,1.33,0.66] {
            let distance=CaseCarousel.distance(aspect:aspect,editorial:false)
            for format in CasePackageFormat.allCases {
                for opening in [0.0,-43,-86,-129,CaseCarousel.collectorOpeningAngle] {
                    for yaw in stride(from:0.0,through:360,by:30) {
                        for pitch in [-80.0,-45,0,45,80] {
                            let points=heldCorners(format:format,opening:opening).map{rotate($0,yaw:yaw,pitch:pitch)}
                            let fit=CaseCarousel.fitHeld(points:points,cameraDistance:distance,aspect:aspect)
                            XCTAssertGreaterThan(fit.scale,0)
                            XCTAssertLessThanOrEqual(fit.scale,CaseCarousel.maximumHeldScale)
                            for point in points {
                                let depth=fit.scale*point.z
                                XCTAssertGreaterThan(distance-depth,0.09999)
                                XCTAssertLessThanOrEqual(abs(depth),CaseCarousel.heldHalfDepth)
                                let x=(fit.scale*point.x+fit.x)/(distance-depth)
                                let y=(fit.scale*point.y+fit.y)/(distance-depth)
                                XCTAssertLessThanOrEqual(abs(x),CaseCarousel.heldViewportFill*slope*aspect+1e-10)
                                XCTAssertLessThanOrEqual(abs(y),CaseCarousel.heldViewportFill*slope+1e-10)
                            }
                        }
                    }
                }
            }
        }
    }

    func testSeasonAndMovieUseNearlyAllAvailableViewport() {
        let aspect=16.0/9.0,distance=CaseCarousel.distance(aspect:16.0/9.0,editorial:false)
        let slope=tan(35*Double.pi/360)
        for format in CasePackageFormat.allCases {
            for opening in [0.0,CaseCarousel.collectorOpeningAngle] {
                let points=heldCorners(format:format,opening:opening).map{rotate($0,yaw:-8,pitch:-4)}
                let fit=CaseCarousel.fitHeld(points:points,cameraDistance:distance,aspect:aspect)
                let x=points.map{(fit.scale*$0.x+fit.x)/(distance-fit.scale*$0.z)/(slope*aspect)}
                let y=points.map{(fit.scale*$0.y+fit.y)/(distance-fit.scale*$0.z)/slope}
                let width=(x.max()!-x.min()!)/2,height=(y.max()!-y.min()!)/2
                XCTAssertGreaterThan(max(width,height),0.97,"The held case must remain large, including an open season.")
            }
        }
    }

    func testShelfHasIdenticalProjectionBehindTheEntireRotationEnvelope() {
        for editorial in [false,true] {
            for aspect in [2.35,16.0/9.0,1.33,0.66] {
                let distance=CaseCarousel.distance(aspect:aspect,editorial:editorial)
                let shelf=CaseCarousel.shelfTransform(aspect:aspect,editorial:editorial)
                for placement in CaseCarousel.placements(aspect:aspect,editorial:editorial) {
                    for format in CasePackageFormat.allCases {
                        for point in corners(width:Double(format.halfWidth),height:1.5,depth:Double(format.halfDepth(collector:true))) {
                            let turned=rotate(point,yaw:placement.angle,pitch:0)*placement.scale
                            let original=turned+SIMD3(placement.x,placement.y,-placement.depth)
                            let transformed=original*shelf.scale+SIMD3(0,0,shelf.z)
                            XCTAssertEqual(transformed.x/(distance-transformed.z),original.x/(distance-original.z),accuracy:1e-10)
                            XCTAssertEqual(transformed.y/(distance-transformed.z),original.y/(distance-original.z),accuracy:1e-10)
                            XCTAssertLessThanOrEqual(transformed.z,-CaseCarousel.heldHalfDepth-CaseCarousel.shelfClearance+1e-10)
                        }
                    }
                }
            }
        }
    }

    private func corners(width:Double,height:Double,depth:Double)->[SIMD3<Double>] {
        [-width,width].flatMap{x in [-height,height].flatMap{y in [-depth,depth].map{SIMD3(x,y,$0)}}}
    }
    private func heldCorners(format:CasePackageFormat,opening:Double)->[SIMD3<Double>] {
        let width=Double(format.halfWidth),depth=Double(format.halfDepth(collector:true))
        let hinge=width-Double(format.bevel)
        let body=corners(width:width,height:1.5,depth:depth+0.015)
        let lid=corners(width:width,height:1.5,depth:(0.07+0.015)*0.45).map {
            rotate($0+SIMD3(hinge,0,0),yaw:opening,pitch:0)+SIMD3(-hinge,0,depth+0.04)
        }
        return body+lid
    }
    private func rotate(_ point:SIMD3<Double>,yaw:Double,pitch:Double)->SIMD3<Double> {
        let y=yaw * .pi/180,p=pitch * .pi/180
        let turned=SIMD3(cos(y)*point.x+sin(y)*point.z,point.y,-sin(y)*point.x+cos(y)*point.z)
        return SIMD3(turned.x,cos(p)*turned.y-sin(p)*turned.z,sin(p)*turned.y+cos(p)*turned.z)
    }
}
