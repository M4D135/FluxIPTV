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

    /// "plus de choix de pointeurs, de taille et de vitesse" (David, 27/11);
    /// what was saved before keeps its name.
    func testThePointerOffersMoreChoicesAndKeepsTheOldOnes() {
        XCTAssertEqual(FluxPointerSpeed.allCases.count, 5)
        XCTAssertEqual(FluxPointerSize.allCases.count, 6)
        XCTAssertEqual(FluxPointerShape.allCases.count, 6)
        XCTAssertEqual(FluxPointerColor.allCases.count, 6)
        XCTAssertEqual(FluxPointerAcceleration.allCases.count, 3)
        for kept in ["slow", "normal", "fast"] { XCTAssertNotNil(FluxPointerSpeed(rawValue: kept)) }
        for kept in ["small", "normal", "large"] { XCTAssertNotNil(FluxPointerSize(rawValue: kept)) }
        for kept in ["arrow", "dot"] { XCTAssertNotNil(FluxPointerShape(rawValue: kept)) }
        let gains = FluxPointerSpeed.allCases.map(\.gain)
        XCTAssertEqual(gains, gains.sorted(), "From the slowest to the fastest.")
        let heights = FluxPointerSize.allCases.map(\.height)
        XCTAssertEqual(heights, heights.sorted(), "From the smallest to the largest.")
        XCTAssertEqual(Set(FluxPointerColor.allCases.map(\.title)).count, 6)
        XCTAssertEqual(Set([FluxPointerSpeed.storageKey, FluxPointerSize.storageKey, FluxPointerShape.storageKey,
                            FluxPointerColor.storageKey, FluxPointerAcceleration.storageKey]).count, 5)
        // Without acceleration a flick goes as far as a slow move; strong, farther than gentle.
        XCTAssertEqual(FluxPointerAcceleration.none.factor(velocity: 5000), 1)
        XCTAssertGreaterThan(FluxPointerAcceleration.strong.factor(velocity: 1500), FluxPointerAcceleration.gentle.factor(velocity: 1500))
        XCTAssertLessThan(FluxPointerAcceleration.strong.factor(velocity: 0), FluxPointerAcceleration.gentle.factor(velocity: 0))
        XCTAssertLessThanOrEqual(FluxPointerAcceleration.strong.factor(velocity: 1e9), 3)
        XCTAssertEqual(FluxPointerAcceleration.gentle.factor(velocity: .infinity), 1)
        let plain = FluxPointerMotion(speed: .normal, acceleration: .none)
        XCTAssertEqual(plain.move(from: .zero, dx: 10, dy: 0, velocity: 4000).x, 10)
        XCTAssertEqual(FluxPointerMotion(speed: .veryFast, acceleration: .none).move(from: .zero, dx: 10, dy: 0, velocity: 0).x, 20)
        XCTAssertTrue(FluxPointerShape.arrow.pointsWithTip)
        XCTAssertFalse(FluxPointerShape.ring.pointsWithTip)
    }

    /// Over a list the pointer keeps its height and the list scrolls under
    /// it; it leaves by a side, or past an end the list has reached.
    func testOverAListThePointerScrollsItAndLeavesByItsSides() {
        let list = CGRect(x: 100, y: 100, width: 600, height: 800)
        let band = FluxPointerRail.band(list)
        XCTAssertEqual(band.minY, 260)
        XCTAssertEqual(band.maxY, 740)
        // Mostly up and down: only scrolls; mostly across: only moves.
        XCTAssertEqual(FluxPointerRail.split(dx: 3, dy: 40).across, 0)
        XCTAssertEqual(FluxPointerRail.split(dx: 40, dy: 3).along, 0)
        XCTAssertEqual(FluxPointerRail.split(dx: 30, dy: 30).across, 30)
        XCTAssertEqual(FluxPointerRail.split(dx: .nan, dy: 3).along, 0)

        var rail = FluxPointerRail()
        // The list scrolled: the pointer stays where it is, at its height.
        var step = rail.move(from: CGPoint(x: 300, y: 500), dx: 0, dy: 0, scrolled: true, list: list)
        XCTAssertEqual(step.point, CGPoint(x: 300, y: 500))
        XCTAssertFalse(step.leaves)
        // Coming in at the top, it is brought down into the band.
        step = rail.move(from: CGPoint(x: 300, y: 110), dx: 0, dy: 0, scrolled: true, list: list)
        XCTAssertEqual(step.point.y, 260)
        // Across, along the row, as far as the side.
        step = rail.move(from: CGPoint(x: 300, y: 500), dx: -150, dy: 0, scrolled: false, list: list)
        XCTAssertEqual(step.point.x, 150)
        step = rail.move(from: step.point, dx: -80, dy: 0, scrolled: false, list: list)
        XCTAssertEqual(step.point.x, 100, "At the side, the pointer waits.")
        XCTAssertFalse(step.leaves)
        XCTAssertEqual(rail.pullX, -30)
        // Back from the pull, the pull is undone first.
        step = rail.move(from: step.point, dx: 20, dy: 0, scrolled: false, list: list)
        XCTAssertEqual(step.point.x, 100)
        XCTAssertEqual(rail.pullX, -10)
        // Pulled on past the side: out of the list, at its height.
        step = rail.move(from: step.point, dx: -60, dy: 0, scrolled: false, list: list)
        XCTAssertTrue(step.leaves)
        XCTAssertEqual(step.point, CGPoint(x: 76, y: 500))
        XCTAssertEqual(rail, FluxPointerRail(), "Out of the list, nothing is pulled.")
        // The list has ended at the bottom: a pull takes the pointer out below.
        step = rail.move(from: CGPoint(x: 300, y: 600), dx: 0, dy: 30, scrolled: false, list: list)
        XCTAssertFalse(step.leaves)
        step = rail.move(from: step.point, dx: 0, dy: 30, scrolled: false, list: list)
        XCTAssertTrue(step.leaves)
        XCTAssertEqual(step.point, CGPoint(x: 300, y: 924))
        // A list that scrolls again stands no pull.
        _ = rail.move(from: CGPoint(x: 300, y: 600), dx: 0, dy: -40, scrolled: false, list: list)
        step = rail.move(from: CGPoint(x: 300, y: 600), dx: 0, dy: -40, scrolled: true, list: list)
        XCTAssertFalse(step.leaves)
        XCTAssertEqual(rail.pullY, -40)
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
