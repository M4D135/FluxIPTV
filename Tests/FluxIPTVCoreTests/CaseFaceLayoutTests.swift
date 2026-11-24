import XCTest
@testable import FluxIPTVCore
final class CaseFaceLayoutTests: XCTestCase {
    func testFaceRegionsDoNotOverlapAndPickCentres() {
        for page in [CaseFaceLayout.Page.front,.details,.episodes] {
            let regions=CaseFaceLayout.regions(page,series:true,trailer:true,episodeCount:4)
            for (i,r) in regions.enumerated() {
                XCTAssertTrue(CGRect(x:0,y:0,width:1,height:1).contains(r.rect))
                XCTAssertEqual(CaseFaceLayout.action(at:CGPoint(x:r.rect.midX,y:r.rect.midY),in:regions),r.action)
                for other in regions.dropFirst(i+1) {XCTAssertFalse(r.rect.intersects(other.rect))}
            }
        }
    }
    func testRemoteFocusAndFaceOrientation() {
        XCTAssertEqual(CaseFaceLayout.face(yaw:0,pitch:0),.front)
        XCTAssertEqual(CaseFaceLayout.face(yaw:180,pitch:0),.details)
        XCTAssertNil(CaseFaceLayout.face(yaw:90,pitch:0))
        let a=CaseFaceLayout.regions(.details,series:false,trailer:false)
        XCTAssertEqual(CaseFaceLayout.nextFocus(from:nil,by:1,regions:a),a.first?.action)
        XCTAssertEqual(CaseFaceLayout.nextFocus(from:a.first?.action,by:-1,regions:a),a.last?.action)
    }
    func testPremiumShellAndProceduralGrain() {
        let mesh=ProceduralCase.premiumMesh()
        XCTAssertLessThan(mesh.count,500)
        XCTAssertGreaterThan(mesh.count,60)
        XCTAssertTrue(mesh.contains{$0.surface == .spine})
        var edges:[String:Int]=[:]
        for t in mesh {for (i,v) in t.vertices.enumerated() {
            let n=v.normal;XCTAssertEqual(n.x*n.x+n.y*n.y+n.z*n.z,1,accuracy:0.002)
            let b=t.vertices[(i+1)%3].position
            let key=[String(describing:v.position),String(describing:b)].sorted().joined(separator:"|")
            edges[key,default:0]+=1
        }}
        XCTAssertTrue(edges.values.allSatisfy{$0==2})
        let a=ProceduralCase.grainNormalMap(size:64),b=ProceduralCase.grainNormalMap(size:64)
        XCTAssertEqual(a,b);XCTAssertEqual(a.count,64*64*4);XCTAssertNotEqual(a,ProceduralCase.grainNormalMap(size:64,seed:19))
    }
}

extension CaseFaceLayoutTests {
    func testTextureBudgetAndQualityLevels() {
        XCTAssertEqual(CaseRenderQuality.balanced.sleeveWidth,1024)
        XCTAssertEqual(CaseRenderQuality.balanced.sleeveHeight,1536)
        XCTAssertLessThanOrEqual(CaseRenderQuality.balanced.textureBytes,12*1024*1024)
        XCTAssertLessThan(CaseRenderQuality.cinema.textureBytes,28*1024*1024)
        XCTAssertLessThan(CaseRenderQuality.economy.fps,CaseRenderQuality.balanced.fps)
        XCTAssertEqual(ProceduralCase.premiumMesh().count,360)
        XCTAssertLessThan(ProceduralCase.premiumMesh(cornerSegments:2).count,360)
    }
    func testPickingEpisodePagesAndMissingTrailer() {
        let rows=CaseFaceLayout.regions(.episodes,series:true,trailer:false,episodeCount:99)
        let episodes=rows.filter{ if case .episode=$0.action {return true};return false }
        XCTAssertEqual(episodes.count,4)
        XCTAssertEqual(CaseFaceLayout.action(at:CGPoint(x:episodes[3].rect.midX,y:episodes[3].rect.midY),in:rows),.episode(3))
        XCTAssertFalse(CaseFaceLayout.regions(.details,series:false,trailer:false).contains{$0.action == .trailer})
    }
}
