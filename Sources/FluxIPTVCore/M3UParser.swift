import Foundation

public struct M3UParser: Sendable {
    public init() {}

    /// Supports EXTINF, tvg-name / tvg-logo, group-title and EXTGRP.
    /// Does not interpret the HLS segment directives found inside a .m3u8 manifest.
    public func parse(_ input: String, sourceID: UUID) -> [IPTVItem] {
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

    // Explicit metadata or conventional Xtream URL prefixes only. Never guess from a codec
    // or a broad word such as "cinéma" (which may be a live channel category).
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
        // Standard Xtream paths end in /{live,movie,series}/user/password/id.ext.
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
