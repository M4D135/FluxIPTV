import Foundation

/// The machine the app runs on, as far as the drawing of the screens goes:
/// what an Apple TV HD keeps fluid is not what an Apple TV 4K of 2022 can
/// afford. "detecte le matos pour voir qualité graphique a appliquer"
/// (David, 26/11).
public enum FluxDeviceClass: String, CaseIterable, Sendable {
    /// Apple TV HD (A8, 2 GB, 2015): the oldest Apple TV that takes apps.
    case appleTVHD
    /// Apple TV 4K of the first generation (A10X, 3 GB, 2017).
    case appleTV4KFirst
    /// Apple TV 4K of 2021 and later (A12, A15…).
    case appleTV4K
    /// A Mac with an Apple chip.
    case macAppleSilicon
    /// A Mac with an Intel processor.
    case macIntel
    /// An iPhone or an iPad with less than 4 GB.
    case mobileModest
    /// An iPhone or an iPad with 4 GB or more.
    case mobile
    /// A machine this version does not know: drawn as the most demanding
    /// known one of its kind would be.
    case unknown

    /// `machine`: the model identifier, as `uname` gives it on a device
    /// (`AppleTV5,3`) or the simulator in `SIMULATOR_MODEL_IDENTIFIER`.
    /// `memory`: the bytes of memory. `appleSilicon`: a Mac on an Apple chip.
    public static func classify(machine: String, memory: UInt64, platform: Platform, appleSilicon: Bool = true) -> Self {
        switch platform {
        case .tvOS:
            guard machine.hasPrefix("AppleTV"), let major = Self.major(machine) else { return .unknown }
            // AppleTV5,3 is the Apple TV HD; AppleTV6,2 the first 4K; the
            // later ones are AppleTV11,1 (2021) and AppleTV14,1 (2022).
            if major <= 5 { return .appleTVHD }
            if major == 6 { return .appleTV4KFirst }
            return .appleTV4K
        case .macOS:
            return appleSilicon ? .macAppleSilicon : .macIntel
        case .iOS:
            return memory >= 3_800_000_000 ? .mobile : .mobileModest
        }
    }

    public enum Platform: Sendable { case tvOS, macOS, iOS }

    /// The number before the comma of a model identifier.
    private static func major(_ machine: String) -> Int? {
        let digits = machine.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// The preset that keeps this machine fluid.
    public var recommended: FluxQualityPreset {
        switch self {
        case .appleTVHD, .mobileModest: .fluid
        case .appleTV4KFirst, .macIntel: .balanced
        case .appleTV4K, .macAppleSilicon, .mobile, .unknown: .quality
        }
    }

    public var title: String {
        switch self {
        case .appleTVHD: "Apple TV HD"
        case .appleTV4KFirst: "Apple TV 4K (1ʳᵉ génération)"
        case .appleTV4K: "Apple TV 4K"
        case .macAppleSilicon: "Mac à puce Apple"
        case .macIntel: "Mac Intel"
        case .mobileModest: "iPhone ou iPad (moins de 4 Go)"
        case .mobile: "iPhone ou iPad"
        case .unknown: "Appareil récent"
        }
    }
}
