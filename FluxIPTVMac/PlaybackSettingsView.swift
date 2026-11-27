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
        case sources, appearance, graphics, dock, remote, video, network, audio, library, diagnostic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sources: "Sources"
            case .appearance: "Interface"
            case .graphics: "Graphismes"
            case .dock: "Dock"
            case .remote: Self.remoteTitle
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
            case .graphics: "gauge.with.dots.needle.67percent"
            case .dock: "dock.rectangle"
            case .remote: Self.remoteIcon
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
            case .appearance: "Studio, couleurs des écrans et présentation des fiches."
            case .graphics: "Qualité selon l’appareil, comme dans un jeu, et chacun de ses réglages."
            case .dock: "Emplacement, thème, loupe, icônes et raccourcis."
            case .remote: Self.remoteSubtitle
            case .video: "Moteur de lecture et déplacements dans la vidéo."
            case .network: "Compromis entre zapping et stabilité."
            case .audio: "Pistes du média en cours et volume."
            case .library: "Historique de lecture et confidentialité."
            case .diagnostic: "État du lecteur, sans adresse ni mot de passe."
            }
        }
        #if os(tvOS)
        private static let remoteTitle = "Télécommande"
        private static let remoteIcon = "appletvremote.gen4"
        private static let remoteSubtitle = "Mode classique ou souris, pointeur et touche Retour."
        #else
        private static let remoteTitle = "Clavier"
        private static let remoteIcon = "keyboard"
        private static let remoteSubtitle = "Ce que fait la touche Retour dans un écran."
        #endif
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
    /// Opens the studio of the appearance over the whole window of a Mac.
    /// A television shows it over the settings, which take the remote back.
    var openStudio: ((StudioShelf) -> Void)? = nil
    /// Each new value hands the remote to the row of the page shown: a
    /// television enters the settings so from the bar, away from the screen.
    var pagesRequest = 0

    @EnvironmentObject private var library: IPTVLibrary
    @State private var draft = PlaybackSettings()
    @State private var page: Page = .appearance
    @State private var sourceEditor: SourceEditor?
    @State private var removingSource: IPTVSource?
    @State private var confirmingClear = false
    @AppStorage(FluxAppearance.glassKey) private var glass = FluxAppearance.richDefault
    @AppStorage(FluxAppearance.motionKey) private var motion = FluxAppearance.motionDefault
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
    @AppStorage(FluxDockThemeChoices.storageKey) private var spaceThemes = ""
    #if os(tvOS)
    @State private var studio: StudioShelf?
    #endif
    @AppStorage(FluxDockItem.orderKey) private var dockOrder = ""
    @AppStorage(FluxDockZoom.storageKey) private var dockZoom: FluxDockZoom = .defaultValue
    @AppStorage(FluxDockSelectionLook.storageKey) private var dockLook: FluxDockSelectionLook = .defaultValue
    @AppStorage(DockShelf.recentsKey) private var dockRecents = true
    /// The section of the dock whose name is being changed, or that asks
    /// before it leaves with its shortcuts.
    @State private var renamingSection: String?
    @State private var sectionName = ""
    @State private var sectionNameInvalid = false
    @State private var confirmingSection: String?
    /// The folder whose icon is being chosen.
    @State private var pickingSymbol: String?
    @State private var creatingDockFolder = false
    @State private var newFolderName = ""
    @State private var newFolderInvalid = false
    @AppStorage(DeskBackBehavior.storageKey) private var backBehavior: DeskBackBehavior = .defaultValue
    @AppStorage(FluxQualityPreset.automaticKey) private var automaticQuality = true
    @AppStorage(FluxPanelGlint.storageKey) private var panelGlint: FluxPanelGlint = .defaultValue
    #if os(tvOS)
    @AppStorage(FluxRemoteMode.storageKey) private var remoteMode: FluxRemoteMode = .defaultValue
    @AppStorage(FluxRemoteMode.toggleKey) private var remoteToggles = FluxRemoteMode.toggleDefault
    @AppStorage(FluxPointerSpeed.storageKey) private var pointerSpeed: FluxPointerSpeed = .defaultValue
    @AppStorage(FluxPointerSize.storageKey) private var pointerSize: FluxPointerSize = .defaultValue
    @AppStorage(FluxPointerShape.storageKey) private var pointerShape: FluxPointerShape = .defaultValue
    #endif
    #if os(tvOS)
    /// Page under the remote: walking the list shows each page at once.
    @FocusState private var focusedPage: Page?
    #endif
    #if os(macOS)
    /// The keyboard of the window, which the screen gives to the settings.
    @Environment(DeskKeys.self) private var keys: DeskKeys?
    /// The field being typed in: it takes the keys as soon as it shows.
    @FocusState private var typing: String?
    #endif

    /// Sources and the dock belong to the screen drawn in the window; the
    /// remote and the keyboard, to a screen they walk, which a phone is not.
    private var pages: [Page] {
        Page.allCases.filter { destination in
            switch destination {
            case .sources, .dock: inline && !overPlayback
            case .remote: Self.walked && inline && !overPlayback
            default: true
            }
        }
    }
    #if os(iOS)
    private static let walked = false
    private static let deviceSymbol = "iphone"
    private static let resetKeysTitle = "Par défaut"
    private static let glintCaption = "Le panneau actif s’éclaire d’un liseré discret ; avec le reflet, une lueur le traverse quand on y entre."
    #elseif os(tvOS)
    private static let walked = true
    private static let deviceSymbol = "appletv.fill"
    private static let resetKeysTitle = "Télécommande par défaut"
    private static let glintCaption = "Le panneau qui a la télécommande s’éclaire d’un liseré discret ; avec le reflet, une lueur le traverse quand on y entre, comme sur un widget de l’Apple TV."
    #else
    private static let walked = true
    private static let deviceSymbol = "desktopcomputer"
    private static let resetKeysTitle = "Clavier par défaut"
    private static let glintCaption = "Le panneau qui a le clavier s’éclaire d’un liseré discret ; avec le reflet, une lueur le traverse quand on y entre."
    #endif

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
            #if os(macOS)
            // Opened from the keyboard, the settings take it on the row of
            // the page shown, as a television gives them the remote.
            if inline, let keys {
                keys.pageID = DeskKeys.pagePrefix + page.rawValue
                if keys.entering { keys.entering = false; keys.focus = keys.pageID }
            }
            #endif
        }
        #if os(macOS)
        .onChange(of: page) { _, shown in keys?.pageID = DeskKeys.pagePrefix + shown.rawValue }
        #endif
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
        .onChange(of: pagesRequest) { _, _ in focusedPage = page }
        #endif
        #if os(tvOS)
        .fullScreenCover(item: $sourceEditor) { editor in
            AddSourceSheet(existing: edited(editor), onSaved: { sourceEditor = nil; sourceSaved() })
                .environmentObject(library)
        }
        // Closed, the studio gives the remote back to the key that opened it.
        .fullScreenCover(item: $studio) { shelf in
            AppearanceStudio(shelf: shelf, kind: library.contentKind) { studio = nil }
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
                                let show = { page = destination; sourceEditor = nil; removingSource = nil }
                                Button(action: show) {
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
                                // The keyboard of a Mac shows each page as it walks the column.
                                .deskTarget(DeskKeys.pagePrefix + destination.rawValue, follows: true, perform: show)
                            }
                        }
                        // The row under the remote or the keyboard grows a
                        // little, ring included: the room around the rows
                        // keeps it whole inside the column, which clipped
                        // its sides (David's television, 26/11).
                        .padding(.vertical, Desk.pt(4)).padding(.horizontal, Desk.pt(5))
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            settingsContent
                                .frame(maxWidth: Desk.pt(960), alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Desk.pt(26)).padding(.bottom, Desk.pt(24))
                        }
                        #if os(macOS)
                        // The control that the keyboard reaches comes into view.
                        .onAppear { keys?.scroll = { id in withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id) } } }
                        #endif
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
        #if os(macOS)
        // Where each control stands, for the arrows of the keyboard.
        .coordinateSpace(name: DeskKeys.space)
        .onPreferenceChange(DeskTargetFrames.self) { frames in keys?.update(frames) }
        #endif
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
            settingsKey("Relancer le flux", prominent: true) { playback.retry(preferred: nil); close() }
                .accessibilityIdentifier("settings-restart")
        }
        .padding(Desk.pt(12)).modifier(SettingsCard())
    }

    /// A key of the settings, which the keyboard of a Mac reaches as the pointer does.
    private func settingsKey(_ title: String, role: ButtonRole? = nil, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .deskKey(prominent: prominent)
            .deskTarget("key-\(title)", perform: action)
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
            case .graphics:
                graphicsSettings
            case .dock:
                dockSettings
            case .remote:
                remoteSettings
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
                        let apply = {
                            let old = draft
                            draft = profile.settings
                            draft.engine = old.engine; draft.hardware = old.hardware; draft.skipSeconds = old.skipSeconds
                            draft.bitrateMbps = old.bitrateMbps; draft.nativeWait = old.nativeWait; draft.reconnectLive = old.reconnectLive
                        }
                        Button(action: apply) { Label(profile.title, systemImage: "slider.horizontal.3") }
                            .deskKey()
                            .deskTarget("profile-\(profile.title)", perform: apply)
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
                            .deskKey()
                            .deskTarget("key-mute") { playback.toggleMute() }
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
                        settingsKey("Effacer l’historique", role: .destructive) { confirmingClear = true }
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
                        settingsKey("Effacer le marqueur de récupération") { playback.resumeNormalMode() }
                    } else { Label("Mode normal", systemImage: "checkmark.circle") }
                    if playback.playingItem != nil { settingsKey("Réessayer le flux") { playback.retry(); close() } }
                    Text("Si l’app se ferme brutalement, conservez le rapport de crash macOS (.ips) pour identifier la cause exacte.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
                section("Licences", "Les composants libres que contient l’application, et l’adresse de leur code.") {
                    #if !os(macOS)
                    licenceRow("VLCKit", "LGPL 2.1 · lecture des flux", "code.videolan.org/videolan/VLCKit")
                    #endif
                    #if os(tvOS) && !FLUX_APP_STORE
                    licenceRow("YouTubeKit", "MIT · bandes-annonces sur l’Apple TV", "github.com/alexeichhorn/YouTubeKit")
                    #endif
                    Text("Le code de FLUX IPTV est public. VLCKit reste un framework séparé, que sa licence permet de remplacer. Les icônes, les fonds et les thèmes sont dessinés pour l’application.")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                .deskTarget("sources-back") { sourceEditor = nil }
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
                .deskTarget("sources-add") { sourceEditor = .new; removingSource = nil }
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
            let key = source.id.uuidString
            if removingSource == source {
                Text("Supprimer cette source ?").font(Desk.font(.callout, .semibold))
                actionButton("Annuler", icon: "xmark", key: "keep-\(key)") { removingSource = nil }
                actionButton("Supprimer", icon: "trash", tint: .red, key: "remove-\(key)") { library.removeSource(source); removingSource = nil }
            } else {
                if active {
                    actionButton("Actualiser", icon: "arrow.clockwise", key: "reload-\(key)") { library.reloadSelected() }.disabled(library.isLoading)
                } else {
                    actionButton("Utiliser", icon: "checkmark.circle", tint: .cyan, key: "use-\(key)") { Task { await library.selectSource(source.id) } }
                }
                if source.kind != .m3uFile { actionButton("Modifier", icon: "pencil", key: "edit-\(key)") { sourceEditor = .existing(source) } }
                actionButton("Supprimer", icon: "trash", iconOnly: true, key: "ask-\(key)") { removingSource = source }
            }
        }
        .padding(Desk.pt(16)).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(active ? 0.30 : 0.20), in: shape)
        .overlay(shape.strokeBorder(active ? Color.cyan.opacity(0.55) : .white.opacity(0.09), lineWidth: active ? 1.5 : 1).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-source-\(source.id.uuidString)")
    }

    /// `key` names the button for the keyboard of a Mac where its title
    /// repeats on the page.
    private func actionButton(_ title: String, icon: String, tint: Color? = nil, iconOnly: Bool = false, key: String? = nil,
                              action: @escaping () -> Void) -> some View {
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
        .deskTarget("action-\(key ?? title)", perform: action)
    }

    // MARK: Dock

    private var dockSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            section("Emplacement", "Sous la colonne de navigation, le dock est compact, n’y montre que ses destinations, et les autres colonnes descendent jusqu’au bord. En bas ou en haut, il garde une bande pour lui. À gauche et à droite, il devient une colonne. Sur l’accueil, il occupe le milieu de la fenêtre.") {
                HStack(spacing: Desk.pt(12)) {
                    ForEach(FluxDockPosition.allCases) { choice in positionTile(choice) }
                }
            }
            section("Thème", "L’apparence de la plaque et des icônes, sur tous les écrans. Un écran peut garder le sien : le studio les essaie en plein écran, écran par écran.") {
                ForEach(FluxDockTheme.Family.allCases) { family in
                    Text(family.title).font(Desk.font(.headline, .semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Desk.pt(10))], spacing: Desk.pt(10)) {
                        ForEach(family.themes) { choice in themeTile(choice) }
                    }
                }
                let own = FluxDockThemeChoices.parse(spaceThemes)
                if !own.isEmpty {
                    Text("Gardent leur propre thème : " + FluxSpace.allCases.compactMap { space in own[space].map { "\(space.title) (\($0.title))" } }.joined(separator: ", ") + ".")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Desk.pt(10)) {
                    #if os(macOS) || os(tvOS)
                    settingsKey("Un thème par écran", prominent: true) { showStudio(.dock) }
                    #endif
                    if !own.isEmpty { settingsKey("Le même thème sur tous les écrans") { spaceThemes = "" } }
                }
            }
            section("Loupe et sélection", "L’icône sous la télécommande, le clavier ou le pointeur grandit, et ses voisines un peu moins.") {
                DeskChoice(title: "Agrandissement", options: FluxDockZoom.allCases.map { ($0, $0.title) }, selection: $dockZoom)
                DeskChoice(title: "Icône sélectionnée", options: FluxDockSelectionLook.allCases.map { ($0, $0.title) },
                           selection: $dockLook)
                Text(lookCaption(dockLook)).font(Desk.font(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                settingsKey("Dock par défaut") {
                    dockPosition = .defaultValue; dockTheme = .defaultValue; spaceThemes = ""; dockOrder = ""
                    dockZoom = .defaultValue; dockLook = .defaultValue
                }
            }
            section("Raccourcis et dossiers", "Une chaîne, un film, une série, une saison ou un épisode se gardent dans le dock depuis « Favoris, listes et dock » : l’étoile d’un titre, ou un appui long sur lui. Une section s’y tient à part, entre deux séparateurs. Un dossier y est une seule icône, qui s’ouvre en éventail ; il peut en contenir d’autres, et porter l’icône de votre choix. Une liste de favoris y devient aussi un dossier, depuis son écran.") {
                DeskToggle(title: "Afficher la vidéo en cours et les récents", isOn: $dockRecents)
                ForEach(library.dockShelf.tree, id: \.section.id) { node in dockSectionRows(node.section, depth: node.depth) }
                newDockFolderRow
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
                        actionButton("Retirer le dossier \(list.name) du dock", icon: "minus.circle", iconOnly: true, key: "stack-\(list.id)") {
                            library.setDockStack(list.id, shown: false)
                        }
                    }
                }
            }
        }
    }

    private func lookCaption(_ look: FluxDockSelectionLook) -> String {
        switch look {
        case .ring: "Un contour blanc, comme la sélection de l’Apple TV."
        case .halo: "Un halo de la couleur de l’icône, sans contour."
        case .lift: "L’icône se soulève au-dessus de son ombre, sans contour."
        }
    }

    /// An empty folder, made here: titles are put in it from their lists.
    @ViewBuilder private var newDockFolderRow: some View {
        if creatingDockFolder {
            HStack(spacing: Desk.pt(12)) {
                Image(systemName: "folder.badge.plus").font(Desk.system(16, .medium))
                    .foregroundStyle(FluxDockItem.favorites.tint).frame(width: Desk.pt(38), height: Desk.pt(38))
                    .background(FluxDockItem.favorites.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
                TextField("Nom du dossier", text: $newFolderName)
                    .textFieldStyle(.plain).font(Desk.font(.body))
                    .onSubmit { createDockFolder() }
                    .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(8))
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous)
                            .strokeBorder(newFolderInvalid ? Color.orange : .white.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityIdentifier("settings-dock-folder-name")
                    #if os(macOS)
                    // The name is typed at once; Escape gives up, as Annuler.
                    .focused($typing, equals: "new-folder")
                    .onAppear { Task { @MainActor in await Task.yield(); typing = "new-folder" } }
                    .onExitCommand { endFolderCreation() }
                    #endif
                    .deskTarget("field-new-folder") { typeIn("new-folder") }
                actionButton("Créer le dossier", icon: "checkmark", iconOnly: true, key: "new-folder-create") { createDockFolder() }
                actionButton("Annuler", icon: "xmark", iconOnly: true, key: "new-folder-cancel") { endFolderCreation() }
            }
        } else {
            actionButton("Créer un dossier du dock", icon: "folder.badge.plus", key: "new-folder") {
                newFolderName = ""; newFolderInvalid = false; creatingDockFolder = true
            }
            .accessibilityIdentifier("settings-dock-new-folder")
        }
    }

    private func createDockFolder() {
        if library.createDockSection(name: newFolderName, folded: true) != nil { endFolderCreation() }
        else { newFolderInvalid = true }
    }
    /// The row of the new folder closes; the keyboard returns to its key.
    private func endFolderCreation() {
        creatingDockFolder = false; newFolderInvalid = false
        returnKeys(to: "action-new-folder")
    }
    /// The keyboard of a Mac types in a field of the settings.
    private func typeIn(_ field: String) {
        #if os(macOS)
        typing = field
        #endif
    }

    /// Where a folder may go from where it is: the bar, then each folder
    /// that can take it. OK on its key moves it to the next one.
    private func moveDockFolder(_ part: DockSection) {
        let shelf = library.dockShelf
        let places: [String?] = [nil] + shelf.tree.filter { $0.section.isFolder }.map { Optional($0.section.id) }
        let start = places.firstIndex(of: part.parentID) ?? 0
        for step in 1..<max(2, places.count) {
            let place = places[(start + step) % places.count]
            if place != part.parentID, library.moveDockSection(part.id, into: place) { return }
        }
    }

    /// A section or a folder of the dock: its name, which can be changed,
    /// what it keeps for the source in use, and for a folder its place
    /// and its icon.
    @ViewBuilder private func dockSectionRows(_ part: DockSection, depth: Int = 0) -> some View {
        let shown = part.shortcuts.filter { $0.sourceID == library.selectedSourceID }
        let inside = library.dockShelf.folders(in: part.id).count
        let tint = part.isFolder ? FluxDockItem.favorites.tint : Color.white.opacity(0.85)
        HStack(spacing: Desk.pt(12)) {
            Image(systemName: part.isFolder ? (part.symbol ?? "folder.fill") : "dock.rectangle").font(Desk.system(16, .medium))
                .foregroundStyle(tint).frame(width: Desk.pt(38), height: Desk.pt(38))
                .background(tint.opacity(part.isFolder ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: Desk.pt(11), style: .continuous))
            if renamingSection == part.id {
                TextField(part.isFolder ? "Nom du dossier" : "Nom de la section", text: $sectionName)
                    .textFieldStyle(.plain).font(Desk.font(.body))
                    .onSubmit { renameDockSection(part) }
                    .padding(.horizontal, Desk.pt(12)).padding(.vertical, Desk.pt(8))
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous)
                            .strokeBorder(sectionNameInvalid ? Color.orange : .white.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityIdentifier("settings-dock-section-name")
                    #if os(macOS)
                    .focused($typing, equals: "rename-\(part.id)")
                    .onAppear { Task { @MainActor in await Task.yield(); typing = "rename-\(part.id)" } }
                    .onExitCommand { endRenaming(part) }
                    #endif
                    .deskTarget("field-rename-\(part.id)") { typeIn("rename-\(part.id)") }
                actionButton("Enregistrer le nom", icon: "checkmark", iconOnly: true, key: "rename-save-\(part.id)") { renameDockSection(part) }
                actionButton("Annuler", icon: "xmark", iconOnly: true, key: "rename-cancel-\(part.id)") { endRenaming(part) }
            } else {
                VStack(alignment: .leading, spacing: Desk.pt(2)) {
                    Text(part.name).font(Desk.font(.body, .semibold)).lineLimit(1)
                    Text(part.isFolder
                         ? "Dossier · \(shown.count) \(shown.count == 1 ? "raccourci" : "raccourcis")" + (inside > 0 ? " · \(inside) \(inside == 1 ? "dossier" : "dossiers")" : "")
                         : shown.isEmpty ? "Vide : elle n’apparaît pas dans le dock." : "\(shown.count) \(shown.count == 1 ? "raccourci" : "raccourcis")")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: Desk.pt(8))
                if confirmingSection == part.id {
                    actionButton("Garder", icon: "xmark", key: "keep-\(part.id)") { confirmingSection = nil }
                    actionButton(part.isFolder ? (inside > 0 ? "Supprimer le dossier et ceux qu’il contient" : "Supprimer le dossier") : "Supprimer la section",
                                 icon: "trash", tint: .red, key: "delete-\(part.id)") {
                        library.deleteDockSection(part.id); confirmingSection = nil
                    }
                } else {
                    if part.isFolder {
                        actionButton("Icône de \(part.name)", icon: "photo.on.rectangle.angled", iconOnly: true, key: "symbol-\(part.id)") {
                            pickingSymbol = pickingSymbol == part.id ? nil : part.id
                        }
                        actionButton("Ranger \(part.name) ailleurs", icon: "arrow.turn.down.right", iconOnly: true, key: "move-\(part.id)") { moveDockFolder(part) }
                    }
                    if !part.isDefault, part.parentID == nil {
                        // One icon that opens as a fan, or its shortcuts side by side in the bar.
                        actionButton(part.folded ? "Afficher les raccourcis de \(part.name) dans le dock" : "Faire de \(part.name) un dossier",
                                     icon: part.folded ? "rectangle.split.3x1" : "folder", iconOnly: true, key: "fold-\(part.id)") {
                            library.setDockFolded(part.id, !part.folded)
                        }
                    }
                    actionButton("Renommer \(part.name)", icon: "pencil", iconOnly: true, key: "rename-\(part.id)") {
                        sectionName = part.name; sectionNameInvalid = false; confirmingSection = nil; renamingSection = part.id
                    }
                    if !part.isDefault {
                        actionButton("Supprimer \(part.name)", icon: "trash", iconOnly: true, key: "ask-\(part.id)") { renamingSection = nil; confirmingSection = part.id }
                    }
                }
            }
        }
        .padding(.leading, Desk.pt(26) * CGFloat(depth))
        .accessibilityElement(children: .contain).accessibilityIdentifier("settings-dock-section-\(part.isDefault ? "default" : part.name)")
        if pickingSymbol == part.id, part.isFolder {
            // The icons a folder may be given, and the pictures of its titles.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Desk.pt(54)), spacing: Desk.pt(8))], alignment: .leading, spacing: Desk.pt(8)) {
                actionButton("Images de ses titres", icon: "rectangle.stack.fill", tint: part.symbol == nil ? .cyan : nil, iconOnly: true,
                             key: "symbol-\(part.id)-covers") {
                    library.setDockSymbol(part.id, nil); pickingSymbol = nil; returnKeys(to: "action-symbol-\(part.id)")
                }
                ForEach(DockSection.symbols, id: \.self) { symbol in
                    actionButton(DockSection.symbolTitle(symbol), icon: symbol, tint: part.symbol == symbol ? .cyan : nil, iconOnly: true,
                                 key: "symbol-\(part.id)-\(symbol)") {
                        library.setDockSymbol(part.id, symbol); pickingSymbol = nil; returnKeys(to: "action-symbol-\(part.id)")
                    }
                }
            }
            .padding(.leading, Desk.pt(50) + Desk.pt(26) * CGFloat(depth))
        }
        ForEach(shown) { shortcut in
            HStack(spacing: Desk.pt(12)) {
                Image(systemName: FluxDockItem(kind: shortcut.kind).symbol).font(Desk.system(13, .medium))
                    .foregroundStyle(FluxDockItem(kind: shortcut.kind).tint).frame(width: Desk.pt(30), height: Desk.pt(30))
                    .background(FluxDockItem(kind: shortcut.kind).tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(9), style: .continuous))
                Text(shortcut.title).font(Desk.font(.callout)).lineLimit(1)
                Spacer(minLength: Desk.pt(8))
                actionButton("Retirer \(shortcut.title) du dock", icon: "minus.circle", iconOnly: true, key: "unpin-\(part.id)-\(shortcut.id)") {
                    // From this section only: another one may keep it.
                    _ = library.assignDock(shortcut, to: library.dockShelf.sections(holding: shortcut.id).subtracting([part.id]))
                }
            }
            .padding(.leading, Desk.pt(50) + Desk.pt(26) * CGFloat(depth))
        }
    }

    private func renameDockSection(_ part: DockSection) {
        if library.renameDockSection(part.id, name: sectionName) { endRenaming(part) }
        else { sectionNameInvalid = true }
    }
    private func endRenaming(_ part: DockSection) {
        renamingSection = nil; sectionNameInvalid = false
        returnKeys(to: "action-rename-\(part.id)")
    }
    /// The keyboard of a Mac goes back to a key when the row it was on closes.
    private func returnKeys(to id: String) {
        #if os(macOS)
        if keys?.focus != nil { keys?.focus = id }
        #endif
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
        .deskTarget("position-\(choice.rawValue)") { dockPosition = choice }
    }

    private func themeTile(_ choice: FluxDockTheme) -> some View {
        let selected = dockTheme == choice
        let tile = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button { dockTheme = choice } label: {
            VStack(alignment: .leading, spacing: Desk.pt(9)) {
                HStack(spacing: Desk.pt(6)) {
                    let plated = choice.skinned || choice.packName != nil
                    HStack(spacing: Desk.pt(plated ? 4 : 6)) {
                        ForEach([FluxDockItem.live, .movie, .series], id: \.self) { item in
                            FluxDockSwatch(item: item, theme: choice)
                        }
                    }
                    // A skin or a pack draws its plate as well as its icons.
                    .padding(plated ? Desk.pt(5) : 0)
                    .background {
                        if let pack = choice.packName { DockPackPlate(pack: pack, radius: Desk.pt(10)) }
                        else if choice.skinned { DockSkinPlate(theme: choice, radius: Desk.pt(10)) }
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
        .deskTarget("dock-theme-\(choice.rawValue)") { dockTheme = choice }
    }

    // MARK: Graphismes

    private var recommended: FluxQualityPreset { FluxGraphics.device.recommended }
    private var currentPreset: FluxQualityPreset? {
        FluxQualityPreset.matching(glass: glass, motion: motion, backdrops: stage != .off,
                                   livePreview: automaticLivePreview, glint: panelGlint)
    }
    /// « Automatique » holds while the settings are those of the preset it chose.
    private var automaticShown: Bool { automaticQuality && currentPreset == recommended }
    private func apply(_ preset: FluxQualityPreset) {
        FluxGraphics.apply(preset)
        automaticQuality = false
    }
    private func applyAutomatic() {
        FluxGraphics.apply(recommended)
        automaticQuality = true
    }
    /// A detail changed by hand leaves « Automatique ».
    private func detail<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; automaticQuality = false })
    }
    private func qualityTile(id: String, symbol: String, title: String, subtitle: String, selected: Bool,
                             badge: String? = nil, action: @escaping () -> Void) -> some View {
        let tile = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: Desk.pt(8)) {
                HStack(spacing: Desk.pt(6)) {
                    Image(systemName: symbol).font(Desk.system(20, .semibold)).foregroundStyle(.cyan)
                    Spacer(minLength: 0)
                    if let badge {
                        Text(badge).font(Desk.system(10, .bold)).tracking(1.1).lineLimit(1)
                            .padding(.horizontal, Desk.pt(7)).padding(.vertical, Desk.pt(3))
                            .foregroundStyle(.cyan).background(Color.cyan.opacity(0.18), in: Capsule())
                    }
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                }
                Text(title).font(Desk.font(.headline, .semibold)).lineLimit(1)
                Text(subtitle).font(Desk.font(.caption)).foregroundStyle(.secondary)
                    .lineLimit(4, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Desk.pt(14)).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .accessibilityLabel("Préréglage \(title)").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-preset-\(id)")
        .deskTarget("preset-\(id)", perform: action)
    }

    /// "dans option choix qualité graphique comme dans un jeu" (David, 26/11).
    private var graphicsSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            section("Qualité graphique", "Comme dans un jeu : un préréglage règle d’un coup le verre, les mouvements, le repère du panneau actif, les fonds et l’aperçu des chaînes. Automatique suit l’appareil.") {
                Label("Appareil détecté : \(FluxGraphics.device.title). Conseillé : \(recommended.title).", systemImage: Self.deviceSymbol)
                    .font(Desk.font(.callout, .medium)).foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Desk.pt(12)) {
                    qualityTile(id: "automatic", symbol: "wand.and.stars", title: "Automatique",
                                subtitle: "Suit l’appareil : \(recommended.title) sur celui-ci.",
                                selected: automaticShown, action: applyAutomatic)
                    ForEach(FluxQualityPreset.allCases) { preset in
                        qualityTile(id: preset.rawValue, symbol: preset.symbol, title: preset.title, subtitle: preset.subtitle,
                                    selected: !automaticShown && currentPreset == preset,
                                    badge: preset == recommended ? "CONSEILLÉ" : nil) { apply(preset) }
                    }
                }
                if !automaticShown && currentPreset == nil {
                    Text("Personnalisé : les réglages plus bas ne suivent aucun préréglage.")
                        .font(Desk.font(.caption)).foregroundStyle(.secondary)
                }
            }
            section("Réglages détaillés", "Chacun se change à part ; en changer un quitte Automatique.") {
                DeskToggle(title: "Liquid Glass", isOn: detail($glass))
                #if os(tvOS)
                Text(FluxAppearance.systemGlass
                     ? "Le verre d’Apple sur les panneaux, comme sur un Mac, et le flou derrière une fiche. Coupé : des surfaces sombres, plus légères à afficher."
                     : "Des panneaux de verre comme sur un Mac. tvOS réserve son propre verre aux Apple TV 4K de 2ᵉ génération et suivantes : sur celle-ci, il est dessiné avec le flou du système. Coupé : des surfaces sombres, plus légères à afficher.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DeskToggle(title: "Mouvements de la sélection", isOn: detail($motion))
                Text(FluxAppearance.systemGlass
                     ? "Ce qui est sélectionné grandit et suit le pouce posé sur la télécommande ; les icônes du dock glissent. Coupés : la sélection s’affiche d’un coup."
                     : "Ce qui est sélectionné grandit, et les icônes du dock glissent. Coupés si ces mouvements saccadent sur cette Apple TV : la sélection s’affiche alors d’un coup.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                #else
                Text(FluxAppearance.nativeAvailable ? "Effet Apple natif disponible." : "Matériau translucide système sur cette version d’OS.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary)
                #endif
                DeskChoice(title: "Repère du panneau actif", options: FluxPanelGlint.allCases.map { ($0, $0.title) },
                           selection: detail($panelGlint))
                Text(Self.glintCaption).font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DeskToggle(title: "Afficher les fonds", isOn: detail(Binding(get: { stage != .off }, set: { stage = $0 ? .orbit : .off })))
                Text("Les images dessinées derrière les écrans, choisies dans le studio. Elles disparaissent pendant la lecture plein écran.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            section("Aperçu des chaînes TV", "La chaîne sélectionnée s’anime dans son écran après un délai.") {
                DeskToggle(title: "Aperçu TV automatique", isOn: detail($automaticLivePreview))
                DeskChoice(title: "Délai avant l’aperçu TV", options: LiveTVPreviewDelay.allCases.map { ($0, $0.title) },
                           selection: $livePreviewDelay).disabled(!automaticLivePreview)
                Text("Un seul aperçu à la fois, muet au départ. Le bouton Son active son audio ; Regarder ouvre la chaîne. Changer de chaîne, de catégorie ou d’espace arrête l’aperçu précédent.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                settingsKey("Graphismes par défaut") {
                    applyAutomatic(); livePreviewDelay = LiveTVPreviewDelay.platformDefault
                }
            }
        }
    }

    // MARK: Télécommande et clavier

    private var remoteSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            #if os(tvOS)
            // "faut pouvoir choisir mode classique ou mode souris, soit dans
            // option soit un système facile pour basculer, voire les deux" (David, 26/11).
            section("Mode de la télécommande", "Classique : un glissement sur le pavé tactile va d’un élément au suivant. Souris : un pointeur suit le pouce, et un clic appuie sur ce qu’il survole.") {
                HStack(alignment: .top, spacing: Desk.pt(12)) {
                    ForEach(FluxRemoteMode.allCases) { mode in remoteModeTile(mode) }
                }
                DeskToggle(title: "Maintenir Lecture/Pause pour changer de mode", isOn: $remoteToggles)
                Text("Hors de la lecture d’une vidéo, un appui long sur Lecture/Pause passe d’un mode à l’autre, où que vous soyez, et une bulle le confirme. Pendant une vidéo, la télécommande reste classique.")
                    .font(Desk.font(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            section("Pointeur", "Son allure en mode souris. Un appui sur un bord du pavé déplace toujours la sélection, comme une flèche.") {
                DeskChoice(title: "Vitesse", options: FluxPointerSpeed.allCases.map { ($0, $0.title) }, selection: $pointerSpeed)
                DeskChoice(title: "Taille", options: FluxPointerSize.allCases.map { ($0, $0.title) }, selection: $pointerSize)
                DeskChoice(title: "Forme", options: FluxPointerShape.allCases.map { ($0, $0.title) }, selection: $pointerShape)
            }
            #endif
            section("Touche Retour", "Ce que fait Retour dans un écran de films, de séries ou de chaînes.") {
                DeskChoice(title: "Retour dans un écran", options: DeskBackBehavior.offered.map { ($0, $0.title) },
                           selection: $backBehavior)
                Text(backCaption(backBehavior)).font(Desk.font(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingsKey(Self.resetKeysTitle) {
                    backBehavior = .defaultValue
                    #if os(tvOS)
                    remoteMode = .defaultValue; remoteToggles = FluxRemoteMode.toggleDefault
                    pointerSpeed = .defaultValue; pointerSize = .defaultValue; pointerShape = .defaultValue
                    #endif
                }
            }
        }
    }

    private func backCaption(_ behavior: DeskBackBehavior) -> String {
        switch behavior {
        case .bar: "Depuis une grille ou une liste, Retour mène d’abord au bouton Retour de la barre du haut, d’où l’accueil et le dock sont à portée. Un second Retour quitte l’écran."
        case .leave: "Retour revient tout de suite à l’écran précédent, comme avant la 0.9.4."
        case .plan: "Retour encadre le haut, la colonne, le contenu, l’aperçu et le dock, et montre où mène chaque flèche : une flèche entre dans la partie voisine, OK referme, un second Retour quitte l’écran."
        }
    }

    #if os(tvOS)
    private func remoteModeTile(_ mode: FluxRemoteMode) -> some View {
        let selected = remoteMode == mode
        let tile = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button { remoteMode = mode } label: {
            HStack(alignment: .top, spacing: Desk.pt(14)) {
                Image(systemName: mode.symbol).font(Desk.system(26, .semibold)).foregroundStyle(.cyan)
                    .frame(width: Desk.pt(40))
                VStack(alignment: .leading, spacing: Desk.pt(4)) {
                    Text(mode.title).font(Desk.font(.headline, .semibold))
                    Text(mode.subtitle).font(Desk.font(.caption)).foregroundStyle(.secondary)
                        .lineLimit(3, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
            }
            .padding(Desk.pt(14)).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .accessibilityLabel("Mode \(mode.title.lowercased())").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-remote-mode-\(mode.rawValue)")
    }
    #endif

    // MARK: Interface

    #if os(macOS) || os(tvOS)
    private func showStudio(_ shelf: StudioShelf) {
        #if os(tvOS)
        studio = shelf
        #else
        openStudio?(shelf)
        #endif
    }
    private func studioTile(_ shelf: StudioShelf, line: String) -> some View {
        let tile = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button { showStudio(shelf) } label: {
            HStack(spacing: Desk.pt(14)) {
                Image(systemName: shelf.symbol).font(Desk.system(26, .semibold)).foregroundStyle(.cyan)
                    .frame(width: Desk.pt(44))
                VStack(alignment: .leading, spacing: Desk.pt(4)) {
                    Text(shelf.title).font(Desk.font(.headline, .semibold))
                    Text(line).font(Desk.font(.caption)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: Desk.pt(8))
                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
            }
            .padding(Desk.pt(14)).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: tile)
            .overlay(tile.strokeBorder(.white.opacity(0.12), lineWidth: 1).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .accessibilityLabel("Studio d’apparence, \(shelf.title.lowercased())")
        .accessibilityIdentifier("settings-studio-\(shelf.rawValue)")
        .deskTarget("studio-\(shelf.rawValue)") { showStudio(shelf) }
    }
    #endif

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: Desk.pt(16)) {
            #if os(macOS) || os(tvOS)
            section("Studio d’apparence", "Les fonds de chaque écran, seuls ou en diaporama, et le thème du dock, écran par écran. Tout s’essaie en plein écran avant d’être gardé.") {
                HStack(spacing: Desk.pt(12)) {
                    studioTile(.backdrops, line: "\(FluxBackdropLibrary.art.count) fonds dessinés, diaporama")
                    studioTile(.dock, line: "\(FluxDockTheme.allCases.count) thèmes : d’aujourd’hui, rétro et dessinés")
                }
            }
            #endif
            environmentSection(.cinema, selection: $cinemaTheme)
            environmentSection(.videoClub, selection: $seriesTheme)
            environmentSection(.livingRoom, selection: $tvTheme)
            section("Présentation et commandes", "La fiche des films et séries présente la description, la boîte du titre, la lecture et les favoris.") {
                ForEach(ClubInterfaceProfile.allCases) { concept in
                    Button { clubProfile = concept } label: {
                        HStack(alignment: .center, spacing: Desk.pt(14)) {
                            Image(systemName: concept.symbol).font(Desk.font(.title2)).frame(width: Desk.pt(40))
                            VStack(alignment: .leading, spacing: Desk.pt(4)) {
                                Text(concept == .neoVideoClub ? "Néo rétro" : "Épurée").font(Desk.font(.headline))
                                Text(concept == .neoVideoClub ? "Grandes jaquettes rapprochées." : "Cartes aérées et commandes discrètes.").font(Desk.font(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Desk.pt(8))
                            if clubProfile == concept { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                        }.padding(Desk.pt(10)).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(clubProfile == concept ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: Desk.pt(12)))
                    }
                    // The same card on a Mac as on a television.
                    #if os(iOS)
                    .buttonStyle(.bordered)
                    #else
                    .buttonStyle(DeskFocusStyle(radius: Desk.pt(12)))
                    #endif
                    .deskTarget("profile-\(concept.rawValue)") { clubProfile = concept }
                }
                DeskToggle(title: "Afficher les jaquettes", isOn: $artwork)
                DeskChoice(title: "Taille des cartes", options: [("cinema", "Grand écran"), ("compact", "Compacte")], selection: $density)
                #if !os(tvOS)
                if let remoteVisible { DeskToggle(title: "Afficher la télécommande virtuelle", isOn: remoteVisible) }
                DeskChoice(title: "Télécommande virtuelle", options: [(RemoteAppearance.black, "Noire tactile"), (RemoteAppearance.silver, "Aluminium")],
                           selection: $remoteAppearance)
                #endif
                // The quality of the display has its own page: Graphismes.
                settingsKey("Apparence par défaut") {
                    artwork = true; density = "cinema"; clubProfile = .neoVideoClub
                    cinemaTheme = .neo90; seriesTheme = .neo90; tvTheme = .neo90
                }
            }
        }
    }

    private func environmentSection(_ environment: MediaEnvironment, selection: Binding<VideoClubTheme>) -> some View {
        section("Couleurs · " + environment.kind.frenchTitle, "Les repères de l’écran " + environment.kind.frenchTitle + " et son fond uni.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Desk.pt(10))], spacing: Desk.pt(10)) {
                ForEach(VideoClubTheme.allCases, id: \.self) { candidate in themeButton(candidate, selection: selection, place: environment.title) }
            }
        }
    }

    private func themeButton(_ candidate: VideoClubTheme, selection: Binding<VideoClubTheme>, place: String) -> some View {
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
        .deskTarget("theme-\(place)-\(candidate.rawValue)") { selection.wrappedValue = candidate }
    }

    private func licenceRow(_ name: String, _ detail: String, _ source: String) -> some View {
        VStack(alignment: .leading, spacing: Desk.pt(3)) {
            HStack(spacing: Desk.pt(10)) {
                Text(name).font(Desk.font(.body, .semibold))
                Text(detail).font(Desk.font(.callout)).foregroundStyle(.secondary)
            }
            Text(source).font(Desk.font(.caption).monospaced()).foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
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
                if off { trackRow("Désactivés", list: title, selected: !tracks.contains(where: \.selected)) { select(nil) } }
                ForEach(tracks) { track in trackRow(track.title, list: title, selected: track.selected) { select(track.id) } }
            }
        }
    }

    private func trackRow(_ title: String, list: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
        .deskTarget("track-\(list)-\(title)", perform: action)
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
        default:
            // A skin draws its own tile, as its dock does; pixels keep their
            // square on a side of 32.
            let side = Desk.pt(theme.pixelated ? 32 : 28)
            Group {
                if let pack = theme.packName {
                    DockPackDestination(theme: theme, pack: pack, item: item, selected: false, focused: false, side: side)
                } else {
                    DockSkinDestination(item: item, theme: theme, selected: false, focused: false, side: side, glyph: Desk.pt(13))
                }
            }
            .frame(width: side, height: side)
        }
    }
}
