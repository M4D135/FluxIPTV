import XCTest
@testable import FluxIPTVCore

final class ProceduralCinemaTests: XCTestCase {
    func testStraightFerroSweep() {
        typealias V = ProceduralCinema.V
        let faces = ProceduralCinema.tube(points:[V(0,0,3),V(0,0,5)],radius:0.25,sides:8,subdivisions:3,color:V(1,1,1))
        XCTAssertEqual(faces.count,48)
        for face in faces {
            XCTAssertGreaterThan(face.normal.length,0.99)
            for p in [face.a,face.b,face.c] { XCTAssertEqual(hypot(p.x,p.y),0.25,accuracy:1e-9) }
            XCTAssertGreaterThan(face.normal.dot(V(face.center.x,face.center.y,0)),0)
        }
    }
    func testRecipesAndProjection() {
        for style in ProceduralCinema.Style.allCases {
            for kind in IPTVMediaKind.allCases {
                let mesh=ProceduralCinema.scene(style:style,kind:kind)
                XCTAssertEqual(mesh,ProceduralCinema.scene(style:style,kind:kind))
                XCTAssertLessThanOrEqual(mesh.count,3000)
                let projected=ProceduralCinema.project(mesh,width:960,height:540)
                if style == .off { XCTAssertTrue(mesh.isEmpty) } else { XCTAssertFalse(projected.isEmpty) }
                XCTAssertTrue(projected.allSatisfy{$0.a.x.isFinite && $0.b.y.isFinite && $0.c.x.isFinite && $0.depth>0 && $0.color.finite})
                XCTAssertEqual(projected.map(\.depth),projected.map(\.depth).sorted(by:>))
            }
        }
    }
    func testMalformedGeometryIsRejected() {
        typealias V=ProceduralCinema.V
        XCTAssertTrue(ProceduralCinema.tube(points:[V(0,0,0),V(0,0,0)],radius:1,color:V(1,1,1)).isEmpty)
        XCTAssertTrue(ProceduralCinema.tube(points:[V(.nan,0,0),V(1,0,0)],radius:1,color:V(1,1,1)).isEmpty)
        XCTAssertTrue(ProceduralCinema.project(ProceduralCinema.scene(style:.orbit,kind:.movie),width:0,height:540).isEmpty)
    }
    func testCrashRecoveryForcesNative() {
        var recovery=PlaybackRecovery(uncleanVLCSession:true)
        XCTAssertEqual(recovery.preferredEngine(.vlc),.native)
        recovery.resumeNormalMode()
        XCTAssertEqual(recovery.preferredEngine(.vlc),.vlc)
    }
}
