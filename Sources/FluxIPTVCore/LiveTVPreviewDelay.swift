/// TV previews have their own preference, independent of case-back trailers.
public enum LiveTVPreviewDelay: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, three = 3, five = 5, ten = 10
    public static let storageKey = "fluxiptv.liveTV.previewDelay.v1"
    public static let automaticKey = "fluxiptv.liveTV.automaticPreview.v1"
    public static let defaultValue: Self = .three
    public var id: Int { rawValue }
    public var title: String { rawValue == 1 ? "1 seconde" : "\(rawValue) secondes" }
}
