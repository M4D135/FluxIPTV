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

        // Menu goes back at once: this screen was the first, the home screen
        // is behind it, and the next Menu belongs to tvOS.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(element("desk-home-screen", in: app).waitForExistence(timeout: 10))
        assertFocus(element("navigation-tab-live", in: app), logical: "tab-live", in: app)
        retainScreenshot("country-06-home", in: app)
        XCUIRemote.shared.press(.menu)
        // A crash/termination is not evidence that tvOS received Menu.
        assertCondition(NSPredicate(format: "state == %lu OR state == %lu",
                                    XCUIApplication.State.runningBackground.rawValue,
                                    XCUIApplication.State.runningBackgroundSuspended.rawValue),
                        on: app, in: app)
        print("PASS: TV_REMOTE Menu returned to the home screen at once, then Menu backgrounded the app")
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
        // The query that 0.9.6 saved with the section is not shown again.
        XCTAssertFalse(app.textFields.matching(NSPredicate(format: "value == %@", "Grand écran")).firstMatch.exists,
                       "A section keeps no query.")
        XCTAssertFalse(element("search-kind-live", in: app).exists, "The section is not the screen of the search.")
        XCTAssertFalse(element("live-channel-fixture-country-fr-0", in: app).exists)
        retainScreenshot("restored-03-returned-to-remembered-channel", in: app)
        print("PASS: TV_REMOTE saved FR/[FR] Cinéma channel released native focus and accepted reentry from the column; the query saved with it by 0.9.6 stayed out")
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
    func testArrowsAloneReachEveryZoneOfTheScreen() {
        let app = launch("live")
        defer { app.terminate() }
        let channel = element("live-channel-fixture-live-0", in: app)
        // The glass around the field carries its identifier, and tvOS 26 also
        // gives it to the icon beside the field: ask for the field itself.
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        let logical = element("flux-catalog-logical-focus", in: app)
        let dock = Self.dockKeys.map { element($0, in: app) }
        assertFocus(channel, logical: "fixture-live-0", in: app)

        // Up: the search field, above the list.
        XCUIRemote.shared.press(.up)
        assertCondition("hasFocus == true", on: search, in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        // Left: the navigation column. Right twice: the list, then the
        // actions beside the preview.
        XCUIRemote.shared.press(.left)
        assertCondition("hasFocus == false", on: channel, in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH %@ OR value == %@", "group-", "countries"), on: logical, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        // From a channel further down, the column is still entered on the
        // row of what is shown, not on the one that faces that channel, and
        // it is left for the channel the remote came from.
        let fourth = element("live-channel-fixture-live-3", in: app)
        move(.down, to: fourth, maximumPresses: 4, in: app)
        assertFocus(fourth, logical: "fixture-live-3", in: app)
        XCUIRemote.shared.press(.left)
        assertCondition(NSPredicate(format: "value == %@", "group-all"), on: logical, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(fourth, logical: "fixture-live-3", in: app)
        // The preview belongs to the channel the remote rests on, and stays
        // with it beside its picture, on Regarder and on Favoris: "pourquoi
        // l'apercu disparait si on va dans la zone" (David, 27/11). The
        // channels of the bench have no stream: whatever state their preview
        // is in, a stopped one belongs to no channel.
        let preview = element("flux-live-preview-state", in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH %@", "fixture-live-3 "), on: preview, in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(element("live-watch", in: app), in: app)
        assertPreviewStays(preview, with: "fixture-live-3", on: "Regarder")
        XCUIRemote.shared.press(.right)
        assertFocus(element("navigation-live-favorite", in: app), in: app)
        assertPreviewStays(preview, with: "fixture-live-3", on: "Favoris")
        XCUIRemote.shared.press(.left)
        assertFocus(element("live-watch", in: app), in: app)
        retainScreenshot("zones-01-actions", in: app)
        // Down from the actions: the dock, whose keys the arrows then walk
        // down to Back, on its left.
        XCUIRemote.shared.press(.down)
        assertOneHasFocus(dock, in: app)
        retainScreenshot("zones-02-dock", in: app)
        move(.left, to: element("desk-back", in: app), maximumPresses: 8, in: app)
        // Up from the dock: back in the screen.
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.up)
        assertCondition("hasFocus == false", on: dock[0], in: app)
        XCTAssertFalse(dock.contains(where: { $0.hasFocus }))
        print("PASS: TV_REMOTE the arrows alone reached the search field, the column, the actions and the dock, and came back")
    }

    /// "ne pas laisser de fonctionnalité vide": after a pause, a press toward
    /// an edge goes somewhere, as a fresh key of a Mac does. From the column
    /// Left goes to Back; along the bar, past one end comes the other; Down
    /// from the bar leads to the search, and Up from the search to the icon
    /// of the screen; Right past the actions of a channel goes there too.
    @MainActor
    func testNoPressOfTheRemoteLeadsNowhere() {
        let app = launch("live")
        defer { app.terminate() }
        let channel = element("live-channel-fixture-live-0", in: app)
        let back = element("desk-back", in: app)
        let television = element("navigation-tab-live", in: app)
        let settings = element("navigation-settings", in: app)
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        let logical = element("flux-catalog-logical-focus", in: app)
        assertFocus(channel, logical: "fixture-live-0", in: app)

        XCUIRemote.shared.press(.left)
        assertCondition(NSPredicate(format: "value BEGINSWITH %@ OR value == %@", "group-", "countries"), on: logical, in: app)
        afterAPause(.left)
        assertFocus(back, in: app)
        retainScreenshot("edges-01-column-to-back", in: app)
        afterAPause(.left)
        assertFocus(settings, in: app)
        afterAPause(.right)
        assertFocus(back, in: app)
        afterAPause(.down)
        assertCondition("hasFocus == true", on: search, in: app)
        retainScreenshot("edges-02-bar-to-search", in: app)
        afterAPause(.up)
        assertFocus(television, in: app)
        retainScreenshot("edges-03-search-to-the-icon", in: app)

        // Up from the bar into the list, then right along the actions of
        // the channel and past them.
        afterAPause(.up)
        assertCondition("hasFocus == false", on: television, in: app)
        for _ in 0..<5 where !holdsFocus(television) { afterAPause(.right) }
        assertFocus(television, in: app)
        print("PASS: TV_REMOTE after a pause, Left from the column reached Back, the bar went round both ways, Down from the bar reached the search, Up from the search and Right past the actions reached the icon of the screen")
    }

    /// The preview of a channel, a moment after the remote has left its row:
    /// stopped, it would belong to no channel.
    @MainActor
    private func assertPreviewStays(_ preview: XCUIElement, with channel: String, on control: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 1.5 * Self.patience)
        let value = preview.value as? String ?? "nil"
        XCTAssertTrue(value.hasPrefix(channel + " "), "On \(control) the preview left \(channel): \(value)",
                      file: file, line: line)
    }

    /// A press after a pause: one that may cross an edge.
    @MainActor
    private func afterAPause(_ direction: XCUIRemote.Button) {
        Thread.sleep(forTimeInterval: 0.8)
        XCUIRemote.shared.press(direction)
    }

    @MainActor
    func testMenuRetracesTheScreensLikeTheBackOfABrowser() {
        let app = launch("home")
        defer { app.terminate() }
        // A simulator that has just been created shows a system tip that
        // takes the first Menu: this flow runs among the last, and waits.
        sleep(3)
        let home = element("desk-home-screen", in: app)
        let live = element("navigation-tab-live", in: app)
        let movie = element("navigation-tab-movie", in: app)
        let channel = element("live-channel-fixture-live-0", in: app)
        let film = element("catalog-card-fixture-movie-0", in: app)
        let dock = Self.dockKeys.map { element($0, in: app) }
        assertFocus(live, logical: "tab-live", in: app)

        // A destination opens with the remote in its content: the first
        // channel here, where nothing was remembered.
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: home, in: app)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        retainScreenshot("back-01-television", in: app)

        // Television, then films, then television again: three steps.
        XCUIRemote.shared.press(.right)
        assertFocus(element("live-watch", in: app), in: app)
        XCUIRemote.shared.press(.down)
        assertOneHasFocus(dock, in: app)
        move(.left, to: movie, maximumPresses: 6, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        XCUIRemote.shared.press(.down)
        assertOneHasFocus(dock, in: app)
        move(.left, to: live, maximumPresses: 6, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(channel, logical: "fixture-live-0", in: app)

        // Menu from inside the list first gives the remote to Back in the
        // bar, beside the home screen and the dock (David, 26/11); Menu
        // again goes back, to the films and to the title selected there.
        let back = element("desk-back", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(back, logical: "desk-back", in: app)
        XCTAssertTrue(channel.exists)
        retainScreenshot("back-01b-the-bar", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        XCTAssertFalse(channel.exists)
        retainScreenshot("back-02-films", in: app)
        // Then the television that was opened first, not the home screen.
        XCUIRemote.shared.press(.menu)
        assertFocus(back, logical: "desk-back", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        XCTAssertFalse(home.exists)
        // Then the home screen, where the path started.
        XCUIRemote.shared.press(.menu)
        assertFocus(back, logical: "desk-back", in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        assertFocus(live, logical: "tab-live", in: app)
        retainScreenshot("back-03-home", in: app)
        print("PASS: TV_REMOTE each destination opened in its content; from a list, Menu gave the remote to Back in the bar, then retraced television, films, television and the home screen")
    }

    /// "faut pouvoir choisir mode classique ou mode souris, soit dans option
    /// soit un système facile pour basculer, voire les deux" (David, 26/11):
    /// Play/Pause held down goes to the mouse and back, and a bubble says so.
    @MainActor
    func testPlayPauseHeldSwitchesBetweenTheRemoteAndTheMouse() {
        let app = launch("live")
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        let channel = element("live-channel-fixture-live-0", in: app)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'classic'"), on: state, in: app)
        XCUIRemote.shared.press(.playPause, forDuration: 1.2)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'active toasts:1'"), on: state, in: app)
        XCTAssertTrue(appears(element("flux-pointer-mode", in: app), timeout: 3), "A bubble says the mode.")
        retainScreenshot("pointer-01-mouse", in: app)
        // Held down, Play/Pause changed the mode only: the channel keeps the remote.
        assertFocus(channel, logical: "fixture-live-0", in: app)
        XCUIRemote.shared.press(.playPause, forDuration: 1.2)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'classic toasts:2'"), on: state, in: app)
        // Classic again: the remote goes from one channel to the next.
        XCUIRemote.shared.press(.down)
        assertFocus(element("live-channel-fixture-live-1", in: app), logical: "fixture-live-1", in: app)
        print("PASS: TV_REMOTE Play/Pause held down went to the mouse and back to the classic remote, each time told by a bubble")
    }

    /// The pointer gives the focus to what it rests on, the channels as the
    /// icons of the dock; a click presses what it rests on. A bench has no
    /// thumb: the app moves the pointer itself, over the content and the bar.
    @MainActor
    func testThePointerGivesTheFocusToWhatItCrossesAndClicksIt() {
        let app = launch("pointer")
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        let swept = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'end='"), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [swept], timeout: 90 * Self.patience), .completed, "The sweep of the pointer did not end.")
        let value = seen(state)?.value as? String ?? ""
        let trace = value.components(separatedBy: "trace:").last?.components(separatedBy: ",") ?? []
        print("TV_REMOTE pointer: \(value)")
        XCTAssertTrue(value.hasPrefix("active"), "The pointer is not the remote: \(value)")
        XCTAssertTrue(trace.contains { $0.hasPrefix("fixture-live-") }, "The pointer gave the focus to no channel: \(trace)")
        XCTAssertTrue(trace.contains { $0.hasPrefix("tab-") }, "The pointer gave the focus to no icon of the dock: \(trace)")
        let end = (trace.last ?? "").replacingOccurrences(of: "end=", with: "")
        XCTAssertTrue(end.hasPrefix("fixture-live-"), "The pointer does not rest on a channel: \(end)")
        assertCondition(NSPredicate(format: "value == %@", end), on: element("flux-catalog-logical-focus", in: app), in: app)
        retainScreenshot("pointer-02-on-a-channel", in: app)
        // A click watches the channel under the pointer; the picture then
        // takes the thumb, without a pointer over it.
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'suspended'"), on: state, in: app)
        retainScreenshot("pointer-03-clicked", in: app)
        print("PASS: TV_REMOTE the pointer gave the focus to the channels and the icons it crossed, and its click watched the channel under it")
    }

    /// The pointer in the fiche of a film and in the panel of its lists,
    /// whose controls take the focus from the fiche and the panel, not from
    /// the screen: the click presses what the pointer rests on, at once.
    @MainActor
    func testThePointerClicksTheFicheAndThePanelOfItsLists() {
        let app = launch("movie", environment: ["FLUX_UI_POINTER": "1"])
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        var trace = pointerTrace(until: "end=", on: state)
        XCTAssertTrue(trace.contains("play"), "The pointer did not give the focus to Lecture: \(trace)")
        XCTAssertEqual(trace.last, "end=favorite", "The pointer does not rest on the key of the lists: \(trace)")
        retainScreenshot("pointer-fiche-01-lists-key", in: app)
        XCUIRemote.shared.press(.select)
        let list = element("favorite-list-0", in: app)
        XCTAssertTrue(appears(list, timeout: 10), "The click did not open the lists of the film.")
        trace = pointerTrace(until: "end2=", on: state)
        XCTAssertTrue(trace.contains("create"), "The pointer did not give the focus to the row of a new list: \(trace)")
        XCTAssertEqual(trace.last, "end2=list-0", "The pointer does not rest on the first list: \(trace)")
        let before = seen(list)?.value as? String ?? ""
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value != %@", before), on: list, in: app)
        retainScreenshot("pointer-fiche-02-list-chosen", in: app)
        print("PASS: TV_REMOTE the pointer pressed the key of the lists in the fiche, then chose a list in the panel, each at the first click")
    }

    /// "pointeur aussi dans les Réglages" (David, 27/11): the content of a
    /// page, the column, which shows the page the pointer rests on, and the
    /// studio, which covers the screen with a pointer of its own.
    @MainActor
    func testThePointerWalksTheSettingsAndTheStudio() {
        let app = launch("settings-graphics", environment: ["FLUX_UI_POINTER": "1"])
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        var trace = pointerTrace(until: "end=", on: state)
        XCTAssertTrue(trace.contains { $0.hasPrefix("preset-") }, "The pointer did not give the focus to a preset: \(trace)")
        XCTAssertTrue(trace.contains { $0.hasPrefix("toggle-") }, "The pointer did not give the focus to a switch: \(trace)")
        XCTAssertTrue(trace.contains("settings-page-appearance"), "The pointer did not enter the column on Interface: \(trace)")
        XCTAssertEqual(trace.last, "end=studio-dock", "The pointer does not rest on the key of the studio: \(trace)")
        XCTAssertEqual(seen(element("settings-page-appearance", in: app))?.value as? String, "Sélectionné",
                       "The column does not show the page the pointer rested on.")
        retainScreenshot("pointer-settings-01-studio-key", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(appears(element("appearance-studio", in: app), timeout: 10), "The click did not open the studio.")
        trace = pointerTrace(until: "end2=", on: state)
        XCTAssertTrue(trace.contains("studio-scope-live"), "The pointer did not move the cursor of the studio: \(trace)")
        let theme = (trace.last ?? "").replacingOccurrences(of: "end2=", with: "")
        XCTAssertTrue(theme.hasPrefix("studio-theme-"), "The pointer does not rest on a theme: \(trace)")
        XCTAssertNotEqual(seen(element(theme, in: app))?.value as? String, "Choisi", "The theme was chosen before the click.")
        retainScreenshot("pointer-settings-02-studio-theme", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value == 'Choisi'"), on: element(theme, in: app), in: app)
        // The arrows still move the cursor, as with the classic remote.
        let catcher = element("studio-catcher", in: app)
        let cursor = seen(catcher)?.value as? String ?? ""
        XCTAssertTrue(cursor.hasPrefix("theme-"), "The cursor of the studio is not on the theme: \(cursor)")
        XCUIRemote.shared.press(.up)
        assertCondition(NSPredicate(format: "value != %@", cursor), on: catcher, in: app)
        // Menu closes the studio: the settings have the pointer again.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: element("appearance-studio", in: app), in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'active'"), on: state, in: app)
        retainScreenshot("pointer-settings-03-back", in: app)
        print("PASS: TV_REMOTE the pointer walked a page of the settings and its column, opened the studio, chose a theme there and came back")
    }

    /// Over the picture the thumb is the picture's; a panel over it, the
    /// languages, gives it back to the pointer.
    @MainActor
    func testThePointerChoosesTheLanguagesOverThePicture() {
        let app = launch("player-tracks", environment: ["FLUX_UI_POINTER": "1"])
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        let trace = pointerTrace(until: "end=", on: state)
        XCTAssertTrue(trace.contains("track-audio-a2"), "The pointer did not give the focus to an audio: \(trace)")
        XCTAssertEqual(trace.last, "end=track-sub-s1", "The pointer does not rest on a subtitle: \(trace)")
        let subtitle = element("track-sub-s1", in: app)
        XCTAssertNotEqual(seen(subtitle)?.value as? String, "Sélectionnée")
        retainScreenshot("pointer-tracks-01-subtitle", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value == 'Sélectionnée'"), on: subtitle, in: app)
        print("PASS: TV_REMOTE the pointer took over from the picture under the languages, and its click chose the subtitle under it")
    }

    /// The settings over the picture give the thumb back to the pointer:
    /// the column shows the page it rests on, and a click changes the
    /// switch under it while the stream goes on.
    @MainActor
    func testThePointerWalksTheSettingsOverThePicture() {
        let app = launch("player-flow", environment: ["FLUX_UI_POINTER": "1"])
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        let play = element("player-playpause", in: app)
        let catcher = element("player-catcher", in: app)
        let settings = element("player-engine", in: app)
        let video = element("settings-page-video", in: app)
        // The picture takes the thumb: the pointer waits, and the arrows
        // open the settings as with the classic remote.
        assertFocus(play, in: app, leavesByItself: true)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(catcher, in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'suspended'"), on: state, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(play, in: app)
        move(.right, to: settings, maximumPresses: 5, in: app)
        XCUIRemote.shared.press(.select)
        // The pointer takes the settings at once: the column follows it.
        XCTAssertTrue(appears(video, timeout: 10), "The arrows did not open the settings.")
        let trace = pointerTrace(until: "end=", on: state)
        XCTAssertEqual(trace, ["settings-page-network", "settings-page-video", "end=toggle-Reprendre automatiquement films et épisodes"],
                       "The pointer did not walk the column and rest on the switch: \(trace)")
        XCTAssertEqual(seen(video)?.value as? String, "Sélectionné", "The column does not show the page the pointer rested on.")
        XCTAssertFalse(catcher.exists, "Nothing invisible stands under the settings.")
        let resume = app.buttons["Reprendre automatiquement films et épisodes"]
        let before = seen(resume)?.value as? String ?? ""
        retainScreenshot("pointer-player-settings-01-switch", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value != %@", before), on: resume, in: app)
        // Menu closes the panels: the picture takes the thumb again.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: video, in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'suspended'"), on: state, in: app)
        print("PASS: TV_REMOTE the settings over the picture gave the thumb back to the pointer, whose column showed the pages it crossed, and its click changed the switch under it")
    }

    /// A message takes the pointer as it takes the remote: what stands
    /// under it is out of reach, and a click on its OK acknowledges it.
    @MainActor
    func testThePointerAnswersAMessage() {
        let app = launch("player-deep", environment: ["FLUX_UI_POINTER": "1"])
        defer { app.terminate() }
        let state = element("flux-pointer-state", in: app)
        let play = element("player-playpause", in: app)
        let catcher = element("player-catcher", in: app)
        let acknowledge = element("desk-notice-ok", in: app)
        let watched = element("live-channel-fixture-live-58", in: app)
        // The sixtieth channel of the fixture cannot be shown: it raises
        // the message of a source whose credentials are missing.
        let unplayable = element("live-channel-fixture-live-59", in: app)
        assertFocus(play, in: app, leavesByItself: true)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(catcher, in: app)
        // Menu leaves the picture for the catalogue, where the pointer is the remote.
        XCUIRemote.shared.press(.menu)
        assertFocus(watched, logical: "fixture-live-58", in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH 'active'"), on: state, in: app)
        // The arrows still move the selection, and the click presses it.
        XCUIRemote.shared.press(.down)
        assertFocus(unplayable, logical: "fixture-live-59", in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(appears(acknowledge, timeout: 10), "The channel did not raise its message.")
        let trace = pointerTrace(until: "end=", on: state)
        XCTAssertEqual(trace, ["desk-notice-ok", "miss:fixture-live-58", "end=desk-notice-ok"],
                       "The pointer reached what stands under the message, or not its OK: \(trace)")
        retainScreenshot("pointer-message-01-ok", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: acknowledge, in: app)
        assertFocus(unplayable, logical: "fixture-live-59", in: app)
        print("PASS: TV_REMOTE the message took the pointer and kept what stands under it out of reach; a click on its OK acknowledged it and gave the channel back")
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
        moveToSave(save, in: app)
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
        // Menu again: the catalogue of the series, on the series that was open.
        XCUIRemote.shared.press(.menu)
        assertFocus(element("catalog-card-fixture-series", in: app), logical: "fixture-series", in: app)
        print("PASS: TV_REMOTE series fiche entered its episodes and its seasons on the selected row, followed the season under the remote, returned to that season on the shelf and then to the series in its catalogue")
    }

    @MainActor
    func testPlayerPanelsKeepTheRemoteWhileAStreamPlays() {
        let app = launch("player-flow")
        defer { app.terminate() }
        let play = element("player-playpause", in: app)
        let catcher = element("player-catcher", in: app)
        let settings = element("player-engine", in: app)
        let languages = element("player-tracks", in: app)
        let video = element("settings-page-video", in: app)
        let network = element("settings-page-network", in: app)
        assertFocus(play, in: app, leavesByItself: true)
        retainScreenshot("player-01-commands", in: app)

        // The stream plays: the commands leave the picture by themselves.
        assertCondition("exists == false", on: play, in: app)
        assertFocus(catcher, in: app)
        // OK brings them back, on play and pause.
        XCUIRemote.shared.press(.select)
        assertFocus(play, in: app)

        // Réglages opens its panels on the page they show.
        move(.right, to: settings, maximumPresses: 5, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(video, in: app)
        retainScreenshot("player-02-settings", in: app)
        // Longer than the delay of the commands: nothing takes the remote
        // from the panels while the stream goes on.
        sleep(Self.pastTheCommands)
        assertFocus(video, in: app)
        XCTAssertFalse(catcher.exists, "Nothing invisible stands under the settings.")
        // Walking the pages shows each one; Right enters the page.
        XCUIRemote.shared.press(.down)
        assertFocus(network, in: app)
        XCTAssertTrue(app.staticTexts["Profils réseau"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.right)
        assertCondition("hasFocus == false", on: network, in: app)
        XCTAssertTrue(network.exists)
        // Left returns to the page in use, not to the nearest row.
        move(.left, to: network, maximumPresses: 3, in: app)
        retainScreenshot("player-03-network-page", in: app)
        // Menu closes the panels and returns to the key that opened them.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: video, in: app)
        assertFocus(settings, in: app)

        // Langues: the audio in use, a choice applied at once, and the same
        // patience while the stream plays.
        XCUIRemote.shared.press(.left)
        assertFocus(languages, in: app)
        XCUIRemote.shared.press(.select)
        let french = element("track-audio-a1", in: app)
        let described = element("track-audio-a2", in: app)
        assertFocus(french, in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(described, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(NSPredicate(format: "value == %@", "Sélectionnée"), on: described, in: app)
        retainScreenshot("player-04-languages", in: app)
        sleep(Self.pastTheCommands)
        assertFocus(described, in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: described, in: app)
        assertFocus(languages, in: app)

        // Menu leaves the stream for the list it was opened from.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: languages, in: app)
        assertFocus(element("live-channel-fixture-live-0", in: app), logical: "fixture-live-0", in: app)
        print("PASS: TV_REMOTE player commands hid and came back, its settings and its languages kept the remote during a stream, Menu closed each panel and then left the stream")
    }

    @MainActor
    func testZappingKeepsTheRemoteOnTheWatchedChannel() {
        let app = launch("player-deep")
        defer { app.terminate() }
        let play = element("player-playpause", in: app)
        let catcher = element("player-catcher", in: app)
        let channels = element("player-zap-list", in: app)
        let next = element("player-next", in: app)
        func row(_ index: Int) -> XCUIElement { element("zap-channel-fixture-live-\(index)", in: app) }
        // The fifty-ninth channel of a hundred and ten, which the
        // catalogue had not selected: its row is far below the top of the
        // list, which must scroll to it before it can take the remote.
        let watched = row(58)
        let playing = NSPredicate(format: "value == %@", "En cours")
        assertFocus(play, in: app, leavesByItself: true)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(catcher, in: app)

        // Commands hidden, Down and Up change channel as a television does:
        // under the banner of the channel alone. The picture keeps the
        // remote, the commands stay away, and the next press goes on.
        let banner = element("player-banner", in: app)
        XCUIRemote.shared.press(.down)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 58,"), on: banner, in: app)
        assertFocus(catcher, in: app)
        XCTAssertFalse(play.exists, "Changing channel does not bring the commands back.")
        retainScreenshot("zap-00-banner-of-the-channel", in: app)
        XCUIRemote.shared.press(.down)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 57,"), on: banner, in: app)
        // A channel that does not answer says so in its banner, which stays;
        // nothing has to be closed, and the next press goes on.
        XCUIRemote.shared.press(.down)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 56,"), on: banner, in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH %@", "Indisponible"), on: banner, in: app)
        assertFocus(catcher, in: app)
        XCTAssertFalse(play.exists, "A dead channel does not bring the commands back either.")
        XCTAssertFalse(element("player-retry", in: app).exists)
        retainScreenshot("zap-00-channel-that-does-not-answer", in: app)
        XCUIRemote.shared.press(.up)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 57,"), on: banner, in: app)
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.up)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 59,"), on: banner, in: app)
        assertCondition(NSPredicate(format: "value BEGINSWITH %@", "En direct"), on: banner, in: app)
        assertFocus(catcher, in: app)
        XCTAssertFalse(play.exists)

        // Left brings the list of channels, on the one being watched.
        XCUIRemote.shared.press(.left)
        assertFocus(watched, in: app)
        assertCondition(playing, on: watched, in: app)
        assertCondition("exists == false", on: banner, in: app)
        retainScreenshot("zap-01-on-the-watched-channel", in: app)
        // Right shows the first category, where that channel is not: the
        // remote is on its first channel. Left returns to all the channels,
        // on the one being watched.
        XCUIRemote.shared.press(.right)
        assertFocus(row(1), in: app)
        assertCondition("exists == false", on: watched, in: app)
        retainScreenshot("zap-02-another-category", in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(watched, in: app)
        // The list builds sixty channels at a time: Down from the last one
        // turns its page, Up from the first one turns it back.
        XCUIRemote.shared.press(.down)
        assertFocus(row(59), in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(row(60), in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(row(59), in: app)
        // Up walks the list, OK shows that channel: the list stays under the
        // remote, and the commands do not come over it.
        XCUIRemote.shared.press(.up)
        assertFocus(watched, in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(row(57), in: app)
        XCUIRemote.shared.press(.select)
        assertCondition(playing, on: row(57), in: app)
        assertFocus(row(57), in: app)
        XCTAssertFalse(play.exists, "The list of channels stands alone over the picture.")
        // The key Lecture/Pause of the remote shows the channel under it too.
        XCUIRemote.shared.press(.up)
        assertFocus(row(56), in: app)
        XCUIRemote.shared.press(.playPause)
        assertCondition(playing, on: row(56), in: app)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.select)
        assertCondition(playing, on: row(57), in: app)
        assertFocus(row(57), in: app)
        // Menu closes it: opened from the picture, it leaves the picture bare.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: row(57), in: app)
        assertFocus(catcher, in: app)

        // OK brings the commands; their key Chaînes opens the list in their
        // place, on the channel now watched, and Menu returns to that key.
        XCUIRemote.shared.press(.select)
        assertFocus(play, in: app)
        move(.left, to: channels, maximumPresses: 4, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(row(57), in: app)
        assertCondition("exists == false", on: channels, in: app)
        retainScreenshot("zap-03-list-in-place-of-the-commands", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: row(57), in: app)
        assertFocus(channels, in: app)
        // Suivante changes channel and keeps the remote, to go on.
        move(.right, to: next, maximumPresses: 4, in: app)
        XCUIRemote.shared.press(.select)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        assertFocus(next, in: app)

        // Menu leaves the stream for the catalogue, on the channel that was
        // being watched: on its second page, and not the one it remembered.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: next, in: app)
        assertFocus(element("live-channel-fixture-live-58", in: app), logical: "fixture-live-58", in: app)
        retainScreenshot("zap-04-back-on-the-watched-channel", in: app)
        print("PASS: TV_REMOTE the channel list opened on the watched channel from the picture and from its key, changed category, page and channel under the remote, Suivante kept the remote, and Menu returned to the watched channel in the catalogue")
    }

    @MainActor
    func testMessageTakesTheRemoteAndGivesItBack() {
        let app = launch("player-deep")
        defer { app.terminate() }
        let play = element("player-playpause", in: app)
        let catcher = element("player-catcher", in: app)
        let acknowledge = element("desk-notice-ok", in: app)
        // The sixtieth channel of the fixture cannot be shown: it raises the
        // message of a source whose credentials are missing.
        let refused = element("zap-channel-fixture-live-59", in: app)
        assertFocus(play, in: app, leavesByItself: true)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(catcher, in: app)

        // Over the list of channels: the message takes the remote, nothing
        // under it answers, OK acknowledges it and the list has the remote again.
        XCUIRemote.shared.press(.left)
        assertFocus(element("zap-channel-fixture-live-58", in: app), in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(refused, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(acknowledge, in: app)
        retainScreenshot("message-01-over-the-channel-list", in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(acknowledge, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: acknowledge, in: app)
        assertFocus(refused, in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: refused, in: app)
        assertFocus(catcher, in: app)

        // Over the catalogue: the same message, closed by Menu this time,
        // returns the remote to the channel it was raised from.
        XCUIRemote.shared.press(.menu)
        let watched = element("live-channel-fixture-live-58", in: app)
        let unplayable = element("live-channel-fixture-live-59", in: app)
        assertFocus(watched, logical: "fixture-live-58", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(unplayable, logical: "fixture-live-59", in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(acknowledge, in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: acknowledge, in: app)
        assertFocus(unplayable, logical: "fixture-live-59", in: app)

        // A channel opened from the catalogue shows its picture, bare, under
        // its banner: Down changes channel at once, and OK brings the commands.
        XCUIRemote.shared.press(.up)
        assertFocus(watched, logical: "fixture-live-58", in: app)
        XCUIRemote.shared.press(.select)
        let banner = element("player-banner", in: app)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 59,"), on: banner, in: app)
        assertFocus(catcher, in: app)
        XCTAssertFalse(play.exists, "A channel opens without its commands.")
        retainScreenshot("message-02-channel-opened-under-its-banner", in: app)
        XCUIRemote.shared.press(.down)
        assertCondition(NSPredicate(format: "label BEGINSWITH %@", "Chaîne 58,"), on: banner, in: app)
        assertFocus(catcher, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(play, in: app)
        assertCondition("exists == false", on: banner, in: app)
        print("PASS: TV_REMOTE a message took the remote over the channel list and over the catalogue, OK and Menu closed it and returned the remote where it was, and a channel opened from the catalogue showed its banner alone, changed channel at once and gave its commands on OK")
    }

    @MainActor
    func testPagesOfALargeCatalogueTurnUnderTheRemote() {
        // Fifty-eight thousand films: the catalogue of a real subscription.
        let app = launch("movies-many")
        defer { app.terminate() }
        let card = element("catalog-card-fixture-movie-1", in: app)
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        let next = element("navigation-page-next", in: app)
        let previous = element("navigation-page-prev", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        XCTAssertTrue(app.staticTexts["Page 1 sur 969"].exists)
        retainScreenshot("pages-01-films-of-a-large-catalogue", in: app)

        // One press up is the line of the search, where the pages are; the
        // jackets start right under it.
        XCUIRemote.shared.press(.up)
        assertCondition("hasFocus == true", on: search, in: app)
        XCTAssertLessThan(card.frame.minY, 240, "The catalogue starts right under one line of controls.")
        // Page suivante is the next key: the previous one has nothing to
        // show yet. It keeps the remote, to turn the next page at once.
        XCUIRemote.shared.press(.right)
        assertFocus(next, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Page 2 sur 969"].waitForExistence(timeout: 10))
        assertFocus(next, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Page 3 sur 969"].waitForExistence(timeout: 10))
        assertFocus(next, in: app)
        assertCondition("exists == false", on: card, in: app)
        // Page précédente is beside it, and Down enters the page from its top.
        XCUIRemote.shared.press(.left)
        assertFocus(previous, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Page 2 sur 969"].waitForExistence(timeout: 10))
        assertFocus(previous, in: app)
        XCUIRemote.shared.press(.down)
        assertOneHasFocus((60..<65).map { element("catalog-card-fixture-movie-\($0)", in: app) }, in: app)
        retainScreenshot("pages-02-second-page", in: app)
        print("PASS: TV_REMOTE the pages of a catalogue of 58 093 films stood on the line of the search, Page suivante and Page précédente kept the remote while they turned, and Down entered the page from its top")
    }

    /// A page of sixty films keeps the line of the search and the bar many
    /// presses away from a title in its middle. Lecture/Pause goes round
    /// the zones of the screen as the hands of a clock: one press from the
    /// content to the bar below, one more to the column on the left, one
    /// more to the search above, and one more back to the title that was left.
    @MainActor
    func testPlayPauseWalksTheZonesOfALongPage() {
        let app = launch("movies-many")
        defer { app.terminate() }
        let films = element("navigation-tab-movie", in: app)
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        // The row of the column that stands for what is shown: all the films.
        let scope = app.buttons["Tous les films"].firstMatch
        assertFocus(element("catalog-card-fixture-movie-1", in: app), logical: "fixture-movie-1", in: app)
        XCTAssertTrue(element("desk-zone-hint", in: app).exists, "The bar says which key walks the zones.")
        // Four rows down: the bar is eight rows further, the search four rows back.
        // Pressed one after the other, until the title has the remote: four
        // presses in a row once left it short of it on a hosted machine
        // (e5e24fb on main), never here nor on the branch.
        let middle = element("catalog-card-fixture-movie-21", in: app)
        move(.down, to: middle, maximumPresses: 6, in: app)
        assertFocus(middle, logical: "fixture-movie-21", in: app)
        retainScreenshot("zones-01-middle-of-a-long-page", in: app)

        XCUIRemote.shared.press(.playPause)
        assertFocus(films, logical: "tab-movie", in: app)
        retainScreenshot("zones-02-the-bar", in: app)
        XCUIRemote.shared.press(.playPause)
        assertFocus(scope, logical: "group-all", in: app)
        retainScreenshot("zones-03-the-column", in: app)
        XCUIRemote.shared.press(.playPause)
        assertCondition("hasFocus == true", on: search, in: app)
        retainScreenshot("zones-04-the-search", in: app)
        XCUIRemote.shared.press(.playPause)
        assertFocus(middle, logical: "fixture-movie-21", in: app)
        // From the bar the arrows go on as before: Left reaches Home and Back.
        XCUIRemote.shared.press(.playPause)
        assertFocus(films, logical: "tab-movie", in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(element("navigation-tab-live", in: app), logical: "tab-live", in: app)
        print("PASS: TV_REMOTE Lecture/Pause went round the zones of a page of sixty films as the hands of a clock: the bar, the column, the search, and back to the title that was left")
    }

    /// "finalement fais qu'une barre sur ecran accueil comme l'autre,
    /// extensible en bas, mais garde cette taille pour la page accueil"
    /// (David, 27/11): one bar at the foot of the home screen, at its size,
    /// and what it cannot hold in Autres, whose folder opens above it
    /// without reaching the name of the application and the time.
    @MainActor
    func testTheHomeScreenKeepsOneBarAtItsFoot() {
        let app = launch("dock-home")
        defer { app.terminate() }
        let films = element("navigation-tab-movie", in: app)
        let folder = element("navigation-dock-stack-default-movie", in: app)
        let more = element("navigation-dock-more", in: app)
        assertFocus(films, logical: "tab-movie", in: app)
        // One row: what is kept stands beside the destinations, Autres too.
        // The films have the remote: the loupe draws them larger from the
        // foot of their cell, and the frame XCTest reads grows with it
        // (193 × 210 points for 124 × 135 at rest). A row is told by its foot.
        XCTAssertTrue(appears(more), "What the bar cannot hold is in Autres.")
        XCTAssertEqual(folder.frame.maxY, films.frame.maxY, accuracy: 6, "The bar stands on one row.")
        XCTAssertEqual(more.frame.maxY, films.frame.maxY, accuracy: 6, "Autres stands in that row.")
        // At the foot of the screen, nine tenths of their size at least: the
        // list kept in the bar, away from the loupe, gives that size.
        XCTAssertGreaterThan(folder.frame.minY, app.frame.height * 0.68, "The bar stands at the foot of the screen.")
        XCTAssertGreaterThan(folder.frame.width, 120, "The icons keep their size.")
        // "au survol, sur ecran accueil, pour film serie etc, on affiche
        // l'ecran de fond" (David, 27/11): the films selected, the pictures
        // of their screen stand behind, though the home screen keeps its own.
        let backdrop = element("flux-home-backdrop", in: app)
        assertCondition(NSPredicate(format: "value == %@", "movie"), on: backdrop, in: app)
        retainScreenshot("home-bar-01-one-bar", in: app)
        // Autres, selected: the large name says what it is, without a bubble,
        // over the pictures of the home screen.
        move(.right, to: more, maximumPresses: 12, in: app)
        XCTAssertFalse(element("flux-dock-bubble", in: app).exists, "The home screen names a title without a bubble.")
        assertCondition(NSPredicate(format: "value == %@", "home"), on: backdrop, in: app)
        // Its folder opens above the bar, under the name of the application.
        XCUIRemote.shared.press(.select)
        let fan = element("dock-fan", in: app)
        XCTAssertTrue(appears(fan), "Autres opens as a fan.")
        XCTAssertGreaterThan(fan.frame.minY, 58, "The folder stays under the name of the application and the time.")
        XCTAssertLessThan(fan.frame.maxY, more.frame.maxY, "The folder rises from the bar.")
        retainScreenshot("home-bar-02-autres", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(more, in: app)
        // The bar goes on to the list kept in it.
        move(.right, to: folder, maximumPresses: 6, in: app)
        print("PASS: TV_REMOTE the bar of the home screen stood on one row at its foot, its surplus in Autres, whose folder opened under the name of the application")
    }

    /// "faudrait donner le choix d'afficher ou non la barre dock, si pas
    /// affichée ça permet de simplifier interface et d'avoir en full screen
    /// le reste" (David, 27/11). Without the dock a screen takes the whole
    /// screen. Back and Home stand at the top of its column: Menu leads
    /// there from the content, then to the home screen, which keeps its
    /// bar to go anywhere. Lecture/Pause goes round the zones that remain.
    @MainActor
    func testWithoutTheDockAScreenTakesTheWholeScreen() {
        let app = launch("home", environment: ["FLUX_UI_DOCK_HIDDEN": "1"])
        defer { app.terminate() }
        let home = element("desk-home-screen", in: app)
        let live = element("navigation-tab-live", in: app)
        let films = element("navigation-tab-movie", in: app)
        let film = element("catalog-card-fixture-movie-0", in: app)
        let back = element("desk-back", in: app)
        let scope = app.buttons["Tous les films"].firstMatch
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        // The home screen keeps its bar: the films open from it.
        assertFocus(live, logical: "tab-live", in: app)
        XCUIRemote.shared.press(.right)
        assertFocus(films, logical: "tab-movie", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: home, in: app)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        // Nothing of the bar under the films: neither its icons nor the plan of the screen.
        XCTAssertFalse(films.exists, "The dock is hidden under the screens.")
        XCTAssertFalse(element("desk-zone-hint", in: app).exists, "The plan of the screen leaves with the dock.")
        retainScreenshot("no-dock-01-films", in: app)
        // Lecture/Pause: the column, the search, and back to the film.
        XCUIRemote.shared.press(.playPause)
        assertFocus(scope, logical: "group-all", in: app)
        XCUIRemote.shared.press(.playPause)
        assertCondition("hasFocus == true", on: search, in: app)
        XCUIRemote.shared.press(.playPause)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        // Menu gives the remote to Back, at the top of the column.
        XCUIRemote.shared.press(.menu)
        assertFocus(back, logical: "desk-back", in: app)
        XCTAssertLessThan(back.frame.midY, app.frame.height * 0.25, "Back stands at the top of the column.")
        XCTAssertTrue(film.exists)
        retainScreenshot("no-dock-02-back-at-the-top", in: app)
        // Menu again: the home screen, on the films.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        assertFocus(films, logical: "tab-movie", in: app)
        print("PASS: TV_REMOTE without the dock the films took the whole screen, Lecture/Pause went round the column and the search, Menu gave the remote to Back at the top of the column and then the home screen, which kept its bar")
    }

    /// A folder made in the dock is one icon of it, with the icon chosen
    /// for it. OK opens it as a fan; a folder kept inside it shows what it
    /// holds in its place, Menu returns to the folder above and then
    /// closes the fan on its icon, and a title opens from two folders deep.
    @MainActor
    func testAFolderOfTheDockOpensTheFoldersItHolds() {
        let app = launch("dock-folders")
        defer { app.terminate() }
        let card = element("catalog-card-fixture-movie-1", in: app)
        let folder = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                                      "navigation-dock-folder-", "Soirée")).firstMatch
        let inner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dock-fan-folder:")).firstMatch
        let film = element("dock-fan-fixture-movie-0", in: app)
        let deep = element("dock-fan-fixture-movie-2", in: app)
        let up = element("dock-fan-up", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        XCUIRemote.shared.press(.down)
        walkDock(to: folder, in: app)
        XCTAssertEqual(folder.label, "Soirée · 3 titres · 1 dossier")
        XCUIRemote.shared.press(.select)
        // The folder it holds comes first, the nearest to the bar; its own film stands above.
        assertFocus(inner, in: app)
        XCTAssertEqual(inner.label, "Classiques · 2")
        XCTAssertTrue(film.exists)
        XCTAssertFalse(deep.exists, "What a folder inside holds shows once that folder is opened.")
        retainScreenshot("folders-01-a-folder-and-the-one-it-holds", in: app)
        // OK on the folder inside: its titles take the place of these, after the way back.
        XCUIRemote.shared.press(.select)
        assertFocus(deep, in: app)
        XCTAssertTrue(up.exists)
        XCTAssertEqual(up.label, "Soirée")
        assertCondition("exists == false", on: film, in: app)
        retainScreenshot("folders-02-inside-the-folder-inside", in: app)
        // Menu returns to the folder above, on the row of the one that was left.
        XCUIRemote.shared.press(.menu)
        assertFocus(inner, in: app)
        XCTAssertTrue(film.exists)
        // Back in it by its row, and out by the row that leads back.
        XCUIRemote.shared.press(.select)
        assertFocus(deep, in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(up, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(inner, in: app)
        // Menu again closes the fan on the icon of the folder.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: inner, in: app)
        assertFocus(folder, in: app)
        // A title opens from two folders deep.
        XCUIRemote.shared.press(.select)
        assertFocus(inner, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(deep, in: app)
        XCUIRemote.shared.press(.select)
        let play = element("media-detail-play", in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: play, in: app)
        assertCondition("exists == false", on: deep, in: app)
        print("PASS: TV_REMOTE a folder of the dock opened the folder it holds, Menu and its first row led back, and a film opened from two folders deep")
    }

    /// The bar draws its selection, magnified with its neighbours, where the
    /// remote is: along the bar of a screen, along the bar of the home
    /// screen, and on the icon of a folder while its titles are walked. On
    /// an Apple TV in tvOS 26 the bar stayed drawn on the icon of the screen,
    /// not magnified: the remote moved, with its sound, and nothing else did.
    @MainActor
    func testTheDockIsDrawnWhereTheRemoteIs() {
        let keys = Self.dockKeys
        var app = launch("movies")
        let drawn = element("flux-dock-drawn", in: app)
        assertFocus(element("catalog-card-fixture-movie-1", in: app), logical: "fixture-movie-1", in: app)
        XCTAssertTrue(appears(drawn), "The fixture shows what the bar draws.")
        assertCondition(NSPredicate(format: "value == %@", "- plat"), on: drawn, in: app)
        XCUIRemote.shared.press(.down)
        walkDock(to: element("navigation-tab-movie", in: app), in: app)
        assertDrawn(drawn, among: keys, in: app)
        for direction in [XCUIRemote.Button.right, .right, .left, .left, .left] {
            XCUIRemote.shared.press(direction)
            assertDrawn(drawn, among: keys, in: app)
        }
        retainScreenshot("dock-drawn-01-along-the-bar", in: app)
        // Back in the screen: nothing of the bar is drawn as selected.
        XCUIRemote.shared.press(.up)
        assertCondition(NSPredicate(format: "value == %@", "- plat"), on: drawn, in: app)
        app.terminate()

        app = launch("home")
        let home = element("flux-home-dock-drawn", in: app)
        assertFocus(element("navigation-tab-live", in: app), logical: "tab-live", in: app)
        assertDrawn(home, among: keys, in: app)
        for direction in [XCUIRemote.Button.right, .right, .left] {
            XCUIRemote.shared.press(direction)
            assertDrawn(home, among: keys, in: app)
        }
        retainScreenshot("dock-drawn-02-home-screen", in: app)
        app.terminate()

        // A folder open on its first title: the icon of the folder stays the magnified one.
        app = launch("dock-folder")
        defer { app.terminate() }
        assertFocus(element("dock-fan-fixture-movie-0", in: app), in: app)
        assertCondition(NSPredicate(format: "value == %@", "dock-fan-fixture-movie-0 agrandi"),
                        on: element("flux-dock-drawn", in: app), in: app)
        retainScreenshot("dock-drawn-03-folder", in: app)
        print("PASS: TV_REMOTE the bar drew its selection magnified where the remote was, on a screen, on the home screen and in a folder, and nothing once the remote left it")
    }

    /// The icon of the bar that has the focus of the system is the one the
    /// bar draws as selected, and the bar is magnified around it.
    @MainActor
    private func assertDrawn(_ drawn: XCUIElement, among keys: [String], in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10 * Self.patience)
        var focused: String?
        while focused == nil, Date() < deadline {
            focused = keys.first { holdsFocus(element($0, in: app)) }
            if focused == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        }
        guard let focused else {
            retainScreenshot("failure-dock-none-focused", in: app)
            XCTFail("No icon of the bar has the focus.", file: file, line: line)
            return
        }
        let id = String(focused.dropFirst("navigation-".count))
        assertCondition(NSPredicate(format: "value == %@", id + " agrandi"), on: drawn, in: app, file: file, line: line)
    }

    /// Keys of the dock, in their default order.
    /// Back returns one screen at a time, as in a web browser. Held, it goes
    /// straight to the home screen: the Back key of the bar under OK held
    /// down, since the Menu button of a remote held down belongs to tvOS.
    @MainActor
    func testBackHeldGoesStraightToTheHomeScreen() {
        let app = launch("home")
        defer { app.terminate() }
        let live = element("navigation-tab-live", in: app)
        let films = element("navigation-tab-movie", in: app)
        let back = element("desk-back", in: app)
        let home = element("desk-home-screen", in: app)
        assertFocus(live, logical: "tab-live", in: app)

        // The films, then the television from the dock: two screens behind.
        XCUIRemote.shared.press(.right)
        assertFocus(films, logical: "tab-movie", in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: home, in: app)
        let film = element("catalog-card-fixture-movie-0", in: app)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        XCUIRemote.shared.press(.down)
        move(.left, to: live, maximumPresses: 8, in: app)
        XCUIRemote.shared.press(.select)
        let channel = element("live-channel-fixture-live-0", in: app)
        assertFocus(channel, logical: "fixture-live-0", in: app)

        // Back and Home stand at the foot of the navigation column: the
        // column leads to Home, the last of the two, and Left to Back.
        XCUIRemote.shared.press(.left)
        assertCondition("hasFocus == false", on: channel, in: app)
        move(.down, to: element("desk-home", in: app), maximumPresses: 24, in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(back, logical: "desk-back", in: app)
        XCTAssertEqual(back.label, "Retour : Films — maintenir : Accueil")
        retainScreenshot("back-01-key-of-the-bar", in: app)
        // A press would show the films. Held, it shows the home screen.
        XCUIRemote.shared.press(.select, forDuration: 1.2)
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        assertFocus(live, logical: "tab-live", in: app)
        XCTAssertFalse(film.exists)
        retainScreenshot("back-02-held-home", in: app)
        print("PASS: TV_REMOTE Back held on the bar went straight to the home screen, past the films")
    }

    /// "pour serie y'a un souci, j'ai le fond de recherche et recherche n'a
    /// pas son menu dedié" (David, 27/11). Recherche in the bar opens a
    /// screen of its own: the field takes the remote, the column says where
    /// to look, and Menu leaves it for the films, on the title that was
    /// left. A query belongs to that screen: the series, then the films,
    /// show all they hold, without it.
    @MainActor
    func testTheSearchIsAScreenOfItsOwn() {
        var app = launch("movies")
        let card = element("catalog-card-fixture-movie-1", in: app)
        let field = app.textFields.matching(identifier: "desk-search").firstMatch
        let back = element("desk-back", in: app)
        let kinds = ["live", "movie", "series"].map { element("search-kind-\($0)", in: app) }
        let empty = element("search-empty-state", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        XCTAssertFalse(kinds[1].exists, "The films have a column of their own.")

        XCUIRemote.shared.press(.down)
        walkDock(to: element("navigation-search", in: app), in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("hasFocus == true", on: field, in: app)
        for row in kinds { XCTAssertTrue(appears(row), "\(row) stands in the column of the search.") }
        XCTAssertTrue(appears(empty))
        XCTAssertTrue(empty.label.contains("Que cherchez-vous"), empty.label)
        assertCondition("exists == false", on: card, in: app)
        retainScreenshot("search-01-a-screen-of-its-own", in: app)

        // Menu: the films again, on the title that was left. From the field
        // it leaves at once; from the bar it would first stop on Back.
        XCUIRemote.shared.press(.menu)
        let deadline = Date().addingTimeInterval(10 * Self.patience)
        while Date() < deadline, !card.exists, !holdsFocus(back) { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        if holdsFocus(back) { XCUIRemote.shared.press(.menu) }
        assertFocus(card, logical: "fixture-movie-1", in: app)
        assertCondition("exists == false", on: kinds[1], in: app)
        retainScreenshot("search-02-back-to-the-films", in: app)
        app.terminate()

        // A query found a film: Left enters the column on where it looked.
        app = launch("search-result")
        defer { app.terminate() }
        let found = element("catalog-card-fixture-movie-0", in: app)
        let search = app.textFields.matching(identifier: "desk-search").firstMatch
        let films = element("search-kind-movie", in: app)
        assertFocus(found, logical: "fixture-movie-0", in: app)
        XCTAssertTrue(appears(element("search-clear", in: app)))
        XCUIRemote.shared.press(.left)
        assertFocus(films, logical: "search-kind-movie", in: app)
        retainScreenshot("search-03-its-column", in: app)
        // Right: back to the film it found, which the column was left for.
        XCUIRemote.shared.press(.right)
        assertFocus(found, logical: "fixture-movie-0", in: app)

        // The series from the bar: their own column, and no query.
        XCUIRemote.shared.press(.down)
        walkDock(to: element("navigation-tab-series", in: app), in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: films, in: app)
        assertCondition(NSPredicate(format: "NOT (value CONTAINS[c] %@)", "dunes"), on: search, in: app)
        retainScreenshot("search-04-the-series-without-the-query", in: app)
        // The films too: all of them, not what the query found.
        XCUIRemote.shared.press(.down)
        walkDock(to: element("navigation-tab-movie", in: app), in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(appears(element("catalog-card-fixture-movie-1", in: app)), "The films show all they hold.")
        assertCondition(NSPredicate(format: "NOT (value CONTAINS[c] %@)", "dunes"), on: search, in: app)
        assertCondition("exists == false", on: films, in: app)
        print("PASS: TV_REMOTE Recherche in the bar opened a screen of its own, its field holding the remote and its column listing where to look; Menu went back to the films on the title that was left; Left from a result entered the column on where it looked; the series and the films showed all they hold, without the query")
    }

    /// The shortcuts of a series: a season opens the fiche of the series on
    /// that season, an episode on that episode, the series its shelf of
    /// seasons. Each time from the films, another section.
    @MainActor
    func testDockShortcutsOfASeriesOpenItsSeasonsAndItsEpisodes() {
        let app = launch("dock")
        defer { app.terminate() }
        func shortcut(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                             "navigation-dock-item-", label)).firstMatch
        }
        let card = element("catalog-card-fixture-movie-1", in: app)
        let series = shortcut("Les saisons")
        let season = shortcut("Les saisons · Saison 3")
        let episode = shortcut("Les saisons · S12 E15")
        let play = element("media-detail-play", in: app)
        let sleeve = element("catalog-card-fixture-series", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        XCTAssertTrue(series.exists && season.exists && episode.exists,
                      "The dock must show the series, its season and its episode that the fixture keeps.")

        // A season: the fiche of the series, on that season.
        XCUIRemote.shared.press(.down)
        walkDock(to: season, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: play, in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(element("media-detail-episode-fixture-series-s3-e1", in: app), in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(element("media-detail-season-3", in: app), in: app)
        retainScreenshot("dock-series-01-season", in: app)
        // Menu: the shelf of the seasons, on that one; then the series.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(element("season-sleeve-3", in: app), logical: "season-3", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(sleeve, logical: "fixture-series", in: app)
        print("PASS: TV_REMOTE dock shortcut of a season opened the fiche of its series on that season")

        // An episode: the fiche on its season and on it.
        XCUIRemote.shared.press(.down)
        walkDock(to: episode, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: play, in: app)
        assertCondition(NSPredicate(format: "label CONTAINS %@", "E15"), on: play, in: app)
        XCUIRemote.shared.press(.left)
        assertFocus(element("media-detail-episode-fixture-series-s12-e15", in: app), in: app)
        retainScreenshot("dock-series-02-episode", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(element("season-sleeve-12", in: app), logical: "season-12", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(sleeve, logical: "fixture-series", in: app)
        print("PASS: TV_REMOTE dock shortcut of an episode opened the fiche of its series on that episode")

        // The series: its shelf of seasons, on the first one.
        XCUIRemote.shared.press(.down)
        walkDock(to: series, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(element("season-sleeve-1", in: app), logical: "season-1", in: app)
        XCTAssertFalse(play.exists)
        retainScreenshot("dock-series-03-seasons", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(sleeve, logical: "fixture-series", in: app)
        print("PASS: TV_REMOTE dock shortcut of a series opened its shelf of seasons")
    }

    /// The dock as a user fills it: shortcuts, a video in progress, and a
    /// list of favourites as a folder. The remote walks all of it, opens the
    /// folder as a fan and closes it, opens a film from its shortcut, and
    /// takes a shortcut out of the dock from the lists of its title.
    @MainActor
    func testTheDockKeepsShortcutsAndOpensItsFolder() {
        let app = launch("dock")
        defer { app.terminate() }
        let card = element("catalog-card-fixture-movie-1", in: app)
        let folder = element("navigation-dock-stack-default-movie", in: app)
        let film = element("navigation-dock-item-shortcuts-fixture-movie-1", in: app)
        let channel = element("navigation-dock-item-shortcuts-fixture-live-0", in: app)
        let resume = element("navigation-dock-resume-fixture-movie-2", in: app)
        let first = element("dock-fan-fixture-movie-0", in: app)
        let second = element("dock-fan-fixture-movie-2", in: app)
        let all = element("dock-fan-all", in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        XCTAssertTrue(channel.exists && film.exists && resume.exists && folder.exists,
                      "The dock must show the shortcuts, the film in progress and the folder that the fixture keeps.")
        XCTAssertEqual(resume.label, "Reprendre « Les lumières du port »")

        // Down: the dock, under the films. Right walks it to its last icon.
        XCUIRemote.shared.press(.down)
        assertCondition("hasFocus == false", on: card, in: app)
        move(.right, to: folder, maximumPresses: 16, in: app)
        assertFocus(folder, logical: "dock-stack-default-movie", in: app)
        retainScreenshot("dock-01-folder-focused", in: app)

        // OK opens the folder as a fan, on its first title; Up walks them.
        XCUIRemote.shared.press(.select)
        assertFocus(first, logical: "dock-fan-fixture-movie-0", in: app)
        XCTAssertEqual(folder.value as? String, "Ouvert")
        retainScreenshot("dock-02-folder-open", in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(second, logical: "dock-fan-fixture-movie-2", in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(all, logical: "dock-fan-all", in: app)
        // Nothing beside the fan takes the remote while it is open.
        XCUIRemote.shared.press(.left)
        assertFocus(all, logical: "dock-fan-all", in: app)
        // Menu closes it, back on its icon.
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: first, in: app)
        assertFocus(folder, logical: "dock-stack-default-movie", in: app)
        retainScreenshot("dock-03-folder-closed", in: app)
        print("PASS: TV_REMOTE dock folder opened as a fan, walked, and closed by Menu on its icon")

        // Down from its first title returns to the icon; another icon closes it.
        XCUIRemote.shared.press(.select)
        assertFocus(first, logical: "dock-fan-fixture-movie-0", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(folder, logical: "dock-stack-default-movie", in: app)
        XCUIRemote.shared.press(.left)
        assertCondition("exists == false", on: first, in: app)
        assertCondition("hasFocus == false", on: folder, in: app)

        // The shortcut of a film opens its fiche; Menu puts the sleeve back.
        move(.left, to: film, maximumPresses: 14, in: app)
        assertFocus(film, logical: "dock-item-shortcuts-fixture-movie-1", in: app)
        // Under a screen, the bar names the title in full above its icon.
        XCTAssertTrue(appears(element("flux-dock-bubble", in: app)), "The dock names the shortcut above it.")
        XCUIRemote.shared.press(.select)
        let play = element("media-detail-play", in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: play, in: app)
        retainScreenshot("dock-04-film-from-shortcut", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        print("PASS: TV_REMOTE dock shortcut opened the fiche of its film, and Menu returned to its sleeve")

        // From another section the shortcut shows the films first, then
        // the fiche: Menu puts the sleeve back among them.
        let live = element("navigation-tab-live", in: app)
        let channelRow = element("live-channel-fixture-live-0", in: app)
        XCUIRemote.shared.press(.down)
        walkDock(to: live, in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(channelRow, logical: "fixture-live-0", in: app)
        // Three channels, then the dock under them.
        for _ in 0..<4 { XCUIRemote.shared.press(.down) }
        assertCondition("hasFocus == false", on: channelRow, in: app)
        walkDock(to: film, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: play, in: app)
        XCTAssertFalse(channelRow.exists, "The fiche of a film stands over the films, not over the channels.")
        retainScreenshot("dock-04b-film-from-another-section", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: play, in: app)
        assertFocus(card, logical: "fixture-movie-1", in: app)
        print("PASS: TV_REMOTE dock shortcut of a film opened from the television showed its fiche over the films")

        // The shortcut of a channel shows the television and plays the
        // channel: its picture takes the remote, under its banner, and
        // Menu returns to its row in the list.
        XCUIRemote.shared.press(.down)
        walkDock(to: channel, in: app)
        XCUIRemote.shared.press(.select)
        // Its banner first: it stays four seconds.
        XCTAssertTrue(appears(element("player-banner", in: app)))
        retainScreenshot("dock-04c-channel-from-shortcut", in: app)
        let picture = element("player-catcher", in: app)
        XCTAssertTrue(picture.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: picture, in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: picture, in: app)
        assertFocus(channelRow, logical: "fixture-live-0", in: app)
        print("PASS: TV_REMOTE dock shortcut of a channel opened from the films played it, and Menu returned to its row")

        // Held, OK opens the lists of the title, where the dock keeps it.
        for _ in 0..<4 { XCUIRemote.shared.press(.down) }
        assertCondition("hasFocus == false", on: channelRow, in: app)
        walkDock(to: film, in: app)
        assertFocus(film, logical: "dock-item-shortcuts-fixture-movie-1", in: app)
        XCUIRemote.shared.press(.select, forDuration: 1.2)
        let list = element("favorite-list-0", in: app)
        let kept = element("favorite-dock-0", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        assertCondition("hasFocus == true", on: list, in: app)
        XCTAssertEqual(kept.value as? String, "Sélectionnée")
        retainScreenshot("dock-05-lists-of-a-shortcut", in: app)
        // Unchecked and saved, it leaves the dock; the remote stays in the bar.
        move(.down, to: kept, maximumPresses: 6, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("value == 'Non sélectionnée'", on: kept, in: app)
        let save = element("favorite-save", in: app)
        moveToSave(save, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: list, in: app)
        assertCondition("exists == false", on: film, in: app)
        assertFocus(live, logical: "tab-live", in: app)
        XCTAssertTrue(channel.exists && folder.exists)
        retainScreenshot("dock-06-shortcut-removed", in: app)
        print("PASS: TV_REMOTE held OK opened the lists of a shortcut; unchecked and saved, it left the dock")
    }

    private static let dockKeys = ["navigation-tab-live", "navigation-tab-movie", "navigation-tab-series",
                                   "navigation-search", "navigation-tab-favorites", "navigation-settings"]

    /// A move of the remote rebuilds what it concerns, and nothing else.
    /// The screen keeps its state in one place, and any change of that
    /// state rebuilds all of it: one press used to rebuild the screen five
    /// times, with eighty-nine sleeves, fifty keys and forty rows of the
    /// column. An Apple TV HD spent most of a second on it. The parts of
    /// the catalogue now say what they are drawn from, and the controls
    /// read the focus themselves; this flow counts what a press rebuilds,
    /// in catalogues of the size of a real subscription.
    @MainActor
    func testAMoveOfTheRemoteRebuildsOnlyWhatItConcerns() {
        func counters(in app: XCUIApplication) -> [String: Int] {
            // The readout refreshes five times a second.
            Thread.sleep(forTimeInterval: 0.7)
            let text = element("flux-probe", in: app).value as? String ?? ""
            var result: [String: Int] = [:]
            for pair in text.split(separator: " ") {
                let parts = pair.split(separator: "=")
                if parts.count == 2, let count = Int(parts[1]) { result[String(parts[0])] = count }
            }
            return result
        }
        func rebuilt(_ name: String, _ before: [String: Int], _ after: [String: Int]) -> Int {
            after[name, default: 0] - before[name, default: 0]
        }

        // Along a row of 58 093 films: three presses.
        var app = launch("movies-many", environment: ["FLUX_UI_PROBE": "1"])
        assertFocus(element("catalog-card-fixture-movie-1", in: app), logical: "fixture-movie-1", in: app)
        var before = counters(in: app)
        XCTAssertGreaterThan(before["screen", default: 0], 0, "The readout of the counters is missing.")
        for _ in 0..<3 { XCUIRemote.shared.press(.right) }
        assertFocus(element("catalog-card-fixture-movie-4", in: app), logical: "fixture-movie-4", in: app)
        var after = counters(in: app)
        print("TV_REMOTE rebuilt along a row: \(after.keys.sorted().map { "\($0)=\(rebuilt($0, before, after))" }.joined(separator: " "))")
        // One update of the screen for a press; twice that is still far
        // from the five it used to take.
        XCTAssertLessThanOrEqual(rebuilt("screen", before, after), 6)
        // No sleeve is drawn again: the two a press concerns show the
        // focus they read themselves.
        XCTAssertEqual(rebuilt("sleeve", before, after), 0)
        XCTAssertEqual(rebuilt("band", before, after), 0)
        XCTAssertEqual(rebuilt("bar", before, after), 0)
        app.terminate()

        // Down a list of 24 665 channels: three presses, which bring at
        // most three new rows on screen.
        app = launch("live-many", environment: ["FLUX_UI_PROBE": "1"])
        defer { app.terminate() }
        assertFocus(element("live-channel-fixture-live-0", in: app), logical: "fixture-live-0", in: app)
        before = counters(in: app)
        for _ in 0..<3 { XCUIRemote.shared.press(.down) }
        assertFocus(element("live-channel-fixture-live-3", in: app), logical: "fixture-live-3", in: app)
        after = counters(in: app)
        print("TV_REMOTE rebuilt down a list: \(after.keys.sorted().map { "\($0)=\(rebuilt($0, before, after))" }.joined(separator: " "))")
        XCTAssertLessThanOrEqual(rebuilt("screen", before, after), 6)
        XCTAssertLessThanOrEqual(rebuilt("channel", before, after), 4)
        XCTAssertEqual(rebuilt("band", before, after), 0)
        XCTAssertEqual(rebuilt("bar", before, after), 0)
        retainScreenshot("rebuild-01-down-a-large-list", in: app)
    }

    @MainActor
    private func assertOneHasFocus(_ controls: [XCUIElement], in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if controls.contains(where: { holdsFocus($0) }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        retainScreenshot("failure-none-focused", in: app)
        XCTFail("None of the \(controls.count) expected controls has the focus.", file: file, line: line)
    }

    /// How many times longer the screen keeps what leaves by itself: the
    /// commands of the player five seconds, the banner of a channel four,
    /// its list twelve. One here. A hosted machine answers three times more
    /// slowly, and once left a question seven seconds without an answer:
    /// the list was gone when the next key came. The run says so there
    /// (FLUX_UI_PATIENCE), the screen stretches those delays and the flows
    /// wait as much longer for what must leave.
    private static let patience: Double = {
        let asked = Double(ProcessInfo.processInfo.environment["FLUX_UI_PATIENCE"] ?? "") ?? 1
        return min(10, max(1, asked))
    }()
    /// Longer than the commands of the player stay.
    private static var pastTheCommands: UInt32 { UInt32((5 * patience + 2).rounded(.up)) }

    /// What a sweep of the pointer crossed, once it has reached `mark`: a
    /// bench has no thumb, the app moves the pointer itself.
    @MainActor
    private func pointerTrace(until mark: String, on state: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", mark), object: state)
        let waited = XCTWaiter.wait(for: [reached], timeout: 120 * Self.patience)
        let value = seen(state)?.value as? String ?? ""
        print("TV_REMOTE pointer: \(value)")
        XCTAssertEqual(waited, .completed, "The sweep of the pointer did not reach \(mark): \(value)", file: file, line: line)
        return value.components(separatedBy: "trace:").last?.components(separatedBy: ",") ?? []
    }

    @MainActor
    private func launch(_ scenario: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.m4d135.FluxIPTV.TVCatalogUISmoke")
        app.launchEnvironment["FLUX_UI_SCENARIO"] = scenario
        app.launchEnvironment["FLUX_UI_REMOTE_TESTING"] = "1"
        // "light": every flow on the dark surfaces and the immediate focus
        // that an Apple TV HD starts with.
        if let effects = ProcessInfo.processInfo.environment["FLUX_UI_EFFECTS"] { app.launchEnvironment["FLUX_UI_EFFECTS"] = effects }
        if Self.patience > 1 { app.launchEnvironment["FLUX_UI_PATIENCE"] = String(Self.patience) }
        for (name, value) in environment { app.launchEnvironment[name] = value }
        app.launch()
        XCTAssertTrue(appears(element("flux-catalog-logical-focus", in: app), timeout: 15))
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// What a control says of itself, read in one go; nil when it is not
    /// there. The commands of the player and the banner of a channel leave
    /// by themselves: asked for its name, then its focus, then its frame,
    /// a control may leave between two questions, and a question put to a
    /// control that is gone is recorded as a failure of its own. A hosted
    /// machine lost a flow to that, after everything it asserts had
    /// passed. One reading fails as a whole, and says so without failing
    /// the flow; XCTest looks twice more for a control that is gone, two
    /// seconds in all, hence the first question.
    @MainActor
    private func seen(_ control: XCUIElement) -> (any XCUIElementSnapshot)? {
        guard control.exists else { return nil }
        return try? control.snapshot()
    }

    @MainActor
    private func holdsFocus(_ control: XCUIElement) -> Bool { seen(control)?.hasFocus ?? false }

    /// A control that is there is seen at once. A wait of XCTest begins
    /// with a second of its own, whatever the machine, and what shows for
    /// four or five seconds cannot afford several of them.
    @MainActor
    private func appears(_ control: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        control.exists || control.waitForExistence(timeout: timeout)
    }

    /// `leavesByItself`: a command of the player, shown for five seconds.
    /// It is looked at for two seconds before the waits of XCTest, which
    /// take three of the five on any machine.
    @MainActor
    private func assertFocus(_ control: XCUIElement, logical: String? = nil, in app: XCUIApplication,
                             leavesByItself: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) {
        var state: (any XCUIElementSnapshot)?
        if leavesByItself {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if let now = seen(control), now.hasFocus { state = now; break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        if state == nil {
            XCTAssertTrue(control.waitForExistence(timeout: 10), file: file, line: line)
            assertCondition("hasFocus == true", on: control, in: app, file: file, line: line)
            state = seen(control)
        }
        if let logical {
            assertCondition(NSPredicate(format: "value == %@", logical),
                            on: element("flux-catalog-logical-focus", in: app), in: app, file: file, line: line)
        }
        // Told from one reading, and only if the control was still there
        // for it. What is asserted is above.
        if let state {
            print("TV_REMOTE focus: \(state.identifier), native=\(state.hasFocus), logical=\(logical ?? "picker-local"), frame=\(state.frame)")
        }
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
        let result = XCTWaiter.wait(for: [expectation], timeout: 10 * Self.patience)
        guard result != .completed else { return }
        // A control that has left the screen cannot be asked its name: the
        // question itself would be recorded as a second failure.
        let name = seen(control)?.identifier ?? "\(control)"
        retainScreenshot("failure-\(name)", in: app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "failed-remote-navigation-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertEqual(result, .completed, "\(name): \(predicate.predicateFormat)", file: file, line: line)
    }

    @MainActor
    private func move(_ direction: XCUIRemote.Button, to target: XCUIElement, maximumPresses: Int,
                      in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Each press synchronizes with XCTest's UI idleness. A bounded row walk
        // tolerates the native engine landing on either neighbour above a tile.
        for _ in 0..<maximumPresses {
            if holdsFocus(target) { return }
            XCUIRemote.shared.press(direction)
        }
        assertFocus(target, in: app, file: file, line: line)
    }

    /// Along the dock to one of its icons, whichever side of it the remote
    /// came down on: to the left as far as it goes, then to the right.
    @MainActor
    private func walkDock(to target: XCUIElement, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<18 where !holdsFocus(target) { XCUIRemote.shared.press(.left) }
        for _ in 0..<18 where !holdsFocus(target) { XCUIRemote.shared.press(.right) }
        assertFocus(target, in: app, file: file, line: line)
    }

    /// The foot of the lists of a title stands under its last row, the one
    /// that creates a folder of the dock, and is entered on Enregistrer.
    @MainActor
    private func moveToSave(_ save: XCUIElement, in app: XCUIApplication) {
        move(.down, to: element("favorite-dock-create-folder", in: app), maximumPresses: 9, in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(save, in: app)
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
