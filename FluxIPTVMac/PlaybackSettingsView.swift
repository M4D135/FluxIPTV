import SwiftUI
import AVKit

/// A single settings destination shared by Apple TV, iOS and Mac. Appearance
/// preferences are immediate; transport changes are drafted and applied explicitly.
struct PlaybackSettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case appearance, video, network, audio, library, diagnostic
        var id: String {rawValue}
        var title: String { switch self {case .appearance:"Interface"; case .video:"Vidéo"; case .network:"Réseau"; case .audio:"Audio et sous-titres"; case .library:"Bibliothèque"; case .diagnostic:"Diagnostic"} }
        var icon: String { switch self {case .appearance:"sparkles.tv"; case .video:"play.rectangle"; case .network:"wifi"; case .audio:"speaker.wave.2"; case .library:"square.stack"; case .diagnostic:"waveform.path.ecg"} }
    }
    @ObservedObject var playback: PlaybackController
    var startAtDiagnostic = false
    var close: () -> Void
    @State private var draft = PlaybackSettings()
    @State private var page: Page = .appearance
    @State private var confirmingClear = false
    @AppStorage(FluxAppearance.glassKey) private var glass = true
    @AppStorage(FluxAppearance.artworkKey) private var artwork = true
    @AppStorage(FluxAppearance.densityKey) private var density = "cinema"
    @AppStorage("fluxiptv.appearance.caseQuality") private var caseQuality: CaseRenderQuality = .balanced
    @AppStorage(TrailerPreviewDelay.storageKey) private var trailerPreviewDelay: TrailerPreviewDelay = .five
    @AppStorage(TrailerPreviewDelay.automaticKey) private var automaticTrailerPreview = true
    @AppStorage(ClubInterfaceProfile.storageKey) private var clubProfile: ClubInterfaceProfile = .neoVideoClub
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.tvKey) private var tvTheme: VideoClubTheme = .neo90
    @AppStorage("fluxiptv.appearance.stage") private var stage: ProceduralCinema.Style = .orbit
    @AppStorage("fluxiptv.remoteAppearance") private var remoteAppearance: RemoteAppearance = .black

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 740
            VStack(alignment:.leading,spacing:14) {
                HStack { VStack(alignment:.leading,spacing:4) { Text("Réglages").font(.largeTitle.bold()); Text("FLUX 0.8.2  ·  Centre de contrôle").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Fermer",action:close).buttonStyle(.bordered) }
                if wide {
                    HStack(alignment:.top,spacing:22) {
                        VStack(alignment:.leading,spacing:8) { ForEach(Page.allCases) { destination in pageButton(destination) }; Spacer(minLength:0) }.frame(width:230)
                        ScrollView { settingsContent.frame(maxWidth:.infinity,alignment:.leading).padding(12) }.id(page)
                    }
                } else {
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:6) { ForEach(Page.allCases) { destination in pageButton(destination) } } }
                    ScrollView { settingsContent.frame(maxWidth:.infinity,alignment:.leading).padding(8) }.id(page)
                }
                if draft != playback.settings {
                    HStack { Button("Annuler les changements") {draft=playback.settings}; Spacer(); if playback.playingItem != nil {Button("Appliquer et relancer") {playback.saveSettings(draft,restart:true);close()}.buttonStyle(.bordered)}; Button("Enregistrer") {playback.saveSettings(draft,restart:false)}.buttonStyle(.borderedProminent) }.padding(12).fluxFrosted(radius:16)
                }
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background { if playback.playingItem == nil { FluxBackdrop() } else { Color.black } }
        }.onAppear {draft=playback.settings; if startAtDiagnostic {page = .diagnostic}}
        .confirmationDialog("Effacer les positions de reprise ?",isPresented:$confirmingClear) {Button("Effacer",role:.destructive){playback.clearHistory()};Button("Annuler",role:.cancel){}}
        #if os(macOS)
        .frame(minWidth:850,minHeight:610)
        #endif
    }
    private func pageButton(_ destination: Page) -> some View {
        Button {page=destination} label: {
            Label(destination.title,systemImage:destination.icon).font(.body.weight(page == destination ? .semibold : .regular)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(12)
                .background(.white.opacity(page == destination ? 0.20 : 0.035),in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(.white.opacity(page == destination ? 0.30 : 0.06),lineWidth:1))
        }.buttonStyle(.plain)
    }
    private func section<V:View>(_ name:String,_ detail:String,@ViewBuilder content:()->V)->some View {
        VStack(alignment:.leading,spacing:16) { Text(name).font(.title2.bold()); Text(detail).font(.callout).foregroundStyle(.secondary); Divider(); content() }
            .padding(18).frame(maxWidth:.infinity,alignment:.leading).fluxFrosted(radius:20)
    }
    private var settingsContent: some View {
        VStack(alignment:.leading,spacing:16) {
            switch page {
            case .appearance:
                appearanceSettings
            case .video:
                section("Lecture et décodage","Choisissez le moteur, le décodage et les déplacements dans la vidéo.") {
                    #if os(macOS)
                    Label("AVPlayer natif · mode sécurisé",systemImage:"shield.checkered")
                    Text("VLC intégré désactivé sur Mac après le plantage OpenGL. Les flux incompatibles peuvent être ouverts dans VLC externe, sur demande.").font(.caption).foregroundStyle(.secondary)
                    #else
                    Picker("Moteur",selection:$draft.engine){ForEach(PlaybackSettings.Engine.allCases,id:\.self){Text($0.title).tag($0)}}
                    Toggle("Décodage matériel VLC (si disponible)",isOn:$draft.hardware)
                    #endif
                    choice("Saut avant / arrière",value:$draft.skipSeconds,values:[5,10,15,30,60,120],unit:"s")
                    Toggle("Reprendre automatiquement films et épisodes",isOn:Binding(get:{playback.resumeEnabled},set:{playback.setResumeEnabled($0)}))
                    Text("Le format et les codecs du fournisseur déterminent les possibilités de lecture.").font(.caption).foregroundStyle(.secondary)
                }
            case .network:
                section("Profils réseau","Ajustez le compromis entre zapping et stabilité.") {
                    ForEach(PlaybackSettings.Profile.allCases,id:\.self){profile in Button{ let old=draft; draft=profile.settings; draft.engine=old.engine; draft.hardware=old.hardware; draft.skipSeconds=old.skipSeconds; draft.bitrateMbps=old.bitrateMbps; draft.nativeWait=old.nativeWait; draft.reconnectLive=old.reconnectLive } label:{Label(profile.title,systemImage:"slider.horizontal.3")}.buttonStyle(.bordered)}
                    choice("Cache réseau",value:$draft.cacheMS,values:[250,500,700,1000,1500,2500,5000,10000,15000],unit:"ms")
                    choice("Délai d’ouverture",value:$draft.timeout,values:[5,10,12,15,20,30,40,60,90],unit:"s")
                    Toggle("Reconnexion du direct",isOn:$draft.reconnectLive)
                    choice("Détection d’interruption",value:$draft.stallTimeout,values:[5,10,12,15,20,30,60,90],unit:"s").disabled(!draft.reconnectLive)
                    choice("Tentatives",value:$draft.retries,values:Array(0...5),unit:"").disabled(!draft.reconnectLive)
                    choice("Débit maximal Apple (adaptatif)",value:$draft.bitrateMbps,values:[0,1,2,4,8,15,25,50,100],unit:"Mbit/s")
                    Toggle("Apple : privilégier la stabilité",isOn:$draft.nativeWait)
                }
            case .audio:
                section("Pistes du flux","Ces choix s’appliquent au média en cours.") {
                    if playback.playingItem == nil {Text("Lancez une vidéo pour sélectionner ses pistes.").foregroundStyle(.secondary)}
                    else if playback.engine == .native {
                        ForEach(Array(playback.audioOptions().enumerated()),id:\.offset){_,option in Button("Audio : "+option.displayName){playback.selectTrack(option,characteristic:.audible)}}
                        Button("Désactiver les sous-titres"){playback.selectTrack(nil,characteristic:.legible)}
                        ForEach(Array(playback.subtitleOptions().enumerated()),id:\.offset){_,option in Button("Sous-titres : "+option.displayName){playback.selectTrack(option,characteristic:.legible)}}
                    } else {Text("Sélection des pistes VLC à compléter.").foregroundStyle(.secondary)}
                    #if !os(tvOS)
                    HStack {Text("Volume");Slider(value:Binding(get:{playback.localVolume},set:{playback.setVolume($0)}),in:0...1);Button(playback.muted ? "Rétablir le son" : "Sourdine"){playback.toggleMute()}}
                    #endif
                }
            case .library:
                section("Historique et confidentialité","Les listes et les positions restent sur votre appareil.") {
                    Text("\(playback.history.entries.count) positions enregistrées")
                    Toggle("Reprise automatique",isOn:Binding(get:{playback.resumeEnabled},set:{playback.setResumeEnabled($0)}))
                    Button("Effacer l’historique",role:.destructive){confirmingClear=true}
                    Text("Les identifiants restent dans le stockage choisi pour chaque source. Les sources et les favoris ne sont pas supprimés par cette action.").font(.caption).foregroundStyle(.secondary)
                }
            case .diagnostic:
                section("État du lecteur","Aucune adresse de flux ni aucun mot de passe ne sont affichés ici.") {
                    Label("Moteur : \(playback.engine.title)",systemImage:"play.rectangle")
                    Text("Reconnexions : \(playback.reconnectCount)")
                    Text(playback.attemptLabel.isEmpty ? "Aucun flux en cours" : playback.attemptLabel).foregroundStyle(.secondary)
                    if let error=playback.playbackError {Text(error).foregroundStyle(.orange)}
                    if playback.recoveryMode {Label("Session VLC précédente non terminée : AVPlayer uniquement",systemImage:"shield.lefthalf.filled").foregroundStyle(.orange);Button("Effacer le marqueur de récupération"){playback.resumeNormalMode()}.buttonStyle(.bordered)}
                    else {Label("Mode normal",systemImage:"checkmark.circle")}
                    if playback.playingItem != nil {Button("Réessayer le flux"){playback.retry();close()}.buttonStyle(.bordered)}
                    Text("Si l’app se ferme brutalement, conservez le rapport de crash macOS (.ips) pour identifier la cause exacte.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var appearanceSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            section("Les trois espaces","Films au cinéma, séries au vidéoclub, chaînes TV dans le salon. Chaque lieu possède son propre thème.") {
                Toggle("Afficher les décors",isOn:Binding(get:{stage != .off},set:{stage = $0 ? .orbit : .off}))
                Text("Les décors sont fixes. Ils disparaissent au lancement de la lecture plein écran.").font(.caption).foregroundStyle(.secondary)
            }
            environmentSection(.cinema,selection:$cinemaTheme)
            environmentSection(.videoClub,selection:$seriesTheme)
            environmentSection(.livingRoom,selection:$tvTheme)
            section("Verso des pochettes","Un cadre montre une image du film ou du fournisseur, puis la bande-annonce disponible.") {
                Toggle("Bande-annonce automatique dans le cadre",isOn:$automaticTrailerPreview)
                Picker("Délai avant la bande-annonce",selection:$trailerPreviewDelay) {
                    ForEach(TrailerPreviewDelay.allCases) {delay in Text(delay.title).tag(delay)}
                }.disabled(!automaticTrailerPreview)
                Text("L’aperçu automatique est muet. Sélectionnez le cadre pour ouvrir la bande-annonce en plein écran. Retour ramène au boîtier.").font(.caption).foregroundStyle(.secondary)
                Text("Les liens vers YouTube et les autres sites restent des actions à ouvrir ; seuls les flux vidéo directs sont lus dans le cadre.").font(.caption).foregroundStyle(.secondary)
            }
            section("Présentation et commandes","La disposition des cartes et des pochettes s’applique aux films et aux séries.") {
                ForEach(ClubInterfaceProfile.allCases) { concept in
                    Button {clubProfile=concept} label: {
                        HStack(alignment:.center,spacing:14) {
                            Image(systemName:concept.symbol).font(.title2).frame(width:40)
                            VStack(alignment:.leading,spacing:4) {
                                Text(concept == .neoVideoClub ? "Néo rétro" : "Épurée").font(.headline)
                                Text(concept == .neoVideoClub ? "Cadres marqués, grandes pochettes et détails rétro." : "Cartes aérées et commandes discrètes.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:8)
                            if clubProfile == concept {Image(systemName:"checkmark.circle.fill").foregroundStyle(.cyan)}
                        }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                            .background(.white.opacity(clubProfile == concept ? 0.16:0.04),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.bordered)
                }
                Toggle("Liquid Glass",isOn:$glass)
                Text(FluxAppearance.nativeAvailable ? "Effet Apple natif disponible." : "Matériau translucide système sur cette version d’OS.").font(.caption).foregroundStyle(.secondary)
                Toggle("Afficher les jaquettes",isOn:$artwork)
                Picker("Matières et pochettes 3D",selection:$caseQuality) {ForEach(CaseRenderQuality.allCases){Text($0.title).tag($0)}}
                Text("\(caseQuality.sleeveWidth) × \(caseQuality.sleeveHeight) par face · jusqu’à \(caseQuality.fps) images/s pendant la manipulation · aucun rendu continu à l’arrêt.").font(.caption).foregroundStyle(.secondary)
                Picker("Taille des cartes",selection:$density) {Text("Grand écran").tag("cinema");Text("Compacte").tag("compact")}
                #if !os(tvOS)
                Picker("Télécommande virtuelle",selection:$remoteAppearance) {Text("Noire tactile").tag(RemoteAppearance.black);Text("Aluminium").tag(RemoteAppearance.silver)}
                #endif
                Button("Apparence par défaut") {
                    glass=true;artwork=true;density="cinema"
                    clubProfile = .neoVideoClub;caseQuality = .balanced;stage = .orbit
                    cinemaTheme = .neo90;seriesTheme = .neo90;tvTheme = .neo90
                    trailerPreviewDelay = .five;automaticTrailerPreview = true
                }
            }
        }
    }
    private func environmentSection(_ environment:MediaEnvironment,selection:Binding<VideoClubTheme>)->some View {
        section(environment.title+" · "+environment.kind.frenchTitle,environment.subtitle) {
            if playback.playingItem == nil {
                RoomEnvironmentPreview(environment:environment,theme:selection.wrappedValue)
                    .frame(maxWidth:560)
                    .accessibilityLabel("Aperçu : "+environment.title+", "+selection.wrappedValue.title)
            }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:160),spacing:10)],spacing:10) {
                ForEach(VideoClubTheme.allCases,id:\.self) {candidate in themeButton(candidate,selection:selection)}
            }
        }
    }
    private func themeButton(_ candidate:VideoClubTheme,selection:Binding<VideoClubTheme>)->some View {
        let palette=candidate.palette
        let selected=selection.wrappedValue == candidate
        return Button {selection.wrappedValue=candidate} label: {
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:5) {
                    ForEach([palette.wall,palette.wood,palette.accent,palette.second].indices,id:\.self) {i in
                        let p=[palette.wall,palette.wood,palette.accent,palette.second][i]
                        Circle().fill(Color(red:p.x,green:p.y,blue:p.z)).frame(width:16,height:16)
                    }
                    Spacer(minLength:0)
                    if selected {Image(systemName:"checkmark.circle.fill").foregroundStyle(.white)}
                }
                Text(candidate.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(candidate.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .background(.white.opacity(selected ? 0.15:0.05),in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color(red:palette.accent.x,green:palette.accent.y,blue:palette.accent.z).opacity(selected ? 0.95:0.15),lineWidth:selected ? 2:1))
        }.buttonStyle(.plain)
        .accessibilityLabel(candidate.title+(selected ? ", sélectionné":""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func choice(_ title:String,value:Binding<Int>,values:[Int],unit:String)->some View {
        let choices=Array(Set(values+[value.wrappedValue])).sorted()
        return Picker(title,selection:value){ForEach(choices,id:\.self){n in Text(n == 0 && unit == "Mbit/s" ? "Automatique" : "\(n) \(unit)").tag(n)}}
    }
}
