import Foundation

/// A country inferred from a provider's TV category prefix. The original
/// category is never changed, and categories without a prefix stay available.
public struct LiveCountry: Identifiable, Equatable, Sendable {
    public static let unknownCode = "unclassified"

    public let code: String
    public let name: String
    public let channelCount: Int
    public var id: String { code }

    public init(code: String, name: String? = nil, channelCount: Int) {
        self.code = code
        self.name = name ?? Self.displayName(for: code)
        self.channelCount = channelCount
    }

    public static func displayName(for code: String) -> String {
        if code == unknownCode { return "Pays non identifié" }
        return french.localizedString(forRegionCode: code) ?? code
    }

    /// Accept only a complete prefix, never an occurrence inside the name.
    /// Examples: FR | Sport, [ES] Cine, UK-News, France • Généralistes, 🇫🇷 TV.
    /// A language label such as EN is not assumed to identify a country.
    public static func detectCode(in category: String) -> String? {
        let prefix = category.drop(while: isLeadingDecoration)
        guard !prefix.isEmpty else { return nil }

        let scalars = prefix.unicodeScalars
        if let first = scalars.first, (0x1F1E6...0x1F1FF).contains(first.value) {
            let indicators = Array(scalars.prefix(2))
            guard indicators.count == 2,
                  indicators.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else { return nil }
            let letters = indicators.compactMap { UnicodeScalar($0.value - 0x1F1E6 + 65) }
            let code = String(String.UnicodeScalarView(letters))
            return regionCodes.contains(code) ? code : nil
        }

        let text = normalized(String(prefix))
        // Longer names precede shorter names and codes: "La Réunion" must
        // not be interpreted as the two-letter Laos code "LA".
        for (name, code) in countryNames where text.hasPrefix(name) {
            let remainder = text.dropFirst(name.count)
            if hasBoundary(remainder) { return code }
        }

        let token = String(text.prefix(while: { $0.isLetter || $0.isNumber }))
        guard !token.isEmpty else { return nil }
        if let code = codeAliases[token] { return code }
        // These are overwhelmingly technical labels in TV playlists. The
        // countries Tuvalu and Sudan remain identifiable by name or flag.
        if token == "TV" || token == "SD" { return nil }
        return regionCodes.contains(token) ? token : nil
    }

    private static let french = Locale(identifier: "fr_FR")
    private static let english = Locale(identifier: "en_US")
    private static let invariant = Locale(identifier: "en_US_POSIX")

    private static let regionCodes: Set<String> = Set(Locale.isoRegionCodes.filter {
        $0.utf8.count == 2 && $0.utf8.allSatisfy { (65...90).contains($0) }
    })

    private static let codeAliases = ["UK": "GB", "USA": "US"]

    private static let countryNames: [(String, String)] = {
        var names: [String: String] = [:]
        for code in regionCodes {
            for locale in [french, english] {
                if let name = locale.localizedString(forRegionCode: code) {
                    let key = normalized(name)
                    if key.count > 2 { names[key] = code }
                }
            }
        }
        // Common playlist spellings/endonyms that differ from the app's
        // French and English localized names. No language-only aliases.
        let common = [
            "ESPANA": "ES", "DEUTSCHLAND": "DE", "ITALIA": "IT",
            "BRASIL": "BR", "NEDERLAND": "NL", "OSTERREICH": "AT",
            "TURKIYE": "TR", "TURKEY": "TR", "BELGIQUE": "BE",
            "ETATS UNIS": "US", "UNITED STATES OF AMERICA": "US",
            "ROYAUME UNI": "GB", "UNITED KINGDOM": "GB",
            "LA REUNION": "RE", "REUNION": "RE"
        ]
        for (name, code) in common { names[name] = code }
        return names.sorted {
            $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count > $1.key.count
        }.map { ($0.key, $0.value) }
    }()

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: invariant).uppercased()
    }

    private static func hasBoundary(_ remainder: Substring) -> Bool {
        guard let next = remainder.first else { return true }
        return !next.isLetter && !next.isNumber
    }

    private static func isLeadingDecoration(_ character: Character) -> Bool {
        // Keep regional indicator symbols so an actual flag can be decoded.
        if character.unicodeScalars.contains(where: { (0x1F1E6...0x1F1FF).contains($0.value) }) { return false }
        return !character.isLetter && !character.isNumber
    }
}
