import XCTest
@testable import FluxIPTVCore

final class SpaceAppearanceTests: XCTestCase {
    func testTheScreenInFrontIsTheOneWhoseLookIsShown() {
        XCTAssertEqual(FluxSpace.current(home: true, settings: false, searching: true, kind: .movie), .home)
        XCTAssertEqual(FluxSpace.current(home: false, settings: true, searching: true, kind: .movie), .settings)
        XCTAssertEqual(FluxSpace.current(home: false, settings: false, searching: true, kind: .movie), .search)
        XCTAssertEqual(FluxSpace.current(home: false, settings: false, searching: false, kind: .live), .live)
        XCTAssertEqual(FluxSpace.current(home: false, settings: false, searching: false, kind: .series), .series)
        XCTAssertEqual(Set(FluxSpace.allCases.map(\.title)).count, FluxSpace.allCases.count)
    }

    func testAScreenKeepsItsOwnDockThemeAndTheOthersFollowAllScreens() {
        let stored = FluxDockThemeChoices.stored([.home: .phosphor, .live: .gel])
        XCTAssertEqual(stored, "home=phosphor,live=gel")
        XCTAssertEqual(FluxDockThemeChoices.theme(for: .home, all: .glass, stored: stored), .phosphor)
        XCTAssertEqual(FluxDockThemeChoices.theme(for: .live, all: .glass, stored: stored), .gel)
        XCTAssertEqual(FluxDockThemeChoices.theme(for: .movie, all: .neon, stored: stored), .neon)
        // What a later version saved, or a typing slip, is dropped.
        XCTAssertEqual(FluxDockThemeChoices.parse("home=phosphor, live = gel ,moon=glass,movie=chrome,=,x"), [.home: .phosphor, .live: .gel])
        let back = FluxDockThemeChoices.setting(nil, for: .home, in: stored)
        XCTAssertEqual(back, "live=gel")
        XCTAssertEqual(FluxDockThemeChoices.setting(.bevel, for: .search, in: back), "live=gel,search=bevel")
    }

    func testEveryDockThemeHasAFamilyANameAndAWordOfItsOwn() {
        XCTAssertEqual(Set(FluxDockTheme.allCases.map(\.title)).count, FluxDockTheme.allCases.count)
        XCTAssertEqual(FluxDockTheme.Family.allCases.flatMap(\.themes), FluxDockTheme.allCases)
        XCTAssertEqual(FluxDockTheme.Family.retro.themes, [.bevel, .eightColor, .fourColor, .greenDesk, .phosphor])
        XCTAssertTrue(FluxDockTheme.allCases.allSatisfy { !$0.subtitle.isEmpty })
        XCTAssertTrue(FluxDockTheme.phosphor.pixelated)
        XCTAssertFalse(FluxDockTheme.gel.pixelated)
    }

    func testEveryPictureIsFoundAgainFromWhatIsSaved() {
        XCTAssertEqual(FluxBackdropLibrary.all.count, FluxBackdropLibrary.art.count)
        for picture in FluxBackdropLibrary.all {
            XCTAssertEqual(FluxBackdropPicture(id: picture.id), picture)
            XCTAssertFalse(picture.title.isEmpty)
        }
        // The rooms of the 0.9.2 are gone: what was saved of them reads as nothing.
        XCTAssertNil(FluxBackdropPicture(id: "room:cinema-zen"))
        XCTAssertNil(FluxBackdropPicture(id: "art:not-shipped"))
        XCTAssertNil(FluxBackdropPicture(id: "cinema-zen"))
        // Each screen but the home screen has pictures of its own; the home
        // screen shows those of the screen of what it holds.
        for space in FluxSpace.allCases {
            XCTAssertEqual(FluxBackdropLibrary.pictures(for: space).isEmpty, space == .home, space.rawValue)
            XCTAssertFalse(FluxBackdropLibrary.pictures(for: space, holding: .series).isEmpty, space.rawValue)
        }
        XCTAssertEqual(FluxBackdropLibrary.pictures(for: .home, holding: .series), FluxBackdropLibrary.pictures(for: .series))
        XCTAssertEqual(FluxBackdropLibrary.pictures(for: .home, holding: .live).map(\.id), ["art:tv-1", "art:tv-2", "art:tv-3"])
        XCTAssertEqual(FluxBackdropLibrary.pictures(for: .search, holding: .live).map(\.id), ["art:recherche-1", "art:recherche-2", "art:recherche-3"])
        // Three more were drawn for the boutique, which no screen shows by itself.
        XCTAssertEqual(FluxBackdropLibrary.boutique.map(\.id), ["art:store-1", "art:store-2", "art:store-3"])
        XCTAssertEqual(FluxBackdropLibrary.art.first { $0.name == "store-2" }?.section, "Boutique")
        XCTAssertEqual(FluxBackdropLibrary.art.first { $0.name == "films-2" }?.section, "Films")
        // Neither the entrance hall nor the video store: David, 26/11.
        XCTAssertNil(FluxBackdropPicture(id: "art:films-3"))
        XCTAssertNil(FluxBackdropPicture(id: "art:series-1"))
        XCTAssertEqual(FluxBackdropPicture.art("tv-2").resource.folder, "Backdrops")
        XCTAssertEqual(FluxBackdropPicture.art("tv-2").title, "Loft panoramique")
        XCTAssertEqual(Set(FluxBackdropLibrary.art.map(\.name)).count, FluxBackdropLibrary.art.count)
    }

    /// Every picture the library names is shipped with the app.
    func testEveryDrawnPictureIsInTheBackdropsFolder() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("FluxIPTVMac/Backdrops")
        for art in FluxBackdropLibrary.art {
            let file = folder.appendingPathComponent(art.name + ".jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent)
        }
        let shipped = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".jpg") }
        XCTAssertEqual(Set(shipped), Set(FluxBackdropLibrary.art.map { $0.name + ".jpg" }), "a picture of the folder that no screen offers")
    }

    func testPicturesAreChosenAndPutInOrder() {
        var plan = FluxBackdropPlan(mode: .pictures)
        let a = FluxBackdropPicture.art("films-2"), b = FluxBackdropPicture.art("tv-1"), c = FluxBackdropPicture.art("series-3")
        plan.toggle(a); plan.toggle(b); plan.toggle(c)
        XCTAssertEqual(plan.shown, [a, b, c])
        plan.move(at: 2, by: -1)
        XCTAssertEqual(plan.shown, [a, c, b])
        plan.move(at: 0, by: -1)
        XCTAssertEqual(plan.shown, [a, c, b], "the first stays first")
        plan.move(at: 0, by: 5)
        XCTAssertEqual(plan.shown, [c, b, a], "a move beyond the end stops at it")
        plan.toggle(b)
        XCTAssertEqual(plan.shown, [c, a])
        XCTAssertTrue(plan.contains(a)); XCTAssertFalse(plan.contains(b))
        // A picture that is no longer shipped is left out.
        plan.pictures.insert("room:cinema-zen", at: 0)
        XCTAssertEqual(plan.shown, [c, a])
        // The automatic pictures and the plain colour show no chosen picture.
        plan.mode = .automatic
        XCTAssertEqual(plan.shown, [])
    }

    func testTheSlideshowFollowsTheClock() {
        let plan = FluxBackdropPlan(mode: .pictures, interval: .seconds30, order: .listed)
        XCTAssertEqual(plan.slot(at: 0, count: 3).current, 0)
        XCTAssertEqual(plan.slot(at: 29.9, count: 3).current, 0)
        XCTAssertEqual(plan.slot(at: 30, count: 3).current, 1)
        XCTAssertEqual(plan.slot(at: 95, count: 3).current, 0)
        XCTAssertEqual(plan.slot(at: 95, count: 3).next, 1)
        XCTAssertEqual(plan.slot(at: 95, count: 3).change, 120)
        // One picture, or none, never changes.
        XCTAssertEqual(plan.slot(at: 95, count: 1).change, .infinity)
        XCTAssertEqual(plan.slot(at: 95, count: 0).current, 0)
        XCTAssertEqual(plan.slot(at: -10, count: 3).current, 2, "a clock before the reference date still counts")
    }

    func testAShuffledSlideshowShowsEveryPictureOnceARoundWithoutRepeatingOne() {
        let plan = FluxBackdropPlan(mode: .pictures, interval: .seconds15, order: .shuffled)
        let count = 5
        var previous: Int?
        for round in 0..<40 {
            var seen: Set<Int> = []
            for step in 0..<count {
                let time = Double((round * count + step) * 15) + 1
                let slot = plan.slot(at: time, count: count)
                seen.insert(slot.current)
                if let previous { XCTAssertNotEqual(slot.current, previous, "round \(round), step \(step)") }
                previous = slot.current
                XCTAssertEqual(slot.next, plan.slot(at: time + 15, count: count).current)
            }
            XCTAssertEqual(seen, Set(0..<count), "round \(round)")
        }
        // Not the order of the list in every round.
        let firsts = Set((0..<12).map { plan.slot(at: Double($0 * count * 15) + 1, count: count).current })
        XCTAssertGreaterThan(firsts.count, 1)
    }

    func testAllScreensShareOnePlanAndAScreenMayKeepItsOwn() {
        var choices = FluxBackdropChoices()
        XCTAssertEqual(choices.plan(for: .home), .automatic)
        let pictures = FluxBackdropPlan(mode: .pictures, pictures: ["art:films-1", "art:series-2"], interval: .minutes5, order: .shuffled)
        choices.set(pictures, for: nil)
        XCTAssertEqual(choices.plan(for: .search), pictures)
        choices.set(FluxBackdropPlan(mode: .plain), for: .settings)
        XCTAssertEqual(choices.plan(for: .settings).mode, .plain)
        XCTAssertTrue(choices.keepsOwn(.settings)); XCTAssertFalse(choices.keepsOwn(.home))
        // A plan for all screens leaves those that keep their own alone.
        choices.set(.automatic, for: nil)
        XCTAssertEqual(choices.plan(for: .settings).mode, .plain)
        XCTAssertEqual(choices.plan(for: .home), .automatic)
        choices.follow(.settings)
        XCTAssertEqual(choices.plan(for: .settings), .automatic)
        choices.set(pictures, for: .live); choices.set(pictures, for: .movie)
        XCTAssertTrue(choices.anyOwn)
        choices.sameEverywhere()
        XCTAssertFalse(choices.anyOwn)
    }

    func testWhatIsSavedComesBackAndAnOlderSaveStillReads() {
        var choices = FluxBackdropChoices()
        choices.set(FluxBackdropPlan(mode: .pictures, pictures: ["art:reglages-3"], interval: .seconds15, order: .shuffled, transition: .cut), for: .home)
        let stored = choices.stored
        XCTAssertEqual(FluxBackdropChoices(stored: stored), choices)
        XCTAssertEqual(FluxBackdropChoices(stored: ""), FluxBackdropChoices())
        XCTAssertEqual(FluxBackdropChoices(stored: "{broken"), FluxBackdropChoices())
        // A plan saved before the transitions existed takes the fade.
        let older = #"{"all":{"mode":"plain"},"own":{"home":{"mode":"pictures","pictures":["room:cinema-zen"],"interval":300}}}"#
        let read = FluxBackdropChoices(stored: older)
        XCTAssertEqual(read.all.mode, .plain)
        XCTAssertEqual(read.plan(for: .home).interval, .minutes5)
        XCTAssertEqual(read.plan(for: .home).transition, .fade)
        XCTAssertEqual(read.plan(for: .home).order, .listed)
    }

    func testThePresetsGoFromTheLightestToTheRichest() {
        XCTAssertEqual(FluxQualityPreset.matching(glass: false, motion: false, backdrops: false, livePreview: false), .fluid)
        XCTAssertEqual(FluxQualityPreset.matching(glass: true, motion: false, backdrops: true, livePreview: true), .balanced)
        XCTAssertEqual(FluxQualityPreset.matching(glass: true, motion: true, backdrops: true, livePreview: true), .quality)
        XCTAssertNil(FluxQualityPreset.matching(glass: false, motion: true, backdrops: true, livePreview: true))
        // The settings of a new install are the richest preset.
        XCTAssertTrue(FluxQualityPreset.quality.glass && FluxQualityPreset.quality.motion && FluxQualityPreset.quality.backdrops)
    }
}
