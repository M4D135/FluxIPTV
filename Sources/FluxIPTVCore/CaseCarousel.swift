import Foundation

/// A fixed five-object window, independent of the size of the catalogue.
public enum CaseCarousel {
    public static let radius = 2
    public static let offsets = [-2, -1, 1, 2]

    public struct Placement: Equatable, Sendable {
        public let offset: Int
        public let x: Double
        public let y: Double
        public let depth: Double
        public let scale: Double
        public let angle: Double
    }

    public static func index(from index: Int, offset: Int, count: Int) -> Int? {
        guard count > 0, index >= 0, index < count, (-radius...radius).contains(offset) else { return nil }
        // Compare the remaining distance before adding, including Int.max catalogues.
        if offset < 0 { return index >= -offset ? index + offset : nil }
        return offset < count - index ? index + offset : nil
    }

    public static func placements(aspect rawAspect: Double, editorial: Bool) -> [Placement] {
        let aspect = rawAspect.isFinite ? max(0.15, rawAspect) : 16.0 / 9.0
        // A continuous shelf sits behind the held case. Narrow screens reveal
        // overlapping edges instead of reducing neighboring cases to thumbnails.
        let spread = min(1, max(0.18, aspect / (16.0 / 9.0)))
        return offsets.map { offset in
            let far = abs(offset) == 2
            let sign = offset < 0 ? -1.0 : 1.0
            let scale = far ? (editorial ? 0.68 : 0.72) : (editorial ? 0.78 : 0.82)
            return Placement(offset: offset,
                x: sign * (far ? (editorial ? 2.60 : 2.65) : (editorial ? 1.48 : 1.55)) * spread,
                y: -1.5 * (1-scale),
                depth: far ? (editorial ? 0.78 : 0.72) : (editorial ? 0.50 : 0.45),
                scale: scale,
                angle: -sign * (far ? (editorial ? 14 : 16) : (editorial ? 10 : 12)))
        }
    }

    public static let collectorHalfDepth = 0.30
    public static let collectorOpeningAngle = -172.0

    /// Only the held object is fitted to the viewport. The camera and shelf
    /// retain their reference layout when the user turns or opens a case.
    public static let heldViewportFill = 0.985
    public static let maximumHeldScale = 1.25
    public static let shelfClearance = 0.16

    public struct HeldFit: Equatable, Sendable {
        public let scale: Double
        public let x: Double
        public let y: Double
    }

    public struct ShelfTransform: Equatable, Sendable {
        public let scale: Double
        public let z: Double
    }

    /// An orientation-independent depth envelope includes the entire season
    /// lid opening arc. XY centering does not change this bound, and fitting
    /// caps the scale, so the shelf never needs to move with the selected case.
    public static let heldHalfDepth: Double = {
        CasePackageFormat.allCases.map { format in
            let w=Double(format.halfWidth),h=Double(format.halfHeight)
            let hinge=hypot(w-Double(format.bevel),Double(format.halfDepth(collector:true))+0.04)
            let lid=hypot(2*w-Double(format.bevel),0.07*0.45+0.015)
            let openingRadius=hypot(hinge+lid,h)
            return openingRadius*maximumHeldScale+0.04
        }.max() ?? 4.5
    }()

    /// Move the whole shelf farther down the same camera rays, once per
    /// viewport/concept change. Its projected size, spacing and perspective
    /// stay identical, while every mesh is beyond the held rotation envelope.
    public static func shelfTransform(aspect:Double,editorial:Bool) -> ShelfTransform {
        let camera=distance(aspect:aspect,editorial:editorial)
        let maximumWidth=Double(CasePackageFormat.dvd.halfWidth)
        let maximumDepth=Double(CasePackageFormat.vhs.halfDepth(collector:true))
        var nearest:Double?
        for placement in placements(aspect:aspect,editorial:editorial) {
            let angle:Double=placement.angle * Double.pi/180
            let widthProjection:Double=maximumWidth*abs(sin(angle))
            let depthProjection:Double=maximumDepth*abs(cos(angle))
            let forwardExtent:Double=placement.scale*(widthProjection+depthProjection)
            let front:Double=forwardExtent-placement.depth
            nearest=max(nearest ?? front,front)
        }
        let scale=max(1,(camera+heldHalfDepth+shelfClearance)/(camera-(nearest ?? 0)))
        return ShelfTransform(scale:scale,z:camera*(1-scale))
    }

    /// Largest centered fit of the actual posed geometry in a fixed perspective
    /// frustum. This linear bound covers every corner, including unequal depths
    /// on an open lid; fitting a front/back baseline wastes that useful area.
    public static func fitHeld(points:[SIMD3<Double>],cameraDistance:Double,aspect rawAspect:Double) -> HeldFit {
        let points=points.filter{$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}
        guard !points.isEmpty,cameraDistance.isFinite,cameraDistance>0.1 else{return HeldFit(scale:1,x:0,y:0)}
        let aspect=rawAspect.isFinite ? max(0.15,rawAspect):16.0/9.0
        let vertical=heldViewportFill*tan(35 * Double.pi/360),horizontal=vertical*aspect
        let left=points.map{horizontal*$0.z-$0.x}.max()!
        let right=points.map{horizontal*$0.z+$0.x}.max()!
        let bottom=points.map{vertical*$0.z-$0.y}.max()!
        let top=points.map{vertical*$0.z+$0.y}.max()!
        var scale=maximumHeldScale
        if left+right>0 {scale=min(scale,2*horizontal*cameraDistance/(left+right))}
        if bottom+top>0 {scale=min(scale,2*vertical*cameraDistance/(bottom+top))}
        if let nearest=points.map(\.z).max(),nearest>0 {scale=min(scale,(cameraDistance-0.1)/nearest)}
        scale=max(0.0001,scale)
        return HeldFit(scale:scale,x:scale*(left-right)/2,y:scale*(bottom-top)/2)
    }

    public static func distance(aspect rawAspect: Double, editorial: Bool, collector: Bool = false,
                                open: Bool = false, format: CasePackageFormat = .dvd) -> Double {
        let aspect = rawAspect.isFinite ? max(0.15, rawAspect) : 16.0 / 9.0
        let slope = tan(35 * Double.pi / 360)
        let halfWidth = Double(format.halfWidth), halfHeight = Double(format.halfHeight)
        let front = Double(format.halfDepth(collector:collector)) + (collector ? 0.08 : 0)
        // The hinged lid extends towards the eye when the collector is open.
        let forward = open ? front + 2 * halfWidth * abs(sin(collectorOpeningAngle * .pi / 180)) : front
        // Only the held object controls the zoom. Shelf neighbors may continue
        // beyond the screen edges, like the rest of a physical row of cases.
        let distance = max(halfHeight / ((open ? 0.92 : 0.96) * slope) + forward,
                           (open ? 2.25 * halfWidth : halfWidth + 0.02) / (0.96 * aspect * slope) + forward)
        return distance
    }
}
