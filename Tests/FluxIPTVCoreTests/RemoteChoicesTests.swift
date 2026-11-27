import XCTest
@testable import FluxIPTVCore

final class RemoteChoicesTests: XCTestCase {
    private func defaults(_ name: String) -> UserDefaults {
        let suite = "flux.choices.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEachMachineGetsThePresetThatKeepsItFluid() {
        func tv(_ machine: String) -> FluxDeviceClass { .classify(machine: machine, memory: 0, platform: .tvOS) }
        XCTAssertEqual(tv("AppleTV5,3"), .appleTVHD)
        XCTAssertEqual(tv("AppleTV6,2"), .appleTV4KFirst)
        XCTAssertEqual(tv("AppleTV11,1"), .appleTV4K)
        XCTAssertEqual(tv("AppleTV14,1"), .appleTV4K)
        XCTAssertEqual(tv("iPhone15,2"), .unknown)
        XCTAssertEqual(tv(""), .unknown)
        XCTAssertEqual(FluxDeviceClass.appleTVHD.recommended, .fluid)
        XCTAssertEqual(FluxDeviceClass.appleTV4KFirst.recommended, .balanced)
        XCTAssertEqual(FluxDeviceClass.appleTV4K.recommended, .quality)
        XCTAssertEqual(FluxDeviceClass.classify(machine: "Mac14,2", memory: 0, platform: .macOS, appleSilicon: false), .macIntel)
        XCTAssertEqual(FluxDeviceClass.classify(machine: "Mac14,2", memory: 0, platform: .macOS), .macAppleSilicon)
        XCTAssertEqual(FluxDeviceClass.classify(machine: "iPhone10,1", memory: 2_000_000_000, platform: .iOS), .mobileModest)
        XCTAssertEqual(FluxDeviceClass.classify(machine: "iPad13,1", memory: 4_000_000_000, platform: .iOS), .mobile)
        XCTAssertTrue(FluxDeviceClass.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testBackLeadsToTheBarFirstAndTheOldSettingIsKept() {
        XCTAssertEqual(DeskBackBehavior.defaultValue, .bar)
        let shown = defaults("back-plan")
        shown.set(true, forKey: DeskZone.backKey)
        DeskBackBehavior.migrate(shown)
        XCTAssertEqual(shown.string(forKey: DeskBackBehavior.storageKey), DeskBackBehavior.plan.rawValue)
        XCTAssertNil(shown.object(forKey: DeskZone.backKey))
        let hidden = defaults("back-none")
        hidden.set(false, forKey: DeskZone.backKey)
        DeskBackBehavior.migrate(hidden)
        XCTAssertNil(hidden.object(forKey: DeskBackBehavior.storageKey), "Without the plan, the new default applies.")
        let chosen = defaults("back-chosen")
        chosen.set(DeskBackBehavior.leave.rawValue, forKey: DeskBackBehavior.storageKey)
        chosen.set(true, forKey: DeskZone.backKey)
        DeskBackBehavior.migrate(chosen)
        XCTAssertEqual(chosen.string(forKey: DeskBackBehavior.storageKey), DeskBackBehavior.leave.rawValue)
    }

    func testTheLoupeOfTheDockGrowsMoreAndCanBeChosen() {
        XCTAssertEqual(FluxDockZoom.defaultValue, .normal)
        XCTAssertEqual(FluxDockZoom.none.maximumScale(base: 1.42), 1)
        XCTAssertEqual(FluxDockZoom.light.maximumScale(base: 1.42), 1.42, accuracy: 0.0001)
        let scales = FluxDockZoom.allCases.map { $0.maximumScale(base: 1.42) }
        XCTAssertEqual(scales, scales.sorted(), "Each size grows more than the one before.")
        XCTAssertGreaterThan(FluxDockZoom.normal.maximumScale(base: 1.42), 1.6)
        let off = defaults("zoom-off")
        off.set(false, forKey: FluxDockItem.magnifyKey)
        FluxDockZoom.migrate(off)
        XCTAssertEqual(off.string(forKey: FluxDockZoom.storageKey), FluxDockZoom.none.rawValue)
        XCTAssertNil(off.object(forKey: FluxDockItem.magnifyKey))
        let on = defaults("zoom-on")
        on.set(true, forKey: FluxDockItem.magnifyKey)
        FluxDockZoom.migrate(on)
        XCTAssertNil(on.object(forKey: FluxDockZoom.storageKey))
    }

    func testTheDrawnPacksMakeAFamilyOfTheirOwn() {
        XCTAssertEqual(FluxDockTheme.Family.illustrated.themes, [.neon90, .nightGlass, .artDeco])
        XCTAssertFalse(FluxDockTheme.neon90.pixelated)
        XCTAssertEqual(FluxDockTheme.allCases.count, 18)
    }

    func testThePresetsSetTheEdgeOfThePanel() {
        XCTAssertEqual(FluxQualityPreset.fluid.glint, .edge)
        XCTAssertEqual(FluxQualityPreset.quality.glint, .glint)
        XCTAssertNil(FluxQualityPreset.matching(glass: true, motion: true, backdrops: true, livePreview: true, glint: .off))
    }

    func testTheRemoteGoesFromOneModeToTheOther() {
        XCTAssertEqual(FluxRemoteMode.defaultValue, .classic)
        XCTAssertEqual(FluxRemoteMode.classic.other, .pointer)
        XCTAssertEqual(FluxRemoteMode.pointer.other, .classic)
        XCTAssertTrue(FluxRemoteMode.toggleDefault)
        XCTAssertNotEqual(FluxRemoteMode.storageKey, FluxRemoteMode.toggleKey)
    }

    func testThePointerFollowsTheThumbAndStaysOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let motion = FluxPointerMotion(speed: .normal)
        let slow = motion.step(from: CGPoint(x: 960, y: 540), dx: 10, dy: 0, velocity: 0, in: screen)
        let fast = motion.step(from: CGPoint(x: 960, y: 540), dx: 10, dy: 0, velocity: 3200, in: screen)
        XCTAssertGreaterThan(fast.x - 960, slow.x - 960, "A flick goes farther than a slow move.")
        XCTAssertEqual(slow.y, 540)
        let past = motion.step(from: CGPoint(x: 1900, y: 1070), dx: 400, dy: 400, velocity: 0, in: screen)
        XCTAssertEqual(past, CGPoint(x: 1920, y: 1080))
        let quick = FluxPointerMotion(speed: .fast).step(from: .zero, dx: 10, dy: 10, velocity: 0, in: screen)
        let gentle = FluxPointerMotion(speed: .slow).step(from: .zero, dx: 10, dy: 10, velocity: 0, in: screen)
        XCTAssertGreaterThan(quick.x, gentle.x)
        XCTAssertEqual(FluxPointerMotion.acceleration(velocity: .nan), 1)
        XCTAssertLessThanOrEqual(FluxPointerMotion.acceleration(velocity: 100_000), 2)
    }

    func testThePointerRestsOnTheSmallestControlUnderIt() {
        let panel = CGRect(x: 0, y: 0, width: 800, height: 600)
        let button = CGRect(x: 100, y: 100, width: 200, height: 80)
        XCTAssertEqual(FluxPointerTarget.pick(CGPoint(x: 150, y: 120), frames: [panel, button]), 1)
        XCTAssertEqual(FluxPointerTarget.pick(CGPoint(x: 700, y: 500), frames: [panel, button]), 0)
        XCTAssertNil(FluxPointerTarget.pick(CGPoint(x: 900, y: 120), frames: [panel, button]))
        XCTAssertEqual(FluxPointerTarget.pick(CGPoint(x: 806, y: 120), frames: [panel, button], tolerance: 12), 0)
        XCTAssertNil(FluxPointerTarget.pick(CGPoint(x: 900, y: 120), frames: [.null, .zero], tolerance: 12))
    }
}
