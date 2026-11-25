/// Decides when a trailer's rendered back face is visible without chattering
/// at the sleeve's edge. Feed the rendered back normal dotted with the unit
/// direction to the camera, never the target Euler angles of an animation.
public struct CasePreviewFacing: Equatable, Sendable {
    public private(set) var isBackFacing = false

    public init() {}

    /// Pause as soon as the back faces away; require a small visible angle to
    /// resume. Inside the positive dead band, retain the previous decision.
    @discardableResult
    public mutating func update(backFacing: Double) -> Bool {
        if !backFacing.isFinite || backFacing <= 0 {
            isBackFacing = false
        } else if backFacing >= 0.06 {
            isBackFacing = true
        }
        return isBackFacing
    }
}
