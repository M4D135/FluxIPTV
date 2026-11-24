import Foundation

/// Shared intent vocabulary for the Siri Remote, keyboard, gamepad and simulator.
public enum RemoteAction: String, CaseIterable, Sendable {
    case up, down, left, right, select, back, home, playPause, search
    case rewind, forward, previous, next, fullscreen, volumeUp, volumeDown, mute, options
}

public enum RemoteAppearance: String, CaseIterable, Identifiable, Sendable {
    case black, silver
    public var id: String { rawValue }
    public var title: String { self == .black ? "Noire · 1re génération" : "Aluminium · 2e/3e génération" }
}

public enum RemoteNavigation {
    /// A click on the aluminium ring uses its polar position; the central disc selects.
    /// dx/dy are relative to the center and normalized to the outer radius.
    public static func clickpad(dx: Double, dy: Double, seconds: Double) -> RemoteAction {
        if hypot(dx, dy) <= 0.57 { return seconds >= 0.65 ? .options : .select }
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .down : .up
    }

    /// A focus grid is made of the visible rows only. Stable IDs preserve focus across refreshes.
    public static func move(from current: String?, action: RemoteAction, rows: [[String]]) -> String? {
        let rows = rows.filter { !$0.isEmpty }
        guard let first = rows.first?.first else { return nil }
        guard let current, let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else { return first }
        switch action {
        case .left: return rows[row][max(0, column - 1)]
        case .right: return rows[row][min(rows[row].count - 1, column + 1)]
        case .up, .down:
            let target = max(0, min(rows.count - 1, row + (action == .up ? -1 : 1)))
            return rows[target][min(column, rows[target].count - 1)]
        default: return current
        }
    }

    /// A click selects; a swipe chooses its dominant axis. A long stationary press opens options.
    public static func touch(dx: Double, dy: Double, seconds: Double, threshold: Double = 24) -> RemoteAction {
        if max(abs(dx), abs(dy)) < threshold { return seconds >= 0.65 ? .options : .select }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }
}


/// Precise scrolling is not a click: one direction per stroke, never select.
public struct RemoteScrollNavigation: Sendable {
    private var dx = 0.0, dy = 0.0
    private var dispatched = false
    public init() {}
    public mutating func delta(_ x: Double, _ y: Double) -> RemoteAction? {
        guard !dispatched, x.isFinite, y.isFinite else { return nil }
        dx += x; dy += y
        guard max(abs(dx), abs(dy)) >= 24 else { return nil }
        dispatched = true
        return RemoteNavigation.touch(dx: dx, dy: dy, seconds: 0)
    }
}
