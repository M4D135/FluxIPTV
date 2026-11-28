import Foundation

public struct M3UParser: Sendable {
    public init() {}

    /// Supports EXTINF, tvg-name / tvg-logo, group-title and EXTGRP.
    /// Does not interpret the HLS segment directives found inside a .m3u8 manifest.
    ///
    /// The list is read on its UTF-8 bytes, one line after the other, and the
    /// reading gives what the reading of each line as text gave up to the 0.9.9
    /// (`M3UParserReferenceTests` keeps that reading and compares the two). A
    /// line the bytes cannot settle alone, such as one that ends on a space
    /// outside ASCII, is still read as text. The reading as text took 2.6 s for
    /// 92 000 entries on a Mac: an expression compiled again on each line, a
    /// copy of each line in capitals, all the lines split at once, a locale
    /// built for each word compared. An Apple TV HD is about ten times slower.
    public func parse(_ input: String, sourceID: UUID) -> [IPTVItem] {
        var text = input
        if Self.bytes(of: &text, hold: "\u{FEFF}") {
            text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        if Self.mentions(&text, "#EXT-X-TARGETDURATION:") || Self.mentions(&text, "#EXT-X-STREAM-INF:") { return [] }
        var reader = M3UReader(sourceID: sourceID)
        text.withUTF8 { reader.read($0) }
        return reader.items
    }

    /// Whether the list holds `marker` as `contains` finds it. The bytes rule it
    /// out first: no other text compares equal to these markers of ASCII.
    private static func mentions(_ text: inout String, _ marker: String) -> Bool {
        bytes(of: &text, hold: marker) && text.contains(marker)
    }

    private static func bytes(of text: inout String, hold marker: String) -> Bool {
        var marker = marker
        return text.withUTF8 { haystack in marker.withUTF8 { ByteSearch.contains(haystack, $0) } }
    }
}

/// The reading of a list, line after line: the entry an `#EXTINF` line
/// announces waits for the address that follows it.
private struct M3UReader {
    private let sourceID: UUID
    private let idPrefix: String
    private(set) var items: [IPTVItem] = []
    private var seen = Set<String>()
    private var pending: (name: String, group: String, logo: URL?, type: String?)?
    private var extensionGroup: String?
    private var kinds = M3UKinds()
    /// One copy of each category name, which all its titles share.
    private var groups = Set<String>()

    init(sourceID: UUID) {
        self.sourceID = sourceID
        idPrefix = "\(sourceID.uuidString):m3u:"
    }

    /// Splits the list where `components(separatedBy: .newlines)` split it:
    /// at U+000A to U+000D, U+0085, U+2028 and U+2029.
    mutating func read(_ text: UnsafeBufferPointer<UInt8>) {
        let end = text.count
        var start = 0, index = 0
        while index < end {
            let byte = text[index]
            let length: Int
            if byte <= 0x0D && byte >= 0x0A {
                length = 1
            } else if byte == 0xC2, index + 1 < end, text[index + 1] == 0x85 {
                length = 2
            } else if byte == 0xE2, index + 2 < end, text[index + 1] == 0x80, text[index + 2] & 0xFE == 0xA8 {
                length = 3
            } else {
                index += 1
                continue
            }
            line(text, start, index)
            index += length
            start = index
        }
        line(text, start, end)
    }

    private mutating func line(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) {
        guard let bounds = UTF8Line.trimmed(text, lower, upper) else {
            read(line: UTF8Line.string(text, lower, upper).trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        let start = bounds.lowerBound, end = bounds.upperBound
        guard start < end else { return }
        guard text[start] == UInt8(ascii: "#") else {
            address(UTF8Line.string(text, start, end))
            return
        }
        // The directives compare without case, as `uppercased()` compared them:
        // settled on the bytes when the first eight are ASCII and the next one
        // cannot join the colon.
        guard end - start >= 8, UTF8Line.isASCII(text, start, start + 8), end == start + 8 || text[start + 8] < 0x80 else {
            read(line: UTF8Line.string(text, start, end))
            return
        }
        if UTF8Line.hasPrefix(text, start, "#EXTINF:") {
            information(text, start + 8, end)
        } else if UTF8Line.hasPrefix(text, start, "#EXTGRP:") {
            extensionGroup = UTF8Line.string(text, start + 8, end)
        }
        // Any other line that starts with "#" is a comment.
    }

    /// A line as text, for the lines the bytes alone do not settle: the
    /// reading of the 0.9.9.
    private mutating func read(line: String) {
        guard !line.isEmpty else { return }
        if line.uppercased().hasPrefix("#EXTINF:") {
            var metadata = String(line.dropFirst("#EXTINF:".count))
            metadata.withUTF8 { information($0, 0, $0.count) }
            return
        }
        if line.uppercased().hasPrefix("#EXTGRP:") {
            extensionGroup = String(line.dropFirst("#EXTGRP:".count))
            return
        }
        if line.hasPrefix("#") { return }
        address(line)
    }

    /// What an `#EXTINF` line says of the entry that follows it.
    private mutating func information(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) {
        let attributes = M3UAttributes(text, lower, upper)
        pending = (
            name: attributes.name.flatMap { $0.isEmpty ? nil : $0 } ?? M3UAttributes.title(text, lower, upper),
            group: attributes.group ?? extensionGroup ?? "Sans catégorie",
            logo: IPTVURL.remoteImage(attributes.logo),
            type: attributes.type ?? attributes.tvgType
        )
        extensionGroup = nil
    }

    private mutating func address(_ line: String) {
        defer { pending = nil; extensionGroup = nil }
        guard let stream = try? IPTVURL.validated(line) else { return }
        let id = idPrefix + StableID.hash(stream.absoluteString)
        guard seen.insert(id).inserted else { return }
        let title = pending?.name.isEmpty == false ? pending!.name : stream.lastPathComponent
        let group = groups.insert(pending?.group ?? extensionGroup ?? "Sans catégorie").memberAfterInsert
        items.append(IPTVItem(
            id: id,
            sourceID: sourceID,
            name: title.isEmpty ? (stream.host ?? "Flux IPTV") : title,
            group: group,
            logoURL: pending?.logo,
            kind: kinds.kind(for: stream, address: line, group: group, explicitType: pending?.type),
            directURL: stream,
            xtreamStreamID: nil,
            fileExtension: nil
        ))
    }
}

/// The kind of each entry: explicit metadata, the conventional Xtream URL
/// prefixes, then the words of its category. Never guess from a codec or a
/// broad word such as "cinéma" (which may be a live channel category). Each
/// word and each category is classified once per list.
private struct M3UKinds {
    private var words: [String: IPTVMediaKind?] = [:]
    private var routes: [String: IPTVMediaKind?] = [:]
    private var categories: [String: IPTVMediaKind?] = [:]

    mutating func kind(for url: URL, address: String, group: String, explicitType: String?) -> IPTVMediaKind {
        if let explicitType, let kind = word(explicitType) { return kind }
        // Standard Xtream paths end in /{live,movie,series}/user/password/id.ext.
        switch M3URoute(address) {
        case .segment(let segment):
            if let kind = route(segment) { return kind }
        case .none:
            break
        case .unknown:
            let segments = url.pathComponents
            if segments.count >= 5, let kind = route(segments[segments.count - 4]) { return kind }
        }
        if let kind = category(group) { return kind }
        return .live
    }

    private mutating func word(_ raw: String) -> IPTVMediaKind? {
        if let known = words[raw] { return known }
        let kind = Self.classify(raw)
        words.updateValue(kind, forKey: raw)
        return kind
    }

    private mutating func route(_ segment: String) -> IPTVMediaKind? {
        if let known = routes[segment] { return known }
        let kind = Self.classify(segment.lowercased())
        routes.updateValue(kind, forKey: segment)
        return kind
    }

    private mutating func category(_ group: String) -> IPTVMediaKind? {
        if let known = categories[group] { return known }
        var found: IPTVMediaKind?
        for part in group.replacingOccurrences(of: " - ", with: "|").split(whereSeparator: { "|:/»".contains($0) }) {
            if let kind = word(String(part)), kind != .live { found = kind; break }
        }
        categories.updateValue(found, forKey: group)
        return found
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func classify(_ raw: String) -> IPTVMediaKind? {
        let value = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: posix)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ["series", "serie", "tv shows", "tv show", "episodes", "episode"].contains(value) { return .series }
        if ["movie", "movies", "film", "films", "vod"].contains(value) { return .movie }
        if ["live", "tv", "direct", "chaines tv"].contains(value) { return .live }
        return nil
    }
}

/// The fourth segment from the end of the path of an address, read from its
/// text as `URL.pathComponents` gives it: the segment Xtream names the kind
/// with. An address with a percent sign, a semicolon, a fragment, a character
/// outside plain ASCII or an unusual path is left to `pathComponents`.
private enum M3URoute {
    case segment(String)
    /// The path has fewer than four segments.
    case none
    case unknown

    init(_ address: String) {
        self = address.utf8.withContiguousStorageIfAvailable(Self.read) ?? .unknown
    }

    private static func read(_ text: UnsafeBufferPointer<UInt8>) -> M3URoute {
        let end = text.count
        var index = 0
        while index < end, isSchemeByte(text[index]) { index += 1 }
        guard index > 0, index + 2 < end, text[index] == UInt8(ascii: ":"),
              text[index + 1] == UInt8(ascii: "/"), text[index + 2] == UInt8(ascii: "/") else { return .unknown }
        index += 3
        let host = index
        while index < end, text[index] != UInt8(ascii: "/"), text[index] != UInt8(ascii: "?") {
            guard isPlain(text[index]) else { return .unknown }
            index += 1
        }
        guard index > host, index < end, text[index] == UInt8(ascii: "/") else { return .unknown }
        let path = index
        var pathEnd = end
        for position in path..<end {
            guard isPlain(text[position]) else { return .unknown }
            if pathEnd == end, text[position] == UInt8(ascii: "?") { pathEnd = position }
        }
        // The segments between the slashes: none empty, none "." or "..".
        var count = 0, start = path + 1
        for position in path + 1...pathEnd where position == pathEnd || text[position] == UInt8(ascii: "/") {
            let length = position - start
            guard length > 0 else { return .unknown }
            if length <= 2, text[start] == UInt8(ascii: "."), length == 1 || text[start + 1] == UInt8(ascii: ".") { return .unknown }
            count += 1
            start = position + 1
        }
        guard count >= 4 else { return .none }
        var segment = 0
        start = path + 1
        for position in path + 1...pathEnd where position == pathEnd || text[position] == UInt8(ascii: "/") {
            if segment == count - 4 { return .segment(UTF8Line.string(text, start, position)) }
            segment += 1
            start = position + 1
        }
        return .unknown
    }

    private static func isSchemeByte(_ byte: UInt8) -> Bool {
        UTF8Line.isLetter(byte) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2B || byte == 0x2D || byte == 0x2E
    }

    /// The unreserved characters and the delimiters an address keeps as they
    /// are, without "%", ";", "#", "[" or "]".
    private static func isPlain(_ byte: UInt8) -> Bool {
        if UTF8Line.isLetter(byte) || (byte >= 0x30 && byte <= 0x39) { return true }
        switch byte {
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "!"),
             UInt8(ascii: "$"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: ","), UInt8(ascii: "="), UInt8(ascii: ":"),
             UInt8(ascii: "@"), UInt8(ascii: "/"), UInt8(ascii: "?"):
            return true
        default:
            return false
        }
    }
}

/// The attributes of an `#EXTINF` line the list reads, found where the
/// expression `(?:^|\s)([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(?:"([^"]*)"|([^\s,]+))`
/// found them up to the 0.9.9: from left to right, each match resuming where
/// the last one ended, a later attribute replacing an earlier one of the same
/// name (compared without case).
private struct M3UAttributes {
    private(set) var name: String?
    private(set) var group: String?
    private(set) var logo: String?
    private(set) var type: String?
    private(set) var tvgType: String?

    init(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) {
        var index = lower
        while index < upper {
            if index == lower, let end = match(text, name: lower, upper) {
                index = end
                continue
            }
            let space = UTF8Line.space(text, index, upper)
            if space > 0, let end = match(text, name: index + space, upper) {
                index = end
                continue
            }
            index += UTF8Line.length(text[index])
        }
    }

    /// The end of the attribute whose name starts at `start`, if one does.
    private mutating func match(_ text: UnsafeBufferPointer<UInt8>, name start: Int, _ upper: Int) -> Int? {
        guard start < upper, UTF8Line.isLetter(text[start]) else { return nil }
        var nameEnd = start + 1
        while nameEnd < upper, UTF8Line.isNameByte(text[nameEnd]) { nameEnd += 1 }
        let equals = UTF8Line.skippingSpaces(text, nameEnd, upper)
        guard equals < upper, text[equals] == UInt8(ascii: "=") else { return nil }
        let value = UTF8Line.skippingSpaces(text, equals + 1, upper)
        guard value < upper else { return nil }
        if text[value] == UInt8(ascii: "\""), let close = UTF8Line.firstQuote(text, value + 1, upper) {
            record(text, start, nameEnd, value + 1, close)
            return close + 1
        }
        // Unquoted, or a quote that never closes: up to a space or a comma.
        var stop = value
        while stop < upper, text[stop] != UInt8(ascii: ","), UTF8Line.space(text, stop, upper) == 0 {
            stop += UTF8Line.length(text[stop])
        }
        guard stop > value else { return nil }
        record(text, start, nameEnd, value, stop)
        return stop
    }

    private mutating func record(_ text: UnsafeBufferPointer<UInt8>, _ nameStart: Int, _ nameEnd: Int,
                                 _ valueStart: Int, _ valueEnd: Int) {
        func named(_ key: StaticString) -> Bool { UTF8Line.equalsIgnoringCase(text, nameStart, nameEnd, key) }
        if named("tvg-name") {
            name = UTF8Line.string(text, valueStart, valueEnd)
        } else if named("group-title") {
            group = UTF8Line.string(text, valueStart, valueEnd)
        } else if named("tvg-logo") {
            logo = UTF8Line.string(text, valueStart, valueEnd)
        } else if named("type") {
            type = UTF8Line.string(text, valueStart, valueEnd)
        } else if named("tvg-type") {
            tvgType = UTF8Line.string(text, valueStart, valueEnd)
        }
    }

    /// The title after the attributes: what follows the first comma outside
    /// quotes, as the Characters of the line gave it. A quote or a comma next to
    /// a scalar beyond U+02FF may belong to a larger Character: those lines are
    /// read as Characters.
    static func title(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> String {
        var quoted = false
        for index in lower..<upper {
            let byte = text[index]
            guard byte == UInt8(ascii: "\"") || byte == UInt8(ascii: ",") else { continue }
            guard UTF8Line.standsAlone(text, index, lower, upper) else {
                return characterTitle(UTF8Line.string(text, lower, upper))
            }
            if byte == UInt8(ascii: "\"") {
                quoted.toggle()
            } else if !quoted {
                return UTF8Line.trimmedString(text, index + 1, upper)
            }
        }
        return ""
    }

    private static func characterTitle(_ metadata: String) -> String {
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
}

/// The bytes of a line of UTF-8, and what the reading of its text gave on them.
private enum UTF8Line {
    static func string(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: text[lower..<upper]), as: UTF8.self)
    }

    /// The bounds of the line without the spaces around it, as
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` left it; nil when a
    /// scalar outside ASCII that the set holds stands at one end.
    static func trimmed(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> Range<Int>? {
        var start = lower, end = upper
        while start < end, isASCIISpace(text[start]) { start += 1 }
        while end > start, isASCIISpace(text[end - 1]) { end -= 1 }
        guard start < end else { return start..<start }
        if text[start] >= 0x80, trimmable.contains(scalar(text, at: start, upper)) { return nil }
        if text[end - 1] >= 0x80, trimmable.contains(scalar(text, endingAt: end, lower)) { return nil }
        return start..<end
    }

    static func trimmedString(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> String {
        guard let bounds = trimmed(text, lower, upper) else {
            return string(text, lower, upper).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return string(text, bounds.lowerBound, bounds.upperBound)
    }

    private static let trimmable = CharacterSet.whitespacesAndNewlines

    /// What `whitespacesAndNewlines` holds in ASCII: U+0009 to U+000D and U+0020.
    static func isASCIISpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    /// The length of the space `\s` matched at `index`, 0 if none: the scalars
    /// of the White_Space property.
    static func space(_ text: UnsafeBufferPointer<UInt8>, _ index: Int, _ upper: Int) -> Int {
        guard index < upper else { return 0 }
        let byte = text[index]
        if byte < 0x80 { return isASCIISpace(byte) ? 1 : 0 }
        guard byte == 0xC2 || (byte >= 0xE1 && byte <= 0xE3) else { return 0 }
        return scalar(text, at: index, upper).properties.isWhitespace ? length(byte) : 0
    }

    static func skippingSpaces(_ text: UnsafeBufferPointer<UInt8>, _ index: Int, _ upper: Int) -> Int {
        var index = index
        while case let length = space(text, index, upper), length > 0 { index += length }
        return index
    }

    static func firstQuote(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> Int? {
        var index = lower
        while index < upper {
            if text[index] == UInt8(ascii: "\"") { return index }
            index += 1
        }
        return nil
    }

    /// Whether the ASCII byte at `index` is a Character of its own: no scalar
    /// beyond U+02FF stands next to it (Swift breaks between any two below).
    static func standsAlone(_ text: UnsafeBufferPointer<UInt8>, _ index: Int, _ lower: Int, _ upper: Int) -> Bool {
        if index > lower, text[index - 1] >= 0x80, scalar(text, endingAt: index, lower).value >= 0x300 { return false }
        if index + 1 < upper, text[index + 1] >= 0x80, scalar(text, at: index + 1, upper).value >= 0x300 { return false }
        return true
    }

    static func length(_ lead: UInt8) -> Int { lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4 }

    static func scalar(_ text: UnsafeBufferPointer<UInt8>, at index: Int, _ upper: Int) -> Unicode.Scalar {
        let lead = text[index], count = length(lead)
        guard count > 1 else { return Unicode.Scalar(lead) }
        guard index + count <= upper else { return "\u{FFFD}" }
        var value = UInt32(lead) & (count == 2 ? 0x1F : count == 3 ? 0x0F : 0x07)
        for offset in 1..<count { value = value << 6 | UInt32(text[index + offset] & 0x3F) }
        return Unicode.Scalar(value) ?? "\u{FFFD}"
    }

    static func scalar(_ text: UnsafeBufferPointer<UInt8>, endingAt end: Int, _ lower: Int) -> Unicode.Scalar {
        var start = end - 1
        while start > lower, text[start] & 0xC0 == 0x80 { start -= 1 }
        return scalar(text, at: start, end)
    }

    static func isASCII(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int) -> Bool {
        for index in lower..<upper where text[index] >= 0x80 { return false }
        return true
    }

    static func isLetter(_ byte: UInt8) -> Bool { (byte | 0x20) &- 0x61 < 26 }

    static func isNameByte(_ byte: UInt8) -> Bool {
        isLetter(byte) || (byte >= 0x30 && byte <= 0x39) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }

    /// Whether the bytes from `start` begin with `marker` in capitals, as the
    /// line in capitals did.
    static func hasPrefix(_ text: UnsafeBufferPointer<UInt8>, _ start: Int, _ marker: StaticString) -> Bool {
        marker.withUTF8Buffer { marker in
            for offset in 0..<marker.count {
                let byte = text[start + offset]
                if (byte &- 0x61 < 26 ? byte - 0x20 : byte) != marker[offset] { return false }
            }
            return true
        }
    }

    /// Whether a name of ASCII is `key` in small letters, as the expression
    /// kept its names.
    static func equalsIgnoringCase(_ text: UnsafeBufferPointer<UInt8>, _ lower: Int, _ upper: Int,
                                   _ key: StaticString) -> Bool {
        key.withUTF8Buffer { key in
            guard upper - lower == key.count else { return false }
            for offset in 0..<key.count {
                let byte = text[lower + offset]
                if (byte &- 0x41 < 26 ? byte | 0x20 : byte) != key[offset] { return false }
            }
            return true
        }
    }
}
