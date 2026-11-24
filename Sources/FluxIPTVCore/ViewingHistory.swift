import Foundation

/// Only opaque catalogue IDs and timing metadata are persisted. Never store stream URLs.
public struct ViewingHistory: Codable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let id: String
        public let seconds: Double
        public let duration: Double
        public let updated: Date
        public var fraction: Double { duration > 0 ? min(1, max(0, seconds / duration)) : 0 }
        public var resumable: Bool { seconds >= 30 && duration - seconds >= 30 && fraction < 0.95 }
    }
    public private(set) var entries: [String: Entry] = [:]
    public init() {}
    public mutating func record(id: String, seconds: Double, duration: Double, now: Date = Date()) {
        guard !id.isEmpty, seconds.isFinite, duration.isFinite, duration > 0, seconds >= 0 else { return }
        entries[id] = Entry(id: id, seconds: min(seconds, duration), duration: duration, updated: now)
        if entries.count > 1000 {
            let keep = entries.values.sorted { $0.updated > $1.updated }.prefix(1000)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        }
    }
    public func resumeSeconds(for id: String) -> Double? {
        guard let entry = entries[id], entry.resumable else { return nil }; return entry.seconds
    }
    public mutating func remove(id: String) { entries.removeValue(forKey: id) }
    public mutating func clear() { entries.removeAll() }
}
