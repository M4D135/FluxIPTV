import XCTest
@testable import FluxIPTVCore

final class CatalogBrowsingStateTests: XCTestCase {
    private let sourceA = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    private let sourceB = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!

    private func item(_ id: String, group: String, kind: IPTVMediaKind = .live, name: String = "Grand écran") -> IPTVItem {
        IPTVItem(id: id, sourceID: sourceA, name: name, group: group, logoURL: nil,
                 kind: kind, directURL: nil, xtreamStreamID: nil, fileExtension: nil)
    }

    func testRoundTripSeparatesEverySourceAndMediaSection() throws {
        let french = CatalogBrowsingState(countryCode: "FR", group: "[FR] Cinéma", search: "écran",
                                          groupSearch: "Cin", presetID: "default-live", catalogPage: 3, browseItemID: "fr1")
        let films = CatalogBrowsingState(group: "Aventure", search: "dunes", groupSearch: "av",
                                         continueOnly: true, catalogPage: 2, browseItemID: "film1")
        let spanish = CatalogBrowsingState(countryCode: "ES", group: "ES - Deportes", search: "canal")
        var preferences = CatalogBrowsingPreferences()
        preferences.remember(french, sourceID: sourceA, kind: .live)
        preferences.remember(films, sourceID: sourceA, kind: .movie)
        preferences.remember(spanish, sourceID: sourceB, kind: .live)
        let saved = CatalogBrowsingPreferences.decoded(try JSONEncoder().encode(preferences))
        XCTAssertEqual(saved.state(for: sourceA, kind: .live), french)
        XCTAssertEqual(saved.state(for: sourceA, kind: .movie), films)
        XCTAssertEqual(saved.state(for: sourceB, kind: .live), spanish)
        XCTAssertEqual(saved.state(for: sourceB, kind: .movie), CatalogBrowsingState())
        XCTAssertEqual(saved.state(for: sourceA, kind: .series), CatalogBrowsingState())
        XCTAssertEqual(saved.lastSourceID, sourceB)
        XCTAssertEqual(saved.preferredKind(for: sourceA), .movie)
        XCTAssertEqual(saved.preferredKind(for: sourceB), .live)
    }

    func testEmptySearchResultsKeepTheExistingCountryAndCategory() {
        let index = CatalogIndex([item("fr1", group: "[FR] Cinéma"), item("es1", group: "ES - Cine")])
        let state = CatalogBrowsingState(countryCode: "FR", group: "[FR] Cinéma",
                                         search: "aucun titre", groupSearch: "Cin", browseItemID: "fr1")
        let restored = state.validated(kind: .live, index: index, presets: FavoritePresets())
        XCTAssertEqual(restored.countryCode, "FR")
        XCTAssertEqual(restored.group, "[FR] Cinéma")
        XCTAssertEqual(restored.search, "aucun titre")
        XCTAssertEqual(restored.groupSearch, "Cin")
        XCTAssertNil(restored.browseItemID)
    }

    func testRefreshReconcilesOnlyMissingOrIncompatibleChoices() {
        let index = CatalogIndex([item("fr1", group: "FR | Cinéma"), item("es1", group: "ES - Deportes")])
        let incompatible = CatalogBrowsingState(countryCode: "FR", group: "ES - Deportes",
                                                search: "écran", presetID: "deleted", catalogPage: 5,
                                                browseItemID: "es1")
        let restored = incompatible.validated(kind: .live, index: index, presets: FavoritePresets())
        XCTAssertEqual(restored.countryCode, "FR")
        XCTAssertNil(restored.group)
        XCTAssertNil(restored.presetID)
        XCTAssertNil(restored.browseItemID)
        XCTAssertEqual(restored.catalogPage, 0)
        XCTAssertEqual(restored.search, "écran")

        let disappeared = CatalogBrowsingState(countryCode: "BE", group: "BE - Info", browseItemID: "removed")
            .validated(kind: .live, index: index, presets: FavoritePresets())
        XCTAssertNil(disappeared.countryCode)
        XCTAssertNil(disappeared.group)
        XCTAssertNil(disappeared.browseItemID)
    }

    func testUnknownCountryRemainsSelectableAndMoviesDoNotInheritCountry() {
        let index = CatalogIndex([item("local", group: "Documentaires"), item("film", group: "FR | Cinéma", kind: .movie)])
        let unknown = CatalogBrowsingState(countryCode: LiveCountry.unknownCode, group: "Documentaires", browseItemID: "local")
        XCTAssertEqual(unknown.validated(kind: .live, index: index, presets: FavoritePresets()), unknown)

        let film = CatalogBrowsingState(countryCode: "FR", group: "FR | Cinéma", continueOnly: true, browseItemID: "film")
            .validated(kind: .movie, index: index, presets: FavoritePresets())
        XCTAssertNil(film.countryCode)
        XCTAssertEqual(film.group, "FR | Cinéma")
        XCTAssertTrue(film.continueOnly)
        XCTAssertEqual(film.browseItemID, "film")
    }

    func testFavoriteMembershipAndSelectionAreValidatedTogether() {
        let selected = item("fr1", group: "FR | Cinéma")
        let other = item("fr2", group: "FR | Cinéma")
        let index = CatalogIndex([selected, other])
        var presets = FavoritePresets()
        let id = FavoritePresets.defaultID(for: .live)
        XCTAssertTrue(presets.toggle(selected, in: id))
        let state = CatalogBrowsingState(countryCode: "FR", group: selected.group, search: "écran",
                                         groupSearch: "Cin", presetID: id, catalogPage: 2, browseItemID: selected.id)
        XCTAssertEqual(state.validated(kind: .live, index: index, presets: presets), state)
        var absent = state
        absent.browseItemID = other.id
        let restored = absent.validated(kind: .live, index: index, presets: presets)
        XCTAssertEqual(restored.presetID, id)
        XCTAssertNil(restored.browseItemID)
        XCTAssertEqual(restored.catalogPage, 0)
    }

    func testRemovingSourceDoesNotEraseOtherSourceAndSections() {
        var preferences = CatalogBrowsingPreferences()
        preferences.remember(CatalogBrowsingState(search: "one"), sourceID: sourceA, kind: .live)
        preferences.remember(CatalogBrowsingState(search: "film"), sourceID: sourceA, kind: .movie)
        preferences.remember(CatalogBrowsingState(search: "two"), sourceID: sourceB, kind: .live)
        preferences.removeSource(sourceA)
        XCTAssertEqual(preferences.state(for: sourceA, kind: .live), CatalogBrowsingState())
        XCTAssertEqual(preferences.state(for: sourceA, kind: .movie), CatalogBrowsingState())
        XCTAssertNil(preferences.preferredKind(for: sourceA))
        XCTAssertEqual(preferences.state(for: sourceB, kind: .live).search, "two")
        XCTAssertEqual(preferences.lastSourceID, sourceB)
        preferences.retainSources([])
        XCTAssertNil(preferences.lastSourceID)
        XCTAssertEqual(preferences.state(for: sourceB, kind: .live), CatalogBrowsingState())
    }

    func testCorruptAndUnsupportedStorageFallBackAndSparseStateDecodes() throws {
        XCTAssertEqual(CatalogBrowsingPreferences.decoded(nil), CatalogBrowsingPreferences())
        XCTAssertEqual(CatalogBrowsingPreferences.decoded(Data("invalid".utf8)), CatalogBrowsingPreferences())
        let future = Data(#"{"version":99,"contexts":{},"preferredKinds":{}}"#.utf8)
        XCTAssertEqual(CatalogBrowsingPreferences.decoded(future), CatalogBrowsingPreferences())
        let partial = try JSONDecoder().decode(CatalogBrowsingState.self, from: Data(#"{"search":"France","catalogPage":-10}"#.utf8))
        XCTAssertEqual(partial.search, "France")
        XCTAssertEqual(partial.catalogPage, 0)
        XCTAssertNil(partial.countryCode)
        XCTAssertFalse(partial.continueOnly)
    }
}
