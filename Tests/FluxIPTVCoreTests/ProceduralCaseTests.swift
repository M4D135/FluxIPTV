import XCTest
@testable import FluxIPTVCore
final class ProceduralCaseTests: XCTestCase {
    func testSolidOutwardFacesAndTextureCoordinates() {
        let mesh = ProceduralCase.mesh()
        XCTAssertEqual(mesh.count, 60)
        XCTAssertEqual(mesh.filter{$0.surface == .front}.count,6)
        XCTAssertEqual(mesh.filter{$0.surface == .back}.count,6)
        var edges: [String:Int] = [:]
        func key(_ p: SIMD3<Float>) -> String { "\(p.x),\(p.y),\(p.z)" }
        for triangle in mesh {
            let v = triangle.vertices
            XCTAssertEqual(v.count,3)
            let c=(v[0].position+v[1].position+v[2].position)/3
            let n=v[0].normal
            XCTAssertGreaterThan(c.x*n.x+c.y*n.y+c.z*n.z,0)
            XCTAssertEqual(n.x*n.x+n.y*n.y+n.z*n.z,1,accuracy:0.001)
            for i in 0..<3 {
                let e=[key(v[i].position),key(v[(i+1)%3].position)].sorted().joined(separator:"|")
                edges[e,default:0] += 1
                if triangle.surface != .edge { XCTAssertTrue((-0.001...1.001).contains(v[i].uv.x)); XCTAssertTrue((-0.001...1.001).contains(v[i].uv.y)) }
            }
        }
        XCTAssertTrue(edges.values.allSatisfy{$0 == 2},"Closed manifold")
        let p=mesh.flatMap(\.vertices).map(\.position)
        XCTAssertEqual(p.map(\.z).max()!-p.map(\.z).min()!,0.21,accuracy:0.001)
    }
    func testBothFacesHaveUprightTextures() {
        for face in [ProceduralCase.Surface.front,.back] {
            let vertices=ProceduralCase.mesh().filter{$0.surface == face}.flatMap(\.vertices)
            let top=vertices.max(by:{$0.position.y < $1.position.y})!
            let bottom=vertices.min(by:{$0.position.y < $1.position.y})!
            XCTAssertEqual(top.uv.y,0,accuracy:0.0001)
            XCTAssertEqual(bottom.uv.y,1,accuracy:0.0001)
        }
    }
    func testBackTextureReversedHorizontallyForPhysicalTurn() {
        let mesh=ProceduralCase.mesh()
        let a=mesh.first{$0.surface == .front}!.vertices[0]
        let b=mesh.first{$0.surface == .back}!.vertices[0]
        XCTAssertEqual(a.position.x,b.position.x)
        XCTAssertEqual(a.uv.x+b.uv.x,1,accuracy:0.0001)
    }
}
