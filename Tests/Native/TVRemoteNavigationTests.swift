import XCTest

/// These tests only observe accessibility state. Every navigation/activation
/// comes from XCUIRemote, through the real tvOS focus engine and production UI.
final class TVRemoteNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCountryChangeReopenAndMenuPreservesSelection() {
        let app = launch("live-fr")
        defer { app.terminate() }
        let firstFrance = element("live-channel-fixture-country-fr-0", in: app)
        let countries = element("navigation-countries", in: app)
        let france = element("live-country-option-FR", in: app)
        let spain = element("live-country-option-ES", in: app)
        assertFocus(firstFrance, logical: "fixture-country-fr-0", in: app)

        // The navigation column is one press to the left of the list.
        XCUIRemote.shared.press(.left)
        assertCondition("hasFocus == false", on: firstFrance, in: app)
        move(.up, to: countries, maximumPresses: 8, in: app)
        assertFocus(countries, logical: "countries", in: app)
        XCUIRemote.shared.press(.select)
        // The countries are listed in the column itself, on the one in use.
        assertFocus(france, logical: "country-FR", in: app)
        XCTAssertTrue((france.value as? String ?? "").contains("sélectionné"))
        retainScreenshot("country-01-column-france-focused", in: app)

        XCUIRemote.shared.press(.up)
        assertFocus(spain, logical: "country-ES", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: spain, in: app)
        assertSpanishResults(in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("country-02-spain-results", in: app)
        print("PASS: TV_REMOTE country FR -> ES through Up and Select")

        XCUIRemote.shared.press(.select)
        assertFocus(spain, logical: "country-ES", in: app)
        XCTAssertTrue((spain.value as? String ?? "").contains("sélectionné"))
        XCTAssertFalse((france.value as? String ?? "").contains("sélectionné"))
        retainScreenshot("country-03-reopened-spain-focused", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(france, logical: "country-FR", in: app)
        // Moving the highlight is not selecting a country. Menu must cancel.
        retainScreenshot("country-04-france-highlight-before-menu", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: france, in: app)
        assertSpanishResults(in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("country-05-menu-preserved-spain", in: app)
        print("PASS: TV_REMOTE reopened ES, moved to FR, Menu preserved ES and returned focus to Pays")

        // Menu shows the compass of the zones; Down jumps into the dock.
        let compass = element("zone-compass", in: app)
        let liveTab = element("navigation-tab-live", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        retainScreenshot("country-06-compass", in: app)
        XCUIRemote.shared.press(.down)
        assertCondition("exists == false", on: compass, in: app)
        assertFocus(liveTab, logical: "tab-live", in: app)
        // From the dock, Menu returns to the home screen, which is the first
        // one: the next Menu belongs to tvOS.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(element("desk-home-screen", in: app).waitForExistence(timeout: 10))
        assertFocus(liveTab, logical: "tab-live", in: app)
        retainScreenshot("country-07-home", in: app)
        XCUIRemote.shared.press(.menu)
        // A crash/termination is not evidence that tvOS received Menu.
        assertCondition(NSPredicate(format: "state == %lu OR state == %lu",
                                    XCUIApplication.State.runningBackground.rawValue,
                                    XCUIApplication.State.runningBackgroundSuspended.rawValue),
                        on: app, in: app)
        print("PASS: TV_REMOTE Menu showed the compass, Down reached the dock, Menu the home screen, then Menu backgrounded the app")
    }

    @MainActor
    func testRestoredChannelCanLoseAndRegainRemoteFocus() {
        let app = launch("live-restored")
        defer { app.terminate() }
        let channel = element("live-channel-fixture-country-fr-1", in: app)
        let countries = element("navigation-countries", in: app)
        assertFocus(channel, logical: "fixture-country-fr-1", in: app)
        retainScreenshot("restored-01-remembered-channel", in: app)

        XCUIRemote.shared.press(.left)
        assertCondition("hasFocus == false", on: channel, in: app)
        move(.up, to: countries, maximumPresses: 8, in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("restored-02-focus-away-on-pays", in: app)
        // The list is on the right of the column, under the search field.
        XCUIRemote.shared.press(.right)
        move(.down, to: channel, maximumPresses: 4, in: app)
        assertFocus(channel, logical: "fixture-country-fr-1", in: app)
        XCTAssertEqual(countries.label, "Pays : France · FR")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Grand écran")).firstMatch.exists)
        XCTAssertFalse(element("live-channel-fixture-country-fr-0", in: app).exists)
        retainScreenshot("restored-03-returned-to-remembered-channel", in: app)
        print("PASS: TV_REMOTE saved FR/Grand écran channel released native focus and accepted reentry from the column")
    }

    @MainActor
    func testFailedSourceReconnectHighlightFollowsRemoteFocus() {
        let app = launch("live-error")
        defer { app.terminate() }
        let countries = element("navigation-countries", in: app)
        let reconnect = element("navigation-reconnect-source", in: app)
        assertFocus(countries, logical: "countries", in: app)
        XCTAssertTrue(reconnect.waitForExistence(timeout: 10))

        // The button stands on the right of the column, under the search field.
        XCUIRemote.shared.press(.right)
        move(.down, to: reconnect, maximumPresses: 4, in: app)
        assertFocus(reconnect, logical: "reconnect-source", in: app)
        retainScreenshot("error-01-reconnect-native-and-logical-focus", in: app)
        XCUIRemote.shared.press(.left)
        assertCondition("hasFocus == false", on: reconnect, in: app)
        retainScreenshot("error-02-reconnect-highlight-released", in: app)
        move(.right, to: reconnect, maximumPresses: 3, in: app)
        assertFocus(reconnect, logical: "reconnect-source", in: app)
        retainScreenshot("error-03-reconnect-highlight-restored", in: app)
        print("PASS: TV_REMOTE failed source reconnect highlight followed the remote from the column, away and back, without a loaded catalogue")
    }

    @MainActor
    func testZonesCompassReachesEveryZoneWithOneArrow() {
        let app = launch("live")
        defer { app.terminate() }
        // A simulator that has just been created shows a system tip that
        // takes the first Menu. This test runs after the others, and waits.
        sleep(3)
        let channel = element("live-channel-fixture-live-0", in: app)
        let compass = element("zone-compass", in: app)
        // The glass around the field carries its identifier, and tvOS 26 also
        // gives it to the icon beside the field: ask for the field itself.
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        let logical = element("flux-catalog-logical-focus", in: app)
        assertFocus(channel, logical: "fixture-live-0", in: app)

        // Up: the search field, which no arrow reaches from the foot of a long list.
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        retainScreenshot("compass-01-from-the-list", in: app)
        XCUIRemote.shared.press(.up)
        assertCondition("exists == false", on: compass, in: app)
        assertCondition("hasFocus == true", on: search, in: app)
        retainScreenshot("compass-02-search-field", in: app)

        // Down from the top: back in the list, on the channel that was selected.
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(channel, logical: "fixture-live-0", in: app)

        // Left: the navigation column, on the scope in use.
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        XCUIRemote.shared.press(.left)
        assertCondition("exists == false", on: compass, in: app)
        assertCondition(NSPredicate(format: "value == %@", "group-all"), on: logical, in: app)
        retainScreenshot("compass-03-column", in: app)

        // OK keeps the selection where it was.
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: compass, in: app)
        assertCondition(NSPredicate(format: "value == %@", "group-all"), on: logical, in: app)

        // Down: the dock, then its neighbours with the arrows.
        XCUIRemote.shared.press(.menu)
        assertFocus(compass, logical: "zone-compass", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(element("navigation-tab-live", in: app), logical: "tab-live", in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(element("navigation-tab-movie", in: app), logical: "tab-movie", in: app)
        XCUIRemote.shared.press(.left)
        XCUIRemote.shared.press(.left)
        assertFocus(element("desk-back", in: app), logical: "desk-back", in: app)
        retainScreenshot("compass-04-dock-and-back", in: app)
        print("PASS: TV_REMOTE Menu then one arrow reached the search field, the list, the column and the dock; OK kept the selection; the arrows walked the bar to Back")
    }

    @MainActor
    func testFilmFicheHoldsTheRemoteAndGivesItBack() {
        let app = launch("movies")
        defer { app.terminate() }
        let card = element("catalog-card-fixture-movie-1", in: app)
        let play = element("media-detail-play", in: app)
        let favorite = element("media-detail-favorite", in: app)
        let description = element("media-detail-description", in: app)
        let close = element("media-detail-back", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)

        // OK opens the glass fiche over the catalogue, on its play control.
        XCUIRemote.shared.press(.select)
        assertFocus(play, in: app)
        XCTAssertTrue(element("navigation-tab-movie", in: app).exists, "The dock stays under the fiche.")
        retainScreenshot("fiche-01-film", in: app)

        // The actions are one row, and its ends hold the remote.
        XCUIRemote.shared.press(.right)
        assertFocus(favorite, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(description, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(description, in: app)
        // Nothing under the fiche takes the remote: neither the dock nor the catalogue.
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        assertFocus(description, in: app)
        // Up reaches the close button, at the far end of the sheet.
        move(.left, to: play, maximumPresses: 3, in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(close, in: app)
        XCUIRemote.shared.press(.down)
        assertOneHasFocus([play, favorite, description], in: app)
        retainScreenshot("fiche-02-back-in-the-actions", in: app)

        // Favourites are a panel above the fiche, opened on the first list.
        move(.left, to: play, maximumPresses: 3, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(favorite, in: app)
        XCUIRemote.shared.press(.select)
        let firstList = element("favorite-list-0", in: app)
        let create = element("favorite-create", in: app)
        let save = element("favorite-save", in: app)
        assertFocus(firstList, in: app)
        retainScreenshot("fiche-03-lists", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(create, in: app)
        // Menu closes the panel without saving, back on the control it came from.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: firstList, in: app)
        assertFocus(favorite, in: app)
        XCTAssertEqual(favorite.label, "Favoris")

        // Choosing the list and saving marks the title, and returns as well.
        XCUIRemote.shared.press(.select)
        assertFocus(firstList, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value == %@", "Sélectionnée"), on: firstList, in: app)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.down)
        move(.right, to: save, maximumPresses: 3, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: firstList, in: app)
        assertFocus(favorite, in: app)
        assertCondition(NSPredicate(format: "label == %@", "Dans les favoris"), on: favorite, in: app)
        retainScreenshot("fiche-04-saved", in: app)

        // The full description is a panel of its own; Menu returns to the fiche.
        XCUIRemote.shared.press(.right)
        assertFocus(description, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(element("media-detail-description-back", in: app), in: app)
        retainScreenshot("fiche-05-description", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(description, in: app)

        // Menu closes the fiche and the sleeve takes the remote back.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        print("PASS: TV_REMOTE film fiche kept the remote in its sheet, reached Close, opened and closed the lists and the description, saved a favourite and returned to its sleeve")
    }

    @MainActor
    func testSeriesFicheColumnsOpenOnWhatIsSelected() {
        let app = launch("series")
        defer { app.terminate() }
        let play = element("media-detail-play", in: app)
        let episode15 = element("media-detail-episode-fixture-series-s12-e15", in: app)
        let episode14 = element("media-detail-episode-fixture-series-s12-e14", in: app)
        let season12 = element("media-detail-season-12", in: app)
        let season11 = element("media-detail-season-11", in: app)
        assertFocus(play, in: app)
        retainScreenshot("series-01-fiche", in: app)

        // Left: the episodes, on the selected one rather than on the nearest row.
        XCUIRemote.shared.press(.left)
        assertFocus(episode15, in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(episode14, in: app)
        assertCondition(NSPredicate(format: "label CONTAINS %@", "E14"), on: play, in: app)

        // Left again: the seasons, on the one in use. Entering changes nothing.
        XCUIRemote.shared.press(.left)
        assertFocus(season12, in: app)
        XCTAssertTrue(episode14.exists)
        // Up: the season before, whose episodes replace the list at once.
        XCUIRemote.shared.press(.up)
        assertFocus(season11, in: app)
        let firstOfEleven = element("media-detail-episode-fixture-series-s11-e1", in: app)
        XCTAssertTrue(firstOfEleven.waitForExistence(timeout: 10))
        retainScreenshot("series-02-season-11", in: app)

        // Right: its first episode; right again: the actions of that episode.
        XCUIRemote.shared.press(.right)
        assertFocus(firstOfEleven, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(play, in: app)
        assertCondition(NSPredicate(format: "label CONTAINS %@", "S11"), on: play, in: app)

        // Menu: the shelf of the seasons, on the season that was open.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(element("season-sleeve-11", in: app), logical: "season-11", in: app)
        retainScreenshot("series-03-shelf", in: app)
        print("PASS: TV_REMOTE series fiche entered its episodes and its seasons on the selected row, followed the season under the remote and returned to that season on the shelf")
    }

    @MainActor
    private func assertOneHasFocus(_ controls: [XCUIElement], in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if controls.contains(where: { $0.exists && $0.hasFocus }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        retainScreenshot("failure-none-focused", in: app)
        XCTFail("None of \(controls.map(\.identifier)) has the focus.", file: file, line: line)
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.m4d135.FluxIPTV.TVCatalogUISmoke")
        app.launchEnvironment["FLUX_UI_SCENARIO"] = scenario
        app.launchEnvironment["FLUX_UI_REMOTE_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(element("flux-catalog-logical-focus", in: app).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func assertFocus(_ control: XCUIElement, logical: String? = nil, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 10), file: file, line: line)
        assertCondition("hasFocus == true", on: control, in: app, file: file, line: line)
        if let logical {
            assertCondition(NSPredicate(format: "value == %@", logical),
                            on: element("flux-catalog-logical-focus", in: app), in: app, file: file, line: line)
        }
        print("TV_REMOTE focus: \(control.identifier), native=\(control.hasFocus), logical=\(logical ?? "picker-local"), frame=\(control.frame)")
    }

    @MainActor
    private func assertCondition(_ format: String, on control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        assertCondition(NSPredicate(format: format), on: control, in: app, file: file, line: line)
    }

    @MainActor
    private func assertCondition(_ predicate: NSPredicate, on control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: control)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            retainScreenshot("failure-\(control.identifier)", in: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "failed-remote-navigation-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertEqual(result, .completed, "\(control.identifier): \(predicate.predicateFormat)", file: file, line: line)
    }

    @MainActor
    private func move(_ direction: XCUIRemote.Button, to target: XCUIElement, maximumPresses: Int,
                      in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Each press synchronizes with XCTest's UI idleness. A bounded row walk
        // tolerates the native engine landing on either neighbour above a tile.
        for _ in 0..<maximumPresses {
            if target.exists && target.hasFocus { return }
            XCUIRemote.shared.press(direction)
        }
        assertFocus(target, in: app, file: file, line: line)
    }

    @MainActor
    private func assertSpanishResults(in app: XCUIApplication) {
        assertCondition(NSPredicate(format: "label == %@", "Pays : Espagne · ES"),
                        on: element("navigation-countries", in: app), in: app)
        for index in 0..<2 {
            XCTAssertTrue(element("live-channel-fixture-country-es-\(index)", in: app).waitForExistence(timeout: 10))
        }
        for index in 0..<3 {
            assertCondition("exists == false", on: element("live-channel-fixture-country-fr-\(index)", in: app), in: app)
        }
    }

    @MainActor
    private func retainScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
