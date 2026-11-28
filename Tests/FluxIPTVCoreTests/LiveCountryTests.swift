import XCTest
@testable import FluxIPTVCore

final class LiveCountryTests: XCTestCase {
    // Independent ISO 3166-1 alpha-2 fixture: do not derive the expected set
    // from Locale.Region or from the detector under test. Countries and
    // territories are included; TV and SD remain ambiguous bare TV labels.
    // Reference: https://www.iso.org/iso-3166-country-codes.html
    private let isoCountryCodes = """
    AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI
    BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN
    CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK
    FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM
    HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN
    KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK
    ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP
    NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW
    SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF
    TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI
    VN VU WF WS YE YT ZA ZM ZW
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    func testEveryISOCountryAndTerritoryHasDetectablePrefixes() {
        XCTAssertEqual(isoCountryCodes.count, 249)
        XCTAssertEqual(Set(isoCountryCodes).count, 249)
        for code in isoCountryCodes {
            XCTAssertEqual(LiveCountry.detectCode(in: "\(flag(for: code)) | Local"), code, code)
            let expectedBareCode: String? = ["TV", "SD"].contains(code) ? nil : code
            XCTAssertEqual(LiveCountry.detectCode(in: "\(code) | News"), expectedBareCode, code)
            XCTAssertEqual(LiveCountry.detectCode(in: "[\(code.lowercased())] Local"), expectedBareCode, code)
        }
    }

    func testEveryISOCountryAndTerritoryRecognizesFrenchAndEnglishNames() throws {
        for code in isoCountryCodes {
            for locale in [Locale(identifier: "fr_FR"), Locale(identifier: "en_US")] {
                let name = try XCTUnwrap(locale.localizedString(forRegionCode: code), "\(locale.identifier): \(code)")
                XCTAssertEqual(LiveCountry.detectCode(in: "\(name) | Local"), code, "\(code): \(name)")
            }
        }
    }

    func testCatalogContainsAndFiltersEveryISOCountryIndependently() throws {
        let channels = isoCountryCodes.map { code in
            channel("country-\(code)", group: "\(flag(for: code)) | \(code) Local", name: "Channel \(code)")
        }
        let unknown = channel("unclassified", group: "Documentaires", name: "Local documentary")
        let index = CatalogIndex(channels + [unknown])
        XCTAssertEqual(Set(index.liveCountries.map(\.code)), Set(isoCountryCodes + [LiveCountry.unknownCode]))
        XCTAssertEqual(index.liveCountries.count, 250)
        XCTAssertEqual(index.liveCountries.last?.code, LiveCountry.unknownCode)
        for (code, channel) in zip(isoCountryCodes, channels) {
            XCTAssertEqual(index.liveCountries.first(where: { $0.code == code })?.channelCount, 1, code)
            let results = try index.matching(kind: .live, search: "", countryCode: code)
            XCTAssertEqual(results.all.items, [channel], code)
            XCTAssertEqual(results.groups, [channel.group], code)
        }
        XCTAssertEqual(try index.matching(kind: .live, search: "", countryCode: LiveCountry.unknownCode).all.items, [unknown])
    }

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

    func testFilmsAndSeriesAreFilteredByLanguageNotByChannelCountryAndCountAsAnActiveScope() throws {
        let films = (1...3).map { channel("film-\($0)", group: "ES Films", name: "Film \($0)", kind: .movie) },
            series = (1...3).map { channel("series-\($0)", group: "US Series", name: "Série \($0)", kind: .series) }
        let index = CatalogIndex(films + series)
        // Films and series never enter the channel countries; their own
        // filter is the language read from their labels (see MediaLanguageTests).
        XCTAssertTrue(index.liveCountries.isEmpty)
        XCTAssertEqual(index.languages(for: .movie).map(\.code), ["es"])
        XCTAssertEqual(index.languages(for: .series).map(\.code), ["en"])
        XCTAssertEqual(Array(try index.matching(kind: .movie, search: "", countryCode: "es").all.items), films)
        XCTAssertEqual(Array(try index.matching(kind: .series, search: "", countryCode: "en").all.items), series)
        XCTAssertEqual(Array(try index.matching(kind: .movie, search: "").all.items), films)
        // A channel country is not a language of the catalogue: it matches no
        // title, and a remembered one is dropped when the catalogue is known.
        XCTAssertTrue(try index.matching(kind: .movie, search: "", countryCode: "FR").all.items.isEmpty)
        XCTAssertNil(CatalogBrowsingState(countryCode: "FR").validated(kind: .movie, index: index, presets: FavoritePresets()).countryCode)
        XCTAssertTrue(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false))
        XCTAssertFalse(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false, countryCode: "FR"))
        XCTAssertFalse(CatalogScope.isAll(group: nil, search: "", presetID: nil, resumeOnly: false, countryCode: LiveCountry.unknownCode))
    }

    private func flag(for code: String) -> String {
        String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar($0.value - 65 + 0x1F1E6) }))
    }

    private func channel(_ id: String, group: String, name: String, kind: IPTVMediaKind = .live) -> IPTVItem {
        IPTVItem(id: id, sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                 name: name, group: group, logoURL: nil, kind: kind, directURL: nil,
                 xtreamStreamID: nil, fileExtension: nil)
    }
}
