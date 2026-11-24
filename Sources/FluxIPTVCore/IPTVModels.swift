import Foundation

public enum IPTVSourceKind: String, Codable, Sendable {
    case xtream
    case m3uURL
    case m3uFile
}

public enum IPTVMediaKind: String, Codable, CaseIterable, Sendable {
    case live
    case movie
    case series

    public var frenchTitle: String {
        switch self {
        case .live: return "Chaînes TV"
        case .movie: return "Films"
        case .series: return "Séries"
        }
    }
}

public struct IPTVItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let sourceID: UUID
    public let name: String
    public let group: String
    public let logoURL: URL?
    /// Optional wide artwork supplied by the provider.
    public let backdropURL: URL?
    public let kind: IPTVMediaKind
    public let directURL: URL?
    public let xtreamStreamID: String?
    public let fileExtension: String?
    /// True for a series catalogue entry; false for a playable episode.
    public let isSeriesCollection: Bool
    public let details: IPTVDetails
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(
        id: String, sourceID: UUID, name: String, group: String,
        logoURL: URL?, kind: IPTVMediaKind, directURL: URL?,
        xtreamStreamID: String?, fileExtension: String?, isSeriesCollection: Bool = false, backdropURL: URL? = nil, details: IPTVDetails = IPTVDetails(), seasonNumber: Int? = nil, episodeNumber: Int? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.backdropURL = backdropURL
        self.kind = kind
        self.directURL = directURL
        self.xtreamStreamID = xtreamStreamID
        self.fileExtension = fileExtension
        self.isSeriesCollection = isSeriesCollection
        self.details = details
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

public struct IPTVDetails: Hashable, Sendable {
    public var synopsis: String?
    public var year: String?
    public var duration: String?
    public var rating: String?
    public var genre: String?
    public var cast: String?
    public var director: String?
    public var trailerURL: URL?
    public init(synopsis: String? = nil, year: String? = nil, duration: String? = nil, rating: String? = nil, genre: String? = nil, cast: String? = nil, director: String? = nil, trailerURL: URL? = nil) {
        self.synopsis = synopsis; self.year = year; self.duration = duration; self.rating = rating; self.genre = genre; self.cast = cast; self.director = director; self.trailerURL = trailerURL
    }
    public func fillingMissing(from fallback: IPTVDetails) -> IPTVDetails {
        IPTVDetails(synopsis: synopsis ?? fallback.synopsis, year: year ?? fallback.year, duration: duration ?? fallback.duration, rating: rating ?? fallback.rating, genre: genre ?? fallback.genre, cast: cast ?? fallback.cast, director: director ?? fallback.director, trailerURL: trailerURL ?? fallback.trailerURL)
    }
}

public struct IPTVSeason: Identifiable, Hashable, Sendable {
    public let number: Int
    public let episodes: [IPTVItem]
    public var id: Int { number }
}

public enum IPTVError: LocalizedError, Sendable {
    case invalidURL
    case unsupportedProtocol
    case invalidPlaylist
    case invalidResponse
    case authenticationFailed
    case serverError(Int)
    case missingCredentials
    case emptyCatalog

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Adresse incorrecte. Vérifiez l’URL complète du fournisseur."
        case .unsupportedProtocol: return "Seules les adresses HTTP et HTTPS sont acceptées."
        case .invalidPlaylist: return "La playlist ne contient aucun flux HTTP(S) utilisable."
        case .invalidResponse: return "Le serveur a renvoyé une réponse non reconnue."
        case .authenticationFailed: return "Identifiants Xtream incorrects ou compte non autorisé."
        case .serverError(let code): return "Le serveur a répondu avec l’erreur HTTP \(code)."
        case .missingCredentials: return "Les identifiants de cette source sont introuvables. Reconnectez-la sans la supprimer."
        case .emptyCatalog: return "Aucun contenu trouvé pour cette source."
        }
    }
}

public enum IPTVURL {
    public static func validated(_ value: String) throws -> URL {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw IPTVError.invalidURL
        }
        guard url.host?.isEmpty == false, url.user == nil, url.password == nil else {
            throw IPTVError.invalidURL
        }
        return url
    }

    public static func remoteImage(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = try? validated(raw) else { return nil }
        return url
    }
}

/// Deterministic, non-reversible identifier; never stores a URL with tokens in favorites.
public enum StableID {
    public static func hash(_ value: String) -> String {
        var result: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            result = (result ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(result, radix: 16)
    }
}


/// Process-local cache only. The caller owns synchronization (the macOS library
/// is MainActor-isolated). Never encode or persist this cache.
struct SessionCredentialCache<Value> {
    private var values: [UUID: Value] = [:]

    func cached(for sourceID: UUID) -> Value? { values[sourceID] }

    mutating func load(for sourceID: UUID, using read: () throws -> Value) rethrows -> Value {
        if let existing = values[sourceID] { return existing }
        let value = try read()
        values[sourceID] = value
        return value
    }

    mutating func store(_ value: Value, for sourceID: UUID) {
        values[sourceID] = value
    }

    mutating func remove(for sourceID: UUID) {
        values.removeValue(forKey: sourceID)
    }
}
