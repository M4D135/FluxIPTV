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

// "pour le mode souris super mais ajoute plus de choix de pointeurs, de
// taille et de vitesse" (David, 27/11): five speeds, three accelerations,
// six sizes, six shapes and six colours. The values saved before keep their
// names.

/// How far the pointer goes for the same way of the thumb.
public enum FluxPointerSpeed: String, CaseIterable, Identifiable, Sendable {
    case verySlow, slow, normal, fast, veryFast
    public static let storageKey = "fluxiptv.remote.pointerSpeed.v1"
    public static let defaultValue: Self = .normal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .verySlow: "Très lente"
        case .slow: "Lente"
        case .normal: "Normale"
        case .fast: "Rapide"
        case .veryFast: "Très rapide"
        }
    }
    public var gain: Double {
        switch self {
        case .verySlow: 0.5
        case .slow: 0.7
        case .normal: 1
        case .fast: 1.45
        case .veryFast: 2
        }
    }
}

/// How much farther a quick flick takes the pointer than a slow move.
public enum FluxPointerAcceleration: String, CaseIterable, Identifiable, Sendable {
    /// The pointer goes as far as the thumb, quick or slow.
    case none
    /// As on a trackpad: finer when slow, up to twice as far when quick.
    case gentle
    /// Finer still when slow, up to three times as far when quick: a flick
    /// crosses the screen.
    case strong
    public static let storageKey = "fluxiptv.remote.pointerAcceleration.v1"
    public static let defaultValue: Self = .gentle
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "Aucune"
        case .gentle: "Normale"
        case .strong: "Forte"
        }
    }
    /// What the way of the thumb is multiplied by, at `velocity` points per second.
    public func factor(velocity: Double) -> Double {
        guard velocity.isFinite else { return 1 }
        let speed = max(0, velocity)
        switch self {
        case .none: return 1
        case .gentle: return min(2, max(0.75, 0.75 + speed / 1600))
        case .strong: return min(3, max(0.6, 0.6 + speed / 1000))
        }
    }
}

/// The size of the pointer on the screen.
public enum FluxPointerSize: String, CaseIterable, Identifiable, Sendable {
    case tiny, small, normal, large, huge, giant
    public static let storageKey = "fluxiptv.remote.pointerSize.v1"
    public static let defaultValue: Self = .normal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .tiny: "Très petit"
        case .small: "Petit"
        case .normal: "Normal"
        case .large: "Grand"
        case .huge: "Très grand"
        case .giant: "Géant"
        }
    }
    /// Height of the arrow, in the points of a television.
    public var height: Double {
        switch self {
        case .tiny: 26
        case .small: 34
        case .normal: 44
        case .large: 58
        case .huge: 76
        case .giant: 100
        }
    }
}

/// The shape of the pointer.
public enum FluxPointerShape: String, CaseIterable, Identifiable, Sendable {
    /// The arrow of a mouse.
    case arrow
    /// A hand whose finger points, as over a link.
    case hand
    /// A round spot, as a finger leaves.
    case dot
    /// A ring that leaves what it rests on to be seen.
    case ring
    /// A ring crossed by its sights.
    case crosshair
    /// A soft light, as a torch on the screen.
    case halo
    public static let storageKey = "fluxiptv.remote.pointerShape.v1"
    public static let defaultValue: Self = .arrow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .arrow: "Flèche"
        case .hand: "Main"
        case .dot: "Rond"
        case .ring: "Anneau"
        case .crosshair: "Viseur"
        case .halo: "Halo"
        }
    }
    /// Whether the pointer points with a tip, at its top left, rather than
    /// with its middle.
    public var pointsWithTip: Bool { self == .arrow || self == .hand }
}

/// The colour of the pointer, with an edge that sets it off the picture.
public enum FluxPointerColor: String, CaseIterable, Identifiable, Sendable {
    case white, black, cyan, yellow, pink, green
    public static let storageKey = "fluxiptv.remote.pointerColor.v1"
    public static let defaultValue: Self = .white
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .white: "Blanc"
        case .black: "Noir"
        case .cyan: "Cyan"
        case .yellow: "Jaune"
        case .pink: "Rose"
        case .green: "Vert"
        }
    }
    /// Red, green and blue, from 0 to 1.
    public var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: (1, 1, 1)
        case .black: (0.07, 0.07, 0.09)
        case .cyan: (0.28, 0.86, 1)
        case .yellow: (1, 0.84, 0.22)
        case .pink: (1, 0.46, 0.76)
        case .green: (0.38, 0.94, 0.52)
        }
    }
    /// A dark pointer takes a light edge; the others a dark one.
    public var isDark: Bool { self == .black }
}

/// The way of the pointer: the way of the thumb, longer when it goes fast,
/// as on a trackpad, and kept on the screen.
public struct FluxPointerMotion: Equatable, Sendable {
    public var speed: FluxPointerSpeed
    public var acceleration: FluxPointerAcceleration
    public init(speed: FluxPointerSpeed = .defaultValue, acceleration: FluxPointerAcceleration = .defaultValue) {
        self.speed = speed
        self.acceleration = acceleration
    }

    /// Slow, a point of the thumb is under a point of the screen; fast, up
    /// to twice as far, so that a flick crosses the screen.
    public static func acceleration(velocity: Double) -> Double {
        FluxPointerAcceleration.gentle.factor(velocity: velocity)
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
        let gain = speed.gain * acceleration.factor(velocity: velocity)
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

/// The scroll pointer over a list. "sur une liste on passe sur un pointeur
/// défilement au survol et on change le fonctionnement au survol de la zone
/// pour haut et bas, on ressort par droite gauche de la zone, sinon c
/// incontrôlable" (David, 27/11). Over a list the pointer keeps its height,
/// in the middle of the list: up and down the thumb scrolls the list under
/// it, so that the row under the pointer changes and the pointer never runs
/// off the list; across, it goes along the row. Pulled on past the left or
/// the right side, or past the top or the bottom of a list that has already
/// ended, it leaves the list.
public struct FluxPointerRail: Equatable, Sendable {
    /// How far the thumb pulls past a side before the pointer leaves.
    public static let exit = 48.0
    /// A way of the thumb this much more up and down than across only
    /// scrolls, and the other way round only moves: a thumb that drifts a
    /// little neither leaves the row nor scrolls the list.
    public static let dominance = 1.5

    /// Where the pointer stays on a list: away from its top and its bottom,
    /// where a row may show only in part.
    public static func band(_ list: CGRect) -> CGRect {
        guard !list.isNull, !list.isEmpty else { return list }
        return list.insetBy(dx: 0, dy: CGFloat(min(160, Double(list.height) * 0.25)))
    }

    /// The pull past the left (negative) or the right side, and past the top
    /// (negative) or the bottom.
    public private(set) var pullX = 0.0
    public private(set) var pullY = 0.0

    public init() {}

    /// The way of the thumb, split into what moves across and what scrolls.
    public static func split(dx: Double, dy: Double) -> (across: Double, along: Double) {
        guard dx.isFinite, dy.isFinite else { return (0, 0) }
        if abs(dy) >= abs(dx) * dominance { return (0, dy) }
        if abs(dx) >= abs(dy) * dominance { return (dx, 0) }
        return (dx, dy)
    }

    /// `dx`: the way across; `dy`: what is left of the way up and down once
    /// the list has scrolled as far as it goes, `scrolled` whether it
    /// scrolled; `list`: what shows of the list. Returns where the pointer
    /// goes, on the list or out of it, and whether it leaves it.
    public mutating func move(from position: CGPoint, dx: Double, dy: Double, scrolled: Bool,
                              list: CGRect) -> (point: CGPoint, leaves: Bool) {
        guard dx.isFinite, dy.isFinite, !list.isNull, !list.isEmpty else { return (position, false) }
        let band = Self.band(list)
        let minX = Double(list.minX), maxX = Double(list.maxX)
        // Back from a pull, the pull is undone before the pointer moves.
        var x = Double(position.x), way = dx
        if pullX < 0, way > 0 { let back = min(way, -pullX); pullX += back; way -= back }
        if pullX > 0, way < 0 { let back = min(-way, pullX); pullX -= back; way += back }
        x += way
        if x < minX { pullX -= minX - x; x = minX }
        if x > maxX { pullX += x - maxX; x = maxX }
        // A list that scrolled has not ended that way: no pull stands.
        if scrolled { pullY = 0 }
        if (pullY < 0 && dy > 0) || (pullY > 0 && dy < 0) { pullY = 0 }
        pullY += dy
        let y = min(Double(band.maxY), max(Double(band.minY), Double(position.y)))
        if abs(pullX) >= Self.exit {
            let out = pullX < 0 ? minX - 24 : maxX + 24
            self = Self()
            return (CGPoint(x: out, y: y), true)
        }
        if abs(pullY) >= Self.exit {
            let out = pullY < 0 ? Double(list.minY) - 24 : Double(list.maxY) + 24
            self = Self()
            return (CGPoint(x: x, y: out), true)
        }
        return (CGPoint(x: x, y: y), false)
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
