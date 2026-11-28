import XCTest
@testable import FluxIPTVCore

/// The reading of the lists up to the 0.9.9, line by line as text, kept as it
/// was to check that the reading on bytes gives the same entries.
private struct ReferenceM3UParser {
    func parse(_ input: String, sourceID: UUID) -> [IPTVItem] {
        var items: [IPTVItem] = []
        var pending: (name: String, group: String, logo: URL?, type: String?)?
        var extensionGroup: String?
        var seen = Set<String>()

        let text = input.replacingOccurrences(of: "\u{FEFF}", with: "")
        if text.contains("#EXT-X-TARGETDURATION:") || text.contains("#EXT-X-STREAM-INF:") { return [] }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("#EXTINF:") {
                let metadata = String(line.dropFirst("#EXTINF:".count))
                let attrs = attributes(metadata)
                let label = title(afterAttributes: metadata)
                let name = attrs["tvg-name"].flatMap { $0.isEmpty ? nil : $0 } ?? label
                pending = (
                    name: name,
                    group: attrs["group-title"] ?? extensionGroup ?? "Sans catégorie",
                    logo: IPTVURL.remoteImage(attrs["tvg-logo"]),
                    type: attrs["type"] ?? attrs["tvg-type"]
                )
                extensionGroup = nil
                continue
            }
            if line.uppercased().hasPrefix("#EXTGRP:") {
                extensionGroup = String(line.dropFirst("#EXTGRP:".count))
                continue
            }
            if line.hasPrefix("#") { continue }

            defer { pending = nil; extensionGroup = nil }
            guard let stream = try? IPTVURL.validated(line) else { continue }
            let id = "\(sourceID.uuidString):m3u:\(StableID.hash(stream.absoluteString))"
            guard seen.insert(id).inserted else { continue }
            let title = pending?.name.isEmpty == false ? pending!.name : stream.lastPathComponent
            let group = pending?.group ?? extensionGroup ?? "Sans catégorie"
            items.append(IPTVItem(
                id: id,
                sourceID: sourceID,
                name: title.isEmpty ? (stream.host ?? "Flux IPTV") : title,
                group: group,
                logoURL: pending?.logo,
                kind: Self.mediaKind(for: stream, group: group, explicitType: pending?.type),
                directURL: stream,
                xtreamStreamID: nil,
                fileExtension: nil
            ))
        }
        return items
    }

    static func mediaKind(for url: URL, group: String, explicitType: String?) -> IPTVMediaKind {
        func classify(_ raw: String) -> IPTVMediaKind? {
            let value = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["series", "serie", "tv shows", "tv show", "episodes", "episode"].contains(value) { return .series }
            if ["movie", "movies", "film", "films", "vod"].contains(value) { return .movie }
            if ["live", "tv", "direct", "chaines tv"].contains(value) { return .live }
            return nil
        }
        if let explicitType, let kind = classify(explicitType) { return kind }
        let segments = url.pathComponents.map { $0.lowercased() }
        if segments.count >= 5, let kind = classify(segments[segments.count - 4]) { return kind }
        let normalizedGroup = group.replacingOccurrences(of: " - ", with: "|")
        for part in normalizedGroup.split(whereSeparator: { "|:/»".contains($0) }) {
            if let kind = classify(String(part)), kind != .live { return kind }
        }
        return .live
    }

    private func title(afterAttributes metadata: String) -> String {
        var insideQuotes = false
        for index in metadata.indices {
            let char = metadata[index]
            if char == "\"" { insideQuotes.toggle() }
            if char == "," && !insideQuotes {
                return String(metadata[metadata.index(after: index)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func attributes(_ metadata: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\s)([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(?:"([^"]*)"|([^\s,]+))"#
        ) else { return [:] }
        let text = metadata as NSString
        let range = NSRange(location: 0, length: text.length)
        var values: [String: String] = [:]
        for match in regex.matches(in: metadata, range: range) {
            let valueRange = match.range(at: 2).location != NSNotFound
                ? match.range(at: 2) : match.range(at: 3)
            values[text.substring(with: match.range(at: 1)).lowercased()] = text.substring(with: valueRange)
        }
        return values
    }
}

/// The reading on bytes gives the entries the reading as text gave, on the
/// lines a provider writes and on the ones that test each shortcut.
final class M3UParserReferenceTests: XCTestCase {
    private let source = UUID(uuidString: "6F1D2B0C-8E4A-4C1B-9B57-3A2E7D5C9F10")!

    private static let separators = ["\n", "\r\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}", "\n\n"]

    /// Lines that test each shortcut of the reading on bytes.
    private static let lines: [String] = [
        "#EXTM3U", "#EXTM3U url-tvg=\"http://epg.example.org/guide.xml\"",
        "#EXTINF:-1 tvg-id=\"a\" tvg-name=\"Info, Monde\" tvg-logo=\"https://cdn.example.org/l.png\" group-title=\"Actualités\",Info HD",
        "#extinf:-1 TVG-NAME=\"Petit\" Group-Title=\"Bas\" TVG-LOGO=\"http://cdn.example.org/b.png\",x",
        "#EXTıNF:-1,Sans point", "#EXTINF:\u{345}-1,Ypogegrammeni", "#EXTINF:\u{301}-1,Accent après les deux-points",
        "#EXTINF:-1 group-title=\"G\u{301}\",T\u{301}itre", "#EXTINF:-1 group-title=\"G\"\u{301},Titre",
        "#EXTINF:-1 group-title=\"G\",\u{301}Titre", "#EXTINF:-1,\u{600}\"Préfixe", "#EXTINF:-1 group-title=\"Ā\",Ō",
        "#EXTINF:-1 group-title=\"\u{200D}\",\u{200D}Joint", "#EXTINF:-1 tvg-name=\"Été\",\u{FE0F}Variante",
        "\u{A0}#EXTINF:-1,Espace insécable\u{A0}", "\u{3000}#EXTINF:-1 group-title=\"Large\",Idéographique\u{3000}",
        "\t #EXTINF:-1 group-title=\"Tab\",Tabulation\t ", "#EXTINF:-1,Fin accentuée é", "#EXTINF:-1,Fin chinoise 東京",
        "#EXTINF:-1 tvg-name\u{2003}=\u{2003}\"Cadratin\",T", "#EXTINF:-1\u{200B}tvg-name=\"Sans chasse\",T",
        "#EXTINF:-1\u{180E}tvg-name=\"Mongol\",T", "#EXTINF:-1\u{1680}tvg-name=\"Ogam\",T", "#EXTINF:-1\u{205F}tvg-name=\"Maths\",T",
        "#EXTINF:-1\u{202F}tvg-name=\"Fine\",T", "#EXTINF:-1\ttvg-name=\"Tab\"\tgroup-title=\"G\",T",
        "#EXTINF:-1 tvg-name=Nu group-title=Sport,Titre", "#EXTINF:-1 tvg-name=\"Ouvert group-title=X,Titre",
        "#EXTINF:-1 tvg-name=\"\" group-title=\"\",Titre vide", "#EXTINF:-1 tvg-name=,Virgule", "#EXTINF:-1 tvg-name=",
        "#EXTINF:-1 tvg-name= \"Espacé\",T", "#EXTINF:-1 tvg-name =\"Espacé 2\",T", "#EXTINF:-1 tvg-name  =  Nu2 ,T",
        "#EXTINF:-1 tvg-name=\"A\"tvg-logo=\"http://l.example/x.png\",Collés", "#EXTINF:-1 tvg-name=\"Un\" tvg-name=\"Deux\",Double",
        "#EXTINF:tvg-name=\"Début\",Au début", "#EXTINF: tvg-name=\"Espace au début\",T", "#EXTINF:,Rien",
        "#EXTINF:-1,Titre avec a=b et tvg-name=\"Dans le titre\"", "#EXTINF:-1 1tvg=\"x\" _a=\"y\" -b=\"z\" tvg-type=\"movie\",T",
        "#EXTINF:-1 type=\"Séries\",T", "#EXTINF:-1 type=\"FILMS\",T", "#EXTINF:-1 tvg-type=\" live \",T", "#EXTINF:-1 type=\"\",T",
        "#EXTINF:-1 TYPE=\"Épisodes\",T", "#EXTINF:-1 type=\"tv shows\" tvg-type=\"movie\",T",
        "#EXTINF:-1 group-title=\"VOD - Action\",T", "#EXTINF:-1 group-title=\"Séries » Drame\",T",
        "#EXTINF:-1 group-title=\"TV Shows: Comédie\",T", "#EXTINF:-1 group-title=\"Chaînes TV | FR\",T",
        "#EXTINF:-1 group-title=\"FILM/2024\",T", "#EXTINF:-1 group-title=\"Direct | Films\",T",
        "#EXTINF:-1 group-title=\"👨‍👩‍👧\",家族 🎬", "#EXTINF:-1,\"Titre, entre guillemets\" suite", "#EXTINF:-1,\"Sans fin, titre",
        "#EXTINF:-1 tvg-name=\"x\",", "#EXTINF:-1 tvg-name=\"\",", "#EXTINF:", "#EXTINF:-1 tvg-logo=\"javascript:alert(1)\",Logo refusé",
        "#EXTGRP:Documentaires", "#extgrp:petit", "#EXTGRP:", "#EXTGRP:\u{301}x", "#EXTGRP: Espacé ", "#EXTGRPX",
        "#EXTVLCOPT:http-user-agent=Lecteur", "#", "#\u{301}http://h.example/live/u/p/0.ts", "#KODIPROP:inputstream=x",
        "http://h.example/movie/u/p/1.mkv", "HTTPS://H.EXAMPLE/SERIES/U/P/2.MKV", "http://h.example:8080/live/u/p/3",
        "http://h.example/a%2Fb/movie/u/p/4.ts", "http://h.example/mo%76ie/u/p/4b.ts", "http://h.example/movie;x/u/p/5.ts",
        "http://h.example//movie/u/p/6.ts", "http://h.example/movie/u/p/7.ts/", "http://h.example/./movie/u/p/8.ts",
        "http://h.example/../movie/u/p/9.ts", "http://h.example/movie/u/p/10.ts?token=a/b/c", "http://h.example/movie/u/p/11.ts#frag",
        "http://h.example?x=1", "http://h.example/?x=1", "http://[::1]/movie/u/p/12.ts", "http://h.example/Mövie/u/p/13.ts",
        "http://h.example/film/u/p/14", "http://h.example/VOD/u/p/15", "http://h.example/episodes/u/p/16",
        "http://h.example/tv%20shows/u/p/17", "http://h.example/u/p/18", "http://h.example", "http://h.example/",
        "http://h.example/a b/movie/u/p/19.ts", "http://user:pw@h.example/live/u/p/20.ts", "ftp://h.example/x",
        "javascript:alert(1)", "rtsp://h.example/x", "http://h.example/movie/u/p/1.mkv", "http:/h.example/movie/u/p/21",
        "http://h.example/x/movie/u/p/22.ts", "http://h.example/series/u/p/23/", "http://h.example/séries/u/p/24",
        "http://h.example/live/u/p/25.ts?a=%20", "http://h.example/a/b/c/d/e/live/u/p/26.ts", "http://h.example/+/movie/u/p/27",
        "  http://h.example/live/u/p/28.ts  ", "\u{A0}http://h.example/live/u/p/29.ts", "http://h.example/live/u/p/30.ts\u{2007}",
        "http://h.example/movie/u/p/31.ts\u{200B}", "\u{FEFF}http://h.example/live/u/p/32.ts", "http://h\u{FEFF}.example/live/u/p/33.ts",
        "http://h.example/live/u/p/34.ts?x#y", "http://h.example:/live/u/p/35.ts", "Http://h.example/Live/U/P/36.TS",
        "http://h.example/live/u/p/37.ts?", "http://h.example/live/u/p/\u{301}38.ts", "texte quelconque", " ", "\t", "\u{3000}",
    ]

    private func assertSameReading(_ text: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = ReferenceM3UParser().parse(text, sourceID: source)
        let found = M3UParser().parse(text, sourceID: source)
        guard found != expected else { return }
        let shared = min(found.count, expected.count)
        let index = (0..<shared).first { found[$0] != expected[$0] } ?? shared
        let describe: ([IPTVItem]) -> String = { items in
            guard index < items.count else { return "nothing" }
            let item = items[index]
            return "\(item.name) | \(item.group) | \(item.kind) | \(item.logoURL?.absoluteString ?? "-") | \(item.directURL?.absoluteString ?? "-")"
        }
        XCTFail("\(label): entry \(index) of \(found.count) (\(expected.count) expected): \(describe(found)) instead of \(describe(expected))",
                file: file, line: line)
    }

    func testTheTrickyLinesReadAsTheyDid() {
        for separator in Self.separators {
            assertSameReading(Self.lines.joined(separator: separator), "separator \(separator.unicodeScalars.map { $0.value })")
        }
        // Each line between an entry that announces it and an address.
        for (index, line) in Self.lines.enumerated() {
            let text = "#EXTM3U\n#EXTINF:-1 group-title=\"Avant\",Avant\n\(line)\nhttp://h.example/live/u/p/\(index).ts\n"
                + "\(line)\n#EXTINF:-1,Après\nhttp://h.example/movie/u/p/\(index).mkv"
            assertSameReading(text, "line \(index): \(line)")
        }
        assertSameReading("\u{FEFF}" + Self.lines.joined(separator: "\n"), "byte order mark")
        assertSameReading(Self.lines.joined(separator: "\u{FEFF}\n"), "byte order marks")
        assertSameReading("#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nhttps://example.org/seg.ts", "segments")
        assertSameReading("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://example.org/v.m3u8", "variants")
        assertSameReading("#EXTM3U\n#EXT-X-TARGETDURATION\u{301}:6\nhttps://example.org/v.m3u8", "marker with an accent")
        assertSameReading("", "empty")
    }

    func testGeneratedListsReadAsTheyDid() {
        var random = SeededRandom(seed: 0x5EED)
        let names = ["tvg-name", "TVG-NAME", "group-title", "tvg-logo", "type", "tvg-type", "tvg-id", "x", "Tvg-Name"]
        let values = ["Été", "Info, Monde", "VOD - Films", "Séries » Drame", "movie", "Series", "", " ", "a\"b", "東京",
                      "http://cdn.example.org/l.png", "Live", "TV Shows", "chaînes tv", "\u{301}", "x\u{A0}y", "👩‍👩‍👦"]
        let spaces = [" ", "  ", "\t", "\u{A0}", "\u{2003}", "\u{3000}", "\u{200B}", ""]
        let titles = ["Titre", " Titre ", "Été à Paris", "\"Cité\", la nuit", "家族 🎬", "", "a=b", "x\u{301}", ",", "\u{2009}fin\u{2009}"]
        let addresses = Self.lines.filter { !$0.hasPrefix("#") } + (0..<40).map { "http://h.example/\(["live", "movie", "series", "x"][$0 % 4])/u/p/\($0)" }
        for list in 0..<300 {
            var lines: [String] = []
            for _ in 0..<random.int(below: 40) {
                switch random.int(below: 6) {
                case 0, 1:
                    var line = random.element(["#EXTINF:", "#extinf:", "#EXTINF:-1", "#EXTINF:-1 ", " #EXTINF:"])
                    for _ in 0..<random.int(below: 5) {
                        let quoted = random.int(below: 3) > 0
                        let value = random.element(values)
                        line += random.element(spaces) + random.element(names) + random.element(["=", " = ", "=\u{2003}"])
                            + (quoted ? "\"\(value)\"" : value)
                    }
                    line += random.element([",", ", ", ""]) + random.element(titles) + random.element(spaces)
                    lines.append(line)
                case 2:
                    lines.append(random.element(["#EXTGRP:", "#extgrp:", "#EXTGRP: "]) + random.element(values))
                case 3:
                    lines.append(random.element(Self.lines))
                default:
                    lines.append(random.element(spaces) + random.element(addresses) + random.element(spaces))
                }
            }
            var text = ""
            for line in lines { text += line + random.element(Self.separators) }
            assertSameReading(text, "list \(list)")
        }
    }

    /// The facts of Foundation and of Swift the reading on bytes stands on.
    func testTheShortcutsStandOnTheirFacts() throws {
        // `components(separatedBy: .newlines)` splits at these scalars only.
        let all = (0...0x10FFFF).compactMap(Unicode.Scalar.init(_:))
        XCTAssertEqual(all.filter { CharacterSet.newlines.contains($0) }.map(\.value), [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029])
        // `whitespacesAndNewlines` holds U+0009 to U+000D and U+0020 in ASCII.
        XCTAssertEqual((0..<128).filter { CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(UInt8($0))) },
                       [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20])
        // `\s` matches the White_Space scalars, all led by 0xC2 or 0xE1 to 0xE3 beyond ASCII.
        var text = ""
        text.unicodeScalars.append(contentsOf: all)
        let regex = try NSRegularExpression(pattern: #"\s"#)
        let utf16 = text as NSString
        let matched = regex.matches(in: text, range: NSRange(location: 0, length: utf16.length)).map {
            (utf16.substring(with: $0.range) as String).unicodeScalars.first!.value
        }
        let whitespace = all.filter(\.properties.isWhitespace)
        XCTAssertEqual(matched, whitespace.map(\.value))
        XCTAssertTrue(whitespace.allSatisfy { $0.value < 0x80 || [0xC2, 0xE1, 0xE2, 0xE3].contains(String($0).utf8.first!) })
        // A quote or a comma next to a scalar below U+0300 is a Character of its own.
        for value in 0..<0x300 where value != 0x0D && value != 0x0A {
            let scalar = String(Character(try XCTUnwrap(Unicode.Scalar(UInt32(value)))))
            for mark in ["\"", ","] {
                XCTAssertEqual((mark + scalar).count, 2, "U+\(String(value, radix: 16))")
                XCTAssertEqual((scalar + mark).count, 2, "U+\(String(value, radix: 16))")
            }
        }
    }
}

/// A generator of numbers that gives the same lists on every run.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }

    mutating func int(below bound: Int) -> Int { Int(next() % UInt64(bound)) }

    mutating func element<T>(_ elements: [T]) -> T { elements[int(below: elements.count)] }
}
