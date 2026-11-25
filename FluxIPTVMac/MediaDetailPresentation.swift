import SwiftUI

struct MediaDetailRemoteEvent: Equatable {
    let action: RemoteAction
    let token = UUID()
}

/// Links the sleeve picked in the catalogue to the case of its fiche, so that
/// the case leaves the shelf and comes forward instead of simply appearing.
struct MediaDetailHero {
    let namespace: Namespace.ID
    let id: String
}

/// A readable screen for one selected title and its physical sleeve. The
/// artwork is static: this screen creates no video session or catalogue grid.
struct MediaDetailPresentation: View {
    let item: IPTVItem
    let details: IPTVDetails
    let close: () -> Void
    let play: () -> Void
    let playEpisode: (IPTVItem, [IPTVSeason]) -> Void
    let favorite: () -> Void
    let isFavorite: Bool
    let remoteEvent: MediaDetailRemoteEvent?
    var initialSeasons: [IPTVSeason] = []
    var initialSeasonNumber: Int? = nil
    var initialEpisodeID: String? = nil
    var suspended = false
    /// False while the fiche is still closing or has not opened yet. The desk
    /// keeps the catalogue behind it and animates between the two states.
    var expanded = true
    var hero: MediaDetailHero? = nil
    /// Another season chosen from the fiche itself.
    var seasonChanged: (Int) -> Void = { _ in }

    @EnvironmentObject private var library: IPTVLibrary
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seasons: [IPTVSeason] = []
    @State private var selectedEpisodeID: String?
    @State private var seasonLoading = false
    @State private var seasonFailed = false
    @State private var seasonReload = UUID()
    @State private var expandedDescription = false
    @State private var descriptionPage = 0
    @State private var focusedID = "play"
    @FocusState private var nativeFocus: String?
    @State private var startingPlayback = false
    @State private var handoffTask: Task<Void, Never>?
    @State private var handoffToken = UUID()
    /// True when the last episode selection came from the keyboard or remote;
    /// only then does the list scroll to it. A pointer never moves the list.
    @State private var keyboardSelection = false

    init(item: IPTVItem, details: IPTVDetails, close: @escaping () -> Void,
         play: @escaping () -> Void, playEpisode: @escaping (IPTVItem, [IPTVSeason]) -> Void,
         favorite: @escaping () -> Void, isFavorite: Bool, remoteEvent: MediaDetailRemoteEvent?,
         initialSeasons: [IPTVSeason] = [], initialSeasonNumber: Int? = nil,
         initialEpisodeID: String? = nil, suspended: Bool = false,
         expanded: Bool = true, hero: MediaDetailHero? = nil, seasonChanged: @escaping (Int) -> Void = { _ in }) {
        self.expanded = expanded
        self.hero = hero
        self.seasonChanged = seasonChanged
        self.item = item
        self.details = details
        self.close = close
        self.play = play
        self.playEpisode = playEpisode
        self.favorite = favorite
        self.isFavorite = isFavorite
        self.remoteEvent = remoteEvent
        self.initialSeasons = initialSeasons
        self.initialSeasonNumber = initialSeasonNumber
        self.initialEpisodeID = initialEpisodeID
        self.suspended = suspended
        // The season shelf already has these episodes. Install them before
        // the first focus evaluation, so the restored episode's Play button
        // is enabled immediately instead of falling back to "Les saisons".
        let availableSeasons = item.isSeriesCollection ? initialSeasons : []
        let initialSeason = availableSeasons.first(where: { $0.number == initialSeasonNumber }) ?? availableSeasons.first
        let initialEpisode = initialSeason?.episodes.first(where: { $0.id == initialEpisodeID }) ?? initialSeason?.episodes.first
        _seasons = State(initialValue: availableSeasons)
        _selectedEpisodeID = State(initialValue: initialEpisode?.id)
    }

    private var selectedSeason: IPTVSeason? {
        seasons.first(where: { $0.number == initialSeasonNumber }) ?? seasons.first
    }
    private var episodes: [IPTVItem] { selectedSeason?.episodes ?? [] }
    private var selectedEpisode: IPTVItem? {
        episodes.first(where: { $0.id == selectedEpisodeID }) ?? episodes.first
    }
    private var synopsis: String {
        let value = details.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Aucune description fournie pour ce titre." : value
    }
    private var metadata: String {
        [details.year, details.duration, details.genre].compactMap { value in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "0" else { return nil }
            return text
        }.joined(separator: "  ·  ")
    }
    private var playbackTitle: String {
        guard item.isSeriesCollection else { return item.kind == .live ? "Regarder la chaîne" : "Voir le film" }
        guard let episode = selectedEpisode else { return "Choisir un épisode" }
        let season = episode.seasonNumber ?? selectedSeason?.number ?? 1
        let number = episode.episodeNumber ?? ((episodes.firstIndex(where: { $0.id == episode.id }) ?? 0) + 1)
        return "Voir S\(season) · E\(number)"
    }
    private var selectionKey: String {
        "\(item.id)|\(initialSeasonNumber.map(String.init) ?? "")|\(initialEpisodeID ?? "")|\(seasonReload)"
    }
    private var focusRows: [[String]] {
        #if os(macOS)
        if !expandedDescription {
            let actions = (startingPlayback || (item.isSeriesCollection && selectedEpisode == nil) ? [] : ["play"]) + ["favorite", "description"]
            return [["back"], actions]
        }
        #endif
        var playbackActions: [String] = []
        if !startingPlayback && (!item.isSeriesCollection || selectedEpisode != nil) { playbackActions.append("play") }
        var rows = [["back", "description", "favorite"], playbackActions]
        if seasonFailed { rows.append(["retry-episodes"]) }
        if !episodes.isEmpty { rows.append(episodes.map { "episode:\($0.id)" }) }
        return rows
    }

    var body: some View {
        ZStack {
            if expandedDescription {
                descriptionScreen
                    .transition(.opacity)
            } else {
                GeometryReader { geometry in
                    let metrics = MediaDetailMetrics(size: geometry.size, series: item.isSeriesCollection, safeAreaInsets: geometry.safeAreaInsets)
                    #if os(macOS)
                    if geometry.size.width >= 900 && geometry.size.height >= 500 { deskLayout(geometry.size) }
                    else {
                        ZStack { backdrop; narrowLayout(metrics) }.opacity(expanded ? 1 : 0)
                    }
                    #else
                    ZStack {
                        backdrop
                        if metrics.wide { wideLayout(metrics) }
                        else { narrowLayout(metrics) }
                    }
                    #endif
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if !os(macOS)
        .background(Color(red: 0.025, green: 0.035, blue: 0.055))
        #endif
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expandedDescription)
        .task(id: selectionKey) { await loadEpisodes() }
        .onChange(of: initialSeasons) { _, value in
            guard !value.isEmpty else { return }
            seasons = value
            if !episodes.contains(where: { $0.id == selectedEpisodeID }) { selectedEpisodeID = episodes.first?.id }
        }
        .onChange(of: remoteEvent) { _, event in
            guard let event else { return }
            handle(event.action)
        }
        .onChange(of: nativeFocus) { _, value in
            guard let value else { return }
            focusedID = value
            if value.hasPrefix("episode:") { selectedEpisodeID = String(value.dropFirst("episode:".count)) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelHandoff() } }
        .onChange(of: suspended) { _, value in if value { cancelHandoff() } }
        .onAppear { setFocus(item.isSeriesCollection && selectedEpisode == nil ? "back" : "play") }
        .onDisappear { cancelHandoff() }
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.055)
                if let url = item.backdropURL {
                    ArtworkView(url: url, fit: false) { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().opacity(0.16)
                }
                LinearGradient(colors: [.black.opacity(0.82), .black.opacity(0.25), .black.opacity(0.68)], startPoint: .leading, endPoint: .trailing)
                RadialGradient(colors: [.cyan.opacity(0.07), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.7)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func wideLayout(_ metrics: MediaDetailMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            topBar(compact: false)
                .frame(height: metrics.headerHeight)
            HStack(alignment: .top, spacing: metrics.gap * 1.4) {
                titleInformation(metrics)
                    .frame(width: metrics.informationWidth, height: metrics.mainHeight, alignment: .topLeading)
                caseSection(metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.frame(height: metrics.mainHeight)
            if item.isSeriesCollection { episodeSection(metrics).frame(height: metrics.episodeHeight) }
            controlsHint.frame(height: metrics.hintHeight)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
    }

    private func narrowLayout(_ metrics: MediaDetailMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar(compact: true)
                titleInformation(metrics)
                caseSection(metrics)
                if item.isSeriesCollection { episodeSection(metrics).frame(height: metrics.episodeHeight) }
                controlsHint
            }.padding(.horizontal, metrics.horizontalPadding).padding(.vertical, metrics.verticalPadding)
        }
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 18) {
            control("back", title: item.isSeriesCollection ? "Les saisons" : "Retour", icon: "chevron.left", action: dismiss)
            if !compact {
                Text(item.isSeriesCollection ? "SÉRIE" : item.kind == .live ? "EN DIRECT" : "CINÉMA")
                    #if os(tvOS)
                    .font(.system(size: 22, weight: .bold))
                    #else
                    .font(.system(size: 13, weight: .bold))
                    #endif
                    .tracking(2.2).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 4)
            if !compact { descriptionControl }
            control("favorite", title: isFavorite ? "Dans les favoris" : "Favoris", icon: isFavorite ? "star.fill" : "star", iconOnly: compact, action: favorite)
        }
    }

    private func titleInformation(_ metrics: MediaDetailMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.informationGap) {
            Text(item.name)
                .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                .tracking(-0.6).lineLimit(metrics.titleLines).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !metadata.isEmpty {
                Text(metadata).font(.system(size: metrics.metadataSize, weight: .medium))
                    .foregroundStyle(.cyan.opacity(0.95)).lineLimit(metrics.metadataLines)
            }
            Text(synopsis)
                .font(.system(size: metrics.bodySize)).lineSpacing(6)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(metrics.synopsisLines)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !metrics.wide { descriptionControl }
            if metrics.wide { Spacer(minLength: 0) }
            playbackControl
        }
    }

    private var descriptionControl: some View {
        control("description", title: "Description complète", icon: "text.alignleft") {
            descriptionPage = 0; expandedDescription = true; setFocus("description-back")
        }
    }

    private var playbackControl: some View {
        control("play", title: startingPlayback ? "Ouverture…" : playbackTitle, icon: "play.fill", primary: true, action: startPlayback)
            .disabled(startingPlayback || (item.isSeriesCollection && selectedEpisode == nil))
    }
    private func caseSection(_ metrics: MediaDetailMetrics) -> some View {
        MediaDetailCaseArtwork(item: item, year: details.year ?? item.details.year)
            .frame(height: metrics.caseHeight)
            .frame(maxWidth: .infinity)
    }

    private func episodeSection(_ metrics: MediaDetailMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(selectedSeason.map { $0.number == 0 ? "Spéciaux" : "Saison \($0.number)" } ?? "Épisodes")
                    .font(.system(size: metrics.bodySize, weight: .bold)).accessibilityAddTraits(.isHeader)
                if !episodes.isEmpty { Text("\(episodes.count) épisodes").font(.system(size: metrics.metadataSize)).foregroundStyle(.white.opacity(0.65)) }
            }
            if seasonLoading {
                HStack(spacing: 12) { ProgressView(); Text("Chargement des épisodes…") }.font(.headline)
            } else if seasonFailed {
                control("retry-episodes", title: "Réessayer les épisodes", icon: "arrow.clockwise") { seasonReload = UUID() }
            } else if episodes.isEmpty {
                Text("Aucun épisode fourni pour cette saison.").foregroundStyle(.secondary)
            } else {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(episodes) { episode in episodeButton(episode, metrics: metrics) }
                        }.padding(.vertical, 4).padding(.horizontal, 4)
                    }
                    // macOS may still reserve a mouse scroller with .hidden.
                    // Keep the full card height; arrows/focus scroll this row.
                    .scrollIndicators(.never)
                    .task(id: selectedEpisodeID) {
                        await Task.yield()
                        guard !Task.isCancelled, let id = selectedEpisodeID else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { reader.scrollTo("episode:\(id)", anchor: .center) }
                    }
                }
            }
        }
    }

    private func episodeButton(_ episode: IPTVItem, metrics: MediaDetailMetrics) -> some View {
        let id = "episode:\(episode.id)"
        let selected = episode.id == selectedEpisodeID
        let number = episode.episodeNumber ?? ((episodes.firstIndex(where: { $0.id == episode.id }) ?? 0) + 1)
        return Button {
            selectedEpisodeID = episode.id; setFocus(id); startPlayback()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 12) {
                    ArtworkView(url: episode.backdropURL ?? episode.logoURL ?? item.logoURL, fit: false) {
                        Image(systemName: "play.rectangle").font(.title).foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: metrics.episodeThumbnailHeight * 16 / 9, height: metrics.episodeThumbnailHeight)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text("Épisode \(number)").font(.system(size: metrics.episodeLabelSize, weight: .bold)).foregroundStyle(.cyan)
                            if selected { Image(systemName: "play.fill").font(.system(size: metrics.metadataSize - 3)).foregroundStyle(.white) }
                        }.lineLimit(1)
                        if let duration = episode.details.duration, !duration.isEmpty {
                            Text(duration).font(.system(size: metrics.metadataSize - 2)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(episode.name).font(.system(size: metrics.metadataSize, weight: .semibold))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                let progress = playback.history.entries[episode.id]?.fraction ?? 0
                if progress > 0 { ProgressView(value: progress).tint(.cyan).frame(height: 3) }
            }
            .padding(16)
            .frame(width: metrics.episodeWidth, height: metrics.episodeCardHeight, alignment: .topLeading)
            .background(selected ? Color.cyan.opacity(0.2) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focusedID == id ? Color.white : selected ? Color.cyan.opacity(0.85) : Color.white.opacity(0.2), lineWidth: focusedID == id ? 3 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focusedID == id)
        }
        .buttonStyle(MediaDetailEpisodeStyle(highlighted: focusedID == id))
        #if os(macOS)
        .focusable()
        #endif
        .focused($nativeFocus, equals: id).focusEffectDisabled()
        .id(id)
        .accessibilityIdentifier("media-detail-episode-\(episode.id)")
        .accessibilityLabel("Épisode \(number), \(episode.name)")
        .accessibilityHint("Lire cet épisode.")
        #if !os(tvOS)
        .onHover { inside in if inside { focusedID = id; selectedEpisodeID = episode.id } }
        #endif
    }

    private var controlsHint: some View {
        Text("Directions : choisir  ·  Valider : ouvrir  ·  Lecture : regarder  ·  Retour : fermer")
            #if os(tvOS)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            #else
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            #endif
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func control(_ id: String, title: String, icon: String, primary: Bool = false, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        Button { setFocus(id); action() } label: {
            if iconOnly { Image(systemName: icon).accessibilityLabel(title) }
            else { Label(title, systemImage: icon).lineLimit(1) }
        }
            .buttonStyle(MediaDetailControlStyle(highlighted: focusedID == id, primary: primary, compact: iconOnly))
            #if os(macOS)
            .focusable()
            #endif
            .focused($nativeFocus, equals: id).focusEffectDisabled()
            .id(id)
            .accessibilityIdentifier("media-detail-\(id)")
            #if os(tvOS) && FLUX_CATALOG_UI_TESTING
            .background(TVCatalogControlFrameProbe(identifier: "media-detail-\(id)").allowsHitTesting(false))
            #elseif os(macOS) && FLUX_CATALOG_UI_TESTING
            .background(CatalogDetailControlFrameProbe(identifier: "media-detail-\(id)").allowsHitTesting(false))
            #endif
            #if !os(tvOS)
            .onHover { inside in if inside { focusedID = id } }
            #endif
    }

    private var descriptionPages: [String] {
        #if os(tvOS)
        let pageLength = 520
        #else
        let pageLength = 850
        #endif
        var pages: [String] = [], current = ""
        for word in synopsis.split(whereSeparator: { $0.isWhitespace }) {
            if current.count + word.count > pageLength && !current.isEmpty { pages.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + String(word)
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [synopsis] : pages
    }
    private var descriptionScreen: some View {
        GeometryReader { geometry in
            #if os(tvOS)
            let titleSize: CGFloat = 56
            let textSize: CGFloat = 34
            let contentWidth: CGFloat = 1600
            #else
            let titleSize: CGFloat = geometry.size.width > 1000 ? 42 : 28
            let textSize: CGFloat = geometry.size.width > 1000 ? 28 : 22
            let contentWidth: CGFloat = 1360
            #endif
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    control("description-back", title: "Retour à la fiche", icon: "chevron.left", action: closeDescription)
                    Spacer()
                    Text("\(descriptionPage + 1) / \(descriptionPages.count)").font(.system(size: textSize * 0.72, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                Text(item.name).font(.system(size: titleSize, weight: .bold)).lineLimit(2)
                ScrollView {
                    Text(descriptionPages[min(descriptionPage, descriptionPages.count - 1)])
                        .font(.system(size: textSize)).lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(descriptionPage).transition(.opacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: descriptionPage)
                }.frame(maxHeight: .infinity)
                if descriptionPages.count > 1 {
                    HStack {
                        control("description-previous", title: "Page −", icon: "arrow.left") { moveDescription(-1) }.disabled(descriptionPage == 0)
                        Spacer()
                        control("description-next", title: "Page +", icon: "arrow.right") { moveDescription(1) }.disabled(descriptionPage + 1 >= descriptionPages.count)
                    }
                }
                Text("Haut / Bas : lire la suite  ·  Retour : retrouver la fiche")
                    .font(.system(size: textSize * 0.6)).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity)
            }
            .padding(geometry.size.width > 1000 ? 60 : 24)
            #if os(macOS)
            .frame(maxWidth: min(contentWidth, geometry.size.width - 96), maxHeight: geometry.size.height - 40)
            .fluxGlass(radius: 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            .frame(maxWidth: contentWidth).frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        #if !os(macOS)
        .background(Color(red: 0.025, green: 0.035, blue: 0.055))
        #endif
        #if os(tvOS)
        .onMoveCommand { direction in
            switch direction {
            case .up: moveDescription(-1)
            case .down: moveDescription(1)
            default: break
            }
        }
        #endif
    }

    private func loadEpisodes() async {
        guard item.isSeriesCollection else { seasons = []; return }
        seasonLoading = initialSeasons.isEmpty; seasonFailed = false
        do {
            let result: [IPTVSeason]
            if initialSeasons.isEmpty { result = try await library.seasons(for: item) }
            else { result = initialSeasons }
            guard !Task.isCancelled else { return }
            seasons = result; seasonLoading = false
            selectedEpisodeID = episodes.first(where: { $0.id == initialEpisodeID })?.id ?? episodes.first?.id
        } catch {
            guard !Task.isCancelled else { return }
            seasonLoading = false; seasonFailed = true
        }
    }
    private func setFocus(_ id: String) { focusedID = id; nativeFocus = id }
    private func closeDescription() { expandedDescription = false; setFocus("description") }
    private func moveDescription(_ delta: Int) { descriptionPage = max(0, min(descriptionPages.count - 1, descriptionPage + delta)) }
    private func cancelHandoff() { handoffToken = UUID(); handoffTask?.cancel(); handoffTask = nil; startingPlayback = false }
    private func dismiss() { cancelHandoff(); close() }
    private func startPlayback() {
        guard !startingPlayback, !suspended else { return }
        let episode = selectedEpisode, allSeasons = seasons
        guard !item.isSeriesCollection || episode != nil else { return }
        startingPlayback = true
        let token = UUID(); handoffToken = token
        handoffTask = Task { @MainActor in
            // Coalesce the button/remote event before handing the selected
            // title to the main player. No preview needs to be stopped here.
            await Task.yield()
            guard !Task.isCancelled, handoffToken == token else { return }
            if let episode, item.isSeriesCollection { playEpisode(episode, allSeasons) }
            else { play() }
            startingPlayback = false; handoffTask = nil
        }
    }
    private func handle(_ action: RemoteAction) {
        guard !suspended, scenePhase == .active else { return }
        if expandedDescription {
            switch action {
            case .back, .home: closeDescription()
            case .up, .rewind: moveDescription(-1)
            case .down, .forward: moveDescription(1)
            case .left: setFocus(descriptionPages.count > 1 ? "description-previous" : "description-back")
            case .right: setFocus(descriptionPages.count > 1 ? "description-next" : "description-back")
            case .select:
                if focusedID == "description-previous" { moveDescription(-1) }
                else if focusedID == "description-next" { moveDescription(1) }
                else { closeDescription() }
            default: break
            }
            return
        }
        #if os(macOS)
        if item.isSeriesCollection, [.up, .down, .left, .right].contains(action) { deskSeriesMove(action); return }
        if action == .select, focusedID.hasPrefix("season:"), let number = Int(focusedID.dropFirst("season:".count)) {
            chooseSeason(number); return
        }
        #endif
        switch action {
        case .back, .home: dismiss()
        case .playPause: startPlayback()
        case .up, .down, .left, .right:
                if let target = RemoteNavigation.move(from: focusedID, action: action, rows: focusRows) {
                setFocus(target)
                if target.hasPrefix("episode:") { selectedEpisodeID = String(target.dropFirst("episode:".count)) }
            }
        case .select:
            switch focusedID {
            case "back": dismiss()
            case "favorite": favorite()
            case "description": descriptionPage = 0; expandedDescription = true; setFocus("description-back")
            case "retry-episodes": seasonReload = UUID()
            default: startPlayback()
            }
        default: break
        }
    }
}

/// One lightweight sleeve uses the full cover, a printed spine and a fixed
/// perspective. It never starts a renderer, animation loop or media session.
private struct MediaDetailCaseArtwork: View {
    let item: IPTVItem
    let year: String?
    var expanded = true
    var hero: MediaDetailHero? = nil
    var showsFormat = true
    /// Room kept on the sides for the perspective and the shadow.
    var sideMargin: CGFloat = 70
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var format: CasePackageFormat { .resolve(year: year) }

    var body: some View {
        GeometryReader { geometry in
            let ratio = CGFloat(format.halfWidth / format.halfHeight)
            let height = max(1, min(geometry.size.height - (showsFormat ? 42 : 0), (geometry.size.width - sideMargin) / ratio))
            let width = height * ratio
            VStack(spacing: 14) {
                MediaDetailCaseBox(item: item, format: format)
                    .rotation3DEffect(.degrees(expanded ? -8 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.28)
                    .modifier(MediaDetailCaseFlourish(expanded: expanded, active: hero != nil && !reduceMotion))
                    .shadow(color: .black.opacity(0.55), radius: 14, x: expanded ? 12 : 3, y: expanded ? 14 : 4)
                    .modifier(MediaDetailCaseHero(hero: hero, isSource: expanded))
                    .frame(width: width, height: height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Boîtier \(format.title) · \(item.name)")
                    .accessibilityIdentifier("media-detail-box")
                    #if FLUX_CATALOG_UI_TESTING
                    #if os(tvOS)
                    .background(TVCatalogControlFrameProbe(identifier: "media-detail-box").allowsHitTesting(false))
                    #elseif os(macOS)
                    .background(CatalogDetailBoxFrameProbe().allowsHitTesting(false))
                    #endif
                    #endif
                if showsFormat {
                    Text(format.title)
                        .font(.system(size: max(12, min(18, height * 0.028)), weight: .semibold))
                        .tracking(3).foregroundStyle(.white.opacity(0.55))
                        .opacity(expanded ? 1 : 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// The case fills the frame it is given, so that it can start at the size of
/// the sleeve it comes from.
private struct MediaDetailCaseBox: View {
    let item: IPTVItem
    let format: CasePackageFormat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let spine = max(6, width * (format == .vhs ? 0.115 : 0.075))
            let radius = max(3, width * 0.018)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            HStack(spacing: 0) {
                LinearGradient(colors: [.black, Color(white: 0.20), Color(white: 0.075)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: spine, height: height)
                    .overlay {
                        Text(item.name)
                            .font(.system(size: max(6, height * 0.026), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .frame(width: height * 0.78, height: spine)
                            .rotationEffect(.degrees(-90))
                            .frame(width: spine, height: height)
                    }
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.26)).frame(width: 1) }
                ArtworkView(url: item.logoURL, fit: true) {
                    VStack(spacing: 18) {
                        Image(systemName: item.isSeriesCollection ? "square.stack.3d.up" : "film")
                            .font(.system(size: max(12, height * 0.09), weight: .light))
                        Text(item.name).font(.system(size: max(10, height * 0.045), weight: .bold))
                            .multilineTextAlignment(.center).lineLimit(5)
                    }
                    .foregroundStyle(.white.opacity(0.86)).padding(max(4, width * 0.07))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Color(red: 0.09, green: 0.16, blue: 0.21), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: max(2, radius * 0.55)))
                .padding(.vertical, format == .vhs ? 4 : 6)
                .padding(.trailing, format == .vhs ? 4 : 6)
            }
            .frame(width: width, height: height)
            .background(Color(white: 0.08), in: shape)
            .clipShape(shape)
            .overlay {
                LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0),
                                       .init(color: .clear, location: 0.16),
                                       .init(color: .clear, location: 0.82),
                                       .init(color: .white.opacity(0.045), location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(.white.opacity(0.40), lineWidth: 1.2) }
        }
    }
}

private struct MediaDetailCaseHero: ViewModifier {
    let hero: MediaDetailHero?
    let isSource: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if let hero { content.matchedGeometryEffect(id: hero.id, in: hero.namespace, properties: .frame, anchor: .center, isSource: isSource) }
        else { content }
    }
}

/// While the case travels between the shelf and the fiche it turns further
/// than its resting angle, the way a hand turns a sleeve to read its front.
private struct MediaDetailCaseFlourish: ViewModifier {
    let expanded: Bool
    let active: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active {
            content.keyframeAnimator(initialValue: 0.0, trigger: expanded) { view, turn in
                view.rotation3DEffect(.degrees(turn), axis: (x: 0.14, y: 1, z: 0), perspective: 0.42)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(expanded ? -30.0 : 20.0, duration: 0.18)
                    SpringKeyframe(0.0, duration: 0.5, spring: .bouncy)
                }
            }
        } else { content }
    }
}

private struct MediaDetailMetrics {
    let wide: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let gap: CGFloat
    let informationGap: CGFloat
    let headerHeight: CGFloat
    let hintHeight: CGFloat
    let informationWidth: CGFloat
    let mainHeight: CGFloat
    let caseHeight: CGFloat
    let episodeHeight: CGFloat
    let episodeWidth: CGFloat
    let episodeCardHeight: CGFloat
    let episodeThumbnailHeight: CGFloat
    let episodeLabelSize: CGFloat
    let titleSize: CGFloat
    let bodySize: CGFloat
    let metadataSize: CGFloat
    let titleLines: Int
    let metadataLines: Int
    let synopsisLines: Int

    init(size: CGSize, series: Bool, safeAreaInsets: EdgeInsets) {
        wide = size.width >= 920 && size.height >= 680
        #if os(tvOS)
        // Keep the full TV safe zone without counting native insets twice.
        horizontalPadding = max(24, 90 - min(safeAreaInsets.leading, safeAreaInsets.trailing))
        verticalPadding = max(24, 60 - min(safeAreaInsets.top, safeAreaInsets.bottom))
        headerHeight = 72
        hintHeight = 26
        titleSize = 60
        bodySize = 30
        metadataSize = 24
        titleLines = 2
        metadataLines = 1
        informationGap = 18
        #else
        horizontalPadding = wide ? max(28, min(56, size.width * 0.028)) : 20
        verticalPadding = horizontalPadding
        headerHeight = 54
        hintHeight = 18
        titleSize = wide ? min(48, max(34, size.width * 0.026)) : 32
        bodySize = wide ? min(27, max(20, size.width * 0.014)) : 19
        metadataSize = wide ? min(21, max(15, size.width * 0.011)) : 15
        titleLines = 3
        metadataLines = 2
        informationGap = 18
        #endif
        gap = wide ? 22 : 18
        let usableWidth = max(1, size.width - horizontalPadding * 2)
        informationWidth = usableWidth * 0.4
        #if os(tvOS)
        episodeHeight = series ? 256 : 0
        episodeWidth = 420
        episodeCardHeight = 200
        episodeLabelSize = 26
        #else
        episodeHeight = series ? max(190, min(240, size.height * 0.235)) : 0
        episodeWidth = wide ? max(250, min(330, usableWidth * 0.225)) : 270
        episodeCardHeight = max(142, episodeHeight - 48)
        episodeLabelSize = metadataSize
        #endif
        episodeThumbnailHeight = min(82, max(58, episodeCardHeight * 0.42))
        let available = size.height - verticalPadding * 2 - headerHeight - hintHeight - gap * (series ? 3 : 2) - episodeHeight
        mainHeight = max(280, available)
        caseHeight = wide ? mainHeight : min(560, max(320, usableWidth * 1.2))
        // Reserve title, metadata and controls before fitting the synopsis.
        let summaryBudget = mainHeight - titleSize * 1.25 * CGFloat(titleLines) - metadataSize * 1.3 * CGFloat(metadataLines) - headerHeight - informationGap * 4
        let fittingLines = max(2, Int((summaryBudget + 6) / (bodySize * 1.25 + 6)))
        synopsisLines = wide ? min(series ? 5 : 9, fittingLines) : 7
    }
}

private struct MediaDetailControlStyle: ButtonStyle {
    let highlighted: Bool
    var primary = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            #if os(tvOS)
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, compact ? 18 : 24).padding(.vertical, 16)
            .frame(minWidth: compact ? 72 : nil, minHeight: 72)
            #else
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 19).padding(.vertical, compact ? 12 : 14)
            #endif
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .background(primary ? Color.cyan.opacity(highlighted ? 0.4 : 0.28) : .white.opacity(highlighted ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 16))
            .fluxMediaGlass(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(highlighted && isEnabled ? .white : .white.opacity(0.2), lineWidth: highlighted && isEnabled ? 3 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : highlighted && isEnabled ? 1.025 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MediaDetailEpisodeStyle: ButtonStyle {
    let highlighted: Bool
    /// Scale of the episode under the pointer or the focus.
    var lift: CGFloat = 1.016
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : highlighted && !reduceMotion ? lift : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if os(macOS)
// MARK: - Desk fiche (Mac): a glass sheet over the blurred catalogue

extension MediaDetailPresentation {
    private var sectionTint: Color { item.isSeriesCollection ? .purple : item.kind == .live ? .cyan : .orange }
    private var sectionTitle: String { item.isSeriesCollection ? "SÉRIE" : item.kind == .live ? "EN DIRECT" : "CINÉMA" }
    private var sectionSymbol: String { item.isSeriesCollection ? "square.stack.3d.up.fill" : item.kind == .live ? "tv.fill" : "film.fill" }
    private var caseYear: String? { details.year ?? item.details.year }

    func deskLayout(_ size: CGSize) -> some View {
        let sheet = CGSize(width: min(size.width - 96, item.isSeriesCollection ? 1340 : 1160),
                           height: min(size.height - 30, 720))
        return Group {
            if item.isSeriesCollection { seriesSheet(sheet) } else { filmSheet(sheet) }
        }
        .frame(width: sheet.width, height: sheet.height)
        .frame(width: size.width, height: size.height)
    }

    /// The glass and its text appear with the fiche; the case travels on its
    /// own, fully opaque, from the sleeve that was picked.
    private func sheetSurface<Content: View>(_ sheet: CGSize, padding: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        return content()
            .padding(padding)
            .frame(width: sheet.width, height: sheet.height, alignment: .topLeading)
            .background {
                // The cover lends its colours to the sheet.
                ArtworkView(url: item.logoURL, fit: false) { Color.clear }
                    .frame(width: sheet.width, height: sheet.height)
                    .blur(radius: 70).opacity(0.20)
                    .clipShape(shape).allowsHitTesting(false).accessibilityHidden(true)
            }
            .background(.black.opacity(0.18), in: shape)
            .fluxGlass(radius: 34)
            .shadow(color: .black.opacity(0.5), radius: 36, x: 0, y: 20)
            .opacity(expanded ? 1 : 0)
            .scaleEffect(expanded ? 1 : 0.96)
    }

    private var kindBadge: some View {
        Label(sectionTitle, systemImage: sectionSymbol)
            .font(.system(size: 12, weight: .bold)).tracking(1.6)
            .foregroundStyle(sectionTint)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(sectionTint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(sectionTint.opacity(0.35), lineWidth: 1))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.55))
    }

    private func clean(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "0" else { return nil }
        return text
    }
    /// A full date or a year becomes the year alone.
    private func yearText(_ value: String?) -> String? {
        guard let text = clean(value) else { return nil }
        if let range = text.range(of: #"(18|19|20|21)[0-9]{2}"#, options: .regularExpression) { return String(text[range]) }
        return text
    }
    /// "01:48:00", "108" and "108 min" all read as "1 h 48".
    private func durationText(_ value: String?) -> String? {
        guard let text = clean(value) else { return nil }
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Int($0) }
        var minutes: Int?
        if fields.count == 3, parts.count == 3 { minutes = parts[0] * 60 + parts[1] }
        else if fields.count == 2, parts.count == 2 { minutes = parts[0] }
        else if let plain = Int(text), plain > 0, plain < 1000 { minutes = plain }
        // A provider's own wording, such as "1 h 48", is kept as written.
        guard let minutes, minutes > 0 else { return text }
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
    private func ratingText(_ value: String?) -> String? {
        guard let text = clean(value), let number = Double(text.replacingOccurrences(of: ",", with: ".").prefix(while: { $0.isNumber || $0 == "." })),
              number > 0 else { return nil }
        return String(format: "%.1f", number).replacingOccurrences(of: ".", with: ",")
    }
    private var genres: [String] {
        guard let text = clean(details.genre) else { return [] }
        return text.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "|" || $0 == "·" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5).map { $0 }
    }

    private func chip(_ text: String, symbol: String? = nil, tint: Color = .white) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint) }
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(.white.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    private var chips: some View {
        MediaDetailFlow(spacing: 8) {
            if let year = yearText(details.year) { chip(year, symbol: "calendar") }
            if let duration = durationText(details.duration) { chip(duration, symbol: "clock") }
            if let rating = ratingText(details.rating) { chip(rating, symbol: "star.fill", tint: .yellow) }
            ForEach(genres, id: \.self) { genre in chip(genre) }
        }
    }

    private func progressNote(for id: String) -> some View {
        let entry = playback.history.entries[id]
        return Group {
            if let entry, entry.fraction > 0 {
                HStack(spacing: 10) {
                    ProgressView(value: entry.fraction).tint(sectionTint).frame(maxWidth: 220)
                    Text(entry.resumable ? "Déjà vu à \(Int((entry.fraction * 100).rounded())) %" : "Déjà vu")
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func creditRow(_ label: String, _ value: String?) -> some View {
        Group {
            if let value = clean(value) {
                GridRow {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        .gridColumnAlignment(.leading)
                    Text(value).font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Film

    private func filmSheet(_ sheet: CGSize) -> some View {
        let padding: CGFloat = 30
        let caseWidth = min(360, max(220, sheet.width * 0.31))
        return ZStack(alignment: .topLeading) {
            sheetSurface(sheet, padding: padding) {
                HStack(alignment: .top, spacing: 30) {
                    Color.clear.frame(width: caseWidth)
                    filmInformation
                }
            }
            MediaDetailCaseArtwork(item: item, year: caseYear, expanded: expanded, hero: hero)
                .frame(width: caseWidth, height: sheet.height - padding * 2)
                .padding(padding)
        }
    }

    private var filmInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                kindBadge
                Spacer(minLength: 0)
                control("back", title: "Fermer la fiche", icon: "xmark", iconOnly: true, action: dismiss)
            }
            Text(item.name)
                .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.4)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            chips
            HStack(spacing: 10) {
                playbackControl
                control("favorite", title: isFavorite ? "Dans les favoris" : "Favoris", icon: isFavorite ? "star.fill" : "star", action: favorite)
                descriptionControl
            }
            progressNote(for: item.id)
            Divider().overlay(.white.opacity(0.18))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        caption("SYNOPSIS")
                        Text(synopsis).font(.system(size: 17)).lineSpacing(5)
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 9) {
                        creditRow("Réalisation", details.director)
                        creditRow("Distribution", details.cast)
                        creditRow("Catégorie", item.group)
                        creditRow("Format", CasePackageFormat.resolve(year: caseYear).title)
                    }
                }
                .padding(.trailing, 8).padding(.bottom, 4)
            }
            controlsHint
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Series: seasons, episodes from top to bottom, then the episode

    private func seriesSheet(_ sheet: CGSize) -> some View {
        let padding: CGFloat = 26
        let inner = CGSize(width: sheet.width - padding * 2, height: sheet.height - padding * 2)
        let left: CGFloat = 232, backHeight: CGFloat = 48
        let right = min(470, max(320, inner.width * 0.35))
        let boxHeight = min(320, max(282, inner.height * 0.46))
        return ZStack(alignment: .topLeading) {
            sheetSurface(sheet, padding: padding) {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        control("back", title: "Les saisons", icon: "chevron.left", action: dismiss)
                            .frame(height: backHeight, alignment: .leading)
                        Color.clear.frame(height: boxHeight)
                        seasonList
                    }.frame(width: left)
                    episodeColumn
                    episodePanel.frame(width: right)
                }
            }
            MediaDetailCaseArtwork(item: item, year: caseYear, expanded: expanded, hero: hero, showsFormat: false, sideMargin: 14)
                .frame(width: left, height: boxHeight)
                .padding(.leading, padding).padding(.top, padding + backHeight + 12)
        }
    }

    private func seasonTitle(_ season: IPTVSeason?) -> String {
        guard let season else { return "Épisodes" }
        return season.number == 0 ? "Spéciaux" : "Saison \(season.number)"
    }

    private var seasonList: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(seasons) { season in seasonRow(season) }
                }.padding(.vertical, 2)
            }
            .onAppear { if let number = selectedSeason?.number { reader.scrollTo("season:\(number)", anchor: .center) } }
            .onChange(of: selectedSeason?.number) { _, number in
                if let number { reader.scrollTo("season:\(number)", anchor: .center) }
            }
        }
    }

    private func seasonRow(_ season: IPTVSeason) -> some View {
        let id = "season:\(season.number)"
        let selected = season.number == selectedSeason?.number
        let focused = focusedID == id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { setFocus(id); chooseSeason(season.number) } label: {
            HStack(spacing: 8) {
                Text(seasonTitle(season)).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(season.episodes.count)").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(sectionTint) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(selected ? sectionTint.opacity(0.24) : .white.opacity(focused ? 0.11 : 0.04), in: shape)
            .overlay(shape.strokeBorder(focused ? Color.white.opacity(0.8) : .clear, lineWidth: 2).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(FluxBareButtonStyle())
        .focusable().focused($nativeFocus, equals: id).focusEffectDisabled().id(id)
        .accessibilityIdentifier("media-detail-season-\(season.number)")
        .accessibilityLabel("\(seasonTitle(season)), \(season.episodes.count) épisodes")
        .accessibilityValue(selected ? "Sélectionnée" : "")
        .onHover { inside in if inside { focusedID = id } }
    }

    func chooseSeason(_ number: Int) {
        guard number != selectedSeason?.number, seasons.contains(where: { $0.number == number }) else { return }
        seasonChanged(number)
    }

    private var episodeColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            kindBadge
            Text(item.name)
                .font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-0.3)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(seasonTitle(selectedSeason)).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if !episodes.isEmpty {
                    Text("\(episodes.count) \(episodes.count == 1 ? "épisode" : "épisodes")")
                        .font(.callout).foregroundStyle(.white.opacity(0.6))
                }
            }
            if seasonLoading {
                HStack(spacing: 12) { ProgressView(); Text("Chargement des épisodes…") }.font(.headline)
            } else if seasonFailed {
                control("retry-episodes", title: "Réessayer les épisodes", icon: "arrow.clockwise") { seasonReload = UUID() }
            } else if episodes.isEmpty {
                Text("Aucun épisode fourni pour cette saison.").foregroundStyle(.secondary)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(episodes) { episode in episodeRow(episode) }
                        }.padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .onAppear { if let id = selectedEpisodeID { reader.scrollTo("episode:\(id)", anchor: .center) } }
                    .onChange(of: selectedSeason?.number) { _, _ in
                        if let id = selectedEpisodeID ?? episodes.first?.id { reader.scrollTo("episode:\(id)", anchor: .top) }
                    }
                    .task(id: selectedEpisodeID) {
                        await Task.yield()
                        guard !Task.isCancelled, keyboardSelection, let id = selectedEpisodeID else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { reader.scrollTo("episode:\(id)", anchor: .center) }
                    }
                }
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func episodeNumber(_ episode: IPTVItem) -> Int {
        episode.episodeNumber ?? ((episodes.firstIndex(where: { $0.id == episode.id }) ?? 0) + 1)
    }

    private func episodeRow(_ episode: IPTVItem) -> some View {
        let id = "episode:\(episode.id)"
        let selected = episode.id == selectedEpisodeID
        let focused = focusedID == id
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let progress = playback.history.entries[episode.id]?.fraction ?? 0
        return Button {
            selectedEpisodeID = episode.id; setFocus(id); startPlayback()
        } label: {
            HStack(spacing: 12) {
                Color.black.opacity(0.4)
                    .frame(width: 116, height: 65)
                    .overlay {
                        ArtworkView(url: episode.backdropURL ?? episode.logoURL ?? item.logoURL, fit: false) {
                            Image(systemName: "play.rectangle").font(.title3).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Épisode \(episodeNumber(episode))").font(.system(size: 12, weight: .bold)).foregroundStyle(sectionTint)
                    Text(episode.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if progress > 0 { ProgressView(value: progress).tint(sectionTint).frame(height: 3) }
                }
                if let duration = durationText(episode.details.duration) {
                    Text(duration).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                }
                Image(systemName: "play.fill").font(.caption).foregroundStyle(.white.opacity(selected ? 0.95 : 0))
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? sectionTint.opacity(0.26) : .white.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(focused ? Color.white.opacity(0.9) : selected ? sectionTint.opacity(0.7) : Color.white.opacity(0.10),
                                        lineWidth: focused ? 2 : 1).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(MediaDetailEpisodeStyle(highlighted: focused, lift: 1.035))
        .focusable().focused($nativeFocus, equals: id).focusEffectDisabled()
        .id(id)
        .zIndex(focused ? 1 : 0)
        .accessibilityIdentifier("media-detail-episode-\(episode.id)")
        .accessibilityLabel("Épisode \(episodeNumber(episode)), \(episode.name)")
        .accessibilityHint("Lire cet épisode.")
        .onHover { inside in
            if inside { keyboardSelection = false; focusedID = id; selectedEpisodeID = episode.id }
        }
    }

    private var episodePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let episode = selectedEpisode {
                let season = episode.seasonNumber ?? selectedSeason?.number ?? 1
                let frame = RoundedRectangle(cornerRadius: 18, style: .continuous)
                Button { startPlayback() } label: {
                    Color.black.opacity(0.45)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            ArtworkView(url: episode.backdropURL ?? episode.logoURL ?? item.backdropURL ?? item.logoURL, fit: false) {
                                Image(systemName: "play.rectangle").font(.system(size: 44, weight: .light)).foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .clipShape(frame)
                        .overlay(frame.strokeBorder(.white.opacity(0.28), lineWidth: 1).allowsHitTesting(false))
                        .overlay(alignment: .bottomLeading) {
                            Text("S\(season) · E\(episodeNumber(episode))")
                                .font(.system(size: 12, weight: .bold)).tracking(0.6)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.7), in: Capsule()).padding(12)
                        }
                        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
                        .contentShape(frame)
                }
                .buttonStyle(FluxBareButtonStyle())
                .accessibilityLabel("Lire l’épisode \(episodeNumber(episode))")
                Text(episode.name).font(.system(size: 20, weight: .bold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                MediaDetailFlow(spacing: 8) {
                    if let duration = durationText(episode.details.duration ?? details.duration) { chip(duration, symbol: "clock") }
                    if let year = yearText(details.year) { chip(year, symbol: "calendar") }
                    if let rating = ratingText(episode.details.rating ?? details.rating) { chip(rating, symbol: "star.fill", tint: .yellow) }
                    ForEach(genres.prefix(2), id: \.self) { genre in chip(genre) }
                }
                HStack(spacing: 8) {
                    playbackControl
                    control("favorite", title: isFavorite ? "Dans les favoris" : "Favoris", icon: isFavorite ? "star.fill" : "star", iconOnly: true, action: favorite)
                    control("description", title: "Description complète", icon: "text.alignleft", iconOnly: true) {
                        descriptionPage = 0; expandedDescription = true; setFocus("description-back")
                    }
                }
                progressNote(for: episode.id)
                Divider().overlay(.white.opacity(0.18))
                ScrollView {
                    Text(clean(episode.details.synopsis) ?? synopsis)
                        .font(.system(size: 15)).lineSpacing(4).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
                }
            } else {
                Text(seasonLoading ? "Chargement…" : "Choisissez un épisode.").font(.title3).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// Seasons, episodes and actions are three columns: left and right change
    /// column, up and down move inside it.
    func deskSeriesMove(_ action: RemoteAction) {
        let seasonIDs = seasons.map { "season:\($0.number)" }
        let episodeIDs = episodes.map { "episode:\($0.id)" }
        let actions = (startingPlayback || selectedEpisode == nil ? [] : ["play"]) + ["favorite", "description"]
        let season = selectedSeason.map { "season:\($0.number)" }
        let episode = selectedEpisodeID.map { "episode:\($0)" }.flatMap { episodeIDs.contains($0) ? $0 : nil } ?? episodeIDs.first
        var target = focusedID
        if focusedID == "back" {
            if action == .down { target = season ?? seasonIDs.first ?? "back" }
            else if action == .right { target = episode ?? actions.first ?? "back" }
        } else if let index = seasonIDs.firstIndex(of: focusedID) {
            switch action {
            case .up: target = index > 0 ? seasonIDs[index - 1] : "back"
            case .down: target = seasonIDs[min(seasonIDs.count - 1, index + 1)]
            case .right: target = episode ?? actions.first ?? focusedID
            default: break
            }
        } else if let index = episodeIDs.firstIndex(of: focusedID) {
            switch action {
            case .up: target = episodeIDs[max(0, index - 1)]
            case .down: target = episodeIDs[min(episodeIDs.count - 1, index + 1)]
            case .left: target = season ?? "back"
            case .right: target = actions.first ?? focusedID
            default: break
            }
        } else if let index = actions.firstIndex(of: focusedID) {
            switch action {
            case .left: target = index > 0 ? actions[index - 1] : episode ?? season ?? "back"
            case .right: target = actions[min(actions.count - 1, index + 1)]
            default: break
            }
        } else {
            target = episode ?? actions.first ?? "back"
        }
        keyboardSelection = true
        setFocus(target)
        if target.hasPrefix("episode:") { selectedEpisodeID = String(target.dropFirst("episode:".count)) }
        // Moving through the seasons shows each one's episodes at once.
        if target.hasPrefix("season:"), let number = Int(target.dropFirst("season:".count)) { chooseSeason(number) }
    }
}

/// Wraps chips onto as many lines as the width requires.
private struct MediaDetailFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > limit { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: limit.isFinite ? limit : widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
#endif
