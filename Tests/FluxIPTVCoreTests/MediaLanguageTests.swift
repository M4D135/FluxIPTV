import XCTest
@testable import FluxIPTVCore

final class MediaLanguageTests: XCTestCase {
    private let source = UUID()
    private func title(_ id: Int, _ name: String, _ group: String, _ kind: IPTVMediaKind = .movie) -> IPTVItem {
        IPTVItem(id: "\(kind.rawValue)-\(id)", sourceID: source, name: name, group: group, logoURL: nil, kind: kind,
                 directURL: nil, xtreamStreamID: String(id), fileExtension: "mkv", isSeriesCollection: kind == .series)
    }

    func testLabelsOfTitlesAndCategories() {
        let expected: [(String, String?)] = [
            ("FR - LE DERNIER AJOUT", "fr"), ("FR", "fr"), ("4K-FR", "fr"), ("[FR] Cinéma", "fr"), ("FR| ENFANTS", "fr"),
            ("FRANCE SÉRIES 4K 3840P", "fr"), ("FRANCE NETFLIX 2025", "fr"), ("Français", "fr"), ("VF", "fr"),
            ("EN", "en"), ("EN - Drama", "en"), ("ENGLISH SERIES (TR)", "en"), ("UK | Movies", "en"), ("USA", "en"),
            ("ES - Comedia", "es"), ("ESPAÑA", "es"), ("LATINO", "es"), ("DE", "de"), ("Deutschland Filme", "de"),
            ("IT", "it"), ("PT", "pt"), ("BR - Novelas", "pt"), ("TR", "tr"), ("Türkiye", "tr"),
            ("AR", "ar"), ("ARABIC MOVIES", "ar"), ("GR", "el"), ("AL", "sq"), ("NO - Film", "no"), ("SE - Film", "sv"),
            ("KOREAN DRAMA", "ko"), ("VOSTFR", MediaLanguage.originalCode), ("MULTI", MediaLanguage.multipleCode),
            ("NETFLIX FR", "fr"), ("SKY DE", "de"),
            // No language: brands, quality tags, ordinary words.
            ("AMAZON DOCU-SERIES 4K 3840P", nil), ("4K-AMZ", nil), ("AMZ", nil), ("LE DERNIER AJOUT", nil),
            ("IN CINEMA", nil), ("NO LIMIT", nil), ("LA CASA", nil), ("MY LIST", nil), ("TOP 10", nil),
            ("Mission: Impossible", nil), ("ACTION", nil), ("", nil), ("4K UHD", nil)
        ]
        for (label, code) in expected {
            XCTAssertEqual(MediaLanguage.detectCode(in: label), code, "label « \(label) »")
        }
    }

    func testTitleLabelIsShortAndSetApart() {
        XCTAssertEqual(MediaLanguage.titleLabel(of: "FR - Menteurs Parfaits (2026)"), "FR")
        XCTAssertEqual(MediaLanguage.titleLabel(of: "4K-FR - Game of Thrones (2011) (US)"), "4K-FR")
        XCTAssertEqual(MediaLanguage.titleLabel(of: "EN | Dune"), "EN")
        XCTAssertEqual(MediaLanguage.titleLabel(of: "AMZ - El juego de las llaves"), "AMZ")
        XCTAssertNil(MediaLanguage.titleLabel(of: "Dune"))
        XCTAssertNil(MediaLanguage.titleLabel(of: "Le Seigneur des anneaux - Les deux tours"))
        XCTAssertNil(MediaLanguage.titleLabel(of: "Spider-Man"))
        XCTAssertNil(MediaLanguage.titleLabel(of: " - Sans étiquette"))
    }

    func testNamesAreFrenchAndSpecialEntriesAreExplicit() {
        XCTAssertEqual(MediaLanguage.displayName(for: "fr"), "Français")
        XCTAssertEqual(MediaLanguage.displayName(for: "en"), "Anglais")
        XCTAssertEqual(MediaLanguage.displayName(for: MediaLanguage.unknownCode), "Langue non identifiée")
        XCTAssertEqual(MediaLanguage.displayName(for: MediaLanguage.originalCode), "Version originale")
        XCTAssertEqual(MediaLanguage.displayName(for: MediaLanguage.multipleCode), "Multilingue")
    }

    func testCatalogueFiltersFilmsAndSeriesByLanguage() throws {
        var items: [IPTVItem] = []
        for index in 0..<4 { items.append(title(index, "FR - Film \(index)", "FR - COMEDIE")) }
        for index in 4..<8 { items.append(title(index, "EN - Movie \(index)", "ENGLISH MOVIES")) }
        // A category label applies when the title has none.
        items.append(title(8, "Sans étiquette", "FR - DRAME"))
        // A label used by fewer titles than the threshold is part of a title,
        // and a language found on fewer titles than that is not offered.
        items.append(title(9, "It - Chapter Two", "HORROR"))
        items.append(title(20, "Vientiane", "LA - CINEMA"))
        items.append(title(10, "AMZ - El juego", "AMAZON SERIES", .series))
        for index in 11..<14 { items.append(title(index, "4K-FR - Série \(index)", "FRANCE SÉRIES 4K", .series)) }
        items.append(IPTVItem(id: "live-1", sourceID: source, name: "FR: TF1", group: "FR | Généralistes", logoURL: nil, kind: .live,
                              directURL: nil, xtreamStreamID: "1", fileExtension: "m3u8"))
        let index = CatalogIndex(items)

        XCTAssertEqual(index.languages(for: .movie).map(\.code), ["en", "fr", MediaLanguage.unknownCode])
        XCTAssertEqual(index.languages(for: .movie).map(\.titleCount), [4, 5, 2])
        XCTAssertEqual(index.language(of: items.first(where: { $0.id == "movie-20" })!), MediaLanguage.unknownCode)
        XCTAssertEqual(index.languages(for: .series).map(\.code), ["fr", MediaLanguage.unknownCode])
        XCTAssertTrue(index.languages(for: .live).isEmpty)
        XCTAssertNil(index.language(of: items.last!))
        XCTAssertEqual(index.language(of: items[9]), MediaLanguage.unknownCode)

        let french = try index.matching(kind: .movie, search: "", countryCode: "fr")
        XCTAssertEqual(french.all.items.map(\.id), ["movie-0", "movie-1", "movie-2", "movie-3", "movie-8"])
        XCTAssertEqual(french.groups, ["FR - COMEDIE", "FR - DRAME"])
        XCTAssertEqual(try index.matching(kind: .movie, search: "movie 5", countryCode: "en").all.items.map(\.id), ["movie-5"])
        XCTAssertEqual(try index.matching(kind: .movie, search: "", countryCode: MediaLanguage.unknownCode).all.items.map(\.id), ["movie-9", "movie-20"])
        XCTAssertEqual(try index.matching(kind: .series, search: "", countryCode: "fr").all.items.count, 3)
        // The channels keep their own filter by country.
        XCTAssertEqual(try index.matching(kind: .live, search: "", countryCode: "FR").all.items.map(\.id), ["live-1"])
        XCTAssertTrue(index.category("FR - DRAME", of: .movie, has: "fr"))
        XCTAssertFalse(index.category("ENGLISH MOVIES", of: .movie, has: "fr"))
    }

    func testRememberedLanguageIsValidatedAgainstTheCatalogue() {
        var items: [IPTVItem] = []
        for index in 0..<3 { items.append(title(index, "FR - Film \(index)", "FR - COMEDIE")) }
        for index in 3..<6 { items.append(title(index, "EN - Movie \(index)", "ENGLISH MOVIES")) }
        let index = CatalogIndex(items), presets = FavoritePresets()
        let kept = CatalogBrowsingState(countryCode: "fr", group: "FR - COMEDIE", browseItemID: "movie-1")
            .validated(kind: .movie, index: index, presets: presets)
        XCTAssertEqual(kept.countryCode, "fr")
        XCTAssertEqual(kept.group, "FR - COMEDIE")
        XCTAssertEqual(kept.browseItemID, "movie-1")
        let mismatched = CatalogBrowsingState(countryCode: "fr", group: "ENGLISH MOVIES", browseItemID: "movie-4")
            .validated(kind: .movie, index: index, presets: presets)
        XCTAssertEqual(mismatched.countryCode, "fr")
        XCTAssertNil(mismatched.group)
        XCTAssertNil(mismatched.browseItemID)
        let gone = CatalogBrowsingState(countryCode: "de").validated(kind: .movie, index: index, presets: presets)
        XCTAssertNil(gone.countryCode)
    }
}
