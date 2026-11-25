import Foundation

/// The release year chooses the physical sleeve for films and series alike.
/// A missing year is a DVD; a visual theme never turns a modern title into VHS.
public enum CasePackageFormat: String, CaseIterable, Sendable {
    case vhs, dvd

    public static func resolve(year: String?) -> CasePackageFormat {
        guard let year,
              let range = year.range(of: #"(?<![0-9])(?:18|19|20|21)[0-9]{2}(?![0-9])"#, options: .regularExpression),
              let value = Int(year[range]) else { return .dvd }
        return value < 2000 ? .vhs : .dvd
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
