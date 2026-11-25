import XCTest
@testable import FluxIPTVCore

final class CasePackageFormatTests: XCTestCase {
    func testReleaseYearBoundaryAndUnknownFormat() {
        for year in ["1895", "1984", "1999", "1999-12-31", "23/04/1999", "1994–2004"] {
            XCTAssertEqual(CasePackageFormat.resolve(year:year),.vhs)
        }
        for year in ["2000", "2000-01-01", "2011", "2026", "2100", "", "0", "Inconnue", "19999"] {
            XCTAssertEqual(CasePackageFormat.resolve(year:year),.dvd)
        }
        XCTAssertEqual(CasePackageFormat.resolve(year:nil),.dvd)
    }

    func testPhysicalShellsKeepUprightArtworkAndDistinctProportions() {
        XCTAssertLessThan(CasePackageFormat.vhs.halfWidth,CasePackageFormat.dvd.halfWidth)
        XCTAssertGreaterThan(CasePackageFormat.vhs.halfDepth(),CasePackageFormat.dvd.halfDepth()*1.9)
        for format in CasePackageFormat.allCases {
            for collector in [false,true] {
                let triangles=ProceduralCase.premiumMesh(format:format,collector:collector)
                let positions=triangles.flatMap(\.vertices).map(\.position)
                XCTAssertEqual(positions.map(\.x).max()!-positions.map(\.x).min()!,format.halfWidth*2,accuracy:0.0001)
                XCTAssertEqual(positions.map(\.y).max()!-positions.map(\.y).min()!,format.halfHeight*2,accuracy:0.0001)
                XCTAssertEqual(positions.map(\.z).max()!-positions.map(\.z).min()!,format.halfDepth(collector:collector)*2,accuracy:0.0001)
                for face in [ProceduralCase.Surface.front,.back] {
                    for vertex in triangles.filter({$0.surface == face}).flatMap(\.vertices) {
                        XCTAssertEqual(vertex.uv.y,0.5-vertex.position.y/format.faceHeight,accuracy:0.0001)
                        let expected=0.5+vertex.position.x/format.faceWidth
                        XCTAssertEqual(vertex.uv.x,face == .back ? 1-expected:expected,accuracy:0.0001)
                    }
                }
                XCTAssertEqual(triangles.count,ProceduralCase.premiumMesh().count)
            }
        }
    }

    func testClosedSleeveUsesAvailableHeightWithoutCropping() {
        let slope=tan(35*Double.pi/360)
        for format in CasePackageFormat.allCases {
            for editorial in [false,true] {
                for aspect in [16.0/9.0,2.35,1.33,1.0,0.66,0.40] {
                    let distance=CaseCarousel.distance(aspect:aspect,editorial:editorial,format:format)
                    let depth=Double(format.halfDepth())
                    let heightFraction=Double(format.halfHeight)/((distance-depth)*slope)
                    let widthFraction=Double(format.halfWidth)/((distance-depth)*slope*aspect)
                    XCTAssertLessThanOrEqual(heightFraction,0.960001)
                    XCTAssertLessThanOrEqual(widthFraction,0.960001)
                    if aspect>=1.33 {XCTAssertGreaterThan(heightFraction,0.90)}
                }
            }
        }
    }

    func testVideoViewportKeepsItsAspectOnDVDAndVHS() {
        for format in CasePackageFormat.allCases {
            let width=CGFloat(format.faceWidth),height=CGFloat(format.faceHeight)
            let video = CaseBackMediaLayout.videoFrame(width:width,height:height)
            let frame = CaseBackMediaLayout.frame
            XCTAssertEqual(video.width*width/(video.height*height),16.0/9.0,accuracy:0.00001)
            XCTAssertEqual(video.midX,frame.midX,accuracy:0.00001)
            XCTAssertEqual(video.midY,frame.midY,accuracy:0.00001)
            XCTAssertLessThanOrEqual(video.width,frame.width+0.00001)
            XCTAssertLessThanOrEqual(video.height,frame.height+0.00001)
            XCTAssertTrue(abs(video.width-frame.width)<0.00001 || abs(video.height-frame.height)<0.00001)
        }
        XCTAssertEqual(CaseBackMediaLayout.videoFrame(width:0,height:3),CaseBackMediaLayout.frame)
        XCTAssertEqual(CaseBackMediaLayout.videoFrame(width:.nan,height:3),CaseBackMediaLayout.frame)
    }
}
