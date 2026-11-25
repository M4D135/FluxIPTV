import Foundation

/// Browsing choices only: no source address, credential, or media URL is stored.
/// Each source and media section owns an independent instance.
public struct CatalogBrowsingState: Codable, Equatable, Sendable {
    public var countryCode: String?
    public var group: String?
    public var search: String
    public var groupSearch: String
    public var presetID: String?
    public var continueOnly: Bool
    public var catalogPage: Int
    public var browseItemID: String?

    public init(countryCode: String? = nil, group: String? = nil, search: String = "",
                groupSearch: String = "", presetID: String? = nil, continueOnly: Bool = false,
                catalogPage: Int = 0, browseItemID: String? = nil) {
        self.countryCode = countryCode
        self.group = group
        self.search = search
        self.groupSearch = groupSearch
        self.presetID = presetID
        self.continueOnly = continueOnly
        self.catalogPage = max(0, catalogPage)
        self.browseItemID = browseItemID
    }

    /// Call only with the completed source catalogue, never with a temporary
    /// empty/search result. A search with no matches must not forget a category.
    public func validated(kind: IPTVMediaKind, index: CatalogIndex, presets: FavoritePresets) -> Self {
        var result = self
        result.catalogPage = max(0, result.catalogPage)
        if kind != .live || !index.liveCountries.contains(where: { $0.code == result.countryCode }) {
            result.countryCode = nil
        }
        let complete = index.unfiltered(kind)
        if let group = result.group {
            let countryMatches = result.countryCode == nil
                || (LiveCountry.detectCode(in: group) ?? LiveCountry.unknownCode) == result.countryCode
            if !complete.groups.contains(group) || !countryMatches { result.group = nil }
        }
        if let id = result.presetID, presets.list(id: id)?.kind != kind { result.presetID = nil }
        if kind != .movie || result.presetID != nil { result.continueOnly = false }
        if let id = result.browseItemID {
            let item = complete.all.item(id: id)
            let term = result.search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = item.map {
                (result.group == nil || result.group == $0.group)
                    && (result.countryCode == nil || (LiveCountry.detectCode(in: $0.group) ?? LiveCountry.unknownCode) == result.countryCode)
                    && (term.isEmpty || $0.name.localizedStandardContains(term) || $0.group.localizedStandardContains(term))
                    && (result.presetID.flatMap { presets.list(id: $0) }?.itemIDs.contains($0.id) ?? true)
            } ?? false
            if !matches { result.browseItemID = nil; result.catalogPage = 0 }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case countryCode, group, search, groupSearch, presetID, continueOnly, catalogPage, browseItemID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try values.decodeIfPresent(String.self, forKey: .countryCode)
        group = try values.decodeIfPresent(String.self, forKey: .group)
        search = try values.decodeIfPresent(String.self, forKey: .search) ?? ""
        groupSearch = try values.decodeIfPresent(String.self, forKey: .groupSearch) ?? ""
        presetID = try values.decodeIfPresent(String.self, forKey: .presetID)
        continueOnly = try values.decodeIfPresent(Bool.self, forKey: .continueOnly) ?? false
        catalogPage = max(0, try values.decodeIfPresent(Int.self, forKey: .catalogPage) ?? 0)
        browseItemID = try values.decodeIfPresent(String.self, forKey: .browseItemID)
    }
}

/// Versioned, source-scoped storage. Refreshing one source cannot overwrite the
/// filters of another source or of an inactive media section.
public struct CatalogBrowsingPreferences: Codable, Equatable, Sendable {
    public static let storageKey = "fluxiptv.catalogBrowsing.v1"
    public private(set) var lastSourceID: UUID?
    private var version = 1
    private var contexts: [String: [String: CatalogBrowsingState]] = [:]
    private var preferredKinds: [String: IPTVMediaKind] = [:]

    public init() {}

    public static func decoded(_ data: Data?) -> Self {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data), saved.version == 1 else {
            return Self()
        }
        return saved
    }

    public func state(for sourceID: UUID, kind: IPTVMediaKind) -> CatalogBrowsingState {
        contexts[sourceID.uuidString]?[kind.rawValue] ?? CatalogBrowsingState()
    }

    public func preferredKind(for sourceID: UUID) -> IPTVMediaKind? { preferredKinds[sourceID.uuidString] }

    public mutating func select(sourceID: UUID, kind: IPTVMediaKind) {
        lastSourceID = sourceID
        preferredKinds[sourceID.uuidString] = kind
    }

    public mutating func remember(_ state: CatalogBrowsingState, sourceID: UUID, kind: IPTVMediaKind) {
        contexts[sourceID.uuidString, default: [:]][kind.rawValue] = state
        select(sourceID: sourceID, kind: kind)
    }

    public mutating func removeSource(_ sourceID: UUID) {
        contexts.removeValue(forKey: sourceID.uuidString)
        preferredKinds.removeValue(forKey: sourceID.uuidString)
        if lastSourceID == sourceID { lastSourceID = nil }
    }

    public mutating func retainSources(_ sourceIDs: Set<UUID>) {
        let keys = Set(sourceIDs.map(\.uuidString))
        contexts = contexts.filter { keys.contains($0.key) }
        preferredKinds = preferredKinds.filter { keys.contains($0.key) }
        if let lastSourceID, !sourceIDs.contains(lastSourceID) { self.lastSourceID = nil }
    }
}
