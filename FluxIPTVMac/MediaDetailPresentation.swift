import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MediaDetailRemoteEvent: Equatable {
    let action: RemoteAction
    let token = UUID()
}

/// A readable screen for one selected title. Artwork is static; the only live
/// surface is its single trailer player. No catalogue neighbours or 3D scene
/// are created while this presentation is visible.
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
    var onTrailerPresentation: (Bool) -> Void = { _ in }

    @EnvironmentObject private var library: IPTVLibrary
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TrailerPreviewDelay.storageKey) private var previewDelay: TrailerPreviewDelay = .five
    @AppStorage(TrailerPreviewDelay.automaticKey) private var automaticPreview = true
    @StateObject private var preview = CaseMediaPreviewController()
    @State private var seasons: [IPTVSeason] = []
    @State private var selectedEpisodeID: String?
    @State private var seasonLoading = false
    @State private var seasonFailed = false
    @State private var seasonReload = UUID()
    @State private var fullscreenTrailer = false
    @State private var expandedDescription = false
    @State private var descriptionPage = 0
    @State private var focusedID = "play"
    @FocusState private var nativeFocus: String?
    @State private var startingPlayback = false
    @State private var handoffTask: Task<Void, Never>?
    @State private var handoffToken = UUID()

    init(item: IPTVItem, details: IPTVDetails, close: @escaping () -> Void,
         play: @escaping () -> Void, playEpisode: @escaping (IPTVItem, [IPTVSeason]) -> Void,
         favorite: @escaping () -> Void, isFavorite: Bool, remoteEvent: MediaDetailRemoteEvent?,
         initialSeasons: [IPTVSeason] = [], initialSeasonNumber: Int? = nil,
         initialEpisodeID: String? = nil, suspended: Bool = false,
         onTrailerPresentation: @escaping (Bool) -> Void = { _ in }) {
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
        self.onTrailerPresentation = onTrailerPresentation
        // The season shelf already has these episodes. Install them before
        // the first focus evaluation, so the restored episode's Play button
        // is enabled immediately instead of falling back to "Les saisons".
        let availableSeasons = item.isSeriesCollection ? initialSeasons : []
        let initialSeason = availableSeasons.first(where: { $0.number == initialSeasonNumber }) ?? availableSeasons.first
        let initialEpisode = initialSeason?.episodes.first(where: { $0.id == initialEpisodeID }) ?? initialSeason?.episodes.first
        _seasons = State(initialValue: availableSeasons)
        _selectedEpisodeID = State(initialValue: initialEpisode?.id)
    }

    private var active: Bool { !suspended && !startingPlayback && scenePhase == .active && !expandedDescription }
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
    private var previewKey: String {
        "\(item.id)|\(active)|\(automaticPreview)|\(previewDelay.rawValue)|\(details.trailerURL?.absoluteString ?? "")|\(item.backdropURL?.absoluteString ?? "")"
    }
    private var selectionKey: String {
        "\(item.id)|\(initialSeasonNumber.map(String.init) ?? "")|\(initialEpisodeID ?? "")|\(seasonReload)"
    }
    private var focusRows: [[String]] {
        var playbackActions: [String] = []
        if !startingPlayback && (!item.isSeriesCollection || selectedEpisode != nil) { playbackActions.append("play") }
        if !startingPlayback && details.trailerURL != nil { playbackActions.append("trailer") }
        if preview.showVideo { playbackActions.append("mute") }
        var rows = [["back", "description", "favorite"], playbackActions]
        if seasonFailed { rows.append(["retry-episodes"]) }
        if !episodes.isEmpty { rows.append(episodes.map { "episode:\($0.id)" }) }
        return rows
    }

    var body: some View {
        ZStack {
            if fullscreenTrailer {
                MediaDetailTrailerPresentation(preview: preview, remoteEvent: remoteEvent, close: closeTrailer)
                    .transition(.opacity)
            } else if expandedDescription {
                descriptionScreen
                    .transition(.opacity)
            } else {
                GeometryReader { geometry in
                    let metrics = MediaDetailMetrics(size: geometry.size, series: item.isSeriesCollection, safeAreaInsets: geometry.safeAreaInsets)
                    ZStack {
                        backdrop
                        if metrics.wide { wideLayout(metrics) }
                        else { narrowLayout(metrics) }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.025, green: 0.035, blue: 0.055))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fullscreenTrailer)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expandedDescription)
        .task(id: previewKey) { configurePreview() }
        .task(id: selectionKey) { await loadEpisodes() }
        .onChange(of: initialSeasons) { _, value in
            guard !value.isEmpty else { return }
            seasons = value
            if !episodes.contains(where: { $0.id == selectedEpisodeID }) { selectedEpisodeID = episodes.first?.id }
        }
        .onChange(of: remoteEvent) { [fullscreenTrailer] _, event in
            // Route according to the screen that received the event. The
            // trailer's handler may close itself before this parent callback
            // runs; reading live state here would consume Back/Select twice.
            guard !fullscreenTrailer, let event else { return }
            handle(event.action)
        }
        .onChange(of: nativeFocus) { _, value in
            guard let value else { return }
            focusedID = value
            if value.hasPrefix("episode:") { selectedEpisodeID = String(value.dropFirst("episode:".count)) }
        }
        .onChange(of: fullscreenTrailer) { _, value in onTrailerPresentation(value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelHandoff(); preview.stop() } }
        .onAppear { setFocus(item.isSeriesCollection && selectedEpisode == nil ? "back" : "play") }
        .onDisappear { cancelHandoff(); preview.stop(); onTrailerPresentation(false) }
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
                trailerSection(metrics)
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
                trailerSection(metrics)
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { playbackControl; trailerControl }
                VStack(alignment: .leading, spacing: 10) { playbackControl; trailerControl }
            }
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
    private var trailerControl: some View {
        control("trailer", title: "Bande-annonce", icon: "play.rectangle", action: openTrailer)
            .disabled(details.trailerURL == nil || startingPlayback)
    }

    private func trailerSection(_ metrics: MediaDetailMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("BANDE-ANNONCE", systemImage: "play.rectangle")
                .font(.system(size: metrics.metadataSize, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.78))
            MediaDetailTrailerSurface(preview: preview, artworkURL: item.backdropURL ?? item.logoURL, artworkIsPoster: item.backdropURL == nil)
                .frame(height: metrics.previewHeight)
                .frame(maxWidth: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
                .overlay(alignment: .bottomTrailing) {
                    control("mute", title: preview.isMuted ? "Activer le son" : "Couper le son", icon: preview.isMuted ? "speaker.slash" : "speaker.wave.2", iconOnly: true) {
                        preview.setMuted(!preview.isMuted)
                    }
                    .disabled(!preview.showVideo)
                    .padding(16)
                }
            Text(preview.statusText)
                .font(.system(size: metrics.metadataSize))
                .foregroundStyle(.white.opacity(0.68)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    .scrollIndicators(.hidden)
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
            .frame(maxWidth: contentWidth).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.025, green: 0.035, blue: 0.055))
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

    private func configurePreview() {
        preview.setBackFacing(active)
        preview.update(item: item, details: details, filmURL: nil, backVisible: active, automatic: automaticPreview, delay: previewDelay)
        preview.setYouTubeViewportEligible(active)
        if fullscreenTrailer && active { preview.activateTrailer() }
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
    private func openTrailer() {
        guard !startingPlayback, details.trailerURL != nil else { return }
        preview.setBackFacing(true); preview.setYouTubeViewportEligible(true)
        _ = preview.activateTrailer()
        fullscreenTrailer = true
    }
    private func closeTrailer() {
        preview.setMuted(true); fullscreenTrailer = false; setFocus("trailer")
    }
    private func closeDescription() { expandedDescription = false; setFocus("description") }
    private func moveDescription(_ delta: Int) { descriptionPage = max(0, min(descriptionPages.count - 1, descriptionPage + delta)) }
    private func cancelHandoff() { handoffToken = UUID(); handoffTask?.cancel(); handoffTask = nil; startingPlayback = false }
    private func dismiss() { cancelHandoff(); preview.stop(); close() }
    private func startPlayback() {
        guard !startingPlayback else { return }
        let episode = selectedEpisode, allSeasons = seasons
        guard !item.isSeriesCollection || episode != nil else { return }
        startingPlayback = true
        let token = UUID(); handoffToken = token
        handoffTask = Task { @MainActor in
            await preview.stopAndWait()
            guard !Task.isCancelled, handoffToken == token else { return }
            if let episode, item.isSeriesCollection { playEpisode(episode, allSeasons) }
            else { play() }
            startingPlayback = false; handoffTask = nil
        }
    }
    private func handle(_ action: RemoteAction) {
        // The fullscreen player owns its events; both views share one session.
        guard !fullscreenTrailer else { return }
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
        switch action {
        case .back, .home: dismiss()
        case .playPause: startPlayback()
        case .fullscreen: openTrailer()
        case .mute: preview.setMuted(!preview.isMuted)
        case .up, .down, .left, .right:
                if let target = RemoteNavigation.move(from: focusedID, action: action, rows: focusRows) {
                setFocus(target)
                if target.hasPrefix("episode:") { selectedEpisodeID = String(target.dropFirst("episode:".count)) }
            }
        case .select:
            switch focusedID {
            case "back": dismiss()
            case "favorite": favorite()
            case "trailer": openTrailer()
            case "mute": preview.setMuted(!preview.isMuted)
            case "description": descriptionPage = 0; expandedDescription = true; setFocus("description-back")
            case "retry-episodes": seasonReload = UUID()
            default: startPlayback()
            }
        default: break
        }
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
    let previewHeight: CGFloat
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
        let videoWidth = wide ? usableWidth - informationWidth - gap * 1.4 : usableWidth
        previewHeight = wide ? max(160, min(videoWidth * 9 / 16, available - metadataSize * 2.6 - 28)) : videoWidth * 9 / 16
        mainHeight = max(280, available)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : highlighted ? 1.016 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MediaDetailTrailerSurface: View {
    @ObservedObject var preview: CaseMediaPreviewController
    var artworkURL: URL?
    var artworkIsPoster = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
            #if os(macOS) || os(iOS)
            if let session = preview.youtubeSession { YouTubeTrailerSurface(session: session) }
            else if let player = preview.player {
                if !preview.showVideo { placeholder }
                MediaDetailNativeVideoSurface(player: player).opacity(preview.showVideo ? 1 : 0)
            }
            else { placeholder }
            #else
            if let player = preview.player {
                if !preview.showVideo { placeholder }
                MediaDetailNativeVideoSurface(player: player).opacity(preview.showVideo ? 1 : 0)
            }
            else { placeholder }
            #endif
            if preview.phase == .loading || preview.phase == .preparing {
                ProgressView().tint(.white).padding(20).background(.black.opacity(0.75), in: Circle()).allowsHitTesting(false)
            }
            if preview.phase == .failed || preview.phase == .external {
                Text(preview.statusText).font(.headline).multilineTextAlignment(.center)
                    .padding(28).frame(maxWidth: 620)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: preview.showVideo)
    }
    private var placeholder: some View {
        ZStack {
            if let still = preview.still {
                Image(decorative: still, scale: 1, orientation: .up).resizable().scaledToFit()
            } else if let artworkURL {
                ArtworkView(url: artworkURL, fit: artworkIsPoster) { Color.clear }
                    .opacity(preview.phase == .unavailable ? 0.42 : 0.75)
            }
            if preview.phase == .unavailable {
                VStack(spacing: 15) {
                    Image(systemName: "play.slash").font(.system(size: 34, weight: .light))
                    Text("Aucune bande-annonce disponible").font(.headline).multilineTextAlignment(.center)
                }.padding(24).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaDetailTrailerPresentation: View {
    @ObservedObject var preview: CaseMediaPreviewController
    let remoteEvent: MediaDetailRemoteEvent?
    let close: () -> Void
    @FocusState private var nativeFocus: String?
    @State private var focus = "back"
    #if os(macOS)
    @State private var expandedWindowNumber: Int?
    @State private var escapeMonitor: Any?
    #endif
    private let actions = ["back", "rewind", "play", "forward", "mute"]

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 880
            #if os(tvOS)
            let horizontalMargin = max(24, 90 - min(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing))
            let topMargin = max(24, 60 - geometry.safeAreaInsets.top)
            #else
            let horizontalMargin: CGFloat = compact ? 12 : 24
            let topMargin: CGFloat = 16
            #endif
            VStack(spacing: 12) {
            HStack(spacing: compact ? 7 : 12) {
                button("back", title: "La fiche", icon: "chevron.left", compact: compact, action: close)
                Spacer(minLength: 0)
                button("rewind", title: "−15 s", icon: "gobackward.15", compact: compact) { preview.seek(by: -15) }
                button("play", title: preview.isPlaying ? "Pause" : "Lire", icon: preview.isPlaying ? "pause.fill" : "play.fill", compact: compact) { preview.togglePlayback() }
                button("forward", title: "+15 s", icon: "goforward.15", compact: compact) { preview.seek(by: 15) }
                button("mute", title: preview.isMuted ? "Activer le son" : "Couper le son", icon: preview.isMuted ? "speaker.slash" : "speaker.wave.2", compact: compact) { preview.setMuted(!preview.isMuted) }
            }.padding(.horizontal, horizontalMargin).padding(.top, topMargin)
            MediaDetailTrailerSurface(preview: preview).frame(maxWidth: .infinity, maxHeight: .infinity)
            if preview.phase != .playing {
                Text(preview.statusText)
                    #if os(tvOS)
                    .font(.system(size: 24))
                    #else
                    .font(.callout)
                    #endif
                    .foregroundStyle(.white.opacity(0.7)).padding(.horizontal, horizontalMargin).padding(.bottom, topMargin)
            }
            }
        }
        .background(.black).foregroundStyle(.white)
        .onAppear {
            nativeFocus = "back"
            #if os(macOS)
            let windowNumber = NSApp.keyWindow?.windowNumber
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window?.windowNumber == windowNumber else { return event }
                close(); return nil
            }
            if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
                expandedWindowNumber = window.windowNumber; window.toggleFullScreen(nil)
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            if let number = expandedWindowNumber, let window = NSApp.windows.first(where: { $0.windowNumber == number }), window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            expandedWindowNumber = nil
            #endif
        }
        .onChange(of: nativeFocus) { _, value in if let value { focus = value } }
        .onChange(of: remoteEvent) { _, event in
            guard let action = event?.action else { return }
            switch action {
            case .back, .home, .fullscreen: close()
            case .playPause: preview.togglePlayback()
            case .rewind: preview.seek(by: -15)
            case .forward: preview.seek(by: 15)
            case .mute: preview.setMuted(!preview.isMuted)
            case .left, .right, .up, .down:
                if let target = RemoteNavigation.move(from: focus, action: action, rows: [actions]) { focus = target; nativeFocus = target }
            case .select:
                switch focus {
                case "back": close()
                case "rewind": preview.seek(by: -15)
                case "forward": preview.seek(by: 15)
                case "mute": preview.setMuted(!preview.isMuted)
                default: preview.togglePlayback()
                }
            default: break
            }
        }
    }
    private func button(_ id: String, title: String, icon: String, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if compact { Image(systemName: icon).accessibilityLabel(title) }
            else { Label(title, systemImage: icon).lineLimit(1) }
        }
            .buttonStyle(MediaDetailControlStyle(highlighted: focus == id, compact: compact))
            #if os(macOS)
            .focusable()
            #endif
            .focused($nativeFocus, equals: id).focusEffectDisabled()
    }
}

#if os(macOS)
private final class MediaDetailVideoView: NSView {
    private let videoLayer = AVPlayerLayer()
    override init(frame: CGRect) {
        super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect; layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); videoLayer.frame = bounds; CATransaction.commit()
    }
    func setPlayer(_ player: AVPlayer) { if videoLayer.player !== player { videoLayer.player = player } }
}
private struct MediaDetailNativeVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> MediaDetailVideoView { let view = MediaDetailVideoView(frame: .zero); view.setPlayer(player); return view }
    func updateNSView(_ view: MediaDetailVideoView, context: Context) { view.setPlayer(player) }
}
#else
private final class MediaDetailVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    func setPlayer(_ player: AVPlayer) {
        let video = layer as! AVPlayerLayer; video.videoGravity = .resizeAspect
        if video.player !== player { video.player = player }
        backgroundColor = .black
    }
}
private struct MediaDetailNativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> MediaDetailVideoView { let view = MediaDetailVideoView(); view.setPlayer(player); return view }
    func updateUIView(_ view: MediaDetailVideoView, context: Context) { view.setPlayer(player) }
}
#endif
