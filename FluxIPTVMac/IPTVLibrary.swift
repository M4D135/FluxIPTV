import Foundation
import Combine

@MainActor
final class IPTVLibrary: ObservableObject {
    @Published private(set) var sources: [IPTVSource] = []
    @Published private(set) var items: [IPTVItem] = []
    @Published private(set) var selectedSourceID: UUID?
    @Published var selectedItemID: String?
    @Published var search = ""
    @Published var contentKind: IPTVMediaKind = .live
    @Published var favoritesOnly = false
    @Published private(set) var isLoading = false
    @Published var alertMessage: String?
    @Published private(set) var favorites: Set<String> = []

    private let sourcesKey = "fluxiptv.savedSources.v1"
    private let favoritesKey = "fluxiptv.favorites.v1"
    private var loadID = UUID()

    init() {
        if let data = UserDefaults.standard.data(forKey: sourcesKey),
           let saved = try? JSONDecoder().decode([IPTVSource].self, from: data) {
            sources = saved
        }
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        if let first = sources.first {
            Task { await selectSource(first.id) }
        }
    }

    var selectedItem: IPTVItem? {
        items.first(where: { $0.id == selectedItemID })
    }

    var selectedSource: IPTVSource? {
        sources.first(where: { $0.id == selectedSourceID })
    }

    var filteredItems: [IPTVItem] {
        items.filter { item in
            item.kind == contentKind &&
            (!favoritesOnly || favorites.contains(item.id)) &&
            (search.isEmpty || item.name.localizedStandardContains(search) || item.group.localizedStandardContains(search))
        }
    }

    func addXtream(name: String, server: String, username: String, password: String,
                   liveExtension: String) async throws {
        let endpoint = try IPTVURL.validated(server)
        guard !username.isEmpty, !password.isEmpty else { throw IPTVError.authenticationFailed }
        let record = IPTVSource(id: UUID(), name: displayName(name, fallback: endpoint.host ?? "Xtream"), kind: .xtream)
        try IPTVKeychain.save(
            IPTVSecret(endpoint: endpoint.absoluteString, username: username, password: password,
                       liveExtension: liveExtension == "ts" ? "ts" : "m3u8"),
            sourceID: record.id
        )
        sources.append(record)
        persistSources()
        await selectSource(record.id)
    }

    func addM3UURL(name: String, address: String) async throws {
        let url = try IPTVURL.validated(address)
        let record = IPTVSource(id: UUID(), name: displayName(name, fallback: url.host ?? "Playlist M3U"), kind: .m3uURL)
        try IPTVKeychain.save(IPTVSecret(endpoint: url.absoluteString, username: "", password: "", liveExtension: ""),
                              sourceID: record.id)
        sources.append(record)
        persistSources()
        await selectSource(record.id)
    }

    func addM3UFile(name: String, fileURL: URL) async throws {
        let record = IPTVSource(id: UUID(), name: displayName(name, fallback: fileURL.deletingPathExtension().lastPathComponent),
                                kind: .m3uFile)
        try LocalPlaylistFiles.importFile(fileURL, id: record.id)
        sources.append(record)
        persistSources()
        await selectSource(record.id)
    }

    func selectSource(_ id: UUID) async {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        loadID = UUID()
        let token = loadID
        selectedSourceID = id
        selectedItemID = nil
        items = []
        isLoading = true
        search = ""
        favoritesOnly = false
        contentKind = .live

        do {
            // Secrets are read on the main actor before the detached parsing task.
            let secret = source.kind == .m3uFile ? nil : try IPTVKeychain.read(sourceID: id)
            let loaded = try await Task.detached(priority: .userInitiated) {
                try await Self.load(source: source, secret: secret)
            }.value
            guard loadID == token else { return }
            items = loaded
            if !loaded.contains(where: { $0.kind == .live }) { contentKind = .movie }
        } catch {
            guard loadID == token else { return }
            alertMessage = error.localizedDescription
        }
        if loadID == token { isLoading = false }
    }

    nonisolated private static func load(source: IPTVSource, secret: IPTVSecret?) async throws -> [IPTVItem] {
        switch source.kind {
        case .xtream:
            guard let secret, let endpoint = try? IPTVURL.validated(secret.endpoint) else {
                throw IPTVError.missingCredentials
            }
            return try await XtreamClient().fetchCatalog(
                server: endpoint, username: secret.username, password: secret.password, sourceID: source.id)
        case .m3uURL:
            guard let secret, let url = try? IPTVURL.validated(secret.endpoint) else {
                throw IPTVError.missingCredentials
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: config)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw IPTVError.serverError(http.statusCode)
            }
            let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? ""
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        case .m3uFile:
            let bytes = try Data(contentsOf: LocalPlaylistFiles.destination(for: source.id))
            let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? ""
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        }
    }

    func playbackURL(for item: IPTVItem) throws -> URL {
        if let direct = item.directURL { return direct }
        let secret = try IPTVKeychain.read(sourceID: item.sourceID)
        let server = try IPTVURL.validated(secret.endpoint)
        guard let url = XtreamClient.streamURL(server: server,
                                                username: secret.username, password: secret.password,
                                                item: item, liveExtension: secret.liveExtension) else {
            throw IPTVError.invalidURL
        }
        return url
    }

    func toggleFavorite(_ item: IPTVItem) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    func removeSource(_ source: IPTVSource) {
        loadID = UUID() // invalidate any in-flight refresh
        IPTVKeychain.delete(sourceID: source.id)
        if source.kind == .m3uFile { LocalPlaylistFiles.remove(for: source.id) }
        sources.removeAll(where: { $0.id == source.id })
        favorites = Set(favorites.filter { !$0.hasPrefix("\(source.id.uuidString):") })
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
        persistSources()
        if selectedSourceID == source.id {
            selectedSourceID = nil
            selectedItemID = nil
            items = []
            isLoading = false
            if let first = sources.first { Task { await selectSource(first.id) } }
        }
    }

    func reloadSelected() {
        if let id = selectedSourceID { Task { await selectSource(id) } }
    }

    private func persistSources() {
        if let bytes = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(bytes, forKey: sourcesKey)
        }
    }

    private func displayName(_ suggested: String, fallback: String) -> String {
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
