import Foundation

/// Navigation of the held object, independent of the input device and renderer.
/// The physical Play key is deliberately distinct from Validate/Select.
public struct CaseInspectorNavigation: Sendable {
    public enum Target: String, CaseIterable, Sendable {
        case object, preview, play, dismiss, favorite, more
    }
    public enum Effect: Equatable, Sendable {
        case none
        case focus(Target)
        case rotate(Double)
        case neighbor(Int)
        case activate(Target)
        case close
    }

    public private(set) var target: Target
    private struct DirectionPress: Sendable {
        let action: RemoteAction
        let time: TimeInterval
    }
    private var previousDirection: DirectionPress?
    private static let bottom: [Target] = [.dismiss, .more, .favorite]

    public init(target: Target = .object) { self.target = target }

    /// Pointer/native focus changes also invalidate a pending double press.
    public mutating func focus(_ target: Target) {
        previousDirection = nil
        self.target = target
    }

    public mutating func handle(action: RemoteAction, at time: TimeInterval,
                                repeating: Bool = false) -> Effect {
        if action == .left || action == .right {
            let step = action == .left ? -1 : 1
            if let index = Self.bottom.firstIndex(of: target) {
                return moveFocus(to: Self.bottom[max(0, min(Self.bottom.count - 1, index + step))])
            }
            target = .object
            // Holding a key may keep rotating, but must never change titles.
            if repeating || !time.isFinite {
                previousDirection = nil
                return .rotate(Double(step) * 25)
            }
            if let previousDirection, previousDirection.action == action {
                let interval = time - previousDirection.time
                if interval + 1e-9 >= 0.08 && interval <= 0.30 + 1e-9 {
                    self.previousDirection = nil
                    return .neighbor(step)
                }
            }
            previousDirection = DirectionPress(action: action, time: time)
            return .rotate(Double(step) * 25)
        }

        previousDirection = nil
        switch action {
        case .up:
            return moveFocus(to: target == .preview || target == .play ? .play : .preview)
        case .down:
            return moveFocus(to: target == .play ? .preview : (Self.bottom.contains(target) ? target : .dismiss))
        case .select:
            return target == .object ? moveFocus(to: .preview) : .activate(target)
        case .playPause:
            return .activate(.play)
        case .back, .home:
            return .close
        case .options:
            focus(.more)
            return .activate(.more)
        case .previous:
            return .neighbor(-1)
        case .next:
            return .neighbor(1)
        default:
            return .none
        }
    }

    private mutating func moveFocus(to destination: Target) -> Effect {
        let changed = target != destination
        focus(destination)
        return changed ? .focus(destination) : .none
    }
}
