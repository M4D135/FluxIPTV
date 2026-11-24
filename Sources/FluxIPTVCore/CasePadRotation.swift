import Foundation

/// Shared input for precise scrolling, touchpad pan and the virtual remote.
public enum CasePadInput: Equatable, Sendable {
    case delta(Double, Double)
    case translation(Double, Double)
    case finish
    case finishTranslation(Double, Double)
    case cancel
}

/// One gesture, no frame timer and no dependency on SceneKit. The renderer
/// displays the pose directly while the user moves, then animates the final pose.
public struct CasePadRotation: Sendable {
    public struct Pose: Equatable, Sendable {
        public let yaw: Double
        public let pitch: Double
        public init(yaw: Double, pitch: Double) { self.yaw = yaw; self.pitch = pitch }
    }
    public let origin: Pose
    private var x = 0.0, y = 0.0
    private var lastDX = 0.0
    public private(set) var pose: Pose
    public init(yaw: Double, pitch: Double) {
        let safeYaw = yaw.isFinite ? yaw : 0
        let safePitch = pitch.isFinite ? pitch : 0
        origin = Pose(yaw: safeYaw, pitch: safePitch)
        pose = origin
    }
    public mutating func delta(_ dx: Double, _ dy: Double) -> Pose {
        guard dx.isFinite, dy.isFinite else { return pose }
        return translation(x + dx, y + dy)
    }
    public mutating func translation(_ dx: Double, _ dy: Double) -> Pose {
        guard dx.isFinite, dy.isFinite else { return pose }
        // Remain responsive on a short stroke, but reject absurd input values.
        let nx = max(-32_000, min(32_000, dx)), ny = max(-32_000, min(32_000, dy))
        lastDX = nx - x; x = nx; y = ny
        pose = Pose(yaw: origin.yaw + x * 1.35, pitch: max(-75, min(75, origin.pitch + y * 0.62)))
        return pose
    }
    public func finish(reduceMotion: Bool = false) -> Pose {
        // Pure vertical strokes keep the desired tilt. Horizontal movement
        // settles on the nearest printable face, with a small bounded bias.
        guard abs(x) >= 9, abs(x) >= abs(y) * 0.65 else { return pose }
        let inertia = reduceMotion ? 0 : max(-24, min(24, lastDX * 2.2))
        let directionalBias = abs(x) >= 35 ? (x > 0 ? 30.0 : -30.0) : 0
        let target = ((pose.yaw + inertia + directionalBias) / 180).rounded() * 180
        return Pose(yaw: target, pitch: 0)
    }
}
