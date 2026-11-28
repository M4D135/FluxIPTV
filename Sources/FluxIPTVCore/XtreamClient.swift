import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Small client for the conventional Xtream-compatible Player API.
/// The service is supplied by the user; no provider is bundled with this app.
public struct XtreamClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchCatalog(
        server: URL, username: String, password: String, sourceID: UUID
    ) async throws -> [IPTVItem] {
        let auth = try await request(server: server, username: username, password: password, action: nil)
        guard let user = auth as? [String: Any],
              let info = user["user_info"] as? [String: Any] else {
            throw IPTVError.invalidResponse
        }
        guard Self.string(info["auth"]) == "1" else { throw IPTVError.authenticationFailed }

        // Each section is read as soon as its answers arrive, beside the
        // others, and its answers are let go then: the three were kept until
        // the last had arrived, then read one after the other.
        async let live = section(server: server, username: username, password: password, streams: "get_live_streams",
                                 categories: "get_live_categories", sourceID: sourceID, kind: .live)
        // Not all Xtream-compatible services expose a VOD endpoint.
        async let movies = section(server: server, username: username, password: password, streams: "get_vod_streams",
                                   categories: "get_vod_categories", sourceID: sourceID, kind: .movie)
        async let series = section(server: server, username: username, password: password, streams: "get_series",
                                   categories: "get_series_categories", sourceID: sourceID, kind: .series)
        let parts = await [live, movies, series]
        // The catalogue keeps this array: joined with `+`, its capacity grew to
        // 147 452 titles for 92 000, some 17 MB never used.
        var result: [IPTVItem] = []
        result.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for part in parts { result += part }
        try Task.checkCancellation()
        if result.isEmpty { throw IPTVError.emptyCatalog }
        return result
    }

    /// The titles of one section; a section the server does not answer is empty.
    private func section(server: URL, username: String, password: String, streams: String, categories: String,
                         sourceID: UUID, kind: IPTVMediaKind) async -> [IPTVItem] {
        async let list = request(server: server, username: username, password: password, action: streams)
        async let groups = request(server: server, username: username, password: password, action: categories)
        let object = (try? await list) ?? []
        let names = (try? await groups) ?? []
        return Self.decodeItems(object, categories: names, sourceID: sourceID, kind: kind)
    }

    public func fetchSeasons(server: URL, username: String, password: String, series: IPTVItem) async throws -> [IPTVSeason] {
        guard series.isSeriesCollection, let seriesID = series.xtreamStreamID else { throw IPTVError.invalidResponse }
        let response = try await request(server: server, username: username, password: password,
                                         action: "get_series_info", parameters: [URLQueryItem(name: "series_id", value: seriesID)])
        guard let response = response as? [String: Any], response["episodes"] != nil else { throw IPTVError.invalidResponse }
        return Self.decodeSeasons(response, series: series)
    }

    public func fetchDetails(server: URL, username: String, password: String, item: IPTVItem) async throws -> IPTVDetails {
        guard let id = item.xtreamStreamID, item.kind == .movie || item.isSeriesCollection else { return item.details }
        let response = try await request(server: server, username: username, password: password, action: item.isSeriesCollection ? "get_series_info" : "get_vod_info", parameters: [URLQueryItem(name: item.isSeriesCollection ? "series_id" : "vod_id", value: id)])
        guard let object = response as? [String:Any] else { throw IPTVError.invalidResponse }
        let info = object["info"] as? [String:Any] ?? [:]
        let data = object["movie_data"] as? [String:Any] ?? [:]
        return Self.details(info).fillingMissing(from: Self.details(data)).fillingMissing(from: item.details)
    }

    static func details(_ info: [String:Any]) -> IPTVDetails {
        func value(_ keys: String...) -> String? {
            for key in keys {
                if let text = string(info[key])?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !isNull(text) {
                    return native(capped(text))
                }
            }
            return nil
        }
        // An empty, zero, or malformed first field must not hide a valid second
        // field. Prefer a playable stream/embed over an external-page fallback.
        let trailer: URL? = {
            var external: URL?
            for key in ["trailer_url", "youtube_trailer", "trailer"] {
                guard let raw = value(key) else { continue }
                if let youtube = YouTubeTrailer(videoID: raw) { return youtube.watchURL }
                guard let url = try? IPTVURL.validated(raw) else { continue }
                switch TrailerPreviewRoute.resolve(url) {
                case .native:
                    return url
                case .youtube(let youtube):
                    return youtube.watchURL
                case .external:
                    // A YouTube channel/search page or invalid ID is not a trailer.
                    if !YouTubeTrailer.isYouTubeHost(url.host ?? ""), external == nil { external = url }
                case .unavailable:
                    break
                }
            }
            return external
        }()
        return IPTVDetails(synopsis: value("plot","description","overview"), year: value("year","releaseDate","release_date","releasedate","air_date"), duration: value("duration","episode_run_time"), rating: value("rating","rating_5based"), genre: value("genre"), cast: value("cast","actors"), director: value("director","directors"), trailerURL: trailer)
    }

    private func request(server: URL, username: String, password: String, action: String?, parameters: [URLQueryItem] = []) async throws -> Any {
        guard let scheme = server.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              server.host != nil else { throw IPTVError.invalidURL }
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        let path = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + (path.hasSuffix("player_api.php") ? path :
            (path.isEmpty ? "player_api.php" : path + "/player_api.php"))
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ] + (action.map { [URLQueryItem(name: "action", value: $0)] } ?? []) + parameters
        // PHP query parsing treats a bare plus as a space; preserve literal plus signs.
        if let query = components?.percentEncodedQuery {
            components?.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components?.url else { throw IPTVError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IPTVError.invalidResponse }
        if action == nil && (http.statusCode == 401 || http.statusCode == 403) { throw IPTVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else { throw IPTVError.serverError(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw IPTVError.invalidResponse
        }
        return json
    }

    static func decodeItems(
        _ object: Any, categories: Any, sourceID: UUID, kind: IPTVMediaKind
    ) -> [IPTVItem] {
        guard let streams = object as? [[String: Any]] else { return [] }
        var labels: [String: String] = [:]
        for category in (categories as? [[String: Any]]) ?? [] {
            guard let id = string(category["category_id"]),
                  let title = category["category_name"] as? String else { continue }
            labels[id] = native(title)
        }
        var seen = Set<String>()
        let idPrefix = "\(sourceID.uuidString):\(kind.rawValue):"
        return streams.compactMap { stream in
            guard let streamID = string(stream[kind == .series ? "series_id" : "stream_id"]), !streamID.isEmpty else { return nil }
            let title = (stream["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty, seen.insert(streamID).inserted else { return nil }
            let category = string(stream["category_id"]).flatMap { labels[$0] } ?? "Sans catégorie"
            let fileExtension: String? = kind == .movie ? sanitizedExtension(stream["container_extension"] as? String) : nil
            return IPTVItem(
                id: idPrefix + streamID,
                sourceID: sourceID,
                name: native(title),
                group: category,
                logoURL: IPTVURL.remoteImage(stream["stream_icon"] as? String) ?? IPTVURL.remoteImage(stream["cover"] as? String),
                kind: kind,
                directURL: kind == .series ? nil : mediaURL(stream["direct_source"]),
                xtreamStreamID: streamID,
                fileExtension: fileExtension, isSeriesCollection: kind == .series,
                backdropURL: Self.backdrop(stream["backdrop_path"]) ?? Self.backdrop(stream["backdrop"]), details: Self.details(stream)
            )
        }
    }

    /// Some Xtream implementations expose either a single URL or an array.
    static func backdrop(_ value: Any?) -> URL? {
        if let string = value as? String { return IPTVURL.remoteImage(string) }
        return (value as? [String])?.lazy.compactMap { IPTVURL.remoteImage($0) }.first
    }

    /// Providers return episodes either keyed by season or as a flat array.
    static func decodeSeasons(_ response: [String: Any], series: IPTVItem) -> [IPTVSeason] {
        var entries: [(Int, [String: Any])] = []
        if let bySeason = response["episodes"] as? [String: Any] {
            for (key, value) in bySeason {
                for entry in value as? [[String: Any]] ?? [] {
                    let season = Int(key) ?? string(entry["season"]).flatMap(Int.init) ?? 0
                    entries.append((max(0, season), entry))
                }
            }
        } else if let flat = response["episodes"] as? [[String: Any]] {
            entries = flat.map { (max(0, string($0["season"]).flatMap(Int.init) ?? 0), $0) }
        } else if let nested = response["episodes"] as? [[[String: Any]]] {
            for (index, season) in nested.enumerated() {
                entries += season.map { (max(0, string($0["season"]).flatMap(Int.init) ?? index + 1), $0) }
            }
        }
        var groups: [Int: [(number: Int, item: IPTVItem)]] = [:]
        // One name per season, shared by its episodes.
        var seasonNames: [Int: String] = [:]
        var seen = Set<String>()
        for (season, entry) in entries {
            guard let streamID = string(entry["id"]) ?? string(entry["episode_id"]) ?? string(entry["stream_id"]), !streamID.isEmpty else { continue }
            let id = "\(series.id):episode:\(streamID)"
            guard seen.insert(id).inserted else { continue }
            let number = string(entry["episode_num"]).flatMap(Int.init) ?? 0
            let rawTitle = (entry["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? (number > 0 ? "Épisode \(number)" : "Épisode") : native(rawTitle)
            let name = number > 0 && !rawTitle.isEmpty ? "E\(number) · \(title)" : title
            let info = entry["info"] as? [String: Any]
            let group = seasonNames[season] ?? series.name + " · Saison \(season)"
            seasonNames[season] = group
            let item = IPTVItem(id: id, sourceID: series.sourceID, name: name,
                                group: group,
                                logoURL: IPTVURL.remoteImage(info?["movie_image"] as? String) ?? IPTVURL.remoteImage(entry["movie_image"] as? String) ?? IPTVURL.remoteImage(info?["cover"] as? String),
                                kind: .series, directURL: mediaURL(entry["direct_source"]) ?? mediaURL(info?["direct_source"]), xtreamStreamID: streamID,
                                fileExtension: sanitizedExtension(entry["container_extension"] as? String)
                                    ?? sanitizedExtension(info?["container_extension"] as? String),
                                backdropURL: Self.backdrop(info?["backdrop_path"]), details: Self.details(info ?? [:]).fillingMissing(from: Self.details(entry)), seasonNumber: season, episodeNumber: number > 0 ? number : nil)
            groups[season, default: []].append((number, item))
        }
        return groups.keys.sorted().map { season in
            let episodes = groups[season, default: []].sorted { a, b in
                if a.number != b.number { return a.number < b.number }
                return a.item.id < b.item.id
            }.map(\.item)
            return IPTVSeason(number: season, episodes: episodes)
        }
    }

    public static func streamURL(
        server: URL, username: String, password: String, item: IPTVItem,
        liveExtension: String = "m3u8"
    ) -> URL? {
        guard !item.isSeriesCollection, let streamID = item.xtreamStreamID,
              let scheme = server.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let ext = item.kind == .live ? (liveExtension == "ts" ? "ts" : "m3u8") : (item.fileExtension ?? "mp4")
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let currentPath = (components?.percentEncodedPath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parent = currentPath.hasSuffix("player_api.php")
            ? String(currentPath.dropLast("player_api.php".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : currentPath
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let route: String
        switch item.kind {
        case .live: route = "live"
        case .movie: route = "movie"
        case .series: route = "series"
        }
        let segments = [route, username, password, "\(streamID).\(ext)"]
        let encoded = segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        components?.percentEncodedPath = "/" + ([parent].filter { !$0.isEmpty } + encoded).joined(separator: "/")
        return components?.url
    }

    private static func mediaURL(_ raw: Any?) -> URL? {
        guard let value = raw as? String else { return nil }
        return try? IPTVURL.validated(value)
    }

    private static let alphanumerics = CharacterSet.alphanumerics

    private static func sanitizedExtension(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (2...6).contains(value.count),
              value.unicodeScalars.allSatisfy({ alphanumerics.contains($0) }) else { return nil }
        return value.lowercased()
    }

    /// "null" in any case: four letters of ASCII, which no other text
    /// lowercases to. A longer value is never lowercased in full.
    private static func isNull(_ text: String) -> Bool {
        text.utf16.count == 4 && text.lowercased() == "null"
    }

    /// The first 4000 Characters: the whole text when it has no more UTF-16
    /// units than that, without walking its Characters.
    private static func capped(_ text: String) -> String {
        text.utf16.count <= 4000 ? text : String(text.prefix(4000))
    }

    /// A text as a native string of UTF-8. `JSONSerialization` gives the texts
    /// that hold more than ASCII in UTF-16: twice the size of an accented
    /// synopsis, and slow for Swift to read (the index folds every name). One
    /// copy in bulk is cheaper than reading them later: 0.7 µs for a synopsis
    /// of 600 accented characters on a Mac, where a copy through Swift took
    /// 9 µs and the `prefix(4000)` of the 0.9.9 took 32 µs.
    static func native(_ text: String) -> String {
        if text.utf8.withContiguousStorageIfAvailable({ _ in true }) == true { return text }
        #if canImport(Darwin)
        let bridged = text as NSString
        let length = bridged.length, size = bridged.lengthOfBytes(using: String.Encoding.utf8.rawValue)
        if size > 0 {
            let copy = String(unsafeUninitializedCapacity: size) { buffer in
                var used = 0
                let converted = bridged.getBytes(buffer.baseAddress, maxLength: size, usedLength: &used,
                                                 encoding: String.Encoding.utf8.rawValue, options: [],
                                                 range: NSRange(location: 0, length: length), remaining: nil)
                return converted ? used : 0
            }
            if copy.utf8.count == size { return copy }
        }
        #endif
        var copy = text
        copy.makeContiguousUTF8()
        return copy
    }

    private static func string(_ any: Any?) -> String? {
        switch any {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }
}
