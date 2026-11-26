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
        XCUIRemote.shared.press(.right)
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

        // Menu from inside the list goes back at once, to the films and to
        // the title that was selected there.
        XCUIRemote.shared.press(.menu)
        assertFocus(film, logical: "fixture-movie-0", in: app)
        XCTAssertFalse(channel.exists)
        retainScreenshot("back-02-films", in: app)
        // Menu again: the television that was opened first, not the home screen.
        XCUIRemote.shared.press(.menu)
        assertFocus(channel, logical: "fixture-live-0", in: app)
        XCTAssertFalse(home.exists)
        // Then the home screen, where the path started.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        assertFocus(live, logical: "tab-live", in: app)
        retainScreenshot("back-03-home", in: app)
        print("PASS: TV_REMOTE each destination opened in its content, and Menu retraced television, films, television and the home screen, one screen at a press")
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
        sleep(7)
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
        sleep(7)
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

    @MainActor
    private func launch(_ scenario: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.m4d135.FluxIPTV.TVCatalogUISmoke")
        app.launchEnvironment["FLUX_UI_SCENARIO"] = scenario
        app.launchEnvironment["FLUX_UI_REMOTE_TESTING"] = "1"
        // "light": every flow on the dark surfaces and the immediate focus
        // that an Apple TV HD starts with.
        if let effects = ProcessInfo.processInfo.environment["FLUX_UI_EFFECTS"] { app.launchEnvironment["FLUX_UI_EFFECTS"] = effects }
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
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
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
    /// that creates a section of the dock, and is entered on Enregistrer.
    @MainActor
    private func moveToSave(_ save: XCUIElement, in app: XCUIApplication) {
        move(.down, to: element("favorite-dock-create", in: app), maximumPresses: 8, in: app)
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
