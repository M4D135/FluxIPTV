import Foundation

/// The release year chooses the physical sleeve for films and series alike.
/// A missing year is a DVD; a visual theme never turns a modern title into VHS.
public enum CasePackageFormat: String, CaseIterable, Sendable {
    case vhs, dvd

    /// The first group of exactly four digits that reads as a year, from
    /// 1800 to 2199, decides. Read by hand: every sleeve of a catalogue
    /// asks, and a regular expression built for each of them cost more
    /// than the rest of the sleeve.
    public static func resolve(year: String?) -> CasePackageFormat {
        guard let year else { return .dvd }
        var value = 0, digits = 0
        func found() -> Bool { digits == 4 && (1800...2199).contains(value) }
        for byte in year.utf8 {
            if (48...57).contains(byte) {
                digits += 1
                // A longer run is not a year; its value no longer matters.
                if digits <= 4 { value = value * 10 + Int(byte - 48) }
            } else {
                if found() { return value < 2000 ? .vhs : .dvd }
                value = 0; digits = 0
            }
        }
        return found() && value < 2000 ? .vhs : .dvd
    }

    public var title: String { self == .vhs ? "VHS" : "DVD" }
    /// Common height, distinct physical proportions and plastic thickness.
    public var halfWidth: Float { self == .vhs ? 0.93 : 1.07 }
    public var halfHeight: Float { 1.5 }
    public var bevel: Float { self == .vhs ? 0.055 : 0.035 }
    public var cornerRadius: Float { self == .vhs ? 0.085 : 0.055 }
    public var faceWidth: Float { 2 * (halfWidth - bevel) }
    public var faceHeight: Float { 2 * (halfHeight - bevel) }
    public func halfDepth(collector: Bool = false) -> Float {
        self == .vhs ? (collector ? 0.34 : 0.22) : (collector ? 0.20 : 0.11)
    }
}
