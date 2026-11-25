import Foundation

/// Closed bevelled sleeve in model space, with independent front and back UVs.
public enum ProceduralCase {
    public enum Surface: Int, CaseIterable, Sendable { case front, back, edge, spine }
    public struct Vertex: Equatable, Sendable {
        public let position: SIMD3<Float>
        public let normal: SIMD3<Float>
        public let uv: SIMD2<Float>
    }
    public struct Triangle: Equatable, Sendable {
        public let surface: Surface
        public let vertices: [Vertex]
    }
    public static func mesh() -> [Triangle] {
        let x: Float = 1, y: Float = 1.5, z: Float = 0.105, bevel: Float = 0.035
        func ring(_ w: Float, _ h: Float, _ cut: Float, _ depth: Float) -> [SIMD3<Float>] {
            [SIMD3(w-cut,h,depth),SIMD3(-w+cut,h,depth),SIMD3(-w,h-cut,depth),SIMD3(-w,-h+cut,depth),SIMD3(-w+cut,-h,depth),SIMD3(w-cut,-h,depth),SIMD3(w,-h+cut,depth),SIMD3(w,h-cut,depth)]
        }
        let front = ring(x-bevel,y-bevel,bevel,z), back = ring(x-bevel,y-bevel,bevel,-z)
        let rings = [front, ring(x,y,bevel*2,z-bevel), ring(x,y,bevel*2,-z+bevel), back]
        var result: [Triangle] = []
        func emit(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ surface: Surface) {
            let u = b-a, v = c-a
            let n0 = SIMD3(u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x)
            let n = n0/sqrt(n0.x*n0.x+n0.y*n0.y+n0.z*n0.z)
            let vertices = [a,b,c].map { p in
                let u = p.x/(2*(x-bevel))+0.5, v = 0.5-p.y/(2*(y-bevel))
                // SceneKit/Metal image convention: top edge maps to v=0, bottom to v=1.
                return Vertex(position:p,normal:n,uv:SIMD2(surface == .back ? 1-u : u,v))
            }
            result.append(Triangle(surface: surface, vertices: vertices))
        }
        for i in 1..<7 { emit(front[0],front[i],front[i+1],.front); emit(back[0],back[i+1],back[i],.back) }
        for r in 0..<3 {
            for i in 0..<8 {
                let j = (i+1)%8, a = rings[r][i], b = rings[r][j], c = rings[r+1][j], d = rings[r+1][i]
                emit(a,d,c,.edge); emit(a,c,b,.edge)
            }
        }
        return result
    }

    /// Smooth rounded DVD/VHS shell. Fixed-size geometry, no subdivisions per frame.
    /// A thin inset middle ring simulates the two halves of the plastic shell.
    public static func premiumMesh(cornerSegments: Int = 4, halfDepth: Float = 0.14,
                                   halfWidth: Float = 1, halfHeight: Float = 1.5,
                                   bevel requestedBevel: Float = 0.047,
                                   cornerRadius requestedRadius: Float = 0.075) -> [Triangle] {
        let segments = max(1,min(8,cornerSegments))
        let x = halfWidth.isFinite ? max(0.5,min(2,halfWidth)) : 1
        let y = halfHeight.isFinite ? max(0.5,min(2,halfHeight)) : 1.5
        let z = halfDepth.isFinite ? max(0.07,min(0.40,halfDepth)) : 0.14
        let bevel = requestedBevel.isFinite ? max(0.012,min(z*0.8,requestedBevel)) : 0.047
        let radius = requestedRadius.isFinite ? max(bevel+0.012,min(0.2,requestedRadius)) : 0.075
        struct Sample { let p: SIMD3<Float>; let n: SIMD3<Float> }
        let ringCount=4*(segments+1)
        func ring(inset:Float, depth:Float, normalXY:Float, normalZ:Float) -> [Sample] {
            let w=x-inset, h=y-inset, r=max(0.012,radius-inset)
            let centres=[SIMD2(w-r,h-r),SIMD2(-w+r,h-r),SIMD2(-w+r,-h+r),SIMD2(w-r,-h+r)]
            var out:[Sample]=[]
            for k in 0..<4 { for j in 0...segments {
                let a=(Float(k)+Float(j)/Float(segments))*Float.pi/2
                let c=cos(a),s=sin(a)
                out.append(Sample(p:SIMD3(centres[k].x+r*c,centres[k].y+r*s,depth), n:SIMD3(normalXY*c,normalXY*s,normalZ)))
            }}
            return out
        }
        let q:Float=0.70710678
        let rings = [ring(inset:bevel,depth:z,normalXY:0,normalZ:1),
                     ring(inset:bevel*(1-q),depth:z-bevel*(1-q),normalXY:q,normalZ:q),
                     ring(inset:0,depth:z-bevel,normalXY:1,normalZ:0),
                     ring(inset:0,depth:0.006,normalXY:1,normalZ:0),
                     ring(inset:0.006,depth:0,normalXY:1,normalZ:0),
                     ring(inset:0,depth:-0.006,normalXY:1,normalZ:0),
                     ring(inset:0,depth:-z+bevel,normalXY:1,normalZ:0),
                     ring(inset:bevel*(1-q),depth:-z+bevel*(1-q),normalXY:q,normalZ:-q),
                     ring(inset:bevel,depth:-z,normalXY:0,normalZ:-1)]
        var out:[Triangle]=[]
        func emit(_ samples:[Sample],_ face:Surface) {
            let v=samples.map { s -> Vertex in
                let p=s.p
                let u=p.x/(2*(x-bevel))+0.5, t=0.5-p.y/(2*(y-bevel))
                let uv:SIMD2<Float>
                switch face {
                case .front: uv=SIMD2(u,t)
                case .back: uv=SIMD2(1-u,t)
                case .spine: uv=SIMD2((z-p.z)/(2*z),0.5-p.y/(2*y))
                case .edge: uv=SIMD2(p.z/(2*z)+0.5,0.5-p.y/(2*y))
                }
                return Vertex(position:p,normal:s.n,uv:uv)
            }
            out.append(Triangle(surface:face,vertices:v))
        }
        let f=Sample(p:SIMD3(0,0,z),n:SIMD3(0,0,1)), b=Sample(p:SIMD3(0,0,-z),n:SIMD3(0,0,-1))
        for i in 0..<ringCount {let j=(i+1)%ringCount;emit([f,rings[0][i],rings[0][j]],.front);emit([b,rings[8][j],rings[8][i]],.back)}
        let leftStraight=2*(segments+1)-1
        for k in 0..<rings.count-1 { for i in 0..<ringCount {
            let j=(i+1)%ringCount, a=rings[k][i],b=rings[k][j],c=rings[k+1][j],d=rings[k+1][i]
            let surface:Surface=(i==leftStraight && k>=2 && k<=5) ? .spine:.edge
            emit([a,d,c],surface);emit([a,c,b],surface)
        }}
        return out
    }

    public static func premiumMesh(cornerSegments: Int = 4, format: CasePackageFormat,
                                   collector: Bool = false, halfDepth: Float? = nil) -> [Triangle] {
        premiumMesh(cornerSegments: cornerSegments, halfDepth: halfDepth ?? format.halfDepth(collector: collector),
                    halfWidth: format.halfWidth, halfHeight: format.halfHeight,
                    bevel: format.bevel, cornerRadius: format.cornerRadius)
    }

    /// Seeded grain; tangent-space normal maps are generated locally, never downloaded.
    public static func grainNormalMap(size requested: Int = 128, seed: UInt64 = 0xF10C, strength: Float = 0.18) -> [UInt8] {
        let size=max(8,min(256,requested))
        var state=seed
        func random()->Float {state=state &* 6364136223846793005 &+ 1;return Float((state >> 40)&0xFFFFFF)/Float(0xFFFFFF)}
        let height=(0..<(size*size)).map{_ in random()}
        func h(_ x:Int,_ y:Int)->Float {height[((y+size)%size)*size+(x+size)%size]}
        var bytes=[UInt8]();bytes.reserveCapacity(size*size*4)
        func pack(_ f:Float)->UInt8 {UInt8(max(0,min(255,Int((f*0.5+0.5)*255))))}
        for y in 0..<size {for x in 0..<size {
            let dx=(h(x-1,y)-h(x+1,y))*strength,dy=(h(x,y-1)-h(x,y+1))*strength
            let inv=1/sqrt(1+dx*dx+dy*dy)
            bytes += [pack(dx*inv),pack(dy*inv),pack(inv),255]
        }}
        return bytes
    }

}
