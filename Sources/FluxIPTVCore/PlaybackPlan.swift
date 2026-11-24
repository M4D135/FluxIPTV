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

public enum PlaybackPlan {
    /// Keep native HLS for live TV; prefer VLC for known non-native containers.
    /// If an engine is requested manually, use that engine for all candidates.
    public static func attempts(urls: [URL], preferred: PlaybackEngine? = nil) -> [PlaybackAttempt] {
        var seen = Set<URL>()
        return urls.filter { url in
            (try? IPTVURL.validated(url.absoluteString)) != nil && seen.insert(url).inserted
        }.prefix(3).flatMap { url -> [PlaybackAttempt] in
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
