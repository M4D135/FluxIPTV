import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Projects a live native/web surface onto the four screen-space corners of
/// the case's video frame. Coordinates use a top-left origin with downward Y.
public struct CasePreviewProjection: Equatable, Sendable {
    /// CATransform3D's column convention, with m33 and m44 left at one and all
    /// other fields left at zero. Translation is already in viewport coordinates.
    public struct Matrix: Equatable, Sendable {
        public let m11: CGFloat
        public let m12: CGFloat
        public let m14: CGFloat
        public let m21: CGFloat
        public let m22: CGFloat
        public let m24: CGFloat
        public let m41: CGFloat
        public let m42: CGFloat
    }

    public let bounds: CGRect
    public var surfaceSize: CGSize { bounds.size }
    public let matrix: Matrix
    private let corners: [CGPoint]
    private let viewport: CGSize
    private let area: CGFloat
    private let minimumWidth: CGFloat
    private let minimumHeight: CGFloat

    public init?(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint, viewport: CGSize) {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let lengths = (0..<4).map { index in Self.distance(points[index], points[(index + 1) % 4]) }
        guard lengths.allSatisfy({ $0.isFinite && $0 > 0 }), let longest = lengths.max() else { return nil }
        // A relative tolerance rejects an almost edge-on or numerically unstable
        // projection while retaining small, valid quads for manual presentation.
        let tolerance = max(CGFloat(1e-8), longest * longest * 1e-10)
        guard tolerance.isFinite else { return nil }
        for index in 0..<4 {
            let turn = Self.cross(points[index], points[(index + 1) % 4], points[(index + 2) % 4])
            // Positive winding is clockwise in downward-Y coordinates. Requiring
            // every turn rejects concave, folded, mirrored, and edge-on surfaces.
            guard turn.isFinite, turn > tolerance else { return nil }
        }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let area = Self.polygonArea(points)
        guard area.isFinite, area > tolerance else { return nil }

        // Unit-square-to-quadrilateral homography. Scaling its input columns
        // produces a transform for the surface's actual local width and height.
        let dx1 = topRight.x - bottomRight.x, dx2 = bottomLeft.x - bottomRight.x
        let dy1 = topRight.y - bottomRight.y, dy2 = bottomLeft.y - bottomRight.y
        let dx3 = topLeft.x - topRight.x + bottomRight.x - bottomLeft.x
        let dy3 = topLeft.y - topRight.y + bottomRight.y - bottomLeft.y
        let g: CGFloat, h: CGFloat
        if dx3 == 0 && dy3 == 0 {
            g = 0; h = 0
        } else {
            let determinant = dx1 * dy2 - dx2 * dy1
            guard determinant.isFinite, abs(determinant) > tolerance else { return nil }
            g = (dx3 * dy2 - dx2 * dy3) / determinant
            h = (dx1 * dy3 - dx3 * dy1) / determinant
        }
        // The projective horizon must not cross the displayed local rectangle.
        guard [1, 1 + g, 1 + h, 1 + g + h].allSatisfy({ $0.isFinite && $0 > 1e-10 }) else { return nil }
        let matrix = Matrix(
            m11: (topRight.x - topLeft.x + g * topRight.x) / bounds.width,
            m12: (topRight.y - topLeft.y + g * topRight.y) / bounds.width,
            m14: g / bounds.width,
            m21: (bottomLeft.x - topLeft.x + h * bottomLeft.x) / bounds.height,
            m22: (bottomLeft.y - topLeft.y + h * bottomLeft.y) / bounds.height,
            m24: h / bounds.height,
            m41: topLeft.x,
            m42: topLeft.y
        )
        guard [matrix.m11, matrix.m12, matrix.m14, matrix.m21, matrix.m22, matrix.m24, matrix.m41, matrix.m42].allSatisfy(\.isFinite) else { return nil }
        self.bounds = bounds
        self.matrix = matrix
        self.corners = points
        self.viewport = viewport
        self.area = area
        self.minimumWidth = min(lengths[0], lengths[2])
        self.minimumHeight = min(lengths[1], lengths[3])
    }

    /// YouTube's embedded viewport needs both dimensions to reach 200 points,
    /// with more than half of its actual projected area visible before autoplay.
    /// Opposite edge lengths are checked, not the larger axis-aligned bounds.
    public var isAutoplayEligible: Bool {
        guard minimumWidth >= 200, minimumHeight >= 200 else { return false }
        var visible = corners
        visible = Self.clip(visible, axis: .x, boundary: 0, keepGreater: true)
        visible = Self.clip(visible, axis: .x, boundary: viewport.width, keepGreater: false)
        visible = Self.clip(visible, axis: .y, boundary: 0, keepGreater: true)
        visible = Self.clip(visible, axis: .y, boundary: viewport.height, keepGreater: false)
        return Self.polygonArea(visible) > area / 2
    }

    /// Maps a point inside [0, surfaceSize.width] × [0, surfaceSize.height]
    /// into viewport coordinates using the same transform as the native view.
    public func project(_ point: CGPoint) -> CGPoint {
        let denominator = matrix.m14 * point.x + matrix.m24 * point.y + 1
        return CGPoint(
            x: (matrix.m11 * point.x + matrix.m21 * point.y + matrix.m41) / denominator,
            y: (matrix.m12 * point.x + matrix.m22 * point.y + matrix.m42) / denominator
        )
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        CGFloat(hypot(Double(b.x - a.x), Double(b.y - a.y)))
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        // Translate to the first vertex to avoid cancellation for a quad with
        // a large screen-space translation but a small displayed area.
        return abs((1..<(points.count - 1)).reduce(CGFloat.zero) { sum, index in
            sum + cross(points[0], points[index], points[index + 1])
        }) / 2
    }

    private enum Axis { case x, y }

    /// Sutherland-Hodgman clipping against one of the viewport's four edges.
    private static func clip(_ points: [CGPoint], axis: Axis, boundary: CGFloat, keepGreater: Bool) -> [CGPoint] {
        guard var previous = points.last else { return [] }
        func coordinate(_ point: CGPoint) -> CGFloat { axis == .x ? point.x : point.y }
        func inside(_ point: CGPoint) -> Bool {
            keepGreater ? coordinate(point) >= boundary : coordinate(point) <= boundary
        }
        var result: [CGPoint] = []
        var previousInside = inside(previous)
        for current in points {
            let currentInside = inside(current)
            if currentInside != previousInside {
                let fraction = (boundary - coordinate(previous)) / (coordinate(current) - coordinate(previous))
                var intersection = CGPoint(x: previous.x + fraction * (current.x - previous.x), y: previous.y + fraction * (current.y - previous.y))
                if axis == .x { intersection.x = boundary } else { intersection.y = boundary }
                result.append(intersection)
            }
            if currentInside { result.append(current) }
            previous = current
            previousInside = currentInside
        }
        return result
    }
}
