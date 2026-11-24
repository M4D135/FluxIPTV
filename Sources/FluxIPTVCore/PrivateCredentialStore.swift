import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Explicit opt-in for development builds on Mac. Unix permissions are not encryption.
/// No Keychain access and no dependence on the signing certificate.
enum CredentialStorageMode: String, Codable, Sendable {
    case keychain, localPrivate
}

enum PrivateCredentialStoreError: LocalizedError {
    case missing, unsafeLocation, inaccessible
    var errorDescription: String? {
        switch self {
        case .missing: return "Identifiants locaux introuvables. Reconnectez cette source sans la supprimer."
        case .unsafeLocation: return "Le dossier privé des identifiants n’est pas sûr. Aucun secret n’a été enregistré."
        case .inaccessible: return "Impossible d’accéder au stockage privé des identifiants. Vérifiez les permissions de l’application."
        }
    }
}

struct PrivateCredentialStore {
    let directory: URL
    private let fm = FileManager.default

    private func check(_ url: URL, type: FileAttributeType, permissions: Int) throws {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == type,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw PrivateCredentialStoreError.unsafeLocation
        }
        // Fail closed when a location is unexpectedly accessible to others.
        guard let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue,
              mode & 0o777 == permissions else { throw PrivateCredentialStoreError.unsafeLocation }
    }

    private func prepare() throws {
        // The parent is the application's own Application Support directory.
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try check(directory, type: .typeDirectory, permissions: 0o700)
    }

    private func location(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    func save<T: Encodable>(_ value: T, for id: UUID) throws {
        try prepare()
        let destination = location(id)
        if fm.fileExists(atPath: destination.path) {
            try check(destination, type: .typeRegular, permissions: 0o600)
        }
        // Write a new, owner-only file before atomically renaming it over the old one.
        let tmp = directory.appendingPathComponent(".write-" + UUID().uuidString)
        let data = try JSONEncoder().encode(value)
        defer { try? fm.removeItem(at: tmp) }
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw PrivateCredentialStoreError.inaccessible
        }
        try check(tmp, type: .typeRegular, permissions: 0o600)
        // POSIX rename replaces a directory entry, not the target of a symlink.
        guard rename(tmp.path, destination.path) == 0 else { throw PrivateCredentialStoreError.inaccessible }
        try check(destination, type: .typeRegular, permissions: 0o600)
    }

    func read<T: Decodable>(_ type: T.Type, for id: UUID) throws -> T {
        guard fm.fileExists(atPath: directory.path) else { throw PrivateCredentialStoreError.missing }
        try check(directory, type: .typeDirectory, permissions: 0o700)
        let file = location(id)
        guard fm.fileExists(atPath: file.path) else { throw PrivateCredentialStoreError.missing }
        try check(file, type: .typeRegular, permissions: 0o600)
        return try JSONDecoder().decode(type, from: Data(contentsOf: file))
    }

    func remove(for id: UUID) throws {
        guard fm.fileExists(atPath: directory.path) else { return }
        try check(directory, type: .typeDirectory, permissions: 0o700)
        let file = location(id)
        guard fm.fileExists(atPath: file.path) else { return }
        try check(file, type: .typeRegular, permissions: 0o600)
        try fm.removeItem(at: file)
    }
}
