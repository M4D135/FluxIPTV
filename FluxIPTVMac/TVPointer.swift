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
    weak var controller: FluxPointerController?
    #if FLUX_CATALOG_UI_TESTING
    /// What the screen says holds the remote, for a bench.
    var benchFocus: String?
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
        /// Gives the focus to the control, through the focus state of its screen.
        let focus: (_ again: Bool) -> Void
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

    /// The control under `point`, chosen as `FluxPointerTarget.pick` does.
    func target(at point: CGPoint, tolerance: Double) -> Target? {
        let list = Array(targets.values)
        return FluxPointerTarget.pick(point, frames: list.map(\.frame), tolerance: tolerance).map { list[$0] }
    }
}

private struct FluxPointerTargetModifier<Value: Hashable>: ViewModifier {
    let value: Value
    let binding: FocusState<Value?>.Binding
    let id: String
    /// What stands under a panel is disabled: the pointer leaves it alone.
    @Environment(\.isEnabled) private var enabled
    /// Its token, and its last frame, which redraw nothing as they change.
    @State private var place = Place()

    final class Place {
        let token = UUID()
        var frame = CGRect.null
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                place.frame = frame
                record(enabled: enabled)
            }
            .onChange(of: enabled) { _, now in record(enabled: now) }
            .onDisappear { FluxPointerTargets.shared.remove(place.token) }
    }

    private func record(enabled: Bool) {
        let frame = place.frame
        guard enabled, !frame.isNull, frame.width > 12, frame.height > 12 else {
            FluxPointerTargets.shared.remove(place.token)
            return
        }
        let binding = binding, value = value
        FluxPointerTargets.shared.set(place.token, .init(id: id, frame: frame) { again in
            // A request the system declined keeps its value: asked again,
            // it is cleared first.
            if again { binding.wrappedValue = nil }
            binding.wrappedValue = value
        })
    }
}

extension View {
    /// The pointer of a television can rest on this control and give it the
    /// focus. After `.focused(binding, equals: id)`, never between a button
    /// and it.
    func fluxPointerTarget(_ id: String, _ binding: FocusState<String?>.Binding) -> some View {
        modifier(FluxPointerTargetModifier(value: id, binding: binding, id: id))
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
    let content: Content
    var body: some View { content.environment(\.scenePhase, relay.phase) }
}

private struct FluxPointerHost<Content: View>: UIViewControllerRepresentable {
    let content: () -> Content
    let settings: FluxPointerSettings
    let phase: ScenePhase

    func makeUIViewController(context: Context) -> FluxPointerController {
        let relay = FluxPhaseRelay(phase)
        // The screens are given once: their state lives in the controller.
        let controller = FluxPointerController(root: AnyView(FluxPhaseRoot(relay: relay, content: content())), relay: relay)
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

    init(root: AnyView, relay: FluxPhaseRelay) {
        self.relay = relay
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
        FluxPointerState.shared.controller = self
        #if FLUX_CATALOG_UI_TESTING
        probe.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        probe.isAccessibilityElement = true
        probe.accessibilityLabel = "Pointeur"
        probe.accessibilityIdentifier = "flux-pointer-state"
        view.addSubview(probe)
        #endif
        refresh()
    }

    #if FLUX_CATALOG_UI_TESTING
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] == "pointer", !swept else { return }
        swept = true
        Task { @MainActor [weak self] in await self?.sweep() }
    }
    #endif

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
        // The control the pointer rests on: it stays under the thumb.
        if frame.insetBy(dx: -24, dy: -24).contains(position) { return }
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
        let targets = FluxPointerTargets.shared
        if let target = targets.target(at: position, tolerance: 14) {
            found = true
            // Until the control has taken the focus, a click would press
            // the one that still has it: the click waits for it.
            overNothing = targets.focusedID != target.id
            updateIdleClick()
            guard overNothing else { asking = nil; return }
            // Asked again after a moment: the first request was declined.
            if let asking, asking.id == target.id {
                guard now - asking.at > 0.3 else { return }
                self.asking = (target.id, now)
                target.focus(true)
            } else {
                asking = (target.id, now)
                target.focus(false)
            }
            #if FLUX_CATALOG_UI_TESTING
            asked += 1
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
        guard pointerActive, let target = FluxPointerTargets.shared.target(at: position, tolerance: 14) else { return }
        overNothing = FluxPointerTargets.shared.focusedID != target.id
        if !overNothing { asking = nil }
        updateIdleClick()
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
            let speed = Double((velocity.x * velocity.x + velocity.y * velocity.y).squareRoot())
            move(to: FluxPointerMotion(speed: settings.speed).step(from: position, dx: dx, dy: dy, velocity: speed, in: view.bounds),
                 animated: false)
            hover()
            show()
        case .ended, .cancelled, .failed:
            hover(force: true)
            show()
        default:
            break
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
        toasts += 1
        report()
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

    private let probe = UIView()
    private var swept = false
    private var trace: [String] = []
    private var toasts = 0
    /// Requests of the focus the pointer made.
    private var asked = 0

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
        return "diag:targets=\(FluxPointerTargets.shared.count);root=\(name(root));top=\(top);all=\(all);focused=\(name(focused));env=\(chain.joined(separator: ">"))"
    }

    /// The mode and what covers the screens; then what a sweep crossed.
    private func report() {
        let state = settings.mode == .classic ? "classic"
            : FluxPointerState.shared.suspended ? "suspended" : pointerActive ? "active" : "covered"
        probe.accessibilityValue = "\(state) toasts:\(toasts)" + (trace.isEmpty ? "" : " trace:" + trace.joined(separator: ","))
    }

    /// "pointer": the pointer crosses the content, then the bar, as a thumb
    /// would; each control it rests on must take the focus. It ends on the
    /// first title it crossed, for the click of the flow.
    private func sweep() async {
        // A hosted machine answers several times more slowly; the flows say
        // how much (FLUX_UI_PATIENCE), and each rest of the pointer is as
        // much longer.
        let patience = min(10, max(1, Double(ProcessInfo.processInfo.environment["FLUX_UI_PATIENCE"] ?? "") ?? 1))
        func rest(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * patience * 1_000_000_000)) }
        await rest(4)
        let bounds = view.bounds
        let rows = [bounds.height * 0.42, bounds.height * 0.55, bounds.maxY - 150, bounds.maxY - 125, bounds.maxY - 100]
        var title: CGPoint?
        // What held the remote at launch is no control crossed: only what
        // changes from now on counts.
        var last = FluxPointerState.shared.benchFocus
        for y in rows {
            for step in 0...10 {
                let point = CGPoint(x: bounds.width * (0.2 + 0.06 * CGFloat(step)), y: y)
                benchMove(to: point)
                await rest(0.3)
                guard let id = FluxPointerState.shared.benchFocus, id != last else { continue }
                last = id
                trace.append(id)
                if title == nil, id.hasPrefix("fixture-") { title = point }
            }
        }
        if !trace.contains(where: { $0.hasPrefix("fixture-") }) { trace.append(diagnosis()) }
        trace.append("hover=asked:\(asked)")
        if let title {
            benchMove(to: title)
            // Back over the title, until the focus has followed.
            for _ in 0..<Int(30 * patience) where !(FluxPointerState.shared.benchFocus ?? "").hasPrefix("fixture-") {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await rest(0.3)
        }
        trace.append("end=" + (FluxPointerState.shared.benchFocus ?? "none"))
        report()
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
