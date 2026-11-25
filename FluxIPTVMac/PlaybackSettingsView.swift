import SwiftUI
import AVKit

/// A single settings destination shared by Apple TV, iOS and Mac. Appearance
/// preferences are immediate; transport changes are drafted and applied explicitly.
/// On the Mac it is a screen of the window, reached from the dock, and it also
/// holds the sources; elsewhere it remains a sheet.
struct PlaybackSettingsView: View {
    /// What the Sources page shows in place of the saved sources.
    enum SourceEditor: Hashable { case new, existing(IPTVSource) }
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
            case .dock: "Emplacement, thème et ordre des icônes."
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
    @AppStorage(FluxAppearance.glassKey) private var glass = true
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
    @AppStorage(DeskZone.backKey) private var backShowsZones = true

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
        }
        .confirmationDialog("Effacer les positions de reprise ?",
                            isPresented: Binding(get: { confirmingClear && !inline }, set: { confirmingClear = $0 })) {
            Button("Effacer", role: .destructive) { playback.clearHistory() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var sheetBody: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 740
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Réglages").font(.largeTitle.bold())
                        Text(versionLabel + "  ·  Centre de contrôle").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Fermer", action: close).buttonStyle(.bordered)
                }
                if wide {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(pages) { destination in pageButton(destination) }
                            Spacer(minLength: 0)
                        }.frame(width: 230)
                        ScrollView { settingsContent.frame(maxWidth: .infinity, alignment: .leading).padding(12) }.id(page)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(pages) { destination in pageButton(destination) } }
                    }
                    ScrollView { settingsContent.frame(maxWidth: .infinity, alignment: .leading).padding(8) }.id(page)
                }
                if draft != playback.settings { saveBar }
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { if playback.playingItem == nil { FluxBackdrop() } else { Color.black } }
        }
        #if os(macOS)
        .frame(minWidth: 850, minHeight: 610)
        #endif
    }

    /// The same navigation column as the catalogue, then one panel of content.
    private var inlineBody: some View {
        FluxGlassGroup {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    navigationHeading
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(pages) { destination in
                                Button { page = destination; sourceEditor = nil; removingSource = nil } label: {
                                    LiveTVScopeLabel(title: destination.title, symbol: destination.icon,
                                                     selected: page == destination, focused: false, accent: .cyan)
                                }
                                .buttonStyle(FluxBareButtonStyle())
                                .accessibilityIdentifier("settings-page-\(destination.rawValue)")
                                .accessibilityValue(page == destination ? "Sélectionné" : "")
                            }
                        }.padding(.vertical, 3)
                    }
                    Text(versionLabel).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.bottom, 2)
                }
                .padding(14).frame(width: 254)
                .frame(maxHeight: .infinity, alignment: .top)
                .fluxGlass(radius: 25)
                .padding(.bottom, navigationFootRoom)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                        Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 14)
                    ScrollView {
                        settingsContent
                            .frame(maxWidth: 960, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26).padding(.bottom, 24)
                    }.id(page)
                    if draft != playback.settings { saveBar.padding(14) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .fluxGlass(radius: 27)
            }
        }
        .padding(.horizontal, 24)
        #if !os(tvOS)
        .controlSize(.large)
        #endif
    }

    @ViewBuilder private var navigationHeading: some View {
        #if os(macOS)
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
            .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 4)
    }

    private var saveBar: some View {
        let bar = HStack {
            Button("Annuler les changements") { draft = playback.settings }
            Spacer()
            if playback.playingItem != nil {
                Button("Appliquer et relancer") { playback.saveSettings(draft, restart: true); close() }.buttonStyle(.bordered)
            }
            Button("Enregistrer") { playback.saveSettings(draft, restart: false) }.buttonStyle(.borderedProminent)
        }.padding(12)
        return Group {
            // Inside a glass panel the bar stays translucent.
            if inline { bar.modifier(SettingsCard()) } else { bar.fluxFrosted(radius: 16) }
        }
    }

    private func pageButton(_ destination: Page) -> some View {
        Button { page = destination } label: {
            Label(destination.title, systemImage: destination.icon)
                .font(.body.weight(page == destination ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.white.opacity(page == destination ? 0.20 : 0.035), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(page == destination ? 0.30 : 0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func section<V: View>(_ name: String, _ detail: String, @ViewBuilder content: () -> V) -> some View {
        let card = VStack(alignment: .leading, spacing: 16) {
            Text(name).font(.title2.bold())
            Text(detail).font(.callout).foregroundStyle(.secondary)
            Divider()
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if inline { card.modifier(SettingsCard()) } else { card.fluxFrosted(radius: 20) }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    Text("VLC intégré désactivé sur Mac après le plantage OpenGL. Les flux incompatibles peuvent être ouverts dans VLC externe, sur demande.").font(.caption).foregroundStyle(.secondary)
                    #else
                    Picker("Moteur", selection: $draft.engine) { ForEach(PlaybackSettings.Engine.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Décodage matériel VLC (si disponible)", isOn: $draft.hardware)
                    #endif
                    choice("Saut avant / arrière", value: $draft.skipSeconds, values: [5, 10, 15, 30, 60, 120], unit: "s")
                    Toggle("Reprendre automatiquement films et épisodes", isOn: Binding(get: { playback.resumeEnabled }, set: { playback.setResumeEnabled($0) }))
                    Text("Le format et les codecs du fournisseur déterminent les possibilités de lecture.").font(.caption).foregroundStyle(.secondary)
                }
            case .network:
                section("Profils réseau", "Ajustez le compromis entre zapping et stabilité.") {
                    ForEach(PlaybackSettings.Profile.allCases, id: \.self) { profile in
                        Button {
                            let old = draft
                            draft = profile.settings
                            draft.engine = old.engine; draft.hardware = old.hardware; draft.skipSeconds = old.skipSeconds
                            draft.bitrateMbps = old.bitrateMbps; draft.nativeWait = old.nativeWait; draft.reconnectLive = old.reconnectLive
                        } label: { Label(profile.title, systemImage: "slider.horizontal.3") }.buttonStyle(.bordered)
                    }
                    choice("Cache réseau", value: $draft.cacheMS, values: [250, 500, 700, 1000, 1500, 2500, 5000, 10000, 15000], unit: "ms")
                    choice("Délai d’ouverture", value: $draft.timeout, values: [5, 10, 12, 15, 20, 30, 40, 60, 90], unit: "s")
                    Toggle("Reconnexion du direct", isOn: $draft.reconnectLive)
                    choice("Détection d’interruption", value: $draft.stallTimeout, values: [5, 10, 12, 15, 20, 30, 60, 90], unit: "s").disabled(!draft.reconnectLive)
                    choice("Tentatives", value: $draft.retries, values: Array(0...5), unit: "").disabled(!draft.reconnectLive)
                    choice("Débit maximal Apple (adaptatif)", value: $draft.bitrateMbps, values: [0, 1, 2, 4, 8, 15, 25, 50, 100], unit: "Mbit/s")
                    Toggle("Apple : privilégier la stabilité", isOn: $draft.nativeWait)
                }
            case .audio:
                section("Pistes du flux", "Ces choix s’appliquent au média en cours.") {
                    if playback.playingItem == nil { Text("Lancez une vidéo pour sélectionner ses pistes.").foregroundStyle(.secondary) }
                    else if playback.engine == .native {
                        ForEach(Array(playback.audioOptions().enumerated()), id: \.offset) { _, option in
                            Button("Audio : " + option.displayName) { playback.selectTrack(option, characteristic: .audible) }
                        }
                        Button("Désactiver les sous-titres") { playback.selectTrack(nil, characteristic: .legible) }
                        ForEach(Array(playback.subtitleOptions().enumerated()), id: \.offset) { _, option in
                            Button("Sous-titres : " + option.displayName) { playback.selectTrack(option, characteristic: .legible) }
                        }
                    } else { Text("Sélection des pistes VLC à compléter.").foregroundStyle(.secondary) }
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
                    Toggle("Reprise automatique", isOn: Binding(get: { playback.resumeEnabled }, set: { playback.setResumeEnabled($0) }))
                    if inline && confirmingClear {
                        HStack(spacing: 10) {
                            Text("Effacer les positions de reprise ?").font(.callout.weight(.semibold))
                            Spacer(minLength: 8)
                            actionButton("Annuler", icon: "xmark") { confirmingClear = false }
                            actionButton("Effacer", icon: "trash", tint: .red) { playback.clearHistory(); confirmingClear = false }
                        }
                    } else {
                        Button("Effacer l’historique", role: .destructive) { confirmingClear = true }
                    }
                    Text("Les identifiants restent dans le stockage choisi pour chaque source. Les sources et les favoris ne sont pas supprimés par cette action.").font(.caption).foregroundStyle(.secondary)
                }
            case .diagnostic:
                section("État du lecteur", "Aucune adresse de flux ni aucun mot de passe ne sont affichés ici.") {
                    Label("Moteur : \(playback.engine.title)", systemImage: "play.rectangle")
                    Text("Reconnexions : \(playback.reconnectCount)")
                    Text(playback.attemptLabel.isEmpty ? "Aucun flux en cours" : playback.attemptLabel).foregroundStyle(.secondary)
                    if let error = playback.playbackError { Text(error).foregroundStyle(.orange) }
                    if playback.recoveryMode {
                        Label("Session VLC précédente non terminée : AVPlayer uniquement", systemImage: "shield.lefthalf.filled").foregroundStyle(.orange)
                        Button("Effacer le marqueur de récupération") { playback.resumeNormalMode() }.buttonStyle(.bordered)
                    } else { Label("Mode normal", systemImage: "checkmark.circle") }
                    if playback.playingItem != nil { Button("Réessayer le flux") { playback.retry(); close() }.buttonStyle(.bordered) }
                    Text("Si l’app se ferme brutalement, conservez le rapport de crash macOS (.ips) pour identifier la cause exacte.").font(.caption).foregroundStyle(.secondary)
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

    private var sourcesSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let editor = sourceEditor {
                Button { sourceEditor = nil } label: {
                    Label("Toutes les sources", systemImage: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(.white.opacity(0.09), in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(FluxBareButtonStyle()).accessibilityIdentifier("settings-sources-back")
                AddSourceSheet(existing: edited(editor), onSaved: { sourceEditor = nil; sourceSaved() },
                               inlineClose: { sourceEditor = nil })
                    .environmentObject(library)
                    .id(editor)
                    .modifier(SettingsCard())
            } else {
                if library.sources.isEmpty {
                    Text("Aucune source pour l’instant. Ajoutez votre abonnement ou votre playlist pour retrouver vos chaînes, films et séries.")
                        .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(library.sources) { source in sourceCard(source) }
                Button { sourceEditor = .new; removingSource = nil } label: {
                    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(.cyan)
                            .frame(width: 58, height: 58)
                            .background(Color.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ajouter une source").font(.title3.weight(.semibold))
                            Text("Xtream Codes, lien M3U ou fichier M3U").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: shape)
                    .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])).foregroundStyle(.white.opacity(0.28)).allowsHitTesting(false))
                    .contentShape(shape)
                }.buttonStyle(FluxBareButtonStyle()).accessibilityIdentifier("settings-add-source")
                Label("Les identifiants restent sur cet appareil, dans le stockage choisi pour chaque source.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
    }

    private func sourceCard(_ source: IPTVSource) -> some View {
        let active = source.id == library.selectedSourceID
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: source.symbol).font(.system(size: 26, weight: .medium))
                .foregroundStyle(active ? Color.cyan : .white.opacity(0.85))
                .frame(width: 58, height: 58)
                .background((active ? Color.cyan : .white).opacity(active ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(source.name).font(.title3.weight(.semibold)).lineLimit(1)
                    if active {
                        Text("ACTIVE").font(.system(size: 10, weight: .bold)).tracking(1.2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(.cyan).background(Color.cyan.opacity(0.20), in: Capsule())
                    }
                }
                Text(summary(source, active: active)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if active, let issue = library.credentialIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if removingSource == source {
                Text("Supprimer cette source ?").font(.callout.weight(.semibold))
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
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(active ? 0.30 : 0.20), in: shape)
        .overlay(shape.strokeBorder(active ? Color.cyan.opacity(0.55) : .white.opacity(0.09), lineWidth: active ? 1.5 : 1).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-source-\(source.id.uuidString)")
    }

    private func actionButton(_ title: String, icon: String, tint: Color? = nil, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return Button(action: action) {
            Group {
                if iconOnly { Image(systemName: icon) } else { Label(title, systemImage: icon) }
            }
            .font(.callout.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, iconOnly ? 13 : 15).padding(.vertical, 11)
            .foregroundStyle(tint ?? .white)
            .background((tint ?? .white).opacity(tint == nil ? 0.09 : 0.18), in: shape)
            .overlay(shape.strokeBorder((tint ?? .white).opacity(0.22), lineWidth: 1).allowsHitTesting(false))
            .contentShape(shape)
        }.buttonStyle(FluxBareButtonStyle()).accessibilityLabel(title)
    }

    // MARK: Dock

    private var dockSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Emplacement", "Sous la colonne de navigation, le dock est compact et les autres colonnes descendent jusqu’au bord. En bas ou en haut, il garde une bande pour lui. À gauche et à droite, il devient une colonne. Sur l’accueil, il occupe le milieu de la fenêtre.") {
                HStack(spacing: 12) {
                    ForEach(FluxDockPosition.allCases) { choice in positionTile(choice) }
                }
            }
            section("Thème", "L’apparence de la plaque et des icônes.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(FluxDockTheme.allCases) { choice in themeTile(choice) }
                }
            }
            section("Icônes", "Glissez une icône dans le dock pour la déplacer, ou utilisez les flèches.") {
                let order = FluxDockItem.order(from: dockOrder)
                ForEach(Array(order.enumerated()), id: \.element) { index, item in
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: .medium))
                            .foregroundStyle(item.tint).frame(width: 38, height: 38)
                            .background(item.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Text(item.title).font(.body.weight(.medium))
                        Spacer(minLength: 8)
                        actionButton("Avancer \(item.title)", icon: "chevron.up", iconOnly: true) {
                            dockOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: index - 1, in: order))
                        }.disabled(index == 0).opacity(index == 0 ? 0.35 : 1)
                        actionButton("Reculer \(item.title)", icon: "chevron.down", iconOnly: true) {
                            dockOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: index + 1, in: order))
                        }.disabled(index == order.count - 1).opacity(index == order.count - 1 ? 0.35 : 1)
                    }
                }
                Toggle("Agrandir les icônes au survol", isOn: $dockMagnifies)
                Button("Dock par défaut") {
                    dockPosition = .defaultValue; dockTheme = .defaultValue; dockOrder = ""; dockMagnifies = true
                }
            }
        }
    }

    private func positionTile(_ choice: FluxDockPosition) -> some View {
        let selected = dockPosition == choice
        let alignment: Alignment = choice == .bottom ? .bottom : choice == .corner ? .bottomLeading : choice == .top ? .top : choice == .leading ? .leading : .trailing
        let screen = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let tile = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { dockPosition = choice } label: {
            VStack(spacing: 10) {
                screen.strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                    .background(.black.opacity(0.25), in: screen)
                    .frame(width: 96, height: 60)
                    .overlay(alignment: alignment) {
                        Capsule().fill(selected ? Color.cyan : .white.opacity(0.75))
                            .frame(width: choice.isVertical ? 7 : choice.isCompact ? 24 : 44, height: choice.isVertical ? 30 : 7)
                            .padding(6)
                    }
                Text(choice.title).font(.callout.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(FluxBareButtonStyle())
        .accessibilityLabel("Dock \(choice.title.lowercased())").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-dock-position-\(choice.rawValue)")
    }

    private func themeTile(_ choice: FluxDockTheme) -> some View {
        let selected = dockTheme == choice
        let tile = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { dockTheme = choice } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ForEach([FluxDockItem.live, .movie, .series], id: \.self) { item in
                        FluxDockSwatch(item: item, theme: choice)
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                }
                Text(choice.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(choice.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: tile)
            .overlay(tile.strokeBorder(Color.cyan.opacity(selected ? 0.85 : 0), lineWidth: 2).allowsHitTesting(false))
            .contentShape(tile)
        }
        .buttonStyle(FluxBareButtonStyle())
        .accessibilityLabel("Thème \(choice.title)").accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings-dock-theme-\(choice.rawValue)")
    }

    // MARK: Interface

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Les trois espaces", "Films au cinéma, séries au vidéoclub, chaînes TV dans le salon. Chaque lieu possède son propre thème.") {
                Toggle("Afficher les décors", isOn: Binding(get: { stage != .off }, set: { stage = $0 ? .orbit : .off }))
                Text("Les décors sont fixes. Ils disparaissent au lancement de la lecture plein écran.").font(.caption).foregroundStyle(.secondary)
            }
            environmentSection(.cinema, selection: $cinemaTheme)
            environmentSection(.videoClub, selection: $seriesTheme)
            environmentSection(.livingRoom, selection: $tvTheme)
            section("Aperçu des chaînes TV", "La chaîne sélectionnée s’anime dans son écran après un délai.") {
                Toggle("Aperçu TV automatique", isOn: $automaticLivePreview)
                Picker("Délai avant l’aperçu TV", selection: $livePreviewDelay) {
                    ForEach(LiveTVPreviewDelay.allCases) { delay in Text(delay.title).tag(delay) }
                }.disabled(!automaticLivePreview)
                Text("Un seul aperçu à la fois, muet au départ. Le bouton Son active son audio ; Regarder ouvre la chaîne. Changer de chaîne, de catégorie ou d’espace arrête l’aperçu précédent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Présentation et commandes", "La fiche des films et séries présente la description, la boîte du titre, la lecture et les favoris.") {
                ForEach(ClubInterfaceProfile.allCases) { concept in
                    Button { clubProfile = concept } label: {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: concept.symbol).font(.title2).frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(concept == .neoVideoClub ? "Néo rétro" : "Épurée").font(.headline)
                                Text(concept == .neoVideoClub ? "Grandes jaquettes rapprochées et décor rétro." : "Cartes aérées et commandes discrètes.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if clubProfile == concept { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(clubProfile == concept ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.bordered)
                }
                #if os(tvOS)
                Toggle(FluxAppearance.nativeAvailable ? "Liquid Glass" : "Transparence légère", isOn: $glass)
                Text(FluxAppearance.nativeAvailable
                     ? "Effet Apple natif sur les panneaux et les commandes. Désactivez-le pour revenir aux surfaces sombres, plus légères à afficher."
                     : "Décors conservés, surfaces sombres et transitions animées.").font(.caption).foregroundStyle(.secondary)
                #else
                Toggle("Liquid Glass", isOn: $glass)
                Text(FluxAppearance.nativeAvailable ? "Effet Apple natif disponible." : "Matériau translucide système sur cette version d’OS.").font(.caption).foregroundStyle(.secondary)
                #endif
                Toggle("Afficher les jaquettes", isOn: $artwork)
                Picker("Taille des cartes", selection: $density) { Text("Grand écran").tag("cinema"); Text("Compacte").tag("compact") }
                #if !os(tvOS)
                #if os(macOS)
                if inline && !overPlayback {
                    Toggle("Retour affiche d’abord les zones de l’écran", isOn: $backShowsZones)
                    Text("Au clavier ou à la télécommande, Retour encadre le haut, la colonne, le contenu, l’aperçu et le dock : les flèches choisissent, OK entre, Retour une seconde fois revient à l’écran précédent. Désactivé, Retour revient tout de suite à l’écran précédent ; Tab passe toujours d’une zone à l’autre.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                #endif
                if let remoteVisible { Toggle("Afficher la télécommande virtuelle", isOn: remoteVisible) }
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
                    .frame(maxWidth: 560)
                    .accessibilityLabel("Aperçu : " + environment.title + ", " + selection.wrappedValue.title)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(VideoClubTheme.allCases, id: \.self) { candidate in themeButton(candidate, selection: selection) }
            }
        }
    }

    private func themeButton(_ candidate: VideoClubTheme, selection: Binding<VideoClubTheme>) -> some View {
        let palette = candidate.palette
        let selected = selection.wrappedValue == candidate
        return Button { selection.wrappedValue = candidate } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    ForEach([palette.wall, palette.wood, palette.accent, palette.second].indices, id: \.self) { i in
                        let p = [palette.wall, palette.wood, palette.accent, palette.second][i]
                        Circle().fill(Color(red: p.x, green: p.y, blue: p.z)).frame(width: 16, height: 16)
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white) }
                }
                Text(candidate.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(candidate.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(selected ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(red: palette.accent.x, green: palette.accent.y, blue: palette.accent.z).opacity(selected ? 0.95 : 0.15), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain)
        .accessibilityLabel(candidate.title + (selected ? ", sélectionné" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choice(_ title: String, value: Binding<Int>, values: [Int], unit: String) -> some View {
        let choices = Array(Set(values + [value.wrappedValue])).sorted()
        return Picker(title, selection: value) {
            ForEach(choices, id: \.self) { n in Text(n == 0 && unit == "Mbit/s" ? "Automatique" : "\(n) \(unit)").tag(n) }
        }
    }
}

/// A translucent card inside the settings panel, which is already glass.
private struct SettingsCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let glyph = Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
        switch theme {
        case .vivid:
            glyph.foregroundStyle(.white)
                .background(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: shape)
        case .neon:
            glyph.foregroundStyle(tint).shadow(color: tint.opacity(0.8), radius: 4)
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
