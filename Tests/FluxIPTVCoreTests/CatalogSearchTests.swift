import XCTest
@testable import FluxIPTVCore

/// The search of the catalogue on folded bytes finds what
/// `localizedStandardContains` found on each title, and the parts of the
/// catalogue read their titles from it without copying them.
final class CatalogSearchTests: XCTestCase {
    private let source = UUID()

    private func item(_ id: String, _ name: String, group: String, kind: IPTVMediaKind = .movie) -> IPTVItem {
        IPTVItem(id: id, sourceID: source, name: name, group: group, logoURL: nil, kind: kind, directURL: nil,
                 xtreamStreamID: id, fileExtension: "mkv")
    }

    private var catalogue: [IPTVItem] {
        let names = ["Été à Paris", "ÉTÉ INDIEN", "Le Château", "chateau fort", "Cœur de pierre", "Straße der Erinnerung",
                     "Ｆｕｌｌ Ｗｉｄｔｈ", "Full Width", "L'Étoile du Nord", "Ça commence", "Mañana", "MAÑANA",
                     "Tokyo 東京", "Δελφοί", "ДОКУМЕНТЫ", "naïve", "NAIVE", "Zoë", "", "  espaces  "]
        let groups = ["FR | FILMS ACTION", "fr | films drame", "Québec", "QUEBEC", "Séries Été", "Ｗｉｄｅ", "Документы"]
        var items: [IPTVItem] = []
        for (i, name) in names.enumerated() {
            items.append(item("m\(i)", name, group: groups[i % groups.count]))
            items.append(item("s\(i)", name + " S01", group: groups[(i + 3) % groups.count], kind: .series))
            items.append(item("l\(i)", name + " HD", group: groups[(i + 5) % groups.count], kind: .live))
        }
        return items
    }

    func testTheFoldedSearchFindsWhatTheLocalizedSearchFound() throws {
        let items = catalogue
        let index = CatalogIndex(items)
        let terms = ["ete", "Été", "ÉTÉ", "chateau", "CHÂTEAU", "coeur", "cœur", "strasse", "straße", "full", "ｆｕｌｌ",
                     "etoile", "ca", "ça", "manana", "MAÑANA", "東京", "δελ", "документ", "naive", "naïve", "zoe",
                     "fr | films", "quebec", "québec", "séries", "wide", "s01", " hd ", "e", "zzz", "'"]
        for kind in IPTVMediaKind.allCases {
            for term in terms {
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                let expected = items.filter { $0.kind == kind }
                    .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) || $0.group.localizedStandardContains(trimmed) }
                    .map(\.id)
                let found = try index.matching(kind: kind, search: term)
                XCTAssertEqual(found.all.items.map(\.id), expected, "\(kind) \"\(term)\"")
                XCTAssertEqual(try index.count(kind: kind, search: term), expected.count, "\(kind) \"\(term)\"")
            }
        }
    }

    func testSearchResultsKeepTheirCategoriesAndPositions() throws {
        let index = CatalogIndex(catalogue)
        let found = try index.matching(kind: .movie, search: "e")
        XCTAssertEqual(found.groups, found.groups.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        var seen = 0
        for group in found.groups {
            let part = found.slice(group: group)
            XCTAssertFalse(part.items.isEmpty)
            XCTAssertTrue(part.items.allSatisfy { $0.group == group })
            for (position, item) in part.items.enumerated() {
                XCTAssertEqual(part.index(of: item.id), position)
                XCTAssertEqual(found.all.item(id: item.id), item)
            }
            seen += part.items.count
        }
        XCTAssertEqual(seen, found.all.items.count)
        // A title of another kind, or that the search left out, is no part of the result.
        XCTAssertNil(found.all.index(of: "l0"))
        XCTAssertNil(found.slice(group: "Absente").index(of: "m0"))
    }

    func testPartsOfTheCatalogueReadTheirTitlesWithoutCopies() {
        let items = (0..<500).map { item("m\($0)", "Film \($0)", group: "Rayon \($0 % 7)") }
        let index = CatalogIndex(items)
        let rayon = index.unfiltered(.movie).slice(group: "Rayon 3")
        XCTAssertEqual(rayon.items.map(\.id), items.filter { $0.group == "Rayon 3" }.map(\.id))
        // A page of a part, and the titles of a part that a history keeps.
        let page = rayon.window(page: 1, size: 20)
        XCTAssertEqual(page.map(\.id), Array(rayon.items.map(\.id)[20..<40]))
        XCTAssertEqual(page.first?.id, rayon.items[20].id)
        XCTAssertEqual(rayon.window(page: 99, size: 20).last?.id, rayon.items.last?.id)
        let kept = rayon.retaining(ids: ["m3", "m80", "m4", "missing", rayon.items[30].id])
        XCTAssertEqual(kept.items.map(\.id), ["m3", "m80", rayon.items[30].id])
        XCTAssertEqual(kept.index(of: "m80"), 1)
        XCTAssertNil(kept.index(of: "m10"))
        XCTAssertEqual(kept.adjacent(to: "m3", offset: 2)?.id, rayon.items[30].id)
        // Parts compare by their titles.
        XCTAssertEqual(index.unfiltered(.movie).all.items, CatalogItems(items))
        XCTAssertNotEqual(rayon.items, kept.items)
    }

    func testLanguagesAndCountriesFilterTheSearch() throws {
        let films = [item("es1", "ES - La Casa", group: "Cine"), item("es2", "ES - El Viaje", group: "Cine"),
                     item("es3", "ES - Casa Grande", group: "Cine"), item("en1", "EN - The House", group: "Cinema"),
                     item("en2", "EN - Casa Blanca", group: "Cinema"), item("en3", "EN - The Road", group: "Cinema")]
        let channels = [item("fr1", "Canal Casa", group: "FR | Généralistes", kind: .live),
                        item("es9", "Casa TV", group: "ES - Deportes", kind: .live)]
        let index = CatalogIndex(films + channels)
        XCTAssertEqual(try index.matching(kind: .movie, search: "casa", countryCode: "es").all.items.map(\.id), ["es1", "es3"])
        XCTAssertEqual(try index.matching(kind: .movie, search: "casa", countryCode: "en").all.items.map(\.id), ["en2"])
        XCTAssertEqual(try index.matching(kind: .movie, search: "", countryCode: "en", ).all.items.count, 3)
        XCTAssertTrue(try index.matching(kind: .movie, search: "casa", countryCode: "zz").all.items.isEmpty)
        XCTAssertEqual(try index.matching(kind: .live, search: "casa", countryCode: "FR").all.items.map(\.id), ["fr1"])
        XCTAssertEqual(try index.matching(kind: .live, search: "casa", membership: ["es9", "es1"]).all.items.map(\.id), ["es9"])
        XCTAssertEqual(index.language(of: films[0]), "es")
        XCTAssertNil(index.language(of: channels[0]))
    }

    func testTheSearchOfOneTitleFoldsAsTheIndexDoes() {
        XCTAssertTrue(CatalogSearch.matches("Le Château", term: "chateau"))
        XCTAssertTrue(CatalogSearch.matches("ÉTÉ", term: " été "))
        // Widths are kept, as `localizedStandardContains` kept them.
        XCTAssertFalse(CatalogSearch.matches("Ｆｕｌｌ", term: "full"))
        XCTAssertTrue(CatalogSearch.matches("Ｆｕｌｌ", term: "ｆｕｌｌ"))
        XCTAssertTrue(CatalogSearch.matches("Quoi", term: "   "))
        XCTAssertFalse(CatalogSearch.matches("Automne", term: "ete"))
    }
}
