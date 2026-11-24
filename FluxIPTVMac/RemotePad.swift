import SwiftUI
import GameController
import Combine
#if os(macOS)
import AppKit
#endif

#if !os(tvOS)
/// Vector replicas: the artwork and hit regions are the same SwiftUI layout.
/// No screenshot, raster assets or external network requests are needed.
struct RemotePad: View {
    @Binding var appearance: RemoteAppearance
    let send: (RemoteAction) -> Void
    let caseSwipe: ((CasePadInput) -> Void)?
    let close: () -> Void
    let volume: Double
    let muted: Bool
    @State private var began: Date?
    @State private var touchPoint: CGSize = .zero
    @State private var lastAction: RemoteAction?
    @State private var expanded = false
    @State private var rotatingCase=false
    @State private var trackpadActive=false

    private var silver: Bool { appearance == .silver }
    private var width: CGFloat { silver ? 116 : 106 }
    private var remoteHeight: CGFloat { silver ? 342 : 310 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("TÉLÉCOMMANDE").font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3) }
                        .buttonStyle(.plain).accessibilityLabel("Masquer la télécommande")
                }
                Picker("Modèle", selection: $appearance) {
                    Text("Noire").tag(RemoteAppearance.black)
                    Text("Aluminium").tag(RemoteAppearance.silver)
                }.pickerStyle(.segmented).labelsHidden()
                // Each actual key is a button layered into the remote body.
                remoteBody
                    .frame(width: width, height: remoteHeight)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 7)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(appearance.title)
                Text((rotatingCase || (trackpadActive && caseSwipe != nil)) ? "Rotation de la pochette" : (caseSwipe != nil ? "Glisser pour tourner" : (lastAction.map(label) ?? "Glisser · cliquer · maintenir")))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).frame(height: 13)
                HStack(spacing: 7) {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(.secondary)
                    ProgressView(value: muted ? 0 : volume).tint(.cyan)
                }.font(.caption2).accessibilityLabel("Volume du lecteur")
                Button { expanded.toggle() } label: {
                    Label("Options de lecture", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                if expanded {
                    HStack(spacing: 8) { accessory(.previous, "backward.end.fill"); accessory(.next, "forward.end.fill"); accessory(.mute, muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    HStack(spacing: 8) { accessory(.rewind, "gobackward.15"); accessory(.forward, "goforward.15"); accessory(.fullscreen, "arrow.up.left.and.arrow.down.right") }
                    HStack(spacing: 8) { accessory(.options, "ellipsis.circle"); accessory(.search, "magnifyingglass") }
                }
            }.padding(13)
        }.frame(width: 190).frame(maxHeight: expanded ? 660 : 460)
            .fluxFrosted(radius: 24)
    }

    private var remoteBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: silver ? 16 : 11)
                .fill(LinearGradient(colors: silver ? [Color(white: 0.89), Color(white: 0.64), Color(white: 0.83)] : [Color(white: 0.24), Color(white: 0.08), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: silver ? 16 : 11)
                .strokeBorder(.white.opacity(silver ? 0.7 : 0.32), lineWidth: 1.2)
            VStack(spacing: silver ? 10 : 9) {
                if silver {
                    HStack { Spacer(); roundKey(.home, symbol: "power", size: 22, title: "Accueil FLUX (arrêt matériel non simulé)") }
                        .padding(.horizontal, 9)
                    touchSurface.frame(width: 92, height: 92)
                } else {
                    touchSurface.frame(width: 98, height: 111)
                }
                HStack(spacing: 10) {
                    if silver { roundKey(.back, symbol: "chevron.left", title: "Retour") }
                    else { roundKey(.back, text: "MENU", title: "Menu / retour") }
                    roundKey(.home, symbol: "tv", title: "Accueil FLUX")
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 12) {
                        if silver {
                            roundKey(.playPause, symbol: "playpause.fill", title: "Lecture / pause")
                            roundKey(.mute, symbol: muted ? "speaker.slash.fill" : "speaker.slash", title: "Sourdine")
                        } else {
                            roundKey(.search, symbol: "mic.fill", title: "Recherche FLUX")
                            roundKey(.playPause, symbol: "playpause.fill", title: "Lecture / pause")
                        }
                    }
                    VStack(spacing: 0) {
                        volumeKey(.volumeUp, "plus")
                        Rectangle().fill(.white.opacity(0.14)).frame(width: 22, height: 1)
                        volumeKey(.volumeDown, "minus")
                    }.background(keyFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
                }
                Spacer(minLength: 0)
                if silver { Text("SIRI REMOTE").font(.system(size: 6, weight: .medium)).tracking(0.9).foregroundStyle(.black.opacity(0.36)).padding(.bottom, 8) }
                else { Capsule().fill(.white.opacity(0.16)).frame(width: 24, height: 2).padding(.bottom, 8) }
            }.padding(.top, silver ? 9 : 4)
            if silver {
                // Side button on the second/third-generation remote.
                Button { trigger(.search) } label: { Capsule().fill(Color(white: 0.38)).frame(width: 5, height: 26) }
                    .buttonStyle(.plain).accessibilityLabel("Recherche FLUX").help("Bouton Siri : recherche dans FLUX")
                    .offset(x: width / 2 + 2, y: -54)
            }
        }.foregroundStyle(.white)
    }

    private var touchSurface: some View {
        GeometryReader { g in
            ZStack {
                if silver {
                    Circle().fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1.2)
                    Circle().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)).padding(19)
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1).padding(19)
                } else {
                    RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    Circle().strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2,3])).frame(width: 26, height: 26)
                }
                VStack { Image(systemName: "chevron.up"); Spacer(); Image(systemName: "chevron.down") }.padding(silver ? 7 : 10)
                HStack { Image(systemName: "chevron.left"); Spacer(); Image(systemName: "chevron.right") }.padding(silver ? 7 : 10)
                if began != nil { Circle().fill(.white.opacity(0.22)).frame(width: 20, height: 20).offset(touchPoint) }
                if trackpadActive { Circle().strokeBorder(.cyan.opacity(0.8),lineWidth:1.5).frame(width:30,height:30).allowsHitTesting(false) }
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(silver ? 0.75 : 0.28))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if began == nil { began = Date() }
                    touchPoint = CGSize(width: value.location.x - g.size.width / 2, height: value.location.y - g.size.height / 2)
                    if let caseSwipe {
                        let dx=Double(value.translation.width),dy=Double(value.translation.height)
                        if rotatingCase || max(abs(dx),abs(dy)) >= 6 {
                            rotatingCase=true
                            caseSwipe(.translation(dx*1.7,dy*1.7))
                        }
                    }
                }.onEnded { value in
                    let seconds = Date().timeIntervalSince(began ?? Date())
                    let dx = Double(value.translation.width), dy = Double(value.translation.height)
                    if let caseSwipe,rotatingCase || max(abs(dx),abs(dy)) >= 6 {
                        caseSwipe(.finishTranslation(dx*1.7,dy*1.7))
                        began=nil;touchPoint = .zero;rotatingCase=false
                        return
                    }
                    rotatingCase=false
                    let rx = Double((value.startLocation.x - g.size.width / 2) / (g.size.width / 2))
                    let ry = Double((value.startLocation.y - g.size.height / 2) / (g.size.height / 2))
                    let action: RemoteAction
                    if max(abs(dx), abs(dy)) >= 24 { action = RemoteNavigation.touch(dx: dx, dy: dy, seconds: seconds) }
                    else if silver { action = RemoteNavigation.clickpad(dx: rx, dy: ry, seconds: seconds) }
                    else if abs(rx) > 0.63 || abs(ry) > 0.63 { action = RemoteNavigation.clickpad(dx: rx, dy: ry, seconds: seconds) }
                    else { action = RemoteNavigation.touch(dx: dx, dy: dy, seconds: seconds) }
                    began = nil; touchPoint = .zero; trigger(action)
                })
        }
        #if os(macOS)
        .background {
            RemoteTrackpadSurface(caseSwipe:caseSwipe,send:trigger,activity:{trackpadActive=$0})
        }
        .help("Survolez le pavé et glissez à deux doigts, sans cliquer. Cliquez pour sélectionner.")
        #endif
        .accessibilityLabel(silver ? "Clickpad circulaire" : "Pavé tactile")
            .accessibilityHint(caseSwipe != nil ? "Glisser pour tourner la pochette. Cliquer sur les bords pour naviguer, au centre pour sélectionner." : "Glisser ou cliquer sur les bords pour naviguer, au centre pour sélectionner, maintenir pour les options")
            .accessibilityAction { trigger(.select) }
            .accessibilityAction(named: Text("Haut")) { trigger(.up) }
            .accessibilityAction(named: Text("Bas")) { trigger(.down) }
            .accessibilityAction(named: Text("Gauche")) { trigger(.left) }
            .accessibilityAction(named: Text("Droite")) { trigger(.right) }
            .accessibilityAction(named: Text("Options")) { trigger(.options) }
    }
    private var keyFill: LinearGradient { LinearGradient(colors: [Color(white: 0.22), Color(white: 0.075)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    private func roundKey(_ action: RemoteAction, symbol: String? = nil, text: String? = nil, size: CGFloat = 33, title: String) -> some View {
        Button { trigger(action) } label: {
            ZStack {
                Circle().fill(keyFill)
                Circle().strokeBorder(.white.opacity(text == "MENU" ? 0.85 : 0.18), lineWidth: text == "MENU" ? 1.5 : 0.8)
                if let symbol { Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold)) }
                if let text { Text(text).font(.system(size: 7, weight: .bold)) }
            }.frame(width: size, height: size)
        }.buttonStyle(RemotePressStyle()).accessibilityLabel(title).help(title)
    }
    private func volumeKey(_ action: RemoteAction, _ symbol: String) -> some View {
        Button { trigger(action) } label: { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 33, height: 38).contentShape(Rectangle()) }
            .buttonStyle(RemotePressStyle()).accessibilityLabel(label(action)).help(label(action))
    }
    private func accessory(_ action: RemoteAction, _ symbol: String) -> some View {
        Button { trigger(action) } label: { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, minHeight: 29).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }
            .buttonStyle(.plain).accessibilityLabel(label(action)).help(label(action))
    }
    private func trigger(_ action: RemoteAction) { lastAction = action; send(action) }
    private func label(_ action: RemoteAction) -> String {
        switch action {
        case .up: "Haut"; case .down: "Bas"; case .left: "Gauche"; case .right: "Droite"
        case .select: "Sélection"; case .options: "Options"; case .back: "Retour"; case .home: "Accueil"
        case .search: "Recherche"; case .playPause: "Lecture / pause"; case .rewind: "Reculer 15 s"
        case .forward: "Avancer 15 s"; case .previous: "Précédent"; case .next: "Suivant"
        case .fullscreen: "Plein écran"; case .volumeUp: "Volume +"; case .volumeDown: "Volume −"; case .mute: "Sourdine"
        }
    }
}
#if os(macOS)
/// Observe precise trackpad scroll without stealing mouse clicks from SwiftUI.
private struct RemoteTrackpadSurface: NSViewRepresentable {
    let caseSwipe: ((CasePadInput)->Void)?
    let send: (RemoteAction)->Void
    let activity: (Bool)->Void
    func makeNSView(context:Context)->RemoteTrackpadReceiver { RemoteTrackpadReceiver(frame:.zero) }
    func updateNSView(_ view:RemoteTrackpadReceiver,context:Context) {
        view.caseSwipe=caseSwipe;view.send=send;view.activity=activity
    }
    static func dismantleNSView(_ view:RemoteTrackpadReceiver,coordinator:()) { view.detach() }
}

@MainActor private final class RemoteTrackpadReceiver:NSView {
    var caseSwipe:((CasePadInput)->Void)?
    var send:((RemoteAction)->Void)?
    var activity:((Bool)->Void)?
    private var monitor:Any?
    private var active=false,rotationMode=false,ownsMomentum=false
    private var x=0.0,y=0.0
    private var navigation=RemoteScrollNavigation()
    private var idle:Task<Void,Never>?
    private var lastEvent:TimeInterval=0
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow();detach()
        guard window != nil else{return}
        monitor=NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self else{return event}
            return self.route(event)
        }
    }
    private func route(_ event:NSEvent)->NSEvent? {
        guard let window,event.window === window,event.hasPreciseScrollingDeltas,!isHiddenOrHasHiddenAncestor else{return event}
        let inside=bounds.contains(convert(event.locationInWindow,from:nil))
        if !event.momentumPhase.isEmpty {
            guard ownsMomentum else{return event}
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {ownsMomentum=false}
            return nil
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            if active {finish(cancelled:false)}
            ownsMomentum=false
            guard inside else{return event}
            ownsMomentum=true
            if event.phase.contains(.mayBegin) {return nil}
        }
        guard inside || active else{return event}
        if event.phase.contains(.cancelled) {finish(cancelled:true);return nil}
        let dx=Double(event.scrollingDeltaX),dy = -Double(event.scrollingDeltaY)
        if dx.isFinite,dy.isFinite,(dx != 0 || dy != 0) {
            if !active {
                active=true;ownsMomentum=true;rotationMode=caseSwipe != nil
                navigation=RemoteScrollNavigation();x=0;y=0;activity?(true)
            }
            if rotationMode {
                // Absolute displacement survives coalesced SwiftUI updates.
                x += dx;y += dy;caseSwipe?(.translation(x,y))
            } else if caseSwipe == nil,let direction=navigation.delta(dx,dy) {send?(direction)}
        }
        if event.phase.contains(.ended) {finish(cancelled:false);return nil}
        if active {
            lastEvent=ProcessInfo.processInfo.systemUptime
            if idle == nil {
                idle=Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds:100_000_000)
                        guard !Task.isCancelled,let self else{return}
                        if ProcessInfo.processInfo.systemUptime-self.lastEvent >= 0.18 {self.finish(cancelled:false);return}
                    }
                }
            }
        }
        return nil
    }
    private func finish(cancelled:Bool) {
        idle?.cancel();idle=nil
        guard active else{return}
        if rotationMode {caseSwipe?(cancelled ? .cancel:.finishTranslation(x,y))}
        active=false;rotationMode=false;x=0;y=0;activity?(false)
    }
    func detach() {
        if let monitor {NSEvent.removeMonitor(monitor);self.monitor=nil}
        idle?.cancel();idle=nil;active=false;rotationMode=false;ownsMomentum=false;x=0;y=0
    }
}
#endif
private struct RemotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1).scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
#endif

/// Desktop/mobile gamepad bridge. On Apple TV we do NOT intercept physical
/// touch events: the system focus engine handles swipes/clicks natively.
@MainActor final class RemoteInputBridge: ObservableObject {
    private var action: ((RemoteAction) -> Void)?
    private var observer: AnyCancellable?
    private var disconnectObserver: AnyCancellable?
    private var connected: [GCController] = []
    private var lastDirection: [ObjectIdentifier: RemoteAction] = [:]
    private var lastMove: [ObjectIdentifier: Date] = [:]
    func connect(_ handler: @escaping (RemoteAction) -> Void) {
        #if !os(tvOS)
        disconnect(); action = handler
        observer = NotificationCenter.default.publisher(for: .GCControllerDidConnect).receive(on: DispatchQueue.main).sink { [weak self] note in if let controller = note.object as? GCController { self?.bind(controller) } }
        disconnectObserver = NotificationCenter.default.publisher(for: .GCControllerDidDisconnect).receive(on: DispatchQueue.main).sink { [weak self] note in if let c = note.object as? GCController { self?.unbind(c) } }
        GCController.controllers().forEach(bind)
        #endif
    }
    func disconnect() { observer = nil; disconnectObserver = nil; for c in connected { clear(c) }; connected = []; lastDirection = [:]; lastMove = [:]; action = nil }
    private func bind(_ c: GCController) {
        guard !connected.contains(where: { $0 === c }) else { return }; connected.append(c)
        let identity = ObjectIdentifier(c)
        let move: GCControllerDirectionPadValueChangedHandler = { [weak self] _, x, y in Task { @MainActor in self?.move(identity: identity, x: x, y: y) } }
        if let pad = c.extendedGamepad {
            pad.dpad.valueChangedHandler = move; pad.leftThumbstick.valueChangedHandler = move
            bindButton(pad.buttonA, .select); bindButton(pad.buttonB, .back); bindButton(pad.buttonX, .playPause); bindButton(pad.buttonY, .options)
            bindButton(pad.buttonMenu, .home); bindButton(pad.leftShoulder, .previous); bindButton(pad.rightShoulder, .next)
            bindButton(pad.leftTrigger, .rewind); bindButton(pad.rightTrigger, .forward)
        } else if let pad = c.microGamepad {
            pad.dpad.valueChangedHandler = move
            bindButton(pad.buttonA, .select); bindButton(pad.buttonX, .playPause); bindButton(pad.buttonMenu, .back)
        }
    }
    private func bindButton(_ button: GCControllerButtonInput, _ command: RemoteAction) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.action?(command) } } }
    }
    private func move(identity: ObjectIdentifier, x: Float, y: Float) {
        guard max(abs(x), abs(y)) >= 0.48 else { if max(abs(x), abs(y)) < 0.20 { lastDirection[identity] = nil }; return }
        let command: RemoteAction = abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
        let now = Date()
        if lastDirection[identity] == command && now.timeIntervalSince(lastMove[identity] ?? .distantPast) < 0.24 { return }
        lastDirection[identity] = command; lastMove[identity] = now; action?(command)
    }
    private func unbind(_ controller: GCController) { clear(controller); connected.removeAll { $0 === controller }; lastDirection[ObjectIdentifier(controller)] = nil; lastMove[ObjectIdentifier(controller)] = nil }
    private func clear(_ c: GCController) {
        if let p = c.extendedGamepad { p.dpad.valueChangedHandler = nil; p.leftThumbstick.valueChangedHandler = nil; for b in [p.buttonA,p.buttonB,p.buttonX,p.buttonY,p.buttonMenu,p.leftShoulder,p.rightShoulder,p.leftTrigger,p.rightTrigger] { b.pressedChangedHandler = nil } }
        if let p = c.microGamepad { p.dpad.valueChangedHandler = nil; for b in [p.buttonA,p.buttonX,p.buttonMenu] { b.pressedChangedHandler = nil } }
    }
}
