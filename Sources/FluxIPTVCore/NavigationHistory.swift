import Foundation

/// Screens opened since the home screen, most recent last. A screen appears
/// once: opening it again moves it to the end. Going back therefore never
/// loops between two screens and always ends on the home screen.
public struct FluxNavigationHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var places: [Place] = []

    public init() {}

    public var isEmpty: Bool { places.isEmpty }

    public mutating func visit(_ place: Place) {
        places.removeAll { $0 == place }
        places.append(place)
    }

    /// Screen that Back shows from `current`; nil is the home screen.
    public func previous(from current: Place) -> Place? {
        places.last { $0 != current }
    }

    /// Leaves `current`, recorded or not, and returns the screen to show
    /// again; nil is the home screen.
    @discardableResult public mutating func leave(_ current: Place) -> Place? {
        places.removeAll { $0 == current }
        return places.last
    }

    /// The home screen is the start of every history.
    public mutating func reset() { places.removeAll() }
}
