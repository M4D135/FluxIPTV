import SwiftUI

/// The machine the app runs on, and the preset that keeps it fluid:
/// "détecte le matos pour voir qualité graphique à appliquer, dans option
/// choix qualité graphique comme dans un jeu" (David, 26/11).
enum FluxGraphics {
    static let stageKey = "fluxiptv.appearance.stage"
    /// The preset last written, so that « Automatique » applies it once per
    /// machine: what is changed afterwards, here or in the studio, stays.
    /// v2 since the 0.9.11, whose Fluide keeps the pictures behind the
    /// screens: an Apple TV HD left in « Automatique » gets them back once.
    static let appliedKey = "fluxiptv.quality.applied.v2"

    /// The model identifier, `AppleTV5,3` or `Mac14,2`; a simulator names
    /// the one it stands for.
    static let machine: String = {
        var system = utsname()
        uname(&system)
        let raw = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        return raw
    }()

    static let device: FluxDeviceClass = {
        #if os(tvOS)
        let platform = FluxDeviceClass.Platform.tvOS
        #elseif os(macOS)
        let platform = FluxDeviceClass.Platform.macOS
        #else
        let platform = FluxDeviceClass.Platform.iOS
        #endif
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        return FluxDeviceClass.classify(machine: machine, memory: ProcessInfo.processInfo.physicalMemory,
                                        platform: platform, appleSilicon: silicon)
    }()

    /// At launch, with « Automatique », the preset of this machine, once. The
    /// 0.9.3 had no such choice: what it turned off was chosen, and stays.
    static func applyAutomatic(_ defaults: UserDefaults = .standard) {
        if defaults.object(forKey: FluxQualityPreset.automaticKey) == nil {
            let chosen = [FluxAppearance.glassKey, FluxAppearance.motionKey, LiveTVPreviewDelay.automaticKey]
                .contains { defaults.object(forKey: $0) != nil && !defaults.bool(forKey: $0) }
                || defaults.string(forKey: stageKey) == ProceduralCinema.Style.off.rawValue
            defaults.set(!chosen, forKey: FluxQualityPreset.automaticKey)
        }
        if defaults.object(forKey: FluxPanelGlint.storageKey) == nil {
            // Settings kept from the 0.9.3 get the glint of their motion.
            let moving = defaults.object(forKey: FluxAppearance.motionKey) == nil
                ? FluxAppearance.motionDefault : defaults.bool(forKey: FluxAppearance.motionKey)
            defaults.set((moving ? FluxPanelGlint.glint : .edge).rawValue, forKey: FluxPanelGlint.storageKey)
        }
        let recommended = device.recommended
        guard defaults.bool(forKey: FluxQualityPreset.automaticKey),
              defaults.string(forKey: appliedKey) != recommended.rawValue else { return }
        apply(recommended, defaults)
    }

    /// Writes what a preset sets; a picture shown stays the one chosen.
    static func apply(_ preset: FluxQualityPreset, _ defaults: UserDefaults = .standard) {
        defaults.set(preset.glass, forKey: FluxAppearance.glassKey)
        defaults.set(preset.motion, forKey: FluxAppearance.motionKey)
        // The pictures behind the screens: those turned off come back with
        // a preset that shows them, as every preset does since the 0.9.11.
        let stage = defaults.string(forKey: stageKey).flatMap(ProceduralCinema.Style.init(rawValue:)) ?? .orbit
        let shown: ProceduralCinema.Style = preset.backdrops ? (stage == .off ? .orbit : stage) : .off
        defaults.set(shown.rawValue, forKey: stageKey)
        defaults.set(preset.livePreview, forKey: LiveTVPreviewDelay.automaticKey)
        defaults.set(preset.glint.rawValue, forKey: FluxPanelGlint.storageKey)
        defaults.set(preset.rawValue, forKey: appliedKey)
    }
}
