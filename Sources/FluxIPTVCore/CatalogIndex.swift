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
    public let items: [IPTVItem]
    private let all: CatalogSlice
    private let kinds: [IPTVMediaKind: CatalogResults]
    public init(_ items: [IPTVItem] = []) {
        // Provider duplicates would otherwise violate SwiftUI's stable identity contract.
        var seen = Set<String>(); seen.reserveCapacity(items.count)
        let unique = items.filter { seen.insert($0.id).inserted }
        self.items = unique
        all = CatalogSlice(unique)
        let grouped = Dictionary(grouping: unique, by: \.kind)
        kinds = Dictionary(uniqueKeysWithValues: IPTVMediaKind.allCases.map { ($0,CatalogResults(kind:$0,items:grouped[$0] ?? [])) })
    }
    public func item(id: String?) -> IPTVItem? { all.item(id:id) }
    public func unfiltered(_ kind: IPTVMediaKind) -> CatalogResults { kinds[kind] ?? CatalogResults(kind:kind) }
    public func matching(kind: IPTVMediaKind, search: String, membership: Set<String>? = nil) throws -> CatalogResults {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = unfiltered(kind)
        if term.isEmpty && membership == nil { return base }
        let candidates = membership.map { base.all.retaining(ids:$0).items } ?? base.all.items
        var found: [IPTVItem] = []
        found.reserveCapacity(candidates.count)
        for (i,item) in candidates.enumerated() {
            if i.isMultiple(of:256) { try Task.checkCancellation() }
            if term.isEmpty || item.name.localizedStandardContains(term) || item.group.localizedStandardContains(term) { found.append(item) }
        }
        try Task.checkCancellation()
        return CatalogResults(kind:kind,items:found)
    }
}

/// The all-content filter is active only when *every* restriction is clear.
public enum CatalogScope {
    public static func isAll(group: String?, search: String, presetID: String?, resumeOnly: Bool) -> Bool {
        group == nil && search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && presetID == nil && !resumeOnly
    }
}
