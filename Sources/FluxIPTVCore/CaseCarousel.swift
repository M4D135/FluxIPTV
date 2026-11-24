import Foundation

/// A fixed five-object window, independent of the size of the catalogue.
public enum CaseCarousel {
    public static let radius = 2
    public static let offsets = [-2, -1, 1, 2]

    /// Direct shortcuts while the closed case is selected. Episode and
    /// explicit command navigation are separate, visibly labelled contexts.
    public static func command(for action: RemoteAction, series: Bool) -> CaseFaceLayout.Action? {
        switch action {
        case .left,.previous: return .previous
        case .right,.next: return .next
        case .back,.home: return .close
        case .up,.select,.playPause: return series ? .episodes : .play
        default: return nil
        }
    }

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
        // A narrow view overlaps the side sleeves more; it never shrinks the
        // central poster merely to make four thumbnails equally prominent.
        let spread = min(1, max(0.18, aspect / (16.0 / 9.0)))
        let small = min(1, max(0.40, aspect / 1.45))
        return offsets.map { offset in
            let far = abs(offset) == 2
            let sign = offset < 0 ? -1.0 : 1.0
            return Placement(offset: offset,
                x: sign * (far ? (editorial ? 2.64 : 2.72) : (editorial ? 1.67 : 1.76)) * spread,
                y: far ? -0.22 : -0.12,
                depth: far ? (editorial ? 1.95 : 1.80) : (editorial ? 1.18 : 1.04),
                scale: (far ? (editorial ? 0.30 : 0.33) : (editorial ? 0.43 : 0.46)) * small,
                angle: -sign * (far ? 30 : (editorial ? 16 : 22)))
        }
    }

    public static let collectorHalfDepth = 0.30
    public static let collectorOpeningAngle = -155.0

    public static func distance(aspect rawAspect: Double, editorial: Bool, collector: Bool = false, open: Bool = false) -> Double {
        let aspect = rawAspect.isFinite ? max(0.15, rawAspect) : 16.0 / 9.0
        let slope = tan(35 * Double.pi / 360)
        let front = collector ? collectorHalfDepth + 0.08 : 0.14
        // The hinged lid extends towards the eye when the collector is open.
        let forward = open ? front + 1.94 * sin(25 * Double.pi / 180) : front
        var distance = max(1.5 / (0.90 * slope) + forward,
                           (open ? 2.25 : 1.04) / (0.94 * aspect * slope) + forward)
        for item in placements(aspect: aspect, editorial: editorial) {
            let outer = abs(item.x) + item.scale * 1.04
            let nearest = -item.depth + item.scale * 0.70
            distance = max(distance, outer / (0.96 * aspect * slope) + nearest)
        }
        return distance
    }
}
