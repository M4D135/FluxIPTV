import Foundation

/// The items of a part of the catalogue, read from the catalogue itself: a
/// part keeps the places of its titles in the catalogue, not copies of them.
/// The index of a catalogue of 92 000 titles held three copies of each one,
/// of 320 bytes: 88 of its 116 MB, more than the titles themselves (bench of
/// the 0.9.10). Its places now take 4 bytes a title.
public struct CatalogItems: RandomAccessCollection, Equatable, ExpressibleByArrayLiteral, Sendable {
    /// The titles of the catalogue, or those a part was made from.
    private let storage: [IPTVItem]
    /// The places in `storage` of the items, ascending, from `lower`; nil
    /// when the items are `storage` itself, from `lower`.
    private let picks: [Int32]?
    private let lower: Int
    public let count: Int

    public init(_ items: [IPTVItem] = []) {
        storage = items; picks = nil; lower = 0; count = items.count
    }

    public init(arrayLiteral elements: IPTVItem...) { self.init(elements) }

    fileprivate init(storage: [IPTVItem], picks: [Int32]?, lower: Int = 0, count: Int) {
        self.storage = storage; self.picks = picks; self.lower = lower; self.count = count
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(position: Int) -> IPTVItem {
        precondition(position >= 0 && position < count, "CatalogItems: index out of range")
        if let picks { return storage[Int(picks[lower + position])] }
        return storage[lower + position]
    }

    /// The place in the catalogue of the item at `position`.
    fileprivate func place(_ position: Int) -> Int32 {
        if let picks { return picks[lower + position] }
        return Int32(lower + position)
    }

    /// The position among these items of the title at `place`, if it is one of them.
    fileprivate func position(ofPlace place: Int32) -> Int? {
        guard let picks else {
            let position = Int(place) - lower
            return position >= 0 && position < count ? position : nil
        }
        var low = lower, high = lower + count
        while low < high {
            let middle = (low + high) / 2
            if picks[middle] < place { low = middle + 1 } else { high = middle }
        }
        return low < lower + count && picks[low] == place ? low - lower : nil
    }

    /// The category of the item at `position`, read without copying the item.
    fileprivate func group(at position: Int) -> String { storage[Int(place(position))].group }

    /// The items from `range`, without copying them.
    fileprivate func window(_ range: Range<Int>) -> CatalogItems {
        CatalogItems(storage: storage, picks: picks, lower: lower + range.lowerBound, count: range.count)
    }

    /// The items at `positions`, which ascend.
    fileprivate func picking(_ positions: [Int]) -> CatalogItems {
        let places = positions.map { place($0) }
        return CatalogItems(storage: storage, picks: places, count: places.count)
    }

    /// Other titles of the same catalogue, by their places, which ascend.
    fileprivate func sharing(_ places: [Int32]) -> CatalogItems {
        CatalogItems(storage: storage, picks: places, count: places.count)
    }

    public static func == (left: CatalogItems, right: CatalogItems) -> Bool {
        left.count == right.count && left.elementsEqual(right)
    }
}

/// Immutable, ordered catalogue window with constant-time navigation by opaque ID.
/// All expensive construction/filtering happens outside the UI actor.
public struct CatalogSlice: Sendable {
    public let items: CatalogItems
    /// The place of each title in the catalogue, by its identifier: one
    /// table for all the parts of a catalogue.
    fileprivate let places: [String: Int32]

    public init(_ items: [IPTVItem] = []) {
        var table: [String: Int32] = [:]
        table.reserveCapacity(items.count)
        for (i, item) in items.enumerated() where table[item.id] == nil { table[item.id] = Int32(i) }
        self.items = CatalogItems(items)
        places = table
    }

    fileprivate init(items: CatalogItems, places: [String: Int32]) {
        self.items = items
        self.places = places
    }

    public func index(of id: String?) -> Int? {
        guard let id, let place = places[id] else { return nil }
        return items.position(ofPlace: place)
    }
    public func item(id: String?) -> IPTVItem? { index(of: id).map { items[$0] } }
    /// Neighbors refer to the entire ordered result, not to its current grid page.
    public func adjacent(to id: String?, offset: Int) -> IPTVItem? {
        guard let i = index(of:id) else { return nil }
        let (target,overflow) = i.addingReportingOverflow(offset)
        guard !overflow, items.indices.contains(target) else { return nil }
        return items[target]
    }
    /// Keep the opened result order (copy-on-write). Playback may return to a
    /// series no longer in a filtered view; use its catalogue if possible.
    public func inspection(containing item: IPTVItem, fallback: CatalogSlice) -> CatalogSlice {
        if index(of:item.id) != nil { return self }
        if fallback.index(of:item.id) != nil { return fallback }
        return CatalogSlice([item])
    }
    public func pageCount(size: Int) -> Int { max(1, (items.count + max(1,size) - 1) / max(1,size)) }
    public func page(for id: String, size: Int) -> Int? { index(of: id).map { $0 / max(1,size) } }
    public func window(page: Int, size: Int) -> CatalogItems {
        let n = max(1,size)
        let start = min(max(0,page),pageCount(size:n)-1) * n
        return items.window(start..<min(items.count,start+n))
    }
    /// History has at most 1000 IDs: look up these rather than rescanning 60k films.
    public func retaining(ids: Set<String>) -> CatalogSlice {
        CatalogSlice(items: items.picking(ids.compactMap { index(of: $0) }.sorted()), places: places)
    }
    /// A virtual grid: no allocation of tens of thousands of focus IDs/rows per click.
    public func move(from current: String?, action: RemoteAction, prefix: [[String]], columns: Int) -> String? {
        let head = prefix.filter { !$0.isEmpty }
        guard !items.isEmpty else { return RemoteNavigation.move(from: current, action: action, rows: head) }
        let width = max(1,columns)
        if let i = index(of: current) {
            let row = i / width, col = i % width
            switch action {
            case .left: return items[max(row * width,i-1)].id
            case .right: return items[min(items.count-1,min(i+1,(row+1)*width-1))].id
            case .up:
                if row == 0, let last = head.last { return last[min(col,last.count-1)] }
                return items[max(0,i-width)].id
            case .down:
                let nextStart = (row+1)*width
                guard nextStart < items.count else { return items[i].id }
                return items[min(items.count-1,nextStart+col)].id
            default: return items[i].id
            }
        }
        guard let current, let r = head.firstIndex(where: { $0.contains(current) }), let c = head[r].firstIndex(of: current) else { return head.first?.first ?? items.first?.id }
        if action == .down && r == head.count-1 { return items[min(min(c,width-1),items.count-1)].id }
        return RemoteNavigation.move(from: current,action:action,rows:head)
    }
}

/// The categories of the titles of a kind, each one numbered once: the
/// titles are sorted into them by number, without hashing their names again.
struct CatalogGroups: Sendable {
    /// Each category once, as the provider writes it.
    let names: [String]
    /// The number of the category of each title, by its position in the kind.
    let ofTitle: [Int32]
    /// The rank of each category in the order of their names.
    let rank: [Int32]

    init(_ items: CatalogItems) {
        var numbers: [String: Int32] = [:]
        var names: [String] = []
        var ofTitle: [Int32] = []
        ofTitle.reserveCapacity(items.count)
        for position in 0..<items.count {
            let group = items.group(at: position)
            if let number = numbers[group] { ofTitle.append(number); continue }
            let number = Int32(names.count)
            numbers[group] = number
            names.append(group)
            ofTitle.append(number)
        }
        let order = names.indices.sorted { names[$0].localizedStandardCompare(names[$1]) == .orderedAscending }
        var rank = [Int32](repeating: 0, count: names.count)
        for (r, number) in order.enumerated() { rank[number] = Int32(r) }
        self.names = names
        self.ofTitle = ofTitle
        self.rank = rank
    }
}

public struct CatalogResults: Sendable {
    public let revision = UUID()
    public let kind: IPTVMediaKind
    public let all: CatalogSlice
    public let groups: [String]
    private let sections: [String: CatalogSlice]

    public init(kind: IPTVMediaKind, items: [IPTVItem] = []) {
        let all = CatalogSlice(items)
        self.init(kind: kind, all: all, groups: CatalogGroups(all.items), positions: nil)
    }

    /// The titles of `all` sorted into their categories. `positions` are
    /// the positions of the titles of `all` in the kind that `groups`
    /// numbers; nil when `all` is the kind itself.
    fileprivate init(kind: IPTVMediaKind, all: CatalogSlice, groups: CatalogGroups, positions: [Int]?) {
        self.kind = kind
        self.all = all
        let items = all.items
        var buckets = [[Int32]](repeating: [], count: groups.names.count)
        for local in 0..<items.count {
            let position = positions?[local] ?? local
            buckets[Int(groups.ofTitle[position])].append(items.place(local))
        }
        var sections: [String: CatalogSlice] = [:]
        sections.reserveCapacity(groups.names.count)
        var present: [Int] = []
        for (number, places) in buckets.enumerated() where !places.isEmpty {
            present.append(number)
            sections[groups.names[number]] = CatalogSlice(items: items.sharing(places), places: all.places)
        }
        self.groups = present.sorted { groups.rank[$0] < groups.rank[$1] }.map { groups.names[$0] }
        self.sections = sections
    }

    public func slice(group: String?) -> CatalogSlice { group.map { sections[$0] ?? CatalogSlice() } ?? all }
}

/// The search of the catalogue: a title and its category are compared
/// without case or accents, as bytes, and the search finds what
/// `localizedStandardContains` found (widths are kept, as it kept them).
/// That call on each title and each category took 70 to 140 ms per search
/// over 60 000 films on a Mac, and the counts of the three kinds 110 to
/// 220 ms more (bench of the 0.9.10); an Apple TV HD is about ten times
/// slower. The folded bytes take 1 to 3 ms.
public enum CatalogSearch {
    /// A text as the search compares it.
    public static func fold(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        append(text, to: &bytes)
        return bytes
    }

    /// Whether `text` holds the query `term`, as the search of the catalogue finds it.
    public static func matches(_ text: String, term: String) -> Bool {
        let needle = fold(term.trimmingCharacters(in: .whitespacesAndNewlines))
        return needle.isEmpty || contains(fold(text), needle)
    }

    static func append(_ text: String, to bytes: inout [UInt8]) {
        var ascii = true
        for byte in text.utf8 where byte >= 0x80 { ascii = false; break }
        if ascii {
            // Most titles: their capitals become small letters, nothing else changes.
            for byte in text.utf8 { bytes.append(byte &- 0x41 < 26 ? byte | 0x20 : byte) }
        } else {
            let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            bytes.append(contentsOf: folded.precomposedStringWithCanonicalMapping.utf8)
        }
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.withUnsafeBufferPointer { text in
            needle.withUnsafeBufferPointer { term in ByteSearch.contains(text, term) }
        }
    }
}

/// The names and the categories of the titles of a kind, folded once for
/// the search, one name after the other in a single run of bytes.
struct CatalogSearchKeys: Sendable {
    private let names: [UInt8]
    /// Where the name of the title at each position ends in `names`.
    private let ends: [Int32]
    /// The folded name of each category, by its number.
    let groups: [[UInt8]]

    init(_ items: CatalogItems, groups: CatalogGroups) {
        var names: [UInt8] = []
        names.reserveCapacity(items.count * 32)
        var ends: [Int32] = []
        ends.reserveCapacity(items.count)
        for item in items {
            CatalogSearch.append(item.name, to: &names)
            ends.append(Int32(names.count))
        }
        self.names = names
        self.ends = ends
        self.groups = groups.names.map(CatalogSearch.fold)
    }

    /// Calls `body` with a test of whether the name at a position holds `needle`.
    func withNames<Result>(_ needle: [UInt8], _ body: ((Int) -> Bool) throws -> Result) rethrows -> Result {
        try names.withUnsafeBufferPointer { text in
            try needle.withUnsafeBufferPointer { term in
                try ends.withUnsafeBufferPointer { ends in
                    try body { position in
                        let start = position == 0 ? 0 : Int(ends[position - 1]), end = Int(ends[position])
                        guard term.count <= end - start, let base = text.baseAddress, let wanted = term.baseAddress else { return false }
                        return ByteSearch.contains(base + start, end - start, wanted, term.count)
                    }
                }
            }
        }
    }
}

public struct CatalogIndex: Sendable {
    /// A label in front of titles counts as a language tag once it is shared
    /// by this many titles; a lone "It - Chapter Two" is a title, not Italian.
    /// A language found on fewer titles of a kind is not offered either: a
    /// real catalogue yields such strays from ordinary words ("LA …" as Lao).
    public static let titleLabelThreshold = 3

    public let items: [IPTVItem]
    public let liveCountries: [LiveCountry]
    private let all: CatalogSlice
    private let kinds: [IPTVMediaKind: CatalogResults]
    private let groups: [IPTVMediaKind: CatalogGroups]
    private let keys: [IPTVMediaKind: CatalogSearchKeys]
    private let liveCountryByGroup: [String: String]
    /// The language of each title, by its place: a number among
    /// `languageCodes`, whose first one, "", is no language (a channel).
    private let languageOfPlace: [UInt16]
    private let languageCodes: [String]
    private let mediaLanguages: [IPTVMediaKind: [MediaLanguage]]
    private let mediaLanguagesByGroup: [IPTVMediaKind: [String: Set<String>]]

    public init(_ items: [IPTVItem] = []) {
        // Provider duplicates would otherwise violate SwiftUI's stable identity contract.
        var places: [String: Int32] = [:]
        places.reserveCapacity(items.count)
        var duplicates = false
        for (place, item) in items.enumerated() {
            if places[item.id] == nil { places[item.id] = Int32(place) } else { duplicates = true }
        }
        // Without duplicates, as a provider gives most of them, the titles
        // are kept as they came: a copy of 92 000 of them is 29 MB more
        // while the catalogue is indexed.
        let unique: [IPTVItem]
        if duplicates {
            places.removeAll(keepingCapacity: true)
            var kept: [IPTVItem] = []
            kept.reserveCapacity(items.count)
            for item in items where places[item.id] == nil {
                places[item.id] = Int32(kept.count)
                kept.append(item)
            }
            unique = kept
        } else { unique = items }
        var picksOfKind: [IPTVMediaKind: [Int32]] = [:]
        for (place, item) in unique.enumerated() { picksOfKind[item.kind, default: []].append(Int32(place)) }
        self.items = unique
        let all = CatalogSlice(items: CatalogItems(unique), places: places)
        self.all = all

        var kinds: [IPTVMediaKind: CatalogResults] = [:]
        var groups: [IPTVMediaKind: CatalogGroups] = [:]
        var keys: [IPTVMediaKind: CatalogSearchKeys] = [:]
        var slices: [IPTVMediaKind: CatalogItems] = [:]
        for kind in IPTVMediaKind.allCases {
            let picks = picksOfKind[kind] ?? []
            let titles = all.items.sharing(picks)
            let numbered = CatalogGroups(titles)
            slices[kind] = titles
            groups[kind] = numbered
            keys[kind] = CatalogSearchKeys(titles, groups: numbered)
            kinds[kind] = CatalogResults(kind: kind, all: CatalogSlice(items: titles, places: places),
                                         groups: numbered, positions: nil)
        }
        self.kinds = kinds
        self.groups = groups
        self.keys = keys

        // Parse each distinct provider category once while building the index,
        // never while the user moves the focus or redraws a channel card.
        var codes: [String: String] = [:]
        var counts: [String: Int] = [:]
        if let live = groups[.live] {
            var titles = [Int](repeating: 0, count: live.names.count)
            for number in live.ofTitle { titles[Int(number)] += 1 }
            for (number, name) in live.names.enumerated() {
                let code = LiveCountry.detectCode(in: name) ?? LiveCountry.unknownCode
                codes[name] = code
                counts[code, default: 0] += titles[number]
            }
        }
        liveCountryByGroup = codes
        liveCountries = counts.map { LiveCountry(code: $0.key, channelCount: $0.value) }.sorted {
            if $0.code == LiveCountry.unknownCode { return false }
            if $1.code == LiveCountry.unknownCode { return true }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        // Films and series: the label in front of the title, then the label
        // of its category. Each distinct label is parsed once.
        let mediaKinds = IPTVMediaKind.allCases.filter { $0 != .live }
        var labels: [IPTVMediaKind: [String?]] = [:]
        var labelUse: [String: Int] = [:]
        for kind in mediaKinds {
            let found = (slices[kind] ?? []).map { MediaLanguage.titleLabel(of: $0.name) }
            for label in found { if let label { labelUse[label, default: 0] += 1 } }
            labels[kind] = found
        }
        var labelCodes: [String: String] = [:]
        for (label, use) in labelUse where use >= Self.titleLabelThreshold {
            if let code = MediaLanguage.detectCode(in: label) { labelCodes[label] = code }
        }
        var groupCodes: [String: String] = [:]
        var detected: [IPTVMediaKind: [String]] = [:]
        var found: [IPTVMediaKind: [String: Int]] = [:]
        for kind in mediaKinds {
            let titles = slices[kind] ?? []
            var codesOfKind: [String] = []
            codesOfKind.reserveCapacity(titles.count)
            for (position, label) in (labels[kind] ?? []).enumerated() {
                var code = label.flatMap { labelCodes[$0] }
                if code == nil {
                    let group = titles.group(at: position)
                    if let known = groupCodes[group] { code = known }
                    else {
                        let fromGroup = MediaLanguage.detectCode(in: group) ?? MediaLanguage.unknownCode
                        groupCodes[group] = fromGroup
                        code = fromGroup
                    }
                }
                let language = code ?? MediaLanguage.unknownCode
                codesOfKind.append(language)
                found[kind, default: [:]][language, default: 0] += 1
            }
            detected[kind] = codesOfKind
        }
        var languageCodes = [""]
        var numbers: [String: UInt16] = [:]
        var languageOfPlace = [UInt16](repeating: 0, count: unique.count)
        var totals: [IPTVMediaKind: [String: Int]] = [:]
        var byGroup: [IPTVMediaKind: [String: Set<String>]] = [:]
        for kind in mediaKinds {
            let titles = slices[kind] ?? []
            for (position, code) in (detected[kind] ?? []).enumerated() {
                let stray = code != MediaLanguage.unknownCode && (found[kind]?[code] ?? 0) < Self.titleLabelThreshold
                let language = stray ? MediaLanguage.unknownCode : code
                let number: UInt16
                if let known = numbers[language] { number = known }
                else {
                    number = UInt16(languageCodes.count)
                    numbers[language] = number
                    languageCodes.append(language)
                }
                languageOfPlace[Int(titles.place(position))] = number
                totals[kind, default: [:]][language, default: 0] += 1
                byGroup[kind, default: [:]][titles.group(at: position), default: []].insert(language)
            }
        }
        self.languageOfPlace = languageOfPlace
        self.languageCodes = languageCodes
        mediaLanguagesByGroup = byGroup
        mediaLanguages = totals.mapValues { counts in
            counts.map { MediaLanguage(code: $0.key, titleCount: $0.value) }.sorted {
                let special = [MediaLanguage.originalCode: 1, MediaLanguage.multipleCode: 2, MediaLanguage.unknownCode: 3]
                let left = special[$0.code] ?? 0, right = special[$1.code] ?? 0
                if left != right { return left < right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
    /// Languages found in the films or in the series; empty for channels.
    public func languages(for kind: IPTVMediaKind) -> [MediaLanguage] { mediaLanguages[kind] ?? [] }
    /// Language of a film, a series or one of its listed entries; nil for a channel.
    public func language(of item: IPTVItem) -> String? {
        guard let place = all.places[item.id] else { return nil }
        let number = Int(languageOfPlace[Int(place)])
        return number == 0 ? nil : languageCodes[number]
    }
    public func category(_ group: String, of kind: IPTVMediaKind, has language: String) -> Bool {
        mediaLanguagesByGroup[kind]?[group]?.contains(language) ?? false
    }
    public func item(id: String?) -> IPTVItem? { all.item(id:id) }
    public func unfiltered(_ kind: IPTVMediaKind) -> CatalogResults { kinds[kind] ?? CatalogResults(kind:kind) }
    /// `countryCode` is the country of a channel's category, or the language
    /// of a film or series: each kind has one such filter.
    public func matching(kind: IPTVMediaKind, search: String, membership: Set<String>? = nil, countryCode: String? = nil) throws -> CatalogResults {
        let base = unfiltered(kind)
        let needle = CatalogSearch.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let country = kind == .live ? countryCode : nil
        let language = kind == .live ? nil : countryCode
        if needle.isEmpty && membership == nil && country == nil && language == nil { return base }
        guard let numbered = groups[kind] else { return CatalogResults(kind: kind) }
        var found: [Int] = []
        try scan(kind: kind, needle: needle, membership: membership, country: country, language: language) { found.append($0) }
        return CatalogResults(kind: kind, all: CatalogSlice(items: base.all.items.picking(found), places: all.places),
                              groups: numbered, positions: found)
    }

    /// How many titles of `kind` the search finds, without gathering them.
    public func count(kind: IPTVMediaKind, search: String) throws -> Int {
        let needle = CatalogSearch.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        if needle.isEmpty { return unfiltered(kind).all.items.count }
        var count = 0
        try scan(kind: kind, needle: needle, membership: nil, country: nil, language: nil) { _ in count += 1 }
        return count
    }

    /// Calls `hit` with the position in its kind of each title that the
    /// search and the filters keep, in the order of the kind.
    private func scan(kind: IPTVMediaKind, needle: [UInt8], membership: Set<String>?, country: String?, language: String?,
                      hit: (Int) -> Void) throws {
        let base = unfiltered(kind).all
        guard let numbered = groups[kind], let keys = keys[kind] else { return }
        // What depends on the category alone is decided once per category.
        let groupHolds: [Bool]? = needle.isEmpty ? nil : keys.groups.map { CatalogSearch.contains($0, needle) }
        let groupAllowed: [Bool]? = country.map { code in numbered.names.map { liveCountryByGroup[$0] == code } }
        var wanted: UInt16?
        if let language {
            guard let number = languageCodes.firstIndex(of: language), number > 0 else { return }
            wanted = UInt16(number)
        }
        let positions: [Int]? = membership.map { ids in ids.compactMap { base.index(of: $0) }.sorted() }
        try keys.withNames(needle) { nameHolds in
            func keeps(_ position: Int) -> Bool {
                let group = Int(numbered.ofTitle[position])
                if let groupAllowed, !groupAllowed[group] { return false }
                if let wanted, languageOfPlace[Int(base.items.place(position))] != wanted { return false }
                guard let groupHolds else { return true }
                return groupHolds[group] || nameHolds(position)
            }
            if let positions {
                for (n, position) in positions.enumerated() {
                    if n.isMultiple(of: 256) { try Task.checkCancellation() }
                    if keeps(position) { hit(position) }
                }
            } else {
                for position in 0..<base.items.count {
                    if position.isMultiple(of: 256) { try Task.checkCancellation() }
                    if keeps(position) { hit(position) }
                }
            }
        }
        try Task.checkCancellation()
    }
}

/// The all-content filter is active only when *every* restriction is clear.
public enum CatalogScope {
    public static func isAll(group: String?, search: String, presetID: String?, resumeOnly: Bool, countryCode: String? = nil) -> Bool {
        group == nil && search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && presetID == nil && !resumeOnly && countryCode == nil
    }
}
