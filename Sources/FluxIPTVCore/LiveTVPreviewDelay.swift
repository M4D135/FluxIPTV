import Foundation

/// TV previews have their own preference, independent of case-back trailers.
public enum LiveTVPreviewDelay: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, three = 3, five = 5, ten = 10
    public static let storageKey = "fluxiptv.liveTV.previewDelay.v1"
    public static let automaticKey = "fluxiptv.liveTV.automaticPreview.v1"
    /// One second everywhere, Apple TV included: « par défaut, aperçu tv
    /// 1s » (David, 26/11). Until the 0.9.3 a television waited three.
    public static let defaultValue: Self = .one
    public static var platformDefault: Self { defaultValue }

    /// The 0.9.3 and before waited three seconds on a television, and the
    /// reset of the settings wrote it: a three saved there was that old
    /// default, not a choice. Runs once.
    public static func migrate(_ defaults: UserDefaults = .standard, television: Bool = Self.television) {
        let done = "fluxiptv.liveTV.previewDelay.migrated.v2"
        guard !defaults.bool(forKey: done) else { return }
        defaults.set(true, forKey: done)
        if television, defaults.object(forKey: storageKey) != nil, defaults.integer(forKey: storageKey) == Self.three.rawValue {
            defaults.removeObject(forKey: storageKey)
        }
    }
    public static var television: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
    public var id: Int { rawValue }
    public var title: String { rawValue == 1 ? "1 seconde" : "\(rawValue) secondes" }
}
