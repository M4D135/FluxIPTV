import Foundation

/// Screens opened since the home screen, in the order they were opened, the
/// one on screen last: the Back of a web browser. Going back shows the screen
/// that came before, then the one before that, and at last the home screen,
/// where every history starts again.
public struct FluxNavigationHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var places: [Place] = []

    /// Longer than this, a history is a pendulum between screens rather than
    /// a path worth retracing: the oldest steps are forgotten.
    public static var capacity: Int { 24 }

    public init() {}

    public var isEmpty: Bool { places.isEmpty }

    /// Opens `place`. Showing again the screen already on top adds no step.
    public mutating func visit(_ place: Place) {
        guard places.last != place else { return }
        places.append(place)
        if places.count > Self.capacity { places.removeFirst(places.count - Self.capacity) }
    }

    /// Screen that Back shows from `current`; nil is the home screen.
    public func previous(from current: Place) -> Place? {
        places.last == current ? places.dropLast().last : places.last
    }

    /// Leaves `current`, recorded or not, and returns the screen to show
    /// again; nil is the home screen.
    @discardableResult public mutating func leave(_ current: Place) -> Place? {
        if places.last == current { places.removeLast() }
        return places.last
    }

    /// The home screen is the start of every history.
    public mutating func reset() { places.removeAll() }
}
