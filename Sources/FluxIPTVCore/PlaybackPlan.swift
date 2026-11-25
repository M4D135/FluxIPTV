import Foundation

/// Only HTTP(S) media URLs supplied by the user's playlist or Xtream service.
/// No URLs or credentials are persisted by the player.
public enum PlaybackEngine: String, CaseIterable, Sendable {
    case native, vlc
    public var title: String { self == .native ? "Apple AVPlayer" : "VLC" }
}

public struct PlaybackAttempt: Equatable, Sendable {
    public let url: URL
    public let engine: PlaybackEngine
}

/// Labels deliberately contain no part of an authenticated address.
public struct PlaybackVariant: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
}

public enum PlaybackPlan {
    /// Share one bounded candidate list between playback and an explicit hand-off.
    public static func candidateURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return Array(urls.filter { url in
            (try? IPTVURL.validated(url.absoluteString)) != nil && seen.insert(url).inserted
        }.prefix(3))
    }

    public static func variants(urls: [URL]) -> [PlaybackVariant] {
        candidateURLs(urls).enumerated().map { index, url in
            PlaybackVariant(id: index, title: variantTitle(url: url, index: index))
        }
    }

    public static func variantTitle(url: URL, index: Int) -> String {
        // Never echo arbitrary extensions: a provider can put credentials or
        // tokens in any URL component, including the last path component.
        let format: String
        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "m3u8": format = "HLS"
        case "mp4", "m4v", "mov", "mkv", "avi", "ts", "m2ts", "webm",
             "flv", "wmv", "mpg", "mpeg", "vob", "ac3", "mp3", "aac",
             "m4a", "ogg", "wav", "flac":
            format = fileExtension.uppercased()
        default: format = "format non indiqué"
        }
        return "Adresse \(index + 1) · \(format)"
    }

    /// Keep native HLS for live TV; prefer VLC for known non-native containers.
    /// If an engine is requested manually, use that engine for all candidates.
    public static func attempts(urls: [URL], preferred: PlaybackEngine? = nil) -> [PlaybackAttempt] {
        candidateURLs(urls).flatMap { url -> [PlaybackAttempt] in
            let ext = url.pathExtension.lowercased()
            let engines: [PlaybackEngine]
            if let preferred { engines = [preferred] }
            else if ["mkv", "avi", "ts", "m2ts", "webm", "flv", "wmv", "mpg", "mpeg", "vob", "ac3"].contains(ext) { engines = [.vlc, .native] }
            else { engines = [.native, .vlc] }
            return engines.map { PlaybackAttempt(url: url, engine: $0) }
        }
    }

    /// The standard Xtream URL is tried first. A provider-supplied direct_source
    /// can be used as an alternate. Guess MKV only if the API omitted its extension.
    public static func urls(server: URL, username: String, password: String, item: IPTVItem, liveExtension: String) -> [URL] {
        guard !item.isSeriesCollection else { return [] }
        var candidates: [URL] = []
        if let standard = XtreamClient.streamURL(server: server, username: username, password: password, item: item, liveExtension: liveExtension) {
            candidates.append(standard)
        }
        if let direct = item.directURL, (try? IPTVURL.validated(direct.absoluteString)) != nil { candidates.append(direct) }
        if item.kind != .live, item.fileExtension == nil, let standard = candidates.first,
           standard.pathExtension.lowercased() == "mp4", item.xtreamStreamID != nil {
            candidates.append(standard.deletingPathExtension().appendingPathExtension("mkv"))
        }
        var seen = Set<URL>()
        return candidates.filter { seen.insert($0).inserted }
    }
}
