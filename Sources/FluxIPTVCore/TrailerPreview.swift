import Foundation

public enum TrailerPreviewDelay: Int, CaseIterable, Identifiable, Codable, Sendable {
    case three = 3, five = 5, ten = 10
    public static let storageKey = "fluxiptv.appearance.trailerPreviewDelay"
    public static let automaticKey = "fluxiptv.appearance.automaticTrailerPreview"
    public var id: Int { rawValue }
    public var title: String { "\(rawValue) secondes" }
}

/// Provider links can designate a native stream or a web page. A YouTube page
/// must never be handed to AVPlayer or silently scraped for a different URL.
public enum TrailerPreviewRoute: Equatable, Sendable {
    case unavailable
    case native(URL)
    case external(URL)

    public static func resolve(_ url: URL?) -> TrailerPreviewRoute {
        guard let url, let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return .unavailable }
        let host = (url.host ?? "").lowercased()
        guard !host.isEmpty else { return .unavailable }
        let webHosts = ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "dailymotion.com", "dai.ly"]
        if webHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .external(url) }
        if ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) { return .native(url) }
        return .external(url)
    }
}
