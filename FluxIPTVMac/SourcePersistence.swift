import Foundation
import Security

struct IPTVSource: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let kind: IPTVSourceKind
    // Optional for decoding source records saved before 0.7.2.
    var credentialStorage: CredentialStorageMode? = nil

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
@MainActor enum IPTVKeychain {
    // The file-based macOS keychain uses legacy ACLs. Disable its prompt only
    // during our own silent calls, restore the previous process setting afterward.
    private static func withoutPrompt<T>(_ operation: () throws -> T) throws -> T {
        #if os(macOS)
        var previous = true
        let read = FluxLegacyKeychainGetInteractionAllowed(&previous)
        guard read == errSecSuccess else { throw KeychainError(status: read) }
        let disabled = FluxLegacyKeychainSetInteractionAllowed(false)
        guard disabled == errSecSuccess else { throw KeychainError(status: disabled) }
        defer { _ = FluxLegacyKeychainSetInteractionAllowed(previous) }
        #endif
        return try operation()
    }
    #if FLUX_KEYCHAIN_TESTING && os(macOS)
    // Exercises only the process guard; the smoke test never accesses an item.
    static func withSilentInteractionForTesting<T>(_ operation: () throws -> T) throws -> T {
        try withoutPrompt(operation)
    }
    #endif
    private static func query(_ sourceID: UUID, interactive: Bool) -> [String: Any] {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: sourceID.uuidString]
        #if os(macOS)
        return base
        #else
        var q = base
        if !interactive { q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        return q
        #endif
    }

    private static let service = "com.m4d135.FluxIPTV.sources"

    static func save(_ secret: IPTVSecret, sourceID: UUID, interactive: Bool = false) throws {
        func operation() throws {
            let data = try JSONEncoder().encode(secret)
            let q = query(sourceID, interactive: interactive)
            let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecSuccess { return }
            guard update == errSecItemNotFound else { throw KeychainError(status: update) }
            var insert = q
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }
        if interactive { try operation() } else { try withoutPrompt(operation) }
    }

    static func read(sourceID: UUID, interactive: Bool = false) throws -> IPTVSecret {
        func operation() throws -> IPTVSecret {
            var q = query(sourceID, interactive: interactive)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &result)
            if status == errSecItemNotFound { throw IPTVError.missingCredentials }
            guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
            return try JSONDecoder().decode(IPTVSecret.self, from: data)
        }
        if interactive { return try operation() }
        return try withoutPrompt(operation)
    }

    static func delete(sourceID: UUID) {
        // A denied ACL must not open a system dialog as a side effect of UI navigation.
        _ = try? withoutPrompt { SecItemDelete(query(sourceID, interactive: false) as CFDictionary) }
    }

}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Le Trousseau n’autorise pas cet accès (code \(status)). Reconnectez la source ou déverrouillez volontairement l’ancienne entrée."
    }
}

/// Use the explicitly selected backend; never silently downgrade security.
@MainActor enum IPTVSecretStore {
    static func local() throws -> PrivateCredentialStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return PrivateCredentialStore(directory: base.appendingPathComponent("FluxIPTV/credentials-local-v1", isDirectory: true))
    }

    static func read(_ source: IPTVSource, interactive: Bool = false) throws -> IPTVSecret {
        #if os(macOS)
        if source.credentialStorage == .localPrivate {
            return try local().read(IPTVSecret.self, for: source.id)
        }
        #endif
        return try IPTVKeychain.read(sourceID: source.id, interactive: interactive)
    }

    static func save(_ secret: IPTVSecret, source: IPTVSource, interactive: Bool = false) throws {
        #if os(macOS)
        if source.credentialStorage == .localPrivate {
            try local().save(secret, for: source.id)
            return
        }
        #endif
        try IPTVKeychain.save(secret, sourceID: source.id, interactive: interactive)
    }

    static func delete(_ source: IPTVSource) {
        #if os(macOS)
        try? local().remove(for: source.id)
        #endif
        IPTVKeychain.delete(sourceID: source.id)
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
