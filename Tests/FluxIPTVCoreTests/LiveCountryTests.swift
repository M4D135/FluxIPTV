import XCTest
@testable import FluxIPTVCore

final class LiveCountryTests: XCTestCase {
    func testDelimitedCodesAndFlags() {
        let categories = [
            "FR": "FR", "FR | Généralistes": "FR", "[FR] Sport": "FR",
            "  | fr | cinéma": "FR", "(ES) Cine": "ES", "ES-Cine": "ES",
            "UK: News": "GB", "[USA] Movies": "US", "US / News": "US",
            "DE_Deutschland": "DE", "PT • Notícias": "PT", "CA | Québec": "CA",
            "🇫🇷 Français": "FR", "[🇪🇸] Cine": "ES", "📺 🇬🇧 News": "GB",
            "🇸🇩 News": "SD", "🇹🇻 Local": "TV"
        ]
        for (category, expected) in categories {
            XCTAssertEqual(LiveCountry.detectCode(in: category), expected, category)
        }
    }

    func testNamesAndEndonymsAreRecognizedWithWholePrefixBoundaries() {
        let categories = [
            "France · Généralistes": "FR", "Espagne - Cinéma": "ES", "España | Cine": "ES",
            "Deutschland | Sport": "DE", "Belgique | Infos": "BE", "États-Unis | News": "US",
            "United States of America / News": "US", "Royaume Uni - Cinéma": "GB",
            "La Réunion - Local": "RE", "South Africa | Sport": "ZA", "Brasil | Futebol": "BR",
            "Soudan | News": "SD", "Tuvalu | Local": "TV"
        ]
        for (category, expected) in categories {
            XCTAssertEqual(LiveCountry.detectCode(in: category), expected, category)
        }
    }

    func testUnrelatedWordsAndLanguagesNeverBecomeCountryPrefixes() {
        for category in ["", "  ", "---", "FRONTIÈRE", "ESport", "ARTE", "INTERNATIONAL",
                         "Cinéma FR", "Sport [ES]", "FR2 Sports", "USAHD", "FranceTV",
                         "EN | News", "FRENCH | Cinema", "Arabic | News", "[ZZ] Unknown", "🇿🇿 Unknown",
                         "TV | Généralistes", "[TV] General", "SD | Sport", "HD | Sport", "4K | Sport",
                         "EU | News", "EZ | News"] {
            XCTAssertNil(LiveCountry.detectCode(in: category), category)
        }
    }

    func testCountryOptionsComeFromCompleteUniqueLiveCatalog() throws {
        let fr = channel("fr-one", group: "FR | Généralistes", name: "Journal"),
            frSport = channel("fr-sport", group: "[FR] Sport", name: "Sport"),
            es = channel("es-one", group: "ES - Noticias", name: "Journal"),
            unknown = channel("unknown", group: "International", name: "Journal"),
            movie = channel("movie", group: "US | Movies", name: "Journal", kind: .movie)
        let index = CatalogIndex([fr, es, frSport, unknown, movie, fr])
        let counts = Dictionary(uniqueKeysWithValues: index.liveCountries.map { ($0.code, $0.channelCount) })
        XCTAssertEqual(counts, ["FR": 2, "ES": 1, LiveCountry.unknownCode: 1])
        XCTAssertEqual(index.liveCountries.last?.code, LiveCountry.unknownCode)
        XCTAssertEqual(index.liveCountries.first(where: { $0.code == "FR" })?.name, "France")
        XCTAssertEqual(index.liveCountries.last?.name, "Pays non identifié")
        XCTAssertEqual(try index.matching(kind: .live, search: "absent", countryCode: "FR").all.items.count, 0)
        XCTAssertEqual(index.liveCountries.count, 3, "An empty search result must not hide other countries.")
    }

    func testCountryCombinesWithSearchFavoritesAndOriginalGroups() throws {
        let frNews = channel("fr-news", group: "FR | Généralistes", name: "Journal"),
            esNews = channel("es-news", group: "ES - Noticias", name: "Journal"),
            frSport = channel("fr-sport", group: "[FR] Sport", name: "Sport"),
            frCinema = channel("fr-cinema", group: "FR | Cinéma", name: "Cinéma"),
            unknown = channel("unknown", group: "International", name: "Journal")
        let index = CatalogIndex([frNews, esNews, frSport, frCinema, unknown])
        let french = try index.matching(kind: .live, search: "", countryCode: "FR")
        XCTAssertEqual(french.all.items, [frNews, frSport, frCinema])
        XCTAssertEqual(Set(french.groups), ["FR | Généralistes", "[FR] Sport", "FR | Cinéma"])
        XCTAssertEqual(french.slice(group: "[FR] Sport").items, [frSport])
        XCTAssertEqual(try index.matching(kind: .live, search: "journal", membership: [frNews.id, esNews.id, frSport.id], countryCode: "FR").all.items, [frNews])
        XCTAssertEqual(try index.matching(kind: .live, search: "cinema", countryCode: "FR").all.items, [frCinema])
        XCTAssertEqual(try index.matching(kind: .live, search: "", countryCode: LiveCountry.unknownCode).all.items, [unknown])
        XCTAssertEqual(try index.matching(kind: .live, search: "").all.items.count, 5)
        XCTAssertTrue(try index.matching(kind: .live, search: "", countryCode: "DE").all.items.isEmpty)
        XCTAssertTrue(try index.matching(kind: .live, search: "", membership: [], countryCode: "FR").all.items.isEmpty)
    }

    func testCountryNeverFiltersFilmsOrSeriesAndCountsAsAnActiveScope() throws {
        let film = channel("film", group: "ES Films", name: "Film", kind: .movie),
            series = channel("series", group: "US Series", name: "Série", kind: .series)
        let index = CatalogIndex([film, series])
        XCTAssertTrue(index.liveCountries.isEmpty)
        XCTAssertEqual(try index.matching(kind: .movie, search: "", countryCode: "FR").all.items, [film])
        XCTAssertEqual(try index.matching(kind: .series, search: "", countryCode: "FR").all.items, [series])
        XCTAssertTrue(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false))
        XCTAssertFalse(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false, countryCode: "FR"))
        XCTAssertFalse(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false, countryCode: LiveCountry.unknownCode))
    }

    private func channel(_ id: String, group: String, name: String, kind: IPTVMediaKind = .live) -> IPTVItem {
        IPTVItem(id: id, sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                 name: name, group: group, logoURL: nil, kind: kind, directURL: nil,
                 xtreamStreamID: nil, fileExtension: nil)
    }
}
