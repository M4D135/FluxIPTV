import XCTest
@testable import FluxIPTVCore

final class FavoritePresetsTests: XCTestCase {
    private let sourceID = UUID(uuidString: "D436229E-3C1A-49E9-B50B-84A67859DF35")!
    private func item(_ kind: IPTVMediaKind, _ id: String = "7") -> IPTVItem {
        IPTVItem(id: "\(sourceID.uuidString):\(kind.rawValue):\(id)", sourceID: sourceID, name: "Example", group: "Test", logoURL: nil, kind: kind, directURL: nil, xtreamStreamID: id, fileExtension: nil)
    }

    func testSeparateListsAndRoundTrip() throws {
        var presets = FavoritePresets()
        let live = try XCTUnwrap(presets.create(name: "Sport", kind: .live))
        let movie = try XCTUnwrap(presets.create(name: "Sport", kind: .movie))
        let series = try XCTUnwrap(presets.create(name: "À voir", kind: .series))
        XCTAssertNil(presets.create(name: " sport ", kind: .live))
        XCTAssertFalse(presets.toggle(item(.series), in: live))
        XCTAssertTrue(presets.toggle(item(.live), in: live))
        XCTAssertTrue(presets.toggle(item(.movie), in: movie))
        XCTAssertTrue(presets.toggle(item(.series), in: series))
        XCTAssertTrue(presets.rename(id: series, name: "Week-end"))
        let saved = try JSONDecoder().decode(FavoritePresets.self, from: JSONEncoder().encode(presets))
        XCTAssertEqual(saved.list(id: series)?.name, "Week-end")
        XCTAssertEqual(saved.list(id: series)?.itemIDs, [item(.series).id])
        XCTAssertEqual(saved.list(id: live)?.itemIDs, [item(.live).id])
        XCTAssertFalse(presets.delete(id: FavoritePresets.defaultID(for: .live)))
        XCTAssertTrue(presets.delete(id: live))
        XCTAssertNotNil(presets.list(id: movie))
        presets.removeSource(sourceID)
        XCTAssertEqual(presets.list(id: movie)?.itemIDs, [])
    }

    func testMigrationAndM3UReclassification() throws {
        let m3uID = "\(sourceID.uuidString):m3u:abc"
        var presets = FavoritePresets(legacyIDs: [item(.live).id, item(.movie).id, m3uID])
        let liveID = FavoritePresets.defaultID(for: .live)
        let movieID = FavoritePresets.defaultID(for: .movie)
        XCTAssertEqual(presets.list(id: liveID)?.itemIDs, [item(.live).id, m3uID])
        XCTAssertEqual(presets.list(id: movieID)?.itemIDs, [item(.movie).id])
        let m3u = IPTVItem(id: m3uID, sourceID: sourceID, name: "Film", group: "Films", logoURL: nil, kind: .movie, directURL: nil, xtreamStreamID: nil, fileExtension: nil)
        XCTAssertTrue(presets.reconcileMigratedM3U([m3u]))
        XCTAssertEqual(presets.list(id: movieID)?.itemIDs, [item(.movie).id, m3uID])
        XCTAssertFalse(presets.reconcileMigratedM3U([m3u]))
        XCTAssertEqual(presets.list(id: liveID)?.itemIDs, [item(.live).id])
    }

    func testConfirmedAssignmentIsAtomicAndPreservesOtherItems() throws {
        var presets = FavoritePresets()
        let movie = item(.movie)
        let other = item(.movie, "8")
        let defaultID = FavoritePresets.defaultID(for: .movie)
        let weekend = try XCTUnwrap(presets.create(name: "Week-end", kind: .movie))
        _ = presets.toggle(other, in: defaultID)
        _ = presets.toggle(movie, in: defaultID)
        XCTAssertTrue(presets.assign(movie, to: [weekend], creating: "À regarder"))
        XCTAssertEqual(presets.list(id: defaultID)?.itemIDs, [other.id])
        XCTAssertEqual(presets.list(id: weekend)?.itemIDs, [movie.id])
        let created = try XCTUnwrap(presets.lists(for: .movie).first { $0.name == "À regarder" })
        XCTAssertEqual(created.itemIDs, [movie.id])
        let before = presets.lists
        XCTAssertFalse(presets.assign(movie, to: [], creating: "à regarder"))
        XCTAssertEqual(presets.lists, before)
        XCTAssertFalse(presets.assign(movie, to: [FavoritePresets.defaultID(for: .live)]))
        XCTAssertEqual(presets.lists, before)
        XCTAssertFalse(presets.assign(movie, to: ["deleted-list"]))
        XCTAssertEqual(presets.lists, before)
        XCTAssertTrue(presets.assign(movie, to: []))
        XCTAssertTrue(presets.lists(for: .movie).allSatisfy { !$0.itemIDs.contains(movie.id) })
        XCTAssertEqual(presets.list(id: defaultID)?.itemIDs, [other.id])
    }
}
