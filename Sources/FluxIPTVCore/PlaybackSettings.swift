import Foundation

public struct PlaybackSettings: Codable, Equatable, Sendable {
    public enum Engine: String, Codable, CaseIterable, Sendable {
        case automatic, native, vlc
        public var title: String { switch self { case .automatic: "Automatique"; case .native: "Apple AVPlayer"; case .vlc: "VLC" } }
        public var preferred: PlaybackEngine? { switch self { case .automatic: nil; case .native: .native; case .vlc: .vlc } }
    }
    public enum Profile: String, CaseIterable, Sendable {
        case fast, balanced, stable
        public var title: String { switch self { case .fast: "Zapping rapide"; case .balanced: "Équilibré"; case .stable: "Connexion instable" } }
        public var settings: PlaybackSettings {
            switch self {
            case .fast: PlaybackSettings(cacheMS: 700, timeout: 12, stallTimeout: 12, retries: 1)
            case .balanced: PlaybackSettings()
            case .stable: PlaybackSettings(cacheMS: 5000, timeout: 40, stallTimeout: 30, retries: 3)
            }
        }
    }
    public var engine: Engine = .automatic
    public var cacheMS = 1500
    public var timeout = 20
    public var stallTimeout = 20
    public var retries = 2
    public var hardware = true
    public var nativeWait = true
    public var skipSeconds = 15
    public var bitrateMbps = 0
    public var reconnectLive = true
    public init(cacheMS: Int = 1500, timeout: Int = 20, stallTimeout: Int = 20, retries: Int = 2) {
        self.cacheMS = cacheMS; self.timeout = timeout; self.stallTimeout = stallTimeout; self.retries = retries
    }
    public var normalized: Self {
        var s = self
        s.cacheMS = min(15000, max(250, cacheMS)); s.timeout = min(90, max(5, timeout)); s.stallTimeout = min(90, max(5, stallTimeout)); s.retries = min(5, max(0, retries)); s.skipSeconds = min(120, max(5, skipSeconds)); s.bitrateMbps = min(100, max(0, bitrateMbps)); return s
    }
    public var vlcOptions: [String] { let s = normalized; return [":network-caching=\(s.cacheMS)", ":avcodec-hw=\(s.hardware ? "any" : "none")"] }
    public var nativeBufferSeconds: Double { Double(normalized.cacheMS) / 1000 }
    public var nativePeakBitrate: Double { Double(normalized.bitrateMbps) * 1_000_000 }
    public func canReconnect(isLive: Bool, attempt: Int) -> Bool { isLive && reconnectLive && attempt < normalized.retries }
}
