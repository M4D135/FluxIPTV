import Foundation

/// A marker stores no media URL, account, password or provider information.
/// A crash/force quit during VLC playback can leave it behind. Recovery never
/// overrides persisted preferences permanently; the user explicitly retries VLC.
public struct PlaybackRecovery: Equatable, Sendable {
    public private(set) var active: Bool
    public init(uncleanVLCSession: Bool) { active = uncleanVLCSession }
    public mutating func resumeNormalMode() { active = false }
    public func preferredEngine(_ requested: PlaybackEngine?) -> PlaybackEngine? {
        active ? .native : requested
    }
}
