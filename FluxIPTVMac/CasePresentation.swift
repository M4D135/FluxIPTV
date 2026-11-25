import SwiftUI
import AVKit
import QuartzCore
#if os(macOS)
import AppKit
#endif
#if os(tvOS)
import CoreImage
import UIKit
#endif

struct CaseRemoteEvent: Equatable {
    let action: RemoteAction
    let token=UUID()
}
struct CasePadSignal: Equatable {
    let input: CasePadInput
    let token=UUID()
}

/// Full-window object inspector. The physical covers stay intact; commands
/// live in a separate glass bar. One SceneKit surface contains at most five sleeves.
struct CasePresentation: View {
    let item: IPTVItem
    let details: IPTVDetails
    let position:Int
    let count:Int
    @Binding var yaw:Double
    @Binding var pitch:Double
    let previous:()->Void
    let next:()->Void
    let close:()->Void
    let play:()->Void
    let playEpisode:(IPTVItem,[IPTVSeason])->Void
    let favorite:()->Void
    let isFavorite:Bool
    let startEpisodes:Bool
    let remoteEvent:CaseRemoteEvent?
    let padSignal:CasePadSignal?
    var previousItem:IPTVItem? = nil
    var nextItem:IPTVItem? = nil
    var previousFarItem:IPTVItem? = nil
    var nextFarItem:IPTVItem? = nil
    var jumpBy:((Int)->Void)? = nil
    var selectedTheme:VideoClubTheme? = nil
    var concept:ClubInterfaceProfile = .neoVideoClub
    var suspended = false
    var onTrailerPresentation: (Bool) -> Void = { _ in }
    @EnvironmentObject private var library:IPTVLibrary
    @EnvironmentObject private var playback:PlaybackController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TrailerPreviewDelay.storageKey) private var previewDelay:TrailerPreviewDelay = .five
    @AppStorage(TrailerPreviewDelay.automaticKey) private var automaticPreview = true
    @StateObject private var mediaPreview=CaseMediaPreviewController()
    @StateObject private var descriptions=CaseDescriptionModel()
    @State private var descriptionID=""
    @State private var descriptionActive=false
    @State private var inspectorNavigation=CaseInspectorNavigation()
    @State private var selectingSeason=false
    @State private var selectingEpisode=false
    @StateObject private var bridge=CaseHitBridge()
    @State private var page:CaseFaceLayout.Page = .details
    @State private var focused:CaseFaceLayout.Action?
    @State private var dragging=false
    @State private var padRotation:CasePadRotation?
    @State private var dragYaw = 0.0
    @State private var dragPitch = 0.0
    @State private var manipulating=false
    @State private var commandsActive=false
    @State private var startingPlayback=false
    @State private var handoffTask:Task<Void,Never>?
    @State private var handoffToken=UUID()
    @State private var trailerFullscreen=false
    @State private var lastPreviewProjection:CasePreviewProjection?
    @State private var qrURL:URL?
    @State private var seasons:[IPTVSeason]=[]
    @State private var seasonIndex = 0
    @State private var episodePage = 0
    @State private var selectedEpisodeIndex = 0
    @State private var seasonLoading = false
    @State private var seasonError = false
    @State private var loadedSeriesID:String?
    @State private var reloadToken=UUID()
    #if os(macOS)
    @FocusState private var keyboardSurfaceFocused:Bool
    #endif
    #if os(tvOS)
    @FocusState private var surfaceFocused:Bool
    @FocusState private var nativeCommandFocus:CaseFaceLayout.Action?
    @State private var pendingDirection:Task<Void,Never>?
    @State private var lastPadTime:TimeInterval = 0
    #endif
    private var selectedSeason:IPTVSeason? {seasons.indices.contains(seasonIndex) ? seasons[seasonIndex]:nil}
    private var episodeCount:Int {selectedSeason?.episodes.count ?? 0}
    private var pageCount:Int {max(1,(episodeCount+CaseFaceLayout.episodePageSize-1)/CaseFaceLayout.episodePageSize)}
    private var visibleEpisodes:[IPTVItem] {
        guard loadedSeriesID == item.id,let entries=selectedSeason?.episodes else{return []}
        let start=min(entries.count,max(0,episodePage)*CaseFaceLayout.episodePageSize)
        return Array(entries[start..<min(entries.count,start+CaseFaceLayout.episodePageSize)])
    }
    private var printData:CasePrintData {
        var status:String?
        if seasonLoading {status="Chargement des épisodes…"}
        else if seasonError {status="Épisodes indisponibles"}
        else if page == .episodes && loadedSeriesID == item.id && episodeCount == 0 {status="Aucun épisode dans cette saison"}
        var data=CasePrintData(page:page,episodes:visibleEpisodes,season:selectedSeason?.number,pageIndex:episodePage,pageCount:pageCount,status:status,retry:seasonError,favorite:isFavorite,position:position,count:count,trailerAvailable:details.trailerURL != nil,episodeProgress:Dictionary(visibleEpisodes.compactMap { episode in playback.history.entries[episode.id].map{(episode.id,$0.fraction)} },uniquingKeysWith:{first,_ in first}))
        let loaded=descriptionID == descriptionKey
        data.descriptionText=loaded ? descriptions.text:(descriptions.source == .iptv ? details.synopsis:"")
        data.descriptionSource=descriptions.source.title
        data.descriptionStatus=loaded ? descriptions.status:(descriptions.source == .iptv ? nil:"Chargement de la description…")
        data.descriptionSourceURL=loaded ? descriptions.sourceURL:nil
        data.previewStatus=mediaPreview.statusText
        data.seasonNumbers=seasons.map(\.number)
        data.selectedSeasonIndex=seasonIndex
        data.seasonSelectionVisible=item.isSeriesCollection && !collectorOpen
        return data
    }
    private var collectorOpen:Bool {item.isSeriesCollection && page == .episodes}
    private var currentFace:CaseFaceLayout.Page? {CaseFaceLayout.face(yaw:yaw,pitch:pitch).map{$0 == .front ? (collectorOpen ? CaseFaceLayout.Page.episodes:.front):.details}}
    private var descriptionKey:String {"\(item.id)|\(item.name)|\(details.year ?? "")|\(descriptions.source.rawValue)|\(details.synopsis ?? "")"}
    private var acceptsRotation:Bool {
        guard !trailerFullscreen,qrURL == nil,!commandsActive,!descriptionActive,!startingPlayback,scenePhase == .active else{return false}
        #if os(tvOS)
        // Ordinary Siri Remote swipes navigate; the visible Manipuler action
        // explicitly grants the continuous pan to the 3D object.
        return manipulating
        #else
        return true
        #endif
    }
    // A selected case owns its session throughout rotation. Only its rendered
    // face pauses playback; a gesture or the target angle never destroys it.
    private var previewActive:Bool {!suspended && !startingPlayback && qrURL == nil && scenePhase == .active}
    private var previewVisible:Bool {previewActive && (trailerFullscreen || bridge.previewBackFacing)}
    private var youtubeViewportEligible:Bool {previewVisible && (trailerFullscreen || bridge.previewProjection?.isAutoplayEligible == true)}
    private var previewKey:String {"\(item.id)|\(previewActive)|\(automaticPreview)|\(previewDelay.rawValue)|\(details.trailerURL?.absoluteString ?? "")|\(item.backdropURL?.absoluteString ?? "")"}
    private let youtubeSurfaceSize=CGSize(width:480,height:270)
    private func regions(_ face:CaseFaceLayout.Page)->[CaseFaceLayout.Region] {
        CaseFaceLayout.regions(face,series:item.isSeriesCollection,trailer:details.trailerURL != nil,episodeCount:visibleEpisodes.count,retry:seasonError).filter { region in
            if case .episode = region.action {return true};return false
        }
    }
    var body:some View {
        ZStack {
            if trailerFullscreen {
                // Retain the actual player while its native host changes size.
                // No live 3D rendering or duplicate audio behind fullscreen.
                CaseTrailerView(preview:mediaPreview,remoteEvent:remoteEvent,close:closeTrailer)
            } else {
                VStack(spacing:4) {
                    inspectionPlayButton.padding(.top,5)
                    modelViewport
                        .frame(maxWidth:.infinity,maxHeight:.infinity)
                        .layoutPriority(1)
                    externalControls
                }.padding(.bottom,8)
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .onChange(of:remoteEvent){_,event in if let event {handle(event.action)}}
        .onChange(of:padSignal){_,signal in if let signal {handlePad(signal.input)}}
        .task(id:previewKey) {
            let filmURL:URL? = previewActive && item.kind == .movie ? (try? library.playbackURLs(for:item))?.first:nil
            mediaPreview.setBackFacing(previewVisible)
            mediaPreview.update(item:item,details:details,filmURL:filmURL,backVisible:previewActive,automatic:automaticPreview,delay:previewDelay)
            mediaPreview.setYouTubeViewportEligible(youtubeViewportEligible)
            if trailerFullscreen && previewActive {mediaPreview.activateTrailer()}
        }
        .onDisappear{cancelHandoff();mediaPreview.stop();onTrailerPresentation(false)}
        .onChange(of:trailerFullscreen){_,visible in onTrailerPresentation(visible)}
        .onChange(of:previewVisible){_,visible in mediaPreview.setBackFacing(visible)}
        .onChange(of:youtubeViewportEligible){_,eligible in mediaPreview.setYouTubeViewportEligible(eligible)}
        .onChange(of:bridge.previewProjection){_,projection in if let projection {lastPreviewProjection=projection}}
        .onAppear {
            mediaPreview.setBackFacing(previewVisible)
            mediaPreview.setYouTubeViewportEligible(youtubeViewportEligible)
            if let projection=bridge.previewProjection {lastPreviewProjection=projection}
        }
        .onChange(of:scenePhase){_,phase in
            if phase != .active {cancelHandoff();padRotation=nil;dragging=false;manipulating=false;mediaPreview.stop()}
        }
        .task(id:descriptionKey) {
            let requested=descriptionKey
            await descriptions.load(item:item,details:details)
            guard !Task.isCancelled,requested == descriptionKey else{return}
            descriptionID=requested
        }

        #if os(macOS)
        .focusable().focused($keyboardSurfaceFocused).focusEffectDisabled()
        .onAppear {keyboardSurfaceFocused=true}
        #endif
        #if os(tvOS)
        .onDisappear{pendingDirection?.cancel()}
        .onChange(of:nativeCommandFocus){_,action in if let action {focused=action;commandsActive=true}}
        #endif
        .onChange(of:item.id){_,_ in
            // Preserve the orientation, but never reuse the previous series data.
            cancelHandoff();trailerFullscreen=false;qrURL=nil;loadedSeriesID=nil;seasons=[];seasonIndex=0;episodePage=0;selectedEpisodeIndex=0;seasonError=false;seasonLoading=false
            page = .details;commandsActive=false;manipulating=false;descriptionActive=false;descriptions.reset();descriptionID=""
            focused=nil;padRotation=nil;dragging=false;lastPreviewProjection=nil
            inspectorNavigation=CaseInspectorNavigation();selectingSeason=false;selectingEpisode=false
            #if os(tvOS)
            nativeCommandFocus=nil;surfaceFocused=true
            #endif
        }
        .onAppear {if startEpisodes && item.isSeriesCollection {page = .episodes;selectingEpisode=true;orient(back:false)}}
        .task(id:"\(item.id)|\(reloadToken)") {await fetchEpisodesIfNeeded()}
        #if os(tvOS)
        .sheet(isPresented:Binding(get:{qrURL != nil},set:{if !$0{qrURL=nil}})) {if let qrURL {CaseQRView(url:qrURL,close:{self.qrURL=nil})}}
        #endif
    }
    private var primaryActions:[CaseFaceLayout.Action] {
        [item.isSeriesCollection ? (collectorOpen ? .details:.episodes):.play,.favorite,.flip,.rotate,.close]
    }
    private var secondaryActions:[CaseFaceLayout.Action] {
        if page == .episodes && item.isSeriesCollection {
            var actions:[CaseFaceLayout.Action]=[.previousPage,.nextPage]
            if details.trailerURL != nil {actions.insert(.trailer,at:0)}
            if seasonError {actions.append(.retry)}
            return actions
        }
        guard currentFace != .front, currentFace != nil else{return []}
        var actions:[CaseFaceLayout.Action]=details.trailerURL != nil ? [.trailer] : []
        actions += [.description,.wikipedia,.allocine]
        return actions
    }
    private var commandActions:[CaseFaceLayout.Action] {primaryActions+secondaryActions}
    private func commandLabel(_ action:CaseFaceLayout.Action)->(String,String) {
        switch action {
        case .play:return (playback.history.entries[item.id]?.resumable == true ? "Reprendre":"Regarder","play.fill")
        case .episodes:return ("Ouvrir la saison","shippingbox")
        case .favorite:return (isFavorite ? "Favori":"Favoris",isFavorite ? "star.fill":"star")
        case .flip:return ("Retourner","arrow.triangle.2.circlepath")
        case .rotate:return (manipulating ? "Terminer":"Manipuler","rotate.3d")
        case .trailer:return ("Bande-annonce","film")
        case .wikipedia:return ("Wikipédia","info.circle")
        case .allocine:return ("Allociné","link")
        case .previous:return ("Précédent","chevron.left")
        case .next:return ("Suivant","chevron.right")
        case .previousSeason:return ("Saison −","chevron.left")
        case .nextSeason:return ("Saison +","chevron.right")
        case .previousPage:return ("Page −","arrow.left")
        case .nextPage:return ("Page +","arrow.right")
        case .details:return (collectorOpen ? "Choisir une saison":"Fiche",collectorOpen ? "shippingbox":"doc.text")
        case .description:return ("Description","text.alignleft")
        case .retry:return ("Réessayer","arrow.clockwise")
        case .close:return ("Reposer","arrow.uturn.backward")
        case .episode(let i):return ("Épisode \(i+1)","play.fill")
        }
    }
    private func commandButton(_ action:CaseFaceLayout.Action,compact:Bool=false)->some View {
        let (title,icon)=commandLabel(action)
        let primary=action == .play || action == .episodes
        return Button {focused=action;activate(action)} label: {
            HStack(spacing:6) {
                Image(systemName:icon)
                if !compact {Text(title).lineLimit(1)}
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal,compact ? 12:16).padding(.vertical,10)
            .background(primary ? Color.white.opacity(0.22):Color.white.opacity(0.055),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(commandsActive && focused == action ? Color.cyan:Color.white.opacity(0.11),lineWidth:commandsActive && focused == action ? 2:1))
        }.buttonStyle(.plain).accessibilityLabel(title)
        #if os(tvOS)
        .focusable(!compact)
        .focused($nativeCommandFocus,equals:action)
        .onMoveCommand { direction in
            switch direction {
            case .up:focusInspector(.preview)
            case .left:moveCommand(-1)
            case .right:moveCommand(1)
            case .down:focusInspector(.dismiss)
            default:break
            }
        }
        .onExitCommand {handle(.back)}
        #endif
    }
    private var sideArrows:some View {
        HStack {
            if position>0 {commandButton(.previous,compact:true)}
            Spacer(minLength:0)
            if position+1<count {commandButton(.next,compact:true)}
        }.padding(.horizontal,16)
    }
    private var externalControls:some View {
        VStack(spacing:6) {
            if commandsActive || descriptionActive || manipulating {
                ScrollViewReader { reader in
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:7) {ForEach(commandActions,id:\.self){ action in commandButton(action).id(action)}}
                            .padding(.horizontal,3)
                    }.frame(height:46)
                    .onChange(of:focused){_,action in
                        if let action,commandActions.contains(action) {
                            withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){reader.scrollTo(action,anchor:.center)}
                        }
                    }
                }
            } else {
                HStack(spacing:12) {
                    inspectionButton("Reposer",icon:"arrow.uturn.backward",target:.dismiss) {activate(.close)}
                    Spacer(minLength:6)
                    inspectionButton("Actions",icon:"ellipsis",target:.more,iconOnly:true) {enterCommands()}
                    Spacer(minLength:6)
                    inspectionButton(isFavorite ? "Favori":"Favoris",icon:isFavorite ? "star.fill":"star",target:.favorite) {favorite()}
                }
            }
            if startingPlayback {ProgressView("Ouverture de la vidéo…").font(.caption)}
            else if seasonLoading {Text("Chargement des saisons…").font(.caption).foregroundStyle(.secondary)}
            else if seasonError {Button("Saisons indisponibles · Réessayer"){activate(.retry)}.font(.caption)}
            else if previewVisible,!mediaPreview.statusText.isEmpty {Text(mediaPreview.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}
            Text(navigationHint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.horizontal,10).padding(.vertical,8)
         .frame(maxWidth:controlBarWidth)
         .fluxMediaGlass(radius:23).padding(.horizontal,10)
         .frame(maxWidth:.infinity)
         .accessibilityHint(navigationHint)
    }
    private var controlBarWidth:CGFloat {
        #if os(tvOS)
        return commandsActive || descriptionActive || manipulating ? 1040:820
        #else
        return commandsActive || descriptionActive || manipulating ? 680:520
        #endif
    }
    private var primaryPlaybackTitle:String {
        if item.isSeriesCollection {
            if let season=selectedSeason,visibleEpisodes.indices.contains(selectedEpisodeIndex) {
                let number=visibleEpisodes[selectedEpisodeIndex].episodeNumber ?? (episodePage*CaseFaceLayout.episodePageSize+selectedEpisodeIndex+1)
                return "Voir S\(season.number) · E\(number)"
            }
            return "Voir l’épisode"
        }
        return playback.history.entries[item.id]?.resumable == true ? "Reprendre le film":"Voir le film"
    }
    private var inspectionPlayButton:some View {
        inspectionButton(primaryPlaybackTitle,icon:"play.fill",target:.play) {playSelectedContent()}
            .padding(4).fluxMediaGlass(radius:22)
            .disabled(startingPlayback || (item.isSeriesCollection && (seasonLoading || visibleEpisodes.isEmpty)))
            .accessibilityHint("La touche Lecture lance aussi ce contenu, quelle que soit la sélection.")
    }
    private func inspectionButton(_ title:String,icon:String,target:CaseInspectorNavigation.Target,iconOnly:Bool=false,action:@escaping ()->Void)->some View {
        let selected=inspectorNavigation.target == target && !commandsActive && !descriptionActive && !manipulating
        return Button(action:action) {
            HStack(spacing:8) {
                Image(systemName:icon)
                if !iconOnly {Text(title).lineLimit(1)}
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal,iconOnly ? 12:15).padding(.vertical,9)
            .background(.white.opacity(selected ? 0.24:0.045),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(selected ? Color.cyan:Color.clear,lineWidth:1.5))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected:[])
            #if os(tvOS)
            .focusable(false)
            #endif
    }
    private var navigationHint:String {
        if descriptionActive {return "← → Source · Valider Ouvrir · ↑ Aperçu · Retour Reposer"}
        if manipulating {return "Flèches : tourner · OK : terminer · Menu : reposer"}
        if commandsActive {return "← → Actions · Valider Choisir · ↑ Aperçu · Retour Reposer"}
        if selectingSeason {return "← → Choisir la saison · Valider Épisodes · Lecture Lire · ↑ Aperçu · ↓ Actions"}
        if selectingEpisode {return "← → Épisode · Valider / Lecture Lire · ↑ Aperçu · ↓ Actions"}
        switch inspectorNavigation.target {
        case .object:
            return item.isSeriesCollection ? "← → Tourner · Double appui : changer · Valider Saisons · ↑ Aperçu":"← → Tourner · Double appui : changer · ↑ Aperçu · Lecture Lire"
        case .preview:return details.trailerURL == nil ? "Aucune bande-annonce fournie · ↑ Lecture · ↓ Actions":"Valider Bande-annonce en grand · ↑ Lecture · ↓ Actions · Lecture Lire"
        case .play:return "Valider / Lecture Lire · ↓ Aperçu · Retour Reposer"
        case .dismiss,.favorite,.more:return "← → Choisir · Valider Activer · ↑ Aperçu · Retour Reposer"
        }
    }
    private var model:some View {
        Case3DView(item:item,details:details,printData:printData,focused:manipulating ? nil:focused,yaw:yaw,pitch:pitch,motion:!reduceMotion && !dragging,bridge:bridge,padInput:handlePad,padEnabled:acceptsRotation,previousItem:previousItem,nextItem:nextItem,previousFarItem:previousFarItem,nextFarItem:nextFarItem,selectedTheme:selectedTheme,previewStill:mediaPreview.still,previewPlayer:mediaPreview.player,previewPlaying:mediaPreview.showVideo && previewVisible,concept:concept)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    @ViewBuilder private var inlineYouTubePreview:some View {
        #if os(macOS) || os(iOS)
        if previewActive, !trailerFullscreen,
           case .youtube = TrailerPreviewRoute.resolve(details.trailerURL),
           let projection=bridge.previewProjection ?? lastPreviewProjection {
            let drawable=bridge.previewProjection != nil && previewVisible
            ZStack(alignment:.topTrailing) {
                if let session=mediaPreview.youtubeSession {
                    // Keep one mounted host through edge-on/front rotations.
                    // A fixed logical viewport is projected onto the sleeve;
                    // its WebKit document never shrinks or reloads mid-gesture.
                    YouTubeTrailerSurface(session:session)
                        .opacity(mediaPreview.showVideo && drawable ? 1:0)
                        .allowsHitTesting(mediaPreview.showVideo && drawable && !dragging && !manipulating)
                        .animation(reduceMotion ? nil:.easeInOut(duration:0.5),value:mediaPreview.showVideo)
                } else {
                    Color.clear.allowsHitTesting(false)
                }
                Button {activate(.trailer)} label: {
                    Label("Agrandir",systemImage:"arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold)).padding(.horizontal,10).padding(.vertical,6)
                        .fluxMediaGlass(radius:12)
                }.buttonStyle(.plain).offset(y:-34)
                    .accessibilityLabel("Bande-annonce en plein écran")
                    .opacity(drawable ? 1:0).allowsHitTesting(drawable)
            }
            .frame(width:youtubeSurfaceSize.width,height:youtubeSurfaceSize.height)
            .projectionEffect(previewTransform(projection,sourceSize:youtubeSurfaceSize))
            .accessibilityHidden(!drawable)
        }
        #endif
    }
    private func previewTransform(_ projection:CasePreviewProjection,sourceSize:CGSize)->ProjectionTransform {
        let m=projection.matrix
        let xScale=projection.surfaceSize.width/sourceSize.width
        let yScale=projection.surfaceSize.height/sourceSize.height
        var transform=CATransform3DIdentity
        transform.m11=m.m11*xScale;transform.m12=m.m12*xScale;transform.m14=m.m14*xScale
        transform.m21=m.m21*yScale;transform.m22=m.m22*yScale;transform.m24=m.m24*yScale
        transform.m41=m.m41;transform.m42=m.m42
        return ProjectionTransform(transform)
    }
    private func openTrailer() {
        leaveCommands()
        inspectorNavigation.focus(.preview);focused = .trailer
        if !collectorOpen {faceBack()}
        let filmURL:URL? = item.kind == .movie ? (try? library.playbackURLs(for:item))?.first:nil
        mediaPreview.setBackFacing(true)
        mediaPreview.update(item:item,details:details,filmURL:filmURL,backVisible:true,automatic:automaticPreview,delay:previewDelay)
        mediaPreview.setYouTubeViewportEligible(true)
        trailerFullscreen=true
        mediaPreview.activateTrailer(unmute:true)
    }
    private func closeTrailer() {
        mediaPreview.setMuted(true)
        trailerFullscreen=false
        inspectorNavigation.focus(.preview);focused = .trailer
        mediaPreview.setBackFacing(bridge.previewBackFacing)
        #if os(macOS)
        keyboardSurfaceFocused=false
        Task { @MainActor in await Task.yield();keyboardSurfaceFocused=true }
        #endif
    }
    private var modelViewport:some View {
        modelControl
            .overlay(alignment:.topLeading) { inlineYouTubePreview }
            .overlay { sideArrows }
            .coordinateSpace(name:"case-viewport")
            #if !os(tvOS)
            // An ancestor gesture survives the video being hosted above the
            // SceneKit view. Native YouTube buttons remain independently usable.
            .simultaneousGesture(caseDragGesture)
            #endif
    }
    #if !os(tvOS)
    private var caseDragGesture:some Gesture {
        DragGesture(minimumDistance:5,coordinateSpace:.named("case-viewport"))
            .onChanged { value in
                guard acceptsRotation else{return}
                if !dragging && !mayBeginDrag(at:value.startLocation) {return}
                #if os(macOS)
                guard padRotation == nil else{return}
                if !dragging {
                    dragYaw=yaw;dragPitch=pitch;dragging=true;focused=nil
                    inspectorNavigation.focus(.object);selectingSeason=false;selectingEpisode=false
                }
                yaw=dragYaw+Double(value.translation.width)*0.60
                pitch=dragPitch+Double(value.translation.height)*0.55
                #else
                handlePad(.translation(Double(value.translation.width),Double(value.translation.height)))
                #endif
            }
            .onEnded { value in
                #if os(macOS)
                if padRotation == nil {dragging=false}
                #else
                if padRotation != nil {handlePad(.finishTranslation(Double(value.translation.width),Double(value.translation.height)))}
                #endif
            }
    }
    private func mayBeginDrag(at point:CGPoint)->Bool {
        guard mediaPreview.showVideo,case .youtube = TrailerPreviewRoute.resolve(details.trailerURL),
              let (_,uv)=bridge.pick?(point),bridge.previewContentUVFrame.contains(uv) else{return true}
        let frame=bridge.previewContentUVFrame
        let y=(uv.y-frame.minY)/frame.height
        // Leave the title, timeline, volume and player control bands to WebKit.
        return y>0.18 && y<0.76
    }
    #endif
    @ViewBuilder private var modelControl:some View {
        #if os(tvOS)
        // One native focus target routes the Siri Remote to the external commands
        // and the printed episode regions.
        Button {handle(.select)} label:{model}
            .buttonStyle(.plain).focused($surfaceFocused).focusEffectDisabled()
            .onAppear{surfaceFocused=true}
            .onMoveCommand {direction in
                let action:RemoteAction
                switch direction {case .left:action = .left;case .right:action = .right;case .up:action = .up;case .down:action = .down;@unknown default:return}
                // Touch swipes also reach the native focus engine on some tvOS
                // versions. Give the continuous pan priority over move commands.
                pendingDirection?.cancel()
                guard !dragging,Date.timeIntervalSinceReferenceDate-lastPadTime > 0.18 else{return}
                pendingDirection=Task { @MainActor in
                    try? await Task.sleep(nanoseconds:20_000_000)
                    guard !Task.isCancelled,!dragging,Date.timeIntervalSinceReferenceDate-lastPadTime > 0.18 else{return}
                    handle(action)
                }
            }
            .accessibilityLabel(item.name)
            .accessibilityHint(navigationHint)
        #else
        model.overlay {
            Color.clear.contentShape(Rectangle())
            .onTapGesture { location in
                guard !dragging else{return}
                if !collectorOpen,let index=bridge.pickSeason?(location) {
                    if selectingSeason && index == seasonIndex {activate(.episodes)} else {selectSeason(index)}
                    return
                }
                guard let (surface,uv)=bridge.pick?(location) else {
                    if let offset=bridge.pickNeighbor?(location) {moveNeighbor(offset)}
                    else {close()}
                    return
                }
                if surface == .front || surface == .back {
                    let face:CaseFaceLayout.Page=surface == .front ? (collectorOpen ? .episodes:.front):.details
                    if face == .details,CaseBackMediaLayout.descriptionFrame.contains(uv) {
                        activate(.description)
                        if CaseBackMediaLayout.descriptionPrevious.contains(uv) {descriptions.step(-1)}
                        else if CaseBackMediaLayout.descriptionNext.contains(uv) {descriptions.step(1)}
                        else if CaseBackMediaLayout.descriptionLink.contains(uv),descriptionID == descriptionKey,let url=descriptions.sourceURL {showLink(url)}
                        else {activate(.description)}
                    }
                    else if face == .details,CaseBackMediaLayout.frame.contains(uv) {activate(.trailer)}
                    else if face == .details,let action=CaseBackMediaLayout.action(at:uv) {
                        if action == .play {playSelectedContent()}else{activate(action)}
                    }
                    else if let action=CaseFaceLayout.action(at:uv,in:regions(face)) {activate(action)}
                    else if collectorOpen && surface == .back {closeCollector()}
                    else {handle(.select)}
                } else {handle(.select)}
            }

            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(item.name)
            .accessibilityHint("Glissez sur la boîte ou à deux doigts sur le trackpad pour la tourner.")
            .accessibilityAction(named:Text("Retourner")){flip()}
            .accessibilityAction(named:Text("Lire le film ou l’épisode")){playSelectedContent()}
            .accessibilityAction(named:Text("Reposer")){close()}
        #endif
    }
    private func handlePad(_ input:CasePadInput) {
        guard acceptsRotation else{return}
        #if os(tvOS)
        lastPadTime=Date.timeIntervalSinceReferenceDate
        pendingDirection?.cancel();pendingDirection=nil
        #endif
        switch input {
        case .delta(let dx,let dy),.translation(let dx,let dy),.finishTranslation(let dx,let dy):
            if padRotation == nil {
                // Do not fight a held mouse button or a second gesture.
                guard !dragging else{return}
                padRotation=CasePadRotation(yaw:yaw,pitch:pitch)
                dragging=true;focused=nil;commandsActive=false;descriptionActive=false
                inspectorNavigation.focus(.object);selectingSeason=false;selectingEpisode=false
            }
            guard var rotation=padRotation else{return}
            let pose:CasePadRotation.Pose
            if case .delta = input {pose=rotation.delta(dx,dy)}
            else {pose=rotation.translation(dx,dy)}
            padRotation=rotation;yaw=pose.yaw;pitch=pose.pitch
            if case .finishTranslation = input {finishPad()}
        case .finish:finishPad()
        case .cancel:
            guard let rotation=padRotation else{return}
            padRotation=nil;dragging=false;yaw=rotation.origin.yaw;pitch=rotation.origin.pitch
        }
    }
    private func finishPad() {
        guard let rotation=padRotation else{return}
        let pose=rotation.finish(reduceMotion:reduceMotion)
        padRotation=nil;dragging=false;yaw=pose.yaw;pitch=pose.pitch
    }
    private func orient(back:Bool) {
        let target=back ? 180.0:0.0
        yaw=target+((yaw-target)/360).rounded()*360;pitch=0
    }
    private func faceBack() {orient(back:true)}
    private func closeCollector() {
        page = .details;leaveCommands();orient(back:false)
        selectingSeason = !seasons.isEmpty
    }
    private func focusInspector(_ target:CaseInspectorNavigation.Target) {
        commandsActive=false;descriptionActive=false;manipulating=false
        selectingSeason=false;selectingEpisode=false
        inspectorNavigation.focus(target)
        focused = target == .preview ? .trailer:nil
        // The open collector already exposes its preview on the hinged lid.
        if target == .preview && !collectorOpen {faceBack()}
        #if os(tvOS)
        nativeCommandFocus=nil;surfaceFocused=true
        #endif
    }
    private func enterCommands() {
        inspectorNavigation.focus(.more)
        selectingSeason=false;selectingEpisode=false;manipulating=false;descriptionActive=false
        commandsActive=true;focused = primaryActions.first
        #if os(tvOS)
        surfaceFocused=false;nativeCommandFocus = focused
        #endif
    }
    private func leaveCommands() {
        commandsActive=false;descriptionActive=false;focused=nil
        selectingSeason=false;selectingEpisode=false;inspectorNavigation.focus(.object)
        #if os(tvOS)
        nativeCommandFocus=nil;surfaceFocused=true
        #endif
    }
    private func moveCommand(_ delta:Int) {
        let actions=commandActions
        guard !actions.isEmpty else{return}
        let index=focused.flatMap{actions.firstIndex(of:$0)} ?? 0
        let action=actions[max(0,min(actions.count-1,index+delta))]
        focused=action
        #if os(tvOS)
        nativeCommandFocus=action
        #endif
    }
    private func flip() {
        leaveCommands();focused=nil;manipulating=false
        if collectorOpen {page = .details;faceBack()}
        else {orient(back:CaseFaceLayout.face(yaw:yaw,pitch:pitch) != .details)}
    }
    private func cancelHandoff() {
        handoffToken=UUID();handoffTask?.cancel();handoffTask=nil;startingPlayback=false
    }
    private func preparePlayback(_ action:@escaping ()->Void) {
        cancelHandoff();startingPlayback=true
        let token=UUID();handoffToken=token
        handoffTask=Task { @MainActor in
            await mediaPreview.stopAndWait()
            guard !Task.isCancelled,handoffToken == token else{return}
            action();startingPlayback=false;handoffTask=nil
        }
    }
    private func moveNeighbor(_ offset:Int) {
        guard CaseCarousel.offsets.contains(offset),CaseCarousel.index(from:position,offset:offset,count:count) != nil else{return}
        cancelHandoff();mediaPreview.stop()
        if let jumpBy {jumpBy(offset)}
        else if offset < 0 {previous()} else {next()}
    }
    private func playSelectedContent() {
        guard !startingPlayback else{return}
        guard item.isSeriesCollection else {preparePlayback(play);return}
        guard !seasonLoading else{return}
        if seasonError {activate(.retry);return}
        guard !visibleEpisodes.isEmpty else{return}
        activate(.episode(max(0,min(selectedEpisodeIndex,visibleEpisodes.count-1))))
    }
    private func selectSeason(_ index:Int) {
        guard seasons.indices.contains(index) else{return}
        if seasonIndex != index {seasonIndex=index;episodePage=0;selectedEpisodeIndex=0}
        page = .details;focusInspector(.object);selectingSeason=true;orient(back:false)
    }
    private func enterEpisodeSelection() {
        focusInspector(.object);selectingEpisode=true
        focused=visibleEpisodes.isEmpty ? nil:.episode(selectedEpisodeIndex)
        orient(back:false)
    }
    private func moveEpisode(_ delta:Int) {
        guard !visibleEpisodes.isEmpty else{return}
        let next=selectedEpisodeIndex+delta
        if next<0,episodePage>0 {episodePage-=1;selectedEpisodeIndex=visibleEpisodes.count-1}
        else if next>=visibleEpisodes.count,episodePage+1<pageCount {episodePage+=1;selectedEpisodeIndex=0}
        else {selectedEpisodeIndex=max(0,min(visibleEpisodes.count-1,next))}
        focused = .episode(selectedEpisodeIndex)
    }
    private func fetchEpisodesIfNeeded() async {
        guard item.isSeriesCollection,loadedSeriesID != item.id else{return}
        let id=item.id
        seasonLoading=true;seasonError=false
        do {
            let result=try await library.seasons(for:item)
            guard !Task.isCancelled,id == item.id else{return}
            seasons=result;seasonIndex=0;episodePage=0;selectedEpisodeIndex=0;loadedSeriesID=id;seasonLoading=false
            if selectingEpisode,!visibleEpisodes.isEmpty {focused = .episode(0)}
        } catch {
            guard !Task.isCancelled else{return};seasonLoading=false;seasonError=true
        }
    }
    private func activate(_ action:CaseFaceLayout.Action) {
        switch action {
        case .flip:flip()
        case .rotate:let wasManipulating=manipulating;leaveCommands();manipulating = !wasManipulating;focused=nil
        case .play:playSelectedContent()
        case .favorite:favorite()
        case .previous:moveNeighbor(-1)
        case .next:moveNeighbor(1)
        case .close:cancelHandoff();mediaPreview.stop();close()
        case .episodes:guard item.isSeriesCollection else{return};page = .episodes;enterEpisodeSelection()
        case .details:closeCollector()
        case .description:
            descriptionActive=true;commandsActive=false;focused = .description
            #if os(tvOS)
            nativeCommandFocus=nil;surfaceFocused=true
            #endif
        case .previousSeason:selectSeason(max(0,seasonIndex-1))
        case .nextSeason:selectSeason(min(max(0,seasons.count-1),seasonIndex+1))
        case .previousPage:episodePage=max(0,episodePage-1);selectedEpisodeIndex=0;enterEpisodeSelection()
        case .nextPage:episodePage=min(pageCount-1,episodePage+1);selectedEpisodeIndex=0;enterEpisodeSelection()
        case .retry:loadedSeriesID=nil;reloadToken=UUID()
        case .episode(let index):if visibleEpisodes.indices.contains(index){selectedEpisodeIndex=index;let episode=visibleEpisodes[index],allSeasons=seasons;preparePlayback{playEpisode(episode,allSeasons)}}
        case .trailer:
            guard let url=details.trailerURL else{return}
            switch TrailerPreviewRoute.resolve(url) {
            case .native:openTrailer()
            case .youtube(let video):
                #if os(macOS) || os(iOS)
                openTrailer()
                #else
                mediaPreview.stop();showLink(video.watchURL)
                #endif
            case .external(let external):mediaPreview.stop();showLink(external)
            case .unavailable:break
            }
        case .wikipedia,.allocine:
            if let url=CinemaLinks.url(for:action == .wikipedia ? .wikipedia:.allocine,name:item.name,year:details.year,series:item.kind == .series){showLink(url)}
        }
    }
    private func handle(_ action:RemoteAction) {
        if padRotation != nil {
            switch action {
            case .left,.right,.up,.down,.select:return
            default:finishPad()
            }
        }
        if trailerFullscreen {return}
        if qrURL != nil {if action == .back || action == .home {qrURL=nil};return}
        if action != .left && action != .right {inspectorNavigation.focus(inspectorNavigation.target)}
        // These shortcuts have the same meaning in every inspection context.
        if action == .back || action == .home {activate(.close);return}
        if action == .playPause {playSelectedContent();return}
        if action == .fullscreen {toggleNativeFullscreen();return}
        if action == .previous {moveNeighbor(-1);return}
        if action == .next {moveNeighbor(1);return}
        if action == .options {enterCommands();return}
        if action == .mute {mediaPreview.toggleMuted();return}

        if manipulating {
            switch action {
            case .left:yaw -= 25
            case .right:yaw += 25
            case .up:pitch -= 25
            case .down:pitch += 25
            case .select:manipulating=false;focusInspector(.object)
            default:break
            }
            return
        }
        if descriptionActive {
            switch action {
            case .left:descriptions.step(-1)
            case .right:descriptions.step(1)
            case .select:if descriptionID == descriptionKey,let url=descriptions.sourceURL {showLink(url)}
            case .up:focusInspector(.preview)
            case .down:focusInspector(.dismiss)
            default:break
            }
            return
        }
        if commandsActive {
            switch action {
            case .left:moveCommand(-1)
            case .right:moveCommand(1)
            case .select:if let focused {activate(focused)}
            case .up:focusInspector(.preview)
            case .down:focusInspector(.dismiss)
            default:break
            }
            return
        }
        if selectingSeason {
            switch action {
            case .left:selectSeason(max(0,seasonIndex-1))
            case .right:selectSeason(min(max(0,seasons.count-1),seasonIndex+1))
            case .select:activate(.episodes)
            case .up:focusInspector(.preview)
            case .down:focusInspector(.dismiss)
            default:break
            }
            return
        }
        if selectingEpisode {
            switch action {
            case .left:moveEpisode(-1)
            case .right:moveEpisode(1)
            case .select:playSelectedContent()
            case .up:focusInspector(.preview)
            case .down:focusInspector(.dismiss)
            default:break
            }
            return
        }
        if action == .select,inspectorNavigation.target == .object,item.isSeriesCollection {
            if collectorOpen {enterEpisodeSelection()}
            else if seasonError {activate(.retry)}
            else if !seasons.isEmpty {selectSeason(seasonIndex)}
            return
        }
        switch inspectorNavigation.handle(action:action,at:Date.timeIntervalSinceReferenceDate) {
        case .none:break
        case .focus(let target):focusInspector(target)
        case .rotate(let degrees):
            focused=nil;selectingSeason=false;selectingEpisode=false
            yaw += degrees
        case .neighbor(let offset):
            if CaseCarousel.index(from:position,offset:offset,count:count) != nil {
                // The first tap already turned immediately. A confirmed double
                // press keeps the original orientation while changing titles.
                yaw -= Double(offset)*25
                moveNeighbor(offset)
            }
        case .activate(let target):
            switch target {
            case .preview:activate(.trailer)
            case .play:playSelectedContent()
            case .dismiss:activate(.close)
            case .favorite:favorite()
            case .more:enterCommands()
            case .object:break
            }
        case .close:activate(.close)
        }
    }

    private func toggleNativeFullscreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }
    private func showLink(_ url:URL) {
        #if os(tvOS)
        qrURL=url
        #else
        openURL(url)
        #endif
    }
}
private struct CaseTrailerView:View {
    @ObservedObject var preview:CaseMediaPreviewController
    let remoteEvent:CaseRemoteEvent?;let close:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var controlsVisible=true
    @State private var controlsHovered=false
    @State private var controlTimer:Task<Void,Never>?
    #if os(macOS)
    @State private var expandedWindowNumber:Int?
    @State private var escapeMonitor:Any?
    #endif
    var body:some View {
        ZStack(alignment:.topLeading) {
            Color.black.ignoresSafeArea()
            trailerSurface.frame(maxWidth:.infinity,maxHeight:.infinity)
            if controlsVisible || preview.phase != .playing {
                HStack(spacing:10) {
                    Button(action:close) {Label("Pochette",systemImage:"chevron.left").padding(10)}
                    if preview.phase == .blocked || preview.phase == .paused {
                        Button {preview.activateTrailer();revealControls()} label:{Label("Lire",systemImage:"play.fill").padding(10)}
                    }
                }.buttonStyle(.plain).font(.callout.weight(.semibold))
                    .padding(4).fluxMediaGlass(radius:22).padding(16)
                    .transition(.opacity)
                    #if !os(tvOS)
                    .onHover {inside in
                        controlsHovered=inside
                        if inside {controlTimer?.cancel()}else if controlsVisible {revealControls()}
                    }
                    #endif
            }
        }
        .onAppear {
            #if os(macOS)
            let windowNumber=NSApp.keyWindow?.windowNumber
            escapeMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { event in
                guard event.keyCode == 53,event.window?.windowNumber == windowNumber else{return event}
                close();return nil
            }
            if let window=NSApp.keyWindow,!window.styleMask.contains(.fullScreen) {
                expandedWindowNumber=window.windowNumber;window.toggleFullScreen(nil)
            }
            #endif
            revealControls()
        }
        .onDisappear {
            controlTimer?.cancel()
            // The retained session is still playing in the miniature after
            // dismissal. Only its sound and native presentation change.
            #if os(macOS)
            if let escapeMonitor {NSEvent.removeMonitor(escapeMonitor);self.escapeMonitor=nil}
            if let number=expandedWindowNumber,let window=NSApp.windows.first(where:{$0.windowNumber==number}),window.styleMask.contains(.fullScreen) {window.toggleFullScreen(nil)}
            expandedWindowNumber=nil
            #endif
        }
        .onChange(of:preview.phase){_,_ in revealControls()}
        .onChange(of:remoteEvent){_,event in
            guard let action=event?.action else{return}
            revealControls()
            switch action {
            case .playPause:preview.togglePlayback()
            case .rewind:preview.seek(by:-15)
            case .forward:preview.seek(by:15)
            case .back,.home:Task { @MainActor in await Task.yield();close() }
            default:break
            }
        }
        #if os(tvOS)
        .onExitCommand(perform:close)
        #else
        .onContinuousHover {phase in if case .active = phase {revealControls()}}
        .simultaneousGesture(TapGesture().onEnded{revealControls()})
        #endif
    }
    @ViewBuilder private var trailerSurface:some View {
        if preview.phase == .failed {
            VStack(spacing:18) {
                Image(systemName:"exclamationmark.circle").font(.largeTitle)
                Text(preview.statusText).multilineTextAlignment(.center)
                Button("Réessayer"){preview.activateTrailer()}
                #if !os(tvOS)
                if let url=preview.externalURL {
                    Button("Ouvrir sur YouTube"){openURL(url)}
                }
                #endif
            }.padding(30).frame(maxWidth:520)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
        } else {
            #if os(macOS) || os(iOS)
            if let session=preview.youtubeSession {
                YouTubeTrailerSurface(session:session)
                    // Native return controls stay outside the YouTube viewport
                    // so its title, branding and own controls remain accessible.
                    .padding(.top,72)
            } else if let player=preview.player {
                VideoPlayer(player:player)
            } else {
                nativePlaceholder
            }
            #else
            if let player=preview.player {VideoPlayer(player:player)}else{nativePlaceholder}
            #endif
        }
    }
    private var nativePlaceholder:some View {
        VStack(spacing:14) {
            if [.idle,.still,.ended,.paused,.blocked].contains(preview.phase) {
                Button(preview.phase == .ended ? "Revoir la bande-annonce":"Lire la bande-annonce"){preview.activateTrailer()}
            }
            else {ProgressView();Text(preview.statusText).font(.callout)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private func revealControls() {
        controlTimer?.cancel()
        withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){controlsVisible=true}
        guard preview.phase == .playing,!voiceOverEnabled,!controlsHovered else{return}
        controlTimer=Task { @MainActor in
            do{try await Task.sleep(nanoseconds:3_000_000_000)}catch{return}
            guard !Task.isCancelled,preview.phase == .playing,!controlsHovered,!voiceOverEnabled else{return}
            withAnimation(reduceMotion ? nil:.easeOut(duration:0.22)){controlsVisible=false}
        }
    }
}
#if os(tvOS)
private struct CaseQRView:View {
    let url:URL;let close:()->Void
    var body:some View {
        VStack(spacing:24){Text("Ouvrir sur iPhone").font(.title);if let filter=CIFilter(name:"CIQRCodeGenerator") { let _=filter.setValue(Data(url.absoluteString.utf8),forKey:"inputMessage");if let output=filter.outputImage,let cg=CIContext().createCGImage(output,from:output.extent){Image(uiImage:UIImage(cgImage:cg)).interpolation(.none).resizable().frame(width:280,height:280).padding(20).background(.white)}};Button("Fermer",action:close)}.padding(36)
    }
}
#endif
