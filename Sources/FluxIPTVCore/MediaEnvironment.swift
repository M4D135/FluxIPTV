import Foundation

/// The place belongs to the content category. Layout concepts never remap it.
public enum MediaEnvironment: String, CaseIterable, Codable, Identifiable, Sendable {
    case cinema, videoClub, livingRoom

    public var id: String { rawValue }
    public init(kind: IPTVMediaKind) {
        switch kind { case .movie: self = .cinema; case .series: self = .videoClub; case .live: self = .livingRoom }
    }
    public var kind: IPTVMediaKind {
        switch self { case .cinema: .movie; case .videoClub: .series; case .livingRoom: .live }
    }
    public var title: String {
        switch self { case .cinema: "Cinéma"; case .videoClub: "Vidéoclub"; case .livingRoom: "Salon TV" }
    }
    public var subtitle: String {
        switch self {
        case .cinema: "Les films à l’affiche, dans un hall de cinéma."
        case .videoClub: "Les séries et leurs saisons, parmi les coffrets du vidéoclub."
        case .livingRoom: "Les chaînes en direct, dans un salon avec grand téléviseur."
        }
    }
    public var symbol: String {
        switch self { case .cinema: "film"; case .videoClub: "film.stack"; case .livingRoom: "tv" }
    }
    /// Filename without extension; matches the reproducible room render recipes.
    public func assetName(theme: VideoClubTheme) -> String { "\(rawValue)-\(theme.rawValue)" }
}

/// Stable keys keep the three theme choices independent and migrate old installs
/// without changing a choice already made in a newer version of the app.
public enum MediaThemePreferences {
    public static let cinemaKey = "fluxiptv.appearance.cinemaTheme"
    public static let seriesKey = "fluxiptv.appearance.seriesTheme"
    public static let tvKey = "fluxiptv.appearance.tvTheme"
    public static let legacyClubKey = "fluxiptv.appearance.theme"

    public static func key(for kind: IPTVMediaKind) -> String {
        switch kind { case .movie: cinemaKey; case .series: seriesKey; case .live: tvKey }
    }

    /// Run before creating appearance views. No migration marker is needed:
    /// each absent key is filled once, while explicit existing values survive.
    public static func migrateLegacy(in defaults: UserDefaults = .standard) {
        let inherited = defaults.string(forKey: legacyClubKey).flatMap(VideoClubTheme.init(rawValue:)) ?? .neo90
        for key in [cinemaKey, seriesKey] where defaults.object(forKey: key) == nil {
            defaults.set(inherited.rawValue, forKey: key)
        }
        if defaults.object(forKey: tvKey) == nil { defaults.set(VideoClubTheme.neo90.rawValue, forKey: tvKey) }
    }

    public static func theme(for kind: IPTVMediaKind, in defaults: UserDefaults = .standard) -> VideoClubTheme {
        let selectedKey = key(for: kind)
        if let stored = defaults.object(forKey: selectedKey) {
            return (stored as? String).flatMap(VideoClubTheme.init(rawValue:)) ?? .neo90
        }
        if kind != .live {
            return defaults.string(forKey: legacyClubKey).flatMap(VideoClubTheme.init(rawValue:)) ?? .neo90
        }
        return .neo90
    }
}
