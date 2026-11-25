import Foundation

/// Immutable, ordered catalogue window with constant-time navigation by opaque ID.
/// All expensive construction/filtering happens outside the UI actor.
public struct CatalogSlice: Sendable {
    public let items: [IPTVItem]
    private let positions: [String: Int]
    public init(_ items: [IPTVItem] = []) {
        self.items = items
        var offsets: [String: Int] = [:]
        offsets.reserveCapacity(items.count)
        for (i, item) in items.enumerated() where offsets[item.id] == nil { offsets[item.id] = i }
        positions = offsets
    }
    public func index(of id: String?) -> Int? { id.flatMap { positions[$0] } }
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
    public func window(page: Int, size: Int) -> ArraySlice<IPTVItem> {
        let n = max(1,size)
        let start = min(max(0,page),pageCount(size:n)-1) * n
        return items[start..<min(items.count,start+n)]
    }
    /// History has at most 1000 IDs: look up these rather than rescanning 60k films.
    public func retaining(ids: Set<String>) -> CatalogSlice {
        let indexes = ids.compactMap { positions[$0] }.sorted()
        return CatalogSlice(indexes.map { items[$0] })
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

public struct CatalogResults: Sendable {
    public let revision = UUID()
    public let kind: IPTVMediaKind
    public let all: CatalogSlice
    public let groups: [String]
    private let sections: [String: CatalogSlice]
    public init(kind: IPTVMediaKind, items: [IPTVItem] = []) {
        self.kind = kind
        all = CatalogSlice(items)
        let grouped = Dictionary(grouping: items, by: \.group)
        groups = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        sections = grouped.mapValues(CatalogSlice.init)
    }
    public func slice(group: String?) -> CatalogSlice { group.map { sections[$0] ?? CatalogSlice() } ?? all }
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
    private let liveCountryByGroup: [String: String]
    private let mediaLanguageByID: [String: String]
    private let mediaLanguages: [IPTVMediaKind: [MediaLanguage]]
    private let mediaLanguagesByGroup: [IPTVMediaKind: [String: Set<String>]]
    public init(_ items: [IPTVItem] = []) {
        // Provider duplicates would otherwise violate SwiftUI's stable identity contract.
        var seen = Set<String>(); seen.reserveCapacity(items.count)
        let unique = items.filter { seen.insert($0.id).inserted }
        self.items = unique
        all = CatalogSlice(unique)
        let grouped = Dictionary(grouping: unique, by: \.kind)
        kinds = Dictionary(uniqueKeysWithValues: IPTVMediaKind.allCases.map { ($0,CatalogResults(kind:$0,items:grouped[$0] ?? [])) })
        // Parse each distinct provider category once while building the index,
        // never while the user moves the focus or redraws a channel card.
        let liveGroups = Dictionary(grouping: grouped[.live] ?? [], by: \.group)
        var codes: [String: String] = [:]
        var counts: [String: Int] = [:]
        for (name, channels) in liveGroups {
            let code = LiveCountry.detectCode(in: name) ?? LiveCountry.unknownCode
            codes[name] = code
            counts[code, default: 0] += channels.count
        }
        liveCountryByGroup = codes
        liveCountries = counts.map { LiveCountry(code: $0.key, channelCount: $0.value) }.sorted {
            if $0.code == LiveCountry.unknownCode { return false }
            if $1.code == LiveCountry.unknownCode { return true }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        // Films and series: the label in front of the title, then the label
        // of its category. Each distinct label is parsed once.
        let media = unique.filter { $0.kind != .live }
        let labels = media.map { MediaLanguage.titleLabel(of: $0.name) }
        var labelUse: [String: Int] = [:]
        for label in labels { if let label { labelUse[label, default: 0] += 1 } }
        var labelCodes: [String: String] = [:]
        for (label, use) in labelUse where use >= Self.titleLabelThreshold {
            if let code = MediaLanguage.detectCode(in: label) { labelCodes[label] = code }
        }
        var groupCodes: [String: String] = [:]
        var detected: [String] = []
        detected.reserveCapacity(media.count)
        var found: [IPTVMediaKind: [String: Int]] = [:]
        for (item, label) in zip(media, labels) {
            var code = label.flatMap { labelCodes[$0] }
            if code == nil {
                if let known = groupCodes[item.group] { code = known }
                else {
                    let fromGroup = MediaLanguage.detectCode(in: item.group) ?? MediaLanguage.unknownCode
                    groupCodes[item.group] = fromGroup
                    code = fromGroup
                }
            }
            let language = code ?? MediaLanguage.unknownCode
            detected.append(language)
            found[item.kind, default: [:]][language, default: 0] += 1
        }
        var byID: [String: String] = [:]
        byID.reserveCapacity(media.count)
        var totals: [IPTVMediaKind: [String: Int]] = [:]
        var byGroup: [IPTVMediaKind: [String: Set<String>]] = [:]
        for (item, code) in zip(media, detected) {
            let stray = code != MediaLanguage.unknownCode && (found[item.kind]?[code] ?? 0) < Self.titleLabelThreshold
            let language = stray ? MediaLanguage.unknownCode : code
            byID[item.id] = language
            totals[item.kind, default: [:]][language, default: 0] += 1
            byGroup[item.kind, default: [:]][item.group, default: []].insert(language)
        }
        mediaLanguageByID = byID
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
    public func language(of item: IPTVItem) -> String? { mediaLanguageByID[item.id] }
    public func category(_ group: String, of kind: IPTVMediaKind, has language: String) -> Bool {
        mediaLanguagesByGroup[kind]?[group]?.contains(language) ?? false
    }
    public func item(id: String?) -> IPTVItem? { all.item(id:id) }
    public func unfiltered(_ kind: IPTVMediaKind) -> CatalogResults { kinds[kind] ?? CatalogResults(kind:kind) }
    /// `countryCode` is the country of a channel's category, or the language
    /// of a film or series: each kind has one such filter.
    public func matching(kind: IPTVMediaKind, search: String, membership: Set<String>? = nil, countryCode: String? = nil) throws -> CatalogResults {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = unfiltered(kind)
        let country = kind == .live ? countryCode : nil
        let language = kind == .live ? nil : countryCode
        if term.isEmpty && membership == nil && country == nil && language == nil { return base }
        let candidates = membership.map { base.all.retaining(ids:$0).items } ?? base.all.items
        var found: [IPTVItem] = []
        found.reserveCapacity(candidates.count)
        for (i,item) in candidates.enumerated() {
            if i.isMultiple(of:256) { try Task.checkCancellation() }
            if let country, liveCountryByGroup[item.group] != country { continue }
            if let language, mediaLanguageByID[item.id] != language { continue }
            if term.isEmpty || item.name.localizedStandardContains(term) || item.group.localizedStandardContains(term) { found.append(item) }
        }
        try Task.checkCancellation()
        return CatalogResults(kind:kind,items:found)
    }
}

/// The all-content filter is active only when *every* restriction is clear.
public enum CatalogScope {
    public static func isAll(group: String?, search: String, presetID: String?, resumeOnly: Bool, countryCode: String? = nil) -> Bool {
        group == nil && search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && presetID == nil && !resumeOnly && countryCode == nil
    }
}
