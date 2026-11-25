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
    public static let collectorOpeningAngle = -155.0

    public static func distance(aspect rawAspect: Double, editorial: Bool, collector: Bool = false,
                                open: Bool = false, format: CasePackageFormat = .dvd) -> Double {
        let aspect = rawAspect.isFinite ? max(0.15, rawAspect) : 16.0 / 9.0
        let slope = tan(35 * Double.pi / 360)
        let halfWidth = Double(format.halfWidth), halfHeight = Double(format.halfHeight)
        let front = Double(format.halfDepth(collector:collector)) + (collector ? 0.08 : 0)
        // The hinged lid extends towards the eye when the collector is open.
        let forward = open ? front + 2 * halfWidth * sin(25 * Double.pi / 180) : front
        // Only the held object controls the zoom. Shelf neighbors may continue
        // beyond the screen edges, like the rest of a physical row of cases.
        let distance = max(halfHeight / ((open ? 0.92 : 0.96) * slope) + forward,
                           (open ? 2.25 * halfWidth : halfWidth + 0.02) / (0.96 * aspect * slope) + forward)
        return distance
    }
}
