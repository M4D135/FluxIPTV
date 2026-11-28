import SwiftUI

#if os(tvOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - The pointer of a television
//
// "un mode pointeur souris avec la télécommande appletv pavé tactile, faut
// pouvoir choisir mode classique ou mode souris, soit dans option soit un
// système facile pour basculer, voire les deux" (David, 27/11).
//
// The screens of a television stand inside a controller of their own. In
// the mode « Souris » it draws a pointer over them that follows the thumb on
// the touch surface, and hands the focus of tvOS to the control under it:
// that control shows itself as the remote shows it, and the click of the
// remote presses it, as a click presses it in the mode « Classique ». The
// swipes no longer go from one control to the next; a press of the arrows
// still does, and the pointer goes along. Play/Pause held down goes from one
// mode to the other.

/// What the screens share with the pointer.
@MainActor final class FluxPointerState {
    static let shared = FluxPointerState()
    /// Something under the screen takes the thumb itself: the picture.
    var suspended = false {
        didSet { if suspended != oldValue { controller?.refresh() } }
    }
    /// Whether the pointer is the remote now.
    var active: Bool { controller?.pointerActive ?? false }

    /// The controllers of the pointer on screen, the last one above the
    /// others: a panel that covers the whole screen brings its own, as the
    /// studio does.
    private var controllers: [WeakController] = []
    private struct WeakController { weak var value: FluxPointerController? }
    /// The pointer of the panel on top, or of the screens.
    var controller: FluxPointerController? { controllers.last { $0.value != nil }?.value }

    fileprivate func enter(_ controller: FluxPointerController) {
        controllers.removeAll { $0.value == nil || $0.value === controller }
        controllers.append(WeakController(value: controller))
    }

    fileprivate func leave(_ controller: FluxPointerController) {
        controllers.removeAll { $0.value == nil || $0.value === controller }
    }

    /// The control the pointer is handing the focus to, and when. A screen
    /// that sends the remote entering a column to the row chosen there
    /// leaves it where the pointer rests.
    fileprivate var pointing: (id: String, at: TimeInterval)?

    /// Whether the pointer has just asked the focus for the control `id`.
    func isPointing(at id: String) -> Bool {
        guard let pointing else { return false }
        return pointing.id == id && ProcessInfo.processInfo.systemUptime - pointing.at < 0.6
    }

    /// A screen moved its own selection, which the pointer may rest on.
    func selectionMoved() { controller?.selectionMoved() }

    /// Where the last control that took the focus stands, in the points of
    /// the screen, in either mode. The strips at the edges are too thin to
    /// count: a strip that takes the remote leaves here the control it came
    /// from (`FluxScreen.crossEdge`).
    var lastFocusFrame: CGRect?

    /// Whether a move command moves the selection of a screen that moves
    /// its own: with the pointer, a swipe moves the pointer only, and the
    /// arrows still move the selection.
    var movesSelection: Bool { controller?.movesSelection ?? true }

    #if FLUX_CATALOG_UI_TESTING
    /// What the screen says holds the remote, for a bench.
    var benchFocus: String?
    /// What a bench reads: the bubbles shown, the controls a sweep crossed.
    fileprivate var toasts = 0
    fileprivate var trace: [String] = []
    /// Requests of the focus the pointer made.
    fileprivate var asked = 0
    fileprivate var swept = false

    /// Every pointer on screen says the same: a bench finds whichever.
    fileprivate func report() {
        for entry in controllers { entry.value?.report() }
    }
    #endif

    // MARK: Lecture/Pause, pressed or held
    //
    // Held down, Lecture/Pause changes the mode; pressed, it does what the
    // screen gives it. SwiftUI hands the press over as the key goes down,
    // before anyone knows whether it will be held: while the hold can change
    // the mode, the press waits for the key to rise, and a hold drops it.

    /// The controller watches the key: the hold can change the mode.
    fileprivate(set) var watchesPlayPause = false
    private var playPauseDown = false
    private var playPauseHeld = false
    /// When the key last rose, and whether it had been held.
    private var playPauseRose: TimeInterval = -1
    private var playPauseRoseHeld = false
    private var pendingPlayPause: (() -> Void)?
    private var pendingFallback: Task<Void, Never>?

    /// What a press of Lecture/Pause does in the screens.
    func playPause(_ action: @escaping () -> Void) {
        guard watchesPlayPause else { action(); return }
        if playPauseDown {
            if !playPauseHeld { wait(action) }
            return
        }
        // The key has just risen: SwiftUI spoke after it.
        if ProcessInfo.processInfo.systemUptime - playPauseRose < 0.35 {
            if !playPauseRoseHeld { action() }
            return
        }
        // SwiftUI spoke before the controller saw the key go down.
        wait(action)
    }

    private func wait(_ action: @escaping () -> Void) {
        pendingPlayPause = action
        pendingFallback?.cancel()
        pendingFallback = Task { @MainActor [weak self] in
            // A key that never says it rose does not lose its press.
            try? await Task.sleep(nanoseconds: UInt64((FluxRemoteMode.holdDuration + 0.4) * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.playPauseHeld else { return }
            self.flushPlayPause()
        }
    }

    private func flushPlayPause() {
        pendingFallback?.cancel()
        pendingFallback = nil
        let action = pendingPlayPause
        pendingPlayPause = nil
        action?()
    }

    fileprivate func playPauseWentDown() {
        playPauseDown = true
        playPauseHeld = false
    }

    fileprivate func playPauseWasHeld() {
        playPauseHeld = true
        pendingPlayPause = nil
        pendingFallback?.cancel()
        pendingFallback = nil
    }

    fileprivate func playPauseWentUp() {
        guard playPauseDown else { return }
        playPauseDown = false
        playPauseRose = ProcessInfo.processInfo.systemUptime
        playPauseRoseHeld = playPauseHeld
        if playPauseHeld { pendingPlayPause = nil } else { flushPlayPause() }
        playPauseHeld = false
    }

    fileprivate func stopWatchingPlayPause() {
        watchesPlayPause = false
        playPauseDown = false
        playPauseHeld = false
        flushPlayPause()
    }
}

// MARK: - What the pointer can rest on
//
// UIKit lists the controls of SwiftUI as focus items, with their frames, but
// a request of UIKit does not give them the focus (tvOS 27.2, bench of the
// 0.9.4: 43 requests, none granted): SwiftUI keeps the focus where its own
// focus state says. Each control therefore says where it stands and how its
// screen gives it the focus, as the screens do it themselves.

/// The controls of the screens, as they stand on the screen.
@MainActor final class FluxPointerTargets {
    static let shared = FluxPointerTargets()

    struct Target {
        let id: String
        /// What its list shows of it.
        var frame: CGRect
        /// The whole of it, part of which a list may hide.
        var full: CGRect
        /// The pointer whose screens hold the control.
        let layer: UUID
        /// Gives the focus to the control, through the focus state of its screen.
        let focus: (_ again: Bool) -> Void
        /// For a place that is no control: whether its screen has selected
        /// it. A control says nothing: it has the focus or not.
        let holds: (() -> Bool)?
    }

    /// By control on screen: two controls may share an identifier, as the
    /// icon of a destination on the home screen and in the bar.
    private var targets: [UUID: Target] = [:]
    /// The identifier that holds the focus now, as the screen says. The
    /// pointer then knows that the control under it took the focus.
    var focusedID: String? {
        didSet { if focusedID != oldValue { FluxPointerState.shared.controller?.focusMoved() } }
    }

    var count: Int { targets.count }

    func set(_ token: UUID, _ target: Target) { targets[token] = target }
    func remove(_ token: UUID) { targets[token] = nil }

    /// The controls of one pointer's screens.
    func targets(in layer: UUID) -> [Target] { targets.values.filter { $0.layer == layer } }

    /// The control of `layer` under `point`, chosen as `FluxPointerTarget.pick` does.
    func target(at point: CGPoint, tolerance: Double, in layer: UUID) -> Target? {
        let list = targets(in: layer)
        return FluxPointerTarget.pick(point, frames: list.map(\.frame), tolerance: tolerance).map { list[$0] }
    }

    /// A page that the pointer scrolls by pushing its edges (`fluxPointerPage`),
    /// or a list that scrolls under it (`fluxPointerList`).
    struct Page {
        /// What shows of it, on the screen.
        let frame: CGRect
        let layer: UUID
        /// The scroll view that SwiftUI draws it in.
        weak var scroll: UIScrollView?
        /// A list: over it the pointer becomes a scroll pointer.
        var list = false
    }

    private var pages: [UUID: Page] = [:]

    func setPage(_ token: UUID, _ page: Page) { pages[token] = page }
    func removePage(_ token: UUID) { pages[token] = nil }

    func pages(in layer: UUID) -> [Page] { pages.values.filter { $0.layer == layer && $0.scroll != nil && !$0.list } }

    /// The page of `layer` that shows at `point`, the innermost.
    func page(at point: CGPoint, in layer: UUID) -> Page? {
        pages(in: layer).filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// The list of `layer` that shows at `point`, the innermost, and its token.
    func list(at point: CGPoint, in layer: UUID) -> (token: UUID, list: Page)? {
        pages.filter { $0.value.layer == layer && $0.value.list && $0.value.scroll != nil && $0.value.frame.contains(point) }
            .min { $0.value.frame.width * $0.value.frame.height < $1.value.frame.width * $1.value.frame.height }
            .map { ($0.key, $0.value) }
    }

    /// The list `token`, while it shows.
    func list(_ token: UUID) -> Page? {
        guard let page = pages[token], page.list, page.scroll != nil, !page.frame.isNull, !page.frame.isEmpty else { return nil }
        return page
    }
}

private struct FluxPointerLayerKey: EnvironmentKey {
    static var defaultValue: UUID? { nil }
}

extension EnvironmentValues {
    /// The pointer whose screens these are: a panel that covers the whole
    /// screen has its own, and the pointer of the screens under it leaves
    /// its controls alone.
    var fluxPointerLayer: UUID? {
        get { self[FluxPointerLayerKey.self] }
        set { self[FluxPointerLayerKey.self] = newValue }
    }
}

private struct FluxPointerTargetModifier: ViewModifier {
    let id: String
    let focus: (_ again: Bool) -> Void
    let holds: (() -> Bool)?
    /// What stands under a panel is disabled: the pointer leaves it alone.
    @Environment(\.isEnabled) private var enabled
    @Environment(\.fluxPointerLayer) private var layer
    /// Its token, and its last frame, which redraw nothing as they change.
    @State private var place = Place()

    final class Place {
        let token = UUID()
        var frame = CGRect.null
        var full = CGRect.null
    }

    /// What shows of a control, and the whole of it.
    struct Frames: Equatable {
        var shown: CGRect
        var full: CGRect
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Frames.self) { Frames(shown: Self.shownFrame($0), full: $0.frame(in: .global)) } action: { frames in
                place.frame = frames.shown
                place.full = frames.full
                record(enabled: enabled)
            }
            .onChange(of: enabled) { _, now in record(enabled: now) }
            .onDisappear { FluxPointerTargets.shared.remove(place.token) }
    }

    /// The part of the control that its list shows: a row scrolled out of
    /// its list keeps a frame, under the bar or the column, where the
    /// pointer must not find it.
    fileprivate static func shownFrame(_ proxy: GeometryProxy) -> CGRect {
        let global = proxy.frame(in: .global)
        // A rail that scrolls sideways inside a list that scrolls down: both
        // cut the control.
        var local = CGRect(origin: .zero, size: proxy.size)
        for axis in [Axis.horizontal, .vertical] {
            if let shown = proxy.bounds(of: .scrollView(axis: axis)) { local = local.intersection(shown) }
        }
        return local.isNull || local.isEmpty ? .null : local.offsetBy(dx: global.minX, dy: global.minY)
    }

    private func record(enabled: Bool) {
        let frame = place.frame
        guard enabled, let layer, !frame.isNull, frame.width > 12, frame.height > 12 else {
            FluxPointerTargets.shared.remove(place.token)
            return
        }
        FluxPointerTargets.shared.set(place.token, .init(id: id, frame: frame, full: place.full.isNull ? frame : place.full,
                                                         layer: layer, focus: focus, holds: holds))
    }
}

extension View {
    /// The pointer of a television can rest on this control and give it the
    /// focus. After `.focused(binding, equals: id)`, never between a button
    /// and it.
    func fluxPointerTarget(_ id: String, _ binding: FocusState<String?>.Binding) -> some View {
        fluxPointerTarget(id, id: id, binding)
    }

    /// The same, for a focus state of another kind: `id` names the control.
    func fluxPointerTarget<Value: Hashable>(_ value: Value, id: String, _ binding: FocusState<Value?>.Binding) -> some View {
        modifier(FluxPointerTargetModifier(id: id, focus: { again in
            // A request the system declined keeps its value: asked again,
            // it is cleared first.
            if again { binding.wrappedValue = nil }
            binding.wrappedValue = value
        }, holds: nil))
    }

    /// The same, for the one control of a focus state that is on or off.
    func fluxPointerTarget(_ id: String, _ binding: FocusState<Bool>.Binding) -> some View {
        modifier(FluxPointerTargetModifier(id: id, focus: { again in
            if again { binding.wrappedValue = false }
            binding.wrappedValue = true
        }, holds: nil))
    }

    /// A place that is no control, in a screen that moves its own
    /// selection: the pointer selects it as the arrows would, and a click
    /// presses what is selected.
    func fluxPointerTarget(_ id: String, select: @escaping () -> Void, isSelected: @escaping () -> Bool) -> some View {
        modifier(FluxPointerTargetModifier(id: id, focus: { _ in select() }, holds: isSelected))
    }

    /// The content of a page longer than the screen, inside its scroll
    /// view: pushed against the top or the bottom of what shows of it, the
    /// pointer stays there and the page scrolls (`FluxPointerScroll`).
    func fluxPointerPage() -> some View {
        modifier(FluxPointerPageModifier(list: false))
    }

    /// The content of a list that scrolls down, inside its scroll view:
    /// "sur une liste on passe sur un pointeur défilement au survol et on
    /// change le fonctionnement au survol de la zone pour haut et bas, on
    /// ressort par droite gauche de la zone" (David, 27/11). Over it the
    /// pointer becomes a scroll pointer that stays put: up and down scroll
    /// the list under it, and the row under it takes the remote; across, it
    /// goes along the row, and a pull past a side takes it out.
    func fluxPointerList() -> some View {
        modifier(FluxPointerPageModifier(list: true))
    }
}

private struct FluxPointerPageModifier: ViewModifier {
    let list: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.fluxPointerLayer) private var layer
    @State private var place = Place()

    final class Place {
        let token = UUID()
        var frame = CGRect.null
        weak var scroll: UIScrollView?
    }

    func body(content: Content) -> some View {
        content
            .background {
                FluxScrollFinder { scroll in
                    place.scroll = scroll
                    record(enabled: enabled)
                }
                .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGRect.self) { FluxPointerTargetModifier.shownFrame($0) } action: { frame in
                place.frame = frame
                record(enabled: enabled)
            }
            .onChange(of: enabled) { _, now in record(enabled: now) }
            .onDisappear { FluxPointerTargets.shared.removePage(place.token) }
    }

    private func record(enabled: Bool) {
        guard enabled, let layer, let scroll = place.scroll, !place.frame.isNull, !place.frame.isEmpty else {
            FluxPointerTargets.shared.removePage(place.token)
            return
        }
        FluxPointerTargets.shared.setPage(place.token, .init(frame: place.frame, layer: layer, scroll: scroll, list: list))
    }
}

/// The scroll view that SwiftUI draws a page in, found from inside the page.
private struct FluxScrollFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.found = found
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.found = found
    }

    final class Probe: UIView {
        var found: ((UIScrollView) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    found?(scroll)
                    return
                }
                view = current.superview
            }
        }
    }
}

/// The settings of the pointer, as the screens save them.
struct FluxPointerSettings: Equatable {
    var mode = FluxRemoteMode.defaultValue
    var toggles = FluxRemoteMode.toggleDefault
    var speed = FluxPointerSpeed.defaultValue
    var acceleration = FluxPointerAcceleration.defaultValue
    var size = FluxPointerSize.defaultValue
    var shape = FluxPointerShape.defaultValue
    var color = FluxPointerColor.defaultValue

    var motion: FluxPointerMotion { FluxPointerMotion(speed: speed, acceleration: acceleration) }
}

/// The screens of a television, under the controller of the pointer.
struct FluxRemoteHost<Content: View>: View {
    @AppStorage(FluxRemoteMode.storageKey) private var mode = FluxRemoteMode.defaultValue.rawValue
    @AppStorage(FluxRemoteMode.toggleKey) private var toggles = FluxRemoteMode.toggleDefault
    @AppStorage(FluxPointerSpeed.storageKey) private var speed = FluxPointerSpeed.defaultValue.rawValue
    @AppStorage(FluxPointerAcceleration.storageKey) private var acceleration = FluxPointerAcceleration.defaultValue.rawValue
    @AppStorage(FluxPointerSize.storageKey) private var size = FluxPointerSize.defaultValue.rawValue
    @AppStorage(FluxPointerShape.storageKey) private var shape = FluxPointerShape.defaultValue.rawValue
    @AppStorage(FluxPointerColor.storageKey) private var color = FluxPointerColor.defaultValue.rawValue
    @Environment(\.scenePhase) private var phase
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    private var settings: FluxPointerSettings {
        FluxPointerSettings(mode: FluxRemoteMode(rawValue: mode) ?? .defaultValue, toggles: toggles,
                            speed: FluxPointerSpeed(rawValue: speed) ?? .defaultValue,
                            acceleration: FluxPointerAcceleration(rawValue: acceleration) ?? .defaultValue,
                            size: FluxPointerSize(rawValue: size) ?? .defaultValue,
                            shape: FluxPointerShape(rawValue: shape) ?? .defaultValue,
                            color: FluxPointerColor(rawValue: color) ?? .defaultValue)
    }

    var body: some View {
        FluxPointerHost(content: content, settings: settings, phase: phase)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }
}

/// The phase of the scene, for screens hosted in a controller of their
/// own: the environment of the scene does not cross into it.
final class FluxPhaseRelay: ObservableObject {
    @Published var phase: ScenePhase
    init(_ phase: ScenePhase) { self.phase = phase }
}

private struct FluxPhaseRoot<Content: View>: View {
    @ObservedObject var relay: FluxPhaseRelay
    let layer: UUID
    let content: Content
    var body: some View {
        content.environment(\.scenePhase, relay.phase).environment(\.fluxPointerLayer, layer)
    }
}

private struct FluxPointerHost<Content: View>: UIViewControllerRepresentable {
    let content: () -> Content
    let settings: FluxPointerSettings
    let phase: ScenePhase

    func makeUIViewController(context: Context) -> FluxPointerController {
        let relay = FluxPhaseRelay(phase)
        let layer = UUID()
        // The screens are given once: their state lives in the controller.
        let controller = FluxPointerController(root: AnyView(FluxPhaseRoot(relay: relay, layer: layer, content: content())),
                                               relay: relay, layer: layer)
        controller.apply(settings)
        return controller
    }

    func updateUIViewController(_ controller: FluxPointerController, context: Context) {
        if controller.relay.phase != phase { controller.relay.phase = phase }
        controller.apply(settings)
    }
}

@MainActor final class FluxPointerController: UIViewController, UIGestureRecognizerDelegate {
    let relay: FluxPhaseRelay
    /// What its screens' controls name as their pointer.
    let layer: UUID
    private let screens: UIHostingController<AnyView>
    private let cursor = FluxPointerCursor()
    private let toast = FluxPointerToast()
    private var settings = FluxPointerSettings()
    private var applied = false

    /// Where the pointer is, in the points of the screen.
    private var position = CGPoint(x: 960, y: 540)
    private var lastTranslation = CGPoint.zero
    private var lastHover: CFTimeInterval = 0
    private var hideTask: Task<Void, Never>?
    /// The control the pointer asked the focus for: its arrival is no move
    /// of anyone else.
    private weak var requested: (any UIFocusItem)?
    /// The control the pointer asked the focus for, and when.
    private var asking: (id: String, at: CFTimeInterval)?
    /// A press of the arrows still goes from one control to the next: while
    /// an arrow is down, and for a moment after it rose.
    private var arrowDown = false
    private var arrowsUntil: TimeInterval = 0
    private var arrowsMove: Bool { arrowDown || ProcessInfo.processInfo.systemUptime < arrowsUntil }
    /// A control has been found under the pointer: the controls of the
    /// screens can be found. Until then a click is never held back.
    private var found = false
    private var overNothing = false
    /// A page the pointer pushed draws itself again before the pointer
    /// looks at what came under it.
    private var settle: Task<Void, Never>?
    /// The list the pointer rides as a scroll pointer, and how far it is
    /// pulled past a side of it.
    private var rail: UUID?
    private var railMotion = FluxPointerRail()

    private lazy var pan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.allowedPressTypes = []
        pan.cancelsTouchesInView = false
        pan.delegate = self
        return pan
    }()
    private lazy var hold: UILongPressGestureRecognizer = {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        hold.allowedTouchTypes = []
        hold.minimumPressDuration = FluxRemoteMode.holdDuration
        hold.delegate = self
        return hold
    }()
    /// When Lecture/Pause goes down and rises: a press waits for it while
    /// the hold can change the mode (`FluxPointerState.playPause`).
    private lazy var playPauseWatch: UILongPressGestureRecognizer = {
        let watch = UILongPressGestureRecognizer(target: self, action: #selector(playPauseWatched(_:)))
        watch.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        watch.allowedTouchTypes = []
        watch.minimumPressDuration = 0
        watch.cancelsTouchesInView = false
        watch.delegate = self
        return watch
    }()
    private lazy var arrows: FluxArrowWatch = {
        let arrows = FluxArrowWatch()
        arrows.allowedPressTypes = [UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow]
            .map { NSNumber(value: $0.rawValue) }
        arrows.allowedTouchTypes = []
        arrows.cancelsTouchesInView = false
        arrows.delaysTouchesEnded = false
        arrows.delegate = self
        arrows.changed = { [weak self] down in
            guard let self else { return }
            arrowDown = down
            arrowsUntil = ProcessInfo.processInfo.systemUptime + 0.6
        }
        return arrows
    }()
    /// A click on nothing presses nothing, as a click of a mouse.
    private lazy var idleClick: UILongPressGestureRecognizer = {
        let click = UILongPressGestureRecognizer(target: self, action: #selector(idleClicked(_:)))
        click.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        click.allowedTouchTypes = []
        click.minimumPressDuration = 0
        click.delegate = self
        click.isEnabled = false
        return click
    }()

    init(root: AnyView, relay: FluxPhaseRelay, layer: UUID) {
        self.relay = relay
        self.layer = layer
        screens = UIHostingController(rootView: root)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        screens.overrideUserInterfaceStyle = .dark
        addChild(screens)
        screens.view.frame = view.bounds
        screens.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(screens.view)
        screens.didMove(toParent: self)
        cursor.alpha = 0
        view.addSubview(cursor)
        view.addSubview(toast)
        for recognizer in [pan, hold, playPauseWatch, arrows, idleClick] as [UIGestureRecognizer] { view.addGestureRecognizer(recognizer) }
        FluxPointerState.shared.enter(self)
        #if FLUX_CATALOG_UI_TESTING
        probe.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        probe.isAccessibilityElement = true
        probe.accessibilityLabel = "Pointeur"
        probe.accessibilityIdentifier = "flux-pointer-state"
        view.addSubview(probe)
        #endif
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Back above the others, or above for the first time: a panel that
        // covered the screens has closed, or this one has just opened.
        FluxPointerState.shared.enter(self)
        refresh()
        #if FLUX_CATALOG_UI_TESTING
        // "pointer", or any screen with FLUX_UI_POINTER=1: a sweep of the
        // pointer, once, over whatever pointer is on top as it goes.
        let environment = ProcessInfo.processInfo.environment
        let scenario = environment["FLUX_UI_SCENARIO"] ?? ""
        guard scenario == "pointer" || scenario == "pointer-list" || environment["FLUX_UI_POINTER"] == "1",
              !FluxPointerState.shared.swept else { return }
        FluxPointerState.shared.swept = true
        Task { @MainActor in await FluxPointerController.sweep(scenario) }
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Covered by a panel of its own, or closed: the pointer above, if
        // any, is the remote.
        FluxPointerState.shared.leave(self)
        hide(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        position = FluxPointerMotion.clamp(position, to: view.bounds)
        toast.place(in: view.bounds)
        cursor.place(at: position)
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [screens] }

    /// The pointer is the remote: the mode is « Souris », and nothing stands
    /// over the screens that takes the thumb itself.
    var pointerActive: Bool {
        settings.mode == .pointer && !FluxPointerState.shared.suspended
            && presentedViewController == nil && screens.presentedViewController == nil
    }

    func apply(_ next: FluxPointerSettings) {
        let previous = settings
        settings = next
        restyle()
        guard applied else { applied = true; refresh(); return }
        if previous.mode != next.mode {
            if next.mode == .pointer { placeOnFocus() } else { leaveRail() }
            refresh()
            announce(next.mode)
        } else if previous.toggles != next.toggles {
            refresh()
        }
    }

    /// The pointer as the settings draw it, or the scroll pointer over a list.
    private func restyle() {
        cursor.style(shape: settings.shape, color: settings.color, height: Desk.tv(CGFloat(settings.size.height)), riding: rail != nil)
        cursor.place(at: position)
    }

    /// A bubble says the new mode, however it came: Lecture/Pause held down,
    /// or the settings, from which the mode « Souris » could not be left in
    /// 0.9.8 ("pour basculer de mode c ok standard vers souris mais pas le
    /// contraire", David, 27/11). The pointer on top speaks for all.
    private func announce(_ mode: FluxRemoteMode) {
        guard FluxPointerState.shared.controller.map({ $0 === self }) ?? true else { return }
        toast.show(mode == .pointer ? "Mode souris" : "Mode classique", symbol: mode.symbol,
                   hint: settings.toggles ? "Maintenez Lecture/Pause pour changer" : "Réglages › Télécommande pour changer")
        #if FLUX_CATALOG_UI_TESTING
        FluxPointerState.shared.toasts += 1
        FluxPointerState.shared.report()
        #endif
    }

    /// The recognizers and the pointer follow the mode and what covers the
    /// screens.
    func refresh() {
        guard isViewLoaded else { return }
        let active = pointerActive
        if !active { leaveRail() }
        pan.isEnabled = active
        arrows.isEnabled = active
        hold.isEnabled = settings.toggles && !FluxPointerState.shared.suspended
        playPauseWatch.isEnabled = hold.isEnabled
        if hold.isEnabled { FluxPointerState.shared.watchesPlayPause = true }
        else if FluxPointerState.shared.watchesPlayPause { FluxPointerState.shared.stopWatchingPlayPause() }
        updateIdleClick()
        if active { show() } else { hide(animated: true) }
        #if FLUX_CATALOG_UI_TESTING
        report()
        #endif
    }

    // MARK: Focus

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        guard super.shouldUpdateFocus(in: context) else { return false }
        // A swipe goes no longer from one control to the next: the pointer
        // goes where the thumb goes. What the screens move themselves, and
        // the arrows, still move.
        guard pointerActive, !context.focusHeading.isEmpty else { return true }
        return arrowsMove
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        // Where the remote is, in either mode, for the edges of the screen.
        if let next = context.nextFocusedItem, let frame = frame(of: next), frame.width > 12, frame.height > 12 {
            FluxPointerState.shared.lastFocusFrame = frame
        }
        guard pointerActive, let next = context.nextFocusedItem else { return }
        // The arrows or a screen took the remote off the list the pointer
        // rides: it is a pointer again.
        if let token = rail, let frame = frame(of: next),
           !(FluxPointerTargets.shared.list(token)?.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) ?? false) {
            leaveRail()
        }
        if let requested, requested === next {
            self.requested = nil
            overNothing = false
            updateIdleClick()
            return
        }
        guard let frame = frame(of: next) else { return }
        // The control the pointer rests on: it stays under the thumb, and
        // once it has the focus a click on it no longer waits, whichever
        // screen gave it the focus.
        if frame.insetBy(dx: -24, dy: -24).contains(position) {
            if let target = pointedTarget(), target.holds == nil, FluxPointerTarget.same(frame, target.frame) {
                overNothing = false
                asking = nil
                updateIdleClick()
            }
            return
        }
        // Another hand moved the remote, the arrows, Play/Pause, a screen
        // that opened: the pointer goes along, onto what has the focus.
        move(to: CGPoint(x: frame.midX, y: frame.midY), animated: true)
        overNothing = false
        updateIdleClick()
    }

    private func placeOnFocus() {
        if let item = UIFocusSystem.focusSystem(for: view)?.focusedItem, let frame = frame(of: item) {
            position = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        cursor.place(at: position)
    }

    /// The frame of a control, in the points of the screen.
    private func frame(of item: any UIFocusItem) -> CGRect? {
        guard let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else { return nil }
        let frame = space.convert(item.frame, to: view)
        return frame.isNull || frame.isInfinite ? nil : frame
    }

    /// The controls that can take the focus near `point`, with their frames.
    private func controls(near point: CGPoint, radius: CGFloat) -> [(item: any UIFocusItem, frame: CGRect)] {
        var result: [(item: any UIFocusItem, frame: CGRect)] = []
        var seen = Set<ObjectIdentifier>()
        let probe = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        func visit(_ container: any UIFocusItemContainer, depth: Int) {
            let space = container.coordinateSpace
            for item in container.focusItems(in: view.convert(probe, to: space)) {
                guard seen.insert(ObjectIdentifier(item)).inserted else { continue }
                if item.canBecomeFocused {
                    let frame = space.convert(item.frame, to: view)
                    if !frame.isNull, !frame.isInfinite, frame.width > 12, frame.height > 12 { result.append((item, frame)) }
                }
                if depth < 10, let inner = item.focusItemContainer, (inner as AnyObject) !== (container as AnyObject) {
                    visit(inner, depth: depth + 1)
                }
            }
        }
        if let root = screens.view.focusItemContainer { visit(root, depth: 0) }
        // The containers between the control that has the focus and the
        // screens may list controls that the screens do not.
        if result.isEmpty, let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem {
            var environment = focused.parentFocusEnvironment
            var steps = 0
            while let current = environment, steps < 24 {
                if let container = current.focusItemContainer { visit(container, depth: 0) }
                environment = current.parentFocusEnvironment
                steps += 1
            }
        }
        return result
    }

    /// Hands the focus to the control under the pointer.
    private func hover(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastHover >= 1.0 / 30 else { return }
        lastHover = now
        // The controls say where they stand (`fluxPointerTarget`), and their
        // screen gives them the focus.
        if let target = pointedTarget() {
            found = true
            // Until the control has taken the focus, a click would press
            // the one that still has it: the click waits for it.
            overNothing = !holds(target)
            updateIdleClick()
            guard overNothing else { asking = nil; return }
            // Asked again after a moment: the first request was declined.
            if let asking, asking.id == target.id {
                guard now - asking.at > 0.3 else { return }
                self.asking = (target.id, now)
                FluxPointerState.shared.pointing = (target.id, ProcessInfo.processInfo.systemUptime)
                target.focus(true)
            } else {
                asking = (target.id, now)
                FluxPointerState.shared.pointing = (target.id, ProcessInfo.processInfo.systemUptime)
                target.focus(false)
            }
            // A screen that moves its own selection has moved it already.
            if target.holds?() == true {
                overNothing = false
                asking = nil
                updateIdleClick()
            }
            #if FLUX_CATALOG_UI_TESTING
            FluxPointerState.shared.asked += 1
            #endif
            return
        }
        // A control that says nothing is still a control: a click on it is
        // not held back.
        let near = controls(near: position, radius: 20)
        guard let index = FluxPointerTarget.pick(position, frames: near.map(\.frame), tolerance: 14) else {
            overNothing = true
            updateIdleClick()
            return
        }
        found = true
        overNothing = false
        updateIdleClick()
        let item = near[index].item
        guard let system = UIFocusSystem.focusSystem(for: view), system.focusedItem !== item else { return }
        requested = item
        system.requestFocusUpdate(to: item)
        system.updateFocusIfNeeded()
        // Declined: a click would press the control that kept the focus.
        if system.focusedItem !== item {
            overNothing = true
            updateIdleClick()
        }
    }

    /// The screen says the focus moved: perhaps to the control under the
    /// pointer, whose click no longer waits. Nothing is asked here: the
    /// screen may have moved the focus itself.
    func focusMoved() {
        guard pointerActive, let target = pointedTarget() else { return }
        overNothing = !holds(target)
        if !overNothing { asking = nil }
        updateIdleClick()
    }

    /// A screen that moves its own selection moved it. Under the pointer,
    /// the click presses it; moved by the arrows, the pointer goes along,
    /// as it goes along with the focus.
    func selectionMoved() {
        guard pointerActive else { return }
        let targets = FluxPointerTargets.shared
        if let target = pointedTarget(), holds(target) {
            overNothing = false
            asking = nil
            updateIdleClick()
            return
        }
        guard let selected = targets.targets(in: layer).first(where: { $0.holds?() == true }) else { return }
        move(to: CGPoint(x: selected.frame.midX, y: selected.frame.midY), animated: true)
        overNothing = false
        asking = nil
        updateIdleClick()
    }

    /// A swipe moves the pointer only; the arrows still move a selection.
    var movesSelection: Bool { !pointerActive || arrowsMove }

    /// Whether `target` has the focus: its screen says so, or the control
    /// that has the focus stands where it stands. The screens with a focus
    /// of their own — a fiche, a panel, the settings — say nothing to the
    /// window, whose focus state then names none of them.
    private func holds(_ target: FluxPointerTargets.Target) -> Bool {
        if let holds = target.holds { return holds() }
        if FluxPointerTargets.shared.focusedID == target.id { return true }
        guard let item = UIFocusSystem.focusSystem(for: view)?.focusedItem, let frame = frame(of: item) else { return false }
        return FluxPointerTarget.same(frame, target.frame)
    }

    private func updateIdleClick() {
        idleClick.isEnabled = pointerActive && found && overNothing
    }

    // MARK: The thumb

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            lastTranslation = .zero
            stopGlide()
            show()
            fallthrough
        case .changed:
            let translation = pan.translation(in: view)
            let dx = Double(translation.x - lastTranslation.x), dy = Double(translation.y - lastTranslation.y)
            lastTranslation = translation
            let velocity = pan.velocity(in: view)
            thumbMoved(dx: dx, dy: dy, velocity: Double((velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()))
        case .ended, .cancelled, .failed:
            // A flick up or down on a list glides it on.
            let velocity = pan.velocity(in: view)
            if pan.state == .ended, rail != nil, abs(velocity.y) >= abs(velocity.x) * CGFloat(FluxPointerRail.dominance) {
                let flick = settings.motion.move(from: .zero, dx: 0, dy: Double(velocity.y), velocity: Double(abs(velocity.y)))
                startGlide(Double(flick.y))
            }
            // A page that has just scrolled looks under the pointer itself.
            if settle == nil, glide == nil { hover(force: true) }
            show()
        default:
            break
        }
    }

    /// The thumb moved by `dx`, `dy`, at `velocity`.
    private func thumbMoved(dx: Double, dy: Double, velocity: Double) {
        let wanted = settings.motion.move(from: position, dx: dx, dy: dy, velocity: velocity)
        if rail != nil, ride(dx: Double(wanted.x - position.x), dy: Double(wanted.y - position.y)) {
            show()
            return
        }
        // Over a list, the pointer becomes the scroll pointer.
        if let found = FluxPointerTargets.shared.list(at: FluxPointerMotion.clamp(wanted, to: view.bounds), in: layer) {
            enterRail(found.token, list: found.list.frame, at: wanted)
            show()
            return
        }
        let pushed = push(to: wanted)
        move(to: pushed.point, animated: false)
        if pushed.scrolled { pageMoved() } else if settle == nil { hover() }
        show()
    }

    // MARK: The scroll pointer

    /// The pointer comes onto a list: it becomes the scroll pointer, in the
    /// middle band of the list, and the row under it takes the remote.
    private func enterRail(_ token: UUID, list: CGRect, at point: CGPoint) {
        stopGlide()
        rail = token
        railMotion = FluxPointerRail()
        restyle()
        let band = FluxPointerRail.band(list)
        move(to: CGPoint(x: min(list.maxX, max(list.minX, point.x)), y: min(band.maxY, max(band.minY, point.y))), animated: true)
        hover(force: true)
        #if FLUX_CATALOG_UI_TESTING
        report()
        #endif
    }

    /// The pointer leaves the list: a pointer again.
    private func leaveRail() {
        stopGlide()
        guard rail != nil else { return }
        rail = nil
        railMotion = FluxPointerRail()
        restyle()
        #if FLUX_CATALOG_UI_TESTING
        report()
        #endif
    }

    /// The thumb over the list the pointer rides: up and down scroll the
    /// list under the pointer, across moves along the row, and a pull past
    /// a side takes the pointer out. False once the list no longer shows.
    private func ride(dx: Double, dy: Double) -> Bool {
        guard let token = rail, let list = FluxPointerTargets.shared.list(token), let scroll = list.scroll else {
            leaveRail()
            return false
        }
        stopGlide()
        let way = FluxPointerRail.split(dx: dx, dy: dy)
        let scrolled = scrollRail(scroll, by: way.along)
        let step = railMotion.move(from: position, dx: way.across, dy: scrolled.rest, scrolled: scrolled.moved != 0,
                                   list: list.frame)
        if step.leaves {
            leaveRail()
            move(to: step.point, animated: true)
            // Out onto another list, it rides that one.
            if let next = FluxPointerTargets.shared.list(at: position, in: layer) {
                enterRail(next.token, list: next.list.frame, at: position)
            } else {
                hover(force: true)
            }
            return true
        }
        move(to: step.point, animated: false)
        if scrolled.moved != 0 { pageMoved() } else if settle == nil { hover() }
        return true
    }

    /// Scrolls `scroll` by `way`, down when positive, as far as it goes.
    /// What is left of the way counts only once the list had ended already:
    /// a flick that reaches the end of the list stops there.
    private func scrollRail(_ scroll: UIScrollView, by way: Double) -> (moved: Double, rest: Double) {
        guard way != 0, way.isFinite else { return (0, 0) }
        let inset = scroll.adjustedContentInset
        let offset = Double(scroll.contentOffset.y)
        let top = -Double(inset.top)
        let bottom = max(top, Double(scroll.contentSize.height + inset.bottom - scroll.bounds.height))
        let room = way > 0 ? bottom - offset : offset - top
        guard room > 0.5 else { return (0, way) }
        let moved = way > 0 ? min(way, room) : -min(-way, room)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: CGFloat(offset + moved)), animated: false)
        return (moved, 0)
    }

    /// On the list the pointer rides, the control under it, or the nearest
    /// that the list shows whole: a row cut by the top or the bottom of the
    /// list is not the one the scroll pointer stands for.
    private func railTarget() -> FluxPointerTargets.Target? {
        guard let token = rail, let list = FluxPointerTargets.shared.list(token) else { return nil }
        let whole = FluxPointerTargets.shared.targets(in: layer).filter { target in
            list.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY))
                && target.full.width - target.frame.width <= 4 && target.full.height - target.frame.height <= 4
        }
        return FluxPointerTarget.pick(position, frames: whole.map(\.frame), tolerance: 60).map { whole[$0] }
    }

    /// What the pointer stands for: on a list, its row; elsewhere, the
    /// control under it.
    private func pointedTarget() -> FluxPointerTargets.Target? {
        railTarget() ?? FluxPointerTargets.shared.target(at: position, tolerance: 14, in: layer)
    }

    // A flick up or down glides the list on, slower and slower, as a list of
    // the system does; the thumb that touches the surface again stops it.
    private var glide: CADisplayLink?
    private var glideSpeed = 0.0
    private var glideClock: CFTimeInterval = 0

    private func startGlide(_ speed: Double) {
        stopGlide()
        guard rail != nil, speed.isFinite, abs(speed) > 500 else { return }
        glideSpeed = speed
        glideClock = CACurrentMediaTime()
        let proxy = FluxDisplayLinkProxy()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(FluxDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        glide = link
    }

    private func stopGlide() {
        glide?.invalidate()
        glide = nil
        glideSpeed = 0
    }

    fileprivate func glided() {
        guard let token = rail, let list = FluxPointerTargets.shared.list(token), let scroll = list.scroll else {
            stopGlide()
            return
        }
        let now = CACurrentMediaTime()
        let elapsed = min(0.05, max(0, now - glideClock))
        glideClock = now
        let scrolled = scrollRail(scroll, by: glideSpeed * elapsed)
        glideSpeed *= pow(0.995, elapsed * 1000)
        if scrolled.moved != 0 { pageMoved() }
        if abs(glideSpeed) < 60 || scrolled.moved == 0 { stopGlide() }
        show()
    }

    /// The thumb takes the pointer to `wanted`: against the edge of a page
    /// that goes on beyond it, the page scrolls by the rest of the way.
    private func push(to wanted: CGPoint) -> (point: CGPoint, scrolled: Bool) {
        let margin = CGFloat(FluxPointerScroll.margin)
        guard let page = FluxPointerTargets.shared.page(at: position, in: layer), let scroll = page.scroll,
              wanted.y > page.frame.maxY - margin || wanted.y < page.frame.minY + margin else { return (wanted, false) }
        let inset = scroll.adjustedContentInset
        let offset = scroll.contentOffset.y
        let above = Double(offset + inset.top)
        let below = Double(scroll.contentSize.height + inset.bottom - scroll.bounds.height - offset)
        let push = FluxPointerScroll.push(from: position, to: wanted, page: page.frame, above: max(0, above), below: max(0, below))
        guard push.scroll != 0 else { return (push.point, false) }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset + CGFloat(push.scroll)), animated: false)
        return (push.point, true)
    }

    /// The page moved under the pointer: what it rested on went with it,
    /// and a click waits until the pointer has looked again, once the page
    /// has drawn itself where it now stands.
    private func pageMoved() {
        overNothing = true
        asking = nil
        updateIdleClick()
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self else { return }
            self.settle = nil
            if self.pointerActive { self.hover(force: true) }
        }
    }

    @objc private func held(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began else { return }
        // Held, the key changes the mode only: its press is dropped. The
        // settings follow, and the pointer says the new mode (`announce`).
        FluxPointerState.shared.playPauseWasHeld()
        UserDefaults.standard.set(settings.mode.other.rawValue, forKey: FluxRemoteMode.storageKey)
    }

    @objc private func playPauseWatched(_ watch: UILongPressGestureRecognizer) {
        switch watch.state {
        case .began: FluxPointerState.shared.playPauseWentDown()
        case .ended, .cancelled, .failed: FluxPointerState.shared.playPauseWentUp()
        default: break
        }
    }

    @objc private func idleClicked(_ click: UILongPressGestureRecognizer) {
        // Held back: the pointer rests on nothing, or on a list that glides.
        if click.state == .began { stopGlide() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// The thumb touches the surface: a list that glides stops under it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pan { stopGlide() }
        return true
    }

    // MARK: Drawing

    private func move(to point: CGPoint, animated: Bool) {
        position = FluxPointerMotion.clamp(point, to: view.bounds)
        if animated, cursor.alpha > 0, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.cursor.place(at: self.position)
            }
        } else {
            cursor.place(at: position)
        }
    }

    private func show() {
        guard pointerActive else { return }
        if cursor.alpha < 1 {
            UIView.animate(withDuration: 0.15) { self.cursor.alpha = 1 }
        }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    private func hide(animated: Bool) {
        hideTask?.cancel()
        hideTask = nil
        guard cursor.alpha > 0 else { return }
        if animated { UIView.animate(withDuration: 0.3) { self.cursor.alpha = 0 } } else { cursor.alpha = 0 }
    }

    #if FLUX_CATALOG_UI_TESTING
    /// A bench has no thumb: it moves the pointer itself, to a point of the
    /// screen, as a thumb would, and the pointer hands the focus there.
    func benchMove(to point: CGPoint) {
        guard pointerActive else { return }
        move(to: point, animated: false)
        show()
        hover(force: true)
    }

    /// The thumb moves the pointer down a little, as far as the bottom of
    /// the page and then the page itself, unless the control `name` shows
    /// whole in the page: whether it does.
    func benchPush(toward name: String, down: Bool) -> Bool {
        guard pointerActive else { return false }
        let targets = FluxPointerTargets.shared
        guard let page = targets.page(at: position, in: layer) ?? targets.pages(in: layer).first else { return false }
        let margin = CGFloat(FluxPointerScroll.margin)
        if let target = benchTarget(name),
           down ? target.frame.maxY < page.frame.maxY - margin : target.frame.minY > page.frame.minY + margin { return true }
        if !page.frame.contains(position) {
            move(to: CGPoint(x: page.frame.midX, y: down ? page.frame.maxY - 60 : page.frame.minY + 60), animated: false)
        }
        thumbMoved(dx: 0, dy: down ? 30 : -30, velocity: 0)
        return false
    }

    private let probe = UIView()

    /// What holds the remote, as the pointer sees it: the place its screen
    /// selected, or the control of its screens that has the focus.
    func benchHeldID() -> String? {
        let list = FluxPointerTargets.shared.targets(in: layer)
        if let selected = list.first(where: { $0.holds?() == true }) { return selected.id }
        guard let item = UIFocusSystem.focusSystem(for: view)?.focusedItem, let frame = frame(of: item) else { return nil }
        return list.filter { $0.holds == nil && FluxPointerTarget.same(frame, $0.frame) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id
    }

    /// The control `name` of these screens, on screen: a name that ends
    /// with `*` stands for the first one, as it is read, whose name begins so.
    func benchTarget(_ name: String) -> FluxPointerTargets.Target? {
        FluxPointerTargets.shared.targets(in: layer)
            .filter { Self.benchMatches($0.id, name) && view.bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .min { abs($0.frame.minY - $1.frame.minY) > 2 ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX }
    }

    static func benchMatches(_ id: String, _ name: String) -> Bool {
        name.hasSuffix("*") ? id.hasPrefix(String(name.dropLast())) : id == name
    }

    /// What the search of the controls sees, for a sweep that crosses none.
    private func diagnosis() -> String {
        func name(_ value: Any?) -> String {
            guard let value else { return "nil" }
            // A generic SwiftUI type names its parameters, commas included.
            let full = String(describing: type(of: value))
            return String(full.prefix { $0 != "<" && $0 != "," })
        }
        let root = screens.view.focusItemContainer
        let top = root.map { $0.focusItems(in: view.convert(view.bounds, to: $0.coordinateSpace)).count } ?? -1
        let all = controls(near: CGPoint(x: view.bounds.midX, y: view.bounds.midY), radius: 4000).count
        let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem
        var chain: [String] = []
        var environment: (any UIFocusEnvironment)? = focused
        while let current = environment, chain.count < 10 {
            chain.append(name(current) + (current.focusItemContainer == nil ? "" : "+"))
            environment = current.parentFocusEnvironment
        }
        let mine = FluxPointerTargets.shared.targets(in: layer).count
        return "diag:targets=\(mine)/\(FluxPointerTargets.shared.count);root=\(name(root));top=\(top);all=\(all);focused=\(name(focused));env=\(chain.joined(separator: ">"))"
    }

    /// The mode and what covers the screens, as the pointer on top says;
    /// then what a sweep crossed.
    fileprivate func report() {
        let shared = FluxPointerState.shared
        let top = shared.controller ?? self
        let state = top.settings.mode == .classic ? "classic"
            : shared.suspended ? "suspended" : top.pointerActive ? "active" : "covered"
        probe.accessibilityValue = "\(state) toasts:\(shared.toasts)" + (top.rail == nil ? "" : " rail")
            + (shared.trace.isEmpty ? "" : " trace:" + shared.trace.joined(separator: ","))
    }

    /// The thumb moves by `dx`, `dy`, slowly, as a bench moves it.
    func benchThumb(dx: Double, dy: Double) {
        guard pointerActive else { return }
        thumbMoved(dx: dx, dy: dy, velocity: 0)
    }

    /// "pointer-list": the pointer comes onto the list of the channels and
    /// becomes the scroll pointer; the thumb down scrolls the list under it,
    /// which keeps its height, and the channel under it takes the remote; a
    /// pull to the left takes it out of the list.
    private func sweepList(patience: Double) async {
        func rest(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * patience * 1_000_000_000)) }
        let shared = FluxPointerState.shared
        let targets = FluxPointerTargets.shared
        func channel() -> FluxPointerTargets.Target? {
            targets.targets(in: layer).filter { $0.id.hasPrefix("fixture-live-") && targets.list(at: CGPoint(x: $0.frame.midX, y: $0.frame.midY), in: layer) != nil }
                .min { $0.frame.minY < $1.frame.minY }
        }
        var first: FluxPointerTargets.Target?
        for _ in 0..<Int(60 * patience) {
            first = channel()
            if first != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let first, let list = targets.list(at: CGPoint(x: first.frame.midX, y: first.frame.midY), in: layer) else {
            shared.trace.append("miss:list")
            shared.trace.append(diagnosis())
            shared.report()
            return
        }
        // Over the list, the thumb makes the pointer its scroll pointer.
        benchMove(to: CGPoint(x: list.list.frame.midX, y: list.list.frame.midY))
        await rest(0.3)
        benchThumb(dx: 2, dy: 0)
        shared.trace.append(rail == list.token ? "rail" : rail == nil ? "free" : "other")
        await rest(0.6)
        let height = position.y
        let before = shared.benchFocus ?? benchHeldID() ?? "none"
        let offset = list.list.scroll?.contentOffset.y ?? 0
        shared.trace.append("on=" + before)
        // Down the list: the list scrolls, the pointer stays at its height.
        for _ in 0..<24 { benchThumb(dx: 0, dy: 30); await rest(0.04) }
        await rest(0.8)
        let after = shared.benchFocus ?? benchHeldID() ?? "none"
        let scrolled = (list.list.scroll?.contentOffset.y ?? 0) - offset
        shared.trace.append(abs(position.y - height) < 1 ? "kept" : "moved:\(Int(position.y - height))")
        shared.trace.append(scrolled > 100 ? "scrolled" : "still:\(Int(scrolled))")
        shared.trace.append("now=" + after)
        // Across and on, past the left side: out of the list.
        for _ in 0..<16 where rail == list.token { benchThumb(dx: -60, dy: 0); await rest(0.05) }
        shared.trace.append(rail == list.token ? "stuck" : "out")
        await rest(0.4)
        // Back onto the list, for the click of the flow on the channel there.
        for _ in 0..<30 where rail != list.token { benchThumb(dx: 30, dy: 0); await rest(0.05) }
        await rest(0.8)
        shared.trace.append("end=" + (shared.benchFocus ?? benchHeldID() ?? "none"))
        shared.report()
    }

    /// A step of a sweep: the pointer rests on each control of `via`, then
    /// on `rests`, where it stays for the click of the flow. A step waits
    /// for its first control to show: the click of the step before opens it.
    private struct SweepStep {
        let via: [String]
        let rests: String
        /// What the flow does first, as a click where the step before
        /// rested: the step waits for it.
        var after: (() -> Bool)? = nil
    }

    /// What the pointer crosses, screen by screen, with FLUX_UI_POINTER=1.
    private static func steps(for scenario: String) -> [SweepStep] {
        switch scenario {
        // The fiche of a film, then the panel of its lists, which the click
        // on « favorite » opens.
        case "movie":
            return [SweepStep(via: ["play"], rests: "favorite"),
                    SweepStep(via: ["create"], rests: "list-0")]
        // Graphismes: a preset; a switch below the bottom of the page, which
        // the pointer pushes; the column, which shows Interface; the key of
        // the studio there, then in the studio a screen and a theme.
        case "settings-graphics":
            // A theme other than the one kept, so that the click changes it.
            let theme = FluxDockTheme.Family.allCases.flatMap(\.themes).first { $0 != FluxDockTheme.defaultValue } ?? .defaultValue
            return [SweepStep(via: ["preset-*", below + "toggle-*", "settings-page-appearance"], rests: "studio-dock"),
                    SweepStep(via: ["studio-scope-live"], rests: "studio-theme-" + theme.rawValue)]
        // Sources, without the dock: Home and Back at the top of the
        // column, which the pointer could not reach up to the 0.9.12 ("mode
        // pointeur impossible de cliquer sur precedent ou home", David,
        // 28/11). The click on Back leads to the home screen, whose bar
        // opens the settings again, where the click on Home leads home.
        case "settings":
            return [SweepStep(via: [DeskZone.homeID], rests: DeskZone.backID),
                    SweepStep(via: [], rests: FluxDockItem.settings.focusID),
                    SweepStep(via: [], rests: DeskZone.homeID)]
        // The settings over the picture: a row of the column, then the key
        // that closes them, at its top.
        case "player-settings":
            return [SweepStep(via: ["settings-page-network"], rests: DeskColumnHeader.closeID)]
        // The languages over the picture: an audio, then a subtitle.
        case "player-tracks":
            return [SweepStep(via: ["track-audio-a2"], rests: "track-sub-s1")]
        // The settings over the picture: the column shows Réseau, then
        // Vidéo again, and a switch of that page.
        case "player-flow":
            return [SweepStep(via: ["settings-page-network", "settings-page-video"],
                              rests: below + "toggle-Reprendre automatiquement films et épisodes")]
        // A message over the catalogue: its OK, then a channel under it,
        // which the pointer must not reach, and its OK again.
        case "player-deep":
            return [SweepStep(via: ["desk-notice-ok", "fixture-live-58"], rests: "desk-notice-ok")]
        // Télécommande: « Souris », then « Halo », below the bottom of the
        // page, which the flow chooses; then « Classique », at its top,
        // which the mouse could not choose in 0.9.8.
        case "settings-remote":
            let halo = { UserDefaults.standard.string(forKey: FluxPointerShape.storageKey) == FluxPointerShape.halo.rawValue }
            return [SweepStep(via: ["remote-mode-pointer"], rests: below + "pointer-shape-halo"),
                    SweepStep(via: [], rests: above + "remote-mode-classic", after: halo)]
        default:
            return []
        }
    }

    /// The sweep of a bench, on the pointer on top as it goes: a panel that
    /// covers the screen brings its own.
    static func sweep(_ scenario: String) async {
        // A hosted machine answers several times more slowly; the flows say
        // how much (FLUX_UI_PATIENCE), and each rest of the pointer is as
        // much longer.
        let patience = min(10, max(1, Double(ProcessInfo.processInfo.environment["FLUX_UI_PATIENCE"] ?? "") ?? 1))
        func rest(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * patience * 1_000_000_000)) }
        await rest(4)
        let shared = FluxPointerState.shared
        guard scenario != "pointer" else {
            await shared.controller?.sweepLive(patience: patience)
            return
        }
        guard scenario != "pointer-list" else {
            await shared.controller?.sweepList(patience: patience)
            return
        }
        for (number, step) in steps(for: scenario).enumerated() {
            if let after = step.after {
                let clock = ProcessInfo.processInfo
                let end = clock.systemUptime + 60 * patience
                while !after(), clock.systemUptime < end { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            for (index, name) in step.via.enumerated() {
                // The first control of a step shows once the flow has
                // clicked, or opened what holds it.
                let held = await Self.reach(name, patience: patience, waiting: index == 0 ? 60 : 6)
                shared.trace.append(held ?? "miss:" + name)
                shared.report()
            }
            let held = await Self.reach(step.rests, patience: patience, waiting: step.via.isEmpty ? 60 : 6)
            shared.trace.append((number == 0 ? "end" : "end\(number + 1)") + "=" + (held ?? "miss:" + step.rests))
            shared.report()
        }
    }

    /// Rests on the control `name`. Named `below:` + name, it lies below
    /// the bottom of its page: the pointer pushes the page down to it first;
    /// named `above:` + name, above its top, and the pointer pushes it up.
    private static func reach(_ name: String, patience: Double, waiting seconds: Double) async -> String? {
        for (mark, down) in [(below, true), (above, false)] where name.hasPrefix(mark) {
            let control = String(name.dropFirst(mark.count))
            await push(toward: control, down: down, patience: patience)
            return await rest(on: control, patience: patience, waiting: seconds)
        }
        return await rest(on: name, patience: patience, waiting: seconds)
    }

    /// A step of a sweep toward a control below the bottom of its page, or
    /// above its top.
    private static let below = "below:"
    private static let above = "above:"

    /// The pointer pushes the page until the control `name` shows.
    private static func push(toward name: String, down: Bool, patience: Double) async {
        let clock = ProcessInfo.processInfo
        let end = clock.systemUptime + 8 * patience
        while clock.systemUptime < end {
            if let top = FluxPointerState.shared.controller, top.benchPush(toward: name, down: down) { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Moves the pointer onto the control `name` of the pointer on top, once
    /// it shows, and waits for it to hold the remote: what holds it then.
    private static func rest(on name: String, patience: Double, waiting seconds: Double) async -> String? {
        let clock = ProcessInfo.processInfo
        let shown = clock.systemUptime + seconds * patience
        var found: (controller: FluxPointerController, target: FluxPointerTargets.Target)?
        while found == nil, clock.systemUptime < shown {
            if let top = FluxPointerState.shared.controller, top.pointerActive, let target = top.benchTarget(name) {
                found = (top, target)
            } else {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard let controller = found?.controller, let target = found?.target else { return nil }
        // What has just opened settles first.
        try? await Task.sleep(nanoseconds: UInt64(0.4 * patience * 1_000_000_000))
        let frame = controller.benchTarget(name)?.frame ?? target.frame
        controller.benchMove(to: CGPoint(x: frame.midX, y: frame.midY))
        let held = clock.systemUptime + 3 * patience
        while clock.systemUptime < held, !(controller.benchHeldID().map { benchMatches($0, name) } ?? false) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? await Task.sleep(nanoseconds: UInt64(0.3 * patience * 1_000_000_000))
        return controller.benchHeldID()
    }

    /// "pointer": the pointer crosses the content, then the bar, as a thumb
    /// would; each control it rests on must take the focus. It ends on the
    /// first title it crossed, for the click of the flow.
    private func sweepLive(patience: Double) async {
        func rest(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * patience * 1_000_000_000)) }
        let shared = FluxPointerState.shared
        let bounds = view.bounds
        let rows = [bounds.height * 0.42, bounds.height * 0.55, bounds.maxY - 150, bounds.maxY - 125, bounds.maxY - 100]
        var title: CGPoint?
        // What held the remote at launch is no control crossed: only what
        // changes from now on counts.
        var last = shared.benchFocus
        for y in rows {
            for step in 0...10 {
                let point = CGPoint(x: bounds.width * (0.2 + 0.06 * CGFloat(step)), y: y)
                benchMove(to: point)
                await rest(0.3)
                guard let id = shared.benchFocus, id != last else { continue }
                last = id
                shared.trace.append(id)
                if title == nil, id.hasPrefix("fixture-") { title = point }
            }
        }
        if !shared.trace.contains(where: { $0.hasPrefix("fixture-") }) { shared.trace.append(diagnosis()) }
        shared.trace.append("hover=asked:\(shared.asked)")
        if let title {
            benchMove(to: title)
            // Back over the title, until the focus has followed.
            for _ in 0..<Int(30 * patience) where !(shared.benchFocus ?? "").hasPrefix("fixture-") {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await rest(0.3)
        }
        shared.trace.append("end=" + (shared.benchFocus ?? "none"))
        shared.report()
    }
    #endif
}

/// Says at once when an arrow goes down and when it rises. A long press,
/// even of no duration, begins on the next turn of the run loop: the focus
/// engine has by then refused to move for the arrow (bench of the 0.9.5,
/// where the arrows of a flow moved nothing in the mode « Souris »). The
/// press goes on to the screens: this only watches it.
private final class FluxArrowWatch: UIGestureRecognizer {
    var changed: (_ down: Bool) -> Void = { _ in }
    private var down = false

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        down = true
        changed(true)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        rise()
        state = .failed
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        rise()
        state = .failed
    }

    override func reset() {
        super.reset()
        rise()
    }

    private func rise() {
        guard down else { return }
        down = false
        changed(false)
    }
}

/// Ticks of the screen for a list that glides, without the display link
/// holding the pointer.
private final class FluxDisplayLinkProxy: NSObject {
    weak var owner: FluxPointerController?
    @MainActor @objc func tick(_ link: CADisplayLink) { owner?.glided() }
}

/// The pointer itself, as its settings draw it, that never takes a touch.
/// Every shape has its path for its shadow, and the hand its shadow drawn
/// in its picture: Core Animation never looks for the outline of a shadow
/// while the pointer moves.
private final class FluxPointerCursor: UIView {
    private let haloLayer = CAShapeLayer()
    private let bodyLayer = CAShapeLayer()
    private let marksLayer = CAShapeLayer()
    private let pictureLayer = CALayer()
    private var drawn: String?
    /// The point that points, in the pointer's own points.
    private var hotspot = CGPoint(x: 2, y: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "flux-pointer"
        for shape in [haloLayer, bodyLayer, marksLayer] {
            shape.fillRule = .evenOdd
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        layer.addSublayer(pictureLayer)
        pictureLayer.contentsGravity = .resize
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        style(shape: .arrow, color: .white, height: 44, riding: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// On a screen at last, the pointer is drawn again at the scale of the screen.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { style(shape: chosen.shape, color: chosen.color, height: chosen.height, riding: chosen.riding) }
    }

    private var chosen = (shape: FluxPointerShape.arrow, color: FluxPointerColor.white, height: CGFloat(44), riding: false)

    func style(shape: FluxPointerShape, color: FluxPointerColor, height: CGFloat, riding: Bool) {
        chosen = (shape, color, height, riding)
        let key = "\(shape.rawValue)-\(color.rawValue)-\(height)-\(riding)-\(traitCollection.displayScale)"
        guard key != drawn else { return }
        drawn = key
        let art = FluxPointerArt(shape: shape, height: height, riding: riding)
        let fill = UIColor(pointer: color)
        let edge = UIColor(pointerEdge: color)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(origin: .zero, size: art.size)
        for sublayer in [haloLayer, bodyLayer, marksLayer, pictureLayer] as [CALayer] { sublayer.frame = bounds }
        haloLayer.path = art.halo
        haloLayer.fillColor = fill.withAlphaComponent(0.26).cgColor
        haloLayer.shadowPath = art.halo
        haloLayer.shadowColor = fill.cgColor
        haloLayer.shadowOpacity = art.halo == nil ? 0 : 0.9
        haloLayer.shadowRadius = height * 0.18
        haloLayer.shadowOffset = .zero
        bodyLayer.path = art.body
        bodyLayer.fillColor = fill.withAlphaComponent(art.bodyAlpha).cgColor
        bodyLayer.strokeColor = edge.cgColor
        bodyLayer.lineWidth = art.edge
        marksLayer.path = art.marks
        marksLayer.fillColor = edge.cgColor
        let scale = max(1, traitCollection.displayScale)
        if let symbol = art.symbol, let picture = Self.picture(of: symbol, fill: fill, edge: edge, size: art.size, scale: scale) {
            pictureLayer.contents = picture.image
            hotspot = picture.tip
            layer.shadowPath = nil
            layer.shadowOpacity = 0
        } else {
            pictureLayer.contents = nil
            hotspot = art.hotspot
            layer.shadowPath = art.body
            layer.shadowOpacity = 0.45
        }
        CATransaction.commit()
    }

    /// The point that points, on `point`.
    func place(at point: CGPoint) {
        center = CGPoint(x: point.x - hotspot.x + bounds.width / 2, y: point.y - hotspot.y + bounds.height / 2)
    }

    /// The hand, drawn once with its edge and its shadow, and the tip of
    /// its finger, found in the drawing: of its opaque points, the one
    /// furthest up and left.
    private static func picture(of symbol: String, fill: UIColor, edge: UIColor, size: CGSize,
                                scale: CGFloat) -> (image: CGImage, tip: CGPoint)? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let glyph = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size.height * 0.7)),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // UIKit draws from the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let margin = FluxPointerArt.pictureMargin
        let fit = min((size.width - 2 * margin) / glyph.size.width, (size.height - 2 * margin) / glyph.size.height)
        let rect = CGRect(x: margin, y: margin, width: glyph.size.width * fit, height: glyph.size.height * fit)
        let line = max(1.5, size.height / 26)
        // The shadow goes down on the screen: up in the space of the bitmap.
        context.setShadow(offset: CGSize(width: 0, height: -3 * scale), blur: 6 * scale,
                          color: UIColor.black.withAlphaComponent(0.45).cgColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let outline = glyph.withTintColor(edge, renderingMode: .alwaysOriginal)
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 4) {
            outline.draw(in: rect.offsetBy(dx: line * CGFloat(cos(angle)), dy: line * CGFloat(sin(angle))))
        }
        glyph.withTintColor(fill, renderingMode: .alwaysOriginal).draw(in: rect)
        context.endTransparencyLayer()
        guard let image = context.makeImage(), let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var tip: (sum: Int, x: Int, y: Int)?
        for y in 0..<height {
            if let tip, y > tip.sum { break }
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 170 {
                if tip == nil || x + y < tip!.sum { tip = (x + y, x, y) }
                break
            }
        }
        guard let tip else { return nil }
        return (image, CGPoint(x: CGFloat(tip.x) / scale, y: CGFloat(tip.y) / scale))
    }
}

extension UIColor {
    /// The colour of the pointer.
    convenience init(pointer color: FluxPointerColor) {
        let rgb = color.components
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// The edge that sets the pointer off the picture.
    convenience init(pointerEdge color: FluxPointerColor) {
        self.init(white: color.isDark ? 1 : 0, alpha: color.isDark ? 0.9 : 0.85)
    }
}

/// What the pointer draws at a height, in its own points: its shape, what is
/// drawn over it in the colour of its edge, a light around it, and the point
/// that points. The settings draw the same (`FluxPointerGlyph`).
struct FluxPointerArt {
    /// Around the picture of the hand, for its edge and its shadow.
    static let pictureMargin: CGFloat = 9

    var size: CGSize
    var hotspot: CGPoint
    var body: CGPath
    var bodyAlpha: CGFloat = 1
    var edge: CGFloat
    var marks: CGPath?
    var halo: CGPath?
    /// A symbol drawn instead of a shape.
    var symbol: String?

    init(shape: FluxPointerShape, height: CGFloat, riding: Bool) {
        let h = max(12, height)
        edge = max(1.5, h / 22)
        if riding {
            // The scroll pointer: an upright capsule, its chevrons up and down.
            let w = (h * 0.6).rounded(), t = (h * 1.12).rounded()
            size = CGSize(width: w, height: t)
            hotspot = CGPoint(x: w / 2, y: t / 2)
            let capsule = CGRect(x: edge, y: edge, width: w - 2 * edge, height: t - 2 * edge)
            body = CGPath(roundedRect: capsule, cornerWidth: capsule.width / 2, cornerHeight: capsule.width / 2, transform: nil)
            let marks = CGMutablePath()
            let mid = w / 2, wide = w * 0.44, tall = w * 0.24
            marks.addLines(between: [CGPoint(x: mid, y: t * 0.15), CGPoint(x: mid + wide / 2, y: t * 0.15 + tall),
                                     CGPoint(x: mid - wide / 2, y: t * 0.15 + tall)])
            marks.closeSubpath()
            marks.addLines(between: [CGPoint(x: mid, y: t * 0.85), CGPoint(x: mid - wide / 2, y: t * 0.85 - tall),
                                     CGPoint(x: mid + wide / 2, y: t * 0.85 - tall)])
            marks.closeSubpath()
            let dot = w * 0.17
            marks.addEllipse(in: CGRect(x: mid - dot / 2, y: t / 2 - dot / 2, width: dot, height: dot))
            self.marks = marks
            return
        }
        switch shape {
        case .arrow:
            size = CGSize(width: (h * 0.66).rounded(.up), height: h)
            hotspot = CGPoint(x: 2, y: 2)
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: 2, y: 2), CGPoint(x: 2, y: h * 0.80), CGPoint(x: h * 0.22, y: h * 0.62),
                                    CGPoint(x: h * 0.35, y: h * 0.94), CGPoint(x: h * 0.47, y: h * 0.89),
                                    CGPoint(x: h * 0.34, y: h * 0.58), CGPoint(x: h * 0.60, y: h * 0.58)])
            path.closeSubpath()
            body = path
        case .hand:
            let m = Self.pictureMargin
            size = CGSize(width: (h * 0.84 + 2 * m).rounded(.up), height: (h + 2 * m).rounded(.up))
            // Drawn, the tip of the finger is found in the picture; this is
            // where it stands near enough, for the settings.
            hotspot = CGPoint(x: m + h * 0.1, y: m + h * 0.04)
            body = CGMutablePath()
            symbol = "hand.point.up.left.fill"
        case .dot:
            let d = (h * 0.6).rounded()
            size = CGSize(width: d, height: d)
            hotspot = CGPoint(x: d / 2, y: d / 2)
            edge = max(1.5, d / 14)
            body = CGPath(ellipseIn: CGRect(x: edge, y: edge, width: d - 2 * edge, height: d - 2 * edge), transform: nil)
            bodyAlpha = 0.82
        case .ring:
            let d = (h * 0.72).rounded()
            size = CGSize(width: d, height: d)
            hotspot = CGPoint(x: d / 2, y: d / 2)
            let outer = d / 2 - edge, inner = outer * 0.58
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: d / 2 - outer, y: d / 2 - outer, width: 2 * outer, height: 2 * outer))
            path.addEllipse(in: CGRect(x: d / 2 - inner, y: d / 2 - inner, width: 2 * inner, height: 2 * inner))
            body = path
        case .crosshair:
            let d = (h * 0.84).rounded()
            size = CGSize(width: d, height: d)
            hotspot = CGPoint(x: d / 2, y: d / 2)
            let c = d / 2, outer = d / 2 - edge, ring = max(3, h * 0.075), tick = max(3, h * 0.075)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: c - outer, y: c - outer, width: 2 * outer, height: 2 * outer))
            let inner = outer - ring
            path.addEllipse(in: CGRect(x: c - inner, y: c - inner, width: 2 * inner, height: 2 * inner))
            // Four ticks inside the ring, toward the middle, which they leave free.
            let near = outer * 0.3, far = inner - 1.5
            path.addRect(CGRect(x: c - tick / 2, y: c - far, width: tick, height: far - near))
            path.addRect(CGRect(x: c - tick / 2, y: c + near, width: tick, height: far - near))
            path.addRect(CGRect(x: c - far, y: c - tick / 2, width: far - near, height: tick))
            path.addRect(CGRect(x: c + near, y: c - tick / 2, width: far - near, height: tick))
            let dot = max(3, h * 0.08)
            path.addEllipse(in: CGRect(x: c - dot / 2, y: c - dot / 2, width: dot, height: dot))
            body = path
        case .halo:
            let d = (h * 0.95).rounded()
            size = CGSize(width: d, height: d)
            hotspot = CGPoint(x: d / 2, y: d / 2)
            let core = max(8, d * 0.24)
            body = CGPath(ellipseIn: CGRect(x: d / 2 - core / 2, y: d / 2 - core / 2, width: core, height: core), transform: nil)
            halo = CGPath(ellipseIn: CGRect(x: d * 0.1, y: d * 0.1, width: d * 0.8, height: d * 0.8), transform: nil)
        }
    }
}

/// The pointer as the settings show it, drawn as the remote will draw it.
struct FluxPointerGlyph: View {
    let shape: FluxPointerShape
    let color: FluxPointerColor
    let height: CGFloat
    var riding = false

    var body: some View {
        let art = FluxPointerArt(shape: shape, height: height, riding: riding)
        let fill = Color(uiColor: UIColor(pointer: color))
        let edge = Color(uiColor: UIColor(pointerEdge: color))
        ZStack(alignment: .topLeading) {
            if let halo = art.halo {
                Path(halo).fill(fill.opacity(0.26)).shadow(color: fill.opacity(0.9), radius: height * 0.18)
            }
            if let symbol = art.symbol {
                let m = FluxPointerArt.pictureMargin
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(fill)
                    .shadow(color: edge, radius: 0.8)
                    .shadow(color: edge, radius: 0.8)
                    .padding(m)
            } else {
                Path(art.body).fill(fill.opacity(art.bodyAlpha), style: FillStyle(eoFill: true))
                Path(art.body).stroke(edge, style: StrokeStyle(lineWidth: art.edge, lineJoin: .round))
            }
            if let marks = art.marks {
                Path(marks).fill(edge, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: art.size.width, height: art.size.height)
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

/// A word at the top of the screen when the mode changes.
private final class FluxPointerToast: UIVisualEffectView {
    private let icon = UIImageView()
    private let title = UILabel()
    private let hint = UILabel()
    private var dismiss: Task<Void, Never>?

    init() {
        super.init(effect: UIBlurEffect(style: .dark))
        isUserInteractionEnabled = false
        alpha = 0
        clipsToBounds = true
        accessibilityIdentifier = "flux-pointer-mode"
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.textColor = .white
        hint.font = .systemFont(ofSize: 21, weight: .regular)
        hint.textColor = UIColor.white.withAlphaComponent(0.7)
        let words = UIStackView(arrangedSubviews: [title, hint])
        words.axis = .vertical
        words.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, words])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40), icon.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func place(in bounds: CGRect) {
        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + 70, width: size.width, height: size.height)
        layer.cornerRadius = size.height / 2
    }

    func show(_ text: String, symbol: String, hint: String) {
        title.text = text
        self.hint.text = hint
        icon.image = UIImage(systemName: symbol)
        accessibilityLabel = text
        if let bounds = superview?.bounds { place(in: bounds) }
        superview?.bringSubviewToFront(self)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        UIAccessibility.post(notification: .announcement, argument: text)
        dismiss?.cancel()
        dismiss = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self else { return }
            UIView.animate(withDuration: 0.35) { self.alpha = 0 }
        }
    }
}
#endif

#if !os(tvOS)
extension View {
    /// Only a television has a pointer that scrolls a list (`fluxPointerList`).
    func fluxPointerList() -> some View { self }
}
#endif
