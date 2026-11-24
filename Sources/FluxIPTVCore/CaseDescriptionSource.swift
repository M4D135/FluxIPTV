import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CaseDescriptionSource: String, CaseIterable, Identifiable, Sendable {
    case iptv, allocine, wikipedia
    public var id: String { rawValue }
    public var title: String {
        switch self { case .iptv: "IPTV"; case .allocine: "Allociné"; case .wikipedia: "Wikipédia" }
    }
    public func next(delta: Int) -> Self {
        let cases = Self.allCases, index = cases.firstIndex(of: self) ?? 0
        return cases[(index + delta % cases.count + cases.count) % cases.count]
    }
}

public struct CaseDescriptionEntry: Equatable, Sendable {
    public let title: String
    public let text: String
    public let sourceURL: URL?
    public let status: String?
    public init(title: String, text: String, sourceURL: URL? = nil, status: String? = nil) {
        self.title = title; self.text = text; self.sourceURL = sourceURL; self.status = status
    }
}

public struct CaseWikiCandidate: Equatable, Sendable {
    public let title: String
    public let extract: String
    public let url: URL
    public let entityID: String?
}

/// Deliberately conservative matching. A missing or ambiguous source stays
/// unavailable rather than silently borrowing another site's description.
public enum CaseDescriptionParser {
    public static func titleKey(_ value: String) -> String {
        var value = CinemaLinks.title(value)
        value = value.replacingOccurrences(of: #"\s*\((?:film|série télévisée|serie televisee|série|serie)(?:[^)]*)\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\s*[\[(](?:19|20)\d{2}[\])]\s*$"#, with: "", options: .regularExpression)
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    public static func year(_ value: String?) -> String? {
        guard let value, let range = value.range(of: #"(?<![0-9])(?:19|20)\d{2}(?![0-9])"#, options: .regularExpression) else { return nil }
        return String(value[range])
    }

    public static func wikipediaCandidates(_ data: Data, name: String, series: Bool) -> [CaseWikiCandidate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = root["query"] as? [String: Any], let pages = query["pages"] as? [[String: Any]] else { return [] }
        return pages.compactMap { page in
            let props = page["pageprops"] as? [String: Any] ?? [:]
            guard page["missing"] == nil, props["disambiguation"] == nil,
                  let title = page["title"] as? String, titleKey(title) == titleKey(name),
                  let extract = page["extract"] as? String, !extract.isEmpty,
                  let rawURL = page["fullurl"] as? String, let url = URL(string: rawURL),
                  url.scheme == "https", url.host == "fr.wikipedia.org" else { return nil }
            let intro = String(extract.prefix(700)).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            let definition = series
                ? #"^[^.!?]{0,240}\b(?:est|etait)\s+une\s+(?:serie televisee|mini[ -]serie)\b"#
                : #"^[^.!?]{0,240}\b(?:est|etait)\s+un\s+(?:film|(?:court|moyen|long)[ -]metrage)\b"#
            let correctKind = intro.range(of: definition, options: .regularExpression) != nil
            guard correctKind else { return nil }
            let rawEntity = props["wikibase_item"] as? String
            let entity = rawEntity.flatMap { $0.range(of: #"^Q[1-9][0-9]*$"#, options: .regularExpression) != nil ? $0 : nil }
            return CaseWikiCandidate(title: title, extract: String(extract.prefix(4000)), url: url, entityID: entity)
        }
    }

    public static func claims(_ data: Data, entityID: String) -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = root["entities"] as? [String: Any], let entity = entities[entityID] as? [String: Any] else { return [:] }
        return entity["claims"] as? [String: Any] ?? [:]
    }

    public static func releaseYears(_ claims: [String: Any]) -> Set<String> {
        Set(["P577", "P580"].flatMap { property in
            (claims[property] as? [[String: Any]] ?? []).compactMap { claim -> String? in
                guard claim["rank"] as? String != "deprecated",
                      let snak = claim["mainsnak"] as? [String: Any], let value = snak["datavalue"] as? [String: Any],
                      let timestamp = value["value"] as? [String: Any],
                      let precision = timestamp["precision"] as? Int, precision >= 9,
                      let time = timestamp["time"] as? String else { return nil }
                return year(time)
            }
        })
    }

    /// Official Wikidata properties: P1265 (film), P1267 (series). These are
    /// identifiers linked to the verified work, never guessed search result IDs.
    public static func allocineURL(_ claims: [String: Any], series: Bool) -> URL? {
        let property = series ? "P1267" : "P1265"
        let ids = Set((claims[property] as? [[String: Any]] ?? []).compactMap { claim -> String? in
            guard claim["rank"] as? String != "deprecated",
                  let snak = claim["mainsnak"] as? [String: Any], let data = snak["datavalue"] as? [String: Any],
                  let id = data["value"] as? String, id.range(of: #"^[0-9]{1,14}$"#, options: .regularExpression) != nil else { return nil }
            return id
        })
        guard ids.count == 1, let id = ids.first else { return nil }
        return URL(string: series ? "https://www.allocine.fr/series/ficheserie_gen_cserie=\(id).html" : "https://www.allocine.fr/film/fichefilm_gen_cfilm=\(id).html")
    }

    public static func allocineDescription(_ html: String, expectedTitle: String, series: Bool, expectedURL: URL? = nil) -> (title: String, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"<script\b[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>([\s\S]*?)</script>"#, options: .caseInsensitive) else { return nil }
        func entries(_ object: Any) -> [[String: Any]] {
            if let array = object as? [Any] { return array.flatMap(entries) }
            guard let item = object as? [String: Any] else { return [] }
            return [item] + ((item["@graph"] as? [Any])?.flatMap(entries) ?? [])
        }
        var matches: [(title: String, text: String)] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html), let data = String(html[range]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for entry in entries(json) {
                let types = (entry["@type"] as? [String]) ?? (entry["@type"] as? String).map { [$0] } ?? []
                guard types.contains(series ? "TVSeries" : "Movie"),
                      let title = entry["name"] as? String, titleKey(plainText(title)) == titleKey(expectedTitle),
                      let description = entry["description"] as? String else { continue }
                if let expectedURL, let advertised = entry["url"] as? String,
                   let url = URL(string: advertised, relativeTo: expectedURL)?.absoluteURL,
                   allocineIdentifier(url, series: series) != allocineIdentifier(expectedURL, series: series) { continue }
                let text = plainText(description)
                guard !text.isEmpty else { continue }
                matches.append((plainText(title), String(text.prefix(4000))))
            }
        }
        guard Set(matches.map(\.text)).count == 1 else { return nil }
        return matches.first
    }

    public static func allocineIdentifier(_ url: URL, series: Bool) -> String? {
        guard url.scheme == "https", ["www.allocine.fr", "allocine.fr"].contains(url.host ?? "") else { return nil }
        let pattern = series ? #"^/series/ficheserie(?:_gen_cserie=|-)([0-9]{1,14})(?:\.html|/.*)?$"# : #"^/film/fichefilm(?:_gen_cfilm=|-)([0-9]{1,14})(?:\.html|/.*)?$"#
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else { return nil }
        return String(path[range])
    }

    public static func plainText(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
        for (entity, value) in entities { clean = clean.replacingOccurrences(of: entity, with: value) }
        if let regex = try? NSRegularExpression(pattern: #"&#([xX][0-9a-fA-F]+|[0-9]+);"#) {
            for match in regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).reversed() {
                guard let full = Range(match.range, in: clean), let numberRange = Range(match.range(at: 1), in: clean) else { continue }
                let raw = String(clean[numberRange]), hex = raw.lowercased().hasPrefix("x")
                if let number = UInt32(hex ? String(raw.dropFirst()) : raw, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { clean.replaceSubrange(full, with: String(scalar)) }
            }
        }
        return clean.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// External metadata is fetched only after the viewer selects that source.
/// Requests contain the public title/year, never IPTV URLs or credentials.
public actor CaseDescriptionService {
    public static let shared = CaseDescriptionService()
    private var cache: [String: CaseDescriptionEntry] = [:]
    private var order: [String] = []
    public init() {}

    public func entry(name: String, year: String?, series: Bool, source: CaseDescriptionSource) async throws -> CaseDescriptionEntry {
        let cleaned = CinemaLinks.title(name), requestedYear = CaseDescriptionParser.year(year)
        let key = "\(source.rawValue)|\(series)|\(cleaned)|\(requestedYear ?? "")"
        if let saved = cache[key] { return saved }
        guard source != .iptv else { return CaseDescriptionEntry(title: cleaned, text: "") }
        let searchURL = CinemaLinks.url(for: source == .wikipedia ? .wikipedia : .allocine, name: cleaned, year: year, series: series)
        func unavailable(_ status: String) -> CaseDescriptionEntry { CaseDescriptionEntry(title: cleaned, text: "", sourceURL: searchURL, status: status) }
        var components = URLComponents(string: "https://fr.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "search"), .init(name: "gsrlimit", value: "8"),
            .init(name: "gsrsearch", value: String(cleaned.prefix(180)) + (series ? " série télévisée" : " film")),
            .init(name: "prop", value: "extracts|pageprops|info"), .init(name: "exintro", value: "1"),
            .init(name: "explaintext", value: "1"), .init(name: "exlimit", value: "8"),
            .init(name: "inprop", value: "url")
        ]
        let data = try await fetch(components.url!)
        var candidates = CaseDescriptionParser.wikipediaCandidates(data, name: cleaned, series: series)
        guard !candidates.isEmpty else { return unavailable("Aucune fiche correspondante vérifiée. Ouvrez la recherche de la source.") }
        if requestedYear == nil && candidates.count > 1 {
            return unavailable("Plusieurs fiches correspondent à ce titre. Ouvrez la source pour choisir.")
        }
        var entityData = Data()
        let ids = Set(candidates.compactMap(\.entityID)).sorted()
        if !ids.isEmpty {
            var entityURL = URLComponents(string: "https://www.wikidata.org/w/api.php")!
            entityURL.queryItems = [.init(name: "action", value: "wbgetentities"), .init(name: "format", value: "json"), .init(name: "ids", value: ids.joined(separator: "|")), .init(name: "props", value: "claims")]
            entityData = try await fetch(entityURL.url!)
        }
        if let requestedYear {
            candidates = candidates.filter { candidate in
                guard let id = candidate.entityID else { return false }
                let claims = CaseDescriptionParser.claims(entityData, entityID: id)
                return CaseDescriptionParser.releaseYears(claims).contains(requestedYear)
            }
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            return unavailable(candidates.isEmpty ? "L’année ne permet pas de confirmer la fiche. Ouvrez la source." : "Plusieurs fiches correspondent à ce titre et cette année. Ouvrez la source pour choisir.")
        }
        let claims = candidate.entityID.map { CaseDescriptionParser.claims(entityData, entityID: $0) } ?? [:]
        let result: CaseDescriptionEntry
        if source == .wikipedia {
            result = CaseDescriptionEntry(title: candidate.title, text: candidate.extract, sourceURL: candidate.url, status: "Présentation Wikipédia · CC BY-SA · auteurs et historique sur la source")
        } else {
            guard let url = CaseDescriptionParser.allocineURL(claims, series: series) else { return unavailable("Aucune fiche Allociné liée à ce titre. Ouvrez la recherche Allociné.") }
            let htmlData = try await fetch(url)
            guard let html = String(data: htmlData, encoding: .utf8), let parsed = CaseDescriptionParser.allocineDescription(html, expectedTitle: candidate.title, series: series, expectedURL: url) else {
                return CaseDescriptionEntry(title: candidate.title, text: "", sourceURL: url, status: "Le synopsis Allociné n’est pas accessible dans l’application. Ouvrez la fiche originale.")
            }
            result = CaseDescriptionEntry(title: parsed.title, text: parsed.text, sourceURL: url, status: "Synopsis Allociné · fiche liée via Wikidata")
        }
        try Task.checkCancellation()
        cache[key] = result; order.removeAll { $0 == key }; order.append(key)
        while order.count > 24 { cache.removeValue(forKey: order.removeFirst()) }
        return result
    }

    private func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard ["fr.wikipedia.org", "www.wikidata.org", "www.allocine.fr"].contains(url.host ?? ""), url.scheme == "https" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.setValue("FluxIPTV/0.8.2 (public movie metadata; https://github.com/M4D135/FluxIPTV)", forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        let data = try await CaseMetadataDownload.data(from: request)
        if ["fr.wikipedia.org", "www.wikidata.org"].contains(url.host ?? "") {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["error"] == nil else { throw URLError(.badServerResponse) }
        }
        return data
    }
}
