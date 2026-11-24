import Foundation

/// Only stable item IDs are persisted. Never store a playlist URL or a credential here.
public struct FavoritePreset: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: IPTVMediaKind
    public var name: String
    public var itemIDs: Set<String>
    public let isDefault: Bool
}

public struct FavoritePresets: Codable, Sendable {
    public private(set) var lists: [FavoritePreset]
    // In v0.1 all M3U entries were classified as live. Reclassify just these migrated
    // IDs when their playlist is loaded; never move user-created memberships.
    private var pendingM3U: Set<String>

    public init(legacyIDs: Set<String> = []) {
        lists = IPTVMediaKind.allCases.map { kind in
            FavoritePreset(id: Self.defaultID(for: kind), kind: kind, name: "Favoris", itemIDs: [], isDefault: true)
        }
        pendingM3U = []
        for id in legacyIDs {
            let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
            let type = parts.count > 1 ? parts[1] : ""
            if type == "m3u" { pendingM3U.insert(id) }
            let kind = IPTVMediaKind(rawValue: type) ?? .live
            if let index = lists.firstIndex(where: { $0.kind == kind && $0.isDefault }) {
                lists[index].itemIDs.insert(id)
            }
        }
    }

    public static func defaultID(for kind: IPTVMediaKind) -> String { "default-\(kind.rawValue)" }
    public func lists(for kind: IPTVMediaKind) -> [FavoritePreset] { lists.filter { $0.kind == kind } }
    public func list(id: String) -> FavoritePreset? { lists.first { $0.id == id } }

    @discardableResult public mutating func create(name: String, kind: IPTVMediaKind) -> String? {
        guard let clean = availableName(name, kind: kind, except: nil) else { return nil }
        let id = UUID().uuidString
        lists.append(FavoritePreset(id: id, kind: kind, name: clean, itemIDs: [], isDefault: false))
        return id
    }

    @discardableResult public mutating func rename(id: String, name: String) -> Bool {
        guard let i = lists.firstIndex(where: { $0.id == id }),
              let clean = availableName(name, kind: lists[i].kind, except: id) else { return false }
        lists[i].name = clean
        return true
    }

    @discardableResult public mutating func delete(id: String) -> Bool {
        guard let i = lists.firstIndex(where: { $0.id == id && !$0.isDefault }) else { return false }
        lists.remove(at: i)
        return true
    }

    @discardableResult public mutating func toggle(_ item: IPTVItem, in id: String) -> Bool {
        guard let i = lists.firstIndex(where: { $0.id == id && $0.kind == item.kind }) else { return false }
        if !lists[i].itemIDs.insert(item.id).inserted { lists[i].itemIDs.remove(item.id) }
        pendingM3U.remove(item.id)
        return true
    }

    /// Commit the user's entire list choice only after confirmation. Validation
    /// happens first, so an invalid new name or a stale list changes nothing.
    @discardableResult public mutating func assign(_ item: IPTVItem, to selectedIDs: Set<String>, creating name: String? = nil) -> Bool {
        let validIDs = Set(lists(for: item.kind).map(\.id))
        guard selectedIDs.isSubset(of: validIDs) else { return false }
        var draft = self
        var memberships = selectedIDs
        if let name {
            guard let id = draft.create(name: name, kind: item.kind) else { return false }
            memberships.insert(id)
        }
        for i in draft.lists.indices where draft.lists[i].kind == item.kind {
            if memberships.contains(draft.lists[i].id) { draft.lists[i].itemIDs.insert(item.id) }
            else { draft.lists[i].itemIDs.remove(item.id) }
        }
        draft.pendingM3U.remove(item.id)
        self = draft
        return true
    }

    public mutating func removeSource(_ sourceID: UUID) {
        let prefix = sourceID.uuidString + ":"
        for i in lists.indices { lists[i].itemIDs = Set(lists[i].itemIDs.filter { !$0.hasPrefix(prefix) }) }
        pendingM3U = Set(pendingM3U.filter { !$0.hasPrefix(prefix) })
    }

    public mutating func reconcileMigratedM3U(_ items: [IPTVItem]) -> Bool {
        guard !pendingM3U.isEmpty else { return false }
        var changed = false
        for item in items where pendingM3U.contains(item.id) {
            pendingM3U.remove(item.id)
            changed = true
            guard item.kind != .live,
                  let old = lists.firstIndex(where: { $0.id == Self.defaultID(for: .live) }),
                  let new = lists.firstIndex(where: { $0.id == Self.defaultID(for: item.kind) }) else { continue }
            if lists[old].itemIDs.remove(item.id) != nil { lists[new].itemIDs.insert(item.id) }
        }
        return changed
    }

    private func availableName(_ name: String, kind: IPTVMediaKind, except: String?) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 60, !lists.contains(where: {
            $0.kind == kind && $0.id != except && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        return clean
    }
}
