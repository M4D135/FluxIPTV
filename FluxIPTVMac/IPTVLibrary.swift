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
        didSet { if oldValue != search && !restoringBrowsing { browsingFilterChanged(); updateResults(debounce: true) } }
    }
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
    @Published var browseItemID: String? {
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
        CatalogBrowsingState(countryCode: countryCode, group: group, search: search,
                             groupSearch: groupSearch, presetID: selectedPresetIDs[kind],
                             continueOnly: continueOnly, catalogPage: catalogPage, browseItemID: browseItemID)
    }

    /// Memory is updated immediately; writing UserDefaults is coalesced while
    /// the remote moves across channels. Lifecycle/source changes flush it.
    private func storeActiveBrowsingState() {
        guard !restoringBrowsing, let context = browsingContext,
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
        search = state.search
        groupSearch = state.groupSearch
        continueOnly = state.continueOnly
        catalogPage = state.catalogPage
        browseItemID = state.browseItemID
        if let id = state.presetID { selectedPresetIDs[contentKind] = id }
        else { selectedPresetIDs.removeValue(forKey: contentKind) }
    }

    private func restoreBrowsingContext() {
        restoringBrowsing = true
        if let sourceID = selectedSourceID, loadedCatalogSourceID == sourceID {
            let saved = browsingPreferences.state(for: sourceID, kind: contentKind)
                .validated(kind: contentKind, index: catalogIndex, presets: presets)
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
              catalogResults.slice(group: group).item(id: id) == nil else { return }
        restoringBrowsing = true
        browseItemID = nil
        catalogPage = 0
        restoringBrowsing = false
        rememberBrowsingChange()
    }

    private func updateResults(debounce: Bool = false, clear: Bool = false) {
        filterTask?.cancel(); filterToken = UUID()
        let token = filterToken
        let kind = contentKind, term = search, membership = selectedPreset?.itemIDs
        let country = countryCode
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
        seriesCache.removeAll()
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
            seriesCache.removeAll()
        } else { flushBrowsingPreferences() }
        isLoading = true
        credentialIssue = nil

        do {
            // At most one successful credential read per source per process session.
            let secret = source.kind == .m3uFile ? nil : try unlockSource(id)
            let loaded = try await Self.indexedLoad(source: source, secret: secret)
            guard loadID == token else { return }
            seriesCache.removeAll()
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
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw IPTVError.serverError(http.statusCode)
            }
            let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? ""
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        case .m3uFile:
            let bytes = try Data(contentsOf: LocalPlaylistFiles.destination(for: source.id))
            let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? ""
            let items = M3UParser().parse(text, sourceID: source.id)
            guard !items.isEmpty else { throw IPTVError.invalidPlaylist }
            return items
        }
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
        seriesCache[series.id] = seasons
        return seasons
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
    func assignDock(_ shortcut: DockShortcut, to sectionIDs: Set<String>, creating name: String? = nil) -> Bool {
        guard dockShelf.assign(shortcut, to: sectionIDs, creating: name) else { return false }
        persistDock()
        return true
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
            seriesCache.removeAll()
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
