import Foundation

/// A language inferred from the label a provider puts in front of a film or a
/// series ("FR - Titre", "4K-EN - …") or of its category ("FRANCE SÉRIES").
/// Titles and categories are never changed, and what carries no label stays
/// available under an explicit "not identified" entry.
public struct MediaLanguage: Identifiable, Equatable, Sendable {
    public static let unknownCode = "unclassified"
    /// Original version with subtitles.
    public static let originalCode = "vo"
    /// Several audio tracks (ISO 639-2 "mul").
    public static let multipleCode = "mul"

    public let code: String
    public let name: String
    public let titleCount: Int
    public var id: String { code }

    public init(code: String, name: String? = nil, titleCount: Int) {
        self.code = code
        self.name = name ?? Self.displayName(for: code)
        self.titleCount = titleCount
    }

    public static func displayName(for code: String) -> String {
        switch code {
        case unknownCode: return "Langue non identifiée"
        case originalCode: return "Version originale"
        case multipleCode: return "Multilingue"
        default:
            guard let name = french.localizedString(forLanguageCode: code), !name.isEmpty else { return code.uppercased() }
            return name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// The short label in front of a title: "4K-FR" for "4K-FR - Dune".
    /// A title without such a label, or with a long first part, has none.
    public static func titleLabel(of name: String) -> String? {
        // Only the first characters can hold a label; a catalogue has tens of
        // thousands of titles, so nothing beyond them is read.
        var previous: Character?, index = name.startIndex, scanned = 0
        while index < name.endIndex, scanned <= 16 {
            let character = name[index], next = name.index(after: index)
            if previous == " ", "-|:–—".contains(character), next < name.endIndex, name[next] == " " {
                let label = name[..<index].trimmingCharacters(in: .whitespaces)
                return label.isEmpty || label.count > 14 ? nil : label
            }
            previous = character; index = next; scanned += 1
        }
        return nil
    }

    /// The title without the label of its language: "Dune" for "4K-FR -
    /// Dune". For the places where a name has little room, under an icon:
    /// ten shortcuts that all begin with "FR - " tell nothing apart once
    /// they are cut short. A first part that names no language is part of
    /// the title ("Rocky - Balboa"), and the catalogue itself keeps every
    /// title as its provider wrote it.
    public static func bareTitle(of name: String) -> String {
        guard let label = titleLabel(of: name), detectCode(in: label) != nil else { return name }
        var previous: Character?, index = name.startIndex
        while index < name.endIndex {
            let character = name[index], next = name.index(after: index)
            if previous == " ", "-|:–—".contains(character), next < name.endIndex, name[next] == " " {
                let rest = name[name.index(after: next)...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? name : rest
            }
            previous = character; index = next
        }
        return name
    }

    /// Reads the first meaningful word of a label, after quality and brand
    /// tags. A two-letter code must be set apart ("FR -", "[FR]", "FR|") unless
    /// it is one of the tags playlists commonly write before a plain space.
    public static func detectCode(in label: String) -> String? {
        let text = normalized(label)
        var words: [(text: String, start: String.Index, end: String.Index)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else { index = text.index(after: index); continue }
            var end = index
            while end < text.endIndex, text[end].isLetter || text[end].isNumber { end = text.index(after: end) }
            words.append((String(text[index..<end]), index, end))
            index = end
        }
        guard let first = words.firstIndex(where: { !ignored.contains($0.text) && !$0.text.allSatisfy(\.isNumber) }) else { return nil }

        // Names of up to three words: "ROYAUME UNI", "ETATS UNIS", "PAYS BAS".
        for length in stride(from: min(3, words.count - first), through: 1, by: -1) {
            let phrase = words[first..<(first + length)].map(\.text).joined(separator: " ")
            if let code = names[phrase] { return code }
        }
        let word = words[first]
        if word.text.count > 2 { return longAliases[word.text] }
        guard word.text.count == 2 else { return nil }
        let after = text[word.end...].first(where: { $0 != " " })
        let before = word.start > text.startIndex ? text[text.index(before: word.start)] : nil
        let setApart = after == nil || "-|:])/•·_,;".contains(after!) || before == "[" || before == "("
        guard setApart || plainTags.contains(word.text) else { return nil }
        return shortAliases[word.text] ?? regionLanguages[word.text]
    }

    private static let french = Locale(identifier: "fr_FR")
    private static let english = Locale(identifier: "en_US")
    private static let invariant = Locale(identifier: "en_US_POSIX")

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: invariant).uppercased()
    }

    /// Quality, packaging and brand words that precede the language in a label.
    private static let ignored: Set<String> = [
        "4K", "8K", "2K", "UHD", "FHD", "QHD", "HD", "SD", "HDR", "HDR10", "DV", "HEVC", "H264", "H265", "X264", "X265",
        "3D", "1080P", "720P", "2160P", "480P", "60FPS", "VIP", "NEW", "TOP", "VOD", "IPTV", "PPV", "RAW", "ULTRA",
        "PREMIUM", "PLUS", "AMAZON", "AMZ", "PRIME", "NETFLIX", "NF", "DISNEY", "DSNP", "APPLE", "ATVP", "HBO",
        "PARAMOUNT", "HULU", "CANAL", "OCS", "PEACOCK", "STARZ", "SHOWTIME", "SKY"
    ]

    /// Two-letter tags accepted before a plain space; the others are common
    /// words of a title or a category ("IN", "NO", "LA", "MY") and need a mark.
    private static let plainTags: Set<String> = [
        "FR", "EN", "UK", "US", "DE", "ES", "IT", "PT", "NL", "TR", "AR", "RU", "PL", "GR", "AL", "RO", "BR", "DK", "FI", "JP", "KR", "CN"
    ]

    /// Playlist usage that differs from the country a code names.
    private static let shortAliases = ["EN": "en", "UK": "en", "AR": "ar", "VO": originalCode, "VF": "fr", "KU": "ku", "FA": "fa", "HI": "hi", "UR": "ur"]

    private static let longAliases: [String: String] = [
        "USA": "en", "ENG": "en", "FRA": "fr", "FRE": "fr", "VFF": "fr", "VFQ": "fr", "TRUEFRENCH": "fr",
        "DEU": "de", "GER": "de", "ESP": "es", "SPA": "es", "LAT": "es", "LATINO": "es", "LATAM": "es", "ITA": "it",
        "POR": "pt", "RUS": "ru", "TUR": "tr", "NLD": "nl", "DUT": "nl", "POL": "pl", "ARA": "ar", "ARAB": "ar",
        "JPN": "ja", "KOR": "ko", "CHN": "zh", "CHI": "zh", "IND": "hi", "BOLLYWOOD": "hi",
        "VOST": originalCode, "VOSTFR": originalCode, "VOSTEN": originalCode, "MULTI": multipleCode, "MULTILANGUE": multipleCode
    ]

    /// Likely language of each country, from the system's own locale data.
    private static let regionLanguages: [String: String] = {
        var result: [String: String] = [:]
        for region in Locale.Region.isoRegions where region.subRegions.isEmpty {
            let code = region.identifier
            guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }) else { continue }
            let likely = Locale.Language(languageCode: Locale.LanguageCode("und"), region: region).maximalIdentifier
            guard let language = Locale.Language(identifier: likely).languageCode?.identifier, language.count == 2,
                  language != "un" else { continue }
            // Both written Norwegians are one audio language.
            result[code] = language == "nb" || language == "nn" ? "no" : language
        }
        return result
    }()

    /// Language and country names in French, English and in the language itself.
    private static let names: [String: String] = {
        var result: [String: String] = [:]
        func add(_ name: String?, _ code: String) {
            guard let name else { return }
            let key = normalized(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
            if key.count > 3, result[key] == nil { result[key] = code }
        }
        // Countries first, so that a language name spelled like a country wins below.
        for (region, language) in regionLanguages {
            for locale in [french, english] { add(locale.localizedString(forRegionCode: region), language) }
        }
        var languages: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            for locale in [french, english, Locale(identifier: code)] {
                guard let name = locale.localizedString(forLanguageCode: code) else { continue }
                let key = normalized(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
                if key.count > 3 { languages[key] = code }
            }
        }
        for (key, code) in languages { result[key] = code == "nb" || code == "nn" ? "no" : code }
        let common = [
            "ESPANA": "es", "DEUTSCHLAND": "de", "ITALIA": "it", "BRASIL": "pt", "NEDERLAND": "nl", "TURKIYE": "tr",
            "TURKEY": "tr", "ETATS UNIS": "en", "UNITED STATES OF AMERICA": "en", "ROYAUME UNI": "en",
            "UNITED KINGDOM": "en", "FRANCAIS": "fr", "FRANCAISE": "fr", "ARABIC": "ar", "ARABE": "ar"
        ]
        for (key, code) in common { result[key] = code }
        return result
    }()
}
