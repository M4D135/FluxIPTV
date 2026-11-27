import SwiftUI

/// The shelves of the studio of the appearance: the pictures behind the
/// screens, and the dock. The icons get a shelf of their own with their packs.
enum StudioShelf: String, CaseIterable, Identifiable {
    case backdrops, dock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .backdrops: "Fonds"
        case .dock: "Dock"
        }
    }
    var symbol: String {
        switch self {
        case .backdrops: "photo.on.rectangle.angled"
        case .dock: "dock.rectangle"
        }
    }
}

#if os(macOS) || os(tvOS)

/// A line of the studio, walked with the arrows.
private enum StudioRow: Hashable {
    case header, scope, modes, art, order, slideshow, family(FluxDockTheme.Family)
}

/// What the cursor of the studio may stand on.
private enum StudioItem: Hashable {
    case shelf(StudioShelf), fullScreen, done
    case scope(FluxSpace?), follow, same
    case mode(FluxBackdropPlan.Mode)
    case picture(FluxBackdropPicture)
    /// A picture of the slideshow, by its place in it.
    case ordered(Int)
    case interval(FluxSlideInterval), order(FluxSlideOrder), transition(FluxSlideTransition)
    case theme(FluxDockTheme)

    var key: String {
        switch self {
        case .shelf(let shelf): "shelf-" + shelf.rawValue
        case .fullScreen: "full-screen"
        case .done: "done"
        case .scope(let space): "scope-" + (space?.rawValue ?? "all")
        case .follow: "follow"
        case .same: "same"
        case .mode(let mode): "mode-" + mode.rawValue
        case .picture(let picture): picture.id
        case .ordered(let index): "ordered-\(index)"
        case .interval(let interval): "interval-\(interval.rawValue)"
        case .order(let order): "order-" + order.rawValue
        case .transition(let transition): "transition-" + transition.rawValue
        case .theme(let theme): "theme-" + theme.rawValue
        }
    }
}

/// The studio of the appearance, over the whole screen: the pictures behind
/// each screen and the theme of its dock, laid out as the shelves of a
/// shop. What the cursor stands on is tried at once, behind the studio and
/// in full screen; OK keeps it for the screen chosen above.
///
/// One surface takes the keys and the remote; the studio draws its own
/// cursor. A television never has to find the next control by itself, and
/// a Mac reads the same keys.
struct AppearanceStudio: View {
    let kind: IPTVMediaKind
    let close: () -> Void
    @State private var shelf: StudioShelf
    /// nil: all screens.
    @State private var scope: FluxSpace?
    /// The studio opens on its shop window: the tab of the shelf asked for.
    @State private var row: StudioRow = .header
    /// The place of the cursor in each line, kept as a console keeps it.
    @State private var columns: [StudioRow: Int] = [:]
    /// The item that the cursor has rested on: its picture is decoded and
    /// shown. Running along a shelf decodes nothing.
    @State private var resting: StudioItem?
    @State private var fullScreen = false
    @State private var fullScreenHint = false
    /// The picture of the slideshow that the arrows move.
    @State private var moving: Int?
    /// The pointer moved the cursor: the shelves stay where they are.
    @State private var pointerDriven = false
    private let start: String?
    @FocusState private var catcher: Bool

    @AppStorage(FluxBackdropChoices.storageKey) private var storedBackdrops = ""
    @AppStorage(FluxDockTheme.storageKey) private var dockAll: FluxDockTheme = .defaultValue
    @AppStorage(FluxDockThemeChoices.storageKey) private var dockSpaces = ""
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.tvKey) private var tvTheme: VideoClubTheme = .neo90
    @AppStorage("fluxiptv.appearance.stage") private var stage: ProceduralCinema.Style = .orbit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `start`: the key of the item the cursor starts on, for a capture.
    init(shelf: StudioShelf, scope: FluxSpace? = nil, kind: IPTVMediaKind, start: String? = nil,
         close: @escaping () -> Void) {
        _shelf = State(initialValue: shelf)
        _scope = State(initialValue: scope)
        self.kind = kind; self.start = start; self.close = close
    }

    // MARK: What is kept

    private var choices: FluxBackdropChoices { FluxBackdropChoices(stored: storedBackdrops) }
    /// The pictures of the screen chosen, or of all screens.
    private var plan: FluxBackdropPlan { choices.plan(for: scope) }
    private var keptTheme: FluxDockTheme {
        scope.map { FluxDockThemeChoices.theme(for: $0, all: dockAll, stored: dockSpaces) } ?? dockAll
    }
    /// The screen shown behind the studio: the one chosen, or the
    /// television for all screens.
    private var previewSpace: FluxSpace { scope ?? .live }
    private var previewKind: IPTVMediaKind {
        switch previewSpace {
        case .live: .live
        case .movie: .movie
        case .series: .series
        case .home, .search, .settings: kind
        }
    }
    private func spaceTheme(_ kind: IPTVMediaKind) -> VideoClubTheme {
        switch kind {
        case .movie: cinemaTheme
        case .series: seriesTheme
        case .live: tvTheme
        }
    }
    private var scopeName: String { scope?.title ?? "tous les écrans" }
    private func keepsOwn(_ space: FluxSpace) -> Bool {
        switch shelf {
        case .backdrops: choices.keepsOwn(space)
        case .dock: FluxDockThemeChoices.parse(dockSpaces)[space] != nil
        }
    }
    private var anyOwn: Bool {
        switch shelf {
        case .backdrops: choices.anyOwn
        case .dock: !FluxDockThemeChoices.parse(dockSpaces).isEmpty
        }
    }

    // MARK: Lines and cursor

    private var rows: [StudioRow] {
        switch shelf {
        case .backdrops:
            var result: [StudioRow] = [.header, .scope, .modes, .art]
            if plan.mode == .pictures, plan.shown.count > 1 { result.append(.order) }
            if plan.mode != .plain { result.append(.slideshow) }
            return result
        case .dock:
            return [.header, .scope] + FluxDockTheme.Family.allCases.map { StudioRow.family($0) }
        }
    }
    /// The lines of the shelf, under the title of the studio.
    private var shelfRows: [StudioRow] { rows.filter { $0 != .header && $0 != .scope } }

    private func items(_ line: StudioRow) -> [StudioItem] {
        switch line {
        case .header:
            return StudioShelf.allCases.map { StudioItem.shelf($0) } + [.fullScreen, .done]
        case .scope:
            var result: [StudioItem] = [.scope(nil)] + FluxSpace.allCases.map { StudioItem.scope($0) }
            if let scope, keepsOwn(scope) { result.append(.follow) }
            if anyOwn { result.append(.same) }
            return result
        case .modes:
            return FluxBackdropPlan.Mode.allCases.map { StudioItem.mode($0) }
        case .art:
            return FluxBackdropLibrary.art.map { StudioItem.picture(.art($0.name)) }
        case .order:
            return plan.shown.indices.map { StudioItem.ordered($0) }
        case .slideshow:
            return FluxSlideInterval.allCases.map { StudioItem.interval($0) }
                + FluxSlideOrder.allCases.map { StudioItem.order($0) }
                + FluxSlideTransition.allCases.map { StudioItem.transition($0) }
        case .family(let family):
            return family.themes.map { StudioItem.theme($0) }
        }
    }

    /// Where the cursor comes in a line that it has not been in yet: on
    /// what is chosen there.
    private func entry(_ line: StudioRow) -> Int {
        let list = items(line)
        let chosen: StudioItem? = switch line {
        case .header: .shelf(shelf)
        case .scope: .scope(scope)
        case .modes: .mode(plan.shown.isEmpty && plan.mode == .pictures ? .automatic : plan.mode)
        case .slideshow: .interval(plan.interval)
        case .family: .theme(keptTheme)
        case .art: plan.shown.first.map { StudioItem.picture($0) }
        case .order: nil
        }
        return chosen.flatMap { list.firstIndex(of: $0) } ?? 0
    }
    private func column(_ line: StudioRow) -> Int {
        let count = items(line).count
        return max(0, min(count - 1, columns[line] ?? entry(line)))
    }
    private var cursor: StudioItem {
        let line = rows.contains(row) ? row : .scope
        let list = items(line)
        return list.isEmpty ? .done : list[column(line)]
    }

    // MARK: Moves and choices

    private func move(_ dx: Int, _ dy: Int) {
        pointerDriven = false
        if fullScreen { fullScreen = false; return }
        let lines = rows
        if dy != 0 {
            moving = nil
            let index = lines.firstIndex(of: row) ?? 1
            row = lines[max(0, min(lines.count - 1, index + dy))]
            return
        }
        let line = lines.contains(row) ? row : .scope
        let list = items(line)
        guard !list.isEmpty else { return }
        let from = column(line)
        let target = max(0, min(list.count - 1, from + dx))
        guard target != from else { return }
        if let moving, line == .order {
            update { $0.move(at: moving, by: target - from) }
            self.moving = target
        }
        columns[line] = target
        settle(on: list[target])
    }

    /// The shelf and the screen follow the cursor along their tabs.
    private func settle(on item: StudioItem) {
        switch item {
        case .shelf(let next) where next != shelf:
            shelf = next; moving = nil
            columns = columns.filter { $0.key == .header }
        case .scope(let next) where next != scope:
            scope = next
            columns = columns.filter { $0.key == .header || $0.key == .scope }
        default: break
        }
    }

    private func activate(_ item: StudioItem) {
        switch item {
        case .shelf, .scope:
            // The tabs are chosen as the cursor comes on them: OK goes down
            // to what they hold.
            settle(on: item)
            if let first = shelfRows.first { row = first }
        case .fullScreen: fullScreen = true
        case .done: close()
        case .follow:
            guard let scope else { return }
            switch shelf {
            case .backdrops:
                var kept = choices; kept.follow(scope); storedBackdrops = kept.stored
            case .dock:
                dockSpaces = FluxDockThemeChoices.setting(nil, for: scope, in: dockSpaces)
            }
        case .same:
            switch shelf {
            case .backdrops:
                var kept = choices; kept.sameEverywhere(); storedBackdrops = kept.stored
            case .dock:
                dockSpaces = ""
            }
        case .mode(let mode):
            // Images choisies waits for a picture.
            guard mode != .pictures || !plan.shown.isEmpty else { return }
            update { $0.mode = mode }
        case .picture(let picture):
            update { plan in
                plan.toggle(picture)
                plan.mode = plan.pictures.isEmpty ? .automatic : .pictures
            }
        case .ordered(let index):
            moving = moving == nil ? index : nil
        case .interval(let interval): update { $0.interval = interval }
        case .order(let order): update { $0.order = order }
        case .transition(let transition): update { $0.transition = transition }
        case .theme(let theme):
            if let scope { dockSpaces = FluxDockThemeChoices.setting(theme, for: scope, in: dockSpaces) }
            else { dockAll = theme }
        }
    }

    /// Changes the plan of the screen chosen, which keeps it as its own.
    private func update(_ change: (inout FluxBackdropPlan) -> Void) {
        var kept = choices
        var edited = kept.plan(for: scope)
        // A picture that the app no longer holds leaves the list.
        edited.pictures = edited.shown.map(\.id)
        change(&edited)
        kept.set(edited, for: scope)
        storedBackdrops = kept.stored
    }

    private func back() {
        if fullScreen { fullScreen = false; return }
        if moving != nil { moving = nil; return }
        close()
    }

    // MARK: What is tried

    /// What stands behind the studio: the item the cursor rests on, else
    /// what the screen chosen keeps. On the tabs of its shelves, the studio
    /// is the boutique: its own pictures stand behind it.
    private var shownPlan: FluxBackdropPlan {
        switch resting ?? cursor {
        case .shelf:
            return FluxBackdropPlan(mode: .pictures, pictures: FluxBackdropLibrary.boutique.map(\.id),
                                    interval: .seconds15, order: .listed, transition: .fade)
        case .picture(let picture):
            return FluxBackdropPlan(mode: .pictures, pictures: [picture.id], transition: plan.transition)
        case .ordered(let index):
            let shown = plan.shown
            guard shown.indices.contains(index) else { return plan }
            return FluxBackdropPlan(mode: .pictures, pictures: [shown[index].id], transition: plan.transition)
        case .mode(.plain):
            return FluxBackdropPlan(mode: .plain)
        case .mode(let mode):
            var tried = plan
            if mode == .automatic || !tried.shown.isEmpty { tried.mode = mode }
            return tried
        default:
            return plan
        }
    }
    private var shownTheme: FluxDockTheme {
        if case .theme(let theme) = cursor { return theme }
        return keptTheme
    }

    // MARK: Body

    var body: some View {
        ZStack {
            #if os(tvOS)
            catcherButton
            #endif
            stageLayer
            if fullScreen {
                fullScreenLayer.transition(.opacity)
            } else {
                chrome.transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fullScreen)
        #if os(macOS)
        .focusable()
        .focused($catcher)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape, .space],
                    phases: [.down, .repeat]) { press in key(press) }
        #endif
        .onAppear {
            place(start)
            Task { @MainActor in await Task.yield(); catcher = true }
        }
        #if os(tvOS)
        // The pointer rests on the cursor, or goes along with the arrows.
        .onChange(of: cursor) { _, _ in FluxPointerState.shared.selectionMoved() }
        #endif
        .task(id: cursor) {
            // A picture is tried once the cursor rests on it.
            if case .picture = cursor {} else if case .ordered = cursor {} else { resting = cursor; return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            resting = cursor
        }
        .task(id: fullScreen) {
            fullScreenHint = fullScreen
            guard fullScreen else { return }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            fullScreenHint = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Studio d’apparence")
        .accessibilityIdentifier("appearance-studio")
    }

    /// Puts the cursor on the item of that key, for a capture.
    private func place(_ key: String?) {
        guard let key else { return }
        for line in rows {
            if let index = items(line).firstIndex(where: { $0.key == key }) {
                row = line; columns[line] = index
                return
            }
        }
    }

    #if os(macOS)
    private func key(_ press: KeyPress) -> KeyPress.Result {
        if fullScreen {
            if press.phase == .down { fullScreen = false }
            return .handled
        }
        switch press.key {
        case .upArrow: move(0, -1)
        case .downArrow: move(0, 1)
        case .leftArrow: move(-1, 0)
        case .rightArrow: move(1, 0)
        case .return: if press.phase == .down { activate(cursor) }
        case .space: if press.phase == .down { fullScreen = true }
        case .escape: if press.phase == .down { back() }
        default: return .ignored
        }
        return .handled
    }
    #endif

    #if os(tvOS)
    /// The one control of the studio: the remote never leaves it.
    private var catcherButton: some View {
        Button {
            if fullScreen { fullScreen = false } else { activate(cursor) }
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(FluxBareButtonStyle())
        .focusEffectDisabled()
        .focused($catcher)
        .onMoveCommand { direction in
            // With the pointer, a swipe moves the pointer only.
            guard FluxPointerState.shared.movesSelection else { return }
            switch direction {
            case .up: move(0, -1)
            case .down: move(0, 1)
            case .left: move(-1, 0)
            case .right: move(1, 0)
            @unknown default: break
            }
        }
        .onExitCommand { back() }
        .onPlayPauseCommand { FluxPointerState.shared.playPause { fullScreen.toggle() } }
        .accessibilityLabel("Studio d’apparence")
        .accessibilityIdentifier("studio-catcher")
        .accessibilityValue(cursor.key)
    }
    #endif

    // MARK: Stage

    private var stageLayer: some View {
        let tried = shownPlan
        return ZStack {
            FluxBackdrop(theme: spaceTheme(previewKind))
            FluxSpaceStage(space: previewSpace, kind: previewKind, trying: tried,
                           fade: tried.mode == .pictures && tried.shown.count == 1 ? 0.45 : 1.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fullScreenLayer: some View {
        ZStack(alignment: .bottom) {
            if shelf == .dock { StudioDock(theme: shownTheme, space: previewSpace, palette: spaceTheme(previewKind)).padding(.bottom, Desk.pt(28)) }
            if fullScreenHint {
                Text(Self.returnHint)
                    .font(Desk.font(.callout, .semibold))
                    .padding(.horizontal, Desk.pt(18)).padding(.vertical, Desk.pt(10))
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, Desk.pt(30))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fullScreenHint)
        .contentShape(Rectangle())
        #if os(macOS)
        .onTapGesture { fullScreen = false }
        #endif
    }

    private static var returnHint: String {
        #if os(tvOS)
        "Appuyez sur la télécommande pour revenir au studio"
        #else
        "Une touche ou un clic pour revenir au studio"
        #endif
    }

    // MARK: Chrome

    private var chrome: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Shades that keep what is written readable over any picture,
                // without a blur to draw again each time the picture changes.
                LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.42)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea().allowsHitTesting(false)
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                       .init(color: .black.opacity(0.62), location: 0.28),
                                       .init(color: .black.opacity(0.86), location: 0.6),
                                       .init(color: .black.opacity(0.92), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.66)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    info.padding(.top, Desk.pt(26))
                    Spacer(minLength: Desk.pt(8))
                    if shelf == .dock {
                        StudioDock(theme: shownTheme, space: previewSpace, palette: spaceTheme(previewKind))
                            .frame(maxWidth: .infinity).padding(.bottom, Desk.pt(16))
                    }
                    let height = geometry.size.height * (shelf == .dock ? 0.4 : 0.5)
                    panel(height: height).frame(height: height)
                    hints.padding(.top, Desk.pt(6))
                }
                .padding(.horizontal, Desk.pt(48)).padding(.top, Desk.pt(26)).padding(.bottom, Desk.pt(18))
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Desk.pt(14)) {
            HStack(spacing: Desk.pt(12)) {
                Label("Studio", systemImage: "paintpalette.fill")
                    .font(Desk.font(.title2, .bold)).padding(.trailing, Desk.pt(12))
                ForEach(Array(items(.header).enumerated()), id: \.element) { index, item in
                    if item == .fullScreen { Spacer(minLength: Desk.pt(12)) }
                    interactive(item, line: .header, index: index) { chip(item) }
                }
            }
            HStack(spacing: Desk.pt(10)) {
                ForEach(Array(items(.scope).enumerated()), id: \.element) { index, item in
                    if item == .follow || (item == .same && !items(.scope).contains(.follow)) {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: Desk.pt(30)).padding(.horizontal, Desk.pt(4))
                    }
                    interactive(item, line: .scope, index: index) { chip(item) }
                }
            }
        }
    }

    private var info: some View {
        let item = resting ?? cursor
        return VStack(alignment: .leading, spacing: Desk.pt(8)) {
            Text(heading(item)).font(Desk.font(.largeTitle, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            if let detail = detail(item) {
                Text(detail).font(Desk.font(.title3)).foregroundStyle(.white.opacity(0.84)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Desk.pt(12)) {
                if let collection = collection(item) {
                    Text(collection).font(Desk.font(.callout, .medium)).foregroundStyle(.white.opacity(0.72))
                    // Every look of this version comes with the app. The shop
                    // will name a price here, and trying will stay free.
                    Text("Inclus").font(Desk.font(.caption, .bold))
                        .padding(.horizontal, Desk.pt(10)).padding(.vertical, Desk.pt(4))
                        .background(Color.cyan.opacity(0.22), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1))
                }
                if let action = actionText(cursor) {
                    Text(action).font(Desk.font(.callout, .semibold)).foregroundStyle(.cyan)
                }
            }
            if shelf == .backdrops, stage == .off {
                Label("Les fonds sont coupés dans Graphismes : les écrans ne les montrent pas.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Desk.font(.callout, .medium)).foregroundStyle(.orange)
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 10, y: 3)
        .frame(maxWidth: Desk.pt(980), alignment: .leading)
        .animation(nil, value: item)
    }

    private func panel(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Desk.pt(14)) {
                    ForEach(shelfRows, id: \.self) { line in rail(line) }
                }
                .padding(.top, Desk.pt(6))
                // The last row rises to the top like the others: nothing of
                // the row before it shows above it.
                .padding(.bottom, max(Desk.pt(64), height * 0.55))
            }
            // The row cut by the foot of the panel fades out instead.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Desk.pt(70)).allowsHitTesting(false)
            }
            .onChange(of: row) { _, line in
                guard !pointerDriven, shelfRows.contains(line) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo(line, anchor: .top) }
            }
            .onAppear {
                // The cursor is placed as the studio appears, which may come
                // after this list: it is brought to the cursor once both are.
                Task { @MainActor in
                    await Task.yield()
                    if shelfRows.contains(row) { proxy.scrollTo(row, anchor: .top) }
                }
            }
        }
    }

    private func rail(_ line: StudioRow) -> some View {
        let list = items(line)
        return VStack(alignment: .leading, spacing: Desk.pt(6)) {
            Text(railTitle(line)).font(Desk.font(.headline, .semibold))
                .foregroundStyle(.white.opacity(row == line ? 1 : 0.82))
                .shadow(color: .black.opacity(0.75), radius: 6, y: 2)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Desk.pt(18)) {
                        ForEach(Array(list.enumerated()), id: \.element) { index, item in
                            if line == .slideshow, item == .order(.listed) || item == .transition(.fade) {
                                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: Desk.pt(30))
                                    .padding(.horizontal, Desk.pt(4)).padding(.top, Desk.pt(8))
                            }
                            interactive(item, line: line, index: index) { card(item) }
                        }
                    }
                    // Room for the card that rises under the cursor.
                    .padding(.vertical, Desk.pt(14)).padding(.horizontal, Desk.pt(12))
                }
                // The cards that go on past the edge fade out there. A shade
                // over the dark foot of the screen, not a mask: a mask would
                // draw each row twice.
                .overlay(alignment: .trailing) {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Desk.pt(72)).allowsHitTesting(false)
                }
                .onChange(of: cursor) { _, item in
                    guard !pointerDriven, row == line else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(item, anchor: .center) }
                }
                .onAppear {
                    Task { @MainActor in
                        await Task.yield()
                        if let chosen = list.indices.contains(column(line)) ? list[column(line)] : nil, column(line) > 2 {
                            proxy.scrollTo(chosen, anchor: .center)
                        }
                    }
                }
            }
        }
        .id(line)
    }

    private var hints: some View {
        HStack(spacing: Desk.pt(22)) {
            #if os(tvOS)
            hint("OK", moving != nil ? "poser l’image" : "choisir")
            if moving != nil { hint("← →", "déplacer") }
            hint("⏯", "plein écran")
            hint("MENU", moving != nil ? "poser" : "terminé")
            #else
            hint("Entrée", moving != nil ? "poser l’image" : "choisir")
            if moving != nil { hint("← →", "déplacer") }
            hint("Espace", "plein écran")
            hint("Échap", moving != nil ? "poser" : "terminé")
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: Desk.pt(8)) {
            Text(key).font(Desk.font(.caption, .bold))
                .padding(.horizontal, Desk.pt(8)).padding(.vertical, Desk.pt(3))
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(6), style: .continuous))
            Text(text).font(Desk.font(.caption, .medium)).foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: Cards

    /// The cursor goes where the pointer is, and a click chooses.
    private func interactive<V: View>(_ item: StudioItem, line: StudioRow, index: Int,
                                      @ViewBuilder _ content: () -> V) -> some View {
        content()
            .id(item)
            .contentShape(Rectangle())
            #if os(macOS)
            // The pointer tries what it passes over; a tab waits for a click.
            .onHover { inside in
                guard inside, !fullScreen else { return }
                pointerDriven = true
                row = line; columns[line] = index
            }
            .onTapGesture {
                pointerDriven = true
                row = line; columns[line] = index
                activate(item)
            }
            #elseif os(tvOS)
            // The pointer of the remote puts the cursor on what it rests on,
            // a click chooses it; a tab waits for the click, as on a Mac.
            .fluxPointerTarget("studio-" + item.key, select: {
                guard !fullScreen else { return }
                pointerDriven = true
                row = line; columns[line] = items(line).firstIndex(of: item) ?? index
            }, isSelected: { item == cursor && !fullScreen })
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heading(item))
            .accessibilityIdentifier("studio-" + item.key)
            .accessibilityValue(isChosen(item) ? "Choisi" : "")
            .accessibilityAddTraits(item == cursor ? .isSelected : [])
    }

    @ViewBuilder private func card(_ item: StudioItem) -> some View {
        let focused = item == cursor && !fullScreen
        switch item {
        case .picture(let picture): pictureCard(picture, focused: focused)
        case .ordered(let index): orderedCard(index, focused: focused)
        case .mode(let mode): modeCard(mode, focused: focused)
        case .theme(let theme): themeCard(theme, focused: focused)
        default: chip(item)
        }
    }

    private var pictureWidth: CGFloat { Desk.pt(250) }

    private func pictureCard(_ picture: FluxBackdropPicture, focused: Bool) -> some View {
        let width = pictureWidth, height = width * 9 / 16
        let number = plan.mode == .pictures ? plan.shown.firstIndex(of: picture).map { $0 + 1 } : nil
        return VStack(alignment: .leading, spacing: Desk.pt(8)) {
            StudioGloss(focused: focused, radius: Desk.pt(14)) {
                BackdropThumbnail(picture: picture).frame(width: width, height: height)
            }
            .overlay(alignment: .topTrailing) {
                if let number { StudioBadge(text: "\(number)").padding(Desk.pt(8)) }
            }
            Text(picture.title).font(Desk.font(.caption, .medium)).lineLimit(1)
                .foregroundStyle(.white.opacity(focused ? 1 : 0.7))
                .frame(width: width, alignment: .leading)
        }
    }

    private func orderedCard(_ index: Int, focused: Bool) -> some View {
        let shown = plan.shown
        let width = Desk.pt(200), height = width * 9 / 16
        let lifted = moving == index
        return VStack(alignment: .leading, spacing: Desk.pt(8)) {
            StudioGloss(focused: focused, radius: Desk.pt(12)) {
                ZStack {
                    if shown.indices.contains(index) { BackdropThumbnail(picture: shown[index]) }
                    if lifted {
                        Color.black.opacity(0.35)
                        Image(systemName: "arrow.left.and.right").font(Desk.system(30, .bold))
                    }
                }
                .frame(width: width, height: height)
            }
            .overlay(alignment: .topLeading) { StudioBadge(text: "\(index + 1)").padding(Desk.pt(8)) }
            .offset(y: lifted ? -Desk.pt(8) : 0)
            Text(shown.indices.contains(index) ? shown[index].title : "")
                .font(Desk.font(.caption, .medium)).lineLimit(1)
                .foregroundStyle(.white.opacity(focused ? 1 : 0.7)).frame(width: width, alignment: .leading)
        }
    }

    private var automaticSample: FluxBackdropPicture {
        FluxBackdropLibrary.pictures(for: previewSpace, holding: previewKind).first ?? .art(FluxBackdropLibrary.art[0].name)
    }

    private func modeCard(_ mode: FluxBackdropPlan.Mode, focused: Bool) -> some View {
        let width = pictureWidth, height = width * 9 / 16
        let count = plan.shown.count
        let chosen = plan.mode == mode && !(mode == .pictures && count == 0)
        let symbol = switch mode {
        case .automatic: "sparkles.tv"
        case .plain: "circle.slash"
        case .pictures: "photo.stack"
        }
        let caption = switch mode {
        case .automatic: scope == .home ? "Celles de l’écran de l’icône" : "Les images de l’écran"
        case .plain: "La couleur seule"
        case .pictures: count == 0 ? "Aucune pour l’instant" : "\(count) \(count == 1 ? "image" : "images")"
        }
        return VStack(alignment: .leading, spacing: Desk.pt(8)) {
            StudioGloss(focused: focused, radius: Desk.pt(14)) {
                ZStack(alignment: .bottomLeading) {
                    switch mode {
                    case .automatic: BackdropThumbnail(picture: automaticSample)
                    case .plain: FluxBackdrop(theme: spaceTheme(previewKind))
                    case .pictures:
                        if let first = plan.shown.first { BackdropThumbnail(picture: first) }
                        else { Color.white.opacity(0.07) }
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    HStack(spacing: Desk.pt(8)) {
                        Image(systemName: symbol)
                        Text(mode.title).lineLimit(1)
                        Spacer(minLength: 0)
                        if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                    }
                    .font(Desk.font(.headline, .semibold)).padding(Desk.pt(12))
                }
                .frame(width: width, height: height)
            }
            Text(caption).font(Desk.font(.caption, .medium)).lineLimit(1)
                .foregroundStyle(.white.opacity(focused ? 1 : 0.7)).frame(width: width, alignment: .leading)
        }
    }

    private func themeCard(_ theme: FluxDockTheme, focused: Bool) -> some View {
        let width = Desk.pt(300), height = Desk.pt(128)
        let chosen = keptTheme == theme
        return VStack(alignment: .leading, spacing: Desk.pt(6)) {
            StudioGloss(focused: focused, radius: Desk.pt(16)) {
                ZStack {
                    BackdropThumbnail(picture: automaticSample, maxPixels: 480)
                        .frame(width: width, height: width * 9 / 16)
                        .frame(width: width, height: height).clipped()
                        .overlay(Color.black.opacity(0.25))
                    StudioDock(theme: theme, space: previewSpace, palette: spaceTheme(previewKind), count: 4)
                        .scaleEffect(0.56)
                }
                .frame(width: width, height: height)
            }
            .overlay(alignment: .topTrailing) {
                if chosen { Image(systemName: "checkmark.circle.fill").font(Desk.system(22, .bold)).foregroundStyle(.cyan).padding(Desk.pt(8)) }
            }
            Text(theme.title).font(Desk.font(.callout, .semibold)).lineLimit(1)
            Text(theme.subtitle).font(Desk.font(.caption2)).foregroundStyle(.white.opacity(0.66))
                .lineLimit(2, reservesSpace: true).frame(width: width, alignment: .leading)
        }
    }

    private func chip(_ item: StudioItem) -> some View {
        let focused = item == cursor && !fullScreen
        let selected = isChosen(item)
        let shape = Capsule()
        return HStack(spacing: Desk.pt(8)) {
            if let symbol = symbol(item) { Image(systemName: symbol) }
            Text(chipTitle(item)).lineLimit(1)
            if case .scope(let space?) = item, keepsOwn(space) {
                Circle().fill(focused ? Color.black : Color.cyan).frame(width: Desk.pt(8), height: Desk.pt(8))
            }
        }
        .font(Desk.font(.callout, .semibold))
        .foregroundStyle(focused ? Color.black : Color.white)
        .padding(.horizontal, Desk.pt(18)).frame(height: Desk.pt(46))
        .background(focused ? Color.white : Color.white.opacity(selected ? 0.26 : 0.09), in: shape)
        .overlay(shape.strokeBorder(selected && !focused ? Color.cyan.opacity(0.9) : Color.white.opacity(focused ? 0 : 0.14),
                                    lineWidth: selected && !focused ? 2 : 1))
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
        .padding(.vertical, Desk.pt(4))
    }

    // MARK: Words

    private func isChosen(_ item: StudioItem) -> Bool {
        switch item {
        case .shelf(let value): value == shelf
        case .scope(let value): value == scope
        case .interval(let value): plan.interval == value
        case .order(let value): plan.order == value
        case .transition(let value): plan.transition == value
        case .theme(let value): keptTheme == value
        default: false
        }
    }

    private func symbol(_ item: StudioItem) -> String? {
        switch item {
        case .shelf(let shelf): shelf.symbol
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .done: "checkmark"
        case .scope(nil): "square.grid.2x2"
        case .scope(.home?): "house.fill"
        case .scope(.live?): "tv"
        case .scope(.movie?): "film"
        case .scope(.series?): "film.stack"
        case .scope(.search?): "magnifyingglass"
        case .scope(.settings?): "gearshape"
        case .follow: "arrow.uturn.backward"
        case .same: "equal.circle"
        case .interval(.seconds15): "timer"
        case .order(.listed): "list.number"
        case .order(.shuffled): "shuffle"
        case .transition(.fade): "circle.lefthalf.filled"
        case .transition(.cut): "rectangle.split.2x1"
        default: nil
        }
    }

    private func chipTitle(_ item: StudioItem) -> String {
        switch item {
        case .shelf(let shelf): shelf.title
        case .fullScreen: "Plein écran"
        case .done: "Terminé"
        case .scope(let space): space?.title ?? "Tous les écrans"
        case .follow: "Comme tous les écrans"
        case .same: "Le même partout"
        case .interval(let interval): interval.title
        case .order(let order): order.title
        case .transition(let transition): transition.title
        default: heading(item)
        }
    }

    private func heading(_ item: StudioItem) -> String {
        switch item {
        case .mode(let mode): mode.title
        case .picture(let picture): picture.title
        case .ordered(let index): plan.shown.indices.contains(index) ? plan.shown[index].title : "Diaporama"
        case .interval(let interval): "Une image toutes les \(interval.title)"
        case .theme(let theme): theme.title
        default: chipTitle(item)
        }
    }

    private func detail(_ item: StudioItem) -> String? {
        switch item {
        case .shelf(.backdrops): return "Les images derrière chaque écran, seules ou l’une après l’autre."
        case .shelf(.dock): return "Le thème de la barre et de ses icônes, pour chaque écran."
        case .fullScreen: return "Le fond seul, sans le studio. Une touche pour revenir."
        case .done: return "Ce qui est gardé reste en place."
        case .scope(nil): return "Le choix des écrans qui ne gardent pas le leur."
        case .scope(let space?):
            // Its own pictures stand behind what is kept in its bar only.
            if space == .home, shelf == .backdrops, keepsOwn(space) {
                return "Accueil garde son propre choix ; une destination sélectionnée montre le fond de son écran."
            }
            return keepsOwn(space) ? "\(space.title) garde son propre choix." : "\(space.title) suit le choix de tous les écrans."
        case .follow: return scope.map { "\($0.title) reprend le choix de tous les écrans." }
        case .same: return "Chaque écran reprend le choix de tous les écrans."
        case .mode(.automatic):
            switch scope {
            case nil: return "Chaque écran montre les images dessinées pour lui, l’une après l’autre."
            case .home?: return "L’accueil montre les images de l’écran qu’ouvre son icône sélectionnée."
            case let space?: return "Les images dessinées pour \(space.title), l’une après l’autre."
            }
        case .mode(.plain): return "La couleur de l’écran, sans image. Le plus léger à afficher."
        case .mode(.pictures):
            let count = plan.shown.count
            return count == 0 ? "Choisissez une ou plusieurs images plus bas : elles passent l’une après l’autre."
                : "\(count) \(count == 1 ? "image choisie" : "images choisies"), l’une après l’autre."
        case .picture(.art(let name)):
            return FluxBackdropLibrary.art.first { $0.name == name }.map { art in
                art.space.map { "Dessiné pour l’écran \($0.title)." } ?? "Dessiné pour la boutique ; tout écran peut le montrer."
            }
        case .ordered(let index): return "Image \(index + 1) sur \(plan.shown.count) du diaporama."
        case .interval(let interval): return "Chaque image reste \(interval.title) avant la suivante."
        case .order(.listed): return "Les images passent dans l’ordre choisi."
        case .order(.shuffled): return "Un ordre nouveau à chaque tour, sans reprendre l’image qui a fini le tour d’avant."
        case .transition(.fade): return "Les images se fondent l’une dans l’autre."
        case .transition(.cut): return "Les images se remplacent d’un coup."
        case .theme(let theme): return theme.subtitle
        }
    }

    /// The collection an item comes from: the shop will sell by collection.
    private func collection(_ item: StudioItem) -> String? {
        switch item {
        case .picture(.art(let name)):
            return FluxBackdropLibrary.art.first { $0.name == name }.map { "Fonds dessinés · \($0.section)" }
        case .theme(let theme): return "Docks · \(theme.family.title)"
        default: return nil
        }
    }

    /// What OK does on the item.
    private func actionText(_ item: StudioItem) -> String? {
        switch item {
        case .picture(let picture):
            if plan.mode == .pictures, plan.contains(picture) { return "OK la retire du diaporama" }
            if plan.mode == .pictures, !plan.shown.isEmpty { return "OK l’ajoute au diaporama de \(scopeName)" }
            return "OK la garde pour \(scopeName)"
        case .theme(let theme):
            return keptTheme == theme ? "Gardé pour \(scopeName)" : "OK le garde pour \(scopeName)"
        case .mode(let mode):
            if mode == .pictures, plan.shown.isEmpty { return "Choisissez d’abord des images" }
            return plan.mode == mode ? "Choisi pour \(scopeName)" : "OK le choisit pour \(scopeName)"
        case .ordered: return moving == nil ? "OK puis ← → pour la déplacer" : "← → la déplacent, OK la pose"
        case .interval, .order, .transition:
            return isChosen(item) ? "Choisi pour \(scopeName)" : "OK le choisit pour \(scopeName)"
        case .follow, .same: return "OK"
        default: return nil
        }
    }

    private func railTitle(_ line: StudioRow) -> String {
        switch line {
        case .modes: "Fond de \(scopeName)"
        case .art: "Fonds dessinés"
        case .order: "Ordre du diaporama"
        case .slideshow: "Diaporama"
        case .family(let family): family.title
        case .header, .scope: ""
        }
    }
}

/// A rounded picture with the light of glass on its top, which rises under
/// the cursor.
private struct StudioGloss<Content: View>: View {
    let focused: Bool
    let radius: CGFloat
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(focused: Bool, radius: CGFloat, @ViewBuilder content: () -> Content) {
        self.focused = focused; self.radius = radius; self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(focused ? 0.24 : 0.11), .white.opacity(0)],
                                          startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                    .allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0.16), lineWidth: focused ? 3 : 1).allowsHitTesting(false))
            .shadow(color: focused ? .black.opacity(0.5) : .clear, radius: focused ? 16 : 0, y: focused ? 8 : 0)
            .scaleEffect(focused && !reduceMotion ? 1.07 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
    }
}

private struct StudioBadge: View {
    let text: String
    var body: some View {
        Text(text).font(Desk.font(.callout, .bold)).monospacedDigit()
            .frame(minWidth: Desk.pt(30), minHeight: Desk.pt(30))
            .padding(.horizontal, Desk.pt(4))
            .background(Color.cyan, in: Capsule())
            .foregroundStyle(.black)
    }
}

/// The dock as a screen draws it, with the destinations alone: the studio
/// shows a theme on it before it is kept.
private struct StudioDock: View {
    let theme: FluxDockTheme
    let space: FluxSpace
    let palette: VideoClubTheme
    var count = 6

    var body: some View {
        let metrics = FluxDockMetrics(.bottom)
        let items = Array(([.live, .movie, .series, .search, .favorites, .settings] as [FluxDockItem]).prefix(count))
        let selected: FluxDockItem = switch space {
        case .movie: .movie
        case .series: .series
        case .search: .search
        case .settings: .settings
        case .home, .live: .live
        }
        let colours = palette.palette
        HStack(spacing: metrics.spacing) {
            ForEach(items) { item in
                FluxDockCell(tile: DockTile(entry: .destination(item), name: item.title, full: item.title, face: .destination(item)),
                             selected: item == selected, focused: item == selected, theme: theme, position: .bottom, metrics: metrics)
                    .frame(width: metrics.cell.width, height: metrics.cell.height)
            }
        }
        .padding(metrics.platePadding)
        .background {
            FluxDockPlate(theme: theme,
                          accent: Color(red: colours.accent.x, green: colours.accent.y, blue: colours.accent.z),
                          second: Color(red: colours.second.x, green: colours.second.y, blue: colours.second.z),
                          radius: metrics.radius)
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
