import SwiftUI
import AVKit
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
    @State private var bridge=CaseHitBridge()
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
    @State private var trailer:URL?
    @State private var qrURL:URL?
    @State private var seasons:[IPTVSeason]=[]
    @State private var seasonIndex = 0
    @State private var episodePage = 0
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
        return data
    }
    private var collectorOpen:Bool {item.isSeriesCollection && page == .episodes}
    private var currentFace:CaseFaceLayout.Page? {CaseFaceLayout.face(yaw:yaw,pitch:pitch).map{$0 == .front ? (collectorOpen ? CaseFaceLayout.Page.episodes:.front):.details}}
    private var descriptionKey:String {"\(item.id)|\(item.name)|\(details.year ?? "")|\(descriptions.source.rawValue)|\(details.synopsis ?? "")"}
    private var acceptsRotation:Bool {
        guard trailer == nil,qrURL == nil,!commandsActive,!descriptionActive,!startingPlayback,scenePhase == .active else{return false}
        #if os(tvOS)
        // Ordinary Siri Remote swipes navigate; the visible Manipuler action
        // explicitly grants the continuous pan to the 3D object.
        return manipulating
        #else
        return manipulating || !collectorOpen
        #endif
    }
    private var previewVisible:Bool {!suspended && currentFace == .details && !collectorOpen && !dragging && !manipulating && !startingPlayback && trailer == nil && qrURL == nil && scenePhase == .active}
    private var previewKey:String {"\(item.id)|\(previewVisible)|\(automaticPreview)|\(previewDelay.rawValue)|\(details.trailerURL?.absoluteString ?? "")|\(item.backdropURL?.absoluteString ?? "")"}
    private func regions(_ face:CaseFaceLayout.Page)->[CaseFaceLayout.Region] {
        CaseFaceLayout.regions(face,series:item.isSeriesCollection,trailer:details.trailerURL != nil,episodeCount:visibleEpisodes.count,retry:seasonError).filter { region in
            if case .episode = region.action {return true};return false
        }
    }
    var body:some View {
        ZStack {
            if let trailer {
                // A trailer has sole use of the video surface. No live 3D render
                // behind it; closing returns to the same side of the same sleeve.
                CaseTrailerView(url:trailer,remoteEvent:remoteEvent,close:{self.trailer=nil})
            } else {
                VStack(spacing:4) {
                    modelControl
                        .overlay { sideArrows }
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
            let filmURL:URL? = previewVisible && item.kind == .movie ? (try? library.playbackURLs(for:item))?.first:nil
            mediaPreview.update(item:item,details:details,filmURL:filmURL,backVisible:previewVisible,automatic:automaticPreview,delay:previewDelay)
        }
        .onDisappear{cancelHandoff();mediaPreview.stop();onTrailerPresentation(false)}
        .onChange(of:trailer != nil){_,visible in onTrailerPresentation(visible)}
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
        .focusable().focused($keyboardSurfaceFocused)
        .onAppear {keyboardSurfaceFocused=true}
        #endif
        #if os(tvOS)
        .onDisappear{pendingDirection?.cancel()}
        .onChange(of:nativeCommandFocus){_,action in if let action {focused=action;commandsActive=true}}
        #endif
        .onChange(of:item.id){_,_ in
            // Preserve the orientation, but never reuse the previous series data.
            cancelHandoff();trailer=nil;qrURL=nil;loadedSeriesID=nil;seasons=[];seasonIndex=0;episodePage=0;seasonError=false;seasonLoading=false
            page = .details;commandsActive=false;manipulating=false;descriptionActive=false;descriptions.reset();descriptionID=""
            focused=nil;padRotation=nil;dragging=false
            #if os(tvOS)
            nativeCommandFocus=nil;surfaceFocused=true
            #endif
        }
        .onAppear {if startEpisodes && item.isSeriesCollection {page = .episodes;orient(back:false)}}
        .task(id:"\(item.id)|\(page == .episodes)|\(reloadToken)") {await fetchEpisodesIfNeeded()}
        #if os(tvOS)
        .sheet(isPresented:Binding(get:{qrURL != nil},set:{if !$0{qrURL=nil}})) {if let qrURL {CaseQRView(url:qrURL,close:{self.qrURL=nil})}}
        #endif
    }
    private var caseTitle:some View {
        HStack(spacing:10) {
            if concept == .neoVideoClub { Image(systemName:"film.stack").foregroundStyle(.cyan) }
            Text(item.name).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer(minLength:8)
            Text("\(position+1) / \(max(1,count))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.horizontal,24).frame(maxWidth:900)
    }
    private var primaryActions:[CaseFaceLayout.Action] {
        [item.isSeriesCollection ? (collectorOpen ? .details:.episodes):.play,.favorite,.flip,.rotate,.close]
    }
    private var secondaryActions:[CaseFaceLayout.Action] {
        guard currentFace != .front, currentFace != nil else{return []}
        if page == .episodes && item.isSeriesCollection {
            var actions:[CaseFaceLayout.Action]=[.previousSeason,.nextSeason,.previousPage,.nextPage]
            if seasonError {actions.append(.retry)}
            return actions
        }
        var actions:[CaseFaceLayout.Action]=details.trailerURL != nil ? [.trailer] : []
        actions += [.description,.wikipedia,.allocine]
        return actions
    }
    private var commandActions:[CaseFaceLayout.Action] {primaryActions+secondaryActions}
    private func commandLabel(_ action:CaseFaceLayout.Action)->(String,String) {
        switch action {
        case .play:return (playback.history.entries[item.id]?.resumable == true ? "Reprendre":"Regarder","play.fill")
        case .episodes:return ("Ouvrir le coffret","shippingbox")
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
        case .details:return (collectorOpen ? "Fermer le coffret":"Fiche",collectorOpen ? "shippingbox":"doc.text")
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
        .focused($nativeCommandFocus,equals:action)
        .onMoveCommand { direction in
            switch direction {
            case .up:leaveCommands()
            case .left:moveCommand(-1)
            case .right:moveCommand(1)
            default:break
            }
        }
        .onExitCommand {leaveCommands()}
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
        VStack(spacing:5) {
            caseTitle
            if startingPlayback {ProgressView("Ouverture de la vidéo…").font(.caption)}
            else if previewVisible {Text(mediaPreview.stillLabel+" · "+mediaPreview.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}
            if collectorOpen && !seasons.isEmpty {seasonStrip}
            ScrollViewReader { reader in
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {ForEach(commandActions,id:\.self){ action in commandButton(action).id(action)}}
                        .padding(.horizontal,3)
                }.frame(height:46)
                 .onChange(of:focused){_,action in
                    if let action,commandActions.contains(action) {
                        withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){reader.scrollTo(action,anchor:.center)}
                    }
                 }
            }
            Text(navigationHint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.horizontal,12).padding(.vertical,7)
         .fluxGlass(radius:23).padding(.horizontal,12)
         .accessibilityHint(navigationHint)
    }
    private var navigationHint:String {
        if descriptionActive {return "Description · \(descriptions.source.title) · ← → : source · OK : ouvrir la source · Retour : pochette"}
        if manipulating {return "Flèches : tourner · OK : terminer"}
        if commandsActive {return "← → : actions · OK : activer · ↑ ou Retour : pochette"}
        if collectorOpen {return "↑ ↓ : épisodes · ← → : saisons · OK : regarder · Retour : fermer"}
        return "← → : pochettes · ↑ / OK : \(item.isSeriesCollection ? "saisons":"regarder") · ↓ : actions · Retour : reposer"
    }
    private var seasonStrip:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:7) {
                ForEach(Array(seasons.enumerated()),id:\.element.id) { index,season in
                    Button {selectSeason(index)} label: {
                        Text("Saison \(season.number)").font(.caption.weight(.semibold))
                            .padding(.horizontal,12).padding(.vertical,6)
                            .background(.white.opacity(index == seasonIndex ? 0.22:0.06),in:Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal,5)
        }.frame(maxWidth:650)
    }
    private var model:some View {
        Case3DView(item:item,details:details,printData:printData,focused:manipulating ? nil:focused,yaw:yaw,pitch:pitch,motion:!reduceMotion && !dragging,bridge:bridge,padInput:handlePad,padEnabled:acceptsRotation,previousItem:previousItem,nextItem:nextItem,previousFarItem:previousFarItem,nextFarItem:nextFarItem,selectedTheme:selectedTheme,previewStill:mediaPreview.still,previewPlayer:mediaPreview.player,previewPlaying:mediaPreview.showVideo && previewVisible,concept:concept)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    @ViewBuilder private var modelControl:some View {
        #if os(tvOS)
        // One native focus target routes the Siri Remote to the external commands
        // and the printed episode regions.
        Button {handle(.select)} label:{model}
            .buttonStyle(.plain).focused($surfaceFocused)
            .onAppear{surfaceFocused=true}
            .onMoveCommand {direction in
                let action:RemoteAction
                switch direction {case .left:action = .left;case .right:action = .right;case .up:action = .up;case .down:action = .down;@unknown default:return}
                // Touch swipes also reach the native focus engine on some tvOS
                // versions. Give the continuous pan priority over move commands.
                pendingDirection?.cancel()
                guard !dragging,Date.timeIntervalSinceReferenceDate-lastPadTime > 0.18 else{return}
                pendingDirection=Task { @MainActor in
                    try? await Task.sleep(nanoseconds:110_000_000)
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
                guard let (surface,uv)=bridge.pick?(location) else {
                    if let offset=bridge.pickNeighbor?(location) {moveNeighbor(offset)}
                    else {close()}
                    return
                }
                if surface == .front || surface == .back {
                    let face:CaseFaceLayout.Page=surface == .front ? (collectorOpen ? .episodes:.front):.details
                    if face == .details && !collectorOpen,CaseBackMediaLayout.descriptionFrame.contains(uv) {
                        activate(.description)
                        if CaseBackMediaLayout.descriptionPrevious.contains(uv) {descriptions.step(-1)}
                        else if CaseBackMediaLayout.descriptionNext.contains(uv) {descriptions.step(1)}
                        else if CaseBackMediaLayout.descriptionLink.contains(uv),descriptionID == descriptionKey,let url=descriptions.sourceURL {showLink(url)}
                        else {activate(.description)}
                    }
                    else if face == .details && !collectorOpen,CaseBackMediaLayout.frame.contains(uv) {activate(.trailer)}
                    else if face == .details && !collectorOpen,let action=CaseBackMediaLayout.action(at:uv) {activate(action == .play && item.isSeriesCollection ? .episodes:action)}
                    else if let action=CaseFaceLayout.action(at:uv,in:regions(face)) {activate(action)}
                    else if collectorOpen && surface == .back {closeCollector()}
                    else {selectPrimary()}
                } else {selectPrimary()}
            }
            .gesture(DragGesture(minimumDistance:5).onChanged{value in
                #if os(macOS)
                if padRotation != nil {return}
                if !dragging {dragYaw=yaw;dragPitch=pitch;dragging=true;focused=nil;commandsActive=false;descriptionActive=false}
                yaw=dragYaw+Double(value.translation.width)*0.60
                pitch=dragPitch+Double(value.translation.height)*0.55
                #else
                handlePad(.translation(Double(value.translation.width),Double(value.translation.height)))
                #endif
            }.onEnded{value in
                #if os(macOS)
                if padRotation == nil {dragging=false}
                #else
                handlePad(.finishTranslation(Double(value.translation.width),Double(value.translation.height)))
                #endif
            })
            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(item.name)
            .accessibilityHint("Glissez sur la boîte ou à deux doigts sur le trackpad pour la tourner.")
            .accessibilityAction(named:Text("Retourner")){flip()}
            .accessibilityAction(named:Text("Lire ou ouvrir les épisodes")){activate(item.isSeriesCollection ? .episodes:.play)}
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
    private func closeCollector() {page = .details;leaveCommands();orient(back:false)}
    private func enterCommands() {
        commandsActive=true;focused = .favorite
        #if os(tvOS)
        surfaceFocused=false;nativeCommandFocus = .favorite
        #endif
    }
    private func leaveCommands() {
        commandsActive=false;descriptionActive=false;focused=collectorOpen && !visibleEpisodes.isEmpty ? .episode(0):nil
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
    private func selectPrimary() {
        if collectorOpen {
            guard !seasonLoading else{return}
            if seasonError {activate(.retry)}
            else if let focused,case .episode=focused {activate(focused)}
            else if !visibleEpisodes.isEmpty {activate(.episode(0))}
        } else {activate(item.isSeriesCollection ? .episodes:.play)}
    }
    private func selectSeason(_ index:Int) {
        guard seasons.indices.contains(index) else{return}
        seasonIndex=index;episodePage=0;focused=seasons[index].episodes.isEmpty ? nil:.episode(0)
        #if os(tvOS)
        nativeCommandFocus=nil;surfaceFocused=true;commandsActive=false
        #endif
    }
    private func moveEpisode(_ delta:Int) {
        guard !visibleEpisodes.isEmpty else{return}
        let current:Int
        if let focused,case .episode(let index)=focused {current=index}else{current=delta>0 ? -1:visibleEpisodes.count}
        let next=current+delta
        if next<0,episodePage>0 {episodePage-=1;focused = .episode(visibleEpisodes.count-1)}
        else if next>=visibleEpisodes.count,episodePage+1<pageCount {episodePage+=1;focused = .episode(0)}
        else {focused = .episode(max(0,min(visibleEpisodes.count-1,next)))}
    }
    private func fetchEpisodesIfNeeded() async {
        guard page == .episodes,item.isSeriesCollection,loadedSeriesID != item.id else{return}
        let id=item.id
        seasonLoading=true;seasonError=false
        do {
            let result=try await library.seasons(for:item)
            guard !Task.isCancelled,id == item.id else{return}
            seasons=result;seasonIndex=0;episodePage=0;loadedSeriesID=id;seasonLoading=false
            if collectorOpen,!visibleEpisodes.isEmpty {focused = .episode(0)}
        } catch {
            guard !Task.isCancelled else{return};seasonLoading=false;seasonError=true
        }
    }
    private func activate(_ action:CaseFaceLayout.Action) {
        switch action {
        case .flip:flip()
        case .rotate:let wasManipulating=manipulating;leaveCommands();manipulating = !wasManipulating;focused=nil
        case .play:preparePlayback(play)
        case .favorite:favorite()
        case .previous:moveNeighbor(-1)
        case .next:moveNeighbor(1)
        case .close:cancelHandoff();mediaPreview.stop();close()
        case .episodes:guard item.isSeriesCollection else{return};manipulating=false;page = .episodes;leaveCommands();orient(back:false)
        case .details:closeCollector()
        case .description:
            descriptionActive=true;commandsActive=false;focused = .description
            #if os(tvOS)
            nativeCommandFocus=nil;surfaceFocused=true
            #endif
        case .previousSeason:selectSeason(max(0,seasonIndex-1))
        case .nextSeason:selectSeason(min(max(0,seasons.count-1),seasonIndex+1))
        case .previousPage:episodePage=max(0,episodePage-1);focused=visibleEpisodes.isEmpty ? nil:.episode(0)
        case .nextPage:episodePage=min(pageCount-1,episodePage+1);focused=visibleEpisodes.isEmpty ? nil:.episode(0)
        case .retry:loadedSeriesID=nil;reloadToken=UUID()
        case .episode(let index):if visibleEpisodes.indices.contains(index){let episode=visibleEpisodes[index],allSeasons=seasons;preparePlayback{playEpisode(episode,allSeasons)}}
        case .trailer:
            guard let url=details.trailerURL else{return}
            switch TrailerPreviewRoute.resolve(url) {
            case .native(let playable):leaveCommands();preparePlayback{trailer=playable}
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
        if trailer != nil {return}
        if qrURL != nil {if action == .back {qrURL=nil};return}
        if manipulating {
            switch action {
            case .left:yaw -= 25
            case .right:yaw += 25
            case .up:pitch -= 25
            case .down:pitch += 25
            case .select,.options:manipulating=false
            case .previous:moveNeighbor(-1)
            case .next:moveNeighbor(1)
            case .back:manipulating=false
            case .home:close()
            case .fullscreen:toggleNativeFullscreen()
            case .playPause:activate(item.isSeriesCollection ? .episodes:.play)
            default:break
            }
            return
        }
        if descriptionActive {
            switch action {
            case .left,.previous:descriptions.step(-1)
            case .right,.next:descriptions.step(1)
            case .select:if descriptionID == descriptionKey,let url=descriptions.sourceURL {showLink(url)}
            case .back,.up:leaveCommands()
            case .down,.options:descriptionActive=false;enterCommands()
            case .home:mediaPreview.stop();close()
            default:break
            }
            return
        }
        if commandsActive {
            switch action {
            case .left:moveCommand(-1)
            case .right:moveCommand(1)
            case .select:if let focused {activate(focused)}
            case .up,.options,.back:leaveCommands()
            case .home:mediaPreview.stop();close()
            case .playPause:selectPrimary()
            default:break
            }
            return
        }
        if collectorOpen {
            switch action {
            case .up:moveEpisode(-1)
            case .down:moveEpisode(1)
            case .left:activate(.previousSeason)
            case .right:activate(.nextSeason)
            case .select,.playPause:selectPrimary()
            case .back:closeCollector()
            case .home:close()
            case .options:enterCommands()
            case .previous:moveNeighbor(-1)
            case .next:moveNeighbor(1)
            case .fullscreen:toggleNativeFullscreen()
            default:break
            }
            return
        }
        switch action {
        case .down,.options:enterCommands()
        case .fullscreen:toggleNativeFullscreen()
        default:if let command=CaseCarousel.command(for:action,series:item.isSeriesCollection) {activate(command)}
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
    let url:URL;let remoteEvent:CaseRemoteEvent?;let close:()->Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var player=AVPlayer()
    #if os(macOS)
    @State private var expandedWindowNumber: Int?
    #endif
    var body:some View {
        ZStack(alignment:.topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player:player).frame(maxWidth:.infinity,maxHeight:.infinity)
            Button {player.pause();player.replaceCurrentItem(with:nil);close()} label:{Label("Revenir à la pochette",systemImage:"xmark.circle.fill").padding(12)}.buttonStyle(.bordered).padding(15)
        }.onAppear{
            #if os(macOS)
            if let window=NSApp.keyWindow,!window.styleMask.contains(.fullScreen) {
                expandedWindowNumber=window.windowNumber;window.toggleFullScreen(nil)
            }
            #endif
            player.replaceCurrentItem(with:AVPlayerItem(url:url));player.play()
         }
         .onDisappear{
            player.pause();player.replaceCurrentItem(with:nil)
            #if os(macOS)
            if let number=expandedWindowNumber,let window=NSApp.windows.first(where:{$0.windowNumber==number}),window.styleMask.contains(.fullScreen) {window.toggleFullScreen(nil)}
            expandedWindowNumber=nil
            #endif
         }
         .onChange(of:scenePhase){_,phase in if phase != .active {player.pause()}}
         .onChange(of:remoteEvent){_,event in
            guard let action=event?.action else{return}
            switch action {
            case .playPause:if player.timeControlStatus == .playing {player.pause()}else{player.play()}
            case .rewind,.forward:
                let current=player.currentTime().seconds
                if current.isFinite {player.seek(to:CMTime(seconds:max(0,current+(action == .rewind ? -15:15)),preferredTimescale:600))}
            case .back,.home:player.pause();player.replaceCurrentItem(with:nil);close()
            default:break
            }
         }
         #if os(tvOS)
         .onExitCommand{player.pause();player.replaceCurrentItem(with:nil);close()}
         #endif
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
