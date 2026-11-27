import SwiftUI

#if os(tvOS)
import UIKit

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
        var frame: CGRect
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

    /// A page that the pointer scrolls by pushing its edges (`fluxPointerPage`).
    struct Page {
        /// What shows of it, on the screen.
        let frame: CGRect
        let layer: UUID
        /// The scroll view that SwiftUI draws it in.
        weak var scroll: UIScrollView?
    }

    private var pages: [UUID: Page] = [:]

    func setPage(_ token: UUID, _ page: Page) { pages[token] = page }
    func removePage(_ token: UUID) { pages[token] = nil }

    func pages(in layer: UUID) -> [Page] { pages.values.filter { $0.layer == layer && $0.scroll != nil } }

    /// The page of `layer` that shows at `point`, the innermost.
    func page(at point: CGPoint, in layer: UUID) -> Page? {
        pages(in: layer).filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
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
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { Self.shownFrame($0) } action: { frame in
                place.frame = frame
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
        FluxPointerTargets.shared.set(place.token, .init(id: id, frame: frame, layer: layer, focus: focus, holds: holds))
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
        modifier(FluxPointerPageModifier())
    }
}

private struct FluxPointerPageModifier: ViewModifier {
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
        FluxPointerTargets.shared.setPage(place.token, .init(frame: place.frame, layer: layer, scroll: scroll))
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
    var size = FluxPointerSize.defaultValue
    var shape = FluxPointerShape.defaultValue
}

/// The screens of a television, under the controller of the pointer.
struct FluxRemoteHost<Content: View>: View {
    @AppStorage(FluxRemoteMode.storageKey) private var mode = FluxRemoteMode.defaultValue.rawValue
    @AppStorage(FluxRemoteMode.toggleKey) private var toggles = FluxRemoteMode.toggleDefault
    @AppStorage(FluxPointerSpeed.storageKey) private var speed = FluxPointerSpeed.defaultValue.rawValue
    @AppStorage(FluxPointerSize.storageKey) private var size = FluxPointerSize.defaultValue.rawValue
    @AppStorage(FluxPointerShape.storageKey) private var shape = FluxPointerShape.defaultValue.rawValue
    @Environment(\.scenePhase) private var phase
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    private var settings: FluxPointerSettings {
        FluxPointerSettings(mode: FluxRemoteMode(rawValue: mode) ?? .defaultValue, toggles: toggles,
                            speed: FluxPointerSpeed(rawValue: speed) ?? .defaultValue,
                            size: FluxPointerSize(rawValue: size) ?? .defaultValue,
                            shape: FluxPointerShape(rawValue: shape) ?? .defaultValue)
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
    /// A press of the arrows still goes from one control to the next.
    private var arrowsUntil: TimeInterval = 0
    /// A control has been found under the pointer: the controls of the
    /// screens can be found. Until then a click is never held back.
    private var found = false
    private var overNothing = false
    /// A page the pointer pushed draws itself again before the pointer
    /// looks at what came under it.
    private var settle: Task<Void, Never>?

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
    private lazy var arrows: UILongPressGestureRecognizer = {
        let arrows = UILongPressGestureRecognizer(target: self, action: #selector(arrowPressed(_:)))
        arrows.allowedPressTypes = [UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow]
            .map { NSNumber(value: $0.rawValue) }
        arrows.allowedTouchTypes = []
        arrows.minimumPressDuration = 0
        arrows.cancelsTouchesInView = false
        arrows.delegate = self
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
        guard scenario == "pointer" || environment["FLUX_UI_POINTER"] == "1", !FluxPointerState.shared.swept else { return }
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
        cursor.style(shape: next.shape, height: Desk.tv(CGFloat(next.size.height)))
        guard applied else { applied = true; refresh(); return }
        if previous.mode != next.mode {
            if next.mode == .pointer { placeOnFocus() }
            refresh()
        } else if previous.toggles != next.toggles {
            refresh()
        }
    }

    /// The recognizers and the pointer follow the mode and what covers the
    /// screens.
    func refresh() {
        guard isViewLoaded else { return }
        let active = pointerActive
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
        return ProcessInfo.processInfo.systemUptime < arrowsUntil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard pointerActive, let next = context.nextFocusedItem else { return }
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
            if let target = FluxPointerTargets.shared.target(at: position, tolerance: 14, in: layer),
               target.holds == nil, FluxPointerTarget.same(frame, target.frame) {
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
        if let target = FluxPointerTargets.shared.target(at: position, tolerance: 14, in: layer) {
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
        guard pointerActive, let target = FluxPointerTargets.shared.target(at: position, tolerance: 14, in: layer) else { return }
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
        if let target = targets.target(at: position, tolerance: 14, in: layer), holds(target) {
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
    var movesSelection: Bool { !pointerActive || ProcessInfo.processInfo.systemUptime < arrowsUntil }

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
            show()
            fallthrough
        case .changed:
            let translation = pan.translation(in: view)
            let dx = Double(translation.x - lastTranslation.x), dy = Double(translation.y - lastTranslation.y)
            lastTranslation = translation
            let velocity = pan.velocity(in: view)
            thumbMoved(dx: dx, dy: dy, velocity: Double((velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()))
        case .ended, .cancelled, .failed:
            // A page that has just scrolled looks under the pointer itself.
            if settle == nil { hover(force: true) }
            show()
        default:
            break
        }
    }

    /// The thumb moved by `dx`, `dy`, at `velocity`.
    private func thumbMoved(dx: Double, dy: Double, velocity: Double) {
        let wanted = FluxPointerMotion(speed: settings.speed).move(from: position, dx: dx, dy: dy, velocity: velocity)
        let pushed = push(to: wanted)
        move(to: pushed.point, animated: false)
        if pushed.scrolled { pageMoved() } else if settle == nil { hover() }
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
        // Held, the key changes the mode only: its press is dropped.
        FluxPointerState.shared.playPauseWasHeld()
        let next = settings.mode.other
        UserDefaults.standard.set(next.rawValue, forKey: FluxRemoteMode.storageKey)
        toast.show(next == .pointer ? "Mode souris" : "Mode classique", symbol: next.symbol,
                   hint: "Maintenez Lecture/Pause pour changer")
        #if FLUX_CATALOG_UI_TESTING
        FluxPointerState.shared.toasts += 1
        FluxPointerState.shared.report()
        #endif
    }

    @objc private func playPauseWatched(_ watch: UILongPressGestureRecognizer) {
        switch watch.state {
        case .began: FluxPointerState.shared.playPauseWentDown()
        case .ended, .cancelled, .failed: FluxPointerState.shared.playPauseWentUp()
        default: break
        }
    }

    @objc private func arrowPressed(_ arrows: UILongPressGestureRecognizer) {
        if arrows.state == .began { arrowsUntil = ProcessInfo.processInfo.systemUptime + 0.6 }
    }

    @objc private func idleClicked(_ click: UILongPressGestureRecognizer) {
        // Held back: the pointer rests on nothing.
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { [.upArrow, .downArrow, .leftArrow, .rightArrow].contains($0.type) }) {
            arrowsUntil = ProcessInfo.processInfo.systemUptime + 0.6
        }
        super.pressesBegan(presses, with: event)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

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
    func benchPush(toward name: String) -> Bool {
        guard pointerActive else { return false }
        let targets = FluxPointerTargets.shared
        guard let page = targets.page(at: position, in: layer) ?? targets.pages(in: layer).first else { return false }
        if let target = benchTarget(name), target.frame.maxY < page.frame.maxY - CGFloat(FluxPointerScroll.margin) { return true }
        if !page.frame.contains(position) { move(to: CGPoint(x: page.frame.midX, y: page.frame.maxY - 60), animated: false) }
        thumbMoved(dx: 0, dy: 30, velocity: 0)
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
        probe.accessibilityValue = "\(state) toasts:\(shared.toasts)"
            + (shared.trace.isEmpty ? "" : " trace:" + shared.trace.joined(separator: ","))
    }

    /// A step of a sweep: the pointer rests on each control of `via`, then
    /// on `rests`, where it stays for the click of the flow. A step waits
    /// for its first control to show: the click of the step before opens it.
    private struct SweepStep {
        let via: [String]
        let rests: String
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
        // The languages over the picture: an audio, then a subtitle.
        case "player-tracks":
            return [SweepStep(via: ["track-audio-a2"], rests: "track-sub-s1")]
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
        for (number, step) in steps(for: scenario).enumerated() {
            for (index, name) in step.via.enumerated() {
                // A control below the bottom of its page: the pointer pushes
                // the page down to it first.
                let control = name.hasPrefix(below) ? String(name.dropFirst(below.count)) : name
                if control != name { await Self.push(toward: control, patience: patience) }
                // The first control of a step after the first shows once the
                // flow has clicked.
                let held = await Self.rest(on: control, patience: patience, waiting: number > 0 && index == 0 ? 60 : 6)
                shared.trace.append(held ?? "miss:" + name)
                shared.report()
            }
            let held = await Self.rest(on: step.rests, patience: patience, waiting: step.via.isEmpty && number > 0 ? 60 : 6)
            shared.trace.append((number == 0 ? "end" : "end\(number + 1)") + "=" + (held ?? "miss:" + step.rests))
            shared.report()
        }
    }

    /// A step of a sweep toward a control below the bottom of its page.
    private static let below = "below:"

    /// The pointer pushes the page down until the control `name` shows.
    private static func push(toward name: String, patience: Double) async {
        let clock = ProcessInfo.processInfo
        let end = clock.systemUptime + 8 * patience
        while clock.systemUptime < end {
            if let top = FluxPointerState.shared.controller, top.benchPush(toward: name) { return }
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

/// The pointer itself: an arrow or a round spot, white with a dark edge,
/// that never takes a touch.
private final class FluxPointerCursor: UIView {
    private let shapeLayer = CAShapeLayer()
    private var shape = FluxPointerShape.arrow
    private var height: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "flux-pointer"
        layer.addSublayer(shapeLayer)
        shapeLayer.fillColor = UIColor.white.cgColor
        shapeLayer.strokeColor = UIColor.black.withAlphaComponent(0.85).cgColor
        shapeLayer.lineJoin = .round
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        style(shape: .arrow, height: 44)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func style(shape: FluxPointerShape, height: CGFloat) {
        guard shape != self.shape || height != self.height || shapeLayer.path == nil else { return }
        self.shape = shape
        self.height = height
        let path = UIBezierPath()
        switch shape {
        case .arrow:
            let h = height
            bounds = CGRect(x: 0, y: 0, width: h * 0.66, height: h)
            path.move(to: CGPoint(x: 2, y: 2))
            path.addLine(to: CGPoint(x: 2, y: h * 0.80))
            path.addLine(to: CGPoint(x: h * 0.22, y: h * 0.62))
            path.addLine(to: CGPoint(x: h * 0.35, y: h * 0.94))
            path.addLine(to: CGPoint(x: h * 0.47, y: h * 0.89))
            path.addLine(to: CGPoint(x: h * 0.34, y: h * 0.58))
            path.addLine(to: CGPoint(x: h * 0.60, y: h * 0.58))
            path.close()
            shapeLayer.fillColor = UIColor.white.cgColor
            shapeLayer.lineWidth = max(1.5, h / 22)
        case .dot:
            let d = height * 0.6
            bounds = CGRect(x: 0, y: 0, width: d, height: d)
            path.append(UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: d - 4, height: d - 4)))
            shapeLayer.fillColor = UIColor.white.withAlphaComponent(0.82).cgColor
            shapeLayer.lineWidth = max(1.5, d / 14)
        }
        shapeLayer.frame = bounds
        shapeLayer.path = path.cgPath
        layer.shadowPath = path.cgPath
    }

    /// The tip of the arrow, or the middle of the spot, on `point`.
    func place(at point: CGPoint) {
        switch shape {
        case .arrow: center = CGPoint(x: point.x - 2 + bounds.width / 2, y: point.y - 2 + bounds.height / 2)
        case .dot: center = point
        }
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
