import Foundation

/// The provider label is not a search title. Strip known IPTV tags, not arbitrary words.
public enum CinemaLinks {
    public enum Site: String, CaseIterable, Sendable { case wikipedia, allocine }
    public static func title(_ label: String) -> String {
        var t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^\s*(?:(?:\[|\(|\|)\s*(?:FR|VF|VFF|VFQ|VOSTFR|VO|EN|ES|DE|IT|MULTI|UHD|FHD|HD|4K)\s*(?:\]|\)|\|)\s*|(?:FR|VF|VFF|VFQ|VOSTFR|VO|EN|ES|DE|IT|MULTI|UHD|FHD|HD|4K)\s*[-:|]\s*)+"#,
            #"(?i)\s+(?:S\d{1,3}\s*E\d{1,4}|Saison\s+\d+(?:\s*[\-–:]?\s*[ÉE]pisode\s+\d+)?)\s*$"#,
            #"(?i)\s*\[(?:4K|UHD|FHD|HD|1080P|2160P|MULTI|VF|VOSTFR)\]\s*$"#,
            #"(?i)\s*\((?:4K|UHD|FHD|HD|1080P|2160P|MULTI|VF|VOSTFR)\)\s*$"#,
            #"\s*[-–|:]\s*$"#
        ]
        for _ in 0..<3 { for p in patterns { t = t.replacingOccurrences(of:p,with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines) } }
        return t.isEmpty ? label.trimmingCharacters(in:.whitespacesAndNewlines) : t
    }
    public static func url(for site: Site, name: String, year: String?, series: Bool) -> URL? {
        let cleaned = title(name)
        guard !cleaned.isEmpty else { return nil }
        let y = year?.prefix(4).description
        let validYear = y.flatMap { $0.count == 4 && $0.allSatisfy(\.isNumber) && !cleaned.contains($0) ? $0 : nil }
        let terms = [String(cleaned.prefix(180)), validYear].compactMap{$0}.joined(separator:" ")
        switch site {
        case .wikipedia:
            var c = URLComponents(string:"https://fr.wikipedia.org/w/index.php")
            c?.queryItems = [URLQueryItem(name:"search",value:terms)]
            return c?.url
        case .allocine:
            // No undocumented Allociné API or guessed fiche IDs. Search indexed fiches.
            let domain = series ? "site:allocine.fr/series/" : "site:allocine.fr/film/"
            var c = URLComponents(string:"https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name:"q",value:"\(domain) \(terms)"),URLQueryItem(name:"hl",value:"fr")]
            return c?.url
        }
    }
}
