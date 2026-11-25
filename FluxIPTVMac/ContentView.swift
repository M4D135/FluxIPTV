import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

private enum FluxPage: Equatable { case catalogue, series, player }

/// One living-room UI for Mac, iPhone, iPad and Apple TV. All actual tvOS navigation
/// uses the OS focus engine; the Mac simulator and gamepad use the shared focus grid.
struct ContentView: View {
    @EnvironmentObject private var library: IPTVLibrary
    @EnvironmentObject private var playback: PlaybackController
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var page: FluxPage = .catalogue
    @State private var group: String? = nil
    @State private var continueOnly = false
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
    @AppStorage(FluxAppearance.glassKey) private var richGlass = true
    @AppStorage(FluxAppearance.densityKey) private var density = "cinema"
    @AppStorage(ClubInterfaceProfile.storageKey) private var clubProfile: ClubInterfaceProfile = .neoVideoClub
    @State private var remoteNavigationActive = false
    @State private var showingGroups = false
    @State private var showingNavigationMenu = false
    @State private var groupSearch = ""
    @State private var liveSidebarVisible = false
    @State private var browserHeight: CGFloat = 900
    @FocusState private var liveGroupSearchFocus: Bool
    @StateObject private var livePreview = LiveTVPreviewController()
    @AppStorage(LiveTVPreviewDelay.storageKey) private var livePreviewDelay: LiveTVPreviewDelay = .three
    @AppStorage(LiveTVPreviewDelay.automaticKey) private var automaticLivePreview = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var series: IPTVItem?
    @State private var seasons: [IPTVSeason] = []
    @State private var seasonNumber: Int?
    @State private var episodesLoading = false
    @State private var episodesFailed = false
    @State private var seriesRequest = UUID()
    @State private var columns = 5
    @State private var compactChrome = false
    @State private var focusID: String? = "tab-live"
    @State private var previewID: String?
    @State private var previewItem: IPTVItem?
    @State private var heldItem: IPTVItem?
    @State private var heldSlice: CatalogSlice?
    @State private var heldDetails = IPTVDetails()
    @State private var caseExpanded = false
    @State private var caseToken = UUID()
    @State private var caseYaw = 0.0
    @State private var casePitch = 0.0
    @State private var caseRemoteEvent: CaseRemoteEvent?
    @State private var casePadSignal: CasePadSignal?
    @State private var caseStartEpisodes = false
    @State private var cardFrames = CaseFrameCache()
    @State private var catalogPage = 0
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var systemFocus: String?
    @FocusState private var searchFocus: Bool
    @State private var cinema = false
    @State private var caseTrailerVisible = false
    @State private var cinemaControls = true
    @State private var playerControlsTask: Task<Void, Never>?
    @State private var hoveredPlayerControls: Set<String> = []
    @State private var playerWidth: CGFloat = 900
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var wasFullscreen = false
    @State private var cinemaWindowNumber: Int?
    @StateObject private var remoteInput = RemoteInputBridge()

    #if FLUX_CATALOG_UI_TESTING
    /// Seed only the initial selection; layout, controls and artwork remain the
    /// same production views used by the application.
    init(fixtureSelection: IPTVItem? = nil) {
        _previewID = State(initialValue: fixtureSelection?.id)
        _previewItem = State(initialValue: fixtureSelection)
        _focusID = State(initialValue: fixtureSelection?.id ?? "tab-live")
    }
    #endif

    private var selectedSeason: IPTVSeason? { seasons.first { $0.number == seasonNumber } }
    private var episodes: [IPTVItem] { selectedSeason?.episodes ?? [] }
    private var visibleSlice: CatalogSlice {
        continueOnly ? resumeSlice : library.catalogResults.slice(group:group)
    }
    private var visible: [IPTVItem] { visibleSlice.items }
    private var groups: [String] { library.catalogResults.groups }
    private var catalogPageSize: Int { max(library.contentKind == .live ? 1 : 2,columns)*12 }
    private var catalogPageCount: Int { visibleSlice.pageCount(size:catalogPageSize) }
    private var displayedItems: ArraySlice<IPTVItem> { visibleSlice.window(page:catalogPage,size:catalogPageSize) }
    private var livePreviewAllowed: Bool {
        page == .catalogue && library.contentKind == .live && heldItem == nil && entranceItem == nil
            && !modalOpen && scenePhase == .active
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
        if let first = displayedItems.first { focusID=first.id; setPreview(first) }
    }
    private var modalOpen: Bool {
        addingSource || editingSource != nil || presetEditor != nil || deletingPreset != nil || itemOptions != nil || showingSources || showingLists || showingEngines || showingGroups || showingNavigationMenu || library.alertMessage != nil
    }
    private var cardWidth: CGFloat {
        #if os(tvOS)
        return density == "compact" ? 185 : (library.contentKind == .live ? 280 : (clubProfile.isEditorial ? 200 : 225))
        #elseif os(iOS)
        return sizeClass == .compact ? 124 : (library.contentKind == .live ? 174 : 150)
        #else
        return density == "compact" ? (library.contentKind == .live ? 160 : 135) : (library.contentKind == .live ? 250 : (clubProfile.isEditorial ? 185 : 205))
        #endif
    }
    private var currentClubItem: IPTVItem? {
        visibleSlice.item(id:previewID) ?? visibleSlice.item(id:focusID) ?? visible.first
    }
    // A COW snapshot of the selected catalogue order. Filter/history refreshes
    // must not change the neighbors of a case already in the user's hands.
    private var inspectionSlice: CatalogSlice { heldSlice ?? visibleSlice }
    private func clubNeighbors(_ item:IPTVItem)->(IPTVItem?,IPTVItem?) {
        (inspectionSlice.adjacent(to:item.id,offset:-1),inspectionSlice.adjacent(to:item.id,offset:1))
    }
    private var showingAllCatalog: Bool {
        CatalogScope.isAll(group:group,search:library.search,presetID:library.selectedPresetID,resumeOnly:continueOnly)
    }
    private func showAllCatalog() {
        continueOnly=false;group=nil;library.selectedPresetID=nil;library.search=""
        clearPreview();resetCatalogWindow();focusID = library.contentKind == .live && !liveSidebarVisible ? "categories" : "group-all"
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
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollViewReader { reader in
                    VStack(spacing: 0) {
                        if page != .player && !cinema {
                            if library.contentKind == .live && page == .catalogue { liveHeader }
                            else { header }
                        }
                        switch page {
                        case .catalogue: catalogue
                        case .series: seriesDetail
                        case .player: playerPage
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity((heldItem != nil && caseExpanded) || entranceItem != nil ? 0 : 1)
                    .allowsHitTesting(heldItem == nil)
                    .disabled(heldItem != nil)
                    .accessibilityHidden(heldItem != nil)
                    .overlay {
                        if let heldItem { heldOverlay(heldItem, reader: reader) }
                    }
                    .coordinateSpace(name: "club-pane")
                    .onPreferenceChange(CaseFrameKey.self) { frames in cardFrames.update(frames) }
                    .onChange(of: heldItem?.id) { _, id in
                        guard id == nil, page == .catalogue, let target=focusID else{return}
                        revealCatalogItem(target)
                        Task { @MainActor in
                            await Task.yield()
                            guard heldItem == nil, page == .catalogue, !searchFocus else{return}
                            reader.scrollTo(target,anchor:.center)
                            systemFocus=target
                        }
                    }
                    .onChange(of: focusID) { _, id in
                        guard let id, heldItem == nil else { return }
                        if page == .catalogue, let item = visibleSlice.item(id:id) {
                            revealCatalogItem(id); setPreview(item)
                        }
                        #if os(tvOS)
                        systemFocus = id
                        reader.scrollTo(id, anchor: .center)
                        #else
                        if remoteNavigationActive && !searchFocus && !liveGroupSearchFocus {
                            systemFocus = id
                            reader.scrollTo(id, anchor: .center)
                        }
                        #endif
                    }
                    .onChange(of: catalogPage) { _, _ in
                        guard page == .catalogue, let id = heldItem?.id ?? focusID, displayedItems.contains(where: { $0.id == id }) else { return }
                        Task { @MainActor in
                            await Task.yield()
                            reader.scrollTo(id,anchor:.center)
                            if heldItem == nil && remoteNavigationActive { systemFocus=id }
                        }
                    }
                    .onChange(of: systemFocus) { _, id in
                        if heldItem == nil, let id, focusID != id { focusID = id }
                    }
                }
                #if !os(tvOS)
                // The simulator is a real side panel, never covers catalogue/video.
                // On narrow mobile displays it is presented separately.
                if showRemote && page != .player && !cinema && !caseTrailerVisible && geometry.size.width >= 800 {
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
            .onAppear { browserHeight = geometry.size.height; updateColumns(geometry.size.width) }
            .onChange(of: geometry.size.height) { _, height in browserHeight = height }
            .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
            .onChange(of: library.contentKind) { _, _ in continueOnly = false; group = nil; groupSearch = ""; liveGroupSearchFocus = false; clearPreview(); updateColumns(geometry.size.width) }
            .onChange(of: showRemote) { _, _ in updateColumns(geometry.size.width) }
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
        #if os(macOS)
        .frame(minWidth: page == .player ? 320 : 860, minHeight: page == .player ? 180 : 540)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { notice in
            if (notice.object as? NSWindow)?.windowNumber == cinemaWindowNumber { cinema = false; cinemaWindowNumber = nil }
        }
        #endif
        #if os(iOS)
        .statusBar(hidden: page == .player && cinema)
        .persistentSystemOverlays(page == .player && cinema ? .hidden : .automatic)
        #endif
        #if os(tvOS)
        .fluxExit(heldItem != nil || page != .catalogue || showingSearch || group != nil || continueOnly || library.selectedPresetID != nil) { if heldItem != nil { dispatch(.back) } else { back() } }
        .onPlayPauseCommand { dispatch(.playPause) }
        #else
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape, .space, "f"], phases: [.down, .repeat]) { press in
            guard !modalOpen else { return .ignored }
            if searchFocus {
                if press.key == .escape { showingSearch = false; searchFocus = false; return .handled }
                return .ignored
            }
            if liveGroupSearchFocus {
                if press.key == .escape { liveGroupSearchFocus = false; return .handled }
                return .ignored
            }
            if heldItem != nil, press.phase == .repeat,
               press.key == .leftArrow || press.key == .rightArrow { return .handled }
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
        .sheet(isPresented: $addingSource) { AddSourceSheet(onSaved: { home() }).environmentObject(library) }
        .sheet(item: $editingSource) { source in AddSourceSheet(existing: source, onSaved: { home() }).environmentObject(library) }
        .sheet(item: $presetEditor) { editor in
            PresetNameSheet(editor: editor) { name in
                if let existing = editor.existing { return library.renamePreset(existing, name: name) }
                return library.createPreset(name: name, kind: editor.kind, initialItem: editor.initialItem)
            }
        }
        .sheet(isPresented: $showingSources) { sourcesPanel }
        .sheet(isPresented: $showingLists) { listsPanel }
        .sheet(isPresented: $showingGroups) { groupsPanel }
        .sheet(isPresented: $showingEngines, onDismiss: { diagnosticSettings = false }) { enginesPanel }
        .sheet(item: $itemOptions) { item in itemPanel(item) }
        .confirmationDialog("Navigation", isPresented: $showingNavigationMenu, titleVisibility: .visible) {
            Button("Sources") { showingSources = true }
            Button("Rechercher") { showingNavigationMenu = false; search() }
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
        .alert("Flux IPTV", isPresented: Binding(get: { library.alertMessage != nil }, set: { if !$0 { library.alertMessage = nil } })) {
            Button("OK", role: .cancel) { library.alertMessage = nil }
        } message: { Text(library.alertMessage ?? "") }
        .onChange(of: library.selectedSourceID) { _, _ in home(); group = nil; clearPreview() }
        .onChange(of: library.selectedPresetID) { _, id in if id != nil {continueOnly=false};if library.contentKind != .live {group=nil};clearPreview() }
        .onChange(of: library.search) { _, _ in if library.contentKind != .live {group=nil};clearPreview() }
        .onChange(of: group) { _, _ in clearPreview(); resetCatalogWindow() }
        .onChange(of: library.catalogResults.revision) { _, _ in resetCatalogWindow() }
        .onChange(of: continueOnly) { _, _ in resetCatalogWindow(); clearPreview() }
        .onChange(of: playback.history.entries) { _, _ in
            if continueOnly { rebuildResumeSlice(); catalogPage=min(catalogPage,catalogPageCount-1) }
        }
        .onChange(of: catalogPageSize) { _, _ in
            if let id=heldItem?.id ?? previewID { revealCatalogItem(id) }
            else { catalogPage=min(catalogPage,catalogPageCount-1) }
        }
        .task(id: livePreviewKey) {
            guard livePreviewAllowed, let item = previewItem, item.kind == .live else { livePreview.stop(); return }
            do {
                let urls = automaticLivePreview ? try library.playbackURLs(for: item) : []
                livePreview.schedule(id: item.id, urls: urls, delay: livePreviewDelay, enabled: automaticLivePreview)
            } catch { livePreview.markUnavailable() }
        }
        .onDisappear { caseDetailTask?.cancel(); caseTransitionTask?.cancel(); entranceTask?.cancel(); favoriteFeedbackTask?.cancel(); playerControlsTask?.cancel(); livePreview.stop() }
    }

    #if !os(tvOS)
    private var remotePanel: some View {
        RemotePad(appearance: $remoteAppearance, send: dispatch, caseSwipe: heldItem == nil ? nil : { input in
            casePadSignal=CasePadSignal(input:input)
        }, close: {
            showRemote = false; remoteNavigationActive = false
        }, volume: playback.localVolume, muted: playback.muted)
    }
    #endif

    // Generated stage and artwork exist only in catalogue/series mode.
    // No decorative render passes or backdrop downloads behind video.
    private var background: some View {
        ZStack {
            if page == .player || caseTrailerVisible {
                Color.black.ignoresSafeArea()
            } else {
                FluxBackdrop(theme: theme)
                ProceduralStage(kind: library.contentKind)
                    .scaleEffect(entranceExpanded ? 1.85 : 1, anchor: .center)
                LinearGradient(colors:[.black.opacity(0.12),.black.opacity(heldItem != nil ? 0.22 : 0.52)],startPoint:.top,endPoint:.bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
        }.accessibilityHidden(true)
    }
    private func setPreview(_ item: IPTVItem) {
        guard previewID != item.id else { return }
        if item.kind == .live {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
                previewID = item.id; previewItem = item
            }
        } else { previewID = item.id; previewItem = item }
    }
    private func clearPreview() { previewID=nil; previewItem=nil }
    private func selectCard(_ item: IPTVItem) {
        // A successful long press presents a sheet before release; the same
        // release must never also fire the short-press playback action.
        guard !modalOpen, entranceItem == nil else { return }
        pointerSelect(item.id); setPreview(item); openItem(item)
    }
    private func chooseFavorites(_ item: IPTVItem) {
        pointerSelect(item.id); itemOptions = item
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
            // Holding next/previous should not queue dozens of API requests.
            try? await Task.sleep(nanoseconds:160_000_000)
            guard !Task.isCancelled,caseToken==token else {return}
            let details=await library.details(for:item)
            guard !Task.isCancelled,caseToken==token,heldItem?.id==item.id else{return}
            heldDetails=details
        }
    }
    private func showCase(_ item: IPTVItem, episodes: Bool = false) {
        caseTransitionTask?.cancel()
        let token=UUID(); caseToken=token
        searchFocus=false
        heldSlice=visibleSlice.inspection(containing:item,fallback:library.catalogResults.all)
        heldDetails=item.details;caseYaw=episodes ? 180:0;casePitch=0;caseExpanded=false;caseStartEpisodes=episodes;caseRemoteEvent=nil;casePadSignal=nil;heldItem=item
        caseTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,caseToken==token else {return}
            withAnimation(reduceMotion ? nil : .spring(response:0.38,dampingFraction:0.86)) {caseExpanded=true}
        }
        requestCaseDetails(item,token:token)
    }
    private func moveCase(_ delta:Int) {
        guard let current=heldItem, let item=inspectionSlice.adjacent(to:current.id,offset:delta) else{return}
        let token=UUID();caseToken=token
        caseTransitionTask?.cancel();caseExpanded=true
        // Preserve orientation and use the catalogue index, even across pages.
        heldDetails=item.details;heldItem=item;setPreview(item);focusID=item.id;library.selectedItemID=item.id
        requestCaseDetails(item,token:token)
    }
    private func putCaseBack(reader:ScrollViewProxy?=nil) {
        guard let item=heldItem else{return}
        caseDetailTask?.cancel();caseTransitionTask?.cancel()
        let token=UUID();caseToken=token
        let destination=visibleSlice.item(id:item.id)?.id ?? visible.first?.id ?? "group-all"
        revealCatalogItem(destination)
        caseTransitionTask=Task { @MainActor in
            // Let the paginated grid lay out the return slot before shrinking.
            await Task.yield()
            guard !Task.isCancelled,caseToken==token else{return}
            reader?.scrollTo(destination,anchor:.center)
            if !reduceMotion {try? await Task.sleep(nanoseconds:40_000_000)}
            guard !Task.isCancelled,caseToken==token else{return}
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.28)) {caseExpanded=false}
            if !reduceMotion {try? await Task.sleep(nanoseconds:300_000_000)}
            guard !Task.isCancelled,caseToken==token else{return};focusID=destination;systemFocus=destination;heldItem=nil;heldSlice=nil
        }
    }
    private func dismissCaseImmediately() {caseDetailTask?.cancel();caseTransitionTask?.cancel();caseToken=UUID();heldItem=nil;heldSlice=nil;caseExpanded=false}
    private func playHeld() {
        guard let item=heldItem else{return}
        guard !item.isSeriesCollection else {return}
        dismissCaseImmediately(); series=nil;seasons=[];playItem(item)
    }
    private func playHeldEpisode(_ episode:IPTVItem, _ allSeasons:[IPTVSeason]) {
        guard let collection=heldItem,collection.isSeriesCollection else{return}
        series=collection;seasons=allSeasons;seasonNumber=episode.seasonNumber
        playItem(episode)
    }
    private func heldOverlay(_ item:IPTVItem,reader:ScrollViewProxy)->some View {
        GeometryReader { geo in
            let source=cardFrames.frame(for:item.id) ?? CGRect(x:geo.size.width*(clubProfile.isEditorial ? 0.65:0.5)-80,y:geo.size.height*0.62-120,width:160,height:240)
            let targetWidth=max(1,geo.size.width)
            let targetHeight=max(1,geo.size.height)
            let sourceScale=max(0.12,min(0.42,source.height/max(1,targetHeight*0.78)))
            ZStack {
                Color.black.opacity(caseExpanded ? 0.12:0).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture {putCaseBack(reader:reader)}
                CasePresentation(item:item,details:heldDetails,position:inspectionSlice.index(of:item.id) ?? 0,count:inspectionSlice.items.count,yaw:$caseYaw,pitch:$casePitch,previous:{moveCase(-1)},next:{moveCase(1)},close:{putCaseBack(reader:reader)},play:{playHeld()},playEpisode:{playHeldEpisode($0,$1)},favorite:{chooseFavorites(item)},isFavorite:library.isFavorite(item),startEpisodes:caseStartEpisodes,remoteEvent:caseRemoteEvent,padSignal:casePadSignal,previousItem:clubNeighbors(item).0,nextItem:clubNeighbors(item).1,previousFarItem:inspectionSlice.adjacent(to:item.id,offset:-2),nextFarItem:inspectionSlice.adjacent(to:item.id,offset:2),jumpBy:{moveCase($0)},selectedTheme:theme(for:item.kind),concept:clubProfile,suspended:modalOpen,onTrailerPresentation:{caseTrailerVisible=$0})
                    .frame(width:targetWidth,height:targetHeight)
                    .scaleEffect(caseExpanded ? 1 : sourceScale)
                    .opacity(caseExpanded ? 1 : 0.68)
                    .position(x:caseExpanded ? geo.size.width/2 : source.midX,y:caseExpanded ? geo.size.height/2 : source.midY)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private var previewHero: some View {
        HStack(alignment:.center,spacing:18) {
            VStack(alignment:.leading,spacing:9) {
                if let item=previewItem {
                    Label(item.kind.frenchTitle.uppercased(),systemImage:mediaIcon(item.kind)).font(.caption.weight(.semibold)).foregroundStyle(themeAccent)
                    Text(item.name).font(.system(.largeTitle,design:.default).weight(.heavy)).lineLimit(2)
                    Text(item.group).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing:9) {
                        navButton(item.kind == .live ? "Regarder" : "Prendre le boîtier",icon:item.kind == .live ? "play.fill":"film.stack",id:"hero-play",active:true) { openItem(item) }
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
    private var liveHeader: some View { header }
    private var header: some View {
        FluxGlassGroup {
            HStack(spacing: compactNavigation ? 8 : 18) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.title2.weight(.semibold)).foregroundStyle(themeAccent)
                    if !compactNavigation {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FLUX").font(.title3.weight(.heavy)).tracking(3)
                            if !compactChrome {
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.accessibilityElement(children: .combine).accessibilityLabel("Flux IPTV")
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(IPTVMediaKind.allCases, id: \.self) { kind in modeButton(kind) }
                }
                Spacer(minLength: 0)
                if compactNavigation {
                    navButton("Navigation", icon: "ellipsis", id: "navigation-more", iconOnly: true) { showingNavigationMenu = true }
                        .fluxNavigationGlass(radius: 20)
                } else {
                    HStack(spacing: 2) {
                        navButton("Sources", icon: "square.stack", id: "sources", iconOnly: true) { showingSources = true }
                        navButton("Recherche", icon: "magnifyingglass", id: "search", iconOnly: true) { search() }
                        #if !os(tvOS)
                        navButton("Télécommande", icon: "appletvremote.gen1", id: "remote", active: showRemote, iconOnly: true) { showRemote.toggle() }
                        #endif
                        if library.contentKind != .live || (browserHeight < 580 && !liveSidebarVisible) {
                            navButton("Listes", icon: "star", id: "lists", active: library.selectedPresetID != nil, iconOnly: true) { showingLists = true }
                        }
                        navButton("Réglages", icon: "gearshape", id: "settings", iconOnly: true) { showingEngines = true }
                    }.padding(4).fluxNavigationGlass(radius: 23)
                }
            }
        }
        .padding(.horizontal, compactNavigation ? 12 : 24).padding(.top, 10).padding(.bottom, 12)
    }
    private func modeButton(_ kind: IPTVMediaKind) -> some View {
        let selected = library.contentKind == kind && page == .catalogue
        let id = "tab-\(kind.rawValue)"
        let symbol: String = kind == .live ? "tv.fill" : kind == .movie ? "film.fill" : "square.stack.3d.up.fill"
        let title: String = kind == .live ? "TV" : kind == .movie ? "Films" : "Séries"
        let tint: Color = kind == .live ? .cyan : kind == .movie ? .orange : .purple
        return Button { pointerSelect(id); changeKind(kind) } label: {
            let layout = browserHeight < 580 ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 4))
            layout {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                    .font(.system(size: browserHeight < 580 ? 20 : compactNavigation ? 22 : 27, weight: .medium))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(selected ? tint : .white.opacity(0.92))
            .frame(minWidth: compactNavigation ? 48 : 72)
            .padding(.horizontal, 8).padding(.vertical, 9)
            .fluxNavigationGlass(selected: selected, tint: tint, radius: 21)
            .overlay {
                RoundedRectangle(cornerRadius: 21)
                    .strokeBorder(focusID == id ? .white.opacity(0.85) : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }.buttonStyle(.plain).fluxFocus($systemFocus, id: id).id(id)
            .accessibilityLabel(title).accessibilityValue(selected ? "Sélectionné" : "")
    }

    private func navButton(_ title: String, icon: String, id: String, active: Bool = false, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        Button { pointerSelect(id); action() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                #if os(iOS)
                if !iconOnly && sizeClass != .compact { Text(title).lineLimit(1) }
                #elseif os(macOS)
                if !iconOnly && (!compactChrome || id.hasPrefix("tab-") || id == "categories") { Text(title).lineLimit(1) }
                #else
                if !iconOnly { Text(title).lineLimit(1) }
                #endif
            }
            .font(.callout.weight(.semibold)).padding(.vertical, 10).padding(.horizontal, 12)
            .foregroundStyle(active ? .white : .primary)
            .background(active ? themeAccent.opacity(0.20) : Color.white.opacity(focusID == id ? 0.13 : 0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focusID == id ? Color.white.opacity(0.8) : .white.opacity(active ? 0.18 : 0.04), lineWidth: focusID == id ? 2 : 1).allowsHitTesting(false))
        }.buttonStyle(.plain).fluxFocus($systemFocus, id: id).id(id).accessibilityLabel(title).fluxHelp(title)
    }

    private var liveSidebarWidth: CGFloat {
        #if os(tvOS)
        340
        #else
        254
        #endif
    }
    private var liveGroups: [String] {
        let term = groupSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? groups : groups.filter { $0.localizedStandardContains(term) }
    }
    private var liveScopeID: String {
        if let group { return "live-category-\(group)" }
        if let preset = library.selectedPresetID { return "live-preset-\(preset)" }
        return "group-all"
    }
    private var liveSidebarIDs: [String] {
        ["group-all"] + library.currentPresets.map { "live-preset-\($0.id)" }
            + ["live-manage-lists"] + liveGroups.map { "live-category-\($0)" }
    }
    private func selectLiveGroup(_ name: String) {
        continueOnly = false
        library.selectedPresetID = nil
        group = name
        liveGroupSearchFocus = false
        clearPreview()
        resetCatalogWindow()
    }
    private func selectLivePreset(_ id: String) {
        continueOnly = false
        group = nil
        library.search = ""
        library.selectedPresetID = id
        clearPreview()
        resetCatalogWindow()
    }
    private func liveScopeButton(_ title: String, symbol: String, id: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
        Button { pointerSelect(id); action() } label: {
            LiveTVScopeLabel(title: title, symbol: symbol, count: count,
                             selected: liveScopeID == id, focused: focusID == id, accent: themeAccent)
        }.buttonStyle(.plain).fluxFocus($systemFocus, id: id).id(id)
            .accessibilityLabel(title)
            .accessibilityValue(liveScopeID == id ? "Sélectionné" : "")
    }
    private var liveSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("VOTRE TÉLÉVISION", systemImage: "tv")
                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les catégories", text: $groupSearch)
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
                        liveScopeButton("Gérer les listes", symbol: "slider.horizontal.3", id: "live-manage-lists") { showingLists = true }
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
            Button { pointerSelect("categories"); groupSearch = ""; showingGroups = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(group ?? "Catégories").font(.callout.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }.padding(.horizontal, 13).padding(.vertical, 10)
            }.buttonStyle(.plain).fluxFocus($systemFocus, id: "categories").id("categories")
                .fluxNavigationGlass(selected: group != nil, tint: themeAccent, radius: 17)
            Spacer(minLength: 0)
            navButton("Favoris", icon: "star.fill", id: "favorites-quick", active: library.selectedPresetID == FavoritePresets.defaultID(for: .live), iconOnly: true) {
                if library.selectedPresetID == FavoritePresets.defaultID(for: .live) { showAllCatalog() }
                else { selectLivePreset(FavoritePresets.defaultID(for: .live)) }
            }.fluxNavigationGlass(radius: 17)
            navButton("Listes", icon: "text.badge.star", id: "lists", active: library.selectedPresetID != nil, iconOnly: true) { showingLists = true }
                .fluxNavigationGlass(radius: 17)
        }
    }
    private var liveCatalogue: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: 18) {
                if liveSidebarVisible { liveSidebar }
                VStack(alignment: .leading, spacing: browserHeight < 700 ? 8 : 14) {
                    if browserHeight >= 700 {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group ?? library.selectedPreset?.name ?? "Télévision")
                                .font(.title2.weight(.bold)).lineLimit(1)
                            Text("\(library.selectedSource?.name ?? "Votre salon TV") · \(library.isFiltering ? "Recherche…" : "\(visible.count) chaînes")")
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
                            Button { groupSearch = ""; showingGroups = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                                .buttonStyle(.plain).fluxFocus($systemFocus, id: "categories").id("categories")
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
                Button("Diagnostic") { diagnosticSettings = true; showingEngines = true }.buttonStyle(.bordered)
            }.padding(12).fluxFrosted(radius: 16)
        }
        if let issue = library.credentialIssue, let source = library.selectedSource, source.kind != .m3uFile {
            VStack(alignment: .leading, spacing: 9) {
                Label("Reconnecter « \(source.name) »", systemImage: "person.crop.circle.badge.exclamationmark").font(.headline)
                Text(issue).font(.caption).foregroundStyle(.secondary)
                navButton("Reconnecter", icon: "arrow.clockwise", id: "reconnect-source") { editingSource = source }
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
                    navButton("Ajouter une source", icon: "plus", id: "add-source") { addingSource = true }
                } else if library.credentialIssue == nil {
                    navButton("Toutes les chaînes", icon: "square.grid.2x2", id: "live-reset") { showAllCatalog() }
                }
            }.frame(maxWidth: .infinity)
            Spacer()
        } else {
            if catalogPageCount > 1 && browserHeight >= 700 { livePagination }
            ScrollView {
                if catalogPageCount > 1 && browserHeight < 700 { livePagination }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns)), spacing: 12) {
                    ForEach(displayedItems) { item in liveChannel(item) }
                }.padding(3).padding(.bottom, 12)
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
                               favorite: library.isFavorite(item), highlighted: focusID == item.id || previewID == item.id,
                               accent: themeAccent)
        }.buttonStyle(.plain).fluxFocus($systemFocus, id: item.id).id(item.id)
            .accessibilityLabel(item.name).accessibilityHint("Sélectionner pour afficher l’aperçu. Regarder ouvre la chaîne. Appui long pour les favoris.")
            .zIndex(previewID == item.id ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84), value: focusID == item.id || previewID == item.id)
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
                }.buttonStyle(.plain).fluxFocus($systemFocus, id: "live-watch").id("live-watch")
                if !compactNavigation && browserHeight >= 580 {
                navButton("Favoris", icon: library.isFavorite(item) ? "star.fill" : "star", id: "live-favorite", iconOnly: true) { chooseFavorites(item) }
                }
                if livePreview.player != nil {
                    Button { livePreview.toggleMuted() } label: {
                        Image(systemName: livePreview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption).padding(compactNavigation ? 7 : 10)
                    }.buttonStyle(.plain).fluxFocus($systemFocus, id: "live-preview-mute").id("live-preview-mute")
                        .accessibilityLabel(livePreview.isMuted ? "Activer le son de l’aperçu" : "Couper le son de l’aperçu")
                }
            }
        }
    }

    @ViewBuilder private var catalogue: some View {
        if library.contentKind == .live { liveCatalogue }
        else { mediaCatalogue }
    }

    private var mediaCatalogue: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playback.recoveryMode {
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(.orange)
                    Text("Mode de récupération : lecture Apple uniquement après une session VLC non terminée.").font(.callout)
                    Spacer()
                    Button("Diagnostic") { diagnosticSettings = true; showingEngines = true }.buttonStyle(.bordered)
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
                    Text("\(library.selectedSource?.name ?? "Bibliothèque")  ·  \(library.isFiltering ? "Recherche…" : "\(visible.count) éléments")").font(.callout).foregroundStyle(.secondary)
                    if !compactChrome {
                        Text(library.contentKind == .movie ? "À l’affiche · Choisir un film" : library.contentKind == .series ? "Les coffrets · Saisons et épisodes" : "En direct · Choisir une chaîne")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                navButton("Actualiser", icon: "arrow.clockwise", id: "reload") { library.reloadSelected() }.disabled(library.selectedSourceID == nil || library.isLoading)
            }.padding(.horizontal, 30)
            HStack(spacing: 10) {
                navButton("Toutes", icon: "square.grid.2x2", id: "group-all", active: showingAllCatalog) { showAllCatalog() }
                navButton(group ?? "Catégories", icon: "line.3.horizontal.decrease", id: "categories", active: group != nil) { groupSearch = ""; showingGroups = true }
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
                    navButton("Reconnecter", icon: "arrow.clockwise", id: "reconnect-source") { editingSource = source }
                }.padding(16).fluxFrosted(radius: 16).padding(.horizontal, 30)
            }
            if library.isLoading && visible.isEmpty { Spacer(); ProgressView("Chargement du catalogue…").frame(maxWidth: .infinity); Spacer() }
            else if library.isFiltering && visible.isEmpty { Spacer(); ProgressView("Recherche…").frame(maxWidth: .infinity); Spacer() }
            else if visible.isEmpty {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "play.tv").font(.system(size: 54)).foregroundStyle(themeAccent)
                    Text(library.sources.isEmpty ? "Votre télévision vous attend" : library.credentialIssue != nil ? "Source à reconnecter" : "Aucun contenu").font(.title.weight(.semibold))
                    if library.sources.isEmpty { navButton("Ajouter une source", icon: "plus", id: "add-source") { addingSource = true } }
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Both visual concepts always begin in the complete, paginated grid.
                if catalogPageCount > 1 { catalogPagination }
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        if library.contentKind == .live {previewHero}
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:columns),spacing:8) {
                            ForEach(displayedItems) { item in card(item) }
                        }.padding(.horizontal,16).padding(.vertical,12)
                    }
                }
            }
        }
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

    private func card(_ item: IPTVItem) -> some View {
        let focused = focusID == item.id || previewID == item.id
        let favorite = library.isFavorite(item)
        return ZStack(alignment: .topTrailing) {
            Button { selectCard(item) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    CatalogSleeveArtwork(item: item)
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                    .background { if item.kind != .live { GeometryReader { proxy in Color.clear.preference(key:CaseFrameKey.self,value:[item.id:proxy.frame(in:.named("club-pane"))]) } } }
                    .opacity(heldItem?.id == item.id && caseExpanded ? 0.18 : 1)
                    .rotation3DEffect(.degrees(focused && !reduceMotion ? -4 : 0),axis:(x:0,y:1,z:0),perspective:0.6)
                    .scaleEffect(focused && !reduceMotion ? 1.025 : 1)
                    .offset(y: focused && !reduceMotion ? -3 : 0)
                    Text(item.name).font(.callout.weight(.semibold)).lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) {
                        Text(CasePackageFormat.resolve(year: item.details.year).title)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 3))
                        Text(item.group).font(.caption).lineLimit(1)
                    }.foregroundStyle(.secondary)
                    if let entry = playback.history.entries[item.id], entry.resumable {
                        ProgressView(value: entry.fraction).tint(themeAccent)
                    }
                }
                .padding(.horizontal,2).padding(.vertical,5)
                .background(.white.opacity(focused ? 0.13 : 0.025), in: RoundedRectangle(cornerRadius: 21))
                .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(focused ? Color.white.opacity(0.88) : .white.opacity(0.08), lineWidth: focused ? 2 : 1).allowsHitTesting(false))
            }.buttonStyle(.plain).fluxFocus($systemFocus, id: item.id).id(item.id)
                #if os(tvOS)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.65).onEnded { _ in chooseFavorites(item) })
                #else
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.65, maximumDistance: 14).onEnded { _ in chooseFavorites(item) })
                #endif
                #if os(macOS)
                .contextMenu {
                    Button("Favoris et listes…") { chooseFavorites(item) }
                    if playback.history.entries[item.id] != nil {
                        Button("Recommencer") {
                            playback.forgetProgress(item.id)
                            if item.isSeriesCollection { showCase(item, episodes: true) } else { playItem(item) }
                        }
                    }
                }
                #endif
                .accessibilityLabel(item.name)
                .accessibilityHint("Cliquer pour ouvrir. Maintenir pour choisir les favoris et les listes.")
            #if os(tvOS)
            if favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).padding(9).background(.black.opacity(0.75), in: Circle()).padding(13).allowsHitTesting(false) }
            #else
            HStack(spacing: 6) {
                Button { chooseFavorites(item) } label: { Image(systemName: favorite ? "star.fill" : "star").foregroundStyle(favorite ? .yellow : .white).frame(width: 29, height: 29).background(.black.opacity(0.72), in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Choisir les favoris et les listes")
                Button { chooseFavorites(item) } label: { Image(systemName: "ellipsis").foregroundStyle(.white).frame(width: 29, height: 29).background(.black.opacity(0.72), in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Listes et options")
            }.padding(13)
            #endif
        }
        .zIndex(focused ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: focused)
    }

    private var seriesDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                if let series {
                    ArtworkView(url: series.logoURL, fit: true) { Image(systemName: "film.stack").font(.largeTitle) }
                        .frame(width: 120, height: 165).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(series.name).font(.largeTitle.bold()).lineLimit(3)
                        Text("\(seasons.count) saisons · \(seasons.reduce(0) { $0 + $1.episodes.count }) épisodes").foregroundStyle(.secondary)
                        navButton("Favoris et listes", icon: "star", id: "series-favorite") { itemOptions = series }
                    }
                }
                Spacer(minLength: 0)
                navButton("Retour", icon: "chevron.backward", id: "series-back") { back() }
            }.padding(.horizontal, 30)
            if episodesLoading { Spacer(); ProgressView("Chargement des épisodes…").frame(maxWidth: .infinity); Spacer() }
            else if episodesFailed { Spacer(); navButton("Réessayer", icon: "arrow.clockwise", id: "series-retry") { if let series { loadSeries(series) } }.frame(maxWidth: .infinity); Spacer() }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(seasons) { season in
                            navButton(season.number == 0 ? "Spéciaux" : "Saison \(season.number)", icon: "play.rectangle.on.rectangle", id: "season-\(season.number)", active: seasonNumber == season.number) { seasonNumber = season.number }
                        }
                    }.padding(.horizontal, 30).padding(.vertical, 5)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(episodes) { episode in
                            Button { pointerSelect(episode.id); playItem(episode) } label: {
                                HStack(spacing: 15) {
                                    ZStack(alignment:.bottomLeading) {
                                        ArtworkView(url:episode.logoURL ?? episode.backdropURL ?? series?.logoURL,fit:false) { Image(systemName:"play.rectangle").font(.title2).frame(maxWidth:.infinity,maxHeight:.infinity) }.frame(width:148,height:84).clipped()
                                        Text("S\(String(format:"%02d",episode.seasonNumber ?? seasonNumber ?? 0)) E\(String(format:"%02d",episode.episodeNumber ?? 0))").font(.caption2.bold()).padding(5).background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:5)).padding(5)
                                    }.clipShape(RoundedRectangle(cornerRadius:10))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(episode.name).font(.headline).lineLimit(2)
                                        if let synopsis=episode.details.synopsis {Text(synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)}
                                        if let entry = playback.history.entries[episode.id], entry.resumable { ProgressView(value: entry.fraction).tint(themeAccent).frame(maxWidth: 180) }
                                    }
                                    Spacer(); Image(systemName: "chevron.right")
                                }.padding(18).background(.white.opacity(focusID == episode.id ? 0.20 : 0.06), in: RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focusID == episode.id ? .white : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).fluxFocus($systemFocus, id: episode.id).id(episode.id)
                                .contextMenu { Button("Recommencer") { playback.forgetProgress(episode.id); playItem(episode) } }
                        }
                    }.padding(.horizontal, 30).padding(.vertical, 8)
                }
            }
        }
    }

    /// Windowed and fullscreen playback share the same edge-to-edge surface.
    /// Chrome floats above the image; showing it never resizes the video.
    private var playerPage: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerSurface(playback: playback, immersive: cinema)
                    .contentShape(Rectangle())
                    #if !os(tvOS)
                    .focusable().focused($systemFocus, equals: "cinema-controls")
                    .id("cinema-controls").focusEffectDisabled()
                    .onTapGesture {
                        if playerControlsVisible { hidePlayerControls() }
                        else { revealPlayerControls() }
                    }
                    #endif
                #if os(tvOS)
                if !playerControlsVisible {
                    // An invisible native focus target lets Select restore the
                    // controls without keeping a permanent badge over the film.
                    Button { revealPlayerControls(focus: true) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .focused($systemFocus, equals: "cinema-controls")
                    .id("cinema-controls")
                    .accessibilityLabel("Afficher les commandes")
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
                if playerControlsVisible {
                    FluxGlassGroup {
                        VStack(spacing: 12) {
                            playerHeading
                            Spacer(minLength: 0)
                            playerDock
                        }
                        .padding(playerChromeInset)
                    }
                    .transition(.opacity)
                }
                if zapBanner && playback.playingItem?.kind == .live && playback.playbackError == nil {
                    VStack { Spacer(); liveBanner.padding(.bottom, playerControlsVisible ? 104 : 0) }
                        .allowsHitTesting(false).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            #if !os(tvOS)
            .onContinuousHover { phase in
                if case .active = phase { revealPlayerControls() }
            }
            #endif
            .onAppear { playerWidth = geometry.size.width; revealPlayerControls() }
            .onChange(of: geometry.size.width) { _, width in playerWidth = width }
        }
        .onChange(of: playback.isPlaying) { _, _ in revealPlayerControls() }
        .onChange(of: playback.opening) { _, _ in revealPlayerControls() }
        .onChange(of: playback.playbackError) { _, _ in revealPlayerControls() }
        .onChange(of: playback.position) { _, position in if !scrubbing { scrubPosition = position } }
        .onChange(of: playback.playingItem?.id) { _, _ in
            scrubbing = false; scrubPosition = 0; revealPlayerControls()
        }
        .onChange(of: systemFocus) { _, id in
            if page == .player, playerControlsVisible, id != nil, id != "cinema-controls" { revealPlayerControls() }
        }
        .onChange(of: modalOpen) { _, _ in if page == .player { revealPlayerControls() } }
        .onChange(of: voiceOverEnabled) { _, _ in if page == .player { revealPlayerControls() } }
        .onDisappear { playerControlsTask?.cancel(); playerControlsTask = nil; hoveredPlayerControls.removeAll() }
    }

    private var playerControlsVisible: Bool {
        cinemaControls || playback.opening || !playback.isPlaying || playback.playbackError != nil || voiceOverEnabled
    }
    private var narrowPlayer: Bool { playerWidth < 520 }
    private var playerChromeInset: CGFloat {
        #if os(tvOS)
        return 34
        #else
        return narrowPlayer ? 10 : 20
        #endif
    }
    private var playerButtonSize: CGFloat {
        #if os(tvOS)
        return 56
        #elseif os(iOS)
        return 44
        #else
        return 40
        #endif
    }
    private var playerTransportIDs: [String] {
        var ids: [String]
        if playback.playingItem?.kind == .live { ids = ["previous", "playpause", "next"] }
        else if narrowPlayer { ids = ["rewind", "playpause", "forward"] }
        else { ids = ["previous", "rewind", "playpause", "forward", "next"] }
        #if !os(tvOS)
        ids.append("mute")
        #endif
        ids.append("engine")
        return ids
    }
    private var playerHeading: some View {
        HStack(spacing: 8) {
            playerButton("player-back")
            Text(playback.playingItem?.name ?? "Lecteur")
                .font(.callout.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            #if !os(tvOS)
            playerButton("player-full")
            #endif
        }
        .padding(5).frame(maxWidth: 620)
        .fluxMediaGlass(radius: 28)
        #if !os(tvOS)
        .onHover { playerControlHover("heading", inside: $0) }
        #endif
    }
    private var playerDock: some View {
        VStack(spacing: 7) {
            if playback.seekable && !playback.opening && playback.playbackError == nil {
                HStack(spacing: 9) {
                    Text(playback.elapsed).font(.caption.monospacedDigit())
                    #if os(tvOS)
                    ProgressView(value: playback.position).tint(.white)
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
                    Text(playback.duration).font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 10)
            }
            HStack(spacing: narrowPlayer ? 2 : 6) {
                ForEach(playerTransportIDs, id: \.self) { id in playerButton(id) }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, narrowPlayer ? 8 : 12).padding(.vertical, 8)
        .frame(maxWidth: playerDockWidth)
        .fluxMediaGlass(radius: 28)
        #if !os(tvOS)
        .onHover { playerControlHover("dock", inside: $0) }
        #endif
    }
    private var playerDockWidth: CGFloat {
        #if os(tvOS)
        return 520
        #else
        return playback.seekable && !narrowPlayer ? 500 : CGFloat(playerTransportIDs.count) * (playerButtonSize + (narrowPlayer ? 2 : 6)) + 24
        #endif
    }
    private func playerButton(_ id: String) -> some View {
        let label = playerButtonLabel(id)
        return Button {
            pointerSelect(id)
            activateFocus()
            if page == .player { revealPlayerControls() }
        } label: {
            Image(systemName: label.icon)
                .font(.system(size: playerSymbolSize(id), weight: .semibold))
                .frame(width: playerButtonSize, height: playerButtonSize)
                .background(.white.opacity(id == "playpause" ? 0.14 : 0), in: Circle())
                .overlay(Circle().strokeBorder(playerButtonFocused(id) ? .white.opacity(0.9) : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .fluxFocus($systemFocus, id: id).id(id)
        .accessibilityLabel(label.title).fluxHelp(label.title)
        .disabled((id == "rewind" || id == "forward") && !playback.seekable)
    }
    private func playerButtonLabel(_ id: String) -> (title: String, icon: String) {
        switch id {
        case "player-back": return ("Retour", "chevron.backward")
        case "player-full": return cinema ? ("Quitter le plein écran", "arrow.down.right.and.arrow.up.left") : ("Plein écran", "arrow.up.left.and.arrow.down.right")
        case "previous": return ("Précédent", "backward.end.fill")
        case "next": return ("Suivant", "forward.end.fill")
        case "rewind": return ("Reculer de \(playback.settings.skipSeconds) secondes", "gobackward")
        case "forward": return ("Avancer de \(playback.settings.skipSeconds) secondes", "goforward")
        case "playpause": return playback.isPlaying ? ("Pause", "pause.fill") : ("Lecture", "play.fill")
        case "mute": return playback.muted ? ("Rétablir le son", "speaker.slash.fill") : ("Couper le son", "speaker.wave.2.fill")
        default: return ("Audio, sous-titres et réglages", "gearshape")
        }
    }
    private func playerSymbolSize(_ id: String) -> CGFloat {
        #if os(tvOS)
        return id == "playpause" ? 28 : 23
        #else
        return id == "playpause" ? 20 : 16
        #endif
    }
    private func playerButtonFocused(_ id: String) -> Bool {
        #if os(tvOS)
        return systemFocus == id
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
    private func revealPlayerControls(focus: Bool = false) {
        guard page == .player else { return }
        playerControlsTask?.cancel()
        if !cinemaControls {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { cinemaControls = true }
        }
        if focus {
            focusID = "playpause"
            Task { @MainActor in
                await Task.yield()
                guard page == .player, playerControlsVisible, !modalOpen else { return }
                systemFocus = "playpause"
            }
        }
        guard playback.isPlaying, !playback.opening, playback.playbackError == nil,
              hoveredPlayerControls.isEmpty, !scrubbing, !modalOpen, !voiceOverEnabled else { return }
        playerControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, page == .player, playback.isPlaying,
                  !playback.opening, playback.playbackError == nil,
                  hoveredPlayerControls.isEmpty, !scrubbing, !modalOpen, !voiceOverEnabled else { return }
            hidePlayerControls()
        }
    }
    private func hidePlayerControls() {
        guard playback.isPlaying, !playback.opening, playback.playbackError == nil,
              !scrubbing, !modalOpen, !voiceOverEnabled else { return }
        playerControlsTask?.cancel(); playerControlsTask = nil
        hoveredPlayerControls.removeAll()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { cinemaControls = false }
        focusID = "cinema-controls"
        Task { @MainActor in
            await Task.yield()
            guard page == .player, !playerControlsVisible else { return }
            systemFocus = "cinema-controls"
        }
    }

    private var groupsPanel: some View {
        panel("Catégories · \(library.contentKind.frenchTitle)") {
            TextField("Filtrer les catégories", text: $groupSearch).fluxFieldStyle()
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
                    Button { continueOnly=false; group=nil; library.selectedPresetID = preset.id; showingLists = false } label: { Label(preset.name + " (\(preset.itemIDs.count))", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
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
        }, saved: favoritesSaved).environmentObject(library)
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
        liveSidebarVisible = library.contentKind == .live && usable >= 920
        if library.contentKind == .live {
            let channelWidth = usable - 48 - (liveSidebarVisible ? liveSidebarWidth + 18 : 0)
            #if os(tvOS)
            let minimumTile: CGFloat = 410
            #else
            let minimumTile: CGFloat = 274
            #endif
            let estimated = (channelWidth + 12) / (minimumTile + 12)
            columns = estimated.isFinite ? Int(max(1, min(6, estimated))) : 3
        } else {
            let estimated = (usable - 32) / (cardWidth + 4)
            columns = estimated.isFinite ? Int(max(2, min(10, estimated))) : 5
        }
    }
    private func pointerSelect(_ id: String) {
        #if !os(tvOS)
        remoteNavigationActive = false
        #endif
        focusID = id
    }
    private func changeKind(_ kind: IPTVMediaKind) { home(); library.contentKind = kind; showAllCatalog(); focusID = "tab-\(kind.rawValue)" }
    private func focusFirstItem() {
        let target = visible.first?.id ?? "tab-\(library.contentKind.rawValue)"
        focusID = target
        Task { @MainActor in
            await Task.yield()
            guard page == .catalogue, !modalOpen, !searchFocus, !liveGroupSearchFocus else { return }
            systemFocus = target
        }
    }
    private func search() {
        guard !modalOpen else { return }
        cancelEntrance()
        if page != .catalogue { home() } else { dismissCaseImmediately() }
        liveGroupSearchFocus = false
        showingSearch = library.contentKind != .live; searchFocus = true
    }
    private func openItem(_ item: IPTVItem) {
        library.selectedItemID = item.id
        setPreview(item)
        if item.kind != .live {showCase(item)} else {series=nil;seasons=[];playItem(item)}
    }
    private func loadSeries(_ item: IPTVItem) {
        let token = UUID(); seriesRequest = token; series = item; page = .series; seasons = []; episodesFailed = false; episodesLoading = true; focusID = "series-back"
        Task { @MainActor in
            do {
                let result = try await library.seasons(for: item)
                guard seriesRequest == token, page == .series else { return }
                seasons = result; seasonNumber = result.first?.number; episodesLoading = false
                focusID = result.first?.episodes.first?.id ?? "series-back"
            } catch { if seriesRequest == token { episodesLoading = false; episodesFailed = true; focusID = "series-retry" } }
        }
    }
    private func playItem(_ item: IPTVItem) {
        livePreview.stop()
        guard !item.isSeriesCollection else { showCase(item, episodes: true); return }
        cancelEntrance()
        dismissCaseImmediately()
        do {
            let urls = try library.playbackURLs(for: item)
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
    private func startPlayback(_ item: IPTVItem, urls: [URL], entering: Bool) {
        page = .player; focusID = "playpause"
        playback.play(item, urls: urls)
        if entering && !cinema { toggleCinema() }
        revealPlayerControls()
        if item.kind == .live { showZapBanner() }
    }
    private func cancelEntrance() {
        entranceTask?.cancel(); entranceTask = nil
        entranceItem = nil; entranceExpanded = false
    }
    private func showZapBanner() {
        let token=UUID();zapToken=token;withAnimation(.easeInOut(duration:0.18)){zapBanner=true}
        Task { @MainActor in
            try? await Task.sleep(nanoseconds:3_600_000_000)
            guard zapToken==token else{return};withAnimation(.easeOut(duration:0.22)){zapBanner=false}
        }
    }
    private var liveBanner:some View {
        HStack(spacing:14) {
            if let item=playback.playingItem {
                ArtworkView(url:item.logoURL,fit:true){Image(systemName:"tv").font(.title2)}.frame(width:44,height:36)
                VStack(alignment:.leading,spacing:4){Text(item.name).font(.headline).lineLimit(1);Text("DIRECT  ·  \(item.group)").font(.caption).foregroundStyle(.secondary).lineLimit(1)}
                Spacer(); if let number=visibleSlice.index(of:item.id) {Text(String(format:"%03d",number+1)).font(.title.monospacedDigit().weight(.bold))}
            }
        }.padding(12).frame(maxWidth: 440).fluxMediaGlass(radius:23).padding(20).allowsHitTesting(false)
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
    private func home() { playerControlsTask?.cancel(); cancelEntrance(); dismissCaseImmediately(); if cinema { toggleCinema(restoringPreviousWindow: true) }; playback.stop(); page = .catalogue; series = nil; seasons = []; seriesRequest = UUID(); focusID = "tab-\(library.contentKind.rawValue)" }
    private func back() {
        if entranceItem != nil { cancelEntrance(); return }
        if heldItem != nil {putCaseBack();return}
        switch page {
        case .player: stopPlayback()
        case .series:
            let id = series?.id; home(); focusID = id ?? "tab-series"
        case .catalogue:
            if showingSearch { showingSearch = false; searchFocus = false; library.search = "" }
            else if continueOnly || group != nil || library.selectedPresetID != nil || !library.search.isEmpty { showAllCatalog() }
            else { focusID = "tab-\(library.contentKind.rawValue)" }
        }
    }
    private func stopPlayback() {
        playerControlsTask?.cancel(); playerControlsTask = nil
        if cinema { toggleCinema(restoringPreviousWindow: true) }
        let lastItem = playback.playingItem
        playback.stop(); page = .catalogue
        if let collection = series { showCase(collection, episodes: true) }
        else if let item = lastItem, item.kind == .movie { showCase(item) }
        else { focusID = lastItem?.id ?? "tab-\(library.contentKind.rawValue)" }
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
    private var focusRows: [[String]] {
        var rows: [[String]] = []
        if page != .player && !cinema {
            if compactNavigation {
                rows.append(["navigation-more"])
            } else {
            #if os(tvOS)
                rows.append(["sources", "search"] + (library.contentKind != .live || (browserHeight < 580 && !liveSidebarVisible) ? ["lists"] : []) + ["settings"])
            #else
                rows.append(["sources", "search", "remote"] + (library.contentKind != .live || (browserHeight < 580 && !liveSidebarVisible) ? ["lists"] : []) + ["settings"])
            #endif
            }
            rows.append(["tab-live", "tab-movie", "tab-series"])
        }
        switch page {
        case .catalogue:
            if library.selectedSourceID != nil && !library.isLoading { rows.append(["reload"]) }
            if library.credentialIssue != nil { rows.append(["reconnect-source"]) }
            if library.contentKind == .live {
                if !liveSidebarVisible { rows.append(browserHeight < 580 ? ["categories"] : ["categories", "favorites-quick", "lists"]) }
                if visible.isEmpty && !library.sources.isEmpty && library.credentialIssue == nil { rows.append(["live-reset"]) }
            } else {
                rows.append(["group-all", "categories"] + (library.contentKind == .movie ? ["continue-only"] : []) + (library.sources.isEmpty ? [] : ["favorites-quick"]))
            }
            if library.sources.isEmpty { rows.append(["add-source"]) }
            else if !visible.isEmpty {
                if library.contentKind == .live, let item = previewItem, visibleSlice.index(of: item.id) != nil {
                    rows.append(["live-watch"] + (!compactNavigation && browserHeight >= 580 ? ["live-favorite"] : []) + (livePreview.player == nil ? [] : ["live-preview-mute"]))
                }
                if catalogPageCount>1 {rows.append((catalogPage>0 ? ["page-prev"] : []) + (catalogPage+1<catalogPageCount ? ["page-next"] : []))}
            }
        case .series:
            rows += [["series-favorite", "series-back"]]
            if episodesFailed { rows.append(["series-retry"]) }
            else { rows.append(seasons.map { "season-\($0.number)" }); rows += episodes.map { [$0.id] } }
        case .player:
            if playerControlsVisible {
                #if os(tvOS)
                rows.append(["player-back"])
                #else
                rows.append(["player-back", "player-full"])
                #endif
                rows.append(playerTransportIDs)
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
            caseRemoteEvent=CaseRemoteEvent(action:action)
            return
        }
        if page == .player && !playerControlsVisible {
            switch action {
            case .left: playback.skip(seconds: -Double(playback.settings.skipSeconds))
            case .right: playback.skip(seconds: Double(playback.settings.skipSeconds))
            case .up: if playback.playingItem?.kind == .live { adjacent(1) }
            case .down: if playback.playingItem?.kind == .live { adjacent(-1) }
            case .select: break
            default: break
            }
            if [.left, .right, .up, .down, .select].contains(action) {
                revealPlayerControls(focus: true)
                return
            }
        }
        switch action {
        case .up, .down, .left, .right:
            if page == .catalogue, library.contentKind == .live {
                focusID = LiveTVNavigation.move(from: focusID, action: action, channels: visibleSlice,
                                               columns: columns, sidebarIDs: liveSidebarVisible ? liveSidebarIDs : [],
                                               preferredSidebarID: liveScopeID, preferredChannelID: previewID, prefix: focusRows)
            }
            else if page == .catalogue { focusID=visibleSlice.move(from:focusID,action:action,prefix:focusRows,columns:columns) }
            else { focusID = RemoteNavigation.move(from: focusID, action: action, rows: focusRows) }
        case .select: activateFocus()
        case .back: back()
        case .home: home()
        case .search: search()
        case .playPause: if page == .player { playback.togglePause() } else if let item = visibleSlice.item(id:focusID) { openItem(item) }
        case .rewind: playback.skip(seconds: -Double(playback.settings.skipSeconds))
        case .forward: playback.skip(seconds: Double(playback.settings.skipSeconds))
        case .previous: adjacent(-1)
        case .next: adjacent(1)
        case .fullscreen: toggleCinema()
        case .volumeUp: playback.adjustVolume(0.1)
        case .volumeDown: playback.adjustVolume(-0.1)
        case .mute: playback.toggleMute()
        case .options:
            if page == .player { showingEngines = true }
            else if let item = visibleSlice.item(id:focusID) ?? (page == .series ? series : nil) { itemOptions = item }
            else { showingLists = true }
        }
        if page == .player { revealPlayerControls() }
    }
    private func activateFocus() {
        guard let id = focusID else { focusID = focusRows.first?.first; return }
        if page == .catalogue, let item = visibleSlice.item(id:id) { openItem(item); return }
        if page == .series, let item = episodes.first(where: { $0.id == id }) { playItem(item); return }
        if id.hasPrefix("tab-"), let kind = IPTVMediaKind(rawValue: String(id.dropFirst(4))) { changeKind(kind); return }
        if id.hasPrefix("season-"), let n = Int(id.dropFirst(7)) { seasonNumber = n; return }
        if id.hasPrefix("live-category-") { selectLiveGroup(String(id.dropFirst("live-category-".count))); return }
        if id.hasPrefix("live-preset-") { selectLivePreset(String(id.dropFirst("live-preset-".count))); return }
        if id == "group-all" { showAllCatalog(); return }
        if id.hasPrefix("group-") { group = String(id.dropFirst(6)); return }
        switch id {
        case "live-watch": if let item = previewItem { playItem(item) }
        case "live-favorite": if let item = previewItem { chooseFavorites(item) }
        case "live-preview-mute": livePreview.toggleMuted()
        case "navigation-more": showingNavigationMenu = true
        case "live-manage-lists": showingLists = true
        case "live-reset": showAllCatalog()
        case "page-prev": changeCatalogPage(-1)
        case "page-next": changeCatalogPage(1)
        case "hero-play": if let item=previewItem { openItem(item) }
        case "hero-favorite": if let item=previewItem { chooseFavorites(item) }
        case "sources": showingSources = true
        case "search": search()
        case "remote": showRemote.toggle()
        case "lists": showingLists = true
        case "categories": groupSearch = ""; showingGroups = true
        case "continue-only": toggleResumeFilter()
        case "favorites-quick":
            if library.contentKind == .live {
                if library.selectedPresetID == FavoritePresets.defaultID(for: .live) { showAllCatalog() }
                else { selectLivePreset(FavoritePresets.defaultID(for: .live)) }
            } else { toggleQuickFavorites() }
        case "volume-down": playback.adjustVolume(-0.1)
        case "volume-up": playback.adjustVolume(0.1)
        case "mute": playback.toggleMute()
        case "reconnect-source": editingSource = library.selectedSource
        case "reload": library.reloadSelected()
        case "add-source": addingSource = true
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
        case "engine", "settings": showingEngines = true
        default: if cinema { playback.togglePause() }
        }
    }
}

private extension View {
    @ViewBuilder func fluxFocus(_ binding: FocusState<String?>.Binding, id: String) -> some View {
        #if os(tvOS)
        self.focused(binding, equals: id)
        #else
        self.focusable().focused(binding, equals: id)
        #endif
    }
}

#if os(tvOS)
private extension View {
    @ViewBuilder func fluxExit(_ enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled { self.onExitCommand(perform: action) } else { self }
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
