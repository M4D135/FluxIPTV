import Foundation

public enum IPTVSourceKind: String, Codable, Sendable {
    case xtream
    case m3uURL
    case m3uFile
}

public enum IPTVMediaKind: String, Codable, CaseIterable, Sendable {
    case live
    case movie

    public var frenchTitle: String {
        switch self {
        case .live: return "Chaînes TV"
        case .movie: return "Films"
        }
    }
}

public struct IPTVItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let sourceID: UUID
    public let name: String
    public let group: String
    public let logoURL: URL?
    public let kind: IPTVMediaKind
    public let directURL: URL?
    public let xtreamStreamID: String?
    public let fileExtension: String?

    public init(
        id: String, sourceID: UUID, name: String, group: String,
        logoURL: URL?, kind: IPTVMediaKind, directURL: URL?,
        xtreamStreamID: String?, fileExtension: String?
    ) {
        self.id = id
        self.sourceID = sourceID
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.kind = kind
        self.directURL = directURL
        self.xtreamStreamID = xtreamStreamID
        self.fileExtension = fileExtension
    }
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
        case .missingCredentials: return "Les identifiants de cette source sont introuvables dans le Trousseau."
        case .emptyCatalog: return "Aucune chaîne trouvée pour cette source."
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
