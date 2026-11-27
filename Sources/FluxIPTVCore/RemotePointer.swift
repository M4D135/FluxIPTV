import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How the remote of an Apple TV goes through a screen. "un mode pointeur
/// souris avec la télécommande appletv pavé tactile, faut pouvoir choisir
/// mode classique ou mode souris, soit dans option soit un système facile
/// pour basculer, voire les deux" (David, 27/11): both, the settings and
/// Play/Pause held down.
public enum FluxRemoteMode: String, CaseIterable, Identifiable, Sendable {
    /// The focus of tvOS: a swipe goes from one control to the next.
    case classic
    /// A pointer follows the thumb on the touch surface; a click presses
    /// what it rests on.
    case pointer

    public static let storageKey = "fluxiptv.remote.mode.v1"
    public static let defaultValue: Self = .classic
    /// Whether Play/Pause held down goes from one mode to the other.
    public static let toggleKey = "fluxiptv.remote.playPauseToggles.v1"
    public static let toggleDefault = true
    /// How long Play/Pause is held to change the mode.
    public static let holdDuration: TimeInterval = 0.7
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: "Classique"
        case .pointer: "Souris"
        }
    }
    public var subtitle: String {
        switch self {
        case .classic: "Un glissement va d’un élément au suivant."
        case .pointer: "Un pointeur suit le pouce sur le pavé ; un clic appuie sur ce qu’il survole."
        }
    }
    public var symbol: String {
        switch self {
        case .classic: "square.grid.2x2"
        case .pointer: "cursorarrow"
        }
    }
    public var other: Self { self == .classic ? .pointer : .classic }
}

/// How far the pointer goes for the same way of the thumb.
public enum FluxPointerSpeed: String, CaseIterable, Identifiable, Sendable {
    case slow, normal, fast
    public static let storageKey = "fluxiptv.remote.pointerSpeed.v1"
    public static let defaultValue: Self = .normal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .slow: "Lente"
        case .normal: "Normale"
        case .fast: "Rapide"
        }
    }
    public var gain: Double {
        switch self {
        case .slow: 0.7
        case .normal: 1
        case .fast: 1.45
        }
    }
}

/// The size of the pointer on the screen.
public enum FluxPointerSize: String, CaseIterable, Identifiable, Sendable {
    case small, normal, large
    public static let storageKey = "fluxiptv.remote.pointerSize.v1"
    public static let defaultValue: Self = .normal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .small: "Petit"
        case .normal: "Normal"
        case .large: "Grand"
        }
    }
    /// Height of the arrow, in the points of a television.
    public var height: Double {
        switch self {
        case .small: 34
        case .normal: 44
        case .large: 58
        }
    }
}

/// The shape of the pointer.
public enum FluxPointerShape: String, CaseIterable, Identifiable, Sendable {
    /// The arrow of a mouse.
    case arrow
    /// A round spot, as a finger leaves.
    case dot
    public static let storageKey = "fluxiptv.remote.pointerShape.v1"
    public static let defaultValue: Self = .arrow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .arrow: "Flèche"
        case .dot: "Rond"
        }
    }
}

/// The way of the pointer: the way of the thumb, longer when it goes fast,
/// as on a trackpad, and kept on the screen.
public struct FluxPointerMotion: Equatable, Sendable {
    public var speed: FluxPointerSpeed
    public init(speed: FluxPointerSpeed = .defaultValue) { self.speed = speed }

    /// Slow, a point of the thumb is under a point of the screen; fast, up
    /// to twice as far, so that a flick crosses the screen.
    public static func acceleration(velocity: Double) -> Double {
        guard velocity.isFinite else { return 1 }
        return min(2, max(0.75, 0.75 + max(0, velocity) / 1600))
    }

    /// `dx`, `dy`: the way of the thumb since its last report, in the points
    /// of the touch surface; `velocity`: its speed, in points per second.
    /// Plain numbers, not a `CGVector`: the tests of the core run on Linux,
    /// where Foundation has points and rectangles but no vectors.
    public func step(from position: CGPoint, dx: Double, dy: Double, velocity: Double, in bounds: CGRect) -> CGPoint {
        Self.clamp(move(from: position, dx: dx, dy: dy, velocity: velocity), to: bounds)
    }

    /// The same way, not yet kept on the screen: a page that the pointer
    /// pushes takes what goes beyond its edge (`FluxPointerScroll`).
    public func move(from position: CGPoint, dx: Double, dy: Double, velocity: Double) -> CGPoint {
        guard dx.isFinite, dy.isFinite else { return position }
        let gain = speed.gain * Self.acceleration(velocity: velocity)
        return CGPoint(x: Double(position.x) + dx * gain, y: Double(position.y) + dy * gain)
    }

    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        guard !bounds.isNull, !bounds.isEmpty else { return point }
        return CGPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
    }
}

/// What the pointer rests on, among the frames of the controls near it.
public enum FluxPointerTarget {
    /// The smallest frame that holds the point: a button on a panel before
    /// the panel. Without one, the nearest frame within `tolerance`, so that
    /// the narrow gap between two titles does not lose the selection.
    public static func pick(_ point: CGPoint, frames: [CGRect], tolerance: Double = 0) -> Int? {
        var best: (index: Int, area: Double)?
        for (index, frame) in frames.enumerated() where !frame.isNull && !frame.isEmpty && frame.contains(point) {
            let area = Double(frame.width * frame.height)
            if best == nil || area < best!.area { best = (index, area) }
        }
        if let best { return best.index }
        guard tolerance > 0 else { return nil }
        var nearest: (index: Int, distance: Double)?
        for (index, frame) in frames.enumerated() where !frame.isNull && !frame.isEmpty {
            let dx = max(Double(frame.minX - point.x), 0, Double(point.x - frame.maxX))
            let dy = max(Double(frame.minY - point.y), 0, Double(point.y - frame.maxY))
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= tolerance, nearest == nil || distance < nearest!.distance { nearest = (index, distance) }
        }
        return nearest?.index
    }

    /// Whether the control that has the focus, drawn at `focused`, is the
    /// one the pointer rests on, at `target`. The system draws a focused
    /// control a little larger, and a list may show only part of a row; a
    /// panel that holds the control is not the control.
    public static func same(_ focused: CGRect, _ target: CGRect) -> Bool {
        guard !focused.isNull, !target.isNull, !focused.isEmpty, !target.isEmpty else { return false }
        let shared = focused.intersection(target)
        guard !shared.isNull, !shared.isEmpty else { return false }
        let area = Double(shared.width * shared.height)
        return area >= 0.6 * Double(target.width * target.height)
            && area >= 0.4 * Double(focused.width * focused.height)
    }
}

/// A page longer than the screen, as a page of the settings. Pushed against
/// the top or the bottom of what shows of it, the pointer stays at that edge
/// and the page scrolls by the rest of the way; once the page ends, the
/// pointer goes on, out of it. Coming from outside, it enters freely.
public enum FluxPointerScroll {
    /// How far inside the edge the pointer stays while it pushes the page.
    public static let margin = 8.0

    /// `position`: where the pointer is; `wanted`: where the thumb takes it;
    /// `page`: what shows of the page; `above`, `below`: how far the page
    /// can still scroll up and down. Returns where the pointer goes, and how
    /// far the page scrolls, down when positive.
    public static func push(from position: CGPoint, to wanted: CGPoint, page: CGRect,
                            above: Double, below: Double) -> (point: CGPoint, scroll: Double) {
        guard !page.isNull, !page.isEmpty, page.contains(position) else { return (wanted, 0) }
        let from = Double(position.y), to = Double(wanted.y)
        let bottom = Double(page.maxY) - margin, top = Double(page.minY) + margin
        if to > from, to > bottom, below > 0 {
            let stop = max(from, bottom)
            let scroll = min(to - stop, below)
            return (CGPoint(x: Double(wanted.x), y: stop + (to - stop - scroll)), scroll)
        }
        if to < from, to < top, above > 0 {
            let stop = min(from, top)
            let scroll = min(stop - to, above)
            return (CGPoint(x: Double(wanted.x), y: stop - (stop - to - scroll)), -scroll)
        }
        return (wanted, 0)
    }
}
