import Foundation

/// Procedural native menu geometry. Open tube sweep adapted from FERRO's
/// geometry.js (Catmull–Rom sampling, parallel-transport frame, outward faces).
/// Reference: M4D135/FERRO @ a443359c4741a815f384278e6427a33758d79f2f.
/// Deliberately independent of WebGL, physics, SceneKit and the video decoder.
public enum ProceduralCinema {
    public struct V: Equatable, Sendable {
        public var x: Double, y: Double, z: Double
        public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
        public static func + (a: V, b: V) -> V { V(a.x+b.x,a.y+b.y,a.z+b.z) }
        public static func - (a: V, b: V) -> V { V(a.x-b.x,a.y-b.y,a.z-b.z) }
        public static func * (a: V, b: Double) -> V { V(a.x*b,a.y*b,a.z*b) }
        public func dot(_ b: V) -> Double { x*b.x+y*b.y+z*b.z }
        public func cross(_ b: V) -> V { V(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
        public var length: Double { sqrt(dot(self)) }
        public var unit: V { let n = length; return n > 1e-9 ? self * (1/n) : V(0,0,0) }
        public var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }
    public struct Face: Equatable, Sendable {
        public let a: V, b: V, c: V
        public let color: V
        public var center: V { (a+b+c)*(1/3) }
        public var normal: V { (b-a).cross(c-a).unit }
    }
    public enum Style: String, CaseIterable, Sendable { case orbit, prism, horizon, off }
    public struct Pixel: Equatable, Sendable { public let x: Double, y: Double }
    public struct ProjectedFace: Equatable, Sendable {
        public let a: Pixel, b: Pixel, c: Pixel
        public let depth: Double
        public let color: V
    }
    /// Native open sweep; bounded input, no degenerate triangles, no caps
    /// (menu arcs extend outside the viewport). Subset, not the full FERRO API.
    public static func tube(points: [V], radius: Double, sides: Int = 8, subdivisions: Int = 3, color: V) -> [Face] {
        guard (2...48).contains(points.count), points.allSatisfy(\.finite), radius.isFinite, radius > 0, color.finite else { return [] }
        let sides = min(12,max(3,sides)), steps = min(4,max(1,subdivisions))
        func p(_ i: Int) -> V { points[min(points.count-1,max(0,i))] }
        var line: [V] = []
        for i in 0..<(points.count-1) {
            let a = p(i-1), b = p(i), c = p(i+1), d = p(i+2)
            for j in 0..<steps {
                let t = Double(j)/Double(steps), t2 = t*t, t3 = t2*t
                line.append((b*2 + (c-a)*t + (a*2-b*5+c*4-d)*t2 + (b*3-a-c*3+d)*t3)*0.5)
            }
        }
        line.append(points[points.count-1])
        let tangents = line.indices.map { i in (line[min(line.count-1,i+1)]-line[max(0,i-1)]).unit }
        guard tangents.allSatisfy({$0.length > 0.9}) else { return [] }
        func initial(_ t: V) -> V { t.cross(abs(t.y)<0.9 ? V(0,1,0):V(1,0,0)).unit }
        var u = initial(tangents[0]); var rings: [[V]] = []
        for i in line.indices {
            let t = tangents[i], transported = (u-t*u.dot(t)).unit
            u = transported.length > 0.9 ? transported : initial(t)
            let v = t.cross(u)
            rings.append((0..<sides).map { j in let a = 2*Double.pi*Double(j)/Double(sides); return line[i]+u*(radius*cos(a))+v*(radius*sin(a)) })
        }
        var faces: [Face] = []
        func append(_ a: V,_ b: V,_ c: V,_ inside: V) {
            let n = (b-a).cross(c-a); guard n.length>1e-10 else {return}
            let flip = n.dot((a+b+c)*(1/3)-inside)<0
            faces.append(Face(a:a,b:flip ? c:b,c:flip ? b:c,color:color))
        }
        for i in 0..<(rings.count-1) {
            let inside = (line[i]+line[i+1])*0.5
            for j in 0..<sides {
                let k=(j+1)%sides
                append(rings[i][j],rings[i][k],rings[i+1][k],inside)
                append(rings[i][j],rings[i+1][k],rings[i+1][j],inside)
            }
        }
        return faces
    }
    /// Three hand-designed recipes, each generated entirely from numeric parameters.
    public static func scene(style: Style, kind: IPTVMediaKind) -> [Face] {
        guard style != .off else { return [] }
        let tint: V
        switch kind { case .live: tint=V(0.12,0.70,0.95); case .movie: tint=V(0.34,0.46,0.95); case .series: tint=V(0.72,0.31,0.85) }
        var mesh: [Face] = []
        switch style {
        case .orbit:
            for i in 0..<5 {
                let k=Double(i), radius=2.2+k*0.43
                let points=(0...18).map { n -> V in
                    let a = -0.85+Double(n)*0.28+k*0.13
                    return V(2.5+radius*cos(a), 0.55+radius*sin(a)*0.68, 5.7+k*0.48+0.85*sin(a+k*0.45))
                }
                mesh += tube(points:points,radius:0.075+k*0.015,sides:8,subdivisions:2,color:tint*(0.84-k*0.09))
            }
        case .prism:
            for i in 0..<7 {
                let k=Double(i), x=1.1+k*0.54
                let points=[V(x-2.4,-2.8,7+k*0.25),V(x,0.6,6+k*0.25),V(x+0.8,1.8,7+k*0.25),V(x+3.0,3.1,9+k*0.25)]
                mesh += tube(points:points,radius:0.09+k*0.013,sides:8,subdivisions:4,color:tint*(1-k*0.065))
            }
        case .horizon:
            for i in 0..<9 {
                let k=Double(i)
                let points=(0...10).map { n -> V in
                    let x = -6+Double(n)*1.3
                    return V(x,-2.4+k*0.23+0.30*sin(x*0.63+k*0.5),5+k*0.52+0.55*cos(x*0.47+k*0.4))
                }
                mesh += tube(points:points,radius:0.045+k*0.004,sides:6,subdivisions:2,color:tint*(0.91-k*0.05))
            }
        case .off: break
        }
        return mesh
    }
    /// Perspective camera at origin, looking along +Z. Painter order is stable.
    /// Positive z only; no unbounded coordinates or NaNs passed to CoreGraphics.
    public static func project(_ mesh: [Face], width: Double, height: Double) -> [ProjectedFace] {
        guard width.isFinite,height.isFinite,width>0,height>0 else{return []}
        let focal=height*0.88, light=V(-0.45,0.8,-1).unit
        func point(_ p: V) -> Pixel { Pixel(x:width/2+p.x*focal/p.z,y:height/2-p.y*focal/p.z) }
        return mesh.compactMap { face -> ProjectedFace? in
            guard [face.a,face.b,face.c].allSatisfy({$0.finite && $0.z>0.25}),face.color.finite else{return nil}
            let n=face.normal, center=face.center
            let view=(center * -1).unit
            guard n.dot(view)>0 else{return nil}
            let diffuse=max(0,n.dot(light)), specular=pow(max(0,n.dot((light+view).unit)),12)
            let base=face.color*(0.22+diffuse*0.82)+V(0.66,0.83,1)*specular*0.72
            let rgb=V(min(1,max(0,base.x)),min(1,max(0,base.y)),min(1,max(0,base.z)))
            return ProjectedFace(a:point(face.a),b:point(face.b),c:point(face.c),depth:center.z,color:rgb)
        }.sorted { $0.depth > $1.depth }
    }
}
