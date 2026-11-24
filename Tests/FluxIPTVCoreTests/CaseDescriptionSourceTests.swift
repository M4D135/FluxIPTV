import XCTest
import Foundation
@testable import FluxIPTVCore

final class CaseDescriptionSourceTests: XCTestCase {
    private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    private func page(_ title: String, extract: String, url: String = "https://fr.wikipedia.org/wiki/Azur",
                      entity: String = "Q123") -> [String: Any] {
        ["title": title, "extract": extract, "fullurl": url, "pageprops": ["wikibase_item": entity]]
    }

    private func pages(_ values: [[String: Any]]) throws -> Data { try json(["query": ["pages": values]]) }

    private func claim(_ value: Any, rank: String = "normal") -> [String: Any] {
        ["rank": rank, "mainsnak": ["snaktype": "value", "datavalue": ["value": value]]]
    }

    private func time(_ year: String, precision: Int = 11) -> [String: Any] {
        ["time": "+\(year)-01-01T00:00:00Z", "precision": precision]
    }

    private func script(_ object: Any) throws -> String {
        "<script type='application/ld+json'>\(String(decoding: try json(object), as: UTF8.self))</script>"
    }

    func testSourceSelectionCyclesThroughTheThreeNamedSources() {
        XCTAssertEqual(CaseDescriptionSource.allCases, [.iptv, .allocine, .wikipedia])
        XCTAssertEqual(CaseDescriptionSource.iptv.next(delta: -1), .wikipedia)
        XCTAssertEqual(CaseDescriptionSource.wikipedia.next(delta: 1), .iptv)
        XCTAssertEqual(CaseDescriptionSource.allocine.next(delta: 3), .allocine)
        XCTAssertEqual(CaseDescriptionSource.iptv.next(delta: Int.min), .allocine)
        XCTAssertEqual(CaseDescriptionSource.wikipedia.next(delta: Int.max), .iptv)
    }

    func testTitleNormalizationRemovesProviderLabelsAndExplicitDisambiguators() {
        XCTAssertEqual(CaseDescriptionParser.titleKey("[VF] Amélie [UHD]"), "amelie")
        XCTAssertEqual(CaseDescriptionParser.titleKey("Amélie (film, 2001)"), "amelie")
        XCTAssertEqual(CaseDescriptionParser.titleKey("Amélie (2001)"), "amelie")
        XCTAssertEqual(CaseDescriptionParser.titleKey("L’Été & l’hiver"), "letelhiver")
        XCTAssertEqual(CaseDescriptionParser.titleKey("Azur (série télévisée)"), "azur")
    }

    func testNumericMovieTitlesAndNumbersBelongingToTheTitleStayDistinct() {
        XCTAssertEqual(CaseDescriptionParser.titleKey("2012"), "2012")
        XCTAssertEqual(CaseDescriptionParser.titleKey("1917"), "1917")
        XCTAssertEqual(CaseDescriptionParser.titleKey("2001, l’Odyssée de l’espace"), "2001lodysseedelespace")
        XCTAssertEqual(CaseDescriptionParser.titleKey("Blade Runner 2049"), "bladerunner2049")
        XCTAssertNotEqual(CaseDescriptionParser.titleKey("Blade Runner"), CaseDescriptionParser.titleKey("Blade Runner 2049"))
        XCTAssertNotEqual(CaseDescriptionParser.titleKey("2012"), CaseDescriptionParser.titleKey("1917"))
    }

    func testYearExtractionAcceptsDatesButNotAnEmbeddedPartOfALongerNumber() {
        XCTAssertEqual(CaseDescriptionParser.year("2024-05-12"), "2024")
        XCTAssertEqual(CaseDescriptionParser.year("+1997-00-00T00:00:00Z"), "1997")
        XCTAssertNil(CaseDescriptionParser.year("120123"))
        XCTAssertNil(CaseDescriptionParser.year("inconnue"))
        XCTAssertNil(CaseDescriptionParser.year(nil))
    }

    func testWikipediaCandidatesRequireExactNormalizedTitleAndApprovedOrigin() throws {
        let good = page("Amélie (film, 2001)", extract: "Amélie est un film français sorti en 2001.")
        let other = page("Amélie 2", extract: "Amélie 2 est un film français.")
        let badOrigin = page("Amélie", extract: "Amélie est un film français.", url: "https://example.test/wiki/Amelie")
        let candidates = CaseDescriptionParser.wikipediaCandidates(try pages([good, other, badOrigin]), name: "[VF] Amélie (2001)", series: false)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.entityID, "Q123")
        XCTAssertEqual(candidates.first?.title, "Amélie (film, 2001)")
        XCTAssertTrue(CaseDescriptionParser.wikipediaCandidates(Data("not json".utf8), name: "Amélie", series: false).isEmpty)
    }

    func testWikipediaRejectsMissingPagesAndDisambiguationAndDoesNotTrustInvalidEntityIDs() throws {
        var missing = page("Azur", extract: "Azur est un film français.")
        missing["missing"] = true
        var disambiguation = page("Azur", extract: "Azur est un film et un nom de couleur.")
        disambiguation["pageprops"] = ["disambiguation": "", "wikibase_item": "Q123"]
        let invalidEntity = page("Azur", extract: "Azur est un film français.", entity: "Q123&ids=Q456")
        let result = CaseDescriptionParser.wikipediaCandidates(try pages([missing, disambiguation, invalidEntity]), name: "Azur", series: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.entityID)
    }

    func testMediaTypeCannotBeInferredFromAnIncidentalMentionOfAFilmOrSeries() throws {
        let film = page("Azur (film)", extract: "Azur est un film d’animation français réalisé en 2020.")
        let series = page("Azur (série télévisée)", extract: "Azur est une série télévisée française créée en 2020.")
        let gameFilm = page("Azur", extract: "Azur est un jeu vidéo inspiré du film homonyme et sorti en 2020.")
        let gameSeries = page("Azur", extract: "Azur est un jeu vidéo adapté d’une série télévisée française.")
        let productionCompany = page("Azur", extract: "Azur est une société de production de films et de séries.")
        let data = try pages([film, series, gameFilm, gameSeries, productionCompany])
        let films = CaseDescriptionParser.wikipediaCandidates(data, name: "Azur", series: false)
        let shows = CaseDescriptionParser.wikipediaCandidates(data, name: "Azur", series: true)
        XCTAssertEqual(films.map(\.title), ["Azur (film)"])
        XCTAssertEqual(shows.map(\.title), ["Azur (série télévisée)"])
    }

    func testWikidataYearsIgnoreDeprecatedClaimsAndDatesLessPreciseThanAYear() throws {
        let claims: [String: Any] = [
            "P577": [claim(time("2019")), claim(time("2018"), rank: "deprecated"), claim(time("2030", precision: 8))],
            "P580": [claim(time("2020", precision: 9))]
        ]
        let data = try json(["entities": ["Q123": ["claims": claims], "Q456": ["claims": ["P577": [claim(time("2001"))]]]]])
        let selected = CaseDescriptionParser.claims(data, entityID: "Q123")
        XCTAssertEqual(CaseDescriptionParser.releaseYears(selected), Set(["2019", "2020"]))
        XCTAssertTrue(CaseDescriptionParser.claims(data, entityID: "Q999").isEmpty)
        XCTAssertTrue(CaseDescriptionParser.claims(Data("broken".utf8), entityID: "Q123").isEmpty)
    }

    func testAllocineIdentifiersUseTheRightPropertyAndRejectAmbiguousOrInjectedIDs() {
        let claims: [String: Any] = [
            "P1265": [claim("1234"), claim("7654", rank: "deprecated")],
            "P1267": [claim("5678")]
        ]
        XCTAssertEqual(CaseDescriptionParser.allocineURL(claims, series: false)?.absoluteString, "https://www.allocine.fr/film/fichefilm_gen_cfilm=1234.html")
        XCTAssertEqual(CaseDescriptionParser.allocineURL(claims, series: true)?.absoluteString, "https://www.allocine.fr/series/ficheserie_gen_cserie=5678.html")
        XCTAssertNil(CaseDescriptionParser.allocineURL(["P1265": [claim("1234"), claim("7777")]], series: false))
        XCTAssertNil(CaseDescriptionParser.allocineURL(["P1265": [claim("1234&redirect=bad")]], series: false))
        XCTAssertNil(CaseDescriptionParser.allocineURL(["P1265": [claim("1234")]], series: true))
    }

    func testAllocineParsesGraphAndArrayTypesButRequiresCorrectKindAndTitle() throws {
        let graph: [String: Any] = ["@graph": [
            ["@type": "WebSite", "name": "Allociné"],
            ["@type": ["CreativeWork", "Movie"], "name": "Amélie", "description": "<p>Amélie &amp; Nino &#x2014; deux amis.</p>"],
            ["@type": "TVSeries", "name": "Autre série", "description": "Une autre histoire."]
        ]]
        let html = try script(graph)
        let result = CaseDescriptionParser.allocineDescription(html, expectedTitle: "Amélie (film, 2001)", series: false)
        XCTAssertEqual(result?.title, "Amélie")
        XCTAssertEqual(result?.text, "Amélie & Nino — deux amis.")
        XCTAssertNil(CaseDescriptionParser.allocineDescription(html, expectedTitle: "Amélie", series: true))
        XCTAssertNil(CaseDescriptionParser.allocineDescription(html, expectedTitle: "Autre film", series: false))
        XCTAssertNil(CaseDescriptionParser.allocineDescription("<html>Aucun synopsis structuré</html>", expectedTitle: "Amélie", series: false))
    }

    func testAllocineConflictingEntriesWithTheSameTitleAreAmbiguous() throws {
        let first: [String: Any] = ["@type": "Movie", "name": "Dune", "description": "Synopsis de la première adaptation."]
        let second: [String: Any] = ["@type": "Movie", "name": "Dune", "description": "Synopsis d’une autre adaptation."]
        let ambiguousHTML = try script([first, second])
        XCTAssertNil(CaseDescriptionParser.allocineDescription(ambiguousHTML, expectedTitle: "Dune", series: false))
        let duplicatedHTML = try script([first, first])
        XCTAssertEqual(CaseDescriptionParser.allocineDescription(duplicatedHTML, expectedTitle: "Dune", series: false)?.text, "Synopsis de la première adaptation.")
    }

    func testPlainTextDecodesMarkupAndDecimalAndBothHexEntityForms() {
        XCTAssertEqual(CaseDescriptionParser.plainText(" <p>L&apos;été &amp; l’hiver&nbsp;: &#8212; &#x2014; &#X2014;</p> "), "L'été & l’hiver : — — —")
        XCTAssertEqual(CaseDescriptionParser.plainText("  une\n  histoire \t  "), "une histoire")
    }

    func testIPTVSourceNeverBorrowsExternalDescriptions() async throws {
        let service = CaseDescriptionService()
        let result = try await service.entry(name: "[VF] Azur", year: "2020", series: false, source: .iptv)
        XCTAssertEqual(result.title, "Azur")
        XCTAssertEqual(result.text, "")
        XCTAssertNil(result.sourceURL)
    }
}
