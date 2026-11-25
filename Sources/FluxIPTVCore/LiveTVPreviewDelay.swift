/// TV previews have their own preference, independent of case-back trailers.
public enum LiveTVPreviewDelay: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, three = 3, five = 5, ten = 10
    public static let storageKey = "fluxiptv.liveTV.previewDelay.v1"
    public static let automaticKey = "fluxiptv.liveTV.automaticPreview.v1"
    public static let defaultValue: Self = .three
    /// A pointer chooses a channel deliberately; a remote crosses many tiles
    /// on its way, so Apple TV keeps the longer default.
    public static var platformDefault: Self {
        #if os(tvOS)
        .three
        #else
        .one
        #endif
    }
    public var id: Int { rawValue }
    public var title: String { rawValue == 1 ? "1 seconde" : "\(rawValue) secondes" }
}
