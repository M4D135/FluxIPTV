import SwiftUI
import AVKit

/// A single settings destination shared by Apple TV, iOS and Mac. Appearance
/// preferences are immediate; transport changes are drafted and applied explicitly.
/// On the Mac it is a screen of the window, reached from the dock, and it also
/// holds the sources; elsewhere it remains a sheet.
struct PlaybackSettingsView: View {
    /// What the Sources page shows in place of the saved sources.
    enum SourceEditor: Hashable, Identifiable {
        case new, existing(IPTVSource)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let source): source.id.uuidString
            }
        }
    }
    enum Page: String, CaseIterable, Identifiable {
        case sources, appearance, dock, video, network, audio, library, diagnostic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sources: "Sources"
            case .appearance: "Interface"
            case .dock: "Dock"
            case .video: "Vidéo"
            case .network: "Réseau"
            case .audio: "Audio et sous-titres"
            case .library: "Bibliothèque"
            case .diagnostic: "Diagnostic"
            }
        }
        var icon: String {
            switch self {
            case .sources: "square.stack"
            case .appearance: "sparkles.tv"
            case .dock: "dock.rectangle"
            case .video: "play.rectangle"
            case .network: "wifi"
            case .audio: "speaker.wave.2"
            case .library: "books.vertical"
            case .diagnostic: "waveform.path.ecg"
            }
        }
        var subtitle: String {
            switch self {
            case .sources: "Vos abonnements et vos playlists."
            case .appearance: "Décors, aperçu des chaînes et présentation."
            case .dock: "Emplacement, thème, icônes et raccourcis."
            case .video: "Moteur de lecture et déplacements dans la vidéo."
            case .network: "Compromis entre zapping et stabilité."
            case .audio: "Pistes du média en cours et volume."
            case .library: "Historique de lecture et confidentialité."
            case .diagnostic: "État du lecteur, sans adresse ni mot de passe."
            }
        }
    }

    @ObservedObject var playback: PlaybackController
    var startAtDiagnostic = false
    /// Drawn in the window as a destination of the dock, not in a sheet.
    var inline = false
    /// Drawn above the picture during playback: glass panels that close, with
    /// the settings of the player only.
    var overPlayback = false
    var initialPage: Page? = nil
    var initialSourceEditor: SourceEditor? = nil
    /// Shows or hides the on-screen remote of the catalogue.
    var remoteVisible: Binding<Bool>? = nil
    /// Room kept under the navigation column for a dock placed there.
    var navigationFootRoom: CGFloat = 0
    /// Back and the home screen, at the top of the navigation column.
    var backTitle = "Retour"
    var goBack: (() -> Void)?
    var goHome: (() -> Void)?
    var close: () -> Void
    var sourceSaved: () -> Void = {}

    @EnvironmentObject private var library: IPTVLibrary
    @State private var draft = PlaybackSettings()
    @State private var page: Page = .appearance
    @State private var sourceEditor: SourceEditor?
    @State private var removingSource: IPTVSource?
    @State private var confirmingClear = false
    @AppStorage(FluxAppearance.glassKey) private var glass = FluxAppearance.richDefault
    @AppStorage(FluxAppearance.artworkKey) private var artwork = true
    @AppStorage(FluxAppearance.densityKey) private var density = "cinema"
    @AppStorage(LiveTVPreviewDelay.storageKey) private var livePreviewDelay: LiveTVPreviewDelay = LiveTVPreviewDelay.platformDefault
    @AppStorage(LiveTVPreviewDelay.automaticKey) private var automaticLivePreview = true
    @AppStorage(ClubInterfaceProfile.storageKey) private var clubProfile: ClubInterfaceProfile = .neoVideoClub
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.tvKey) private var tvTheme: VideoClubTheme = .neo90
    @AppStorage("fluxiptv.appearance.stage") private var stage: ProceduralCinema.Style = .orbit
    @AppStorage("fluxiptv.remoteAppearance") private var remoteAppearance: RemoteAppearance = .black
    @AppStorage(FluxDockPosition.storageKey) private var dockPosition: FluxDockPosition = .defaultValue
    @AppStorage(FluxDockTheme.storageKey) private var dockTheme: FluxDockTheme = .defaultValue
    @AppStorage(FluxDockItem.orderKey) private var dockOrder = ""
    @AppStorage(FluxDockItem.magnifyKey) private var dockMagnifies = true
    @AppStorage(DockShelf.recentsKey) private var dockRecents = true
    /// The section of the dock whose name is being changed, or that asks
    /// before it leaves with its shortcuts.
    @State private var renamingSection: String?
    @State private var sectionName = ""
    @State private var sectionNameInvalid = false
    @State private var confirmingSection: String?
    @AppStorage(DeskZone.backKey) private var backShowsZones = false
    #if os(tvOS)
    /// Page under the remote: walking the list shows each page at once.
    @FocusState private var focusedPage: Page?
    #endif

    /// Sources and the dock belong to the screen drawn in the window.
    private var pages: [Page] { Page.allCases.filter { (inline && !overPlayback) || ($0 != .sources && $0 != .dock) } }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "FLUX \(version)\(build.isEmpty ? "" : " · build \(build)")"
    }

    var body: some View {
        Group {
            if inline { inlineBody } else { sheetBody }
        }
        .onAppear {
            draft = playback.settings
            if startAtDiagnostic { page = .diagnostic }
            else if let initialPage, pages.contains(initialPage) { page = initialPage }
            else if overPlayback { page = .video }
            else if inline { page = .sources }
            if inline { sourceEditor = initialSourceEditor }
            #if os(tvOS)
            if inline {
                // A destination opens with the remote in its content: here,
                // on the page that is shown.
                let shown = page
                Task { @MainActor in await Task.yield(); focusedPage = shown }
            }
            #endif
        }
        // In the window the settings are saved as they are chosen: nothing is
        // lost by closing the panel, and nothing waits for a Save key.
        .onChange(of: draft) { _, value in
            if inline, value != playback.settings { playback.saveSettings(value, restart: false) }
        }
        #if os(tvOS)
        .onChange(of: focusedPage) { old, new in
            guard let new else { return }
            // Coming back from the content, the remote lands on the page in
            // use, not on the nearest row: that row would replace the page.
            if old == nil, new != page { focusedPage = page; return }
            if new != page { page = new; sourceEditor = nil; removingSource = nil }
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(item: $sourceEditor) { editor in
            AddSourceSheet(existing: edited(editor), onSaved: { sourceEditor = nil; sourceSaved() })
                .environmentObject(library)
        }
        #endif
        .confirmationDialog("Effacer les positions de reprise ?",
                            isPresented: Binding(get: { confirmingClear && !inline }, set: { confirmingClear = $0 })) {
            Button("Effacer", role: .destructive) { playback.clearHistory() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var sheetBody: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 740
            VStack(alignment: .leading, spacing: Desk.pt(14)) {
                HStack {
                    VStack(alignment: .leading, spacing: Desk.pt(4)) {
                        Text("Réglages").font(Desk.font(.largeTitle, .bold))
                        Text(versionLabel + "  ·  Centre de contrôle").font(Desk.font(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Fermer", action: close).buttonStyle(.bordered)
                }
                if wide {
                    HStack(alignment: .top, spacing: Desk.pt(22)) {
                        VStack(alignment: .leading, spacing: Desk.pt(8)) {
                            ForEach(pages) { destination in pageButton(destination) }
                            Spacer(minLength: 0)
                        }.frame(width: Desk.pt(230))
                        ScrollView { settingsContent.frame(maxWidth: .infinity, alignment: .leading).padding(Desk.pt(12)) }.id(page)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Desk.pt(6)) { ForEach(pages) { destination in pageButton(destination) } }
                    }
                    ScrollView { settingsContent.frame(maxWidth: .infinity, alignment: .leading).padding(Desk.pt(8)) }.id(page)
                }
                if draft != playback.settings { saveBar }
            }
            .padding(Desk.pt(24)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { if playback.playingItem == nil { FluxBackdrop() } else { Color.black } }
        }
        #if os(macOS)
        .frame(minWidth: Desk.pt(850), minHeight: Desk.pt(610))
        #endif
    }

    /// The same navigation column as the catalogue, then one panel of content.
    private var inlineBody: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: Desk.pt(18)) {
                VStack(alignment: .leading, spacing: Desk.pt(12)) {
                    navigationHeading
                    ScrollView {
                        VStack(alignment: .leading, spacing: Desk.pt(5)) {
                            ForEach(pages) { destination in
                                Button { page = destination; sourceEditor = nil; removingSource = nil } label: {
                                    LiveTVScopeLabel(title: destination.title, symbol: destination.icon,
                                                     selected: page == destination, focused: false, accent: .cyan)
                                }
                                .buttonStyle(DeskFocusStyle(radius: Desk.pt(13)))
                                #if os(tvOS)
                                .focused($focusedPage, equals: destination)
                                #endif
                                .accessibilityIdentifier("settings-page-\(destination.rawValue)")
                                #if os(tvOS) && FLUX_CATALOG_UI_TESTING
                                .background(TVCatalogControlFrameProbe(identifier: "settings-page-\(destination.rawValue)").allowsHitTesting(false))
                                #endif
                                .accessibilityValue(page == destination ? "Sélectionné" : "")
                            }
                        }.padding(.vertical, Desk.pt(3))
                    }
                    Text(versionLabel).font(Desk.font(.caption2).monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, Desk.pt(10)).padding(.bottom, Desk.pt(2))
                }
                .padding(Desk.pt(14)).frame(width: navigationWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .fluxGlass(radius: Desk.pt(25))
                .padding(.bottom, navigationFootRoom)
                #if os(tvOS)
                .focusSection()
                #endif

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Desk.pt(5)) {
                        Text(page.title).font(Desk.font(.largeTitle, .bold)).accessibilityAddTraits(.isHeader)
                        Text(page.subtitle).font(Desk.font(.callout)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Desk.pt(26)).padding(.top, Desk.pt(22)).padding(.bottom, Desk.pt(14))
                    ScrollView {
                        settingsContent
                            .frame(maxWidth: Desk.pt(960), alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Desk.pt(26)).padding(.bottom, Desk.pt(24))
                    }.id(page)
                    if playback.restartPending { restartBar.padding(Desk.pt(14)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .fluxGlass(radius: Desk.pt(27))
                #if os(tvOS)
                // Right from any page enters its content, wherever it starts.
                .focusSection()
                #endif
            }
        }
        .padding(.horizontal, Desk.pt(24))
        #if !os(tvOS)
        .controlSize(.large)
        #endif
    }

    @ViewBuilder private var navigationHeading: some View {
        #if os(macOS) || os(tvOS)
        if overPlayback {
            DeskColumnHeader(title: "RÉGLAGES", close: close)
        } else if let goBack, let goHome {
            DeskColumnHeader(title: "RÉGLAGES", backTitle: backTitle, back: goBack, home: goHome)
        } else { plainNavigationHeading }
        #else
        plainNavigationHeading
        #endif
    }
    private var plainNavigationHeading: some View {
        Label("RÉGLAGES", systemImage: "gearshape")
            .font(Desk.font(.caption, .semibold)).tracking(1.5).foregroundStyle(.secondary)
            .padding(.horizontal, Desk.pt(10)).padding(.top, Desk.pt(4))
    }

    /// The settings are saved as they are chosen. Those the engine reads when
    /// it opens a stream wait for the next one, or for this key.
    private var restartBar: some View {
        HStack(spacing: Desk.pt(12)) {
            Label("Enregistré. Ce flux garde ses réglages d’ouverture jusqu’à sa relance.", systemImage: "checkmark.circle.fill")
                .font(Desk.font(.callout)).foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Desk.pt(8))
            Button("Relancer le flux") { playback.retry(preferred: nil); close() }
                .deskKey(prominent: true)
                .accessibilityIdentifier("settings-restart")
        }
        .padding(Desk.pt(12)).modifier(SettingsCard())
    }

    private var saveBar: some View {
        let bar = HStack {
            Button("Annuler les changements") { draft = playback.settings }
            Spacer()
            if playback.playingItem != nil {
                Button("Appliquer et relancer") { playback.saveSettings(draft, restart: true); close() }.buttonStyle(.bordered)
            }
            Button("Enregistrer") { playback.saveSettings(draft, restart: false) }.buttonStyle(.borderedProminent)
        }.padding(Desk.pt(12))
        return Group {
            // Inside a glass panel the bar stays translucent.
            if inline { bar.modifier(SettingsCard()) } else { bar.fluxFrosted(radius: Desk.pt(16)) }
        }
    }

    private func pageButton(_ destination: Page) -> some View {
        Button { page = destination } label: {
            Label(destination.title, systemImage: destination.icon)
                .font(Desk.font(.body, page == destination ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Desk.pt(12))
                .background(.white.opacity(page == destination ? 0.20 : 0.035), in: RoundedRectangle(cornerRadius: Desk.pt(14)))
                .overlay(RoundedRectangle(cornerRadius: Desk.pt(14)).strokeBorder(.white.opacity(page == destination ? 0.30 : 0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func section<V: View>(_ name: String, _ detail: String, @ViewBuilder content: () -> V) -> some View {
        let card = VStack(alignment: .leading, spacing: Desk.pt(16)) {
            Text(name).font(Desk.font(.title2, .bold))
            Text(detail).font(Desk.font(.callout)).foregroundStyle(.secondary)
            Divider()
            content()
        }.font(Desk.font(.body)).padding(Desk.pt(18)).frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if inline { card.modifier(SettingsCard()) } else { card.fluxFrosted(radius: Desk.pt(20)) }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            switch page {
            case .sources:
                sourcesSettings
            case .appearance:
                appearanceSettings
            case .dock:
                dockSettings
            case .video:
                section("Lecture et décodage", "Choisissez le moteur, le décodage et les déplacements dans la vidéo.") {
                    #if os(macOS)
                    Label("AVPlayer natif · mode sécurisé", systemImage: "shield.checkered")
                    Text("VLC intégré désactivé sur Mac après le plantage OpenGL. Les flux incompatibles peuvent être ouverts dans VLC externe, sur demande.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                    #else
                    DeskChoice(title: "Moteur de lecture", options: PlaybackSettings.Engine.allCases.map { ($0, $0.title) },
                               selection: $draft.engine)
                    DeskToggle(title: "Décodage matériel VLC (si disponible)", isOn: $draft.hardware)
                    #endif
                    choice("Saut avant / arrière", value: $draft.skipSeconds, values: [5, 10, 15, 30, 60, 120], unit: "s")
                    DeskToggle(title: "Reprendre automatiquement films et épisodes", isOn: Binding(get: { playback.resumeEnabled }, set: { playback.setResumeEnabled($0) }))
                    Text("Le format et les codecs du fournisseur déterminent les possibilités de lecture.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
            case .network:
                section("Profils réseau", "Ajustez le compromis entre zapping et stabilité.") {
                    ForEach(PlaybackSettings.Profile.allCases, id: \.self) { profile in
                        Button {
                            let old = draft
                            draft = profile.settings
                            draft.engine = old.engine; draft.hardware = old.hardware; draft.skipSeconds = old.skipSeconds
                            draft.bitrateMbps = old.bitrateMbps; draft.nativeWait = old.nativeWait; draft.reconnectLive = old.reconnectLive
                        } label: { Label(profile.title, systemImage: "slider.horizontal.3") }.deskKey()
                    }
                    choice("Cache réseau", value: $draft.cacheMS, values: [250, 500, 700, 1000, 1500, 2500, 5000, 10000, 15000], unit: "ms")
                    choice("Délai d’ouverture", value: $draft.timeout, values: [5, 10, 12, 15, 20, 30, 40, 60, 90], unit: "s")
                    DeskToggle(title: "Reconnexion du direct", isOn: $draft.reconnectLive)
                    choice("Détection d’interruption", value: $draft.stallTimeout, values: [5, 10, 12, 15, 20, 30, 60, 90], unit: "s").disabled(!draft.reconnectLive)
                    choice("Tentatives", value: $draft.retries, values: Array(0...5), unit: "").disabled(!draft.reconnectLive)
                    choice("Débit maximal Apple (adaptatif)", value: $draft.bitrateMbps, values: [0, 1, 2, 4, 8, 15, 25, 50, 100], unit: "Mbit/s")
                    DeskToggle(title: "Apple : privilégier la stabilité", isOn: $draft.nativeWait)
                }
            case .audio:
                section("Pistes du flux", "Ces choix s’appliquent tout de suite au média en cours, quel que soit le moteur.") {
                    if playback.playingItem == nil {
                        Text("Lancez une vidéo pour choisir ses pistes.").font(Desk.font(.body)).foregroundStyle(.secondary)
                    } else {
                        trackList("Audio", tracks: playback.audioTracks, off: false,
                                  empty: "Ce flux n’annonce pas ses pistes audio.") { id in
                            if let id { playback.selectAudioTrack(id) }
                        }
                        trackList("Sous-titres", tracks: playback.subtitleTracks, off: playback.subtitlesCanBeOff,
                                  empty: "Ce flux n’annonce aucun sous-titre.") { playback.selectSubtitleTrack($0) }
                    }
                    #if !os(tvOS)
                    HStack {
                        Text("Volume")
                        Slider(value: Binding(get: { playback.localVolume }, set: { playback.setVolume($0) }), in: 0...1)
                        Button(playback.muted ? "Rétablir le son" : "Sourdine") { playback.toggleMute() }
                    }
                    #endif
                }
            case .library:
                section("Historique et confidentialité", "Les listes et les positions restent sur votre appareil.") {
                    Text("\(playback.history.entries.count) positions enregistrées")
                    DeskToggle(title: "Reprise automatique", isOn: Binding(get: { playback.resumeEnabled }, set: { playback.setResumeEnabled($0) }))
                    if inline && confirmingClear {
                        HStack(spacing: Desk.pt(10)) {
                            Text("Effacer les positions de reprise ?").font(Desk.font(.callout, .semibold))
                            Spacer(minLength: Desk.pt(8))
                            actionButton("Annuler", icon: "xmark") { confirmingClear = false }
                            actionButton("Effacer", icon: "trash", tint: .red) { playback.clearHistory(); confirmingClear = false }
                        }
                    } else {
                        Button("Effacer l’historique", role: .destructive) { confirmingClear = true }.deskKey()
                    }
                    Text("Les identifiants restent dans le stockage choisi pour chaque source. Les sources et les favoris ne sont pas supprimés par cette action.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
            case .diagnostic:
                section("État du lecteur", "Aucune adresse de flux ni aucun mot de passe ne sont affichés ici.") {
                    Label("Moteur : \(playback.engine.title)", systemImage: "play.rectangle")
                    Text("Reconnexions : \(playback.reconnectCount)")
                    Text(playback.attemptLabel.isEmpty ? "Aucun flux en cours" : playback.attemptLabel).foregroundStyle(.secondary)
                    if let error = playback.playbackError { Text(error).foregroundStyle(.orange) }
                    if playback.recoveryMode {
                        Label("Session VLC précédente non terminée : AVPlayer uniquement", systemImage: "shield.lefthalf.filled").foregroundStyle(.orange)
                        Button("Effacer le marqueur de récupération") { playback.resumeNormalMode() }.deskKey()
                    } else { Label("Mode normal", systemImage: "checkmark.circle") }
                    if playback.playingItem != nil { Button("Réessayer le flux") { playback.retry(); close() }.deskKey() }
                    Text("Si l’app se ferme brutalement, conservez le rapport de crash macOS (.ips) pour identifier la cause exacte.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Sources

    private func kindTitle(_ kind: IPTVSourceKind) -> String {
        switch kind {
        case .xtream: "Xtream Codes"
        case .m3uURL: "Lien M3U"
        case .m3uFile: "Fichier M3U"
        }
    }
    private func counted(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count.formatted(.number.locale(Locale(identifier: "fr_FR")))) \(count == 1 ? one : many)"
    }
    private func summary(_ source: IPTVSource, active: Bool) -> String {
        var parts = [kindTitle(source.kind)]
        guard active else { return parts[0] }
        if library.isLoading { parts.append("Chargement…") }
        else if library.browsingCatalogReady {
            parts.append(counted(library.catalogCount(.live), "chaîne", "chaînes"))
            parts.append(counted(library.catalogCount(.movie), "film", "films"))
            parts.append(counted(library.catalogCount(.series), "série", "séries"))
        }
        return parts.joined(separator: "  ·  ")
    }
    private func edited(_ editor: SourceEditor) -> IPTVSource? {
        if case .existing(let source) = editor { return source }
        return nil
    }

    /// The same width as the navigation column of the catalogue.
    private var navigationWidth: CGFloat {
        #if os(iOS)
        254
        #else
        max(FluxDockMetrics(.corner).length(count: FluxDockItem.allCases.count, vertical: false), Desk.tv(410))
        #endif
    }
    /// On a television the form of a source is a screen of its own.
    private var sourceFormCovers: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    private var sourcesSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(14)) {
            if let editor = sourceEditor, !sourceFormCovers {
                Button { sourceEditor = nil } label: {
                    Label("Toutes les sources", systemImage: "chevron.left")
                        .font(Desk.font(.callout, .semibold))
                        .padding(.horizontal, Desk.pt(15)).padding(.vertical, Desk.pt(10))
                        .background(.white.opacity(0.09), in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(DeskFocusStyle(radius: Desk.pt(22))).accessibilityIdentifier("settings-sources-back")
                AddSourceSheet(existing: edited(editor), onSaved: { sourceEditor = nil; sourceSaved() },
                               inlineClose: { sourceEditor = nil })
                    .environmentObject(library)
                    .id(editor)
                    .modifier(SettingsCard())
            } else {
                if library.sources.isEmpty {
                    Text("Aucune source pour l’instant. Ajoutez votre abonnement ou votre playlist pour retrouver vos chaînes, films et séries.")
                        .font(Desk.font(.title3)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(library.sources) { source in sourceCard(source) }
                Button { sourceEditor = .new; removingSource = nil } label: {
                    let shape = RoundedRectangle(cornerRadius: Desk.pt(20), style: .continuous)
                    HStack(spacing: Desk.pt(16)) {
                        Image(systemName: "plus").font(Desk.system(24, .semibold)).foregroundStyle(.cyan)
                            .frame(width: Desk.pt(58), height: Desk.pt(58))
                            .background(Color.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: Desk.pt(16), style: .continuous))
                        VStack(alignment: .leading, spacing: Desk.pt(4)) {
                            Text("Ajouter une source").font(Desk.font(.title3, .semibold))
                            Text("Xtream Codes, lien M3U ou fichier M3U").font(Desk.font(.callout)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Desk.pt(8))
                        Image(systemName: "chevron.right").font(Desk.font(.headline)).foregroundStyle(.secondary)
                    }
                    .padding(Desk.pt(16)).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: shape)
                    .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])).foregroundStyle(.white.opacity(0.28)).allowsHitTesting(false))
                    .contentShape(shape)
                }.buttonStyle(DeskFocusStyle(radius: Desk.pt(20))).accessibilityIdentifier("settings-add-source")
                Label("Les identifiants restent sur cet appareil, dans le stockage choisi pour chaque source.", systemImage: "lock.shield")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).padding(.top, Desk.pt(4))
            }
        }
    }

    private func sourceCard(_ source: IPTVSource) -> some View {
        let active = source.id == library.selectedSourceID
        let shape = RoundedRectangle(cornerRadius: Desk.pt(20), style: .continuous)
        return HStack(alignment: .center, spacing: Desk.pt(16)) {
            Image(systemName: source.symbol).font(Desk.system(26, .medium))
                .foregroundStyle(active ? Color.cyan : .white.opacity(0.85))
                .frame(width: Desk.pt(58), height: Desk.pt(58))
                .background((active ? Color.cyan : .white).opacity(active ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: Desk.pt(16), style: .continuous))
            VStack(alignment: .leading, spacing: Desk.pt(5)) {
                HStack(spacing: Desk.pt(10)) {
                    Text(source.name).font(Desk.font(.title3, .semibold)).lineLimit(1)
                    if active {
                        Text("ACTIVE").font(Desk.system(10, .bold)).tracking(1.2)
                            .padding(.horizontal, Desk.pt(8)).padding(.vertical, Desk.pt(4))
                            .foregroundStyle(.cyan).background(Color.cyan.opacity(0.20), in: Capsule())
                    }
                }
                Text(summary(source, active: active)).font(Desk.font(.callout)).foregroundStyle(.secondary).lineLimit(2)
                if active, let issue = library.credentialIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill").font(Desk.font(.caption)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Desk.pt(12))
            if removingSource == source {
                Text("Supprimer cette source ?").font(Desk.font(.callout, .semibold))
                actionButton("Annuler", icon: "xmark") { removingSource = nil }
                actionButton("Supprimer", icon: "trash", tint: .red) { library.removeSource(source); removingSource = nil }
            } else {
                if active {
                    actionButton("Actualiser", icon: "arrow.clockwise") { library.reloadSelected() }.disabled(library.isLoading)
                } else {
                    actionButton("Utiliser", icon: "checkmark.circle", tint: .cyan) { Task { await library.selectSource(source.id) } }
                }
                if source.kind != .m3uFile { actionButton("Modifier", icon: "pencil") { sourceEditor = .existing(source) } }
                actionButton("Supprimer", icon: "trash", iconOnly: true) { removingSource = source }
            }
        }
        .padding(Desk.pt(16)).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(active ? 0.30 : 0.20), in: shape)
        .overlay(shape.strokeBorder(active ? Color.cyan.opacity(0.55) : .white.opacity(0.09), lineWidth: active ? 1.5 : 1).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-source-\(source.id.uuidString)")
    }

    private func actionButton(_ title: String, icon: String, tint: Color? = nil, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Desk.pt(13), style: .continuous)
        return Button(action: action) {
            Group {
                if iconOnly { Image(systemName: icon) } else { Label(title, systemImage: icon) }
            }
            .font(Desk.font(.callout, .semibold)).lineLimit(1)
            .padding(.horizontal, iconOnly ? 13 : 15).padding(.vertical, Desk.pt(11))
            .foregroundStyle(tint ?? .white)
            .background((tint ?? .white).opacity(tint == nil ? 0.09 : 0.18), in: shape)
            .overlay(shape.strokeBorder((tint ?? .white).opacity(0.22), lineWidth: 1).allowsHitTesting(false))
            .contentShape(shape)
        }.buttonStyle(DeskFocusStyle(radius: Desk.pt(13))).accessibilityLabel(title)
    }

    // MARK: Dock

    private var dockSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            section("Emplacement", "Sous la colonne de navigation, le dock est compact, n’y montre que ses destinations, et les autres colonnes descendent jusqu’au bord. En bas ou en haut, il garde une bande pour lui. À gauche et à droite, il devient une colonne. Sur l’accueil, il occupe le milieu de la fenêtre.") {
                HStack(spacing: Desk.pt(12)) {
                    ForEach(FluxDockPosition.allCases) { choice in positionTile(choice) }
                }
            }
            section("Thème", "L’apparence de la plaque et des icônes.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Desk.pt(10))], spacing: Desk.pt(10)) {
                    ForEach(FluxDockTheme.allCases) { choice in themeTile(choice) }
                }
            }
            section("Icônes", "Glissez une icône dans le dock pour la déplacer, ou utilisez les flèches.") {
                let order = FluxDockItem.order(from: dockOrder)
                ForEach(Array(order.enumerated()), id: \.element) { index, item in
                    HStack(spacing: Desk.pt(14)) {
                        Image(systemName: item.symbol).font(Desk.system(18, .medium))
                            .foregroundStyle(item.tint).frame(width: Desk.pt(38), height: Desk.pt(38))
                            .background(item.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
                        Text(item.title).font(Desk.font(.body, .medium))
                        Spacer(minLength: Desk.pt(8))
                        actionButton("Avancer \(item.title)", icon: "chevron.up", iconOnly: true) {
                            dockOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: index - 1, in: order))
                        }.disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
                        actionButton("Reculer \(item.title)", icon: "chevron.down", iconOnly: true) {
                            dockOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: index + 1, in: order))
                        }.disabled(index == order.count - 1).opacity(index == order.count - 1 ? 0.35 : 1)
                    }
                }
                DeskToggle(title: "Agrandir les icônes au survol", isOn: $dockMagnifies)
                Button("Dock par défaut") {
                    dockPosition = .defaultValue; dockTheme = .defaultValue; dockOrder = ""; dockMagnifies = true
                }.deskKey()
            }
            section("Raccourcis", "Une chaîne, un film, une série, une saison ou un épisode se gardent dans le dock depuis « Favoris, listes et dock » : l’étoile d’un titre, ou un appui long sur lui. Chaque section s’y tient à part, entre deux séparateurs. Une liste de favoris y devient un dossier depuis son écran, et s’ouvre en éventail.") {
                DeskToggle(title: "Afficher la vidéo en cours et les récents", isOn: $dockRecents)
                ForEach(library.dockShelf.sections) { part in dockSectionRows(part) }
                ForEach(library.dockShelf.stacks.compactMap { library.presets.list(id: $0) }) { list in
                    HStack(spacing: Desk.pt(12)) {
                        Image(systemName: "folder.fill").font(Desk.system(16, .medium))
                            .foregroundStyle(FluxDockItem.favorites.tint).frame(width: Desk.pt(38), height: Desk.pt(38))
                            .background(FluxDockItem.favorites.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
                        VStack(alignment: .leading, spacing: Desk.pt(2)) {
                            Text(list.name).font(Desk.font(.body, .semibold)).lineLimit(1)
                            Text("Dossier · \(list.kind.frenchTitle) · \(list.itemIDs.count) \(list.itemIDs.count == 1 ? "titre" : "titres")")
                                .font(Desk.font(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Desk.pt(8))
                        actionButton("Retirer le dossier \(list.name) du dock", icon: "minus.circle", iconOnly: true) {
                            library.setDockStack(list.id, shown: false)
                        }
                    }
                }
            }
        }
    }

    /// A section of the dock: its name, which can be changed, and what it
    /// keeps for the source in use.
    @ViewBuilder private func dockSectionRows(_ part: DockSection) -> some View {
        let shown = part.shortcuts.filter { $0.sourceID == library.selectedSourceID }
        HStack(spacing: Desk.pt(12)) {
            Image(systemName: "dock.rectangle").font(Desk.system(16, .medium))
                .foregroundStyle(.white.opacity(0.85)).frame(width: Desk.pt(38), height: Desk.pt(38))
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
            if renamingSection == part.id {
                TextField("Nom de la section", text: $sectionName)
                    .textFieldStyle(.plain).font(Desk.font(.body))
                    .onSubmit { renameDockSection(part) }
                    .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(8))
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous)
                            .strokeBorder(sectionNameInvalid ? Color.orange : .white.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityIdentifier("settings-dock-section-name")
                actionButton("Enregistrer le nom", icon: "checkmark", iconOnly: true) { renameDockSection(part) }
                actionButton("Annuler", icon: "xmark", iconOnly: true) { renamingSection = nil }
            } else {
                VStack(alignment: .leading, spacing: Desk.pt(2)) {
                    Text(part.name).font(Desk.font(.body, .semibold)).lineLimit(1)
                    Text(shown.isEmpty ? "Vide : elle n’apparaît pas dans le dock." : "\(shown.count) \(shown.count == 1 ? "raccourci" : "raccourcis")")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: Desk.pt(8))
                if confirmingSection == part.id {
                    actionButton("Garder", icon: "xmark") { confirmingSection = nil }
                    actionButton("Supprimer la section", icon: "trash", tint: .red) {
                        library.deleteDockSection(part.id); confirmingSection = nil
                    }
                } else {
                    actionButton("Renommer \(part.name)", icon: "pencil", iconOnly: true) {
                        sectionName = part.name; sectionNameInvalid = false; confirmingSection = nil; renamingSection = part.id
                    }
                    if !part.isDefault {
                        actionButton("Supprimer \(part.name)", icon: "trash", iconOnly: true) { renamingSection = nil; confirmingSection = part.id }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("settings-dock-section-\(part.isDefault ? "default" : part.name)")
        ForEach(shown) { shortcut in
            HStack(spacing: Desk.pt(12)) {
                Image(systemName: FluxDockItem(kind: shortcut.kind).symbol).font(Desk.system(13, .medium))
                    .foregroundStyle(FluxDockItem(kind: shortcut.kind).tint).frame(width: Desk.pt(30), height: Desk.pt(30))
                    .background(FluxDockItem(kind: shortcut.kind).tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(9), style: .continuous))
                Text(shortcut.title).font(Desk.font(.callout)).lineLimit(1)
                Spacer(minLength: Desk.pt(8))
                actionButton("Retirer \(shortcut.title) du dock", icon: "minus.circle", iconOnly: true) {
                    // From this section only: another one may keep it.
                    _ = library.assignDock(shortcut, to: library.dockShelf.sections(holding: shortcut.id).subtracting([part.id]))
                }
            }
            .padding(.leading, Desk.pt(50))
        }
    }

    private func renameDockSection(_ part: DockSection) {
        if library.renameDockSection(part.id, name: sectionName) { renamingSection = nil; sectionNameInvalid = false }
        else { sectionNameInvalid = true }
    }

    private func positionTile(_ choice: FluxDockPosition) -> some View {
        let selected = dockPosition == choice
        let alignment: Alignment = choice == .bottom ? .bottom : choice == .corner ? .bottomLeading : choice == .top ? .top : choice == .leading ? .leading : .trailing
        let screen = RoundedRectangle(cornerRadius: Desk.pt(9), style: .continuous)
        let tile = RoundedRectangle(cornerRadius: Desk.pt(16), style: .continuous)
        return Button { dockPosition = choice } label: {
            VStack(spacing: Desk.pt(10)) {
                screen.strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                    .background(.black.opacity(0.25), in: screen)
                    .frame(width: Desk.pt(96), height: Desk.pt(60))
                    .overlay(alignment: alignment) {
                        Capsule().fill(selected ? Color.cyan : .white.opacity(0.75))
                            .frame(width: choice.isVertical ? 7 : choice.isCompact ? 24 : 44, height: choice.isVertical ? 30 : 7)
                            .padding(Desk.pt(6))
                    }
                Text(choice.title).font(Desk.font(.callout, selected ? .semibold : .regular))
            }
            .padding(.horizontal, Desk.pt(14)).padding(.vertical, Desk.pt(12)).frame(maxWidth: .infinity)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(16)))
        .accessibilityLabel("Dock \(choice.title.lowercased())").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-dock-position-\(choice.rawValue)")
    }

    private func themeTile(_ choice: FluxDockTheme) -> some View {
        let selected = dockTheme == choice
        let tile = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button { dockTheme = choice } label: {
            VStack(alignment: .leading, spacing: Desk.pt(9)) {
                HStack(spacing: Desk.pt(6)) {
                    ForEach([FluxDockItem.live, .movie, .series], id: \.self) { item in
                        FluxDockSwatch(item: item, theme: choice)
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                }
                Text(choice.title).font(Desk.font(.callout, .semibold)).lineLimit(1)
                Text(choice.subtitle).font(Desk.font(.caption2)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .padding(Desk.pt(12)).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .accessibilityLabel("Thème \(choice.title)").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-dock-theme-\(choice.rawValue)")
    }

    // MARK: Interface

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            section("Les trois espaces", "Films au cinéma, séries au vidéoclub, chaînes TV dans le salon. Chaque lieu possède son propre thème.") {
                DeskToggle(title: "Afficher les décors", isOn: Binding(get: { stage != .off }, set: { stage = $0 ? .orbit : .off }))
                Text("Les décors sont fixes. Ils disparaissent au lancement de la lecture plein écran.").font(Desk.font(.caption)).foregroundStyle(.secondary)
            }
            environmentSection(.cinema, selection: $cinemaTheme)
            environmentSection(.videoClub, selection: $seriesTheme)
            environmentSection(.livingRoom, selection: $tvTheme)
            section("Aperçu des chaînes TV", "La chaîne sélectionnée s’anime dans son écran après un délai.") {
                DeskToggle(title: "Aperçu TV automatique", isOn: $automaticLivePreview)
                DeskChoice(title: "Délai avant l’aperçu TV", options: LiveTVPreviewDelay.allCases.map { ($0, $0.title) },
                           selection: $livePreviewDelay).disabled(!automaticLivePreview)
                Text("Un seul aperçu à la fois, muet au départ. Le bouton Son active son audio ; Regarder ouvre la chaîne. Changer de chaîne, de catégorie ou d’espace arrête l’aperçu précédent.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary)
            }
            section("Présentation et commandes", "La fiche des films et séries présente la description, la boîte du titre, la lecture et les favoris.") {
                ForEach(ClubInterfaceProfile.allCases) { concept in
                    Button { clubProfile = concept } label: {
                        HStack(alignment: .center, spacing: Desk.pt(14)) {
                            Image(systemName: concept.symbol).font(Desk.font(.title2)).frame(width: Desk.pt(40))
                            VStack(alignment: .leading, spacing: Desk.pt(4)) {
                                Text(concept == .neoVideoClub ? "Néo rétro" : "Épurée").font(Desk.font(.headline))
                                Text(concept == .neoVideoClub ? "Grandes jaquettes rapprochées et décor rétro." : "Cartes aérées et commandes discrètes.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Desk.pt(8))
                            if clubProfile == concept { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                        }.padding(Desk.pt(10)).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(clubProfile == concept ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: Desk.pt(12)))
                    }
                    #if os(tvOS)
                    .buttonStyle(DeskFocusStyle(radius: Desk.pt(12)))
                    #else
                    .buttonStyle(.bordered)
                    #endif
                }
                #if os(tvOS)
                DeskToggle(title: FluxAppearance.nativeAvailable ? "Effets complets (Liquid Glass)" : "Effets complets", isOn: $glass)
                Text(FluxAppearance.richDefault
                     ? "Verre Apple sur les panneaux, flou derrière une fiche et focus animé. Coupez-les si la télécommande manque de fluidité : surfaces sombres et focus immédiat, bien plus légers à afficher."
                     : "Verre Apple sur les panneaux, flou derrière une fiche et focus animé. Coupés au départ sur cette Apple TV, dont la puce les affiche trop lentement : surfaces sombres et focus immédiat gardent la télécommande fluide.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary)
                #else
                DeskToggle(title: "Liquid Glass", isOn: $glass)
                Text(FluxAppearance.nativeAvailable ? "Effet Apple natif disponible." : "Matériau translucide système sur cette version d’OS.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                #endif
                DeskToggle(title: "Afficher les jaquettes", isOn: $artwork)
                DeskChoice(title: "Taille des cartes", options: [("cinema", "Grand écran"), ("compact", "Compacte")], selection: $density)
                #if !os(tvOS)
                #if os(macOS)
                if inline && !overPlayback {
                    DeskToggle(title: "Retour affiche d’abord les zones de l’écran", isOn: $backShowsZones)
                    Text("Au clavier ou à la télécommande, Retour encadre le haut, la colonne, le contenu, l’aperçu et le dock, et indique où mène chaque flèche : une flèche entre dans la zone voisine, OK referme, Retour une seconde fois revient à l’écran précédent. Désactivé, comme au départ, Retour revient tout de suite à l’écran précédent ; Tab passe toujours d’une zone à l’autre. Maintenu, Retour mène droit à l’accueil.")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                #endif
                if let remoteVisible { DeskToggle(title: "Afficher la télécommande virtuelle", isOn: remoteVisible) }
                Picker("Télécommande virtuelle", selection: $remoteAppearance) { Text("Noire tactile").tag(RemoteAppearance.black); Text("Aluminium").tag(RemoteAppearance.silver) }
                #endif
                Button("Apparence par défaut") {
                    glass = true; artwork = true; density = "cinema"
                    clubProfile = .neoVideoClub; stage = .orbit
                    cinemaTheme = .neo90; seriesTheme = .neo90; tvTheme = .neo90
                    livePreviewDelay = LiveTVPreviewDelay.platformDefault; automaticLivePreview = true
                }
            }
        }
    }

    private func environmentSection(_ environment: MediaEnvironment, selection: Binding<VideoClubTheme>) -> some View {
        section(environment.title + " · " + environment.kind.frenchTitle, environment.subtitle) {
            if playback.playingItem == nil {
                RoomEnvironmentPreview(environment: environment, theme: selection.wrappedValue)
                    .frame(maxWidth: Desk.pt(560))
                    .accessibilityLabel("Aperçu : " + environment.title + ", " + selection.wrappedValue.title)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Desk.pt(10))], spacing: Desk.pt(10)) {
                ForEach(VideoClubTheme.allCases, id: \.self) { candidate in themeButton(candidate, selection: selection) }
            }
        }
    }

    private func themeButton(_ candidate: VideoClubTheme, selection: Binding<VideoClubTheme>) -> some View {
        let palette = candidate.palette
        let selected = selection.wrappedValue == candidate
        return Button { selection.wrappedValue = candidate } label: {
            VStack(alignment: .leading, spacing: Desk.pt(9)) {
                HStack(spacing: Desk.pt(5)) {
                    ForEach([palette.wall, palette.wood, palette.accent, palette.second].indices, id: \.self) { i in
                        let p = [palette.wall, palette.wood, palette.accent, palette.second][i]
                        Circle().fill(Color(red: p.x, green: p.y, blue: p.z)).frame(width: Desk.pt(16), height: Desk.pt(16))
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white) }
                }
                Text(candidate.title).font(Desk.font(.callout, .semibold)).lineLimit(1)
                Text(candidate.subtitle).font(Desk.font(.caption2)).foregroundStyle(.secondary).lineLimit(2)
            }.padding(Desk.pt(12)).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(selected ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: Desk.pt(14)))
                .overlay(RoundedRectangle(cornerRadius: Desk.pt(14)).strokeBorder(Color(red: palette.accent.x, green: palette.accent.y, blue: palette.accent.z).opacity(selected ? 0.95 : 0.15), lineWidth: selected ? 2 : 1))
        }.buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .accessibilityLabel(candidate.title + (selected ? ", sélectionné" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choice(_ title: String, value: Binding<Int>, values: [Int], unit: String) -> some View {
        let choices = Array(Set(values + [value.wrappedValue])).sorted()
        return DeskChoice(title: title,
                          options: choices.map { ($0, $0 == 0 && unit == "Mbit/s" ? "Automatique" : unit.isEmpty ? "\($0)" : "\($0) \(unit)") },
                          selection: value)
    }

    /// Tracks of the media on screen; `off` adds the row that shows none.
    private func trackList(_ title: String, tracks: [PlaybackTrack], off: Bool, empty: String,
                           select: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Desk.pt(6)) {
            Text(title).font(Desk.font(.callout, .semibold)).foregroundStyle(.white.opacity(0.78))
            if tracks.isEmpty {
                Text(empty).font(Desk.font(.body)).foregroundStyle(.secondary)
            } else {
                if off { trackRow("Désactivés", selected: !tracks.contains(where: \.selected)) { select(nil) } }
                ForEach(tracks) { track in trackRow(track.title, selected: track.selected) { select(track.id) } }
            }
        }
    }

    private func trackRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous)
        return Button(action: action) {
            HStack(spacing: Desk.pt(10)) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Desk.font(.body)).foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.5))
                Text(title).font(Desk.font(.body, selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(9))
            .frame(maxWidth: Desk.pt(520), alignment: .leading)
            .background(.white.opacity(selected ? 0.14 : 0.06), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(12)))
        .accessibilityLabel(title).accessibilityValue(selected ? "Sélectionnée" : "")
    }
}

/// A translucent card inside the settings panel, which is already glass.
private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Desk.pt(20), style: .continuous)
        content
            .background(.black.opacity(0.24), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 1).allowsHitTesting(false))
    }
}

/// One destination drawn the way a dock theme draws it, for the theme tiles.
private struct FluxDockSwatch: View {
    let item: FluxDockItem
    let theme: FluxDockTheme
    var body: some View {
        let tint = item.tint
        let shape = RoundedRectangle(cornerRadius: Desk.pt(8), style: .continuous)
        let glyph = Image(systemName: item.symbol).font(Desk.system(13, .medium)).frame(width: Desk.pt(28), height: Desk.pt(28))
        switch theme {
        case .vivid:
            glyph.foregroundStyle(.white)
                .background(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: shape)
        case .neon:
            glyph.foregroundStyle(tint).shadow(color: tint.opacity(0.8), radius: Desk.pt(4))
                .background(Color(red: 0.02, green: 0.025, blue: 0.06), in: shape)
                .overlay(shape.strokeBorder(tint.opacity(0.6), lineWidth: 1))
        case .floating:
            glyph.foregroundStyle(.white.opacity(0.92)).background(.white.opacity(0.10), in: Circle())
        case .glass, .smoked:
            // The same tinted tile on a clear or a dark plate.
            glyph.foregroundStyle(.white)
                .background(LinearGradient(colors: [tint.opacity(0.52), tint.opacity(0.18)], startPoint: .top, endPoint: .bottom), in: shape)
                .background(theme == .smoked ? Color(red: 0.035, green: 0.04, blue: 0.055) : Color.white.opacity(0.10), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.30), lineWidth: 1))
        }
    }
}
