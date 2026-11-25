import Foundation

public enum TrailerPreviewDelay: Int, CaseIterable, Identifiable, Codable, Sendable {
    case one = 1, three = 3, five = 5, ten = 10
    public static let storageKey = "fluxiptv.appearance.trailerPreviewDelay"
    public static let automaticKey = "fluxiptv.appearance.automaticTrailerPreview"
    public var id: Int { rawValue }
    public var title: String { rawValue == 1 ? "1 seconde" : "\(rawValue) secondes" }
}

/// A validated public YouTube identifier. The embedded player consumes this ID;
/// the watch page is never handed to AVPlayer or scraped for media URLs.
public struct YouTubeTrailer: Equatable, Sendable {
    public let videoID: String

    private static let watchHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    private static let shortHosts: Set<String> = ["youtu.be", "www.youtu.be"]
    private static let embedHosts: Set<String> = ["youtube-nocookie.com", "www.youtube-nocookie.com"]

    public init?(videoID: String) {
        guard videoID.utf8.count == 11, videoID.utf8.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        }) else { return nil }
        self.videoID = videoID
    }

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == (scheme == "https" ? 443 : 80),
              let host = url.host?.lowercased(), Self.isYouTubeHost(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        if Self.shortHosts.contains(host), path.count == 1 {
            candidate = path[0]
        } else if Self.watchHosts.contains(host), path == ["watch"] {
            // Ambiguous duplicate parameters must not select an arbitrary film.
            let identifiers = (components.queryItems ?? []).filter { $0.name == "v" }
            candidate = identifiers.count == 1 ? identifiers[0].value : nil
        } else if path.count == 2, !Self.shortHosts.contains(host),
                  (path[0] == "embed" || (Self.watchHosts.contains(host) && ["shorts", "live", "v"].contains(path[0]))) {
            candidate = path[1]
        } else {
            candidate = nil
        }
        guard let candidate else { return nil }
        self.init(videoID: candidate)
    }

    /// Both URLs are valid by construction: identifiers contain only eleven URL-safe ASCII bytes.
    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }
    public var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")! }

    static func isYouTubeHost(_ host: String) -> Bool {
        watchHosts.contains(host.lowercased()) || shortHosts.contains(host.lowercased()) || embedHosts.contains(host.lowercased())
    }
}

/// Provider links designate a native stream, an official YouTube embed, or an
/// unsupported web page that can be opened explicitly by the user.
public enum TrailerPreviewRoute: Equatable, Sendable {
    case unavailable
    case native(URL)
    case youtube(YouTubeTrailer)
    case external(URL)

    public static func resolve(_ url: URL?) -> TrailerPreviewRoute {
        guard let url, let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil else { return .unavailable }
        let host = (url.host ?? "").lowercased()
        guard !host.isEmpty else { return .unavailable }
        if let youtube = YouTubeTrailer(url: url) { return .youtube(youtube) }
        let webHosts = ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "dailymotion.com", "dai.ly"]
        if webHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .external(url) }
        if ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) { return .native(url) }
        return .external(url)
    }
}
