import Foundation
import XCTest
@testable import FluxIPTVCore

final class PrivateCredentialStoreTests: XCTestCase {
    private struct Secret: Codable, Equatable { let username: String; let password: String }
    private func fixture() throws -> (URL, PrivateCredentialStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, PrivateCredentialStore(directory: root.appendingPathComponent("private")))
    }
    func testPersistentStorageAndUpdate() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), other = UUID(), first = Secret(username: "demo", password: "fake-été?#"), second = Secret(username: "demo2", password: "fake2")
        try store.save(first, for: id)
        let restarted = PrivateCredentialStore(directory: store.directory)
        XCTAssertEqual(try restarted.read(Secret.self, for: id), first)
        try restarted.save(second, for: id)
        XCTAssertEqual(try store.read(Secret.self, for: id), second)
        XCTAssertThrowsError(try store.read(Secret.self, for: other))
        let fm = FileManager.default
        let file = store.directory.appendingPathComponent(id.uuidString + ".json")
        XCTAssertEqual((try fm.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try restarted.remove(for: id)
        XCTAssertThrowsError(try store.read(Secret.self, for: id))
    }
    func testRejectsUnsafeDirectoryAndFile() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), secret = Secret(username: "test", password: "fake")
        try store.save(secret, for: id)
        let file = store.directory.appendingPathComponent(id.uuidString + ".json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try store.read(Secret.self, for: id))
        XCTAssertThrowsError(try store.save(secret, for: id))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.directory.path)
        XCTAssertThrowsError(try store.read(Secret.self, for: id))
        XCTAssertThrowsError(try store.save(secret, for: UUID()))
    }
    func testRejectsSymbolicLink() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), secret = Secret(username: "test", password: "fake")
        try store.save(secret, for: id)
        let file = store.directory.appendingPathComponent(id.uuidString + ".json")
        let other = root.appendingPathComponent("other")
        try Data("original".utf8).write(to: other)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        XCTAssertThrowsError(try store.read(Secret.self, for: id))
        XCTAssertThrowsError(try store.save(secret, for: id))
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "original")
    }
}
