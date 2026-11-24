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

        async let liveData = request(server: server, username: username, password: password, action: "get_live_streams")
        async let liveCategories = request(server: server, username: username, password: password, action: "get_live_categories")
        async let movieData = request(server: server, username: username, password: password, action: "get_vod_streams")
        async let movieCategories = request(server: server, username: username, password: password, action: "get_vod_categories")

        let live = try await liveData
        let liveGroups = (try? await liveCategories) ?? []
        // Not all Xtream-compatible services expose a VOD endpoint.
        let movies = (try? await movieData) ?? []
        let movieGroups = (try? await movieCategories) ?? []
        let result = Self.decodeItems(live, categories: liveGroups, sourceID: sourceID, kind: .live)
            + Self.decodeItems(movies, categories: movieGroups, sourceID: sourceID, kind: .movie)
        if result.isEmpty { throw IPTVError.emptyCatalog }
        return result
    }

    private func request(server: URL, username: String, password: String, action: String?) async throws -> Any {
        guard let scheme = server.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              server.host != nil else { throw IPTVError.invalidURL }
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        let path = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + (path.hasSuffix("player_api.php") ? path :
            (path.isEmpty ? "player_api.php" : path + "/player_api.php"))
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ] + (action.map { [URLQueryItem(name: "action", value: $0)] } ?? [])
        guard let url = components?.url else { throw IPTVError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IPTVError.invalidResponse }
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
            labels[id] = title
        }
        return streams.compactMap { stream in
            guard let streamID = string(stream["stream_id"]), !streamID.isEmpty else { return nil }
            let title = (stream["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { return nil }
            let category = string(stream["category_id"]).flatMap { labels[$0] } ?? "Sans catégorie"
            let fileExtension: String? = kind == .movie ? sanitizedExtension(stream["container_extension"] as? String) : nil
            return IPTVItem(
                id: "\(sourceID.uuidString):\(kind.rawValue):\(streamID)",
                sourceID: sourceID,
                name: title,
                group: category,
                logoURL: IPTVURL.remoteImage((stream["stream_icon"] ?? stream["cover"]) as? String),
                kind: kind,
                directURL: nil,
                xtreamStreamID: streamID,
                fileExtension: fileExtension
            )
        }
    }

    public static func streamURL(
        server: URL, username: String, password: String, item: IPTVItem,
        liveExtension: String = "m3u8"
    ) -> URL? {
        guard let streamID = item.xtreamStreamID,
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
        let segments = [item.kind == .live ? "live" : "movie", username, password, "\(streamID).\(ext)"]
        let encoded = segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        components?.percentEncodedPath = "/" + ([parent].filter { !$0.isEmpty } + encoded).joined(separator: "/")
        return components?.url
    }

    private static func sanitizedExtension(_ raw: String?) -> String? {
        guard let raw, (2...6).contains(raw.count),
              raw.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return raw.lowercased()
    }

    private static func string(_ any: Any?) -> String? {
        switch any {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }
}
