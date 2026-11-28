import Foundation
import Combine

@MainActor
final class IPTVLibrary: ObservableObject {
    @Published private(set) var sources: [IPTVSource] = []
    @Published private(set) var catalogResults = CatalogResults(kind: .live)
    @Published private(set) var isFiltering = false
    private var catalogIndex = CatalogIndex()
    private var filterTask: Task<Void, Never>?
    private var filterToken = UUID()
    private var detailCache: [String: IPTVDetails] = [:]
    private var detailOrder: [String] = []
    @Published private(set) var selectedSourceID: UUID?
    @Published var selectedItemID: String?
    @Published var search = "" {
        didSet {
            guard oldValue != search, !restoringBrowsing else { return }
            // What is typed is a search, on its own screen: the section
            // where it was typed keeps what it showed.
            if !searchScreen, Self.searchHasAScreen, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enterSearchScreen()
            }
            browsingFilterChanged(); updateResults(debounce: true); updateSearchCounts()
        }
    }
    /// The screen of the search, with its own column and its own pictures:
    /// "recherche n'a pas son menu dédié", and the series showed the
    /// pictures of the search (David, 27/11). Its query runs over the whole
    /// catalogue of a kind, whatever the filters of that section, which
    /// keeps them; no section keeps a query.
    @Published private(set) var searchScreen = false
    /// How many titles of each kind the query finds, on the screen of the search.
    @Published private(set) var searchCounts: [IPTVMediaKind: Int] = [:]
    /// The last queries sent, the latest first.
    @Published private(set) var recentSearches: [String] = []
    static let recentSearchesKey = "fluxiptv.search.recent.v1"
    #if os(macOS) || os(tvOS)
    static let searchHasAScreen = true
    #else
    static let searchHasAScreen = false
    #endif
    private var countTask: Task<Void, Never>?
    @Published var contentKind: IPTVMediaKind = .live {
        didSet { if oldValue != contentKind && !restoringBrowsing { changeBrowsingKind() } }
    }
    @Published var group: String? {
        didSet { if oldValue != group && !restoringBrowsing { browsingFilterChanged() } }
    }
    @Published var groupSearch = "" {
        didSet { if oldValue != groupSearch { rememberBrowsingChange() } }
    }
    @Published var continueOnly = false {
        didSet {
            guard oldValue != continueOnly && !restoringBrowsing else { return }
            if continueOnly && selectedPresetID != nil {
                restoringBrowsing = true
                selectedPresetIDs.removeValue(forKey: contentKind)
                restoringBrowsing = false
                updateResults(clear: true)
            }
            browsingFilterChanged()
        }
    }
    @Published var countryCode: String? {
        didSet {
            guard oldValue != countryCode && !restoringBrowsing else { return }
            restoringBrowsing = true
            if let group, let countryCode {
                // A category that holds nothing in the chosen country or language is left.
                let kept = contentKind == .live
                    ? (LiveCountry.detectCode(in: group) ?? LiveCountry.unknownCode) == countryCode
                    : catalogIndex.category(group, of: contentKind, has: countryCode)
                if !kept { self.group = nil }
            }
            restoringBrowsing = false
            browsingFilterChanged()
            updateResults(clear: true)
        }
    }
    @Published var catalogPage = 0 {
        didSet { if oldValue != catalogPage { rememberBrowsingChange() } }
    }
    /// The title the remote rests on, kept for the next visit. Not
    /// published: no view draws it, and it changes with every press of the
    /// remote, which rebuilt every view of the library.
    var browseItemID: String? {
        didSet { if oldValue != browseItemID { rememberBrowsingChange() } }
    }
    @Published private(set) var browsingRevision = UUID()
    @Published private(set) var presets = FavoritePresets() {
        didSet { if selectedPresetID != nil && !restoringBrowsing { updateResults() } }
    }
    @Published private(set) var selectedPresetIDs: [IPTVMediaKind: String] = [:] {
        didSet {
            if oldValue[contentKind] != selectedPresetIDs[contentKind] && !restoringBrowsing {
                if selectedPresetIDs[contentKind] != nil {
                    restoringBrowsing = true
                    continueOnly = false
                    restoringBrowsing = false
                }
                browsingFilterChanged(); updateResults(clear: true)
            }
        }
    }
    /// What the user keeps in the dock: shortcuts in named sections, lists
    /// shown as folders, and what was watched last. Identifiers and names
    /// only, as for the favourites: never an address.
    @Published private(set) var dockShelf = DockShelf()
    /// The section or the folder of the dock that the favourites show in
    /// the place of a list: what the bar keeps is found among them too.
    @Published var favoriteDockSectionID: String? {
        didSet { if oldValue != favoriteDockSectionID && !restoringBrowsing { updateResults() } }
    }
    @Published private(set) var isLoading = false
    @Published var alertMessage: String?
    @Published private(set) var credentialIssue: String?

    private let sourcesKey = "fluxiptv.savedSources.v1"
    private let favoritesKey = "fluxiptv.favorites.v1"
    private let presetsKey = "fluxiptv.favoritePresets.v2"
    private var browsingPreferences = CatalogBrowsingPreferences()
    private var browsingDefaults: UserDefaults? = .standard
    private var browsingContext: (sourceID: UUID, kind: IPTVMediaKind)?
    private var loadedCatalogSourceID: UUID?
    private var restoringBrowsing = false
    private var browsingSaveTask: Task<Void, Never>?
    private var browsingDirty = false
    private var seriesCache: [String: [IPTVSeason]] = [:]
    /// The series whose seasons are kept, oldest first. Each holds all its
    /// episodes: an evening through series kept every one of them.
    private var seriesOrder: [String] = []
    private var loadID = UUID()
    // Keep successful reads in RAM only. Never prompt while changing media.
    private var sessionCredentials = SessionCredentialCache<IPTVSecret>()

    init() {
        browsingPreferences = CatalogBrowsingPreferences.decoded(
            UserDefaults.standard.data(forKey: CatalogBrowsingPreferences.storageKey))
        if let data = UserDefaults.standard.data(forKey: sourcesKey),
           let saved = try? JSONDecoder().decode([IPTVSource].self, from: data) {
            sources = saved
        }
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode(FavoritePresets.self, from: data) {
            presets = saved
        } else {
            // Retain v1 data as a fallback; v2 is written immediately on first launch.
            presets = FavoritePresets(legacyIDs: Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []))
            persistPresets()
        }
        if let data = UserDefaults.standard.data(forKey: DockShelf.storageKey),
           let saved = try? JSONDecoder().decode(DockShelf.self, from: data) {
            dockShelf = saved
        }
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
        browsingPreferences.retainSources(Set(sources.map(\.id)))
        if let first = sources.first(where: { $0.id == browsingPreferences.lastSourceID }) ?? sources.first {
            Task { await selectSource(first.id) }
        }
    }

    #if FLUX_CATALOG_UI_TESTING
    /// Empty first-run state without reading or modifying real saved sources.
    init(emptyCatalogFixture kind: IPTVMediaKind) {
        browsingDefaults = nil
        contentKind = kind
    }

    /// Settled failed-source screen after its alert was dismissed. No account
    /// is read and no refresh is started; the production view must still let
    /// native remote focus and its visible highlight follow each other.
    init(unavailableCatalogFixture source: IPTVSource, kind: IPTVMediaKind) {
        precondition(source.kind == .xtream)
        browsingDefaults = nil
        sources = [source]
        selectedSourceID = source.id
        contentKind = kind
        credentialIssue = "La source de démonstration doit être reconnectée."
    }

    /// Isolated local catalogue for the native UI capture harness. This path
    /// neither loads saved accounts nor starts a source refresh.
    init(catalogFixture source: IPTVSource, items: [IPTVItem], kind: IPTVMediaKind,
         browsingDefaults: UserDefaults? = nil) {
        precondition(source.kind == .m3uFile)
        precondition(items.allSatisfy {
            $0.sourceID == source.id && $0.directURL == nil && $0.xtreamStreamID == nil
                && ($0.logoURL == nil || $0.logoURL?.isFileURL == true)
                && $0.backdropURL == nil && $0.details.trailerURL == nil
        })
        self.browsingDefaults = browsingDefaults
        browsingPreferences = CatalogBrowsingPreferences.decoded(
            browsingDefaults?.data(forKey: CatalogBrowsingPreferences.storageKey))
        if let data = browsingDefaults?.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode(FavoritePresets.self, from: data) {
            presets = saved
        }
        if let data = browsingDefaults?.data(forKey: DockShelf.storageKey),
           let saved = try? JSONDecoder().decode(DockShelf.self, from: data) {
            dockShelf = saved
        }
        recentSearches = browsingDefaults?.stringArray(forKey: Self.recentSearchesKey) ?? []
        sources = [source]
        selectedSourceID = source.id
        catalogIndex = CatalogIndex(items)
        loadedCatalogSourceID = source.id
        contentKind = kind
        restoreBrowsingContext()
        updateResults(clear: true)
    }

    /// Reload the same isolated source through the production installation and
    /// preference reconciliation path, without network requests or accounts.
    func reloadCatalogFixture(_ items: [IPTVItem]) {
        precondition(items.allSatisfy { $0.sourceID == selectedSourceID && $0.directURL == nil && $0.xtreamStreamID == nil })
        installCatalog(CatalogIndex(items))
    }

    /// The seasons of a series of the fixture, as its source would give
    /// them: asked for, they come from here and nothing is downloaded.
    func cacheFixtureSeasons(_ seasons: [IPTVSeason], for series: IPTVItem) {
        precondition(series.sourceID == selectedSourceID && series.isSeriesCollection
                     && seasons.allSatisfy { $0.episodes.allSatisfy { $0.directURL == nil && $0.xtreamStreamID == nil } })
        keepSeasons(seasons, for: series.id)
    }
    #endif

    var selectedItem: IPTVItem? {
        catalogIndex.item(id: selectedItemID)
    }

    var selectedSource: IPTVSource? {
        sources.first(where: { $0.id == selectedSourceID })
    }

    var currentPresets: [FavoritePreset] { presets.lists(for: contentKind) }
    var liveCountries: [LiveCountry] { catalogIndex.liveCountries }
    /// Languages of the films or of the series; empty for the channels.
    var mediaLanguages: [MediaLanguage] { catalogIndex.languages(for: contentKind) }
    var browsingCatalogReady: Bool { selectedSourceID != nil && loadedCatalogSourceID == selectedSourceID }

    var selectedPresetID: String? {
        get { selectedPresetIDs[contentKind] }
        set {
            if let newValue, presets.list(id: newValue)?.kind == contentKind {
                selectedPresetIDs[contentKind] = newValue
            } else {
                selectedPresetIDs.removeValue(forKey: contentKind)
            }
        }
    }

    var activeFavoriteID: String { selectedPresetID ?? FavoritePresets.defaultID(for: contentKind) }
    var activeFavoriteName: String { presets.list(id: activeFavoriteID)?.name ?? "Favoris" }
    var selectedPreset: FavoritePreset? { selectedPresetID.flatMap { presets.list(id: $0) } }

    func catalogItem(id: String?) -> IPTVItem? { catalogIndex.item(id: id) }
    /// Size of one kind in the loaded source, whatever the current filters.
    func catalogCount(_ kind: IPTVMediaKind) -> Int { catalogIndex.unfiltered(kind).all.items.count }

    private func currentBrowsingState(kind: IPTVMediaKind) -> CatalogBrowsingState {
        // A query belongs to the screen of the search: no section keeps one.
        // Where the search has no screen of its own (iPhone, iPad), the
        // field is a part of the section and keeps its query, as before.
        CatalogBrowsingState(countryCode: countryCode, group: group, search: Self.searchHasAScreen ? "" : search,
                             groupSearch: groupSearch, presetID: selectedPresetIDs[kind],
                             continueOnly: continueOnly, catalogPage: catalogPage, browseItemID: browseItemID)
    }

    /// Memory is updated immediately; writing UserDefaults is coalesced while
    /// the remote moves across channels. Lifecycle/source changes flush it.
    private func storeActiveBrowsingState() {
        // The screen of the search leaves the section as it found it.
        guard !restoringBrowsing, !searchScreen, let context = browsingContext,
              context.sourceID == selectedSourceID, loadedCatalogSourceID == context.sourceID else { return }
        browsingPreferences.remember(currentBrowsingState(kind: context.kind),
                                     sourceID: context.sourceID, kind: context.kind)
        browsingDirty = true
    }

    private func rememberBrowsingChange() {
        guard !restoringBrowsing, browsingContext?.kind == contentKind else { return }
        storeActiveBrowsingState()
        scheduleBrowsingSave()
    }

    private func browsingFilterChanged() {
        guard !restoringBrowsing else { return }
        restoringBrowsing = true
        catalogPage = 0
        browseItemID = nil
        restoringBrowsing = false
        rememberBrowsingChange()
    }

    private func scheduleBrowsingSave() {
        guard browsingDefaults != nil, browsingDirty else { return }
        browsingSaveTask?.cancel()
        browsingSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.writeBrowsingPreferences()
        }
    }

    private func writeBrowsingPreferences() {
        browsingSaveTask?.cancel()
        browsingSaveTask = nil
        guard browsingDirty, let defaults = browsingDefaults,
              let data = try? JSONEncoder().encode(browsingPreferences) else { return }
        defaults.set(data, forKey: CatalogBrowsingPreferences.storageKey)
        browsingDirty = false
    }

    func flushBrowsingPreferences() {
        storeActiveBrowsingState()
        writeBrowsingPreferences()
    }

    private func changeBrowsingKind() {
        // The fields still belong to browsingContext.kind even though this
        // property observer already sees the new contentKind.
        storeActiveBrowsingState()
        if let sourceID = selectedSourceID {
            browsingPreferences.select(sourceID: sourceID, kind: contentKind)
            browsingDirty = true
        }
        restoreBrowsingContext()
        updateResults(clear: true)
        flushBrowsingPreferences()
    }

    private func applyBrowsingState(_ state: CatalogBrowsingState) {
        countryCode = state.countryCode
        group = state.group
        // A section shows what it holds; the screen of the search keeps its
        // query from one kind to the next, from its first page.
        if !searchScreen { search = Self.searchHasAScreen ? "" : state.search }
        groupSearch = state.groupSearch
        continueOnly = state.continueOnly
        catalogPage = searchScreen ? 0 : state.catalogPage
        browseItemID = searchScreen ? nil : state.browseItemID
        if let id = state.presetID { selectedPresetIDs[contentKind] = id }
        else { selectedPresetIDs.removeValue(forKey: contentKind) }
    }

    private func restoreBrowsingContext() {
        restoringBrowsing = true
        if let sourceID = selectedSourceID, loadedCatalogSourceID == sourceID {
            var stored = browsingPreferences.state(for: sourceID, kind: contentKind)
            // A query that 0.9.6 kept with a section is not shown again: the
            // title it remembers is judged on what the section will show.
            if Self.searchHasAScreen { stored.search = "" }
            let saved = stored.validated(kind: contentKind, index: catalogIndex, presets: presets)
            applyBrowsingState(saved)
            browsingContext = (sourceID, contentKind)
        } else {
            // Loading/error states must never validate against an empty index
            // or save these temporary defaults over the stored filters.
            browsingContext = nil
            applyBrowsingState(CatalogBrowsingState())
        }
        restoringBrowsing = false
        browsingRevision = UUID()
        rememberBrowsingChange()
    }

    private func prepareBrowsingSource(_ id: UUID) {
        flushBrowsingPreferences()
        let kind = browsingPreferences.preferredKind(for: id) ?? .live
        restoringBrowsing = true
        browsingContext = nil
        selectedSourceID = id
        contentKind = kind
        selectedPresetIDs = [:]
        applyBrowsingState(CatalogBrowsingState())
        clearCatalog()
        restoringBrowsing = false
        browsingPreferences.select(sourceID: id, kind: kind)
        browsingDirty = true
        browsingRevision = UUID()
        scheduleBrowsingSave()
    }

    private func reconcileVisibleBrowsingSelection() {
        guard !restoringBrowsing, !isFiltering,
              browsingContext?.sourceID == selectedSourceID,
              browsingContext?.kind == contentKind,
              loadedCatalogSourceID == selectedSourceID,
              let id = browseItemID,
              // The search shows the whole kind, whatever the group of the section.
              catalogResults.slice(group: searchScreen ? nil : group).item(id: id) == nil else { return }
        restoringBrowsing = true
        browseItemID = nil
        catalogPage = 0
        restoringBrowsing = false
        rememberBrowsingChange()
    }

    private func updateResults(debounce: Bool = false, clear: Bool = false) {
        filterTask?.cancel(); filterToken = UUID()
        let token = filterToken
        // What the favourites show: a list, or what a section of the dock
        // keeps. The search looks through the whole catalogue of the kind.
        let kind = contentKind, term = search
        let membership = searchScreen ? nil : dockMembership ?? selectedPreset?.itemIDs
        let country = searchScreen ? nil : countryCode
        if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && membership == nil && country == nil {
            catalogResults = catalogIndex.unfiltered(kind); isFiltering = false
            reconcileVisibleBrowsingSelection()
            return
        }
        if clear || catalogResults.kind != kind { catalogResults = CatalogResults(kind:kind) }
        isFiltering = true
        let index = catalogIndex
        filterTask = Task { @MainActor [weak self] in
            if debounce { try? await Task.sleep(nanoseconds:150_000_000) }
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority:.userInitiated) { try index.matching(kind:kind,search:term,membership:membership,countryCode:country) }
            let result = await withTaskCancellationHandler(operation: { try? await worker.value }, onCancel: { worker.cancel() })
            guard let self, !Task.isCancelled, self.filterToken == token else { return }
            if let result { self.catalogResults = result }
            self.isFiltering = false
            self.reconcileVisibleBrowsingSelection()
        }
    }

    private func installCatalog(_ index: CatalogIndex) {
        storeActiveBrowsingState()
        catalogIndex = index
        loadedCatalogSourceID = selectedSourceID
        detailCache.removeAll(); detailOrder.removeAll()
        restoringBrowsing = true
        reconcileCatalog(index.items)
        restoringBrowsing = false
        restoreBrowsingContext()
        updateResults(clear: true)
        updateSearchCounts()
    }

    /// Opens the screen of the search over the section in front, which
    /// keeps what it shows for when it comes back.
    func enterSearchScreen() {
        guard !searchScreen else { return }
        storeActiveBrowsingState()
        searchScreen = true
        restoringBrowsing = true
        catalogPage = 0
        browseItemID = nil
        restoringBrowsing = false
        updateResults(clear: true)
        updateSearchCounts()
    }

    /// Leaves the screen of the search: its query goes, and the section
    /// shows again what it showed, under its own pictures.
    func leaveSearchScreen() {
        guard searchScreen else { return }
        countTask?.cancel()
        searchScreen = false
        searchCounts = [:]
        restoringBrowsing = true
        search = ""
        restoringBrowsing = false
        restoreBrowsingContext()
        updateResults(clear: true)
    }

    /// Keeps the query among the last ones: when it is sent, and when a
    /// title it found is opened. Six at most, the latest first.
    func rememberSearch() {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchScreen, !term.isEmpty else { return }
        var kept = recentSearches.filter { $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        kept.insert(term, at: 0)
        recentSearches = Array(kept.prefix(6))
        browsingDefaults?.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    /// Counts what the query finds among the channels, the films and the
    /// series, once the typing pauses.
    private func updateSearchCounts() {
        countTask?.cancel()
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchScreen, !term.isEmpty else {
            if !searchCounts.isEmpty { searchCounts = [:] }
            return
        }
        let index = catalogIndex
        countTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            // Counted without gathering what is found: the three kinds were
            // filtered in full, their categories built, to be counted.
            let worker = Task.detached(priority: .utility) { () -> [IPTVMediaKind: Int]? in
                var counts: [IPTVMediaKind: Int] = [:]
                for kind in IPTVMediaKind.allCases {
                    guard let found = try? index.count(kind: kind, search: term) else { return nil }
                    counts[kind] = found
                }
                return counts
            }
            let counts = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard let self, let counts, !Task.isCancelled, self.searchScreen,
                  self.search.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            self.searchCounts = counts
        }
    }

    private func clearCatalog() {
        loadedCatalogSourceID = nil
        catalogIndex = CatalogIndex()
        detailCache.removeAll(); detailOrder.removeAll()
        updateResults(clear: true)
    }

    private func unlockSource(_ id: UUID) throws -> IPTVSecret {
        guard let source = sources.first(where: { $0.id == id }) else { throw IPTVError.missingCredentials }
        return try sessionCredentials.load(for: id) {
            try IPTVSecretStore.read(source)
        }
    }

    private func unlockedSecret(for id: UUID) throws -> IPTVSecret {
        // Playback and episode navigation are never allowed to raise a Keychain prompt.
        guard let secret = sessionCredentials.cached(for: id) else {
            throw IPTVError.missingCredentials
        }
        return secret
    }

    func xtreamSecret(for source: IPTVSource, interactive: Bool = false) throws -> IPTVSecret {
        if !interactive { return try unlockSource(source.id) }
        let secret = try IPTVSecretStore.read(source, interactive: true)
        sessionCredentials.store(secret, for: source.id)
        return secret
    }

    func addXtream(name: String, server: String, username: String, password: String,
                   liveExtension: String, replacing existing: IPTVSource? = nil, allowKeychainPrompt: Bool = false, storage: CredentialStorageMode = .keychain) async throws {
        let login = try XtreamLogin(server: server, username: username, password: password)
        let record = IPTVSource(id: existing?.id ?? UUID(),
                                name: displayName(name, fallback: login.server.host ?? "Xtream"), kind: .xtream, credentialStorage: storage)
        let secret = IPTVSecret(endpoint: login.server.absoluteString, username: login.username,
                                password: login.password, liveExtension: liveExtension == "ts" ? "ts" : "m3u8")
        // Validate first. Failed or cancelled attempts leave the original source and Keychain intact.
        let loaded = try await Self.indexedLoad(source: record, secret: secret)
        try Task.checkCancellation()
        if let existing, !sources.contains(where: { $0.id == existing.id && $0.kind == .xtream }) {
            throw IPTVError.missingCredentials
        }
        try IPTVSecretStore.save(secret, source: record, interactive: allowKeychainPrompt)
        sessionCredentials.store(secret, for: record.id)
        if let index = sources.firstIndex(where: { $0.id == record.id }) {
            sources[index] = record
        } else { sources.append(record) }
        persistSources()
        // Remove a stale local copy when explicitly switching back to Keychain.
        #if os(macOS)
        if existing?.credentialStorage == .localPrivate, storage == .keychain {
            try? IPTVSecretStore.local().remove(for: record.id)
        }
        #endif
        activate(record, loaded: loaded)
    }

    func addM3UURL(name: String, address: String, replacing existing: IPTVSource? = nil, allowKeychainPrompt: Bool = false, storage: CredentialStorageMode = .keychain) async throws {
        let url = try IPTVURL.validated(address)
        let record = IPTVSource(id: existing?.id ?? UUID(), name: displayName(name, fallback: url.host ?? "Playlist M3U"), kind: .m3uURL, credentialStorage: storage)
        let secret = IPTVSecret(endpoint: url.absoluteString, username: "", password: "", liveExtension: "")
        let loaded = try await Self.indexedLoad(source: record, secret: secret)
        try Task.checkCancellation()
        try IPTVSecretStore.save(secret, source: record, interactive: allowKeychainPrompt)
        sessionCredentials.store(secret, for: record.id)
        if let i = sources.firstIndex(where: { $0.id == record.id }) { sources[i] = record } else { sources.append(record) }
        persistSources()
        // Remove a stale local copy when explicitly switching back to Keychain.
        #if os(macOS)
        if existing?.credentialStorage == .localPrivate, storage == .keychain {
            try? IPTVSecretStore.local().remove(for: record.id)
        }
        #endif
        activate(record, loaded: loaded)
    }

    func addM3UFile(name: String, fileURL: URL) async throws {
        let record = IPTVSource(id: UUID(), name: displayName(name, fallback: fileURL.deletingPathExtension().lastPathComponent),
                                kind: .m3uFile)
        try LocalPlaylistFiles.importFile(fileURL, id: record.id)
        do {
            let loaded = try await Self.indexedLoad(source: record, secret: nil)
            try Task.checkCancellation()
            sources.append(record)
            persistSources()
            activate(record, loaded: loaded)
        } catch {
            LocalPlaylistFiles.remove(for: record.id)
            throw error
        }
    }

    private func activate(_ source: IPTVSource, loaded: CatalogIndex) {
        credentialIssue = nil
        loadID = UUID()
        if selectedSourceID != source.id { prepareBrowsingSource(source.id) }
        selectedItemID = nil
        forgetSeasons()
        isLoading = false
        installCatalog(loaded)
        flushBrowsingPreferences()
    }

    private func reconcileCatalog(_ loaded: [IPTVItem]) {
        if presets.reconcileMigratedM3U(loaded) { persistPresets() }
        if !loaded.contains(where: { $0.kind == contentKind }), selectedPresetID == nil,
           let availableKind = IPTVMediaKind.allCases.first(where: { kind in loaded.contains { $0.kind == kind } }) {
            contentKind = availableKind
        }
    }

    func selectSource(_ id: UUID) async {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        loadID = UUID()
        let token = loadID
        let refreshing = selectedSourceID == id
        if !refreshing {
            prepareBrowsingSource(id)
            selectedItemID = nil
            forgetSeasons()
        } else { flushBrowsingPreferences() }
        isLoading = true
        credentialIssue = nil

        do {
            // At most one successful credential read per source per process session.
            let secret = source.kind == .m3uFile ? nil : try unlockSource(id)
            let loaded = try await Self.indexedLoad(source: source, secret: secret)
            guard loadID == token else { return }
            forgetSeasons()
            installCatalog(loaded)
        } catch {
            guard loadID == token else { return }
            // Authentication/storage failures are recoverable inline, not blocking launch.
            if error is KeychainError || error is PrivateCredentialStoreError || error is DecodingError {
                credentialIssue = Self.safeSourceError(error)
            } else if let e = error as? IPTVError {
                switch e {
                case .missingCredentials, .authenticationFailed: credentialIssue = Self.safeSourceError(e)
                default: alertMessage = Self.safeSourceError(e)
                }
            } else { alertMessage = Self.safeSourceError(error) }
        }
        if loadID == token { isLoading = false }
    }

    nonisolated private static func indexedLoad(source: IPTVSource, secret: IPTVSecret?) async throws -> CatalogIndex {
        let worker = Task.detached(priority: .userInitiated) {
            let items = try await Self.load(source: source, secret: secret)
            try Task.checkCancellation()
            return CatalogIndex(items)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    nonisolated private static func load(source: IPTVSource, secret: IPTVSecret?) async throws -> [IPTVItem] {
        switch source.kind {
        case .xtream:
            guard let secret, let endpoint = try? IPTVURL.validated(secret.endpoint) else {
                throw IPTVError.missingCredentials
            }
            return try await XtreamClient().fetchCatalog(
                server: endpoint, username: secret.username, password: secret.password, sourceID: source.id)
        case .m3uURL:
            guard let secret, let url = try? IPTVURL.validated(secret.endpoint) else {
                throw IPTVError.missingCredentials
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: config)
            // A session is kept, with its connections, until it is
            // invalidated: one was left behind at every reload of a list.
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            // The bytes received are let go once read as text, before the
            // titles are built: some 26 MB for a list of 92 000 entries.
            let text: String
            do {
                let (bytes, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw IPTVError.serverError(http.statusCode)
                }
                text = playlistText(bytes)
            }
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        case .m3uFile:
            let text = playlistText(try Data(contentsOf: LocalPlaylistFiles.destination(for: source.id)))
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        }
    }

    nonisolated private static func playlistText(_ bytes: Data) -> String {
        String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    func playbackURLs(for item: IPTVItem) throws -> [URL] {
        if item.xtreamStreamID == nil, let direct = item.directURL { return [direct] }
        let secret = try unlockedSecret(for: item.sourceID)
        let server = try IPTVURL.validated(secret.endpoint)
        let urls = PlaybackPlan.urls(server: server, username: secret.username, password: secret.password,
                                     item: item, liveExtension: secret.liveExtension)
        guard !urls.isEmpty else { throw IPTVError.invalidURL }
        return urls
    }

    func details(for item: IPTVItem) async -> IPTVDetails {
        if let cached = detailCache[item.id] { return cached }
        guard let source = sources.first(where: { $0.id == item.sourceID }), source.kind == .xtream,
              let secret = try? unlockedSecret(for: item.sourceID), let server = try? IPTVURL.validated(secret.endpoint) else { return item.details }
        let token = loadID
        guard let result = try? await XtreamClient().fetchDetails(server: server, username: secret.username, password: secret.password, item: item),
              !Task.isCancelled, token == loadID else { return item.details }
        if detailCache[item.id] == nil { detailOrder.append(item.id) }
        detailCache[item.id] = result
        if detailOrder.count > 96 { detailCache.removeValue(forKey: detailOrder.removeFirst()) }
        return result
    }

    func seasons(for series: IPTVItem) async throws -> [IPTVSeason] {
        guard series.isSeriesCollection else { throw IPTVError.invalidResponse }
        if let cached = seriesCache[series.id] { return cached }
        let secret = try unlockedSecret(for: series.sourceID)
        let server = try IPTVURL.validated(secret.endpoint)
        let token = loadID
        let seasons = try await XtreamClient().fetchSeasons(server: server, username: secret.username,
                                                           password: secret.password, series: series)
        try Task.checkCancellation()
        guard token == loadID else { throw CancellationError() }
        keepSeasons(seasons, for: series.id)
        return seasons
    }

    /// The seasons of the last 24 series opened stay at hand.
    private func keepSeasons(_ seasons: [IPTVSeason], for id: String) {
        if seriesCache[id] == nil { seriesOrder.append(id) }
        seriesCache[id] = seasons
        if seriesOrder.count > 24 { seriesCache.removeValue(forKey: seriesOrder.removeFirst()) }
    }

    private func forgetSeasons() {
        seriesCache.removeAll()
        seriesOrder.removeAll()
    }

    func isFavorite(_ item: IPTVItem, in id: String? = nil) -> Bool {
        presets.list(id: id ?? activeFavoriteID)?.itemIDs.contains(item.id) == true
    }

    func toggleFavorite(_ item: IPTVItem, in id: String? = nil) {
        if presets.toggle(item, in: id ?? activeFavoriteID) { persistPresets() }
    }

    func assignFavorites(_ item: IPTVItem, to selectedIDs: Set<String>, creating name: String? = nil) -> Bool {
        guard presets.assign(item, to: selectedIDs, creating: name) else { return false }
        persistPresets()
        return true
    }

    func createPreset(name: String, kind: IPTVMediaKind, initialItem: IPTVItem? = nil) -> Bool {
        guard let id = presets.create(name: name, kind: kind) else { return false }
        if let initialItem { _ = presets.toggle(initialItem, in: id) }
        selectedPresetIDs[kind] = id
        persistPresets()
        return true
    }

    func renamePreset(_ preset: FavoritePreset, name: String) -> Bool {
        guard presets.rename(id: preset.id, name: name) else { return false }
        persistPresets()
        return true
    }

    func deletePreset(_ preset: FavoritePreset) {
        guard presets.delete(id: preset.id) else { return }
        if selectedPresetIDs[preset.kind] == preset.id { selectedPresetIDs.removeValue(forKey: preset.kind) }
        persistPresets()
        // Its folder leaves the dock with it.
        if dockShelf.retainStacks(Set(presets.lists.map(\.id))) { persistDock() }
    }

    // MARK: Dock

    /// The sections of the dock that keep this shortcut, and a new one to
    /// create for it: the whole choice, or nothing.
    func assignDock(_ shortcut: DockShortcut, to sectionIDs: Set<String>, creating name: String? = nil,
                    folded: Bool = false, in parentID: String? = nil) -> Bool {
        guard dockShelf.assign(shortcut, to: sectionIDs, creating: name, folded: folded, in: parentID) else { return false }
        persistDock()
        return true
    }

    /// An empty section of the bar, or with `folded` a folder: in the bar,
    /// or in another folder.
    @discardableResult func createDockSection(name: String, folded: Bool, in parentID: String? = nil) -> String? {
        guard let id = dockShelf.createSection(name: name, folded: folded, in: parentID) else { return nil }
        persistDock()
        return id
    }

    /// One folder of the bar, or its shortcuts in the bar again.
    @discardableResult func setDockFolded(_ id: String, _ folded: Bool) -> Bool {
        guard dockShelf.setFolded(id, folded) else { return false }
        persistDock()
        return true
    }

    /// A folder into another, or back into the bar.
    @discardableResult func moveDockSection(_ id: String, into parentID: String?) -> Bool {
        guard dockShelf.moveSection(id, into: parentID) else { return false }
        persistDock()
        return true
    }

    /// The icon of a folder; nil shows the pictures of what it holds.
    func setDockSymbol(_ id: String, _ symbol: String?) {
        if dockShelf.setSymbol(id, symbol) { persistDock() }
    }

    func removeDockShortcut(_ id: String) {
        guard dockShelf.contains(id) else { return }
        dockShelf.remove(shortcutID: id)
        persistDock()
    }

    func moveDockShortcut(_ id: String, in sectionID: String, to index: Int) {
        if dockShelf.move(shortcutID: id, in: sectionID, to: index) { persistDock() }
    }

    func renameDockSection(_ id: String, name: String) -> Bool {
        guard dockShelf.renameSection(id: id, name: name) else { return false }
        persistDock()
        return true
    }

    func deleteDockSection(_ id: String) {
        if dockShelf.deleteSection(id: id) { persistDock() }
    }

    /// Shows or hides a list of favourites as a folder of the dock.
    func setDockStack(_ listID: String, shown: Bool) {
        guard dockShelf.showsStack(listID) != shown, !shown || presets.list(id: listID) != nil else { return }
        dockShelf.setStack(listID, shown: shown)
        persistDock()
    }

    /// What has just been opened comes first among the recents.
    func visitDock(_ shortcut: DockShortcut) {
        guard dockShelf.recents.first != shortcut else { return }
        dockShelf.visit(shortcut)
        persistDock()
    }

    func forgetDockRecent(_ id: String) {
        guard dockShelf.recents.contains(where: { $0.id == id }) else { return }
        dockShelf.forget(recentID: id)
        persistDock()
    }

    private func persistDock() {
        if let bytes = try? JSONEncoder().encode(dockShelf) { browsingDefaults?.set(bytes, forKey: DockShelf.storageKey) }
        // The favourites may be showing what a section keeps.
        if let shown = favoriteDockSectionID {
            if dockShelf.section(id: shown) == nil { favoriteDockSectionID = nil } else { updateResults() }
        }
    }

    /// Titles of the catalogue that the section of the dock shown among
    /// the favourites keeps, for the kind on screen: a season and an
    /// episode stand for their series.
    private var dockMembership: Set<String>? {
        guard let id = favoriteDockSectionID, let section = dockShelf.section(id: id) else { return nil }
        return Set(section.shortcuts.filter { $0.sourceID == selectedSourceID && $0.kind == contentKind }.map(\.itemID))
    }

    private func persistPresets() {
        if let bytes = try? JSONEncoder().encode(presets) { browsingDefaults?.set(bytes, forKey: presetsKey) }
    }

    func removeSource(_ source: IPTVSource) {
        storeActiveBrowsingState()
        browsingPreferences.removeSource(source.id)
        browsingDirty = true
        if selectedSourceID == source.id { browsingContext = nil }
        if selectedSourceID == source.id { loadID = UUID() } // invalidate this source’s in-flight refresh
        sessionCredentials.remove(for: source.id)
        IPTVSecretStore.delete(source)
        if source.kind == .m3uFile { LocalPlaylistFiles.remove(for: source.id) }
        sources.removeAll(where: { $0.id == source.id })
        presets.removeSource(source.id)
        persistPresets()
        if dockShelf.removeSource(source.id) { persistDock() }
        persistSources()
        if selectedSourceID == source.id {
            forgetSeasons()
            restoringBrowsing = true
            selectedSourceID = nil
            selectedPresetIDs = [:]
            applyBrowsingState(CatalogBrowsingState())
            credentialIssue = nil
            selectedItemID = nil
            clearCatalog()
            restoringBrowsing = false
            browsingRevision = UUID()
            isLoading = false
            if let first = sources.first { Task { await selectSource(first.id) } }
        }
        writeBrowsingPreferences()
    }

    func reloadSelected() {
        if let id = selectedSourceID { Task { await selectSource(id) } }
    }

    static func safeSourceError(_ error: Error) -> String {
        if let error = error as? IPTVError { return error.localizedDescription }
        if let error = error as? KeychainError { return error.localizedDescription }
        if let error = error as? PrivateCredentialStoreError { return error.localizedDescription }
        if let network = error as? URLError {
            switch network.code {
            case .timedOut: return "Le serveur ne répond pas. Vérifiez l’adresse, le port et votre connexion."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Serveur inaccessible. Vérifiez l’adresse et le port."
            case .notConnectedToInternet, .networkConnectionLost: return "Connexion réseau indisponible. Réessayez."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                return "Connexion HTTPS impossible. Vérifiez le certificat et le protocole indiqué par le fournisseur."
            default: return "Erreur réseau. Vérifiez le serveur et réessayez."
            }
        }
        return "Impossible de charger la source. Vérifiez les informations saisies et réessayez."
    }

    private func persistSources() {
        if let bytes = try? JSONEncoder().encode(sources) {
            browsingDefaults?.set(bytes, forKey: sourcesKey)
        }
    }

    private func displayName(_ suggested: String, fallback: String) -> String {
        let trimmed = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
