import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

/// `home` is the first screen of the desk: the destinations, in the middle
/// of the window. Back returns to it, screen after screen.
private enum FluxPage: Equatable { case home, catalogue, series, player, settings }

/// Settings page requested by the dock, a notice or the welcome screen. A new
/// revision reopens the page even when the settings are already on screen.
private struct DeskSettingsRequest: Equatable {
    var revision = UUID()
    var page: PlaybackSettingsView.Page?
    var sourceEditor: PlaybackSettingsView.SourceEditor?
}

/// A submitted search may still be filtering. Retain its browsing context, not
/// an item from the previous result set, until the current results are ready.
private struct CatalogFocusRequest: Equatable {
    let sourceID: UUID?
    let kind: IPTVMediaKind
    let query: String
    let group: String?
    let presetID: String?
    let resumeOnly: Bool
    let countryCode: String?
}

#if os(tvOS)
/// Restoration can finish filtering before its lazy grid cell is mounted or
/// the native focus engine has made its initial choice (often a search field).
private struct BrowseRestoreFocusRequest {
    let revision: UUID
    let context: CatalogFocusRequest
    let targetID: String
}
#endif

#if FLUX_CATALOG_UI_TESTING
struct CatalogSearchFocusSnapshot {
    let focusID: String?
    let nativeFocusID: String?
    let query: String
    let filtering: Bool
    let pending: Bool
    let heldItemID: String?
    /// True in the report that follows the last key of a scenario: a long
    /// path on a slow machine is not over after a delay chosen in advance.
    var keysPlayed = false
}

/// How many times longer the delays of the screen last under a remote flow
/// on a slow machine. The commands of the player stay five seconds, the
/// banner of a channel four, its list twelve; a hosted machine answers the
/// bench three times more slowly than a Mac, and now and then not at all
/// for several seconds: a flow written at the pace of a hand could not
/// always act within them there. One wherever nothing asks otherwise, and
/// the application never reads it.
enum FluxFixturePatience {
    static let factor: Double = {
        let asked = Double(ProcessInfo.processInfo.environment["FLUX_UI_PATIENCE"] ?? "") ?? 1
        return min(10, max(1, asked))
    }()
}
#endif

/// One living-room UI for Mac, iPhone, iPad and Apple TV. All actual tvOS navigation
/// uses the OS focus engine; the Mac simulator and gamepad use the shared focus grid.
///
/// The focus of the system is owned by `ContentView`, the window above this
/// screen: a view is rebuilt each time a focus it owns moves, and this one
/// holds the whole catalogue. Here that focus is a binding, written to send
/// the remote somewhere and read when something happens, never to draw.
struct FluxScreen: View, Equatable {
    let nativeFocus: FocusState<String?>.Binding
    /// Where the window tells this screen that the focus has moved.
    let focusRelay: FluxFocusRelay
    private var systemFocus: String? {
        get { nativeFocus.wrappedValue }
        nonmutating set { nativeFocus.wrappedValue = newValue }
    }
    /// Nothing the window hands over changes during its life: the screen
    /// is rebuilt by its own state alone.
    nonisolated static func == (left: FluxScreen, right: FluxScreen) -> Bool { true }
    @EnvironmentObject private var library: IPTVLibrary
    @EnvironmentObject private var playback: PlaybackController
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    #if (os(macOS) || os(tvOS)) && !FLUX_CATALOG_UI_TESTING
    @State private var page: FluxPage = .home
    #else
    @State private var page: FluxPage = .catalogue
    #endif
    private var group: String? {
        get { library.group }
        nonmutating set { library.group = newValue }
    }
    private var continueOnly: Bool {
        get { library.continueOnly }
        nonmutating set { library.continueOnly = newValue }
    }
    @State private var addingSource = false
    @State private var editingSource: IPTVSource?
    @State private var presetEditor: PresetEditor?
    @State private var deletingPreset: FavoritePreset?
    @State private var itemOptions: IPTVItem?
    @State private var favoriteFeedback: String?
    @State private var favoriteFeedbackTask: Task<Void, Never>?
    @State private var entranceItem: IPTVItem?
    @State private var entranceExpanded = false
    @State private var entranceTask: Task<Void, Never>?
    @State private var showingSources = false
    @State private var showingLists = false
    @State private var showingSearch = false
    @State private var showingEngines = false
    @State private var diagnosticSettings = false
    @State private var showRemote = false
    @AppStorage("fluxiptv.remoteAppearance") private var remoteAppearance: RemoteAppearance = .black
    @AppStorage(FluxAppearance.glassKey) private var richGlass = FluxAppearance.richDefault
    @AppStorage(FluxAppearance.motionKey) private var focusMotion = FluxAppearance.motionDefault
    @AppStorage(FluxAppearance.densityKey) private var density = "cinema"
    @AppStorage(ClubInterfaceProfile.storageKey) private var clubProfile: ClubInterfaceProfile = .neoVideoClub
    @State private var remoteNavigationActive = false
    @State private var showingGroups = false
    @State private var showingCountries = false
    @State private var showingNavigationMenu = false
    private var groupSearch: String {
        get { library.groupSearch }
        nonmutating set { library.groupSearch = newValue }
    }
    @State private var liveSidebarVisible = false
    @State private var browserHeight: CGFloat = 900
    @FocusState private var liveGroupSearchFocus: Bool
    /// Kept, not watched: each change of the preview would rebuild the whole
    /// screen. The picture and the key of its sound watch it themselves.
    @State private var livePreview = LiveTVPreviewController()
    @AppStorage(LiveTVPreviewDelay.storageKey) private var livePreviewDelay: LiveTVPreviewDelay = LiveTVPreviewDelay.platformDefault
    @AppStorage(LiveTVPreviewDelay.automaticKey) private var automaticLivePreview = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var series: IPTVItem?
    @State private var seasons: [IPTVSeason] = []
    @State private var seasonNumber: Int?
    @State private var episodesLoading = false
    @State private var episodesFailed = false
    @State private var seriesRequest = UUID()
    @State private var seriesTask: Task<Void, Never>?
    @State private var columns = 5
    @State private var compactChrome = false
    @State private var focusID: String? = "tab-live"
    @State private var previewID: String?
    @State private var previewItem: IPTVItem?
    @State private var heldItem: IPTVItem?
    @State private var heldDetails = IPTVDetails()
    @State private var caseExpanded = false
    @State private var caseToken = UUID()
    @State private var caseRemoteEvent: MediaDetailRemoteEvent?
    @State private var heldSeasonNumber: Int?
    @State private var heldEpisodeID: String?
    private var catalogPage: Int {
        get { library.catalogPage }
        nonmutating set { library.catalogPage = newValue }
    }
    @State private var pendingBrowseRestore = true
    @State private var browseRestoreTask: Task<Void, Never>?
    #if os(tvOS)
    @State private var pendingBrowseFocus: BrowseRestoreFocusRequest?
    @State private var mountedBrowseFocusTargets: Set<String> = []
    @State private var browserHasEnteredFocus = false
    #endif
    @State private var resumeSlice = CatalogSlice()
    @State private var caseDetailTask: Task<Void, Never>?
    @State private var caseTransitionTask: Task<Void, Never>?
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.tvKey) private var tvTheme: VideoClubTheme = .neo90
    private var theme: VideoClubTheme { theme(for: library.contentKind) }
    private var environment: MediaEnvironment { MediaEnvironment(kind: library.contentKind) }
    private func theme(for kind: IPTVMediaKind) -> VideoClubTheme {
        switch kind { case .movie: cinemaTheme; case .series: seriesTheme; case .live: tvTheme }
    }
    private var themeAccent:Color {let p=theme.palette.accent;return Color(red:p.x,green:p.y,blue:p.z)}
    @State private var zapBanner = false
    @State private var zapToken = UUID()
    /// The channel was changed from the bare picture: the picture stays bare.
    /// Only the banner tells what the stream does, until the commands are
    /// asked for: Up and Down go on changing channel.
    @State private var zapSurfing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocus: Bool
    @State private var pendingCatalogFocus: CatalogFocusRequest?
    @State private var cinema = false
    @State private var cinemaControls = true
    @State private var playerControlsTask: Task<Void, Never>?
    @State private var hoveredPlayerControls: Set<String> = []
    /// Key of the bar under the pointer.
    @State private var hoveredPlayerButton: String?
    /// Languages of the media on screen, shown in place of the bar.
    @State private var playerTracks = false
    @State private var playerWidth: CGFloat = 900
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var wasFullscreen = false
    @State private var cinemaWindowNumber: Int?
    @StateObject private var remoteInput = RemoteInputBridge()
    // Desk layout: dock, navigation column and panels drawn inside the window.
    @AppStorage(FluxDockPosition.storageKey) private var dockPosition: FluxDockPosition = .defaultValue
    @AppStorage(FluxDockItem.orderKey) private var dockOrder = ""
    @State private var favoritesMode = false
    @State private var sidebarCountries = false
    @State private var dockReturnFocus: String?
    @State private var settingsRequest = DeskSettingsRequest()
    @State private var deskPreviewWidth: CGFloat = 520
    @State private var deskWidth: CGFloat = 0
    /// Screens opened since the home screen; Back walks them in reverse.
    @State private var deskHistory = FluxNavigationHistory<FluxDockItem>()
    /// Icon of the bar of the home screen that the pointer is on.
    @State private var homeHover: String?
    /// The folder of the dock that is open above it, by its identifier.
    @State private var dockFan: String?
    /// What the lists of a title were asked for: an episode chosen in its
    /// fiche, or the shortcut of the dock whose icon was held.
    @State private var itemDockExtra: DockShortcut?
    @AppStorage(DockShelf.recentsKey) private var dockRecents = true
    @State private var homeKind: IPTVMediaKind?
    /// Settings asked for during playback: glass panels above the picture.
    @State private var playerSettings: DeskSettingsRequest?
    /// Zones of the screen, shown by Back for a keyboard or a remote.
    @State private var zoneMode = false
    @State private var zoneFocus: DeskZone = .content
    /// Row of the navigation column that must receive the remote when the
    /// content of the column changes under it.
    @State private var sidebarFocusRequest: String?
    /// Row of the navigation column asked to take the remote when the column
    /// is entered from the catalogue, until that row has it.
    @State private var columnEntryRequest: String?
    /// When the Back of the bar was held down, for the release that follows.
    @State private var backHeldAt: Date?
    /// What scrolls the lists, for the requests of the focus.
    @State private var scrolls = FluxScrollHandles()
    #if os(tvOS)
    /// Control of the player that is being handed the remote, until it
    /// says it has it.
    @State private var remoteHold: String?
    #endif
    /// Back returns at once to the screen before (David, 26 November); the
    /// zones of the screen first is a setting of the Mac.
    @AppStorage(DeskZone.backKey) private var backShowsZones = false
    // Channel list over the picture, to change channel without leaving it.
    @State private var zapListVisible = false
    @State private var zapFocusID: String?
    @State private var zapKeyboard = false
    @State private var zapListTask: Task<Void, Never>?
    /// Channel of the list whose row is asked to take the remote.
    @State private var zapFocusRequest: String?
    /// Channel of the row that really has it, told by the row itself.
    @State private var zapNativeFocus: String?
    /// The key Chaînes opened the list: its commands return when it closes.
    @State private var zapOpenedFromKey = false
    @State private var keyboardPointer: CGPoint?
    @State private var newListKind: IPTVMediaKind?
    @State private var newListName = ""
    @State private var renamingList = false
    @State private var confirmingListDeletion = false
    @State private var listNameInvalid = false
    @FocusState private var listNameFocus: Bool
    /// The key of a message of the library, on a television.
    @FocusState private var noticeFocus: Bool
    /// Shared by a sleeve of the catalogue and the case of its fiche.
    @Namespace private var caseNamespace

    #if FLUX_CATALOG_UI_TESTING
    private var fixtureSearchSubmission: String?
    private var fixtureSearchObservation: ((CatalogSearchFocusSnapshot) -> Void)?
    private var fixtureRestoreBrowsing = false
    /// A capture has no stream: a room stands for the picture under the
    /// panels drawn above the player.
    private var fixturePictureStandIn = false
    /// Keys of a remote, sent once the screen is up.
    private var fixtureActions: [RemoteAction] = []
    /// A capture of the commands keeps them on a media that plays.
    private var fixtureHoldsControls = false
    /// A capture plays nothing: the channel list of the player is drawn as
    /// if the selected channel were on screen.
    private var fixtureZapList = false
    /// Seed only the initial selection; layout, controls and artwork remain the
    /// same production views used by the application.
    init(nativeFocus: FocusState<String?>.Binding, focusRelay: FluxFocusRelay, fixtureSelection: IPTVItem? = nil, fixtureSeasons: [IPTVSeason] = [], fixtureOpenSeason: Int? = nil, fixtureEpisodeID: String? = nil, fixtureOpenItem: Bool = false, fixtureSearchSubmission: String? = nil, fixtureSearchObservation: ((CatalogSearchFocusSnapshot) -> Void)? = nil, fixtureOpenCountries: Bool = false, fixtureRestoreBrowsing: Bool = false, fixtureSettingsPage: PlaybackSettingsView.Page? = nil, fixtureFavorites: Bool = false, fixtureHome: Bool = false, fixturePlayerSettings: Bool = false, fixtureZone: DeskZone? = nil, fixtureActions: [RemoteAction] = [], fixtureZapList: Bool = false, fixtureAddSource: Bool = false, fixtureLists: Bool = false,
         fixturePlayer: Bool = false, fixtureHoldsControls: Bool = false, fixtureTracksPanel: Bool = false,
         fixtureBanner: Bool = false) {
        self.nativeFocus = nativeFocus
        self.focusRelay = focusRelay
        self.fixtureActions = fixtureActions
        self.fixtureHoldsControls = fixtureHoldsControls
        if fixturePlayer {
            fixturePictureStandIn = true
            _page = State(initialValue: .player)
            _playerTracks = State(initialValue: fixtureTracksPanel)
        }
        _addingSource = State(initialValue: fixtureAddSource)
        if fixtureLists { _itemOptions = State(initialValue: fixtureSelection) }
        if fixtureZapList {
            self.fixtureZapList = true
            fixturePictureStandIn = true
            _page = State(initialValue: .player)
            _zapListVisible = State(initialValue: true)
            _zapKeyboard = State(initialValue: true)
            _zapFocusID = State(initialValue: fixtureSelection?.id)
        }
        if fixtureHome { _page = State(initialValue: .home) }
        if let fixtureZone {
            _zoneMode = State(initialValue: true)
            _zoneFocus = State(initialValue: fixtureZone)
        }
        if fixturePlayerSettings {
            _page = State(initialValue: .player)
            _playerSettings = State(initialValue: DeskSettingsRequest())
            fixturePictureStandIn = true
        }
        if let fixtureSettingsPage {
            _page = State(initialValue: .settings)
            _settingsRequest = State(initialValue: DeskSettingsRequest(page: fixtureSettingsPage))
        }
        _favoritesMode = State(initialValue: fixtureFavorites)
        self.fixtureSearchSubmission = fixtureSearchSubmission
        self.fixtureSearchObservation = fixtureSearchObservation
        self.fixtureRestoreBrowsing = fixtureRestoreBrowsing
        _pendingBrowseRestore = State(initialValue: fixtureRestoreBrowsing)
        _showingSearch = State(initialValue: fixtureSearchSubmission != nil)
        #if os(macOS) || os(tvOS)
        // The desk lists countries and languages in its navigation column.
        _sidebarCountries = State(initialValue: fixtureOpenCountries)
        #else
        _showingCountries = State(initialValue: fixtureOpenCountries)
        #endif
        _previewID = State(initialValue: fixtureSelection?.id)
        _previewItem = State(initialValue: fixtureSelection)
        if fixtureBanner {
            // The bare picture just after a change of channel: its banner alone.
            fixturePictureStandIn = true
            _page = State(initialValue: .player)
            _cinemaControls = State(initialValue: false)
            _zapSurfing = State(initialValue: true)
            _zapBanner = State(initialValue: true)
        }
        _focusID = State(initialValue: fixtureBanner ? "cinema-controls" : fixturePlayer ? "playpause" : fixtureSelection?.id ?? "tab-live")
        if let fixtureSelection, !fixtureSelection.isSeriesCollection, fixtureOpenItem {
            _heldItem = State(initialValue: fixtureSelection)
            _heldDetails = State(initialValue: fixtureSelection.details)
            _caseExpanded = State(initialValue: true)
        }
        if let fixtureSelection,fixtureSelection.isSeriesCollection,let first=fixtureSeasons.first {
            _page=State(initialValue:.series)
            _series=State(initialValue:fixtureSelection)
            _seasons=State(initialValue:fixtureSeasons)
            _seasonNumber=State(initialValue:fixtureOpenSeason ?? first.number)
            _focusID=State(initialValue:"season-\(fixtureOpenSeason ?? first.number)")
            if let fixtureOpenSeason {
                _heldItem=State(initialValue:fixtureSelection)
                _heldDetails=State(initialValue:fixtureSelection.details)
                _heldSeasonNumber=State(initialValue:fixtureOpenSeason)
                _heldEpisodeID=State(initialValue:fixtureEpisodeID)
                _caseExpanded=State(initialValue:true)
            }
        }
    }
    #else
    init(nativeFocus: FocusState<String?>.Binding, focusRelay: FluxFocusRelay) {
        self.nativeFocus = nativeFocus
        self.focusRelay = focusRelay
    }
    #endif

    private var visibleSlice: CatalogSlice {
        continueOnly ? resumeSlice : library.catalogResults.slice(group:group)
    }
    private var catalogFocusContext: CatalogFocusRequest {
        CatalogFocusRequest(sourceID: library.selectedSourceID, kind: library.contentKind,
                            query: library.search, group: group,
                            presetID: library.selectedPresetID, resumeOnly: continueOnly,
                            countryCode: library.countryCode)
    }
    private var visible: [IPTVItem] { visibleSlice.items }
    private var groups: [String] { library.catalogResults.groups }
    private var catalogPageSize: Int {
        if usesDesk && library.contentKind == .live { return max(1, columns) * 40 }
        return max(library.contentKind == .live ? 1 : 2,columns)*12
    }
    private var catalogPageCount: Int { visibleSlice.pageCount(size:catalogPageSize) }
    private var displayedItems: ArraySlice<IPTVItem> { visibleSlice.window(page:catalogPage,size:catalogPageSize) }
    private var livePreviewAllowed: Bool {
        let browsing = page == .catalogue && library.contentKind == .live && heldItem == nil && entranceItem == nil
            && !modalOpen && scenePhase == .active
        #if os(tvOS)
        return browsing && focusID == previewItem?.id && !searchFocus
        #else
        return browsing
        #endif
    }
    private var livePreviewKey: String {
        "\(livePreviewAllowed)|\(previewItem?.id ?? "")|\(automaticLivePreview)|\(livePreviewDelay.rawValue)|\(library.selectedSourceID?.uuidString ?? "")"
    }
    private func revealCatalogItem(_ id: String) {
        if let p = visibleSlice.page(for:id,size:catalogPageSize), p != catalogPage { catalogPage = p }
    }
    private func rebuildResumeSlice() {
        guard continueOnly else { resumeSlice = CatalogSlice(); return }
        let ids = Set(playback.history.entries.values.lazy.filter(\.resumable).map(\.id))
        resumeSlice = library.catalogResults.slice(group:group).retaining(ids:ids)
    }
    private func resetCatalogWindow() {
        rebuildResumeSlice(); catalogPage = 0
    }
    private func changeCatalogPage(_ delta: Int) {
        let target = max(0,min(catalogPageCount-1,catalogPage+delta))
        guard target != catalogPage else { return }
        catalogPage = target
        // The key that turned the page keeps the selection, to turn the next
        // one at once: a large catalogue has hundreds of them. At an end of
        // the catalogue that key goes, and the other one takes the selection.
        if focusID == "page-next" { if target + 1 >= catalogPageCount { focusID = "page-prev" } }
        else if focusID == "page-prev" { if target == 0 { focusID = "page-next" } }
        else if let first = displayedItems.first { focusID = first.id }
        if let first = displayedItems.first { setPreview(first) }
    }
    private var modalOpen: Bool {
        addingSource || editingSource != nil || presetEditor != nil || deletingPreset != nil || itemOptions != nil || showingSources || showingLists || showingEngines || showingGroups || showingCountries || showingNavigationMenu || library.alertMessage != nil || playerSettings != nil
    }
    private var handlesCatalogueBack: Bool {
        guard page == .catalogue, let id = focusID else { return false }
        return !id.hasPrefix("tab-") && id != "search"
    }
    private var cardWidth: CGFloat {
        #if os(iOS)
        return sizeClass == .compact ? 124 : (library.contentKind == .live ? 174 : 150)
        #else
        // Seven portrait cards fit the 1080p TV safe width in the normal mode.
        // Keep their full footer inside the remaining height below the menus;
        // six columns still left a 552-point card in a roughly 520-point area.
        // A Mac shows the same sleeves at the size of its window.
        return Desk.tv(density == "compact" ? 210 : 240)
        #endif
    }
    private var currentClubItem: IPTVItem? {
        visibleSlice.item(id:previewID) ?? visibleSlice.item(id:focusID) ?? visible.first
    }
    private var showingAllCatalog: Bool {
        CatalogScope.isAll(group:group,search:library.search,presetID:library.selectedPresetID,resumeOnly:continueOnly,
                           countryCode: library.countryCode)
    }
    private func showAllCatalog() {
        library.countryCode = nil
        continueOnly=false;group=nil;library.selectedPresetID=nil;library.search=""
        groupSearch = ""
        clearPreview();resetCatalogWindow();focusID = library.contentKind == .live && !televisionLayout && !liveSidebarVisible ? "categories" : "group-all"
    }
    private func toggleResumeFilter() {
        if !continueOnly {library.selectedPresetID=nil}
        continueOnly.toggle()
    }
    private func toggleQuickFavorites() {
        continueOnly=false
        library.selectedPresetID = library.selectedPresetID == FavoritePresets.defaultID(for:library.contentKind) ? nil : FavoritePresets.defaultID(for:library.contentKind)
    }
    private var headerSpacing: CGFloat {
        #if os(tvOS)
        return 25
        #else
        return 12
        #endif
    }

    var body: some View {
        let _ = FluxProbe.hit("screen")
        // The actions of this screen read its state when they run.
        let _ = (focusRelay.moved = { id in nativeFocusMoved(to: id) })
        activeCatalogue
    }

    // Opaque subview boundaries keep each SwiftUI expression small enough for
    // all four Apple SDK builds without erasing view identity or adding layers.
    private var catalogueLayout: some View {
        GeometryReader { geometry in
            responsiveBrowser(geometry: geometry)
        }
        #if os(macOS)
        // The margins of a television around its picture: what fills the
        // screen there fills the window here, and the rest keeps inside.
        .safeAreaPadding(Desk.screenMargins)
        #endif
    }

    private func browserPane(reader: ScrollViewProxy) -> some View {
        ZStack {
            #if os(macOS) || os(tvOS)
            deskPane(reader: reader)
            #else
            if library.sources.isEmpty {
                firstSourceWelcome
            } else if let heldItem {
                heldOverlay(heldItem, reader: reader)
            } else {
                VStack(spacing: 0) {
                    if page != .player && !cinema {
                        if library.contentKind == .live && page == .catalogue { liveHeader }
                        else { header }
                    }
                    switch page {
                    case .catalogue, .settings, .home: catalogue
                    case .series: seriesDetail
                    case .player: playerPage
                    }
                }
                .opacity(entranceItem == nil ? 1 : 0)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "club-pane")
    }

    private func focusedBrowserPane(reader: ScrollViewProxy) -> some View {
        scrolls.pane = reader
        return browserPane(reader: reader)
        .onChange(of: page) { previous, destination in
            pendingCatalogFocus = nil
            if destination == .catalogue, pendingBrowseRestore { restoreBrowsingContext(); return }
            guard previous == .series,destination == .catalogue,let target=focusID,visibleSlice.item(id:target) != nil else{return}
            revealCatalogItem(target)
            Task { @MainActor in
                await Task.yield()
                guard page == .catalogue,heldItem == nil,focusID == target else{return}
                sendRemote(to: target, reader: reader) { page == .catalogue && heldItem == nil }
            }
        }
        .onChange(of: heldItem?.id) { _, id in
            if id != nil { pendingCatalogFocus = nil }
            if id == nil, page == .catalogue, pendingBrowseRestore { restoreBrowsingContext(); return }
            guard id == nil, page != .player, let target=focusID else{return}
            if page == .catalogue {revealCatalogItem(target)}
            Task { @MainActor in
                await Task.yield()
                guard heldItem == nil, page != .player, !searchFocus else{return}
                sendRemote(to: target, reader: reader) { heldItem == nil && page != .player && !searchFocus }
            }
        }
        .onChange(of: focusID) { previous, id in
            #if FLUX_CATALOG_UI_TESTING
            reportSearchFocusFixture()
            #endif
            guard let id, heldItem == nil else { return }
            // Native focus may move while a saved source is still loading.
            // Highlight that control without replacing the saved page/item;
            // restoration reveals and previews its own destination below.
            if page == .catalogue, !pendingBrowseRestore, let item = visibleSlice.item(id:id) {
                revealCatalogItem(id); setPreview(item)
            }
            #if os(tvOS)
            // Scroll lazy destinations into existence without mistaking an
            // early programmatic binding write for native focus readiness.
            if !pendingBrowseRestore || page != .catalogue { systemFocus = id }
            // A move along a row of sleeves leaves the list where it is:
            // asking it again would lay the whole grid out for nothing.
            let sameRow: Bool = {
                guard page == .catalogue, library.contentKind != .live, !pendingBrowseRestore,
                      let from = visibleSlice.index(of: previous), let to = visibleSlice.index(of: id) else { return false }
                return from / max(1, columns) == to / max(1, columns)
            }()
            if !sameRow { reader.scrollTo(id, anchor: .center) }
            #else
            if remoteNavigationActive && !searchFocus && !liveGroupSearchFocus {
                systemFocus = id
                reader.scrollTo(id, anchor: .center)
            }
            #endif
        }
        .onChange(of: catalogPage) { _, _ in
            guard page == .catalogue else { return }
            guard let id = heldItem?.id ?? focusID, displayedItems.contains(where: { $0.id == id }) else {
                // Turned from its keys, the page is read from its top.
                if let first = displayedItems.first { reader.scrollTo(first.id, anchor: .top) }
                return
            }
            Task { @MainActor in
                await Task.yield()
                reader.scrollTo(id,anchor:.center)
                if heldItem == nil && remoteNavigationActive && !pendingBrowseRestore { systemFocus=id }
            }
        }
        #if os(tvOS)
        .onChange(of: searchFocus) { _, focused in
            if focused, page == .catalogue, heldItem == nil, !modalOpen {
                browserHasEnteredFocus = true
                resolveBrowseRestoreFocus()
            }
        }
        .onChange(of: liveGroupSearchFocus) { _, focused in
            // The filter of the categories is the control nearest to the top
            // of the catalogue: it is reached from the column, not from a title.
            if focused, columnEntryRequest == nil, !pendingBrowseRestore, page == .catalogue, heldItem == nil, !modalOpen,
               visibleSlice.item(id: focusID) != nil { enterColumn() }
        }
        #endif
    }
    /// The focus of the system has moved: the window says so. The screen
    /// is not rebuilt for the move itself, only for what it changes here.
    private func nativeFocusMoved(to id: String?) {
        if page == .player, playerControlsVisible, id != nil, id != "cinema-controls" { revealPlayerControls() }
        #if os(tvOS)
        // A control of the player is being handed the remote: where the
        // system rests meanwhile is not a move of the user.
        if let held = remoteHold, id != held { return }
        // The remote left the open folder for another icon: it closes.
        // Only where the focus of the system is the remote itself: on a
        // Mac the keys and the pointer close it, and the focus of the
        // window, which follows them, may still be on its way.
        if let fan = dockFan, let id, id != fan, !id.hasPrefix(DockEntry.fanPrefix) { dockFan = nil }
        // The first native entry into a list that has just replaced the
        // content of the column is redirected to its selected row. The
        // request is consumed before the binding is written, so that
        // later moves never snap back.
        if let request = sidebarFocusRequest, let id, id == "countries-back" || id.hasPrefix("country-") {
            sidebarFocusRequest = nil
            focusID = request
            if id != request { systemFocus = request }
            return
        }
        // The navigation column is entered on the row of what is shown,
        // whatever stands at the height the remote came from.
        // Not while the catalogue hands the remote back to a title: the
        // system may then rest a moment on a control of the column.
        if let id, columnEntryRequest == nil, !pendingBrowseRestore, page == .catalogue, heldItem == nil, !modalOpen,
           deskSidebarIDs.contains(id), id != deskScopeID, visibleSlice.item(id: focusID) != nil {
            enterColumn()
            return
        }
        // And the catalogue is entered from the column on the title that
        // was left there, not on the one that faces the row of the column.
        if let id, columnEntryRequest == nil, !pendingBrowseRestore, page == .catalogue, heldItem == nil, !modalOpen,
           let from = focusID, deskSidebarIDs.contains(from), visibleSlice.item(id: id) != nil,
           let kept = library.browseItemID ?? previewID, kept != id, visibleSlice.item(id: kept) != nil {
            library.browseItemID = kept
            restoreBrowsingContext()
            return
        }
        if id != nil, page == .catalogue, heldItem == nil, !modalOpen {
            browserHasEnteredFocus = true
        }
        if pendingBrowseRestore, pendingBrowseFocus != nil,
           page == .catalogue, heldItem == nil, !modalOpen {
            resolveBrowseRestoreFocus()
            // The incoming ID may be a temporary header. Do not let it
            // overwrite the destination that was just handed off.
            return
        }
        // Waiting for source data alone must not freeze the drawn focus:
        // there may never be a handoff if loading ends in an error.
        #endif
        // Removing the old results can make the native focus engine pick
        // the first header button before our submitted-search destination
        // is mounted. Keep that temporary fallback from cancelling the
        // explicit handoff; acknowledge only the requested destination.
        if let request = pendingCatalogFocus, request == catalogFocusContext,
           !library.isFiltering, page == .catalogue, heldItem == nil,
           !modalOpen, !searchFocus, !liveGroupSearchFocus {
            let target = visible.first?.id ?? "tab-\(library.contentKind.rawValue)"
            guard id == target else { return }
            pendingCatalogFocus = nil
            #if FLUX_CATALOG_UI_TESTING
            reportSearchFocusFixture()
            #endif
        }
        if heldItem == nil, let id, focusID != id {
            #if os(tvOS)
            // A move of the remote is one update of the screen: what follows
            // the selection is set with it, not after it.
            if page == .catalogue, !pendingBrowseRestore, let item = visibleSlice.item(id: id) {
                revealCatalogItem(id); setPreview(item)
            }
            #endif
            focusID = id
        }
        #if FLUX_CATALOG_UI_TESTING
        reportSearchFocusFixture()
        #endif
    }
    #if os(tvOS)
    /// Gives the remote to the row of the column that stands for what is
    /// shown. That row may be far down a list that builds its rows as they
    /// come on screen: the column is brought to it, and it is asked again
    /// until it says it has the remote.
    private func enterColumn() {
        let id = deskScopeID
        guard deskSidebarIDs.contains(id) else { return }
        columnEntryRequest = id
        focusID = id
        Task { @MainActor in
            for _ in 0..<10 {
                await Task.yield()
                guard columnEntryRequest == id, page == .catalogue else { return }
                // A lazy list knows a row it has not built yet by its
                // category, not by the name given to the row.
                if id.hasPrefix("live-category-") { scrolls.column?.scrollTo(String(id.dropFirst("live-category-".count)), anchor: .center) }
                scrolls.column?.scrollTo(id, anchor: .center)
                // A request the system declined still reads as granted.
                liveGroupSearchFocus = false
                systemFocus = nil
                await Task.yield()
                guard columnEntryRequest == id else { return }
                systemFocus = id
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            columnEntryRequest = nil
        }
    }
    #endif

    private func browserChrome(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                focusedBrowserPane(reader: reader)
            }
            #if !os(tvOS)
            // The simulator is a real side panel, never covers catalogue/video.
            // On narrow mobile displays it is presented separately.
            if showRemote && page != .player && !cinema && width >= 800 {
                Divider().overlay(.white.opacity(0.08))
                remotePanel.padding(12)
            }
            #endif
        }
        .background { background }
        .overlay {
            if let entranceItem {
                PlaybackEntranceView(kind: entranceItem.kind, expanded: entranceExpanded)
            }
        }
        .overlay(alignment: .top) {
            if let favoriteFeedback {
                Label(favoriteFeedback, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).padding(14)
                    .fluxFrosted(radius: 18).padding(.top, 18)
                    .allowsHitTesting(false).transition(.opacity)
            }
        }
        .allowsHitTesting(entranceItem == nil)
    }

    private func responsiveBrowser(geometry: GeometryProxy) -> some View {
        browserChrome(width: geometry.size.width)
        .onAppear {
            browserHeight = geometry.size.height; updateColumns(geometry.size.width)
            if library.sources.isEmpty { focusID = "add-source"; systemFocus = "add-source" }
            #if os(macOS) || os(tvOS)
            // The home screen starts on the section used last.
            if showsHome { focusID = currentDockID; systemFocus = focusID }
            #endif
            #if FLUX_CATALOG_UI_TESTING
            if fixtureRestoreBrowsing { restoreBrowsingContext() }
            else if !library.sources.isEmpty, heldItem == nil {
                #if os(tvOS)
                // The player hands the remote over as it does when a stream opens.
                if page == .player { restorePlayerFocus() } else { systemFocus = focusID }
                #else
                systemFocus = focusID
                #endif
            }
            #if os(macOS) || os(tvOS)
            if sidebarCountries {
                // The list of countries opens on the one in use.
                focusID = library.countryCode.map { "country-\($0)" } ?? "country-all"
                systemFocus = focusID
            }
            if page == .settings {
                focusID = FluxDockItem.settings.focusID
                #if !os(tvOS)
                systemFocus = focusID
                #endif
            }
            // A folder of the dock, open as a press on its icon opens it.
            if let folder = UserDefaults.standard.string(forKey: "fluxiptv.fixture.dockFan") {
                Task { @MainActor in
                    // Once the window has given its first focus, which would close it.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard let entry = dockPlan(hero: showsHome).arrangement.entry(id: folder) else { return }
                    focusID = folder
                    dockActivate(entry)
                }
            }
            if page == .player, playerTracks {
                // The languages open on the audio in use.
                focusID = PlayerTracks.entry(audio: playback.audioTracks, subtitles: playback.subtitleTracks,
                                             canBeOff: playback.subtitlesCanBeOff)
                systemFocus = focusID
            }
            #endif
            #if os(tvOS)
            if fixtureZapList, let id = zapFocusID { systemFocus = "zap-\(id)" }
            #endif
            if !fixtureActions.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    #if os(macOS)
                    // A key window receives its first native focus a little
                    // after it appears, and that focus would overwrite the
                    // result of keys sent before it. Off screen it never comes.
                    if ProcessInfo.processInfo.environment["FLUX_CATALOG_UI_BACKGROUND"] != "1" {
                        for _ in 0..<14 where systemFocus == nil { try? await Task.sleep(nanoseconds: 50_000_000) }
                    }
                    #endif
                    for action in fixtureActions {
                        dispatch(action)
                        try? await Task.sleep(nanoseconds: 60_000_000)
                    }
                    // The bench reads the selection once it is told that
                    // every key has been played, however long that took.
                    reportSearchFocusFixture(keysPlayed: true)
                }
            }
            if let query = fixtureSearchSubmission {
                library.search = query
                focusFirstItem()
                // Exercise the same early OK as the remote, while the
                // debounced library still exposes the previous results.
                activateFocus()
                reportSearchFocusFixture()
            }
            #else
            restoreBrowsingContext()
            #endif
        }
        .onChange(of: geometry.size.height) { _, height in browserHeight = height; updateColumns(geometry.size.width) }
        .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
        .onChange(of: library.contentKind) { _, _ in
            liveGroupSearchFocus = false; clearPreview(); updateColumns(geometry.size.width)
            restoreBrowsingContext()
        }
        .onChange(of: showRemote) { _, _ in updateColumns(geometry.size.width) }
        .onChange(of: dockPosition) { _, _ in updateColumns(geometry.size.width) }
        .onChange(of: density) { _, _ in updateColumns(geometry.size.width) }
        .onChange(of: clubProfile) { _, _ in updateColumns(geometry.size.width) }
        #if !os(tvOS)
        #if os(iOS)
        .sheet(isPresented: Binding(get: { showRemote && page != .player && geometry.size.width < 800 }, set: { if !$0 { showRemote = false } })) {
            remotePanel.padding(18).presentationDetents([.large])
        }
        #endif
        #endif
    }

    private var platformCatalogue: some View {
        catalogueLayout
        #if os(macOS)
        // The desk needs room for its three columns beside the dock.
        .frame(minWidth: page == .player ? 320 : usesDesk ? 1040 : 860, minHeight: page == .player ? 180 : usesDesk ? 620 : 540)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { notice in
            if (notice.object as? NSWindow)?.windowNumber == cinemaWindowNumber { cinema = false; cinemaWindowNumber = nil }
        }
        #endif
        #if os(iOS)
        .statusBar(hidden: page == .player && cinema)
        .persistentSystemOverlays(page == .player && cinema ? .hidden : .automatic)
        #endif
    }

    private var commandCatalogue: some View {
        platformCatalogue
        #if os(tvOS)
        // The home screen is the first one: Menu leaves the application
        // there, and returns one step everywhere else.
        .fluxExit(heldItem != nil || deskCovered || dockFan != nil || (page != .home && !library.sources.isEmpty)) {
            #if os(tvOS)
            // Menu first closes what stands above the screen.
            if library.alertMessage != nil { library.alertMessage = nil; return }
            if itemOptions != nil { itemOptions = nil; return }
            #endif
            if heldItem != nil { dispatch(.back) } else { back() }
        }
        #if os(tvOS)
        // The screen takes the remote back where it was when a panel closes.
        .onChange(of: deskCovered) { _, covered in
            guard !covered else { return }
            if page == .player { restorePlayerFocus(); return }
            // An icon that the lists have just taken out of the dock is
            // no longer there to take the remote back.
            if let held = focusID, DockEntry.isShelfID(held), !dockPlan(hero: showsHome).ids.contains(held) { focusID = currentDockID }
            let id = focusID
            Task { @MainActor in
                await Task.yield()
                guard !deskCovered, focusID == id else { return }
                if let id { sendRemote(to: id) { !deskCovered } } else { systemFocus = id }
            }
        }
        #endif
        .onPlayPauseCommand { dispatch(.playPause) }
        #else
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape, .space, "f", .tab, "\u{19}"], phases: [.down, .repeat]) { press in
            #if os(macOS)
            if deskDismissWithKey(press.key) { return .handled }
            #endif
            guard !modalOpen else { return .ignored }
            if searchFocus {
                if press.key == .escape { showingSearch = false; searchFocus = false; return .handled }
                return .ignored
            }
            if liveGroupSearchFocus {
                if press.key == .escape { liveGroupSearchFocus = false; return .handled }
                return .ignored
            }
            #if os(macOS)
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            // Tab walks the zones of the screen; Shift-Tab walks them back.
            if press.key == .tab || press.key == "\u{19}" {
                return cycleZone(forward: press.key == .tab && !press.modifiers.contains(.shift)) ? .handled : .ignored
            }
            #else
            if press.key == .tab || press.key == "\u{19}" { return .ignored }
            #endif
            #if os(macOS)
            // Held, Back goes straight to the home screen.
            if press.key == .escape, press.phase == .repeat { holdBack(); return .handled }
            #endif
            #if os(macOS)
            // With Command an arrow goes straight to the zone on that side.
            if press.modifiers.contains(.command), press.phase == .down {
                let way: RemoteAction? = press.key == .upArrow ? .up : press.key == .downArrow ? .down
                    : press.key == .leftArrow ? .left : press.key == .rightArrow ? .right : nil
                if let way { return jumpZone(way) ? .handled : .ignored }
            }
            #endif
            if press.key == "f" && press.modifiers.contains([.command, .shift]) { dispatch(.fullscreen) }
            else if press.key == "f" && press.modifiers.contains(.command) { search() }
            else if press.key == .upArrow { dispatch(.up) }
            else if press.key == .downArrow { dispatch(.down) }
            else if press.key == .leftArrow { dispatch(.left) }
            else if press.key == .rightArrow { dispatch(.right) }
            else if press.key == .return { dispatch(.select) }
            else if press.key == .escape { dispatch(.back) }
            else if press.key == .space { dispatch(.playPause) }
            else { return .ignored }
            return .handled
        }
        .onAppear { remoteInput.connect { action in if !modalOpen && !searchFocus && !liveGroupSearchFocus { dispatch(action) } } }
        .onDisappear { remoteInput.disconnect() }
        #endif
    }

    private var sourceSheets: some View {
        commandCatalogue
        .fluxFormCover(isPresented: $addingSource) { AddSourceSheet(onSaved: { home() }).environmentObject(library) }
        .fluxFormCover(item: $editingSource) { source in AddSourceSheet(existing: source, onSaved: { home() }).environmentObject(library) }
        .sheet(item: $presetEditor) { editor in
            PresetNameSheet(editor: editor) { name in
                if let existing = editor.existing { return library.renamePreset(existing, name: name) }
                return library.createPreset(name: name, kind: editor.kind, initialItem: editor.initialItem)
            }
        }
    }

    private var catalogueSheets: some View {
        sourceSheets
        .sheet(isPresented: $showingSources) { sourcesPanel }
        .sheet(isPresented: $showingLists) { listsPanel }
        .sheet(isPresented: $showingGroups) { groupsPanel }
        .sheet(isPresented: $showingCountries) {
            LiveCountryPicker(countries: library.liveCountries, selection: library.countryCode,
                              select: selectLiveCountry, close: { showingCountries = false })
        }
        .sheet(isPresented: $showingEngines, onDismiss: { diagnosticSettings = false }) { enginesPanel }
        #if os(iOS)
        .sheet(item: $itemOptions) { item in itemPanel(item) }
        #endif
    }

    private var catalogueDialogs: some View {
        catalogueSheets
        .confirmationDialog("Navigation", isPresented: $showingNavigationMenu, titleVisibility: .visible) {
            Button("Sources") { showingSources = true }
            Button("Listes et favoris") { showingLists = true }
            #if !os(tvOS)
            Button(showRemote ? "Masquer la télécommande" : "Télécommande") { showRemote.toggle() }
            #endif
            Button("Réglages") { showingEngines = true }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer la liste ?", isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }), presenting: deletingPreset) { preset in
            Button("Supprimer « \(preset.name) »", role: .destructive) { library.deletePreset(preset); deletingPreset = nil; group = nil }
            Button("Annuler", role: .cancel) { deletingPreset = nil }
        }
        #if os(iOS)
        .alert("Flux IPTV", isPresented: Binding(get: { library.alertMessage != nil }, set: { if !$0 { library.alertMessage = nil } })) {
            Button("OK", role: .cancel) { library.alertMessage = nil }
        } message: { Text(library.alertMessage ?? "") }
        #endif
    }

    private var sourceObservedCatalogue: some View {
        catalogueDialogs
        .onChange(of: library.selectedSourceID) { _, _ in home(); clearPreview(); restoreBrowsingContext() }
        .onChange(of: library.browsingRevision) { _, _ in restoreBrowsingContext() }
        .onChange(of: library.isLoading) { _, loading in
            if !loading && pendingBrowseRestore { restoreBrowsingContext() }
        }
        .onChange(of: library.sources.isEmpty) { _, empty in
            if empty { home(); focusID = "add-source"; systemFocus = "add-source" }
        }
        .onChange(of: library.selectedPresetID) { _, _ in clearPreview() }
        .onChange(of: library.search) { _, _ in clearPreview() }
        .onChange(of: itemOptions?.id) { _, id in if id == nil { itemDockExtra = nil } }
    }

    private var resultsObservedCatalogue: some View {
        sourceObservedCatalogue
        .onChange(of: group) { _, _ in clearPreview(); rebuildResumeSlice() }
        .onChange(of: library.countryCode) { _, _ in clearPreview() }
        .onChange(of: library.catalogResults.revision) { _, _ in
            rebuildResumeSlice()
            if !library.isLoading && !library.isFiltering {
                catalogPage = min(catalogPage, catalogPageCount - 1)
                if pendingBrowseRestore { restoreBrowsingContext() }
            }
        }
        .onChange(of: catalogFocusContext) { _, context in
            if let request = pendingCatalogFocus, request != context { pendingCatalogFocus = nil }
            #if os(tvOS)
            if let request = pendingBrowseFocus, request.context != context { cancelBrowsingRestore() }
            #endif
            #if FLUX_CATALOG_UI_TESTING
            reportSearchFocusFixture()
            #endif
        }
        .onChange(of: library.isFiltering) { _, filtering in
            if !filtering {
                if pendingBrowseRestore { restoreBrowsingContext() }
                else { resolveCatalogFocus() }
            }
            #if FLUX_CATALOG_UI_TESTING
            reportSearchFocusFixture()
            #endif
        }
        .onChange(of: continueOnly) { _, _ in rebuildResumeSlice(); clearPreview() }
        .onChange(of: modalOpen) { _, open in
            if !open && pendingBrowseRestore { restoreBrowsingContext() }
        }
        .onChange(of: playback.history.entries) { _, _ in
            if continueOnly { rebuildResumeSlice(); catalogPage=min(catalogPage,catalogPageCount-1) }
        }
        .onChange(of: catalogPageSize) { _, _ in
            guard !library.isLoading, !library.isFiltering, !pendingBrowseRestore else { return }
            if let id=heldItem?.id ?? previewID { revealCatalogItem(id) }
            else { catalogPage=min(catalogPage,catalogPageCount-1) }
        }
    }

    private var activeCatalogue: some View {
        resultsObservedCatalogue
        .task(id: livePreviewKey) {
            guard !Task.isCancelled else { return }
            guard livePreviewAllowed, let item = previewItem, item.kind == .live else { livePreview.stop(); return }
            do {
                let urls = automaticLivePreview ? try library.playbackURLs(for: item) : []
                livePreview.schedule(id: item.id, urls: urls, delay: livePreviewDelay, enabled: automaticLivePreview)
            } catch { livePreview.markUnavailable(id: item.id) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { library.flushBrowsingPreferences() }
        }
        .onDisappear { caseDetailTask?.cancel(); caseTransitionTask?.cancel(); seriesTask?.cancel(); entranceTask?.cancel(); favoriteFeedbackTask?.cancel(); playerControlsTask?.cancel(); browseRestoreTask?.cancel(); livePreview.stop(); library.flushBrowsingPreferences() }
    }

    #if !os(tvOS)
    private var remotePanel: some View {
        RemotePad(appearance: $remoteAppearance, send: dispatch, caseSwipe: nil, close: {
            showRemote = false; remoteNavigationActive = false
        }, volume: playback.localVolume, muted: playback.muted)
    }
    #endif

    // Generated stage and artwork exist only in catalogue/series mode.
    // No decorative render passes or backdrop downloads behind video.
    private var background: some View {
        ZStack {
            if page == .player || (heldItem != nil && !usesDesk) {
                Color.black.ignoresSafeArea()
            } else if library.sources.isEmpty && !usesDesk {
                Color(red: 0.025, green: 0.035, blue: 0.065).ignoresSafeArea()
            } else {
                Group {
                    #if os(macOS) || os(tvOS)
                    if showsHome { homeRooms }
                    else {
                        FluxBackdrop(theme: theme)
                        ProceduralStage(kind: library.contentKind)
                    }
                    #else
                    FluxBackdrop(theme: theme)
                    ProceduralStage(kind: library.contentKind)
                    #endif
                }
                // A fiche or the settings float over the same room, out of focus.
                .blur(radius: livesBlur ? backdropBlur : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: caseExpanded)
                LinearGradient(colors:[.black.opacity(televisionLayout ? 0.52 : 0.12),.black.opacity(televisionLayout ? 0.72 : 0.52)],startPoint:.top,endPoint:.bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                // Without the blur a veil keeps the room behind what is read.
                if !livesBlur, backdropBlur > 0 {
                    Color.black.opacity(backdropBlur > 20 ? 0.46 : 0.24).ignoresSafeArea().allowsHitTesting(false)
                }
            }
        }.accessibilityHidden(true)
    }
    /// A whole screen put out of focus is blurred again for every picture
    /// that moves above it. The full effects do it; a slow Apple TV dims
    /// what is behind instead, which costs it nothing.
    private var livesBlur: Bool {
        #if os(tvOS)
        richGlass && FluxAppearance.systemGlass
        #else
        true
        #endif
    }
    private var backdropBlur: CGFloat {
        #if os(macOS) || os(tvOS)
        if (heldItem != nil && caseExpanded) || page == .settings { return 26 }
        // Behind the home screen the room is a wallpaper: its signs and
        // posters must not compete with the name of the destination.
        return showsHome ? 9 : 0
        #else
        return 0
        #endif
    }
    /// Hands the remote to a control this screen returns to. A title of the
    /// catalogue comes back with the update that asks for it, and a slow
    /// Apple TV has not built it yet: it is asked until it answers.
    private func sendRemote(to id: String, reader: ScrollViewProxy? = nil, while valid: @escaping () -> Bool) {
        reader?.scrollTo(id, anchor: .center)
        #if os(tvOS)
        if visibleSlice.item(id: id) != nil {
            holdRemote(on: id, inCatalogue: true, while: valid)
            return
        }
        // An icon of the dock says when it has the remote, too.
        if dockVisibleForRemote, FluxDockItem(focusID: id) != nil || DockEntry.isShelfID(id) {
            holdRemote(on: id, while: valid)
            return
        }
        #endif
        systemFocus = id
    }
    #if os(tvOS)
    /// The dock is on screen, at the foot of a section or in the middle of
    /// the home screen: one of its icons can be asked to take the remote.
    private var dockVisibleForRemote: Bool { page != .player && !cinema && entranceItem == nil }
    #endif
    private func setPreview(_ item: IPTVItem) {
        // A value written again would rebuild the screen for nothing.
        if !library.isLoading && !library.isFiltering && !pendingBrowseRestore, library.browseItemID != item.id {
            library.browseItemID = item.id
        }
        guard previewID != item.id else { return }
        if item.kind == .live {
            livePreview.stop()
            #if os(tvOS)
            // A remote runs down a list: the panel follows it at once. A
            // spring would redraw it for half a second after every press.
            previewID = item.id; previewItem = item
            #else
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
                previewID = item.id; previewItem = item
            }
            #endif
        } else { previewID = item.id; previewItem = item }
    }
    private func clearPreview() { previewID=nil; previewItem=nil }
    private func selectCard(_ item: IPTVItem) {
        // A successful long press presents a sheet before release; the same
        // release must never also fire the short-press playback action.
        guard !modalOpen, entranceItem == nil else { return }
        pointerSelect(item.id); setPreview(item); openItem(item)
    }
    private func chooseFavorites(_ item: IPTVItem, episode: IPTVItem? = nil) {
        pointerSelect(item.id)
        itemDockExtra = episode.map { DockShortcut(series: item, episode: $0) }
        itemOptions = item
    }
    /// What the dock can keep of a title, from where its lists are asked
    /// for: the title itself, the season being shown, an episode.
    private func dockChoices(for item: IPTVItem) -> [DockShortcut] {
        #if os(macOS) || os(tvOS)
        var result = [DockShortcut(item: item)]
        if item.isSeriesCollection {
            let season = heldItem?.id == item.id ? heldSeasonNumber : (page == .series && series?.id == item.id ? seasonNumber : nil)
            if let season { result.append(DockShortcut(series: item, season: season)) }
        }
        if let extra = itemDockExtra, extra.itemID == item.id, !result.contains(where: { $0.id == extra.id }) { result.append(extra) }
        return result
        #else
        return []
        #endif
    }
    private func favoritesSaved() {
        favoriteFeedbackTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { favoriteFeedback = "Listes enregistrées" }
        favoriteFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { favoriteFeedback = nil }
        }
    }
    private func requestCaseDetails(_ item: IPTVItem, token: UUID) {
        caseDetailTask?.cancel()
        caseDetailTask = Task { @MainActor in
            // A quick return cancels metadata loading before opening a connection.
            try? await Task.sleep(nanoseconds:160_000_000)
            guard !Task.isCancelled,caseToken==token else {return}
            let details=await library.details(for:item)
            guard !Task.isCancelled,caseToken==token,heldItem?.id==item.id else{return}
            heldDetails=details
        }
    }
    private func showCase(_ item: IPTVItem, season: Int? = nil, episodeID: String? = nil) {
        if item.isSeriesCollection && season == nil {loadSeries(item);return}
        caseTransitionTask?.cancel()
        let token=UUID(); caseToken=token
        searchFocus=false
        heldSeasonNumber=season;heldEpisodeID=episodeID
        heldDetails=item.details;caseExpanded=false;caseRemoteEvent=nil;heldItem=item
        caseTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,caseToken==token else {return}
            withAnimation(reduceMotion ? nil : usesDesk ? .spring(response: 0.5, dampingFraction: 0.84) : .easeOut(duration:0.20)) {caseExpanded=true}
        }
        requestCaseDetails(item,token:token)
    }
    private func putCaseBack(reader:ScrollViewProxy?=nil) {
        guard let item=heldItem else{return}
        caseDetailTask?.cancel();caseTransitionTask?.cancel()
        let token=UUID();caseToken=token
        let destination=heldSeasonNumber.map{"season-\($0)"} ?? visibleSlice.item(id:item.id)?.id ?? visible.first?.id ?? "group-all"
        if heldSeasonNumber == nil {revealCatalogItem(destination)}
        caseTransitionTask=Task { @MainActor in
            withAnimation(reduceMotion ? nil : usesDesk ? .spring(response: 0.38, dampingFraction: 0.9) : .easeOut(duration:0.16)) {caseExpanded=false}
            if !reduceMotion {try? await Task.sleep(nanoseconds: usesDesk ? 380_000_000 : 180_000_000)}
            guard !Task.isCancelled,caseToken==token else{return}
            focusID=destination;heldItem=nil;heldSeasonNumber=nil;heldEpisodeID=nil
            // Recreate only the catalogue being returned to, then restore its
            // selected poster. No hidden grid or neighboring cases stay mounted.
            await Task.yield()
            guard !Task.isCancelled,caseToken==token,heldItem == nil else{return}
            sendRemote(to: destination, reader: reader) { heldItem == nil && page != .player }
        }
    }
    private func dismissCaseImmediately() {caseDetailTask?.cancel();caseTransitionTask?.cancel();caseToken=UUID();heldItem=nil;heldSeasonNumber=nil;heldEpisodeID=nil;caseExpanded=false}
    private func playHeld() {
        guard let item=heldItem else{return}
        guard !item.isSeriesCollection else {return}
        dismissCaseImmediately(); series=nil;seasons=[];playItem(item)
    }
    private func playHeldEpisode(_ episode:IPTVItem, _ allSeasons:[IPTVSeason]) {
        guard let collection=heldItem,collection.isSeriesCollection else{return}
        series=collection;seasons=allSeasons;seasonNumber=episode.seasonNumber ?? heldSeasonNumber
        playItem(episode)
    }
    private func heldOverlay(_ item:IPTVItem,reader:ScrollViewProxy)->some View {
        MediaDetailPresentation(item:item,details:heldDetails,
            close:{putCaseBack(reader:reader)},play:{playHeld()},
            playEpisode:{playHeldEpisode($0,$1)},favorite:{chooseFavorites(item, episode: $0)},
            isFavorite:library.isFavorite(item),remoteEvent:caseRemoteEvent,
            initialSeasons:heldSeasonNumber == nil ? []:seasons,
            initialSeasonNumber:heldSeasonNumber,initialEpisodeID:heldEpisodeID,
            suspended:modalOpen,
            expanded: usesDesk ? caseExpanded : true, hero: caseHero(item),
            seasonChanged: { number in heldSeasonNumber = number; heldEpisodeID = nil; seasonNumber = number })
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .opacity(usesDesk || caseExpanded ? 1 : 0)
    }
    /// Identifier shared with the sleeve that opened this fiche.
    private func sleeveID(_ item: IPTVItem, season: Int? = nil) -> String {
        season.map { "sleeve-\(item.id)::season::\($0)" } ?? "sleeve-\(item.id)"
    }
    private func caseHero(_ item: IPTVItem) -> MediaDetailHero? {
        usesDesk ? MediaDetailHero(namespace: caseNamespace, id: sleeveID(item, season: heldSeasonNumber)) : nil
    }
    /// The sleeve leaves its shelf while its fiche is open.
    private func sleeveHeld(_ item: IPTVItem) -> Bool {
        usesDesk && heldItem?.id == item.id && heldSeasonNumber == nil
    }
    private var previewHero: some View {
        HStack(alignment:.center,spacing:18) {
            VStack(alignment:.leading,spacing:9) {
                if let item=previewItem {
                    Label(item.kind.frenchTitle.uppercased(),systemImage:mediaIcon(item.kind)).font(.caption.weight(.semibold)).foregroundStyle(themeAccent)
                    Text(item.name).font(.system(.largeTitle,design:.default).weight(.heavy)).lineLimit(2)
                    Text(item.group).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing:9) {
                        navButton(item.kind == .live ? "Regarder" : item.isSeriesCollection ? "Voir les saisons":"Voir la fiche",icon:item.kind == .live ? "play.fill":"film.stack",id:"hero-play",active:true) { openItem(item) }
                        navButton("Favoris et listes",icon:library.isFavorite(item) ? "star.fill" : "star",id:"hero-favorite") { chooseFavorites(item) }
                    }
                } else {
                    Text("VOTRE UNIVERS").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(themeAccent)
                    Text(library.contentKind.frenchTitle).font(.largeTitle.weight(.heavy))
                    Text("Sélectionnez un contenu pour le découvrir.").font(.callout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            if let item=previewItem, !compactChrome {
                ArtworkView(url:item.logoURL,fit:item.kind == .live) { Image(systemName:mediaIcon(item.kind)).font(.largeTitle).frame(maxWidth:.infinity,maxHeight:.infinity) }
                    .frame(width:110,height:142).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.35),lineWidth:1))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : -7),axis:(x:0,y:1,z:0),perspective:0.7)
                    .accessibilityHidden(true)
            }
        }.padding(.horizontal,30).padding(.vertical,compactChrome ? 8 : 16)
    }

    private var compactNavigation: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    private var televisionLayout: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
    /// The Mac presents the desk layout: a dock for the destinations, a
    /// navigation column, and panels drawn in the window instead of sheets.
    private var usesDesk: Bool {
        #if os(macOS) || os(tvOS)
        true
        #else
        false
        #endif
    }
    /// Dock destination that stands for the screen being shown.
    private var currentDockID: String {
        if page == .settings { return FluxDockItem.settings.focusID }
        if favoritesMode && page != .home { return FluxDockItem.favorites.focusID }
        return FluxDockItem(kind: library.contentKind).focusID
    }
    /// On the Mac the form is drawn in the settings; on a television it is
    /// a screen of its own, and a sheet on a phone.
    private func presentAddSource() {
        #if os(macOS)
        openSettings(.sources, editing: .new)
        #else
        addingSource = true
        #endif
    }
    private func presentEditSource(_ source: IPTVSource) {
        #if os(macOS)
        openSettings(.sources, editing: .existing(source))
        #else
        editingSource = source
        #endif
    }
    /// Back and Home stand at the top of the column unless the bar carries them.
    private var deskHeaderIDs: [String] {
        #if os(iOS)
        return []
        #else
        return barFlanks ? [] : [DeskZone.backID, DeskZone.homeID]
        #endif
    }
    /// A remote always shows what it selects; a keyboard only once it is used.
    private var focusShown: Bool {
        #if os(tvOS)
        true
        #else
        remoteNavigationActive
        #endif
    }
    /// Control that the dock and the bars draw as selected. A keyboard moves
    /// a selection of the screen. A television has a focus of its own, that
    /// each control reads from itself: the screen is not rebuilt when the
    /// remote moves, and nothing is drawn where the remote is not.
    private var shownFocusID: String? {
        #if os(tvOS)
        nil
        #else
        focusID
        #endif
    }
    /// Whether the keyboard has selected this control; never on a
    /// television, whose controls show the focus of the system.
    private func selectedByKeyboard(_ id: String) -> Bool {
        #if os(tvOS)
        false
        #else
        focusID == id
        #endif
    }
    private func presentSources() {
        #if os(macOS) || os(tvOS)
        openSettings(.sources)
        #else
        showingSources = true
        #endif
    }
    private func presentLists() {
        #if os(macOS) || os(tvOS)
        enterFavorites()
        #else
        showingLists = true
        #endif
    }
    private func presentCountries() {
        #if os(macOS) || os(tvOS)
        sidebarCountries = true
        let current = library.countryCode.map { "country-\($0)" } ?? "country-all"
        focusID = current
        #if os(tvOS)
        // The rows mount with this update and the focus engine first enters
        // the list by itself: its entry is redirected to the country in use.
        sidebarFocusRequest = current
        #endif
        #else
        showingCountries = true
        #endif
    }
    /// During playback the settings are glass panels above the picture, which
    /// keeps playing; elsewhere on the Mac they are a screen of the window.
    private func presentSettings(diagnostic: Bool = false) {
        #if os(macOS) || os(tvOS)
        if page == .player {
            // The commands stay where they are, under the panels.
            playerControlsTask?.cancel(); playerControlsTask = nil
            playerTracks = false
            if !cinemaControls { cinemaControls = true }
            playerSettings = DeskSettingsRequest(page: diagnostic ? .diagnostic : nil)
        }
        else { openSettings(diagnostic ? .diagnostic : nil) }
        #else
        diagnosticSettings = diagnostic; showingEngines = true
        #endif
    }
    private func leaveSettings() {
        guard page == .settings else { return }
        #if os(macOS) || os(tvOS)
        deskBack()
        #else
        page = .catalogue
        focusID = currentDockID
        systemFocus = focusID
        #endif
    }

    /// Saved sources are restored synchronously by IPTVLibrary. An empty
    /// library starts here, without reopening an import sheet after dismissal.
    private var firstSourceWelcome: some View {
        VStack(spacing: televisionLayout ? 30 : 22) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: televisionLayout ? 92 : 58, weight: .light))
                .foregroundStyle(.cyan)
            Text("Bienvenue dans FLUX")
                .font(.system(size: televisionLayout ? 48 : 32, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Chargez votre liste pour retrouver vos chaînes, films et séries.")
                .font(.system(size: televisionLayout ? 28 : 18))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center).frame(maxWidth: 850)
            let sourceLayout = compactNavigation ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 20))
            sourceLayout {
                Label("Xtream Codes", systemImage: "server.rack")
                Label("Lien M3U", systemImage: "link")
                #if !os(tvOS)
                Label("Fichier M3U", systemImage: "doc")
                #endif
            }.font(.system(size: televisionLayout ? 23 : 14)).foregroundStyle(.secondary)
            Button { presentAddSource() } label: {
                Label("Charger une liste", systemImage: "plus.rectangle.fill")
                    .font(.system(size: televisionLayout ? 29 : 20, weight: .semibold))
                    .padding(.horizontal, televisionLayout ? 34 : 24)
                    .padding(.vertical, televisionLayout ? 23 : 16)
                    .fluxNavigationGlass(selected: true, tint: .cyan, radius: 24)
                    .overlay(FluxFocused(id: "add-source", logical: selectedByKeyboard("add-source")) { focused in
                        RoundedRectangle(cornerRadius: 24).strokeBorder(focused ? .white : .clear, lineWidth: 3)
                    })
            }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "add-source")
                .id("add-source").accessibilityIdentifier("welcome-load-source")
                #if os(tvOS) && FLUX_CATALOG_UI_TESTING
                .background(TVCatalogControlFrameProbe(identifier: "welcome-load-source").allowsHitTesting(false))
                #endif
                .padding(.top, 10)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveHeader: some View { header }
    private var header: some View {
        FluxGlassGroup {
            HStack(spacing: compactNavigation ? 8 : 18) {
                if !compactNavigation { HStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.title2.weight(.semibold)).foregroundStyle(themeAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FLUX").font(.title3.weight(.heavy)).tracking(3)
                            if !compactChrome {
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                }.accessibilityElement(children: .combine).accessibilityLabel("Flux IPTV")
                    #if os(tvOS) && FLUX_CATALOG_UI_TESTING
                    // Read the drawn selection independently from UIKit focus
                    // without adding a focusable control to the fixture.
                    .accessibilityIdentifier("flux-catalog-logical-focus")
                    .accessibilityValue(focusID ?? "none")
                    #endif
                }
                Spacer(minLength: 0)
                HStack(spacing: televisionLayout ? 20 : compactNavigation ? 5 : 10) {
                    ForEach(IPTVMediaKind.allCases, id: \.self) { kind in modeButton(kind) }
                    headerDestination("Recherche",symbol:"magnifyingglass",id:"search",selected:showingSearch || searchFocus || !library.search.isEmpty,tint:.cyan) {search()}
                }
                Spacer(minLength: 0)
                if compactNavigation {
                    navButton("Navigation", icon: "ellipsis", id: "navigation-more", iconOnly: true) { showingNavigationMenu = true }
                        .fluxNavigationGlass(radius: 20)
                } else {
                    HStack(spacing: 2) {
                        navButton("Sources", icon: "square.stack", id: "sources", iconOnly: true) { showingSources = true }
                        #if !os(tvOS)
                        navButton("Télécommande", icon: "appletvremote.gen1", id: "remote", active: showRemote, iconOnly: true) { showRemote.toggle() }
                        #endif
                        if televisionLayout || library.contentKind != .live || (browserHeight < 580 && !liveSidebarVisible) {
                            navButton("Listes", icon: "star", id: "lists", active: library.selectedPresetID != nil, iconOnly: true) { showingLists = true }
                        }
                        navButton("Réglages", icon: "gearshape", id: "settings", iconOnly: true) { showingEngines = true }
                    }.padding(4).fluxNavigationGlass(radius: 23)
                }
            }
        }
        .padding(.horizontal, televisionLayout ? 36 : compactNavigation ? 12 : 24)
        .padding(.top, televisionLayout ? 16 : 10).padding(.bottom, televisionLayout ? 22 : 12)
    }
    private func modeButton(_ kind: IPTVMediaKind) -> some View {
        let selected = library.contentKind == kind && page != .player
        let id = "tab-\(kind.rawValue)"
        let symbol: String = kind == .live ? "tv.fill" : kind == .movie ? "film.fill" : "square.stack.3d.up.fill"
        let title: String = kind == .live ? "TV" : kind == .movie ? "Films" : "Séries"
        let tint: Color = kind == .live ? .cyan : kind == .movie ? .orange : .purple
        return headerDestination(title,symbol:symbol,id:id,selected:selected,tint:tint) {changeKind(kind)}
    }
    private func headerDestination(_ title:String,symbol:String,id:String,selected:Bool,tint:Color,action:@escaping ()->Void)->some View {
        let focused = focusID == id
        return Button { pointerSelect(id); action() } label: {
            let layout = browserHeight < 580 ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 4))
            layout {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                    .font(.system(size: televisionLayout ? 52 : browserHeight < 580 ? 25 : compactNavigation ? 29 : 38, weight: .medium))
                Text(title).font(.system(size: televisionLayout ? 25 : compactNavigation ? 12 : 15, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(selected ? tint : .white.opacity(0.92))
            .frame(minWidth: televisionLayout ? 130 : compactNavigation ? 48 : 88, minHeight: televisionLayout ? 94 : nil)
            .padding(.horizontal, televisionLayout ? 16 : compactNavigation ? 5 : 12)
            .padding(.vertical, televisionLayout ? 16 : 12)
            .fluxNavigationGlass(selected: selected, tint: tint, radius: 21)
            .overlay {
                RoundedRectangle(cornerRadius: 21)
                    .strokeBorder(focused ? .white.opacity(0.95) : .clear, lineWidth: televisionLayout ? 3 : 2)
                    .allowsHitTesting(false)
            }
        }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id)
            .scaleEffect(focused && !reduceMotion ? 1.045 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.88), value: focused)
            .accessibilityLabel(title).accessibilityValue(selected ? "Sélectionné" : "")
            .accessibilityIdentifier("navigation-\(id)")
            #if os(tvOS)
            .onAppear { browseFocusTargetAppeared(id) }
            .onDisappear { mountedBrowseFocusTargets.remove(id) }
            #endif
            #if os(tvOS) && FLUX_CATALOG_UI_TESTING
            .background(TVCatalogControlFrameProbe(identifier: "navigation-\(id)").allowsHitTesting(false))
            #endif
    }

    private func navButton(_ title: String, icon: String, id: String, active: Bool = false, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        return Button { pointerSelect(id); action() } label: {
            FluxFocused(id: id, logical: selectedByKeyboard(id)) { focused in
                HStack(spacing: Desk.tv(6)) {
                    Image(systemName: icon)
                    #if os(iOS)
                    if !iconOnly && sizeClass != .compact { Text(title).lineLimit(1) }
                    #elseif os(macOS)
                    if !iconOnly && (!compactChrome || id.hasPrefix("tab-") || id == "categories") { Text(title).lineLimit(1) }
                    #else
                    if !iconOnly { Text(title).lineLimit(1) }
                    #endif
                }
                // The keys of the desk are those of a television, at the size of the window.
                .font(usesDesk ? .system(size: Desk.tv(25), weight: .semibold) : .callout.weight(.semibold))
                .padding(.vertical, usesDesk ? Desk.tv(16) : 10).padding(.horizontal, usesDesk ? Desk.tv(18) : 12)
                .foregroundStyle(active ? .white : .primary)
                .background(active ? themeAccent.opacity(0.20) : Color.white.opacity(focused ? 0.13 : 0.035), in: RoundedRectangle(cornerRadius: Desk.tv(16)))
                .overlay(RoundedRectangle(cornerRadius: Desk.tv(16)).strokeBorder(focused ? Color.white.opacity(0.8) : .white.opacity(active ? 0.18 : 0.04), lineWidth: focused ? 2 : 1).allowsHitTesting(false))
            }
        }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id).accessibilityLabel(title).fluxHelp(title)
            .accessibilityIdentifier("navigation-\(id)")
    }

    /// The navigation column of the desk is as wide as the bar under it.
    private var liveSidebarWidth: CGFloat {
        #if os(iOS)
        254
        #else
        // Wide enough for « Toutes les chaînes » and its count on one line.
        max(FluxDockMetrics(.corner).length(count: FluxDockItem.allCases.count, vertical: false), Desk.tv(410))
        #endif
    }
    private var liveGroups: [String] {
        let term = groupSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? groups : groups.filter { $0.localizedStandardContains(term) }
    }
    private var liveCountryTitle: String {
        guard let code = library.countryCode else { return library.contentKind == .live ? "Tous les pays" : "Toutes les langues" }
        // Films and series are filtered by the language of their label.
        if library.contentKind != .live { return MediaLanguage.displayName(for: code) }
        let name = LiveCountry.displayName(for: code)
        return code == LiveCountry.unknownCode ? name : "\(name) · \(code)"
    }
    private var liveCountryButton: some View {
        navButton(liveCountryTitle, icon: library.contentKind == .live ? "globe.europe.africa" : "character.bubble", id: "countries",
                  active: library.countryCode != nil) { presentCountries() }
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "live-country-picker"))
        #endif
        .accessibilityLabel("\(library.contentKind == .live ? "Pays" : "Langue") : \(liveCountryTitle)")
    }
    private func selectLiveCountry(_ code: String?) {
        library.countryCode = code
        showingCountries = false
        sidebarCountries = false
        clearPreview()
        focusID = "countries"
        Task { @MainActor in
            await Task.yield()
            guard !showingCountries, page == .catalogue else { return }
            systemFocus = "countries"
        }
    }
    private var liveScopeID: String {
        if let group { return "live-category-\(group)" }
        if let preset = library.selectedPresetID { return "live-preset-\(preset)" }
        return "group-all"
    }
    private var liveSidebarIDs: [String] {
        ["countries", "group-all"] + library.currentPresets.map { "live-preset-\($0.id)" }
            + ["live-manage-lists"] + liveGroups.map { "live-category-\($0)" }
    }
    private func selectLiveGroup(_ name: String) {
        continueOnly = false
        group = name
        liveGroupSearchFocus = false
        clearPreview()
        resetCatalogWindow()
    }
    private func selectLivePreset(_ id: String) {
        continueOnly = false
        library.selectedPresetID = id
        clearPreview()
        resetCatalogWindow()
    }
    private func toggleLiveFavorites() {
        let id = FavoritePresets.defaultID(for: .live)
        if library.selectedPresetID == id {
            library.selectedPresetID = nil
            clearPreview()
            resetCatalogWindow()
        } else { selectLivePreset(id) }
    }
    private func liveScopeSelected(_ id: String) -> Bool {
        if id == "group-all" { return showingAllCatalog }
        if id.hasPrefix("live-category-") { return group == String(id.dropFirst("live-category-".count)) }
        if id.hasPrefix("live-preset-") { return library.selectedPresetID == String(id.dropFirst("live-preset-".count)) }
        if id.hasPrefix("favorite-list-") { return library.selectedPresetID == String(id.dropFirst("favorite-list-".count)) }
        if id == "continue-only" { return continueOnly }
        return false
    }
    /// What a row of the navigation column is drawn from. Its identifier
    /// names what its action does.
    private struct ScopeKey: Equatable {
        let title: String
        let symbol: String
        let id: String
        let count: Int?
        let selected: Bool
        /// Selected with the keyboard; a television shows its own focus.
        let keyboard: Bool
        let theme: VideoClubTheme
    }
    private func liveScopeButton(_ title: String, symbol: String, id: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
        let key = ScopeKey(title: title, symbol: symbol, id: id, count: count, selected: liveScopeSelected(id),
                           keyboard: selectedByKeyboard(id), theme: theme)
        return FluxStable(key) {
            Button { pointerSelect(id); action() } label: {
                FluxFocused(id: id, logical: key.keyboard) { focused in
                    LiveTVScopeLabel(title: title, symbol: symbol, count: count,
                                     selected: key.selected, focused: focused, accent: themeAccent)
                }
                #if os(tvOS)
                // The row says when it really has the remote.
                .background(DeskFocusReport { focused in if focused, columnEntryRequest == id { columnEntryRequest = nil } })
                #endif
            }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id)
                .accessibilityLabel(title)
                .accessibilityValue(key.selected ? "Sélectionné" : "")
        }.equatable()
    }
    private var liveSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("VOTRE TÉLÉVISION", systemImage: "tv")
                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 4)
            liveCountryButton
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les catégories", text: $library.groupSearch)
                    .focused($liveGroupSearchFocus)
                    .onSubmit {
                        liveGroupSearchFocus = false
                        focusID = liveGroups.first.map { "live-category-\($0)" } ?? "group-all"
                        systemFocus = focusID
                    }
                if !groupSearch.isEmpty {
                    Button { groupSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche de catégories")
                }
            }.font(.callout).padding(11)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
            ScrollViewReader { categoryReader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        liveScopeButton("Toutes les chaînes", symbol: "square.grid.2x2", id: "group-all", count: library.catalogResults.all.items.count) { showAllCatalog() }
                        ForEach(library.currentPresets) { preset in
                            liveScopeButton(preset.name, symbol: preset.isDefault ? "star.fill" : "text.badge.star", id: "live-preset-\(preset.id)") { selectLivePreset(preset.id) }
                        }
                        liveScopeButton("Gérer les listes", symbol: "slider.horizontal.3", id: "live-manage-lists") { presentLists() }
                        Text("CATÉGORIES").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 5)
                        ForEach(liveGroups, id: \.self) { name in
                            liveScopeButton(name, symbol: "folder", id: "live-category-\(name)", count: library.catalogResults.slice(group: name).items.count) { selectLiveGroup(name) }
                        }
                        if liveGroups.isEmpty {
                            Text(groupSearch.isEmpty ? "Les catégories apparaîtront avec vos chaînes." : "Aucune catégorie correspondante.")
                                .font(.caption).foregroundStyle(.secondary).padding(12)
                        }
                    }.padding(.vertical, 3)
                }
                .onChange(of: focusID) { _, id in
                    if let id, liveSidebarIDs.contains(id) { categoryReader.scrollTo(id, anchor: .center) }
                }
            }
        }
        .padding(14).frame(width: liveSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .fluxGlass(radius: 25)
    }
    private var liveCompactScopes: some View {
        HStack(spacing: 8) {
            liveCountryButton
            Button { pointerSelect("categories"); showingGroups = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(group ?? "Catégories").font(.callout.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }.padding(.horizontal, 13).padding(.vertical, 10)
            }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "categories").id("categories")
                .fluxNavigationGlass(selected: group != nil, tint: themeAccent, radius: 17)
            Spacer(minLength: 0)
            navButton("Favoris", icon: "star.fill", id: "favorites-quick", active: library.selectedPresetID == FavoritePresets.defaultID(for: .live), iconOnly: true) {
                toggleLiveFavorites()
            }.fluxNavigationGlass(radius: 17)
            navButton("Listes", icon: "text.badge.star", id: "lists", active: library.selectedPresetID != nil, iconOnly: true) { showingLists = true }
                .fluxNavigationGlass(radius: 17)
        }
    }
    @ViewBuilder private var liveCatalogue: some View {
        #if os(tvOS)
        liveTelevisionCatalogue
        #else
        liveDesktopCatalogue
        #endif
    }

    #if os(tvOS)
    private var televisionScopeIDs: [String] {
        ["countries", "favorites-quick", "group-all"] + groups.map { "live-category-\($0)" } + ["categories"]
    }

    /// Horizontal channel categories leave the full width for large 16:9 tiles.
    /// Only the selected tile mounts a video layer; the room remains a still image.
    private var liveTelevisionCatalogue: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                Text("En direct").font(.system(size: 34, weight: .bold))
                Text(library.isFiltering ? "Recherche…" : "\(visible.count) \(visible.count == 1 ? "chaîne" : "chaînes")")
                    .font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 10)
                Text("OK Regarder · Appui long Favoris")
                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.65))
                navButton("Actualiser", icon: "arrow.clockwise", id: "reload", iconOnly: true) { library.reloadSelected() }
                    .disabled(library.selectedSourceID == nil || library.isLoading)
            }
            if showingSearch {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                    TextField("Rechercher une chaîne", text: $library.search)
                        .focused($searchFocus).onSubmit { searchFocus = false; focusFirstItem() }
                    Button("Fermer") { showingSearch = false; searchFocus = false; focusFirstItem() }
                }.font(.system(size: 25)).padding(18).fluxGlass(radius: 20)
            }
            ScrollViewReader { categoryReader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        liveCountryButton
                        televisionCategory("Favoris", id: "favorites-quick", selected: library.selectedPresetID == FavoritePresets.defaultID(for: .live)) {
                            toggleLiveFavorites()
                        }
                        televisionCategory("Toutes les chaînes", id: "group-all", selected: showingAllCatalog) { showAllCatalog() }
                        ForEach(groups, id: \.self) { name in
                            televisionCategory(name, id: "live-category-\(name)", selected: group == name) { selectLiveGroup(name) }
                        }
                        televisionCategory("Toutes les catégories", id: "categories", selected: false) {
                            showingGroups = true
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 8)
                }
                .frame(height: 82)
                .onChange(of: focusID) { _, id in
                    if let id, televisionScopeIDs.contains(id) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { categoryReader.scrollTo(id, anchor: .center) }
                    }
                }
            }
            liveNotices
            liveChannelContent
        }.padding(.horizontal, 36).padding(.bottom, 20)
    }

    private func televisionCategory(_ title: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let focused = focusID == id
        return Button { pointerSelect(id); action() } label: {
            Text(title).font(.system(size: 25, weight: focused || selected ? .semibold : .medium))
                .lineLimit(1).frame(maxWidth: 330)
                .padding(.horizontal, 24).padding(.vertical, 17)
                .foregroundStyle(focused ? Color.black : .white)
                .background(focused ? Color.white : Color.white.opacity(selected ? 0.19 : 0.045), in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(themeAccent).frame(height: 4).padding(.horizontal, 20) }
                }
        }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id)
            .scaleEffect(focused && !reduceMotion ? 1.035 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9), value: focused)
            .accessibilityValue(selected ? "Sélectionné" : "")
    }
    #endif

    private var liveDesktopCatalogue: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: 18) {
                if liveSidebarVisible { liveSidebar }
                VStack(alignment: .leading, spacing: browserHeight < 700 ? 8 : 14) {
                    if browserHeight >= 700 {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group ?? library.selectedPreset?.name ?? "Télévision")
                                .font(.title2.weight(.bold)).lineLimit(1)
                            Text("\(library.selectedSource?.name ?? "Votre salon TV") · \(library.isFiltering ? "Recherche…" : "\(visible.count) \(visible.count == 1 ? "chaîne" : "chaînes")")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        navButton("Actualiser", icon: "arrow.clockwise", id: "reload", iconOnly: true) { library.reloadSelected() }
                            .disabled(library.selectedSourceID == nil || library.isLoading)
                            .fluxNavigationGlass(radius: 18)
                    }.padding(.horizontal, 3)
                    }
                    HStack(spacing: 10) {
                        if browserHeight < 580 && !liveSidebarVisible {
                            liveCountryButton
                            Button { showingGroups = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                                .buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "categories").id("categories")
                                .accessibilityLabel("Catégories TV")
                        } else { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }
                        TextField("Rechercher une chaîne", text: $library.search)
                            .focused($searchFocus).onSubmit { searchFocus = false; focusFirstItem() }
                        if !library.search.isEmpty {
                            Button { library.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("Effacer la recherche de chaînes")
                        }
                        if browserHeight < 700 {
                            navButton("Actualiser", icon: "arrow.clockwise", id: "reload", iconOnly: true) { library.reloadSelected() }
                                .disabled(library.selectedSourceID == nil || library.isLoading)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, browserHeight < 700 ? 5 : 13).fluxGlass(radius: 20)
                    if !liveSidebarVisible && browserHeight >= 580 { liveCompactScopes }
                    liveNotices
                    if let item = previewItem, item.kind == .live, visibleSlice.index(of: item.id) != nil {
                        liveSelectedChannel(item)
                    }
                    liveChannelContent
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }.padding(.horizontal, compactNavigation ? 12 : 24).padding(.bottom, browserHeight < 700 ? 10 : 18)
    }
    @ViewBuilder private var liveNotices: some View {
        if playback.recoveryMode {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(.orange)
                Text("Lecture Apple activée après une interruption de VLC.").font(.caption)
                Spacer(minLength: 4)
                Button("Diagnostic") { presentSettings(diagnostic: true) }.buttonStyle(.bordered)
            }.padding(12).fluxFrosted(radius: 16)
        }
        if let issue = library.credentialIssue, let source = library.selectedSource, source.kind != .m3uFile {
            VStack(alignment: .leading, spacing: 9) {
                Label("Reconnecter « \(source.name) »", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(usesDesk ? Desk.font(.headline) : .headline).lineLimit(2)
                Text(issue).font(usesDesk ? Desk.font(.caption) : .caption).foregroundStyle(.secondary)
                navButton("Reconnecter", icon: "arrow.clockwise", id: "reconnect-source") { presentEditSource(source) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).fluxFrosted(radius: 18)
        }
    }
    @ViewBuilder private var liveChannelContent: some View {
        if (library.isLoading || library.isFiltering) && visible.isEmpty {
            Spacer()
            ProgressView(library.isLoading ? "Chargement des chaînes…" : "Recherche…").frame(maxWidth: .infinity)
            Spacer()
        } else if visible.isEmpty {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "tv").font(.system(size: 48, weight: .light)).foregroundStyle(themeAccent)
                Text(library.sources.isEmpty ? "Votre télévision vous attend" : "Aucune chaîne dans cette sélection")
                    .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if library.sources.isEmpty {
                    navButton("Ajouter une source", icon: "plus", id: "add-source") { presentAddSource() }
                } else if library.credentialIssue == nil {
                    navButton("Toutes les chaînes", icon: "square.grid.2x2", id: "live-reset") { showAllCatalog() }
                }
            }.frame(maxWidth: .infinity)
            Spacer()
        } else {
            if catalogPageCount > 1 && browserHeight >= 700 { livePagination }
            ScrollView {
                if catalogPageCount > 1 && browserHeight < 700 { livePagination }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: televisionLayout ? 24 : 12), count: max(1, columns)), spacing: televisionLayout ? 26 : 12) {
                    ForEach(displayedItems) { item in liveChannel(item) }
                }.padding(televisionLayout ? 10 : 3).padding(.bottom, 12)
            }
        }
    }
    private var livePagination: some View {
        HStack(spacing: 10) {
            navButton("Page précédente", icon: "chevron.left", id: "page-prev", iconOnly: true) { changeCatalogPage(-1) }.disabled(catalogPage == 0)
            Text("\(catalogPage + 1) / \(catalogPageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            navButton("Page suivante", icon: "chevron.right", id: "page-next", iconOnly: true) { changeCatalogPage(1) }.disabled(catalogPage + 1 >= catalogPageCount)
            Spacer(minLength: 0)
            if let first = displayedItems.first, let last = displayedItems.last, let start = visibleSlice.index(of: first.id), let end = visibleSlice.index(of: last.id) {
                Text("\(start + 1)–\(end + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
    private func liveChannel(_ item: IPTVItem) -> some View {
        Button {
            guard !modalOpen else { return }
            #if os(tvOS)
            selectCard(item)
            #else
            pointerSelect(item.id); setPreview(item)
            #endif
        } label: {
            LiveTVChannelLabel(item: item, number: (visibleSlice.index(of: item.id) ?? 0) + 1,
                               favorite: library.isFavorite(item), highlighted: focusID == item.id,
                               accent: themeAccent,
                               preview: televisionLayout && focusID == item.id ? livePreview : nil,
                               delay: livePreviewDelay, automaticPreview: automaticLivePreview)
        }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: item.id).id(item.id)
            .accessibilityLabel(item.name).accessibilityHint(televisionLayout ? "L’aperçu démarre dans cette vignette. Valider pour regarder. Appui long pour les favoris." : "Sélectionner pour afficher l’aperçu. Regarder ouvre la chaîne. Appui long pour les favoris.")
            .accessibilityIdentifier("live-channel-\(item.id)")
            #if os(tvOS)
            .onAppear { browseFocusTargetAppeared(item.id) }
            .onDisappear { mountedBrowseFocusTargets.remove(item.id) }
            #endif
            #if os(tvOS) && FLUX_CATALOG_UI_TESTING
            .background(TVCatalogControlFrameProbe(identifier: "live-channel-\(item.id)").allowsHitTesting(false))
            #endif
            .zIndex(focusID == item.id ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84), value: focusID == item.id)
            .contextMenu {
                Button("Regarder", systemImage: "play.fill") { selectCard(item) }
                Button("Favoris et listes", systemImage: "star") { chooseFavorites(item) }
            }
            #if os(tvOS)
            .onLongPressGesture(minimumDuration: 0.65) { chooseFavorites(item) }
            #else
            .onLongPressGesture(minimumDuration: 0.65, maximumDistance: 12) { chooseFavorites(item) }
            .onHover { inside in if inside && !modalOpen { pointerSelect(item.id); setPreview(item) } }
            #endif
    }

    private func liveSelectedChannel(_ item: IPTVItem) -> some View {
        HStack(spacing: compactNavigation || browserHeight < 700 ? 12 : 20) {
                    LiveTVPreviewScreen(preview: livePreview, item: item, delay: livePreviewDelay, automatic: automaticLivePreview)
                        .frame(width: compactNavigation ? 112 : browserHeight < 580 ? 140 : browserHeight < 700 ? 220 : liveSidebarVisible ? 330 : 280)
                    liveSelectedActions(item).frame(minWidth: compactNavigation ? 120 : 160, maxWidth: .infinity, alignment: .leading)
        }
        .padding(browserHeight < 580 ? 10 : 14).fluxGlass(radius: 27)
        .shadow(color: .black.opacity(0.26), radius: 16, x: 0, y: 12)
        .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
    private func liveSelectedActions(_ item: IPTVItem) -> some View {
        VStack(alignment: .leading, spacing: compactNavigation || browserHeight < 700 ? 6 : 10) {
            if !compactNavigation && browserHeight >= 700 {
            Label("CHAÎNE SÉLECTIONNÉE", systemImage: "tv.fill")
                .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(themeAccent)
            }
            Text(item.name).font(.headline).lineLimit(browserHeight < 580 ? 1 : 2)
            if browserHeight >= 580 { Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: compactNavigation ? 5 : 8) {
                Button { playItem(item) } label: {
                    Label("Regarder", systemImage: "play.fill").font((compactNavigation ? Font.caption : .callout).weight(.semibold))
                        .padding(.horizontal, compactNavigation ? 10 : 15).padding(.vertical, browserHeight < 700 ? 7 : 10)
                        .fluxNavigationGlass(selected: true, tint: themeAccent, radius: 17)
                }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "live-watch").id("live-watch")
                if !compactNavigation && browserHeight >= 580 {
                navButton("Favoris", icon: library.isFavorite(item) ? "star.fill" : "star", id: "live-favorite", iconOnly: true) { chooseFavorites(item) }
                }
                LiveTVPreviewObserver(preview: livePreview) { preview in
                    if preview.player != nil {
                        Button { preview.toggleMuted() } label: {
                            Image(systemName: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.caption).padding(compactNavigation ? 7 : 10)
                        }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "live-preview-mute").id("live-preview-mute")
                            .accessibilityLabel(preview.isMuted ? "Activer le son de l’aperçu" : "Couper le son de l’aperçu")
                    }
                }
            }
        }
    }

    @ViewBuilder private var catalogue: some View {
        #if os(macOS) || os(tvOS)
        if library.contentKind == .live { liveDeskCatalogue }
        else { mediaDeskCatalogue }
        #else
        if library.contentKind == .live { liveCatalogue }
        else { mediaCatalogue }
        #endif
    }

    private var mediaCatalogue: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playback.recoveryMode {
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.orange)
                    Text("Mode de récupération : lecture Apple uniquement après une session VLC non terminée.").font(.callout)
                    Spacer()
                    Button("Diagnostic") { presentSettings(diagnostic: true) }.buttonStyle(.bordered)
                }.padding(12).fluxFrosted(radius: 14).padding(.horizontal, 28)
            }
            if showingSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher dans \(library.contentKind.frenchTitle.lowercased())", text: $library.search)
                        .focused($searchFocus).fluxFieldStyle().onSubmit { searchFocus = false; focusFirstItem() }
                    Button("Effacer") { library.search = "" }
                    Button("Fermer") { showingSearch = false; searchFocus = false }
                }.padding(14).fluxGlass().padding(.horizontal, 26)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.selectedPreset?.name ?? environment.title).font(.system(.largeTitle, design: .default).weight(.bold)).lineLimit(1)
                    Text("\(library.selectedSource?.name ?? "Bibliothèque")  ·  \(library.isFiltering ? "Recherche…" : "\(visible.count) \(visible.count == 1 ? "élément" : "éléments")")").font(.callout).foregroundStyle(.secondary)
                    if !compactChrome {
                        Text(library.contentKind == .movie ? "À l’affiche · Choisir un film" : library.contentKind == .series ? "Les séries · Saisons et épisodes" : "En direct · Choisir une chaîne")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                navButton("Actualiser", icon: "arrow.clockwise", id: "reload") { library.reloadSelected() }.disabled(library.selectedSourceID == nil || library.isLoading)
            }.padding(.horizontal, 30)
            HStack(spacing: 10) {
                navButton("Toutes", icon: "square.grid.2x2", id: "group-all", active: showingAllCatalog) { showAllCatalog() }
                navButton(group ?? "Catégories", icon: "line.3.horizontal.decrease", id: "categories", active: group != nil) { showingGroups = true }
                if group != nil { Button { self.group = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Effacer le filtre") }
                Spacer(minLength: 0)
                if library.contentKind == .movie { navButton("À reprendre", icon: "clock.arrow.circlepath", id: "continue-only", active: continueOnly) { toggleResumeFilter() } }
                if !library.sources.isEmpty { navButton("Favoris", icon: "star.fill", id: "favorites-quick", active: library.selectedPresetID == FavoritePresets.defaultID(for: library.contentKind)) { toggleQuickFavorites() } }
            }.padding(.horizontal, 30).padding(.vertical, 2)
            if let issue = library.credentialIssue, let source = library.selectedSource, source.kind != .m3uFile {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").font(.title2).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reconnecter « \(source.name) »").font(.headline)
                        Text(issue).font(.caption).foregroundStyle(.secondary)
                        Text("Vos listes et favoris restent intacts.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    navButton("Reconnecter", icon: "arrow.clockwise", id: "reconnect-source") { presentEditSource(source) }
                }.padding(16).fluxFrosted(radius: 16).padding(.horizontal, 30)
            }
            if library.isLoading && visible.isEmpty { Spacer(); ProgressView("Chargement du catalogue…").frame(maxWidth: .infinity); Spacer() }
            else if library.isFiltering && visible.isEmpty { Spacer(); ProgressView("Recherche…").frame(maxWidth: .infinity); Spacer() }
            else if visible.isEmpty {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "play.tv").font(.system(size: 54)).foregroundStyle(themeAccent)
                    Text(library.sources.isEmpty ? "Votre télévision vous attend" : library.credentialIssue != nil ? "Source à reconnecter" : "Aucun contenu").font(.title.weight(.semibold))
                    if library.sources.isEmpty { navButton("Ajouter une source", icon: "plus", id: "add-source") { presentAddSource() } }
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Both visual concepts always begin in the complete, paginated grid.
                if catalogPageCount > 1 { catalogPagination }
                #if os(tvOS)
                GeometryReader { viewport in
                    // Headers, search and pagination have already taken their
                    // space. Keep one complete row inside the remaining view,
                    // including the 12-point scroll padding above and below.
                    mediaCatalogGrid(cardHeight: max(0, viewport.size.height - 24))
                }
                #else
                mediaCatalogGrid()
                #endif
            }
        }
    }

    private func mediaCatalogGrid(cardHeight: CGFloat? = nil) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Desk.tv(8)) {
                if library.contentKind == .live { previewHero }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Desk.tv(4)), count: columns), spacing: Desk.tv(8)) {
                    ForEach(displayedItems) { item in card(item, height: cardHeight) }
                }
                #if !os(tvOS)
                .padding(.horizontal, Desk.tv(16))
                #endif
                .padding(.vertical, Desk.tv(12))
            }
        }
        #if os(tvOS)
        // Keep the scroll container itself inside the TV safe area. Placing
        // this existing gap only on the grid lets ScrollView expand its
        // backing container across the leading safe-area inset, separating
        // native focus geometry from the visible cards. The usable grid width
        // and card positions stay the same; no coordinate offset is needed.
        .padding(.horizontal, 16)
        #endif
    }

    private var catalogPagination: some View {
        HStack(spacing:12) {
            navButton("Page précédente",icon:"chevron.left",id:"page-prev") { changeCatalogPage(-1) }.disabled(catalogPage==0)
            Text("Page \(catalogPage+1) / \(catalogPageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            navButton("Page suivante",icon:"chevron.right",id:"page-next") { changeCatalogPage(1) }.disabled(catalogPage+1>=catalogPageCount)
            Spacer(minLength:0)
            if let first=displayedItems.first,let last=displayedItems.last,let a=visibleSlice.index(of:first.id),let b=visibleSlice.index(of:last.id) {
                Text("\(a+1)–\(b+1) / \(visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.padding(.horizontal,30)
    }

    /// What a sleeve of the catalogue is drawn from.
    private struct CardKey: Equatable {
        let item: IPTVItem
        let height: CGFloat?
        /// The full effects: the focus is animated.
        let rich: Bool
        /// Selected with the keyboard; a television shows its own focus.
        let selected: Bool
        let favorite: Bool
        /// Share already watched of a title that can be resumed.
        let progress: Double?
        let watched: Bool
        /// The fiche has taken this sleeve out of the catalogue.
        let held: Bool
        let expanded: Bool
        let theme: VideoClubTheme
        let desk: Bool
        let television: Bool
        let reduceMotion: Bool
    }

    private func card(_ item: IPTVItem, height: CGFloat? = nil) -> some View {
        let entry = playback.history.entries[item.id]
        #if os(macOS)
        let held = sleeveHeld(item)
        #else
        let held = false
        #endif
        let key = CardKey(item: item, height: height, rich: focusMotion, selected: selectedByKeyboard(item.id),
                          favorite: library.isFavorite(item), progress: entry.flatMap { $0.resumable ? $0.fraction : nil },
                          watched: entry != nil, held: held, expanded: held && caseExpanded, theme: theme,
                          desk: usesDesk, television: televisionLayout, reduceMotion: reduceMotion)
        #if os(tvOS)
        // The sleeve under the remote grows over its neighbours.
        return FluxRaised { report in
            FluxStable(key) { cardBody(item, key: key, report: report) }.equatable()
        }
        #else
        return FluxStable(key) { cardBody(item, key: key, report: { _ in }) }.equatable()
            .zIndex(key.selected ? 1 : 0)
        #endif
    }

    /// Rebuilt only when `key` changes: a move of the remote leaves every
    /// sleeve alone but the two it concerns, which read the focus themselves.
    private func cardBody(_ item: IPTVItem, key: CardKey, report: @escaping (Bool) -> Void) -> some View {
        FluxProbe.hit("sleeve")
        let favorite = key.favorite
        return ZStack(alignment: .topTrailing) {
            Button { selectCard(item) } label: {
                FluxFocused(id: item.id, logical: key.selected) { focused in
                    VStack(alignment: .leading, spacing: Desk.tv(8)) {
                        CatalogSleeveArtwork(item: item)
                        .aspectRatio(2.0/3.0, contentMode: .fit)
                        #if os(macOS)
                        .matchedGeometryEffect(id: sleeveID(item), in: caseNamespace, properties: .frame, anchor: .center,
                                               isSource: !key.expanded)
                        .opacity(key.held ? 0 : 1)
                        #endif
                        #if os(tvOS)
                        // The sleeve under the remote grows and follows the thumb.
                        .fluxFocusLean(focused)
                        .frame(maxWidth: .infinity)
                        #else
                        .rotation3DEffect(.degrees(focused && !key.reduceMotion ? -4 : 0),axis:(x:0,y:1,z:0),perspective:0.6)
                        .scaleEffect(focused && !key.reduceMotion ? (key.desk ? 1.05 : 1.025) : 1)
                        .offset(y: focused && !key.reduceMotion ? -3 : 0)
                        #endif
                        Text(item.name).font(Desk.font(.callout, .semibold)).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                            #if os(tvOS)
                            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                            #endif
                        HStack(spacing: Desk.tv(5)) {
                            Text(CasePackageFormat.resolve(year: item.details.year).title)
                                .font(.system(size: key.desk ? Desk.tv(15) : 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, Desk.tv(5)).padding(.vertical, Desk.tv(2))
                                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: Desk.tv(3)))
                            Text(item.group).font(Desk.font(.caption)).lineLimit(1)
                        }.foregroundStyle(.secondary)
                            #if os(tvOS)
                            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                            #endif
                        if let progress = key.progress {
                            ProgressView(value: progress).tint(themeAccent)
                                #if os(tvOS)
                                .layoutPriority(1)
                                #endif
                        }
                    }
                    #if os(tvOS)
                    // Text keeps its natural size. The flexible 2:3 artwork takes
                    // the height left by the labels and optional progress bar;
                    // reserve the card's own 5-point vertical padding on each side.
                    .frame(height: key.height.map { max(0, $0 - 10) }, alignment: .top)
                    #endif
                    .padding(.horizontal, Desk.tv(2)).padding(.vertical, Desk.tv(5))
                    #if os(tvOS)
                    // The plate and the ring of the focus are drawn once and
                    // only shown or hidden: a colour or a width that changes
                    // is drawn again for every picture of its animation.
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21))
                    .background(RoundedRectangle(cornerRadius: 21).fill(.white.opacity(0.11)).opacity(focused ? 1 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
                    .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.88), lineWidth: 2)
                        .opacity(focused ? 1 : 0).allowsHitTesting(false))
                    .animation(key.reduceMotion || !key.rich ? nil : .easeOut(duration: 0.12), value: focused)
                    #else
                    .background(.white.opacity(focused ? 0.13 : 0.025), in: RoundedRectangle(cornerRadius: Desk.tv(21)))
                    .overlay(RoundedRectangle(cornerRadius: Desk.tv(21)).strokeBorder(focused ? Color.white.opacity(0.88) : .white.opacity(0.08), lineWidth: focused ? 2 : 1).allowsHitTesting(false))
                    .animation(key.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: focused)
                    #endif
                }
                #if os(tvOS)
                .background(DeskFocusReport(report: report))
                #endif
            }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: item.id).id(item.id)
                .accessibilityIdentifier("catalog-card-\(item.id)")
                #if os(tvOS)
                .onAppear { browseFocusTargetAppeared(item.id) }
                .onDisappear { mountedBrowseFocusTargets.remove(item.id) }
                #endif
                #if os(tvOS) && FLUX_CATALOG_UI_TESTING
                .background(TVCatalogControlFrameProbe(identifier: "catalog-card-\(item.id)").allowsHitTesting(false))
                #endif
                #if os(tvOS)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.65).onEnded { _ in chooseFavorites(item) })
                #else
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 14).onEnded { _ in chooseFavorites(item) })
                #endif
                #if os(macOS)
                .onHover { inside in if inside { deskHover(item) } }
                .contextMenu {
                    Button("Favoris et listes…") { chooseFavorites(item) }
                    if key.watched {
                        Button("Recommencer") {
                            playback.forgetProgress(item.id)
                            if item.isSeriesCollection { loadSeries(item) } else { playItem(item) }
                        }
                    }
                }
                #endif
                .accessibilityLabel(item.name)
                .accessibilityHint("Cliquer pour ouvrir. Maintenir pour choisir les favoris et les listes.")
            #if os(tvOS)
            if favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).padding(9).background(.black.opacity(0.75), in: Circle()).padding(13).allowsHitTesting(false) }
            #else
            if key.desk && !key.selected {
                // At rest a Mac shows what a television shows: the star of a
                // favourite. The keys of a pointer come with the pointer.
                if favorite {
                    Image(systemName: "star.fill").font(.system(size: Desk.tv(29))).foregroundStyle(.yellow)
                        .padding(Desk.tv(9)).background(.black.opacity(0.75), in: Circle()).padding(Desk.tv(13)).allowsHitTesting(false)
                }
            } else {
                let side: CGFloat = key.desk ? Desk.tv(47) : 29
                HStack(spacing: key.desk ? Desk.tv(8) : 6) {
                    Button { chooseFavorites(item) } label: {
                        Image(systemName: favorite ? "star.fill" : "star").font(key.desk ? .system(size: side * 0.5) : .body).foregroundStyle(favorite ? .yellow : .white)
                            .frame(width: side, height: side).background(.black.opacity(0.72), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Choisir les favoris et les listes")
                    Button { chooseFavorites(item) } label: {
                        Image(systemName: "ellipsis").font(key.desk ? .system(size: side * 0.5) : .body).foregroundStyle(.white)
                            .frame(width: side, height: side).background(.black.opacity(0.72), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Listes et options")
                }.padding(key.desk ? Desk.tv(13) : 13)
            }
            #endif
        }
    }

    /// The shelf of the seasons spans the screen. On a television its sleeves
    /// keep the size they have in the catalogue, which a column narrows.
    private var shelfColumns: Int {
        #if os(iOS)
        return columns
        #else
        let estimated = (deskWidth - Desk.tv(40)) / (cardWidth + Desk.tv(4)) + 0.02
        return estimated.isFinite ? max(columns, Int(min(10, estimated))) : columns
        #endif
    }

    private var seriesDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                navButton("Retour aux séries", icon: "chevron.backward", id: "series-back") { back() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(series?.name ?? "Série").font(Desk.font(.title2, .bold)).lineLimit(2)
                    Text(episodesLoading ? "Chargement des saisons…" : "\(seasons.count) saisons · Choisissez une saison")
                        .font(Desk.font(.callout)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let series {
                    navButton("Favoris et listes", icon: "star", id: "series-favorite") { itemOptions = series }
                }
            }.padding(.horizontal, 24).padding(.top, 6)
            if episodesLoading {
                Spacer(); ProgressView("Chargement des saisons…").frame(maxWidth: .infinity); Spacer()
            } else if episodesFailed {
                Spacer()
                VStack(spacing: 12) {
                    Text("Les saisons n’ont pas pu être chargées.").foregroundStyle(.secondary)
                    navButton("Réessayer", icon: "arrow.clockwise", id: "series-retry") { if let series { loadSeries(series) } }
                }.frame(maxWidth: .infinity)
                Spacer()
            } else if seasons.isEmpty {
                Spacer()
                Text("Le fournisseur n’a communiqué aucune saison pour cette série.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                Spacer()
            } else if let series {
                SeriesSeasonShelf(series: series, seasons: seasons, columns: shelfColumns,
                                  focusedID: focusID, systemFocus: nativeFocus,
                                  focus: focusSeason, open: {showSeason($0)},
                                  heroNamespace: usesDesk ? caseNamespace : nil,
                                  heldSeason: heldItem?.id == series.id ? heldSeasonNumber : nil,
                                  heroExpanded: caseExpanded)
                Text("Choisissez une saison pour voir ses épisodes · Retour : catalogue des séries")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 10)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Windowed and fullscreen playback share the same edge-to-edge surface.
    /// Chrome floats above the image; showing it never resizes the video.
    private var playerPage: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerSurface(playback: playback, immersive: cinema, quiet: liveBannerShown)
                    #if os(tvOS)
                    // The picture fills the television. What is written over
                    // it keeps to the safe area.
                    .ignoresSafeArea()
                    #endif
                    .contentShape(Rectangle())
                    #if FLUX_CATALOG_UI_TESTING
                    .overlay { if fixturePictureStandIn { ProceduralStage(kind: .movie) } }
                    #endif
                    #if !os(tvOS)
                    .focusable().focused(nativeFocus, equals: "cinema-controls")
                    .id("cinema-controls").focusEffectDisabled()
                    .onTapGesture {
                        // A click beside the list of channels closes it.
                        if zapListVisible { closeZapList() }
                        else if playerControlsVisible { hidePlayerControls() }
                        else { zapSurfing = false; revealPlayerControls() }
                    }
                    #endif
                #if os(tvOS)
                if !playerControlsVisible && !playerCovered {
                    // An invisible native focus target lets Select restore the
                    // controls without keeping a permanent badge over the film.
                    // It never stands under a panel: it would take the remote
                    // from the settings as soon as the commands hide.
                    Button { revealPlayerControls(focus: true) } label: {
                        FluxFocused(id: "cinema-controls", logical: false) { _ in Color.clear.contentShape(Rectangle()) }
                    }
                    .buttonStyle(FluxBareButtonStyle())
                    .focusEffectDisabled()
                    .focused(nativeFocus, equals: "cinema-controls")
                    .id("cinema-controls")
                    .accessibilityLabel("Afficher les commandes")
                    .accessibilityIdentifier("player-catcher")
                    #if FLUX_CATALOG_UI_TESTING
                    .background(TVCatalogControlFrameProbe(identifier: "player-catcher").allowsHitTesting(false))
                    #endif
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: dispatch(.left)
                        case .right: dispatch(.right)
                        case .up: dispatch(.up)
                        case .down: dispatch(.down)
                        @unknown default: break
                        }
                    }
                }
                #endif
                if playerChromeShown {
                    PlayerScrim().transition(.opacity)
                    FluxGlassGroup {
                        VStack(spacing: 0) {
                            playerHeading
                            Spacer(minLength: 0)
                            if playerTracks { playerTracksPanel.transition(.opacity) }
                            else { playerBar.transition(.opacity) }
                        }
                        .padding(playerChromeInset)
                    }
                    .transition(.opacity)
                }
                if liveBannerShown {
                    // What is written at the foot stays readable over a bright picture.
                    PlayerScrim(top: false).transition(.opacity)
                    VStack { Spacer(); liveBanner }
                        .allowsHitTesting(false).transition(.opacity)
                }
                if zapListVisible, zapListAvailable {
                    zapList
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            #if !os(tvOS)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88), value: zapListVisible)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    // The pointer asks for the commands.
                    zapSurfing = false
                    revealPlayerControls()
                    // The left edge of the picture calls the channel list.
                    if location.x < 14, !zapListVisible { openZapList() }
                }
            }
            #endif
            .onAppear { playerWidth = geometry.size.width; revealPlayerControls() }
            .onChange(of: geometry.size.width) { _, width in playerWidth = width }
        }
        .onChange(of: playback.isPlaying) { _, _ in revealPlayerControls() }
        .onChange(of: playback.opening) { _, opening in
            // The picture has come: its banner stays a moment more.
            if zapSurfing && !opening { showZapBanner() }
            revealPlayerControls()
        }
        .onChange(of: playback.playbackError) { _, _ in revealPlayerControls() }
        .onChange(of: playback.position) { _, position in if !scrubbing { scrubPosition = position } }
        .onChange(of: playback.playingItem?.id) { _, _ in
            scrubbing = false; scrubPosition = 0; revealPlayerControls()
        }
        .onChange(of: modalOpen) { _, _ in if page == .player { revealPlayerControls() } }
        .onChange(of: voiceOverEnabled) { _, _ in if page == .player { revealPlayerControls() } }
        .onDisappear {
            playerControlsTask?.cancel(); playerControlsTask = nil; hoveredPlayerControls.removeAll()
            zapListTask?.cancel(); zapListTask = nil; zapListVisible = false
            playerSettings = nil; playerTracks = false; hoveredPlayerButton = nil
            zapSurfing = false; zapBanner = false
        }
    }

    // MARK: Zapping: the channel list over the picture

    /// The commands leave the picture to the settings drawn above it, and to
    /// the list of channels: side by side they would overlap, and the remote
    /// would wander from one to the other.
    private var playerChromeShown: Bool { playerControlsVisible && playerSettings == nil && !zapListVisible }
    /// A panel above the picture: the settings or the languages. Nothing
    /// hides the commands under it, and nothing takes the remote from it.
    private var playerPanelOpen: Bool { playerSettings != nil || playerTracks }
    /// A panel or the list of channels: the picture is not alone, the
    /// commands neither hide nor take the remote.
    private var playerCovered: Bool { playerPanelOpen || zapListVisible }
    /// Live television only; an episode keeps its own previous and next.
    private var zapListAvailable: Bool {
        #if FLUX_CATALOG_UI_TESTING
        if fixtureZapList { return page == .player }
        #endif
        return page == .player && playback.playingItem?.kind == .live && series == nil
    }
    private var zapPlayingID: String? {
        #if FLUX_CATALOG_UI_TESTING
        if fixtureZapList { return previewID }
        #endif
        return playback.playingItem?.id
    }
    /// `fromKey`: the key Chaînes of the commands opened it.
    private func openZapList(keyboard: Bool = false, fromKey: Bool = false) {
        guard zapListAvailable else { return }
        zapKeyboard = keyboard
        zapOpenedFromKey = fromKey
        zapFocusID = visibleSlice.item(id: playback.playingItem?.id)?.id ?? visible.first?.id
        playerControlsTask?.cancel(); playerControlsTask = nil
        zapListVisible = true
        armZapListTimer()
        #if os(tvOS)
        // The remote lands on the channel being watched.
        requestZapFocus(zapFocusID)
        #endif
    }
    #if os(tvOS)
    /// Asks the remote for a row of the list, until that row has it. Its row
    /// may be far down a list that has just been built, and a list rebuilt
    /// under the remote has it on the first row the system finds, and
    /// scrolls back there: the list is brought to the awaited row, which is
    /// asked again while the list settles.
    private func requestZapFocus(_ id: String?) {
        zapFocusRequest = id
        guard let id else { return }
        Task { @MainActor in
            for _ in 0..<40 {
                await claimZapFocus(id)
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard zapListVisible, zapFocusRequest == id else { return }
                // A lazy list knows a row it has not built yet by the
                // identity of its channel, not by the name given to the row.
                scrolls.channels?.scrollTo(id, anchor: .center)
            }
            // It never came: the remote stays where the system put it.
            zapFocusRequest = nil
            if let row = zapNativeFocus { zapFocusID = row }
        }
    }
    /// One request. What the system declined still reads as granted in the
    /// binding: it is emptied first, so that the request is made anew.
    private func claimZapFocus(_ id: String) async {
        await Task.yield()
        guard zapListVisible, zapFocusRequest == id, zapNativeFocus != id else { return }
        systemFocus = nil
        await Task.yield()
        guard zapListVisible, zapFocusRequest == id else { return }
        systemFocus = "zap-\(id)"
    }
    /// A row says that it has the remote, or that it lost it: the channel
    /// under the remote is the one OK will show. While a row is awaited, the
    /// one the system falls back on is not a choice.
    private func zapRowFocused(_ id: String, _ focused: Bool) {
        guard focused else { if zapNativeFocus == id { zapNativeFocus = nil }; return }
        zapNativeFocus = id
        if let awaited = zapFocusRequest, awaited != id { return }
        zapFocusRequest = nil
        zapFocusID = id
        armZapListTimer()
    }
    #endif
    /// The picture returns as the list found it: its commands on the key
    /// that opened the list, or nothing over it.
    private func closeZapList() {
        zapListTask?.cancel(); zapListTask = nil
        zapFocusRequest = nil
        guard zapListVisible else { return }
        zapListVisible = false
        guard page == .player else { return }
        if zapOpenedFromKey { revealPlayerControls(on: "zap-list"); return }
        hidePlayerControls()
        // A stream that is opening or has failed keeps its commands on screen.
        if playerControlsVisible { revealPlayerControls(focus: true) } else { focusPicture() }
    }
    #if os(tvOS)
    /// The stream takes the remote back where a message found it: in the
    /// list of channels, on its commands or on the picture. Its panels keep
    /// their own place.
    private func restorePlayerFocus() {
        let key = focusID
        Task { @MainActor in
            await Task.yield()
            guard page == .player, !deskCovered, !playerPanelOpen else { return }
            if zapListVisible { requestZapFocus(zapFocusID) }
            else if playerControlsVisible {
                let id = key.flatMap { playerBarIDs.contains($0) || $0 == "player-back" ? $0 : nil } ?? "playpause"
                holdRemote(on: id) { page == .player && playerControlsVisible && !deskCovered && !playerPanelOpen }
            }
            else { focusPicture() }
        }
    }
    #endif
    /// The list leaves by itself when nothing is done with it.
    private func armZapListTimer(seconds: UInt64 = 12) {
        zapListTask?.cancel()
        zapListTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: patient(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Nothing moves under a message until it is acknowledged.
            if library.alertMessage != nil { armZapListTimer(seconds: seconds); return }
            closeZapList()
        }
    }
    private func zap(to item: IPTVItem) {
        zapFocusID = item.id
        // A list called from the bare picture leaves it bare.
        if !zapOpenedFromKey { zapSurfing = true }
        if item.id != playback.playingItem?.id { playItem(item) }
        armZapListTimer()
    }
    /// "Toutes les chaînes" comes before the first category, and the cycle wraps.
    private func cycleZapCategory(_ delta: Int) {
        let names = groups
        guard !names.isEmpty else { return }
        let count = names.count + 1
        let current = group.flatMap { names.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let next = ((current + delta) % count + count) % count
        if next == 0 { group = nil; clearPreview(); resetCatalogWindow() }
        else { selectLiveGroup(names[next - 1]) }
        zapFocusID = visibleSlice.item(id: playback.playingItem?.id)?.id ?? visible.first?.id
        #if os(tvOS)
        // The rows of the other category replace these under the remote.
        requestZapFocus(zapFocusID)
        #endif
        armZapListTimer()
    }
    private func handleZapList(_ action: RemoteAction) {
        zapKeyboard = true
        switch action {
        case .up, .down:
            let current = zapFocusID ?? playback.playingItem?.id
            let target = visibleSlice.adjacent(to: current, offset: action == .down ? 1 : -1)
                ?? visibleSlice.item(id: current) ?? visible.first
            zapFocusID = target?.id
        case .left: cycleZapCategory(-1)
        case .right: cycleZapCategory(1)
        case .select, .playPause:
            if let item = visibleSlice.item(id: zapFocusID) { zap(to: item) }
        case .back, .home: closeZapList(); return
        default: break
        }
        armZapListTimer()
    }

    private var zapList: some View {
        let playingID = zapPlayingID
        let anchor = zapFocusID ?? playingID
        let size = 60
        let pageIndex = anchor.flatMap { visibleSlice.page(for: $0, size: size) } ?? 0
        let window = visibleSlice.window(page: pageIndex, size: size)
        return VStack(alignment: .leading, spacing: Desk.pt(10)) {
            HStack(spacing: Desk.pt(6)) {
                zapHeaderButton("chevron.left", title: "Catégorie précédente") { cycleZapCategory(-1) }
                VStack(spacing: 2) {
                    Text(group ?? library.selectedPreset?.name ?? "Toutes les chaînes").font(Desk.font(.headline)).lineLimit(1)
                    Text("\(visible.count) \(visible.count == 1 ? "chaîne" : "chaînes")").font(Desk.font(.caption)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                zapHeaderButton("chevron.right", title: "Catégorie suivante") { cycleZapCategory(1) }
                #if !os(tvOS)
                zapHeaderButton("xmark", title: "Fermer la liste des chaînes") { closeZapList() }
                #endif
            }
            ScrollViewReader { reader in
                let _ = (scrolls.channels = reader)
                ScrollView {
                    LazyVStack(spacing: Desk.pt(6)) {
                        ForEach(window) { item in
                            zapRow(item, playing: item.id == playingID,
                                   first: item.id == window.first?.id, last: item.id == window.last?.id)
                        }
                    }.padding(.horizontal, Desk.pt(10)).padding(.vertical, Desk.pt(6))
                }
                // Another category or another sixty channels is another list,
                // from its top: one that kept the place of the last would
                // show nothing where the new one is shorter.
                .id("\(group ?? "")|\(pageIndex)")
                // A lazy list knows a row it has not built yet by the identity
                // of its channel, not by the name given to the row.
                .onAppear { if let anchor { reader.scrollTo(anchor, anchor: .center); reader.scrollTo("zap-\(anchor)", anchor: .center) } }
                #if !os(tvOS)
                .onChange(of: zapFocusID) { _, id in
                    // A pointer never moves the list under itself.
                    guard zapKeyboard, let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { reader.scrollTo("zap-\(id)", anchor: .center) }
                }
                #endif
            }
            Text(zapHint)
                .font(Desk.font(.caption2)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        .padding(Desk.pt(12)).frame(width: Desk.pt(460))
        .frame(maxHeight: .infinity)
        .fluxMediaGlass(radius: Desk.pt(28))
        .padding(playerChromeInset)
        #if !os(tvOS)
        // A drawer: it stays under the pointer and retracts soon after it.
        .onHover { inside in armZapListTimer(seconds: inside ? 12 : 2) }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Liste des chaînes")
    }
    private var zapHint: String {
        #if os(tvOS)
        // Two lines by design: one would break after a separator.
        "Haut, bas : choisir  ·  OK : regarder\nGauche, droite : catégorie  ·  Retour : fermer"
        #else
        "↑ ↓ choisir  ·  Entrée regarder  ·  ← → catégorie  ·  Échap fermer"
        #endif
    }

    @ViewBuilder private func zapHeaderButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        let glyph = Image(systemName: symbol).font(Desk.system(13, .bold))
            .frame(width: Desk.pt(32), height: Desk.pt(32))
            .background(.white.opacity(0.12), in: Circle())
        #if os(tvOS)
        // Left and Right of the remote change the category from any row:
        // these are signs of it, and the remote never leaves the channels.
        glyph.foregroundStyle(.white.opacity(0.75)).accessibilityHidden(true)
        #else
        Button(action: action) { glyph.contentShape(Circle()) }
            .buttonStyle(FluxBareButtonStyle()).foregroundStyle(.white)
            .accessibilityLabel(title).fluxHelp(title)
        #endif
    }

    #if os(tvOS)
    /// The remote walks the rows by itself. At an end of the sixty that are
    /// built, the list turns its page and the next channel takes the remote.
    private func zapWalk(_ delta: Int, from item: IPTVItem, atEnd: Bool) {
        zapFocusRequest = nil
        guard atEnd, let target = visibleSlice.adjacent(to: item.id, offset: delta) else { return }
        zapFocusID = target.id
        requestZapFocus(target.id)
        armZapListTimer()
    }
    #endif

    private func zapRow(_ item: IPTVItem, playing: Bool, first: Bool, last: Bool) -> some View {
        let highlighted = zapFocusID == item.id
        return Button { zap(to: item) } label: {
            LiveTVChannelRow(item: item, number: (visibleSlice.index(of: item.id) ?? 0) + 1,
                             favorite: library.isFavorite(item), highlighted: highlighted, accent: themeAccent)
                .overlay(alignment: .trailing) {
                    if playing {
                        Image(systemName: "play.fill").font(Desk.font(.caption2)).foregroundStyle(themeAccent)
                            .padding(Desk.pt(6)).background(.black.opacity(0.55), in: Circle()).padding(.trailing, Desk.pt(34))
                    }
                }
                #if os(tvOS)
                .background(DeskFocusReport { zapRowFocused(item.id, $0) })
                #endif
        }
        .buttonStyle(FluxBareButtonStyle())
        .id("zap-\(item.id)")
        .zIndex(highlighted ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: highlighted)
        #if os(tvOS)
        // The remote walks the list; Left and Right, which lead nowhere in
        // it, change the category.
        .focused(nativeFocus, equals: "zap-\(item.id)").focusEffectDisabled()
        .onAppear { if zapFocusRequest == item.id { Task { @MainActor in await claimZapFocus(item.id) } } }
        .onMoveCommand { direction in
            switch direction {
            case .left: cycleZapCategory(-1)
            case .right: cycleZapCategory(1)
            case .up: zapWalk(-1, from: item, atEnd: first)
            case .down: zapWalk(1, from: item, atEnd: last)
            @unknown default: break
            }
        }
        #else
        .onHover { inside in
            if inside { zapKeyboard = false; zapFocusID = item.id; armZapListTimer() }
        }
        #endif
        .accessibilityLabel(item.name).accessibilityValue(playing ? "En cours" : "")
        .accessibilityIdentifier("zap-channel-\(item.id)")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "zap-channel-\(item.id)").allowsHitTesting(false))
        #endif
    }

    private var playerControlsVisible: Bool {
        if cinemaControls || voiceOverEnabled { return true }
        // A stream that opens, waits or fails keeps its commands on screen,
        // but not while the channels are walked: the banner says it then.
        return !zapSurfing && (playback.opening || !playback.isPlaying || playback.playbackError != nil)
    }
    /// The banner stands alone at the foot of the bare picture: when the
    /// channel has just changed, and for as long as it opens or fails.
    private var liveBannerShown: Bool {
        guard !playerChromeShown, !playerCovered, series == nil, playback.playingItem?.kind == .live else { return false }
        if zapSurfing { return zapBanner || playback.opening || playback.playbackError != nil }
        return zapBanner && playback.playbackError == nil
    }
    private var narrowPlayer: Bool { playerWidth < 520 }
    private var playerChromeInset: CGFloat {
        #if os(iOS)
        return narrowPlayer ? 10 : 20
        #else
        // What is written over the picture keeps the margin of a television.
        return narrowPlayer ? 10 : Desk.tv(34)
        #endif
    }
    /// Keys of the bar, by group: the channels, the transport, the options.
    private var playerBarGroups: [[String]] {
        let item = playback.playingItem
        var groups: [[String]] = []
        if item?.kind == .live {
            if series == nil && !narrowPlayer { groups.append(["zap-list"]) }
            groups.append(["previous", "playpause", "next"])
        } else if series != nil && !narrowPlayer {
            groups.append(["previous", "rewind", "playpause", "forward", "next"])
        } else {
            // A film has no neighbour worth a key: the catalogue is one Back away.
            groups.append(["rewind", "playpause", "forward"])
        }
        var options: [String] = []
        if item != nil && !narrowPlayer { options.append("favorite-toggle") }
        options.append(PlayerTracks.buttonID)
        options.append("engine")
        #if !os(tvOS)
        options.append("mute")
        #endif
        groups.append(options)
        return groups
    }
    private var playerBarIDs: [String] { playerBarGroups.flatMap { $0 } }
    private var playerBarWidth: CGFloat {
        let groups = playerBarGroups
        let keys = CGFloat(groups.reduce(0) { $0 + $1.count })
        if narrowPlayer { return keys * 46 + (keys - 1) * 2 }
        let separators = CGFloat(max(0, groups.count - 1))
        return keys * PlayerActionLabel.width + (keys - 1 - separators) * Desk.pt(2) + separators * Desk.pt(21)
    }
    private var playerTrackRows: [[String]] {
        PlayerTracks.rows(audio: playback.audioTracks, subtitles: playback.subtitleTracks, canBeOff: playback.subtitlesCanBeOff)
    }

    /// Back, what is on screen, and the time: nothing else stands on the picture.
    private var playerHeading: some View {
        HStack(alignment: .center, spacing: Desk.pt(14)) {
            playerPill("player-back", symbol: "chevron.backward", title: narrowPlayer ? nil : "Retour")
            playerTitle
            Spacer(minLength: Desk.pt(8))
            #if !os(tvOS)
            playerPill("player-full", symbol: playerButtonLabel("player-full").icon, title: nil)
            #endif
            if !narrowPlayer {
                TimelineView(.everyMinute) { context in
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .font(Desk.font(.callout, .bold).monospacedDigit())
                        .padding(.horizontal, Desk.pt(15)).frame(height: Desk.pt(40))
                        .fluxMediaGlass(radius: Desk.pt(20))
                }
                .accessibilityHidden(true)
            }
        }
        #if os(tvOS)
        .focusSection()
        #else
        .onHover { playerControlHover("heading", inside: $0) }
        #endif
    }

    private var playerTitle: some View {
        let item = playback.playingItem
        return HStack(spacing: Desk.pt(12)) {
            if let item, item.kind == .live, !narrowPlayer {
                ArtworkView(url: item.logoURL, fit: true) { Image(systemName: "tv").font(Desk.font(.title3)).foregroundStyle(.white.opacity(0.7)) }
                    .frame(width: Desk.pt(52), height: Desk.pt(38))
                    .padding(Desk.pt(5))
                    .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
            }
            VStack(alignment: .leading, spacing: Desk.pt(2)) {
                Text(item?.name ?? "Lecteur").font(Desk.font(narrowPlayer ? .headline : .title2, .bold)).lineLimit(1)
                if !narrowPlayer { playerSubtitle }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.65), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }

    /// Under the title: the direct and its number, or where a film or an
    /// episode stands in its catalogue.
    @ViewBuilder private var playerSubtitle: some View {
        if let item = playback.playingItem {
            if item.kind == .live {
                HStack(spacing: Desk.pt(7)) {
                    Circle().fill(.red).frame(width: Desk.pt(8), height: Desk.pt(8))
                    Text("EN DIRECT").font(Desk.font(.caption, .bold)).tracking(0.8)
                    Text(([visibleSlice.index(of: item.id).map { "N° \($0 + 1)" }, item.group.isEmpty ? nil : item.group] as [String?])
                        .compactMap { $0 }.joined(separator: "  ·  "))
                        .font(Desk.font(.caption)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                }
            } else {
                // The category of a film often repeats its genre.
                let genre = item.details.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let parts: [String?] = series != nil
                    ? [series?.name, item.seasonNumber.map { "Saison \($0)" }, item.episodeNumber.map { "Épisode \($0)" }]
                    : [item.details.year, item.details.duration, genre.isEmpty ? item.group : genre]
                let line = parts.compactMap { value -> String? in
                    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "0" else { return nil }
                    return text
                }.prefix(3).joined(separator: "  ·  ")
                if !line.isEmpty { Text(line).font(Desk.font(.caption)).foregroundStyle(.white.opacity(0.78)).lineLimit(1) }
            }
        }
    }

    private func playerPill(_ id: String, symbol: String, title: String?) -> some View {
        let selected = playerButtonFocused(id) || hoveredPlayerButton == id
        let label = playerButtonLabel(id)
        return Button {
            pointerSelect(id); activateFocus()
            if page == .player { revealPlayerControls() }
        } label: {
            FluxFocused(id: id, logical: selected) { lit in
                HStack(spacing: Desk.pt(7)) {
                    Image(systemName: symbol).font(Desk.font(.callout, .bold))
                    if let title { Text(title).font(Desk.font(.callout, .semibold)).lineLimit(1) }
                }
                .foregroundStyle(lit ? Color.black : .white)
                .padding(.horizontal, Desk.pt(title == nil ? 12 : 15)).frame(minWidth: Desk.pt(40), minHeight: Desk.pt(40))
                .background(lit ? Color.white : Color.clear, in: Capsule())
                .fluxMediaGlass(radius: Desk.pt(20))
                .scaleEffect(lit && !reduceMotion ? 1.06 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: lit)
            }
        }
        .buttonStyle(FluxBareButtonStyle())
        .fluxFocus(nativeFocus, id: id).id(id)
        .accessibilityLabel(label.title).fluxHelp(label.title)
        .accessibilityIdentifier("player-\(id)")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "player-\(id)").allowsHitTesting(false))
        #endif
        #if !os(tvOS)
        .onHover { inside in hoveredPlayerButton = inside ? id : (hoveredPlayerButton == id ? nil : hoveredPlayerButton) }
        #endif
    }

    /// The bar under the picture: a dock of what can be done while watching.
    private var playerBar: some View {
        let groups = playerBarGroups
        return VStack(spacing: Desk.pt(10)) {
            if playback.seekable && !playback.opening && playback.playbackError == nil {
                playerTimeline.frame(width: max(playerBarWidth, min(Desk.pt(560), playerWidth - 80)))
            }
            HStack(spacing: narrowPlayer ? 2 : Desk.pt(2)) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 && !narrowPlayer {
                        Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: Desk.pt(40))
                            .padding(.horizontal, Desk.pt(10)).padding(.bottom, Desk.pt(18))
                    }
                    ForEach(group, id: \.self) { id in playerButton(id) }
                }
            }
        }
        .padding(.horizontal, narrowPlayer ? 8 : Desk.pt(16)).padding(.top, Desk.pt(12)).padding(.bottom, Desk.pt(9))
        .fluxMediaGlass(radius: Desk.pt(30))
        #if os(tvOS)
        .frame(maxWidth: .infinity)
        .focusSection()
        #else
        .onHover { playerControlHover("dock", inside: $0) }
        #endif
    }

    private var playerTimeline: some View {
        HStack(spacing: Desk.pt(12)) {
            Text(playback.elapsed).font(Desk.font(.caption).monospacedDigit())
            #if os(tvOS)
            PlayerProgressTrack(fraction: playback.position)
                .accessibilityElement()
                .accessibilityLabel("Progression")
                .accessibilityValue(playback.elapsed + " sur " + playback.duration)
            #else
            Slider(value: $scrubPosition, in: 0...1, onEditingChanged: { editing in
                scrubbing = editing
                if !editing { playback.seek(scrubPosition) }
                revealPlayerControls()
            }).labelsHidden().tint(.white)
                .accessibilityLabel("Position de lecture")
            #endif
            Text(playback.duration).font(Desk.font(.caption).monospacedDigit())
        }
        .foregroundStyle(.white)
    }

    private var playerTracksPanel: some View {
        PlayerTracksPanel(audio: playback.audioTracks, subtitles: playback.subtitleTracks,
                          subtitlesCanBeOff: playback.subtitlesCanBeOff,
                          focusedID: focusShown || playerPanelFocusNative ? playerFocusedID : nil,
                          systemFocus: nativeFocus, accent: themeAccent,
                          selectAudio: { playback.selectAudioTrack($0) },
                          selectSubtitle: { playback.selectSubtitleTrack($0) },
                          close: { closePlayerTracks() })
        #if os(tvOS)
        .frame(maxWidth: .infinity)
        #else
        .onHover { playerControlHover("tracks", inside: $0) }
        #endif
    }
    /// The remote shows its own focus; a keyboard shows the selection it moves.
    private var playerPanelFocusNative: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
    /// Row of a panel of the player that the keyboard has selected; the
    /// panel reads the focus of a television by itself.
    private var playerFocusedID: String? {
        #if os(tvOS)
        nil
        #else
        remoteNavigationActive ? focusID : nil
        #endif
    }

    private func openPlayerTracks() {
        guard page == .player else { return }
        playerControlsTask?.cancel(); playerControlsTask = nil
        if !cinemaControls { cinemaControls = true }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { playerTracks = true }
        let target = PlayerTracks.entry(audio: playback.audioTracks, subtitles: playback.subtitleTracks,
                                        canBeOff: playback.subtitlesCanBeOff)
        focusID = target
        Task { @MainActor in
            await Task.yield()
            guard page == .player, playerTracks else { return }
            systemFocus = target
        }
    }
    private func closePlayerTracks() {
        guard playerTracks else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { playerTracks = false }
        revealPlayerControls(on: PlayerTracks.buttonID)
    }
    /// The settings leave the picture: the remote returns to the key that
    /// opened them, and the commands hide again after their delay.
    private func closePlayerSettings() {
        guard playerSettings != nil else { return }
        playerSettings = nil
        revealPlayerControls(on: "engine")
    }

    private func playerButton(_ id: String) -> some View {
        let label = playerButtonLabel(id)
        return Button {
            pointerSelect(id)
            activateFocus()
            if page == .player { revealPlayerControls() }
        } label: {
            FluxFocused(id: id, logical: playerButtonFocused(id) || hoveredPlayerButton == id) { lit in
                PlayerActionLabel(symbol: label.icon, title: label.short, prominent: id == "playpause",
                                  highlighted: lit,
                                  active: playerButtonActive(id), tint: id == "favorite-toggle" ? .yellow : themeAccent,
                                  compact: narrowPlayer)
            }
        }
        .buttonStyle(FluxBareButtonStyle())
        .fluxFocus(nativeFocus, id: id).id(id)
        .accessibilityLabel(label.title).fluxHelp(label.title)
        .accessibilityIdentifier("player-\(id)")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "player-\(id)").allowsHitTesting(false))
        #endif
        .disabled((id == "rewind" || id == "forward") && !playback.seekable)
        #if !os(tvOS)
        .onHover { inside in hoveredPlayerButton = inside ? id : (hoveredPlayerButton == id ? nil : hoveredPlayerButton) }
        #endif
    }
    /// `title` is spoken and shown as a tip; `short` is written under the key.
    private func playerButtonLabel(_ id: String) -> (title: String, icon: String, short: String) {
        let live = playback.playingItem?.kind == .live
        switch id {
        case "player-back": return ("Retour", "chevron.backward", "Retour")
        case "player-full": return cinema ? ("Quitter le plein écran", "arrow.down.right.and.arrow.up.left", "Fenêtre") : ("Plein écran", "arrow.up.left.and.arrow.down.right", "Plein écran")
        case "previous": return live ? ("Chaîne précédente", "backward.end.fill", "Précédente") : ("Épisode précédent", "backward.end.fill", "Précédent")
        case "next": return live ? ("Chaîne suivante", "forward.end.fill", "Suivante") : ("Épisode suivant", "forward.end.fill", "Suivant")
        case "rewind": return ("Reculer de \(playback.settings.skipSeconds) secondes", "gobackward", "−\(playback.settings.skipSeconds) s")
        case "forward": return ("Avancer de \(playback.settings.skipSeconds) secondes", "goforward", "+\(playback.settings.skipSeconds) s")
        case "playpause": return playback.isPlaying ? ("Pause", "pause.fill", "Pause") : ("Lecture", "play.fill", "Lecture")
        case "mute": return playback.muted ? ("Rétablir le son", "speaker.slash.fill", "Son") : ("Couper le son", "speaker.wave.2.fill", "Son")
        case "zap-list": return ("Liste des chaînes", "list.bullet", "Chaînes")
        case "favorite-toggle":
            let favorite = playback.playingItem.map { library.isFavorite($0) } ?? false
            return favorite ? ("Retirer des favoris", "star.fill", "Favori") : ("Ajouter aux favoris", "star", "Favori")
        case PlayerTracks.buttonID: return ("Audio et sous-titres", "captions.bubble", "Langues")
        default: return ("Réglages du lecteur", "gearshape", "Réglages")
        }
    }
    private func playerButtonActive(_ id: String) -> Bool {
        switch id {
        case "favorite-toggle": return playback.playingItem.map { library.isFavorite($0) } ?? false
        case "mute": return playback.muted
        case "zap-list": return zapListVisible
        default: return false
        }
    }
    /// A key of the player selected with the keyboard; on a television the
    /// key shows the focus of the system by itself.
    private func playerButtonFocused(_ id: String) -> Bool {
        #if os(tvOS)
        return false
        #else
        return remoteNavigationActive && focusID == id
        #endif
    }
    private func playerControlHover(_ region: String, inside: Bool) {
        if inside { hoveredPlayerControls.insert(region); revealPlayerControls() }
        else {
            hoveredPlayerControls.remove(region)
            // Removing an idle panel sends a final hover exit. It must not
            // immediately resurrect the very controls we have just hidden.
            if cinemaControls { revealPlayerControls() }
        }
    }
    /// A television is read from a sofa and its bar is walked key by key:
    /// the commands stay a little longer there.
    private var playerControlsDelay: UInt64 {
        #if os(tvOS)
        5_000_000_000
        #else
        3_000_000_000
        #endif
    }
    /// A delay within which the remote has to act, as long as on a device.
    /// Only a remote flow on a slow machine stretches it.
    private func patient(_ nanoseconds: UInt64) -> UInt64 {
        #if FLUX_CATALOG_UI_TESTING
        UInt64(Double(nanoseconds) * FluxFixturePatience.factor)
        #else
        nanoseconds
        #endif
    }
    /// The commands stay while a capture or a remote flow needs them.
    private var playerControlsHeld: Bool {
        #if FLUX_CATALOG_UI_TESTING
        fixtureHoldsControls
        #else
        false
        #endif
    }
    /// `on`: the key that receives the remote; `focus` alone means play/pause.
    private func revealPlayerControls(focus: Bool = false, on target: String? = nil) {
        guard page == .player else { return }
        // While the channels are walked nothing brings the commands back by
        // itself; a request made for a key of theirs ends the walk.
        if zapSurfing {
            guard focus || target != nil else { return }
            zapSurfing = false
        }
        playerControlsTask?.cancel()
        if !cinemaControls {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { cinemaControls = true }
        }
        if focus || target != nil {
            let id = target ?? "playpause"
            focusID = id
            #if os(tvOS)
            holdRemote(on: id) { page == .player && playerControlsVisible && !modalOpen && !playerCovered }
            #else
            Task { @MainActor in
                await Task.yield()
                guard page == .player, playerControlsVisible, !modalOpen, !playerCovered else { return }
                systemFocus = id
            }
            #endif
        }
        guard playback.isPlaying, !playback.opening, playback.playbackError == nil, !playerCovered, !playerControlsHeld,
              hoveredPlayerControls.isEmpty, !scrubbing, !modalOpen, !voiceOverEnabled else { return }
        playerControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: patient(playerControlsDelay))
            guard !Task.isCancelled, page == .player, playback.isPlaying,
                  !playback.opening, playback.playbackError == nil, !playerCovered,
                  hoveredPlayerControls.isEmpty, !scrubbing, !modalOpen, !voiceOverEnabled else { return }
            hidePlayerControls()
        }
    }
    private func hidePlayerControls() {
        guard zapSurfing || (playback.isPlaying && !playback.opening && playback.playbackError == nil),
              !playerCovered, !playerControlsHeld, !scrubbing, !modalOpen, !voiceOverEnabled else { return }
        playerControlsTask?.cancel(); playerControlsTask = nil
        hoveredPlayerControls.removeAll()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { cinemaControls = false }
        focusID = "cinema-controls"
        focusPicture()
    }
    /// The bare picture takes the remote: the control that waits there comes
    /// back with this update, and can take the focus only after it.
    private func focusPicture() {
        #if os(tvOS)
        holdRemote(on: "cinema-controls") { page == .player && !playerControlsVisible && !playerCovered }
        #else
        Task { @MainActor in
            await Task.yield()
            guard page == .player, !playerControlsVisible, !playerCovered else { return }
            systemFocus = "cinema-controls"
        }
        #endif
    }
    #if os(tvOS)
    /// Hands the remote to a control of the player, and asks again until
    /// that control says it has it. The system declines a request made
    /// before the control can take it, the sooner as the Apple TV is
    /// slow, and the binding then reads as if the request had been
    /// granted: the remote was nowhere, on a screen that showed nothing
    /// selected. Only for controls that report to the ledger: the keys of
    /// the player, the picture, the titles of the catalogue.
    private func holdRemote(on id: String, inCatalogue: Bool = false, while valid: @escaping () -> Bool) {
        remoteHold = id
        Task { @MainActor in
            for _ in 0..<15 {
                await Task.yield()
                guard remoteHold == id, valid() else { break }
                if FluxFocusLedger.shared.real == id { break }
                // A lazy list has to build the cell before it can answer.
                if inCatalogue { scrolls.pane?.scrollTo(id, anchor: .center) }
                systemFocus = nil
                await Task.yield()
                guard remoteHold == id, valid() else { break }
                systemFocus = id
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if remoteHold == id { remoteHold = nil }
        }
    }
    #endif

    private var groupsPanel: some View {
        panel("Catégories · \(library.contentKind.frenchTitle)") {
            TextField("Filtrer les catégories", text: $library.groupSearch).fluxFieldStyle()
            Button("Toutes les catégories") { group = nil; showingGroups = false }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groups.filter { groupSearch.isEmpty || $0.localizedStandardContains(groupSearch) }, id: \.self) { name in
                    Button { if library.contentKind == .live { selectLiveGroup(name) } else { group = name }; showingGroups = false } label: { HStack { Text(name).lineLimit(2); Spacer(); if group == name { Image(systemName: "checkmark") } }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                }
            }
            Button("Fermer") { showingGroups = false }
        }
    }
    private var sourcesPanel: some View {
        panel("Sources") {
            ForEach(library.sources) { source in
                HStack {
                    Button { showingSources = false; Task { await library.selectSource(source.id) } } label: { Label(source.name, systemImage: source.symbol).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
                    if source.kind != .m3uFile { Button("Modifier") { showingSources = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editingSource = source } } }
                    Button(role: .destructive) { library.removeSource(source) } label: { Image(systemName: "trash") }
                }
            }
            Button("Ajouter une source") { showingSources = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addingSource = true } }.buttonStyle(.borderedProminent)
            Button("Fermer") { showingSources = false }
        }
    }
    private var listsPanel: some View {
        panel("Listes · \(library.contentKind.frenchTitle)") {
            Button("Catalogue complet") { showAllCatalog(); showingLists = false }
            ForEach(library.currentPresets) { preset in
                HStack {
                    Button {
                        if library.contentKind == .live { selectLivePreset(preset.id) }
                        else { continueOnly=false; group=nil; library.selectedPresetID = preset.id }
                        showingLists = false
                    } label: { Label(preset.name + " (\(preset.itemIDs.count))", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
                    if !preset.isDefault {
                        Button("Renommer") { showingLists = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presetEditor = PresetEditor(kind: preset.kind, existing: preset) } }
                        Button(role: .destructive) { showingLists = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { deletingPreset = preset } } label: { Image(systemName: "trash") }
                    }
                }
            }
            Button("Nouvelle liste") { showingLists = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presetEditor = PresetEditor(kind: library.contentKind, existing: nil) } }.buttonStyle(.borderedProminent)
            Button("Fermer") { showingLists = false }
        }
    }
    private func itemPanel(_ item: IPTVItem) -> some View {
        FavoriteAssignmentSheet(item: item, open: {
            itemOptions = nil; openItem(item)
        }, saved: favoritesSaved, inlineClose: usesDesk ? { itemOptions = nil } : nil,
        dockChoices: dockChoices(for: item), dockPreferred: itemDockExtra?.id).environmentObject(library)
    }
    private var enginesPanel: some View {
        PlaybackSettingsView(playback: playback, startAtDiagnostic: diagnosticSettings) { showingEngines = false }
            .environmentObject(library)
    }
    private func panel<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) { Text(title).font(.title.bold()); content() }.padding(28).frame(maxWidth: .infinity, alignment: .leading) }.fluxSheetSize(width: 680, height: 500)
    }
    private func mediaIcon(_ kind: IPTVMediaKind) -> String { switch kind { case .live: "tv"; case .movie: "film"; case .series: "rectangle.stack" } }
    private func updateColumns(_ width: CGFloat) {
        let usable = width - (showRemote && width >= 800 ? 215 : 0)
        compactChrome = usable < 900
        #if os(macOS) || os(tvOS)
        updateDeskColumns(usable)
        #else
        updateLegacyColumns(usable)
        #endif
    }
    private func updateLegacyColumns(_ usable: CGFloat) {
        #if os(tvOS)
        liveSidebarVisible = false
        #else
        liveSidebarVisible = library.contentKind == .live && usable >= 920
        #endif
        if library.contentKind == .live {
            let channelWidth = usable - (televisionLayout ? 92 : 48) - (liveSidebarVisible ? liveSidebarWidth + 18 : 0)
            #if os(tvOS)
            let minimumTile: CGFloat = 360
            let gap: CGFloat = 24
            #else
            let minimumTile: CGFloat = 274
            let gap: CGFloat = 12
            #endif
            let estimated = (channelWidth + gap) / (minimumTile + gap)
            columns = estimated.isFinite ? Int(max(1, min(televisionLayout ? 4 : 6, estimated))) : 3
        } else {
            let estimated = (usable - 32 + 4) / (cardWidth + 4)
            columns = estimated.isFinite ? Int(max(2, min(10, estimated))) : 5
        }
    }
    private func pointerSelect(_ id: String) {
        cancelBrowsingRestore()
        #if !os(tvOS)
        remoteNavigationActive = false
        #endif
        zoneMode = false
        focusID = id
    }
    private func changeKind(_ kind: IPTVMediaKind) {
        library.flushBrowsingPreferences()
        home()
        library.contentKind = kind
        restoreBrowsingContext()
    }
    /// Wait for the matching source and filters before restoring a channel or
    /// poster. A remembered selection never opens a player on app launch.
    private func restoreBrowsingContext() {
        browseRestoreTask?.cancel()
        #if os(tvOS)
        pendingBrowseFocus = nil
        #endif
        pendingBrowseRestore = true
        pendingCatalogFocus = nil
        showingSearch = !library.search.isEmpty
        // A failed load has no focus destination to wait for. Release the
        // pending state so reconnect/error controls keep normal navigation.
        // A later source selection or successful install starts restoration
        // again through selectedSourceID/browsingRevision observations.
        if library.sources.isEmpty || library.credentialIssue != nil ||
           (!library.browsingCatalogReady && !library.isLoading) {
            cancelBrowsingRestore()
            return
        }
        guard library.browsingCatalogReady, !library.isLoading, !library.isFiltering, !library.sources.isEmpty,
              library.credentialIssue == nil else { return }
        let revision = library.browsingRevision
        let source = library.selectedSourceID
        let kind = library.contentKind
        let context = catalogFocusContext
        let rememberedItemID = library.browseItemID
        browseRestoreTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, library.browsingRevision == revision,
                  library.selectedSourceID == source, library.contentKind == kind,
                  catalogFocusContext == context,
                  !library.isLoading, !library.isFiltering, page == .catalogue,
                  heldItem == nil, !modalOpen else { return }
            rebuildResumeSlice()
            catalogPage = min(catalogPage, catalogPageCount - 1)
            let target: String
            if let item = visibleSlice.item(id: rememberedItemID) {
                revealCatalogItem(item.id)
                setPreview(item)
                target = item.id
            } else {
                #if os(tvOS)
                // Nothing is remembered here: the remote starts on the first
                // title, in the content, rather than on a control beside it.
                if let first = visible.first {
                    revealCatalogItem(first.id)
                    setPreview(first)
                    target = first.id
                } else { target = "tab-\(kind.rawValue)" }
                #else
                target = "tab-\(kind.rawValue)"
                #endif
            }
            browseRestoreTask = nil
            #if os(tvOS)
            if target.hasPrefix("tab-") {
                // An empty section: its key of the dock is always on screen.
                pendingBrowseFocus = nil
                pendingBrowseRestore = false
                focusID = target
                systemFocus = target
                return
            }
            pendingBrowseFocus = BrowseRestoreFocusRequest(revision: revision, context: context, targetID: target)
            focusID = target
            // A return to the same remembered item does not change the
            // selection: its cell, which a lazy list has yet to build, is
            // brought on screen all the same.
            scrolls.pane?.scrollTo(target, anchor: .center)
            resolveBrowseRestoreFocus()
            #else
            focusID = target
            searchFocus = false
            liveGroupSearchFocus = false
            systemFocus = target
            pendingBrowseRestore = false
            #endif
        }
    }
    #if os(tvOS)
    private func browseFocusTargetAppeared(_ id: String) {
        mountedBrowseFocusTargets.insert(id)
        resolveBrowseRestoreFocus()
    }
    /// Gives the remote to a title of the catalogue when the catalogue comes
    /// back on screen, after a stream or the shelf of a series. Its cell
    /// returns with that update and cannot take the focus yet: tvOS 26 then
    /// settles on a control beside the list. The catalogue already waits for
    /// the cell of the title it remembers: this title becomes that one, be
    /// it a channel reached by zapping, which the catalogue never selected.
    private func focusWhenBackOnScreen(_ id: String) {
        library.browseItemID = id
        // The cell that was on screen before left with its page.
        mountedBrowseFocusTargets.remove(id)
        browserHasEnteredFocus = true
        focusID = id
        restoreBrowsingContext()
    }
    private func resolveBrowseRestoreFocus() {
        guard pendingBrowseRestore, let request = pendingBrowseFocus else { return }
        guard request.revision == library.browsingRevision, request.context == catalogFocusContext else {
            cancelBrowsingRestore()
            return
        }
        guard !library.isLoading, !library.isFiltering, page == .catalogue,
              heldItem == nil, !modalOpen, browserHasEnteredFocus,
              mountedBrowseFocusTargets.contains(request.targetID) else { return }
        // Consume before writing: subsequent remote navigation, including a
        // deliberate move back into Search, must never be pulled to this item.
        pendingBrowseFocus = nil
        pendingBrowseRestore = false
        searchFocus = false
        liveGroupSearchFocus = false
        focusID = request.targetID
        sendRemote(to: request.targetID) { page == .catalogue && heldItem == nil && !modalOpen }
    }
    #endif
    private func cancelBrowsingRestore() {
        browseRestoreTask?.cancel()
        browseRestoreTask = nil
        pendingBrowseRestore = false
        #if os(tvOS)
        pendingBrowseFocus = nil
        #endif
    }
    private func focusFirstItem() {
        guard page == .catalogue, heldItem == nil, !modalOpen, !searchFocus, !liveGroupSearchFocus else { return }
        cancelBrowsingRestore()
        pendingCatalogFocus = catalogFocusContext
        resolveCatalogFocus()
    }
    private func resolveCatalogFocus() {
        guard let request = pendingCatalogFocus else { return }
        guard request == catalogFocusContext, page == .catalogue, heldItem == nil,
              !modalOpen, !searchFocus, !liveGroupSearchFocus else {
            pendingCatalogFocus = nil
            return
        }
        guard !library.isFiltering else { return }
        let target = visible.first?.id ?? "tab-\(library.contentKind.rawValue)"
        // Publish the destination in the results transaction. In particular,
        // an empty list must move toward its existing header before the native
        // engine can fall back to the search field and cancel this handoff.
        focusID = target
        Task { @MainActor in
            await Task.yield()
            guard pendingCatalogFocus == request else { return }
            guard request == catalogFocusContext, page == .catalogue, heldItem == nil,
                  !library.isFiltering, !modalOpen,
                  !searchFocus, !liveGroupSearchFocus else {
                pendingCatalogFocus = nil
                return
            }
            // The native engine may briefly choose a header while the new
            // result mounts. Apply both focus states after that view update.
            let alreadyFocused = systemFocus == target
            focusID = target
            systemFocus = target
            // A changed binding is acknowledged by onChange(systemFocus).
            // If it already names the target, there will be no change event.
            if alreadyFocused {
                pendingCatalogFocus = nil
                #if FLUX_CATALOG_UI_TESTING
                reportSearchFocusFixture()
                #endif
            }
        }
    }
    #if FLUX_CATALOG_UI_TESTING
    private func reportSearchFocusFixture(keysPlayed: Bool = false) {
        fixtureSearchObservation?(CatalogSearchFocusSnapshot(focusID: focusID, nativeFocusID: systemFocus, query: library.search,
            filtering: library.isFiltering, pending: pendingCatalogFocus != nil, heldItemID: heldItem?.id, keysPlayed: keysPlayed))
    }
    #endif
    private func search() {
        guard !modalOpen else { return }
        cancelBrowsingRestore()
        cancelEntrance()
        if page != .catalogue { home() } else { dismissCaseImmediately() }
        liveGroupSearchFocus = false
        showingSearch = !usesDesk && (televisionLayout || library.contentKind != .live); searchFocus = true
        #if os(macOS) || os(tvOS)
        // The field may only mount with this update, after leaving the settings.
        sidebarCountries = false
        Task { @MainActor in
            await Task.yield()
            guard page == .catalogue, heldItem == nil else { return }
            searchFocus = true
        }
        #endif
    }
    private func openItem(_ item: IPTVItem) {
        // While a query is filtering, visibleSlice can still contain the old
        // matches. A quick second OK must not open one of those stale items.
        guard page != .catalogue || !library.isFiltering else { return }
        cancelBrowsingRestore()
        library.selectedItemID = item.id
        setPreview(item)
        if item.isSeriesCollection {loadSeries(item)}
        else if item.kind != .live {showCase(item)}
        else {series=nil;seasons=[];playItem(item)}
    }
    /// `wanted` and `episodeID`: a shortcut of the dock leads to a season
    /// or to an episode, which `play` starts at once.
    private func loadSeries(_ item: IPTVItem, season wanted: Int? = nil, episodeID: String? = nil, play: Bool = false) {
        cancelEntrance();dismissCaseImmediately();livePreview.stop();searchFocus=false
        seriesTask?.cancel()
        let token = UUID(); seriesRequest = token; series = item; page = .series; seasons = []; seasonNumber=nil; episodesFailed = false; episodesLoading = true; focusID = "series-back"
        seriesTask=Task { @MainActor in
            do {
                let result = try await library.seasons(for: item)
                guard !Task.isCancelled,seriesRequest == token, page == .series else { return }
                let asked = result.first { $0.number == wanted && wanted != nil }
                    ?? episodeID.flatMap { id in result.first { $0.episodes.contains { $0.id == id } } }
                let shown = asked ?? result.first
                seasons = result; seasonNumber = shown?.number; episodesLoading = false
                focusID = shown.map(SeriesSeasonShelf.focusID) ?? "series-back"
                if let asked {
                    if play, let episode = asked.episodes.first(where: { $0.id == episodeID }) { playItem(episode) }
                    else { showSeason(asked, episodeID: episodeID) }
                }
            } catch {
                guard !Task.isCancelled,seriesRequest == token,page == .series else{return}
                episodesLoading = false; episodesFailed = true; focusID = "series-retry"
            }
            if seriesRequest == token {seriesTask=nil}
        }
    }
    private func focusSeason(_ season:IPTVSeason) {
        seasonNumber=season.number;pointerSelect(SeriesSeasonShelf.focusID(season))
    }
    private func showSeason(_ season:IPTVSeason,episodeID:String? = nil) {
        guard let collection=series,seasons.contains(where:{$0.number == season.number}) else{return}
        seasonNumber=season.number;focusID=SeriesSeasonShelf.focusID(season)
        showCase(collection,season:season.number,episodeID:episodeID)
    }
    private func playItem(_ item: IPTVItem) {
        livePreview.stop()
        guard !item.isSeriesCollection else { loadSeries(item); return }
        cancelEntrance()
        dismissCaseImmediately()
        do {
            #if FLUX_CATALOG_UI_TESTING
            let urls = playback.simulates(item) ? [] : try library.playbackURLs(for: item)
            #else
            let urls = try library.playbackURLs(for: item)
            #endif
            let entering = page != .player
            guard entering && !reduceMotion else {
                startPlayback(item, urls: urls, entering: entering)
                return
            }
            entranceItem = item; entranceExpanded = false
            entranceTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.42)) { entranceExpanded = true }
                try? await Task.sleep(nanoseconds: 460_000_000)
                guard !Task.isCancelled else { return }
                // The decorative view is removed before the decoder is started.
                entranceItem = nil; entranceExpanded = false
                startPlayback(item, urls: urls, entering: true)
                entranceTask = nil
            }
        }
        catch { library.alertMessage = IPTVLibrary.safeSourceError(error) }
    }
    /// What plays joins the recents of the dock: a film, an episode with
    /// its series, and a channel once it has been watched a moment — a
    /// remote that runs through the channels leaves none behind.
    private func rememberInDock(_ item: IPTVItem) {
        #if os(macOS) || os(tvOS)
        if item.kind == .live {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard page == .player, playback.playingItem?.id == item.id else { return }
                library.visitDock(DockShortcut(item: item))
            }
        } else if item.kind == .movie {
            library.visitDock(DockShortcut(item: item))
        } else if let collection = series, !item.isSeriesCollection {
            library.visitDock(DockShortcut(series: collection, episode: item))
        }
        #endif
    }
    private func startPlayback(_ item: IPTVItem, urls: [URL], entering: Bool) {
        page = .player
        rememberInDock(item)
        // A channel opens as on a television: its picture, bare, under its
        // banner, where Up and Down change channel at once. A film or an
        // episode opens under its commands. VoiceOver keeps them in any case.
        let bare = entering && item.kind == .live && series == nil && !voiceOverEnabled
        // A change of channel keeps the remote where it is: on Suivante, to
        // go on, or in the list.
        if entering { zapSurfing = bare; focusID = bare ? "cinema-controls" : "playpause" }
        playback.play(item, urls: urls)
        if entering && !cinema { toggleCinema() }
        if bare {
            cinemaControls = false
            focusPicture()
        } else {
            #if os(tvOS)
            // Its commands come with this update: they take the remote after it.
            revealPlayerControls(focus: entering)
            #else
            revealPlayerControls()
            #endif
        }
        if item.kind == .live { showZapBanner() }
    }
    private func cancelEntrance() {
        entranceTask?.cancel(); entranceTask = nil
        entranceItem = nil; entranceExpanded = false
    }
    private func showZapBanner() {
        let token=UUID();zapToken=token;withAnimation(.easeInOut(duration:0.18)){zapBanner=true}
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: patient(4_000_000_000))
            guard zapToken==token else{return};withAnimation(.easeOut(duration:0.22)){zapBanner=false}
        }
    }
    /// Shown alone when a channel changes while the commands are hidden.
    @ViewBuilder private var liveBanner: some View {
        if let item = playback.playingItem {
            PlayerChannelBanner(number: visibleSlice.index(of: item.id).map { $0 + 1 },
                                name: item.name, group: item.group, logoURL: item.logoURL,
                                favorite: library.isFavorite(item), status: liveBannerStatus,
                                accent: themeAccent, hints: liveBannerHints, compact: narrowPlayer)
                #if os(tvOS) && FLUX_CATALOG_UI_TESTING
                .background(TVCatalogControlFrameProbe(identifier: "player-banner").allowsHitTesting(false))
                #endif
                .padding(playerChromeInset)
                .allowsHitTesting(false)
        }
    }
    private var liveBannerStatus: PlayerChannelBanner.Status {
        if playback.playbackError != nil { return .failed }
        return playback.opening ? .opening : .live
    }
    /// What the bare picture answers to, written where it is looked at.
    private var liveBannerHints: [PlayerChannelBanner.Hint] {
        #if os(tvOS)
        [.init(symbol: "chevron.up.chevron.down", action: "Chaîne"), .init(symbol: "chevron.left", action: "Liste"),
         .init(text: "OK", action: "Commandes")]
        #elseif os(macOS)
        [.init(text: "↑ ↓", action: "Chaîne"), .init(text: "←", action: "Liste")]
        #else
        []
        #endif
    }
    private func adjacent(_ delta: Int) {
        guard let item = playback.playingItem else { return }
        let target: IPTVItem
        if series != nil {
            let candidates=seasons.flatMap(\.episodes)
            guard let i=candidates.firstIndex(where:{$0.id==item.id}),candidates.indices.contains(i+delta) else{return}
            target=candidates[i+delta]
            if let season=seasons.first(where:{$0.episodes.contains(where:{$0.id==target.id})}) {seasonNumber=season.number}
        } else {
            guard let i=visibleSlice.index(of:item.id),visible.indices.contains(i+delta),!visible[i+delta].isSeriesCollection else{return}
            target=visible[i+delta]
        }
        playItem(target)
    }
    private func home() { playerControlsTask?.cancel(); seriesTask?.cancel(); seriesTask=nil; cancelEntrance(); dismissCaseImmediately(); if cinema { toggleCinema(restoringPreviousWindow: true) }; playback.stop(); page = .catalogue; series = nil; seasons = []; seasonNumber=nil; episodesLoading=false; episodesFailed=false; seriesRequest = UUID(); focusID = "tab-\(library.contentKind.rawValue)" }
    private func back() {
        if entranceItem != nil { cancelEntrance(); return }
        #if os(macOS) || os(tvOS)
        // An open folder of the dock closes first.
        if dockFan != nil { closeDockFan(); return }
        #endif
        if page == .player, playerTracks { closePlayerTracks(); return }
        if page == .player, playerSettings != nil { closePlayerSettings(); return }
        if page == .player, zapListVisible { closeZapList(); return }
        if heldItem != nil {putCaseBack();return}
        switch page {
        case .player: stopPlayback()
        case .series:
            let id = series?.id; home(); focusID = id ?? "tab-series"
            #if os(tvOS)
            if let id, visibleSlice.item(id: id) != nil { focusWhenBackOnScreen(id) }
            #endif
        case .settings:
            leaveSettings()
        case .catalogue:
            // A Back during restored-search filtering must stay closed when
            // those results arrive; the saved query itself remains unchanged.
            cancelBrowsingRestore()
            #if os(macOS) || os(tvOS)
            deskBack()
            #else
            if showingSearch { showingSearch = false; searchFocus = false }
            else { focusID = "tab-\(library.contentKind.rawValue)" }
            #endif
        case .home:
            // Nothing is behind the home screen.
            break
        }
    }
    private func stopPlayback() {
        playerControlsTask?.cancel(); playerControlsTask = nil
        if cinema { toggleCinema(restoringPreviousWindow: true) }
        let lastItem = playback.playingItem
        playback.stop(); page = .catalogue
        if let collection = series {
            page = .series
            if let season=seasons.first(where:{$0.number == seasonNumber}) ?? seasons.first {showSeason(season,episodeID:lastItem?.id)}
            else {loadSeries(collection)}
        }
        else if let item = lastItem, item.kind == .movie { showCase(item) }
        else {
            focusID = lastItem?.id ?? "tab-\(library.contentKind.rawValue)"
            #if os(tvOS)
            if let item = lastItem, visibleSlice.item(id: item.id) != nil { focusWhenBackOnScreen(item.id) }
            // Another category was browsed from the stream and the channel
            // is not in it: the remote goes to the content all the same.
            else { restoreBrowsingContext() }
            #endif
        }
    }
    private func toggleCinema(restoringPreviousWindow: Bool = false) {
        #if !os(tvOS)
        guard page == .player else { return }
        #if os(macOS)
        if cinema { if (!restoringPreviousWindow || !wasFullscreen), let w = NSApp.windows.first(where: { $0.windowNumber == cinemaWindowNumber }), w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }; cinemaWindowNumber = nil; cinema = false }
        else if let w = NSApp.keyWindow { wasFullscreen = w.styleMask.contains(.fullScreen); cinemaWindowNumber = w.windowNumber; cinema = true; if !wasFullscreen { w.toggleFullScreen(nil) } }
        #else
        cinema.toggle()
        #endif
        if !restoringPreviousWindow {
            focusID = "player-full"
            revealPlayerControls()
        }
        #endif
    }
    /// On the desk the pages of films and series stand on the line of the
    /// search; the channels keep theirs in their own panel.
    private var deskPagerInBand: Bool { library.contentKind != .live && !visible.isEmpty && catalogPageCount > 1 }
    private var focusRows: [[String]] {
        if library.sources.isEmpty { return [["add-source"]] }
        var rows: [[String]] = []
        if page != .player && !cinema && !usesDesk {
            if compactNavigation {
                rows.append(["navigation-more"])
            } else {
            #if os(tvOS)
                rows.append(["sources", "lists", "settings"])
            #else
                rows.append(["sources", "remote"] + (library.contentKind != .live || (browserHeight < 580 && !liveSidebarVisible) ? ["lists"] : []) + ["settings"])
            #endif
            }
            rows.append(["tab-live", "tab-movie", "tab-series", "search"])
        }
        switch page {
        case .settings, .home: break
        case .catalogue where usesDesk:
            // Rows above the grid, from the controls along the top of the
            // window. The navigation column, the actions beside the preview
            // and the dock have their own zones.
            let pages = !visible.isEmpty && catalogPageCount > 1
                ? (catalogPage > 0 ? ["page-prev"] : []) + (catalogPage + 1 < catalogPageCount ? ["page-next"] : []) : []
            // The pages of films and series stand on the line of the search.
            rows.append(deskHeaderIDs + [DeskZone.searchID] + (deskPagerInBand ? pages : [])
                        + (library.selectedSourceID != nil && !library.isLoading ? ["reload"] : []))
            if library.credentialIssue != nil { rows.append(["reconnect-source"]) }
            if visible.isEmpty && library.credentialIssue == nil && library.contentKind == .live { rows.append(["live-reset"]) }
            if !pages.isEmpty && !deskPagerInBand { rows.append(pages) }
        case .catalogue:
            if library.selectedSourceID != nil && !library.isLoading { rows.append(["reload"]) }
            if library.credentialIssue != nil { rows.append(["reconnect-source"]) }
            if library.contentKind == .live {
                #if os(tvOS)
                rows.append(televisionScopeIDs)
                #else
                if !liveSidebarVisible { rows.append(browserHeight < 580 ? ["countries", "categories"] : ["countries", "categories", "favorites-quick", "lists"]) }
                #endif
                if visible.isEmpty && !library.sources.isEmpty && library.credentialIssue == nil { rows.append(["live-reset"]) }
            } else {
                rows.append(["group-all", "categories"] + (library.contentKind == .movie ? ["continue-only"] : []) + (library.sources.isEmpty ? [] : ["favorites-quick"]))
            }
            if library.sources.isEmpty { rows.append(["add-source"]) }
            else if !visible.isEmpty {
                if !televisionLayout, library.contentKind == .live, let item = previewItem, visibleSlice.index(of: item.id) != nil {
                    rows.append(["live-watch"] + (!compactNavigation && browserHeight >= 580 ? ["live-favorite"] : []) + (livePreview.player == nil ? [] : ["live-preview-mute"]))
                }
                if catalogPageCount>1 {rows.append((catalogPage>0 ? ["page-prev"] : []) + (catalogPage+1<catalogPageCount ? ["page-next"] : []))}
            }
        case .series:
            rows += [["series-back", "series-favorite"]]
            if episodesFailed { rows.append(["series-retry"]) }
            else {
                for start in stride(from:0,to:seasons.count,by:max(1,columns)) {
                    rows.append(seasons[start..<min(seasons.count,start+max(1,columns))].map(SeriesSeasonShelf.focusID))
                }
            }
        case .player:
            if playerTracks { rows += playerTrackRows }
            else if playerControlsVisible {
                #if os(tvOS)
                rows.append(["player-back"])
                #else
                rows.append(["player-back", "player-full"])
                #endif
                rows.append(playerBarIDs)
            } else { rows.append(["cinema-controls"]) }
        }
        return rows
    }
    private func dispatch(_ action: RemoteAction) {
        if entranceItem != nil {
            if action == .back || action == .home { cancelEntrance() }
            return
        }
        guard !modalOpen else { return }
        #if !os(tvOS)
        remoteNavigationActive = true
        #endif
        if heldItem != nil {
            caseRemoteEvent=MediaDetailRemoteEvent(action:action)
            return
        }
        #if os(macOS) || os(tvOS)
        if zoneMode { handleZones(action); return }
        #endif
        // The settings are worked with the pointer or the remote of a
        // television: the keys of the player wait under them, and none of
        // them changes channel behind the panels.
        if page == .player, playerSettings != nil {
            if action == .back || action == .home { closePlayerSettings() }
            else if action == .playPause { playback.togglePause() }
            return
        }
        if page == .player, zapListVisible { handleZapList(action); return }
        // In live television a jump back has no meaning: Left and OK bring the
        // channel list, Up and Down keep changing channel directly.
        if page == .player, !playerControlsVisible, zapListAvailable, action == .left || action == .select {
            openZapList(keyboard: true); return
        }
        if page == .player && !playerControlsVisible {
            // A television changes channel under its banner alone: the
            // commands stay away, and Up and Down go on.
            if series == nil, playback.playingItem?.kind == .live, action == .up || action == .down {
                zapSurfing = true
                adjacent(action == .up ? 1 : -1)
                // At an end of the list the banner says which channel this is.
                showZapBanner()
                return
            }
            switch action {
            case .left: playback.skip(seconds: -Double(playback.settings.skipSeconds))
            case .right: playback.skip(seconds: Double(playback.settings.skipSeconds))
            default: break
            }
            if [.left, .right, .up, .down, .select].contains(action) {
                revealPlayerControls(focus: true)
                return
            }
        }
        switch action {
        case .up, .down, .left, .right:
            #if os(macOS)
            // Rows scroll under a still pointer during keyboard navigation;
            // remember where it rests so that only a real move selects a row.
            keyboardPointer = NSEvent.mouseLocation
            focusID = deskMove(action)
            #else
            if page == .catalogue, library.contentKind == .live {
                focusID = LiveTVNavigation.move(from: focusID, action: action, channels: visibleSlice,
                                               columns: columns, sidebarIDs: liveSidebarVisible ? liveSidebarIDs : [],
                                               preferredSidebarID: liveScopeID, preferredChannelID: previewID, prefix: focusRows)
            }
            else if page == .catalogue { focusID=visibleSlice.move(from:focusID,action:action,prefix:focusRows,columns:columns) }
            else { focusID = RemoteNavigation.move(from: focusID, action: action, rows: focusRows) }
            #endif
        case .select: activateFocus()
        case .back: back()
        case .home:
            #if os(macOS) || os(tvOS)
            showHome()
            #else
            home()
            #endif
        case .search: search()
        case .playPause:
            #if os(tvOS)
            // Outside the player, Lecture/Pause walks the zones of the screen.
            if page != .player, cycleZone(forward: true) { break }
            #endif
            if page == .player {
                // A pause is told by the commands, on their key.
                #if os(tvOS)
                if !playerControlsVisible, !playerCovered { revealPlayerControls(focus: true) }
                #endif
                zapSurfing = false
                playback.togglePause()
            }
            else if page == .series {activateFocus()}
            else if let item = visibleSlice.item(id:focusID) { openItem(item) }
        case .rewind: playback.skip(seconds: -Double(playback.settings.skipSeconds))
        case .forward: playback.skip(seconds: Double(playback.settings.skipSeconds))
        case .previous: adjacent(-1)
        case .next: adjacent(1)
        case .fullscreen: toggleCinema()
        case .volumeUp: playback.adjustVolume(0.1)
        case .volumeDown: playback.adjustVolume(-0.1)
        case .mute: playback.toggleMute()
        case .options:
            if page == .player { presentSettings() }
            else if let item = visibleSlice.item(id:focusID) ?? (page == .series ? series : nil) { itemOptions = item }
            else { presentLists() }
        }
        if page == .player { revealPlayerControls() }
    }
    private func activateFocus() {
        guard let id = focusID else { focusID = focusRows.first?.first; return }
        #if os(macOS) || os(tvOS)
        if deskActivate(id) { return }
        #endif
        if page == .catalogue, let item = visibleSlice.item(id:id) { openItem(item); return }
        if id.hasPrefix("tab-"), let kind = IPTVMediaKind(rawValue: String(id.dropFirst(4))) { changeKind(kind); return }
        if page == .series,id.hasPrefix("season-"),let n=Int(id.dropFirst(7)),let season=seasons.first(where:{$0.number == n}) {showSeason(season);return}
        if id.hasPrefix("live-category-") { selectLiveGroup(String(id.dropFirst("live-category-".count))); return }
        if id.hasPrefix("live-preset-") { selectLivePreset(String(id.dropFirst("live-preset-".count))); return }
        if id == "group-all" { showAllCatalog(); return }
        if id.hasPrefix("group-") { group = String(id.dropFirst(6)); return }
        if id.hasPrefix("track-audio-") { playback.selectAudioTrack(String(id.dropFirst("track-audio-".count))); return }
        if id.hasPrefix("track-sub-") {
            let track = String(id.dropFirst("track-sub-".count))
            playback.selectSubtitleTrack(track == "off" ? nil : track); return
        }
        switch id {
        case PlayerTracks.buttonID: openPlayerTracks()
        case PlayerTracks.closeID: closePlayerTracks()
        case "favorite-toggle": if let item = playback.playingItem { library.toggleFavorite(item) }
        case "zap-list": if zapListVisible { closeZapList() } else { openZapList(keyboard: remoteNavigationActive, fromKey: true) }
        case "live-watch": if let item = previewItem { playItem(item) }
        case "live-favorite": if let item = previewItem { chooseFavorites(item) }
        case "live-preview-mute": livePreview.toggleMuted()
        case "navigation-more": showingNavigationMenu = true
        case "live-manage-lists": presentLists()
        case "live-reset": showAllCatalog()
        case "page-prev": changeCatalogPage(-1)
        case "page-next": changeCatalogPage(1)
        case "hero-play": if let item=previewItem { openItem(item) }
        case "hero-favorite": if let item=previewItem { chooseFavorites(item) }
        case "sources": presentSources()
        case "search": search()
        case "remote": showRemote.toggle()
        case "lists": presentLists()
        case "categories": showingGroups = true
        case "countries": presentCountries()
        case "continue-only": toggleResumeFilter()
        case "favorites-quick":
            if library.contentKind == .live {
                toggleLiveFavorites()
            } else { toggleQuickFavorites() }
        case "volume-down": playback.adjustVolume(-0.1)
        case "volume-up": playback.adjustVolume(0.1)
        case "mute": playback.toggleMute()
        case "reconnect-source": if let source = library.selectedSource { presentEditSource(source) }
        case "reload": library.reloadSelected()
        case "add-source": presentAddSource()
        case "series-back", "player-back": back()
        case "stop": stopPlayback()
        case "cinema-controls": revealPlayerControls(focus: true)
        case "hide-controls": hidePlayerControls()
        case "exit-full": toggleCinema()
        case "series-favorite": itemOptions = series
        case "series-retry": if let series { loadSeries(series) }
        case "player-full": toggleCinema()
        case "previous": adjacent(-1)
        case "next": adjacent(1)
        case "rewind": playback.skip(seconds: -Double(playback.settings.skipSeconds))
        case "forward": playback.skip(seconds: Double(playback.settings.skipSeconds))
        case "playpause": playback.togglePause()
        case "engine", "settings": presentSettings()
        default: if cinema { playback.togglePause() }
        }
    }
}

/// The window of the application. It owns the focus of the system and
/// nothing else: a move of the remote changes that focus, which rebuilds
/// the view that owns it. The screen under it is rebuilt by its own state.
struct ContentView: View {
    @FocusState private var focus: String?
    @State private var relay = FluxFocusRelay()
    private let screen: (FocusState<String?>.Binding, FluxFocusRelay) -> FluxScreen

    #if FLUX_CATALOG_UI_TESTING
    /// The parameters of a fixture, handed to the screen as they are.
    init(fixtureSelection: IPTVItem? = nil, fixtureSeasons: [IPTVSeason] = [], fixtureOpenSeason: Int? = nil, fixtureEpisodeID: String? = nil,
         fixtureOpenItem: Bool = false, fixtureSearchSubmission: String? = nil, fixtureSearchObservation: ((CatalogSearchFocusSnapshot) -> Void)? = nil,
         fixtureOpenCountries: Bool = false, fixtureRestoreBrowsing: Bool = false, fixtureSettingsPage: PlaybackSettingsView.Page? = nil,
         fixtureFavorites: Bool = false, fixtureHome: Bool = false, fixturePlayerSettings: Bool = false, fixtureZone: DeskZone? = nil,
         fixtureActions: [RemoteAction] = [], fixtureZapList: Bool = false, fixtureAddSource: Bool = false, fixtureLists: Bool = false,
         fixturePlayer: Bool = false, fixtureHoldsControls: Bool = false, fixtureTracksPanel: Bool = false, fixtureBanner: Bool = false) {
        screen = { focus, relay in
            FluxScreen(nativeFocus: focus, focusRelay: relay, fixtureSelection: fixtureSelection, fixtureSeasons: fixtureSeasons, fixtureOpenSeason: fixtureOpenSeason,
                       fixtureEpisodeID: fixtureEpisodeID, fixtureOpenItem: fixtureOpenItem, fixtureSearchSubmission: fixtureSearchSubmission,
                       fixtureSearchObservation: fixtureSearchObservation, fixtureOpenCountries: fixtureOpenCountries,
                       fixtureRestoreBrowsing: fixtureRestoreBrowsing, fixtureSettingsPage: fixtureSettingsPage, fixtureFavorites: fixtureFavorites,
                       fixtureHome: fixtureHome, fixturePlayerSettings: fixturePlayerSettings, fixtureZone: fixtureZone, fixtureActions: fixtureActions,
                       fixtureZapList: fixtureZapList, fixtureAddSource: fixtureAddSource, fixtureLists: fixtureLists, fixturePlayer: fixturePlayer,
                       fixtureHoldsControls: fixtureHoldsControls, fixtureTracksPanel: fixtureTracksPanel, fixtureBanner: fixtureBanner)
        }
    }
    #else
    init() { screen = { FluxScreen(nativeFocus: $0, focusRelay: $1) } }
    #endif

    var body: some View {
        #if os(macOS)
        // The window says its size: the desk is drawn at the share of a
        // television's screen that it is.
        GeometryReader { geometry in
            screen($focus, relay).equatable()
                .onChange(of: focus) { _, id in relay.moved?(id) }
                .onChange(of: geometry.size, initial: true) { _, size in
                    let scale = DeskScale.fitting(size)
                    if DeskScale.shared.value != scale { DeskScale.shared.value = scale }
                }
        }
        #else
        screen($focus, relay).equatable()
            .onChange(of: focus) { _, id in relay.moved?(id) }
        #endif
    }
}

private extension View {
    @ViewBuilder func fluxFocus(_ binding: FocusState<String?>.Binding, id: String) -> some View {
        #if os(tvOS)
        self.focused(binding, equals: id).focusEffectDisabled()
        #else
        // Every focusable control draws its own highlight; the system ring
        // would add a rectangle around rounded cards and rows.
        self.focusable().focused(binding, equals: id).focusEffectDisabled()
        #endif
    }
}

#if os(tvOS)
private extension View {
    func fluxExit(_ enabled: Bool, action: @escaping () -> Void) -> some View {
        // Keep the catalogue's structural identity when focus leaves a tab.
        // A conditional wrapper remounts its controls during restoration and
        // lets the native engine fall back to Pays. A nil action keeps Menu
        // available to the system without replacing the catalogue subtree.
        self.onExitCommand(perform: enabled ? action : nil)
    }
}
#endif


private extension View {
    @ViewBuilder func fluxHelp(_ title: String) -> some View {
        #if os(macOS)
        self.help(title)
        #else
        self
        #endif
    }
}

#if os(macOS) || os(tvOS)
// MARK: - Desk layout (Mac): dock, screens and panels drawn in the window

extension FluxScreen {
    private var themeSecond: Color {
        let p = theme.palette.second
        return Color(red: p.x, green: p.y, blue: p.z)
    }
    /// The home screen is the bar itself, in the middle of the window.
    var showsHome: Bool { page == .home && !library.sources.isEmpty }
    private var dockVisible: Bool {
        page != .player && !cinema && entranceItem == nil && !showsHome
    }
    /// A fiche, the lists of a title or a message stand above the screen. A
    /// pointer cannot reach what is under them; on a television nothing under
    /// them takes the focus of the remote either.
    private var deskCovered: Bool { heldItem != nil || itemOptions != nil || library.alertMessage != nil }
    private var dockAlignment: Alignment {
        switch dockPosition {
        case .bottom: .bottom
        case .corner: .bottomLeading
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    private var dockEdge: Edge.Set {
        switch dockPosition {
        case .bottom, .corner: .bottom
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    private var dockRoom: CGFloat { dockVisible ? FluxDockMetrics.thickness(dockPosition) : 0 }

    private var deskHasColumns: Bool { page == .settings || (page == .catalogue && !library.sources.isEmpty) }
    /// The compact dock sits under the navigation column, which stops above
    /// it: the other columns reach the bottom of the window. A dock on an
    /// edge keeps a strip of its own, whose corners stay empty.
    private var dockInNavigation: Bool { dockVisible && dockPosition == .corner && deskHasColumns }
    private var navigationFootRoom: CGFloat { dockInNavigation ? dockRoom - Desk.tv(10) : 0 }

    private func edgeInsets(strip: Bool) -> EdgeInsets {
        guard dockVisible else { return EdgeInsets() }
        let room = dockRoom
        switch dockPosition {
        case .bottom, .corner: return EdgeInsets(top: Desk.tv(14), leading: 0, bottom: strip ? room : Desk.tv(10), trailing: 0)
        case .top: return EdgeInsets(top: strip ? room : Desk.tv(14), leading: 0, bottom: Desk.tv(8), trailing: 0)
        case .leading: return EdgeInsets(top: Desk.tv(14), leading: room, bottom: Desk.tv(8), trailing: 0)
        case .trailing: return EdgeInsets(top: Desk.tv(14), leading: 0, bottom: Desk.tv(8), trailing: room)
        }
    }
    /// Margins of a screen: its columns keep their own room for the dock.
    private var dockInsets: EdgeInsets { edgeInsets(strip: !dockInNavigation) }
    /// A fiche never slides under the dock.
    private var ficheInsets: EdgeInsets { edgeInsets(strip: true) }
    private var dockSelection: Set<FluxDockItem> {
        var result: Set<FluxDockItem> = []
        if let current = FluxDockItem(focusID: currentDockID) { result.insert(current) }
        if page != .settings && (searchFocus || !library.search.isEmpty) { result.insert(.search) }
        return result
    }
    private var fichePresented: Bool { heldItem != nil && caseExpanded }

    func deskPane(reader: ScrollViewProxy) -> some View {
        ZStack {
            if showsHome {
                deskHome
                    .allowsHitTesting(!deskCovered)
                    #if os(tvOS)
                    .disabled(deskCovered)
                    #endif
                    .transition(homeTransition)
            } else {
                deskPage
                    .padding(dockInsets)
                    // The catalogue stays in place, out of focus, behind a fiche.
                    .blur(radius: livesBlur && (fichePresented || itemOptions != nil || library.alertMessage != nil) ? 22 : 0)
                    .allowsHitTesting(!deskCovered)
                    #if os(tvOS)
                    // An open folder of the dock keeps the remote, as a panel does.
                    .disabled(deskCovered || dockFan != nil)
                    #endif
                    .opacity(entranceItem == nil ? 1 : 0)
                    .transition(.opacity)
            }
            if let heldItem {
                Color.black.opacity(fichePresented ? (livesBlur ? 0.36 : 0.68) : 0).ignoresSafeArea().allowsHitTesting(false)
                heldOverlay(heldItem, reader: reader).padding(ficheInsets)
                    // What stands above the fiche puts it out of focus too.
                    .blur(radius: livesBlur && (itemOptions != nil || library.alertMessage != nil) ? 16 : 0)
                    #if os(tvOS)
                    .disabled(itemOptions != nil || library.alertMessage != nil)
                    #endif
            }
            if dockVisible, dockFan != nil { dockFanVeil }
            if dockVisible {
                deskDock
                    #if os(tvOS)
                    .disabled(deskCovered)
                    #endif
                    .transition(.opacity)
            }
            if page == .player, let request = playerSettings {
                deskPlayerSettings(request)
                    #if os(tvOS)
                    .disabled(library.alertMessage != nil)
                    #endif
            }
            if zoneMode {
                Color.black.opacity(0.34).ignoresSafeArea().allowsHitTesting(false).transition(.opacity)
                zoneCaption
            }
            #if os(tvOS) && FLUX_CATALOG_UI_TESTING
            // Read the drawn selection independently from UIKit focus
            // without adding a focusable control to the fixture.
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityElement().accessibilityLabel("Flux IPTV")
                .accessibilityIdentifier("flux-catalog-logical-focus")
                .accessibilityValue(focusID ?? "none")
            #endif
            if let item = itemOptions {
                deskItemPanel(item)
                    #if os(tvOS)
                    .disabled(library.alertMessage != nil)
                    #endif
            }
            if let message = library.alertMessage { deskNotice(message) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: playerSettings)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: dockFan)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: zoneMode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: zoneFocus)
        .onChange(of: page) { _, _ in zoneMode = false; dockFan = nil }
        // The home screen shrinks toward the place its bar takes on the others.
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88), value: showsHome)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fichePresented)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: itemOptions?.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: library.alertMessage)
    }

    @ViewBuilder private var deskPage: some View {
        switch page {
        case .settings: deskSettings
        case .player: playerPage
        case .series:
            if library.sources.isEmpty { firstSourceWelcome } else { seriesDetail }
        case .catalogue, .home:
            // Without a source the home screen has nothing to offer yet.
            if library.sources.isEmpty { firstSourceWelcome } else { catalogue }
        }
    }

    private var deskDock: some View {
        Group {
            if barFlanks { deskBar } else {
                dockItself
                    .padding(dockEdge, FluxDockMetrics.edgeMargin)
                    .padding(.leading, dockPosition == .corner ? Desk.pt(24) : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockAlignment)
    }

    private var dockItself: some View {
        let plan = dockPlan()
        return dockItself(plan, fan: dockFanModel(plan))
    }

    private func dockItself(_ plan: DockPlan, fan: DockFan?, hero: CGFloat? = nil, crowded: Bool = false) -> some View {
        FluxDock(tiles: dockTiles(plan), breaks: plan.arrangement.breaks, shrink: plan.shrink,
                 selection: hero == nil ? dockSelection : [], focusedID: shownFocusID, showsFocus: focusShown,
                 accent: themeAccent, second: themeSecond, hero: hero, crowded: crowded,
                 hover: hero == nil ? nil : { homeHover = $0?.id },
                 zoneRing: hero == nil && zoneMode && deskZoneEntry(.dock) != nil ? zoneFocus == .dock : nil,
                 fan: fan, systemFocus: nativeFocus,
                 activate: { entry in pointerSelect(entry.id); dockActivate(entry) },
                 manage: { manageDock($0) }, remove: { removeDock($0) },
                 reorder: { shortcut, section, index in moveDock(shortcut, in: section, to: index) },
                 openFanRow: { openShortcut($0.shortcut, resuming: false) }, openFanList: { openDockFanList() },
                 openSettings: { openSettings(.dock) })
    }

    /// Under an open folder the screen is dimmed and out of reach; a
    /// click beside the folder closes it.
    private var dockFanVeil: some View {
        Color.black.opacity(0.34).ignoresSafeArea()
            .contentShape(Rectangle()).onTapGesture { closeDockFan() }
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// At the bottom the bar is the Dock of a Mac, in the middle of the
    /// window. Back and Home stand on its left and the clock on its right:
    /// nothing of its strip is lost, and the columns need no header for them.
    var barFlanks: Bool { dockPosition == .bottom }
    /// Controls of the bar that stand before its destinations.
    var barLeadIDs: [String] {
        guard barFlanks, dockVisible else { return [] }
        return [DeskZone.backID] + (deskBackPlace == nil ? [] : [DeskZone.homeID])
    }

    /// What the bar at the foot of the screen is drawn from.
    private struct BarKey: Equatable {
        let backTarget: String
        let home: Bool
        let selection: Set<FluxDockItem>
        /// Selected with the keyboard; a television shows its own focus.
        let keyboard: String?
        /// The zones of the screen are shown, and whether the dock is the one chosen.
        let zone: Bool?
        /// Room that the dock leaves to its flanks: 0 the date and the
        /// name of the screen behind, 1 no date, 2 neither.
        let flank: Int
        let dock: DockPlan
        let fan: DockFan?
        let theme: VideoClubTheme
        let rich: Bool
        /// The screen has zones that one key walks: the bar says which key.
        let zones: Bool
    }

    /// The two flanks have the same width: the dock stays in the middle.
    private var deskBar: some View {
        let plan = dockPlan()
        let fan = dockFanModel(plan)
        let plate = FluxDockMetrics(.bottom, shrink: plan.shrink)
            .length(count: plan.arrangement.entries.count, breaks: plan.arrangement.breaks.count, vertical: false)
        let flank = plate <= deskWidth - 2 * Desk.pt(Self.barFlank + 42) && deskWidth >= Desk.pt(1240) ? 0
            : plate <= deskWidth - 2 * Desk.pt(Self.barFlank) ? 1 : 2
        let key = BarKey(backTarget: deskBackTarget, home: deskBackPlace != nil, selection: dockSelection,
                         keyboard: focusShown ? shownFocusID : nil,
                         zone: zoneMode && deskZoneEntry(.dock) != nil ? zoneFocus == .dock : nil,
                         flank: flank, dock: plan, fan: fan, theme: theme, rich: richGlass,
                         zones: page == .catalogue && !library.sources.isEmpty)
        return FluxStable(key) { deskBarBody(plan, fan: fan, flank: flank, zones: key.zones) }.equatable()
    }
    /// Width that each flank of the bar needs for Back with the name of
    /// the screen behind, Home, and the room where the icons grow; and
    /// for Back and Home alone.
    private static let barFlank: CGFloat = 244
    private static let barFlankBare: CGFloat = 154

    /// Rebuilt only when what it shows changes: a move of the remote in
    /// the catalogue leaves the bar alone.
    private func deskBarBody(_ plan: DockPlan, fan: DockFan?, flank: Int, zones: Bool) -> some View {
        FluxProbe.hit("bar")
        let metrics = FluxDockMetrics(.bottom)
        let plate = metrics.cell.height + metrics.platePadding * 2
        return HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: Desk.pt(10)) {
                barButton(DeskZone.backID, symbol: "chevron.backward", title: flank == 2 ? nil : deskBackTarget,
                          help: deskBackTitle + " — maintenir : Accueil",
                          fills: deskBackPlace == nil, held: { holdBack() }) { deskLeaveScreen() }
                if deskBackPlace != nil {
                    barButton(DeskZone.homeID, symbol: "house.fill", title: nil, help: "Accueil", fills: true) { showHome() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: plate)
            .padding(.leading, Desk.pt(24))
            #if os(tvOS)
            // The whole flank guides the remote to its buttons.
            .focusSection()
            #endif
            dockItself(plan, fan: fan)
                #if os(tvOS)
                .focusSection()
                #endif
            VStack(alignment: .trailing, spacing: Desk.pt(7)) {
                if zones { zoneHint }
                TimelineView(.everyMinute) { context in
                    HStack(spacing: Desk.pt(10)) {
                        if flank == 0 {
                            Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(Desk.font(.callout, .medium)).foregroundStyle(.white.opacity(0.72))
                        }
                        Text(context.date.formatted(.dateTime.hour().minute()))
                            .font(Desk.font(.callout, .bold).monospacedDigit())
                    }
                    .padding(.horizontal, Desk.pt(15)).frame(height: Desk.pt(40))
                    .fluxGlass(radius: Desk.pt(20))
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing).frame(height: plate)
            .padding(.trailing, Desk.pt(24))
        }
        .padding(.bottom, FluxDockMetrics.edgeMargin)
    }

    /// The key that walks the zones of the screen, said above the clock:
    /// nothing else on the screen tells that the content, the bar, the
    /// line of the search and the column are one press from each other.
    private var zoneHint: some View {
        HStack(spacing: Desk.pt(6)) {
            #if os(tvOS)
            Image(systemName: "playpause.fill")
            Text("Zones")
            #else
            Text("⇥").fontWeight(.heavy)
            Text("Zones")
            #endif
        }
        .font(Desk.font(.caption, .semibold)).foregroundStyle(.white.opacity(0.74))
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .padding(.trailing, Desk.pt(8))
        .accessibilityElement(children: .ignore)
        #if os(tvOS)
        .accessibilityLabel("Lecture/Pause : zone suivante")
        #else
        .accessibilityLabel("Tabulation : zone suivante")
        .help("Tab passe à la zone suivante : contenu, barre, recherche, colonne. ⌘ + flèche va droit à la zone de ce côté.")
        #endif
        .accessibilityIdentifier("desk-zone-hint")
    }

    /// `fills`: on a television the remote goes to the nearest control, and
    /// the list above the dock is nearer than a small button far on the left.
    /// The last button of the flank answers for the whole of it, up to the dock.
    private func barButton(_ id: String, symbol: String, title: String?, help: String, fills: Bool,
                           held: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        let selected = focusShown && shownFocusID == id
        return Button {
            // The release that ends a long press is not a press.
            if let since = backHeldAt, Date().timeIntervalSince(since) < 1 { return }
            pointerSelect(id); action()
        } label: {
            HStack(spacing: 0) {
                FluxFocused(id: id, logical: selected) { focused in
                    HStack(spacing: Desk.pt(7)) {
                        Image(systemName: symbol).font(Desk.font(.callout, .bold))
                        if let title { Text(title).font(Desk.font(.callout, .semibold)).lineLimit(1) }
                    }
                    .padding(.horizontal, Desk.pt(title == nil ? 12 : 15)).frame(minWidth: Desk.pt(40), minHeight: Desk.pt(40))
                    .fluxGlass(radius: Desk.pt(20))
                    .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 2).allowsHitTesting(false))
                    .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
                }
            }
            #if os(tvOS)
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
            guard let held else { return }
            backHeldAt = Date()
            held()
        })
        .fluxHelp(help).accessibilityLabel(help).accessibilityIdentifier(id)
    }

    /// Back held down: the home screen at once, from wherever one is. The
    /// key of a keyboard, and the Back of the bar under a pointer or under
    /// the OK of a remote. The Menu button of an Apple TV held down belongs
    /// to the system, which shows its own home screen.
    func holdBack() {
        guard !library.sources.isEmpty, page != .home || heldItem != nil else { return }
        if library.alertMessage != nil { library.alertMessage = nil }
        itemOptions = nil; zoneMode = false; dockFan = nil
        showHome()
    }

    private var deskSettings: some View {
        PlaybackSettingsView(playback: playback, inline: true, initialPage: settingsRequest.page,
                             initialSourceEditor: settingsRequest.sourceEditor, remoteVisible: $showRemote,
                             navigationFootRoom: navigationFootRoom, backTitle: deskBackTitle,
                             goBack: barFlanks ? nil : { back() }, goHome: barFlanks ? nil : { showHome() },
                             close: { leaveSettings() }, sourceSaved: { home() })
            .environmentObject(library)
            .id(settingsRequest.revision)
    }

    /// Favourites and lists of one title, above the dimmed screen.
    private func deskItemPanel(_ item: IPTVItem) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { itemOptions = nil }
            itemPanel(item)
                .fluxGlass(radius: Desk.pt(28))
                .shadow(color: .black.opacity(0.45), radius: Desk.pt(30), y: 16)
                // Like a fiche, the panel never slides under the dock.
                .padding(ficheInsets)
        }
        .transition(.opacity)
    }

    /// A message of the library, shown in the window rather than as an alert.
    private func deskNotice(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().contentShape(Rectangle())
            VStack(alignment: .leading, spacing: Desk.pt(16)) {
                Label("Flux IPTV", systemImage: "exclamationmark.bubble.fill")
                    .font(Desk.font(.headline)).foregroundStyle(themeAccent)
                Text(message).font(Desk.font(.title3)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button { library.alertMessage = nil } label: {
                        Text("OK").font(Desk.font(.headline)).padding(.horizontal, Desk.pt(28)).padding(.vertical, Desk.pt(10))
                            .fluxNavigationGlass(selected: true, tint: themeAccent, radius: Desk.pt(15))
                    }.buttonStyle(FluxBareButtonStyle())
                    #if os(tvOS)
                    // What a message covers is only put out of reach: the
                    // focus stays there until the message asks for it.
                    .focused($noticeFocus)
                    .onAppear { Task { @MainActor in await Task.yield(); noticeFocus = true } }
                    #endif
                    .accessibilityIdentifier("desk-notice-ok")
                }
            }
            .padding(Desk.pt(24)).frame(maxWidth: Desk.pt(540)).fluxGlass(radius: Desk.pt(26))
            .shadow(color: .black.opacity(0.45), radius: Desk.pt(30), y: 16)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
    }

    #if os(macOS)
    func deskDismissWithKey(_ key: KeyEquivalent) -> Bool {
        if library.alertMessage != nil {
            // Nothing under the message moves until it is acknowledged.
            if key == .return || key == .escape || key == .space { library.alertMessage = nil }
            return true
        }
        if playerTracks, key == .escape { closePlayerTracks(); return true }
        if playerSettings != nil, key == .escape { closePlayerSettings(); return true }
        return false
    }
    #endif

    /// Settings of the player, asked for during playback: the same glass
    /// panels as the settings screen, above the picture that keeps playing.
    private func deskPlayerSettings(_ request: DeskSettingsRequest) -> some View {
        ZStack {
            Color.black.opacity(0.30).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { closePlayerSettings() }
            PlaybackSettingsView(playback: playback, inline: true, overPlayback: true, initialPage: request.page,
                                 close: { closePlayerSettings() })
                .environmentObject(library)
                .id(request.revision)
                .frame(maxWidth: Desk.pt(1180), maxHeight: Desk.pt(780))
                .padding(.vertical, Desk.pt(44))
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: What the dock keeps

    /// What the dock holds, fitted to the room it has: cheap to build and to
    /// compare at every update of the screen. The pictures of its titles
    /// are looked up only when it changes.
    struct DockPlan: Equatable {
        var arrangement = DockArrangement(groups: [])
        var shrink: CGFloat = 1
        /// What a folder is drawn from: its name, its size and a sign of
        /// what it holds.
        var stacks: [String] = []
        /// What was watched of the video in progress, in fiftieths.
        var progress: Int?
        /// The catalogue that the titles are looked up in.
        var catalogue: UUID?
        var ready = false
        var ids: [String] { arrangement.entries.map(\.id) }
    }

    /// Room that the bar has along its edge.
    private func dockLength(_ position: FluxDockPosition) -> CGFloat {
        // Before the window is measured nothing is known to be too long.
        guard deskWidth > 0, browserHeight > 0 else { return .greatestFiniteMagnitude }
        switch position {
        // Between Back and the clock, which keep the same width on each side.
        case .bottom: return max(0, deskWidth - 2 * Desk.pt(Self.barFlankBare))
        case .top, .corner: return max(0, deskWidth - Desk.pt(48) - 2 * FluxDockMetrics(position).growth)
        case .leading, .trailing: return max(0, browserHeight - Desk.pt(56) - 2 * FluxDockMetrics(position).growth)
        }
    }

    /// The film or the episode watched last that was left unfinished. The
    /// recents know the series of an episode; a film that was watched
    /// before the dock kept recents is found in the catalogue.
    private func dockResume(_ shelf: DockShelf) -> DockShortcut? {
        let source = library.selectedSourceID
        let unfinished = playback.history.entries.values.filter(\.resumable).sorted { $0.updated > $1.updated }
        for entry in unfinished.prefix(12) {
            if let recent = shelf.recent(played: entry.id, sourceID: source) { return recent }
            if let item = library.catalogItem(id: entry.id), item.kind == .movie, item.sourceID == source { return DockShortcut(item: item) }
        }
        return nil
    }

    /// `hero`: the bar of the home screen, which is laid out as a bar at
    /// the bottom whatever edge the other screens give it.
    func dockPlan(hero: Bool = false) -> DockPlan {
        let destinations = FluxDockItem.order(from: dockOrder)
        let position: FluxDockPosition = hero ? .bottom : dockPosition
        // The compact bar under the column has the room of its destinations.
        guard !position.isCompact, !library.sources.isEmpty else {
            return DockPlan(arrangement: DockArrangement(groups: [destinations.map(DockEntry.destination)]))
        }
        let shelf = library.dockShelf
        let resume = dockRecents ? dockResume(shelf) : nil
        var arrangement = shelf.arrangement(destinations: destinations, sourceID: library.selectedSourceID,
                                            lists: library.presets.lists.map(\.id), recentCount: dockRecents ? 3 : 0, resume: resume)
        let room = dockLength(position)
        if hero {
            // The home screen gives the bar up to three rows instead of
            // making its icons smaller: only the shortcuts that their own
            // row cannot hold go into the folder of the others.
            let surplus = arrangement.shortcutCount - heroRowLimit
            if arrangement.entries.count > heroRowLimit, surplus > 0 {
                arrangement = arrangement.fitted(to: arrangement.entries.count - surplus, sparingRecents: true)
            }
        } else {
            let capacity = FluxDockMetrics.capacity(position, room: room, breaks: arrangement.breaks.count)
            if arrangement.entries.count > capacity { arrangement = arrangement.fitted(to: max(capacity, destinations.count + 1)) }
        }
        let stacks = arrangement.entries.compactMap { entry -> String? in
            guard case .stack(let id) = entry, let list = library.presets.list(id: id) else { return nil }
            return "\(id)|\(list.name)|\(list.itemIDs.count)|\(list.itemIDs.hashValue)"
        }
        let progress = resume?.playedID.flatMap { playback.history.entries[$0] }.map { Int(($0.fraction * 50).rounded()) }
        return DockPlan(arrangement: arrangement,
                        shrink: hero ? 1 : FluxDockMetrics.shrink(position, count: arrangement.entries.count, breaks: arrangement.breaks.count, room: room),
                        stacks: stacks, progress: progress, catalogue: library.browsingRevision, ready: library.browsingCatalogReady)
    }

    /// What one row of the bar of the home screen holds.
    private var heroRowLimit: Int { FluxDockMetrics.heroRowCapacity(width: deskWidth > 0 ? deskWidth : 1920 * Desk.scale) }
    /// The bar of the home screen: one row while it holds on one, then two,
    /// then three.
    func heroRows(_ plan: DockPlan) -> [DockArrangement] { plan.arrangement.rows(limit: heroRowLimit) }

    /// The titles of a list, in the order of their names: a list keeps
    /// them in none.
    private func dockListItems(_ listID: String, limit: Int) -> [IPTVItem] {
        guard let list = library.presets.list(id: listID) else { return [] }
        let items = list.itemIDs.compactMap { library.catalogItem(id: $0) }
        return Array(items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(limit))
    }

    private func dockItem(_ shortcut: DockShortcut) -> IPTVItem? {
        shortcut.sourceID == library.selectedSourceID ? library.catalogItem(id: shortcut.itemID) : nil
    }

    /// The icons of the bar, with the pictures of their titles.
    private func dockTiles(_ plan: DockPlan) -> [DockTile] {
        plan.arrangement.entries.map { entry in
            switch entry {
            case .destination(let item):
                return DockTile(entry: entry, name: item.title, full: item.title, face: .destination(item))
            // Under an icon a name is cut short: the label of its language,
            // the same on every title of a catalogue, would be all that is
            // left of it. The whole name stands above the icon pointed at.
            case .shortcut(let shortcut, _), .recent(let shortcut):
                return DockTile(entry: entry, name: MediaLanguage.bareTitle(of: shortcut.name), full: shortcut.title,
                                face: .title(dockItem(shortcut), kind: shortcut.kind, badge: shortcut.badge, progress: nil))
            case .resume(let shortcut):
                return DockTile(entry: entry, name: MediaLanguage.bareTitle(of: shortcut.name), full: "Reprendre « \(shortcut.title) »",
                                face: .title(dockItem(shortcut), kind: shortcut.kind, badge: shortcut.badge,
                                             progress: Double(plan.progress ?? 0) / 50))
            case .stack(let listID):
                let list = library.presets.list(id: listID)
                let count = list?.itemIDs.count ?? 0
                let name = list?.name ?? "Liste"
                return DockTile(entry: entry, name: name,
                                full: "\(name) · \(list?.kind.frenchTitle ?? "Favoris") · \(count) \(count == 1 ? "titre" : "titres")",
                                face: .folder(covers: dockListItems(listID, limit: 3), count: count, symbol: "star.fill"))
            case .more:
                let hidden = plan.arrangement.hidden.compactMap(\.shortcut)
                return DockTile(entry: entry, name: "Autres", full: "Autres raccourcis",
                                face: .folder(covers: Array(hidden.lazy.compactMap { dockItem($0) }.prefix(3)), count: hidden.count,
                                              symbol: "ellipsis"))
            }
        }
    }

    /// Titles that an open folder has the height to show above the bar.
    private var dockFanRoom: Int {
        let metrics = FluxDockMetrics(.bottom)
        let row = metrics.tile * 0.9 + metrics.label * 0.42
        return max(3, min(8, Int((browserHeight - FluxDockMetrics.thickness(.bottom) - Desk.pt(120)) / row) - 1))
    }

    /// The folder that is open above the bar, with its titles.
    func dockFanModel(_ plan: DockPlan) -> DockFan? {
        guard let id = dockFan, let entry = plan.arrangement.entry(id: id) else { return nil }
        switch entry {
        case .stack(let listID):
            guard let list = library.presets.list(id: listID) else { return nil }
            let rows = dockListItems(listID, limit: dockFanRoom).map { DockFanRow(shortcut: DockShortcut(item: $0), item: $0, badge: nil) }
            return DockFan(anchorID: id, title: list.name, rows: rows, more: max(0, list.itemIDs.count - rows.count), listTitle: nil)
        case .more:
            let hidden = plan.arrangement.hidden.compactMap(\.shortcut)
            let rows = hidden.prefix(dockFanRoom).map { DockFanRow(shortcut: $0, item: dockItem($0), badge: $0.badge) }
            return DockFan(anchorID: id, title: "Autres raccourcis", rows: Array(rows), more: max(0, hidden.count - rows.count),
                           listTitle: "Tous les raccourcis")
        case .destination, .shortcut, .resume, .recent: return nil
        }
    }

    /// A press on an icon of the dock.
    func dockActivate(_ entry: DockEntry) {
        // The release that ends a long press has opened the lists of the title.
        guard itemOptions == nil else { return }
        switch entry {
        case .destination(let item): dockAction(item)
        case .shortcut(let shortcut, _), .recent(let shortcut): openShortcut(shortcut, resuming: false)
        case .resume(let shortcut): openShortcut(shortcut, resuming: true)
        case .stack, .more: toggleDockFan(entry.id)
        }
    }

    /// Shows the catalogue of a kind, out of the favourites.
    private func enterSection(_ kind: IPTVMediaKind) {
        let leavingFavorites = favoritesMode
        favoritesMode = false; sidebarCountries = false
        searchFocus = false; liveGroupSearchFocus = false
        if library.contentKind == kind { home() } else { changeKind(kind) }
        if leavingFavorites { library.selectedPresetID = nil }
    }

    /// Opens what a shortcut stands for: a channel plays, a film shows its
    /// fiche, a series its seasons, a season or an episode the fiche of the
    /// series on it. The video in progress plays on from where it stopped.
    func openShortcut(_ shortcut: DockShortcut, resuming: Bool) {
        dockFan = nil
        guard let item = dockItem(shortcut) else {
            library.alertMessage = library.isLoading || !library.browsingCatalogReady
                ? "Le catalogue se charge : « \(shortcut.title) » pourra s’ouvrir dans un instant."
                : "« \(shortcut.title) » n’est plus dans le catalogue de cette source."
            return
        }
        let moved = library.contentKind != shortcut.kind
        enterSection(shortcut.kind)
        let open = {
            // The section must not take the remote back for what it remembers.
            cancelBrowsingRestore()
            switch shortcut.target {
            case .channel: series = nil; seasons = []; playItem(item)
            case .film:
                if resuming { series = nil; seasons = []; playItem(item) }
                else { library.selectedItemID = item.id; setPreview(item); showCase(item) }
            case .series: loadSeries(item)
            case .season: loadSeries(item, season: shortcut.season)
            case .episode: loadSeries(item, season: shortcut.season, episodeID: shortcut.episodeID, play: resuming)
            }
            recordPlace()
        }
        // Another section shows its own catalogue first, in this update.
        if moved { Task { @MainActor in await Task.yield(); open() } } else { open() }
    }

    private func toggleDockFan(_ id: String) {
        if dockFan == id { closeDockFan(); return }
        dockFan = id
        guard let first = dockFanModel(dockPlan(hero: showsHome))?.ids.first else { return }
        focusID = first
        #if os(tvOS)
        // Its titles come with this update: the first takes the remote after it.
        holdRemote(on: first) { dockFan == id }
        #else
        Task { @MainActor in
            await Task.yield()
            if dockFan == id, focusID == first { systemFocus = first }
        }
        #endif
    }

    /// Closes the open folder; the remote goes back to its icon.
    func closeDockFan() {
        guard let id = dockFan else { return }
        dockFan = nil
        guard let current = focusID, current.hasPrefix(DockEntry.fanPrefix) else { return }
        focusID = id
        #if os(tvOS)
        holdRemote(on: id) { dockFan == nil && focusID == id }
        #else
        systemFocus = id
        #endif
    }

    /// Last row of an open folder: the list on its own screen, or every
    /// shortcut of the dock in the settings.
    private func openDockFanList() {
        guard let id = dockFan else { return }
        dockFan = nil
        if id == DockEntry.moreID { openSettings(.dock); return }
        guard id.hasPrefix(DockEntry.stackPrefix),
              let list = library.presets.list(id: String(id.dropFirst(DockEntry.stackPrefix.count))) else { return }
        enterFavorites()
        selectFavoriteList(list)
        #if os(tvOS)
        restoreBrowsingContext()
        #endif
    }

    /// The lists of the title that an icon stands for, where it can leave
    /// the dock or join a section of it.
    private func manageDock(_ entry: DockEntry) {
        guard let shortcut = entry.shortcut else { return }
        dockFan = nil
        // What the catalogue no longer holds can only leave the bar.
        guard let item = dockItem(shortcut) else { removeDock(entry); return }
        focusID = entry.id
        itemDockExtra = shortcut.target == .season || shortcut.target == .episode ? shortcut : nil
        itemOptions = item
    }

    private func removeDock(_ entry: DockEntry) {
        switch entry {
        case .shortcut(let shortcut, let section):
            // From this section only: another one may keep it.
            _ = library.assignDock(shortcut, to: library.dockShelf.sections(holding: shortcut.id).subtracting([section]))
        case .recent(let shortcut): library.forgetDockRecent(shortcut.id)
        case .stack(let listID): library.setDockStack(listID, shown: false)
        case .destination, .resume, .more: break
        }
        if focusID == entry.id { focusID = currentDockID }
    }

    /// A shortcut dragged among those of its section that this source shows.
    private func moveDock(_ shortcut: DockShortcut, in section: String, to index: Int) {
        guard let all = library.dockShelf.section(id: section)?.shortcuts else { return }
        let shown = all.filter { $0.sourceID == library.selectedSourceID }
        guard shown.indices.contains(index), let target = all.firstIndex(where: { $0.id == shown[index].id }) else { return }
        library.moveDockShortcut(shortcut.id, in: section, to: target)
    }

    // MARK: Destinations

    private func dockAction(_ item: FluxDockItem) {
        dockFan = nil
        switch item {
        case .live, .movie, .series:
            if let kind = item.mediaKind { showSection(kind) }
        case .search:
            // From the home screen the search opens in the section used last.
            if page == .home { showSection(library.contentKind) }
            search()
        case .favorites: enterFavorites()
        case .settings: openSettings()
        }
        recordPlace()
    }

    /// Remembers the screen being shown, for Back.
    private func recordPlace() {
        guard page != .home, let place = FluxDockItem(focusID: currentDockID) else { return }
        deskHistory.visit(place)
    }

    /// Back first closes what is open in the screen, then shows the screen
    /// that came before this one, as the Back of a web browser does, down to
    /// the home screen. On a television that is all it does: the remote
    /// reaches every control with its arrows. With a keyboard, whose arrows
    /// follow rows, it may first show the zones of the screen.
    func deskBack() {
        if page == .catalogue {
            if sidebarCountries { closeCountries(); return }
            if newListKind != nil || renamingList || confirmingListDeletion {
                newListKind = nil; renamingList = false; confirmingListDeletion = false
                return
            }
            #if os(macOS)
            if zoneMode { deskLeaveScreen(); return }
            if backShowsZones, deskZones.count > 1, deskZone(of: focusID) != .dock {
                openZones(); return
            }
            #endif
        }
        deskLeaveScreen()
    }

    /// Closes the list of countries or languages, back on the button that
    /// opened it. That button returns to the column with this update: it can
    /// take the focus only once it is there, and before that a television
    /// settles on the nearest control, the filter of the categories.
    private func closeCountries() {
        sidebarCountries = false
        focusID = "countries"
        Task { @MainActor in
            await Task.yield()
            guard !sidebarCountries, page == .catalogue, focusID == "countries" else { return }
            liveGroupSearchFocus = false
            systemFocus = "countries"
        }
    }

    /// Shows the screen that came before this one, down to the home screen.
    func deskLeaveScreen() {
        zoneMode = false
        guard let current = FluxDockItem(focusID: currentDockID) else { showHome(); return }
        if let previous = deskHistory.leave(current) { dockAction(previous) } else { showHome() }
    }

    /// Screen that Back shows — nil is the home screen — and its name.
    private var deskBackPlace: FluxDockItem? {
        FluxDockItem(focusID: currentDockID).flatMap { deskHistory.previous(from: $0) }
    }
    private var deskBackTarget: String { deskBackPlace?.title ?? "Accueil" }
    var deskBackTitle: String { "Retour : \(deskBackTarget)" }

    // MARK: Zones

    /// Control that receives the selection when a zone is entered; nil when
    /// the screen does not offer that zone.
    func deskZoneEntry(_ zone: DeskZone) -> String? {
        guard page == .catalogue, !library.sources.isEmpty, heldItem == nil else { return nil }
        switch zone {
        case .dock: return dockVisible ? currentDockID : nil
        case .top: return DeskZone.searchID
        case .column:
            let ids = deskSidebarIDs
            return ids.contains(deskScopeID) ? deskScopeID : ids.first
        case .content: return visibleSlice.item(id: previewID)?.id ?? displayedItems.first?.id
        case .actions: return deskTrailingIDs.first
        }
    }
    private var deskZones: [DeskZone] { DeskZone.allCases.filter { deskZoneEntry($0) != nil } }
    private func deskZone(of id: String?) -> DeskZone? {
        guard let id else { return nil }
        if FluxDockItem(focusID: id) != nil || DockEntry.isShelfID(id) || barLeadIDs.contains(id) { return .dock }
        if deskSidebarIDs.contains(id) { return .column }
        if deskTrailingIDs.contains(id) { return .actions }
        if focusRows.contains(where: { $0.contains(id) }) { return .top }
        return visibleSlice.item(id: id) == nil ? nil : .content
    }

    private func openZones() {
        let zones = deskZones
        zoneFocus = deskZone(of: focusID).flatMap { zones.contains($0) ? $0 : nil }
            ?? (zones.contains(.content) ? .content : zones.first ?? .dock)
        zoneMode = true
    }

    /// Leaves the compass where the selection was.
    func closeZones() { zoneMode = false }

    private func enterZone(_ zone: DeskZone) {
        zoneMode = false
        guard let id = deskZoneEntry(zone) else { return }
        if zone == .content, let item = visibleSlice.item(id: id) { revealCatalogItem(id); setPreview(item) }
        #if os(tvOS)
        // The field of the search has a focus of its own on a television.
        if zone == .top { liveGroupSearchFocus = false; focusID = id; searchFocus = true; return }
        searchFocus = false; liveGroupSearchFocus = false
        // The row of the column that stands for what is shown, wherever it is.
        if zone == .column { enterColumn(); return }
        focusID = id
        // The control may be far down a list or just back on screen: it is
        // brought into view and asked until it says it has the remote.
        sendRemote(to: id, reader: zone == .content ? scrolls.pane : nil) {
            page == .catalogue && !deskCovered && focusID == id
        }
        #else
        focusID = id
        systemFocus = id
        #endif
    }

    /// The zone that holds the remote, or the selection of the keyboard.
    private var deskCurrentZone: DeskZone? {
        if searchFocus { return .top }
        if liveGroupSearchFocus { return .column }
        #if os(tvOS)
        return deskZone(of: systemFocus) ?? deskZone(of: focusID)
        #else
        return deskZone(of: focusID)
        #endif
    }

    /// One arrow jumps into the neighbouring zone; OK stays; Back leaves the screen.
    func handleZones(_ action: RemoteAction) {
        switch action {
        case .up, .down, .left, .right:
            let target = DeskZoneMap.move(from: zoneFocus, action: action, available: deskZones, dock: dockPosition)
            if target != zoneFocus { enterZone(target) }
        case .select, .playPause: closeZones()
        case .back: deskLeaveScreen()
        case .home: zoneMode = false; showHome()
        case .search: zoneMode = false; search()
        default: closeZones()
        }
    }

    /// One key enters the next zone of the screen: Tab on a keyboard,
    /// Lecture/Pause on the remote of a television. A long list keeps the
    /// line of the search and the bar many presses away; this key is one
    /// press from the content to the bar, one more to the search, one more
    /// to the column, and one more back to the title that was left.
    func cycleZone(forward: Bool) -> Bool {
        guard page == .catalogue, heldItem == nil, !modalOpen, !deskCovered, dockFan == nil else { return false }
        let current = zoneMode ? zoneFocus : deskCurrentZone
        guard let next = DeskZoneMap.hop(from: current, forward: forward, available: deskZones) else { return false }
        remoteNavigationActive = true
        enterZone(next)
        return true
    }

    /// An arrow held with Command goes straight to the zone on that side.
    func jumpZone(_ action: RemoteAction) -> Bool {
        guard page == .catalogue, heldItem == nil, !modalOpen, !deskCovered, dockFan == nil else { return false }
        let zones = deskZones
        let wanted: [DeskZone]
        switch action {
        case .up: wanted = [.top]
        case .down: wanted = [.dock]
        case .left: wanted = [.column]
        case .right: wanted = deskCurrentZone == .content ? [.actions, .content] : [.content]
        default: return false
        }
        guard let zone = wanted.first(where: zones.contains) else { return false }
        remoteNavigationActive = true
        enterZone(zone)
        return true
    }

    /// Frame of a zone while Back shows the zones of the screen.
    @ViewBuilder func zoneFrame(_ zone: DeskZone, radius: CGFloat, outset: CGFloat = 0, labelled: Bool = true) -> some View {
        if zoneMode, deskZoneEntry(zone) != nil {
            let active = zoneFocus == zone
            let shape = RoundedRectangle(cornerRadius: radius + outset, style: .continuous)
            shape.strokeBorder(active ? themeAccent : Color.white.opacity(0.30), lineWidth: active ? 3 : 1)
                .background(themeAccent.opacity(active ? 0.10 : 0), in: shape)
                .shadow(color: active ? themeAccent.opacity(0.7) : .clear, radius: Desk.pt(10))
                .overlay(alignment: .topTrailing) {
                    if active && labelled {
                        Text(zone.title.uppercased()).font(Desk.font(.caption2, .heavy)).tracking(1.2)
                            .foregroundStyle(.black).padding(.horizontal, Desk.pt(9)).padding(.vertical, Desk.pt(4))
                            .background(themeAccent, in: Capsule()).padding(Desk.pt(8))
                    }
                }
                .padding(-outset)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The compass of the zones: where each arrow leads, and where Back returns.
    private var zoneCaption: some View {
        let zones = deskZones
        let moves: [(RemoteAction, String)] = [(.up, "arrow.up"), (.left, "arrow.left"), (.right, "arrow.right"), (.down, "arrow.down")]
        let reachable = moves.compactMap { action, symbol -> (String, String)? in
            let target = DeskZoneMap.move(from: zoneFocus, action: action, available: zones, dock: dockPosition)
            return target == zoneFocus ? nil : (symbol, target.title)
        }
        return HStack(spacing: Desk.pt(18)) {
            ForEach(reachable, id: \.0) { symbol, name in
                Label(name, systemImage: symbol).font(Desk.font(.callout, .semibold))
            }
            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: Desk.pt(20))
            Label("Retour : \(deskBackTarget)", systemImage: "chevron.backward")
                .font(Desk.font(.callout, .medium)).foregroundStyle(themeAccent)
        }
        .padding(.horizontal, Desk.pt(22)).frame(height: Desk.pt(46))
        .fluxGlass(radius: Desk.pt(23))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zones de l’écran. " + reachable.map { "\($0.1)" }.joined(separator: ", ") + ". Retour pour \(deskBackTarget).")
    }

    func showHome() {
        guard !library.sources.isEmpty else { return }
        cancelEntrance()
        if page == .series || page == .player || heldItem != nil { home() }
        searchFocus = false; liveGroupSearchFocus = false; showingSearch = false; sidebarCountries = false
        newListKind = nil; renamingList = false; confirmingListDeletion = false
        // A list opened from the favourites belongs to that destination.
        if favoritesMode { favoritesMode = false; library.selectedPresetID = nil }
        livePreview.stop()
        library.flushBrowsingPreferences()
        deskHistory.reset()
        homeHover = nil; dockFan = nil
        page = .home
        focusID = currentDockID
        systemFocus = focusID
    }

    private func showSection(_ kind: IPTVMediaKind) {
        let leavingFavorites = favoritesMode, fromHome = page == .home
        #if os(tvOS)
        // From the home screen the remote is on an icon that the dock of
        // the section shows too, under the same name: the focus does not
        // change, and nothing would tell the catalogue that the remote is
        // there to be handed to its first title. Another section than
        // the last one opened with the remote left on its icon.
        if fromHome { browserHasEnteredFocus = true }
        #endif
        favoritesMode = false
        sidebarCountries = false
        if library.contentKind == kind {
            home()
            // The section opens where it was left, as it did at launch. A
            // television always puts the remote back in its content.
            #if os(tvOS)
            restoreBrowsingContext()
            #else
            if fromHome { restoreBrowsingContext() }
            #endif
        } else { changeKind(kind) }
        // A list opened from the favourites belongs to that destination; the
        // section itself opens on its whole catalogue.
        if leavingFavorites { library.selectedPresetID = nil }
        #if !os(tvOS)
        focusID = currentDockID
        #endif
    }

    func openSettings(_ destination: PlaybackSettingsView.Page? = nil, editing: PlaybackSettingsView.SourceEditor? = nil) {
        cancelEntrance()
        if page == .series || heldItem != nil { home() }
        searchFocus = false; liveGroupSearchFocus = false; sidebarCountries = false
        livePreview.stop()
        settingsRequest = DeskSettingsRequest(page: destination, sourceEditor: editing)
        page = .settings
        // The control that held the keyboard focus leaves with its screen.
        focusID = FluxDockItem.settings.focusID
        #if !os(tvOS)
        // On a television the settings take the remote on their own pages.
        systemFocus = focusID
        #endif
        recordPlace()
    }

    func enterFavorites() {
        #if os(tvOS)
        if page == .home { browserHasEnteredFocus = true }
        #endif
        if page != .catalogue || heldItem != nil { home() }
        sidebarCountries = false
        favoritesMode = true
        if library.selectedPresetID == nil {
            let kinds = [library.contentKind] + IPTVMediaKind.allCases.filter { $0 != library.contentKind }
            let filled = kinds.lazy.compactMap { kind in library.presets.lists(for: kind).first(where: { !$0.itemIDs.isEmpty }) }.first
            if let target = filled ?? library.presets.lists(for: library.contentKind).first { selectFavoriteList(target) }
        }
        #if os(tvOS)
        // The remote goes to the first title of the list, as in a section.
        restoreBrowsingContext()
        #else
        focusID = currentDockID
        systemFocus = focusID
        #endif
        recordPlace()
    }

    private func selectFavoriteList(_ preset: FavoritePreset) {
        newListKind = nil; renamingList = false; confirmingListDeletion = false
        if library.contentKind != preset.kind { changeKind(preset.kind) }
        favoritesMode = true
        continueOnly = false; group = nil
        library.selectedPresetID = preset.id
        clearPreview(); resetCatalogWindow()
    }

    func deskActivate(_ id: String) -> Bool {
        if let item = FluxDockItem(focusID: id) { dockAction(item); return true }
        if DockEntry.isShelfID(id) {
            let plan = dockPlan(hero: showsHome)
            if id == DockEntry.fanAllID { openDockFanList() }
            else if id.hasPrefix(DockEntry.fanPrefix) {
                if let row = dockFanModel(plan)?.rows.first(where: { $0.id == id }) { openShortcut(row.shortcut, resuming: false) }
            }
            else if let entry = plan.arrangement.entry(id: id) { dockActivate(entry) }
            return true
        }
        if id.hasPrefix("favorite-list-") {
            if let preset = library.presets.list(id: String(id.dropFirst("favorite-list-".count))) { selectFavoriteList(preset) }
            return true
        }
        if id == DeskZone.backID { deskLeaveScreen(); return true }
        if id == DeskZone.homeID { showHome(); return true }
        if id == DeskZone.searchID { search(); return true }
        if id == "countries-back" { closeCountries(); return true }
        if id.hasPrefix("favorite-new-"), let kind = IPTVMediaKind(rawValue: String(id.dropFirst("favorite-new-".count))) {
            beginNewList(kind); return true
        }
        if id == "country-all" { selectLiveCountry(nil); return true }
        if id.hasPrefix("country-") { selectLiveCountry(String(id.dropFirst("country-".count))); return true }
        return false
    }

    // MARK: Keyboard and remote

    private var deskSidebarIDs: [String] {
        guard page == .catalogue, !library.sources.isEmpty else { return [] }
        if favoritesMode {
            return IPTVMediaKind.allCases.flatMap { kind in
                library.presets.lists(for: kind).map { "favorite-list-\($0.id)" } + ["favorite-new-\(kind.rawValue)"]
            }
        }
        if sidebarCountries && facetAvailable {
            return ["countries-back", "country-all"] + facetEntries.map { "country-\($0.code)" }
        }
        return (facetAvailable ? ["countries"] : []) + ["group-all"]
            + library.currentPresets.map { "live-preset-\($0.id)" }
            + (library.contentKind == .movie ? ["continue-only"] : [])
            + ["live-manage-lists"] + liveGroups.map { "live-category-\($0)" }
    }
    /// Row of the navigation column that stands for the current selection.
    private var deskScopeID: String {
        if favoritesMode { return library.selectedPresetID.map { "favorite-list-\($0)" } ?? deskSidebarIDs.first ?? "group-all" }
        if sidebarCountries { return library.countryCode.map { "country-\($0)" } ?? "country-all" }
        if continueOnly { return "continue-only" }
        return liveScopeID
    }
    private var deskTrailingIDs: [String] {
        guard page == .catalogue, library.contentKind == .live, let item = previewItem,
              visibleSlice.index(of: item.id) != nil else { return [] }
        return ["live-watch", "live-favorite"] + (livePreview.player == nil ? [] : ["live-preview-mute"])
    }

    private func deskContentMove(from current: String?, _ action: RemoteAction) -> String? {
        switch page {
        case .catalogue:
            return DeskNavigation.move(from: current, action: action, items: visibleSlice, columns: columns,
                                       sidebarIDs: deskSidebarIDs, preferredSidebarID: deskScopeID,
                                       preferredItemID: previewID, toolbar: focusRows, trailingIDs: deskTrailingIDs,
                                       headerIDs: deskHeaderIDs)
        case .series, .player:
            return RemoteNavigation.move(from: current, action: action, rows: focusRows)
        case .settings, .home:
            return current
        }
    }

    func deskMove(_ action: RemoteAction) -> String? {
        if let anchor = dockFan {
            // An open folder: the arrows walk its titles, from the
            // nearest to the bar; across them it closes and the bar goes on.
            let position: FluxDockPosition = showsHome ? .bottom : dockPosition
            let ids = dockFanModel(dockPlan(hero: showsHome))?.ids ?? []
            let further: RemoteAction = position == .top ? .down : .up
            let nearer: RemoteAction = position == .top ? .up : .down
            if let current = focusID, let index = ids.firstIndex(of: current) {
                if action == further { return ids[min(ids.count - 1, index + 1)] }
                if action == nearer, index > 0 { return ids[index - 1] }
                if action == nearer || (position.isVertical && action == position.outward) { return anchor }
                dockFan = nil; focusID = anchor
            } else if focusID == anchor, action == (position.isVertical ? position.inward : further), let first = ids.first {
                return first
            } else { dockFan = nil }
        }
        if showsHome {
            // The home screen is its bar: Left and Right walk it, and Up
            // and Down its rows when it has several.
            let plan = dockPlan(hero: true)
            let ids = plan.ids
            guard let focusID, ids.contains(focusID) else { return currentDockID }
            let rows = heroRows(plan).map { $0.entries.map(\.id) }
            if rows.count > 1 { return DockArrangement.move(from: focusID, action: action, rows: rows) }
            return FluxDockNavigation.move(from: focusID, action: action, position: .bottom, dockIDs: ids,
                                           preferredDockID: currentDockID, entryID: nil) { current, _ in current }
        }
        let dockIDs = dockVisible ? barLeadIDs + dockPlan().ids : []
        let wasInDock = focusID.map(dockIDs.contains) ?? false
        let remembered = dockReturnFocus.flatMap { id -> String? in
            if visibleSlice.item(id: id) != nil || deskSidebarIDs.contains(id) || deskTrailingIDs.contains(id) { return id }
            return focusRows.contains(where: { $0.contains(id) }) ? id : nil
        }
        let target = FluxDockNavigation.move(from: focusID, action: action, position: dockPosition, dockIDs: dockIDs,
                                             preferredDockID: currentDockID, entryID: remembered) { current, direction in
            deskContentMove(from: current, direction)
        }
        if !wasInDock, let target, dockIDs.contains(target) { dockReturnFocus = focusID }
        return target
    }

    func updateDeskColumns(_ usable: CGFloat) {
        liveSidebarVisible = true
        let dock = dockPosition.isVertical ? FluxDockMetrics.thickness(dockPosition) : 0
        deskWidth = usable - dock
        let content = usable - dock - Desk.pt(48) - liveSidebarWidth - Desk.pt(18)
        if library.contentKind == .live {
            // One list of channels; the picture takes the width that remains,
            // as long as its panel keeps the height for what is written below.
            let list = min(Desk.pt(460), max(Desk.pt(330), content * 0.34))
            let strip = dockPosition.isVertical || dockPosition == .corner ? 0 : FluxDockMetrics.thickness(dockPosition)
            let byHeight = (browserHeight - Desk.pt(52) - Desk.pt(310) - strip) * 16 / 9 + Desk.pt(28)
            deskPreviewWidth = max(Desk.pt(380), min(content - list - Desk.pt(18), byHeight))
            columns = 1
        } else {
            // The gap between two sleeves, as the grid draws it.
            let estimated = (content - Desk.pt(32) + Desk.tv(4)) / (cardWidth + Desk.tv(4))
            // A window of the shape of a television holds what it holds:
            // a rounding of the scale must not cost a column.
            columns = estimated.isFinite ? Int(max(2, min(10, estimated + 0.02))) : 5
        }
    }
}
#endif

#if os(macOS) || os(tvOS)
// MARK: - Home screen (Mac): the destinations in the middle of the window

extension FluxScreen {
    /// Destination that the home screen describes: under the pointer, else
    /// held by the keyboard, else the section used last.
    private var homeItem: FluxDockItem {
        homeHover.flatMap { FluxDockItem(focusID: $0) } ?? focusID.flatMap { FluxDockItem(focusID: $0) }
            ?? FluxDockItem(kind: library.contentKind)
    }

    /// What the home screen says of the icon being pointed at: a
    /// destination and what it holds, or what the user keeps in the bar.
    private func homeHeadline(_ plan: DockPlan) -> (title: String, line: String, id: String) {
        // While the remote walks an open folder, its icon is the one.
        let pointed = homeHover ?? (focusID.map { $0.hasPrefix(DockEntry.fanPrefix) } == true ? dockFan : focusID)
        func kind(_ shortcut: DockShortcut) -> String {
            switch shortcut.target {
            case .channel: "Chaîne en direct"
            case .film: "Film"
            case .series: "Série"
            case .season: "Saison d’une série"
            case .episode: "Épisode"
            }
        }
        if let id = pointed, let entry = plan.arrangement.entry(id: id) {
            switch entry {
            case .destination: break
            case .shortcut(let shortcut, let section):
                let part = library.dockShelf.section(id: section)?.name ?? "Raccourcis"
                return (shortcut.title, "\(kind(shortcut)) · \(part)", id)
            case .resume(let shortcut):
                return (shortcut.title, "Reprendre · \((plan.progress ?? 0) * 2) % vus", id)
            case .recent(let shortcut): return (shortcut.title, "\(kind(shortcut)) · vu récemment", id)
            case .stack(let listID):
                let list = library.presets.list(id: listID)
                let count = list?.itemIDs.count ?? 0
                return (list?.name ?? "Liste", "\(list?.kind.frenchTitle ?? "Favoris") · \(count) \(count == 1 ? "titre" : "titres")", id)
            case .more:
                let count = plan.arrangement.hidden.count
                return ("Autres raccourcis", "\(count) \(count == 1 ? "raccourci" : "raccourcis") de plus", id)
            }
        }
        let item = homeItem
        return (homeTitle(item), homeLine(item), item.focusID)
    }
    /// Recherche, Favoris and Réglages keep the room shown before them.
    private var homeRoomKind: IPTVMediaKind { homeItem.mediaKind ?? homeKind ?? library.contentKind }

    private var dockUnitPoint: UnitPoint {
        switch dockPosition {
        case .bottom: .bottom
        case .corner: .bottomLeading
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    var homeTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.3, anchor: dockUnitPoint).combined(with: .opacity)
    }

    /// The three rooms stay mounted behind the home screen: pointing at a
    /// destination brings its room forward without waiting for a decode.
    var homeRooms: some View {
        ZStack {
            ForEach(IPTVMediaKind.allCases, id: \.self) { kind in
                ZStack {
                    FluxBackdrop(theme: theme(for: kind))
                    ProceduralStage(kind: kind, pixelLimit: 2560)
                }
                .opacity(kind == homeRoomKind ? 1 : 0)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: homeRoomKind)
    }

    private func homeTitle(_ item: FluxDockItem) -> String {
        switch item {
        case .live: "Télévision"
        case .movie: "Films"
        case .series: "Séries"
        case .search: "Recherche"
        case .favorites: "Favoris"
        case .settings: "Réglages"
        }
    }

    private func homeLine(_ item: FluxDockItem) -> String {
        func count(_ kind: IPTVMediaKind, _ one: String, _ many: String) -> String {
            let value = library.catalogCount(kind)
            return "\(value.formatted()) \(value == 1 ? one : many)"
        }
        switch item {
        case .live: return count(.live, "chaîne en direct", "chaînes en direct")
        case .movie: return count(.movie, "film", "films")
        case .series: return count(.series, "série", "séries")
        case .search:
            switch library.contentKind {
            case .live: return "Trouver une chaîne"
            case .movie: return "Trouver un film"
            case .series: return "Trouver une série"
            }
        case .favorites:
            let lists = library.presets.lists
            let titles = lists.reduce(0) { $0 + $1.itemIDs.count }
            return "\(lists.count) \(lists.count == 1 ? "liste" : "listes") · \(titles.formatted()) \(titles == 1 ? "titre" : "titres")"
        case .settings: return "Sources, interface, dock et lecture"
        }
    }

    var deskHome: some View {
        GeometryReader { geometry in
            let plan = dockPlan(hero: true)
            // As it fills, the bar takes a second row, then a third: its
            // icons keep their size instead of sharing one row.
            let rows = heroRows(plan)
            let longest = rows.max { $0.entries.count < $1.entries.count } ?? plan.arrangement
            let scale = FluxDockMetrics.heroScale(count: longest.entries.count, breaks: longest.breaks.count,
                                                  width: geometry.size.width, height: geometry.size.height, rows: rows.count)
            let headline = homeHeadline(plan)
            // Transparent room that the bar keeps above its plate for the
            // icons that grow under the pointer.
            let growth = FluxDockMetrics(hero: scale).growth
            let fan = dockFanModel(plan)
            ZStack {
                if dockFan != nil { dockFanVeil }
                // The plate of the bar is in the middle of the window; the
                // name of what is pointed at stands above it. Each row
                // keeps above it the room where its icons grow: the rows
                // are brought closer, and a lower one is drawn over the
                // one above it.
                VStack(spacing: rows.count > 1 ? -growth * 0.62 : 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        dockItself(DockPlan(arrangement: row, shrink: 1, stacks: plan.stacks, progress: plan.progress,
                                            catalogue: plan.catalogue, ready: plan.ready),
                                   fan: fan, hero: scale, crowded: rows.count > 1)
                            #if os(tvOS)
                            .focusSection()
                            #endif
                    }
                }
                    .overlay(alignment: .top) {
                        ZStack {
                            VStack(spacing: 8 * scale) {
                                Text(headline.title)
                                    .font(.system(size: 66 * scale, weight: .bold)).tracking(-0.5)
                                    .minimumScaleFactor(0.45)
                                    .accessibilityAddTraits(.isHeader)
                                Text(headline.line)
                                    .font(.system(size: 21 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                            }
                            // A long title of series shrinks before it leaves the window.
                            .lineLimit(1).frame(width: max(200, geometry.size.width - 96))
                            .shadow(color: .black.opacity(0.6), radius: Desk.pt(16), y: 4)
                            .id(headline.id).transition(.opacity)
                        }
                        // An open folder rises where the name stands.
                        .opacity(dockFan == nil ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: headline.id)
                        .alignmentGuide(.top) { $0[.bottom] - growth + 18 * scale }
                        .allowsHitTesting(false)
                    }
                    .offset(y: -growth / 2)
                homeBar.frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: homeItem) { _, item in
            if let kind = item.mediaKind { homeKind = kind }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Accueil")
        .accessibilityIdentifier("desk-home-screen")
    }

    /// Name of the application and of its source, then the date and the time.
    private var homeBar: some View {
        HStack(spacing: Desk.pt(12)) {
            HStack(spacing: Desk.pt(10)) {
                Image(systemName: "play.tv.fill").foregroundStyle(themeAccent)
                Text("FLUX").font(Desk.font(.callout, .heavy)).tracking(4)
                if let source = library.selectedSource {
                    Text(source.name).font(Desk.font(.callout, .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
            }
            .padding(.horizontal, Desk.pt(16)).frame(height: Desk.pt(38)).fluxGlass(radius: Desk.pt(19))
            Spacer(minLength: Desk.pt(12))
            TimelineView(.everyMinute) { context in
                HStack(spacing: Desk.pt(12)) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(Desk.font(.callout, .medium)).foregroundStyle(.white.opacity(0.72))
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .font(Desk.font(.callout, .bold).monospacedDigit())
                }
                .padding(.horizontal, Desk.pt(16)).frame(height: Desk.pt(38)).fluxGlass(radius: Desk.pt(19))
            }
        }
        .padding(.horizontal, Desk.pt(24)).padding(.top, Desk.pt(14)).frame(height: Desk.pt(58), alignment: .top)
    }
}
#endif

#if os(macOS) || os(tvOS)
// MARK: - Desk screens (Mac): navigation column, channels, preview, catalogue

extension FluxScreen {
    // MARK: Navigation column

    /// The same column in every section: scopes and categories, the countries
    /// of the channels, or the favourite lists of the three kinds.
    private var deskSidebar: some View {
        return VStack(alignment: .leading, spacing: Desk.pt(12)) {
            if favoritesMode { favoritesSidebar }
            else if sidebarCountries && facetAvailable { countriesSidebar }
            else { scopeSidebar }
        }
        .padding(Desk.pt(14)).frame(width: liveSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        // A frame drawn after the glass would be sampled by it: the frames
        // of the zones belong to what each glass panel shows.
        .overlay { zoneFrame(.column, radius: Desk.pt(25)) }
        .fluxGlass(radius: Desk.pt(25))
        .padding(.bottom, navigationFootRoom)
    }

    /// Back and the home screen are at the top of every navigation column.
    /// With the search, the reload and the pages they form the top zone.
    private func sidebarHeading(_ title: String) -> some View {
        DeskColumnHeader(title: title, backTitle: deskBackTitle,
                         back: barFlanks ? nil : { deskLeaveScreen() }, home: barFlanks ? nil : { showHome() },
                         focusedID: focusShown ? shownFocusID : nil, systemFocus: nativeFocus)
            .overlay { if !barFlanks { zoneFrame(.top, radius: Desk.pt(14), outset: 6, labelled: false) } }
    }

    @ViewBuilder private var scopeSidebar: some View {
        let kind = library.contentKind
        sidebarHeading(kind == .live ? "TÉLÉVISION" : kind == .movie ? "FILMS" : "SÉRIES")
        if facetAvailable { liveCountryButton }
        #if os(tvOS)
        // The field of the television opens its own keyboard.
        HStack(spacing: Desk.pt(8)) {
            Image(systemName: "magnifyingglass").font(Desk.font(.callout)).foregroundStyle(.secondary)
            TextField("Filtrer les catégories", text: $library.groupSearch,
                      prompt: Text("Filtrer les catégories")
                        .foregroundStyle(liveGroupSearchFocus ? Color.black.opacity(0.55) : Color.white.opacity(0.55)))
                .textFieldStyle(.plain).font(Desk.font(.callout))
                .focused($liveGroupSearchFocus)
                .onSubmit {
                    liveGroupSearchFocus = false
                    focusID = liveGroups.first.map { "live-category-\($0)" } ?? "group-all"
                    systemFocus = focusID
                }
        }
        .padding(.leading, Desk.pt(12)).padding(.trailing, Desk.pt(4)).padding(.vertical, Desk.pt(4))
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: Desk.pt(14)))
        .overlay {
            RoundedRectangle(cornerRadius: Desk.pt(14))
                .strokeBorder(.white.opacity(liveGroupSearchFocus ? 0.8 : 0), lineWidth: 2).allowsHitTesting(false)
        }
        #else
        HStack(spacing: Desk.pt(8)) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filtrer les catégories", text: $library.groupSearch)
                .textFieldStyle(.plain)
                .focused($liveGroupSearchFocus)
                .onSubmit {
                    liveGroupSearchFocus = false
                    focusID = liveGroups.first.map { "live-category-\($0)" } ?? "group-all"
                    systemFocus = focusID
                }
            if !groupSearch.isEmpty {
                Button { groupSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Effacer la recherche de catégories")
            }
        }
        .font(Desk.font(.callout)).padding(Desk.pt(11))
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: Desk.pt(13)))
        #endif
        ScrollViewReader { reader in
            let _ = (scrolls.column = reader)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Desk.pt(5)) {
                    liveScopeButton(kind == .live ? "Toutes les chaînes" : kind == .movie ? "Tous les films" : "Toutes les séries",
                                    symbol: "square.grid.2x2", id: "group-all",
                                    count: library.catalogResults.all.items.count) { showAllCatalog() }
                    ForEach(library.currentPresets) { preset in
                        liveScopeButton(preset.name, symbol: preset.isDefault ? "star.fill" : "text.badge.star",
                                        id: "live-preset-\(preset.id)") {
                            if library.selectedPresetID == preset.id { library.selectedPresetID = nil; clearPreview(); resetCatalogWindow() }
                            else { selectLivePreset(preset.id) }
                        }
                    }
                    if kind == .movie {
                        liveScopeButton("À reprendre", symbol: "clock.arrow.circlepath", id: "continue-only") { toggleResumeFilter() }
                    }
                    liveScopeButton("Gérer les listes", symbol: "slider.horizontal.3", id: "live-manage-lists") { presentLists() }
                    Text("CATÉGORIES").font(Desk.font(.caption2, .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        .padding(.horizontal, Desk.pt(12)).padding(.top, Desk.pt(18)).padding(.bottom, Desk.pt(5))
                    ForEach(liveGroups, id: \.self) { name in
                        liveScopeButton(name, symbol: "folder", id: "live-category-\(name)",
                                        count: library.catalogResults.slice(group: name).items.count) { toggleCategory(name) }
                    }
                    if liveGroups.isEmpty {
                        Text(groupSearch.isEmpty ? "Les catégories apparaîtront avec votre catalogue." : "Aucune catégorie correspondante.")
                            .font(Desk.font(.caption)).foregroundStyle(.secondary).padding(Desk.pt(12))
                    }
                }.padding(.vertical, Desk.pt(3))
            }
            .onChange(of: focusID) { _, id in
                if let id, remoteNavigationActive, deskSidebarIDs.contains(id) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// A second click on the selected category returns to the whole scope.
    private func toggleCategory(_ name: String) {
        if group == name {
            group = nil
            clearPreview(); resetCatalogWindow()
        } else if library.contentKind == .live {
            selectLiveGroup(name)
        } else {
            // "À reprendre" keeps combining with a category for films.
            group = name
            liveGroupSearchFocus = false
            clearPreview(); resetCatalogWindow()
        }
    }

    /// Countries of the channels, or languages of the films and series.
    private var facetEntries: [(code: String, name: String, count: Int)] {
        library.contentKind == .live
            ? library.liveCountries.map { ($0.code, $0.name, $0.channelCount) }
            : library.mediaLanguages.map { ($0.code, $0.name, $0.titleCount) }
    }
    /// A catalogue whose titles carry no language label offers no such filter.
    private var facetAvailable: Bool {
        library.contentKind == .live || library.mediaLanguages.contains { $0.code != MediaLanguage.unknownCode }
    }

    private func flag(_ code: String?) -> String {
        guard let code else { return "🌍" }
        let letters = code.uppercased().unicodeScalars
        guard code != LiveCountry.unknownCode, letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else { return "🏳️" }
        return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }))
    }

    @ViewBuilder private var countriesSidebar: some View {
        Button { pointerSelect("countries"); closeCountries() } label: {
            FluxFocused(id: "countries-back", logical: selectedByKeyboard("countries-back")) { focusedBack in
                HStack(spacing: Desk.pt(8)) {
                    Image(systemName: "chevron.left").font(Desk.font(.caption, .bold))
                    Text(library.contentKind == .live ? "Pays des chaînes" : library.contentKind == .movie ? "Langue des films" : "Langue des séries")
                        .font(Desk.font(.callout, .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(11))
                .background(.white.opacity(focusedBack ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: Desk.pt(13)))
                .overlay { RoundedRectangle(cornerRadius: Desk.pt(13)).strokeBorder(focusedBack ? .white.opacity(0.75) : .clear, lineWidth: 2).allowsHitTesting(false) }
                .contentShape(RoundedRectangle(cornerRadius: Desk.pt(13)))
            }
        }
        .buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "countries-back").id("countries-back")
        .accessibilityLabel("Revenir aux catégories")
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Desk.pt(5)) {
                    countryRow(code: nil, name: library.contentKind == .live ? "Tous les pays" : "Toutes les langues",
                               count: facetEntries.reduce(0) { $0 + $1.count })
                    ForEach(facetEntries, id: \.code) { entry in
                        countryRow(code: entry.code, name: entry.name, count: entry.count)
                    }
                }.padding(.vertical, Desk.pt(3))
            }
            .onAppear { reader.scrollTo(library.countryCode.map { "country-\($0)" } ?? "country-all", anchor: .center) }
            .onChange(of: focusID) { _, id in
                if let id, remoteNavigationActive, deskSidebarIDs.contains(id) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func countryRow(code: String?, name: String, count: Int) -> some View {
        let id = code.map { "country-\($0)" } ?? "country-all"
        let selected = library.countryCode == code
        let key = CountryKey(code: code, name: name, count: count, selected: selected, keyboard: selectedByKeyboard(id),
                             live: library.contentKind == .live, theme: theme)
        return FluxStable(key) { countryRowBody(code: code, name: name, count: count, id: id, key: key) }.equatable()
    }

    /// What a row of the countries or of the languages is drawn from.
    private struct CountryKey: Equatable {
        let code: String?
        let name: String
        let count: Int
        let selected: Bool
        let keyboard: Bool
        let live: Bool
        let theme: VideoClubTheme
    }

    private func countryRowBody(code: String?, name: String, count: Int, id: String, key: CountryKey) -> some View {
        let selected = key.selected
        return Button { pointerSelect(id); selectLiveCountry(code) } label: {
          FluxFocused(id: id, logical: key.keyboard) { focused in
            HStack(spacing: Desk.pt(10)) {
                if library.contentKind == .live {
                    Text(flag(code)).font(Desk.font(.title3)).frame(width: Desk.pt(30))
                } else {
                    // A language has no flag: its code, as playlists write it.
                    Text(code == nil ? "•" : code == MediaLanguage.unknownCode ? "?" : code == MediaLanguage.multipleCode ? "MULTI" : (code ?? "").uppercased())
                        .font(Desk.system(10, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: Desk.pt(30), height: Desk.pt(20))
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Desk.pt(5)))
                }
                Text(name).font(Desk.font(.callout, selected ? .semibold : .regular))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").font(Desk.font(.caption).monospacedDigit()).foregroundStyle(.secondary)
                if selected { Image(systemName: "checkmark").font(Desk.font(.caption, .bold)).foregroundStyle(themeAccent) }
            }
            .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(10))
            .background(selected ? themeAccent.opacity(0.16) : .white.opacity(focused ? 0.09 : 0), in: RoundedRectangle(cornerRadius: Desk.pt(13)))
            .overlay { RoundedRectangle(cornerRadius: Desk.pt(13)).strokeBorder(focused ? .white.opacity(0.75) : .clear, lineWidth: 2).allowsHitTesting(false) }
            .contentShape(RoundedRectangle(cornerRadius: Desk.pt(13)))
          }
        }
        // The focus binding belongs to the button itself: nothing may stand
        // between them, or the remote cannot be sent to the row.
        .buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: id).id(id)
        .accessibilityIdentifier("live-country-option-\(code ?? "all")")
        .accessibilityLabel(name)
        .accessibilityValue("\(count) \(library.contentKind == .live ? "chaînes" : "titres")\(selected ? ", sélectionné" : "")")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "live-country-option-\(code ?? "all")").allowsHitTesting(false))
        #endif
    }

    @ViewBuilder private var favoritesSidebar: some View {
        sidebarHeading("FAVORIS")
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Desk.pt(5)) {
                    ForEach(IPTVMediaKind.allCases, id: \.self) { kind in
                        Text(kind.frenchTitle.uppercased())
                            .font(Desk.font(.caption2, .semibold)).tracking(1.5).foregroundStyle(.secondary)
                            .padding(.horizontal, Desk.pt(12)).padding(.top, kind == .live ? 8 : 18).padding(.bottom, Desk.pt(5))
                        ForEach(library.presets.lists(for: kind)) { preset in
                            liveScopeButton(preset.name, symbol: preset.isDefault ? "star.fill" : "text.badge.star",
                                            id: "favorite-list-\(preset.id)", count: preset.itemIDs.count) { selectFavoriteList(preset) }
                        }
                        newListRow(kind)
                    }
                }.padding(.vertical, Desk.pt(3))
            }
            .onChange(of: focusID) { _, id in
                if let id, remoteNavigationActive, deskSidebarIDs.contains(id) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder private func newListRow(_ kind: IPTVMediaKind) -> some View {
        if newListKind == kind {
            VStack(alignment: .leading, spacing: Desk.pt(5)) {
                HStack(spacing: Desk.pt(7)) {
                    TextField("Nom de la liste", text: $newListName)
                        .textFieldStyle(.plain).focused($listNameFocus)
                        .onSubmit { commitNewList(kind) }
                        .onExitCommand { newListKind = nil }
                    Button { commitNewList(kind) } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(themeAccent) }
                        .buttonStyle(.plain).accessibilityLabel("Créer la liste")
                        .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { newListKind = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Annuler la nouvelle liste")
                }
                .font(Desk.font(.callout)).padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(10))
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: Desk.pt(13)))
                if listNameInvalid {
                    Text("Nom déjà utilisé ou trop long.").font(Desk.font(.caption2)).foregroundStyle(.orange).padding(.horizontal, Desk.pt(12))
                }
            }
        } else {
            liveScopeButton("Nouvelle liste", symbol: "plus", id: "favorite-new-\(kind.rawValue)") { beginNewList(kind) }
        }
    }

    func beginNewList(_ kind: IPTVMediaKind) {
        renamingList = false; confirmingListDeletion = false; listNameInvalid = false
        newListName = ""; newListKind = kind
        Task { @MainActor in
            await Task.yield()
            listNameFocus = true
        }
    }

    private func commitNewList(_ kind: IPTVMediaKind) {
        let before = Set(library.presets.lists(for: kind).map(\.id))
        guard library.createPreset(name: newListName, kind: kind) else { listNameInvalid = true; return }
        listNameInvalid = false; newListKind = nil
        if let created = library.presets.lists(for: kind).first(where: { !before.contains($0.id) }) { selectFavoriteList(created) }
    }

    /// A list created by the user can be renamed or removed from its own screen.
    @ViewBuilder private var favoriteListActions: some View {
        if favoritesMode, let preset = library.selectedPreset, !renamingList, !confirmingListDeletion {
            // Any list can stand in the dock as a folder.
            let shown = library.dockShelf.showsStack(preset.id)
            navButton(shown ? "Retirer du dock" : "Dossier dans le dock", icon: "dock.rectangle", id: "favorite-dock", active: shown) {
                library.setDockStack(preset.id, shown: !shown)
            }
        }
        if favoritesMode, let preset = library.selectedPreset, !preset.isDefault {
            if renamingList {
                TextField("Nom de la liste", text: $newListName)
                    .textFieldStyle(.plain).focused($listNameFocus)
                    .onSubmit { renameList(preset) }
                    .onExitCommand { renamingList = false }
                    .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(9)).frame(width: Desk.pt(220))
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Desk.pt(12)))
                    .overlay { RoundedRectangle(cornerRadius: Desk.pt(12)).strokeBorder(listNameInvalid ? Color.orange : .white.opacity(0.12), lineWidth: 1) }
                navButton("Enregistrer", icon: "checkmark", id: "favorite-rename-save") { renameList(preset) }
                navButton("Annuler", icon: "xmark", id: "favorite-rename-cancel", iconOnly: true) { renamingList = false }
            } else if confirmingListDeletion {
                Text("Supprimer cette liste ?").font(Desk.font(.callout, .semibold))
                navButton("Annuler", icon: "xmark", id: "favorite-delete-cancel") { confirmingListDeletion = false }
                navButton("Supprimer", icon: "trash", id: "favorite-delete-confirm", active: true) {
                    let kind = preset.kind
                    library.deletePreset(preset)
                    confirmingListDeletion = false
                    if let fallback = library.presets.lists(for: kind).first { selectFavoriteList(fallback) }
                }
            } else {
                navButton("Renommer", icon: "pencil", id: "favorite-rename") {
                    listNameInvalid = false; newListName = preset.name; renamingList = true
                    Task { @MainActor in
                        await Task.yield()
                        listNameFocus = true
                    }
                }
                navButton("Supprimer", icon: "trash", id: "favorite-delete", iconOnly: true) { confirmingListDeletion = true }
            }
        }
    }

    private func renameList(_ preset: FavoritePreset) {
        if library.renamePreset(preset, name: newListName) { renamingList = false; listNameInvalid = false }
        else { listNameInvalid = true }
    }

    // MARK: Title and search shared by the three sections

    private var deskTitle: String {
        if continueOnly { return "À reprendre" }
        if let preset = library.selectedPreset { return favoritesMode ? "\(preset.name) · \(preset.kind.frenchTitle)" : preset.name }
        if let group { return group }
        return library.contentKind == .live ? "Télévision" : environment.title
    }
    private var deskSubtitle: String {
        let count = visible.count
        let noun: String
        switch library.contentKind {
        case .live: noun = count == 1 ? "chaîne" : "chaînes"
        case .movie: noun = count == 1 ? "film" : "films"
        case .series: noun = count == 1 ? "série" : "séries"
        }
        let amount = library.isFiltering ? "Recherche…" : "\(count.formatted(.number.locale(Locale(identifier: "fr_FR")))) \(noun)"
        // The count first: a long name of source is what a narrow line cuts.
        return "\(amount) · \(library.selectedSource?.name ?? "Bibliothèque")"
    }

    /// The name of what is shown and, where there is room, what it holds.
    private func deskTitleBlock(subtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: Desk.pt(4)) {
            Text(deskTitle).font(Desk.font(.title2, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.5), radius: Desk.pt(6), y: 1)
            if subtitle {
                Text(deskSubtitle).font(Desk.font(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: Desk.pt(4), y: 1)
            }
        }
    }
    /// The end of the top band: the actions of a list of favourites, the
    /// pages of a catalogue of films or series, and reload. The channels
    /// keep their pages in their own panel.
    @ViewBuilder private var deskTopActions: some View {
        favoriteListActions
        if deskPagerInBand { deskPager }
        navButton("Actualiser", icon: "arrow.clockwise", id: "reload", iconOnly: true) { library.reloadSelected() }
            .disabled(library.selectedSourceID == nil || library.isLoading)
            .fluxNavigationGlass(radius: Desk.pt(18))
    }
    private var deskPager: some View {
        HStack(spacing: Desk.pt(4)) {
            navButton("Page précédente", icon: "chevron.left", id: "page-prev", iconOnly: true) { changeCatalogPage(-1) }
                .disabled(catalogPage == 0)
            Text("\(catalogPage + 1) / \(catalogPageCount)").font(Desk.font(.callout).monospacedDigit())
                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
                .accessibilityLabel("Page \(catalogPage + 1) sur \(catalogPageCount)")
            navButton("Page suivante", icon: "chevron.right", id: "page-next", iconOnly: true) { changeCatalogPage(1) }
                .disabled(catalogPage + 1 >= catalogPageCount)
        }
        .fluxNavigationGlass(radius: Desk.pt(18))
    }
    private var deskTitleRow: some View {
        HStack(alignment: .center, spacing: Desk.pt(10)) {
            deskTitleBlock(subtitle: true)
            Spacer(minLength: 0)
            deskTopActions
        }.padding(.horizontal, Desk.pt(3))
    }

    private var deskSearchField: some View { deskSearchField(short: false) }
    /// `short`: beside the title of a narrow column, which says what is searched.
    private func deskSearchField(short: Bool) -> some View {
        let prompt: String
        switch library.contentKind {
        case _ where short: prompt = "Rechercher"
        case .live: prompt = "Rechercher une chaîne"
        case .movie: prompt = "Rechercher un film"
        case .series: prompt = "Rechercher une série"
        }
        #if os(tvOS)
        // The field of the television opens its own keyboard; the glass
        // around it marks it on the decor and shows when the remote is on it.
        return HStack(spacing: Desk.pt(10)) {
            Image(systemName: "magnifyingglass").font(Desk.font(.body, .semibold))
                .foregroundStyle(searchFocus ? .primary : .secondary)
            // Under the remote the system draws the field light: its prompt
            // then needs a dark ink to stay readable.
            TextField(prompt, text: $library.search,
                      prompt: Text(prompt).foregroundStyle(searchFocus ? Color.black.opacity(0.55) : Color.white.opacity(0.55)))
                .textFieldStyle(.plain).font(Desk.font(.body))
                .focused($searchFocus).onSubmit { searchFocus = false; focusFirstItem() }
        }
        .padding(.leading, Desk.pt(16)).padding(.trailing, Desk.pt(6)).padding(.vertical, Desk.pt(5))
        .fluxGlass(radius: Desk.pt(22))
        .overlay {
            RoundedRectangle(cornerRadius: Desk.pt(22), style: .continuous)
                .strokeBorder(.white.opacity(searchFocus ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false)
        }
        .accessibilityIdentifier("desk-search")
        #else
        let selected = focusID == DeskZone.searchID && focusShown && !searchFocus
        return HStack(spacing: Desk.pt(10)) {
            // A remote selects the field as a control; OK then places the cursor in it.
            Image(systemName: "magnifyingglass").foregroundStyle(selected ? .primary : .secondary)
                .fluxFocus(nativeFocus, id: DeskZone.searchID).id(DeskZone.searchID)
            TextField(prompt, text: $library.search)
                .textFieldStyle(.plain)
                .focused($searchFocus).onSubmit { searchFocus = false; focusFirstItem() }
            if !library.search.isEmpty {
                Button { library.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
            }
        }
        // As tall as the field of a television, which the system draws.
        .font(Desk.font(.body)).padding(.horizontal, Desk.pt(16)).frame(minHeight: Desk.tv(83))
        .fluxGlass(radius: Desk.pt(22))
        .overlay {
            RoundedRectangle(cornerRadius: Desk.pt(22), style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false)
        }
        .accessibilityIdentifier("desk-search")
        #endif
    }

    /// Title, search, pages and reload: with Back and Home, the top zone. It
    /// holds on one line wherever the column is wide enough, so that the
    /// catalogue starts as high as it can: with what the screen holds under
    /// its name, then without it, and on two lines only in a narrow column.
    private var deskTopBand: some View {
        let preset = favoritesMode ? library.selectedPreset : nil
        let bandIDs: Set<String> = [DeskZone.searchID, "page-prev", "page-next", "reload", "favorite-dock", "favorite-rename", "favorite-rename-save",
                                    "favorite-rename-cancel", "favorite-delete", "favorite-delete-cancel", "favorite-delete-confirm"]
        let key = TopBandKey(title: deskTitle, subtitle: deskSubtitle, search: library.search, searching: searchFocus,
                             kind: library.contentKind, pager: deskPagerInBand, page: catalogPage, pages: catalogPageCount,
                             reloadable: !(library.selectedSourceID == nil || library.isLoading),
                             presetID: preset?.id, presetName: preset?.name, presetLocked: preset?.isDefault ?? true,
                             presetDocked: preset.map { library.dockShelf.showsStack($0.id) } ?? false,
                             renaming: renamingList, confirming: confirmingListDeletion, listName: newListName,
                             listInvalid: listNameInvalid, naming: listNameFocus,
                             keyboard: focusShown ? shownFocusID.flatMap { bandIDs.contains($0) ? $0 : nil } : nil,
                             zone: zoneMode && deskZoneEntry(.top) != nil ? zoneFocus == .top : nil,
                             theme: theme, rich: richGlass)
        return FluxStable(key) { deskTopBandBody }.equatable()
    }

    /// What the line above the catalogue is drawn from.
    private struct TopBandKey: Equatable {
        let title: String
        let subtitle: String
        let search: String
        let searching: Bool
        let kind: IPTVMediaKind
        let pager: Bool
        let page: Int
        let pages: Int
        let reloadable: Bool
        /// A list of favourites on screen, and what can be done with it.
        let presetID: String?
        let presetName: String?
        let presetLocked: Bool
        /// Shown in the dock as a folder.
        let presetDocked: Bool
        let renaming: Bool
        let confirming: Bool
        let listName: String
        let listInvalid: Bool
        let naming: Bool
        /// Selected with the keyboard; a television shows its own focus.
        let keyboard: String?
        let zone: Bool?
        let theme: VideoClubTheme
        let rich: Bool
    }

    /// Rebuilt only when what it shows changes. It measures up to three
    /// layouts to choose one: a move of the remote in the catalogue must
    /// not ask it again.
    private var deskTopBandBody: some View {
        FluxProbe.hit("band")
        return ViewThatFits(in: .horizontal) {
            deskTopLine(subtitle: true)
            deskTopLine(subtitle: false)
            VStack(alignment: .leading, spacing: Desk.pt(12)) {
                deskTitleRow
                deskSearchField
            }
        }
        .overlay { zoneFrame(.top, radius: Desk.pt(20), outset: 6, labelled: false) }
        // Up from anywhere in the catalogue reaches this line, and Down
        // from it what stands under it, whatever their alignment.
        .deskFocusSection()
    }
    private func deskTopLine(subtitle: Bool) -> some View {
        return HStack(alignment: .center, spacing: Desk.pt(14)) {
            // The title takes its own width and no more: what remains of
            // the line is the search.
            deskTitleBlock(subtitle: subtitle).frame(maxWidth: Desk.pt(290), alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            deskSearchField(short: !subtitle)
                .frame(minWidth: Desk.pt(subtitle ? 250 : 200), idealWidth: Desk.pt(subtitle ? 250 : 200), maxWidth: .infinity)
            deskTopActions
        }
        .padding(.horizontal, Desk.pt(3))
    }

    // MARK: Television

    /// Categories, then the channels, then the picture and what is known of
    /// the selected channel.
    var liveDeskCatalogue: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: Desk.pt(18)) {
                deskSidebar.deskFocusSection()
                VStack(alignment: .leading, spacing: Desk.pt(12)) {
                    deskTopBand
                    Group { liveNotices }.deskFocusSection()
                    liveDeskChannels
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .deskFocusSection()
                // Regarder and Favoris stand lower than most channels: the
                // panel answers Right from any of them.
                liveDeskPreviewPanel.frame(width: deskPreviewWidth).deskFocusSection()
            }
        }
        .padding(.horizontal, Desk.pt(24))
    }

    private var liveDeskChannels: some View {
        Group {
            if (library.isLoading || library.isFiltering) && visible.isEmpty {
                ProgressView(library.isLoading ? "Chargement des chaînes…" : "Recherche…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                VStack(spacing: Desk.pt(16)) {
                    Image(systemName: "tv").font(Desk.system(48, .light)).foregroundStyle(themeAccent)
                    Text(favoritesMode ? "Cette liste est vide" : "Aucune chaîne dans cette sélection")
                        .font(Desk.font(.title3, .semibold)).multilineTextAlignment(.center)
                    if favoritesMode {
                        Text("Ajoutez une chaîne depuis son étoile.").font(Desk.font(.callout)).foregroundStyle(.secondary)
                    } else if library.credentialIssue == nil {
                        navButton("Toutes les chaînes", icon: "square.grid.2x2", id: "live-reset") { showAllCatalog() }
                    }
                }.padding(Desk.pt(24)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if catalogPageCount > 1 {
                        livePagination.padding(.horizontal, Desk.pt(14)).padding(.top, Desk.pt(10)).padding(.bottom, Desk.pt(2))
                    }
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Desk.pt(10)), count: max(1, columns)), spacing: Desk.pt(8)) {
                            ForEach(displayedItems) { item in liveDeskChannel(item) }
                        }.padding(Desk.pt(12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { zoneFrame(.content, radius: Desk.pt(25)) }
        .clipShape(RoundedRectangle(cornerRadius: Desk.pt(25), style: .continuous))
        .fluxGlass(radius: Desk.pt(25))
    }

    /// What a channel of the list is drawn from.
    private struct ChannelKey: Equatable {
        let item: IPTVItem
        let number: Int
        /// The full effects: the focus is animated.
        let rich: Bool
        let favorite: Bool
        /// Selected with the keyboard; a television shows its own focus.
        let selected: Bool
        let theme: VideoClubTheme
        let reduceMotion: Bool
    }

    private func liveDeskChannel(_ item: IPTVItem) -> some View {
        let key = ChannelKey(item: item, number: (visibleSlice.index(of: item.id) ?? 0) + 1, rich: focusMotion, favorite: library.isFavorite(item),
                             selected: selectedByKeyboard(item.id), theme: theme, reduceMotion: reduceMotion)
        #if os(tvOS)
        // The row under the remote grows over its neighbours.
        return FluxRaised { report in
            FluxStable(key) { liveDeskChannelBody(item, key: key, report: report) }.equatable()
        }
        #else
        return FluxStable(key) { liveDeskChannelBody(item, key: key, report: { _ in }) }.equatable()
            .zIndex(key.selected ? 1 : 0)
        #endif
    }

    /// Rebuilt only when `key` changes: a move of the remote leaves every
    /// row alone but the two it concerns, which read the focus themselves.
    private func liveDeskChannelBody(_ item: IPTVItem, key: ChannelKey, report: @escaping (Bool) -> Void) -> some View {
        FluxProbe.hit("channel")
        return Button {
            guard !modalOpen else { return }
            // The pointer has already selected the row under it: a click
            // watches that channel. A touch selects first, then watches.
            if previewID == item.id { selectCard(item) }
            else { pointerSelect(item.id); setPreview(item) }
        } label: {
            FluxFocused(id: item.id, logical: key.selected) { highlighted in
                LiveTVChannelRow(item: item, number: key.number, favorite: key.favorite, highlighted: highlighted, accent: themeAccent)
                    #if os(tvOS)
                    .animation(key.reduceMotion || !key.rich ? nil : .easeOut(duration: 0.12), value: highlighted)
                    #else
                    .animation(key.reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.8), value: highlighted)
                    #endif
            }
            #if os(tvOS)
            .background(DeskFocusReport(report: report))
            #endif
        }
        .buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: item.id).id(item.id)
        .accessibilityLabel(item.name)
        .accessibilityHint("Le pointeur affiche l’aperçu. Cliquer pour regarder. Appui long pour les favoris.")
        .accessibilityIdentifier("live-channel-\(item.id)")
        #if os(tvOS)
        // The remote selects a channel by resting on it; a long press opens its lists.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.65).onEnded { _ in chooseFavorites(item) })
        .onAppear { browseFocusTargetAppeared(item.id) }
        .onDisappear { mountedBrowseFocusTargets.remove(item.id) }
        #if FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "live-channel-\(item.id)").allowsHitTesting(false))
        #endif
        #else
        .contextMenu {
            Button("Regarder", systemImage: "play.fill") { selectCard(item) }
            Button("Favoris et listes", systemImage: "star") { chooseFavorites(item) }
        }
        .onLongPressGesture(minimumDuration: 0.65, maximumDistance: 12) { chooseFavorites(item) }
        .onHover { inside in if inside { deskHover(item) } }
        #endif
    }

    #if os(macOS)
    /// The row or sleeve under the pointer becomes the selection. During
    /// keyboard navigation the list scrolls under a pointer that has not
    /// moved: that pointer selects nothing.
    func deskHover(_ item: IPTVItem) {
        // Under an open folder of the dock the screen is out of reach.
        guard !modalOpen, heldItem == nil, entranceItem == nil, page == .catalogue, dockFan == nil else { return }
        if remoteNavigationActive, let rest = keyboardPointer, rest == NSEvent.mouseLocation { return }
        guard focusID != item.id || previewID != item.id else { return }
        pointerSelect(item.id); setPreview(item)
    }
    #endif

    private var liveDeskPreviewPanel: some View {
        return VStack(alignment: .leading, spacing: Desk.pt(14)) {
            if let item = previewItem, item.kind == .live, visibleSlice.index(of: item.id) != nil {
                #if os(tvOS)
                // A remote has Regarder just under the picture: a picture that
                // took its focus without showing it would be a lost press.
                LiveTVPreviewScreen(preview: livePreview, item: item, delay: livePreviewDelay,
                                    automatic: automaticLivePreview, large: true)
                    .accessibilityIdentifier("live-preview")
                #else
                Button { playItem(item) } label: {
                    LiveTVPreviewScreen(preview: livePreview, item: item, delay: livePreviewDelay,
                                        automatic: automaticLivePreview, large: true)
                        .overlay { Color.clear.contentShape(RoundedRectangle(cornerRadius: Desk.pt(20))) }
                }
                .buttonStyle(FluxBareButtonStyle())
                .accessibilityLabel("Regarder \(item.name)")
                .accessibilityIdentifier("live-preview")
                .fluxHelp("Regarder la chaîne")
                #endif
                liveDeskDetails(item)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.18), .black.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: Desk.pt(12)) {
                        Image(systemName: "tv").font(Desk.system(46, .light)).foregroundStyle(themeAccent)
                        Text("Choisissez une chaîne").font(Desk.font(.title3, .semibold))
                        Text("Son aperçu démarre ici, puis un clic l’ouvre en grand.")
                            .font(Desk.font(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(Desk.pt(20))
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Desk.pt(20)))
                .overlay { RoundedRectangle(cornerRadius: Desk.pt(20)).strokeBorder(.white.opacity(0.30), lineWidth: 1).allowsHitTesting(false) }
            }
            Spacer(minLength: 0)
        }
        .padding(Desk.pt(14))
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay { zoneFrame(.actions, radius: Desk.pt(27)) }
        .fluxGlass(radius: Desk.pt(27))
        .accessibilityElement(children: .contain)
    }

    private func liveDeskDetails(_ item: IPTVItem) -> some View {
        let number = (visibleSlice.index(of: item.id) ?? 0) + 1
        let country = LiveCountry.detectCode(in: item.group)
        return VStack(alignment: .leading, spacing: Desk.pt(12)) {
            HStack(spacing: Desk.pt(10)) {
                HStack(spacing: Desk.pt(6)) {
                    Circle().fill(.red.opacity(0.95)).frame(width: Desk.pt(7), height: Desk.pt(7))
                    Text("EN DIRECT").font(Desk.font(.caption2, .bold)).tracking(1.2)
                }
                .padding(.horizontal, Desk.pt(9)).padding(.vertical, Desk.pt(5))
                .background(.black.opacity(0.35), in: Capsule())
                Text("N° \(number)").font(Desk.font(.caption, .medium).monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if library.isFavorite(item) { Image(systemName: "star.fill").font(Desk.font(.callout)).foregroundStyle(.yellow) }
            }
            Text(item.name).font(Desk.font(.title2, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Desk.pt(8)) {
                Button { playItem(item) } label: {
                    Label("Regarder", systemImage: "play.fill").font(Desk.font(.callout, .semibold))
                        .padding(.horizontal, Desk.pt(18)).padding(.vertical, Desk.pt(11))
                        .fluxNavigationGlass(selected: true, tint: themeAccent, radius: Desk.pt(17))
                        .overlay {
                            FluxFocused(id: "live-watch", logical: selectedByKeyboard("live-watch") && focusShown) { focused in
                                RoundedRectangle(cornerRadius: Desk.pt(17)).strokeBorder(focused ? .white.opacity(0.9) : .clear, lineWidth: 2)
                            }
                            .allowsHitTesting(false)
                        }
                }.buttonStyle(FluxBareButtonStyle()).fluxFocus(nativeFocus, id: "live-watch").id("live-watch")
                    .accessibilityIdentifier("live-watch")
                navButton("Favoris", icon: library.isFavorite(item) ? "star.fill" : "star", id: "live-favorite") { chooseFavorites(item) }
                LiveTVPreviewObserver(preview: livePreview) { preview in
                    if preview.player != nil {
                        navButton(preview.isMuted ? "Activer le son de l’aperçu" : "Couper le son de l’aperçu",
                                  icon: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  id: "live-preview-mute", iconOnly: true) { preview.toggleMuted() }
                    }
                }
            }
            Divider().overlay(.white.opacity(0.14))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow("Catégorie", item.group)
                if let country { detailRow("Pays", "\(flag(country))  \(LiveCountry.displayName(for: country))") }
                detailRow("Source", library.selectedSource?.name ?? "—")
                detailRow("Position", "\(number) sur \(visible.count)")
            }
            Text(automaticLivePreview
                 ? "L’aperçu démarre après \(livePreviewDelay.title), sans le son. Un clic sur l’image ou sur la chaîne l’ouvre en plein écran."
                 : "L’aperçu automatique est désactivé dans Réglages › Interface.")
                .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Desk.pt(4))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(Desk.font(.callout)).foregroundStyle(.secondary)
            Text(value).font(Desk.font(.callout, .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Films and series

    var mediaDeskCatalogue: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: Desk.pt(18)) {
                deskSidebar.deskFocusSection()
                VStack(alignment: .leading, spacing: Desk.pt(12)) {
                    deskTopBand
                    Group { liveNotices }.deskFocusSection()
                    mediaDeskContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .deskFocusSection()
            }
        }
        .padding(.horizontal, Desk.pt(24))
    }

    @ViewBuilder private var mediaDeskContent: some View {
        if (library.isLoading || library.isFiltering) && visible.isEmpty {
            ProgressView(library.isLoading ? "Chargement du catalogue…" : "Recherche…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            VStack(spacing: Desk.pt(16)) {
                Image(systemName: library.contentKind == .movie ? "film" : "square.stack.3d.up")
                    .font(Desk.system(48, .light)).foregroundStyle(themeAccent)
                Text(library.credentialIssue != nil ? "Source à reconnecter" : favoritesMode ? "Cette liste est vide" : "Aucun titre dans cette sélection")
                    .font(Desk.font(.title3, .semibold))
                if favoritesMode {
                    Text("Ajoutez un titre depuis son étoile.").font(Desk.font(.callout)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            mediaCatalogGrid().overlay { zoneFrame(.content, radius: Desk.pt(22)) }
        }
    }
}
#endif
