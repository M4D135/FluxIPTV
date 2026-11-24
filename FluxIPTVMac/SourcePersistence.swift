import Foundation
import Security

struct IPTVSource: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let kind: IPTVSourceKind

    var symbol: String {
        switch kind {
        case .xtream: "server.rack"
        case .m3uURL: "link"
        case .m3uFile: "doc.text"
        }
    }
}

struct IPTVSecret: Codable, Sendable {
    let endpoint: String
    let username: String
    let password: String
    let liveExtension: String
}

/// Authenticated endpoints and passwords never go to UserDefaults or Git.
enum IPTVKeychain {
    private static let service = "com.m4d135.FluxIPTV.sources"

    static func save(_ secret: IPTVSecret, sourceID: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func read(sourceID: UUID) throws -> IPTVSecret {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw IPTVError.missingCredentials }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(IPTVSecret.self, from: data)
    }

    static func delete(sourceID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Accès au Trousseau impossible (code \(status))."
    }
}

enum LocalPlaylistFiles {
    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("FluxIPTV/playlists", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func destination(for id: UUID) throws -> URL {
        try root().appendingPathComponent("\(id.uuidString).m3u")
    }

    static func importFile(_ selectedURL: URL, id: UUID) throws {
        let permission = selectedURL.startAccessingSecurityScopedResource()
        defer { if permission { selectedURL.stopAccessingSecurityScopedResource() } }
        let bytes = try Data(contentsOf: selectedURL)
        guard !bytes.isEmpty else { throw IPTVError.invalidPlaylist }
        try bytes.write(to: destination(for: id), options: [.atomic])
    }

    static func remove(for id: UUID) {
        guard let url = try? destination(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
