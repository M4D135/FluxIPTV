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

    func testTheFocusedControlIsKnownByWhereItStands() {
        let row = CGRect(x: 100, y: 100, width: 600, height: 60)
        // Focused, a row grows a little: still the same row.
        XCTAssertTrue(FluxPointerTarget.same(row.insetBy(dx: -15, dy: -3), row))
        // A list shows only the top of the row; it has the focus whole.
        XCTAssertTrue(FluxPointerTarget.same(row, CGRect(x: 100, y: 100, width: 600, height: 26)))
        // The row below, the panel around, a button inside: not the row.
        XCTAssertFalse(FluxPointerTarget.same(row.offsetBy(dx: 0, dy: 66), row))
        XCTAssertFalse(FluxPointerTarget.same(CGRect(x: 0, y: 0, width: 1200, height: 800), row))
        XCTAssertFalse(FluxPointerTarget.same(CGRect(x: 110, y: 110, width: 80, height: 40), row))
        XCTAssertFalse(FluxPointerTarget.same(.null, row))
    }

    /// "pointeur aussi dans les Réglages" (David, 27/11): a page of the
    /// settings goes on below the screen, and the pointer pushes it.
    func testThePointerPushesAPageThatGoesOnBeyondItsEdge() {
        let page = CGRect(x: 0, y: 100, width: 800, height: 400)
        let bottom = 500 - FluxPointerScroll.margin, top = 100 + FluxPointerScroll.margin
        // Pushed down past the bottom: it stays at the edge, the page scrolls by the rest.
        var push = FluxPointerScroll.push(from: CGPoint(x: 300, y: 450), to: CGPoint(x: 320, y: 530), page: page, above: 0, below: 1000)
        XCTAssertEqual(push.point, CGPoint(x: 320, y: bottom))
        XCTAssertEqual(push.scroll, 530 - bottom)
        // Pushed again from the edge: the whole way goes to the page.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: bottom), to: CGPoint(x: 300, y: bottom + 20), page: page, above: 40, below: 1000)
        XCTAssertEqual(push.point.y, bottom)
        XCTAssertEqual(push.scroll, 20)
        // The end of the page comes: the pointer goes on with what is left.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: bottom), to: CGPoint(x: 300, y: bottom + 20), page: page, above: 40, below: 5)
        XCTAssertEqual(push.point.y, bottom + 15)
        XCTAssertEqual(push.scroll, 5)
        // At the end, out of the page, toward the bar below.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: bottom), to: CGPoint(x: 300, y: 560), page: page, above: 40, below: 0)
        XCTAssertEqual(push.point.y, 560)
        XCTAssertEqual(push.scroll, 0)
        // Up against the top: the page goes back up.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: 130), to: CGPoint(x: 300, y: 80), page: page, above: 40, below: 0)
        XCTAssertEqual(push.point.y, top)
        XCTAssertEqual(push.scroll, -(top - 80))
        // Inside the page, away from its edges: only the pointer moves.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 300, y: 350), page: page, above: 40, below: 1000)
        XCTAssertEqual(push.point.y, 350)
        XCTAssertEqual(push.scroll, 0)
        // From the bar below, the pointer enters the page freely.
        push = FluxPointerScroll.push(from: CGPoint(x: 300, y: 560), to: CGPoint(x: 300, y: 480), page: page, above: 40, below: 1000)
        XCTAssertEqual(push.point.y, 480)
        XCTAssertEqual(push.scroll, 0)
        // The way of the thumb, kept on the screen or not.
        let motion = FluxPointerMotion(speed: .normal)
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let far = motion.move(from: CGPoint(x: 960, y: 1070), dx: 0, dy: 400, velocity: 0)
        XCTAssertGreaterThan(far.y, 1080)
        XCTAssertEqual(motion.step(from: CGPoint(x: 960, y: 1070), dx: 0, dy: 400, velocity: 0, in: screen), FluxPointerMotion.clamp(far, to: screen))
    }
}
